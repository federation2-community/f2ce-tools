-- f2ce-tools map — BFS flag finder for exploration (ported from map_explore_bfs.lua)

function f2t_map_explore_bfs_find_flag(starting_room_id, target_flag, max_depth)
    max_depth = max_depth or 20
    local queue   = {{room_id = starting_room_id, depth = 0}}
    local visited = {[starting_room_id] = true}
    local rooms_checked = 0

    while #queue > 0 do
        local current = table.remove(queue, 1)
        rooms_checked = rooms_checked + 1
        if current.depth >= max_depth then break end

        if getRoomUserData(current.room_id, string.format("fed2_flag_%s", target_flag)) == "true" then
            return current.room_id
        end

        local stubs = getExitStubs(current.room_id)
        if stubs then
            for _, stub_dir_num in pairs(stubs) do
                local direction = f2t_map_explore_direction_number_to_name(stub_dir_num)
                if direction and f2t_map_explore_is_exit_valid(current.room_id, direction) then
                    local dest_id = f2t_map_explore_get_exit_destination(current.room_id, direction)
                    if dest_id and not visited[dest_id] then
                        visited[dest_id] = true
                        table.insert(queue, {room_id = dest_id, depth = current.depth + 1})
                    end
                end
            end
        end
    end

    return nil
end

f2t_debug_log("[map] Loaded explore_bfs.lua")
