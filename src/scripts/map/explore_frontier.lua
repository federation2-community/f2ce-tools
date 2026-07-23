-- f2ce-tools map — exploration frontier management (ported from map_explore_frontier.lua)

local DIRECTION_COMMANDS = {
    [1]="n",[2]="ne",[3]="nw",[4]="e",[5]="w",[6]="s",[7]="se",[8]="sw",
    [9]="u",[10]="d",[11]="in",[12]="out",
}

function f2t_map_explore_direction_number_to_name(dir_num)
    return DIRECTION_COMMANDS[dir_num]
end

function f2t_map_explore_is_exit_valid(room_id, direction)
    if hasExitLock(room_id, direction) then return false end
    local exits = getRoomExits(room_id)
    if not exits then return true end
    local dest_id = exits[direction]
    if not dest_id then return true end
    if roomLocked(dest_id) then return false end
    if F2T_MAP_EXPLORE_STATE.visited_rooms[dest_id] then return false end
    return true
end

function f2t_map_explore_add_room_to_frontier(room_id)
    local stubs = getExitStubs(room_id)
    if not stubs then return 0 end
    local added_count = 0
    for _, stub_dir_num in pairs(stubs) do
        local direction = f2t_map_explore_direction_number_to_name(stub_dir_num)
        if direction and f2t_map_explore_is_exit_valid(room_id, direction) then
            table.insert(F2T_MAP_EXPLORE_STATE.frontier_stack, {room_id=room_id, direction=direction})
            added_count = added_count + 1
        end
    end
    return added_count
end

function f2t_map_explore_remove_from_frontier(room_id)
    local new_frontier = {}
    local removed_count = 0
    for _, exit in ipairs(F2T_MAP_EXPLORE_STATE.frontier_stack) do
        if exit.room_id == room_id then removed_count = removed_count + 1
        else table.insert(new_frontier, exit)
        end
    end
    F2T_MAP_EXPLORE_STATE.frontier_stack = new_frontier
    return removed_count
end

function f2t_map_explore_get_exit_destination(room_id, direction)
    local exits = getRoomExits(room_id)
    if not exits then return nil end
    return exits[direction]
end

function f2t_map_explore_has_frontier()
    return #F2T_MAP_EXPLORE_STATE.frontier_stack > 0
end

function f2t_map_explore_pop_frontier()
    if #F2T_MAP_EXPLORE_STATE.frontier_stack == 0 then return nil end
    return table.remove(F2T_MAP_EXPLORE_STATE.frontier_stack)
end

function f2t_map_explore_frontier_size()
    return #F2T_MAP_EXPLORE_STATE.frontier_stack
end

function f2t_map_explore_recompute_frontier()
    local area_id      = F2T_MAP_EXPLORE_STATE.starting_area_id
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not area_id or not current_room then return end

    local is_brief       = F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count ~= nil
    local reference_room = is_brief and F2T_MAP_EXPLORE_STATE.starting_room_id or current_room

    local candidates = {}
    local rooms_in_area = getAreaRooms(area_id)
    if not rooms_in_area then F2T_MAP_EXPLORE_STATE.frontier_stack = {}; return end

    for _, room_id in pairs(rooms_in_area) do
        local stubs = getExitStubs(room_id)
        if stubs then
            for _, stub_dir_num in pairs(stubs) do
                local direction = f2t_map_explore_direction_number_to_name(stub_dir_num)
                if direction and f2t_map_explore_is_exit_valid(room_id, direction) then
                    local success, weight = getPath(reference_room, room_id)
                    if success then
                        table.insert(candidates, {room_id=room_id, direction=direction, distance=weight})
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.distance < b.distance end)

    if is_brief and reference_room == F2T_MAP_EXPLORE_STATE.starting_room_id then
        local seeking_exchange = F2T_MAP_EXPLORE_STATE.brief_flags_set and F2T_MAP_EXPLORE_STATE.brief_flags_set["exchange"]
        if seeking_exchange and #candidates > 0 then
            local direction_priority = {"e","n","sw","w","s","ne","nw","se","in","u","d","out"}
            local grouped = {}
            for _, dir in ipairs(direction_priority) do grouped[dir] = {} end
            for _, candidate in ipairs(candidates) do
                local dir = candidate.direction
                if grouped[dir] then table.insert(grouped[dir], candidate)
                else
                    if not grouped["other"] then grouped["other"] = {} end
                    table.insert(grouped["other"], candidate)
                end
            end
            candidates = {}
            for _, dir in ipairs(direction_priority) do
                for _, candidate in ipairs(grouped[dir]) do table.insert(candidates, candidate) end
            end
            if grouped["other"] then
                for _, candidate in ipairs(grouped["other"]) do table.insert(candidates, candidate) end
            end
        end
    end

    F2T_MAP_EXPLORE_STATE.frontier_stack = {}
    for i = 1, #candidates do
        table.insert(F2T_MAP_EXPLORE_STATE.frontier_stack, {room_id=candidates[i].room_id, direction=candidates[i].direction})
    end
    f2t_debug_log("[map-explore] Frontier recomputed: %d stub(s) remaining", #F2T_MAP_EXPLORE_STATE.frontier_stack)
end

f2t_debug_log("[map] Loaded explore_frontier.lua")
