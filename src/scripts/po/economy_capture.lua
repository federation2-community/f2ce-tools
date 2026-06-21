-- Capture control for po data commands
-- Provides independent exchange and production capture functions
-- Each can be used standalone or chained together (as po economy does)

-- ========================================
-- Independent Capture Functions
-- ========================================

--- Capture exchange data for a planet
--- Sends "display exchange [planet]" and parses the output
--- @param planet string|nil Planet name (nil = current planet)
--- @param callback function Called with parsed exchange data array on completion
--- @return boolean True if capture started, false if busy
function f2t_po_capture_exchange(planet, callback)
    if f2t_po.phase ~= "idle" then
        cecho("\n<red>[po]<reset> A capture is already in progress\n")
        return false
    end

    f2t_po_reset()
    f2t_po.phase = "capturing_exchange"
    f2t_po.planet = planet
    f2t_po.callback = callback

    f2t_debug_log("[po] Starting exchange capture for planet: %s", tostring(planet))

    local cmd = "display exchange"
    if planet then
        cmd = string.format("display exchange %s", planet)
    end
    send(cmd, false)  -- false suppresses command echo

    -- Safety timer in case no output arrives (network lag, unexpected state)
    f2t_po_capture_reset_timer()

    return true
end

--- Capture production data for a planet
--- Sends "display production [group] [planet]" and parses the output
--- @param planet string|nil Planet name (nil = current planet)
--- @param callback function Called with parsed production data table on completion
--- @param group string|nil Commodity group (default "all" when planet specified)
--- @return boolean True if capture started, false if busy
function f2t_po_capture_production(planet, callback, group)
    if f2t_po.phase ~= "idle" then
        cecho("\n<red>[po]<reset> A capture is already in progress\n")
        return false
    end

    f2t_po_reset()
    f2t_po.phase = "capturing_production"
    f2t_po.planet = planet
    f2t_po.callback = callback

    f2t_debug_log("[po] Starting production capture for planet: %s", tostring(planet))

    local cmd = "display production"
    if planet then
        -- Game requires commodity group before planet name
        local prod_group = group or "all"
        cmd = string.format("display production %s %s", prod_group, planet)
    end
    send(cmd, false)  -- false suppresses command echo

    -- Start timer (production has no end marker, uses silence timeout)
    f2t_po_capture_reset_timer()

    return true
end

-- ========================================
-- Timer Management
-- ========================================

--- Reset the capture timer (rolling 0.5s timeout)
function f2t_po_capture_reset_timer()
    if f2t_po.timer_id then
        killTimer(f2t_po.timer_id)
    end

    f2t_po.timer_id = tempTimer(0.5, function()
        f2t_po_capture_timer_expired()
    end)
end

--- Called when capture timer expires (0.5s silence)
function f2t_po_capture_timer_expired()
    f2t_po.timer_id = nil

    if f2t_po.phase == "capturing_production" then
        f2t_debug_log("[po] Production capture complete (%d lines)", #f2t_po.capture_buffer)
        local parsed = f2t_po_parse_production_buffer(f2t_po.capture_buffer)
        local callback = f2t_po.callback
        f2t_po_reset()
        if callback then
            callback(parsed)
        end
    elseif f2t_po.phase == "capturing_exchange" then
        -- Exchange timed out without seeing summary line
        f2t_debug_log("[po] Exchange capture timed out unexpectedly")
        f2t_po_capture_abort("Exchange data capture timed out")
    end
end

-- ========================================
-- Completion Handlers
-- ========================================

--- Called by the exchange summary trigger when exchange capture is complete
function f2t_po_capture_exchange_complete()
    if f2t_po.timer_id then
        killTimer(f2t_po.timer_id)
        f2t_po.timer_id = nil
    end

    f2t_debug_log("[po] Exchange capture complete (%d lines)", #f2t_po.capture_buffer)
    local parsed = f2t_po_parse_exchange_buffer(f2t_po.capture_buffer)
    local callback = f2t_po.callback
    f2t_po_reset()
    if callback then
        callback(parsed)
    end
end

--- Abort capture with error message
--- Calls stored callback with empty data so callers don't hang
--- @param message string Error message to display
function f2t_po_capture_abort(message)
    f2t_debug_log("[po] Aborting: %s", message)
    cecho(string.format("\n<red>[po]<reset> %s\n", message))
    local callback = f2t_po.callback
    f2t_po_reset()
    if callback then
        callback({})
    end
end

-- ========================================
-- Economy Command (Orchestrator)
-- ========================================

--- Start the po economy command
--- Chains exchange + production captures and merges results
--- @param planet string|nil Planet name (nil = current planet)
--- @param group string|nil Canonical group name filter (nil = all)
function f2t_po_economy_start(planet, group)
    -- Check before showing progress message
    if f2t_po.phase ~= "idle" then
        cecho("\n<red>[po]<reset> A capture is already in progress\n")
        return
    end

    -- Verify planet ownership via GMCP
    local owner = gmcp.room and gmcp.room.info and gmcp.room.info.owner
    local player_name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not owner or not player_name or owner ~= player_name then
        cecho(string.format("\n<red>[po]<reset> Current system is not owned by you (owner: %s)\n",
            owner or "unknown"))
        return
    end

    cecho("\n<green>[po]<reset> Gathering economy data...\n")

    -- Determine planet name for display before capture starts
    local planet_display = planet
    if not planet_display and gmcp and gmcp.room and gmcp.room.info then
        planet_display = gmcp.room.info.area or "Unknown"
    end

    f2t_debug_log("[po] Economy start: planet=%s, group=%s, display=%s",
        tostring(planet), tostring(group), tostring(planet_display))

    -- Phase 1: Capture exchange data
    local started = f2t_po_capture_exchange(planet, function(exchange_data)
        if #exchange_data == 0 then
            cecho("\n<red>[po]<reset> No exchange data captured\n")
            return
        end

        f2t_debug_log("[po] Exchange phase complete, %d commodities parsed", #exchange_data)

        -- Block new captures during the delay between exchange and production
        f2t_po.phase = "transitioning"

        -- Phase 2: Capture production data (brief delay between commands)
        tempTimer(0.3, function()
            f2t_po.phase = "idle"
            f2t_debug_log("[po] Starting production phase")
            f2t_po_capture_production(planet, function(production_data)
                f2t_debug_log("[po] Production phase complete, %d commodities parsed",
                    f2t_table_count_keys(production_data))
                -- Phase 3: Merge and display
                local merged = f2t_po_merge_economy_data(exchange_data, production_data)
                f2t_po_economy_display(planet_display or "Unknown", merged, group)
            end)
        end)
    end)

    if not started then
        return
    end
end

f2t_debug_log("[po] Economy capture module loaded")