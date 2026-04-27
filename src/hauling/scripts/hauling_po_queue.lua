-- Planet Owner Queue Builder
-- Builds deficit and excess job queues, resolves sources/destinations, bundles for 14-lot ships

-- ========================================
-- Deficit and Excess Detection
-- ========================================

--- Find commodities with stock at or below deficit threshold across owned planets
--- @param planet_exchange_data table {[planet_name] = exchange_data_array}
--- @return table Array of {type="deficit", commodity=string, target_planet=string, sell_planet=string}
function f2t_po_hauling_find_deficits(planet_exchange_data)
    local deficits = {}
    local threshold = tonumber(f2t_settings_get("hauling", "po_deficit_threshold")) or -525

    f2t_debug_log("[hauling/po-queue] Deficit threshold: %d", threshold)

    for planet, exchange_data in pairs(planet_exchange_data) do
        for _, item in ipairs(exchange_data) do
            if item.stock_current and item.stock_current <= threshold then
                local lots = math.min(7, math.ceil(math.abs(item.stock_current) / 75))
                f2t_debug_log("[hauling/po-queue] Deficit found: %s on %s (stock: %d, lots: %d)",
                    item.name, planet, item.stock_current, lots)
                table.insert(deficits, {
                    type = "deficit",
                    commodity = item.name,
                    target_planet = planet,
                    lots = lots,
                    -- For deficit: sell_planet = target (deliver to planet with deficit)
                    sell_planet = planet,
                    sell_system = F2T_HAULING_STATE.po_current_system,
                    buy_planet = nil,      -- Resolved later
                    buy_system = nil,
                    resolved = false
                })
            end
        end
    end

    f2t_debug_log("[hauling/po-queue] Found %d deficits", #deficits)
    return deficits
end

--- Find commodities with stock at or above excess threshold across owned planets
--- @param planet_exchange_data table {[planet_name] = exchange_data_array}
--- @return table Array of {type="excess", commodity=string, target_planet=string, buy_planet=string}
function f2t_po_hauling_find_excesses(planet_exchange_data)
    local excesses = {}
    local threshold = tonumber(f2t_settings_get("hauling", "po_excess_threshold")) or 20000

    f2t_debug_log("[hauling/po-queue] Excess threshold: %d", threshold)

    for planet, exchange_data in pairs(planet_exchange_data) do
        for _, item in ipairs(exchange_data) do
            if item.stock_current and item.stock_current >= threshold then
                f2t_debug_log("[hauling/po-queue] Excess found: %s on %s (stock: %d)",
                    item.name, planet, item.stock_current)
                table.insert(excesses, {
                    type = "excess",
                    commodity = item.name,
                    target_planet = planet,
                    lots = 7,
                    -- For excess: buy_planet = target (buy from planet with excess)
                    buy_planet = planet,
                    buy_system = F2T_HAULING_STATE.po_current_system,
                    sell_planet = nil,     -- Resolved later
                    sell_system = nil,
                    resolved = false
                })
            end
        end
    end

    f2t_debug_log("[hauling/po-queue] Found %d excesses", #excesses)
    return excesses
end

-- ========================================
-- Source/Destination Resolution
-- ========================================

--- Check if an owned planet can be a source for a deficit job
--- Looks for the commodity on owned planets where stock > 0
--- @param commodity string Commodity name
--- @param target_planet string Planet with the deficit (skip this one)
--- @param planet_exchange_data table Exchange data for all owned planets
--- @return string|nil Planet name that has stock, or nil
--- @return string|nil System name
local function find_owned_source(commodity, target_planet, planet_exchange_data)
    local commodity_lower = string.lower(commodity)

    for planet, exchange_data in pairs(planet_exchange_data) do
        if planet ~= target_planet then
            for _, item in ipairs(exchange_data) do
                if string.lower(item.name) == commodity_lower and
                   item.stock_current and item.stock_current > 0 then
                    f2t_debug_log("[hauling/po-queue] Found owned source for %s: %s (stock: %d)",
                        commodity, planet, item.stock_current)
                    return planet, F2T_HAULING_STATE.po_current_system
                end
            end
        end
    end

    return nil, nil
end

--- Check if an owned planet can be a destination for an excess job
--- Looks for the commodity on owned planets where stock < max
--- @param commodity string Commodity name
--- @param target_planet string Planet with the excess (skip this one)
--- @param planet_exchange_data table Exchange data for all owned planets
--- @return string|nil Planet name that has room, or nil
--- @return string|nil System name
local function find_owned_destination(commodity, target_planet, planet_exchange_data)
    local commodity_lower = string.lower(commodity)

    for planet, exchange_data in pairs(planet_exchange_data) do
        if planet ~= target_planet then
            for _, item in ipairs(exchange_data) do
                if string.lower(item.name) == commodity_lower and
                   item.stock_current and item.stock_max and
                   item.stock_current < item.stock_max then
                    f2t_debug_log("[hauling/po-queue] Found owned destination for %s: %s (stock: %d/%d)",
                        commodity, planet, item.stock_current, item.stock_max)
                    return planet, F2T_HAULING_STATE.po_current_system
                end
            end
        end
    end

    return nil, nil
end

--- Resolve source/destination for all jobs sequentially
--- Checks owned planets first, falls back to cartel via price check
--- @param jobs table Array of job objects to resolve
--- @param planet_exchange_data table Exchange data for owned planets
--- @param callback function Called with resolved jobs array when complete
function f2t_po_hauling_resolve_jobs(jobs, planet_exchange_data, callback)
    if #jobs == 0 then
        callback({})
        return
    end

    local resolved_jobs = {}
    local resolve_index = 0

    local function resolve_next()
        resolve_index = resolve_index + 1

        if resolve_index > #jobs then
            f2t_debug_log("[hauling/po-queue] All %d jobs resolved", #resolved_jobs)
            callback(resolved_jobs)
            return
        end

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        local job = jobs[resolve_index]
        f2t_debug_log("[hauling/po-queue] Resolving job %d/%d: %s %s on %s",
            resolve_index, #jobs, job.type, job.commodity, job.target_planet)

        if job.type == "deficit" then
            -- Deficit: need a source (where to buy)
            local source_planet, source_system = find_owned_source(
                job.commodity, job.target_planet, planet_exchange_data)

            if source_planet then
                job.buy_planet = source_planet
                job.buy_system = source_system
                job.resolved = true
                table.insert(resolved_jobs, job)
                f2t_debug_log("[hauling/po-queue] Deficit resolved from owned planet: %s", source_planet)
                resolve_next()
            else
                -- Fall back to cartel price check
                f2t_debug_log("[hauling/po-queue] No owned source for %s, checking cartel", job.commodity)
                f2t_price_check_commodity(job.commodity, function(commodity_name, parsed_data, analysis)
                    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                        return
                    end

                    -- top_sell = exchanges selling (where we buy), skip same planet as sell destination
                    local found = false
                    if analysis and analysis.top_sell then
                        for _, candidate in ipairs(analysis.top_sell) do
                            if candidate.planet ~= job.sell_planet then
                                job.buy_planet = candidate.planet
                                job.buy_system = candidate.system
                                job.resolved = true
                                table.insert(resolved_jobs, job)
                                f2t_debug_log("[hauling/po-queue] Deficit resolved from cartel: %s:%s",
                                    candidate.system, candidate.planet)
                                found = true
                                break
                            else
                                f2t_debug_log("[hauling/po-queue] Skipping %s (same as sell planet)", candidate.planet)
                            end
                        end
                    end
                    if not found then
                        f2t_debug_log("[hauling/po-queue] No source found for %s, skipping",
                            job.commodity)
                        cecho(string.format("\n<yellow>[hauling]<reset> No source found for %s deficit on %s, skipping\n",
                            job.commodity, job.target_planet))
                    end

                    tempTimer(0.3, function()
                        resolve_next()
                    end)
                end)
            end

        elseif job.type == "excess" then
            -- Excess: need a destination (where to sell)
            local dest_planet, dest_system = find_owned_destination(
                job.commodity, job.target_planet, planet_exchange_data)

            if dest_planet then
                job.sell_planet = dest_planet
                job.sell_system = dest_system
                job.resolved = true
                table.insert(resolved_jobs, job)
                f2t_debug_log("[hauling/po-queue] Excess resolved to owned planet: %s", dest_planet)
                resolve_next()
            else
                -- Fall back to cartel price check
                f2t_debug_log("[hauling/po-queue] No owned destination for %s, checking cartel", job.commodity)
                f2t_price_check_commodity(job.commodity, function(commodity_name, parsed_data, analysis)
                    if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                        return
                    end

                    -- top_buy = exchanges buying (where we sell), skip same planet as buy source
                    local found = false
                    if analysis and analysis.top_buy then
                        for _, candidate in ipairs(analysis.top_buy) do
                            if candidate.planet ~= job.buy_planet then
                                job.sell_planet = candidate.planet
                                job.sell_system = candidate.system
                                job.resolved = true
                                table.insert(resolved_jobs, job)
                                f2t_debug_log("[hauling/po-queue] Excess resolved to cartel: %s:%s",
                                    candidate.system, candidate.planet)
                                found = true
                                break
                            else
                                f2t_debug_log("[hauling/po-queue] Skipping %s (same as buy planet)", candidate.planet)
                            end
                        end
                    end
                    if not found then
                        f2t_debug_log("[hauling/po-queue] No destination found for %s, skipping",
                            job.commodity)
                        cecho(string.format("\n<yellow>[hauling]<reset> No destination found for %s excess on %s, skipping\n",
                            job.commodity, job.target_planet))
                    end

                    tempTimer(0.3, function()
                        resolve_next()
                    end)
                end)
            end
        end
    end

    resolve_next()
end

-- ========================================
-- Job Bundling (14-lot ships)
-- ========================================

--- Bundle jobs for 14-lot ships by grouping jobs with the same sell destination
--- Works for both deficit and excess jobs
--- @param jobs table Array of resolved job objects
--- @param ship_lots number Ship capacity in lots
--- @return table Array of jobs (some bundled with secondary commodity)
function f2t_po_hauling_bundle_jobs(jobs, ship_lots)
    if ship_lots < 14 or #jobs < 2 then
        f2t_debug_log("[hauling/po-queue] No bundling: ship_lots=%d, jobs=%d", ship_lots, #jobs)
        return jobs
    end

    f2t_debug_log("[hauling/po-queue] Attempting to bundle %d jobs for %d-lot ship", #jobs, ship_lots)

    -- Group by sell_planet, preserving insertion order of groups
    local groups = {}
    local group_order = {}  -- Deterministic order (first-seen sell_planet)
    local ungrouped = {}

    for _, job in ipairs(jobs) do
        local sell_key = job.sell_planet
        if sell_key then
            if not groups[sell_key] then
                groups[sell_key] = {}
                table.insert(group_order, sell_key)
            end
            table.insert(groups[sell_key], job)
        else
            table.insert(ungrouped, job)
        end
    end

    -- Pair jobs within each group (deterministic order preserves deficit priority)
    local result = {}
    for _, sell_planet in ipairs(group_order) do
        local group_jobs = groups[sell_planet]
        local i = 1
        while i <= #group_jobs do
            if i + 1 <= #group_jobs then
                -- Bundle pair
                local primary = group_jobs[i]
                local secondary = group_jobs[i + 1]

                primary.bundled_commodity = secondary.commodity
                primary.bundled_lots = secondary.lots
                primary.bundled_buy_planet = secondary.buy_planet
                primary.bundled_buy_system = secondary.buy_system
                primary.bundled_sell_planet = secondary.sell_planet
                primary.bundled_sell_system = secondary.sell_system

                f2t_debug_log("[hauling/po-queue] Bundled: %s + %s → sell at %s",
                    primary.commodity, secondary.commodity, sell_planet)

                table.insert(result, primary)
                i = i + 2
            else
                -- Odd one out, stays single
                table.insert(result, group_jobs[i])
                i = i + 1
            end
        end
    end

    -- Add ungrouped jobs
    for _, job in ipairs(ungrouped) do
        table.insert(result, job)
    end

    f2t_debug_log("[hauling/po-queue] Bundling complete: %d jobs → %d trips", #jobs, #result)
    return result
end

-- ========================================
-- Queue Builder (Orchestrator)
-- ========================================

--- Build the complete job queue from exchange data
--- Finds deficits + excesses, resolves all sources/destinations, bundles for capacity
--- @param planet_exchange_data table {[planet_name] = exchange_data_array}
--- @param owned_planets table Array of owned planet names
--- @param callback function Called with (job_queue) when complete
function f2t_po_hauling_build_queue(planet_exchange_data, owned_planets, callback)
    f2t_debug_log("[hauling/po-queue] Building job queue from %d owned planets",
        #owned_planets)

    -- Find deficits
    local deficits = f2t_po_hauling_find_deficits(planet_exchange_data)
    F2T_HAULING_STATE.po_deficit_count = #deficits

    -- Find excesses (unless po_mode is deficit-only)
    local po_mode = f2t_settings_get("hauling", "po_mode")
    local excesses = {}
    if po_mode ~= "deficit" then
        excesses = f2t_po_hauling_find_excesses(planet_exchange_data)
    else
        f2t_debug_log("[hauling/po-queue] Skipping excess detection (po_mode=deficit)")
    end
    F2T_HAULING_STATE.po_excess_count = #excesses

    -- Combine all jobs (deficits first for priority)
    local all_jobs = {}
    for _, job in ipairs(deficits) do
        table.insert(all_jobs, job)
    end
    for _, job in ipairs(excesses) do
        table.insert(all_jobs, job)
    end

    if #all_jobs == 0 then
        f2t_debug_log("[hauling/po-queue] No deficits or excesses found")
        callback({})
        return
    end

    cecho(string.format("\n<green>[hauling]<reset> Found <orange>%d<reset> deficit(s) and <yellow>%d<reset> excess(es), resolving sources...\n",
        #deficits, #excesses))

    -- Resolve all sources/destinations
    f2t_po_hauling_resolve_jobs(all_jobs, planet_exchange_data, function(resolved_jobs)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        -- Bundle for 14-lot ships
        local ship_lots = F2T_HAULING_STATE.po_ship_lots
        local final_queue = f2t_po_hauling_bundle_jobs(resolved_jobs, ship_lots)

        f2t_debug_log("[hauling/po-queue] Final queue: %d jobs (%d bundled trips)",
            #resolved_jobs, #final_queue)

        callback(final_queue)
    end)
end

f2t_debug_log("[hauling/po] Queue module loaded")
