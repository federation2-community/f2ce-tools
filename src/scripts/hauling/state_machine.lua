-- Hauling State Machine
-- Manages the buy/sell cycle for automated commodity trading

-- Hand the stamina monitor our pause/resume, when that module is installed.
-- Called on resume too: a failed food run leaves hauling paused, and the
-- monitor must be watching again once the player resumes.
function f2t_hauling_register_stamina()
    if not f2t_stamina_register_client then return end
    f2t_stamina_register_client({
        pause_callback = f2t_hauling_pause,
        resume_callback = f2t_hauling_resume,
        check_active = function()
            return F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
        end
    })
end

-- Start hauling automation
--- @param requested_mode string|nil Strategy to run (see F2T_HAUL_STRATEGIES); nil uses hauling/mode
function f2t_hauling_start(requested_mode)
    if F2T_HAULING_STATE.active then
        cecho("\n<yellow>[hauling]<reset> Hauling already active\n")
        return
    end

    if not f2t_insurance_allows() then
        f2t_insurance_check("hauling", function()
            if not F2T_HAULING_STATE.active then f2t_hauling_start(requested_mode) end
        end)
        return
    end

    local strategy, strategy_note = f2t_hauling_resolve_strategy(requested_mode)
    if not strategy then
        cecho(string.format("\n<red>[hauling]<reset> %s\n", strategy_note or "Cannot determine hauling mode"))
        return
    end
    if strategy_note then
        cecho(string.format("\n<yellow>[hauling]<reset> %s\n", strategy_note))
    end

    -- Check if cargo hold is empty
    local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if cargo and #cargo > 0 then
        cecho(string.format(
            "\n<red>[hauling]<reset> Cargo hold must be empty to start hauling (%d lots currently loaded)\n",
            #cargo))
        cecho("\n<dim_grey>Use 'bs' to sell all cargo first<reset>\n")
        return
    end

    cecho("\n<green>[hauling]<reset> Starting automated hauling...\n")

    F2T_HAULING_STATE.active = true
    F2T_HAULING_STATE.paused = false
    F2T_HAULING_STATE.pause_requested = false
    F2T_HAULING_STATE.stopping = false
    F2T_HAULING_STATE.cycle_count = 0
    raiseEvent("f2tHaulingStatusChanged")

    -- Set navigation ownership for hauling
    -- Callback handles customs interrupt by requesting auto-resume
    if f2t_map_set_nav_owner then
        f2t_map_set_nav_owner("hauling", function(reason)
            f2t_debug_log("[hauling] Navigation interrupted by %s", reason)
            -- Hauling uses auto-resume - customs handler will resume navigation
            return { auto_resume = true }
        end)
    end

    -- Reset statistics for new session
    F2T_HAULING_STATE.total_cycles = 0
    F2T_HAULING_STATE.session_profit = 0
    F2T_HAULING_STATE.commodity_history = {}
    F2T_HAULING_STATE.po_deficit_cycles = 0
    F2T_HAULING_STATE.po_excess_cycles = 0

    -- Load margin threshold from settings
    F2T_HAULING_STATE.margin_threshold_pct = f2t_settings_get("hauling", "margin_threshold")

    f2t_debug_log("[hauling] Starting new hauling session (margin threshold: %.0f%%)",
        F2T_HAULING_STATE.margin_threshold_pct)

    -- Cancel any standalone stamina prompt (hauling will handle stamina automatically)
    if f2t_stamina_cancel_standalone_prompt then
        f2t_stamina_cancel_standalone_prompt()
    end

    f2t_hauling_register_stamina()

    -- NOTE: Don't start completion timer yet - it will be started when entering buying/selling phase

    -- Store mode and display to user
    local strategy_def = F2T_HAUL_STRATEGIES[strategy]
    local mode = strategy_def.mode
    F2T_HAULING_STATE.mode = mode
    F2T_HAULING_STATE.strategy = strategy
    F2T_HAULING_STATE.po_deficit_only = strategy_def.deficitOnly or false
    local rank = f2t_get_rank() or "unknown"
    local mode_name = f2t_hauling_get_mode_name(mode)
    if strategy_def.deficitOnly then mode_name = mode_name .. " (deficits only)" end

    cecho(string.format("\n<cyan>[hauling]<reset> Rank: %s - Using %s\n", rank, mode_name))
    f2t_debug_log("[hauling] Strategy selected: %s (%s)", strategy, mode_name)

    -- Exchange and PO modes depend on other components.  Exchange needs the
    -- commodities module (price analysis + bulk buy/sell); PO additionally needs
    -- the po module (remote exchange capture).  If a dependency is absent, fail
    -- cleanly instead of erroring on the first nil call.  AC and Akaturi modes
    -- are fully self-contained and reach none of this.
    if mode == "exchange" and not f2t_price_get_all_data then
        cecho("\n<red>[hauling]<reset> " .. mode_name .. " requires the commodities module, which is not installed.\n")
        cecho("<dim_grey>Install the commodities component to enable exchange hauling.<reset>\n")
        f2t_hauling_do_stop()
        return
    end
    if mode == "po" and not (f2t_price_get_all_data and f2t_po_capture_exchange) then
        cecho("\n<red>[hauling]<reset> " .. mode_name .. " requires the commodities and po modules, " ..
            "which are not installed.\n")
        cecho("<dim_grey>Install the commodities and po components to enable PO hauling, " ..
            "or use 'haul start exchange'.<reset>\n")
        f2t_hauling_do_stop()
        return
    end

    -- Exchange and PO modes both price-check commodities remotely (analyzing phase,
    -- PO sell search) and require the Remote Price Check Service tool. Check up
    -- front rather than letting the sequence silently stall in "analyzing" the
    -- first time a price-check call is gated deep inside the phase logic.
    if mode == "exchange" or mode == "po" then
        local price_form, price_reason = f2tPriceRemoteForm()
        if not price_form then
            cecho(string.format("\n<red>[hauling]<reset> %s: %s\n", mode_name, price_reason))
            cecho("<dim_grey>See: https://federation2.com/guide/#sec-230.20<reset>\n")
            f2t_hauling_do_stop()
            return
        end
    end

    -- PO mode: validate ship capacity
    if mode == "po" then
        local hold = gmcp.char and gmcp.char.ship and gmcp.char.ship.hold
        if not hold or not hold.max then
            cecho("\n<red>[hauling]<reset> Cannot determine ship capacity\n")
            f2t_hauling_do_stop()
            return
        end

        local ship_lots = math.floor(hold.max / 75)
        if ship_lots < 7 then
            cecho(string.format(
                "\n<red>[hauling]<reset> Ship too small for PO hauling " ..
                "(need at least 525 tons / 7 lots, have %d tons / %d lots)\n",
                hold.max, ship_lots))
            f2t_hauling_do_stop()
            return
        end

        F2T_HAULING_STATE.po_ship_lots = ship_lots
        f2t_debug_log("[hauling/po] Ship capacity: %d lots (%d tons)", ship_lots, hold.max)

        if ship_lots >= 14 then
            cecho(string.format("\n<cyan>[hauling]<reset> Ship capacity: %d lots (bundling enabled)\n", ship_lots))
        else
            cecho(string.format("\n<cyan>[hauling]<reset> Ship capacity: %d lots\n", ship_lots))
        end
    end

    -- Register mode-specific event handlers
    if mode == "ac" then
        F2T_HAULING_STATE.handler_id = f2t_ac_register_handlers()
    elseif mode == "exchange" then
        F2T_HAULING_STATE.handler_id = f2t_exchange_register_handlers()
    elseif mode == "akaturi" then
        F2T_HAULING_STATE.handler_id = f2t_akaturi_register_handlers()
    elseif mode == "po" then
        F2T_HAULING_STATE.handler_id = f2t_po_register_handlers()
    end

    -- Hold brief for the whole session rather than letting every leg of every
    -- speedwalk toggle brief/full on its own.
    f2t_map_brief_hold_acquire("hauling")

    -- Get starting phase for this mode and transition
    local starting_phase = f2t_hauling_get_starting_phase(mode)

    if not starting_phase then
        cecho(string.format("\n<red>[hauling]<reset> Unknown starting phase for mode: %s\n", mode))
        f2t_hauling_do_stop()
        return
    end

    f2t_hauling_transition(starting_phase)
end

-- Gracefully stop hauling automation (finish current cycle first)
function f2t_hauling_stop()
    if not F2T_HAULING_STATE.active then
        cecho("\n<yellow>[hauling]<reset> Hauling not active\n")
        return
    end

    -- Stop supersedes any pending deferred pause
    F2T_HAULING_STATE.pause_requested = false

    -- For AC jobs, check if we've accepted a job (even if cargo not yet collected)
    -- We should finish any job that's past the selection phase
    if F2T_HAULING_STATE.mode == "ac" and F2T_HAULING_STATE.ac_job then
        local phase = F2T_HAULING_STATE.current_phase
        -- If we're in a phase where we've committed to a job, finish it
        if phase == "ac_accepting_job" or phase == "ac_collecting" or
           phase == "ac_navigating_to_dest" or phase == "ac_delivering" then
            F2T_HAULING_STATE.stopping = true
            local job = F2T_HAULING_STATE.ac_job
            local current = f2t_ac_get_current_job()

            -- Different message depending on whether we have cargo
            if current and current.collected then
                cecho(string.format("\n<green>[hauling]<reset> Stopping after delivering cargo (%s to %s)...\n",
                    job.commodity, job.destination))
            else
                cecho(string.format(
                    "\n<green>[hauling]<reset> Stopping after completing job %d (%s from %s to %s)...\n",
                    job.id, job.commodity, job.source, job.destination))
            end

            cecho("\n<dim_grey>Use 'haul terminate' to stop immediately<reset>\n")
            f2t_debug_log("[hauling/ac] Graceful stop requested, will finish job %d (phase: %s)",
                job.id, phase)
            return
        end
        -- Otherwise (fetching/selecting phase), we can stop immediately below
    end

    -- Akaturi: a package in hand is delivered first; otherwise stop now
    if F2T_HAULING_STATE.mode == "akaturi" then
        local contract = f2t_akaturi_contract()
        if F2T_HAULING_STATE.current_phase == "akaturi_working_dropoff" and contract then
            F2T_HAULING_STATE.stopping = true
            cecho(string.format("\n<green>[hauling]<reset> Stopping after delivering the %s to %s...\n",
                contract.package or "package", contract.deliveryPlanet))
            cecho("\n<dim_grey>Use 'haul terminate' to stop immediately<reset>\n")
            return
        end
        f2t_akaturi_visit_cancel("hauling")
        if F2T_SPEEDWALK_ACTIVE then f2t_map_speedwalk_stop() end
        f2t_hauling_do_stop()
        return
    end

    -- For PO hauling, check if we have cargo in hold
    if F2T_HAULING_STATE.mode == "po" then
        local po_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
        if po_cargo and #po_cargo > 0 then
            F2T_HAULING_STATE.stopping = true
            cecho(string.format(
                "\n<green>[hauling]<reset> Stopping after selling cargo (%d lots in hold)...\n", #po_cargo))
            cecho("\n<dim_grey>Use 'haul terminate' to stop immediately<reset>\n")
            f2t_debug_log("[hauling/po] Graceful stop requested, will finish selling %d lots", #po_cargo)
            return
        end
        -- No cargo, stop immediately
        if F2T_SPEEDWALK_ACTIVE then
            f2t_debug_log("[hauling] Stopping speedwalk due to immediate stop")
            f2t_map_speedwalk_stop()
        end
        f2t_hauling_do_stop()
        return
    end

    -- For exchange hauling, check if we have cargo in hold
    local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if cargo and #cargo > 0 then
        -- Set stopping flag and let current cycle complete
        F2T_HAULING_STATE.stopping = true
        cecho(string.format(
            "\n<green>[hauling]<reset> Stopping after current cycle completes (%d lots in hold)...\n", #cargo))
        cecho("\n<dim_grey>Use 'haul terminate' to stop immediately<reset>\n")
        f2t_debug_log("[hauling] Graceful stop requested, will finish selling %d lots", #cargo)
    else
        -- No cargo/job, stop immediately
        -- Stop any active speedwalk since we're stopping now
        if F2T_SPEEDWALK_ACTIVE then
            f2t_debug_log("[hauling] Stopping speedwalk due to immediate stop")
            f2t_map_speedwalk_stop()
        end
        f2t_hauling_do_stop()
    end
end

-- Called by death recovery. A death loses cargo and AC jobs, so those runs end;
-- an Akaturi contract survives an insured death, so that run pauses and
-- resumes on f2tDeathRecovered (see akaturi_phases.lua).
function f2t_hauling_on_death()
    if not F2T_HAULING_STATE.active then return end
    if F2T_HAULING_STATE.mode ~= "akaturi" then
        f2t_hauling_terminate()
        return
    end
    if not F2T_HAULING_STATE.paused then f2t_hauling_pause(true) end
    F2T_HAULING_STATE.paused_for_death = true
    raiseEvent("f2tHaulingStatusChanged")
end

-- Terminate hauling automation immediately
function f2t_hauling_terminate()
    if not F2T_HAULING_STATE.active then
        cecho("\n<yellow>[hauling]<reset> Hauling not active\n")
        return
    end

    cecho("\n<yellow>[hauling]<reset> Terminating hauling immediately...\n")
    f2t_debug_log("[hauling] Immediate termination requested")

    F2T_HAULING_STATE.pause_requested = false

    -- Stop any active speedwalk
    if F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling] Stopping speedwalk due to termination")
        f2t_map_speedwalk_stop()
    end

    f2t_hauling_do_stop()
end

-- Internal function to actually stop hauling (preserves statistics)
function f2t_hauling_do_stop()
    -- Clear navigation ownership
    if f2t_map_clear_nav_owner then
        f2t_map_clear_nav_owner()
    end

    -- Released before the safe room run so that walk handles its own mode
    -- switching like any other standalone speedwalk.
    f2t_map_brief_hold_release("hauling")

    -- Check if we should navigate to safe room
    local use_safe_room = f2t_settings_get("hauling", "use_safe_room")
    local safe_room = f2t_settings_get("hauling", "safe_room")

    if use_safe_room and safe_room and safe_room ~= "" then
        cecho(string.format("\n<green>[hauling]<reset> Returning to safe room: <cyan>%s<reset>\n", safe_room))
        f2t_debug_log("[hauling] Navigating to safe room: %s", safe_room)

        f2t_map_navigate(safe_room)

        -- Wait for navigation to complete before showing final stats
        tempTimer(2, function()
            f2t_hauling_finish_stop()
        end)
    else
        -- Safe room disabled or not configured, stop immediately
        f2t_hauling_finish_stop()
    end
end

-- Complete the stop sequence (called after safe room navigation)
function f2t_hauling_finish_stop()
    -- Show final statistics
    if F2T_HAULING_STATE.total_cycles > 0 then
        cecho("\n<green>[hauling]<reset> Final Session Statistics:\n")
        cecho(string.format("  Total Cycles: <cyan>%d<reset>\n", F2T_HAULING_STATE.total_cycles))

        if F2T_HAULING_STATE.mode == "po" or
           (F2T_HAULING_STATE.po_deficit_cycles > 0 or F2T_HAULING_STATE.po_excess_cycles > 0) then
            cecho(string.format("  Deficit Cycles: <orange>%d<reset>\n",
                F2T_HAULING_STATE.po_deficit_cycles))
            cecho(string.format("  Excess Cycles: <yellow>%d<reset>\n",
                F2T_HAULING_STATE.po_excess_cycles))
        else
            cecho(string.format("  Session Profit: <green>%d ig<reset>\n", F2T_HAULING_STATE.session_profit))
            local avg_profit = math.floor(F2T_HAULING_STATE.session_profit / F2T_HAULING_STATE.total_cycles)
            cecho(string.format("  Avg Profit/Cycle: <cyan>%d ig<reset>\n", avg_profit))
        end
    end

    cecho("\n<green>[hauling]<reset> Hauling automation stopped\n")

    f2t_debug_log("[hauling] Stopped after %d cycles, session profit: %d ig",
        F2T_HAULING_STATE.total_cycles, F2T_HAULING_STATE.session_profit)

    -- Clean up mode-specific event handlers
    if F2T_HAULING_STATE.mode == "ac" and F2T_HAULING_STATE.handler_id then
        f2t_ac_cleanup_handlers(F2T_HAULING_STATE.handler_id)
    elseif F2T_HAULING_STATE.mode == "exchange" and F2T_HAULING_STATE.handler_id then
        f2t_exchange_cleanup_handlers(F2T_HAULING_STATE.handler_id)
    elseif F2T_HAULING_STATE.mode == "akaturi" and F2T_HAULING_STATE.handler_id then
        f2t_akaturi_cleanup_handlers(F2T_HAULING_STATE.handler_id)
    elseif F2T_HAULING_STATE.mode == "po" and F2T_HAULING_STATE.handler_id then
        f2t_po_cleanup_handlers(F2T_HAULING_STATE.handler_id)
    elseif F2T_HAULING_STATE.handler_id then
        -- Generic cleanup for any other mode
        killAnonymousEventHandler(F2T_HAULING_STATE.handler_id)
        f2t_debug_log("[hauling] Cleaned up event handlers for mode: %s", F2T_HAULING_STATE.mode or "unknown")
    end

    -- Kill any pending cycle pause timer
    if F2T_HAULING_STATE.cycle_pause_timer_id then
        killTimer(F2T_HAULING_STATE.cycle_pause_timer_id)
        F2T_HAULING_STATE.cycle_pause_timer_id = nil
        f2t_debug_log("[hauling] Killed pending cycle pause timer")
    end
    F2T_HAULING_STATE.cycle_pause_end_time = nil

    -- Unregister from stamina monitor (monitoring continues in standalone mode)
    f2t_stamina_unregister_client()

    -- Withdraw hauling's price checks; anyone else's keep running
    if f2t_price_cancel_all and f2t_price_cancel_all("hauling") then
        f2t_debug_log("[hauling] Withdrew pending price checks")
    end

    -- Reset active state (but preserve statistics for status display)
    F2T_HAULING_STATE.active = false
    F2T_HAULING_STATE.paused = false
    F2T_HAULING_STATE.pause_requested = false
    F2T_HAULING_STATE.paused_room_id = nil
    F2T_HAULING_STATE.stopping = false
    F2T_HAULING_STATE.mode = nil
    F2T_HAULING_STATE.po_deficit_only = false
    F2T_HAULING_STATE.current_phase = nil
    F2T_HAULING_STATE.handler_id = nil
    F2T_HAULING_STATE.commodity_queue = {}
    F2T_HAULING_STATE.queue_index = 1
    F2T_HAULING_STATE.current_commodity = nil
    F2T_HAULING_STATE.buy_location = nil
    F2T_HAULING_STATE.sell_location = nil
    F2T_HAULING_STATE.expected_profit = 0
    F2T_HAULING_STATE.actual_cost = 0
    F2T_HAULING_STATE.current_commodity_stats = {
        lots_bought = 0,
        total_cost = 0,
        lots_sold = 0,
        total_revenue = 0,
        profit = 0
    }
    F2T_HAULING_STATE.commodity_cycles = 0
    F2T_HAULING_STATE.commodity_total_profit = 0
    F2T_HAULING_STATE.sell_attempts = 0
    F2T_HAULING_STATE.dump_attempts = 0
    F2T_HAULING_STATE.cargo_clear_attempts = 0

    -- Clear AC job state
    F2T_HAULING_STATE.ac_job = nil
    F2T_HAULING_STATE.ac_accept_sent = false
    F2T_HAULING_STATE.ac_collect_sent = false
    F2T_HAULING_STATE.ac_deliver_sent = false
    F2T_HAULING_STATE.ac_cash_before_deliver = nil
    F2T_HAULING_STATE.ac_completing = false
    F2T_HAULING_STATE.ac_50_milestone_shown = false
    F2T_HAULING_STATE.ac_unreachable = {}
    F2T_HAULING_STATE.ac_walk_token = 0

    -- Clear Akaturi state; the contract itself stays with the game
    F2T_HAULING_STATE.akaturi_take_attempts = 0
    F2T_HAULING_STATE.akaturi_room_waits = 0
    F2T_HAULING_STATE.akaturi_promotion_noted = false
    F2T_HAULING_STATE.akaturi_start_points = 0
    F2T_HAULING_STATE.paused_for_death = false

    -- Clear PO state, keeping what the last session worked on for display
    if #F2T_HAULING_STATE.po_job_queue > 0 then
        F2T_HAULING_STATE.po_last_queue = F2T_HAULING_STATE.po_job_queue
    end
    if #F2T_HAULING_STATE.po_owned_planets > 0 then
        F2T_HAULING_STATE.po_last_planets = F2T_HAULING_STATE.po_owned_planets
    end
    F2T_HAULING_STATE.po_owned_planets = {}
    F2T_HAULING_STATE.po_current_system = nil
    F2T_HAULING_STATE.po_planet_exchange_data = {}
    F2T_HAULING_STATE.po_job_queue = {}
    F2T_HAULING_STATE.po_job_index = 1
    F2T_HAULING_STATE.po_current_job = nil
    F2T_HAULING_STATE.po_ship_lots = 0
    F2T_HAULING_STATE.po_scan_count = 0
    F2T_HAULING_STATE.po_deficit_count = 0
    F2T_HAULING_STATE.po_excess_count = 0
    F2T_HAULING_STATE.po_scan_planets = {}

    -- Clear cycle pause tracking
    F2T_HAULING_STATE.cycle_pause_return_location = nil

    -- NOTE: DO NOT reset total_cycles, session_profit, or commodity_history
    -- These are preserved so 'haul status' can show last session statistics

    raiseEvent("f2tHaulingStatusChanged")
end

-- Pause hauling
--- @param immediate boolean|nil If true, pause immediately (used by system-initiated pauses e.g.
--- Akaturi room finding). If false/nil, defer pause to next phase boundary.
function f2t_hauling_pause(immediate)
    if not F2T_HAULING_STATE.active then
        cecho("\n<yellow>[hauling]<reset> Hauling not active\n")
        return
    end

    if F2T_HAULING_STATE.paused then
        cecho("\n<yellow>[hauling]<reset> Already paused\n")
        return
    end

    if immediate then
        -- Immediate pause (system-initiated): stop everything now
        -- Supersedes any pending deferred pause
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true

        -- Store speedwalk destination before stopping (so we can recompute on resume)
        if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_DESTINATION_ROOM_ID then
            F2T_HAULING_STATE.paused_speedwalk_destination = F2T_SPEEDWALK_DESTINATION_ROOM_ID
            f2t_debug_log("[hauling] Stored speedwalk destination: %d", F2T_SPEEDWALK_DESTINATION_ROOM_ID)
        else
            F2T_HAULING_STATE.paused_speedwalk_destination = nil
        end

        cecho(string.format("\n<green>[hauling]<reset> Paused at phase: <cyan>%s<reset>\n",
            F2T_HAULING_STATE.current_phase or "unknown"))

        f2t_debug_log("[hauling] Paused immediately at phase: %s", F2T_HAULING_STATE.current_phase or "unknown")

        -- Kill cycle pause timer if pausing during cycle_pausing (resume will recreate)
        if F2T_HAULING_STATE.cycle_pause_timer_id then
            killTimer(F2T_HAULING_STATE.cycle_pause_timer_id)
            F2T_HAULING_STATE.cycle_pause_timer_id = nil
            f2t_debug_log("[hauling] Killed cycle pause timer (will recreate on resume)")
        end

        -- An Akaturi room search starts over on resume
        if F2T_HAULING_STATE.mode == "akaturi" then
            f2t_akaturi_visit_cancel("hauling")
            F2T_HAULING_STATE.paused_speedwalk_destination = nil
        end
        -- Stop any active speedwalk (will recompute on resume)
        if F2T_SPEEDWALK_ACTIVE then
            f2t_debug_log("[hauling] Stopping speedwalk (will recompute on resume)")
            f2t_map_speedwalk_stop()
        end

        f2t_map_brief_hold_release("hauling")
    else
        -- Deferred pause (user): let current operation complete, pause at next phase boundary
        if F2T_HAULING_STATE.pause_requested then
            cecho("\n<yellow>[hauling]<reset> Pause already pending...\n")
            return
        end

        F2T_HAULING_STATE.pause_requested = true

        cecho(string.format(
            "\n<green>[hauling]<reset> Will pause after current operation... (phase: <cyan>%s<reset>)\n",
            F2T_HAULING_STATE.current_phase or "unknown"))
        cecho("\n<dim_grey>Use 'haul terminate' for immediate stop<reset>\n")

        f2t_debug_log("[hauling] Deferred pause requested at phase: %s", F2T_HAULING_STATE.current_phase or "unknown")
    end

    raiseEvent("f2tHaulingStatusChanged")
end

-- Resume hauling
function f2t_hauling_resume()
    if not F2T_HAULING_STATE.active then
        cecho("\n<yellow>[hauling]<reset> Hauling not active\n")
        return
    end

    -- Handle cancelling a pending deferred pause
    if F2T_HAULING_STATE.pause_requested and not F2T_HAULING_STATE.paused then
        F2T_HAULING_STATE.pause_requested = false
        cecho("\n<green>[hauling]<reset> Pause request cancelled\n")
        f2t_debug_log("[hauling] Deferred pause request cancelled")
        raiseEvent("f2tHaulingStatusChanged")
        return
    end

    if not F2T_HAULING_STATE.paused then
        cecho("\n<yellow>[hauling]<reset> Not paused\n")
        return
    end

    if not f2t_insurance_allows() then
        f2t_insurance_check("hauling", function()
            if F2T_HAULING_STATE.active and F2T_HAULING_STATE.paused then f2t_hauling_resume() end
        end)
        return
    end

    F2T_HAULING_STATE.paused = false
    F2T_HAULING_STATE.paused_for_death = false
    F2T_HAULING_STATE.pause_requested = false
    f2t_map_brief_hold_acquire("hauling")
    raiseEvent("f2tHaulingStatusChanged")

    cecho(string.format("\n<green>[hauling]<reset> Resuming from phase: <cyan>%s<reset>\n",
        F2T_HAULING_STATE.current_phase or "unknown"))

    f2t_debug_log("[hauling] Resumed from phase: %s", F2T_HAULING_STATE.current_phase or "unknown")

    f2t_hauling_register_stamina()

    -- Re-establish navigation ownership (may have been cleared by stamina monitor)
    if f2t_map_set_nav_owner then
        f2t_map_set_nav_owner("hauling", function(reason)
            f2t_debug_log("[hauling] Navigation interrupted by %s", reason)
            return { auto_resume = true }
        end)
    end

    -- Akaturi phases restart from the contract as it now stands, which also
    -- covers work done by hand while paused. AC walks are restarted by their
    -- phase, so they explore again rather than replaying a bare speedwalk.
    if F2T_HAULING_STATE.mode == "akaturi" or F2T_HAULING_STATE.mode == "ac" then
        F2T_HAULING_STATE.paused_speedwalk_destination = nil
    end

    -- If we had a paused speedwalk, recompute path to the original destination
    local should_restart_phase = true
    if F2T_HAULING_STATE.paused_speedwalk_destination then
        local destination = F2T_HAULING_STATE.paused_speedwalk_destination
        F2T_HAULING_STATE.paused_speedwalk_destination = nil  -- Clear it

        f2t_debug_log("[hauling] Recomputing speedwalk to destination: %d", destination)
        cecho(string.format("\n<cyan>[hauling]<reset> Recomputing path to destination...\n"))

        -- Navigate to the stored destination
        local result = f2t_map_navigate(destination)
        if f2t_map_navigate_ok(result) then
            f2t_debug_log("[hauling] Already at destination, continuing phase")
            -- Already there, restart phase
        else
            -- Navigation started, don't restart phase yet
            should_restart_phase = false
        end
    end

    -- Only re-execute phase if we don't have an active speedwalk
    -- This prevents starting a new navigation when we're already navigating
    if should_restart_phase and F2T_HAULING_STATE.current_phase then
        f2t_debug_log("[hauling] Restarting phase: %s", F2T_HAULING_STATE.current_phase)
        f2t_hauling_transition(F2T_HAULING_STATE.current_phase)
    end
end

-- Show current hauling status
function f2t_hauling_show_status()
    -- Show status header
    if F2T_HAULING_STATE.active then
        cecho("\n<green>[hauling]<reset> Status:\n")
        local state_str = F2T_HAULING_STATE.paused and "PAUSED"
            or F2T_HAULING_STATE.pause_requested and "PAUSING..."
            or "RUNNING"
        cecho(string.format("  State: <cyan>%s<reset>\n", state_str))
        cecho(string.format("  Mode: <cyan>%s<reset>\n", f2t_hauling_strategy_label(F2T_HAULING_STATE.strategy)))
        cecho(string.format("  Phase: <cyan>%s<reset> <dim_grey>(%s)<reset>\n",
            f2t_hauling_phase_label(F2T_HAULING_STATE.current_phase) or "none",
            F2T_HAULING_STATE.current_phase or "none"))
        if F2T_HAULING_STATE.current_phase == "cycle_pausing" and F2T_HAULING_STATE.cycle_pause_end_time then
            local remaining = F2T_HAULING_STATE.cycle_pause_end_time - os.time()
            if remaining > 0 then
                cecho(string.format("  Resuming in: <cyan>%ds<reset>\n", remaining))
            end
        end
    else
        cecho("\n<green>[hauling]<reset> Status: <yellow>STOPPED<reset>\n")
        local next_strategy = f2t_hauling_default_strategy()
        if next_strategy then
            cecho(string.format("  Next start: <cyan>%s<reset> <dim_grey>(haul mode to change)<reset>\n",
                f2t_hauling_strategy_label(next_strategy)))
        end

        -- If no statistics exist, nothing to show
        if F2T_HAULING_STATE.total_cycles == 0 and #F2T_HAULING_STATE.commodity_history == 0 then
            cecho("\n<dim_grey>No hauling session data available. Use 'haul start' to begin.<reset>\n")
            return
        end

        cecho("\n<dim_grey>Last session results:<reset>\n")
    end

    -- Overall statistics (show for both active and stopped)
    cecho("\n<white>Session Statistics:<reset>\n")
    cecho(string.format("  Total Cycles: <cyan>%d<reset>\n",
        F2T_HAULING_STATE.total_cycles))

    if F2T_HAULING_STATE.mode == "po" or
       (F2T_HAULING_STATE.po_deficit_cycles > 0 or F2T_HAULING_STATE.po_excess_cycles > 0) then
        -- PO mode: show deficit/excess cycle breakdown
        cecho(string.format("  Deficit Cycles: <orange>%d<reset>\n",
            F2T_HAULING_STATE.po_deficit_cycles))
        cecho(string.format("  Excess Cycles: <yellow>%d<reset>\n",
            F2T_HAULING_STATE.po_excess_cycles))
    else
        -- Other modes: show profit stats
        cecho(string.format("  Session Profit: <green>%d ig<reset>\n",
            F2T_HAULING_STATE.session_profit))
        if F2T_HAULING_STATE.total_cycles > 0 then
            local avg_profit = math.floor(F2T_HAULING_STATE.session_profit / F2T_HAULING_STATE.total_cycles)
            cecho(string.format("  Avg Profit/Cycle: <cyan>%d ig<reset>\n", avg_profit))
        end
    end

    -- Active session details (only show when hauling is running)
    if F2T_HAULING_STATE.active then
        -- PO-specific status
        if F2T_HAULING_STATE.mode == "po" then
            cecho(string.format("\n<white>Mode:<reset> <cyan>Planet Owner Trading<reset>\n"))
            cecho(string.format("  System: <cyan>%s<reset>\n",
                F2T_HAULING_STATE.po_current_system or "unknown"))

            if #F2T_HAULING_STATE.po_owned_planets > 0 then
                cecho(string.format("  Owned Planets: <cyan>%s<reset>\n",
                    table.concat(F2T_HAULING_STATE.po_owned_planets, ", ")))
            end

            cecho(string.format("  Ship Capacity: <cyan>%d lots<reset>%s\n",
                F2T_HAULING_STATE.po_ship_lots,
                F2T_HAULING_STATE.po_ship_lots >= 14 and " (bundling)" or ""))
            cecho(string.format("  Scan Iterations: <cyan>%d<reset>\n",
                F2T_HAULING_STATE.po_scan_count))

            -- Current job and queue (hide during cycle pause - queue is exhausted)
            if F2T_HAULING_STATE.current_phase ~= "cycle_pausing" then
                local job = F2T_HAULING_STATE.po_current_job
                if job then
                    local type_color = job.type == "deficit" and "orange" or "yellow"
                    cecho(string.format("\n<white>Current Job:<reset> <%s>%s<reset> <cyan>%s<reset>\n",
                        type_color, job.type, job.commodity))
                    cecho(string.format("  Buy: <cyan>%s<reset> → Sell: <cyan>%s<reset>\n",
                        job.buy_planet or "?", job.sell_planet or "?"))
                    if job.bundled_commodity then
                        cecho(string.format("  Bundled: <cyan>%s<reset> (%s → %s)\n",
                            job.bundled_commodity,
                            job.bundled_buy_planet or "?", job.bundled_sell_planet or "?"))
                    end
                end

                -- Job queue progress
                local queue = F2T_HAULING_STATE.po_job_queue
                if queue and #queue > 0 then
                    cecho(string.format("\n<white>Job Queue:<reset> <cyan>%d/%d<reset>\n",
                        F2T_HAULING_STATE.po_job_index, #queue))
                    for i, qjob in ipairs(queue) do
                        local marker = i == F2T_HAULING_STATE.po_job_index and " <yellow>*<reset>" or ""
                        local tc = qjob.type == "deficit" and "red" or "yellow"
                        local bundle_info = qjob.bundled_commodity
                            and string.format(" + %s", qjob.bundled_commodity) or ""
                        cecho(string.format("  %d. <%s>%s<reset> <cyan>%s<reset>%s (%s → %s)%s\n",
                            i, tc, qjob.type, qjob.commodity, bundle_info,
                            qjob.buy_planet or "?", qjob.sell_planet or "?", marker))
                    end
                end
            end
        end

        -- Commodity queue and current commodity (hide during cycle pause - queue is exhausted)
        if F2T_HAULING_STATE.current_phase ~= "cycle_pausing" then
            if F2T_HAULING_STATE.commodity_queue and #F2T_HAULING_STATE.commodity_queue > 0 then
                cecho(string.format("\n<white>Commodity Queue:<reset> <cyan>%d/%d<reset>\n",
                    F2T_HAULING_STATE.queue_index, #F2T_HAULING_STATE.commodity_queue))
                for i, comm in ipairs(F2T_HAULING_STATE.commodity_queue) do
                    local marker = i == F2T_HAULING_STATE.queue_index and " <yellow>*<reset>" or ""
                    cecho(string.format("  %d. <cyan>%s<reset> (profit: %d ig/ton)%s\n",
                        i, comm.commodity, comm.expected_profit, marker))
                end
            end

            if F2T_HAULING_STATE.current_commodity then
                cecho(string.format("\n<white>Current Commodity:<reset> <cyan>%s<reset>\n",
                    F2T_HAULING_STATE.current_commodity))
                cecho(string.format("  Expected Profit: <green>%d ig/ton<reset>\n",
                    F2T_HAULING_STATE.expected_profit))
                cecho(string.format("  Commodity Cycles: <cyan>%d<reset>\n",
                    F2T_HAULING_STATE.commodity_cycles))

                -- Current cycle stats
                local stats = F2T_HAULING_STATE.current_commodity_stats
                if stats.lots_bought > 0 or stats.lots_sold > 0 then
                    cecho("  <white>Current Cycle:<reset>\n")
                    if stats.lots_bought > 0 then
                        cecho(string.format("    Bought: %d lots (cost: %d ig)\n",
                            stats.lots_bought, stats.total_cost))
                    end
                    if stats.lots_sold > 0 then
                        cecho(string.format("    Sold: %d lots (revenue: %d ig)\n",
                            stats.lots_sold, stats.total_revenue))
                    end
                end
            end
        end

        -- Locations
        if F2T_HAULING_STATE.buy_location then
            cecho(string.format("\n<white>Buy Location:<reset> <cyan>%s: %s<reset> at <yellow>%d ig/ton<reset>\n",
                F2T_HAULING_STATE.buy_location.system,
                F2T_HAULING_STATE.buy_location.planet,
                F2T_HAULING_STATE.buy_location.price))
        end

        if F2T_HAULING_STATE.sell_location then
            cecho(string.format("<white>Sell Location:<reset> <cyan>%s: %s<reset> at <yellow>%d ig/ton<reset>\n",
                F2T_HAULING_STATE.sell_location.system,
                F2T_HAULING_STATE.sell_location.planet,
                F2T_HAULING_STATE.sell_location.price))
        end
    end  -- End active session details

    -- Commodity history (show for both active and stopped)
    if #F2T_HAULING_STATE.commodity_history > 0 then
        cecho("\n<white>Completed Commodities:<reset>\n")
        for _, hist in ipairs(F2T_HAULING_STATE.commodity_history) do
            cecho(string.format("  <cyan>%s<reset>: %d cycles, profit: <green>%d ig<reset>\n",
                hist.commodity, hist.cycles, hist.profit))
        end
    end
end

-- Transition to a new phase
function f2t_hauling_transition(new_phase)
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    -- Deferred pause: convert pause_requested to actual pause at phase boundary
    if F2T_HAULING_STATE.pause_requested then
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true
        F2T_HAULING_STATE.current_phase = new_phase  -- Store NEXT phase for clean resume
        f2t_map_brief_hold_release("hauling")
        cecho(string.format("\n<green>[hauling]<reset> Paused at phase: <cyan>%s<reset>\n", new_phase))
        f2t_debug_log("[hauling] Deferred pause activated at phase: %s", new_phase)
        raiseEvent("f2tHaulingStatusChanged")
        return
    end

    f2t_debug_log("[hauling] Transitioning to phase: %s", new_phase)
    F2T_HAULING_STATE.current_phase = new_phase
    raiseEvent("f2tHaulingStatusChanged")

    -- Execute phase
    if new_phase == "analyzing" then
        f2t_hauling_phase_analyze()
    elseif new_phase == "navigating_to_buy" then
        f2t_hauling_phase_navigate_to_buy()
    elseif new_phase == "buying" then
        f2t_hauling_phase_buy()
    elseif new_phase == "navigating_to_sell" then
        f2t_hauling_phase_navigate_to_sell()
    elseif new_phase == "selling" then
        f2t_hauling_phase_sell()
    -- Armstrong Cuthbert phases
    elseif new_phase == "ac_fetching_jobs" then
        f2t_hauling_phase_ac_fetch_jobs()
    elseif new_phase == "ac_selecting_job" then
        f2t_hauling_phase_ac_select_job()
    elseif new_phase == "ac_navigating_to_source" then
        f2t_hauling_phase_ac_navigate_to_source()
    elseif new_phase == "ac_accepting_job" then
        f2t_hauling_phase_ac_accept_job()
    elseif new_phase == "ac_collecting" then
        f2t_hauling_phase_ac_collect()
    elseif new_phase == "ac_navigating_to_dest" then
        f2t_hauling_phase_ac_navigate_to_dest()
    elseif new_phase == "ac_delivering" then
        f2t_hauling_phase_ac_deliver()
    -- Akaturi phases
    -- Akaturi phases all resume from the contract as it stands
    elseif new_phase == "akaturi_getting_job" or new_phase == "akaturi_reading_contract"
        or new_phase == "akaturi_working_pickup" or new_phase == "akaturi_working_dropoff" then
        f2t_hauling_phase_akaturi_get_job()
    -- Planet Owner phases
    elseif new_phase == "po_scanning_system" then
        f2t_hauling_phase_po_scan_system()
    elseif new_phase == "po_scanning_exchanges" then
        f2t_hauling_phase_po_scan_exchanges()
    elseif new_phase == "po_building_queue" then
        f2t_hauling_phase_po_build_queue()
    elseif new_phase == "po_navigating_to_buy" then
        f2t_hauling_phase_po_navigate_to_buy()
    elseif new_phase == "po_navigating_to_bundled_buy" then
        -- Bundled buy navigation: re-navigate to second source on resume
        f2t_hauling_phase_po_bundled_buy_navigate()
    elseif new_phase == "po_buying" then
        f2t_hauling_phase_po_buy()
    elseif new_phase == "po_navigating_to_sell" then
        f2t_hauling_phase_po_navigate_to_sell()
    elseif new_phase == "po_selling" then
        f2t_hauling_phase_po_sell()
    elseif new_phase == "po_checking_deficits" then
        f2t_hauling_phase_po_check_deficits()
    -- Planet Owner: next job pseudo-phase (used by deferred pause resume)
    elseif new_phase == "po_next_job" then
        f2t_hauling_phase_po_next_job()
    -- Exchange mode: next commodity pseudo-phase (used by deferred pause resume)
    elseif new_phase == "next_commodity" then
        f2t_hauling_next_commodity()
    -- Cycle pause: resume respects remaining pause time
    elseif new_phase == "cycle_pausing" then
        local remaining = 0
        if F2T_HAULING_STATE.cycle_pause_end_time then
            remaining = F2T_HAULING_STATE.cycle_pause_end_time - os.time()
        end

        if remaining > 0 then
            -- Re-create timer for remaining duration
            f2t_debug_log("[hauling] Resuming cycle_pausing with %d seconds remaining", remaining)
            cecho(string.format(
                "\n<green>[hauling]<reset> Resuming pause, <yellow>%d seconds<reset> remaining...\n", remaining))

            if F2T_HAULING_STATE.cycle_pause_timer_id then
                killTimer(F2T_HAULING_STATE.cycle_pause_timer_id)
            end
            F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(remaining, function()
                F2T_HAULING_STATE.cycle_pause_timer_id = nil
                F2T_HAULING_STATE.cycle_pause_end_time = nil
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                    and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                    if F2T_HAULING_STATE.mode == "po" then
                        f2t_hauling_transition("po_scanning_system")
                    else
                        f2t_hauling_transition("analyzing")
                    end
                end
            end)
        else
            -- Pause time already elapsed, proceed immediately
            f2t_debug_log("[hauling] Cycle pause time elapsed, proceeding immediately")
            F2T_HAULING_STATE.cycle_pause_end_time = nil
            if F2T_HAULING_STATE.mode == "po" then
                f2t_hauling_phase_po_scan_system()
            else
                f2t_hauling_phase_analyze()
            end
        end
    else
        cecho(string.format("\n<red>[hauling]<reset> Unknown phase: %s\n", new_phase))
        f2t_hauling_stop()
    end
end

-- ========================================
-- Shared: Status for display
-- ========================================

local PHASE_LABELS = {
    analyzing                    = "analyzing prices",
    navigating_to_buy            = "heading to buy",
    buying                       = "buying",
    navigating_to_sell           = "heading to sell",
    selling                      = "selling",
    next_commodity               = "next commodity",
    cycle_pausing                = "cycle pause",
    ac_fetching_jobs             = "selecting job",
    ac_selecting_job             = "selecting job",
    ac_navigating_to_source      = "heading to pickup",
    ac_accepting_job             = "accepting job",
    ac_collecting                = "collecting cargo",
    ac_navigating_to_dest        = "heading to dropoff",
    ac_delivering                = "delivering cargo",
    akaturi_getting_job          = "getting contract",
    akaturi_reading_contract     = "reading contract",
    akaturi_working_pickup       = "finding pickup",
    akaturi_working_dropoff      = "finding dropoff",
    po_scanning_system           = "scanning system",
    po_scanning_exchanges        = "scanning exchanges",
    po_building_queue            = "planning jobs",
    po_navigating_to_buy         = "heading to buy",
    po_navigating_to_bundled_buy = "heading to buy",
    po_buying                    = "buying",
    po_navigating_to_sell        = "heading to sell",
    po_selling                   = "selling",
    po_checking_deficits         = "checking deficits",
    po_next_job                  = "next job",
}

--- Plain-English label for a phase constant
--- @param phase string|nil
--- @return string|nil
function f2t_hauling_phase_label(phase)
    if not phase then return nil end
    return PHASE_LABELS[phase] or phase:gsub("_", " ")
end

--- Read-only view of the automation state, shared by `haul status` consumers
--- and the Commerce panels
--- @return table
function f2tHaulingSnapshot()
    local state = F2T_HAULING_STATE
    local runState
    if not state.active then
        runState = "stopped"
    elseif state.stopping then
        runState = "stopping"
    elseif state.paused then
        runState = "paused"
    elseif state.pause_requested then
        runState = "pausing"
    else
        runState = "running"
    end

    local nextStrategy, nextNote = f2t_hauling_default_strategy()
    return {
        active          = state.active,
        runState        = runState,
        strategy        = state.active and state.strategy or nextStrategy,
        lastStrategy    = state.strategy,
        strategyNote    = not state.active and nextNote or nil,
        phase           = state.current_phase,
        phaseLabel      = state.active and f2t_hauling_phase_label(state.current_phase) or nil,
        totalCycles     = state.total_cycles or 0,
        sessionProfit   = state.session_profit or 0,
        deficitCycles   = state.po_deficit_cycles or 0,
        excessCycles    = state.po_excess_cycles or 0,
        cyclePauseLeft  = state.cycle_pause_end_time and math.max(0, state.cycle_pause_end_time - os.time()) or nil,
    }
end

-- ========================================
-- Shared: Jettison Cargo
-- ========================================

--- Jettison all remaining cargo, then call callback
--- Used by both exchange and PO modes as a last resort when cargo can't be sold
--- @param callback function Called when cargo is cleared
function f2t_hauling_jettison_cargo(callback)
    local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if not cargo or #cargo == 0 then
        callback()
        return
    end

    -- Collect unique commodities and their lot counts
    local commodities = {}
    for _, lot in ipairs(cargo) do
        commodities[lot.commodity] = (commodities[lot.commodity] or 0) + 1
    end

    -- Send jettison commands for each commodity
    for commodity, lots in pairs(commodities) do
        f2t_debug_log("[hauling] Jettisoning %d lots of %s", lots, commodity)
        cecho(string.format("\n<yellow>[hauling]<reset> Jettisoning %d lots of <cyan>%s<reset>\n", lots, commodity))
        for _ = 1, lots do
            send(string.format("jettison %s", commodity), false)
        end
    end

    -- Wait for jettison to complete, then continue
    tempTimer(1, function()
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end
        callback()
    end)
end

f2t_debug_log("[hauling] State machine loaded")