-- Buy/sell cycle phase implementations

-- Refusals are commodity/side/location scoped, not permanent map blacklists.
-- Retain them across repeat loads of this commodity so stale premium quotes
-- cannot send us back to a supplier/buyer which has already refused it.
local function market_state()
    local state = F2T_HAULING_STATE
    if not state.exchange_market or state.exchange_market.commodity ~= state.current_commodity then
        state.exchange_market = {commodity=state.current_commodity, buy={}, sell={}, rejected={buy={}, sell={}}}
    end
    return state.exchange_market
end

local function location_key(location)
    if type(location) ~= "table" or type(location.planet) ~= "string" or location.planet == "" then return nil end
    return (tostring(location.system or "") .. "\t" .. location.planet):lower()
end

local function reject_location(side, location)
    local key = location_key(location)
    if key then market_state().rejected[side][key] = true end
end

local function normalized_planet(value)
    return tostring(value or ""):match("^%s*(.-)%s*$"):lower()
end

local function cargo_origins()
    local origins = {}
    local cargo = gmcp and gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    for _, lot in ipairs(type(cargo) == "table" and cargo or {}) do
        if normalized_planet(lot.commodity) == normalized_planet(F2T_HAULING_STATE.current_commodity) then
            local origin = normalized_planet(lot.origin)
            if origin ~= "" then origins[origin] = true end
        end
    end
    return origins
end

local function available_locations(side, rows)
    local result, seen = {}, {}
    local rejected = market_state().rejected[side]
    local origins = side == "sell" and cargo_origins() or {}
    for _, row in ipairs(rows or {}) do
        local key = location_key(row)
        local price = key and tonumber(row.price)
        local is_origin = side == "sell" and origins[normalized_planet(row.planet)]
        local customs_blocked = type(f2t_hauling_customs_system_blocked) == "function"
            and f2t_hauling_customs_system_blocked(row.system)
        if key and price and price > 0 and price < math.huge and not seen[key]
            and not rejected[key] and not is_origin and not customs_blocked then
            seen[key] = true
            result[#result + 1] = {planet=row.planet, system=row.system, price=price}
        end
    end
    return result
end

local function remember_market(analysis, parsed)
    if type(analysis) ~= "table" or type(analysis.top_buy) ~= "table"
        or type(analysis.top_sell) ~= "table" then return nil end
    -- top_* is the UI's limited shortlist (20 rows for the premium provider),
    -- not the available market. Both native and premium callbacks also carry
    -- their complete, already policy-filtered parsed response. Retain that for
    -- routing without widening the displayed tables or issuing extra polls.
    local buyers, suppliers = analysis.top_buy, analysis.top_sell
    if type(parsed) == "table" and (parsed.buy ~= nil or parsed.sell ~= nil) then
        if type(parsed.buy) ~= "table" or type(parsed.sell) ~= "table" then return nil end
        buyers, suppliers = parsed.buy, parsed.sell
    end
    local market = market_state()
    market.buy = available_locations("buy", suppliers)
    market.sell = available_locations("sell", buyers)
    market.quoted = {buy=#suppliers, sell=#buyers}
    return {top_sell=market.buy, top_buy=market.sell, profit=analysis.profit}
end

-- Use the already reviewed alternatives first. Only an exhausted list needs a
-- fresh price request. Identity/token guards also reject late stopped-run replies.
function f2t_hauling_retry_exchange(side)
    local state, market = F2T_HAULING_STATE, market_state()
    if not state.active or state.paused then return end
    if side == "buy" and state.stopping then f2t_hauling_do_stop(); return end
    reject_location(side, state[side .. "_location"])
    state.current_phase = "finding_" .. side
    local token = {}
    market.pending = token
    local function current()
        return state == F2T_HAULING_STATE and state.active and not state.paused
            and state.exchange_market == market and market.pending == token
            and state.current_phase == "finding_" .. side
    end
    local function choose()
        local candidates = available_locations(side, market[side])
        local buyer = side == "buy" and available_locations("sell", market.sell)[1]
        for _, candidate in ipairs(candidates) do
            local cost = side == "buy" and candidate.price or nil
            local bid = side == "sell" and candidate.price or (buyer and buyer.price)
            local required = cost and cost * (1 + state.margin_threshold_pct / 100) or nil
            local eligible = (side == "sell" and bid and bid > 0)
                or (required and bid and bid > cost and bid >= required)
            if eligible then
                market.pending = nil
                state[side .. "_location"] = candidate
                if side == "buy" then state.sell_location = buyer end
                if side == "sell" then
                    state.sell_recovery = true
                    state.recovery_after_sequence = nil
                    state.recovery_expected_lots = nil
                end
                cecho(string.format("\n<yellow>[hauling]<reset> Trying next %s: <cyan>%s exchange<reset>\n",
                    side == "buy" and "supplier" or "buyer", candidate.planet))
                f2t_hauling_transition("navigating_to_" .. side)
                return true
            end
        end
        return false
    end
    if choose() then return end
    f2t_price_check_commodity(state.current_commodity, function(_commodity, parsed, analysis)
        if not current() then return end
        if side == "buy" and state.stopping then f2t_hauling_do_stop(); return end
        if not remember_market(analysis, parsed) then
            cecho("\n<red>[hauling]<reset> Could not refresh alternative exchanges; stopping with cargo preserved.\n")
            f2t_hauling_do_stop()
            return
        end
        if choose() then return end
        market.pending = nil
        if side == "buy" and #(gmcp.char.ship.cargo or {}) == 0 then
            cecho("\n<yellow>[hauling]<reset> No eligible supplier remains; moving to next commodity.\n")
            f2t_hauling_remove_current_commodity()
        else
            local remaining = available_locations("sell", market.sell)
            local best = remaining[1] and remaining[1].price
            cecho(string.format(
                "\n<yellow>[hauling]<reset> Buyer search for %s: %d quoted, %d untried after refusals; " ..
                "best remaining bid %s. Stopping with unsold cargo preserved.\n", state.current_commodity,
                market.quoted.sell, #remaining, best and (tostring(best) .. "ig/ton") or "none"))
            f2t_hauling_do_stop()
        end
    end)
end

-- Returns a set of lowercase, trimmed commodity names.
local function parse_excluded_commodities()
    local setting = f2t_settings_get("hauling", "excluded_commodities")
    local excluded = {}
    for commodity in string.gmatch(tostring(setting or ""), "[^,]+") do
        local trimmed = commodity:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            excluded[trimmed:lower()] = true
        end
    end
    local policy = F2T_HAULING_STATE and F2T_HAULING_STATE.session_policy
    for _, commodity in ipairs(type(policy) == "table"
        and type(policy.excluded_commodities) == "table" and policy.excluded_commodities or {}) do
        local trimmed = tostring(commodity):match("^%s*(.-)%s*$")
        if trimmed ~= "" then excluded[trimmed:lower()] = true end
    end

    return excluded
end

-- f2t_map_navigate() now self-heals an unmapped destination on its own
-- (auto-exploring and retrying); this is only the last-resort action for when
-- that ultimately fails too.
local function pause_on_nav_failure()
    cecho("\n<red>[hauling]<reset> Navigation could not be started, pausing hauling\n")
    cecho("<dim_grey>Resolve the issue above (e.g. explore/map the destination) and run 'haul resume'<reset>\n")
    f2t_hauling_pause(true)
end

local function begin_exchange_queue(tradeable, round, catalog_count, lazy_prices)
    if #tradeable == 0 then
        cecho("\n<red>[hauling]<reset> No eligible commodities found\n")
        f2t_hauling_stop()
        return
    end
    if not lazy_prices then
        table.sort(tradeable, function(a, b) return a.profit > b.profit end)
    end
    F2T_HAULING_STATE.commodity_queue = {}
    for index, comm in ipairs(tradeable) do
        table.insert(F2T_HAULING_STATE.commodity_queue, {
            commodity = comm.commodity,
            expected_profit = comm.profit
        })
        if comm.profit then
            f2t_debug_log("[hauling] Queued commodity %d: %s (profit: %d ig/ton)",
                index, comm.commodity, comm.profit)
        else
            f2t_debug_log("[hauling] Queued commodity %d: %s (live price pending)", index, comm.commodity)
        end
    end
    F2T_HAULING_STATE.queue_index = 1
    if lazy_prices then
        cecho(string.format("\n<green>[hauling]<reset> Premium rotation %d: queued %d of %d; " ..
            "each commodity will be price-scanned only when processed.\n", round, #tradeable, catalog_count))
    else
        cecho(string.format("\n<green>[hauling]<reset> Rotation %d: queued %d unattempted profitable commodities " ..
            "after reviewing all %d; one load each.\n", round, #tradeable, catalog_count))
    end
    f2t_hauling_next_commodity()
end

-- Phase 1: regular hauling reviews the complete catalog; premium hauling
-- queues its fixed saved rotation and defers the sole primary quote until use.
function f2t_hauling_phase_analyze()
    local state, request = F2T_HAULING_STATE, {}
    state.exchange_analysis_request = request
    if state.rotation == "top_base_21" then
        local tradeable, round, catalog_count =
            f2t_hauling_rotation_queue_catalog(parse_excluded_commodities())
        if not tradeable then
            cecho("\n<red>[hauling]<reset> " .. tostring(round) .. " No travel or purchase started.\n")
            f2t_hauling_do_stop()
            return
        end
        begin_exchange_queue(tradeable, round, catalog_count, true)
        return
    end
    f2t_debug_log("[hauling] Phase: Analyzing commodities")
    cecho("\n<green>[hauling]<reset> Analyzing commodity prices (this may take a minute)...\n")

    f2t_price_get_all_data(function(results)
        if state ~= F2T_HAULING_STATE or state.exchange_analysis_request ~= request
            or not state.active or state.paused then
            return
        end

        local excluded = parse_excluded_commodities()

        local tradeable, round, catalog_count = f2t_hauling_rotation_queue(results, excluded)
        if not tradeable then
            cecho("\n<red>[hauling]<reset> " .. tostring(round) .. " No travel or purchase started.\n")
            f2t_hauling_do_stop()
            return
        end

        begin_exchange_queue(tradeable, round, catalog_count, false)
    end)
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
                local current_location = gmcp.room and gmcp.room.info and gmcp.room.info.num
                if current_location then
                    F2T_HAULING_STATE.cycle_pause_return_location = current_location
                    local safe_room_msg =
                        "\n<green>[hauling]<reset> All commodities traded, going to safe room for " ..
                        "<yellow>%d seconds<reset>...\n"
                    cecho(string.format(safe_room_msg, cycle_pause))
                    f2t_debug_log(
                        "[hauling] Navigating to safe room for cycle pause (%d seconds), will return to room: %s",
                        cycle_pause, current_location)

                    f2t_map_navigate(safe_room)

                    -- After navigation completes, wait, then return.
                    tempTimer(3, function()
                        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                            and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                            if F2T_HAULING_STATE.pause_requested then
                                f2t_hauling_transition("analyzing")
                                return
                            end
                            local pausing_msg =
                                "\n<green>[hauling]<reset> Pausing at safe room for <yellow>%d seconds<reset>...\n"
                            cecho(string.format(pausing_msg, cycle_pause))
                            F2T_HAULING_STATE.cycle_pause_end_time = os.time() + cycle_pause
                            F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                                F2T_HAULING_STATE.cycle_pause_timer_id = nil
                                F2T_HAULING_STATE.cycle_pause_end_time = nil
                                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                                    and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                                    local return_to = F2T_HAULING_STATE.cycle_pause_return_location
                                    if return_to then
                                        if not F2T_HAULING_STATE.pause_requested then
                                            local returning_msg =
                                                "\n<green>[hauling]<reset> Returning to previous location: " ..
                                                "<cyan>%s<reset>\n"
                                            cecho(string.format(returning_msg, return_to))
                                        end
                                        f2t_debug_log("[hauling] Returning to room: %s", return_to)
                                        f2t_map_navigate(return_to)

                                        -- Wait for return navigation, then re-analyze.
                                        tempTimer(3, function()
                                            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                                                and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                                                if not F2T_HAULING_STATE.pause_requested then
                                                    local msg = "\n<green>[hauling]<reset> " ..
                                                        "Pause complete, refreshing market data...\n"
                                                    cecho(msg)
                                                end
                                                f2t_hauling_transition("analyzing")
                                            end
                                        end)
                                    else
                                        if not F2T_HAULING_STATE.pause_requested then
                                            cecho(
                                                "\n<green>[hauling]<reset> Pause complete, refreshing market data...\n")
                                        end
                                        f2t_hauling_transition("analyzing")
                                    end
                                    F2T_HAULING_STATE.cycle_pause_return_location = nil
                                end
                            end)
                        end
                    end)
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
    local saved, reason = f2t_hauling_rotation_claim(commodity_data.commodity)
    if not saved then
        cecho("\n<red>[hauling]<reset> " .. tostring(reason) .. " No travel or purchase started.\n")
        f2t_hauling_do_stop()
        return
    end
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
    F2T_HAULING_STATE.exchange_market = nil

    if commodity_data.expected_profit then
        f2t_debug_log("[hauling] Starting commodity %d/%d: %s (expected profit: %d ig/ton)",
            F2T_HAULING_STATE.queue_index, #F2T_HAULING_STATE.commodity_queue,
            commodity_data.commodity, commodity_data.expected_profit)
        cecho(string.format(
            "\n<green>[hauling]<reset> Trading <cyan>%s<reset> (expected profit: <green>%d ig/ton<reset>)\n",
            commodity_data.commodity, commodity_data.expected_profit))
    else
        f2t_debug_log("[hauling] Starting commodity %d/%d: %s (requesting one live quote)",
            F2T_HAULING_STATE.queue_index, #F2T_HAULING_STATE.commodity_queue, commodity_data.commodity)
        cecho(string.format(
            "\n<green>[hauling]<reset> Trading <cyan>%s<reset>; requesting its live market now.\n",
            commodity_data.commodity))
    end

    f2t_hauling_get_commodity_details(commodity_data.commodity)
end

-- Get detailed price data for selected commodity
function f2t_hauling_get_commodity_details(commodity)
    f2t_debug_log("[hauling] Getting details for: %s", commodity)
    local market = market_state()

    f2t_price_check_commodity(commodity, function(commodity_name, parsed, analysis)
        f2t_debug_log("[hauling] Received commodity details callback for: %s", commodity_name)
        f2t_debug_log("[hauling] State - active: %s, paused: %s",
            tostring(F2T_HAULING_STATE.active), tostring(F2T_HAULING_STATE.paused))

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused
            or F2T_HAULING_STATE.exchange_market ~= market then
            f2t_debug_log("[hauling] Callback aborted - hauling not active or paused")
            return
        end

        if F2T_HAULING_STATE.stopping then
            f2t_debug_log("[hauling] Graceful stop complete, sold all cargo")
            cecho("\n<green>[hauling]<reset> Cargo sold, stopping now...\n")
            f2t_hauling_do_stop()
            return
        end

        analysis = remember_market(analysis, parsed)
        if not analysis then
            cecho("\n<red>[hauling]<reset> Commodity prices unavailable; stopping.\n")
            f2t_hauling_do_stop()
            return
        end
        -- Do not reuse a previous commodity's location if one side is empty.
        F2T_HAULING_STATE.buy_location = nil
        F2T_HAULING_STATE.sell_location = nil
        if #analysis.top_buy == 0 or #analysis.top_sell == 0 then
            f2t_hauling_remove_current_commodity()
            return
        end
        f2t_debug_log("[hauling] Analysis - top_buy count: %d, top_sell count: %d, profit: %d",
            #analysis.top_buy, #analysis.top_sell, analysis.profit or 0)

        -- Each rotation buys only one load, so validate even its first purchase.
        -- A planet cannot buy bonded cargo that originated on that planet.
        do
            local best_buy = analysis.top_sell[1]
            local best_buyer
            for _, candidate in ipairs(analysis.top_buy) do
                if normalized_planet(candidate.planet) ~= normalized_planet(best_buy.planet) then
                    best_buyer = candidate
                    break
                end
            end
            local best_sell_price = best_buyer and best_buyer.price or 0
            local best_buy_price = best_buy and best_buy.price or 0

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
            for _, best_sell in ipairs(analysis.top_buy) do
                if normalized_planet(best_sell.planet) ~= normalized_planet(F2T_HAULING_STATE.buy_location.planet) then
                    F2T_HAULING_STATE.sell_location = {
                        system = best_sell.system,
                        planet = best_sell.planet,
                        price = best_sell.price
                    }
                    f2t_debug_log("[hauling] Sell location: %s: %s at %d ig/ton",
                        best_sell.system, best_sell.planet, best_sell.price)
                    break
                end
            end
        end
        if not F2T_HAULING_STATE.sell_location then
            cecho("\n<yellow>[hauling]<reset> No off-world buyer is available for bonded cargo; " ..
                "moving to the next commodity.\n")
            f2t_hauling_remove_current_commodity()
            return
        end

        f2t_hauling_transition("navigating_to_buy")
    end)
end

-- Never abandon or dump owned cargo to advance the rotation. Once it is
-- aboard, exhaust positive off-world bids without imposing a profit floor.
function f2t_hauling_remove_current_commodity()
    local cargo = gmcp.char.ship.cargo
    if cargo and #cargo > 0 then f2t_hauling_find_next_sell_location(); return end
    f2t_hauling_finish_remove_commodity()
end

-- Preserve old phase entry points without retaining an unguarded sale bypass.
function f2t_hauling_phase_dump_cargo()
    f2t_hauling_phase_recovery_sell()
end

function f2t_hauling_find_next_dump_location()
    f2t_hauling_find_next_sell_location()
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

    local nav_result = f2t_map_navigate(destination, {
        on_result = function(success)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            if not success then pause_on_nav_failure() end
            -- success: a real speedwalk is now in flight; f2t_hauling_check_nav_to_buy_complete
            -- (wired to gmcp.room.info) picks up its completion normally.
        end,
    })

    -- false doesn't mean failure: it auto-retries via "look"; the GMCP handler confirms completion.
    if f2t_map_navigate_ok(nav_result) and not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling] Already at buy location, waiting for GMCP update")
        tempTimer(0.5, function()
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            f2t_debug_log("[hauling] GMCP ready, proceeding to buy")
            f2t_hauling_transition("buying")
        end)
    end
end

-- Text receipts and ship GMCP are independent arrivals. Once all receipts have
-- arrived, keep the haul parked until the matching cargo count/costs are visible.
function f2t_hauling_purchase_cleanup()
    local pending = F2T_HAULING_STATE.purchase_settlement
    if pending and pending.timer then killTimer(pending.timer) end
    F2T_HAULING_STATE.purchase_settlement = nil
end

function f2t_hauling_purchase_observe()
    local state = F2T_HAULING_STATE
    local pending = state.purchase_settlement
    if not pending or not state.active or state.exchange_market ~= pending.market
        or state.current_commodity ~= pending.commodity or state.current_phase ~= "waiting_buy_cargo" then return end
    local cargo = gmcp and gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if type(cargo) ~= "table" or #cargo ~= pending.lots or not f2t_hauling_cargo_cost() then return end
    f2t_hauling_purchase_cleanup()
    pending.complete()
end

local function wait_for_purchase_cargo(lots, complete)
    local state = F2T_HAULING_STATE
    f2t_hauling_purchase_cleanup()
    local pending = {lots=lots, complete=complete, market=state.exchange_market, commodity=state.current_commodity}
    state.purchase_settlement = pending
    state.current_phase = "waiting_buy_cargo"
    pending.timer = tempTimer(5, function()
        if state ~= F2T_HAULING_STATE or not state.active or state.purchase_settlement ~= pending
            or state.exchange_market ~= pending.market then return end
        f2t_hauling_purchase_cleanup()
        cecho("\n<red>[hauling]<reset> Purchase receipts arrived but cargo GMCP did not reconcile within 5 seconds; " ..
            "stopping with cargo preserved and no automatic retry.\n")
        f2t_hauling_do_stop()
    end)
    f2t_hauling_purchase_observe()
end

-- Phase 3: buy commodity
function f2t_hauling_phase_buy()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then return end
    if F2T_HAULING_STATE.purchase_settlement then
        -- A repeated arrival/resume transition must not erase the pending phase.
        F2T_HAULING_STATE.current_phase = "waiting_buy_cargo"
        f2t_hauling_purchase_observe()
        return
    end
    -- Immediate pause/resume during a counted response must not resend it.
    if F2T_BULK_STATE and F2T_BULK_STATE.active then return end
    if not F2T_HAULING_STATE.current_commodity then
        cecho("\n<red>[hauling]<reset> No commodity selected\n")
        f2t_hauling_stop()
        return
    end

    local existing_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if existing_cargo and #existing_cargo > 0 then
        cecho("\n<red>[hauling]<reset> Unexpected cargo before purchase; stopping with cargo preserved.\n")
        f2t_hauling_do_stop()
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Buying <cyan>%s<reset> to fill hold...\n",
        F2T_HAULING_STATE.current_commodity))

    f2t_debug_log("[hauling] Buying commodity: %s", F2T_HAULING_STATE.current_commodity)

    local state = F2T_HAULING_STATE
    local market = state.exchange_market
    f2t_bulk_buy_start(state.current_commodity, nil, function(commodity, lots_bought, status, error_msg, code, receipt)
        f2t_debug_log("[hauling] Buy complete: commodity=%s, lots=%d, status=%s", commodity, lots_bought, status)

        if state ~= F2T_HAULING_STATE or not state.active or state.exchange_market ~= market then
            return
        end

        if status == "error" then
            cecho(string.format("\n<red>[hauling]<reset> Buy failed: %s\n", error_msg or "unknown error"))
            f2t_hauling_do_stop()
            return
        end

        local cargo = gmcp and gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
        if code == "not_selling" then
            reject_location("buy", F2T_HAULING_STATE.buy_location)
            if lots_bought == 0 and cargo and #cargo == 0 then
                if state.paused then state.current_phase = "finding_buy"
                else f2t_hauling_retry_exchange("buy") end
                return
            end
            -- A partially filled counted buy is still cargo to deliver, not
            -- permission to buy another hold from a different supplier.
        end
        if lots_bought == 0 then
            cecho("\n<red>[hauling]<reset> Buy failed - no cargo loaded\n")
            f2t_hauling_stop()
            return
        end

        -- Sum actual server purchase receipts, never extrapolate from the first
        -- bay or a remote quote when subsequent bays may cost more.
        local total_cost = receipt and tonumber(receipt.cost)
        if lots_bought < 1 or not total_cost or total_cost ~= total_cost or total_cost < 0
            or total_cost == math.huge or receipt.count ~= lots_bought then
            cecho("\n<red>[hauling]<reset> Purchase receipts did not reconcile; stopping without retry.\n")
            f2t_hauling_do_stop()
            return
        end
        wait_for_purchase_cargo(lots_bought, function()
            F2T_HAULING_STATE.actual_cost = total_cost / (lots_bought * 75)
            F2T_HAULING_STATE.current_commodity_stats.lots_bought =
                F2T_HAULING_STATE.current_commodity_stats.lots_bought + lots_bought
            F2T_HAULING_STATE.current_commodity_stats.total_cost =
                F2T_HAULING_STATE.current_commodity_stats.total_cost + total_cost

            f2t_debug_log("[hauling] Tracking buy: %d lots averaging %.2f ig/ton = %d ig confirmed cost",
                lots_bought, F2T_HAULING_STATE.actual_cost, total_cost)

            local bought_msg =
                "\n<green>[hauling]<reset> Bought %d lots of <cyan>%s<reset> averaging <yellow>%.2f ig/ton<reset> " ..
                "(cost: %d ig)\n"
            cecho(string.format(bought_msg, lots_bought, commodity, F2T_HAULING_STATE.actual_cost, total_cost))

            local next_phase = state.rotation == "top_base_21" and "selecting_sell" or "navigating_to_sell"
            if state.paused then state.current_phase = next_phase
            else f2t_hauling_transition(next_phase) end
        end)
    end)
end

-- Premium hauling deliberately refreshes once after the counted bulk purchase.
-- The supplier quote chose where to buy; this quote chooses the best positive
-- off-world bid. Once cargo is aboard, clearing it takes priority over profit.
-- Refusal recovery still exhausts retained buyers before one exceptional refresh.
function f2t_hauling_select_sell_destination()
    local state = F2T_HAULING_STATE
    if not state.active or state.paused then return end
    local market = state.exchange_market
    local commodity = state.current_commodity
    local request = {}
    state.sell_analysis_request = request
    state.sell_location = nil
    cecho(string.format(
        "\n<green>[hauling]<reset> Refreshing off-world buyers for <cyan>%s<reset> after confirmed purchase...\n",
        commodity))

    f2t_price_check_commodity(commodity, function(_, parsed, analysis)
        if state ~= F2T_HAULING_STATE or not state.active or state.paused
            or state.exchange_market ~= market or state.sell_analysis_request ~= request
            or state.current_phase ~= "selecting_sell" then return end
        state.sell_analysis_request = nil
        analysis = remember_market(analysis, parsed)
        if not analysis then
            cecho("\n<red>[hauling]<reset> Post-purchase buyer scan was invalid; " ..
                "stopping with cargo preserved.\n")
            f2t_hauling_do_stop()
            return
        end

        local candidates = available_locations("sell", market.sell)
        local candidate = candidates[1]
        if candidate then
            state.sell_location = candidate
            cecho(string.format(
                "\n<green>[hauling]<reset> Fresh off-world buyer selected: <cyan>%s exchange<reset> " ..
                "at <yellow>%sig/ton<reset>.\n",
                candidate.planet, candidate.price))
            f2t_hauling_transition("navigating_to_sell")
            return
        end

        cecho(string.format(
            "\n<yellow>[hauling]<reset> Post-purchase buyer scan found no positive off-world bid " ..
            "among %d quoted buyer%s. Stopping with cargo preserved.\n",
            market.quoted.sell or 0, market.quoted.sell == 1 and "" or "s"))
        f2t_hauling_do_stop()
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

    local nav_result = f2t_map_navigate(destination, {
        on_result = function(success)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            if not success then pause_on_nav_failure() end
            -- success: a real speedwalk is now in flight; f2t_hauling_check_nav_to_sell_complete
            -- (wired to gmcp.room.info) picks up its completion normally.
        end,
    })

    -- false doesn't mean failure: it auto-retries via "look"; the GMCP handler confirms completion.
    if f2t_map_navigate_ok(nav_result) and not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling] Already at sell location, waiting for GMCP update")
        tempTimer(0.5, function()
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            f2t_debug_log("[hauling] GMCP ready, proceeding to sell")
            f2t_hauling_transition("selling")
        end)
    end
end

-- Every exchange sale, including the initial buyer, requires a current-room
-- quote covering the remaining cargo cost. The guarded path records receipts
-- and advances the rotation after this single load is cleared.
function f2t_hauling_phase_sell()
    f2t_hauling_phase_recovery_sell()
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

-- Exchange event handlers

function f2t_hauling_check_nav_to_buy_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "navigating_to_buy" then
        return
    end

    if not F2T_SPEEDWALK_ACTIVE and not F2T_SPEEDWALK_CUSTOMS_PENDING then
        -- Capture immediately to avoid a race with the next speedwalk.
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling] Speedwalk stopped with result: %s", result or "unknown")

        -- Exchange handlers act on the result immediately (no tempTimer, unlike AC
        -- handlers) since they only transition phase; buying/selling verify location themselves.

        if result == "completed" then
            f2t_debug_log("[hauling] Navigation to buy location complete")
            f2t_hauling_transition("buying")

        elseif result == "stopped" then
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_debug_log("[hauling] User stopped navigation, stopping hauling")
            f2t_hauling_stop()

        elseif result == "failed" then
            -- Exchange mode stops on a blocked path (the chosen commodity/location was
            -- the best option); AC mode instead fetches a new job since many exist.
            local buy_loc = F2T_HAULING_STATE.buy_location
            local location_str = buy_loc and string.format("%s:%s", buy_loc.system, buy_loc.planet) or "buy location"
            cecho(string.format(
                "\n<red>[hauling]<reset> Cannot reach %s (path blocked), stopping hauling\n", location_str))
            f2t_debug_log("[hauling] Navigation to buy failed after retries, stopping")
            f2t_hauling_stop()

        else
            f2t_debug_log("[hauling] Unknown speedwalk result, using legacy behavior")
            f2t_hauling_transition("buying")
        end
    end
end

function f2t_hauling_check_nav_to_sell_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "navigating_to_sell" then
        return
    end

    if not F2T_SPEEDWALK_ACTIVE and not F2T_SPEEDWALK_CUSTOMS_PENDING then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling] Speedwalk stopped with result: %s", result or "unknown")

        -- (See the buy handler above for why Exchange navigation works this way.)

        if result == "completed" then
            f2t_debug_log("[hauling] Navigation to sell location complete")
            f2t_hauling_transition("selling")

        elseif result == "stopped" then
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_debug_log("[hauling] User stopped navigation, stopping hauling")
            f2t_hauling_stop()

        elseif result == "failed" then
            local sell_loc = F2T_HAULING_STATE.sell_location
            local location_str = sell_loc and string.format("%s:%s", sell_loc.system, sell_loc.planet)
                or "sell location"
            cecho(string.format(
                "\n<red>[hauling]<reset> Cannot reach %s (path blocked), stopping hauling\n", location_str))
            f2t_debug_log("[hauling] Navigation to sell failed after retries, stopping")
            f2t_hauling_stop()

        else
            f2t_debug_log("[hauling] Unknown speedwalk result, using legacy behavior")
            f2t_hauling_transition("selling")
        end
    end
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

    f2t_hauling_retry_exchange("sell")
end

function f2t_hauling_check_nav_to_dump_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    if F2T_HAULING_STATE.current_phase ~= "dumping_cargo" then
        return
    end

    if not F2T_SPEEDWALK_ACTIVE and not F2T_SPEEDWALK_CUSTOMS_PENDING then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling] Speedwalk stopped with result: %s", result or "unknown")

        -- (See the buy handler above for why Exchange navigation works this way.)

        if result == "completed" then
            f2t_debug_log("[hauling] Navigation to dump location complete")
            f2t_hauling_phase_dump_cargo()

        elseif result == "stopped" then
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_debug_log("[hauling] User stopped navigation, stopping hauling")
            f2t_hauling_stop()

        elseif result == "failed" then
            cecho("\n<red>[hauling]<reset> Cannot reach dump location (path blocked), stopping hauling\n")
            f2t_debug_log("[hauling] Navigation to dump failed after retries, stopping")
            f2t_hauling_stop()

        else
            f2t_debug_log("[hauling] Unknown speedwalk result, using legacy behavior")
            f2t_hauling_phase_dump_cargo()
        end
    end
end

--- @return string Event handler ID
function f2t_exchange_register_handlers()
    f2t_hauling_purchase_cleanup()
    f2t_hauling_recovery_cleanup()
    local handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        f2t_hauling_recovery_observe("room")
        -- Brief delay lets GMCP settle before checking navigation completion.
        tempTimer(0.5, function()
            f2t_hauling_check_nav_to_buy_complete()
            f2t_hauling_check_nav_to_sell_complete()
            f2t_hauling_check_nav_to_dump_complete()
        end)
    end)
    F2T_HAULING_STATE.recovery_handlers = {
        registerAnonymousEventHandler("gmcp.exchange.commodities", function() f2t_hauling_recovery_observe("full") end),
        registerAnonymousEventHandler("gmcp.exchange.commodity", function() f2t_hauling_recovery_observe("tick") end),
        registerAnonymousEventHandler("gmcp.char.ship", function()
            f2t_hauling_purchase_observe()
            f2t_hauling_recovery_observe("cargo")
        end),
    }

    f2t_debug_log("[hauling/exchange] Registered Exchange event handlers")
    return handler_id
end

--- @param handler_id string Event handler ID to kill
function f2t_exchange_cleanup_handlers(handler_id)
    f2t_hauling_purchase_cleanup()
    f2t_hauling_recovery_cleanup()
    for _, id in ipairs(F2T_HAULING_STATE.recovery_handlers or {}) do killAnonymousEventHandler(id) end
    F2T_HAULING_STATE.recovery_handlers = nil
    if handler_id then
        killAnonymousEventHandler(handler_id)
        f2t_debug_log("[hauling/exchange] Cleaned up Exchange event handlers")
    end
end

f2t_debug_log("[hauling] Phase implementations loaded")
