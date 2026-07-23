-- f2ce-tools map — circuit builder commands (ported from map_circuit_builder.lua)

function f2t_map_circuit_cmd_create(circuit_id)
    if not circuit_id or circuit_id == "" then
        cecho("\n<red>[map]<reset> Usage: map special circuit create <circuit_id>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_id   = getRoomArea(current_room)
    local area_name = getRoomAreaName(area_id)
    if f2t_map_circuit_load(area_name, circuit_id) then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' already exists in %s\n", circuit_id, area_name)); return
    end
    local circuit_data = {vehicle_room=nil, stops={}, board_command="in", exit_command="out",
                          boarding_pattern=nil, is_loop=true}
    if f2t_map_circuit_save(area_name, circuit_id, circuit_data) then
        cecho(string.format("\n<green>[map]<reset> Created circuit '%s' in area %s\n", circuit_id, area_name))
        cecho("\n<dim_grey>Next: Set vehicle room (by hash), add stops, then connect<reset>\n")
    else
        cecho(string.format("\n<red>[map]<reset> Failed to create circuit '%s'\n", circuit_id))
    end
end

function f2t_map_circuit_cmd_set(circuit_id, property, value)
    if not circuit_id or not property or not value then
        cecho("\n<red>[map]<reset> Usage: map special circuit set <circuit_id> <property> <value>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_id   = getRoomArea(current_room)
    local area_name = getRoomAreaName(area_id)
    local circuit_data = f2t_map_circuit_load(area_name, circuit_id)
    if not circuit_data then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found in %s\n", circuit_id, area_name)); return
    end
    if property == "vehicle_room" then
        local room_num = tonumber(value)
        local hash = nil
        if room_num then
            if not roomExists(room_num) then
                cecho(string.format("\n<red>[map]<reset> Room %d does not exist in map\n", room_num)); return
            end
            hash = f2t_map_generate_hash_from_room(room_num)
            if not hash then
                cecho(string.format("\n<red>[map]<reset> Could not generate hash for room %d\n", room_num)); return
            end
        else
            if not value:match("^[^%.]+%.[^%.]+%.%d+$") then
                cecho(string.format("\n<red>[map]<reset> Invalid hash format: %s\n", value)); return
            end
            hash = value
        end
        circuit_data.vehicle_room = hash
    elseif property == "board_command" or property == "exit_command" or property == "boarding_pattern" then
        circuit_data[property] = value
    elseif property == "is_loop" then
        local bv = value:lower()
        if bv == "true" or bv == "yes" or bv == "1" then circuit_data.is_loop = true
        elseif bv == "false" or bv == "no" or bv == "0" then circuit_data.is_loop = false
        else cecho(string.format("\n<red>[map]<reset> Invalid boolean value: %s\n", value)); return
        end
    else
        cecho(string.format("\n<red>[map]<reset> Unknown property: %s\n", property)); return
    end
    if f2t_map_circuit_save(area_name, circuit_id, circuit_data) then
        cecho(string.format("\n<green>[map]<reset> Set %s.%s = %s\n", circuit_id, property, tostring(value)))
    else
        cecho(string.format("\n<red>[map]<reset> Failed to update circuit '%s'\n", circuit_id))
    end
end

function f2t_map_circuit_cmd_stop_add(circuit_id, stop_name)
    if not circuit_id or not stop_name then
        cecho("\n<red>[map]<reset> Usage: map special circuit stop add <circuit_id> <stop_name>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID or gmcp.room.info.num
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_id   = getRoomArea(current_room)
    local area_name = getRoomAreaName(area_id)
    local circuit_data = f2t_map_circuit_load(area_name, circuit_id)
    if not circuit_data then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found in %s\n", circuit_id, area_name)); return
    end
    for _, stop in ipairs(circuit_data.stops) do
        if stop.name == stop_name then
            cecho(string.format("\n<red>[map]<reset> Stop '%s' already exists in circuit\n", stop_name)); return
        end
    end
    local hash = f2t_map_generate_hash_from_room(current_room)
    if not hash then
        cecho(string.format("\n<red>[map]<reset> Could not generate hash for room %d\n", current_room)); return
    end
    table.insert(circuit_data.stops, {name=stop_name, hash=hash, arrival_pattern=stop_name})
    f2t_map_circuit_mark_stop(current_room, circuit_id, stop_name)
    if f2t_map_circuit_save(area_name, circuit_id, circuit_data) then
        cecho(string.format("\n<green>[map]<reset> Added stop '%s' (hash: %s, room: %d) to circuit '%s'\n",
            stop_name, hash, current_room, circuit_id))
    end
end

function f2t_map_circuit_cmd_stop_set(circuit_id, stop_name, property, value)
    if not circuit_id or not stop_name or not property or not value then
        cecho("\n<red>[map]<reset> Usage: map special circuit stop set <circuit_id> <stop_name> <property> <value>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_name = getRoomAreaName(getRoomArea(current_room))
    local circuit_data = f2t_map_circuit_load(area_name, circuit_id)
    if not circuit_data then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found\n", circuit_id)); return
    end
    local stop = f2t_map_circuit_find_stop(circuit_data, stop_name)
    if not stop then
        cecho(string.format("\n<red>[map]<reset> Stop '%s' not found\n", stop_name)); return
    end
    if property == "arrival_pattern" then
        stop.arrival_pattern = value
    else
        cecho(string.format("\n<red>[map]<reset> Unknown property: %s\n", property)); return
    end
    if f2t_map_circuit_save(area_name, circuit_id, circuit_data) then
        cecho(string.format("\n<green>[map]<reset> Set %s.%s.%s = %s\n", circuit_id, stop_name, property, value))
    end
end

function f2t_map_circuit_cmd_connect(circuit_id)
    if not circuit_id or circuit_id == "" then
        cecho("\n<red>[map]<reset> Usage: map special circuit connect <circuit_id>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_name = getRoomAreaName(getRoomArea(current_room))
    local circuit_data = f2t_map_circuit_load(area_name, circuit_id)
    if not circuit_data then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found in %s\n", circuit_id, area_name)); return
    end
    if not circuit_data.stops or #circuit_data.stops < 2 then
        cecho(string.format("\n<red>[map]<reset> Circuit needs at least 2 stops (has %d)\n",
            #(circuit_data.stops or {}))); return
    end
    local connection_count = 0
    local stops = circuit_data.stops
    for i, from_stop in ipairs(stops) do
        local from_room = f2t_map_get_room_by_hash(from_stop.hash)
        if from_room then
            for j, to_stop in ipairs(stops) do
                if i ~= j then
                    local to_room = f2t_map_get_room_by_hash(to_stop.hash)
                    if to_room then
                        local command = string.format("__circuit:%s:%s", circuit_id, to_stop.name)
                        addSpecialExit(from_room, to_room, command)
                        addCustomLine(from_room, to_room, command, "dash line", color_table.grey, false)
                        connection_count = connection_count + 1
                    else
                        cecho(string.format("\n<yellow>[map]<reset> Warning: Stop '%s' not found in map, skipping\n", to_stop.name))
                    end
                end
            end
        else
            cecho(string.format("\n<yellow>[map]<reset> Warning: Stop '%s' not found in map, skipping\n", from_stop.name))
        end
    end
    cecho(string.format("\n<green>[map]<reset> Created %d circuit connections for '%s'\n", connection_count, circuit_id))
end

function f2t_map_circuit_cmd_list()
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_name = getRoomAreaName(getRoomArea(current_room))
    local circuits  = f2t_map_circuit_list(area_name)
    if #circuits == 0 then
        cecho(string.format("\n<yellow>[map]<reset> No circuits found in %s\n", area_name)); return
    end
    cecho(string.format("\n<green>[map]<reset> Circuits in %s:\n", area_name))
    for _, circuit_id in ipairs(circuits) do
        local cd = f2t_map_circuit_load(area_name, circuit_id)
        if cd then
            cecho(string.format("  <yellow>%s<reset> - %d stops, vehicle room %s\n",
                circuit_id, #(cd.stops or {}), tostring(cd.vehicle_room or "not set")))
        end
    end
end

function f2t_map_circuit_cmd_show(circuit_id)
    if not circuit_id or circuit_id == "" then
        cecho("\n<red>[map]<reset> Usage: map special circuit show <circuit_id>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_name = getRoomAreaName(getRoomArea(current_room))
    local cd = f2t_map_circuit_load(area_name, circuit_id)
    if not cd then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found in %s\n", circuit_id, area_name)); return
    end
    cecho(string.format("\n<green>[map]<reset> Circuit: <yellow>%s<reset>\n", circuit_id))
    cecho(string.format("  Area: %s\n  vehicle_room: %s\n  board_command: %s\n  exit_command: %s\n",
        area_name, tostring(cd.vehicle_room or "not set"), cd.board_command, cd.exit_command))
    cecho(string.format("  boarding_pattern: %s\n  is_loop: %s\n", cd.boarding_pattern or "none", tostring(cd.is_loop)))
    if cd.stops and #cd.stops > 0 then
        cecho(string.format("\n  <green>Stops (%d):<reset>\n", #cd.stops))
        for i, stop in ipairs(cd.stops) do
            local room_id = f2t_map_get_room_by_hash(stop.hash)
            cecho(string.format("    %d. <yellow>%s<reset> (hash: %s, %s)\n",
                i, stop.name, stop.hash, room_id and string.format("room %d", room_id) or "not mapped"))
            cecho(string.format("       arrival_pattern: %s\n", stop.arrival_pattern))
        end
    else
        cecho("\n  <yellow>No stops defined<reset>\n")
    end
end

function f2t_map_circuit_cmd_delete(circuit_id)
    if not circuit_id or circuit_id == "" then
        cecho("\n<red>[map]<reset> Usage: map special circuit delete <circuit_id>\n"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map]<reset> Cannot determine current location\n"); return end
    local area_name = getRoomAreaName(getRoomArea(current_room))
    local cd = f2t_map_circuit_load(area_name, circuit_id)
    if not cd then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found in %s\n", circuit_id, area_name)); return
    end
    if cd.stops then
        for _, stop in ipairs(cd.stops) do
            local stop_room = f2t_map_get_room_by_hash(stop.hash)
            if stop_room then
                local special_exits = getSpecialExits(stop_room)
                if special_exits then
                    for cmd, to_room in pairs(special_exits) do
                        if cmd:match("^__circuit:" .. circuit_id .. ":") then
                            removeSpecialExit(stop_room, cmd)
                            removeCustomLine(stop_room, to_room)
                        end
                    end
                end
                f2t_map_circuit_unmark_stop(stop_room)
            end
        end
    end
    if f2t_map_circuit_delete(area_name, circuit_id) then
        cecho(string.format("\n<green>[map]<reset> Deleted circuit '%s' and removed all connections\n", circuit_id))
    else
        cecho(string.format("\n<red>[map]<reset> Failed to delete circuit '%s'\n", circuit_id))
    end
end
