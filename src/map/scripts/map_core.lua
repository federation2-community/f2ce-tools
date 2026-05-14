-- Core mapper logic for Federation 2
-- Handles GMCP room.info events and orchestrates mapping

-- ========================================
-- Main GMCP Room Handler
-- ========================================

-- Process GMCP room.info event
-- This is called whenever you move to a new room
function f2t_map_handle_gmcp_room()
    -- Check if mapper is enabled
    if not F2T_MAP_ENABLED then
        f2t_debug_log("[map] Mapper disabled, skipping room processing")
        return
    end

    -- Validate GMCP data
    if not gmcp or not gmcp.room or not gmcp.room.info then
        f2t_debug_log("[map] ERROR: No GMCP room data available")
        return
    end

    local room_data = gmcp.room.info

    -- Validate required fields
    if not room_data.system or not room_data.area or not room_data.num then
        f2t_debug_log("[map] ERROR: Missing required GMCP fields (system: %s, area: %s, num: %s)",
            tostring(room_data.system), tostring(room_data.area), tostring(room_data.num))
        return
    end

    f2t_debug_log("[map] Processing room: %s.%s.%d (%s)",
        room_data.system, room_data.area, room_data.num, room_data.name or "unnamed")

    -- Generate hash for this room
    local hash = f2t_map_generate_hash(room_data)
    if not hash then
        return
    end

    -- Check if room exists
    local room_id = f2t_map_get_room_by_hash(hash)
    local is_new_room = (room_id == nil)

    -- Ignore same-room GMCP events while waiting for movement confirmation.
    -- Another player entering the room (or similar game events) can trigger
    -- gmcp.room.info for the room we're already in. Treating that as a failed
    -- move would cause false "Exit blocked" detection; genuine blocked exits
    -- are handled by the movement timeout instead.
    if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE and
       room_id and room_id == F2T_MAP_CURRENT_ROOM_ID then
        f2t_debug_log("[map] Ignoring same-room GMCP during movement wait (room %d)", room_id)
        return
    end

    if is_new_room then
        -- Create new room
        room_id = f2t_map_create_new_room(room_data)
        if not room_id then
            f2t_debug_log("[map] ERROR: Failed to create room")
            return
        end
    else
        -- Update existing room
        f2t_map_update_room(room_id, room_data)
        f2t_debug_log("[map] Room exists, updating: ID %d", room_id)
    end

    -- Process exits (standard and stubs)
    f2t_debug_log("[map] Processing exits for room %d", room_id)
    f2t_map_process_exits(room_id, room_data.exits, room_data)

    -- Connect any stubs from other rooms that should point to us
    -- This handles one-way exits where the source room was visited before we existed
    -- Only needed for new rooms (existing rooms already had incoming stubs connected)
    if is_new_room then
        f2t_map_connect_incoming_stubs(room_id, room_data.num)
    end

    -- Process special exits (board, etc.)
    f2t_debug_log("[map] Processing special exits for room %d", room_id)
    f2t_map_process_special_exits(room_id, room_data)

    -- Update current room tracking
    F2T_MAP_CURRENT_ROOM_ID = room_id

    -- Center map on current room
    f2t_debug_log("[map] Centering map on room %d", room_id)
    centerview(room_id)

    -- Set map zoom for the area
    local area_id = getRoomArea(room_id)
    if area_id then
        local zoom = f2t_settings_get("map", "area_zoom")
        setMapZoom(zoom, area_id)
    end

    -- Check for pending special exit discovery
    if F2T_MAP_PENDING_SPECIAL_EXIT then
        f2t_debug_log("[map] Completing special exit discovery")
        f2t_map_special_exit_discovery_complete(room_id)
    end

    -- Check for manual boarding during circuit travel
    -- If circuit is waiting for arrival and we just moved to the vehicle room, treat as boarding
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active and
       F2T_MAP_CIRCUIT_STATE.phase == "waiting_arrival" then
        local current_hash = f2t_map_generate_hash_from_room(room_id)
        if current_hash == F2T_MAP_CIRCUIT_STATE.vehicle_room then
            f2t_debug_log("[map-circuit] Manual boarding detected (already at vehicle)")
            f2t_map_circuit_handle_boarding(true)  -- Skip sending board command
        end
    end

    -- Check for on-arrival command
    local arrival_cmd, exec_type = f2t_map_special_get_arrival(room_id)
    if arrival_cmd and exec_type then
        -- Check if command should execute based on type
        if f2t_map_special_should_execute_arrival(room_id, exec_type) then
            f2t_debug_log("[map] Executing on-arrival command: %s (type: %s)", arrival_cmd, exec_type)
            send(arrival_cmd)

            -- Mark as executed
            f2t_map_special_mark_arrival_executed(room_id, exec_type)

            -- If speedwalk is active, set wait flag and schedule continuation
            if F2T_SPEEDWALK_ACTIVE then
                F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = true
                tempTimer(0.5, function()
                    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = false
                    f2t_debug_log("[map] On-arrival command complete, continuing speedwalk")
                    f2t_map_speedwalk_on_room_change()
                end)
            end
        else
            -- Command exists but shouldn't execute, advance speedwalk normally
            f2t_map_speedwalk_on_room_change()
        end
    else
        -- No arrival command, advance speedwalk normally if active
        f2t_map_speedwalk_on_room_change()
    end

    -- Check for active exploration
    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        f2t_map_explore_on_room_change()
    end

    f2t_debug_log("[map] Room processing complete: ID %d", room_id)
end

-- ========================================
-- Room Creation Orchestration
-- ========================================

-- Create a new room with all associated data
-- Returns: room_id or nil on failure
function f2t_map_create_new_room(room_data)
    -- Create or get area
    local area_data = {
        system = room_data.system,
        cartel = room_data.cartel,
        owner = room_data.owner
    }
    local area_id = f2t_map_get_or_create_area(room_data.area, area_data)
    if not area_id then
        f2t_debug_log("[map] ERROR: Failed to create/get area")
        return nil
    end

    -- Create room
    local room_id = f2t_map_create_room(room_data, area_id)
    if not room_id then
        return nil
    end

    -- Calculate absolute coordinates from Fed2 room number
    local x, y, z = f2t_map_calculate_coords_from_room_num(room_data.num)

    -- Set room coordinates
    f2t_map_set_room_coords(room_id, x, y, z)

    -- Apply room styling (reads stored flags including fallbacks)
    f2t_map_update_room_style(room_id)

    f2t_debug_log("[map] New room created and configured: ID %d", room_id)

    return room_id
end

-- ========================================
-- Synchronization
-- ========================================

-- Force synchronize current room with GMCP data
-- Useful for recovering from desyncs
function f2t_map_sync()
    if not F2T_MAP_ENABLED then
        cecho("\n<red>[map]<reset> Mapper is disabled. Use 'map on' first.\n")
        return
    end

    cecho("\n<green>[map]<reset> Synchronizing with current location...\n")

    -- Process current room
    f2t_map_handle_gmcp_room()

    cecho("\n<green>[map]<reset> Synchronization complete.\n")
end
