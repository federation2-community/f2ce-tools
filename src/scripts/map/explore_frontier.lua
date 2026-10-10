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

function f2t_map_explore_recompute_frontier()
    local area_id      = F2T_MAP_EXPLORE_STATE.starting_area_id
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not area_id or not current_room then return end

    -- Nearest from where the player stands, so the sweep works outward from
    -- here instead of crossing the planet and back between neighbouring exits
    local reference_room = current_room

    local candidates = {}
    for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
        local directions = {}
        for _, stub_dir_num in pairs(getExitStubs(room_id) or {}) do
            local direction = f2t_map_explore_direction_number_to_name(stub_dir_num)
            if direction and f2t_map_explore_is_exit_valid(room_id, direction) then
                directions[#directions + 1] = direction
            end
        end
        -- One pathfind per room rather than one per stub: every stub in a room
        -- is the same distance away, and a four-stub room used to run the same
        -- Dijkstra four times.
        if #directions > 0 then
            local success, weight = getPath(reference_room, room_id)
            if success then
                for _, direction in ipairs(directions) do
                    table.insert(candidates, {room_id=room_id, direction=direction, distance=weight})
                end
            end
        end
    end

    -- Hunting an exchange, equally near exits go in the order exchanges most
    -- often lie from a landing pad; distance always comes first
    local seeking_exchange = F2T_MAP_EXPLORE_STATE.brief_flags_set
        and F2T_MAP_EXPLORE_STATE.brief_flags_set["exchange"]
    local rank = {}
    if seeking_exchange then
        for i, dir in ipairs({"e","n","sw","w","s","ne","nw","se","in","u","d","out"}) do rank[dir] = i end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return (rank[a.direction] or 99) < (rank[b.direction] or 99)
    end)

    F2T_MAP_EXPLORE_STATE.frontier_stack = {}
    for i = 1, #candidates do
        table.insert(F2T_MAP_EXPLORE_STATE.frontier_stack,
            {room_id=candidates[i].room_id, direction=candidates[i].direction})
    end
    f2t_debug_log("[map-explore] Frontier recomputed: %d stub(s) remaining", #F2T_MAP_EXPLORE_STATE.frontier_stack)
end

f2t_debug_log("[map] Loaded explore_frontier.lua")
