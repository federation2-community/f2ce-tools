-- f2ce-tools map — map-specific argument parsing (ported from map_arg_parser.lua)

function f2t_map_parse_optional_room_id(words, index)
    if not words[index] then return F2T_MAP_CURRENT_ROOM_ID, false end
    local room_id = tonumber(words[index])
    if room_id then return room_id, false end
    local potential_hash = f2t_parse_rest(words, index)
    if potential_hash:match("^[^%.]+%.[^%.]+%.%d+$") then
        room_id = getRoomIDbyHash(potential_hash)
        if room_id and room_id > 0 then return room_id, false end
        cecho(string.format("\n<red>[map]<reset> Room with hash '%s' not found in map\n", potential_hash))
        return nil, true
    end
    cecho(string.format("\n<red>[map]<reset> '%s' is not a valid room ID or Fed2 hash\n", potential_hash))
    return nil, true
end

function f2t_map_parse_optional_room_and_arg(words, start_index)
    if not words[start_index] then return nil, nil, false end
    local potential_room = tonumber(words[start_index])
    if potential_room then
        if words[start_index + 1] then
            return potential_room, words[start_index + 1], true
        else
            return nil, nil, false
        end
    end
    return F2T_MAP_CURRENT_ROOM_ID, words[start_index], true
end

function f2t_map_parse_optional_room_and_args(words, start_index, arg_count)
    local total_with_room    = start_index + arg_count
    local total_without_room = start_index + arg_count - 1
    if #words >= total_with_room then
        local room_id = tonumber(words[start_index])
        if room_id then
            local args = {}
            for i = 1, arg_count do table.insert(args, words[start_index + i]) end
            return room_id, args, true
        end
    end
    if #words >= total_without_room then
        local args = {}
        for i = 0, arg_count - 1 do table.insert(args, words[start_index + i]) end
        return F2T_MAP_CURRENT_ROOM_ID, args, true
    end
    return nil, nil, false
end

function f2t_map_ensure_current_room(args)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room or not roomExists(current_room) then
        cecho("\n<yellow>[map]<reset> No current room detected. Refreshing location data...\n")
        send("look")
        local original_command = string.format("map %s", args)
        tempTimer(0.5, function()
            current_room = F2T_MAP_CURRENT_ROOM_ID
            if not current_room or not roomExists(current_room) then
                cecho("\n<red>[map]<reset> Error: Still no current room. Are you connected and mapped?\n")
                cecho("\n<dim_grey>Try running 'map sync' to force synchronization.<reset>\n")
            else
                cecho("\n<green>[map]<reset> Location refreshed. Retrying command...\n")
                expandAlias(original_command)
            end
        end)
        return nil
    end
    return current_room
end
