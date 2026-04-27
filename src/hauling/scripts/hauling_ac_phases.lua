-- Armstrong Cuthbert hauling phases
-- Implements the AC job workflow: fetch jobs -> select -> navigate to source -> accept -> collect -> navigate to dest -> deliver

--- Phase: Fetch available AC jobs from work command
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_ac_fetch_jobs()
    if F2T_HAULING_STATE.paused then
        return false
    end

    -- Deferred pause: pause between AC jobs
    if F2T_HAULING_STATE.pause_requested then
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        cecho("\n<green>[hauling]<reset> Paused between AC jobs\n")
        f2t_debug_log("[hauling/ac] Deferred pause activated between jobs")
        return false
    end

    f2t_debug_log("[hauling/ac] Starting fetch jobs phase")

    -- Check if we've reached 500 credits (stop condition)
    if f2t_ac_has_enough_credits() then
        local credits = f2t_ac_get_hauling_credits()
        cecho(string.format("\n<green>[hauling]<reset> Congratulations! You've earned %d hauling credits and can now advance to the next rank!\n", credits))
        cecho("\n<green>[hauling]<reset> Stopping hauling automation.\n")
        f2t_hauling_stop()
        return true
    end

    -- Check for 50 credit milestone message (only in Sol system)
    if not F2T_HAULING_STATE.ac_50_milestone_shown and f2t_ac_reached_50_credits() then
        -- Only show this message if currently in Sol system
        if f2t_is_in_system("Sol") then
            cecho("\n<yellow>[hauling]<reset> You've reached 50 hauling credits! You may now find more profitable jobs from players on player-operated planets.\n")
            cecho("\n<yellow>[hauling]<reset> However, I'll continue hauling in Sol for now.\n")
        end
        F2T_HAULING_STATE.ac_50_milestone_shown = true
    end

    -- Start capturing job output
    f2t_ac_start_capture()
    f2t_debug_log("[hauling/ac] Started job capture, sending work command")

    -- Send work command
    send("work")

    -- Start the capture timer - it will fire after 0.5s of no new lines
    -- Each captured line resets this timer
    f2t_ac_start_capture_timer()

    -- Transition to selecting phase - capture timer will call select function when output completes
    F2T_HAULING_STATE.current_phase = "ac_selecting_job"
    return false
end

--- Phase: Select best AC job from fetched jobs
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_ac_select_job()
    if F2T_HAULING_STATE.paused then
        return false
    end

    f2t_debug_log("[hauling/ac] Starting select job phase")

    -- Get jobs from capture
    local jobs = f2t_ac_stop_capture()
    f2t_debug_log("[hauling/ac] Stopped capture, found %d jobs", jobs and #jobs or 0)

    if not jobs or #jobs == 0 then
        cecho("\n<red>[hauling]<reset> No AC jobs available, retrying in 10 seconds...\n")
        tempTimer(10, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                and F2T_HAULING_STATE.current_phase == "ac_selecting_job" then
                f2t_hauling_phase_ac_fetch_jobs()
            end
        end)
        return false
    end

    -- Get ship capacity
    local ship_capacity = 0
    if gmcp and gmcp.char and gmcp.char.ship and gmcp.char.ship.hold then
        ship_capacity = gmcp.char.ship.hold.max or 0
    end

    if ship_capacity == 0 then
        cecho("\n<red>[hauling]<reset> Cannot determine ship capacity\n")
        f2t_hauling_stop()
        return true
    end

    -- Get current planet if at AC room
    local current_planet = f2t_ac_get_current_planet()

    -- Select best job
    local job = f2t_ac_select_best_job(jobs, current_planet, ship_capacity)

    if not job then
        cecho("\n<red>[hauling]<reset> No suitable jobs for ship capacity, retrying in 10 seconds...\n")
        tempTimer(10, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                and F2T_HAULING_STATE.current_phase == "ac_selecting_job" then
                f2t_hauling_phase_ac_fetch_jobs()
            end
        end)
        return false
    end

    -- Store selected job
    F2T_HAULING_STATE.ac_job = job
    F2T_HAULING_STATE.ac_job_taken = false

    cecho(string.format("\n<green>[hauling]<reset> Selected job %d: %d tons of %s from %s to %s (%dig/tn, %dhcr)\n",
        job.number, job.tons, job.commodity, job.source, job.destination,
        job.payment_per_ton, job.hauling_credits))

    -- Check if already at source
    if current_planet == job.source then
        f2t_debug_log("[hauling/ac] Already at source planet %s", job.source)
        F2T_HAULING_STATE.current_phase = "ac_accepting_job"
        return f2t_hauling_phase_ac_accept_job()
    else
        -- Navigate to source
        f2t_debug_log("[hauling/ac] Need to navigate to source planet %s", job.source)
        F2T_HAULING_STATE.current_phase = "ac_navigating_to_source"
        return f2t_hauling_phase_ac_navigate_to_source()
    end
end

--- Phase: Navigate to AC room at source planet
--- @return boolean True if already there, false if navigating
function f2t_hauling_phase_ac_navigate_to_source()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local job = F2T_HAULING_STATE.ac_job
    if not job then
        cecho("\n<red>[hauling]<reset> No job selected\n")
        f2t_hauling_stop()
        return true
    end

    f2t_debug_log("[hauling/ac] Navigating to source: %s", job.source)

    -- Check if already there
    local current_planet = f2t_ac_get_current_planet()
    if current_planet == job.source then
        f2t_debug_log("[hauling/ac] Already at source")
        F2T_HAULING_STATE.current_phase = "ac_accepting_job"
        return true
    end

    -- Get Fed2 hash for destination
    local hash = f2t_ac_get_room_hash(job.source)
    if not hash then
        cecho(string.format("\n<red>[hauling]<reset> Unknown AC room for planet: %s\n", job.source))
        f2t_hauling_stop()
        return true
    end

    -- Use map navigation with hash
    cecho(string.format("\n<cyan>[hauling]<reset> Navigating to AC room at %s...\n", job.source))
    local result = f2t_map_navigate(hash)

    if result == true then
        -- Map says we're already there, but verify by checking planet
        local verify_planet = f2t_ac_get_current_planet()
        if verify_planet == job.source then
            f2t_debug_log("[hauling/ac] Verified at source AC room")
            F2T_HAULING_STATE.current_phase = "ac_accepting_job"
            return f2t_hauling_phase_ac_accept_job()
        else
            -- Map was wrong, wait for actual navigation
            f2t_debug_log("[hauling/ac] Map returned true but not at correct planet (at %s, need %s), waiting for navigation",
                verify_planet or "unknown", job.source)
            return false
        end
    end

    -- result is false or nil - navigation started or needs retry
    -- Wait for speedwalk to complete (event handler will transition)
    -- Note: f2t_map_navigate may return false if current location unknown,
    -- but it will auto-retry with 'look' command
    f2t_debug_log("[hauling/ac] Waiting for navigation to complete")
    return false
end

--- Phase: Accept the AC job
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_ac_accept_job()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local job = F2T_HAULING_STATE.ac_job
    if not job then
        cecho("\n<red>[hauling]<reset> No job to accept\n")
        f2t_hauling_stop()
        return true
    end

    f2t_debug_log("[hauling/ac] Accepting job %d", job.number)

    -- Verify we're at AC room, wait if not (speedwalk might be in progress)
    if not f2t_ac_at_room() then
        f2t_debug_log("[hauling/ac] Not at AC room yet, waiting for navigation to complete")

        -- Wait and retry - customs intercept or navigation will handle getting us there
        tempTimer(1.0, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
               F2T_HAULING_STATE.current_phase == "ac_accepting_job" and
               F2T_HAULING_STATE.ac_job then
                f2t_hauling_phase_ac_accept_job()
            end
        end)
        return false
    end

    -- Clear flags for new job
    F2T_HAULING_STATE.ac_job_taken = false
    F2T_HAULING_STATE.ac_cargo_collected = false
    F2T_HAULING_STATE.ac_cargo_delivered = false
    F2T_HAULING_STATE.ac_collect_sent = false
    F2T_HAULING_STATE.ac_deliver_sent = false

    -- Send accept command
    send(string.format("ac %d", job.number))
    cecho(string.format("\n<cyan>[hauling]<reset> Accepting job %d...\n", job.number))

    -- Transition to collecting phase after brief delay to allow accept to complete
    F2T_HAULING_STATE.current_phase = "ac_collecting"
    tempTimer(1.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and F2T_HAULING_STATE.current_phase == "ac_collecting" then
            f2t_hauling_phase_ac_collect()
        end
    end)
    return false
end

--- Phase: Collect cargo from AC room
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_ac_collect()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local job = F2T_HAULING_STATE.ac_job
    if not job then
        cecho("\n<red>[hauling]<reset> No job to collect cargo for\n")
        f2t_hauling_stop()
        return true
    end

    -- Check if job was taken by someone else
    if F2T_HAULING_STATE.ac_job_taken then
        cecho("\n<yellow>[hauling]<reset> Job was taken, fetching new jobs...\n")
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        return f2t_hauling_phase_ac_fetch_jobs()
    end

    -- Check for collect errors
    if F2T_HAULING_STATE.ac_collect_error then
        cecho(string.format("\n<red>[hauling]<reset> Collect error: %s\n", F2T_HAULING_STATE.ac_collect_error))
        F2T_HAULING_STATE.ac_collect_error = nil
        -- Retry by fetching new jobs
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        return f2t_hauling_phase_ac_fetch_jobs()
    end

    -- Check if already collected
    if F2T_HAULING_STATE.ac_cargo_collected then
        cecho(string.format("\n<green>[hauling]<reset> Cargo collected: %d tons of %s\n", job.tons, job.commodity))
        F2T_HAULING_STATE.current_phase = "ac_navigating_to_dest"
        return f2t_hauling_phase_ac_navigate_to_dest()
    end

    -- Check if we've already sent collect command (prevent duplicate sends)
    if F2T_HAULING_STATE.ac_collect_sent then
        f2t_debug_log("[hauling/ac] Already sent collect command, waiting for response")
        return false
    end

    f2t_debug_log("[hauling/ac] Collecting cargo")

    -- Verify we're at AC room, or move into it if at shuttlepad
    if not f2t_ac_at_room() then
        -- Check if we're at a shuttlepad (might need to go 'north' into AC building)
        if gmcp.room.info.flags and f2t_has_value(gmcp.room.info.flags, "shuttlepad") then
            f2t_debug_log("[hauling/ac] At shuttlepad, entering AC building")
            send("north")
            -- Wait for room change, then retry collect phase
            tempTimer(0.5, function()
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                   F2T_HAULING_STATE.current_phase == "ac_collecting" and
                   F2T_HAULING_STATE.ac_job then
                    f2t_hauling_phase_ac_collect()
                end
            end)
            return false
        else
            cecho("\n<red>[hauling]<reset> Not at AC room and not at shuttlepad, cannot collect cargo\n")
            f2t_hauling_stop()
            return true
        end
    end

    -- Send collect command (only once)
    send("collect")
    cecho("\n<cyan>[hauling]<reset> Collecting cargo...\n")
    F2T_HAULING_STATE.ac_collect_sent = true

    -- Wait for success/error trigger (will set flags)
    -- Check again after brief delay to process trigger results
    tempTimer(1.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_collecting" and
           F2T_HAULING_STATE.ac_job then  -- Ensure we still have a job
            f2t_hauling_phase_ac_collect()
        end
    end)
    return false
end

--- Phase: Navigate to AC room at destination planet
--- @return boolean True if already there, false if navigating
function f2t_hauling_phase_ac_navigate_to_dest()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local job = F2T_HAULING_STATE.ac_job
    if not job then
        cecho("\n<red>[hauling]<reset> No job selected\n")
        f2t_hauling_stop()
        return true
    end

    f2t_debug_log("[hauling/ac] Navigating to destination: %s", job.destination)

    -- Check if already there
    local current_planet = f2t_ac_get_current_planet()
    if current_planet == job.destination then
        f2t_debug_log("[hauling/ac] Already at destination")
        F2T_HAULING_STATE.current_phase = "ac_delivering"
        return true
    end

    -- Get Fed2 hash for destination
    local hash = f2t_ac_get_room_hash(job.destination)
    if not hash then
        cecho(string.format("\n<red>[hauling]<reset> Unknown AC room for planet: %s\n", job.destination))
        f2t_hauling_stop()
        return true
    end

    -- Use map navigation with hash
    cecho(string.format("\n<cyan>[hauling]<reset> Navigating to AC room at %s...\n", job.destination))
    local result = f2t_map_navigate(hash)

    if result == true then
        -- Map says we're already there, but verify by checking planet
        local verify_planet = f2t_ac_get_current_planet()
        if verify_planet == job.destination then
            f2t_debug_log("[hauling/ac] Verified at destination AC room")
            F2T_HAULING_STATE.current_phase = "ac_delivering"
            return f2t_hauling_phase_ac_deliver()
        else
            -- Map was wrong, wait for actual navigation
            f2t_debug_log("[hauling/ac] Map returned true but not at correct planet (at %s, need %s), waiting for navigation",
                verify_planet or "unknown", job.destination)
            return false
        end
    end

    -- result is false or nil - navigation started or needs retry
    -- Wait for speedwalk to complete (event handler will transition)
    -- Note: f2t_map_navigate may return false if current location unknown,
    -- but it will auto-retry with 'look' command
    f2t_debug_log("[hauling/ac] Waiting for navigation to destination to complete")
    return false
end

--- Phase: Deliver cargo to AC room
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_ac_deliver()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local job = F2T_HAULING_STATE.ac_job
    if not job then
        cecho("\n<red>[hauling]<reset> No job to deliver cargo for\n")
        f2t_hauling_stop()
        return true
    end

    -- Check for deliver errors
    if F2T_HAULING_STATE.ac_deliver_error then
        cecho(string.format("\n<red>[hauling]<reset> Deliver error: %s\n", F2T_HAULING_STATE.ac_deliver_error))
        F2T_HAULING_STATE.ac_deliver_error = nil
        -- Retry by fetching new jobs
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        return f2t_hauling_phase_ac_fetch_jobs()
    end

    -- Check if already delivered
    if F2T_HAULING_STATE.ac_cargo_delivered then
        local new_credits = f2t_ac_get_hauling_credits() or 0
        local payment = F2T_HAULING_STATE.ac_payment_amount or 0

        cecho(string.format("\n<green>[hauling]<reset> Job complete! Earned %dig and %dhcr (Total: %dhcr)\n",
            payment, job.hauling_credits, new_credits))

        -- Update statistics with actual payment received
        F2T_HAULING_STATE.total_cycles = (F2T_HAULING_STATE.total_cycles or 0) + 1
        F2T_HAULING_STATE.session_profit = (F2T_HAULING_STATE.session_profit or 0) + payment

        -- Add to history
        table.insert(F2T_HAULING_STATE.commodity_history or {}, {
            commodity = job.commodity,
            cycles = 1,
            profit = payment,
            hauling_credits = job.hauling_credits
        })

        -- Reset job state
        F2T_HAULING_STATE.ac_job = nil
        F2T_HAULING_STATE.ac_cargo_collected = false
        F2T_HAULING_STATE.ac_cargo_delivered = false
        F2T_HAULING_STATE.ac_payment_amount = nil
        F2T_HAULING_STATE.ac_collect_sent = false
        F2T_HAULING_STATE.ac_deliver_sent = false
        F2T_HAULING_STATE.ac_deliver_waiting = false
        F2T_HAULING_STATE.ac_50_milestone_shown = F2T_HAULING_STATE.ac_50_milestone_shown or false

        -- Check if graceful stop was requested
        if F2T_HAULING_STATE.stopping then
            f2t_debug_log("[hauling/ac] Job complete, stopping as requested")
            f2t_hauling_do_stop()
            return true
        end

        -- Check if we should repay loan (Commander rank only)
        local should_repay, loan_amount = f2t_ac_should_repay_loan()
        if should_repay and loan_amount then
            cecho(string.format("\n<yellow>[hauling]<reset> You have enough cash to repay your loan (%dig). Repaying now...\n", loan_amount))
            f2t_debug_log("[hauling/ac] Repaying loan: %d", loan_amount)

            -- Send repay command
            send(string.format("repay %d", loan_amount))

            -- Wait briefly for confirmation, then continue
            tempTimer(1.0, function()
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                    and F2T_HAULING_STATE.current_phase == "ac_delivering" then
                    cecho("\n<green>[hauling]<reset> Loan repaid! You'll now earn more from hauling.\n")
                    -- Continue to fetch new jobs
                    F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
                    f2t_hauling_phase_ac_fetch_jobs()
                end
            end)
            return false
        end

        -- Start next job
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        return f2t_hauling_phase_ac_fetch_jobs()
    end

    -- Check if we've already sent deliver command (prevent duplicate sends)
    if F2T_HAULING_STATE.ac_deliver_sent then
        f2t_debug_log("[hauling/ac] Already sent deliver command, waiting for response")
        return false
    end

    f2t_debug_log("[hauling/ac] Delivering cargo")

    -- Verify we're at AC room, or move into it if at shuttlepad
    if not f2t_ac_at_room() then
        -- Check if we're at a shuttlepad (might need to go 'north' into AC building)
        if gmcp.room.info.flags and f2t_has_value(gmcp.room.info.flags, "shuttlepad") then
            f2t_debug_log("[hauling/ac] At shuttlepad, entering AC building")
            send("north")
            -- Wait for room change, then retry deliver phase
            tempTimer(0.5, function()
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                   F2T_HAULING_STATE.current_phase == "ac_delivering" and
                   F2T_HAULING_STATE.ac_job then
                    f2t_hauling_phase_ac_deliver()
                end
            end)
            return false
        else
            -- Not at AC room yet - wait for navigation to complete (customs intercept might be handling this)
            f2t_debug_log("[hauling/ac] Not at AC room yet, waiting for navigation to complete")
            tempTimer(1.0, function()
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                   F2T_HAULING_STATE.current_phase == "ac_delivering" and
                   F2T_HAULING_STATE.ac_job then
                    f2t_hauling_phase_ac_deliver()
                end
            end)
            return false
        end
    end

    -- Send deliver command (only once)
    send("deliver")
    cecho("\n<cyan>[hauling]<reset> Delivering cargo...\n")
    F2T_HAULING_STATE.ac_deliver_sent = true

    -- Wait for success/error trigger (will set flags)
    -- Use extended timeout if stevedores are busy, otherwise normal timeout
    local wait_time = F2T_HAULING_STATE.ac_deliver_waiting and 15.0 or 1.0

    if F2T_HAULING_STATE.ac_deliver_waiting then
        f2t_debug_log("[hauling/ac] Waiting up to 15s for stevedores to become available")
    end

    tempTimer(wait_time, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_delivering" and
           F2T_HAULING_STATE.ac_job then  -- Ensure we still have a job
            f2t_hauling_phase_ac_deliver()
        end
    end)
    return false
end

-- ========================================
-- AC Event Handlers
-- ========================================

--- Check if navigation to AC source is complete
function f2t_hauling_check_nav_to_ac_source_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "ac_navigating_to_source" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        -- Capture result immediately to prevent race conditions with next speedwalk
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/ac] Speedwalk stopped with result: %s", result or "unknown")

        -- Wait briefly for final GMCP update before processing result
        -- IMPORTANT: AC handlers verify planet location using f2t_ac_get_current_planet()
        -- which depends on gmcp.room.info. We need to wait for GMCP to settle after
        -- room change before checking location. Exchange handlers don't need this
        -- because they just transition phases without location verification.
        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "ac_navigating_to_source") then
                return
            end

            local job = F2T_HAULING_STATE.ac_job
            if not job then
                f2t_debug_log("[hauling/ac] No job in state, cannot verify source")
                return
            end

            -- Check speedwalk result and handle accordingly
            if result == "completed" then
                -- Speedwalk completed successfully - verify we're at correct planet
                local current_planet = f2t_ac_get_current_planet()
                if current_planet == job.source then
                    f2t_debug_log("[hauling/ac] Verified arrival at source planet %s", job.source)
                    f2t_hauling_transition("ac_accepting_job")
                else
                    f2t_debug_log("[hauling/ac] Speedwalk completed but not at source (at %s, need %s)",
                        current_planet or "unknown", job.source)
                    cecho(string.format("\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.source))
                    f2t_hauling_phase_ac_navigate_to_source()
                end

            elseif result == "stopped" then
                -- User manually stopped speedwalk - respect that and stop hauling
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_debug_log("[hauling/ac] User stopped navigation, stopping hauling")
                f2t_hauling_stop()

            elseif result == "failed" then
                -- Speedwalk couldn't reach destination after retries - path is blocked
                -- NOTE: AC mode fetches new jobs instead of stopping because there are many
                -- available jobs. One blocked path doesn't mean all jobs are unreachable.
                -- Exchange mode stops hauling on "failed" because the selected commodity/location
                -- is the most profitable choice - can't proceed without reaching it.
                cecho(string.format("\n<red>[hauling]<reset> Cannot reach %s (path blocked), skipping job and fetching new ones\n", job.source))
                f2t_debug_log("[hauling/ac] Navigation failed after retries, skipping job")
                F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
                f2t_hauling_phase_ac_fetch_jobs()

            else
                -- No result or unknown - treat as legacy behavior for compatibility
                f2t_debug_log("[hauling/ac] Unknown speedwalk result, using legacy verification")
                local current_planet = f2t_ac_get_current_planet()
                if current_planet == job.source then
                    f2t_hauling_transition("ac_accepting_job")
                else
                    cecho(string.format("\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.source))
                    f2t_hauling_phase_ac_navigate_to_source()
                end
            end
        end)
    end
end

--- Check if navigation to AC destination is complete
function f2t_hauling_check_nav_to_ac_dest_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "ac_navigating_to_dest" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        -- Capture result immediately to prevent race conditions with next speedwalk
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/ac] Speedwalk stopped with result: %s", result or "unknown")

        -- Wait briefly for final GMCP update before processing result
        -- (See source handler for explanation of why AC uses tempTimer)
        tempTimer(0.3, function()
            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
                    F2T_HAULING_STATE.current_phase == "ac_navigating_to_dest") then
                return
            end

            local job = F2T_HAULING_STATE.ac_job
            if not job then
                f2t_debug_log("[hauling/ac] No job in state, cannot verify destination")
                return
            end

            -- Check speedwalk result and handle accordingly
            if result == "completed" then
                -- Speedwalk completed successfully - verify we're at correct planet
                local current_planet = f2t_ac_get_current_planet()
                if current_planet == job.destination then
                    f2t_debug_log("[hauling/ac] Verified arrival at destination planet %s", job.destination)
                    f2t_hauling_transition("ac_delivering")
                else
                    f2t_debug_log("[hauling/ac] Speedwalk completed but not at destination (at %s, need %s)",
                        current_planet or "unknown", job.destination)
                    cecho(string.format("\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.destination))
                    f2t_hauling_phase_ac_navigate_to_dest()
                end

            elseif result == "stopped" then
                -- User manually stopped speedwalk - respect that and stop hauling
                cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
                f2t_debug_log("[hauling/ac] User stopped navigation, stopping hauling")
                f2t_hauling_stop()

            elseif result == "failed" then
                -- Speedwalk couldn't reach destination after retries - path is blocked
                -- (See source handler for explanation of why AC fetches new jobs vs stopping)
                cecho(string.format("\n<red>[hauling]<reset> Cannot reach %s (path blocked), skipping job and fetching new ones\n", job.destination))
                f2t_debug_log("[hauling/ac] Navigation failed after retries, skipping job")
                F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
                f2t_hauling_phase_ac_fetch_jobs()

            else
                -- No result or unknown - treat as legacy behavior for compatibility
                f2t_debug_log("[hauling/ac] Unknown speedwalk result, using legacy verification")
                local current_planet = f2t_ac_get_current_planet()
                if current_planet == job.destination then
                    f2t_hauling_transition("ac_delivering")
                else
                    cecho(string.format("\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.destination))
                    f2t_hauling_phase_ac_navigate_to_dest()
                end
            end
        end)
    end
end

--- Check if AC job selection should proceed after work command completes
function f2t_hauling_check_ac_select_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "ac_selecting_job" then
        return
    end

    f2t_debug_log("[hauling/ac] Work command output complete, selecting job")
    f2t_hauling_phase_ac_select_job()
end

--- Check if AC cargo collection should proceed after accept command
function f2t_hauling_check_ac_collect_ready()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "ac_collecting" then
        return
    end

    -- Wait a moment for triggers to fire, then check collect completion
    tempTimer(0.5, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_collecting" and
           F2T_HAULING_STATE.ac_job then  -- Ensure we still have a job and are in correct phase
            f2t_hauling_phase_ac_collect()
        end
    end)
end

--- Check if AC cargo delivery should proceed
function f2t_hauling_check_ac_deliver_ready()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "ac_delivering" then
        return
    end

    -- Wait a moment for triggers to fire, then check deliver completion
    tempTimer(0.5, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_delivering" and
           F2T_HAULING_STATE.ac_job then  -- Ensure we still have a job and are in correct phase
            f2t_hauling_phase_ac_deliver()
        end
    end)
end

--- Register AC-specific GMCP event handlers
--- @return string Event handler ID
function f2t_ac_register_handlers()
    local handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        -- Check navigation completion after brief delay for GMCP to settle
        tempTimer(0.5, function()
            f2t_hauling_check_nav_to_ac_source_complete()
            f2t_hauling_check_nav_to_ac_dest_complete()
            f2t_hauling_check_ac_select_complete()
            f2t_hauling_check_ac_collect_ready()
            f2t_hauling_check_ac_deliver_ready()
        end)
    end)

    f2t_debug_log("[hauling/ac] Registered AC event handlers")
    return handler_id
end

--- Cleanup AC event handlers
--- @param handler_id string Event handler ID to kill
function f2t_ac_cleanup_handlers(handler_id)
    if handler_id then
        killAnonymousEventHandler(handler_id)
        f2t_debug_log("[hauling/ac] Cleaned up AC event handlers")
    end
end

f2t_debug_log("[hauling/ac] AC phases module loaded")
