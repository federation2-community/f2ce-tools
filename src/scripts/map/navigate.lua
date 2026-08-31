-- f2ce-tools map — navigation (ported from map_navigate.lua)
--
-- f2t_map_navigate(destination, opts) is the shared speedwalk entry point.
--
-- It returns a status, always one of:
--   "walking"  a speedwalk is in flight
--   "arrived"  already standing there, nothing sent
--   "pending"  resolving asynchronously (auto-explore, whereis, a location
--              retry); the outcome arrives through on_result
--   "failed"   no route, and nothing left to try
-- f2t_map_navigate_ok(status) is the "did we get moving" test callers want;
-- reading the status for truthiness would read "failed" as success.
--
-- opts (all optional):
--   interactive   - show a confirm dialog before auto-exploring an unmapped
--                   destination (used by the `nav` alias; a typed name could
--                   be a typo). Automated callers omit this and self-heal
--                   immediately instead.
--   on_result(ok, status) - fired exactly once for every call, whichever path
--                   it takes. The statuses settled synchronously fire it on
--                   the next tick, so it never re-enters the caller mid-call.
--   suppress_hint - skip hint handling entirely, behave like plain failure.
--   compensate_incomplete_map - when getPath() finds no route through
--                   locally-mapped rooms to an otherwise-known destination,
--                   fall back to ordinary local pathing toward the
--                   destination system's link room, then to auto-exploring
--                   the remaining gap (asking `whereis` only as a last
--                   resort, for the system name) rather than just failing.
--                   Off by default: many callers pass room ids/hashes rather
--                   than real place names, for which asking `whereis`
--                   wouldn't make sense.
--   target_room_id - internal. The room the whole chain is trying to reach,
--                   carried so an auto-explore can stop the moment a route to
--                   it exists instead of finishing a sweep whose job is done.
--   explored      - internal. Scopes this chain has already swept, so it
--                   never runs the same fruitless sweep twice.
--   compensate_attempt - internal. Counts how many times this chain has
--                   already fallen back to compensating, so reach_system ->
--                   explore -> navigate -> reach_system cannot lap forever.

-- A full self-heal runs to four legs, each making real progress and each
-- needing its own pass: sweep the system we are standing in for its
-- interstellar link, walk to the destination system's link room, sweep that
-- system for the planet's orbit and the way down, then sweep the planet for
-- the room actually asked for. The `explored` set is what really bounds the
-- chain - a scope is never swept twice - and this is the backstop.
local MAX_COMPENSATE_ATTEMPTS = 4

-- Did a navigate get us moving, or find us already standing there?
function f2t_map_navigate_ok(status)
    return status == "walking" or status == "arrived"
end

function f2t_map_navigate(destination, opts)
    opts = opts or {}

    -- Settle the call: hand the caller a status and fire on_result once. The
    -- callback goes on the next tick so a synchronous outcome cannot re-enter
    -- the caller before its own next statement has run.
    local function settle(status)
        local callback = opts.on_result
        if callback then
            tempTimer(0, function() callback(f2t_map_navigate_ok(status), status) end)
        end
        return status
    end

    f2t_debug_log("[map] f2t_map_navigate destination is '%s'", destination)
    f2t_debug_log("[map/nav] navigate('%s') attempt=%d compensate=%s interactive=%s",
        tostring(destination), (opts.compensate_attempt or 0),
        tostring(opts.compensate_incomplete_map or false), tostring(opts.interactive or false))
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n"); return settle("failed")
    end
    local target_id, error_msg, hint = f2t_map_resolve_location(destination)
    f2t_debug_log("[map/nav]   resolved to %s%s", f2t_map_describe_room(target_id),
        target_id and "" or string.format(" - %s, hint=%s", tostring(error_msg),
            hint and string.format("%s '%s'", tostring(hint.kind), tostring(hint.name)) or "none"))
    if not target_id then
        -- Never launch a new hint-driven explore while one is already active -
        -- it would stomp the single global F2T_MAP_EXPLORE_STATE mid-sweep.
        local exploring_already = F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active
        if hint and not opts.suppress_hint and not exploring_already then
            f2t_map_navigate_handle_hint(destination, hint, error_msg, opts)
            return "pending"
        end
        -- Say why, when the reason is us rather than the name. Reporting the
        -- resolve error here reads as "no such place" for a place that is
        -- perfectly real and would have been found a moment earlier.
        if hint and not opts.suppress_hint and exploring_already then
            cecho(string.format(
                "\n<yellow>[map]<reset> Not looking up '%s': an exploration is still running." ..
                " Use <white>map explore stop<reset> first\n", tostring(destination)))
            return settle("failed")
        end
        cecho(string.format("\n<red>[map]<reset> %s\n", error_msg or "Could not find destination"))
        return settle("failed")
    end
    -- A retry is already scheduled with the same opts, and it is the one that
    -- settles: reporting a result here would fire on_result twice.
    if not f2t_map_ensure_current_location(f2t_map_navigate, {destination, opts}) then
        return "pending"
    end
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    if current_room_id == target_id then
        cecho("\n<green>[map]<reset> You are already at the destination\n")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return settle("arrived")
    end
    local success = getPath(current_room_id, target_id)
    f2t_debug_log("[map/nav]   from %s: getPath %s%s", f2t_map_describe_room(current_room_id),
        success and "ok" or "NO ROUTE",
        success and string.format(" (%d steps: %s)", #speedWalkDir,
            table.concat(speedWalkDir, ", ")) or "")
    if not success then
        if opts.compensate_incomplete_map and (opts.compensate_attempt or 0) < MAX_COMPENSATE_ATTEMPTS then
            f2t_map_navigate_compensate(destination, target_id, opts)
            return "pending"
        end
        local current_area = getRoomArea(current_room_id)
        local target_area  = getRoomArea(target_id)
        cecho("\n<red>[map]<reset> No path found to destination\n")
        cecho(string.format("\n<dim_grey>Current: Room %d (%s)<reset>\n",
            current_room_id, current_area and getRoomAreaName(current_area) or "unknown"))
        cecho(string.format("<dim_grey>Target: Room %d (%s)<reset>\n",
            target_id, target_area and getRoomAreaName(target_area) or "unknown"))
        if current_area ~= target_area then
            cecho("\n<yellow>[map]<reset> Rooms are in different areas - make sure areas are connected\n")
        end
        return settle("failed")
    end
    if #speedWalkDir == 0 then
        cecho("\n<green>[map]<reset> Already at destination\n")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return settle("arrived")
    end
    -- Hand the walk what it needs to come back here if its route evaporates.
    F2T_SPEEDWALK_NAV_REQUEST = opts.compensate_incomplete_map and {
        destination = destination,
        opts = {
            compensate_incomplete_map = true,
            compensate_attempt = (opts.compensate_attempt or 0) + 1,
            interactive        = opts.interactive,
            target_room_id     = opts.target_room_id or target_id,
            explored           = opts.explored,
            on_result          = opts.on_result,
        },
    } or nil
    doSpeedWalk()
    return settle("walking")
end

-- ── Hint handling ────────────────────────────────────────────────────────────
-- resolve_location couldn't find the destination outright, but returned a hint
-- worth acting on: a locally-known-but-incomplete planet/system, or a bare
-- name worth asking the game's `whereis` about before giving up on it.

-- Ask before exploring, once. `run` gets opts with `interactive` cleared, so
-- a single yes authorises the whole self-heal instead of stopping to ask
-- again for each leg of the thing it just authorised.
--
-- Two things can waive the question: an automated caller, which never wanted
-- to be asked, and the "Ask before auto-exploring" setting, which is how
-- someone who always answers yes stops being asked. Read at the point of use
-- so a change in the settings tab takes effect on the next nav.
local function confirmThen(destination, hint, error_msg, opts, run)
    if not opts.interactive or not f2t_settings_get("map", "nav_explore_confirm") then
        run(opts)
        return
    end
    local proceedOpts = {}
    for key, value in pairs(opts) do proceedOpts[key] = value end
    proceedOpts.interactive = nil

    f2tShowNavHintConfirm(destination, hint, error_msg,
        function() run(proceedOpts) end,
        function()
            cecho(string.format("\n<red>[map]<reset> %s\n", error_msg))
            if opts.on_result then opts.on_result(false, "failed") end
        end)
end

function f2t_map_navigate_handle_hint(destination, hint, error_msg, opts)
    if hint.kind == "whereis_pending" then
        cecho(string.format("\n<dim_grey>[map] Checking whereis for '%s'...<reset>\n", hint.name))
        f2t_map_whereis_lookup(hint.name, function(system_name)
            if system_name then
                local system_hint = {kind = "system", name = system_name}
                f2t_map_navigate_handle_hint(destination, system_hint, error_msg, opts)
            else
                cecho(string.format("\n<red>[map]<reset> %s\n", error_msg))
                if opts.on_result then opts.on_result(false, "failed") end
            end
        end)
        return
    end

    -- A link target has nothing to discover at the far end, so the only
    -- thing worth asking about is whether we must explore *this* system first
    -- to find the link we jump from. Explore neither end, ask nothing.
    if hint.link_only then
        local hereSystem = f2t_get_current_system()
        local haveLocalLink = hereSystem and hereSystem ~= ""
            and f2t_map_find_link_room_in_system(hereSystem) ~= nil
        if haveLocalLink then
            f2t_map_navigate_explore_hint(destination, hint, opts)
            return
        end
    end

    confirmThen(destination, hint, error_msg, opts, function(next_opts)
        f2t_map_navigate_explore_hint(destination, hint, next_opts)
    end)
end

function f2t_map_navigate_explore_hint(destination, hint, opts)
    local settled = false
    local timer_id

    local explored = opts.explored or {}
    local linkWanted = nil
    local finishEarly = false

    -- Every jump starts from the interstellar link of the system we are in.
    -- With that unmapped there is no way out of here at all, so a sweep of
    -- anywhere else cannot even set off - the explorer would walk to some
    -- arbitrary room in local space and jump from it, which the game answers
    -- with "You jump up and down, but nothing happens." Sweep here first; the
    -- retry then carries on to the real target now that there is a way out.
    local hereSystem = f2t_get_current_system()

    -- Nothing outside this system is reachable at all while its link refuses
    -- us, so say that now rather than after a walk across the system to find
    -- out again at the link.
    local barredReason = hereSystem and f2t_map_link_barred and f2t_map_link_barred(hereSystem)
    if barredReason and string.lower(hint.name or "") ~= string.lower(hereSystem) then
        cecho(string.format("\n<red>[map]<reset> Cannot reach '%s': %s\n",
            tostring(destination), barredReason))
        finishEarly = true
    end

    if hereSystem and hereSystem ~= ""
        and not f2t_map_find_link_room_in_system(hereSystem)
        and string.lower(hint.name or "") ~= string.lower(hereSystem) then
        f2t_debug_log("[map/nav] explore: no link mapped in %s - sweeping here before %s",
            hereSystem, tostring(hint.name))
        cecho(string.format(
            "\n<cyan>[map]<reset> No interstellar link mapped in %s yet - exploring here first\n",
            hereSystem))
        hint = {kind = "system", name = hereSystem}
        linkWanted = hereSystem
    end

    -- Travelling, not sweeping: the destination is a link and we already have
    -- a link here to jump from. Kept as its own scope so it never collides
    -- with a real sweep of the same system.
    local travelOnly = hint.link_only and not linkWanted
    local scope = string.format("%s:%s",
        travelOnly and "link" or hint.kind, string.lower(hint.name or ""))

    local function finish(success, status)
        if settled then return end
        settled = true
        if timer_id then killTimer(timer_id); timer_id = nil end
        f2t_map_brief_hold_release("nav")
        if opts.on_result then opts.on_result(success, status or "failed") end
    end

    local function on_complete()
        -- Hints stay live for the retry. Sweeping one scope routinely only
        -- earns the right to attempt the next - find the local link, then the
        -- destination system, then the planet - and `explored` below is what
        -- stops that turning into a loop, so suppressing hints here would
        -- only cut the chain off one leg short of the answer.
        local result = f2t_map_navigate(destination, {
            compensate_incomplete_map = opts.compensate_incomplete_map,
            compensate_attempt = (opts.compensate_attempt or 0) + 1,
            target_room_id = opts.target_room_id,
            explored = explored,
        })
        finish(f2t_map_navigate_ok(result), result)
    end

    if finishEarly then
        finish(false)
        return
    end

    -- Sweeping the same scope again cannot find anything the first pass
    -- missed, and each pass is real in-game travel.
    if explored[scope] then
        f2t_debug_log("[map] Already swept %s this trip, not repeating it", scope)
        finish(false)
        return
    end
    explored[scope] = true

    -- Hold brief for the whole self-heal rather than letting each leg take and
    -- give it back: a sweep that ends and hands straight to a walk was sending
    -- full, brief, full again within a second or two. The explorer's own
    -- acquire and release become no-ops while this is held, and the walks skip
    -- their own toggling.
    f2t_map_brief_hold_acquire("nav")

    if travelOnly then
        f2t_debug_log("[map/nav] travel: %s's link, nothing to sweep at that end", hint.name)
        cecho(string.format(
            "\n<cyan>[map]<reset> Jumping to %s - nothing to explore at that end\n", hint.name))
        -- The explorer owns the travel primitive and the arrival dispatcher
        -- that drives it, so claim the run for the trip and hand it straight
        -- back. No sweep follows, and no stop condition is needed: arriving
        -- is the whole job.
        local claimed = not F2T_MAP_EXPLORE_STATE.active
        if claimed then f2t_map_explore_claim_run("system") end
        local function travelDone(arrived)
            if claimed then f2t_map_explore_release_run() end
            if arrived then on_complete() else finish(false) end
        end
        f2t_map_explore_travel_to("system", hint.name,
            function() travelDone(true) end,
            function() travelDone(false) end)
        timer_id = tempTimer(180, function() finish(false) end)
        return
    end

    f2t_debug_log("[map/nav] explore: sweeping %s to reach '%s'", scope, tostring(destination))
    local started = false
    if hint.kind == "planet" then
        started = f2t_map_explore_planet_start("brief", hint.name, on_complete, {hint.flag})
    elseif hint.kind == "system" then
        started = f2t_map_explore_system_start("brief", hint.name, on_complete)
    end

    if not started then
        finish(false)
        return
    end

    -- The sweep exists to find a route, so end it the moment there is one -
    -- left alone it keeps flying the whole system long after the answer is in,
    -- which is how a nav to one planet emptied the fuel tank.
    --
    -- Handed to the explorer as a predicate rather than watched from a GMCP
    -- handler out here: an outside handler runs after the explorer has already
    -- sent its next move, so it stops one step past the answer and has to
    -- backtrack. The explorer asks this before it chooses.
    --
    -- Re-resolve rather than watching the room id we started with. Reaching a
    -- planet's orbit is already the whole answer - boarding from orbit always
    -- lands you on its shuttlepad - and the arrival stubs that room and wires
    -- the "board" exit to it. So the destination resolves to a room that did
    -- not exist when this began, and the id we set out with may be an older,
    -- orphaned one that never becomes reachable at all.
    local function routeExists()
        local here = F2T_MAP_CURRENT_ROOM_ID
        if not here then return false end
        -- A sweep redirected to find the local interstellar link is done the
        -- moment that room is mapped; the rest of the system is not its job.
        if linkWanted then
            return f2t_map_find_link_room_in_system(linkWanted) ~= nil
        end
        local target = f2t_map_resolve_location(destination) or opts.target_room_id
        if not target or not roomExists(target) then return false end
        return here == target or getPath(here, target) and true or false
    end

    F2T_MAP_EXPLORE_STATE.stop_when = routeExists
    F2T_MAP_EXPLORE_STATE.stop_reason = linkWanted
        and string.format("Found %s's interstellar link - ending the sweep early", linkWanted)
        or "Route to the destination found - ending the sweep early"
    F2T_MAP_EXPLORE_STATE.on_stop_early = function()
        if settled then return end
        f2t_debug_log("[map/nav] explore: %s - swept enough",
            linkWanted and string.format("%s's interstellar link is mapped", linkWanted)
                or string.format("'%s' now resolves to a reachable room", tostring(destination)))
        tempTimer(0.5, function()
            if not settled then on_complete() end
        end)
    end

    timer_id = tempTimer(180, function() finish(false) end)
end

-- ── Compensating for an incomplete map ──────────────────────────────────────
-- getPath() only knows rooms/exits this map has actually recorded, and it's
-- all-or-nothing: it won't hand back a route that gets partway there even
-- when most of the journey - the jump chain into the destination's system -
-- is already well mapped and has worked before. So always try ordinary local
-- pathing to the destination system's link room first; that's the reliable
-- part, and it's just getPath()/doSpeedWalk doing their normal job, nothing
-- game-text-driven about it. `whereis` only enters the picture as a last
-- resort, and only ever to learn the destination's system NAME - never to
-- have its suggested command text parsed or sent. That text isn't meant to
-- be executed verbatim (this game has no ";"-style command chaining, client
-- or server side) and once the system name is known, ordinary local pathing
-- to that system's link room already does the job more reliably anyway.

function f2t_map_navigate_compensate(destination, target_id, opts)
    opts = opts or {}
    local target_area_id = target_id and roomExists(target_id) and getRoomArea(target_id)
    local target_system   = target_area_id and getAreaUserData(target_area_id, "fed2_system")
    if not (target_system and target_system ~= "") then
        f2t_map_navigate_whereis_for_system(destination, target_id, opts)
        return
    end

    -- Settle the whole plan before anything moves. If the map already joins
    -- that system's link room to the target, this is only a walk and needs no
    -- permission. If it doesn't, exploring is coming either way - so ask now,
    -- rather than part-way through the long speedwalk the answer was going to
    -- authorise.
    opts.target_room_id = opts.target_room_id or target_id
    opts.explored = opts.explored or {}

    local link_room = f2t_map_find_link_room_in_system(target_system)
    local link_reaches = link_room and roomExists(link_room) and getPath(link_room, target_id) or false
    f2t_debug_log("[map/nav] compensate: target %s is in the %s system; its link room is %s; "
        .. "link -> target %s", f2t_map_describe_room(target_id), tostring(target_system),
        f2t_map_describe_room(link_room), link_reaches and "reachable" or "NOT reachable")
    if link_room and roomExists(link_room) and not link_reaches then
        local hint = f2t_map_navigate_target_hint(target_id, target_system, link_room)
        hint.mapped_but_unreachable = true
        confirmThen(destination, hint, "No mapped route to destination", opts, function(next_opts)
            f2t_map_navigate_reach_system(destination, target_id, target_system, next_opts)
        end)
        return
    end

    f2t_map_navigate_reach_system(destination, target_id, target_system, opts)
end

-- Ordinary getPath()/speedwalk to a known system's link room. If we're
-- already standing at it, the gap is purely the ground-level stretch beyond
-- it (a planet's shuttlepad, reached via "board" from its orbit - system
-- exploration alone never lands), so hand that straight to the same
-- confirm-then-explore flow used for any unmapped destination
-- (f2t_map_navigate_handle_hint), scoped to just that planet's own area
-- rather than sweeping the whole system.
function f2t_map_navigate_reach_system(destination, target_id, system_name, opts)
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    local link_room = f2t_map_find_link_room_in_system(system_name)
    f2t_debug_log("[map/nav] reach_system(%s): link room %s, standing in %s", tostring(system_name),
        f2t_map_describe_room(link_room), f2t_map_describe_room(current_room_id))
    if link_room and link_room == current_room_id then
        local hint = f2t_map_navigate_target_hint(target_id, system_name)
        f2t_map_navigate_handle_hint(destination, hint, "No path found to destination", opts)
        return
    end
    if not link_room or not roomExists(link_room) or not getPath(current_room_id, link_room) then
        f2t_map_navigate_whereis_for_system(destination, target_id, opts)
        return
    end
    cecho(string.format(
        "\n<dim_grey>[map] No mapped route to the exact destination yet - heading to %s's link room first...<reset>\n",
        system_name))
    doSpeedWalk()
    local function poll()
        if F2T_SPEEDWALK_ACTIVE then
            tempTimer(0.5, poll)
            return
        end
        if F2T_SPEEDWALK_LAST_RESULT ~= "completed" then
            cecho("\n<red>[map]<reset> No path found to destination\n")
            if opts.on_result then opts.on_result(false, "failed") end
            return
        end
        f2t_map_navigate(destination, {
            suppress_hint             = true,
            compensate_incomplete_map = true,
            compensate_attempt        = (opts.compensate_attempt or 0) + 1,
            interactive               = opts.interactive,
            target_room_id            = opts.target_room_id or target_id,
            explored                  = opts.explored,
            on_result                 = opts.on_result,
        })
    end
    tempTimer(0.5, poll)
end

-- Last resort: the destination's system isn't known locally at all, or
-- local pathing can't reach its link room through the mapped jump graph.
-- Ask whereis purely for the system's name, then hand off to the same
-- confirm-then-explore flow as any other unmapped destination.
function f2t_map_navigate_whereis_for_system(destination, target_id, opts)
    -- whereis takes a bare planet name and nothing else. "mars exchange", a
    -- room id or a room hash would just draw the not-found line, which reads
    -- back as "no such place" and abandons a destination already resolved to a
    -- real room.
    local place = f2t_map_whereis_subject(destination)
    if not place then
        cecho("\n<red>[map]<reset> No path found to destination\n")
        if opts.on_result then opts.on_result(false, "failed") end
        return
    end
    cecho(string.format(
        "\n<dim_grey>[map] No mapped route yet - checking whereis for '%s'...<reset>\n", place))
    f2t_map_whereis_lookup(place, function(system_name)
        if not system_name then
            cecho("\n<red>[map]<reset> No path found to destination\n")
            if opts.on_result then opts.on_result(false, "failed") end
            return
        end
        local hint = f2t_map_navigate_target_hint(target_id, system_name)
        f2t_map_navigate_handle_hint(destination, hint, "No path found to destination", opts)
    end)
end

-- The place part of a destination, or nil when there is nothing whereis could
-- usefully be asked about: a Mudlet room id, a Fed2 room hash, or a bare flag
-- word with no place attached.
function f2t_map_whereis_subject(destination)
    if not destination or destination == "" then return nil end
    if tonumber(destination) then return nil end
    if string.match(destination, "^[^%.]+%.[^%.]+%.%d+$") then return nil end
    local place = f2t_map_split_place_and_flag(destination)
    return place
end

-- Picks the scope of exploration that can actually close the gap. The two
-- fix different things and neither substitutes for the other: a system sweep
-- maps space - orbits, and the "board" links down - but never lands, so it
-- can't find a shuttlepad; a planet sweep maps the surface but has to be
-- standing on it to start.
--
-- Boarding from orbit always sets you down on the shuttlepad, so a shuttlepad
-- target never needs its planet swept - only the route to the planet, which
-- is the system's business. And a deeper surface target only warrants a
-- planet sweep once that planet's orbit is mapped and reachable, since a
-- planet sweep has to start from the surface. `from_room` is where the sweep
-- would begin from, which is not where we are standing when the plan is being
-- settled up front.
function f2t_map_navigate_target_hint(target_id, system_name, from_room)
    local target_area_id   = target_id and roomExists(target_id) and getRoomArea(target_id)
    local target_area_name = target_area_id and getRoomAreaName(target_area_id)
    local space_area_name  = f2t_map_get_system_space_area_actual(system_name)
    if not target_area_name or target_area_name == space_area_name then
        f2t_debug_log("[map/nav]   scope: system %s (target is in the system's own space area)", system_name)
        return {kind = "system", name = system_name}
    end
    if f2t_map_room_has_flag(target_id, "shuttlepad") then
        f2t_debug_log("[map/nav]   scope: system %s (target is %s's shuttlepad - boarding from orbit lands there)",
            system_name, target_area_name)
        return {kind = "system", name = system_name}
    end

    local orbit_room = f2t_map_find_orbit_room(space_area_name, target_area_name)
    from_room = from_room or F2T_MAP_CURRENT_ROOM_ID
    if orbit_room and from_room and getPath(from_room, orbit_room) then
        f2t_debug_log("[map/nav]   scope: planet %s (its orbit %s is already reachable)",
            target_area_name, f2t_map_describe_room(orbit_room))
        return {kind = "planet", name = target_area_name, flag = f2t_map_planet_nav_default()}
    end
    f2t_debug_log("[map/nav]   scope: system %s (%s's orbit is %s)", system_name, target_area_name,
        orbit_room and "mapped but unreachable" or "not mapped")
    return {kind = "system", name = system_name}
end
