-- f2ce-tools map — special navigation (ported from map_special.lua)

F2T_MAP_PENDING_SPECIAL_EXIT = nil
F2T_MAP_LAST_DISCOVERY = nil

F2T_MAP_ARRIVAL_TYPE_ALWAYS    = "always"
F2T_MAP_ARRIVAL_TYPE_ONCE_ROOM = "once-room"
F2T_MAP_ARRIVAL_TYPE_ONCE_AREA = "once-area"
F2T_MAP_ARRIVAL_TYPE_ONCE_EVER = "once-ever"

F2T_MAP_ARRIVAL_ONCE_AREA_EXECUTED = F2T_MAP_ARRIVAL_ONCE_AREA_EXECUTED or {}
F2T_MAP_ARRIVAL_LAST_AREA = F2T_MAP_ARRIVAL_LAST_AREA or nil

function f2t_map_special_set_arrival(room_id, command, exec_type)
    if not room_id or not roomExists(room_id) then return false end
    if not command or command == "" then return false end
    exec_type = exec_type or F2T_MAP_ARRIVAL_TYPE_ALWAYS
    if exec_type ~= F2T_MAP_ARRIVAL_TYPE_ALWAYS and
       exec_type ~= F2T_MAP_ARRIVAL_TYPE_ONCE_ROOM and
       exec_type ~= F2T_MAP_ARRIVAL_TYPE_ONCE_AREA and
       exec_type ~= F2T_MAP_ARRIVAL_TYPE_ONCE_EVER then
        return false
    end
    setRoomUserData(room_id, "fed2_arrival_cmd", command)
    setRoomUserData(room_id, "fed2_arrival_type", exec_type)
    if exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_ROOM or exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_EVER then
        setRoomUserData(room_id, "fed2_arrival_executed", "false")
    end
    return true
end

function f2t_map_special_get_arrival(room_id)
    if not room_id or not roomExists(room_id) then return nil, nil end
    local command = getRoomUserData(room_id, "fed2_arrival_cmd")
    if command == "" or not command then return nil, nil end
    local exec_type = getRoomUserData(room_id, "fed2_arrival_type")
    if exec_type == "" or not exec_type then exec_type = F2T_MAP_ARRIVAL_TYPE_ALWAYS end
    return command, exec_type
end

function f2t_map_special_should_execute_arrival(room_id, exec_type)
    if not room_id or not exec_type then return false end
    if exec_type == F2T_MAP_ARRIVAL_TYPE_ALWAYS then return true end
    if exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_ROOM or exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_EVER then
        return getRoomUserData(room_id, "fed2_arrival_executed") ~= "true"
    end
    if exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_AREA then
        local current_area = getRoomArea(room_id)
        if current_area ~= F2T_MAP_ARRIVAL_LAST_AREA then
            F2T_MAP_ARRIVAL_ONCE_AREA_EXECUTED = {}
            F2T_MAP_ARRIVAL_LAST_AREA = current_area
        end
        return not F2T_MAP_ARRIVAL_ONCE_AREA_EXECUTED[tostring(room_id)]
    end
    return false
end

function f2t_map_special_mark_arrival_executed(room_id, exec_type)
    if not room_id or not exec_type then return end
    if exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_ROOM or exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_EVER then
        setRoomUserData(room_id, "fed2_arrival_executed", "true")
    end
    if exec_type == F2T_MAP_ARRIVAL_TYPE_ONCE_AREA then
        F2T_MAP_ARRIVAL_ONCE_AREA_EXECUTED[tostring(room_id)] = true
    end
end

function f2t_map_special_remove_arrival(room_id)
    if not room_id or not roomExists(room_id) then return false end
    setRoomUserData(room_id, "fed2_arrival_cmd", "")
    return true
end

function f2t_map_special_set_exit(from_room_id, to_room_id, command)
    if not from_room_id or not roomExists(from_room_id) then return false end
    if not to_room_id or not roomExists(to_room_id) then return false end
    if not command or command == "" then return false end
    command = command:match("^%s*(.-)%s*$")
    local exit_command = command
    if command == "noop" then exit_command = string.format("__move_no_op_%d", to_room_id) end
    addSpecialExit(from_room_id, to_room_id, exit_command)
    addCustomLine(from_room_id, to_room_id, exit_command, "dash line", color_table.grey, true)
    return true
end

function f2t_map_special_get_all_exits(room_id)
    if not room_id or not roomExists(room_id) then return {} end
    local mudlet_exits = getSpecialExits(room_id) or {}
    local exits = {}
    for dest_room_id, commands in pairs(mudlet_exits) do
        if type(commands) == "table" then
            for command, _ in pairs(commands) do exits[command] = dest_room_id end
        end
    end
    return exits
end

function f2t_map_special_remove_exit(room_id, command)
    if not room_id or not roomExists(room_id) or not command or command == "" then return false end
    local exits = f2t_map_special_get_all_exits(room_id)
    if not exits or not exits[command] then return false end
    removeSpecialExit(room_id, command)
    removeCustomLine(room_id, command)
    return true
end

function f2t_map_special_exit_discovery_start(from_room_id, command)
    if not from_room_id or not roomExists(from_room_id) then
        cecho("\n<red>[map]<reset> Error: Invalid source room\n")
        return false
    end
    F2T_MAP_PENDING_SPECIAL_EXIT = {from_room = from_room_id, command = command}
    local from_name = getRoomName(from_room_id) or string.format("Room %d", from_room_id)
    cecho(string.format("\n<green>[map]<reset> Testing special exit from <white>%s<reset>\n", from_name))
    if command == "noop" then
        cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
        cecho("\n<yellow>[map]<reset> Auto-transit detected. Move to the destination room naturally.\n")
    else
        cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", command))
        cecho("\n<dim_grey>Sending command and waiting for room change...<reset>\n")
        send(command)
    end
    return true
end

function f2t_map_special_exit_discovery_complete(to_room_id)
    if not F2T_MAP_PENDING_SPECIAL_EXIT then return false end
    local from_room = F2T_MAP_PENDING_SPECIAL_EXIT.from_room
    local command   = F2T_MAP_PENDING_SPECIAL_EXIT.command
    if from_room == to_room_id then
        cecho("\n<yellow>[map]<reset> Warning: Command did not change rooms\n")
        F2T_MAP_PENDING_SPECIAL_EXIT = nil
        return false
    end
    local success = f2t_map_special_set_exit(from_room, to_room_id, command)
    if success then
        local from_name = getRoomName(from_room) or string.format("Room %d", from_room)
        local to_name   = getRoomName(to_room_id) or string.format("Room %d", to_room_id)
        cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n", from_name, to_name))
        if command == "noop" then
            cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
        else
            cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", command))
        end
        F2T_MAP_LAST_DISCOVERY = {from_room = from_room, to_room = to_room_id, command = command}
    else
        cecho("\n<red>[map]<reset> Failed to create special exit\n")
    end
    F2T_MAP_PENDING_SPECIAL_EXIT = nil
    return success
end

function f2t_map_special_create_reverse(from_room_id, to_room_id, command)
    if not from_room_id or not roomExists(from_room_id) then return false end
    if not to_room_id   or not roomExists(to_room_id)   then return false end
    return f2t_map_special_set_exit(to_room_id, from_room_id, command)
end

function f2t_map_special_reverse_exit(current_room_id, command)
    if not current_room_id or not roomExists(current_room_id) then
        return false, "Invalid room", nil, nil, nil
    end
    if not F2T_MAP_LAST_DISCOVERY then
        return false, "No recent discovery to reverse. Use discovery method first.", nil, nil, nil
    end
    if current_room_id ~= F2T_MAP_LAST_DISCOVERY.to_room then
        local expected_name = getRoomName(F2T_MAP_LAST_DISCOVERY.to_room) or
                             string.format("Room %d", F2T_MAP_LAST_DISCOVERY.to_room)
        return false, string.format("Not in destination room. Navigate to %s first.", expected_name), nil, nil, nil
    end
    local reverse_command = command or F2T_MAP_LAST_DISCOVERY.command
    local from_room_id = F2T_MAP_LAST_DISCOVERY.to_room
    local dest_room_id = F2T_MAP_LAST_DISCOVERY.from_room
    local success = f2t_map_special_create_reverse(F2T_MAP_LAST_DISCOVERY.from_room,
                                                    F2T_MAP_LAST_DISCOVERY.to_room,
                                                    reverse_command)
    if not success then return false, "Failed to create reverse exit", nil, nil, nil end
    return true, nil, from_room_id, dest_room_id, reverse_command
end

function f2t_map_special_list_arrivals()
    local rooms_with_arrivals = {}
    local all_rooms = getRooms()
    for room_id, _ in pairs(all_rooms) do
        local arrival_cmd, exec_type = f2t_map_special_get_arrival(room_id)
        if arrival_cmd then
            table.insert(rooms_with_arrivals, {
                id = room_id, name = getRoomName(room_id) or "unnamed",
                command = arrival_cmd, exec_type = exec_type or F2T_MAP_ARRIVAL_TYPE_ALWAYS,
            })
        end
    end
    table.sort(rooms_with_arrivals, function(a, b) return a.name < b.name end)
    cecho("\n<green>[map]<reset> Rooms with on-arrival commands\n")
    if #rooms_with_arrivals == 0 then
        cecho("\n<dim_grey>No on-arrival commands configured.<reset>\n"); return
    end
    for _, room in ipairs(rooms_with_arrivals) do
        local hash = f2t_map_generate_hash_from_room(room.id) or "unknown"
        cecho(string.format("\n<white>%s<reset> <dim_grey>[%d | %s]<reset>\n", room.name, room.id, hash))
        cecho(string.format("  <yellow>%s<reset> <cyan>(%s)<reset>\n", room.command, room.exec_type))
    end
    cecho(string.format("\n<dim_grey>Total: %d room(s)<reset>\n", #rooms_with_arrivals))
end

function f2t_map_special_list(room_id)
    if not room_id or not roomExists(room_id) then
        cecho("\n<red>[map]<reset> Invalid room\n"); return
    end
    local room_name = getRoomName(room_id)
    local hash = f2t_map_generate_hash_from_room(room_id)
    cecho(string.format("\n<green>[map]<reset> Special behaviors for room %d (<white>%s<reset>)\n",
        room_id, room_name or "unnamed"))
    if hash then cecho(string.format("<dim_grey>Hash: %s<reset>\n", hash)) end
    local arrival_cmd = f2t_map_special_get_arrival(room_id)
    if arrival_cmd then
        cecho("\n<cyan>On-Arrival Command:<reset>\n")
        cecho(string.format("  <white>%s<reset>\n", arrival_cmd))
    end
    local exits = f2t_map_special_get_all_exits(room_id)
    if exits and next(exits) ~= nil then
        cecho("\n<cyan>Special Exits:<reset>\n")
        for command, dest_room_id in pairs(exits) do
            local dest_name = getRoomName(dest_room_id) or "unnamed"
            local dest_hash = f2t_map_generate_hash_from_room(dest_room_id) or "unknown"
            if command:match("^__move_no_op_%d+$") then
                cecho(string.format("  <yellow>%s<reset> <dim_grey>(auto-transit)<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                    command, dest_name, dest_room_id, dest_hash))
            else
                cecho(string.format("  <yellow>%s<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                    command, dest_name, dest_room_id, dest_hash))
            end
        end
    end
    if not arrival_cmd and (not exits or next(exits) == nil) then
        cecho("\n<dim_grey>No special behaviors configured for this room.<reset>\n")
    end
end

f2t_debug_log("[map-special] Special navigation system initialized")
