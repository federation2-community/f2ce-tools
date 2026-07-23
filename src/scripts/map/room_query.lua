-- f2ce-tools map — room query utilities (ported from map_room_query.lua)

function f2t_map_find_room_with_flag(area_id, flag)
    if not area_id then return nil end
    local area_rooms = getAreaRooms(area_id)
    if not area_rooms then return nil end
    local flag_key = string.format("fed2_flag_%s", flag)
    if area_rooms[0] and getRoomUserData(area_rooms[0], flag_key) == "true" then
        return area_rooms[0]
    end
    for _, room_id in ipairs(area_rooms) do
        if getRoomUserData(room_id, flag_key) == "true" then return room_id end
    end
    return nil
end

function f2t_map_find_all_rooms_with_flag(area_id, flag)
    if not area_id or not flag then return {} end
    local results = {}
    local room_ids = getAreaRooms(area_id)
    if not room_ids then return results end
    local flag_key = string.format("fed2_flag_%s", flag)
    for _, room_id in ipairs(room_ids) do
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

function f2t_map_resolve_location(location)
    if not location or location == "" then
        return nil, "No location specified"
    end

    local original_arg = location
    local arg = string.lower(location)
    local target_id = nil

    local KNOWN_FLAGS = {
        shuttlepad=true, exchange=true, bar=true, courier=true, link=true,
        orbit=true, weapons=true, repair=true, shipyard=true, hospital=true, insure=true,
    }
    local FLAG_SHORTCUTS = {ex="exchange", sp="shuttlepad", ac="courier"}

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
                return nil, string.format("'%s' not found - area may not exist or hasn't been explored yet", area_name)
            end

            local area_rooms = getAreaRooms(area_id)
            if not area_rooms then
                return nil, string.format("No rooms found in '%s' - try 'map explore %s'", search_area_name, area_name)
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
                if area_rooms[0] and getRoomUserData(area_rooms[0], flag_key) == "true" then
                    table.insert(matching_rooms, area_rooms[0])
                end
                for _, room_id in ipairs(area_rooms) do
                    if getRoomUserData(room_id, flag_key) == "true" then
                        table.insert(matching_rooms, room_id)
                    end
                end
            end

            if #matching_rooms == 0 then
                if flag == "orbit" then
                    return nil, string.format("No orbit mapped for '%s' - try 'map explore %s' to discover it", area_name, area_name)
                else
                    return nil, string.format("No %s found in '%s' - try 'map explore %s' to discover one", flag, search_area_name, area_name)
                end
            end

            target_id = matching_rooms[1]
            return target_id, nil
        end
    end

    -- Planet
    local single_arg = arg
    if FLAG_SHORTCUTS[single_arg] then single_arg = FLAG_SHORTCUTS[single_arg] end
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
                return nil, string.format("'%s' system space not in your map - fly there to add it", single_arg)
            end
            local space_area_id = f2t_map_get_area_id(space_area_name)
            if not space_area_id then
                return nil, string.format("'%s' system space not in your map - fly there to add it", single_arg)
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
                            target_id = room_id; break
                        end
                    end
                end
            end
            if target_id then return target_id, nil end
            return nil, string.format("No orbit mapped for '%s' - try 'map explore %s' to discover it", single_arg, system_name)

        elseif planet_dest == "exchange" then
            local planet_area_id = f2t_map_get_area_id(single_arg)
            if planet_area_id then
                target_id = f2t_map_find_room_with_flag(planet_area_id, "exchange")
                if target_id then return target_id, nil end
                return nil, string.format("No exchange mapped on '%s' - try 'map explore %s' to discover one", single_arg, single_arg)
            end
            return nil, string.format("Planet '%s' is not in your map yet - explore it first", single_arg)

        else
            local planet_area_id = f2t_map_get_area_id(single_arg)
            if planet_area_id then
                target_id = f2t_map_find_room_with_flag(planet_area_id, "shuttlepad")
                if target_id then return target_id, nil end
                return nil, string.format("No shuttlepad mapped on '%s' - try 'map explore %s' to discover one", single_arg, single_arg)
            end
            return nil, string.format("Planet '%s' is not in your map yet - explore it first", single_arg)
        end
    end

    -- System
    local space_area = f2t_map_get_system_space_area_actual(single_arg)
    if space_area then
        local space_area_id = f2t_map_get_area_id(space_area)
        target_id = f2t_map_find_room_with_flag(space_area_id, "link")
        if target_id then return target_id, nil end
        return nil, string.format("No link room mapped in '%s' - try 'map explore %s' to discover it", space_area, single_arg)
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

    local area_rooms = getAreaRooms(search_area_id)
    if not area_rooms then
        if KNOWN_FLAGS[single_arg] then
            return nil, string.format("No %s found here - try 'map explore' to discover one", single_arg)
        end
        return nil, string.format("No rooms found in area '%s'", search_area_name or "unknown")
    end

    local flag_key = string.format("fed2_flag_%s", single_arg)
    local matching_rooms = {}
    if area_rooms[0] and getRoomUserData(area_rooms[0], flag_key) == "true" then
        table.insert(matching_rooms, area_rooms[0])
    end
    for _, room_id in ipairs(area_rooms) do
        if getRoomUserData(room_id, flag_key) == "true" then
            table.insert(matching_rooms, room_id)
        end
    end

    if #matching_rooms == 0 then
        if string.find(single_arg, " ", 1, true) then
            return nil, string.format(
                "'%s' not found in your map - may be a real location you haven't explored yet, or an invalid destination/flag\nUse: nav <area> <flag>   valid flags: exchange, courier (ac), shuttlepad, bar, hospital, insure, repair, shipyard, weapons, link, orbit\nIf this is a real location, explore there manually first to add it to your map",
                location)
        elseif KNOWN_FLAGS[single_arg] then
            local area_display = (search_area_name and search_area_name ~= "") and ("'" .. search_area_name .. "'") or "this area"
            return nil, string.format("No %s found in %s - try 'map explore' to discover one", single_arg, area_display)
        else
            return nil, string.format(
                "'%s' not found - not a mapped planet, system, or navigation flag\nIf this is a real location, explore there manually first to add it to your map",
                location)
        end
    end

    target_id = matching_rooms[1]
    return target_id, nil
end
