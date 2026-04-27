-- Planet Owner Phase Implementations
-- Phase functions and event handlers for PO hauling mode

-- ========================================
-- Cycle Pause Helper
-- ========================================

--- Pause between cycles, optionally navigating to safe room first
--- Since PO scanning is fully remote, no need to return from safe room
--- @param message string Message to show before pausing
local function po_cycle_pause_and_rescan(message)
    local cycle_pause = tonumber(f2t_settings_get("hauling", "cycle_pause")) or 60
    local use_safe_room = f2t_settings_get("hauling", "use_safe_room")
    local safe_room = f2t_settings_get("shared", "safe_room")

    -- Kill any stale cycle pause timer from a previous cycle or session
    if F2T_HAULING_STATE.cycle_pause_timer_id then
        killTimer(F2T_HAULING_STATE.cycle_pause_timer_id)
        F2T_HAULING_STATE.cycle_pause_timer_id = nil
    end

    if cycle_pause > 0 then
        F2T_HAULING_STATE.current_phase = "cycle_pausing"
        F2T_HAULING_STATE.cycle_pause_end_time = os.time() + cycle_pause

        if use_safe_room and safe_room and safe_room ~= "" then
            cecho(string.format("\n<green>[hauling]<reset> %s, going to safe room for <yellow>%d seconds<reset>...\n",
                message, cycle_pause))
            f2t_debug_log("[hauling/po] Navigating to safe room for cycle pause (%d seconds)", cycle_pause)
            f2t_map_navigate(safe_room)

            -- Navigation will complete well within the cycle pause window
            F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                F2T_HAULING_STATE.cycle_pause_timer_id = nil
                F2T_HAULING_STATE.cycle_pause_end_time = nil
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                    and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                    if not F2T_HAULING_STATE.pause_requested then
                        cecho("\n<green>[hauling]<reset> Pause complete, re-scanning...\n")
                    end
                    f2t_hauling_transition("po_scanning_system")
                end
            end)
        else
            cecho(string.format("\n<green>[hauling]<reset> %s, pausing for <yellow>%d seconds<reset> before re-scanning...\n",
                message, cycle_pause))
            F2T_HAULING_STATE.cycle_pause_timer_id = tempTimer(cycle_pause, function()
                F2T_HAULING_STATE.cycle_pause_timer_id = nil
                F2T_HAULING_STATE.cycle_pause_end_time = nil
                if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
                    and F2T_HAULING_STATE.current_phase == "cycle_pausing" then
                    f2t_hauling_transition("po_scanning_system")
                end
            end)
        end
    else
        f2t_hauling_transition("po_scanning_system")
    end
end

-- ========================================
-- Phase: Scan System
-- ========================================

--- Start system scan to discover planet names
function f2t_hauling_phase_po_scan_system()
    f2t_debug_log("[hauling/po] Phase: po_scanning_system")

    f2t_po_hauling_scan_system(function(planet_names, planets_without_exchange)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if not planet_names or #planet_names == 0 then
            cecho("\n<red>[hauling]<reset> No planets with exchanges found in system\n")
            f2t_hauling_do_stop()
            return
        end

        -- Store for exchange scanning phase
        F2T_HAULING_STATE.po_scan_planets = planet_names

        f2t_hauling_transition("po_scanning_exchanges")
    end)
end

-- ========================================
-- Phase: Scan Exchanges
-- ========================================

--- Capture exchange data remotely for all planets (no navigation needed)
function f2t_hauling_phase_po_scan_exchanges()
    f2t_debug_log("[hauling/po] Phase: po_scanning_exchanges")

    local planet_names = F2T_HAULING_STATE.po_scan_planets

    f2t_po_hauling_scan_exchanges(planet_names, function(owned_planets, planet_exchange_data)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if #owned_planets == 0 then
            cecho("\n<red>[hauling]<reset> No owned planets found in this system\n")
            f2t_hauling_do_stop()
            return
        end

        cecho(string.format("\n<green>[hauling]<reset> Found <cyan>%d<reset> owned planet(s): %s\n",
            #owned_planets, table.concat(owned_planets, ", ")))

        F2T_HAULING_STATE.po_scan_count = F2T_HAULING_STATE.po_scan_count + 1
        f2t_hauling_transition("po_building_queue")
    end)
end

-- ========================================
-- Phase: Build Queue
-- ========================================

--- Build job queue from exchange data
function f2t_hauling_phase_po_build_queue()
    f2t_debug_log("[hauling/po] Phase: po_building_queue")

    local planet_exchange_data = F2T_HAULING_STATE.po_planet_exchange_data
    local owned_planets = F2T_HAULING_STATE.po_owned_planets

    f2t_po_hauling_build_queue(planet_exchange_data, owned_planets, function(job_queue)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if #job_queue == 0 then
            cecho("\n<yellow>[hauling]<reset> No deficits or excesses found, nothing to do\n")
            po_cycle_pause_and_rescan("Nothing to do")
            return
        end

        F2T_HAULING_STATE.po_job_queue = job_queue
        F2T_HAULING_STATE.po_job_index = 1

        -- Count deficits and excesses in queue
        local deficit_count = 0
        local excess_count = 0
        for _, job in ipairs(job_queue) do
            if job.type == "deficit" then
                deficit_count = deficit_count + 1
            else
                excess_count = excess_count + 1
            end
        end

        cecho(string.format("\n<green>[hauling]<reset> Queue built: <cyan>%d<reset> jobs (%d deficit, %d excess)\n",
            #job_queue, deficit_count, excess_count))

        -- Start with first job
        f2t_hauling_phase_po_next_job()
    end)
end

-- ========================================
-- Phase: Next Job
-- ========================================

--- Advance to next job in queue or cycle back to scanning
function f2t_hauling_phase_po_next_job()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    -- Deferred pause: pause between PO jobs
    if F2T_HAULING_STATE.pause_requested then
        F2T_HAULING_STATE.pause_requested = false
        F2T_HAULING_STATE.paused = true
        F2T_HAULING_STATE.current_phase = "po_next_job"
        cecho("\n<green>[hauling]<reset> Paused between jobs\n")
        f2t_debug_log("[hauling/po] Deferred pause activated between jobs")
        return
    end

    -- Check graceful stop
    if F2T_HAULING_STATE.stopping then
        f2t_debug_log("[hauling/po] Graceful stop complete")
        cecho("\n<green>[hauling]<reset> Stopping now...\n")
        f2t_hauling_do_stop()
        return
    end

    local queue = F2T_HAULING_STATE.po_job_queue
    local index = F2T_HAULING_STATE.po_job_index

    if not queue or index > #queue then
        -- Queue exhausted, cycle pause then re-scan
        f2t_debug_log("[hauling/po] Job queue exhausted, cycling")
        cecho("\n<green>[hauling]<reset> All jobs complete\n")
        po_cycle_pause_and_rescan("All jobs complete")
        return
    end

    local job = queue[index]
    F2T_HAULING_STATE.po_current_job = job
    F2T_HAULING_STATE.po_sell_attempts = 0

    f2t_debug_log("[hauling/po] Starting job %d/%d: %s %s (%s → %s)",
        index, #queue, job.type, job.commodity,
        job.buy_planet or "?", job.sell_planet or "?")

    local type_color = job.type == "deficit" and "orange" or "yellow"
    cecho(string.format("\n<green>[hauling]<reset> Job %d/%d: <%s>%s<reset> <cyan>%s<reset> (%s → %s)\n",
        index, #queue, type_color, job.type, job.commodity,
        job.buy_planet or "?", job.sell_planet or "?"))

    if job.bundled_commodity then
        cecho(string.format("  <dim_grey>Bundled: <cyan>%s<reset> (%s → %s)<reset>\n",
            job.bundled_commodity,
            job.bundled_buy_planet or "?", job.bundled_sell_planet or "?"))
    end

    f2t_hauling_transition("po_navigating_to_buy")
end

-- ========================================
-- Phase: Navigate to Buy
-- ========================================

--- Navigate to the buy location for current job
function f2t_hauling_phase_po_navigate_to_buy()
    local job = F2T_HAULING_STATE.po_current_job
    if not job then
        cecho("\n<red>[hauling]<reset> No current job\n")
        f2t_hauling_do_stop()
        return
    end

    local destination = string.format("%s exchange", job.buy_planet)
    cecho(string.format("\n<green>[hauling]<reset> Navigating to buy location: <cyan>%s exchange<reset>\n",
        job.buy_planet))
    f2t_debug_log("[hauling/po] Navigating to buy: %s", destination)

    local nav_result = f2t_map_navigate(destination)

    if nav_result == false then
        cecho(string.format("\n<red>[hauling]<reset> Cannot navigate to %s exchange, skipping job\n", job.buy_planet))
        f2t_debug_log("[hauling/po] Navigation to buy location failed, skipping job")
        F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
        f2t_hauling_phase_po_next_job()
    elseif nav_result == true and not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling/po] Already at buy location")
        f2t_hauling_transition("po_buying")
    end
end

-- ========================================
-- Phase: Buy
-- ========================================

--- Buy commodity at current location
function f2t_hauling_phase_po_buy()
    local job = F2T_HAULING_STATE.po_current_job
    if not job then
        cecho("\n<red>[hauling]<reset> No current job\n")
        f2t_hauling_do_stop()
        return
    end

    -- Check if cargo hold has leftover cargo from a previous partial sell
    local existing_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if existing_cargo and #existing_cargo > 0 then
        F2T_HAULING_STATE.cargo_clear_attempts = (F2T_HAULING_STATE.cargo_clear_attempts or 0) + 1
        if F2T_HAULING_STATE.cargo_clear_attempts > 2 then
            cecho(string.format("\n<red>[hauling]<reset> Failed to clear cargo after %d attempts, stopping\n",
                F2T_HAULING_STATE.cargo_clear_attempts - 1))
            f2t_debug_log("[hauling/po] Cargo clear attempts exhausted (%d), stopping", F2T_HAULING_STATE.cargo_clear_attempts - 1)
            f2t_hauling_do_stop()
            return
        end
        cecho(string.format("\n<yellow>[hauling]<reset> Cargo hold not empty (%d lots remaining), selling before buying\n",
            #existing_cargo))
        f2t_debug_log("[hauling/po] Cargo hold has %d lots, selling before buying (attempt %d)", #existing_cargo, F2T_HAULING_STATE.cargo_clear_attempts)
        -- Sell leftover cargo first, then retry this buy
        f2t_bulk_sell_start(nil, nil, function(commodity_sold, lots_sold, status, error_msg)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            -- Check again after selling
            local still_has_cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
            if still_has_cargo and #still_has_cargo > 0 then
                cecho(string.format("\n<yellow>[hauling]<reset> Still %d lots unsold, jettisoning to clear hold\n", #still_has_cargo))
                f2t_debug_log("[hauling/po] Jettisoning %d unsellable lots", #still_has_cargo)
                f2t_hauling_jettison_cargo(function()
                    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                        return
                    end
                    -- Retry buy (counter already incremented)
                    f2t_hauling_transition("po_buying")
                end)
                return
            end
            -- Cargo clear, reset counter and proceed
            F2T_HAULING_STATE.cargo_clear_attempts = 0
            f2t_hauling_transition("po_buying")
        end)
        return
    end

    local commodity = job.commodity
    local lots = job.lots

    cecho(string.format("\n<green>[hauling]<reset> Buying %d lots of <cyan>%s<reset>...\n", lots, commodity))
    f2t_debug_log("[hauling/po] Buying %d lots of %s", lots, commodity)

    f2t_bulk_buy_start(commodity, lots, function(bought_commodity, lots_bought, status, error_msg)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        f2t_debug_log("[hauling/po] Buy complete: %s, lots=%d, status=%s",
            bought_commodity, lots_bought, status)

        if status == "error" or lots_bought == 0 then
            cecho(string.format("\n<red>[hauling]<reset> Buy failed for %s: %s\n",
                commodity, error_msg or "unknown error"))
            -- Skip this job, move to next
            F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
            f2t_hauling_phase_po_next_job()
            return
        end

        cecho(string.format("\n<green>[hauling]<reset> Bought %d lots of <cyan>%s<reset>\n",
            lots_bought, commodity))

        -- Check if bundled with second commodity from same source
        if job.bundled_commodity and job.bundled_buy_planet == job.buy_planet then
            -- Same source, buy second commodity here
            local bundled_lots = job.bundled_lots or lots
            f2t_debug_log("[hauling/po] Bundled buy: same source, buying %s (%d lots)", job.bundled_commodity, bundled_lots)
            cecho(string.format("\n<green>[hauling]<reset> Buying bundled %d lots of <cyan>%s<reset>...\n",
                bundled_lots, job.bundled_commodity))

            f2t_bulk_buy_start(job.bundled_commodity, bundled_lots, function(b_commodity, b_lots, b_status, b_error)
                if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                    return
                end

                if b_status == "error" or b_lots == 0 then
                    cecho(string.format("\n<yellow>[hauling]<reset> Bundled buy failed for %s, continuing with primary\n",
                        job.bundled_commodity))
                else
                    cecho(string.format("\n<green>[hauling]<reset> Bought %d lots of <cyan>%s<reset>\n",
                        b_lots, job.bundled_commodity))
                end

                f2t_hauling_transition("po_navigating_to_sell")
            end)
        elseif job.bundled_commodity and job.bundled_buy_planet ~= job.buy_planet then
            -- Different source, navigate to second source
            f2t_debug_log("[hauling/po] Bundled buy: different source, navigating to %s",
                job.bundled_buy_planet)
            f2t_hauling_transition("po_navigating_to_bundled_buy")
        else
            -- No bundle, go to sell
            f2t_hauling_transition("po_navigating_to_sell")
        end
    end)
end

--- Navigate to the second (bundled) commodity's source
--- Separate function so the transition dispatcher can call it on resume
function f2t_hauling_phase_po_bundled_buy_navigate()
    local job = F2T_HAULING_STATE.po_current_job
    if not job or not job.bundled_commodity then
        f2t_hauling_transition("po_navigating_to_sell")
        return
    end

    local dest = string.format("%s exchange", job.bundled_buy_planet)
    cecho(string.format("\n<green>[hauling]<reset> Navigating to bundled buy: <cyan>%s exchange<reset>\n",
        job.bundled_buy_planet))
    f2t_debug_log("[hauling/po] Navigating to bundled buy: %s", dest)

    local nav_result = f2t_map_navigate(dest)

    if nav_result == false then
        cecho(string.format("\n<yellow>[hauling]<reset> Cannot navigate to %s exchange, skipping bundled buy\n",
            job.bundled_buy_planet))
        f2t_debug_log("[hauling/po] Bundled buy navigation failed, proceeding to sell")
        f2t_hauling_transition("po_navigating_to_sell")
    elseif nav_result == true and not F2T_SPEEDWALK_ACTIVE then
        -- Set phase to prevent GMCP handler re-entry during async buy
        F2T_HAULING_STATE.current_phase = "po_buying"
        f2t_hauling_phase_po_bundled_buy()
    end
end

--- Buy the second (bundled) commodity after navigating to its source
function f2t_hauling_phase_po_bundled_buy()
    local job = F2T_HAULING_STATE.po_current_job
    if not job or not job.bundled_commodity then
        f2t_hauling_transition("po_navigating_to_sell")
        return
    end

    local commodity = job.bundled_commodity
    local lots = job.bundled_lots or job.lots

    cecho(string.format("\n<green>[hauling]<reset> Buying bundled %d lots of <cyan>%s<reset>...\n",
        lots, commodity))
    f2t_debug_log("[hauling/po] Buying bundled: %d lots of %s", lots, commodity)

    f2t_bulk_buy_start(commodity, lots, function(bought_commodity, lots_bought, status, error_msg)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if status == "error" or lots_bought == 0 then
            cecho(string.format("\n<yellow>[hauling]<reset> Bundled buy failed for %s, continuing with primary\n",
                commodity))
        else
            cecho(string.format("\n<green>[hauling]<reset> Bought %d lots of <cyan>%s<reset>\n",
                lots_bought, commodity))
        end

        f2t_hauling_transition("po_navigating_to_sell")
    end)
end

-- ========================================
-- Phase: Navigate to Sell
-- ========================================

--- Navigate to the sell location for current job
function f2t_hauling_phase_po_navigate_to_sell()
    local job = F2T_HAULING_STATE.po_current_job
    if not job then
        cecho("\n<red>[hauling]<reset> No current job\n")
        f2t_hauling_do_stop()
        return
    end

    local destination = string.format("%s exchange", job.sell_planet)
    cecho(string.format("\n<green>[hauling]<reset> Navigating to sell location: <cyan>%s exchange<reset>\n",
        job.sell_planet))
    f2t_debug_log("[hauling/po] Navigating to sell: %s", destination)

    local nav_result = f2t_map_navigate(destination)

    if nav_result == false then
        cecho(string.format("\n<red>[hauling]<reset> Cannot navigate to %s exchange, skipping job\n", job.sell_planet))
        f2t_debug_log("[hauling/po] Navigation to sell location failed, skipping job")
        -- We have cargo but can't sell - skip to next job
        F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
        f2t_hauling_phase_po_next_job()
    elseif nav_result == true and not F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[hauling/po] Already at sell location")
        f2t_hauling_transition("po_selling")
    end
end

-- ========================================
-- Phase: Sell
-- ========================================

--- Sell all cargo at current location
function f2t_hauling_phase_po_sell()
    cecho("\n<green>[hauling]<reset> Selling all cargo...\n")
    f2t_debug_log("[hauling/po] Selling all cargo")

    -- Sell everything (bs command)
    f2t_bulk_sell_start(nil, nil, function(commodity, lots_sold, status, error_msg)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        f2t_debug_log("[hauling/po] Sell complete: lots=%d, status=%s", lots_sold, status)

        if lots_sold > 0 then
            -- Track cycle and type-specific counter
            F2T_HAULING_STATE.total_cycles = F2T_HAULING_STATE.total_cycles + 1
            local job = F2T_HAULING_STATE.po_current_job
            if job and job.type == "deficit" then
                F2T_HAULING_STATE.po_deficit_cycles = F2T_HAULING_STATE.po_deficit_cycles + 1
            else
                F2T_HAULING_STATE.po_excess_cycles = F2T_HAULING_STATE.po_excess_cycles + 1
            end
            cecho(string.format("\n<green>[hauling]<reset> Sold %d lots (cycle %d)\n",
                lots_sold, F2T_HAULING_STATE.total_cycles))
        end

        -- Check if cargo is now empty
        local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
        if cargo and #cargo > 0 then
            -- Partial sell - find next sell location
            f2t_debug_log("[hauling/po] Partial sell, %d lots remaining", #cargo)
            cecho(string.format("\n<yellow>[hauling]<reset> %d lots remain unsold, finding next sell location...\n", #cargo))
            f2t_hauling_po_find_next_sell()
            return
        end

        -- Hold empty, reset sell attempts and advance
        F2T_HAULING_STATE.po_sell_attempts = 0

        -- Only re-check deficits after selling excess production
        -- When filling deficits, go through the whole queue first to avoid wasted scans
        local job = F2T_HAULING_STATE.po_current_job
        if job and job.type == "deficit" then
            f2t_debug_log("[hauling/po] Deficit job complete, advancing to next job")
            F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
            f2t_hauling_phase_po_next_job()
        else
            f2t_hauling_transition("po_checking_deficits")
        end
    end)
end

-- ========================================
-- Partial Sell: Find Next Sell Location
-- ========================================

--- Find next sell location when exchange stopped buying our cargo
--- Uses price check to find any exchange that will buy, navigates there
function f2t_hauling_po_find_next_sell()
    F2T_HAULING_STATE.po_sell_attempts = F2T_HAULING_STATE.po_sell_attempts + 1

    local max_attempts = tonumber(f2t_settings_get("hauling", "po_max_sell_attempts")) or 3

    if F2T_HAULING_STATE.po_sell_attempts > max_attempts then
        cecho(string.format("\n<yellow>[hauling]<reset> Tried %d sell locations, jettisoning remaining cargo\n",
            max_attempts))
        f2t_debug_log("[hauling/po] Max sell attempts reached, jettisoning")
        f2t_hauling_jettison_cargo(function()
            F2T_HAULING_STATE.po_sell_attempts = 0
            F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
            f2t_hauling_phase_po_next_job()
        end)
        return
    end

    local job = F2T_HAULING_STATE.po_current_job
    if not job then
        F2T_HAULING_STATE.po_sell_attempts = 0
        F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
        f2t_hauling_phase_po_next_job()
        return
    end

    -- Determine which commodity to look up (primary or bundled, check what's in cargo)
    local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    local commodity = cargo and #cargo > 0 and cargo[1].commodity or job.commodity

    f2t_debug_log("[hauling/po] Finding next sell location for %s (attempt %d/%d)",
        commodity, F2T_HAULING_STATE.po_sell_attempts, max_attempts)

    f2t_price_check_commodity(commodity, function(commodity_name, parsed_data, analysis)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if not analysis or not analysis.top_buy then
            cecho(string.format("\n<yellow>[hauling]<reset> No price data for %s, skipping to next job\n", commodity))
            F2T_HAULING_STATE.po_sell_attempts = 0
            F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
            f2t_hauling_phase_po_next_job()
            return
        end

        -- Find next viable buyer, skipping the planet we bought from
        local found = false
        local viable_index = 0
        for _, candidate in ipairs(analysis.top_buy) do
            if candidate.planet == job.buy_planet then
                f2t_debug_log("[hauling/po] Skipping %s (same as buy planet)", candidate.planet)
            else
                viable_index = viable_index + 1
                if viable_index == F2T_HAULING_STATE.po_sell_attempts then
                    f2t_debug_log("[hauling/po] Next sell location: %s:%s at %d ig/ton",
                        candidate.system, candidate.planet, candidate.price)
                    cecho(string.format("\n<green>[hauling]<reset> Trying sell location: <cyan>%s exchange<reset>\n",
                        candidate.planet))

                    job.sell_planet = candidate.planet
                    job.sell_system = candidate.system
                    f2t_hauling_transition("po_navigating_to_sell")
                    found = true
                    break
                end
            end
        end

        if not found then
            cecho(string.format("\n<yellow>[hauling]<reset> No more exchanges buying %s, jettisoning remaining cargo\n",
                commodity))
            f2t_hauling_jettison_cargo(function()
                F2T_HAULING_STATE.po_sell_attempts = 0
                F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
                f2t_hauling_phase_po_next_job()
            end)
        end
    end)
end

-- ========================================
-- Phase: Check Deficits (After Sell)
-- ========================================

--- Re-scan exchanges remotely after selling to check for new deficits
function f2t_hauling_phase_po_check_deficits()
    f2t_debug_log("[hauling/po] Phase: po_checking_deficits")
    cecho("\n<green>[hauling]<reset> Checking for new deficits...\n")

    local owned_planets = F2T_HAULING_STATE.po_owned_planets

    f2t_po_hauling_rescan_exchanges(owned_planets, function(fresh_exchange_data)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Update stored exchange data
        F2T_HAULING_STATE.po_planet_exchange_data = fresh_exchange_data

        -- Check for new deficits
        local new_deficits = f2t_po_hauling_find_deficits(fresh_exchange_data)

        if #new_deficits > 0 then
            cecho(string.format("\n<green>[hauling]<reset> Found <cyan>%d<reset> new deficit(s), resolving...\n",
                #new_deficits))

            -- Resolve sources for new deficits
            f2t_po_hauling_resolve_jobs(new_deficits, fresh_exchange_data, function(resolved_deficits)
                if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                    return
                end

                if #resolved_deficits > 0 then
                    -- Bundle for 14-lot ships
                    local bundled = f2t_po_hauling_bundle_jobs(resolved_deficits, F2T_HAULING_STATE.po_ship_lots)

                    -- Insert at front of remaining queue
                    local queue = F2T_HAULING_STATE.po_job_queue
                    local current_index = F2T_HAULING_STATE.po_job_index + 1  -- After current job

                    for i = #bundled, 1, -1 do
                        table.insert(queue, current_index, bundled[i])
                    end

                    f2t_debug_log("[hauling/po] Inserted %d deficit jobs at front of queue", #bundled)
                    cecho(string.format("\n<green>[hauling]<reset> Added %d deficit job(s) to front of queue\n",
                        #bundled))
                end

                -- Continue with next job
                F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
                f2t_hauling_phase_po_next_job()
            end)
        else
            f2t_debug_log("[hauling/po] No new deficits found")
            -- Continue with next job
            F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
            f2t_hauling_phase_po_next_job()
        end
    end)
end

-- ========================================
-- Event Handlers
-- ========================================

--- Check if PO navigation is complete (generic for all PO navigation phases)
function f2t_hauling_check_po_nav_complete()
    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
        return
    end

    local phase = F2T_HAULING_STATE.current_phase

    -- Only handle PO navigation phases
    if phase ~= "po_navigating_to_buy" and phase ~= "po_navigating_to_sell" and
       phase ~= "po_navigating_to_bundled_buy" then
        return
    end

    -- Check if speedwalk completed
    if not F2T_SPEEDWALK_ACTIVE then
        local result = F2T_SPEEDWALK_LAST_RESULT
        f2t_debug_log("[hauling/po] Navigation completed in phase %s with result: %s",
            phase, result or "unknown")

        if result == "completed" then
            if phase == "po_navigating_to_buy" then
                f2t_hauling_transition("po_buying")
            elseif phase == "po_navigating_to_sell" then
                f2t_hauling_transition("po_selling")
            elseif phase == "po_navigating_to_bundled_buy" then
                f2t_hauling_phase_po_bundled_buy()
            end

        elseif result == "stopped" then
            cecho("\n<yellow>[hauling]<reset> Navigation stopped by user, stopping hauling\n")
            f2t_hauling_stop()

        elseif result == "failed" then
            cecho(string.format("\n<red>[hauling]<reset> Cannot reach destination (path blocked)\n"))
            f2t_debug_log("[hauling/po] Skipping job due to navigation failure")
            F2T_HAULING_STATE.po_job_index = F2T_HAULING_STATE.po_job_index + 1
            f2t_hauling_phase_po_next_job()

        else
            -- Unknown result, proceed optimistically
            f2t_debug_log("[hauling/po] Unknown result, using legacy behavior")
            if phase == "po_navigating_to_buy" then
                f2t_hauling_transition("po_buying")
            elseif phase == "po_navigating_to_sell" then
                f2t_hauling_transition("po_selling")
            elseif phase == "po_navigating_to_bundled_buy" then
                f2t_hauling_phase_po_bundled_buy()
            end
        end
    end
end

--- Register PO-specific GMCP event handlers
--- @return string Event handler ID
function f2t_po_register_handlers()
    local handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        -- Check navigation completion after brief delay for GMCP to settle
        tempTimer(0.5, function()
            f2t_hauling_check_po_nav_complete()
        end)
    end)

    f2t_debug_log("[hauling/po] Registered PO event handlers")
    return handler_id
end

--- Cleanup PO event handlers
--- @param handler_id string Event handler ID to kill
function f2t_po_cleanup_handlers(handler_id)
    if handler_id then
        killAnonymousEventHandler(handler_id)
        f2t_debug_log("[hauling/po] Cleaned up PO event handlers")
    end
end

f2t_debug_log("[hauling/po] Phases module loaded")
