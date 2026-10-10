-- f2ce-tools map — room query utilities (ported from map_room_query.lua)

-- Prefer a room the map can actually reach from where we stand. A map can
-- hold a stranded duplicate of a whole system or planet area (a Dyson
-- Sphere rebuild, a stale import), and every one of its rooms answers a
-- flag/name lookup just as readily as the live one - which is how a nav or
-- an "already explored" check ends up pointing at a room nothing can
-- actually walk to.
local function preferReachable(candidates)
    if #candidates < 2 then return candidates[1] end
    local here = F2T_MAP_CURRENT_ROOM_ID
    if here then
        for _, room_id in ipairs(candidates) do
            if room_id == here or getPath(here, room_id) then return room_id end
        end
    end
    return candidates[1]
end

function f2t_map_find_room_with_flag(area_id, flag)
    if not area_id then return nil end
    local flag_key = string.format("fed2_flag_%s", flag)
    local candidates = {}
    for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
        if getRoomUserData(room_id, flag_key) == "true" then
            candidates[#candidates + 1] = room_id
        end
    end
    return preferReachable(candidates)
end

-- The closest mapped room carrying `flag`, by walking steps, or nil when none
-- is reachable. Also returns the step count. Breadth-first from from_room,
-- stopping at the first match: a getPath per candidate stalls on flags found
-- all over the galaxy. same_area keeps the search on from_room's own area, so
-- a planet search can't leave through a link's jumps and find one elsewhere.
function f2t_map_nearest_room_with_flag(flag, from_room, same_area)
    from_room = from_room or F2T_MAP_CURRENT_ROOM_ID
    if not from_room or not roomExists(from_room) then return nil end
    local area_id = same_area and getRoomArea(from_room) or nil
    local targets = {}
    for _, room_id in ipairs(searchRoomUserData("fed2_flag_" .. flag, "true") or {}) do
        targets[tonumber(room_id)] = true
    end
    if next(targets) == nil then return nil end

    local queue, depths, head = { from_room }, { [from_room] = 0 }, 1
    while head <= #queue do
        local room_id = queue[head]
        head = head + 1
        local depth = depths[room_id]
        if targets[room_id] then return room_id, depth end
        local function visit(dest_id)
            if type(dest_id) == "number" and not depths[dest_id] and not roomLocked(dest_id)
                and (not area_id or getRoomArea(dest_id) == area_id) then
                depths[dest_id] = depth + 1
                queue[#queue + 1] = dest_id
            end
        end
        for direction, dest_id in pairs(getRoomExits(room_id) or {}) do
            if not hasExitLock(room_id, direction) then visit(dest_id) end
        end
        -- {[destRoomId] = {command = "1" when locked, "0" when not}}
        for dest_id, commands in pairs(getSpecialExits(room_id) or {}) do
            for _, locked in pairs(commands) do
                if locked ~= "1" then visit(dest_id) break end
            end
        end
    end
    return nil
end

-- Unlike f2t_map_find_room_with_flag, never falls back to an unreachable room.
function f2t_map_find_reachable_room_with_flag(area_id, flag, from_room)
    if not area_id or not from_room or not roomExists(from_room) then return nil end
    local flag_key = string.format("fed2_flag_%s", flag)
    for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
        if getRoomUserData(room_id, flag_key) == "true"
           and (room_id == from_room or getPath(from_room, room_id)) then
            return room_id
        end
    end
    return nil
end

-- The interstellar link room of an area. A system has exactly one server-side
-- (Galaxy::FindLink resolves a single link per star), but a map can hold more
-- than one room flagged "link" for it - a stale duplicate from an earlier
-- import, or a room whose flag was never cleared - and picking the wrong one
-- points every "jump <system>" exit at a room the game never puts you in.
-- Prefer whichever GMCP last confirmed us standing in: apply_gmcp_jumps
-- stamps fed2_jump_synced_at on arrival, so the freshest stamp is the room
-- the game actually uses.
function f2t_map_find_link_room(area_id)
    if not area_id then return nil end
    local best, best_stamp = nil, nil
    for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
        if getRoomUserData(room_id, "fed2_flag_link") == "true" then
            local stamp = tonumber(getRoomUserData(room_id, "fed2_jump_synced_at"))
            if not best or (stamp and (not best_stamp or stamp > best_stamp)) then
                best, best_stamp = room_id, stamp
            end
        end
    end
    return best
end

-- The room in a system's space area that orbits a given planet, which is
-- where its "board" link down to the surface hangs off.
function f2t_map_find_orbit_room(space_area_name, planet_name)
    local space_area_id = space_area_name and f2t_map_get_area_id(space_area_name)
    if not space_area_id or not planet_name then return nil end
    local candidates = {}
    for _, room_id in ipairs(f2t_map_area_room_list(space_area_id)) do
        local planet = getRoomUserData(room_id, "fed2_planet")
        if planet and string.lower(planet) == string.lower(planet_name) then
            candidates[#candidates + 1] = room_id
        end
    end
    return preferReachable(candidates)
end

-- A planet's shuttlepad. The room the orbit's "board" exit leads to is that
-- room by definition, so prefer it over a flag search: a map can carry an
-- older, orphaned shuttlepad room for the same planet (an import whose room
-- numbers no longer match, say) that nothing connects to, and a flag search
-- has no way to tell the two apart.
function f2t_map_find_shuttlepad_room(planet_name)
    local planet_area_id = f2t_map_get_area_id(planet_name)
    if not planet_area_id then return nil end

    local planet = f2t_map_lookup_planet(planet_name)
    local space_area_name = planet and planet.system
        and f2t_map_get_system_space_area_actual(planet.system)
    local orbit_room = f2t_map_find_orbit_room(space_area_name, planet_name)
    if orbit_room then
        -- getSpecialExits() is {[destRoomId] = {command = true, ...}}, but the
        -- value shape has varied across Mudlet versions, so check it.
        for dest_room_id, commands in pairs(getSpecialExits(orbit_room) or {}) do
            if type(commands) == "table" and roomExists(dest_room_id)
                and getRoomArea(dest_room_id) == planet_area_id then
                for command in pairs(commands) do
                    if type(command) == "string" and string.lower(command) == "board" then
                        return dest_room_id
                    end
                end
            end
        end
    end

    return preferReachable(f2t_map_find_all_rooms_with_flag(planet_area_id, "shuttlepad"))
end

function f2t_map_find_all_rooms_with_flag(area_id, flag)
    if not area_id or not flag then return {} end
    local results = {}
    local flag_key = string.format("fed2_flag_%s", flag)
    for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
        if getRoomUserData(room_id, flag_key) == "true" then
            table.insert(results, room_id)
        end
    end
    return results
end

function f2t_map_ensure_current_location(callback_fn, callback_args)
    if F2T_MAP_CURRENT_ROOM_ID and roomExists(F2T_MAP_CURRENT_ROOM_ID) then
        return true
    end
    cecho("\n<yellow>[map]<reset> Current location unknown - sending 'look' to update...\n")
    send("look")
    if callback_fn then
        tempTimer(0.5, function()
            if callback_args then
                callback_fn(table.unpack(callback_args))
            else
                callback_fn()
            end
        end)
    end
    return false
end

function f2t_map_room_has_flag(room_id, flag)
    if not room_id or not flag then return false end
    return getRoomUserData(room_id, string.format("fed2_flag_%s", flag)) == "true"
end

-- Room flags a destination string may name, and the shorthands for them.
-- Module scope because the destination grammar ("<place> <flag>") is parsed
-- outside the resolver too - see describe() in nav_api.lua.
F2T_MAP_KNOWN_FLAGS = {
    shuttlepad=true, exchange=true, bar=true, courier=true, link=true,
    orbit=true, weapons=true, repair=true, shipyard=true, hospital=true, insure=true,
}
F2T_MAP_FLAG_SHORTCUTS = {ex="exchange", sp="shuttlepad", ac="courier"}

-- The canonical flag a word names, or nil when it names no flag at all.
function f2t_map_canonical_flag(word)
    if not word or word == "" then return nil end
    word = string.lower(word)
    if F2T_MAP_FLAG_SHORTCUTS[word] then return F2T_MAP_FLAG_SHORTCUTS[word] end
    return F2T_MAP_KNOWN_FLAGS[word] and word or nil
end

-- Split a destination into its place part and the flag it asks for, when it
-- has one: "mars exchange" -> "mars", "exchange". A bare flag word is all
-- flag and no place.
function f2t_map_split_place_and_flag(location)
    if not location or location == "" then return nil, nil end
    local words = {}
    for word in string.gmatch(location, "%S+") do table.insert(words, word) end
    if #words == 0 then return nil, nil end
    local flag = f2t_map_canonical_flag(words[#words])
    if not flag then return location, nil end
    if #words == 1 then return nil, flag end
    table.remove(words, #words)
    return table.concat(words, " "), flag
end

function f2t_map_resolve_location(location)
    if not location or location == "" then
        return nil, "No location specified"
    end

    local original_arg = location
    local arg = string.lower(location)
    local target_id = nil

    local KNOWN_FLAGS = F2T_MAP_KNOWN_FLAGS
    local FLAG_SHORTCUTS = F2T_MAP_FLAG_SHORTCUTS

    -- Saved destination
    local dest_hash = f2t_map_destination_get(arg)
    if dest_hash then
        target_id = f2t_map_get_room_by_hash(dest_hash)
        if target_id then return target_id, nil end
        return nil, string.format("Destination '%s' points to unmapped room (%s)", arg, dest_hash)
    end

    -- Mudlet room ID
    local room_num = tonumber(arg)
    if room_num then
        if not roomExists(room_num) then
            return nil, string.format("Room %d does not exist in the map", room_num)
        end
        return room_num, nil
    end

    -- Fed2 hash
    if string.match(arg, "^[^%.]+%.[^%.]+%.%d+$") then
        target_id = f2t_map_get_room_by_hash(original_arg)
        if not target_id then
            return nil, string.format("Room with hash '%s' not found", original_arg)
        end
        return target_id, nil
    end

    -- Area flag format
    if string.match(arg, "%s") then
        local words = {}
        for word in string.gmatch(arg, "%S+") do table.insert(words, word) end
        local last_word = words[#words]
        local is_area_flag_format = KNOWN_FLAGS[last_word] or FLAG_SHORTCUTS[last_word]

        if is_area_flag_format and #words >= 2 then
            local flag = last_word
            if FLAG_SHORTCUTS[flag] then flag = FLAG_SHORTCUTS[flag] end
            table.remove(words, #words)
            local area_name = table.concat(words, " ")
            local search_area_name = area_name

            if flag == "orbit" then
                local planet_data = f2t_map_lookup_planet(area_name)
                if planet_data and planet_data.system then
                    search_area_name = f2t_map_get_system_space_area_actual(planet_data.system)
                    if not search_area_name then
                        return nil, string.format("System space for planet '%s' not found", area_name)
                    end
                end
            end

            if flag == "link" then
                local space_area = f2t_map_get_system_space_area_actual(area_name)
                if space_area then search_area_name = space_area end
            end

            local area_id = f2t_map_get_area_id(search_area_name)
            if not area_id then
                local err_msg = string.format(
                    "'%s' not found - area may not exist or hasn't been explored yet", area_name)
                -- A planet sweep has to start from a mapped room on that planet,
                -- so a planet with no area yet needs its system found first.
                if flag ~= "link" then
                    return nil, err_msg
                end
                return nil, err_msg
            end

            local area_rooms = f2t_map_area_room_list(area_id)
            if #area_rooms == 0 then
                return nil,
                    string.format("No rooms found in '%s' - try 'map explore %s'", search_area_name, area_name)
            end

            local flag_key = string.format("fed2_flag_%s", flag)
            local matching_rooms = {}

            if flag == "orbit" then
                for _, room_id in ipairs(area_rooms) do
                    local room_planet = getRoomUserData(room_id, "fed2_planet")
                    if room_planet and string.lower(room_planet) == string.lower(area_name) then
                        table.insert(matching_rooms, room_id)
                    end
                end
            else
                for _, room_id in ipairs(area_rooms) do
                    if getRoomUserData(room_id, flag_key) == "true" then
                        table.insert(matching_rooms, room_id)
                    end
                end
            end

            if #matching_rooms == 0 then
                if flag == "orbit" then
                    return nil, string.format(
                        "No orbit mapped for '%s' - try 'map explore %s' to discover it", area_name, area_name)
                else
                    return nil, string.format(
                        "No %s found in '%s' - try 'map explore %s' to discover one",
                        flag, search_area_name, area_name)
                end
            end

            target_id = matching_rooms[1]
            return target_id, nil
        end
    end

    -- Planet
    -- Planet before system, deliberately. Fed2 reuses names across planets,
    -- systems, cartels and syndicates, and most systems have a planet of the
    -- same name carrying their link - so a bare name almost always means that
    -- planet, and answering it with the Planet nav default is what the user
    -- meant. Anything that specifically wants the system says so with a flag
    -- ("<name> link"), which the area-flag branch above already handles.
    local single_arg = arg
    if FLAG_SHORTCUTS[single_arg] then single_arg = FLAG_SHORTCUTS[single_arg] end
    local planet_data = f2t_map_lookup_planet(single_arg)
    if planet_data then
        local system_name = planet_data.system
        local planet_dest = f2t_map_planet_nav_default()

        if planet_dest == "orbit" then
            if not system_name then
                return nil, string.format("Cannot determine system for planet '%s'", single_arg)
            end
            local space_area_name = f2t_map_get_system_space_area_actual(system_name)
            if not space_area_name then
                return nil, string.format("'%s' system space not in your map - fly there to add it", single_arg)
            end
            local space_area_id = f2t_map_get_area_id(space_area_name)
            if not space_area_id then
                return nil, string.format("'%s' system space not in your map - fly there to add it", single_arg)
            end
            for _, room_id in ipairs(f2t_map_area_room_list(space_area_id)) do
                local room_planet = getRoomUserData(room_id, "fed2_planet")
                if room_planet and string.lower(room_planet) == string.lower(single_arg) then
                    target_id = room_id; break
                end
            end
            if target_id then return target_id, nil end
            return nil, string.format(
                "No orbit mapped for '%s' - try 'map explore %s' to discover it", single_arg, system_name)

        elseif planet_dest == "exchange" then
            local planet_area_id = f2t_map_get_area_id(single_arg)
            if planet_area_id then
                target_id = f2t_map_find_room_with_flag(planet_area_id, "exchange")
                if target_id then return target_id, nil end
                local err_msg = string.format(
                    "No exchange mapped on '%s' - try 'map explore %s' to discover one", single_arg, single_arg)
                return nil, err_msg
            end
            return nil, string.format("Planet '%s' is not in your map yet - explore it first", single_arg)

        else
            local planet_area_id = f2t_map_get_area_id(single_arg)
            if planet_area_id then
                target_id = f2t_map_find_shuttlepad_room(single_arg)
                if target_id then return target_id, nil end
                local err_msg = string.format(
                    "No shuttlepad mapped on '%s' - try 'map explore %s' to discover one", single_arg, single_arg)
                return nil, err_msg
            end
            return nil, string.format("Planet '%s' is not in your map yet - explore it first", single_arg)
        end
    end

    -- System
    local space_area = f2t_map_get_system_space_area_actual(single_arg)
    if space_area then
        local space_area_id = f2t_map_get_area_id(space_area)
        target_id = f2t_map_find_link_room(space_area_id)
        if target_id then return target_id, nil end
        return nil, string.format("No link room mapped in '%s'", space_area)
    end

    -- Flag in current area
    if not F2T_MAP_CURRENT_ROOM_ID then return nil, "Current location unknown" end
    local current_area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
    if not current_area_id then return nil, "Cannot determine current area" end

    local area_name = f2t_map_get_area_name(current_area_id)
    local search_area_id = current_area_id
    local search_area_name = area_name

    if single_arg == "link" then
        local current_system   = gmcp.room and gmcp.room.info and gmcp.room.info.system
        local current_area_name = gmcp.room and gmcp.room.info and gmcp.room.info.area
        if current_system and current_area_name and not string.match(current_area_name, "Space$") then
            local sa = f2t_map_get_system_space_area_actual(current_system)
            if sa then
                local sai = f2t_map_get_area_id(sa)
                if sai then search_area_id = sai; search_area_name = sa end
            end
        end
    end

    local area_rooms = f2t_map_area_room_list(search_area_id)
    if #area_rooms == 0 then
        if KNOWN_FLAGS[single_arg] then
            return nil, string.format("No %s found here - try 'map explore' to discover one", single_arg)
        end
        return nil, string.format("No rooms found in area '%s'", search_area_name or "unknown")
    end

    local flag_key = string.format("fed2_flag_%s", single_arg)
    local matching_rooms = {}
    for _, room_id in ipairs(area_rooms) do
        if getRoomUserData(room_id, flag_key) == "true" then
            table.insert(matching_rooms, room_id)
        end
    end

    if #matching_rooms == 0 then
        -- A bare flag word ("exchange") means one in the current area
        if KNOWN_FLAGS[single_arg] then
            local area_display =
                (search_area_name and search_area_name ~= "") and ("'" .. search_area_name .. "'") or "this area"
            return nil, string.format("No %s mapped in %s", single_arg, area_display)
        end
        return nil, string.format("'%s' isn't a mapped planet, system or room", location)
    end

    target_id = matching_rooms[1]
    return target_id, nil
end
