-- f2ce-tools map — exploration navigation (ported from map_explore_navigation.lua)

-- Walking only finds ordinary exits. On a Sol planet the game files also name
-- the special ones (teleport disks, lift buttons, airlocks; see mechanics.lua):
-- the next one the map hasn't been through, from a room reachable from here.
local function next_known_crossing(current_room)
    local area_id = F2T_MAP_EXPLORE_STATE.starting_area_id
    if not area_id or not f2t_map_sol_uncrossed or getAreaUserData(area_id, "fed2_system") ~= "Sol" then
        return nil
    end
    local crossed = F2T_MAP_EXPLORE_STATE.crossed_specials or {}
    F2T_MAP_EXPLORE_STATE.crossed_specials = crossed
    for _, option in ipairs(f2t_map_sol_uncrossed(getRoomAreaName(area_id), crossed)) do
        crossed[option.key] = true
        if option.from_id == current_room or getPath(current_room, option.from_id) then
            return {room_id = option.from_id, direction = option.command, special = true}
        end
    end
    return nil
end

-- A queued exit can be mapped before it's walked (another exit naming the same
-- game room showed where it leads), and needs no visit then.
local function still_unexplored(exit)
    local dir_num = f2t_map_direction_to_number(exit.direction)
    for _, stub_dir_num in pairs(getExitStubs(exit.room_id) or {}) do
        if stub_dir_num == dir_num then return true end
    end
    return false
end

function f2t_map_explore_navigate_to_next()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local next_exit    = F2T_MAP_EXPLORE_STATE.planned_exit

    if next_exit then
        F2T_MAP_EXPLORE_STATE.planned_exit = nil
    else
        while not next_exit and #F2T_MAP_EXPLORE_STATE.frontier_stack > 0 do
            local candidate = table.remove(F2T_MAP_EXPLORE_STATE.frontier_stack, 1)
            if still_unexplored(candidate) then next_exit = candidate end
        end
    end

    if not next_exit then
        -- Exploration complete for this area
        -- Leaving "navigating" so a same-room gmcp.room.info re-fire (another
        -- player's ship arriving/leaving) can't walk this branch a second time.
        if F2T_MAP_EXPLORE_STATE.phase ~= "navigating" then
            f2t_debug_log("[map/explore] nothing left to explore, but phase is %s",
                tostring(F2T_MAP_EXPLORE_STATE.phase))
            return
        end
        -- Held in a ride's holding room (an airlock): it moves us on by itself
        if current_room and getRoomUserData(current_room, "fed2_transit") == "true" then
            f2t_debug_log("[map/explore] in a ride's holding room, waiting to arrive")
            return
        end
        next_exit = next_known_crossing(current_room)
        if next_exit then
            cecho(string.format("\n<cyan>[map-explore]<reset> No ordinary exits left; taking '%s' (known from the " ..
                "game files) to reach the rest\n", next_exit.direction))
        end
    end

    if not next_exit then
        F2T_MAP_EXPLORE_STATE.phase = "area_complete"

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
            -- A special exit's command isn't a direction to lock; it is already marked tried
            if not next_exit.special then
                f2t_map_explore_temp_lock_exit(next_exit.room_id, next_exit.direction)
            end
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
