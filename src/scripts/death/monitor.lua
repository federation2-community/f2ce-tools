-- Death Monitoring and Recovery System
-- Always-on system that detects death, issues insure, and locks death rooms

-- ========================================
-- State Management
-- ========================================

-- Initialize state (preserve some fields across reloads, reset others)
F2T_DEATH_STATE = F2T_DEATH_STATE or {}

-- Always reset handler IDs on script load (old handlers are invalid after reload)
-- This is critical because package reload kills old handlers but state persists
F2T_DEATH_STATE.monitoring_active = false  -- Force re-registration of handlers
F2T_DEATH_STATE.room_tracking_handler_id = nil
F2T_DEATH_STATE.vitals_handler_id = nil
F2T_DEATH_STATE.suicide_timeout_id = nil

-- Initialize other fields if not present
F2T_DEATH_STATE.active = F2T_DEATH_STATE.active or false
F2T_DEATH_STATE.current_phase = F2T_DEATH_STATE.current_phase or "idle"
F2T_DEATH_STATE.previous_room_hash = nil   -- Reset room tracking on reload
F2T_DEATH_STATE.current_room_hash = nil
F2T_DEATH_STATE.death_room_hash = F2T_DEATH_STATE.death_room_hash or nil
F2T_DEATH_STATE.death_room_id = F2T_DEATH_STATE.death_room_id or nil
F2T_DEATH_STATE.death_cause = nil           -- "suicide", "starvation", or nil (room hazard)
F2T_DEATH_STATE.stamina_was_critical = false

-- ========================================
-- Monitoring Control
-- ========================================

-- Called by the suicide alias to flag the death cause before it happens.
-- Clears automatically after 10s if no death follows.
function f2t_death_detect_suicide()
    F2T_DEATH_STATE.death_cause = "suicide"
    if F2T_DEATH_STATE.suicide_timeout_id then
        killTimer(F2T_DEATH_STATE.suicide_timeout_id)
    end
    F2T_DEATH_STATE.suicide_timeout_id = tempTimer(10, function()
        if F2T_DEATH_STATE.death_cause == "suicide" and not F2T_DEATH_STATE.active then
            F2T_DEATH_STATE.death_cause = nil
        end
        F2T_DEATH_STATE.suicide_timeout_id = nil
    end)
    f2t_debug_log("[death] Suicide command detected via alias")
end

function f2t_death_start_monitoring()
    if F2T_DEATH_STATE.monitoring_active then
        f2t_debug_log("[death] Monitoring already active")
        return
    end

    F2T_DEATH_STATE.monitoring_active = true

    -- Register handler to track previous room (GMCP updates before death text)
    f2t_death_register_room_tracking_handler()

    -- Track critical stamina (exactly 0 = starvation; negative = room damage, ignored)
    F2T_DEATH_STATE.vitals_handler_id = registerAnonymousEventHandler("gmcp.char.vitals", function()
        local vstam = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.stamina
        if vstam and vstam.cur ~= nil then
            local cur = tonumber(vstam.cur) or 0
            if cur == 0 then
                -- Exactly 0 = player ran out of stamina (starvation-style death possible)
                F2T_DEATH_STATE.stamina_was_critical = true
                f2t_debug_log("[death] Stamina reached 0 — starvation flag set")
            elseif cur > 0 and not F2T_DEATH_STATE.active then
                -- Stamina recovered while not dying — clear the flag
                F2T_DEATH_STATE.stamina_was_critical = false
            end
            -- Negative cur values (room damage) do NOT set the flag
        end
    end)

    f2t_debug_log("[death] Death monitoring started")
end

-- ========================================
-- Recovery Process
-- ========================================

function f2t_death_start_recovery()
    if F2T_DEATH_STATE.active then
        f2t_debug_log("[death] Recovery already in progress, ignoring")
        return
    end

    F2T_DEATH_STATE.active = true
    f2t_debug_log("[death] Starting death recovery process")

    -- Capture location IMMEDIATELY (before teleport)
    f2t_death_capture_location()

    -- Lets components note what they were doing before it is stopped
    raiseEvent("f2tDeathDetected")

    -- Stop all active automation
    f2t_death_stop_all_components()

    -- Wait 0.5s for GMCP to settle, then proceed directly to processing
    -- (Don't wait for GMCP room change - it may have already fired before our trigger)
    F2T_DEATH_STATE.current_phase = "awaiting_respawn"
    f2t_debug_log("[death] Phase: awaiting_respawn, waiting 0.5s for respawn to complete")

    tempTimer(0.5, function()
        if F2T_DEATH_STATE.active and F2T_DEATH_STATE.current_phase == "awaiting_respawn" then
            f2t_debug_log("[death] Respawn delay complete, proceeding to recovery")
            f2t_death_phase_processing()
        end
    end)
end

-- ========================================
-- Location Capture
-- ========================================

function f2t_death_capture_location()
    -- Use PREVIOUS room - GMCP updates BEFORE death text arrives
    -- By the time our trigger fires, GMCP already shows respawn location
    if F2T_DEATH_STATE.previous_room_hash then
        F2T_DEATH_STATE.death_room_hash = F2T_DEATH_STATE.previous_room_hash
        -- Look up room ID from hash (don't use F2T_MAP_CURRENT_ROOM_ID - race condition)
        local looked_up = getRoomIDbyHash(F2T_DEATH_STATE.previous_room_hash)
        F2T_DEATH_STATE.death_room_id = (looked_up and looked_up > 0) and looked_up or nil
        f2t_debug_log("[death] Captured death location from previous room: %s (ID: %s)",
            F2T_DEATH_STATE.death_room_hash,
            tostring(F2T_DEATH_STATE.death_room_id))
    else
        -- Fallback: no previous room tracked yet (shouldn't happen normally)
        f2t_debug_log("[death] WARNING: No previous room tracked, cannot determine death location")
        F2T_DEATH_STATE.death_room_hash = nil
        F2T_DEATH_STATE.death_room_id = nil
    end
end

-- ========================================
-- Component Stopping
-- ========================================

function f2t_death_stop_all_components()
    -- Stop hauling (highest priority - has cargo, cycles); a mode whose work
    -- survives a death pauses instead, to resume on f2tDeathRecovered
    if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
        f2t_debug_log("[death] Stopping active hauling")
        if f2t_hauling_on_death then
            f2t_hauling_on_death()
        elseif f2t_hauling_terminate then
            f2t_hauling_terminate()
        elseif f2t_hauling_do_stop then
            f2t_hauling_do_stop()
        end
    end

    -- Stop map exploration
    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        f2t_debug_log("[death] Stopping active exploration")
        if f2t_map_explore_stop then
            f2t_map_explore_stop()
        end
    end

    if f2tStaminaCancelTrip and f2tStaminaCancelTrip(true) then
        f2t_debug_log("[death] Cancelled food run")
    end

    if f2tNav and f2tNav.stopAll() then
        f2t_debug_log("[death] Stopped navigation")
    end
end

-- ========================================
-- Previous Room Tracking (Always-On)
-- ========================================

-- GMCP updates BEFORE death text arrives, so we need to track previous room
-- When death trigger fires, GMCP already shows respawn location

function f2t_death_register_room_tracking_handler()
    -- Kill existing handler if any
    if F2T_DEATH_STATE.room_tracking_handler_id then
        killAnonymousEventHandler(F2T_DEATH_STATE.room_tracking_handler_id)
        F2T_DEATH_STATE.room_tracking_handler_id = nil
    end

    -- Initialize current room
    local room = gmcp.room and gmcp.room.info
    if room and room.system and room.area and room.num then
        F2T_DEATH_STATE.current_room_hash = string.format("%s.%s.%s",
            room.system, room.area, room.num)
    end

    F2T_DEATH_STATE.room_tracking_handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        f2t_death_track_room_change()
    end)

    f2t_debug_log("[death] Room tracking handler registered")
end

function f2t_death_track_room_change()
    local room = gmcp.room and gmcp.room.info
    if not room or not room.system or not room.area or not room.num then
        return
    end

    local new_hash = string.format("%s.%s.%s", room.system, room.area, room.num)

    -- Only update if room actually changed
    if new_hash ~= F2T_DEATH_STATE.current_room_hash then
        -- Move current to previous
        F2T_DEATH_STATE.previous_room_hash = F2T_DEATH_STATE.current_room_hash
        F2T_DEATH_STATE.previous_room_id = F2T_MAP_CURRENT_ROOM_ID

        -- Update current
        F2T_DEATH_STATE.current_room_hash = new_hash

        f2t_debug_log("[death] Room changed: %s -> %s (prev ID: %s)",
            F2T_DEATH_STATE.previous_room_hash or "nil",
            new_hash,
            tostring(F2T_DEATH_STATE.previous_room_id))
    end
end

-- ========================================
-- Phase: Processing (Recovery Actions)
-- ========================================

function f2t_death_phase_processing()
    F2T_DEATH_STATE.current_phase = "processing"
    f2t_debug_log("[death] Phase: processing, executing recovery actions")

    -- Wait 0.3s for game state to stabilize after respawn
    tempTimer(0.3, function()
        if F2T_DEATH_STATE.active and F2T_DEATH_STATE.current_phase == "processing" then
            f2t_death_execute_recovery()
        end
    end)
end

function f2t_death_execute_recovery()
    -- Send insure command
    f2t_debug_log("[death] Sending insure command")
    send("insure")

    -- Wait 0.5s for insure to process, then lock room
    tempTimer(0.5, function()
        if F2T_DEATH_STATE.active then
            f2t_death_lock_room()
        end
    end)
end

-- ========================================
-- Room Locking
-- ========================================

function f2t_death_lock_room()
    local room_id = F2T_DEATH_STATE.death_room_id
    local cause = F2T_DEATH_STATE.death_cause

    -- Suicide is player-caused — do not lock the room
    if cause == "suicide" then
        f2t_debug_log("[death] Death was a suicide — skipping room lock")
        f2t_death_show_summary(false, "suicide")
        f2t_death_complete()
        return
    end

    -- Starvation: stamina reached exactly 0 before death, which means the player slowly
    -- ran out of stamina (not instant room damage). Room itself is not a hazard.
    -- Note: room damage (e.g. Mocha hill) drops stamina to negative values, which does NOT
    -- set stamina_was_critical, so those deaths still result in room locking.
    if F2T_DEATH_STATE.stamina_was_critical then
        f2t_debug_log("[death] Death preceded by stamina reaching 0 — likely starvation, skipping room lock")
        f2t_death_show_summary(false, "starvation")
        f2t_death_complete()
        return
    end

    -- Safe room override: user explicitly declared this room should never be auto-locked.
    -- The death summary will show the skip reason so the user knows the flag is active.
    if room_id and roomExists(room_id) then
        local is_safe = getRoomUserData(room_id, "f2t_safe")
        if is_safe == "true" then
            f2t_debug_log("[death] Room %d is marked safe — skipping auto-lock", room_id)
            f2t_death_show_summary(false, "safe_room")
            f2t_death_complete()
            return
        end
    end

    if not room_id or not roomExists(room_id) then
        -- Room not in map - still complete recovery
        f2t_debug_log("[death] Death room not mapped, cannot lock (hash: %s)",
            F2T_DEATH_STATE.death_room_hash or "unknown")
        f2t_death_show_summary(false, nil)
        f2t_death_complete()
        return
    end

    f2t_debug_log("[death] Locking death room: %d", room_id)

    -- Lock using existing function
    local success = true
    if f2t_map_manual_lock_room then
        success = f2t_map_manual_lock_room(room_id)
    else
        -- Fallback to direct Mudlet call
        lockRoom(room_id, true)
    end

    if success ~= false then
        f2t_debug_log("[death] Room locked successfully")

        -- Add death-specific metadata
        setRoomUserData(room_id, "f2t_locked_reason", "death")
        setRoomUserData(room_id, "f2t_death_date", os.date("%Y-%m-%d %H:%M:%S"))

        f2t_debug_log("[death] Death metadata added to room")

        -- Apply skull/blood-red styling (map component may not be loaded in all contexts)
        if f2t_map_apply_death_room_style then
            f2t_map_apply_death_room_style(room_id)
            updateMap()
        end
    else
        f2t_debug_log("[death] WARNING: Failed to lock room")
    end

    -- Show summary and complete
    f2t_death_show_summary(success ~= false, nil)
    f2t_death_complete()
end

-- ========================================
-- User Summary
-- ========================================

function f2t_death_show_summary(room_locked, cause)
    local death_hash = F2T_DEATH_STATE.death_room_hash or "unknown"
    local death_room_id = F2T_DEATH_STATE.death_room_id
    local room_name = death_room_id and roomExists(death_room_id) and getRoomName(death_room_id) or nil

    cecho("\n")
    cecho("<red>+-------------------------------------------+<reset>\n")
    cecho("<red>|<reset>              <white>DEATH RECOVERY<reset>               <red>|<reset>\n")
    cecho("<red>+-------------------------------------------+<reset>\n")
    cecho(string.format("<red>|<reset>  Death Location: <yellow>%s<reset>\n", death_hash))

    if room_name then
        -- Truncate long room names
        if #room_name > 30 then
            room_name = room_name:sub(1, 27) .. "..."
        end
        cecho(string.format("<red>|<reset>  Room: <cyan>%s<reset>\n", room_name))
    end

    cecho("<red>|<reset>  Insurance: <green>Claimed<reset>\n")
    if f2t_insurance_status() == true then
        cecho("<red>|<reset>  Re-insured: <green>Yes<reset>\n")
    else
        cecho("<red>|<reset>  Re-insured: <red>Not yet<reset>\n")
    end

    if cause == "suicide" then
        cecho("<red>|<reset>  Room Status: <dim_grey>Skipped (suicide)<reset>\n")
    elseif cause == "starvation" then
        cecho("<red>|<reset>  Room Status: <dim_grey>Skipped (starvation)<reset>\n")
    elseif cause == "safe_room" then
        cecho("<red>|<reset>  Room Status: <cyan>Safe<reset> (marked safe — use 'map room unsafe' to change)\n")
    elseif room_locked then
        cecho("<red>|<reset>  Room Status: <red>LOCKED<reset> (navigation avoids)\n")
    elseif death_room_id then
        cecho("<red>|<reset>  Room Status: <yellow>Lock failed<reset>\n")
    else
        cecho("<red>|<reset>  Room Status: <yellow>Not in map (cannot lock)<reset>\n")
    end

    cecho("<red>+-------------------------------------------+<reset>\n")
end

-- ========================================
-- Completion and Cleanup
-- ========================================

-- Tell components recovery is over and whether the player is insured again.
-- Work only resumes on insured = true; uninsured, the player is asked to get
-- insured, and getting insured from that prompt lets the work resume too.
local function announceRecovery()
    tempTimer(2, function()
        if f2t_insurance_status() == true then
            raiseEvent("f2tDeathRecovered", true)
            return
        end
        cecho("\n<red>[death]<reset> You aren't insured again yet. Another death would be permanent.\n")
        f2t_insurance_check("carrying on after this death", function()
            raiseEvent("f2tDeathRecovered", f2t_insurance_status() == true)
        end, function()
            raiseEvent("f2tDeathRecovered", false)
        end)
    end)
end

function f2t_death_complete()
    f2t_debug_log("[death] Death recovery completed")
    announceRecovery()

    -- Cleanup handlers and timers
    f2t_death_cleanup()

    -- Reset state
    F2T_DEATH_STATE.active = false
    F2T_DEATH_STATE.current_phase = "idle"
    F2T_DEATH_STATE.death_room_hash = nil
    F2T_DEATH_STATE.death_room_id = nil
    F2T_DEATH_STATE.death_cause = nil
    F2T_DEATH_STATE.stamina_was_critical = false
    if F2T_DEATH_STATE.suicide_timeout_id then
        killTimer(F2T_DEATH_STATE.suicide_timeout_id)
        F2T_DEATH_STATE.suicide_timeout_id = nil
    end
end

function f2t_death_cleanup()
    -- Nothing to clean up currently - respawn uses simple tempTimer
    -- Keep function for future use if needed
end