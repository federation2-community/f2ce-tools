-- Automated, rank-adaptive hauling. Owns the global F2T_HAULING_STATE table
-- and registers hauling's settings into the Muxlet settings UI
-- (F2CE-Tools/Hauling tab).
--
-- No "enabled" toggle: inert until `haul start`, resets on `haul stop` /
-- `haul terminate`.
--
-- Mode by rank (see mode_detection.lua):
--   Commander/Captain        -> Armstrong Cuthbert jobs (standalone)
--   Adventurer/Adventuress   -> Akaturi contracts (standalone)
--   Merchant...Financier     -> Exchange trading (needs commodities module)
--   Founder+                 -> Planet Owner trading (needs commodities module)

F2T_HAULING_STATE = {
    active = false,
    paused = false,
    pause_requested = false, -- Deferred pause: set by user, converted to paused at next phase boundary
    paused_room_id = nil, -- Room ID where hauling was paused (for location validation on resume)
    stopping = false,     -- Graceful stop requested (finish current cycle)
    mode = nil,           -- Current hauling mode: "ac", "akaturi", "exchange", "po"
    current_phase = nil,  -- Current phase in the state machine
    handler_id = nil,     -- GMCP event handler ID for current mode

    -- Commodity queue and caching
    commodity_queue = {},       -- Top 5 commodities from price all (sorted by profit)
    queue_index = 1,            -- Current position in queue
    current_commodity = nil,    -- Current commodity being traded

    -- Location tracking
    buy_location = nil,         -- {system, planet, price}
    sell_location = nil,        -- {system, planet, price}

    -- Profit tracking
    expected_profit = 0,        -- Expected profit per ton when commodity was selected
    actual_cost = 0,            -- What we actually paid per ton (our purchase price)
    margin_threshold_pct = 40,  -- Minimum profit margin % (profit/cost) to continue trading (default 40%)

    -- Per-commodity tracking
    current_commodity_stats = { -- Stats for current commodity cycle
        lots_bought = 0,
        total_cost = 0,
        lots_sold = 0,
        total_revenue = 0,
        profit = 0
    },
    commodity_total_profit = 0, -- Accumulated profit across all cycles of current commodity

    -- Overall statistics
    total_cycles = 0,           -- Total complete cycles (all commodities)
    commodity_cycles = 0,       -- Cycles for current commodity
    session_profit = 0,         -- Total profit this session
    commodity_history = {},     -- History: [{commodity, cycles, profit}, ...]

    -- Sell attempt tracking
    sell_attempts = 0,          -- Track how many exchanges we've tried to sell to

    -- Cycle pause tracking
    cycle_pause_return_location = nil,  -- Room to return to after cycle pause

    -- Armstrong Cuthbert job tracking (Commander, Captain ranks)
    ac_job = nil,                   -- Currently selected job (or nil)
    ac_job_taken = false,           -- Job was taken by someone else
    ac_cargo_collected = false,     -- Cargo collection complete
    ac_cargo_delivered = false,     -- Cargo delivery complete
    ac_collect_sent = false,        -- Collect command sent (prevent duplicates)
    ac_deliver_sent = false,        -- Deliver command sent (prevent duplicates)
    ac_collect_error = nil,         -- Collection error message
    ac_deliver_error = nil,         -- Delivery error message
    ac_deliver_waiting = false,     -- Waiting for stevedores
    ac_50_milestone_shown = false,  -- Whether 50 credit message shown
    ac_payment_amount = nil,        -- Payment received for job

    -- Akaturi contract tracking (Adventurer rank)
    akaturi_contract = {
        pickup_planet = nil,
        pickup_room = nil,
        delivery_planet = nil,
        delivery_room = nil,
        item = nil
    },
    akaturi_package_collected = false,
    akaturi_package_delivered = false,
    akaturi_pickup_error = false,
    akaturi_delivery_error = false,
    akaturi_pickup_sent = false,
    akaturi_delivery_sent = false,
    akaturi_payment_amount = nil,

    -- Planet Owner mode state (Founder+ rank)
    po_owned_planets = {},           -- Array of owned planet names (discovered during scan)
    po_current_system = nil,         -- System being operated in
    po_planet_exchange_data = {},    -- {[planet_name] = exchange_data_array}
    po_job_queue = {},               -- Array of resolved job objects
    po_job_index = 1,                -- Current position in queue
    po_current_job = nil,            -- Currently executing job
    po_ship_lots = 0,                -- Ship capacity in lots (hold.max / 75)
    po_scan_count = 0,               -- Full scan iterations completed
    po_deficit_count = 0,            -- Deficits found in last scan
    po_excess_count = 0,             -- Excesses found in last scan
    po_sell_attempts = 0,            -- Sell attempt counter for partial sell retry
    cargo_clear_attempts = 0,        -- Retry counter for sell-then-jettison in buy phase
    po_scan_planets = {},            -- Planets to scan during exchange scan
    po_deficit_cycles = 0,           -- Total deficit cycles completed this session
    po_excess_cycles = 0,            -- Total excess cycles completed this session

    -- Cycle pause tracking
    cycle_pause_timer_id = nil,      -- Timer ID for cycle pause (so we can kill it on stop)
    cycle_pause_end_time = nil,      -- os.time() when current cycle pause should end (for resume)
}

-- ── Settings (registered into the Muxlet settings UI) ─────────────────────────
-- Legacy registrations carried `validator` closures; the new settings layer
-- constrains values through the widget (min/max/choices) and ignores validator,
-- so they are dropped here.

f2t_settings_register("hauling", "margin_threshold", {
    tab         = "F2CE-Tools/Hauling",
    label       = "Margin threshold (%)",
    description = "Minimum profit margin % to continue trading a commodity",
    default     = 40,
    min = 0, max = 100,
})

f2t_settings_register("hauling", "cycle_pause", {
    label       = "Cycle pause (s)",
    description = "Seconds to pause after completing all 5 commodities (0 = no pause)",
    default     = 60,
    min = 0, max = 300,
})

f2t_settings_register("hauling", "use_safe_room", {
    label       = "Use safe room",
    description = "Return to safe room on completion, failure, or cycle pause",
    default     = false,
})

-- safe_room is owned by hauling (the only reader).  Previously lived in the
-- "shared" namespace alongside stamina settings; moved here so it gets the
-- Hauling tab and carries no orphan-namespace baggage.
f2t_settings_register("hauling", "safe_room", {
    label       = "Safe room",
    description = "Safe room location automation returns to on failure, completion, or pause",
    default     = "Sol.Earth.454",
})

f2t_settings_register("hauling", "excluded_commodities", {
    label       = "Excluded commodities",
    description = "Comma-separated list of commodities to exclude from trading",
    default     = "",
})

f2t_settings_register("hauling", "po_mode", {
    label       = "PO mode",
    description = "PO hauling mode: 'both' (deficit + excess) or 'deficit' (deficit only)",
    default     = "both",
    choices     = {"both", "deficit"},
})

f2t_settings_register("hauling", "po_deficit_threshold", {
    label       = "PO deficit threshold",
    description = "Stock level at or below which deficit hauling triggers",
    default     = -525,
    min = -525, max = -75,
})

f2t_settings_register("hauling", "po_excess_threshold", {
    label       = "PO excess threshold",
    description = "Stock level at or above which excess selling triggers",
    default     = 20000,
    min = 750, max = 20000,
})

f2t_settings_register("hauling", "po_max_sell_attempts", {
    label       = "Max sell attempts",
    description = "Maximum sell locations to try before jettisoning cargo",
    default     = 3,
    min = 1, max = 10,
})

f2t_debug_log("[hauling] Component initialized")