-- f2ce-tools map — circuit movement state machine (ported from map_circuit_movement.lua)

F2T_MAP_CIRCUIT_STATE = {
    active = false, circuit_id = nil, area_name = nil, vehicle_room = nil,
    destination_stop = nil, destination_room = nil, destination_pattern = nil,
    board_command = nil, exit_command = nil, boarding_pattern = nil,
    phase = nil, boarding_trigger_id = nil, arrival_trigger_id = nil,
}

function f2t_map_circuit_create_boarding_trigger()
    if not F2T_MAP_CIRCUIT_STATE.active then return end
    if F2T_MAP_CIRCUIT_STATE.boarding_pattern then
        F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = tempRegexTrigger(
            F2T_MAP_CIRCUIT_STATE.boarding_pattern,
            function() f2t_map_circuit_handle_boarding() end)
    else
        F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = tempRegexTrigger(
            "^A canned voice announces",
            function() f2t_map_circuit_handle_boarding() end)
    end
end

function f2t_map_circuit_create_arrival_trigger()
    if not F2T_MAP_CIRCUIT_STATE.active then return end
    F2T_MAP_CIRCUIT_STATE.arrival_trigger_id = tempRegexTrigger(
        F2T_MAP_CIRCUIT_STATE.destination_pattern,
        function() f2t_map_circuit_handle_arrival() end)
end

function f2t_map_circuit_delete_triggers()
    if F2T_MAP_CIRCUIT_STATE.boarding_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.boarding_trigger_id)
        F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = nil
    end
    if F2T_MAP_CIRCUIT_STATE.arrival_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.arrival_trigger_id)
        F2T_MAP_CIRCUIT_STATE.arrival_trigger_id = nil
    end
end

function f2t_map_circuit_begin(circuit_command)
    local circuit_id, dest_stop = circuit_command:match("^__circuit:([^:]+):(.+)$")
    if not circuit_id or not dest_stop then
        cecho("\n<red>[map]<reset> Invalid circuit command format\n"); return false
    end
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    local area_id   = getRoomArea(current_room_id)
    local area_name = getRoomAreaName(area_id)
    local circuit_data = f2t_map_circuit_load(area_name, circuit_id)
    if not circuit_data then
        cecho(string.format("\n<red>[map]<reset> Circuit '%s' not found\n", circuit_id)); return false
    end
    local dest_stop_data = f2t_map_circuit_find_stop(circuit_data, dest_stop)
    if not dest_stop_data then
        cecho(string.format("\n<red>[map]<reset> Stop '%s' not found in circuit\n", dest_stop)); return false
    end
    local dest_room_id = f2t_map_get_room_by_hash(dest_stop_data.hash)
    if not dest_room_id then
        cecho(string.format("\n<red>[map]<reset> Stop '%s' (hash %s) not found in map\n",
            dest_stop, dest_stop_data.hash)); return false
    end
    F2T_MAP_CIRCUIT_STATE = {
        active = true, circuit_id = circuit_id, area_name = area_name,
        vehicle_room = circuit_data.vehicle_room,
        destination_stop = dest_stop, destination_room = dest_room_id,
        destination_pattern = dest_stop_data.arrival_pattern,
        board_command = circuit_data.board_command or "in",
        exit_command  = circuit_data.exit_command  or "out",
        boarding_pattern = circuit_data.boarding_pattern,
        phase = "waiting_arrival",
        boarding_trigger_id = nil, arrival_trigger_id = nil,
    }
    f2t_map_circuit_create_boarding_trigger()
    cecho(string.format("\n<green>[map]<reset> Waiting for circuit to %s...\n", dest_stop))
    return true
end

function f2t_map_circuit_handle_boarding(skip_send)
    if not F2T_MAP_CIRCUIT_STATE.active then return end
    if F2T_MAP_CIRCUIT_STATE.phase ~= "waiting_arrival" then return end
    if F2T_MAP_CIRCUIT_STATE.boarding_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.boarding_trigger_id)
        F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = nil
    end
    if not skip_send then send(F2T_MAP_CIRCUIT_STATE.board_command) end
    F2T_MAP_CIRCUIT_STATE.phase = "waiting_destination"
    cecho(string.format("\n<green>[map]<reset> Riding circuit to %s...\n", F2T_MAP_CIRCUIT_STATE.destination_stop))
    tempTimer(0.5, function()
        if F2T_MAP_CIRCUIT_STATE.active and F2T_MAP_CIRCUIT_STATE.phase == "waiting_destination" then
            f2t_map_circuit_create_arrival_trigger()
        end
    end)
end

function f2t_map_circuit_handle_arrival()
    if not F2T_MAP_CIRCUIT_STATE.active then return end
    if F2T_MAP_CIRCUIT_STATE.phase ~= "waiting_destination" then return end
    if F2T_MAP_CIRCUIT_STATE.arrival_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.arrival_trigger_id)
        F2T_MAP_CIRCUIT_STATE.arrival_trigger_id = nil
    end
    send(F2T_MAP_CIRCUIT_STATE.exit_command)
    tempTimer(0.5, function() f2t_map_circuit_verify_and_resume() end)
end

function f2t_map_circuit_verify_and_resume()
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room == F2T_MAP_CIRCUIT_STATE.destination_room then
        cecho(string.format("\n<green>[map]<reset> Arrived at %s\n", F2T_MAP_CIRCUIT_STATE.destination_stop))
        f2t_map_circuit_delete_triggers()
        F2T_MAP_CIRCUIT_STATE = {active = false}
        f2t_map_speedwalk_on_room_change()
    else
        cecho(string.format("\n<red>[map]<reset> Error: Expected room %d, but in room %d\n",
            F2T_MAP_CIRCUIT_STATE.destination_room, current_room))
        f2t_map_circuit_delete_triggers()
        F2T_MAP_CIRCUIT_STATE = {active = false}
        f2t_map_speedwalk_stop()
    end
end

function f2t_map_circuit_stop()
    if not F2T_MAP_CIRCUIT_STATE.active then
        cecho("\n<yellow>[map]<reset> No active circuit travel\n"); return
    end
    cecho("\n<yellow>[map]<reset> Circuit travel stopped\n")
    f2t_map_circuit_delete_triggers()
    F2T_MAP_CIRCUIT_STATE = {active = false}
    f2t_map_speedwalk_stop()
end

function f2t_map_circuit_status()
    if not F2T_MAP_CIRCUIT_STATE.active then
        cecho("\n<yellow>[map]<reset> No active circuit travel\n"); return
    end
    cecho("\n<green>[map]<reset> Circuit Travel Status:\n")
    cecho(string.format("  Circuit: <yellow>%s<reset>\n", F2T_MAP_CIRCUIT_STATE.circuit_id))
    cecho(string.format("  Destination: <yellow>%s<reset> (room %d)\n",
        F2T_MAP_CIRCUIT_STATE.destination_stop, F2T_MAP_CIRCUIT_STATE.destination_room))
    cecho(string.format("  Phase: <yellow>%s<reset>\n", F2T_MAP_CIRCUIT_STATE.phase))
end
