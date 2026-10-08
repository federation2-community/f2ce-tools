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

-- A game room that moves you on as you enter (Hydrostatic's room 1 sends you
-- to its Main Terminal) is never shown, so exits naming it can't be matched by
-- number. Once one is walked, the area remembers where that number really
-- lands, and every exit naming it is mapped there too.
local function arrival_key(fed2_num)
    return "fed2_arrives_" .. fed2_num
end

local function listed_destination(room_id, direction)
    local dir_num = f2t_map_direction_to_number(direction)
    local exits_data = getRoomUserData(room_id, "fed2_exits")
    if not dir_num or not exits_data then return nil end
    for dir, num in string.gmatch(exits_data, "([^,:]+):(%d+)") do
        if f2t_map_direction_to_number(dir) == dir_num then return tonumber(num) end
    end
    return nil
end

local function arrival_room(area_id, fed2_num)
    local hash = getAreaUserData(area_id, arrival_key(fed2_num))
    if not hash or hash == "" then return nil end
    return f2t_map_get_room_by_hash(hash)
end

local function connect_stubs_listing(area_id, fed2_num, dest_room_id)
    local fed2_num_str = tostring(fed2_num)
    for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
        local stubs = getExitStubs(room_id)
        local exits_data = stubs and next(stubs) ~= nil and getRoomUserData(room_id, "fed2_exits")
        if exits_data and exits_data ~= "" then
            for dir, num in string.gmatch(exits_data, "([^,:]+):(%d+)") do
                if num == fed2_num_str and has_stub_in_direction(room_id, dir) then
                    local dir_num = f2t_map_direction_to_number(dir)
                    setExit(room_id, dest_room_id, dir_num)
                    setExitStub(room_id, dir_num, false)
                end
            end
        end
    end
end

function f2t_map_note_arrival(from_room_id, arrived_room_id, direction)
    if not from_room_id or not arrived_room_id or not direction then return end
    local area_id = getRoomArea(from_room_id)
    if not area_id or area_id ~= getRoomArea(arrived_room_id) then return end
    local listed = listed_destination(from_room_id, direction)
    if not listed or listed == tonumber(getRoomUserData(arrived_room_id, "fed2_num")) then return end
    local listed_hash = string.format("%s.%s.%d", getRoomUserData(from_room_id, "fed2_system"),
        getRoomUserData(from_room_id, "fed2_area"), listed)
    if f2t_map_get_room_by_hash(listed_hash) then return end
    local arrived_hash = f2t_map_generate_hash_from_room(arrived_room_id)
    if not arrived_hash then return end
    if getAreaUserData(area_id, arrival_key(listed)) ~= arrived_hash then
        setAreaUserData(area_id, arrival_key(listed), arrived_hash)
        f2t_debug_log("[map] Room %d on this planet lands in %s", listed, arrived_hash)
    end
    connect_stubs_listing(area_id, listed, arrived_room_id)
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
            -- A mapped exit can lead somewhere other than the room the game
            -- names (a room that moves you on as you enter): leave it be
            if not get_existing_exit(current_room_id, direction) then
                local area_id = getRoomArea(current_room_id)
                local lands_in = area_id and arrival_room(area_id, fed2_num)
                local dir_num = f2t_map_direction_to_number(direction)
                if lands_in then
                    setExit(current_room_id, lands_in, dir_num)
                    setExitStub(current_room_id, dir_num, false)
                elseif not has_stub_in_direction(current_room_id, direction) then
                    setExitStub(current_room_id, dir_num, true)
                end
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
    f2t_map_note_arrival(prev_room_id, current_room_id, direction)
end

function f2t_map_connect_incoming_stubs(room_id, fed2_num)
    if not room_id or not fed2_num then return end
    local area_id = getRoomArea(room_id)
    if not area_id then return end
    local fed2_num_str = tostring(fed2_num)
    for _, other_room_id in ipairs(f2t_map_area_room_list(area_id)) do
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
                    -- Landing from orbit always sets you down on the planet's
                    -- landing pad, so this stub is that room. Flagging it now
                    -- is what lets "nav <planet>" resolve and reach it without
                    -- anyone having walked the surface first.
                    local dest_data = {system=dest_system, area=dest_area, num=dest_num,
                                       name=string.format("%s (via board)", dest_area),
                                       flags={"shuttlepad"}}
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

