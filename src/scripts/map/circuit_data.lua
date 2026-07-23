-- f2ce-tools map — circuit data storage (ported from map_circuit_data.lua)

function f2t_map_circuit_save(area_name, circuit_id, circuit_data)
    if not area_name or not circuit_id or not circuit_data then return false end
    local area_id = f2t_map_get_area_id(area_name)
    if not area_id then return false end
    setAreaUserData(area_id, string.format("f2t_circuit_%s", circuit_id), yajl.to_string(circuit_data))
    return true
end

function f2t_map_circuit_load(area_name, circuit_id)
    if not area_name or not circuit_id then return nil end
    local area_id = f2t_map_get_area_id(area_name)
    if not area_id then return nil end
    local json = getAreaUserData(area_id, string.format("f2t_circuit_%s", circuit_id))
    if not json or json == "" then return nil end
    return yajl.to_value(json)
end

function f2t_map_circuit_delete(area_name, circuit_id)
    if not area_name or not circuit_id then return false end
    local area_id = f2t_map_get_area_id(area_name)
    if not area_id then return false end
    setAreaUserData(area_id, string.format("f2t_circuit_%s", circuit_id), "")
    return true
end

function f2t_map_circuit_list(area_name)
    if not area_name then return {} end
    local area_id = f2t_map_get_area_id(area_name)
    if not area_id then return {} end
    local all_data = getAllAreaUserData(area_id)
    local circuits = {}
    if all_data then
        for key, _ in pairs(all_data) do
            if key:match("^f2t_circuit_") then
                table.insert(circuits, key:gsub("^f2t_circuit_", ""))
            end
        end
    end
    return circuits
end

function f2t_map_circuit_mark_stop(room_id, circuit_id, stop_name)
    if not room_id or not circuit_id or not stop_name then return false end
    setRoomUserData(room_id, "f2t_circuit_stop", string.format("%s:%s", circuit_id, stop_name))
    return true
end

function f2t_map_circuit_get_stop(room_id)
    if not room_id then return nil end
    local marker = getRoomUserData(room_id, "f2t_circuit_stop")
    if not marker or marker == "" then return nil end
    return marker:match("^([^:]+):(.+)$")
end

function f2t_map_circuit_unmark_stop(room_id)
    if not room_id then return false end
    setRoomUserData(room_id, "f2t_circuit_stop", "")
    return true
end

function f2t_map_circuit_get_vehicle_room(area_name, circuit_id)
    local circuit = f2t_map_circuit_load(area_name, circuit_id)
    if not circuit then return nil end
    return circuit.vehicle_room
end

function f2t_map_circuit_find_stop(circuit_data, stop_name)
    if not circuit_data or not circuit_data.stops then return nil end
    for _, stop in ipairs(circuit_data.stops) do
        if stop.name == stop_name then return stop end
    end
    return nil
end

function f2t_map_circuit_get_stop_index(circuit_data, stop_name)
    if not circuit_data or not circuit_data.stops then return nil end
    for i, stop in ipairs(circuit_data.stops) do
        if stop.name == stop_name then return i end
    end
    return nil
end

function f2t_map_circuit_is_loop(circuit_data)
    if not circuit_data then return false end
    return circuit_data.is_loop == true
end
