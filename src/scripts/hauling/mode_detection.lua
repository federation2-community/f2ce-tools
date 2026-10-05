-- Hauling strategies: what `haul start` runs, which ranks may run it, and how a
-- request (command argument or the hauling/mode setting) resolves to one.
--
-- Rank defaults:
-- - Groundhog (level 1): No hauling available
-- - Commander, Captain (levels 2-3): ac
-- - Adventurer/Adventuress (level 4): akaturi
-- - Merchant to Financier (levels 5-9): exchange
-- - Founder+ (level 10+): planet (default), deficit, exchange

-- Ordered so menus list them in a stable order.
F2T_HAUL_STRATEGY_ORDER = { "ac", "akaturi", "exchange", "planet", "deficit" }

F2T_HAUL_STRATEGIES = {
    ac = {
        mode  = "ac",
        label = "AC Jobs",
        desc  = "Armstrong Cuthbert cargo jobs",
    },
    akaturi = {
        mode  = "akaturi",
        label = "Akaturi",
        desc  = "Akaturi courier contracts",
    },
    exchange = {
        mode  = "exchange",
        label = "Exchange",
        desc  = "Buy low, sell high across the cartel's exchanges",
    },
    planet = {
        mode  = "po",
        label = "Planet",
        desc  = "Supply your planets' deficits and sell off their excesses",
    },
    deficit = {
        mode        = "po",
        deficitOnly = true,
        label       = "Deficits",
        desc        = "Supply your planets' deficits only",
    },
}

-- Words accepted on the command line besides the strategy ids themselves.
local STRATEGY_ALIASES = {
    jobs     = "ac",
    ak       = "akaturi",
    trade    = "exchange",
    trading  = "exchange",
    po       = "planet",
    deficits = "deficit",
}

--- Canonical strategy id for a typed word, or nil if it names none
--- @param word string|nil
--- @return string|nil
function f2t_hauling_normalize_strategy(word)
    if not word or word == "" then return nil end
    local lowered = string.lower(word)
    if lowered == "auto" then return "auto" end
    lowered = STRATEGY_ALIASES[lowered] or lowered
    return F2T_HAUL_STRATEGIES[lowered] and lowered or nil
end

--- Strategies the given rank level may run, rank default first
--- @param rankLevel number|nil
--- @return table Array of strategy ids (empty below Commander)
function f2t_hauling_strategies_for_level(rankLevel)
    if not rankLevel or rankLevel < 2 then return {} end
    if rankLevel <= 3 then return { "ac" } end
    if rankLevel == 4 then return { "akaturi" } end
    if rankLevel <= 9 then return { "exchange" } end
    return { "planet", "deficit", "exchange" }
end

--- Strategies the current character may run, rank default first
--- @return table Array of strategy ids
function f2t_hauling_available_strategies()
    return f2t_hauling_strategies_for_level(f2t_get_rank_level(f2t_get_rank()))
end

--- Whether the current character may run a strategy
--- @param strategy string Strategy id
--- @return boolean
function f2t_hauling_strategy_available(strategy)
    for _, id in ipairs(f2t_hauling_available_strategies()) do
        if id == strategy then return true end
    end
    return false
end

--- Display label for a strategy id
--- @param strategy string|nil
--- @return string
function f2t_hauling_strategy_label(strategy)
    local def = strategy and F2T_HAUL_STRATEGIES[strategy]
    return def and def.label or "Auto"
end

--- Strategy `haul start` would run with no argument: the hauling/mode setting
--- when this rank can run it, otherwise the rank default
--- @return string|nil strategy, string|nil note Why the setting was passed over
function f2t_hauling_default_strategy()
    local available = f2t_hauling_available_strategies()
    if #available == 0 then return nil, nil end

    local setting = f2t_hauling_normalize_strategy(f2t_settings_get("hauling", "mode"))
    if not setting or setting == "auto" then return available[1], nil end
    if f2t_hauling_strategy_available(setting) then return setting, nil end

    return available[1], string.format("Mode '%s' isn't available at %s rank; using %s",
        setting, f2t_get_rank() or "your", f2t_hauling_strategy_label(available[1]))
end

--- Resolve what `haul start [requested]` should run
--- @param requested string|nil Strategy word from the command line
--- @return string|nil strategy Strategy id, nil on error
--- @return string|nil err Error message when strategy is nil, otherwise an informational note
function f2t_hauling_resolve_strategy(requested)
    local rank = f2t_get_rank()
    if not rank then
        f2t_debug_log("[hauling/mode] Cannot determine rank, no GMCP data")
        return nil, "Cannot determine your rank. Make sure you're connected to the game."
    end

    local rankLevel = f2t_get_rank_level(rank)
    if not rankLevel then
        f2t_debug_log("[hauling/mode] Unknown rank: %s", rank)
        return nil, string.format("Unknown rank: %s", rank)
    end

    if rankLevel == 1 then
        return nil, "Hauling is not available at Groundhog rank. Reach Commander rank to use Armstrong Cuthbert jobs."
    end

    if requested and requested ~= "" then
        local strategy = f2t_hauling_normalize_strategy(requested)
        if not strategy then
            return nil, string.format("Unknown hauling mode '%s'. Modes: auto, %s",
                requested, table.concat(F2T_HAUL_STRATEGY_ORDER, ", "))
        end
        if strategy ~= "auto" then
            if not f2t_hauling_strategy_available(strategy) then
                return nil, string.format("%s isn't available at %s rank. Available: %s",
                    f2t_hauling_strategy_label(strategy), rank,
                    table.concat(f2t_hauling_available_strategies(), ", "))
            end
            f2t_debug_log("[hauling/mode] Requested strategy: %s (rank %s)", strategy, rank)
            return strategy, nil
        end
        return f2t_hauling_available_strategies()[1], nil
    end

    local strategy, note = f2t_hauling_default_strategy()
    f2t_debug_log("[hauling/mode] Default strategy: %s (rank %s)", tostring(strategy), rank)
    return strategy, note
end

--- Get a user-friendly name for a hauling mode
--- @param mode string Mode identifier ("ac", "akaturi", "exchange", "po")
--- @return string Display name for the mode
function f2t_hauling_get_mode_name(mode)
    if mode == "ac" then
        return "Armstrong Cuthbert Jobs"
    elseif mode == "akaturi" then
        return "Akaturi Contracts"
    elseif mode == "exchange" then
        return "Exchange Trading"
    elseif mode == "po" then
        return "Planet Owner Trading"
    else
        return "Unknown Mode"
    end
end

--- Get the starting phase for a hauling mode
--- @param mode string Mode identifier ("ac", "akaturi", "exchange", "po")
--- @return string Phase name to start with
function f2t_hauling_get_starting_phase(mode)
    if mode == "ac" then
        return "ac_fetching_jobs"
    elseif mode == "akaturi" then
        return "akaturi_getting_job"
    elseif mode == "exchange" then
        return "analyzing"
    elseif mode == "po" then
        return "po_scanning_system"
    else
        return nil
    end
end

f2t_debug_log("[hauling/mode] Mode detection module loaded")
