-- Speedwalking implementation for Federation 2 mapper
-- Overrides Mudlet's doSpeedWalk to work with Fed2's GMCP room system

-- ========================================
-- Speedwalk State
-- ========================================

-- Current speedwalk state
F2T_SPEEDWALK_ACTIVE = false
F2T_SPEEDWALK_PAUSED = false
F2T_SPEEDWALK_DIR = {}                     -- Direction commands (copy of speedWalkDir)
F2T_SPEEDWALK_PATH = {}                -- Room IDs for each step (copy of speedWalkPath)
F2T_SPEEDWALK_CURRENT_STEP = 0
F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = false  -- Waiting for on-arrival command to complete
F2T_SPEEDWALK_DESTINATION_ROOM_ID = nil    -- Destination room ID for recomputing path
F2T_SPEEDWALK_LAST_COMMAND = nil           -- Last movement command sent (for retry)

-- Movement verification state (for detecting failed movements)
F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil       -- Expected destination room ID for current step
F2T_SPEEDWALK_WAITING_FOR_MOVE = false     -- Expecting room change after command
F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil        -- Timer ID for timeout detection

-- Recovery tracking
F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0     -- Reset on success, increment on failure

-- Result tracking (for integration with other components)
F2T_SPEEDWALK_LAST_RESULT = nil            -- "completed", "stopped", "failed"
F2T_SPEEDWALK_FAILED_EXIT_ROOM = nil       -- Room where exit failed (set when result="failed")
F2T_SPEEDWALK_FAILED_EXIT_DIR = nil        -- Direction that failed (set when result="failed")

-- Navigation ownership (for interrupt handling)
-- Instead of interrupt handlers checking each component, components register a callback
F2T_SPEEDWALK_OWNER = nil                  -- Component name: "map-explore", "stamina", "hauling", nil=standalone
F2T_SPEEDWALK_ON_INTERRUPT = nil           -- Callback: function(reason) -> { auto_resume = bool }

-- ========================================
-- Navigation Ownership
-- ========================================

-- Set navigation ownership (call before starting navigation)
-- @param owner string|nil - Component name for logging
-- @param on_interrupt function|nil - Callback: function(reason) -> { auto_resume = bool }
function f2t_map_set_nav_owner(owner, on_interrupt)
    F2T_SPEEDWALK_OWNER = owner
    F2T_SPEEDWALK_ON_INTERRUPT = on_interrupt
    f2t_debug_log("[map] Navigation owner set: %s", owner or "standalone")
end

-- Clear navigation ownership (called automatically when navigation ends)
function f2t_map_clear_nav_owner()
    F2T_SPEEDWALK_OWNER = nil
    F2T_SPEEDWALK_ON_INTERRUPT = nil
end

-- ========================================
-- Mudlet doSpeedWalk Override
-- ========================================

-- Override Mudlet's built-in doSpeedWalk function
-- This gets called when user double-clicks a room in the mapper or after getPath()
-- Processes the speedWalkDir global variable set by getPath()
function doSpeedWalk()
    -- Mudlet's getPath() stores the path in the global variable speedWalkDir
    if not speedWalkDir or #speedWalkDir == 0 then
        cecho("\n<red>[map]<reset> No path available - call getPath() first\n")
        f2t_debug_log("[map] Speedwalk failed: speedWalkDir is empty")
        return false
    end

    -- Initialize speedwalk state
    F2T_SPEEDWALK_ACTIVE = true
    F2T_SPEEDWALK_PAUSED = false
    F2T_SPEEDWALK_DIR = speedWalkDir  -- Copy directions
    F2T_SPEEDWALK_PATH = speedWalkPath  -- Copy room IDs
    F2T_SPEEDWALK_CURRENT_STEP = 0
    F2T_SPEEDWALK_DESTINATION_ROOM_ID = tonumber(speedWalkPath[#speedWalkPath])  -- Store destination (number)
    F2T_SPEEDWALK_LAST_COMMAND = nil
    F2T_SPEEDWALK_LAST_RESULT = nil  -- Clear stale result from previous speedwalk

    -- Reset verification state
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0

    local path_length = #speedWalkDir

    cecho(string.format("\n<green>[map]<reset> Speedwalking (%d steps)\n", path_length))
    f2t_debug_log("[map] Speedwalk started: %d steps to room %s", path_length,
        F2T_SPEEDWALK_DESTINATION_ROOM_ID and tostring(F2T_SPEEDWALK_DESTINATION_ROOM_ID) or "unknown (blind)")

    -- Take the first step
    f2t_map_speedwalk_next_step()

    return true
end

-- ========================================
-- Special Movement Handling
-- ========================================

-- Handle special movement patterns (circuit, auto-transit, etc.)
-- Returns: true if handled (speedwalk paused/stopped), false if normal movement
function f2t_map_handle_special_movement(direction)
    -- Check for circuit movement
    if direction:match("^__circuit:") then
        -- Circuit travel: initiate circuit state machine
        f2t_debug_log("[map] Circuit command detected: %s", direction)
        if f2t_map_circuit_begin(direction) then
            -- Circuit travel initiated successfully
            -- Speedwalk will resume when circuit travel completes
            F2T_SPEEDWALK_LAST_COMMAND = nil  -- No command sent yet
        else
            -- Circuit travel failed to start
            cecho("\n<red>[map]<reset> Circuit travel failed, stopping speedwalk\n")
            f2t_map_speedwalk_stop()
        end
        return true
    end

    -- Check for auto-transit (__move_no_op_<room_id>)
    if direction:match("^__move_no_op_%d+$") then
        -- Auto-transit: don't send anything, just wait for GMCP
        f2t_debug_log("[map] Auto-transit (__move_no_op): waiting for GMCP room change")
        F2T_SPEEDWALK_LAST_COMMAND = nil  -- No command sent

        -- Don't set up verification - noop means we're waiting for auto-transit
        -- The game will move us when ready, just wait for GMCP room change
        -- Verification would fail because we're still in the source room
        f2t_debug_log("[map] Auto-transit: no verification (waiting for game to move us)")

        -- Next GMCP room change will advance speedwalk automatically
        return true
    end

    -- Not a special movement pattern
    return false
end

-- Execute the next step in the speedwalk
function f2t_map_speedwalk_next_step()
    if not F2T_SPEEDWALK_ACTIVE then
        return
    end

    if F2T_SPEEDWALK_PAUSED then
        f2t_debug_log("[map] Speedwalk paused, not advancing")
        return
    end

    if F2T_SPEEDWALK_WAITING_FOR_ARRIVAL then
        f2t_debug_log("[map] Speedwalk waiting for on-arrival command to complete")
        return
    end

    F2T_SPEEDWALK_CURRENT_STEP = F2T_SPEEDWALK_CURRENT_STEP + 1

    if F2T_SPEEDWALK_CURRENT_STEP > #F2T_SPEEDWALK_DIR then
        -- Speedwalk complete
        f2t_map_speedwalk_complete()
        return
    end

    local direction = F2T_SPEEDWALK_DIR[F2T_SPEEDWALK_CURRENT_STEP]

    f2t_debug_log("[map] Speedwalk step %d/%d: %s",
        F2T_SPEEDWALK_CURRENT_STEP, #F2T_SPEEDWALK_DIR, direction)

    -- Check if this is a special movement pattern (circuit, auto-transit, etc.)
    if f2t_map_handle_special_movement(direction) then
        return
    end

    -- Store the command before sending (for potential retry)
    F2T_SPEEDWALK_LAST_COMMAND = direction

    -- Start movement verification (before sending command)
    -- Get expected destination room (as number) from our local copy
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = tonumber(F2T_SPEEDWALK_PATH[F2T_SPEEDWALK_CURRENT_STEP])
    F2T_SPEEDWALK_WAITING_FOR_MOVE = true

    -- Store current room for blocked exit detection
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = F2T_MAP_CURRENT_ROOM_ID

    -- Start timeout timer
    local timeout_seconds = f2t_settings_get("map", "speedwalk_timeout")
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = tempTimer(timeout_seconds, function()
        f2t_map_speedwalk_on_move_timeout()
    end)

    f2t_debug_log("[map] Movement verification started (expecting room %d, timeout %ds)",
        F2T_SPEEDWALK_EXPECTED_ROOM_ID or 0, timeout_seconds)

    -- Send the command (could be normal direction or special exit command)
    send(direction)
end

-- Called when speedwalk completes successfully
function f2t_map_speedwalk_complete()
    if not F2T_SPEEDWALK_ACTIVE then
        return
    end

    local dest_name = F2T_MAP_CURRENT_ROOM_ID and getRoomName(F2T_MAP_CURRENT_ROOM_ID)
    cecho(string.format("\n<green>[map]<reset> Arrived at <white>%s<reset>\n",
        dest_name or "destination"))
    f2t_debug_log("[map] Speedwalk complete")

    -- Set result for integration with other components
    F2T_SPEEDWALK_LAST_RESULT = "completed"

    -- Reset speedwalk state
    F2T_SPEEDWALK_ACTIVE = false
    F2T_SPEEDWALK_PAUSED = false
    F2T_SPEEDWALK_DIR = {}
    F2T_SPEEDWALK_PATH = {}
    F2T_SPEEDWALK_CURRENT_STEP = 0
    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = false
    F2T_SPEEDWALK_DESTINATION_ROOM_ID = nil
    F2T_SPEEDWALK_LAST_COMMAND = nil

    -- Reset verification state
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0

    -- Clear navigation ownership
    f2t_map_clear_nav_owner()
end

-- Stop/cancel speedwalk completely
function f2t_map_speedwalk_stop()
    if not F2T_SPEEDWALK_ACTIVE then
        return false
    end

    cecho("\n<yellow>[map]<reset> Speedwalk stopped\n")
    f2t_debug_log("[map] Speedwalk stopped at step %d/%d",
        F2T_SPEEDWALK_CURRENT_STEP, #F2T_SPEEDWALK_DIR)

    -- Set result for integration with other components
    -- Preserve "failed" result if set by caller (e.g., recompute_path failure)
    -- This allows callers to distinguish "user stopped manually" vs "path blocked"
    if F2T_SPEEDWALK_LAST_RESULT ~= "failed" then
        F2T_SPEEDWALK_LAST_RESULT = "stopped"
    end

    -- Clean up circuit state if active
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then
        f2t_debug_log("[map] Cleaning up active circuit travel")
        f2t_map_circuit_delete_triggers()
        F2T_MAP_CIRCUIT_STATE = {active = false}
    end

    -- Reset speedwalk state
    F2T_SPEEDWALK_ACTIVE = false
    F2T_SPEEDWALK_PAUSED = false
    F2T_SPEEDWALK_DIR = {}
    F2T_SPEEDWALK_PATH = {}
    F2T_SPEEDWALK_CURRENT_STEP = 0
    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = false
    F2T_SPEEDWALK_DESTINATION_ROOM_ID = nil
    F2T_SPEEDWALK_LAST_COMMAND = nil

    -- Clean up verification state
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0

    -- Clear navigation ownership
    f2t_map_clear_nav_owner()

    return true
end

-- Pause active speedwalk
function f2t_map_speedwalk_pause()
    if not F2T_SPEEDWALK_ACTIVE then
        return false
    end

    if F2T_SPEEDWALK_PAUSED then
        cecho("\n<yellow>[map]<reset> Speedwalk is already paused\n")
        return false
    end

    F2T_SPEEDWALK_PAUSED = true
    local remaining = #F2T_SPEEDWALK_DIR - F2T_SPEEDWALK_CURRENT_STEP

    cecho(string.format("\n<yellow>[map]<reset> Speedwalk paused (%d steps remaining)\n", remaining))
    f2t_debug_log("[map] Speedwalk paused at step %d/%d",
        F2T_SPEEDWALK_CURRENT_STEP, #F2T_SPEEDWALK_DIR)

    return true
end

-- Resume paused speedwalk
function f2t_map_speedwalk_resume()
    if not F2T_SPEEDWALK_ACTIVE then
        return false
    end

    if not F2T_SPEEDWALK_PAUSED then
        cecho("\n<yellow>[map]<reset> Speedwalk is not paused\n")
        return false
    end

    F2T_SPEEDWALK_PAUSED = false
    local remaining = #F2T_SPEEDWALK_DIR - F2T_SPEEDWALK_CURRENT_STEP

    cecho(string.format("\n<green>[map]<reset> Speedwalk resumed (%d steps remaining)\n", remaining))
    f2t_debug_log("[map] Speedwalk resumed at step %d/%d",
        F2T_SPEEDWALK_CURRENT_STEP, #F2T_SPEEDWALK_DIR)

    -- Continue immediately
    f2t_map_speedwalk_next_step()

    return true
end

-- ========================================
-- GMCP Integration
-- ========================================

-- Hook into room processing to advance speedwalk
-- This should be called from the main GMCP handler after room processing
function f2t_map_speedwalk_on_room_change()
    if not F2T_SPEEDWALK_ACTIVE then
        return
    end

    -- If circuit travel is active, let the circuit state machine handle room changes
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then
        f2t_debug_log("[map] Ignoring room change during active circuit travel")
        return
    end

    -- If we're waiting for movement verification, check if we arrived at expected room
    if F2T_SPEEDWALK_WAITING_FOR_MOVE then
        -- Cancel timeout timer
        if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
            killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
            F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
        end

        F2T_SPEEDWALK_WAITING_FOR_MOVE = false

        -- Verify we arrived at the expected room
        local current_room = F2T_MAP_CURRENT_ROOM_ID
        local expected_room = F2T_SPEEDWALK_EXPECTED_ROOM_ID

        f2t_debug_log("[map] Movement verification: expected room %d, current room %d",
            expected_room or 0, current_room or 0)

        -- Check if movement was successful
        local movement_success = false
        if current_room == expected_room then
            -- Exact match: arrived at expected room
            movement_success = true
        elseif expected_room == nil and current_room ~= F2T_SPEEDWALK_ROOM_BEFORE_MOVE then
            -- No expectation (exploration stub exit): any new room is success
            movement_success = true
        end

        if movement_success then
            -- Success! Arrived at expected or acceptable destination
            f2t_debug_log("[map] Movement successful - arrived at %s",
                expected_room and "expected room" or "new room (stub exit)")
            F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
            F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
            F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil

            -- Continue to next step
            f2t_map_speedwalk_next_step()
        else
            -- Failure! Didn't arrive at expected room (wrong room OR same room)
            f2t_debug_log("[map] Movement failed - current room (%d) != expected room (%d)",
                current_room or 0, expected_room or 0)

            -- Check if we're still in the same room (blocked exit)
            if F2T_SPEEDWALK_ROOM_BEFORE_MOVE and current_room == F2T_SPEEDWALK_ROOM_BEFORE_MOVE then
                -- Movement was blocked - we stayed in the same room
                local blocked_dir = F2T_SPEEDWALK_LAST_COMMAND

                cecho(string.format("\n<yellow>[map]<reset> Exit blocked: <white>%s<reset> from room %d\n",
                    blocked_dir or "unknown", current_room))
                f2t_debug_log("[map] Blocked exit detected: room=%d, direction=%s (not locking - will retry)",
                    current_room, blocked_dir)
            end

            F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
            F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil

            -- Handle failure (will retry with new path that avoids locked exit)
            f2t_map_speedwalk_handle_move_failure()
        end
    else
        -- Not waiting for verification, just continue
        -- (This handles legacy interruption recovery paths)
        f2t_map_speedwalk_next_step()
    end
end

-- ========================================
-- Interruption Recovery
-- ========================================

-- Retry the last movement command
-- Used when a temporary interruption is resolved (e.g., refueled)
function f2t_map_speedwalk_retry_last_command()
    if not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[map] Cannot retry: speedwalk not active")
        return false
    end

    if not F2T_SPEEDWALK_LAST_COMMAND then
        f2t_debug_log("[map] Cannot retry: no last command stored")
        return false
    end

    cecho("\n<yellow>[map]<reset> Retrying movement...\n")
    f2t_debug_log("[map] Retrying last command: %s", F2T_SPEEDWALK_LAST_COMMAND)

    -- Resend the last command
    send(F2T_SPEEDWALK_LAST_COMMAND)

    return true
end

-- Recompute path from current location to destination
-- Used when location changes unexpectedly (e.g., Sol customs intercept)
function f2t_map_speedwalk_recompute_path()
    if not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[map] Cannot recompute: speedwalk not active")
        return false
    end

    if not F2T_SPEEDWALK_DESTINATION_ROOM_ID then
        f2t_debug_log("[map] Cannot recompute: no destination stored")
        cecho("\n<red>[map]<reset> Unable to recover speedwalk: destination unknown\n")
        -- Set result to "failed" before stop (so callers know this wasn't user-initiated)
        F2T_SPEEDWALK_LAST_RESULT = "failed"
        -- Preserve which exit failed (for exploration to lock)
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_MAP_CURRENT_ROOM_ID
        F2T_SPEEDWALK_FAILED_EXIT_DIR = F2T_SPEEDWALK_LAST_COMMAND
        f2t_debug_log("[map] Failed exit (blind movement): room %d, direction %s",
            F2T_SPEEDWALK_FAILED_EXIT_ROOM or 0, F2T_SPEEDWALK_FAILED_EXIT_DIR or "unknown")
        f2t_map_speedwalk_stop()
        return false
    end

    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    if not current_room_id then
        f2t_debug_log("[map] Cannot recompute: current room unknown")
        cecho("\n<red>[map]<reset> Unable to recover speedwalk: current location unknown\n")
        -- Set result to "failed" before stop (so callers know this wasn't user-initiated)
        F2T_SPEEDWALK_LAST_RESULT = "failed"
        -- Preserve which exit failed (for exploration to lock)
        -- Use ROOM_BEFORE_MOVE since current room is unknown
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_SPEEDWALK_ROOM_BEFORE_MOVE
        F2T_SPEEDWALK_FAILED_EXIT_DIR = F2T_SPEEDWALK_LAST_COMMAND
        f2t_debug_log("[map] Failed exit (room unknown): room %d, direction %s",
            F2T_SPEEDWALK_FAILED_EXIT_ROOM or 0, F2T_SPEEDWALK_FAILED_EXIT_DIR or "unknown")
        f2t_map_speedwalk_stop()
        return false
    end

    cecho("\n<yellow>[map]<reset> Recomputing path from current location...\n")
    f2t_debug_log("[map] Recomputing path from room %d to room %d",
        current_room_id, F2T_SPEEDWALK_DESTINATION_ROOM_ID)

    -- Compute new path using Mudlet's pathfinding
    -- getPath() returns: success (boolean), cost (number)
    -- getPath() sets globals: speedWalkDir, speedWalkPath, speedWalkWeight
    local success, cost = getPath(current_room_id, F2T_SPEEDWALK_DESTINATION_ROOM_ID)

    if not success then
        cecho("\n<red>[map]<reset> Unable to find path from current location\n")
        f2t_debug_log("[map] Path recomputation failed - no valid path")
        -- Set result to "failed" before stop (so callers know this wasn't user-initiated)
        F2T_SPEEDWALK_LAST_RESULT = "failed"
        -- Preserve which exit failed (for exploration to lock)
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = current_room_id
        F2T_SPEEDWALK_FAILED_EXIT_DIR = F2T_SPEEDWALK_LAST_COMMAND
        f2t_debug_log("[map] Failed exit (no path): room %d, direction %s",
            F2T_SPEEDWALK_FAILED_EXIT_ROOM or 0, F2T_SPEEDWALK_FAILED_EXIT_DIR or "unknown")
        f2t_map_speedwalk_stop()
        return false
    end

    -- Check if we arrived at destination during interruption
    if #speedWalkDir == 0 then
        cecho("\n<green>[map]<reset> Already at destination\n")
        f2t_debug_log("[map] Arrived at destination during interruption")
        f2t_map_speedwalk_stop()
        return true
    end

    -- Update speedwalk state with new path
    F2T_SPEEDWALK_DIR = speedWalkDir  -- Copy directions
    F2T_SPEEDWALK_PATH = speedWalkPath  -- Copy room IDs
    F2T_SPEEDWALK_CURRENT_STEP = 0
    F2T_SPEEDWALK_LAST_COMMAND = nil

    -- Reset verification state for new path
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end

    -- NOTE: Don't reset failure counter here - recompute is part of retry mechanism
    -- Counter only resets on actual movement success

    local path_length = #speedWalkDir
    cecho(string.format("\n<green>[map]<reset> Path recomputed (%d steps), resuming...\n", path_length))
    f2t_debug_log("[map] Path recomputed: %d steps (attempt %d)", path_length, F2T_SPEEDWALK_CONSECUTIVE_FAILURES)

    -- Start walking the new path
    f2t_map_speedwalk_next_step()

    return true
end

-- ========================================
-- Movement Verification
-- ========================================

-- Handle movement failure (blocked exit, error, etc.)
function f2t_map_speedwalk_handle_move_failure()
    if not F2T_SPEEDWALK_ACTIVE then
        return
    end

    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = F2T_SPEEDWALK_CONSECUTIVE_FAILURES + 1

    local max_retries = f2t_settings_get("map", "speedwalk_max_retries")

    f2t_debug_log("[map] Movement failed (attempt %d/%d)", F2T_SPEEDWALK_CONSECUTIVE_FAILURES, max_retries)

    if F2T_SPEEDWALK_CONSECUTIVE_FAILURES >= max_retries then
        -- Give up after max retries
        cecho(string.format("\n<red>[map]<reset> Path appears blocked after %d attempts, stopping speedwalk\n", max_retries))
        f2t_debug_log("[map] Max retries exceeded, stopping speedwalk")

        -- Set result to "failed" instead of "stopped" (so caller knows why it stopped)
        -- IMPORTANT: This must be set BEFORE cleanup, as components check this result
        F2T_SPEEDWALK_LAST_RESULT = "failed"

        -- Preserve which exit failed (for exploration to lock)
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_MAP_CURRENT_ROOM_ID
        F2T_SPEEDWALK_FAILED_EXIT_DIR = F2T_SPEEDWALK_LAST_COMMAND
        f2t_debug_log("[map] Failed exit: room %d, direction %s",
            F2T_SPEEDWALK_FAILED_EXIT_ROOM or 0, F2T_SPEEDWALK_FAILED_EXIT_DIR or "unknown")

        -- Stop speedwalk (but don't override the "failed" result we just set)
        -- IMPORTANT: We inline the stop logic here instead of calling f2t_map_speedwalk_stop()
        -- because that function sets result to "stopped", which would overwrite our "failed" result.
        -- Components need to distinguish between "user stopped manually" vs "path genuinely blocked".
        cecho("\n<yellow>[map]<reset> Speedwalk stopped\n")
        f2t_debug_log("[map] Speedwalk stopped at step %d/%d",
            F2T_SPEEDWALK_CURRENT_STEP, #F2T_SPEEDWALK_DIR)

        -- Clean up circuit state if active
        if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then
            f2t_debug_log("[map] Cleaning up active circuit travel")
            f2t_map_circuit_delete_triggers()
            F2T_MAP_CIRCUIT_STATE = {active = false}
        end

        -- Reset speedwalk state
        F2T_SPEEDWALK_ACTIVE = false
        F2T_SPEEDWALK_PAUSED = false
        F2T_SPEEDWALK_DIR = {}
        F2T_SPEEDWALK_PATH = {}
        F2T_SPEEDWALK_CURRENT_STEP = 0
        F2T_SPEEDWALK_WAITING_FOR_ARRIVAL = false
        F2T_SPEEDWALK_DESTINATION_ROOM_ID = nil
        F2T_SPEEDWALK_LAST_COMMAND = nil

        -- Clean up verification state
        F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
        F2T_SPEEDWALK_WAITING_FOR_MOVE = false
        F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
        if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
            killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
            F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
        end
        F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0

        -- Clear navigation ownership
        f2t_map_clear_nav_owner()

        return
    end

    -- Retry by recomputing path
    cecho(string.format("\n<yellow>[map]<reset> Movement erred, recomputing path... (attempt %d/%d)\n",
        F2T_SPEEDWALK_CONSECUTIVE_FAILURES, max_retries))

    f2t_map_speedwalk_recompute_path()
end

-- Handle movement timeout (no GMCP response)
function f2t_map_speedwalk_on_move_timeout()
    if not F2T_SPEEDWALK_ACTIVE or not F2T_SPEEDWALK_WAITING_FOR_MOVE then
        return
    end

    f2t_debug_log("[map] Movement timeout - no GMCP response after %ds",
        f2t_settings_get("map", "speedwalk_timeout"))

    -- Clear timeout state
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil

    -- Treat timeout as movement failure
    f2t_map_speedwalk_handle_move_failure()
end
