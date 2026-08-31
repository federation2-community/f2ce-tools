-- f2ce-tools map — manual exit management (ported from map_manual_exit.lua)

function f2t_map_manual_add_exit(from_room, to_room, direction, bidirectional)
    if not from_room or not roomExists(from_room) then
        cecho(string.format("\n<red>[map]<reset> Source room %s does not exist\n", tostring(from_room))); return false
    end
    if not to_room or not roomExists(to_room) then
        cecho(string.format("\n<red>[map]<reset> Destination room %s does not exist\n", tostring(to_room)))
        return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end

    local valid_directions = {
        "north","south","east","west","northeast","northwest","southeast","southwest","up","down","in","out"
    }
    direction = string.lower(direction)
    if not f2t_has_value(valid_directions, direction) then
        cecho(string.format("\n<red>[map]<reset> Invalid direction: %s\n", direction))
        cecho(string.format("\n<dim_grey>Valid directions: %s<reset>\n", table.concat(valid_directions, ", ")))
        return false
    end

    local reverse_dir_map = {
        north="south",south="north",east="west",west="east",
        northeast="southwest",southwest="northeast",northwest="southeast",southeast="northwest",
        up="down",down="up",["in"]="out",out="in",
    }

    setExit(from_room, to_room, direction)
    local from_name = getRoomName(from_room) or string.format("Room %d", from_room)
    local to_name   = getRoomName(to_room)   or string.format("Room %d", to_room)
    cecho(string.format(
        "\n<green>[map]<reset> Exit created: <white>%s<reset> --%s--> <white>%s<reset>\n",
        from_name, direction, to_name))

    if bidirectional then
        local reverse_dir = reverse_dir_map[direction]
        if reverse_dir then
            setExit(to_room, from_room, reverse_dir)
            cecho(string.format(
                "<green>[map]<reset> Reverse exit created: <white>%s<reset> --%s--> <white>%s<reset>\n",
                to_name, reverse_dir, from_name))
        else
            cecho(string.format("\n<yellow>[map]<reset> Warning: No reverse direction for '%s'\n", direction))
        end
    end
    return true
end

function f2t_map_manual_remove_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return end
    direction = string.lower(direction)
    local exits = getRoomExits(room_id)
    if not exits or not exits[direction] then
        cecho(string.format("\n<red>[map]<reset> No exit '%s' from room %d\n", direction, room_id)); return
    end
    local dest_room = exits[direction]
    local room_name = getRoomName(room_id) or string.format("Room %d", room_id)
    local dest_name = getRoomName(dest_room) or string.format("Room %d", dest_room)
    f2t_map_manual_request_confirmation(
        string.format("remove exit '%s' from room %d (%s -> %s)", direction, room_id, room_name, dest_name),
        function(data)
            if not roomExists(data.room_id) then
                cecho(string.format("\n<red>[map]<reset> Room %d no longer exists\n", data.room_id)); return
            end
            local current_exits = getRoomExits(data.room_id)
            if not current_exits or not current_exits[data.direction] then
                cecho(string.format(
                    "\n<red>[map]<reset> Exit '%s' no longer exists in room %d\n", data.direction, data.room_id))
                return
            end
            setExitStub(data.room_id, data.direction, 0)
            cecho(string.format(
                "\n<green>[map]<reset> Exit removed: <white>%s<reset> (%s)\n", data.direction, data.description))
        end,
        {room_id = room_id, direction = direction, description = string.format("%s -> %s", room_name, dest_name)}
    )
end

function f2t_map_manual_list_exits(room_id)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    local room_name = getRoomName(room_id) or "unnamed"
    local dir_num_to_name = {
        [1]="north",[2]="northeast",[3]="northwest",[4]="east",[5]="west",
        [6]="south",[7]="southeast",[8]="southwest",[9]="up",[10]="down",
        [11]="in",[12]="out",
    }
    local abbrev_to_full = {
        n="north",ne="northeast",nw="northwest",e="east",w="west",
        s="south",se="southeast",sw="southwest",u="up",d="down",
        ["in"]="in",out="out",
    }
    local exits = getRoomExits(room_id) or {}
    local stub_dirs = {}
    local stubs = getExitStubs(room_id) or {}
    for _, dir_num in ipairs(stubs) do
        local dir_name = dir_num_to_name[dir_num]
        if dir_name and not exits[dir_name] then stub_dirs[dir_name] = true end
    end
    local gmcp_only_dirs = {}
    if room_id == F2T_MAP_CURRENT_ROOM_ID and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.exits then
        for abbrev, fed2_num in pairs(gmcp.room.info.exits) do
            local full = abbrev_to_full[abbrev] or abbrev
            if not exits[full] and not stub_dirs[full] then gmcp_only_dirs[full] = fed2_num end
        end
    end
    local special_exits = getSpecialExitsSwap(room_id)

    cecho(string.format("\n<green>[map]<reset> Exits for room %d (<white>%s<reset>):\n", room_id, room_name))
    if next(exits) ~= nil then
        cecho("\n  <yellow>Connected Exits:<reset>\n")
        for dir, dest_id in pairs(exits) do
            local dest_name = getRoomName(dest_id) or "unnamed"
            local dest_hash = getRoomHashByID(dest_id) or "unknown"
            local lock_marker = hasExitLock(room_id, dir) and " <red>[LOCKED]<reset>" or ""
            cecho(string.format("    <cyan>%-12s<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>%s\n",
                dir, dest_name, dest_id, dest_hash, lock_marker))
        end
    else
        cecho("\n  <dim_grey>No connected exits<reset>\n")
    end
    local unexplored = {}
    for dir, _ in pairs(stub_dirs)    do unexplored[dir] = true end
    for dir, _ in pairs(gmcp_only_dirs) do unexplored[dir] = true end
    if next(unexplored) ~= nil then
        cecho("\n  <yellow>Unexplored Exits:<reset>\n")
        for dir, _ in pairs(unexplored) do
            cecho(string.format("    <dim_grey>%-12s<reset> -> <dim_grey>(unexplored)<reset>\n", dir))
        end
    end
    if special_exits and next(special_exits) ~= nil then
        cecho("\n  <yellow>Special Exits:<reset>\n")
        for dest_id, command in pairs(special_exits) do
            local dest_name = getRoomName(dest_id) or "unnamed"
            local dest_hash = getRoomHashByID(dest_id) or "unknown"
            if command:match("^__move_no_op_%d+$") then
                cecho(string.format(
                    "    <magenta>%-30s<reset> <dim_grey>(auto-transit)<reset> -> " ..
                    "<white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                    command, dest_name, dest_id, dest_hash))
            else
                cecho(string.format("    <magenta>%-30s<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                    command, dest_name, dest_id, dest_hash))
            end
        end
    else
        cecho("\n  <dim_grey>No special exits<reset>\n")
    end
    cecho("\n")
end

-- `map exit ...`, including the `stub` sub-ladder. Kept beside the exit
-- functions it drives rather than in the alias file.
function f2t_map_exit_command(args)
    local current_room = f2t_map_ensure_current_room(args)
    if not current_room then return end

    local rest = args:match("^exit%s*(.*)") or ""
    if f2t_handle_help("map exit", rest) then return end

    if rest == "" then
        f2t_show_registered_help("map exit")
        return
    end

    local words = f2t_parse_words(rest)
    local exit_subcmd = words[1]

    if exit_subcmd == "special" then
        local dest_or_remove = words[2]

        if f2t_handle_help("map exit special", dest_or_remove) then return end

        if not dest_or_remove then
            f2t_show_registered_help("map exit special")
            return
        end

        if dest_or_remove == "list" then
            local room_id = current_room
            if words[3] then
                room_id = tonumber(words[3])
                if not room_id then
                    cecho("\n<red>[map]<reset> Invalid room ID: must be a number\n")
                    return
                end
            end

            if not roomExists(room_id) then
                cecho(string.format("\n<red>[map]<reset> Room %d does not exist\n", room_id))
                return
            end

            local room_name = getRoomName(room_id)
            local exits = f2t_map_special_get_all_exits(room_id)
            cecho(string.format("\n<green>[map]<reset> Special exits for room %d (<white>%s<reset>)\n",
                room_id, room_name or "unnamed"))

            if exits and next(exits) ~= nil then
                for command, dest_room_id in pairs(exits) do
                    local dest_name = getRoomName(dest_room_id) or "unnamed"
                    local dest_hash = f2t_map_generate_hash_from_room(dest_room_id) or "unknown"
                    if command:match("^__move_no_op_%d+$") then
                        cecho(string.format(
                            "  <yellow>%s<reset> <dim_grey>(auto-transit)<reset> -> <white>%s<reset>"
                            .. " <dim_grey>[%d | %s]<reset>\n",
                            command, dest_name, dest_room_id, dest_hash))
                    else
                        cecho(string.format("  <yellow>%s<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
                            command, dest_name, dest_room_id, dest_hash))
                    end
                end
            else
                cecho("\n<dim_grey>No special exits configured for this room.<reset>\n")
            end

        elseif dest_or_remove == "reverse" then
            local command = string.match(rest, "^special%s+reverse%s+(.+)$")
            local success, error_msg, from_room, to_room, used_command =
                f2t_map_special_reverse_exit(current_room, command)

            if success then
                local from_name = getRoomName(from_room) or string.format("Room %d", from_room)
                local to_name = getRoomName(to_room) or string.format("Room %d", to_room)
                cecho(string.format(
                    "\n<green>[map]<reset> Reverse special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                    from_name, to_name))
                if used_command == "noop" then
                    cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
                else
                    cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", used_command))
                end
            else
                cecho(string.format("\n<red>[map]<reset> Error: %s\n", error_msg or "Failed to create reverse exit"))
            end

        elseif dest_or_remove == "remove" then
            if #words < 3 then
                cecho("\n<red>[map]<reset> Usage: map exit special remove <command>\n")
                cecho("\n<red>[map]<reset> Usage: map exit special remove <room_id> <command>\n")
                return
            end

            local room_id, command
            if tonumber(words[3]) ~= nil then
                room_id = tonumber(words[3])
                command = string.match(rest, "^special%s+remove%s+%d+%s+(.+)$")
            else
                room_id = current_room
                command = string.match(rest, "^special%s+remove%s+(.+)$")
            end

            if not command then
                cecho("\n<red>[map]<reset> Invalid command\n")
                return
            end

            local success = f2t_map_special_remove_exit(room_id, command)
            if success then
                cecho(string.format("\n<green>[map]<reset> Special exit removed: <yellow>%s<reset>\n", command))
            else
                cecho(string.format("\n<yellow>[map]<reset> No special exit found for command: %s\n", command))
            end

        else
            local second_is_number = tonumber(dest_or_remove) ~= nil
            local third_is_number = words[3] and tonumber(words[3]) ~= nil

            if not second_is_number then
                local command = string.match(rest, "^special%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Invalid command\n")
                    return
                end
                f2t_map_special_exit_discovery_start(current_room, command)

            elseif second_is_number and third_is_number then
                local source_room_id = tonumber(words[2])
                local dest_room_id = tonumber(words[3])
                local command = string.match(rest, "^special%s+%d+%s+%d+%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Missing command\n")
                    return
                end
                local success = f2t_map_special_set_exit(source_room_id, dest_room_id, command)
                if success then
                    local from_name = getRoomName(source_room_id) or string.format("Room %d", source_room_id)
                    local to_name = getRoomName(dest_room_id) or string.format("Room %d", dest_room_id)
                    cecho(string.format(
                        "\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                        from_name, to_name))
                    if command == "noop" then
                        cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
                    else
                        cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", command))
                    end
                else
                    cecho("\n<red>[map]<reset> Failed to create special exit\n")
                end

            else
                local source_room_id = current_room
                local dest_room_id = tonumber(words[2])
                if not dest_room_id then
                    cecho("\n<red>[map]<reset> Invalid room ID: must be a number\n")
                    return
                end
                local command = string.match(rest, "^special%s+%d+%s+(.+)$")
                if not command then
                    cecho("\n<red>[map]<reset> Missing command\n")
                    return
                end
                local success = f2t_map_special_set_exit(source_room_id, dest_room_id, command)
                if success then
                    local from_name = getRoomName(source_room_id) or string.format("Room %d", source_room_id)
                    local to_name = getRoomName(dest_room_id) or string.format("Room %d", dest_room_id)
                    cecho(string.format(
                        "\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
                        from_name, to_name))
                    if command == "noop" then
                        cecho("\n<dim_grey>  Command: (auto-transit, wait for GMCP)<reset>\n")
                    else
                        cecho(string.format("\n<dim_grey>  Command: %s<reset>\n", command))
                    end
                else
                    cecho("\n<red>[map]<reset> Failed to create special exit\n")
                end
            end
        end

    elseif exit_subcmd == "add" then
        if #words < 4 then
            cecho("\n<red>[map]<reset> Usage: map exit add <from_room_id> <to_room_id> <direction>\n")
            return
        end
        local from_room = tonumber(words[2])
        local to_room = tonumber(words[3])
        local direction = words[4]
        if not from_room or not to_room then
            cecho("\n<red>[map]<reset> Room IDs must be numbers\n")
            return
        end
        f2t_map_manual_add_exit(from_room, to_room, direction, false)

    elseif exit_subcmd == "remove" then
        if #words < 3 then
            cecho("\n<red>[map]<reset> Usage: map exit remove <room_id> <direction>\n")
            return
        end
        local room_id = tonumber(words[2])
        local direction = words[3]
        if not room_id then
            cecho("\n<red>[map]<reset> Room ID must be a number\n")
            return
        end
        f2t_map_manual_remove_exit(room_id, direction)

    elseif exit_subcmd == "list" then
        local room_id
        if words[2] then
            room_id = tonumber(words[2])
            if not room_id then
                cecho("\n<red>[map]<reset> Room ID must be a number\n")
                return
            end
        else
            room_id = current_room
        end
        f2t_map_manual_list_exits(room_id)

    elseif exit_subcmd == "lock" then
        local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 2)
        if not success then
            cecho("\n<red>[map]<reset> Usage: map exit lock [room_id] <direction>\n")
            return
        end
        if not room_id then
            cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
            return
        end
        f2t_map_manual_lock_exit(room_id, direction)

    elseif exit_subcmd == "unlock" then
        if words[2] == "all" then
            local area_name = table.concat(words, " ", 3)
            local area_id = (area_name ~= "") and f2t_map_get_area_id(area_name)
                or (current_room and getRoomArea(current_room))
            if not area_id then
                cecho("\n<red>[map]<reset> Usage: map exit unlock all [area]\n")
                return
            end
            f2t_map_manual_unlock_area_exits(area_id)
            return
        end
        local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 2)
        if not success then
            cecho("\n<red>[map]<reset> Usage: map exit unlock [room_id] <direction>\n")
            return
        end
        if not room_id then
            cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
            return
        end
        f2t_map_manual_unlock_exit(room_id, direction)

    elseif exit_subcmd == "death" then
        local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 2)
        if not success then
            cecho("\n<red>[map]<reset> Usage: map exit death [room_id] <direction>\n")
            return
        end
        if not room_id then
            cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
            return
        end
        f2t_map_manual_death_exit(room_id, direction)

    elseif exit_subcmd == "stub" then
        local stub_subcmd = words[2]

        if f2t_handle_help("map exit stub", stub_subcmd) then return end

        if not stub_subcmd then
            f2t_show_registered_help("map exit stub")
            return
        end

        if stub_subcmd == "create" then
            local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map exit stub create [room_id] <direction>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_create_stub(room_id, direction)

        elseif stub_subcmd == "delete" then
            local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map exit stub delete [room_id] <direction>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_delete_stub(room_id, direction)

        elseif stub_subcmd == "connect" then
            local room_id, direction, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map exit stub connect [room_id] <direction>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_connect_stub(room_id, direction)

        elseif stub_subcmd == "list" then
            local room_id
            if words[3] then
                room_id = tonumber(words[3])
                if not room_id then
                    cecho("\n<red>[map]<reset> Room ID must be a number\n")
                    return
                end
            else
                room_id = current_room
            end
            f2t_map_manual_list_stubs(room_id)

        else
            cecho(string.format("\n<red>[map]<reset> Unknown stub command: %s\n", stub_subcmd))
            f2t_show_help_hint("map exit stub")
        end

    else
        cecho(string.format("\n<red>[map]<reset> Unknown exit subcommand: %s\n", exit_subcmd))
        f2t_show_help_hint("map exit")
    end
end
