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

-- How many rooms out from where a brief sweep started (its landing pad) it
-- finishes first. What a brief sweep looks for, the exchange above all, is
-- nearly always within a few rooms of the pad.
local BRIEF_RING = 3

-- Exits in the order a sweep takes them. A full sweep visits everything, so
-- it always takes the nearest exit from where the player stands, which keeps
-- it from crossing back and forth. A brief sweep first finishes the ring
-- around its start, nearest to the start first, and only then goes down
-- branches nearest-first: a long branch it would otherwise follow to the end
-- usually holds nothing it is looking for, and can be a way in with no way back.
function f2t_map_explore_recompute_frontier()
    local area_id      = F2T_MAP_EXPLORE_STATE.starting_area_id
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not area_id or not current_room then return end

    local reference_room = current_room
    local start_room = F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count ~= nil
        and F2T_MAP_EXPLORE_STATE.starting_room_id or nil
    if start_room and not roomExists(start_room) then start_room = nil end

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
                -- An exit from a room fewer than BRIEF_RING steps from the start
                -- leads at most BRIEF_RING rooms out
                local ring
                if start_room then
                    local fromStart, startWeight = getPath(start_room, room_id)
                    if room_id == start_room then fromStart, startWeight = true, 0 end
                    if fromStart and startWeight < BRIEF_RING then ring = startWeight end
                end
                for _, direction in ipairs(directions) do
                    table.insert(candidates, {room_id=room_id, direction=direction, distance=weight, ring=ring})
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
        -- The ring around a brief sweep's start comes first, nearest the start first
        if (a.ring ~= nil) ~= (b.ring ~= nil) then return a.ring ~= nil end
        if a.ring and a.ring ~= b.ring then return a.ring < b.ring end
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
