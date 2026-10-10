-- Buy/sell cycle phase implementations

-- Returns a set of lowercase, trimmed commodity names.
local function parse_excluded_commodities()
    local setting = f2t_settings_get("hauling", "excluded_commodities")
    if not setting or setting == "" then
        return {}
    end

    local excluded = {}
    for commodity in string.gmatch(setting, "[^,]+") do
        local trimmed = commodity:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            excluded[trimmed:lower()] = true
        end
    end

    return excluded
end

-- Navigation already heals what it can on the way; this is for when it still can't get there.
local function pause_on_nav_failure(planet, reason)
    cecho(string.format("\n<red>[hauling]<reset> Can't reach %s exchange (%s), pausing hauling\n",
        planet, reason or "no route"))
    cecho("<dim_grey>Resolve the issue above and run 'haul resume'<reset>\n")
    f2t_hauling_pause(true)
end

--- Whether exchange hauling skips a commodity (hauling/excluded_commodities)
--- @param commodity string
--- @return boolean
function f2t_hauling_commodity_excluded(commodity)
    return parse_excluded_commodities()[commodity:lower()] == true
end

--- Commodities exchange hauling would queue from a price scan, best first
--- @param results table Array of price analyses (f2t_price_get_all_data)
--- @return table Up to five analyses
function f2t_hauling_rank_commodities(results)
    local excluded = parse_excluded_commodities()

    local tradeable = {}
    for _, analysis in ipairs(results) do
        if excluded[analysis.commodity:lower()] then
            f2t_debug_log("[hauling] Skipping excluded commodity: %s", analysis.commodity)
        elseif analysis.profit and analysis.profit > 0 and
           #analysis.top_buy > 0 and #analysis.top_sell > 0 then
            table.insert(tradeable, analysis)
        end
    end

    table.sort(tradeable, function(a, b)
        return a.profit > b.profit
    end)

    local queue = {}
    for i = 1, math.min(5, #tradeable) do queue[i] = tradeable[i] end
    return queue
end

-- Phase 1: analyze commodities, queue the most profitable
function f2t_hauling_phase_analyze()
    f2t_debug_log("[hauling] Phase: Analyzing commodities")

    local started, how = f2t_price_get_all_data(function(results, err)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if err then
            cecho(string.format("\n<red>[hauling]<reset> Price scan stopped: %s\n", err))
            f2t_hauling_stop()
            return
        end

        local tradeable = f2t_hauling_rank_commodities(results)

        if #tradeable == 0 then
            cecho("\n<red>[hauling]<reset> No profitable commodities found\n")
            f2t_hauling_stop()
            return
        end

        F2T_HAULING_STATE.commodity_queue = {}
        local count = #tradeable
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

        f2t_hauling_next_commodity()
    end, { owner = "hauling", maxAge = F2T_PRICE_SCAN_REUSE_SECONDS })

    if not started then
        f2t_hauling_stop()
    elseif how == "reused" then
        cecho("\n<green>[hauling]<reset> Using the price scan from the last few minutes\n")
    else
        cecho("\n<green>[hauling]<reset> Analyzing commodity prices (this may take a minute)...\n")
    end
end

-- Move to next commodity in queue
function f2t_hauling_next_commodity()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    -- Deferred pause: apply now that we're between commodities.
    if F2T_HAULING_STATE.pause_requested then
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true
        F2T_HAULING_STATE.current_phase = "next_commodity"
        cecho("\n<green>[hauling]<reset> Paused between commodities\n")
        f2t_debug_log("[hauling] Deferred pause activated between commodities")
        return
    end

    if F2T_HAULING_STATE.stopping then
        f2t_debug_log("[hauling] Graceful stop complete, cargo sold")
        cecho("\n<green>[hauling]<reset> Cargo sold, stopping now...\n")
        f2t_hauling_do_stop()
        return
    end

    if not F2T_HAULING_STATE.commodity_queue or
       #F2T_HAULING_STATE.commodity_queue == 0 or
       F2T_HAULING_STATE.queue_index > #F2T_HAULING_STATE.commodity_queue then

        f2t_debug_log("[hauling] Commodity queue exhausted, re-analyzing")

        local cycle_pause = tonumber(f2t_settings_get("hauling", "cycle_pause")) or 0
        local use_safe_room = f2t_settings_get("hauling", "use_safe_room")
        local safe_room = f2t_settings_get("hauling", "safe_room")

        -- Clear any stale timer from a previous cycle.
        if F2T_HAULING_STATE.cycle_pause_timer_id then
            killTimer(F2T_HAULING_STATE.cycle_pause_timer_id)
            F2T_HAULING_STATE.cycle_pause_timer_id = nil
        end

        if cycle_pause > 0 then
            F2T_HAULING_STATE.current_phase = "cycle_pausing"

            if use_safe_room and safe_room and safe_room ~= "" then
                -- Navigate to safe room, pause, then return and continue.
                local current_location = F2T_MAP_CURRENT_ROOM_ID
                if current_location then
                    F2T_HAULING_STATE.cycle_pause_return_location = current_location
                    cecho(string.format("\n<green>[hauling]<reset> All commodities traded, going to safe room " ..
                        "for <yellow>%d seconds<reset>...\n", cycle_pause))
                    f2t_debug_log(
                        "[hauling] Navigating to safe room for cycle pause (%d seconds), will return to room: %s",
                        cycle_pause, current_location)

                    local function refresh()
                        F2T_HAULING_STATE.cycle_pause_return_location = nil
                        if not F2T_HAULING_STATE.pause_requested then
                            cecho("\n<green>[hauling]<reset> Pause complete, refreshing market data...\n")
                        end
                        f2t_hauling_transition("analyzing")
                    end

                    local function pauseThenReturn()
                        if F2T_HAULING_STATE.pause_requested then
                            f2t_hauling_transition("analyzing")
                            return
                        end
                        cecho(string.format(
                            "\n<green>[hauling]<reset> Pausing at safe room for <yellow>%d seconds<reset>...\n",
                            cycle_pause))
                        F2T_HAULING_STATE.cycle_pause_end_time = os.time() + cycle_pause
                        F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                            F2T_HAULING_STATE.cycle_pause_timer_id = nil
                            F2T_HAULING_STATE.cycle_pause_end_time = nil
                            if not (F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                                    and F2T_HAULING_STATE.current_phase == "cycle_pausing") then
                                return
                            end
                            local return_to = F2T_HAULING_STATE.cycle_pause_return_location
                            if not return_to then
                                refresh()
                                return
                            end
                            if not F2T_HAULING_STATE.pause_requested then
                                cecho(string.format(
                                    "\n<green>[hauling]<reset> Returning to previous location: <cyan>%s<reset>\n",
                                    getRoomName(return_to) or return_to))
                            end
                            f2t_hauling_walk(return_to, refresh, refresh)
                        end)
                    end

                    f2t_hauling_walk(safe_room, pauseThenReturn, pauseThenReturn)
                else
                    -- Can't determine current location, pause in place.
                    local pause_in_place_msg =
                        "\n<green>[hauling]<reset> All commodities traded, pausing for <yellow>%d seconds<reset> " ..
                        "before refreshing...\n"
                    cecho(string.format(pause_in_place_msg, cycle_pause))
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
                -- No safe room, pause in place.
                local pause_in_place_msg2 =
                    "\n<green>[hauling]<reset> All commodities traded, pausing for <yellow>%d seconds<reset> " ..
                    "before refreshing...\n"
                cecho(string.format(pause_in_place_msg2, cycle_pause))
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

    local commodity_data = F2T_HAULING_STATE.commodity_queue[F2T_HAULING_STATE.queue_index]
    F2T_HAULING_STATE.current_commodity = commodity_data.commodity
    F2T_HAULING_STATE.expected_profit = commodity_data.expected_profit

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

    f2t_debug_log("[hauling] Starting commodity %d/%d: %s (expected profit: %d ig/ton)",
        F2T_HAULING_STATE.queue_index, #F2T_HAULING_STATE.commodity_queue,
        commodity_data.commodity, commodity_data.expected_profit)

    cecho(string.format(
        "\n<green>[hauling]<reset> Trading <cyan>%s<reset> (expected profit: <green>%d ig/ton<reset>)\n",
        commodity_data.commodity, commodity_data.expected_profit))

    f2t_hauling_get_commodity_details(commodity_data.commodity)
end

-- Get detailed price data for selected commodity
function f2t_hauling_get_commodity_details(commodity)
    f2t_debug_log("[hauling] Getting details for: %s", commodity)

    f2t_price_check_for("hauling", commodity, function(commodity_name, _parsed_data, analysis)
        f2t_debug_log("[hauling] Received commodity details callback for: %s", commodity_name)
        f2t_debug_log("[hauling] State - active: %s, paused: %s",
            tostring(F2T_HAULING_STATE.active), tostring(F2T_HAULING_STATE.paused))

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            f2t_debug_log("[hauling] Callback aborted - hauling not active or paused")
            return
        end

        if F2T_HAULING_STATE.stopping then
            f2t_debug_log("[hauling] Graceful stop complete, sold all cargo")
            cecho("\n<green>[hauling]<reset> Cargo sold, stopping now...\n")
            f2t_hauling_do_stop()
            return
        end

        f2t_debug_log("[hauling] Analysis - top_buy count: %d, top_sell count: %d, profit: %d",
            #analysis.top_buy, #analysis.top_sell, analysis.profit or 0)

        -- Margin re-validated only after the first cycle; first cycle always starts trading.
        if F2T_HAULING_STATE.commodity_cycles > 0 then
            local best_sell_price = #analysis.top_buy > 0 and analysis.top_buy[1].price or 0
            local best_buy_price = #analysis.top_sell > 0 and analysis.top_sell[1].price or 0

            if best_buy_price > 0 then
                local expected_margin_pct = ((best_sell_price - best_buy_price) / best_buy_price) * 100

                f2t_debug_log("[hauling] Margin check (cycle %d): sell=%d, buy=%d, margin=%.1f%%, threshold=%.0f%%",
                    F2T_HAULING_STATE.commodity_cycles, best_sell_price, best_buy_price,
                    expected_margin_pct, F2T_HAULING_STATE.margin_threshold_pct)

                if expected_margin_pct < F2T_HAULING_STATE.margin_threshold_pct then
                    local margin_low_msg =
                        "\n<yellow>[hauling]<reset> Current market margin for <cyan>%s<reset> too low " ..
                        "(%.1f%% < %.0f%%) - moving to next commodity\n"
                    cecho(string.format(margin_low_msg,
                        commodity, expected_margin_pct, F2T_HAULING_STATE.margin_threshold_pct))
                    f2t_debug_log("[hauling] Removing commodity from queue due to low current market margin")

                    f2t_hauling_remove_current_commodity()
                    return
                end
            end
        end

        -- top_sell = "exchanges selling" (where WE buy).
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

        -- top_buy = "exchanges buying" (where WE sell).
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

        f2t_hauling_transition("navigating_to_buy")
    end)
end

-- Remove current commodity from queue and move to next
function f2t_hauling_remove_current_commodity()
    if not F2T_HAULING_STATE.commodity_queue then
        return
    end

    -- Cargo still aboard has to be dumped before switching commodities.
    local cargo = gmcp.char.ship.cargo
    if cargo and #cargo > 0 then
        local commodity = F2T_HAULING_STATE.current_commodity
        cecho(string.format(
            "\n<yellow>[hauling]<reset> Abandoning <cyan>%s<reset>, finding exchange to dump remaining cargo\n",
            commodity))
        f2t_debug_log("[hauling] Need to dump %d lots of %s before switching commodity", #cargo, commodity)

        F2T_HAULING_STATE.dump_attempts = 0

        f2t_price_check_for("hauling", commodity, function(_commodity_name, _parsed_data, analysis)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end

            if analysis and analysis.top_buy and #analysis.top_buy > 0 then
                local dump_location = analysis.top_buy[1]

                f2t_debug_log("[hauling] Dumping at: %s: %s (price: %d ig/ton)",
                    dump_location.system, dump_location.planet, dump_location.price)

                F2T_HAULING_STATE.dump_location = dump_location
                f2t_hauling_transition("dumping_cargo")
            else
                -- No exchanges buying this commodity - jettison and move on.
                cecho(string.format(
                    "\n<yellow>[hauling]<reset> No exchanges buying %s, jettisoning remaining cargo\n", commodity))
                f2t_hauling_jettison_cargo(function()
                    f2t_hauling_finish_remove_commodity()
                end)
            end
        end)
        return
    end

    f2t_hauling_finish_remove_commodity()
end

-- Phase: walk to the exchange chosen to dump the abandoned commodity at
function f2t_hauling_phase_navigate_to_dump()
    local dump_location = F2T_HAULING_STATE.dump_location
    if not dump_location then
        f2t_hauling_find_next_dump_location()
        return
    end
    cecho(string.format("\n<yellow>[hauling]<reset> Navigating to dump location: <cyan>%s exchange<reset>\n",
        dump_location.planet))
    f2t_hauling_walk(string.format("%s exchange", dump_location.planet), f2t_hauling_phase_dump_cargo,
        function(reason)
            cecho(string.format("\n<yellow>[hauling]<reset> Cannot reach %s (%s), trying next dump location\n",
                dump_location.planet, reason or "no route"))
            f2t_hauling_find_next_dump_location()
        end)
end

-- Phase: dump cargo at any price (when abandoning a commodity)
function f2t_hauling_phase_dump_cargo()
    local commodity = F2T_HAULING_STATE.current_commodity

    if not commodity then
        cecho("\n<red>[hauling]<reset> No commodity to dump\n")
        f2t_hauling_stop()
        return
    end
    F2T_HAULING_STATE.current_phase = "dump_selling"

    cecho(string.format("\n<yellow>[hauling]<reset> Dumping all <cyan>%s<reset> cargo at any price...\n", commodity))
    f2t_debug_log("[hauling] Dumping commodity: %s", commodity)

    f2t_bulk_sell_start(nil, nil, function(_sold_commodity, lots_sold, status, _error_msg)
        f2t_debug_log("[hauling] Dump sell complete: sold %d lots, status: %s", lots_sold, status)

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        local cargo = gmcp.char.ship.cargo
        if cargo and #cargo > 0 then
            f2t_debug_log("[hauling] %d lots remain after dump, finding next exchange", #cargo)
            cecho(string.format(
                "\n<yellow>[hauling]<reset> %d lots remain, finding next exchange to dump...\n", #cargo))

            f2t_hauling_find_next_dump_location()
        else
            f2t_debug_log("[hauling] All cargo dumped successfully")
            cecho("\n<green>[hauling]<reset> All cargo dumped\n")

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

    F2T_HAULING_STATE.dump_attempts = (F2T_HAULING_STATE.dump_attempts or 0) + 1

    local MAX_DUMP_ATTEMPTS = 5

    f2t_debug_log("[hauling] Finding dump location #%d for %s (max: %d)",
        F2T_HAULING_STATE.dump_attempts, commodity, MAX_DUMP_ATTEMPTS)

    if F2T_HAULING_STATE.dump_attempts > MAX_DUMP_ATTEMPTS then
        cecho(string.format(
            "\n<yellow>[hauling]<reset> Attempted %d exchanges, jettisoning remaining <cyan>%s<reset>...\n",
            MAX_DUMP_ATTEMPTS, commodity))
        f2t_debug_log("[hauling] Max dump attempts exceeded, jettisoning cargo")

        f2t_hauling_jettison_cargo(function()
            f2t_hauling_finish_remove_commodity()
        end)
        return
    end

    f2t_price_check_for("hauling", commodity, function(_commodity_name, _parsed_data, analysis)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if #analysis.top_buy >= F2T_HAULING_STATE.dump_attempts then
            local next_dump = analysis.top_buy[F2T_HAULING_STATE.dump_attempts]

            f2t_debug_log("[hauling] Next dump location: %s: %s at %d ig/ton",
                next_dump.system, next_dump.planet, next_dump.price)

            F2T_HAULING_STATE.dump_location = next_dump
            f2t_hauling_transition("dumping_cargo")
        else
            cecho(string.format(
                "\n<yellow>[hauling]<reset> No more exchanges buying <cyan>%s<reset>, jettisoning...\n", commodity))
            f2t_debug_log("[hauling] No more exchanges available, jettisoning cargo")

            f2t_hauling_jettison_cargo(function()
                f2t_hauling_finish_remove_commodity()
            end)
        end
    end)
end

-- Actually remove commodity from queue (called after cargo is clear)
function f2t_hauling_finish_remove_commodity()
    if F2T_HAULING_STATE.current_commodity and F2T_HAULING_STATE.commodity_cycles > 0 then
        table.insert(F2T_HAULING_STATE.commodity_history, {
            commodity = F2T_HAULING_STATE.current_commodity,
            cycles = F2T_HAULING_STATE.commodity_cycles,
            profit = F2T_HAULING_STATE.commodity_total_profit
        })
    end

    table.remove(F2T_HAULING_STATE.commodity_queue, F2T_HAULING_STATE.queue_index)

    f2t_debug_log("[hauling] Removed commodity from queue, %d remaining",
        #F2T_HAULING_STATE.commodity_queue)

    -- Index isn't incremented: removal shifted the next commodity into this slot.
    f2t_hauling_next_commodity()
end

-- Phase 2: navigate to buy location
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

    f2t_hauling_walk(destination,
        function() f2t_hauling_transition("buying") end,
        function(reason) pause_on_nav_failure(planet, reason) end)
end

-- Phase 3: buy commodity
function f2t_hauling_phase_buy()
    if not F2T_HAULING_STATE.current_commodity then
        cecho("\n<red>[hauling]<reset> No commodity selected\n")
        f2t_hauling_stop()
        return
    end

    -- Cargo left over from a previous failed sell has to clear before buying.
    local existing_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if existing_cargo and #existing_cargo > 0 then
        F2T_HAULING_STATE.cargo_clear_attempts = (F2T_HAULING_STATE.cargo_clear_attempts or 0) + 1
        if F2T_HAULING_STATE.cargo_clear_attempts > 2 then
            cecho(string.format("\n<red>[hauling]<reset> Failed to clear cargo after %d attempts, stopping\n",
                F2T_HAULING_STATE.cargo_clear_attempts - 1))
            f2t_debug_log("[hauling] Cargo clear attempts exhausted (%d), stopping",
                F2T_HAULING_STATE.cargo_clear_attempts - 1)
            f2t_hauling_do_stop()
            return
        end
        cecho(string.format(
            "\n<yellow>[hauling]<reset> Cargo hold not empty (%d lots remaining), selling before buying\n",
            #existing_cargo))
        f2t_debug_log("[hauling] Cargo hold has %d lots, selling before buying (attempt %d)",
            #existing_cargo, F2T_HAULING_STATE.cargo_clear_attempts)
        f2t_bulk_sell_start(nil, nil, function(_commodity_sold, _lots_sold, _status, _error_msg)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            local still_has_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
            if still_has_cargo and #still_has_cargo > 0 then
                cecho(string.format(
                    "\n<yellow>[hauling]<reset> Still %d lots unsold, jettisoning to clear hold\n", #still_has_cargo))
                f2t_debug_log("[hauling] Jettisoning %d unsellable lots", #still_has_cargo)
                f2t_hauling_jettison_cargo(function()
                    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                        return
                    end
                    -- Retry buy; the clear-attempt counter is already incremented above.
                    f2t_hauling_transition("buying")
                end)
                return
            end
            F2T_HAULING_STATE.cargo_clear_attempts = 0
            f2t_hauling_transition("buying")
        end)
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Buying <cyan>%s<reset> to fill hold...\n",
        F2T_HAULING_STATE.current_commodity))

    f2t_debug_log("[hauling] Buying commodity: %s", F2T_HAULING_STATE.current_commodity)

    f2t_bulk_buy_start(F2T_HAULING_STATE.current_commodity, nil, function(commodity, lots_bought, status, error_msg)
        f2t_debug_log("[hauling] Buy complete: commodity=%s, lots=%d, status=%s", commodity, lots_bought, status)

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if status == "error" then
            cecho(string.format("\n<red>[hauling]<reset> Buy failed: %s\n", error_msg or "unknown error"))
            f2t_hauling_stop()
            return
        end

        local cargo = gmcp.char.ship.cargo
        if not cargo or #cargo == 0 then
            cecho("\n<red>[hauling]<reset> Buy failed - no cargo loaded\n")
            f2t_hauling_stop()
            return
        end

        -- Cargo lot shape: {commodity, base, cost, origin}.
        local cargo_lot = cargo[1]   -- all lots are the same commodity
        if cargo_lot then
            F2T_HAULING_STATE.actual_cost = cargo_lot.cost or 0
            f2t_debug_log("[hauling] Cargo cost: %d ig/ton", F2T_HAULING_STATE.actual_cost)
        end

        local total_cost = lots_bought * F2T_HAULING_STATE.actual_cost * 75   -- 75 tons/lot
        F2T_HAULING_STATE.current_commodity_stats.lots_bought =
            F2T_HAULING_STATE.current_commodity_stats.lots_bought + lots_bought
        F2T_HAULING_STATE.current_commodity_stats.total_cost =
            F2T_HAULING_STATE.current_commodity_stats.total_cost + total_cost

        f2t_debug_log("[hauling] Tracking buy: %d lots at %d ig/ton = %d ig total cost",
            lots_bought, F2T_HAULING_STATE.actual_cost, total_cost)

        local bought_msg =
            "\n<green>[hauling]<reset> Bought %d lots of <cyan>%s<reset> at <yellow>%d ig/ton<reset> " ..
            "(cost: %d ig)\n"
        cecho(string.format(bought_msg, lots_bought, commodity, F2T_HAULING_STATE.actual_cost, total_cost))

        f2t_hauling_transition("navigating_to_sell")
    end)
end

-- Phase 4: navigate to sell location
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

    f2t_hauling_walk(destination,
        function() f2t_hauling_transition("selling") end,
        function(reason) pause_on_nav_failure(planet, reason) end)
end

-- Phase 5: sell commodity
function f2t_hauling_phase_sell()
    if not F2T_HAULING_STATE.current_commodity then
        cecho("\n<red>[hauling]<reset> No commodity selected\n")
        f2t_hauling_stop()
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Selling <cyan>%s<reset>...\n",
        F2T_HAULING_STATE.current_commodity))

    f2t_debug_log("[hauling] Selling commodity: %s", F2T_HAULING_STATE.current_commodity)

    f2t_bulk_sell_start(F2T_HAULING_STATE.current_commodity, nil, function(commodity, lots_sold, status, error_msg)
        f2t_debug_log("[hauling] Sell complete: commodity=%s, lots=%d, status=%s", commodity, lots_sold, status)

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if status == "error" then
            cecho(string.format("\n<red>[hauling]<reset> Sell failed: %s\n", error_msg or "unknown error"))
            f2t_hauling_stop()
            return
        end

        -- sell_location.price is what the exchange pays us (its buy price).
        local exchange_buy_price = F2T_HAULING_STATE.sell_location.price
        local total_revenue = lots_sold * exchange_buy_price * 75   -- lots * price/ton * 75 tons/lot
        F2T_HAULING_STATE.current_commodity_stats.lots_sold =
            F2T_HAULING_STATE.current_commodity_stats.lots_sold + lots_sold
        F2T_HAULING_STATE.current_commodity_stats.total_revenue =
            F2T_HAULING_STATE.current_commodity_stats.total_revenue + total_revenue

        f2t_debug_log("[hauling] Tracking sell: %d lots at %d ig/ton = %d ig total revenue",
            lots_sold, exchange_buy_price, total_revenue)

        -- Profit margin: (revenue - cost) / cost.
        local profit_per_ton = exchange_buy_price - F2T_HAULING_STATE.actual_cost
        local profit_margin_pct = (profit_per_ton / F2T_HAULING_STATE.actual_cost) * 100

        f2t_debug_log("[hauling] Profit margin: %.1f%% (%d - %d = %d profit per ton)",
            profit_margin_pct, exchange_buy_price, F2T_HAULING_STATE.actual_cost, profit_per_ton)

        local margin_too_low = profit_margin_pct < F2T_HAULING_STATE.margin_threshold_pct
        local selling_at_loss = exchange_buy_price <= F2T_HAULING_STATE.actual_cost

        if selling_at_loss or margin_too_low then
            if selling_at_loss then
                local loss_msg =
                    "\n<red>[hauling]<reset> Exchange buying at/below our cost for <cyan>%s<reset> " ..
                    "(%d <= %d ig/ton) - LOSS!\n"
                cecho(string.format(loss_msg, commodity, exchange_buy_price, F2T_HAULING_STATE.actual_cost))
            else
                cecho(string.format(
                    "\n<yellow>[hauling]<reset> Profit margin too low for <cyan>%s<reset> (%.1f%% < %.0f%%)\n",
                    commodity, profit_margin_pct, F2T_HAULING_STATE.margin_threshold_pct))
            end
            cecho("\n<yellow>[hauling]<reset> Abandoning commodity and dumping remaining cargo\n")

            -- Log the cycle with whatever sold before abandoning the rest.
            f2t_hauling_complete_commodity_cycle()

            f2t_hauling_remove_current_commodity()
            return
        end

        local sold_msg =
            "\n<green>[hauling]<reset> Sold %d lots of <cyan>%s<reset> at <yellow>%d ig/ton<reset> " ..
            "(realized margin: %.1f%%, revenue: %d ig)\n"
        cecho(string.format(sold_msg, lots_sold, commodity, exchange_buy_price, profit_margin_pct, total_revenue))

        local cargo = gmcp.char.ship.cargo
        if cargo and #cargo > 0 then
            f2t_debug_log("[hauling] Partial sell, %d lots remaining, finding next location", #cargo)

            f2t_hauling_find_next_sell_location()
        else
            F2T_HAULING_STATE.sell_attempts = 0

            f2t_hauling_complete_commodity_cycle()

            -- Refresh prices before starting the next cycle to confirm it's still profitable.
            f2t_debug_log("[hauling] Cycle complete, checking if still profitable")
            f2t_hauling_get_commodity_details(F2T_HAULING_STATE.current_commodity)
        end
    end)
end

-- Complete a commodity cycle (all cargo sold)
function f2t_hauling_complete_commodity_cycle()
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

    if f2t_is_rank_exactly("Merchant") and f2t_merchant_has_enough_points() then
        local points = f2t_merchant_get_points() or 0
        cecho(string.format(
            "\n<yellow>[hauling]<reset> <green>You have %d merchant points - ready to advance to Trader rank!<reset>\n",
            points))
        cecho("\n<dim_grey>Continue hauling or promote to Trader when ready<reset>\n")
    end

    f2t_debug_log("[hauling] Cycle stats - commodity: %s, cycles: %d, profit: %d ig",
        F2T_HAULING_STATE.current_commodity, F2T_HAULING_STATE.commodity_cycles, cycle_profit)

    F2T_HAULING_STATE.current_commodity_stats = {
        lots_bought = 0,
        total_cost = 0,
        lots_sold = 0,
        total_revenue = 0,
        profit = 0
    }
end

-- Find next sell location after partial sell
function f2t_hauling_find_next_sell_location()
    if not F2T_HAULING_STATE.current_commodity then
        f2t_hauling_stop()
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Finding next sell location for <cyan>%s<reset>...\n",
        F2T_HAULING_STATE.current_commodity))

    F2T_HAULING_STATE.sell_attempts = F2T_HAULING_STATE.sell_attempts + 1

    f2t_price_check_for("hauling", F2T_HAULING_STATE.current_commodity,
        function(_commodity_name, _parsed_data, analysis)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- top_buy = "exchanges buying" (where WE sell).
        if #analysis.top_buy >= F2T_HAULING_STATE.sell_attempts then
            local next_sell = analysis.top_buy[F2T_HAULING_STATE.sell_attempts]

            local profit_per_ton = next_sell.price - F2T_HAULING_STATE.actual_cost
            local profit_margin_pct = (profit_per_ton / F2T_HAULING_STATE.actual_cost) * 100

            f2t_debug_log("[hauling] Next sell location: %s: %s at %d ig/ton (margin: %.1f%%)",
                next_sell.system, next_sell.planet, next_sell.price, profit_margin_pct)

            if profit_margin_pct < F2T_HAULING_STATE.margin_threshold_pct then
                cecho(string.format(
                    "\n<yellow>[hauling]<reset> Best remaining location has insufficient margin (%.1f%% < %.0f%%)\n",
                    profit_margin_pct, F2T_HAULING_STATE.margin_threshold_pct))
                cecho("\n<yellow>[hauling]<reset> Abandoning commodity and dumping remaining cargo\n")

                f2t_hauling_complete_commodity_cycle()
                f2t_hauling_remove_current_commodity()
                return
            end

            F2T_HAULING_STATE.sell_location = {
                system = next_sell.system,
                planet = next_sell.planet,
                price = next_sell.price
            }

            f2t_hauling_transition("navigating_to_sell")
        else
            cecho("\n<red>[hauling]<reset> No more sell locations available\n")

            f2t_hauling_complete_commodity_cycle()
            f2t_hauling_remove_current_commodity()
        end
    end)
end

f2t_debug_log("[hauling] Phase implementations loaded")
