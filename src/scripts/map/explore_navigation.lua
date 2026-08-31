-- f2ce-tools map — exploration navigation (ported from map_explore_navigation.lua)

function f2t_map_explore_navigate_to_next()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local next_exit    = F2T_MAP_EXPLORE_STATE.planned_exit

    if next_exit then
        F2T_MAP_EXPLORE_STATE.planned_exit = nil
    else
        if #F2T_MAP_EXPLORE_STATE.frontier_stack > 0 then
            next_exit = table.remove(F2T_MAP_EXPLORE_STATE.frontier_stack, 1)
        end
    end

    if not next_exit then
        -- Exploration complete for this area
        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count and
           F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count > 0 then
            local planet_name = F2T_MAP_EXPLORE_STATE.brief_planet_name or "Unknown"
            local area_id = F2T_MAP_EXPLORE_STATE.starting_area_id
            local system_name = area_id and getAreaUserData(area_id, "fed2_system") or ""
            local is_sol = f2t_map_explore_is_sol(system_name)
            local missing_flags = {}
            for flag, _ in pairs(F2T_MAP_EXPLORE_STATE.brief_flags_set or {}) do
                local courier_exempt = flag == "courier" and not is_sol
                if not F2T_MAP_EXPLORE_STATE.brief_flags_found[flag] and not courier_exempt then
                    table.insert(missing_flags, flag)
                end
            end
            table.sort(missing_flags)
            if #missing_flags > 0 then
                local flags_msg = table.concat(missing_flags, ", ")
                cecho(string.format("\n  <yellow>Warning:<reset> Flag%s not found on '%s': <yellow>%s<reset>\n",
                    #missing_flags > 1 and "s" or "", planet_name, flags_msg))
            end
        end

        if F2T_MAP_EXPLORE_STATE.target_room_name and not F2T_MAP_EXPLORE_STATE.target_room_found_id then
            cecho(string.format("\n  <yellow>Warning:<reset> Target room '%s' not found\n",
                F2T_MAP_EXPLORE_STATE.target_room_name))
        end

        local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback
        if callback then
            cecho("\n<green>[map-explore]<reset> Area exploration complete\n\n")
            -- target_room_found_id is nil for every existing 0-arg callback and
            -- for a target-room search that never matched - only a caller that
            -- passed target_room_name to f2t_map_explore_planet_start reads it.
            local found_room_id = F2T_MAP_EXPLORE_STATE.target_room_found_id
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then callback(found_room_id) end
            end)
        else
            F2T_MAP_EXPLORE_STATE.phase = "returning"
            f2t_map_explore_next_step()
        end
        return
    end

    f2t_map_explore_brief_mode_start()

    if current_room ~= next_exit.room_id then
        F2T_MAP_EXPLORE_STATE.planned_exit = next_exit
        local success = f2t_map_navigate_ok(f2t_map_navigate(tostring(next_exit.room_id)))
        if not success then
            cecho(string.format("\n<red>[map-explore]<reset> Failed to navigate to room %d\n", next_exit.room_id))
            F2T_MAP_EXPLORE_STATE.planned_exit = nil
            f2t_map_explore_temp_lock_exit(next_exit.room_id, next_exit.direction)
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_next_step() end
            end)
        end
        return
    end

    F2T_MAP_EXPLORE_STATE.last_room_before_move     = current_room
    F2T_MAP_EXPLORE_STATE.last_direction_attempted  = next_exit.direction
    f2t_map_speedwalk_send_blind({next_exit.direction})
end

function f2t_map_explore_return_to_start()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local current_room  = F2T_MAP_CURRENT_ROOM_ID
    local starting_room = F2T_MAP_EXPLORE_STATE.starting_room_id

    if current_room ~= starting_room then
        cecho("\n<green>[map-explore]<reset> Returning to starting room...\n")
        local success = f2t_map_navigate_ok(f2t_map_navigate(tostring(starting_room)))
        if not success then
            cecho(string.format("\n<red>[map-explore]<reset> Failed to return to starting room %d\n", starting_room))
            f2t_map_explore_complete()
        end
        return
    end

    local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback
    if callback then
        callback()
    else
        f2t_map_explore_complete()
    end
end

f2t_debug_log("[map] Loaded explore_navigation.lua")
