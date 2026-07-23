-- f2ce-tools map — navigation (ported from map_navigate.lua)

function f2t_map_navigate(destination)
    f2t_debug_log("[map] f2t_map_navigate destination is '%s'", destination)
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n"); return false
    end
    local target_id, error_msg = f2t_map_resolve_location(destination)
    if not target_id then
        cecho(string.format("\n<red>[map]<reset> %s\n", error_msg or "Could not find destination")); return false
    end
    if not f2t_map_ensure_current_location(f2t_map_navigate, {destination}) then
        return false
    end
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    if current_room_id == target_id then
        cecho("\n<green>[map]<reset> You are already at the destination\n")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return true
    end
    local success = getPath(current_room_id, target_id)
    if not success then
        local current_area = getRoomArea(current_room_id)
        local target_area  = getRoomArea(target_id)
        cecho("\n<red>[map]<reset> No path found to destination\n")
        cecho(string.format("\n<dim_grey>Current: Room %d (%s)<reset>\n",
            current_room_id, current_area and getRoomAreaName(current_area) or "unknown"))
        cecho(string.format("<dim_grey>Target: Room %d (%s)<reset>\n",
            target_id, target_area and getRoomAreaName(target_area) or "unknown"))
        if current_area ~= target_area then
            cecho("\n<yellow>[map]<reset> Rooms are in different areas - make sure areas are connected\n")
        end
        return false
    end
    if #speedWalkDir == 0 then
        cecho("\n<green>[map]<reset> Already at destination\n")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return true
    end
    doSpeedWalk()
    return true
end
