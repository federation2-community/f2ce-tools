-- What the game files say about Sol (sol_mechanics.lua, generated), applied to
-- a map the player explores themselves. As rooms are reached: a known special
-- exit is added once both its ends are mapped, a ride's holding room is marked
-- so walks wait there, and an exit into a room that kills on entry is locked
-- (as 'map exit death' does) before anything walks through it.

local index = nil

local function sol_hash(planet, num)
    return string.format("Sol.%s.%d", planet, num)
end

local function build_index()
    index = { rooms = {}, deadly = {} }
    local function entry(hash)
        index.rooms[hash] = index.rooms[hash] or { out = {}, into = {} }
        return index.rooms[hash]
    end
    for planet, data in pairs(F2T_SOL_MECHANICS or {}) do
        for _, special in ipairs(data.special or {}) do
            local from, command, to = sol_hash(planet, special[1]), special[2], sol_hash(planet, special[3])
            table.insert(entry(from).out, { command = command, to = to })
            table.insert(entry(to).into, { command = command, from = from })
        end
        for _, num in ipairs(data.transit or {}) do entry(sol_hash(planet, num)).transit = true end
        index.deadly[planet] = {}
        for _, num in ipairs(data.deadly or {}) do index.deadly[planet][num] = true end
    end
end

local function mapped(hash)
    local id = getRoomIDbyHash(hash)
    return (id and id > 0) and id or nil
end

local function link(from_id, to_id, command)
    local existing = getSpecialExitsSwap(from_id) or {}
    if existing[command] == to_id then return end
    addSpecialExit(from_id, to_id, command)
    f2t_debug_log("[map/mechanics] special exit %d --%s--> %d", from_id, command, to_id)
end

local DIRECTION_NAMES = { n = "north", ne = "northeast", e = "east", se = "southeast", s = "south",
    sw = "southwest", w = "west", nw = "northwest", up = "up", down = "down", ["in"] = "in", out = "out" }

--- Apply known Sol mechanics to the room just reached (called from the GMCP room handler)
--- @param room_id number
--- @param room_data table gmcp.room.info
function f2t_map_apply_known_mechanics(room_id, room_data)
    if room_data.system ~= "Sol" or not F2T_SOL_MECHANICS then return end
    if not index then build_index() end

    local here = index.rooms[sol_hash(room_data.area, room_data.num)]
    if here then
        if here.transit and getRoomUserData(room_id, "fed2_transit") ~= "true" then
            setRoomUserData(room_id, "fed2_transit", "true")
        end
        for _, special in ipairs(here.out) do
            local to_id = mapped(special.to)
            if to_id then link(room_id, to_id, special.command) end
        end
        for _, special in ipairs(here.into) do
            local from_id = mapped(special.from)
            if from_id then link(from_id, room_id, special.command) end
        end
    end

    local deadly = index.deadly[room_data.area]
    if deadly and room_data.exits then
        for short, num in pairs(room_data.exits) do
            local direction = DIRECTION_NAMES[short] or short
            local dest = (getRoomExits(room_id) or {})[direction]
            local done = dest and hasExitLock(room_id, direction) and getRoomUserData(dest, "f2t_danger") == "true"
            if deadly[tonumber(num)] and not done then
                cecho(string.format("\n<red>[map]<reset> The game files say %s kills on entry; locking that way.\n",
                    direction))
                f2t_map_manual_death_exit(room_id, direction)
            end
        end
    end
end

--- What the game files say it takes to reach a named Akaturi room on a Sol
--- planet, or nil when walking does it
--- @param planet string
--- @param room string
--- @return table|nil { via = {"command (room)", ...}, gate = "..." }
function f2t_map_sol_route_note(planet, room)
    local data = F2T_SOL_MECHANICS and F2T_SOL_MECHANICS[planet]
    return data and data.pickups and data.pickups[room] or nil
end

--- Known special exits on a planet that the map hasn't crossed yet: the room
--- they start from is mapped, the room they lead to isn't
--- @param planet string
--- @param skip table|nil keys "from|command" to leave out
--- @return table list of { from_id, command, to_num }
function f2t_map_sol_uncrossed(planet, skip)
    local data = F2T_SOL_MECHANICS and F2T_SOL_MECHANICS[planet]
    local list = {}
    for _, special in ipairs(data and data.special or {}) do
        local key = planet .. "|" .. special[1] .. "|" .. special[2]
        local from_id = mapped(sol_hash(planet, special[1]))
        if from_id and not mapped(sol_hash(planet, special[3])) and not (skip and skip[key]) then
            table.insert(list, { from_id = from_id, command = special[2], to_num = special[3], key = key })
        end
    end
    return list
end

local function sol_planet_rooms(planet)
    local data = F2T_SOL_MECHANICS and planet and F2T_SOL_MECHANICS[planet]
    return data and data.rooms and data or nil
end

local function has_flag(room, flag)
    return string.find("," .. room[2] .. ",", "," .. flag .. ",", 1, true) ~= nil
end

--- Whether the game files give a Sol planet a room with this flag
--- @return boolean|nil nil when there is no data for the planet
function f2t_map_sol_planet_has_flag(planet, flag)
    local data = sol_planet_rooms(planet)
    if not data then return nil end
    for _, room in pairs(data.rooms) do
        if has_flag(room, flag) then return true end
    end
    return false
end

-- Where walking into room num really leaves you
local function landing(data, num)
    local seen = {}
    while data.bounce[num] and not seen[num] do
        seen[num] = true
        num = data.bounce[num]
    end
    return num
end

--- The fewest moves the game files give from room `from` to the nearest room
--- `wanted(num, name, flags)` accepts, never through a room that kills
--- @return table|nil commands, number|nil destination room number
function f2t_map_sol_route(planet, from, wanted)
    local data = sol_planet_rooms(planet)
    if not data or not data.rooms[from] then return nil end
    if not index then build_index() end
    local deadly = index.deadly[planet] or {}
    local specials = {}
    for _, special in ipairs(data.special or {}) do
        specials[special[1]] = specials[special[1]] or {}
        table.insert(specials[special[1]], { special[2], special[3] })
    end

    local previous = { [from] = false }
    local queue, head = { from }, 1
    while head <= #queue do
        local num = queue[head]
        head = head + 1
        local room = data.rooms[num]
        if num ~= from and wanted(num, room[1], room[2]) then
            local commands = {}
            while previous[num] do
                table.insert(commands, 1, previous[num].command)
                num = previous[num].from
            end
            return commands, queue[head - 1]
        end
        local steps = {}
        for short, dest in string.gmatch(room[3], "([^,:]+):(%d+)") do
            table.insert(steps, { short, tonumber(dest) })
        end
        for _, special in ipairs(specials[num] or {}) do table.insert(steps, special) end
        for _, step in ipairs(steps) do
            local dest = landing(data, step[2])
            if data.rooms[dest] and previous[dest] == nil and not deadly[dest] then
                previous[dest] = { from = num, command = step[1] }
                table.insert(queue, dest)
            end
        end
    end
    return nil
end

f2t_debug_log("[map] Loaded mechanics.lua")
