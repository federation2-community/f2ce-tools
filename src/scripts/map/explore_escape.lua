-- f2ce-tools map — exploration escape logic (ported from map_explore_escape.lua)

function f2t_map_explore_escape_start(destination_room_id, on_success, on_failure)
    if not F2T_MAP_EXPLORE_STATE.active then
        if on_failure then on_failure("Exploration not active") end; return false
    end
    if F2T_MAP_EXPLORE_STATE.escape_state then
        if on_failure then on_failure("Escape already in progress") end; return false
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then
        if on_failure then on_failure("Current room unknown") end; return false
    end
    if current_room == destination_room_id then
        if on_success then on_success() end; return true
    end
    if f2t_map_navigate(tostring(destination_room_id)) then
        F2T_MAP_EXPLORE_STATE.escape_state = {
            destination_room_id = destination_room_id,
            on_success = on_success, on_failure = on_failure,
            phase = "navigating_to_destination",
        }
        F2T_MAP_EXPLORE_STATE.phase = "brief_escaping"
        return true
    end
    cecho("\n<yellow>[map-explore]<reset> Cannot navigate from current room, attempting to escape...\n")
    local gmcp_exits = gmcp.room and gmcp.room.info and gmcp.room.info.exits
    if not gmcp_exits or next(gmcp_exits) == nil then
        cecho("\n<red>[map-explore]<reset> No exits available from current room\n")
        if on_failure then on_failure("No exits available") end; return false
    end
    local exits_to_try = {}
    for dir, _ in pairs(gmcp_exits) do table.insert(exits_to_try, dir) end
    F2T_MAP_EXPLORE_STATE.escape_state = {
        destination_room_id = destination_room_id,
        on_success = on_success, on_failure = on_failure,
        exits_to_try = exits_to_try, attempts = 0, max_attempts = 10,
        starting_room_id = current_room, phase = "walking_exits",
    }
    F2T_MAP_EXPLORE_STATE.phase = "brief_escaping"
    f2t_map_explore_escape_try_next_exit()
    return true
end

function f2t_map_explore_escape_try_next_exit()
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return end
    escape.attempts = escape.attempts + 1
    if escape.attempts > escape.max_attempts then
        f2t_map_explore_escape_fail("Max escape attempts exceeded"); return
    end
    if #escape.exits_to_try == 0 then
        local gmcp_exits = gmcp.room and gmcp.room.info and gmcp.room.info.exits
        if gmcp_exits then
            for dir, _ in pairs(gmcp_exits) do table.insert(escape.exits_to_try, dir) end
        end
        if #escape.exits_to_try == 0 then
            f2t_map_explore_escape_fail("No exits available"); return
        end
    end
    local direction = table.remove(escape.exits_to_try, 1)
    cecho(string.format("  <dim_grey>Trying exit: %s<reset>\n", direction))
    speedWalkDir  = {direction}
    speedWalkPath = {nil}
    doSpeedWalk()
end

function f2t_map_explore_escape_on_room_change()
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return false end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room == escape.destination_room_id then
        f2t_map_explore_escape_success(); return true
    end
    if escape.phase == "navigating_to_destination" then return true end
    if f2t_map_navigate(tostring(escape.destination_room_id)) then
        cecho("\n<green>[map-explore]<reset> Found path! Navigating to destination...\n")
        escape.phase = "navigating_to_destination"; return true
    end
    tempTimer(0.3, function()
        if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.escape_state then
            f2t_map_explore_escape_try_next_exit()
        end
    end)
    return true
end

function f2t_map_explore_escape_on_speedwalk_complete(result)
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return false end
    if result == "completed" then
        local current_room = F2T_MAP_CURRENT_ROOM_ID
        if current_room == escape.destination_room_id then
            f2t_map_explore_escape_success(); return true
        end
        if f2t_map_navigate(tostring(escape.destination_room_id)) then
            escape.phase = "navigating_to_destination"; return true
        end
        tempTimer(0.3, function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.escape_state then
                f2t_map_explore_escape_try_next_exit()
            end
        end)
    elseif result == "failed" then
        tempTimer(0.3, function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.escape_state then
                f2t_map_explore_escape_try_next_exit()
            end
        end)
    elseif result == "stopped" then
        f2t_map_explore_escape_fail("Stopped by user")
    end
    return true
end

function f2t_map_explore_escape_success()
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return end
    cecho("\n<green>[map-explore]<reset> Escaped successfully, resuming exploration...\n")
    local on_success = escape.on_success
    F2T_MAP_EXPLORE_STATE.escape_state = nil
    if on_success then
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active then on_success() end
        end)
    end
end

function f2t_map_explore_escape_fail(reason)
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return end
    local on_failure = escape.on_failure
    local destination_room_id = escape.destination_room_id
    F2T_MAP_EXPLORE_STATE.escape_state = nil
    if on_failure then
        on_failure(reason)
    else
        f2t_map_explore_pause_stranded(reason, destination_room_id)
    end
end

function f2t_map_explore_pause_stranded(reason, destination_room_id)
    if not F2T_MAP_EXPLORE_STATE.active then return end
    F2T_MAP_EXPLORE_STATE.paused         = true
    F2T_MAP_EXPLORE_STATE.paused_reason  = "stranded"
    F2T_MAP_EXPLORE_STATE.paused_destination = destination_room_id
    cecho("\n<yellow>[map-explore]<reset> Exploration paused - unable to navigate\n")
    cecho(string.format("\n<dim_grey>Reason: %s<reset>\n", reason))
    if destination_room_id then
        cecho(string.format("<dim_grey>Destination: %s (room %d)<reset>\n",
            getRoomName(destination_room_id) or "Unknown", destination_room_id))
    end
    cecho("\n<yellow>To recover:<reset>\n")
    cecho("  1. Manually navigate to a known location\n")
    cecho("  2. Use <white>map explore resume<reset> to continue\n")
    cecho("  Or use <white>map explore stop<reset> to abort\n")
end

f2t_debug_log("[map] Loaded explore_escape.lua")
