-- f2ce-tools map — room creation and management (ported from map_room.lua)

function f2t_map_generate_hash(room_data)
    if not room_data then return nil end
    local system, area, num = room_data.system, room_data.area, room_data.num
    if not system or not area or not num then return nil end
    return string.format("%s.%s.%d", system, area, num)
end

function f2t_map_generate_hash_from_room(room_id)
    if not room_id or not roomExists(room_id) then return nil end
    local system  = getRoomUserData(room_id, "fed2_system")
    local area    = getRoomUserData(room_id, "fed2_area")
    local num_str = getRoomUserData(room_id, "fed2_num")
    if not system or system == "" or not area or area == "" or not num_str or num_str == "" then
        return nil
    end
    local num = tonumber(num_str)
    if not num then return nil end
    return string.format("%s.%s.%d", system, area, num)
end

function f2t_map_get_room_by_hash(hash)
    if not hash then return nil end
    local room_id = getRoomIDbyHash(hash)
    if room_id and room_id > 0 then return room_id end
    return nil
end

function f2t_map_create_room(room_data, area_id)
    if not room_data or not area_id then return nil end
    local hash = f2t_map_generate_hash(room_data)
    if not hash then return nil end
    local existing_id = f2t_map_get_room_by_hash(hash)
    if existing_id then return existing_id end

    local room_id = createRoomID()
    if not room_id then return nil end
    addRoom(room_id)
    setRoomArea(room_id, area_id)
    setRoomIDbyHash(room_id, hash)
    if room_data.name then
        setRoomName(room_id, f2t_clean_room_name(room_data.name))
    end
    f2t_debug_log("[map] Room created: %s -> ID %d (area: %d)", hash, room_id, area_id)
    f2t_map_store_room_metadata(room_id, room_data)
    return room_id
end

function f2t_map_store_room_metadata(room_id, room_data)
    if not room_id or not roomExists(room_id) or not room_data then return false end

    if room_data.system  then setRoomUserData(room_id, "fed2_system",  room_data.system) end
    if room_data.cartel  then setRoomUserData(room_id, "fed2_cartel",  room_data.cartel) end
    if room_data.area    then setRoomUserData(room_id, "fed2_area",    room_data.area)   end
    if room_data.num     then setRoomUserData(room_id, "fed2_num",     tostring(room_data.num)) end

    -- Keep the area's cartel current too: systems change cartels, and the
    -- cartel-scoped route BFS and topology bootstrap read area userdata.
    if room_data.cartel then
        local area_id = getRoomArea(room_id)
        if area_id and getAreaUserData(area_id, "fed2_cartel") ~= room_data.cartel then
            setAreaUserData(area_id, "fed2_cartel", room_data.cartel)
        end
    end

    if room_data.flags then
        for _, flag in ipairs(room_data.flags) do
            setRoomUserData(room_id, string.format("fed2_flag_%s", flag), "true")
        end
    end

    -- Fallback: set orbit flag from orbit field
    if room_data.orbit then
        if getRoomUserData(room_id, "fed2_flag_orbit") ~= "true" then
            setRoomUserData(room_id, "fed2_flag_orbit", "true")
        end
    end

    -- Fallback: set space flag from area name
    if room_data.area and string.match(room_data.area, " Space$") then
        if getRoomUserData(room_id, "fed2_flag_space") ~= "true" then
            setRoomUserData(room_id, "fed2_flag_space", "true")
        end
    end

    -- Store exits for stub connection
    if room_data.exits then
        local exit_parts = {}
        for direction, fed2_num in pairs(room_data.exits) do
            table.insert(exit_parts, string.format("%s:%d", direction, fed2_num))
        end
        setRoomUserData(room_id, "fed2_exits", table.concat(exit_parts, ","))
    end

    -- Store planet name
    if room_data.orbit then
        local parts = {}
        for part in string.gmatch(room_data.orbit, "[^.]+") do table.insert(parts, part) end
        if #parts == 3 then setRoomUserData(room_id, "fed2_planet", parts[2]) end
    elseif room_data.area and not string.match(room_data.area, " Space$") then
        setRoomUserData(room_id, "fed2_planet", room_data.area)
    end

    return true
end

function f2t_map_update_room(room_id, room_data)
    if not room_id or not roomExists(room_id) or not room_data then return false end

    if room_data.name then
        local clean_name = f2t_clean_room_name(room_data.name)
        if getRoomName(room_id) ~= clean_name then
            setRoomName(room_id, clean_name)
        end
    end

    f2t_map_store_room_metadata(room_id, room_data)
    f2t_map_update_room_style(room_id)

    if room_data.num then
        local x, y, z = getRoomCoordinates(room_id)
        if not x or not y or not z or (x == 0 and y == 0 and z == 0) then
            local new_x, new_y, new_z = f2t_map_calculate_coords_from_room_num(room_data.num)
            f2t_map_set_room_coords(room_id, new_x, new_y, new_z)
        end
    end

    return true
end
