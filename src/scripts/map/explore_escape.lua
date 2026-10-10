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
    if f2t_map_walk_room(destination_room_id) then
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
    F2T_MAP_EXPLORE_STATE.escape_state = {
        destination_room_id = destination_room_id,
        on_success = on_success, on_failure = on_failure,
        tried = {}, attempts = 0, max_attempts = 20,
        phase = "walking_exits",
    }
    F2T_MAP_EXPLORE_STATE.phase = "brief_escaping"
    f2t_map_explore_escape_try_next_exit()
    return true
end

-- The current room's exits not yet tried from it, unexplored ones first: a
-- mapped exit only leads somewhere the map already knows has no way out.
local function untried_exits(escape, room_id)
    local gmcp_exits = gmcp.room and gmcp.room.info and gmcp.room.info.exits
    local stub_dirs = {}
    for _, dir_num in pairs(getExitStubs(room_id) or {}) do stub_dirs[dir_num] = true end
    local unexplored, mapped = {}, {}
    for dir in pairs(gmcp_exits or {}) do
        if not escape.tried[room_id .. "|" .. dir] then
            if stub_dirs[f2t_map_direction_to_number(dir)] then
                table.insert(unexplored, dir)
            else
                table.insert(mapped, dir)
            end
        end
    end
    for _, dir in ipairs(mapped) do table.insert(unexplored, dir) end
    return unexplored
end

-- Maps the exit just walked, as exploring would, so each try can open a route
local function record_move(escape)
    local from_room, direction = escape.pending_from, escape.pending_direction
    escape.pending_from, escape.pending_direction = nil, nil
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if from_room and direction and current_room and current_room ~= from_room then
        f2t_map_resolve_stub_exit(from_room, current_room, direction)
    end
end

function f2t_map_explore_escape_try_next_exit()
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return end
    escape.attempts = escape.attempts + 1
    if escape.attempts > escape.max_attempts then
        f2t_map_explore_escape_fail("Max escape attempts exceeded"); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local direction = current_room and untried_exits(escape, current_room)[1]
    if not direction then
        f2t_map_explore_escape_fail("No untried exits from this room"); return
    end
    escape.tried[current_room .. "|" .. direction] = true
    escape.pending_from, escape.pending_direction = current_room, direction
    cecho(string.format("  <dim_grey>Trying exit: %s<reset>\n", direction))
    f2t_map_speedwalk_send_blind({direction})
end

function f2t_map_explore_escape_on_room_change()
    local escape = F2T_MAP_EXPLORE_STATE.escape_state
    if not escape then return false end
    record_move(escape)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room == escape.destination_room_id then
        f2t_map_explore_escape_success(); return true
    end
    if escape.phase == "navigating_to_destination" then return true end
    if f2t_map_walk_room(escape.destination_room_id) then
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
        record_move(escape)
        local current_room = F2T_MAP_CURRENT_ROOM_ID
        if current_room == escape.destination_room_id then
            f2t_map_explore_escape_success(); return true
        end
        if f2t_map_walk_room(escape.destination_room_id) then
            escape.phase = "navigating_to_destination"; return true
        end
        tempTimer(0.3, function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.escape_state then
                f2t_map_explore_escape_try_next_exit()
            end
        end)
    elseif result == "failed" then
        escape.pending_from, escape.pending_direction = nil, nil
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
