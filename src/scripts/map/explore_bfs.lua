-- f2ce-tools map — BFS flag finder for exploration (ported from map_explore_bfs.lua)

-- Nearest room carrying `target_flag`, breadth-first from a starting room over
-- exits that actually lead somewhere. Confined to the starting room's area, so
-- a planet-level search cannot leave through a link room's "jump" special exit
-- and find the flag in another system.
function f2t_map_explore_bfs_find_flag(starting_room_id, target_flag, max_depth)
    max_depth = max_depth or 20
    local area_id  = getRoomArea(starting_room_id)
    local flag_key = string.format("fed2_flag_%s", target_flag)
    local queue    = {{room_id = starting_room_id, depth = 0}}
    local visited  = {[starting_room_id] = true}
    local head     = 1

    while head <= #queue do
        local current = queue[head]
        head = head + 1

        if getRoomUserData(current.room_id, flag_key) == "true" then
            return current.room_id
        end

        if current.depth < max_depth then
            local function visit(dest_id)
                if type(dest_id) == "number" and dest_id > 0 and not visited[dest_id]
                    and not roomLocked(dest_id) and getRoomArea(dest_id) == area_id then
                    visited[dest_id] = true
                    queue[#queue + 1] = {room_id = dest_id, depth = current.depth + 1}
                end
            end
            -- getRoomExits() is {[direction] = destRoomId}; getSpecialExits()
            -- is the opposite shape, {[destRoomId] = {command = true, ...}}.
            for direction, dest_id in pairs(getRoomExits(current.room_id) or {}) do
                if not hasExitLock(current.room_id, direction) then visit(dest_id) end
            end
            for dest_id in pairs(getSpecialExits(current.room_id) or {}) do
                visit(dest_id)
            end
        end
    end

    return nil
end

f2t_debug_log("[map] Loaded explore_bfs.lua")
