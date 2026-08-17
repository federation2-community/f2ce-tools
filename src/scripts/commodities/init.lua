-- f2ce-tools commodities — initialization
--
-- Price checking/analysis (price, pr) and bulk trading (bb, bs).  No enabled
-- toggle: the commands are the entry points, and the capture triggers self-gate
-- on F2T_PRICE_CAPTURE_ACTIVE / F2T_BULK_STATE.active.
--
-- Provides the price/bulk functions that hauling's exchange and PO modes depend
-- on (f2t_price_get_all_data, f2t_bulk_buy_start, f2t_bulk_sell_start, etc.).

-- ── Settings ──────────────────────────────────────────────────────────────────
-- Legacy carried a `validator`; the new settings layer enforces min/max via the
-- widget, so it is dropped.

f2t_settings_register("commodities", "results_count", {
    tab         = "F2CE-Tools/Misc",
    order       = 4,
    label       = "Results count",
    description = "Number of top exchanges to show in price tables",
    default     = 5,
    min = 1, max = 20,
})

-- ── Price capture state ───────────────────────────────────────────────────────
F2T_PRICE_CAPTURE_ACTIVE   = false
F2T_PRICE_CAPTURE_DATA     = {}
F2T_PRICE_CURRENT_COMMODITY = nil
F2T_PRICE_CALLBACK         = nil

-- ── Bulk operation state ──────────────────────────────────────────────────────
F2T_BULK_STATE = {
    active    = false,   -- Whether a bulk operation is in progress
    command   = nil,     -- "buy" or "sell"
    commodity = nil,     -- Commodity name
    remaining = 0,       -- Number of operations remaining
    total     = 0,       -- Total operations requested
    callback  = nil,     -- Callback function for programmatic mode

    -- Sell tracking (for margin calculation)
    total_cost    = 0,   -- Total cost of cargo being sold
    total_revenue = 0,   -- Total revenue from sales
    lots_sold     = 0,   -- Number of lots sold (for averaging)

    watchdogTimerId = nil,  -- Timer guarding against an unanswered buy/sell command
}

-- ── Bulk operation watchdog ───────────────────────────────────────────────────
-- A bulk operation only advances when a response trigger fires, so any reply the
-- triggers do not recognise would otherwise stall the caller (and any hauling
-- state machine driving it) forever. Fail the operation instead.
F2T_BULK_WATCHDOG_SECONDS = 15

function f2t_bulk_watchdog_stop()
    if F2T_BULK_STATE.watchdogTimerId then
        killTimer(F2T_BULK_STATE.watchdogTimerId)
        F2T_BULK_STATE.watchdogTimerId = nil
    end
end

function f2t_bulk_watchdog_start()
    f2t_bulk_watchdog_stop()

    local command = F2T_BULK_STATE.command
    F2T_BULK_STATE.watchdogTimerId = tempTimer(F2T_BULK_WATCHDOG_SECONDS, function()
        F2T_BULK_STATE.watchdogTimerId = nil
        if not F2T_BULK_STATE.active or F2T_BULK_STATE.command ~= command then
            return
        end

        local reason = string.format("No recognised response to '%s %s' after %d seconds",
            command, string.lower(F2T_BULK_STATE.commodity or "?"), F2T_BULK_WATCHDOG_SECONDS)
        f2t_debug_log("[bulk] Watchdog fired: %s", reason)
        cecho(string.format("\n<yellow>[bulk-%s]<reset> %s, aborting\n", command, reason))

        if command == "buy" then
            f2t_bulk_buy_error(reason)
        else
            f2t_bulk_sell_error(reason)
        end
    end)
end

-- ── Help ──────────────────────────────────────────────────────────────────────
f2t_register_help("price", {
    description = "Check commodity prices and find profitable trading opportunities",
    usage = {
        {cmd = "price <commodity>", desc = "Show top buy/sell locations for specific commodity"},
        {cmd = "pr <commodity>", desc = "Shorthand for price command"},
        {cmd = "", desc = ""},
        {cmd = "price all", desc = "Analyze all commodities, sorted by profitability"},
        {cmd = "", desc = ""},
        {cmd = "price settings", desc = "List all commodities settings"},
        {cmd = "price settings set <name> <value>", desc = "Change a setting (e.g., results_count)"}
    },
    examples = {
        "price alloys                             # Check alloys prices",
        "pr nanofabrics                           # Check nanofabrics (shorthand)",
        "",
        "price all                                # Find most profitable commodities",
        "",
        "price settings set results_count 10      # Show top 10 exchanges instead of 5"
    }
})

f2t_register_help("bb", {
    description = "Bulk buy commodities at exchanges",
    usage = {
        {cmd = "bb <commodity> [count]", desc = "Buy commodity in bulk"},
        {cmd = "bb <commodity>", desc = "Buy all available cargo space"}
    },
    examples = {
        "bb alloys       # Buy alloys until cargo full",
        "bb alloys 5     # Buy exactly 5 lots of alloys",
        "bb grain 10     # Buy 10 lots of grain"
    }
})

f2t_register_help("bs", {
    description = "Bulk sell commodities at exchanges",
    usage = {
        {cmd = "bs", desc = "Sell entire cargo hold"},
        {cmd = "bs <commodity>", desc = "Sell all lots of specific commodity"},
        {cmd = "bs <commodity> <count>", desc = "Sell specific number of lots"}
    },
    examples = {
        "bs              # Sell everything in cargo",
        "bs alloys       # Sell all alloys lots",
        "bs grain 5      # Sell 5 lots of grain"
    }
})

f2t_debug_log("[commodities] Component initialized")