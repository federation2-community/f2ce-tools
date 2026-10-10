-- f2ce-tools map - f2tNav, the one way to move the player
--
-- Every system that needs to get somewhere (hauling, stamina, insurance, the
-- nav command, UI clicks, another package) asks f2tNav and hears back exactly
-- once. Nothing outside the map component reads speedwalk or explore state;
-- f2tNav.status() and f2tNav.busy() are the only view of it.
--
--   f2tNav.go(destination, opts) -> trip
--     destination   anything a nav command accepts: "<planet> exchange", a
--                   planet, "<system> link", a room id or hash, a saved name
--     opts.owner    who is asking: "player", "hauling", "stamina", ... (default "player")
--     opts.onDone   function(result), called once on the next tick:
--                     result.status  "arrived" | "stopped" | "unreachable" | "superseded"
--                     result.reason  why, for "unreachable"
--                     result.by      the owner that took over, for "superseded"
--                     result.roomId  where the player ended up
--     opts.ask      confirm before exploring an unmapped destination (typed nav)
--   f2tNav.stop(owner)   end the trip as "stopped"; with owner, only that owner's
--   f2tNav.pause() / f2tNav.resume()
--   f2tNav.status() -> nil | {owner, destination, paused}
--   f2tNav.busy()   -> true while anything is moving the player
--
-- One trip at a time. A new go() ends the current trip as "superseded" first.
--
-- Events: f2tNavStarted(owner, destination)
--         f2tNavFinished(owner, status, roomId, reason)
--
-- A trip is a series of legs, each planned from where the player stands once
-- the previous one is over. A leg is one of: a walk the map already has a route
-- for, a jump chain over the legal jump graph (topology.lua), a board from orbit
-- or a pad, or a sweep of one system's space or one planet that stops as soon as
-- the next leg exists. Between systems the plan is link -> jumps -> link; inside
-- the destination's system it is orbit -> board -> shuttlepad -> the room.

f2tNav = f2tNav or {}

-- The engine reports quiet for this many 0.5s polls before a leg counts as over.
local IDLE_POLLS_TO_SETTLE = 3
-- Legs from the same room that went nowhere, before the destination counts as unreachable.
local MAX_STALLS = 2
local MAX_LEGS = 24
-- How long a sweep may take to get going (a system sweep asks "di system" first).
local SWEEP_START_SECONDS = 20

local trip = nil

local function same(a, b)
    return a ~= nil and b ~= nil and string.lower(a) == string.lower(b)
end

local function exploreActive()
    return F2T_MAP_EXPLORE_STATE ~= nil and F2T_MAP_EXPLORE_STATE.active == true
end

-- An exploration running now that wasn't when the trip began is the trip's own sweep.
local function ownsExplore(t)
    return exploreActive() and not t.exploreAtStart
end

local function engineMoving(t)
    if t.sweepStartedAt then
        if exploreActive() or os.time() - t.sweepStartedAt < SWEEP_START_SECONDS then return true end
        t.sweepStartedAt = nil
    end
    return F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_CUSTOMS_PENDING or ownsExplore(t)
end

local function clearStopCondition(t)
    local pending = F2T_MAP_EXPLORE_PENDING_STOP
    if t.stopWhen and pending and pending.stop_when == t.stopWhen then
        f2t_map_explore_set_stop_condition(nil)
    end
    t.stopWhen = nil
end

-- Stop whatever the engine is doing for this trip, without reporting anything.
local function haltEngine(t)
    local exploring = ownsExplore(t)
    if F2T_SPEEDWALK_ACTIVE then f2t_map_speedwalk_stop() end
    if exploring then f2t_map_explore_stop("Navigation ended") end
end

local function finish(t, status, reason, by)
    if trip == t then trip = nil end
    if t.pollTimer then killTimer(t.pollTimer); t.pollTimer = nil end
    t.generation = t.generation + 1
    clearStopCondition(t)
    f2t_map_brief_hold_release("nav")
    local roomId = F2T_MAP_CURRENT_ROOM_ID
    f2t_debug_log("[nav] trip %d (%s -> %s) %s%s", t.id, t.owner, tostring(t.destination), status,
        reason and (": " .. reason) or "")
    if status == "unreachable" and t.owner == "player" then
        cecho(string.format("\n<red>[map]<reset> Can't get to '%s': %s\n", t.destination, reason or "no route"))
    end
    raiseEvent("f2tNavFinished", t.owner, status, roomId, reason)
    if t.onDone then
        tempTimer(0, function()
            local ok, err = pcall(t.onDone, { status = status, reason = reason, by = by, roomId = roomId })
            if not ok then f2t_debug_log("[nav] onDone for %s failed: %s", t.owner, tostring(err)) end
        end)
    end
end

-- ── Legs ─────────────────────────────────────────────────────────────────────

local function note(text)
    cecho(string.format("\n<cyan>[map]<reset> %s\n", text))
end

local function reachable(roomId)
    local here = F2T_MAP_CURRENT_ROOM_ID
    if not roomId or not here or not roomExists(roomId) then return false end
    return roomId == here or getPath(here, roomId) and true or false
end

-- Walk to a room the map already has a route to. False when it has none, or we're there.
local function walkTo(t, roomId, why)
    local here = F2T_MAP_CURRENT_ROOM_ID
    if not roomId or not here or roomId == here or not roomExists(roomId) then return false end
    if not getPath(here, roomId) then return false end
    if why then note(why) end
    t.state = "walking"
    f2t_map_walk_room(roomId)
    if t.paused then f2t_map_speedwalk_pause() end
    return true
end

-- Send commands the map has no rooms for yet (a jump chain, a board).
local function sendCommands(t, commands, why)
    note(why)
    t.state = "walking"
    f2t_map_speedwalk_send_blind(commands)
    if t.paused then f2t_map_speedwalk_pause() end
end

-- A typed nav asks once before travel into the unknown; one yes covers the trip.
local function authorise(t, hint, proceed)
    if not t.ask or not f2t_settings_get("map", "nav_explore_confirm") or not f2tShowNavHintConfirm or not Mux then
        t.ask = false
        proceed()
        return
    end
    local generation = t.generation
    t.state = "asking"
    f2tShowNavHintConfirm(t.destination, hint, "No mapped route", function()
        if trip ~= t or t.generation ~= generation then return end
        t.ask = false
        proceed()
    end, function()
        if trip ~= t or t.generation ~= generation then return end
        finish(t, "stopped")
    end)
end

-- Sweep one system's space or one planet until done() holds. False when that
-- scope was already swept this trip, so sweeping it again can't help.
local function sweep(t, kind, name, flag, why, done)
    local scope = kind .. ":" .. string.lower(name)
    if t.swept[scope] then return false end
    if exploreActive() then
        finish(t, "unreachable", "an exploration is already running; stop it with 'map explore stop' first")
        return true
    end
    t.swept[scope] = true
    local hint = { kind = kind, name = name, flag = flag or "shuttlepad" }
    authorise(t, hint, function()
        note(why)
        f2t_map_brief_hold_acquire("nav")
        t.state = "walking"
        t.sweepStartedAt = os.time()
        t.stopWhen = done
        f2t_map_explore_set_stop_condition(done, "Found the way - ending the search", function() end)
        local function swept()
            if trip == t then t.sweepStartedAt = nil end
        end
        local started
        if kind == "planet" then
            started = f2t_map_explore_planet_start("brief", name, swept, flag and { flag } or nil)
        else
            started = f2t_map_explore_system_start("brief", name, swept)
        end
        if not started then
            clearStopCondition(t)
            finish(t, "unreachable", string.format("couldn't start exploring %s", name))
        end
    end)
    return true
end

-- ── Where the destination is ─────────────────────────────────────────────────

local function placeOfRoom(roomId, flag)
    local area = getRoomArea(roomId)
    local areaName = area and getRoomAreaName(area)
    local system = getRoomUserData(roomId, "fed2_system")
    if (not system or system == "") and area then system = getAreaUserData(area, "fed2_system") end
    if areaName and f2t_map_get_system_from_space_area(areaName) then
        return { system = system or f2t_map_get_system_from_space_area(areaName) }
    end
    return { system = system, planet = areaName, flag = flag }
end

-- The destination as places, {system, planet, flag}, from what the map and the
-- topology model already know. Returns nil plus an error for no such place, or
-- nil, nil, a name to ask the game about (whereis), and a system to fall back on.
local function placeOf(destination)
    local resolved, err = f2t_map_resolve_location(destination)

    local direct = tonumber(destination) or string.match(destination, "^[^%.]+%.[^%.]+%.%d+$")
        or f2t_map_destination_get(string.lower(destination))
    if direct then
        if not resolved then return nil, err end
        return placeOfRoom(resolved)
    end

    local placeName, flag = f2t_map_split_place_and_flag(destination)
    if not placeName then
        -- A bare flag means this planet's
        local here = F2T_MAP_CURRENT_ROOM_ID
        local current = here and placeOfRoom(here, flag)
        if not current or not current.planet then return nil, err or string.format("no %s here", flag) end
        return current
    end

    if flag == "link" then
        return { system = f2t_map_topology_canonical_system(placeName) or placeName }
    end

    if resolved then return placeOfRoom(resolved, flag) end

    local planetArea = f2t_map_get_area_id(placeName)
    local planet = planetArea and f2t_map_lookup_planet(placeName)
    if planet and planet.system and planet.system ~= "" then
        return { system = planet.system, planet = getRoomAreaName(planetArea), flag = flag }
    end

    local knownSystem = f2t_map_lookup_system(placeName) and f2t_map_get_system_from_space_area(
        f2t_map_get_system_space_area_actual(placeName)) or f2t_map_topology_canonical_system(placeName)
    if knownSystem and not flag then return { system = knownSystem } end

    return nil, nil, placeName, knownSystem, flag
end

-- placeOf, asking the game about a place the map has never seen. Works it out
-- once per trip.
local function describe(t, done)
    if t.place then done(t.place) return end
    local place, err, askName, fallbackSystem, flag = placeOf(t.destination)
    if place or not askName then
        t.place = place
        done(place, err)
        return
    end

    note(string.format("Asking where %s is...", askName))
    local generation = t.generation
    f2t_map_whereis_lookup(askName, function(system)
        if trip ~= t or t.generation ~= generation then return end
        if system then
            t.place = { system = system, planet = askName, flag = flag }
        elseif fallbackSystem then
            t.place = { system = fallbackSystem }
        else
            done(nil, string.format("the game knows no place called '%s'", askName))
            return
        end
        done(t.place)
    end)
end

-- ── Planning ─────────────────────────────────────────────────────────────────

local planNext

-- Get off a planet and into its system's space.
local function toSpace(t, planet)
    local here = F2T_MAP_CURRENT_ROOM_ID
    local pad = f2t_map_find_shuttlepad_room(planet)
    if here == pad or f2t_map_room_has_flag(here, "shuttlepad") then
        sendCommands(t, { "board" }, string.format("Boarding to leave %s", planet))
        return true
    end
    if walkTo(t, pad, string.format("Heading to %s's landing pad", planet)) then return true end
    return sweep(t, "planet", planet, nil, string.format("Exploring %s for its landing pad", planet), function()
        return reachable(f2t_map_find_shuttlepad_room(planet))
    end)
end

local function jump(t, from, to)
    local route = f2t_map_topology_route(from, to)
    if not route or #route == 0 then
        if t.lookedUp[string.lower(to)] then
            finish(t, "unreachable", string.format("no known jump route from %s to %s", from, to))
            return
        end
        t.lookedUp[string.lower(to)] = true
        note(string.format("Looking up where the %s system sits...", to))
        local generation = t.generation
        f2t_map_di_system_capture_start(to, function(_, _, noSuchSystem)
            if trip ~= t or t.generation ~= generation then return end
            if noSuchSystem then
                finish(t, "unreachable", string.format("there is no star system called '%s'", to))
                return
            end
            planNext(t)
        end)
        return
    end
    local function send()
        sendCommands(t, route, string.format("Jumping to %s: %s", to, table.concat(route, ", ")))
    end
    if f2t_map_find_link_room_in_system(to) then
        send()
    else
        authorise(t, { kind = "system", name = to, link_only = true }, send)
    end
end

-- Leave this system for the destination's.
local function planTravel(t, place, here, hereSystem, inSpace, hereArea)
    local destLink = f2t_map_find_link_room_in_system(place.system)
    if walkTo(t, destLink, string.format("Heading for the %s system", place.system)) then return end

    local barred = f2t_map_link_barred(hereSystem)
    if barred then
        finish(t, "unreachable", string.format("%s's link won't let you out: %s", hereSystem, barred))
        return
    end
    local localLink = f2t_map_find_link_room_in_system(hereSystem)
    if localLink and localLink == here then
        jump(t, hereSystem, place.system)
        return
    end
    if walkTo(t, localLink, string.format("Heading to %s's interstellar link", hereSystem)) then return end
    if inSpace then
        if sweep(t, "system", hereSystem, nil, string.format("Exploring %s for its interstellar link", hereSystem),
            function() return reachable(f2t_map_find_link_room_in_system(hereSystem)) end) then
            return
        end
        finish(t, "unreachable", string.format("explored %s and found no way to its interstellar link", hereSystem))
        return
    end
    if toSpace(t, hereArea) then return end
    finish(t, "unreachable", string.format("found no way off %s", hereArea))
end

-- Already in the destination's system.
local function planArrival(t, place, here, inSpace, hereArea)
    local function destinationReachable()
        return reachable(f2t_map_resolve_location(t.destination))
    end

    if not place.planet then
        if inSpace then
            if sweep(t, "system", place.system, nil, string.format("Exploring %s space for it", place.system),
                destinationReachable) then
                return
            end
            finish(t, "unreachable", string.format("explored %s space and found no route to it", place.system))
            return
        end
        if toSpace(t, hereArea) then return end
        finish(t, "unreachable", string.format("found no way off %s", hereArea))
        return
    end

    if same(hereArea, place.planet) and place.flag ~= "orbit" then
        local what = place.flag or "destination"
        if sweep(t, "planet", place.planet, place.flag, string.format("Exploring %s for its %s", place.planet, what),
            destinationReachable) then
            return
        end
        finish(t, "unreachable", string.format("explored %s and found no %s", place.planet, what))
        return
    end

    local spaceArea = f2t_map_get_system_space_area_actual(place.system)
    local orbit = spaceArea and f2t_map_find_orbit_room(spaceArea, place.planet)
    if orbit and orbit == here then
        -- Boarding from orbit always sets down on the planet's landing pad
        sendCommands(t, { "board" }, string.format("Landing on %s", place.planet))
        return
    end
    if walkTo(t, orbit, string.format("Heading to %s's orbit", place.planet)) then return end
    if inSpace then
        if sweep(t, "system", place.system, nil, string.format("Exploring %s space for %s", place.system, place.planet),
            function()
                local area = f2t_map_get_system_space_area_actual(place.system)
                return reachable(area and f2t_map_find_orbit_room(area, place.planet))
            end) then
            return
        end
        finish(t, "unreachable", string.format("explored %s space and didn't find %s", place.system, place.planet))
        return
    end
    if toSpace(t, hereArea) then return end
    finish(t, "unreachable", string.format("found no way off %s", hereArea))
end

planNext = function(t)
    if trip ~= t then return end
    t.state = "planning"
    clearStopCondition(t)
    local here = F2T_MAP_CURRENT_ROOM_ID
    if not here or not roomExists(here) then
        finish(t, "unreachable", "you aren't on the map")
        return
    end

    -- The map already knows the way
    local target = f2t_map_resolve_location(t.destination)
    if target == here then
        finish(t, "arrived")
        return
    end
    if walkTo(t, target) then return end

    local generation = t.generation
    describe(t, function(place, err)
        if trip ~= t or t.generation ~= generation then return end
        if not place then
            finish(t, "unreachable", err or "no such place")
            return
        end
        if not place.system or place.system == "" then
            finish(t, "unreachable", "couldn't tell which system it's in")
            return
        end
        local hereNow = F2T_MAP_CURRENT_ROOM_ID
        local area = getRoomArea(hereNow)
        local hereArea = area and getRoomAreaName(area)
        local inSpace = hereArea ~= nil and f2t_map_get_system_from_space_area(hereArea) ~= nil
        local hereSystem = f2t_get_current_system() or getRoomUserData(hereNow, "fed2_system")
        if not hereSystem or hereSystem == "" or not hereArea then
            finish(t, "unreachable", "couldn't tell which system you're in")
            return
        end
        f2t_debug_log("[nav] trip %d leg %d: at %s in %s; destination %s/%s/%s", t.id, t.legs,
            f2t_map_describe_room(hereNow), tostring(hereSystem), tostring(place.system),
            tostring(place.planet), tostring(place.flag))
        if same(hereSystem, place.system) then
            planArrival(t, place, hereNow, inSpace, hereArea)
        else
            planTravel(t, place, hereNow, hereSystem, inSpace, hereArea)
        end
    end)
end

local function launch(t)
    t.generation = t.generation + 1
    t.idlePolls = 0
    t.legs = t.legs + 1
    t.launchRoom = F2T_MAP_CURRENT_ROOM_ID
    planNext(t)
end

local function poll(t)
    if trip ~= t then return end
    t.pollTimer = tempTimer(0.5, function() poll(t) end)
    if t.state ~= "walking" or t.paused or t.holding then return end
    if engineMoving(t) then
        t.idlePolls = 0
        return
    end
    t.idlePolls = t.idlePolls + 1
    if t.idlePolls < IDLE_POLLS_TO_SETTLE then return end

    -- The leg is over. Where it left us decides the next one.
    local here = F2T_MAP_CURRENT_ROOM_ID
    if here and f2t_map_resolve_location(t.destination) == here then
        finish(t, "arrived")
        return
    end
    if here == t.launchRoom and F2T_SPEEDWALK_LAST_RESULT ~= "completed" then
        t.stalls = t.stalls + 1
    else
        t.stalls = 0
    end
    if t.stalls >= MAX_STALLS then
        finish(t, "unreachable", "the way from here is blocked")
        return
    end
    if t.legs >= MAX_LEGS then
        finish(t, "unreachable", string.format("still not there after %d legs", MAX_LEGS))
        return
    end
    f2t_debug_log("[nav] trip %d: leg ended at %s", t.id, f2t_map_describe_room(here))
    launch(t)
end

-- ── API ──────────────────────────────────────────────────────────────────────

--- Whether the room the player stands in is on the map; says what to do when
--- it isn't. Without it there is no route to plan.
--- @return boolean
function f2t_map_on_map()
    if F2T_MAP_CURRENT_ROOM_ID and roomExists(F2T_MAP_CURRENT_ROOM_ID) then return true end
    cecho("\n<yellow>[map]<reset> You aren't on the map yet, so there's no route to plan. Import the bundled " ..
        "map with <white>map import db<reset>, or look around so this room is mapped, then try again.\n")
    return false
end

--- Go somewhere
--- @param destination string|number
--- @param opts table|nil {owner, onDone, ask}
--- @return table trip
function f2tNav.go(destination, opts)
    opts = opts or {}
    local owner = opts.owner or "player"
    if trip then
        local previous = trip
        trip = nil
        haltEngine(previous)
        finish(previous, "superseded", nil, owner)
    end

    F2T_NAV_NEXT_TRIP_ID = (F2T_NAV_NEXT_TRIP_ID or 0) + 1
    local t = {
        id = F2T_NAV_NEXT_TRIP_ID,
        owner = owner,
        destination = destination ~= nil and tostring(destination) or "",
        onDone = opts.onDone,
        ask = opts.ask == true,
        exploreAtStart = exploreActive(),
        generation = 0,
        legs = 0,
        stalls = 0,
        idlePolls = 0,
        swept = {},
        lookedUp = {},
        state = "planning",
    }
    f2t_debug_log("[nav] trip %d: %s -> %s", t.id, owner, t.destination)

    if t.destination == "" then
        finish(t, "unreachable", "no destination given")
        return t
    end
    if not f2t_map_on_map() then
        finish(t, "unreachable", "you aren't on the map")
        return t
    end

    trip = t
    raiseEvent("f2tNavStarted", owner, t.destination)
    t.pollTimer = tempTimer(0.5, function() poll(t) end)
    launch(t)
    return t
end

--- End the current trip as "stopped"
--- @param owner string|nil Only stop a trip this owner started
--- @return boolean true if a trip was stopped
function f2tNav.stop(owner)
    local t = trip
    if not t or (owner and t.owner ~= owner) then return false end
    trip = nil
    haltEngine(t)
    finish(t, "stopped")
    return true
end

-- Pause the trip, or with no trip, a walk an exploration is making
function f2tNav.pause()
    local t = trip
    if not t then
        return F2T_SPEEDWALK_ACTIVE and f2t_map_speedwalk_pause() or false
    end
    if t.paused then return false end
    t.paused = true
    if F2T_SPEEDWALK_ACTIVE then f2t_map_speedwalk_pause() end
    if ownsExplore(t) then f2t_map_explore_pause() end
    cecho("\n<yellow>[map]<reset> Navigation paused\n")
    return true
end

function f2tNav.resume()
    local t = trip
    if not t then
        return F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_PAUSED and f2t_map_speedwalk_resume() or false
    end
    if not t.paused then return false end
    t.paused = false
    t.idlePolls = 0
    if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_PAUSED then f2t_map_speedwalk_resume() end
    if ownsExplore(t) then f2t_map_explore_resume() end
    cecho("\n<green>[map]<reset> Navigation resumed\n")
    return true
end

-- Stop every kind of movement: the trip, and any walk an exploration is making.
-- For when the player can no longer be moved at all (death, revoked control).
function f2tNav.stopAll()
    local stopped = f2tNav.stop()
    if F2T_SPEEDWALK_ACTIVE then
        f2t_map_speedwalk_stop()
        stopped = true
    end
    return stopped
end

--- The trip under way, or a walk an exploration is making (owner and destination nil)
--- @return table|nil {owner, destination, paused}
function f2tNav.status()
    local t = trip
    if t then return { owner = t.owner, destination = t.destination, paused = t.paused == true } end
    if F2T_SPEEDWALK_ACTIVE then return { paused = F2T_SPEEDWALK_PAUSED == true } end
    return nil
end

--- What a trip from `origin` (default: here) would do, without moving. A route
--- the map already has comes back with its move counts; anything else as the legs
--- the planner would take, from what the map and topology know right now.
--- @return table|nil {mapped, fromRoom, toRoom, moves, spaceMoves, legs}, or nil and why
function f2tNav.plan(destination, origin)
    local fromRoom = F2T_MAP_CURRENT_ROOM_ID
    if origin and origin ~= "" then
        local err
        fromRoom, err = f2t_map_resolve_location(origin)
        if not fromRoom then return nil, string.format("can't find the origin: %s", err or origin) end
    end
    if not fromRoom or not roomExists(fromRoom) then return nil, "you aren't on the map" end
    destination = tostring(destination or "")
    if destination == "" then return nil, "no destination given" end

    local toRoom = f2t_map_resolve_location(destination)
    if toRoom == fromRoom then
        return { mapped = true, fromRoom = fromRoom, toRoom = toRoom, moves = 0, spaceMoves = 0, legs = {} }
    end
    if toRoom and getPath(fromRoom, toRoom) then
        local spaceMoves = 0
        for _, roomId in ipairs(speedWalkPath) do
            if getRoomUserData(tonumber(roomId), "fed2_flag_space") == "true" then spaceMoves = spaceMoves + 1 end
        end
        return { mapped = true, fromRoom = fromRoom, toRoom = toRoom, moves = #speedWalkDir,
            spaceMoves = spaceMoves, legs = {} }
    end

    local place, err, askName = placeOf(destination)
    local legs = {}
    if not place then
        if not askName then return nil, err or "no such place" end
        table.insert(legs, string.format("Ask the game where %s is, then travel there", askName))
        return { mapped = false, fromRoom = fromRoom, toRoom = toRoom, legs = legs }
    end

    local area = getRoomArea(fromRoom)
    local fromArea = area and getRoomAreaName(area)
    local fromSystem = getRoomUserData(fromRoom, "fed2_system")
    if (not fromSystem or fromSystem == "") and area then fromSystem = getAreaUserData(area, "fed2_system") end
    local inSpace = fromArea and f2t_map_get_system_from_space_area(fromArea) ~= nil

    if not same(fromSystem, place.system) then
        if not inSpace then table.insert(legs, string.format("Leave %s for space", fromArea or "this planet")) end
        if f2t_map_find_link_room_in_system(fromSystem or "") then
            table.insert(legs, string.format("Go to %s's interstellar link", fromSystem))
        else
            table.insert(legs, string.format("Explore %s for its interstellar link", fromSystem or "this system"))
        end
        local route = f2t_map_topology_route(fromSystem, place.system)
        if route and #route > 0 then
            table.insert(legs, table.concat(route, ", "))
        else
            table.insert(legs, string.format("Look up where %s sits, then jump there", place.system))
        end
    elseif not inSpace and place.planet and not same(fromArea, place.planet) then
        table.insert(legs, string.format("Leave %s for space", fromArea or "this planet"))
    end

    if place.planet then
        local spaceArea = f2t_map_get_system_space_area_actual(place.system)
        if not same(fromArea, place.planet) then
            if spaceArea and f2t_map_find_orbit_room(spaceArea, place.planet) then
                table.insert(legs, string.format("Fly to %s's orbit", place.planet))
            else
                table.insert(legs, string.format("Explore %s space for %s", place.system, place.planet))
            end
        end
        if place.flag ~= "orbit" then
            if not same(fromArea, place.planet) then table.insert(legs, string.format("Land on %s", place.planet)) end
            if toRoom then
                table.insert(legs, string.format("Walk to %s", getRoomName(toRoom) or "the destination"))
            else
                table.insert(legs, string.format("Explore %s for its %s", place.planet, place.flag or "destination"))
            end
        end
    elseif not toRoom then
        table.insert(legs, string.format("Explore %s space for it", place.system))
    end
    return { mapped = false, fromRoom = fromRoom, toRoom = toRoom, legs = legs }
end

--- True while a trip is under way or the engine is walking for anyone
function f2tNav.busy()
    return trip ~= nil or F2T_SPEEDWALK_ACTIVE == true or F2T_SPEEDWALK_CUSTOMS_PENDING == true
end

-- Customs stopped the walk. A trip's own walk waits out the inspection and plans
-- again from wherever it left us; returns false when no trip owns the walk.
function f2tNav.holdForCustoms()
    local t = trip
    if not t or ownsExplore(t) then return false end
    t.holding = true
    t.generation = t.generation + 1
    f2t_map_speedwalk_stop()
    tempTimer(1.0, function()
        if trip ~= t then return end
        send("look")
        tempTimer(1.0, function()
            if trip ~= t then return end
            t.holding = false
            cecho("\n<yellow>[map]<reset> Resuming navigation after customs...\n")
            launch(t)
        end)
    end)
    return true
end

-- A reload replaces these handlers rather than adding to them.
for _, handlerId in ipairs(F2T_NAV_HANDLER_IDS or {}) do killAnonymousEventHandler(handlerId) end
F2T_NAV_HANDLER_IDS = {
    -- The player stopped an exploration that was this trip's sweep: that stops the trip.
    registerAnonymousEventHandler("f2tExploreStopped", function(_, reason)
        local t = trip
        if t and reason == nil and not t.exploreAtStart then
            trip = nil
            if F2T_SPEEDWALK_ACTIVE then f2t_map_speedwalk_stop() end
            finish(t, "stopped")
        end
    end),
    -- A dead socket looks like a blocked exit to the walk; hold it until the connection is back.
    registerAnonymousEventHandler("sysDisconnectionEvent", function()
        f2t_map_speedwalk_pause_for_disconnect()
    end),
}

f2t_debug_log("[map] Loaded nav_api.lua")
