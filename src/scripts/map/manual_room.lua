-- f2ce-tools map — manual room management (ported from map_manual_room.lua)

function f2t_map_manual_create_room(system, area, num, name)
    if not system or system == "" then cecho("\n<red>[map]<reset> System name required\n"); return nil end
    if not area   or area   == "" then cecho("\n<red>[map]<reset> Area name required\n");   return nil end
    if not num or type(num) ~= "number" then cecho("\n<red>[map]<reset> Room number must be a number\n"); return nil end

    local hash = string.format("%s.%s.%d", system, area, num)
    local existing_id = getRoomIDbyHash(hash)
    if existing_id and existing_id > 0 then
        cecho(string.format("\n<yellow>[map]<reset> Room already exists: %s (ID: %d)\n", hash, existing_id))
        return existing_id
    end

    local area_id = f2t_map_get_or_create_area(area, {system = system})
    if not area_id then cecho(string.format("\n<red>[map]<reset> Failed to create area: %s\n", area)); return nil end

    local room_id = createRoomID()
    if not room_id then cecho("\n<red>[map]<reset> Failed to create room ID\n"); return nil end

    addRoom(room_id); setRoomArea(room_id, area_id)
    setRoomIDbyHash(room_id, hash)
    setRoomName(room_id, (name and name ~= "") and name or hash)

    local x = num % 64
    local y = -math.floor(num / 64)
    setRoomCoordinates(room_id, x, y, 0)
    setRoomUserData(room_id, "fed2_system", system)
    setRoomUserData(room_id, "fed2_area",   area)
    setRoomUserData(room_id, "fed2_num",    tostring(num))

    local afc = getRoomArea(room_id)
    if afc then
        local cartel = getAreaUserData(afc, "fed2_cartel")
        if cartel and cartel ~= "" then setRoomUserData(room_id, "fed2_cartel", cartel) end
    end

    cecho(string.format("\n<green>[map]<reset> Room created: <white>%s<reset> (ID: %d)\n", hash, room_id))
    cecho(string.format("  <dim_grey>Area: %s | Coords: (%d, %d, 0)<reset>\n", area, x, y))
    return room_id
end

function f2t_map_manual_delete_room(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    local room_name = getRoomName(room_id) or "unnamed"
    local hash = getRoomHashByID(room_id) or "unknown"
    f2t_map_manual_request_confirmation(
        string.format("delete room %d (%s)", room_id, room_name),
        function(data)
            if not roomExists(data.room_id) then
                cecho(string.format("\n<red>[map]<reset> Room %d no longer exists\n", data.room_id)); return
            end
            deleteRoom(data.room_id)
            cecho(string.format("\n<green>[map]<reset> Room deleted: <white>%d<reset> (%s)\n", data.room_id, data.room_name))
        end,
        {room_id = room_id, room_name = room_name, hash = hash}
    )
end

function f2t_map_manual_room_info(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    local name      = getRoomName(room_id)
    local hash      = getRoomHashByID(room_id)
    local area_id   = getRoomArea(room_id)
    local area_name = f2t_map_get_area_name(area_id)
    local x, y, z  = getRoomCoordinates(room_id)
    local char      = getRoomChar(room_id)
    local env       = getRoomEnv(room_id)
    local weight    = getRoomWeight(room_id)
    local exits     = getRoomExits(room_id)
    local special_exits = getSpecialExitsSwap(room_id)

    cecho(string.format("\n<green>[map]<reset> Room Information: <white>%d<reset>\n", room_id))
    cecho(string.format("  <yellow>Name:<reset> %s\n", name or "(none)"))
    cecho(string.format("  <yellow>Hash:<reset> %s\n", hash or "(none)"))
    cecho(string.format("  <yellow>Area:<reset> %s (ID: %d)\n", area_name or "(none)", area_id or 0))
    cecho(string.format("  <yellow>Coordinates:<reset> (%d, %d, %d)\n", x or 0, y or 0, z or 0))
    if char and char ~= "" then cecho(string.format("  <yellow>Symbol:<reset> %s\n", char)) end
    if env  and env  >= 0  then cecho(string.format("  <yellow>Environment:<reset> %d\n", env)) end
    if weight and weight ~= 1 then cecho(string.format("  <yellow>Weight:<reset> %d\n", weight)) end

    local fed2_system = getRoomUserData(room_id, "fed2_system")
    local fed2_area   = getRoomUserData(room_id, "fed2_area")
    local fed2_num    = getRoomUserData(room_id, "fed2_num")
    if fed2_system or fed2_area or fed2_num then
        cecho("\n  <dim_grey>Fed2 Metadata:<reset>\n")
        if fed2_system then cecho(string.format("    <dim_grey>System: %s<reset>\n", fed2_system)) end
        if fed2_area   then cecho(string.format("    <dim_grey>Area: %s<reset>\n",   fed2_area))   end
        if fed2_num    then cecho(string.format("    <dim_grey>Num: %s<reset>\n",    fed2_num))    end
    end
    if exits and next(exits) ~= nil then
        cecho("\n  <yellow>Standard Exits:<reset>\n")
        for dir, dest_id in pairs(exits) do
            cecho(string.format("    <cyan>%s<reset> -> %s (ID: %d)\n", dir, getRoomName(dest_id) or "unnamed", dest_id))
        end
    end
    if special_exits and next(special_exits) ~= nil then
        cecho("\n  <yellow>Special Exits:<reset>\n")
        for dest_id, command in pairs(special_exits) do
            cecho(string.format("    <magenta>%s<reset> -> %s (ID: %d)\n", command, getRoomName(dest_id) or "unnamed", dest_id))
        end
    end
    local room_locked = roomLocked(room_id)
    cecho("\n  <yellow>Lock Status:<reset>\n")
    if room_locked then
        cecho("    <red>Room is LOCKED<reset>\n")
        local death_date = getRoomUserData(room_id, "f2t_death_date")
        if death_date and death_date ~= "" then
            cecho(string.format("    <red>Death Location<reset>: %s\n", death_date))
        end
    else
        cecho("    <green>Room is UNLOCKED<reset>\n")
    end
    cecho("\n")
end

function f2t_map_manual_set_room_name(room_id, name)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not name or name == "" then cecho("\n<red>[map]<reset> Name cannot be empty\n"); return false end
    setRoomName(room_id, name)
    cecho(string.format("\n<green>[map]<reset> Room %d name set to: <white>%s<reset>\n", room_id, name))
    return true
end

function f2t_map_manual_set_room_area(room_id, area_name)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not area_name or area_name == "" then cecho("\n<red>[map]<reset> Area name cannot be empty\n"); return false end
    local area_id = f2t_map_get_or_create_area(area_name)
    if not area_id then cecho(string.format("\n<red>[map]<reset> Failed to create area: %s\n", area_name)); return false end
    setRoomArea(room_id, area_id)
    cecho(string.format("\n<green>[map]<reset> Room %d moved to area: <white>%s<reset> (ID: %d)\n", room_id, area_name, area_id))
    return true
end

function f2t_map_manual_set_room_coords(room_id, x, y, z)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not x or not y or not z then cecho("\n<red>[map]<reset> Coordinates must be numbers (x, y, z)\n"); return false end
    setRoomCoordinates(room_id, x, y, z)
    cecho(string.format("\n<green>[map]<reset> Room %d coordinates set to: <white>(%d, %d, %d)<reset>\n", room_id, x, y, z))
    return true
end

function f2t_map_manual_set_room_symbol(room_id, symbol)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not symbol or symbol == "" then cecho("\n<red>[map]<reset> Symbol cannot be empty\n"); return false end
    if string.len(symbol) > 1 then cecho("\n<red>[map]<reset> Symbol must be exactly 1 character\n"); return false end
    setRoomChar(room_id, symbol)
    cecho(string.format("\n<green>[map]<reset> Room %d symbol set to: <white>%s<reset>\n", room_id, symbol))
    return true
end

function f2t_map_manual_set_room_color(room_id, r, g, b)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not r or not g or not b then cecho("\n<red>[map]<reset> Color must be RGB values (0-255)\n"); return false end
    if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then
        cecho("\n<red>[map]<reset> RGB values must be between 0 and 255\n"); return false
    end
    setRoomBackgroundColor(room_id, r, g, b)
    cecho(string.format("\n<green>[map]<reset> Room %d color set to: <white>RGB(%d, %d, %d)<reset>\n", room_id, r, g, b))
    return true
end

function f2t_map_manual_set_room_env(room_id, env_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not env_id or type(env_id) ~= "number" then cecho("\n<red>[map]<reset> Environment ID must be a number\n"); return false end
    setRoomEnv(room_id, env_id)
    cecho(string.format("\n<green>[map]<reset> Room %d environment set to: <white>%d<reset>\n", room_id, env_id))
    return true
end

function f2t_map_manual_set_room_weight(room_id, weight)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not weight or type(weight) ~= "number" then cecho("\n<red>[map]<reset> Weight must be a number\n"); return false end
    if weight < 1 then cecho("\n<red>[map]<reset> Weight must be >= 1\n"); return false end
    setRoomWeight(room_id, weight)
    cecho(string.format("\n<green>[map]<reset> Room %d weight set to: <white>%d<reset>\n", room_id, weight))
    return true
end
