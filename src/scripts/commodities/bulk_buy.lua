-- Bulk buy logic for commodities component

-- Start a bulk buy operation
-- @param commodity: The commodity to buy (supports short names like "petros")
-- @param requested_lots: Number of lots to buy (nil = fill hold)
-- @param callback: Optional callback(commodity, lots_bought, status, error_msg) for programmatic mode
function f2t_bulk_buy_start(commodity, requested_lots, callback)
    -- Resolve short names to full names
    local resolved, was_short = f2t_resolve_commodity(commodity)
    if was_short then
        f2t_debug_log("[bulk-buy] Resolved short name '%s' to '%s'", commodity, resolved)
    end
    commodity = resolved

    f2t_debug_log("[bulk-buy] Starting bulk buy: commodity=%s, requested=%s, mode=%s",
        commodity, tostring(requested_lots), callback and "programmatic" or "user")

    -- Check if we're in an exchange
    local room_info = gmcp.room and gmcp.room.info
    if not room_info or not room_info.flags then
        f2t_debug_log("[bulk-buy] ERROR: Room data not available")
        if not callback then
            cecho("\n<red>[bulk-buy]<reset> Room data not available\n")
        else
            callback(commodity, 0, "error", "Room data not available")
        end
        return false
    end

    local flags = room_info.flags
    if not f2t_has_value(flags, "exchange") then
        f2t_debug_log("[bulk-buy] ERROR: Not at exchange")
        if not callback then
            cecho("\n<red>[bulk-buy]<reset> You must be in a commodity exchange to trade commodities!\n")
        else
            callback(commodity, 0, "error", "Not at exchange")
        end
        return false
    end

    -- Calculate available hold space
    -- Note: gmcp.char.ship.hold.cur = available space (not used space)
    local hold = gmcp.char and gmcp.char.ship and gmcp.char.ship.hold
    if not hold or not hold.cur or not hold.max then
        f2t_debug_log("[bulk-buy] ERROR: Ship hold data not available")
        if not callback then
            cecho("\n<red>[bulk-buy]<reset> Ship hold data not available\n")
        else
            callback(commodity, 0, "error", "Ship hold data not available")
        end
        return false
    end

    local available_space = hold.cur
    local max_hold = hold.max
    local used_space = max_hold - available_space
    local max_lots = math.floor(available_space / 75)

    f2t_debug_log("[bulk-buy] Hold space: %d/%d tons (%d lots available)", available_space, max_hold, max_lots)

    if max_lots == 0 then
        f2t_debug_log("[bulk-buy] ERROR: Hold is full")
        if not callback then
            cecho(string.format(
                "\n<red>[bulk-buy]<reset> Your hold is full! (%d/%d tons used)\n", used_space, max_hold))
        else
            callback(commodity, 0, "error", "Hold is full")
        end
        return false
    end

    -- Determine how many lots to buy
    local lots_to_buy = requested_lots and math.min(requested_lots, max_lots) or max_lots

    f2t_debug_log("[bulk-buy] Will buy %d lots of %s", lots_to_buy, commodity)

    -- Initialize state
    F2T_BULK_STATE.active = true
    F2T_BULK_STATE.command = "buy"
    F2T_BULK_STATE.commodity = commodity
    F2T_BULK_STATE.remaining = lots_to_buy
    F2T_BULK_STATE.total = lots_to_buy
    F2T_BULK_STATE.callback = callback

    -- Only show user feedback in user mode
    if not callback then
        cecho(string.format("\n<green>[bulk-buy]<reset> Buying up to %d lots of %s (%d tons)...\n",
            lots_to_buy, commodity, lots_to_buy * 75))
    end

    -- Send first buy command
    f2t_bulk_buy_next()
    return true
end

-- Send the next buy command
function f2t_bulk_buy_next()
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "buy" then
        return
    end

    if F2T_BULK_STATE.remaining <= 0 then
        f2t_bulk_buy_finish()
        return
    end

    f2t_debug_log("[bulk-buy] Sending buy command (%d remaining)", F2T_BULK_STATE.remaining)
    send(string.format("buy %s", string.lower(F2T_BULK_STATE.commodity)), false)
end

-- Handle successful buy
function f2t_bulk_buy_success()
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "buy" then
        return
    end

    F2T_BULK_STATE.remaining = F2T_BULK_STATE.remaining - 1
    f2t_debug_log("[bulk-buy] Buy successful (%d remaining)", F2T_BULK_STATE.remaining)

    -- Check if we still have room and should continue
    -- Note: gmcp.char.ship.hold.cur = available space (not used space)
    local hold = gmcp.char and gmcp.char.ship and gmcp.char.ship.hold
    local available_space = hold and hold.cur or 0

    if available_space < 75 then
        -- Hold is full
        f2t_debug_log("[bulk-buy] Hold is full (%d tons available), stopping", available_space)
        if not F2T_BULK_STATE.callback then
            cecho("\n<yellow>[bulk-buy]<reset> Hold is full\n")
        end
        f2t_bulk_buy_finish()
    elseif F2T_BULK_STATE.remaining > 0 then
        -- Continue buying
        f2t_bulk_buy_next()
    else
        -- Done with requested amount
        f2t_bulk_buy_finish()
    end
end

-- Handle buy error (stop the bulk operation)
function f2t_bulk_buy_error(reason)
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "buy" then
        return
    end

    f2t_debug_log("[bulk-buy] ERROR: %s", reason)

    -- Only show user feedback in user mode
    if not F2T_BULK_STATE.callback then
        cecho(string.format("\n<red>[bulk-buy]<reset> %s\n", reason))
    end

    f2t_bulk_buy_finish()
end

-- Finish the bulk buy operation
function f2t_bulk_buy_finish()
    if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= "buy" then
        return
    end

    local bought = F2T_BULK_STATE.total - F2T_BULK_STATE.remaining
    local tons = bought * 75
    local commodity = F2T_BULK_STATE.commodity
    local callback = F2T_BULK_STATE.callback

    f2t_debug_log("[bulk-buy] Finishing: bought %d lots of %s (%d tons)", bought, commodity, tons)

    -- Reset state BEFORE callback to prevent re-entrant state corruption
    -- (callback may synchronously start a new bulk operation)
    F2T_BULK_STATE.active = false
    F2T_BULK_STATE.command = nil
    F2T_BULK_STATE.callback = nil

    -- User mode: show formatted output
    if not callback then
        cecho(string.format("\n<green>[bulk-buy]<reset> Complete: Bought %d lots of %s (%d tons)\n",
            bought, commodity, tons))

    -- Programmatic mode: call callback with data
    else
        local status = bought > 0 and "success" or "failed"
        callback(commodity, bought, status, nil)
    end
end