-- Planet Owner Discovery
-- System scanning and remote exchange capture for PO hauling mode
-- Uses map component's di system capture and po component's exchange capture
-- All scanning is done remotely (no navigation required)

-- ========================================
-- System Scanning
-- ========================================

--- Scan current system for planet names using map component's di system parser
--- On first scan, verifies system ownership via GMCP
--- @param callback function Called with (planet_names, planets_without_exchange) when complete
function f2t_po_hauling_scan_system(callback)
    -- Use stored system name on subsequent scans (ship may be in a different system)
    local system_name = F2T_HAULING_STATE.po_current_system
    if not system_name then
        -- First scan: get system from GMCP and verify ownership
        system_name = gmcp.room and gmcp.room.info and gmcp.room.info.system
        if not system_name then
            cecho("\n<red>[hauling]<reset> Cannot determine current system\n")
            callback(nil, nil)
            return
        end

        -- Verify ownership: system and all planets share one owner
        local owner = gmcp.room and gmcp.room.info and gmcp.room.info.owner
        local player_name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name

        if not owner or not player_name or owner ~= player_name then
            cecho(string.format("\n<red>[hauling]<reset> Current system <cyan>%s<reset> is not owned by you (owner: %s)\n",
                system_name, owner or "unknown"))
            callback(nil, nil)
            return
        end

        F2T_HAULING_STATE.po_current_system = system_name
        f2t_debug_log("[hauling/po] System %s owned by %s, confirmed", system_name, player_name)
    end

    f2t_debug_log("[hauling/po] Scanning system: %s", system_name)
    cecho(string.format("\n<green>[hauling]<reset> Scanning system <cyan>%s<reset> for planets...\n", system_name))

    f2t_map_di_system_capture_start(system_name, function(planet_names, planets_without_exchange)
        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        if not planet_names or #planet_names == 0 then
            cecho("\n<red>[hauling]<reset> No planets found in system\n")
            callback(nil, nil)
            return
        end

        -- Filter out planets without exchanges
        local planets_with_exchange = {}
        for _, planet_name in ipairs(planet_names) do
            if not planets_without_exchange[planet_name] then
                table.insert(planets_with_exchange, planet_name)
            else
                f2t_debug_log("[hauling/po] Skipping planet without exchange: %s", planet_name)
            end
        end

        f2t_debug_log("[hauling/po] Found %d planets with exchanges in %s",
            #planets_with_exchange, system_name)

        callback(planets_with_exchange, planets_without_exchange)
    end)
end

-- ========================================
-- Remote Exchange Scanning
-- ========================================

--- Capture exchange data remotely for all planets (no navigation needed)
--- Uses "display exchange <planet>" which works from any location
--- @param planet_names table Array of planet names to scan
--- @param callback function Called with (owned_planets, planet_exchange_data) when complete
function f2t_po_hauling_scan_exchanges(planet_names, callback)
    if not planet_names or #planet_names == 0 then
        callback({}, {})
        return
    end

    f2t_debug_log("[hauling/po] Remote scanning exchanges for %d planets", #planet_names)
    cecho(string.format("\n<green>[hauling]<reset> Capturing exchange data for %d planets...\n", #planet_names))

    local scan_data = {}
    local owned_planets = {}
    local scan_index = 0
    local total = #planet_names

    local function scan_next()
        scan_index = scan_index + 1

        if scan_index > total then
            f2t_debug_log("[hauling/po] Exchange scan complete: %d planets captured", #owned_planets)
            F2T_HAULING_STATE.po_owned_planets = owned_planets
            F2T_HAULING_STATE.po_planet_exchange_data = scan_data
            callback(owned_planets, scan_data)
            return
        end

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        local planet = planet_names[scan_index]
        f2t_debug_log("[hauling/po] Scanning %s (%d/%d)", planet, scan_index, total)

        local started = f2t_po_capture_exchange(planet, function(exchange_data)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end

            f2t_debug_log("[hauling/po] Captured %d commodities for %s", #exchange_data, planet)
            scan_data[planet] = exchange_data
            table.insert(owned_planets, planet)

            tempTimer(0.3, function()
                scan_next()
            end)
        end)

        if not started then
            cecho(string.format("\n<yellow>[hauling]<reset> Exchange capture busy, skipping %s\n", planet))
            f2t_debug_log("[hauling/po] Exchange capture busy, skipping %s", planet)
            tempTimer(0.5, function()
                scan_next()
            end)
        end
    end

    scan_next()
end

-- ========================================
-- Remote Exchange Re-scan
-- ========================================

--- Re-scan exchanges remotely for all owned planets (no navigation needed)
--- Used during deficit re-check after selling cargo
--- @param owned_planets table Array of owned planet names
--- @param callback function Called with (planet_exchange_data) when complete
function f2t_po_hauling_rescan_exchanges(owned_planets, callback)
    if not owned_planets or #owned_planets == 0 then
        callback({})
        return
    end

    f2t_debug_log("[hauling/po] Remote re-scan of %d owned planets", #owned_planets)

    local scan_data = {}
    local scan_index = 0
    local total = #owned_planets

    -- Sequential remote capture (po capture is single-threaded)
    local function scan_next()
        scan_index = scan_index + 1

        if scan_index > total then
            f2t_debug_log("[hauling/po] Remote re-scan complete")
            callback(scan_data)
            return
        end

        if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
            return
        end

        local planet = owned_planets[scan_index]
        f2t_debug_log("[hauling/po] Remote scanning %s (%d/%d)", planet, scan_index, total)

        local started = f2t_po_capture_exchange(planet, function(exchange_data)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end

            f2t_debug_log("[hauling/po] Remote captured %d commodities for %s",
                #exchange_data, planet)
            scan_data[planet] = exchange_data

            -- Brief delay between captures
            tempTimer(0.3, function()
                scan_next()
            end)
        end)

        if not started then
            cecho(string.format("\n<yellow>[hauling]<reset> Exchange capture busy, skipping rescan of %s\n", planet))
            f2t_debug_log("[hauling/po] Exchange capture busy during rescan, skipping %s", planet)
            -- Use stale data for this planet if available
            if F2T_HAULING_STATE.po_planet_exchange_data[planet] then
                scan_data[planet] = F2T_HAULING_STATE.po_planet_exchange_data[planet]
                f2t_debug_log("[hauling/po] Using stale exchange data for %s", planet)
            end
            tempTimer(0.5, function()
                scan_next()
            end)
        end
    end

    scan_next()
end

f2t_debug_log("[hauling/po] Discovery module loaded")
