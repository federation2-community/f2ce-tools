-- Hauling Phase Implementations
-- Each phase of the buy/sell cycle

-- Parse excluded commodities setting into lookup table
-- Returns table with commodity names as keys (lowercase, trimmed)
local function parse_excluded_commodities()
    local setting = f2t_settings_get("hauling", "excluded_commodities")
    if not setting or setting == "" then
        return {}
    end

    local excluded = {}
    for commodity in string.gmatch(setting, "[^,]+") do
        -- Trim whitespace and convert to lowercase for case-insensitive matching
        local trimmed = commodity:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            excluded[trimmed:lower()] = true
        end
    end

    return excluded
end

-- Phase 1: Analyze all commodities to find most profitable
function f2t_hauling_phase_analyze()
    f2t_debug_log("[hauling] Phase: Analyzing commodities")
    cecho("\n<green>[hauling]<reset> Analyzing commodity prices (this may take a minute)...\n")

    -- Use price all data function
    f2t_price_get_all_data(function(results)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Get exclusion list
        local excluded = parse_excluded_commodities()

        -- Filter to only tradeable commodities
        local tradeable = {}
        for _, analysis in ipairs(results) do
            -- Check if commodity is excluded (case-insensitive)
            local commodity_lower = analysis.commodity:lower()
            if excluded[commodity_lower] then
                f2t_debug_log("[hauling] Skipping excluded commodity: %s", analysis.commodity)
                -- Continue to next iteration
            elseif analysis.profit and analysis.profit > 0 and
               #analysis.top_buy > 0 and #analysis.top_sell > 0 then
                table.insert(tradeable, analysis)
            end
        end

        if #tradeable == 0 then
            cecho("\n<red>[hauling]<reset> No profitable commodities found\n")
            f2t_hauling_stop()
            return
        end

        -- Sort by profit descending
        table.sort(tradeable, function(a, b)
            return a.profit > b.profit
        end)

        -- Take top 5 commodities
        F2T_HAULING_STATE.commodity_queue = {}
        local count = math.min(5, #tradeable)
        for i = 1, count do
            local comm = tradeable[i]
            table.insert(F2T_HAULING_STATE.commodity_queue, {
                commodity = comm.commodity,
                expected_profit = comm.profit
            })
            f2t_debug_log("[hauling] Queued commodity %d: %s (profit: %d ig/ton)",
                i, comm.commodity, comm.profit)
        end

        F2T_HAULING_STATE.queue_index = 1

        cecho(string.format("\n<green>[hauling]<reset> Queued <cyan>%d<reset> profitable commodities\n", count))

        -- Start trading first commodity
        f2t_hauling_next_commodity()
    end)
end

-- Move to next commodity in queue
function f2t_hauling_next_commodity()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    -- Deferred pause: pause between commodities
    if F2T_HAULING_STATE.pause_requested then
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true
        F2T_HAULING_STATE.current_phase = "next_commodity"
        cecho("\n<green>[hauling]<reset> Paused between commodities\n")
        f2t_debug_log("[hauling] Deferred pause activated between commodities")
        return
    end

    -- Check if graceful stop was requested
    if F2T_HAULING_STATE.stopping then
        f2t_debug_log("[hauling] Graceful stop complete, cargo sold")
        cecho("\n<green>[hauling]<reset> Cargo sold, stopping now...\n")
        f2t_hauling_do_stop()
        return
    end

    -- Check if queue is empty or exhausted
    if not F2T_HAULING_STATE.commodity_queue or
       #F2T_HAULING_STATE.commodity_queue == 0 or
       F2T_HAULING_STATE.queue_index > #F2T_HAULING_STATE.commodity_queue then

        f2t_debug_log("[hauling] Commodity queue exhausted, re-analyzing")

        -- Check if we should pause before re-analyzing
        local cycle_pause = tonumber(f2t_settings_get("hauling", "cycle_pause")) or 0
        local use_safe_room = f2t_settings_get("hauling", "use_safe_room")
        local safe_room = f2t_settings_get("shared", "safe_room")

        -- Kill any stale cycle pause timer from a previous cycle or session
        if F2T_HAULING_STATE.cycle_pause_timer_id then
            killTimer(F2T_HAULING_STATE.cycle_pause_timer_id)
            F2T_HAULING_STATE.cycle_pause_timer_id = nil
        end

        if cycle_pause > 0 then
            F2T_HAULING_STATE.current_phase = "cycle_pausing"

            if use_safe_room and safe_room and safe_room ~= "" then
                -- Navigate to safe room, pause, then return and continue
                local current_location = gmcp.room and gmcp.room.info and gmcp.room.info.num
                if current_location then
                    F2T_HAULING_STATE.cycle_pause_return_location = current_location
                    cecho(string.format("\n<green>[hauling]<reset> All commodities traded, going to safe room for <yellow>%d seconds<reset>...\n", cycle_pause))
                    f2t_debug_log("[hauling] Navigating to safe room for cycle pause (%d seconds), will return to room: %s", cycle_pause, current_location)

                    f2t_map_navigate(safe_room)

                    -- After navigation completes, wait, then return
                    tempTimer(3, function()
                        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                            and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                            if F2T_HAULING_STATE.pause_requested then
                                f2t_hauling_transition("analyzing")
                                return
                            end
                            cecho(string.format("\n<green>[hauling]<reset> Pausing at safe room for <yellow>%d seconds<reset>...\n", cycle_pause))
                            F2T_HAULING_STATE.cycle_pause_end_time = os.time() + cycle_pause
                            F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                                F2T_HAULING_STATE.cycle_pause_timer_id = nil
                                F2T_HAULING_STATE.cycle_pause_end_time = nil
                                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                                    and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                                    local return_to = F2T_HAULING_STATE.cycle_pause_return_location
                                    if return_to then
                                        if not F2T_HAULING_STATE.pause_requested then
                                            cecho(string.format("\n<green>[hauling]<reset> Returning to previous location: <cyan>%s<reset>\n", return_to))
                                        end
                                        f2t_debug_log("[hauling] Returning to room: %s", return_to)
                                        f2t_map_navigate(return_to)

                                        -- Wait for return navigation, then re-analyze
                                        tempTimer(3, function()
                                            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                                                and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                                                if not F2T_HAULING_STATE.pause_requested then
                                                    cecho("\n<green>[hauling]<reset> Pause complete, refreshing market data...\n")
                                                end
                                                f2t_hauling_transition("analyzing")
                                            end
                                        end)
                                    else
                                        if not F2T_HAULING_STATE.pause_requested then
                                            cecho("\n<green>[hauling]<reset> Pause complete, refreshing market data...\n")
                                        end
                                        f2t_hauling_transition("analyzing")
                                    end
                                    F2T_HAULING_STATE.cycle_pause_return_location = nil
                                end
                            end)
                        end
                    end)
                else
                    -- Can't determine current location, pause in place
                    cecho(string.format("\n<green>[hauling]<reset> All commodities traded, pausing for <yellow>%d seconds<reset> before refreshing...\n", cycle_pause))
                    F2T_HAULING_STATE.cycle_pause_end_time = os.time() + cycle_pause
                    F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                        F2T_HAULING_STATE.cycle_pause_timer_id = nil
                        F2T_HAULING_STATE.cycle_pause_end_time = nil
                        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                            and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                            if not F2T_HAULING_STATE.pause_requested then
                                cecho("\n<green>[hauling]<reset> Pause complete, refreshing market data...\n")
                            end
                            f2t_hauling_transition("analyzing")
                        end
                    end)
                end
            else
                -- No safe room, pause in place
                cecho(string.format("\n<green>[hauling]<reset> All commodities traded, pausing for <yellow>%d seconds<reset> before refreshing...\n", cycle_pause))
                F2T_HAULING_STATE.cycle_pause_end_time = os.time() + cycle_pause
                F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                    F2T_HAULING_STATE.cycle_pause_timer_id = nil
                    F2T_HAULING_STATE.cycle_pause_end_time = nil
                    if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                        and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                        if not F2T_HAULING_STATE.pause_requested then
                            cecho("\n<green>[hauling]<reset> Pause complete, refreshing market data...\n")
                        end
                        f2t_hauling_transition("analyzing")
                    end
                end)
            end
        else
            cecho("\n<green>[hauling]<reset> All commodities traded, refreshing market data...\n")
            f2t_hauling_transition("analyzing")
        end
        return
    end

    -- Get next commodity from queue
    local commodity_data = F2T_HAULING_STATE.commodity_queue[F2T_HAULING_STATE.queue_index]
    F2T_HAULING_STATE.current_commodity = commodity_data.commodity
    F2T_HAULING_STATE.expected_profit = commodity_data.expected_profit

    -- Reset commodity-specific stats
    F2T_HAULING_STATE.current_commodity_stats = {
        lots_bought = 0,
        total_cost = 0,
        lots_sold = 0,
        total_revenue = 0,
        profit = 0
    }
    F2T_HAULING_STATE.commodity_cycles = 0
    F2T_HAULING_STATE.commodity_total_profit = 0  -- Reset accumulated profit for new commodity
    F2T_HAULING_STATE.sell_attempts = 0  -- Reset sell attempt counter for new commodity

    f2t_debug_log("[hauling] Starting commodity %d/%d: %s (expected profit: %d ig/ton)",
        F2T_HAULING_STATE.queue_index, #F2T_HAULING_STATE.commodity_queue,
        commodity_data.commodity, commodity_data.expected_profit)

    cecho(string.format("\n<green>[hauling]<reset> Trading <cyan>%s<reset> (expected profit: <green>%d ig/ton<reset>)\n",
        commodity_data.commodity, commodity_data.expected_profit))

    -- Get detailed buy/sell locations for this commodity
    f2t_hauling_get_commodity_details(commodity_data.commodity)
end

-- Get detailed price data for selected commodity
function f2t_hauling_get_commodity_details(commodity)
    f2t_debug_log("[hauling] Getting details for: %s", commodity)

    f2t_price_check_commodity(commodity, function(commodity_name, parsed_data, analysis)
        f2t_debug_log("[hauling] Received commodity details callback for: %s", commodity_name)
        f2t_debug_log("[hauling] State - active: %s, paused: %s", tostring(F2T_HAULING_STATE.active), tostring(F2T_HAULING_STATE.paused))

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            f2t_debug_log("[hauling] Callback aborted - hauling not active or paused")
            return
        end

        -- Check if graceful stop was requested
        if F2T_HAULING_STATE.stopping then
            f2t_debug_log("[hauling] Graceful stop complete, sold all cargo")
            cecho("\n<green>[hauling]<reset> Cargo sold, stopping now...\n")
            f2t_hauling_do_stop()
            return
        end

        f2t_debug_log("[hauling] Analysis - top_buy count: %d, top_sell count: %d, profit: %d",
            #analysis.top_buy, #analysis.top_sell, analysis.profit or 0)

        -- Only validate margin AFTER we've done at least one cycle
        -- First cycle: just start trading
        -- Subsequent cycles: validate margin is still acceptable
        if F2T_HAULING_STATE.commodity_cycles > 0 then
            -- Get best sell price (where we sell) and best buy price (where we buy)
            local best_sell_price = #analysis.top_buy > 0 and analysis.top_buy[1].price or 0
            local best_buy_price = #analysis.top_sell > 0 and analysis.top_sell[1].price or 0

            if best_buy_price > 0 then
                -- Calculate expected margin for this commodity
                local expected_margin_pct = ((best_sell_price - best_buy_price) / best_buy_price) * 100

                f2t_debug_log("[hauling] Margin check (cycle %d): sell=%d, buy=%d, margin=%.1f%%, threshold=%.0f%%",
                    F2T_HAULING_STATE.commodity_cycles, best_sell_price, best_buy_price,
                    expected_margin_pct, F2T_HAULING_STATE.margin_threshold_pct)

                -- Check if margin fell below threshold
                if expected_margin_pct < F2T_HAULING_STATE.margin_threshold_pct then
                    cecho(string.format("\n<yellow>[hauling]<reset> Current market margin for <cyan>%s<reset> too low (%.1f%% < %.0f%%) - moving to next commodity\n",
                        commodity, expected_margin_pct, F2T_HAULING_STATE.margin_threshold_pct))
                    f2t_debug_log("[hauling] Removing commodity from queue due to low current market margin")

                    -- Remove this commodity from queue and move to next
                    f2t_hauling_remove_current_commodity()
                    return
                end
            end
        end

        -- Select best buy location (where exchange sells = top_sell)
        -- Note: top_sell = "exchanges selling" (where WE buy)
        if #analysis.top_sell > 0 then
            local best_buy = analysis.top_sell[1]
            F2T_HAULING_STATE.buy_location = {
                system = best_buy.system,
                planet = best_buy.planet,
                price = best_buy.price
            }

            f2t_debug_log("[hauling] Buy location: %s: %s at %d ig/ton",
                best_buy.system, best_buy.planet, best_buy.price)
        end

        -- Select best sell location (where exchange buys = top_buy)
        -- Note: top_buy = "exchanges buying" (where WE sell)
        if #analysis.top_buy > 0 then
            local best_sell = analysis.top_buy[1]
            F2T_HAULING_STATE.sell_location = {
                system = best_sell.system,
                planet = best_sell.planet,
                price = best_sell.price
            }

            f2t_debug_log("[hauling] Sell location: %s: %s at %d ig/ton",
                best_sell.system, best_sell.planet, best_sell.price)
        end

        -- Transition to navigation
        f2t_hauling_transition("navigating_to_buy")
    end)
end

-- Remove current commodity from queue and move to next
function f2t_hauling_remove_current_commodity()
    if not F2T_HAULING_STATE.commodity_queue then
        return
    end

    -- Check if we still have cargo - if so, we need to dump it before moving on
    local cargo = gmcp.char.ship.cargo
    if cargo and #cargo > 0 then
        local commodity = F2T_HAULING_STATE.current_commodity
        cecho(string.format("\n<yellow>[hauling]<reset> Abandoning <cyan>%s<reset>, finding exchange to dump remaining cargo\n", commodity))
        f2t_debug_log("[hauling] Need to dump %d lots of %s before switching commodity", #cargo, commodity)

        -- Initialize dump attempts counter
        F2T_HAULING_STATE.dump_attempts = 0

        -- Get fresh price data to find ANY exchange that will buy (even at terrible price)
        f2t_price_check_commodity(commodity, function(commodity_name, parsed_data, analysis)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end

            -- Find any exchange that will buy this commodity
            if analysis and analysis.top_buy and #analysis.top_buy > 0 then
                -- Take the first exchange that will buy (we don't care about price anymore)
                local dump_location = analysis.top_buy[1]

                f2t_debug_log("[hauling] Dumping at: %s: %s (price: %d ig/ton)",
                    dump_location.system, dump_location.planet, dump_location.price)

                -- Navigate to dump location
                local destination = string.format("%s exchange", dump_location.planet)
                cecho(string.format("\n<yellow>[hauling]<reset> Navigating to dump location: <cyan>%s exchange<reset>\n",
                    dump_location.planet))

                local nav_result = f2t_map_navigate(destination)

                -- Note: f2t_map_navigate may return false if current location unknown,
                -- but it will auto-retry with 'look' command. Event handler will detect completion.

                -- Set up a phase transition to dump the cargo
                F2T_HAULING_STATE.current_phase = "dumping_cargo"
                F2T_HAULING_STATE.dump_location = dump_location

                -- If already at destination, dump immediately
                if nav_result == true and not F2T_SPEEDWALK_ACTIVE then
                    tempTimer(0.5, function()
                        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                            return
                        end
                        f2t_hauling_phase_dump_cargo()
                    end)
                end
                -- Otherwise speedwalk is in progress or navigation is retrying, GMCP handler will detect completion
            else
                -- No exchanges buying this commodity - jettison and move on
                cecho(string.format("\n<yellow>[hauling]<reset> No exchanges buying %s, jettisoning remaining cargo\n", commodity))
                f2t_hauling_jettison_cargo(function()
                    f2t_hauling_finish_remove_commodity()
                end)
            end
        end)
        return
    end

    -- No cargo, can remove immediately
    f2t_hauling_finish_remove_commodity()
end

-- Phase: Dump cargo at any price (when abandoning commodity)
function f2t_hauling_phase_dump_cargo()
    local commodity = F2T_HAULING_STATE.current_commodity

    if not commodity then
        cecho("\n<red>[hauling]<reset> No commodity to dump\n")
        f2t_hauling_stop()
        return
    end

    cecho(string.format("\n<yellow>[hauling]<reset> Dumping all <cyan>%s<reset> cargo at any price...\n", commodity))
    f2t_debug_log("[hauling] Dumping commodity: %s", commodity)

    -- Use bulk sell to dump all cargo
    f2t_bulk_sell_start(nil, nil, function(sold_commodity, lots_sold, status, error_msg)
        f2t_debug_log("[hauling] Dump sell complete: sold %d lots, status: %s", lots_sold, status)

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Check if cargo is now empty
        local cargo = gmcp.char.ship.cargo
        if cargo and #cargo > 0 then
            -- Still have cargo - need to find another exchange
            f2t_debug_log("[hauling] %d lots remain after dump, finding next exchange", #cargo)
            cecho(string.format("\n<yellow>[hauling]<reset> %d lots remain, finding next exchange to dump...\n", #cargo))

            -- Continue dumping at next exchange
            f2t_hauling_find_next_dump_location()
        else
            -- Cargo is empty, we're done
            f2t_debug_log("[hauling] All cargo dumped successfully")
            cecho("\n<green>[hauling]<reset> All cargo dumped\n")

            -- Now actually remove the commodity and continue
            f2t_hauling_finish_remove_commodity()
        end
    end)
end

-- Find next dump location after partial dump
function f2t_hauling_find_next_dump_location()
    if not F2T_HAULING_STATE.current_commodity then
        f2t_hauling_stop()
        return
    end

    local commodity = F2T_HAULING_STATE.current_commodity

    -- Increment dump attempt counter (initialize if needed)
    F2T_HAULING_STATE.dump_attempts = (F2T_HAULING_STATE.dump_attempts or 0) + 1

    -- Maximum dump attempts before jettisoning
    local MAX_DUMP_ATTEMPTS = 5

    f2t_debug_log("[hauling] Finding dump location #%d for %s (max: %d)",
        F2T_HAULING_STATE.dump_attempts, commodity, MAX_DUMP_ATTEMPTS)

    -- If we've tried too many exchanges, just jettison the cargo
    if F2T_HAULING_STATE.dump_attempts > MAX_DUMP_ATTEMPTS then
        cecho(string.format("\n<yellow>[hauling]<reset> Attempted %d exchanges, jettisoning remaining <cyan>%s<reset>...\n",
            MAX_DUMP_ATTEMPTS, commodity))
        f2t_debug_log("[hauling] Max dump attempts exceeded, jettisoning cargo")

        f2t_hauling_jettison_cargo(function()
            f2t_hauling_finish_remove_commodity()
        end)
        return
    end

    -- Get fresh price data
    f2t_price_check_commodity(commodity, function(commodity_name, parsed_data, analysis)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Find next exchange that will buy (we don't care about price)
        if #analysis.top_buy >= F2T_HAULING_STATE.dump_attempts then
            local next_dump = analysis.top_buy[F2T_HAULING_STATE.dump_attempts]

            f2t_debug_log("[hauling] Next dump location: %s: %s at %d ig/ton",
                next_dump.system, next_dump.planet, next_dump.price)

            -- Navigate to dump location
            local destination = string.format("%s exchange", next_dump.planet)
            cecho(string.format("\n<yellow>[hauling]<reset> Navigating to dump location: <cyan>%s exchange<reset>\n",
                next_dump.planet))

            local nav_result = f2t_map_navigate(destination)

            -- Note: f2t_map_navigate may return false if current location unknown,
            -- but it will auto-retry with 'look' command. Event handler will detect completion.

            -- Keep dumping_cargo phase active
            F2T_HAULING_STATE.current_phase = "dumping_cargo"
            F2T_HAULING_STATE.dump_location = next_dump

            -- If already at destination, dump immediately
            if nav_result == true and not F2T_SPEEDWALK_ACTIVE then
                tempTimer(0.5, function()
                    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                        return
                    end
                    f2t_hauling_phase_dump_cargo()
                end)
            end
            -- Otherwise speedwalk is in progress or navigation is retrying, GMCP handler will detect completion
        else
            -- No more exchanges available - jettison instead
            cecho(string.format("\n<yellow>[hauling]<reset> No more exchanges buying <cyan>%s<reset>, jettisoning...\n", commodity))
            f2t_debug_log("[hauling] No more exchanges available, jettisoning cargo")

            f2t_hauling_jettison_cargo(function()
                f2t_hauling_finish_remove_commodity()
            end)
        end
    end)
end

-- Actually remove commodity from queue (called after cargo is clear)
function f2t_hauling_finish_remove_commodity()
    -- Save history for this commodity before removing
    if F2T_HAULING_STATE.current_commodity and F2T_HAULING_STATE.commodity_cycles > 0 then
        table.insert(F2T_HAULING_STATE.commodity_history, {
            commodity = F2T_HAULING_STATE.current_commodity,
            cycles = F2T_HAULING_STATE.commodity_cycles,
            profit = F2T_HAULING_STATE.commodity_total_profit
        })
    end

    -- Remove current commodity from queue
    table.remove(F2T_HAULING_STATE.commodity_queue, F2T_HAULING_STATE.queue_index)

    f2t_debug_log("[hauling] Removed commodity from queue, %d remaining",
        #F2T_HAULING_STATE.commodity_queue)

    -- Don't increment index since we removed an item - next commodity is now at same index
    -- Move to next commodity
    f2t_hauling_next_commodity()
end

-- Phase 2: Navigate to buy location
function f2t_hauling_phase_navigate_to_buy()
    if not F2T_HAULING_STATE.buy_location then
        cecho("\n<red>[hauling]<reset> No buy location set\n")
        f2t_hauling_stop()
        return
    end

    local planet = F2T_HAULING_STATE.buy_location.planet
    local destination = string.format("%s exchange", planet)

    cecho(string.format("\n<green>[hauling]<reset> Navigating to buy location: <cyan>%s exchange<reset>\n", planet))
    f2t_debug_log("[hauling] Navigating to: %s", destination)

    -- Navigate to planet's exchange using map system
    local nav_result = f2t_map_navigate(destination)

    -- Note: f2t_map_navigate may return false if current location unknown,
    -- but it will auto-retry with 'look' command. Event handler will detect completion.

    -- If we got true AND speedwalk is not active, we're already at destination
    if nav_result == true and not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling] Already at buy location, waiting for GMCP update")
        tempTimer(0.5, function()
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            f2t_debug_log("[hauling] GMCP ready, proceeding to buy")
            f2t_hauling_transition("buying")
        end)
    end
    -- Otherwise speedwalk is in progress or navigation is retrying, event handler will detect completion
end

-- Phase 3: Buy commodity
function f2t_hauling_phase_buy()
    if not F2T_HAULING_STATE.current_commodity then
        cecho("\n<red>[hauling]<reset> No commodity selected\n")
        f2t_hauling_stop()
        return
    end

    -- Check if cargo hold has leftover cargo from a previous failed sell
    local existing_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if existing_cargo and #existing_cargo > 0 then
        F2T_HAULING_STATE.cargo_clear_attempts = (F2T_HAULING_STATE.cargo_clear_attempts or 0) + 1
        if F2T_HAULING_STATE.cargo_clear_attempts > 2 then
            cecho(string.format("\n<red>[hauling]<reset> Failed to clear cargo after %d attempts, stopping\n",
                F2T_HAULING_STATE.cargo_clear_attempts - 1))
            f2t_debug_log("[hauling] Cargo clear attempts exhausted (%d), stopping", F2T_HAULING_STATE.cargo_clear_attempts - 1)
            f2t_hauling_do_stop()
            return
        end
        cecho(string.format("\n<yellow>[hauling]<reset> Cargo hold not empty (%d lots remaining), selling before buying\n",
            #existing_cargo))
        f2t_debug_log("[hauling] Cargo hold has %d lots, selling before buying (attempt %d)", #existing_cargo, F2T_HAULING_STATE.cargo_clear_attempts)
        f2t_bulk_sell_start(nil, nil, function(commodity_sold, lots_sold, status, error_msg)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            local still_has_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
            if still_has_cargo and #still_has_cargo > 0 then
                cecho(string.format("\n<yellow>[hauling]<reset> Still %d lots unsold, jettisoning to clear hold\n", #still_has_cargo))
                f2t_debug_log("[hauling] Jettisoning %d unsellable lots", #still_has_cargo)
                f2t_hauling_jettison_cargo(function()
                    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                        return
                    end
                    -- Retry buy (counter already incremented)
                    f2t_hauling_transition("buying")
                end)
                return
            end
            -- Cargo clear, reset counter and proceed
            F2T_HAULING_STATE.cargo_clear_attempts = 0
            f2t_hauling_transition("buying")
        end)
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Buying <cyan>%s<reset> to fill hold...\n",
        F2T_HAULING_STATE.current_commodity))

    f2t_debug_log("[hauling] Buying commodity: %s", F2T_HAULING_STATE.current_commodity)

    -- Use bulk buy with callback (programmatic mode)
    f2t_bulk_buy_start(F2T_HAULING_STATE.current_commodity, nil, function(commodity, lots_bought, status, error_msg)
        -- Callback invoked when buy operation completes
        f2t_debug_log("[hauling] Buy complete: commodity=%s, lots=%d, status=%s", commodity, lots_bought, status)

        -- Check if still active and not paused
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Handle error cases
        if status == "error" then
            cecho(string.format("\n<red>[hauling]<reset> Buy failed: %s\n", error_msg or "unknown error"))
            f2t_hauling_stop()
            return
        end

        -- Verify we have cargo before continuing
        local cargo = gmcp.char.ship.cargo
        if not cargo or #cargo == 0 then
            cecho("\n<red>[hauling]<reset> Buy failed - no cargo loaded\n")
            f2t_hauling_stop()
            return
        end

        -- Extract actual cost from cargo data
        -- Cargo structure: {commodity, base, cost, origin}
        local cargo_lot = cargo[1]  -- Get first lot (all should be same commodity)
        if cargo_lot then
            F2T_HAULING_STATE.actual_cost = cargo_lot.cost or 0
            f2t_debug_log("[hauling] Cargo cost: %d ig/ton", F2T_HAULING_STATE.actual_cost)
        end

        -- Track purchase cost
        local total_cost = lots_bought * F2T_HAULING_STATE.actual_cost * 75  -- Use actual cost from cargo
        F2T_HAULING_STATE.current_commodity_stats.lots_bought =
            F2T_HAULING_STATE.current_commodity_stats.lots_bought + lots_bought
        F2T_HAULING_STATE.current_commodity_stats.total_cost =
            F2T_HAULING_STATE.current_commodity_stats.total_cost + total_cost

        f2t_debug_log("[hauling] Tracking buy: %d lots at %d ig/ton = %d ig total cost",
            lots_bought, F2T_HAULING_STATE.actual_cost, total_cost)

        cecho(string.format("\n<green>[hauling]<reset> Bought %d lots of <cyan>%s<reset> at <yellow>%d ig/ton<reset> (cost: %d ig)\n",
            lots_bought, commodity, F2T_HAULING_STATE.actual_cost, total_cost))

        -- Transition to navigating to sell location
        f2t_hauling_transition("navigating_to_sell")
    end)
end

-- Phase 4: Navigate to sell location
function f2t_hauling_phase_navigate_to_sell()
    if not F2T_HAULING_STATE.sell_location then
        cecho("\n<red>[hauling]<reset> No sell location set\n")
        f2t_hauling_stop()
        return
    end

    local planet = F2T_HAULING_STATE.sell_location.planet
    local destination = string.format("%s exchange", planet)

    cecho(string.format("\n<green>[hauling]<reset> Navigating to sell location: <cyan>%s exchange<reset>\n", planet))
    f2t_debug_log("[hauling] Navigating to: %s", destination)

    -- Navigate to planet's exchange
    local nav_result = f2t_map_navigate(destination)

    -- Note: f2t_map_navigate may return false if current location unknown,
    -- but it will auto-retry with 'look' command. Event handler will detect completion.

    -- If we got true AND speedwalk is not active, we're already at destination
    if nav_result == true and not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling] Already at sell location, waiting for GMCP update")
        tempTimer(0.5, function()
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            f2t_debug_log("[hauling] GMCP ready, proceeding to sell")
            f2t_hauling_transition("selling")
        end)
    end
    -- Otherwise speedwalk is in progress or navigation is retrying, event handler will detect completion
end

-- Phase 5: Sell commodity
function f2t_hauling_phase_sell()
    if not F2T_HAULING_STATE.current_commodity then
        cecho("\n<red>[hauling]<reset> No commodity selected\n")
        f2t_hauling_stop()
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Selling <cyan>%s<reset>...\n",
        F2T_HAULING_STATE.current_commodity))

    f2t_debug_log("[hauling] Selling commodity: %s", F2T_HAULING_STATE.current_commodity)

    -- Use bulk sell with callback (programmatic mode)
    f2t_bulk_sell_start(F2T_HAULING_STATE.current_commodity, nil, function(commodity, lots_sold, status, error_msg)
        -- Callback invoked when sell operation completes
        f2t_debug_log("[hauling] Sell complete: commodity=%s, lots=%d, status=%s", commodity, lots_sold, status)

        -- Check if still active and not paused
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Handle error cases
        if status == "error" then
            cecho(string.format("\n<red>[hauling]<reset> Sell failed: %s\n", error_msg or "unknown error"))
            f2t_hauling_stop()
            return
        end

        -- Track sales revenue
        -- Note: sell_location.price = what the exchange PAYS US (exchange's buy price)
        local exchange_buy_price = F2T_HAULING_STATE.sell_location.price
        local total_revenue = lots_sold * exchange_buy_price * 75  -- lots * price/ton * 75 tons/lot
        F2T_HAULING_STATE.current_commodity_stats.lots_sold =
            F2T_HAULING_STATE.current_commodity_stats.lots_sold + lots_sold
        F2T_HAULING_STATE.current_commodity_stats.total_revenue =
            F2T_HAULING_STATE.current_commodity_stats.total_revenue + total_revenue

        f2t_debug_log("[hauling] Tracking sell: %d lots at %d ig/ton = %d ig total revenue",
            lots_sold, exchange_buy_price, total_revenue)

        -- Calculate profit margin: (revenue - cost) / cost
        local profit_per_ton = exchange_buy_price - F2T_HAULING_STATE.actual_cost
        local profit_margin_pct = (profit_per_ton / F2T_HAULING_STATE.actual_cost) * 100

        f2t_debug_log("[hauling] Profit margin: %.1f%% (%d - %d = %d profit per ton)",
            profit_margin_pct, exchange_buy_price, F2T_HAULING_STATE.actual_cost, profit_per_ton)

        -- Check if profit margin fell below threshold
        local margin_too_low = profit_margin_pct < F2T_HAULING_STATE.margin_threshold_pct

        -- Check if we're selling at a loss
        local selling_at_loss = exchange_buy_price <= F2T_HAULING_STATE.actual_cost

        if selling_at_loss or margin_too_low then
            if selling_at_loss then
                cecho(string.format("\n<red>[hauling]<reset> Exchange buying at/below our cost for <cyan>%s<reset> (%d <= %d ig/ton) - LOSS!\n",
                    commodity, exchange_buy_price, F2T_HAULING_STATE.actual_cost))
            else
                cecho(string.format("\n<yellow>[hauling]<reset> Profit margin too low for <cyan>%s<reset> (%.1f%% < %.0f%%)\n",
                    commodity, profit_margin_pct, F2T_HAULING_STATE.margin_threshold_pct))
            end
            cecho("\n<yellow>[hauling]<reset> Abandoning commodity and dumping remaining cargo\n")

            -- Complete this commodity cycle with what we've sold
            f2t_hauling_complete_commodity_cycle()

            -- Dump remaining cargo and move to next commodity
            f2t_hauling_remove_current_commodity()
            return
        end

        cecho(string.format("\n<green>[hauling]<reset> Sold %d lots of <cyan>%s<reset> at <yellow>%d ig/ton<reset> (realized margin: %.1f%%, revenue: %d ig)\n",
            lots_sold, commodity, exchange_buy_price, profit_margin_pct, total_revenue))

        -- Check if we still have cargo (partial sell)
        local cargo = gmcp.char.ship.cargo
        if cargo and #cargo > 0 then
            -- Still have cargo, try next best sell location
            f2t_debug_log("[hauling] Partial sell, %d lots remaining, finding next location", #cargo)

            -- Re-check prices to find next best sell location
            f2t_hauling_find_next_sell_location()
        else
            -- All sold, cycle complete
            F2T_HAULING_STATE.sell_attempts = 0

            -- Complete this commodity cycle
            f2t_hauling_complete_commodity_cycle()

            -- Get fresh price data to verify still profitable before next cycle
            f2t_debug_log("[hauling] Cycle complete, checking if still profitable")
            f2t_hauling_get_commodity_details(F2T_HAULING_STATE.current_commodity)
        end
    end)
end

-- Complete a commodity cycle (all cargo sold)
function f2t_hauling_complete_commodity_cycle()
    -- Calculate profit for this cycle
    local cycle_profit = F2T_HAULING_STATE.current_commodity_stats.total_revenue -
                         F2T_HAULING_STATE.current_commodity_stats.total_cost

    F2T_HAULING_STATE.current_commodity_stats.profit = cycle_profit
    F2T_HAULING_STATE.commodity_cycles = F2T_HAULING_STATE.commodity_cycles + 1
    F2T_HAULING_STATE.total_cycles = F2T_HAULING_STATE.total_cycles + 1
    F2T_HAULING_STATE.session_profit = F2T_HAULING_STATE.session_profit + cycle_profit
    F2T_HAULING_STATE.commodity_total_profit = F2T_HAULING_STATE.commodity_total_profit + cycle_profit

    local lots_traded = F2T_HAULING_STATE.current_commodity_stats.lots_sold
    local profit_per_lot = lots_traded > 0 and math.floor(cycle_profit / lots_traded) or 0

    cecho(string.format("\n<green>[hauling]<reset> Commodity cycle complete: <cyan>%s<reset>\n",
        F2T_HAULING_STATE.current_commodity))
    cecho(string.format("  Profit: <green>%d ig<reset> (%d ig/lot) | Total cycles: <cyan>%d<reset>\n",
        cycle_profit, profit_per_lot, F2T_HAULING_STATE.total_cycles))

    -- Check merchant points progress (if Merchant rank)
    if f2t_is_rank_exactly("Merchant") and f2t_merchant_has_enough_points() then
        local points = f2t_merchant_get_points() or 0
        cecho(string.format("\n<yellow>[hauling]<reset> <green>You have %d merchant points - ready to advance to Trader rank!<reset>\n", points))
        cecho("\n<dim_grey>Continue hauling or promote to Trader when ready<reset>\n")
    end

    f2t_debug_log("[hauling] Cycle stats - commodity: %s, cycles: %d, profit: %d ig",
        F2T_HAULING_STATE.current_commodity, F2T_HAULING_STATE.commodity_cycles, cycle_profit)

    -- Reset cycle stats for next iteration
    F2T_HAULING_STATE.current_commodity_stats = {
        lots_bought = 0,
        total_cost = 0,
        lots_sold = 0,
        total_revenue = 0,
        profit = 0
    }
end

-- ========================================
-- Exchange Event Handlers
-- ========================================

--- Check if navigation to buy location is complete
function f2t_hauling_check_nav_to_buy_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "navigating_to_buy" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        -- Capture result immediately to prevent race conditions with next speedwalk
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling] Speedwalk stopped with result: %s", result or "unknown")

        -- NOTE: Exchange handlers process result immediately without tempTimer (unlike AC handlers)
        -- because they just transition to next phase without needing to verify location via GMCP.
        -- The buying/selling phases handle their own location verification as needed.

        -- Check speedwalk result and handle accordingly
        if result == "completed" then
            -- Speedwalk completed successfully - proceed to buying
            f2t_debug_log("[hauling] Navigation to buy location complete")
            f2t_hauling_transition("buying")

        elseif result == "stopped" then
            -- User manually stopped speedwalk - respect that and stop hauling
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_debug_log("[hauling] User stopped navigation, stopping hauling")
            f2t_hauling_stop()

        elseif result == "failed" then
            -- Speedwalk couldn't reach destination after retries - path is blocked
            -- NOTE: Exchange mode stops hauling on "failed" because the selected commodity/
            -- location is the most profitable choice. Can't proceed without reaching it.
            -- AC mode fetches new jobs instead because many jobs are available.
            local buy_loc = F2T_HAULING_STATE.buy_location
            local location_str = buy_loc and string.format("%s:%s", buy_loc.system, buy_loc.planet) or "buy location"
            cecho(string.format("\n<red>[hauling]<reset> Cannot reach %s (path blocked), stopping hauling\n", location_str))
            f2t_debug_log("[hauling] Navigation to buy failed after retries, stopping")
            f2t_hauling_stop()

        else
            -- No result or unknown - treat as legacy behavior for compatibility
            f2t_debug_log("[hauling] Unknown speedwalk result, using legacy behavior")
            f2t_hauling_transition("buying")
        end
    end
end

--- Check if navigation to sell location is complete
function f2t_hauling_check_nav_to_sell_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "navigating_to_sell" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        -- Capture result immediately to prevent race conditions with next speedwalk
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling] Speedwalk stopped with result: %s", result or "unknown")

        -- (See buy handler for explanation of Exchange navigation design)

        -- Check speedwalk result and handle accordingly
        if result == "completed" then
            -- Speedwalk completed successfully - proceed to selling
            f2t_debug_log("[hauling] Navigation to sell location complete")
            f2t_hauling_transition("selling")

        elseif result == "stopped" then
            -- User manually stopped speedwalk - respect that and stop hauling
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_debug_log("[hauling] User stopped navigation, stopping hauling")
            f2t_hauling_stop()

        elseif result == "failed" then
            -- Speedwalk couldn't reach destination after retries - path is blocked
            -- (See buy handler for explanation of why Exchange stops on "failed")
            local sell_loc = F2T_HAULING_STATE.sell_location
            local location_str = sell_loc and string.format("%s:%s", sell_loc.system, sell_loc.planet) or "sell location"
            cecho(string.format("\n<red>[hauling]<reset> Cannot reach %s (path blocked), stopping hauling\n", location_str))
            f2t_debug_log("[hauling] Navigation to sell failed after retries, stopping")
            f2t_hauling_stop()

        else
            -- No result or unknown - treat as legacy behavior for compatibility
            f2t_debug_log("[hauling] Unknown speedwalk result, using legacy behavior")
            f2t_hauling_transition("selling")
        end
    end
end

--- Find next sell location after partial sell
function f2t_hauling_find_next_sell_location()
    if not F2T_HAULING_STATE.current_commodity then
        f2t_hauling_stop()
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Finding next sell location for <cyan>%s<reset>...\n",
        F2T_HAULING_STATE.current_commodity))

    -- Increment sell attempts
    F2T_HAULING_STATE.sell_attempts = F2T_HAULING_STATE.sell_attempts + 1

    -- Get fresh price data
    f2t_price_check_commodity(F2T_HAULING_STATE.current_commodity, function(commodity_name, parsed_data, analysis)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Find next best sell location
        -- Note: top_buy = "exchanges buying" (where WE sell)
        if #analysis.top_buy >= F2T_HAULING_STATE.sell_attempts then
            local next_sell = analysis.top_buy[F2T_HAULING_STATE.sell_attempts]

            -- Check if this location meets our margin threshold
            local profit_per_ton = next_sell.price - F2T_HAULING_STATE.actual_cost
            local profit_margin_pct = (profit_per_ton / F2T_HAULING_STATE.actual_cost) * 100

            f2t_debug_log("[hauling] Next sell location: %s: %s at %d ig/ton (margin: %.1f%%)",
                next_sell.system, next_sell.planet, next_sell.price, profit_margin_pct)

            -- Check if margin is acceptable
            if profit_margin_pct < F2T_HAULING_STATE.margin_threshold_pct then
                cecho(string.format("\n<yellow>[hauling]<reset> Best remaining location has insufficient margin (%.1f%% < %.0f%%)\n",
                    profit_margin_pct, F2T_HAULING_STATE.margin_threshold_pct))
                cecho("\n<yellow>[hauling]<reset> Abandoning commodity and dumping remaining cargo\n")

                -- Complete cycle and move to next commodity
                f2t_hauling_complete_commodity_cycle()
                f2t_hauling_remove_current_commodity()
                return
            end

            -- Margin is acceptable, navigate to this location
            F2T_HAULING_STATE.sell_location = {
                system = next_sell.system,
                planet = next_sell.planet,
                price = next_sell.price
            }

            f2t_hauling_transition("navigating_to_sell")
        else
            cecho("\n<red>[hauling]<reset> No more sell locations available\n")

            -- Dump remaining cargo and move to next commodity
            f2t_hauling_complete_commodity_cycle()
            f2t_hauling_remove_current_commodity()
        end
    end)
end

--- Check if navigation to dump location is complete
function f2t_hauling_check_nav_to_dump_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "dumping_cargo" then
        return
    end

    -- Check if speedwalk is no longer active
    if not F2T_SPEEDWALK_ACTIVE then
        -- Capture result immediately to prevent race conditions with next speedwalk
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling] Speedwalk stopped with result: %s", result or "unknown")

        -- (See buy handler for explanation of Exchange navigation design)

        -- Check speedwalk result and handle accordingly
        if result == "completed" then
            -- Speedwalk completed successfully - proceed to dumping
            f2t_debug_log("[hauling] Navigation to dump location complete")
            f2t_hauling_phase_dump_cargo()

        elseif result == "stopped" then
            -- User manually stopped speedwalk - respect that and stop hauling
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_debug_log("[hauling] User stopped navigation, stopping hauling")
            f2t_hauling_stop()

        elseif result == "failed" then
            -- Speedwalk couldn't reach dump location after retries - path is blocked
            -- (See buy handler for explanation of why Exchange stops on "failed")
            cecho("\n<red>[hauling]<reset> Cannot reach dump location (path blocked), stopping hauling\n")
            f2t_debug_log("[hauling] Navigation to dump failed after retries, stopping")
            f2t_hauling_stop()

        else
            -- No result or unknown - treat as legacy behavior for compatibility
            f2t_debug_log("[hauling] Unknown speedwalk result, using legacy behavior")
            f2t_hauling_phase_dump_cargo()
        end
    end
end

--- Register Exchange-specific GMCP event handlers
--- @return string Event handler ID
function f2t_exchange_register_handlers()
    local handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        -- Check navigation completion after brief delay for GMCP to settle
        tempTimer(0.5, function()
            f2t_hauling_check_nav_to_buy_complete()
            f2t_hauling_check_nav_to_sell_complete()
            f2t_hauling_check_nav_to_dump_complete()
        end)
    end)

    f2t_debug_log("[hauling/exchange] Registered Exchange event handlers")
    return handler_id
end

--- Cleanup Exchange event handlers
--- @param handler_id string Event handler ID to kill
function f2t_exchange_cleanup_handlers(handler_id)
    if handler_id then
        killAnonymousEventHandler(handler_id)
        f2t_debug_log("[hauling/exchange] Cleaned up Exchange event handlers")
    end
end

f2t_debug_log("[hauling] Phase implementations loaded")
