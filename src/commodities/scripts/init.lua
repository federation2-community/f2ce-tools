-- Initialize commodities component
-- Provides commodity price checking and analysis tools

-- Initialize settings
f2t_settings = f2t_settings or {}
f2t_settings.commodities = f2t_settings.commodities or {}

-- Register settings
f2t_settings_register("commodities", "results_count", {
    description = "Number of top exchanges to show in price tables",
    default = 5,
    min = 1, max = 20,
    validator = function(value)
        local num = tonumber(value)
        if not num then
            return false, "Value must be a number"
        end
        if num < 1 or num > 20 then
            return false, "Value must be between 1 and 20"
        end
        return true
    end
})

-- Global state for price capture
F2T_PRICE_CAPTURE_ACTIVE = false
F2T_PRICE_CAPTURE_DATA = {}
F2T_PRICE_CURRENT_COMMODITY = nil
F2T_PRICE_CALLBACK = nil

-- Register help for price command
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

-- Global state for bulk command operations
F2T_BULK_STATE = {
    active = false,      -- Whether a bulk operation is in progress
    command = nil,       -- "buy" or "sell"
    commodity = nil,     -- Commodity name
    remaining = 0,       -- Number of operations remaining
    total = 0,           -- Total operations requested
    callback = nil,      -- Callback function for programmatic mode

    -- Sell tracking (for margin calculation)
    total_cost = 0,      -- Total cost of cargo being sold
    total_revenue = 0,   -- Total revenue from sales
    lots_sold = 0        -- Number of lots sold (for averaging)
}

-- Register help for bulk buy command
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

-- Register help for bulk sell command
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
