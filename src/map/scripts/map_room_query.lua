-- Room query functions for finding rooms by various criteria

-- Find a room with a specific flag in a specific area
-- Returns: room_id or nil
function f2t_map_find_room_with_flag(area_id, flag)
    if not area_id then
        return nil
    end

    local area_rooms = getAreaRooms(area_id)
    if not area_rooms then
        return nil
    end

    local flag_key = string.format("fed2_flag_%s", flag)

    -- Check [0] entry first (Mudlet can use 0-indexed tables)
    if area_rooms[0] then
        local has_flag = getRoomUserData(area_rooms[0], flag_key)
        if has_flag == "true" then
            return area_rooms[0]
        end
    end

    -- Check remaining entries
    for _, room_id in ipairs(area_rooms) do
        local has_flag = getRoomUserData(room_id, flag_key)
        if has_flag == "true" then
            return room_id
        end
    end

    return nil
end

-- Find all rooms with a specific flag in a specific area
-- Returns: array of room_ids
function f2t_map_find_all_rooms_with_flag(area_id, flag)
    if not area_id then
        f2t_debug_log("[map] ERROR: f2t_map_find_all_rooms_with_flag called with nil area_id")
        return {}
    end

    if not flag then
        f2t_debug_log("[map] ERROR: f2t_map_find_all_rooms_with_flag called with nil flag")
        return {}
    end

    local results = {}
    local room_ids = getAreaRooms(area_id)

    if not room_ids then
        return results
    end

    local flag_key = string.format("fed2_flag_%s", flag)

    for _, room_id in ipairs(room_ids) do
        local has_flag = getRoomUserData(room_id, flag_key)
        if has_flag == "true" then
            table.insert(results, room_id)
        end
    end

    f2t_debug_log("[map] Found %d room(s) with flag '%s' in area %d", #results, flag, area_id)
    return results
end

-- Ensure current location is known, with automatic retry if needed
-- Takes an optional callback function to execute after location is confirmed
-- Returns: true if location is known, false if retry was initiated
function f2t_map_ensure_current_location(callback_fn, callback_args)
    -- Check if current location is known
    if F2T_MAP_CURRENT_ROOM_ID and roomExists(F2T_MAP_CURRENT_ROOM_ID) then
        return true  -- Location is known
    end

    -- Location unknown - send 'look' and retry
    cecho("\n<yellow>[map]<reset> Current location unknown - sending 'look' to update...\n")
    f2t_debug_log("[map] Current room ID: %s, exists: %s",
        tostring(F2T_MAP_CURRENT_ROOM_ID),
        F2T_MAP_CURRENT_ROOM_ID and tostring(roomExists(F2T_MAP_CURRENT_ROOM_ID)) or "N/A")

    send("look")

    -- If callback provided, execute it after GMCP updates
    if callback_fn then
        tempTimer(0.5, function()
            f2t_debug_log("[map] Retrying after 'look' command")
            if callback_args then
                callback_fn(unpack(callback_args))
            else
                callback_fn()
            end
        end)
    end

    return false  -- Location was unknown, retry initiated
end

-- Check if a specific room has a specific flag
-- Returns: true if room has the flag, false otherwise
function f2t_map_room_has_flag(room_id, flag)
    if not room_id or not flag then
        return false
    end

    local flag_key = string.format("fed2_flag_%s", flag)
    local has_flag = getRoomUserData(room_id, flag_key)
    return has_flag == "true"
end

-- Room resolution for Federation 2 mapper
-- Extracts location parsing logic for reuse by navigation and route calculation
-- Resolve a location string to a Mudlet room ID
-- Returns: room_id (number) or nil, error_message (string)
function f2t_map_resolve_location(location)
    if not location or location == "" then
        return nil, "No location specified"
    end

    -- Store original location for case-sensitive operations (e.g., hashes)
    local original_arg = location

    -- Normalize input (case-insensitive) for most operations
    local arg = string.lower(location)
    local target_id = nil

    -- Known flags (for disambiguating "area flag" vs multi-word locations)
    local KNOWN_FLAGS = {
        shuttlepad = true,
        exchange   = true,
        bar        = true,
        courier    = true,
        link       = true,
        orbit      = true,
        weapons    = true,
        repair     = true,
        shipyard   = true,
        hospital   = true,
        insure     = true
    }

    -- Flag shortcuts
    local FLAG_SHORTCUTS = {
        ex = "exchange",
        sp = "shuttlepad",
        ac = "courier"
    }

    -- Try resolving as saved location first (before any other resolution)
    local dest_hash = f2t_map_destination_get(arg)
    if dest_hash then
        target_id = f2t_map_get_room_by_hash(dest_hash)
        if target_id then
            f2t_debug_log("[map] Resolved location '%s' -> hash %s -> room %d", arg, dest_hash, target_id)
            return target_id, nil
        else
            return nil, string.format("Destination '%s' points to unmapped room (%s)", arg, dest_hash)
        end
    end

    -- Try parsing as Mudlet room ID (pure number)
    local room_num = tonumber(arg)
    if room_num then
        if not roomExists(room_num) then
            return nil, string.format("Room %d does not exist in the map", room_num)
        end
        f2t_debug_log("[map] Resolved room ID %d", room_num)
        return room_num, nil
    end

    -- Try parsing as Fed2 hash (system.area.num)
    if string.match(arg, "^[^%.]+%.[^%.]+%.%d+$") then
        local hash = original_arg
        target_id = f2t_map_get_room_by_hash(hash)
        if not target_id then
            return nil, string.format("Room with hash '%s' not found", hash)
        end
        f2t_debug_log("[map] Resolved Fed2 hash %s -> room %d", hash, target_id)
        return target_id, nil
    end

    -- Try parsing as "area flag" (multiple words where last word is a known flag)
    if string.match(arg, "%s") then
        local words = {}
        for word in string.gmatch(arg, "%S+") do
            table.insert(words, word)
        end

        local last_word = words[#words]
        local is_area_flag_format = KNOWN_FLAGS[last_word] or FLAG_SHORTCUTS[last_word]

        if is_area_flag_format and #words >= 2 then
            local flag = last_word
            if FLAG_SHORTCUTS[flag] then
                flag = FLAG_SHORTCUTS[flag]
            end

            table.remove(words, #words)
            local area_name = table.concat(words, " ")

            -- Special handling for "orbit" flag
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

            -- Special handling for "link" flag
            -- Link rooms are in system space, not on planet surface
            if flag == "link" then
                local space_area = f2t_map_get_system_space_area_actual(area_name)
                if space_area then
                    search_area_name = space_area
                    f2t_debug_log("[map] Resolved link: system '%s' -> space area '%s'", area_name, search_area_name)
                end
            end

            local area_id = f2t_map_get_area_id(search_area_name)
            if not area_id then
                return nil, string.format("Area '%s' not found", search_area_name)
            end

            local area_rooms = getAreaRooms(area_id)
            if not area_rooms then
                return nil, string.format("No rooms found in area '%s'", search_area_name)
            end

            local flag_key = string.format("fed2_flag_%s", flag)
            local matching_rooms = {}

            if flag == "orbit" then
                if area_rooms[0] then
                    local room_planet = getRoomUserData(area_rooms[0], "fed2_planet")
                    if room_planet and string.lower(room_planet) == string.lower(area_name) then
                        table.insert(matching_rooms, area_rooms[0])
                    end
                end
                for _, room_id in ipairs(area_rooms) do
                    local room_planet = getRoomUserData(room_id, "fed2_planet")
                    if room_planet and string.lower(room_planet) == string.lower(area_name) then
                        table.insert(matching_rooms, room_id)
                    end
                end
            else
                if area_rooms[0] then
                    local has_flag = getRoomUserData(area_rooms[0], flag_key)
                    if has_flag == "true" then
                        table.insert(matching_rooms, area_rooms[0])
                    end
                end
                for _, room_id in ipairs(area_rooms) do
                    local has_flag = getRoomUserData(room_id, flag_key)
                    if has_flag == "true" then
                        table.insert(matching_rooms, room_id)
                    end
                end
            end

            if #matching_rooms == 0 then
                local search_desc = flag == "orbit" and string.format("orbit for planet '%s'", area_name) or string.format("flag '%s'", flag)
                return nil, string.format("No rooms with %s found in area '%s'", search_desc, search_area_name)
            end

            target_id = matching_rooms[1]
            f2t_debug_log("[map] Resolved area flag (%s %s) -> room %d", area_name, flag, target_id)
            return target_id, nil
        end
    end

    -- Try as planet first (use configured default location)
    local single_arg = arg
    if FLAG_SHORTCUTS[single_arg] then
        single_arg = FLAG_SHORTCUTS[single_arg]
    end

    local planet_data = f2t_map_lookup_planet(single_arg)
    if planet_data then
        local system_name = planet_data.system
        local planet_dest = F2T_MAP_PLANET_NAV_DEFAULT or "shuttlepad"

        if planet_dest == "orbit" then
            if not system_name then
                return nil, string.format("Cannot determine system for planet '%s'", single_arg)
            end

            local space_area_name = f2t_map_get_system_space_area_actual(system_name)
            if not space_area_name then
                return nil, string.format("System space for planet '%s' not found", single_arg)
            end

            local space_area_id = f2t_map_get_area_id(space_area_name)
            if not space_area_id then
                return nil, string.format("System space area '%s' not found", space_area_name)
            end

            local area_rooms = getAreaRooms(space_area_id)
            if area_rooms then
                if area_rooms[0] then
                    local room_planet = getRoomUserData(area_rooms[0], "fed2_planet")
                    if room_planet and string.lower(room_planet) == string.lower(single_arg) then
                        target_id = area_rooms[0]
                    end
                end
                if not target_id then
                    for _, room_id in ipairs(area_rooms) do
                        local room_planet = getRoomUserData(room_id, "fed2_planet")
                        if room_planet and string.lower(room_planet) == string.lower(single_arg) then
                            target_id = room_id
                            break
                        end
                    end
                end
            end

            if target_id then
                f2t_debug_log("[map] Resolved planet (%s) -> orbit room %d", single_arg, target_id)
                return target_id, nil
            else
                return nil, string.format("No orbit found for planet '%s'", single_arg)
            end
        else
            local planet_area_id = f2t_map_get_area_id(single_arg)
            if planet_area_id then
                target_id = f2t_map_find_room_with_flag(planet_area_id, "shuttlepad")
                if target_id then
                    f2t_debug_log("[map] Resolved planet (%s) -> shuttlepad room %d", single_arg, target_id)
                    return target_id, nil
                else
                    return nil, string.format("No shuttlepad found on planet '%s'", single_arg)
                end
            else
                return nil, string.format("Planet '%s' not yet mapped", single_arg)
            end
        end
    end

    -- Try as system (look for link in "{System} Space")
    local space_area = f2t_map_get_system_space_area_actual(single_arg)
    if space_area then
        local space_area_id = f2t_map_get_area_id(space_area)
        target_id = f2t_map_find_room_with_flag(space_area_id, "link")
        if target_id then
            f2t_debug_log("[map] Resolved system (%s) -> link room %d", single_arg, target_id)
            return target_id, nil
        else
            return nil, string.format("No link found in '%s'", space_area)
        end
    end

    -- Try as flag in current area
    if not F2T_MAP_CURRENT_ROOM_ID then
        return nil, "Current location unknown"
    end

    local current_area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
    if not current_area_id then
        return nil, "Cannot determine current area"
    end

    local area_name = f2t_map_get_area_name(current_area_id)
    local search_area_id = current_area_id
    local search_area_name = area_name

    -- Special "link" resolution: if on planet surface, resolve to system space
    if single_arg == "link" then
        local current_system = gmcp.room and gmcp.room.info and gmcp.room.info.system
        local current_area_name = gmcp.room and gmcp.room.info and gmcp.room.info.area

        if current_system and current_area_name and not string.match(current_area_name, "Space$") then
            local space_area = f2t_map_get_system_space_area_actual(current_system)
            if space_area then
                local space_area_id = f2t_map_get_area_id(space_area)
                if space_area_id then
                    search_area_id = space_area_id
                    search_area_name = space_area
                end
            end
        end
    end

    local area_rooms = getAreaRooms(search_area_id)
    if not area_rooms then
        return nil, string.format("No rooms found in area '%s'", search_area_name or "unknown")
    end

    local flag_key = string.format("fed2_flag_%s", single_arg)
    local matching_rooms = {}

    if area_rooms[0] then
        local has_flag = getRoomUserData(area_rooms[0], flag_key)
        if has_flag == "true" then
            table.insert(matching_rooms, area_rooms[0])
        end
    end
    for _, room_id in ipairs(area_rooms) do
        local has_flag = getRoomUserData(room_id, flag_key)
        if has_flag == "true" then
            table.insert(matching_rooms, room_id)
        end
    end

    if #matching_rooms == 0 then
        return nil, string.format("No rooms with flag '%s' found in area '%s'", single_arg, search_area_name or "unknown")
    end

    target_id = matching_rooms[1]
    f2t_debug_log("[map] Resolved flag in area (%s in %s) -> room %d", single_arg, search_area_name, target_id)
    return target_id, nil
end

f2t_debug_log("[map] Room query functions loaded")
