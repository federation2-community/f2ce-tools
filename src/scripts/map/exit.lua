-- f2ce-tools map — exit handling (ported from map_exit.lua)

local DIR_EXPANSION_MAP = {
    n="north",s="south",e="east",w="west",
    ne="northeast",nw="northwest",se="southeast",sw="southwest",
    u="up",d="down",
}

local function get_existing_exit(room_id, direction)
    local exits = getRoomExits(room_id)
    local existing = exits[direction]
    if not existing then
        local expanded = DIR_EXPANSION_MAP[direction]
        if expanded then existing = exits[expanded] end
    end
    return existing
end

local function has_stub_in_direction(room_id, direction)
    local stubs = getExitStubs(room_id)
    local direction_num = f2t_map_direction_to_number(direction)
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == direction_num then return true end
    end
    return false
end

function f2t_map_process_exits(current_room_id, gmcp_exits, gmcp_room_data)
    if not current_room_id or not roomExists(current_room_id) then return end
    if not gmcp_exits then return end

    local current_exits = getRoomExits(current_room_id)
    local seen_directions = {}

    for direction, fed2_num in pairs(gmcp_exits) do
        seen_directions[direction] = true
        local dest_hash = string.format("%s.%s.%d", gmcp_room_data.system, gmcp_room_data.area, fed2_num)
        local dest_room_id = f2t_map_get_room_by_hash(dest_hash)

        if dest_room_id then
            local existing_exit = get_existing_exit(current_room_id, direction)
            if existing_exit ~= dest_room_id then
                local opposite_dir = f2t_map_get_opposite_direction(direction)
                if opposite_dir then
                    local dest_existing_exit = get_existing_exit(dest_room_id, opposite_dir)
                    if not dest_existing_exit or dest_existing_exit ~= current_room_id then
                        local dest_has_stub = has_stub_in_direction(dest_room_id, opposite_dir)
                        local dest_should_have_exit = false
                        local dest_exits_data = getRoomUserData(dest_room_id, "fed2_exits")
                        if dest_exits_data then
                            local our_fed2_num = gmcp_room_data.num
                            for dir_num_pair in string.gmatch(dest_exits_data, "[^,]+") do
                                local dir, num = string.match(dir_num_pair, "([^:]+):(%d+)")
                                if dir == opposite_dir and num and tonumber(num) == our_fed2_num then
                                    dest_should_have_exit = true; break
                                end
                            end
                        end
                        if dest_has_stub then
                            local odn = f2t_map_direction_to_number(opposite_dir)
                            setExitStub(dest_room_id, odn, false)
                            setExit(dest_room_id, current_room_id, odn)
                        elseif dest_should_have_exit then
                            local odn = f2t_map_direction_to_number(opposite_dir)
                            setExit(dest_room_id, current_room_id, odn)
                        end
                    end
                end

                local dir_num = f2t_map_direction_to_number(direction)
                if has_stub_in_direction(current_room_id, direction) then
                    local success = connectExitStub(current_room_id, dir_num, dest_room_id)
                    if not success then
                        setExit(current_room_id, dest_room_id, dir_num)
                        setExitStub(current_room_id, dir_num, false)
                    end
                else
                    setExit(current_room_id, dest_room_id, dir_num)
                end
            end
        else
            if not has_stub_in_direction(current_room_id, direction) then
                setExitStub(current_room_id, f2t_map_direction_to_number(direction), true)
            end
        end
    end

    for direction in pairs(current_exits) do
        local normalized_dir = f2t_map_normalize_direction(direction)
        if not seen_directions[direction] and not seen_directions[normalized_dir] then
            setExit(current_room_id, -1, f2t_map_direction_to_number(direction))
        end
    end
end

function f2t_map_resolve_stub_exit(prev_room_id, current_room_id, direction)
    if not prev_room_id or not current_room_id or not direction then return end
    if not roomExists(prev_room_id) or not roomExists(current_room_id) then return end
    local dir_num = f2t_map_direction_to_number(direction)
    if not dir_num then return end
    local stubs = getExitStubs(prev_room_id)
    if not stubs then return end
    local has_stub = false
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == dir_num then has_stub = true; break end
    end
    if not has_stub then return end
    setExit(prev_room_id, current_room_id, dir_num)
    setExitStub(prev_room_id, dir_num, false)
end

function f2t_map_connect_incoming_stubs(room_id, fed2_num)
    if not room_id or not fed2_num then return end
    local area_id = getRoomArea(room_id)
    if not area_id then return end
    local area_rooms = getAreaRooms(area_id)
    if not area_rooms then return end
    local fed2_num_str = tostring(fed2_num)
    for _, other_room_id in pairs(area_rooms) do
        if other_room_id ~= room_id then
            local stubs = getExitStubs(other_room_id)
            if stubs and next(stubs) ~= nil then
                local exits_data = getRoomUserData(other_room_id, "fed2_exits")
                if exits_data and exits_data ~= "" then
                    for dir_num_pair in string.gmatch(exits_data, "[^,]+") do
                        local dir, num = string.match(dir_num_pair, "([^:]+):(%d+)")
                        if dir and num == fed2_num_str then
                            local dir_num = f2t_map_direction_to_number(dir)
                            if dir_num then
                                local has_stub = false
                                for _, stub_dir in pairs(stubs) do
                                    if stub_dir == dir_num then has_stub = true; break end
                                end
                                if has_stub then
                                    setExit(other_room_id, room_id, dir_num)
                                    setExitStub(other_room_id, dir_num, false)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function f2t_map_process_special_exits(current_room_id, gmcp_room_data)
    if not current_room_id or not roomExists(current_room_id) or not gmcp_room_data then return end
    if gmcp_room_data.flags then
        f2t_map_process_link_room(current_room_id, gmcp_room_data)
    end
    if gmcp_room_data.board or gmcp_room_data.orbit then
        local board_hash = gmcp_room_data.board or gmcp_room_data.orbit
        local dest_room_id = f2t_map_get_room_by_hash(board_hash)
        if not dest_room_id then
            local parts = {}
            for part in string.gmatch(board_hash, "[^.]+") do table.insert(parts, part) end
            if #parts == 3 then
                local dest_system = parts[1]
                local dest_area   = parts[2]
                local dest_num    = tonumber(parts[3])
                if dest_system and dest_area and dest_num then
                    local dest_data = {system=dest_system, area=dest_area, num=dest_num,
                                       name=string.format("%s (via board)", dest_area), flags={}}
                    local dest_area_id = f2t_map_get_or_create_area(dest_area, {system=dest_system})
                    if dest_area_id then
                        dest_room_id = f2t_map_create_room(dest_data, dest_area_id)
                        if dest_room_id then
                            local x, y, z = f2t_map_calculate_coords_from_room_num(dest_num)
                            f2t_map_set_room_coords(dest_room_id, x, y, z)
                            centerview(current_room_id)
                        end
                    end
                end
            end
        end
        if dest_room_id then
            removeSpecialExit(current_room_id, "board")
            addSpecialExit(current_room_id, dest_room_id, "board")
        end
    end
end

function f2t_map_get_exit(room_id, direction)
    if not room_id or not roomExists(room_id) then return nil end
    return getRoomExits(room_id)[direction]
end
