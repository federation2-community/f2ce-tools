-- Navigation function
-- Central navigation logic that can be called from aliases or other scripts

-- Navigate to a destination (room ID, hash, planet, system, or flag)
-- Returns: true if navigation started, false if failed
function f2t_map_navigate(destination)
    f2t_debug_log("[map] f2t_map_navigate destination is '%s'", destination)
    
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n")
        return false
    end

    -- Resolve destination to room ID using shared resolution function
    local target_id, error_msg = f2t_map_resolve_location(destination)

    if not target_id then
        cecho(string.format("\n<red>[map]<reset> %s\n", error_msg or "Could not find destination"))
        if string.match(error_msg or "", "not yet mapped") or string.match(error_msg or "", "unmapped room") then
            cecho("\n<dim_grey>Visit the location first to add it to the map<reset>\n")
        end
        return false
    end

    -- Verify current location is known before pathfinding
    if not f2t_map_ensure_current_location(f2t_map_navigate, {destination}) then
        return false  -- Retry scheduled after 'look'
    end

    -- Current location is now guaranteed to be known
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID

    -- Check if already at destination
    if current_room_id == target_id then
        cecho("\n<green>[map]<reset> You are already at the destination\n")
        f2t_debug_log("[map] Already at destination (room %d)", target_id)
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return true
    end

    -- Calculate path using Mudlet's pathfinding
    f2t_debug_log("[map] Calling getPath(%d, %d)", current_room_id, target_id)
    local success, cost = getPath(current_room_id, target_id)
    f2t_debug_log("[map] getPath returned: success=%s, cost=%s", tostring(success), tostring(cost))

    if not success then
        local current_area = getRoomArea(current_room_id)
        local target_area = getRoomArea(target_id)
        local current_area_name = current_area and getRoomAreaName(current_area) or "unknown"
        local target_area_name = target_area and getRoomAreaName(target_area) or "unknown"

        cecho("\n<red>[map]<reset> No path found to destination\n")
        cecho(string.format("\n<dim_grey>Current: Room %d (%s)<reset>\n", current_room_id, current_area_name))
        cecho(string.format("<dim_grey>Target: Room %d (%s)<reset>\n", target_id, target_area_name))

        if current_area ~= target_area then
            cecho("\n<yellow>[map]<reset> Rooms are in different areas - make sure areas are connected\n")
        end

        f2t_debug_log("[map] No path: current=%d (%s), target=%d (%s)",
            current_room_id, current_area_name, target_id, target_area_name)
        return false
    end

    -- Check if path is empty
    if #speedWalkDir == 0 then
        cecho("\n<green>[map]<reset> Already at destination\n")
        f2t_debug_log("[map] Empty path - already at destination")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return true
    end

    -- Start speedwalk
    doSpeedWalk()
    return true
end