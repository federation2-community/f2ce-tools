-- f2ce-tools map — lock management (ported from map_manual_lock.lua)

function f2t_map_manual_lock_room(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if roomLocked(room_id) then
        cecho(string.format("\n<yellow>[map]<reset> Room %d is already locked\n", room_id)); return true
    end
    lockRoom(room_id, true)
    f2t_map_apply_locked_room_style(room_id)
    local room_name = getRoomName(room_id) or "unnamed"
    local hash = getRoomHashByID(room_id) or "unknown"
    cecho(string.format("\n<green>[map]<reset> Room locked: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    cecho(string.format("  <dim_grey>Hash: %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this room<reset>\n")
    return true
end

function f2t_map_manual_unlock_room(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not roomLocked(room_id) then
        cecho(string.format("\n<yellow>[map]<reset> Room %d is not locked\n", room_id)); return true
    end
    lockRoom(room_id, false)
    setRoomUserData(room_id, "f2t_death_date", "")
    setRoomUserData(room_id, "f2t_danger", "")
    setRoomUserData(room_id, "f2t_locked_reason", "")
    f2t_map_update_room_style(room_id)
    cecho(string.format("\n<green>[map]<reset> Room unlocked: <white>%s<reset> (ID: %d)\n",
        getRoomName(room_id) or "unnamed", room_id))
    return true
end

function f2t_map_manual_lock_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end
    direction = string.lower(direction)
    local dir_expand = {n="north",s="south",e="east",w="west",ne="northeast",nw="northwest",se="southeast",sw="southwest",u="up",d="down"}
    direction = dir_expand[direction] or direction

    local exits = getRoomExits(room_id)
    if exits and exits[direction] then
        if hasExitLock(room_id, direction) then
            cecho(string.format("\n<yellow>[map]<reset> Exit '%s' in room %d is already locked\n", direction, room_id)); return true
        end
        lockExit(room_id, direction, true)
        local room_name = getRoomName(room_id) or "unnamed"
        local dest_name = getRoomName(exits[direction]) or "unnamed"
        cecho(string.format("\n<green>[map]<reset> Exit locked: <white>%s<reset> --%s--> <white>%s<reset>\n", room_name, direction, dest_name))
        cecho("  <red>Navigation will avoid this exit<reset>\n")
        return true
    end

    local dir_num = f2t_map_direction_to_number(direction)
    if not dir_num then
        cecho(string.format("\n<red>[map]<reset> Unknown direction: %s\n", direction)); return false
    end

    local has_stub = false
    local stubs = getExitStubs(room_id)
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == dir_num then has_stub = true; break end
    end

    local gmcp_fed2_num = nil
    if room_id == F2T_MAP_CURRENT_ROOM_ID and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.exits then
        local abbrev = f2t_map_normalize_direction(direction)
        gmcp_fed2_num = gmcp.room.info.exits[direction] or gmcp.room.info.exits[abbrev]
    end

    if not has_stub and not gmcp_fed2_num then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id)); return false
    end
    if not gmcp_fed2_num then
        cecho(string.format("\n<yellow>[map]<reset> Exit '%s' is a stub — destination unknown\n", direction))
        cecho("\n<dim_grey>Must be standing in this room with GMCP to lock an undiscovered exit.\n")
        return false
    end

    local system = getRoomUserData(room_id, "fed2_system") or (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.system)
    local area   = getRoomUserData(room_id, "fed2_area")   or (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.area)
    if not system or not area then
        cecho("\n<red>[map]<reset> Cannot determine system/area to create placeholder room\n"); return false
    end

    local hash = string.format("%s.%s.%d", system, area, gmcp_fed2_num)
    local dest_room_id = getRoomIDbyHash(hash)
    if dest_room_id and dest_room_id > 0 then
        -- placeholder already exists
    else
        local area_id = getRoomArea(room_id)
        if not area_id or area_id <= 0 then
            cecho("\n<red>[map]<reset> Cannot determine area ID to create placeholder room\n"); return false
        end
        dest_room_id = createRoomID()
        if not addRoom(dest_room_id) then
            cecho(string.format("\n<red>[map]<reset> Failed to create placeholder room (ID: %d)\n", dest_room_id)); return false
        end
        setRoomArea(dest_room_id, area_id)
        setRoomIDbyHash(dest_room_id, hash)
        setRoomName(dest_room_id, string.format("[Locked] %s.%d", area, gmcp_fed2_num))
        local x, y, z = f2t_map_calculate_coords_from_room_num(gmcp_fed2_num)
        setRoomCoordinates(dest_room_id, x, y, z)
        setRoomUserData(dest_room_id, "fed2_system", system)
        setRoomUserData(dest_room_id, "fed2_area",   area)
        setRoomUserData(dest_room_id, "fed2_num",    tostring(gmcp_fed2_num))
    end

    if has_stub then setExitStub(room_id, dir_num, false) end
    local exit_created = setExit(room_id, dest_room_id, dir_num)
    if not exit_created then
        if has_stub then setExitStub(room_id, dir_num, true) end
        cecho(string.format("\n<red>[map]<reset> Failed to connect exit to placeholder room %d\n", dest_room_id)); return false
    end
    lockExit(room_id, direction, true)
    lockRoom(dest_room_id, true)
    f2t_map_apply_locked_room_style(dest_room_id)

    local room_name = getRoomName(room_id) or "unnamed"
    local dest_name = getRoomName(dest_room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Exit locked: <white>%s<reset> --%s--> <white>%s<reset>\n", room_name, direction, dest_name))
    cecho(string.format("  <yellow>Locked placeholder created for undiscovered room %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this exit<reset>\n")
    updateMap()
    return true
end

function f2t_map_manual_death_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end
    direction = string.lower(direction)
    local dir_expand = {n="north",s="south",e="east",w="west",ne="northeast",nw="northwest",se="southeast",sw="southwest",u="up",d="down"}
    direction = dir_expand[direction] or direction

    local exits = getRoomExits(room_id)
    if exits and exits[direction] then
        local dest_room = exits[direction]
        lockExit(room_id, direction, true)
        lockRoom(dest_room, true)
        setRoomUserData(dest_room, "f2t_danger", "true")
        f2t_map_apply_death_room_style(dest_room)
        local room_name = getRoomName(room_id) or "unnamed"
        local dest_name = getRoomName(dest_room) or "unnamed"
        cecho(string.format("\n<green>[map]<reset> Exit marked dangerous: <white>%s<reset> --%s--> <white>%s<reset>\n", room_name, direction, dest_name))
        cecho("  <red>Destination marked as death/danger room<reset>\n")
        updateMap(); return true
    end

    local dir_num = f2t_map_direction_to_number(direction)
    if not dir_num then
        cecho(string.format("\n<red>[map]<reset> Unknown direction: %s\n", direction)); return false
    end
    local has_stub = false
    local stubs = getExitStubs(room_id)
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == dir_num then has_stub = true; break end
    end
    local gmcp_fed2_num = nil
    if room_id == F2T_MAP_CURRENT_ROOM_ID and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.exits then
        local abbrev = f2t_map_normalize_direction(direction)
        gmcp_fed2_num = gmcp.room.info.exits[direction] or gmcp.room.info.exits[abbrev]
    end
    if not has_stub and not gmcp_fed2_num then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id)); return false
    end
    if not gmcp_fed2_num then
        cecho(string.format("\n<yellow>[map]<reset> Exit '%s' is a stub — destination unknown\n", direction))
        cecho("\n<dim_grey>Must be standing in this room with GMCP to mark an undiscovered exit as danger.\n")
        return false
    end
    local system = getRoomUserData(room_id, "fed2_system") or (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.system)
    local area   = getRoomUserData(room_id, "fed2_area")   or (gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.area)
    if not system or not area then
        cecho("\n<red>[map]<reset> Cannot determine system/area to create placeholder room\n"); return false
    end
    local hash = string.format("%s.%s.%d", system, area, gmcp_fed2_num)
    local dest_room_id = getRoomIDbyHash(hash)
    if dest_room_id and dest_room_id > 0 then
        setRoomUserData(dest_room_id, "f2t_danger", "true")
        f2t_map_apply_death_room_style(dest_room_id)
    else
        local area_id = getRoomArea(room_id)
        if not area_id or area_id <= 0 then
            cecho("\n<red>[map]<reset> Cannot determine area ID to create placeholder room\n"); return false
        end
        dest_room_id = createRoomID()
        if not addRoom(dest_room_id) then
            cecho(string.format("\n<red>[map]<reset> Failed to create placeholder room (ID: %d)\n", dest_room_id)); return false
        end
        setRoomArea(dest_room_id, area_id)
        setRoomIDbyHash(dest_room_id, hash)
        setRoomName(dest_room_id, string.format("[Death] %s.%d", area, gmcp_fed2_num))
        local x, y, z = f2t_map_calculate_coords_from_room_num(gmcp_fed2_num)
        setRoomCoordinates(dest_room_id, x, y, z)
        setRoomUserData(dest_room_id, "fed2_system", system)
        setRoomUserData(dest_room_id, "fed2_area",   area)
        setRoomUserData(dest_room_id, "fed2_num",    tostring(gmcp_fed2_num))
        setRoomUserData(dest_room_id, "f2t_danger",  "true")
    end
    if has_stub then setExitStub(room_id, dir_num, false) end
    local exit_created = setExit(room_id, dest_room_id, dir_num)
    if not exit_created then
        if has_stub then setExitStub(room_id, dir_num, true) end
        cecho(string.format("\n<red>[map]<reset> Failed to connect exit to placeholder room %d\n", dest_room_id)); return false
    end
    lockExit(room_id, direction, true)
    lockRoom(dest_room_id, true)
    f2t_map_apply_death_room_style(dest_room_id)
    local room_name = getRoomName(room_id) or "unnamed"
    local dest_name = getRoomName(dest_room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Exit marked dangerous: <white>%s<reset> --%s--> <white>%s<reset>\n", room_name, direction, dest_name))
    cecho(string.format("  <yellow>Death placeholder created for undiscovered room %s<reset>\n", hash))
    cecho("  <red>Navigation will avoid this exit and room<reset>\n")
    updateMap(); return true
end

function f2t_map_manual_mark_room_death(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    lockRoom(room_id, true)
    setRoomUserData(room_id, "f2t_danger", "true")
    f2t_map_apply_death_room_style(room_id)
    local room_name = getRoomName(room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Room marked dangerous: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    cecho("  <red>Navigation will avoid this room<reset>\n")
    updateMap(); return true
end

function f2t_map_manual_unlock_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end
    direction = string.lower(direction)
    local dir_expand = {n="north",s="south",e="east",w="west",ne="northeast",nw="northwest",se="southeast",sw="southwest",u="up",d="down"}
    direction = dir_expand[direction] or direction
    local exits = getRoomExits(room_id)
    if not exits or not exits[direction] then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id)); return false
    end
    if not hasExitLock(room_id, direction) then
        cecho(string.format("\n<yellow>[map]<reset> Exit '%s' in room %d is not locked\n", direction, room_id)); return true
    end
    lockExit(room_id, direction, false)
    local room_name = getRoomName(room_id) or "unnamed"
    local dest_name = getRoomName(exits[direction]) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Exit unlocked: <white>%s<reset> --%s--> <white>%s<reset>\n", room_name, direction, dest_name))
    return true
end

function f2t_map_manual_lock_status(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    local room_name = getRoomName(room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Lock status for room %d (<white>%s<reset>):\n", room_id, room_name))
    local is_safe = getRoomUserData(room_id, "f2t_safe")
    if is_safe == "true" then cecho("  <cyan>Safe flag: SET<reset> (death monitor will never auto-lock)\n") end
    if roomLocked(room_id) then
        cecho("  <red>Room is LOCKED<reset>\n")
        local death_date = getRoomUserData(room_id, "f2t_death_date")
        if death_date and death_date ~= "" then
            cecho(string.format("  <red>Death Location<reset>: %s\n", death_date))
        end
    else
        cecho("  <green>Room is UNLOCKED<reset>\n")
    end
    local exits = getRoomExits(room_id)
    if exits and next(exits) ~= nil then
        cecho("\n  <yellow>Exit Lock Status:<reset>\n")
        local has_locked = false
        for dir, dest_id in pairs(exits) do
            if hasExitLock(room_id, dir) then
                has_locked = true
                cecho(string.format("    <red>%-10s<reset> <red>LOCKED<reset>   -> <white>%s<reset> (ID: %d)\n",
                    dir, getRoomName(dest_id) or "unnamed", dest_id))
            end
        end
        if not has_locked then cecho("    <green>No locked exits<reset>\n") end
    end
    cecho("\n")
end

function f2t_map_manual_mark_room_safe(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    setRoomUserData(room_id, "f2t_safe", "true")
    local room_name = getRoomName(room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Room marked safe: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    cecho("  <cyan>Death monitor will never auto-lock this room<reset>\n")
    return true
end

function f2t_map_manual_mark_room_unsafe(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    setRoomUserData(room_id, "f2t_safe", "")
    local room_name = getRoomName(room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Safe mark removed from room: <white>%s<reset> (ID: %d)\n", room_name, room_id))
    f2t_map_manual_mark_room_death(room_id)
    return true
end
