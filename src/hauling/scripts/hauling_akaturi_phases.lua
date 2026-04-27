-- Akaturi contract hauling phases
-- Implements the Akaturi workflow: get job -> find pickup room -> navigate -> pickup -> find delivery room -> navigate -> deliver

--- Phase: Get Akaturi job from AC room
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_akaturi_get_job()
    if F2T_HAULING_STATE.paused then
        return false
    end

    -- Deferred pause: pause between Akaturi contracts
    if F2T_HAULING_STATE.pause_requested then
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true
        F2T_HAULING_STATE.current_phase = "akaturi_getting_job"
        cecho("\n<green>[hauling]<reset> Paused between Akaturi contracts\n")
        f2t_debug_log("[hauling/akaturi] Deferred pause activated between contracts")
        return false
    end

    f2t_debug_log("[hauling/akaturi] Starting get job phase")

    -- Check if we've completed all 25 jobs
    if f2t_akaturi_is_complete() then
        local points = f2t_akaturi_get_points()
        cecho(string.format("\n<green>[hauling]<reset> Congratulations! You've completed all 25 Akaturi contracts (%d points)!\n", points))
        cecho("\n<green>[hauling]<reset> Stopping hauling automation.\n")
        f2t_hauling_stop()
        return true
    end

    -- Must be at a known Sol AC room to issue 'ak' command
    -- Akaturi contracts only work at actual AC offices, not just any shuttlepad
    local current_hash = f2t_get_current_room_hash()
    local at_known_ac_room = false

    if current_hash then
        for planet, hash in pairs(F2T_AC_ROOMS) do
            if hash == current_hash then
                at_known_ac_room = true
                f2t_debug_log("[hauling/akaturi] At known AC room: %s", planet)
                break
            end
        end
    end

    if not at_known_ac_room then
        -- Determine which AC room to navigate to
        local target_planet = "Earth"  -- Default fallback
        local current_planet = f2t_get_current_planet()

        -- Prefer AC room on current planet if it exists
        if current_planet and F2T_AC_ROOMS[current_planet] then
            target_planet = current_planet
            f2t_debug_log("[hauling/akaturi] Using AC room on current planet: %s", target_planet)
        else
            f2t_debug_log("[hauling/akaturi] Current planet has no AC room, navigating to Earth")
        end

        -- Navigate to chosen AC room
        local ac_hash = f2t_ac_get_room_hash(target_planet)
        if not ac_hash then
            cecho(string.format("\n<red>[hauling]<reset> Cannot determine AC room location for %s\n", target_planet))
            f2t_hauling_stop()
            return true
        end

        cecho(string.format("\n<cyan>[hauling]<reset> Navigating to Armstrong Cuthbert on %s...\n", target_planet))
        local result = f2t_map_navigate(ac_hash)

        if result == true then
            -- Verify we're actually at a known AC room
            local arrived_hash = f2t_get_current_room_hash()
            if arrived_hash == ac_hash then
                f2t_debug_log("[hauling/akaturi] Verified at AC room")
                -- Continue to get job
            else
                f2t_debug_log("[hauling/akaturi] Map returned true but not at expected AC room, waiting")
                return false
            end
        else
            -- Wait for navigation to complete
            f2t_debug_log("[hauling/akaturi] Waiting for navigation to AC room")
            return false
        end
    end

    -- Reset contract state for new job
    f2t_akaturi_reset_contract()

    -- Start capturing job output
    f2t_akaturi_start_job_capture()
    f2t_debug_log("[hauling/akaturi] Started job capture, sending ak command")

    -- Send ak command
    send("ak")
    cecho("\n<cyan>[hauling]<reset> Requesting Akaturi contract...\n")

    -- Transition to parsing phase - triggers will handle capture
    F2T_HAULING_STATE.current_phase = "akaturi_parsing_pickup"

    -- Wait for output to complete (prompt will trigger parsing)
    return false
end

--- Phase: Parse pickup location from job output
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_akaturi_parse_pickup()
    if F2T_HAULING_STATE.paused then
        return false
    end

    f2t_debug_log("[hauling/akaturi] Starting parse pickup phase")

    -- Get captured job lines
    local lines = f2t_akaturi_stop_job_capture()

    if not lines or #lines == 0 then
        cecho("\n<red>[hauling]<reset> No job output captured, retrying...\n")
        tempTimer(2, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                and F2T_HAULING_STATE.current_phase == "akaturi_parsing_pickup" then
                F2T_HAULING_STATE.current_phase = "akaturi_getting_job"
                f2t_hauling_phase_akaturi_get_job()
            end
        end)
        return false
    end

    -- Parse pickup location
    local planet, room = f2t_akaturi_parse_job(lines)

    if not planet or not room then
        cecho("\n<red>[hauling]<reset> Failed to parse pickup location from job output\n")
        cecho("\n<red>[hauling]<reset> Retrying...\n")
        tempTimer(2, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                and F2T_HAULING_STATE.current_phase == "akaturi_parsing_pickup" then
                F2T_HAULING_STATE.current_phase = "akaturi_getting_job"
                f2t_hauling_phase_akaturi_get_job()
            end
        end)
        return false
    end

    -- Store pickup location
    F2T_HAULING_STATE.akaturi_contract.pickup_planet = planet
    F2T_HAULING_STATE.akaturi_contract.pickup_room = room

    cecho(string.format("\n<green>[hauling]<reset> Contract assigned: Pick up package from '%s' on %s\n", room, planet))

    -- Transition to searching phase
    F2T_HAULING_STATE.current_phase = "akaturi_searching_pickup"
    return f2t_hauling_phase_akaturi_search_pickup()
end

--- Phase: Search map for pickup room
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_akaturi_search_pickup()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local contract = F2T_HAULING_STATE.akaturi_contract
    if not contract.pickup_planet or not contract.pickup_room then
        cecho("\n<red>[hauling]<reset> Missing pickup location data\n")
        f2t_hauling_stop()
        return true
    end

    f2t_debug_log("[hauling/akaturi] Searching for pickup room: %s on %s", contract.pickup_room, contract.pickup_planet)
    cecho(string.format("\n<cyan>[hauling]<reset> Searching map for '%s' on %s...\n", contract.pickup_room, contract.pickup_planet))

    -- Search map for room (synchronous)
    local matches = f2t_akaturi_search_room(contract.pickup_planet, contract.pickup_room)

    -- Check if planet not mapped
    if matches == nil then
        cecho(string.format("\n<yellow>[hauling]<reset> Planet '%s' not yet mapped\n", contract.pickup_planet))
        cecho(string.format("\n<yellow>[hauling]<reset> Navigating to %s. Please find the room manually and resume hauling.\n", contract.pickup_planet))

        -- Navigate to planet (will pause after arrival via special phase)
        F2T_HAULING_STATE.current_phase = "akaturi_navigating_to_planet_for_pickup"
        f2t_map_navigate(contract.pickup_planet)
        return false
    end

    -- Check if no matches found
    if #matches == 0 then
        -- No exact matches found - navigate to planet and pause for manual finding
        cecho(string.format("\n<yellow>[hauling]<reset> Could not find '%s' on %s in map database\n", contract.pickup_room, contract.pickup_planet))
        cecho(string.format("\n<yellow>[hauling]<reset> Navigating to %s. Please find the room manually and resume hauling.\n", contract.pickup_planet))

        -- Navigate to planet (will pause after arrival via special phase)
        F2T_HAULING_STATE.current_phase = "akaturi_navigating_to_planet_for_pickup"
        f2t_map_navigate(contract.pickup_planet)
        return false
    end

    if #matches == 1 then
        cecho(string.format("\n<green>[hauling]<reset> Found room: %s (ID: %s)\n", matches[1].name, matches[1].room_id))
    else
        cecho(string.format("\n<yellow>[hauling]<reset> Found %d rooms matching '%s', will try each one\n", #matches, contract.pickup_room))
    end

    -- Store matches and reset index
    F2T_AKATURI_STATE.pickup_matches = matches
    f2t_akaturi_reset_match_index()

    -- Transition to navigating phase
    F2T_HAULING_STATE.current_phase = "akaturi_navigating_pickup"
    return f2t_hauling_phase_akaturi_navigate_pickup()
end

--- Phase: Navigate to pickup room
--- @return boolean True if already there, false if navigating
function f2t_hauling_phase_akaturi_navigate_pickup()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local contract = F2T_HAULING_STATE.akaturi_contract
    if not contract.pickup_planet or not contract.pickup_room then
        cecho("\n<red>[hauling]<reset> Missing pickup location data\n")
        f2t_hauling_stop()
        return true
    end

    -- Get next match to try
    local room_id = f2t_akaturi_get_next_match(F2T_AKATURI_STATE.pickup_matches)

    if not room_id then
        -- No more matches to try - navigate to planet and pause
        cecho(string.format("\n<yellow>[hauling]<reset> All room matches failed. Navigating to %s.\n", contract.pickup_planet))
        cecho("\n<yellow>[hauling]<reset> Please find the pickup room manually and resume hauling.\n")

        -- Navigate to planet
        f2t_map_navigate(contract.pickup_planet)

        -- Pause hauling
        f2t_hauling_pause(true)
        return false
    end

    f2t_debug_log("[hauling/akaturi] Navigating to pickup room: %s", room_id)
    cecho(string.format("\n<cyan>[hauling]<reset> Navigating to pickup location (%d/%d)...\n",
        F2T_AKATURI_STATE.current_match_index, #F2T_AKATURI_STATE.pickup_matches))

    -- Navigate to room
    local result = f2t_map_navigate(room_id)

    if result == true then
        -- Already at destination
        f2t_debug_log("[hauling/akaturi] Already at pickup location")
        F2T_HAULING_STATE.current_phase = "akaturi_collecting"
        return f2t_hauling_phase_akaturi_collect()
    end

    -- Wait for navigation to complete
    f2t_debug_log("[hauling/akaturi] Waiting for navigation to pickup location")
    return false
end

--- Phase: Collect package and parse delivery location
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_akaturi_collect()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local contract = F2T_HAULING_STATE.akaturi_contract
    if not contract.pickup_planet or not contract.pickup_room then
        cecho("\n<red>[hauling]<reset> Missing pickup location data\n")
        f2t_hauling_stop()
        return true
    end

    -- Check if we got an error (wrong room)
    if F2T_HAULING_STATE.akaturi_pickup_error then
        f2t_debug_log("[hauling/akaturi] Pickup failed, trying next match")
        F2T_HAULING_STATE.akaturi_pickup_error = false

        -- Try next match
        F2T_HAULING_STATE.current_phase = "akaturi_navigating_pickup"
        return f2t_hauling_phase_akaturi_navigate_pickup()
    end

    -- Check if already collected
    if F2T_HAULING_STATE.akaturi_package_collected then
        -- Timer-based capture is now handling the delivery location parsing
        -- See: f2t_akaturi_reset_pickup_timer() and f2t_akaturi_process_pickup_capture()
        -- Just wait for timer to process the capture
        f2t_debug_log("[hauling/akaturi] Package collected, waiting for delivery info capture to complete")
        return false
    end

    -- Wait for navigation to complete before sending pickup
    if F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling/akaturi] Waiting for navigation to complete before pickup")
        tempTimer(0.5, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
               F2T_HAULING_STATE.current_phase == "akaturi_collecting" then
                f2t_hauling_phase_akaturi_collect()
            end
        end)
        return false
    end

    -- Check if we've already sent pickup command
    if F2T_HAULING_STATE.akaturi_pickup_sent then
        f2t_debug_log("[hauling/akaturi] Already sent pickup command, waiting for response")
        return false
    end

    f2t_debug_log("[hauling/akaturi] Collecting package")

    -- Send pickup command
    -- Note: Capture will be started by hauling_akaturi_pickup_success.lua trigger
    send("pickup")
    cecho("\n<cyan>[hauling]<reset> Picking up package...\n")
    F2T_HAULING_STATE.akaturi_pickup_sent = true

    -- Wait for pickup success trigger to fire
    -- Timer-based capture will handle delivery location parsing
    return false
end

--- Phase: Navigate to delivery room
--- @return boolean True if already there, false if navigating
function f2t_hauling_phase_akaturi_navigate_delivery()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local contract = F2T_HAULING_STATE.akaturi_contract
    if not contract.delivery_planet or not contract.delivery_room then
        cecho("\n<red>[hauling]<reset> Missing delivery location data\n")
        f2t_hauling_stop()
        return true
    end

    -- Get next match to try
    local room_id = f2t_akaturi_get_next_match(F2T_AKATURI_STATE.delivery_matches)

    if not room_id then
        -- No more matches to try
        cecho(string.format("\n<yellow>[hauling]<reset> All room matches failed. Navigating to %s.\n", contract.delivery_planet))
        cecho("\n<yellow>[hauling]<reset> Please find the delivery room manually and resume hauling.\n")

        f2t_map_navigate(contract.delivery_planet)
        f2t_hauling_pause(true)
        return false
    end

    f2t_debug_log("[hauling/akaturi] Navigating to delivery room: %s", room_id)
    cecho(string.format("\n<cyan>[hauling]<reset> Navigating to delivery location (%d/%d)...\n",
        F2T_AKATURI_STATE.current_match_index, #F2T_AKATURI_STATE.delivery_matches))

    -- Navigate to room
    local result = f2t_map_navigate(room_id)

    if result == true then
        -- Already at destination
        f2t_debug_log("[hauling/akaturi] Already at delivery location")
        F2T_HAULING_STATE.current_phase = "akaturi_delivering"
        return f2t_hauling_phase_akaturi_deliver()
    end

    -- Wait for navigation to complete
    f2t_debug_log("[hauling/akaturi] Waiting for navigation to delivery location")
    return false
end

--- Phase: Deliver package and complete contract
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_akaturi_deliver()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local contract = F2T_HAULING_STATE.akaturi_contract
    if not contract.delivery_planet or not contract.delivery_room then
        cecho("\n<red>[hauling]<reset> Missing delivery location data\n")
        f2t_hauling_stop()
        return true
    end

    -- Check if we got an error (wrong room)
    if F2T_HAULING_STATE.akaturi_delivery_error then
        f2t_debug_log("[hauling/akaturi] Delivery failed, trying next match")
        F2T_HAULING_STATE.akaturi_delivery_error = false

        -- Try next match
        F2T_HAULING_STATE.current_phase = "akaturi_navigating_delivery"
        return f2t_hauling_phase_akaturi_navigate_delivery()
    end

    -- Check if already delivered
    if F2T_HAULING_STATE.akaturi_package_delivered then
        local points = f2t_akaturi_get_points() or 0
        local payment = F2T_HAULING_STATE.akaturi_payment_amount or 0

        cecho(string.format("\n<green>[hauling]<reset> Contract complete! Earned %dig (Total points: %d/25)\n", payment, points))

        -- Update statistics
        F2T_HAULING_STATE.total_cycles = (F2T_HAULING_STATE.total_cycles or 0) + 1
        F2T_HAULING_STATE.session_profit = (F2T_HAULING_STATE.session_profit or 0) + payment

        -- Add to history
        table.insert(F2T_HAULING_STATE.commodity_history or {}, {
            commodity = contract.item or "package",
            cycles = 1,
            profit = payment
        })

        -- Reset contract state
        f2t_akaturi_reset_contract()
        F2T_HAULING_STATE.akaturi_package_collected = false
        F2T_HAULING_STATE.akaturi_package_delivered = false
        F2T_HAULING_STATE.akaturi_payment_amount = nil
        F2T_HAULING_STATE.akaturi_pickup_sent = false
        F2T_HAULING_STATE.akaturi_delivery_sent = false

        -- Check if graceful stop was requested
        if F2T_HAULING_STATE.stopping then
            f2t_debug_log("[hauling/akaturi] Contract complete, stopping as requested")
            f2t_hauling_do_stop()
            return true
        end

        -- Start next contract
        F2T_HAULING_STATE.current_phase = "akaturi_getting_job"
        return f2t_hauling_phase_akaturi_get_job()
    end

    -- Wait for navigation to complete before sending dropoff
    if F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling/akaturi] Waiting for navigation to complete before dropoff")
        tempTimer(0.5, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
               F2T_HAULING_STATE.current_phase == "akaturi_delivering" then
                f2t_hauling_phase_akaturi_deliver()
            end
        end)
        return false
    end

    -- Check if we've already sent dropoff command
    if F2T_HAULING_STATE.akaturi_delivery_sent then
        f2t_debug_log("[hauling/akaturi] Already sent dropoff command, waiting for response")
        return false
    end

    f2t_debug_log("[hauling/akaturi] Delivering package")

    -- Send dropoff command
    send("dropoff")
    cecho("\n<cyan>[hauling]<reset> Delivering package...\n")
    F2T_HAULING_STATE.akaturi_delivery_sent = true

    -- Wait for trigger to set flag
    tempTimer(1.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "akaturi_delivering" then
            f2t_hauling_phase_akaturi_deliver()
        end
    end)
    return false
end

-- ========================================
-- Akaturi Event Handlers
-- ========================================

--- Check if navigation to pickup room is complete
function f2t_hauling_check_nav_to_akaturi_pickup_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "akaturi_navigating_pickup" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/akaturi] Speedwalk stopped with result: %s", result or "unknown")

        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "akaturi_navigating_pickup") then
                return
            end

            if result == "completed" then
                f2t_debug_log("[hauling/akaturi] Arrived at pickup location")
                f2t_hauling_transition("akaturi_collecting")

            elseif result == "stopped" then
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_hauling_stop()

            elseif result == "failed" then
                cecho("\n<red>[hauling]<reset> Cannot reach pickup location, trying next match or pausing\n")
                f2t_hauling_phase_akaturi_navigate_pickup()

            else
                f2t_debug_log("[hauling/akaturi] Unknown speedwalk result, transitioning to collect phase")
                f2t_hauling_transition("akaturi_collecting")
            end
        end)
    end
end

--- Check if navigation to delivery room is complete
function f2t_hauling_check_nav_to_akaturi_delivery_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "akaturi_navigating_delivery" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/akaturi] Speedwalk stopped with result: %s", result or "unknown")

        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "akaturi_navigating_delivery") then
                return
            end

            if result == "completed" then
                f2t_debug_log("[hauling/akaturi] Arrived at delivery location")
                f2t_hauling_transition("akaturi_delivering")

            elseif result == "stopped" then
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_hauling_stop()

            elseif result == "failed" then
                cecho("\n<red>[hauling]<reset> Cannot reach delivery location, trying next match or pausing\n")
                f2t_hauling_phase_akaturi_navigate_delivery()

            else
                f2t_debug_log("[hauling/akaturi] Unknown speedwalk result, transitioning to deliver phase")
                f2t_hauling_transition("akaturi_delivering")
            end
        end)
    end
end

--- Check if navigation to AC room is complete (for getting job)
function f2t_hauling_check_nav_to_ac_for_akaturi_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "akaturi_getting_job" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/akaturi] Speedwalk to AC room stopped with result: %s", result or "unknown")

        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "akaturi_getting_job") then
                return
            end

            if result == "completed" then
                -- Verify we're at AC room
                if f2t_ac_at_room() then
                    f2t_debug_log("[hauling/akaturi] Arrived at AC room, retrying get job")
                    f2t_hauling_phase_akaturi_get_job()
                else
                    cecho("\n<red>[hauling]<reset> Navigation complete but not at AC room\n")
                    f2t_hauling_stop()
                end

            elseif result == "stopped" then
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_hauling_stop()

            elseif result == "failed" then
                cecho("\n<red>[hauling]<reset> Cannot reach AC room, stopping hauling\n")
                f2t_hauling_stop()

            else
                f2t_debug_log("[hauling/akaturi] Unknown speedwalk result")
                if f2t_ac_at_room() then
                    f2t_hauling_phase_akaturi_get_job()
                end
            end
        end)
    end
end

--- Check if navigation to planet for manual pickup is complete
function f2t_hauling_check_nav_to_planet_for_pickup_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "akaturi_navigating_to_planet_for_pickup" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/akaturi] Speedwalk to planet stopped with result: %s", result or "unknown")

        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "akaturi_navigating_to_planet_for_pickup") then
                return
            end

            if result == "completed" or result == nil then
                -- Navigation complete - pause for manual room finding
                local room_name = F2T_HAULING_STATE.akaturi_contract.pickup_room or "the pickup room"
                cecho(string.format("\n<yellow>[hauling]<reset> Arrived at planet. Please find '%s' manually.\n", room_name))
                cecho("\n<dim_grey>Run 'haul resume' when you're at the correct room<reset>\n")
                f2t_hauling_pause(true)

            elseif result == "stopped" then
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_hauling_stop()

            elseif result == "failed" then
                cecho("\n<red>[hauling]<reset> Cannot reach planet, stopping hauling\n")
                f2t_hauling_stop()
            end
        end)
    end
end

--- Check if navigation to planet for manual delivery is complete
function f2t_hauling_check_nav_to_planet_for_delivery_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "akaturi_navigating_to_planet_for_delivery" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/akaturi] Speedwalk to planet stopped with result: %s", result or "unknown")

        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "akaturi_navigating_to_planet_for_delivery") then
                return
            end

            if result == "completed" or result == nil then
                -- Navigation complete - pause for manual room finding
                local room_name = F2T_HAULING_STATE.akaturi_contract.delivery_room or "the delivery room"
                cecho(string.format("\n<yellow>[hauling]<reset> Arrived at planet. Please find '%s' manually.\n", room_name))
                cecho("\n<dim_grey>Run 'haul resume' when you're at the correct room<reset>\n")
                f2t_hauling_pause(true)

            elseif result == "stopped" then
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_hauling_stop()

            elseif result == "failed" then
                cecho("\n<red>[hauling]<reset> Cannot reach planet, stopping hauling\n")
                f2t_hauling_stop()
            end
        end)
    end
end

--- Register Akaturi-specific GMCP event handlers
--- @return string Event handler ID
function f2t_akaturi_register_handlers()
    local handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        tempTimer(0.5, function()
            f2t_hauling_check_nav_to_ac_for_akaturi_complete()
            f2t_hauling_check_nav_to_akaturi_pickup_complete()
            f2t_hauling_check_nav_to_akaturi_delivery_complete()
            f2t_hauling_check_nav_to_planet_for_pickup_complete()
            f2t_hauling_check_nav_to_planet_for_delivery_complete()
        end)
    end)

    f2t_debug_log("[hauling/akaturi] Registered Akaturi event handlers")
    return handler_id
end

--- Cleanup Akaturi event handlers
--- @param handler_id string Event handler ID to kill
function f2t_akaturi_cleanup_handlers(handler_id)
    if handler_id then
        killAnonymousEventHandler(handler_id)
        f2t_debug_log("[hauling/akaturi] Cleaned up Akaturi event handlers")
    end
end

f2t_debug_log("[hauling/akaturi] Akaturi phases module loaded")
