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
        cecho(string.format(
            "\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n", from_name, to_name))
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
                cecho(string.format(
                    "  <yellow>%s<reset> <dim_grey>(auto-transit)<reset> -> " ..
                    "<white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
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

-- `map special ...`. Kept beside the special-exit functions it drives
-- rather than in the alias file.
function f2t_map_special_command(args)
    local current_room = f2t_map_ensure_current_room(args)
    if not current_room then return end

    local rest = args:match("^special%s*(.*)") or ""

    if rest == "" or f2t_handle_help("map special", rest) then
        if rest == "" then f2t_show_registered_help("map special") end
        return
    end

    local words = f2t_parse_words(rest)
    local special_subcmd = words[1]

    if special_subcmd == "arrival" then
        local arrival_rest = string.match(rest, "^arrival%s*(.*)") or ""

        if arrival_rest == "" or f2t_handle_help("map special arrival", arrival_rest) then
            if arrival_rest == "" then f2t_show_registered_help("map special arrival") end
            return
        end

        local command_or_remove = words[2]

        if command_or_remove == "list" then
            f2t_map_special_list_arrivals()
        elseif command_or_remove == "remove" then
            local success = f2t_map_special_remove_arrival(current_room)
            if success then
                cecho("\n<green>[map]<reset> On-arrival command removed\n")
            else
                cecho("\n<red>[map]<reset> Failed to remove on-arrival command\n")
            end
        else
            local type_or_command = command_or_remove
            local exec_type = F2T_MAP_ARRIVAL_TYPE_ALWAYS

            if type_or_command == "always" or type_or_command == "once-room" or
               type_or_command == "once-area" or type_or_command == "once-ever" then
                exec_type = type_or_command

                if #words < 3 then
                    cecho("\n<red>[map]<reset> Missing command after execution type\n")
                    cecho("\n<dim_grey>Usage: map special arrival [type] <command><reset>\n")
                    return
                end

                local command_parts = {}
                for i = 3, #words do table.insert(command_parts, words[i]) end
                local command = table.concat(command_parts, " ")

                local success = f2t_map_special_set_arrival(current_room, command, exec_type)
                if success then
                    cecho(string.format(
                        "\n<green>[map]<reset> On-arrival command set (<cyan>%s<reset>): <white>%s<reset>\n",
                        exec_type, command))
                else
                    cecho("\n<red>[map]<reset> Failed to set on-arrival command\n")
                end
            else
                local command = string.match(rest, "^arrival%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Invalid command\n")
                    return
                end
                local success = f2t_map_special_set_arrival(current_room, command, exec_type)
                if success then
                    cecho(string.format("\n<green>[map]<reset> On-arrival command set: <white>%s<reset>\n", command))
                else
                    cecho("\n<red>[map]<reset> Failed to set on-arrival command\n")
                end
            end
        end

    elseif special_subcmd == "circuit" then
        local circuit_rest = string.match(args, "^special%s+circuit%s*(.*)") or ""

        if circuit_rest == "" or f2t_handle_help("map special circuit", circuit_rest) then
            if circuit_rest == "" then f2t_show_registered_help("map special circuit") end
            return
        end

        local circuit_subcmd = words[2]

        if circuit_subcmd == "create" then
            f2t_map_circuit_cmd_create(words[3])

        elseif circuit_subcmd == "set" then
            local value = string.match(rest, "^circuit%s+set%s+%S+%s+%S+%s+(.+)$")
            f2t_map_circuit_cmd_set(words[3], words[4], value)

        elseif circuit_subcmd == "stop" then
            local stop_action = words[3]
            if not stop_action then
                cecho("\n<red>[map]<reset> Usage: map special circuit stop add <id> <name>\n")
                return
            end
            if stop_action == "add" then
                f2t_map_circuit_cmd_stop_add(words[4], words[5])
            elseif stop_action == "set" then
                local value = string.match(rest, "^circuit%s+stop%s+set%s+%S+%s+%S+%s+arrival_pattern%s+(.+)$")
                f2t_map_circuit_cmd_stop_set(words[4], words[5], words[6], value)
            else
                cecho(string.format("\n<red>[map]<reset> Unknown stop command: %s\n", stop_action))
            end

        elseif circuit_subcmd == "connect" then
            f2t_map_circuit_cmd_connect(words[3])

        elseif circuit_subcmd == "list" then
            f2t_map_circuit_cmd_list()

        elseif circuit_subcmd == "show" then
            f2t_map_circuit_cmd_show(words[3])

        elseif circuit_subcmd == "delete" then
            f2t_map_circuit_cmd_delete(words[3])

        else
            cecho(string.format("\n<red>[map]<reset> Unknown circuit command: %s\n", circuit_subcmd))
        end

    else
        cecho(string.format("\n<red>[map]<reset> Unknown special subcommand: %s\n", special_subcmd))
        f2t_show_help_hint("map special")
    end
end

f2t_debug_log("[map-special] Special navigation system initialized")
