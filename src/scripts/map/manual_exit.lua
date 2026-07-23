-- f2ce-tools map — manual exit management (ported from map_manual_exit.lua)

function f2t_map_manual_add_exit(from_room, to_room, direction, bidirectional)
    if not from_room or not roomExists(from_room) then
        cecho(string.format("\n<red>[map]<reset> Source room %s does not exist\n", tostring(from_room))); return false
    end
    if not to_room or not roomExists(to_room) then
        cecho(string.format("\n<red>[map]<reset> Destination room %s does not exist\n", tostring(to_room))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end

    local valid_directions = {"north","south","east","west","northeast","northwest","southeast","southwest","up","down","in","out"}
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
    cecho(string.format("\n<green>[map]<reset> Exit created: <white>%s<reset> --%s--> <white>%s<reset>\n", from_name, direction, to_name))

    if bidirectional then
        local reverse_dir = reverse_dir_map[direction]
        if reverse_dir then
            setExit(to_room, from_room, reverse_dir)
            cecho(string.format("<green>[map]<reset> Reverse exit created: <white>%s<reset> --%s--> <white>%s<reset>\n", to_name, reverse_dir, from_name))
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
                cecho(string.format("\n<red>[map]<reset> Exit '%s' no longer exists in room %d\n", data.direction, data.room_id)); return
            end
            setExitStub(data.room_id, data.direction, 0)
            cecho(string.format("\n<green>[map]<reset> Exit removed: <white>%s<reset> (%s)\n", data.direction, data.description))
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
                cecho(string.format("    <magenta>%-30s<reset> <dim_grey>(auto-transit)<reset> -> <white>%s<reset> <dim_grey>[%d | %s]<reset>\n",
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
