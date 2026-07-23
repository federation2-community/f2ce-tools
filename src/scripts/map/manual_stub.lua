-- f2ce-tools map — stub exit management (ported from map_manual_stub.lua)

local DIRECTION_NUMBERS = {
    [1]="north",[2]="northeast",[3]="northwest",[4]="east",[5]="west",[6]="south",
    [7]="southeast",[8]="southwest",[9]="up",[10]="down",[11]="in",[12]="out",
}

local function direction_number_to_name(dir_num)
    return DIRECTION_NUMBERS[dir_num]
end

function f2t_map_manual_create_stub(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end
    direction = string.lower(direction)
    local existing_stubs = getExitStubs1(room_id)
    if existing_stubs then
        for _, stub_dir_num in pairs(existing_stubs) do
            if direction_number_to_name(stub_dir_num) == direction then
                cecho(string.format("\n<yellow>[map]<reset> Stub exit '%s' already exists in room %d\n", direction, room_id))
                return true
            end
        end
    end
    local exits = getRoomExits(room_id)
    if exits and exits[direction] then
        cecho(string.format("\n<red>[map]<reset> Regular exit '%s' already exists in room %d\n", direction, room_id))
        return false
    end
    setExitStub(room_id, direction, true)
    local room_name = getRoomName(room_id) or "unnamed"
    cecho(string.format("\n<green>[map]<reset> Stub exit created: <white>%s<reset> --%s--> <yellow>(stub)<reset>\n", room_name, direction))
    return true
end

function f2t_map_manual_delete_stub(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end
    direction = string.lower(direction)
    local existing_stubs = getExitStubs1(room_id)
    local stub_exists = false
    if existing_stubs then
        for _, stub_dir_num in pairs(existing_stubs) do
            if direction_number_to_name(stub_dir_num) == direction then stub_exists = true; break end
        end
    end
    if not stub_exists then
        cecho(string.format("\n<yellow>[map]<reset> No stub exit '%s' in room %d\n", direction, room_id)); return false
    end
    setExitStub(room_id, direction, false)
    cecho(string.format("\n<green>[map]<reset> Stub exit deleted: <white>%s<reset> --%s--> <dim_grey>(removed)<reset>\n",
        getRoomName(room_id) or "unnamed", direction))
    return true
end

function f2t_map_manual_connect_stub(room_id, direction)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return false
    end
    if not direction or direction == "" then cecho("\n<red>[map]<reset> Direction required\n"); return false end
    direction = string.lower(direction)
    local existing_stubs = getExitStubs1(room_id)
    local stub_exists = false
    if existing_stubs then
        for _, stub_dir_num in pairs(existing_stubs) do
            if direction_number_to_name(stub_dir_num) == direction then stub_exists = true; break end
        end
    end
    if not stub_exists then
        cecho(string.format("\n<red>[map]<reset> No stub exit '%s' in room %d\n", direction, room_id)); return false
    end
    local dir_num = f2t_map_direction_to_number(direction)
    local success = connectExitStub(room_id, dir_num)
    if success then
        local exits = getRoomExits(room_id)
        local dest_room = exits and exits[direction]
        if dest_room then
            cecho(string.format("\n<green>[map]<reset> Stub exit connected: <white>%s<reset> --%s--> <white>%s<reset>\n",
                getRoomName(room_id) or "unnamed", direction, getRoomName(dest_room) or "unnamed"))
        else
            cecho(string.format("\n<green>[map]<reset> Stub exit '%s' in room %d connected\n", direction, room_id))
        end
        return true
    else
        cecho(string.format("\n<red>[map]<reset> Failed to connect stub exit '%s' in room %d\n", direction, room_id))
        cecho("\n<dim_grey>Ensure destination room has opposite stub exit<reset>\n")
        return false
    end
end

function f2t_map_manual_list_stubs(room_id)
    room_id = room_id or F2T_MAP_CURRENT_ROOM_ID
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    cecho(string.format("\n<green>[map]<reset> Stub exits for room %d (<white>%s<reset>):\n",
        room_id, getRoomName(room_id) or "unnamed"))
    local stubs = getExitStubs1(room_id)
    if stubs and next(stubs) ~= nil then
        for _, stub_dir_num in pairs(stubs) do
            local stub_dir = direction_number_to_name(stub_dir_num)
            if stub_dir then
                cecho(string.format("  <yellow>%-10s<reset> <dim_grey>(stub exit, not connected)<reset>\n", stub_dir))
            else
                cecho(string.format("  <yellow>%-10s<reset> <dim_grey>(unknown direction: %d)<reset>\n", "???", stub_dir_num))
            end
        end
        cecho(string.format("\n<dim_grey>Use 'map exit stub connect %d <direction>' to connect stubs<reset>\n", room_id))
    else
        cecho("\n<dim_grey>No stub exits in this room<reset>\n")
    end
    cecho("\n")
end
