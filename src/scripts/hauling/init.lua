-- Automated, rank-adaptive hauling. Owns the global F2T_HAULING_STATE table
-- and registers hauling's settings into the Muxlet settings UI
-- (F2CE-Tools/Hauling tab).
--
-- No "enabled" toggle: inert until `haul start`, resets on `haul stop` /
-- `haul terminate`.
--
-- Strategy by rank (see mode_detection.lua; hauling/mode picks among them):
--   Commander/Captain        -> ac: Armstrong Cuthbert jobs (standalone)
--   Adventurer/Adventuress   -> akaturi: Akaturi contracts (standalone)
--   Merchant...Manufacturer  -> exchange: Exchange trading (needs commodities module)
--   Financier                -> none: Financiers may not trade on the exchanges
--   Founder+                 -> planet / deficit: Planet Owner trading, or exchange

F2T_HAULING_STATE = {
    active = false,
    paused = false,
    pause_requested = false, -- Deferred pause: set by user, converted to paused at next phase boundary
    paused_room_id = nil, -- Room ID where hauling was paused (for location validation on resume)
    stopping = false,     -- Graceful stop requested (finish current cycle)
    mode = nil,           -- Current hauling mode: "ac", "akaturi", "exchange", "po"
    strategy = nil,       -- Strategy of the current or last session (see F2T_HAUL_STRATEGIES); kept after stop
    po_deficit_only = false, -- PO mode skips excess selling (the "deficit" strategy)
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
    -- Job state (accepted/collected/delivered) is read live from
    -- gmcp.jobs.board / gmcp.char.job -- these flags only guard against
    -- resending a command while waiting for the GMCP confirmation.
    ac_job = nil,                   -- Currently selected job (raw gmcp.jobs.board entry, or nil)
    ac_accept_sent = false,         -- Accept command sent (prevent duplicates)
    ac_collect_sent = false,        -- Collect command sent (prevent duplicates)
    ac_deliver_sent = false,        -- Deliver command sent (prevent duplicates)
    ac_cash_before_deliver = nil,   -- Cash snapshot taken right before "deliver", to compute actual payment
    ac_completing = false,          -- Job-complete accounting is running (guards against double-counting)
    ac_50_milestone_shown = false,  -- Whether 50 credit message shown

    -- Akaturi (Adventurer rank); the contract itself is F2T_AKATURI_CONTRACT
    akaturi_take_attempts = 0,       -- ak sent without a contract arriving
    akaturi_room_waits = 0,          -- Waits for the contract's room text
    akaturi_promotion_noted = false, -- Promotion-ready message shown this session
    akaturi_start_points = 0,        -- Credits at haul start; below 25 means stop at 25
    paused_for_death = false,        -- Paused by death recovery; resumes on f2tDeathRecovered

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
    po_last_queue = {},              -- Job queue of the last PO session, kept after stop for display
    po_last_planets = {},            -- Owned planets of the last PO session, kept after stop for display

    -- Cycle pause tracking
    cycle_pause_timer_id = nil,      -- Timer ID for cycle pause (so we can kill it on stop)
    cycle_pause_end_time = nil,      -- os.time() when current cycle pause should end (for resume)
}

-- ── Settings (registered into the Muxlet settings UI) ─────────────────────────
-- Legacy registrations carried `validator` closures; the new settings layer
-- constrains values through the widget (min/max/choices) and ignores validator,
-- so they are dropped here.

f2t_settings_register("hauling", "mode", {
    tab         = "F2CE-Tools/Hauling",
    label       = "Mode",
    description = "What 'haul start' runs: auto (rank default), ac, akaturi, exchange, " ..
        "planet (Founder+: deficits and excesses) or deficit (Founder+: deficits only)",
    default     = "auto",
    choices     = {"auto", "ac", "akaturi", "exchange", "planet", "deficit"},
})

f2t_settings_register("hauling", "ac_priority", {
    label       = "AC job priority",
    description = "Among the board jobs paying the most hauling credits, which AC hauling takes " ..
        "next: shortest (pickup nearest where the last job was delivered) or return (most pay)",
    default     = "shortest",
    choices     = {"shortest", "return"},
})

f2t_settings_register("hauling", "margin_threshold", {
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

-- Planet Owner strategy tuning lives in the po namespace so it shows on the
-- Planet Owner tab instead of to every rank on the Hauling tab.
f2t_settings_register("po", "haul_deficit_threshold", {
    tab         = "F2CE-Tools/Planet Owner",
    label       = "Haul deficit threshold",
    description = "Planet hauling supplies a commodity once its stock is at or below this level",
    default     = -525,
    min = -525, max = -75,
})

f2t_settings_register("po", "haul_excess_threshold", {
    tab         = "F2CE-Tools/Planet Owner",
    label       = "Haul excess threshold",
    description = "Planet hauling sells off a commodity once its stock is at or above this level",
    default     = 20000,
    min = 750, max = 20000,
})

f2t_settings_register("po", "haul_prefer_owned_sources", {
    tab         = "F2CE-Tools/Planet Owner",
    label       = "Haul from owned planets first",
    description = "Planet hauling sources deficits from your own planets first; " ..
        "off = buy wherever is cheapest in the cartel",
    default     = true,
})

f2t_settings_register("po", "haul_min_source_stock", {
    tab         = "F2CE-Tools/Planet Owner",
    label       = "Haul min source stock (tons)",
    description = "Planet hauling skips sources with fewer tons for sale than this (0 = any that can fill a lot)",
    default     = 0,
    min = 0, max = 20000,
})

f2t_settings_register("po", "haul_max_resource_attempts", {
    tab         = "F2CE-Tools/Planet Owner",
    label       = "Haul re-source attempts",
    description = "Alternative sources planet hauling tries when a deficit buy gets nothing, before skipping the job",
    default     = 2,
    min = 0, max = 10,
})

f2t_settings_register("po", "haul_max_sell_attempts", {
    tab         = "F2CE-Tools/Planet Owner",
    label       = "Haul sell attempts",
    description = "Sell locations planet hauling tries before jettisoning excess cargo",
    default     = 3,
    min = 1, max = 10,
})

local RELOCATED_PO_SETTINGS = {
    po_deficit_threshold     = "haul_deficit_threshold",
    po_excess_threshold      = "haul_excess_threshold",
    po_prefer_owned_sources  = "haul_prefer_owned_sources",
    po_min_source_stock      = "haul_min_source_stock",
    po_max_resource_attempts = "haul_max_resource_attempts",
    po_max_sell_attempts     = "haul_max_sell_attempts",
}

-- Retired hauling keys are carried over once, then dropped so they cannot
-- shadow a later change: po_mode ("both"/"deficit") becomes hauling/mode, and
-- the PO tuning keys move to the po namespace.
local function migrateRetiredSettings()
    local data = Mux and Mux.settings and Mux.settings._data
    local stored = data and data.hauling
    if not stored then return end
    local changed = false

    if stored.po_mode ~= nil then
        if stored.po_mode == "deficit" and stored.mode == nil
            and not Mux.settings.set("hauling", "mode", "deficit") then
            return
        end
        stored.po_mode = nil
        changed = true
    end

    for oldKey, newKey in pairs(RELOCATED_PO_SETTINGS) do
        if stored[oldKey] ~= nil then
            data.po = data.po or {}
            if data.po[newKey] == nil then data.po[newKey] = stored[oldKey] end
            stored[oldKey] = nil
            changed = true
        end
    end

    if changed then Mux.settings.save() end
end

-- Strip and status displays follow a mode change made from any surface.
-- Re-hooked on every muxletReady because a Muxlet reload clears its listeners.
local function hookModeSetting()
    if not (Mux and Mux.settings and Mux.settings.onChange) then return end
    Mux.settings.onChange("hauling", "mode", function()
        raiseEvent("f2tHaulingStatusChanged")
    end)
end

registerAnonymousEventHandler("muxletReady", function()
    migrateRetiredSettings()
    hookModeSetting()
end)
if Mux and Mux._ready then
    migrateRetiredSettings()
    hookModeSetting()
end

f2t_debug_log("[hauling] Component initialized")