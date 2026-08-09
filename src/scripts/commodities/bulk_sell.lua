-- Bulk sell logic for commodities component

-- Count how many lots of a commodity are in the cargo hold
local function count_cargo_lots(commodity)
    local count = 0
    local cargo = gmcp.char.ship.cargo or {}
    local commodity_lower = string.lower(commodity)

    for _, item in ipairs(cargo) do
        if string.lower(item.commodity) == commodity_lower then
            count = count + 1
        end
    end

    f2t_debug_log("[bulk-sell] Counted %d lots of %s in cargo", count, commodity)
    return count
end

-- Calculate total cost of a commodity in cargo hold (from GMCP cargo data)
-- Returns: total_cost, lot_count
local function calculate_commodity_cost(commodity)
    local cargo = gmcp.char.ship.cargo or {}
    local commodity_lower = string.lower(commodity)
    local total_cost = 0
    local lot_count = 0

    for _, item in ipairs(cargo) do
        if string.lower(item.commodity) == commodity_lower then
            -- GMCP cargo has: {commodity, base, cost, origin}
            -- cost = price per ton we paid, multiply by 75 for lot cost
            total_cost = total_cost + ((item.cost or 0) * 75)
            lot_count = lot_count + 1
        end
    end

    f2t_debug_log("[bulk-sell] Commodity %s: %d lots, total cost: %d ig", commodity, lot_count, total_cost)
    return total_cost, lot_count
end

-- Get list of all unique commodities in cargo hold
local function get_all_commodities()
    local cargo = gmcp.char.ship.cargo or {}
    local commodities = {}
    local seen = {}

    for _, item in ipairs(cargo) do
        local comm_lower = string.lower(item.commodity)
        if not seen[comm_lower] then
            seen[comm_lower] = true
            table.insert(commodities, item.commodity)
        end
    end

    f2t_debug_log("[bulk-sell] Found %d unique commodities in cargo", #commodities)
    return commodities
end

-- Start a bulk sell operation
-- @param commodity: The commodity to sell (nil = sell all cargo, supports short names like "petros")
-- @param requested_lots: Number of lots to sell (nil = sell all of commodity)
-- @param callback: Optional callback(commodity, lots_sold, status, error_msg) for programmatic mode
function f2t_bulk_sell_start(commodity, requested_lots, callback)
    -- Resolve short names to full names (if commodity specified)
    if commodity then
        local resolved, was_short = f2t_resolve_commodity(commodity)
        if was_short then
            f2t_debug_log("[bulk-sell] Resolved short name '%s' to '%s'", commodity, resolved)
        end
        commodity = resolved
    end

    f2t_debug_log("[bulk-sell] Starting bulk sell: commodity=%s, requested=%s, mode=%s",
        tostring(commodity), tostring(requested_lots), callback and "programmatic" or "user")

    -- Check if we're in an exchange
    local room_info = gmcp.room and gmcp.room.info
    if not room_info or not room_info.flags then
        f2t_debug_log("[bulk-sell] ERROR: Room data not available")
        if not callback then
            cecho("\n<red>[bulk-sell]<reset> Room data not available\n")
        else
            callback(commodity, 0, "error", "Room data not available")
        end
        return false
    end

    local flags = room_info.flags
    if not f2t_has_value(flags, "exchange") then
        f2t_debug_log("[bulk-sell] ERROR: Not at exchange")
        if not callback then
            cecho("\n<red>[bulk-sell]<reset> You must be in a commodity exchange to trade commodities!\n")
        else
            callback(commodity, 0, "error", "Not at exchange")
        end
        return false
    end

    -- If no commodity specified, sell everything
    if not commodity then
        f2t_debug_log("[bulk-sell] No commodity specified, selling all cargo")
        local all_commodities = get_all_commodities()

        if #all_commodities == 0 then
            f2t_debug_log("[bulk-sell] ERROR: Cargo hold is empty")
            if not callback then
                cecho("\n<red>[bulk-sell]<reset> Your cargo hold is empty!\n")
            else
                callback(nil, 0, "error", "Cargo hold is empty")
            end
            return false
        end

        -- Initialize state for selling all commodities
        F2T_BULK_STATE.active = true
        F2T_BULK_STATE.command = "sell"
        F2T_BULK_STATE.commodity_queue = all_commodities
        F2T_BULK_STATE.queue_index = 1
        F2T_BULK_STATE.total_sold = 0
        F2T_BULK_STATE.callback = callback
        -- Aggregate stats across all commodities
        F2T_BULK_STATE.aggregate_cost = 0
        F2T_BULK_STATE.aggregate_revenue = 0
        F2T_BULK_STATE.aggregate_lots_sold = 0

        f2t_debug_log("[bulk-sell] Initialized queue mode with %d commodities", #all_commodities)

        -- Only show user feedback in user mode
        if not callback then
            cecho(string.format(
                "\n<green>[bulk-sell]<reset> Selling all cargo (%d different commodities)...\n", #all_commodities))
        end

        -- Start selling first commodity
        f2t_bulk_sell_next_commodity()
        return true
    end

    -- Count how many lots we have in cargo
    local available_lots = count_cargo_lots(commodity)

    if available_lots == 0 then
        f2t_debug_log("[bulk-sell] ERROR: No %s in cargo", commodity)
        if not callback then
            cecho(string.format("\n<red>[bulk-sell]<reset> You don't have any %s in your cargo hold!\n", commodity))
        else
            callback(commodity, 0, "error", string.format("No %s in cargo", commodity))
        end
        return false
    end

    -- Determine how many lots to sell
    local lots_to_sell = requested_lots and math.min(requested_lots, available_lots) or available_lots

    f2t_debug_log("[bulk-sell] Will sell %d lots of %s (have %d available)", lots_to_sell, commodity, available_lots)

    -- Calculate total cost from GMCP cargo data
    local total_cost, _ = calculate_commodity_cost(commodity)

    -- Initialize state for selling single commodity
    F2T_BULK_STATE.active = true
    F2T_BULK_STATE.command = "sell"
    F2T_BULK_STATE.commodity = commodity
    F2T_BULK_STATE.remaining = lots_to_sell
    F2T_BULK_STATE.total = lots_to_sell
    F2T_BULK_STATE.commodity_queue = nil
    F2T_BULK_STATE.callback = callback
    F2T_BULK_STATE.total_cost = total_cost
    F2T_BULK_STATE.total_revenue = 0
    F2T_BULK_STATE.lots_sold = 0

    -- Only show user feedback in user mode
    if not callback then
        cecho(string.format("\n<green>[bulk-sell]<reset> Selling %d lots of %s (%d tons)...\n",
            lots_to_sell, commodity, lots_to_sell * 75))
    end

    -- Send first sell command
    f2t_bulk_sell_next()
    return true
end

-- Start selling the next commodity in the queue
function f2t_bulk_sell_next_commodity()
    if not F2T_BULK_STATE.commodity_queue then
        return
    end

    if F2T_BULK_STATE.queue_index > #F2T_BULK_STATE.commodity_queue then
        -- Done with all commodities
        f2t_bulk_sell_finish_all()
        return
    end

    local commodity = F2T_BULK_STATE.commodity_queue[F2T_BULK_STATE.queue_index]
    local available_lots = count_cargo_lots(commodity)

    if available_lots == 0 then
        -- Skip this commodity and move to next
        F2T_BULK_STATE.queue_index = F2T_BULK_STATE.queue_index + 1
        f2t_bulk_sell_next_commodity()
        return
    end

    -- Calculate cost for this commodity
    local total_cost, _ = calculate_commodity_cost(commodity)

    -- Set up state for this commodity
    F2T_BULK_STATE.commodity = commodity
    F2T_BULK_STATE.remaining = available_lots
    F2T_BULK_STATE.total = available_lots
    F2T_BULK_STATE.total_cost = total_cost
    F2T_BULK_STATE.total_revenue = 0
    F2T_BULK_STATE.lots_sold = 0

    f2t_debug_log("[bulk-sell] Starting commodity %d/%d: %s (%d lots, cost: %d ig)",
        F2T_BULK_STATE.queue_index, #F2T_BULK_STATE.commodity_queue, commodity, available_lots, total_cost)

    -- Send first sell command
    f2t_bulk_sell_next()
end

-- Send the next sell command
function f2t_bulk_sell_next()
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "sell" then
        return
    end

    if F2T_BULK_STATE.remaining <= 0 then
        f2t_bulk_sell_finish()
        return
    end

    f2t_debug_log("[bulk-sell] Sending sell command (%d remaining)", F2T_BULK_STATE.remaining)
    send(string.format("sell %s", string.lower(F2T_BULK_STATE.commodity)), false)
end

-- Handle successful sell
-- @param commodity: Commodity name from trigger
-- @param revenue_per_ton: Revenue per ton from trigger
-- @param revenue_total: Total revenue for this lot from trigger
function f2t_bulk_sell_success(commodity, revenue_per_ton, revenue_total)
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "sell" then
        return
    end

    F2T_BULK_STATE.remaining = F2T_BULK_STATE.remaining - 1
    if F2T_BULK_STATE.commodity_queue then
        F2T_BULK_STATE.total_sold = F2T_BULK_STATE.total_sold + 1
    end

    -- Track revenue
    if revenue_total then
        F2T_BULK_STATE.total_revenue = F2T_BULK_STATE.total_revenue + revenue_total
        F2T_BULK_STATE.lots_sold = F2T_BULK_STATE.lots_sold + 1
        f2t_debug_log("[bulk-sell] Sell successful: %d ig/ton, %d ig total (%d remaining)",
            revenue_per_ton, revenue_total, F2T_BULK_STATE.remaining)
    else
        f2t_debug_log("[bulk-sell] Sell successful (%d remaining)", F2T_BULK_STATE.remaining)
    end

    if F2T_BULK_STATE.remaining > 0 then
        -- Continue selling current commodity
        f2t_bulk_sell_next()
    else
        -- Done with current commodity
        if F2T_BULK_STATE.commodity_queue then
            -- Accumulate stats before moving to next commodity
            F2T_BULK_STATE.aggregate_cost = F2T_BULK_STATE.aggregate_cost + (F2T_BULK_STATE.total_cost or 0)
            F2T_BULK_STATE.aggregate_revenue = F2T_BULK_STATE.aggregate_revenue + (F2T_BULK_STATE.total_revenue or 0)
            F2T_BULK_STATE.aggregate_lots_sold = F2T_BULK_STATE.aggregate_lots_sold + (F2T_BULK_STATE.lots_sold or 0)
            -- Move to next commodity in queue
            F2T_BULK_STATE.queue_index = F2T_BULK_STATE.queue_index + 1
            f2t_bulk_sell_next_commodity()
        else
            -- Single commodity mode, we're done
            f2t_bulk_sell_finish()
        end
    end
end

-- Handle sell error (stop the bulk operation)
function f2t_bulk_sell_error(reason)
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "sell" then
        return
    end

    f2t_debug_log("[bulk-sell] ERROR: %s", reason)

    -- Only show user feedback in user mode
    if not F2T_BULK_STATE.callback then
        cecho(string.format("\n<red>[bulk-sell]<reset> %s\n", reason))
    end

    if F2T_BULK_STATE.commodity_queue then
        -- In queue mode, move to next commodity
        f2t_debug_log("[bulk-sell] Queue mode: moving to next commodity")
        F2T_BULK_STATE.queue_index = F2T_BULK_STATE.queue_index + 1
        f2t_bulk_sell_next_commodity()
    else
        -- Single commodity mode, finish
        f2t_debug_log("[bulk-sell] Single mode: finishing")
        f2t_bulk_sell_finish()
    end
end

-- Finish selling single commodity
function f2t_bulk_sell_finish()
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "sell" then
        return
    end

    local sold = F2T_BULK_STATE.total - F2T_BULK_STATE.remaining
    local tons = sold * 75
    local commodity = F2T_BULK_STATE.commodity
    local callback = F2T_BULK_STATE.callback

    f2t_debug_log("[bulk-sell] Finishing: sold %d lots of %s (%d tons)", sold, commodity, tons)

    -- Capture margin data before reset
    local total_cost = F2T_BULK_STATE.total_cost or 0
    local total_revenue = F2T_BULK_STATE.total_revenue or 0
    local lots_sold_count = F2T_BULK_STATE.lots_sold or 0
    local total_lots = F2T_BULK_STATE.total or 0

    -- Reset state BEFORE callback to prevent re-entrant state corruption
    -- (callback may synchronously start a new bulk operation)
    F2T_BULK_STATE.active = false
    F2T_BULK_STATE.command = nil
    F2T_BULK_STATE.callback = nil
    F2T_BULK_STATE.total_cost = 0
    F2T_BULK_STATE.total_revenue = 0
    F2T_BULK_STATE.lots_sold = 0

    -- User mode: show formatted output with margin info
    if not callback then
        local msg = string.format("\n<green>[bulk-sell]<reset> Complete: Sold %d lots of %s (%d tons)",
            sold, commodity, tons)

        -- Calculate and display margin if we have cost and revenue data
        if total_cost > 0 and total_revenue > 0 and lots_sold_count > 0 then
            -- Scale cost proportionally: total_cost is for all lots in cargo, but we may have sold fewer
            -- Cost per lot = total_cost / total, then multiply by lots_sold
            local cost_per_lot = total_cost / total_lots
            local cost = cost_per_lot * lots_sold_count
            local revenue = total_revenue
            local profit = revenue - cost
            local margin_pct = (profit / cost) * 100

            local avg_cost_per_ton = math.floor(cost / (lots_sold_count * 75))
            local avg_revenue_per_ton = math.floor(revenue / (lots_sold_count * 75))

            -- Color code margin
            local margin_color = "white"
            if margin_pct >= 40 then
                margin_color = "green"
            elseif margin_pct >= 20 then
                margin_color = "yellow"
            elseif margin_pct < 0 then
                margin_color = "red"
            end

            -- Color code profit
            local profit_color = profit >= 0 and "green" or "red"

            msg = msg .. string.format(
                "\n  <dim_grey>Cost: <white>%d ig<reset> <dim_grey>(%d ig/ton)<reset> | " ..
                "<dim_grey>Revenue: <white>%d ig<reset> <dim_grey>(%d ig/ton)<reset>",
                cost, avg_cost_per_ton, revenue, avg_revenue_per_ton)
            msg = msg .. string.format("\n  <dim_grey>Profit: <%s>%d ig<reset> | <dim_grey>Margin: <%s>%.1f%%<reset>",
                profit_color, profit, margin_color, margin_pct)
        end

        cecho(msg .. "\n")

    -- Programmatic mode: call callback with data
    else
        local status = sold > 0 and "success" or "failed"
        callback(commodity, sold, status, nil)
    end
end

-- Finish selling all commodities
function f2t_bulk_sell_finish_all()
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "sell" then
        return
    end

    local total_sold = F2T_BULK_STATE.total_sold
    local total_tons = total_sold * 75
    local callback = F2T_BULK_STATE.callback

    -- Check if there's still cargo remaining
    local cargo = gmcp.char.ship.cargo or {}
    local remaining_lots = #cargo

    f2t_debug_log("[bulk-sell] Finishing all: sold %d lots (%d tons), %d lots remain",
        total_sold, total_tons, remaining_lots)

    -- Capture aggregate data before reset
    local agg_cost = F2T_BULK_STATE.aggregate_cost or 0
    local agg_revenue = F2T_BULK_STATE.aggregate_revenue or 0
    local agg_lots_sold = F2T_BULK_STATE.aggregate_lots_sold or 0

    -- Reset state BEFORE callback to prevent re-entrant state corruption
    -- (callback may synchronously start a new bulk operation)
    F2T_BULK_STATE.active = false
    F2T_BULK_STATE.command = nil
    F2T_BULK_STATE.commodity_queue = nil
    F2T_BULK_STATE.callback = nil
    F2T_BULK_STATE.aggregate_cost = 0
    F2T_BULK_STATE.aggregate_revenue = 0
    F2T_BULK_STATE.aggregate_lots_sold = 0

    -- User mode: show formatted output
    if not callback then
        local msg
        if remaining_lots == 0 then
            -- Cargo hold is completely empty
            msg = string.format("\n<green>[bulk-sell]<reset> Complete: Sold all cargo - %d lots (%d tons)",
                total_sold, total_tons)
        else
            -- Still have unsold cargo
            local remaining_tons = remaining_lots * 75
            msg = string.format(
                "\n<green>[bulk-sell]<reset> Complete: Sold %d lots (%d tons) - %d lots (%d tons) remain unsold",
                total_sold, total_tons, remaining_lots, remaining_tons)
        end

        -- Calculate and display aggregate margin info
        if agg_cost > 0 and agg_revenue > 0 and agg_lots_sold > 0 then
            local profit = agg_revenue - agg_cost
            local margin_pct = (profit / agg_cost) * 100

            local avg_cost_per_ton = math.floor(agg_cost / (agg_lots_sold * 75))
            local avg_revenue_per_ton = math.floor(agg_revenue / (agg_lots_sold * 75))

            -- Color code margin
            local margin_color = "white"
            if margin_pct >= 40 then
                margin_color = "green"
            elseif margin_pct >= 20 then
                margin_color = "yellow"
            elseif margin_pct < 0 then
                margin_color = "red"
            end

            -- Color code profit
            local profit_color = profit >= 0 and "green" or "red"

            msg = msg .. string.format(
                "\n  <dim_grey>Cost: <white>%d ig<reset> <dim_grey>(%d ig/ton)<reset> | " ..
                "<dim_grey>Revenue: <white>%d ig<reset> <dim_grey>(%d ig/ton)<reset>",
                agg_cost, avg_cost_per_ton, agg_revenue, avg_revenue_per_ton)
            msg = msg .. string.format("\n  <dim_grey>Profit: <%s>%d ig<reset> | <dim_grey>Margin: <%s>%.1f%%<reset>",
                profit_color, profit, margin_color, margin_pct)
        end

        cecho(msg .. "\n")

    -- Programmatic mode: call callback with data
    else
        local status = total_sold > 0 and "success" or "failed"
        callback(nil, total_sold, status, nil)
    end
end