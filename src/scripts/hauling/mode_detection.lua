-- Hauling Mode Detection
-- Determines which hauling mode to use based on player rank

-- Mode availability by rank:
-- - Groundhog (level 1): No hauling available
-- - Commander, Captain (levels 2-3): Armstrong Cuthbert jobs
-- - Adventurer/Adventuress (level 4): Akaturi contracts
-- - Merchant to Financier (levels 5-9): Exchange trading
-- - Founder+ (level 10+): Planet Owner trading (default), Exchange trading (optional)

--- Detect which hauling mode should be used based on player rank
--- @param requested_mode string|nil Optional mode override (e.g., "exchange" to force exchange mode for Founder+)
--- @return string|nil Mode name ("ac", "akaturi", "exchange", "po") or nil if no mode available
--- @return string|nil Error message if mode cannot be determined
function f2t_hauling_detect_mode(requested_mode)
    local rank = f2t_get_rank()

    if not rank then
        f2t_debug_log("[hauling/mode] Cannot determine rank, no GMCP data")
        return nil, "Cannot determine your rank. Make sure you're connected to the game."
    end

    local rank_level = f2t_get_rank_level(rank)

    if not rank_level then
        f2t_debug_log("[hauling/mode] Unknown rank: %s", rank)
        return nil, string.format("Unknown rank: %s", rank)
    end

    f2t_debug_log("[hauling/mode] Checking mode for rank: %s (level %d), requested: %s",
        rank, rank_level, tostring(requested_mode))

    -- Groundhog (level 1) - No hauling available
    if rank_level == 1 then
        f2t_debug_log("[hauling/mode] Rank too low for hauling (Groundhog)")
        return nil, "Hauling is not available at Groundhog rank. Reach Commander rank to use Armstrong Cuthbert jobs."
    end

    -- Commander, Captain (levels 2-3) - Armstrong Cuthbert jobs
    if rank_level >= 2 and rank_level <= 3 then
        f2t_debug_log("[hauling/mode] Selected mode: ac (rank level %d)", rank_level)
        return "ac", nil
    end

    -- Adventurer/Adventuress (level 4) - Akaturi contracts
    if rank_level == 4 then
        f2t_debug_log("[hauling/mode] Selected mode: akaturi (rank level %d)", rank_level)
        return "akaturi", nil
    end

    -- Merchant to Financier (levels 5-9) - Exchange trading
    if rank_level >= 5 and rank_level <= 9 then
        f2t_debug_log("[hauling/mode] Selected mode: exchange (rank level %d)", rank_level)
        return "exchange", nil
    end

    -- Founder+ (level 10+) - Planet Owner trading (default) or Exchange trading (override)
    if rank_level >= 10 then
        if requested_mode and string.lower(requested_mode) == "exchange" then
            f2t_debug_log("[hauling/mode] Selected mode: exchange (requested override, rank level %d)", rank_level)
            return "exchange", nil
        end

        f2t_debug_log("[hauling/mode] Selected mode: po (rank level %d)", rank_level)
        return "po", nil
    end

    -- Should never reach here, but handle it anyway
    f2t_debug_log("[hauling/mode] Unexpected rank level: %d", rank_level)
    return nil, string.format("Unexpected rank level: %d", rank_level)
end

--- Get a user-friendly name for a hauling mode
--- @param mode string Mode identifier ("ac", "akaturi", "exchange")
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
--- @param mode string Mode identifier ("ac", "akaturi", "exchange")
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