-- Main map command - handles all map-related subcommands
local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("map")
    return
end

if f2t_handle_help("map", args) then
    return
end

local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "on" then
    F2T_MAP_ENABLED = true
    f2t_settings_set("map", "enabled", true)
    cecho("\n<green>[map]<reset> Auto-mapping <yellow>ENABLED<reset>\n")
    f2t_debug_log("[map] Mapper enabled by user")

elseif subcommand == "off" then
    F2T_MAP_ENABLED = false
    f2t_settings_set("map", "enabled", false)
    cecho("\n<green>[map]<reset> Auto-mapping <red>DISABLED<reset>\n")
    f2t_debug_log("[map] Mapper disabled by user")

elseif subcommand == "sync" then
    f2t_map_sync()

elseif subcommand == "resync" then
    local rest = args:match("^resync%s*(.*)") or ""

    if f2t_handle_help("map resync", rest) then return end

    if rest == "" or rest == "jumps" then
        f2t_map_resync_all_jump_exits()
    elseif rest == "here" then
        if not F2T_MAP_CURRENT_ROOM_ID then
            cecho("\n<red>[map]<reset> No current room.\n")
            return
        end
        if f2t_map_resync_jump_exits(F2T_MAP_CURRENT_ROOM_ID) then
            cecho("\n<green>[map]<reset> Resyncing jump exits for the current room...\n")
        else
            cecho("\n<orange>[map]<reset> A jump-exit probe is already in progress; try again shortly.\n")
        end
    else
        cecho(string.format("\n<red>[map]<reset> Unknown resync target: %s\n", rest))
        f2t_show_help_hint("map resync")
    end

elseif subcommand == "clear" then
    local confirm = args:match("^clear%s+(.+)")

    if not confirm or confirm ~= "confirm" then
        cecho("\n<yellow>[map]<reset> This will delete the ENTIRE map!\n")
        cecho("\n<yellow>[map]<reset> Type <white>map clear confirm<reset> to proceed.\n")
        return
    end

    local rooms = getRooms()
    local room_count = 0
    for room_id, _ in pairs(rooms) do
        deleteRoom(room_id)
        room_count = room_count + 1
    end

    F2T_MAP_CURRENT_ROOM_ID = nil
    updateMap()

    cecho(string.format("\n<green>[map]<reset> Map cleared. %d rooms deleted.\n", room_count))

    if F2T_MAP_ENABLED then
        cecho("\n<green>[map]<reset> Synchronizing with current location...\n")
        f2t_map_sync()
    end

elseif subcommand == "dest" or subcommand == "destination" then
    local rest = args:match("^dest%s*(.*)") or args:match("^destination%s*(.*)") or ""

    if f2t_handle_help("map dest", rest) then return end

    if rest == "" or rest == "list" then
        f2t_map_destination_list()
        return
    end

    local dest_subcommand, dest_rest = string.match(rest, "^(%S+)%s*(.*)$")
    if not dest_subcommand then
        dest_subcommand = rest
        dest_rest = ""
    end
    dest_subcommand = string.lower(dest_subcommand)

    if dest_subcommand == "add" then
        if dest_rest == "" then
            cecho("\n<red>[map]<reset> Usage: map dest add <name>\n")
            return
        end
        f2t_map_destination_add(dest_rest)

    elseif dest_subcommand == "remove" or dest_subcommand == "rm" then
        if dest_rest == "" then
            cecho("\n<red>[map]<reset> Usage: map dest remove <name>\n")
            return
        end
        f2t_map_destination_remove(dest_rest)

    elseif dest_subcommand == "list" then
        f2t_map_destination_list()

    else
        cecho(string.format("\n<red>[map]<reset> Unknown dest command: %s\n", dest_subcommand))
        f2t_show_help_hint("map dest")
    end

elseif subcommand == "settings" then
    local settings_args = args:match("^settings%s*(.*)") or ""
    if f2t_handle_help("map settings", settings_args) then return end
    f2t_handle_settings_command("map", settings_args)

elseif subcommand == "search" then
    local rest = args:match("^search%s+(.+)") or ""

    if f2t_handle_help("map search", rest) then return end

    if rest == "" then
        f2t_show_registered_help("map search")
        return
    end

    local words = f2t_parse_words(rest)

    if string.lower(words[1]) == "all" then
        if #words < 2 then
            cecho("\n<red>[map]<reset> Missing search text after 'all'\n")
            return
        end
        local search_text = table.concat(words, " ", 2)
        local results = f2t_map_search_all(search_text)
        f2t_map_search_display(results, search_text, "all areas")
    else
        local location, search_text = f2t_map_parse_location_prefix(rest)

        if location then
            local results = f2t_map_search_planet_or_system(location, search_text)
            f2t_map_search_display(results, search_text, location)
        else
            search_text = rest

            if not f2t_map_ensure_current_location() then
                cecho("\n<yellow>[map]<reset> Current location unknown. Refreshing...\n")
                send("look")
                tempTimer(0.5, function()
                    expandAlias(string.format("map search %s", search_text))
                end)
                return
            end

            local results = f2t_map_search_current_area(search_text)
            if results == nil then
                cecho("\n<red>[map]<reset> Cannot determine current area\n")
                return
            end

            local current_area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
            local area_name = f2t_map_get_area_name(current_area_id) or "current area"
            f2t_map_search_display(results, search_text, area_name)
        end
    end

elseif subcommand == "explore" then
    local rest = args:match("^explore%s*(.*)") or ""

    if f2t_handle_help("map explore", rest) then return end

    if rest == "" then
        f2t_map_explore_start("brief")
        return
    end

    local words = f2t_parse_words(rest)
    local first = string.lower(words[1])

    if first == "full" or first == "brief" then
        local mode = first
        local target = words[2] and f2t_parse_rest(words, 2) or nil
        f2t_map_explore_start(mode, target)

    elseif first == "cartel" then
        local cartel_name = f2t_parse_rest(words, 2)

        if not cartel_name or cartel_name == "" then
            cartel_name = f2t_map_get_current_cartel()
        end

        if not cartel_name or cartel_name == "" then
            cecho("\n<red>[map]<reset> Error: No cartel specified and couldn't detect current cartel\n")
            cecho("\n<dim_grey>Usage: map explore cartel <cartel><reset>\n")
            return
        end

        f2t_map_explore_cartel_start(cartel_name)

    elseif first == "galaxy" then
        f2t_map_explore_galaxy_start()

    elseif first == "stop" then
        f2t_map_explore_stop()

    elseif first == "pause" then
        f2t_map_explore_pause()

    elseif first == "resume" then
        f2t_map_explore_resume()

    elseif first == "status" then
        f2t_map_explore_status()

    elseif first == "suspected" then
        f2t_map_explore_list_suspected()

    else
        local target = f2t_parse_rest(words, 1)
        f2t_map_explore_start("brief", target)
    end

elseif subcommand == "room" then
    local rest = args:match("^room%s*(.*)") or ""

    if f2t_handle_help("map room", rest) then return end

    if rest == "" then
        f2t_show_registered_help("map room")
        return
    end

    local words = f2t_parse_words(rest)
    local room_subcmd = words[1]

    if room_subcmd == "add" then
        local system = words[2]
        local area = words[3]
        local num = tonumber(words[4])
        local name = string.match(rest, "^add%s+%S+%s+%S+%s+%S+%s+(.+)$")

        if not system or not area or not num then
            cecho("\n<red>[map]<reset> Usage: map room add <system> <area> <num> [name]\n")
            f2t_show_help_hint("map room")
            return
        end

        f2t_map_manual_create_room(system, area, num, name)

    elseif room_subcmd == "delete" then
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then cecho("\n<red>[map]<reset> No current room. Please specify room_id\n") end
            return
        end
        f2t_map_manual_delete_room(room_id)

    elseif room_subcmd == "info" then
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then cecho("\n<red>[map]<reset> No current room. Please specify room_id\n") end
            return
        end
        f2t_map_manual_room_info(room_id)

    elseif room_subcmd == "set" then
        local property = words[2]

        if not property then
            cecho("\n<red>[map]<reset> Usage: map room set <property> [room_id] <value...>\n")
            f2t_show_help_hint("map room")
            return
        end

        if property == "name" then
            local room_id, name
            local potential_room = tonumber(words[3])

            if potential_room and words[4] then
                room_id = potential_room
                name = f2t_parse_rest(words, 4)
            else
                room_id = F2T_MAP_CURRENT_ROOM_ID
                name = f2t_parse_rest(words, 3)
            end

            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            if not name or name == "" then
                cecho("\n<red>[map]<reset> Usage: map room set name [room_id] <name>\n")
                return
            end
            f2t_map_manual_set_room_name(room_id, name)

        elseif property == "area" then
            local room_id, area, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not area then
                cecho("\n<red>[map]<reset> Usage: map room set area [room_id] <area>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_set_room_area(room_id, area)

        elseif property == "coords" then
            local room_id, coord_args, success = f2t_map_parse_optional_room_and_args(words, 3, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map room set coords [room_id] <x> <y> <z>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local x, y, z = tonumber(coord_args[1]), tonumber(coord_args[2]), tonumber(coord_args[3])
            if not x or not y or not z then
                cecho("\n<red>[map]<reset> Coordinates must be numbers\n")
                return
            end
            f2t_map_manual_set_room_coords(room_id, x, y, z)

        elseif property == "symbol" then
            local room_id, symbol, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not symbol then
                cecho("\n<red>[map]<reset> Usage: map room set symbol [room_id] <char>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            f2t_map_manual_set_room_symbol(room_id, symbol)

        elseif property == "color" then
            local room_id, color_args, success = f2t_map_parse_optional_room_and_args(words, 3, 3)
            if not success then
                cecho("\n<red>[map]<reset> Usage: map room set color [room_id] <r> <g> <b>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local r, g, b = tonumber(color_args[1]), tonumber(color_args[2]), tonumber(color_args[3])
            if not r or not g or not b then
                cecho("\n<red>[map]<reset> Color values must be numbers\n")
                return
            end
            f2t_map_manual_set_room_color(room_id, r, g, b)

        elseif property == "env" then
            local room_id, env_str, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not env_str then
                cecho("\n<red>[map]<reset> Usage: map room set env [room_id] <env_id>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local env_id = tonumber(env_str)
            if not env_id then
                cecho("\n<red>[map]<reset> Environment ID must be a number\n")
                return
            end
            f2t_map_manual_set_room_env(room_id, env_id)

        elseif property == "weight" then
            local room_id, weight_str, success = f2t_map_parse_optional_room_and_arg(words, 3)
            if not success or not weight_str then
                cecho("\n<red>[map]<reset> Usage: map room set weight [room_id] <weight>\n")
                return
            end
            if not room_id then
                cecho("\n<red>[map]<reset> No current room. Please specify room_id\n")
                return
            end
            local weight = tonumber(weight_str)
            if not weight then
                cecho("\n<red>[map]<reset> Weight must be a number\n")
                return
            end
            f2t_map_manual_set_room_weight(room_id, weight)

        else
            cecho(string.format("\n<red>[map]<reset> Unknown property: %s\n", property))
            cecho("\n<dim_grey>Available: name, area, coords, symbol, color, env, weight<reset>\n")
        end

    elseif room_subcmd == "lock" then
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then cecho("\n<red>[map]<reset> No current room. Please specify room_id\n") end
            return
        end
        f2t_map_manual_lock_room(room_id)

    elseif room_subcmd == "unlock" then
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then cecho("\n<red>[map]<reset> No current room. Please specify room_id\n") end
            return
        end
        f2t_map_manual_unlock_room(room_id)

    elseif room_subcmd == "death" then
        local room_id = tonumber(words[2])
        if not room_id then
            cecho("\n<red>[map]<reset> Usage: map room death <room_id>\n")
            cecho("\n<dim_grey>A room ID is required (you cannot be standing in a death room)<reset>\n")
            return
        end
        f2t_map_manual_mark_room_death(room_id)

    elseif room_subcmd == "safe" then
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then cecho("\n<red>[map]<reset> No current room. Please specify room_id\n") end
            return
        end
        f2t_map_manual_mark_room_safe(room_id)

    elseif room_subcmd == "unsafe" then
        local room_id, error_shown = f2t_map_parse_optional_room_id(words, 2)
        if not room_id then
            if not error_shown then cecho("\n<red>[map]<reset> No current room. Please specify room_id\n") end
            return
        end
        f2t_map_manual_mark_room_unsafe(room_id)

    else
        cecho(string.format("\n<red>[map]<reset> Unknown room command: %s\n", room_subcmd))
        f2t_show_help_hint("map room")
    end

elseif subcommand == "confirm" then
    f2t_map_manual_confirm()

elseif subcommand == "cancel" then
    f2t_map_manual_cancel_confirmation()

elseif subcommand == "restyle" then
    f2t_map_restyle_all()

elseif subcommand == "raw" then
    local rest = args:match("^raw%s*(.*)") or ""
    if f2t_handle_help("map raw", rest) then return end

    if rest == "" then
        f2t_map_raw_display_room(nil, true)
    else
        local room_id = tonumber(rest)
        if room_id then
            f2t_map_raw_display_room(room_id, false)
        else
            cecho("\n<red>[map]<reset> Usage: map raw [room_id]\n")
        end
    end

elseif subcommand == "exit" then
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
                        cecho(string.format("  <yellow>%s<reset> <dim_grey>(auto-transit)<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
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
                cecho(string.format("\n<green>[map]<reset> Reverse special exit created: <white>%s<reset> -> <white>%s<reset>\n",
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
                    cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
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
                    cecho(string.format("\n<green>[map]<reset> Special exit created: <white>%s<reset> -> <white>%s<reset>\n",
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

elseif subcommand == "special" then
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
                    cecho(string.format("\n<green>[map]<reset> On-arrival command set (<cyan>%s<reset>): <white>%s<reset>\n",
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

elseif subcommand == "export" then
    local rest = args:match("^export%s*(.*)") or ""
    if f2t_handle_help("map export", rest) then return end
    f2t_map_export()

elseif subcommand == "import" then
    local rest = args:match("^import%s*(.*)") or ""
    if f2t_handle_help("map import", rest) then return end
    if rest == "" then
        f2t_map_import()
    elseif rest:lower() == "db" then
        -- Open the bundled-resource picker directly, regardless of the
        -- first-run gate (useful for re-importing or testing). The picker
        -- renders inside the live Fed2 Map pane's own slot (not a standalone
        -- dialog), so it needs that pane to be open somewhere first.
        local slotContent, gid
        if f2tGetMapSlotInfo then
            slotContent, gid = f2tGetMapSlotInfo()
        end
        if f2tShowMapImportOverlay and slotContent then
            f2tShowMapImportOverlay(slotContent, gid, "manual")
        else
            cecho("\n<yellow>[map]<reset> Map database picker unavailable — open the Fed2 Map pane first.\n")
        end
    else
        cecho(string.format("\n<red>[map]<reset> Unknown import option: %s\n", rest))
        f2t_show_help_hint("map import")
        return
    end

else
    cecho(string.format("\n<red>[map]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("map")
end
