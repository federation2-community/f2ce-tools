-- Armstrong Cuthbert hauling phases
-- Implements the AC job workflow: select -> navigate to source -> accept -> collect -> navigate to dest -> deliver
--
-- Job selection and accept/collect/deliver confirmation are all driven off
-- live GMCP data (gmcp.jobs.board, gmcp.char.job) rather than command output
-- scraping. Each phase function double-checks GMCP state before acting, and
-- also acts as its own reactive handler: f2t_ac_register_handlers() re-calls
-- whichever phase is current whenever the relevant GMCP data changes, so
-- transitions happen within milliseconds of the server pushing an update.
-- tempTimer() safety nets remain solely as a fallback in case a GMCP push is
-- ever missed -- they are not the primary detection mechanism.

--- Phase: Select the best AC job from the live job board
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

    -- Check if we've reached 500 credits (stop condition)
    if f2t_ac_has_enough_credits() then
        local credits = f2t_ac_get_hauling_credits()
        cecho(string.format(
            "\n<green>[hauling]<reset> Congratulations! You've earned %d hauling credits " ..
            "and can now advance to the next rank!\n",
            credits))
        cecho("\n<green>[hauling]<reset> Stopping hauling automation.\n")
        f2t_hauling_stop()
        return true
    end

    -- Check for 50 credit milestone message (only in Sol system)
    if not F2T_HAULING_STATE.ac_50_milestone_shown and f2t_ac_reached_50_credits() then
        -- Only show this message if currently in Sol system
        if f2t_is_in_system("Sol") then
            cecho("\n<yellow>[hauling]<reset> You've reached 50 hauling credits! You may now find more profitable " ..
                "jobs from players on player-operated planets.\n")
            cecho("\n<yellow>[hauling]<reset> However, I'll continue hauling in Sol for now.\n")
        end
        F2T_HAULING_STATE.ac_50_milestone_shown = true
    end

    F2T_HAULING_STATE.current_phase = "ac_selecting_job"
    return f2t_hauling_phase_ac_select_job()
end

--- Phase: Select best AC job from the live gmcp.jobs.board
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_ac_select_job()
    if F2T_HAULING_STATE.paused then
        return false
    end

    local jobs = f2t_ac_get_board()

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
        f2t_debug_log("[hauling/ac] No suitable job on board (%d listed), waiting for board update", #jobs)
        -- gmcp.jobs.board handler re-calls this the instant the board changes;
        -- this timer is just a fallback in case a push is ever missed
        tempTimer(10, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                and F2T_HAULING_STATE.current_phase == "ac_selecting_job" then
                f2t_hauling_phase_ac_select_job()
            end
        end)
        return false
    end

    -- Store selected job
    F2T_HAULING_STATE.ac_job = job
    F2T_HAULING_STATE.ac_accept_sent = false
    F2T_HAULING_STATE.ac_collect_sent = false
    F2T_HAULING_STATE.ac_deliver_sent = false

    cecho(string.format("\n<green>[hauling]<reset> Selected job %d: %d tons of %s from %s to %s (%dig/tn, %dhcr)\n",
        job.id, job.quantity, job.commodity, job.source, job.destination,
        job.payment, job.credits))

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
            f2t_debug_log(
                "[hauling/ac] Map returned true but not at correct planet (at %s, need %s), waiting for navigation",
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

    -- Already holding this job -- the accept landed
    if f2t_ac_current_job_matches(job) then
        f2t_debug_log("[hauling/ac] Job %d accepted", job.id)
        F2T_HAULING_STATE.current_phase = "ac_collecting"
        return f2t_hauling_phase_ac_collect()
    end

    -- Verify we're at AC room, wait if not (speedwalk might be in progress)
    if not f2t_ac_at_room() then
        f2t_debug_log("[hauling/ac] Not at AC room yet, waiting for navigation to complete")

        tempTimer(1.0, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
               F2T_HAULING_STATE.current_phase == "ac_accepting_job" and
               F2T_HAULING_STATE.ac_job then
                f2t_hauling_phase_ac_accept_job()
            end
        end)
        return false
    end

    if F2T_HAULING_STATE.ac_accept_sent then
        -- Already asked for it. gmcp.jobs.board is realtime, so if the job
        -- has dropped off the board and we still don't hold it, someone else
        -- got there first.
        if not f2t_ac_board_has_job(job.id) then
            cecho(string.format("\n<yellow>[hauling]<reset> Job %d was taken, fetching new jobs...\n", job.id))
            f2t_debug_log("[hauling/ac] Job %d no longer on board and not accepted, reselecting", job.id)
            F2T_HAULING_STATE.ac_job = nil
            F2T_HAULING_STATE.ac_accept_sent = false
            F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
            return f2t_hauling_phase_ac_fetch_jobs()
        end
        f2t_debug_log("[hauling/ac] Accept sent, waiting for gmcp.char.job to confirm")
        return false
    end

    -- Clear flags for new job
    F2T_HAULING_STATE.ac_collect_sent = false
    F2T_HAULING_STATE.ac_deliver_sent = false

    -- Send accept command
    F2T_HAULING_STATE.ac_accept_sent = true
    send(string.format("ac %d", job.id))
    cecho(string.format("\n<cyan>[hauling]<reset> Accepting job %d...\n", job.id))

    -- gmcp.char.job normally confirms within milliseconds via the event
    -- handler; this is just a safety net in case an update is ever missed
    tempTimer(3.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_accepting_job" and
           F2T_HAULING_STATE.ac_job then
            f2t_hauling_phase_ac_accept_job()
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

    local current = f2t_ac_get_current_job()
    if not current or not f2t_ac_current_job_matches(job) then
        -- Lost the accepted job somehow -- reselect
        cecho("\n<yellow>[hauling]<reset> Job no longer active, fetching new jobs...\n")
        f2t_debug_log("[hauling/ac] gmcp.char.job no longer matches accepted job, reselecting")
        F2T_HAULING_STATE.ac_job = nil
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        return f2t_hauling_phase_ac_fetch_jobs()
    end

    -- Check if already collected
    if current.collected then
        cecho(string.format("\n<green>[hauling]<reset> Cargo collected: %d tons of %s\n", job.quantity, job.commodity))
        F2T_HAULING_STATE.current_phase = "ac_navigating_to_dest"
        return f2t_hauling_phase_ac_navigate_to_dest()
    end

    -- Check if we've already sent collect command (prevent duplicate sends)
    if F2T_HAULING_STATE.ac_collect_sent then
        f2t_debug_log("[hauling/ac] Collect sent, waiting for gmcp.char.job.collected")
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

    -- gmcp.char.job.collected normally flips within milliseconds via the
    -- event handler; this is just a safety net in case an update is ever missed
    tempTimer(3.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_collecting" and
           F2T_HAULING_STATE.ac_job then
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
            f2t_debug_log(
                "[hauling/ac] Map returned true but not at correct planet (at %s, need %s), waiting for navigation",
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

    -- gmcp.char.job clears the instant delivery is confirmed by the server --
    -- if we no longer hold this job, the delivery went through.
    if not f2t_ac_current_job_matches(job) then
        local new_credits = f2t_ac_get_hauling_credits() or 0

        cecho(string.format("\n<green>[hauling]<reset> Job complete! Earned %dig and %dhcr (Total: %dhcr)\n",
            job.totalValue, job.credits, new_credits))

        -- Update statistics with the job's own payment fields (fixed at accept time)
        F2T_HAULING_STATE.total_cycles = (F2T_HAULING_STATE.total_cycles or 0) + 1
        F2T_HAULING_STATE.session_profit = (F2T_HAULING_STATE.session_profit or 0) + job.totalValue

        -- Add to history
        table.insert(F2T_HAULING_STATE.commodity_history or {}, {
            commodity = job.commodity,
            cycles = 1,
            profit = job.totalValue,
            hauling_credits = job.credits
        })

        -- Reset job state
        F2T_HAULING_STATE.ac_job = nil
        F2T_HAULING_STATE.ac_accept_sent = false
        F2T_HAULING_STATE.ac_collect_sent = false
        F2T_HAULING_STATE.ac_deliver_sent = false
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
            cecho(string.format(
                "\n<yellow>[hauling]<reset> You have enough cash to repay your loan (%dig). Repaying now...\n",
                loan_amount))
            f2t_debug_log("[hauling/ac] Repaying loan: %d", loan_amount)

            send(string.format("repay %d", loan_amount))

            -- Confirm via gmcp.char.vitals as soon as the loan clears, with a
            -- short fallback in case the push is ever missed
            local watch_id
            local function continueAfterRepay()
                if watch_id then
                    killAnonymousEventHandler(watch_id)
                    watch_id = nil
                end
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                    and F2T_HAULING_STATE.current_phase == "ac_delivering" then
                    cecho("\n<green>[hauling]<reset> Loan repaid! You'll now earn more from hauling.\n")
                    F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
                    f2t_hauling_phase_ac_fetch_jobs()
                end
            end
            watch_id = registerAnonymousEventHandler("gmcp.char.vitals", function()
                if f2t_ac_get_loan_amount() == 0 then
                    continueAfterRepay()
                end
            end)
            tempTimer(5.0, continueAfterRepay)
            return false
        end

        -- Start next job
        F2T_HAULING_STATE.current_phase = "ac_fetching_jobs"
        return f2t_hauling_phase_ac_fetch_jobs()
    end

    -- Check if we've already sent deliver command (prevent duplicate sends)
    if F2T_HAULING_STATE.ac_deliver_sent then
        f2t_debug_log("[hauling/ac] Deliver sent, waiting for gmcp.char.job to clear")
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

    -- Send deliver command (only once). If stevedores are busy the game
    -- queues the delivery and gmcp.char.job simply won't clear until it's
    -- actually done -- no need to resend or detect that state specially.
    send("deliver")
    cecho("\n<cyan>[hauling]<reset> Delivering cargo...\n")
    F2T_HAULING_STATE.ac_deliver_sent = true

    -- gmcp.char.job normally clears within milliseconds of the delivery
    -- actually completing; this is just a safety net in case an update is
    -- ever missed. Long timeout since stevedore waits can run ~15s.
    tempTimer(20.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "ac_delivering" and
           F2T_HAULING_STATE.ac_job then
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
    if not F2T_SPEEDWALK_ACTIVE and not F2T_SPEEDWALK_CUSTOMS_PENDING then
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
                    cecho(string.format(
                        "\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.source))
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
                cecho(string.format(
                    "\n<red>[hauling]<reset> Cannot reach %s (path blocked), skipping job and fetching new ones\n",
                    job.source))
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
                    cecho(string.format(
                        "\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.source))
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
    if not F2T_SPEEDWALK_ACTIVE and not F2T_SPEEDWALK_CUSTOMS_PENDING then
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
                    cecho(string.format(
                        "\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.destination))
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
                cecho(string.format(
                    "\n<red>[hauling]<reset> Cannot reach %s (path blocked), skipping job and fetching new ones\n",
                    job.destination))
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
                    cecho(string.format(
                        "\n<yellow>[hauling]<reset> Navigation interrupted, resuming to %s...\n", job.destination))
                    f2t_hauling_phase_ac_navigate_to_dest()
                end
            end
        end)
    end
end

--- Re-run job selection when the live board changes
function f2t_hauling_check_ac_board_update()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "ac_selecting_job" then
        return
    end

    f2t_debug_log("[hauling/ac] Job board updated, re-selecting")
    f2t_hauling_phase_ac_select_job()
end

--- Re-run the current AC phase when gmcp.char.job changes (accept/collect/
--- deliver confirmation all land here)
function f2t_hauling_check_ac_job_update()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    local phase = F2T_HAULING_STATE.current_phase
    if phase == "ac_accepting_job" then
        f2t_hauling_phase_ac_accept_job()
    elseif phase == "ac_collecting" then
        f2t_hauling_phase_ac_collect()
    elseif phase == "ac_delivering" then
        f2t_hauling_phase_ac_deliver()
    end
end

--- Register AC-specific GMCP event handlers
--- @return table Map of handler ids, keyed by GMCP event name
function f2t_ac_register_handlers()
    local handlers = {}

    -- Map navigation completion (speedwalk state, unrelated to job data)
    handlers.room_info = registerAnonymousEventHandler("gmcp.room.info", function()
        tempTimer(0.5, function()
            f2t_hauling_check_nav_to_ac_source_complete()
            f2t_hauling_check_nav_to_ac_dest_complete()
        end)
    end)

    -- Live job board (job selection)
    handlers.jobs_board = registerAnonymousEventHandler("gmcp.jobs.board", f2t_hauling_check_ac_board_update)
    handlers.jobs = registerAnonymousEventHandler("gmcp.jobs", f2t_hauling_check_ac_board_update)

    -- Current contract (accept/collect/deliver confirmation)
    handlers.char_job = registerAnonymousEventHandler("gmcp.char.job", f2t_hauling_check_ac_job_update)

    f2t_debug_log("[hauling/ac] Registered AC event handlers")
    return handlers
end

--- Cleanup AC event handlers
--- @param handlers table Map of handler ids returned by f2t_ac_register_handlers
function f2t_ac_cleanup_handlers(handlers)
    if not handlers then
        return
    end
    for _, handler_id in pairs(handlers) do
        killAnonymousEventHandler(handler_id)
    end
    f2t_debug_log("[hauling/ac] Cleaned up AC event handlers")
end

f2t_debug_log("[hauling/ac] AC phases module loaded")
