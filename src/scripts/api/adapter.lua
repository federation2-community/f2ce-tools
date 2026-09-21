-- Native F2CE adapter for F2CE.API.v1.
--
-- This file is the only API layer allowed to touch implementation globals.
-- Module consumers receive copied state and opaque handles from v1.lua.

local api = F2CE and F2CE.API and F2CE.API.v1
if not api then return end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[clone(key, seen)] = clone(item, seen) end
    return result
end

local repeating_timers = {}

local adapter = {
    name = "f2ce-native",
    compatibility = "F2CE-Tools 3.3.x (legacy fallback >= 3.2.5)",
}

function adapter.f2ceVersion()
    if F2T_VERSION and F2T_VERSION ~= "unknown" then return F2T_VERSION end
    if type(getPackageInfo) == "function" then
        local info = getPackageInfo("f2ce-tools")
        if type(info) == "table" and info.version then return info.version end
    end
    return "unknown"
end

function adapter.registerEvent(event_name, callback)
    if type(registerAnonymousEventHandler) ~= "function" then return nil end
    local ok, id = pcall(registerAnonymousEventHandler, event_name, callback)
    if ok then return id end
    return nil
end

function adapter.unregisterEvent(id)
    if id and type(killAnonymousEventHandler) == "function" then pcall(killAnonymousEventHandler, id) end
end

function adapter.timer(delay, callback, repeating)
    if type(tempTimer) ~= "function" then return nil end
    if not repeating then return tempTimer(delay, callback) end
    local token = { active = true, timer_id = nil }
    local function tick()
        if not token.active then return end
        callback()
        if token.active then token.timer_id = tempTimer(delay, tick) end
    end
    token.timer_id = tempTimer(delay, tick)
    repeating_timers[token] = true
    return token
end

function adapter.cancelTimer(id)
    if type(id) == "table" and repeating_timers[id] then
        id.active = false
        repeating_timers[id] = nil
        if id.timer_id and type(killTimer) == "function" then pcall(killTimer, id.timer_id) end
        return
    end
    if id and type(killTimer) == "function" then pcall(killTimer, id) end
end

function adapter.muxletContentAvailable()
    return type(Mux) == "table" and type(Mux.registerContent) == "function"
end

function adapter.sendCommand(command, options)
    if type(send) ~= "function" then return false end
    send(command, options and options.echo == true)
    return true
end

function adapter.gmcpSnapshot(path)
    local node = gmcp
    for _, key in ipairs(path or {}) do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return clone(node)
end

function adapter.observeLine(callback)
    if type(tempRegexTrigger) ~= "function" then return nil end
    return tempRegexTrigger("^.*$", function() callback(line or "") end)
end
function adapter.unobserveLine(id)
    if id and type(killTrigger) == "function" then killTrigger(id) end
end
function adapter.parseFactory(lines, number)
    if type(f2t_factory_parse_display) ~= "function" then return nil, "native factory parser unavailable" end
    return f2t_factory_parse_display(lines, number)
end
function adapter.parseDepot(lines, planet)
    if type(f2t_depot_parse_display) ~= "function" then return nil, "native depot parser unavailable" end
    return f2t_depot_parse_display(lines, planet)
end

-- Use the native capture engine, not a temporary parser replacement. The
-- callback itself is the ownership token: never reset someone else's capture.
local exchange_callbacks = {}
function adapter.exchangeCapture(kind, planet, callback)
    local capture = kind == "exchange" and f2t_po_capture_exchange or f2t_po_capture_production
    if type(capture) ~= "function" or type(f2t_po_reset) ~= "function" then
        return false, "native PO capture service is unavailable"
    end
    local wrapper = function(rows, failure, metadata)
        exchange_callbacks[callback] = nil
        if planet and (type(metadata) ~= "table" or type(metadata.planet) ~= "string"
            or metadata.planet:lower() ~= planet:lower()) then
            callback(nil, failure or "capture header did not confirm the requested planet")
        else
            callback(rows, failure)
        end
    end
    exchange_callbacks[callback] = wrapper
    local started, reason = capture(planet, wrapper)
    if not started then exchange_callbacks[callback] = nil end
    return started, reason
end

function adapter.exchangeCancel(callback)
    local wrapper = exchange_callbacks[callback]
    exchange_callbacks[callback] = nil
    if type(f2t_po) ~= "table" or f2t_po.phase == "idle" then return true end
    if not wrapper or f2t_po.callback ~= wrapper then return false, "capture ownership changed" end
    if type(f2t_po_reset) ~= "function" then return false, "capture reset is unavailable" end
    f2t_po_reset()
    return true
end

local function active(state)
    return type(state) == "table" and state.active == true
end

function adapter.nativeCommandBlocker(owned_hauling_price)
    -- Native hauling reserves "hauling" for its entire session, including
    -- stationary price analysis. Only the API's borrowed hauling-price lease
    -- may share that reservation; it never permits an in-flight movement.
    local own_reservation = owned_hauling_price == true
        and active(F2T_HAULING_STATE) and F2T_SPEEDWALK_OWNER == "hauling"
    if F2T_SPEEDWALK_OWNER ~= nil and not own_reservation then
        return { kind = "navigation_owner", owner = tostring(F2T_SPEEDWALK_OWNER) }
    end
    if F2T_SPEEDWALK_ACTIVE == true then return { kind = "speedwalk" } end
    if F2T_SPEEDWALK_WAITING_FOR_MOVE == true then return { kind = "movement_pending" } end
    if active(F2T_MAP_EXPLORE_STATE) then return { kind = "map_exploration" } end
    if active(F2T_MAP_CIRCUIT_STATE) then return { kind = "map_circuit" } end
    if active(F2T_HAULING_STATE) and not owned_hauling_price then return { kind = "hauling" } end
    if active(F2T_DEATH_STATE) then return { kind = "death_recovery" } end
    if F2T_PRICE_CAPTURE_ACTIVE == true then return { kind = "price_capture" } end
    if F2T_PRICE_CALLBACK ~= nil then return { kind = "price_request" } end
    if active(F2T_BULK_STATE) then return { kind = "bulk_trade" } end
    if active(F2T_MAP_WHEREIS_CAPTURE) then return { kind = "whereis_capture" } end
    if active(F2T_MAP_DI_SYSTEM_CAPTURE) then return { kind = "system_capture" } end
    if active(F2T_MAP_TOPOLOGY_CAPTURE) then return { kind = "topology_capture" } end
    if type(F2T_GALAXY) == "table" and F2T_GALAXY.capture_active == true then
        return { kind = "galaxy_capture" }
    end
    if type(f2t_factory) == "table" and f2t_factory.capturing == true then
        return { kind = "factory_capture" }
    end
    if type(f2t_factory) == "table" and f2t_factory.flushing == true then
        return { kind = "factory_flush" }
    end
    if type(f2t_po) == "table" and f2t_po.phase and f2t_po.phase ~= "idle" then
        return { kind = "planet_owner_capture", phase = tostring(f2t_po.phase) }
    end
    return nil
end

function adapter.navAcquireOwner(owner, on_interrupt)
    if type(f2t_map_set_nav_owner) ~= "function" then
        return false, { kind = "unavailable", operation = "f2t_map_set_nav_owner" }
    end
    local blocker = adapter.nativeCommandBlocker()
    if blocker and not (blocker.kind == "navigation_owner" and blocker.owner == tostring(owner)) then
        return false, blocker
    end
    f2t_map_set_nav_owner(owner, on_interrupt)
    if F2T_SPEEDWALK_OWNER ~= owner then
        return false, { kind = "ownership_not_acquired", owner = F2T_SPEEDWALK_OWNER }
    end
    return true
end

function adapter.navReleaseOwner(owner)
    if F2T_SPEEDWALK_OWNER == nil then return true end
    if F2T_SPEEDWALK_OWNER ~= owner then
        return false, { kind = "ownership_changed", owner = tostring(F2T_SPEEDWALK_OWNER) }
    end
    if type(f2t_map_clear_nav_owner) ~= "function" then return false end
    f2t_map_clear_nav_owner()
    return true
end

-- Retained for adapters embedding the candidate. New API code uses the
-- compare-and-release operations above so it cannot clobber another owner.
function adapter.navSetOwner(owner, on_interrupt)
    return adapter.navAcquireOwner(owner, on_interrupt)
end
function adapter.navClearOwner()
    if F2T_SPEEDWALK_OWNER == nil then return true end
    return false
end
function adapter.navigate(destination, options)
    if type(f2t_map_navigate) ~= "function" then return false, "f2t_map_navigate is unavailable" end
    -- A 3.3 pending navigation may perform several internal speedwalks. Clear
    -- the previous run before starting so API consumers never observe it as
    -- the result of this request.
    F2T_SPEEDWALK_LAST_RESULT = nil
    local result, detail = f2t_map_navigate(destination, options)
    return result, detail
end
function adapter.navPause()
    if F2T_SPEEDWALK_ACTIVE and type(f2t_map_speedwalk_pause) == "function" then
        return f2t_map_speedwalk_pause()
    end
    if active(F2T_MAP_EXPLORE_STATE) and type(f2t_map_explore_pause) == "function" then
        f2t_map_explore_pause()
        return true
    end
    return false
end
function adapter.navResume()
    if F2T_SPEEDWALK_ACTIVE and type(f2t_map_speedwalk_resume) == "function" then
        return f2t_map_speedwalk_resume()
    end
    if active(F2T_MAP_EXPLORE_STATE) and F2T_MAP_EXPLORE_STATE.paused
        and type(f2t_map_explore_resume) == "function" then
        f2t_map_explore_resume()
        return true
    end
    return false
end
function adapter.navStop()
    if type(f2t_map_navigation_cancel) == "function" then
        return f2t_map_navigation_cancel("API navigation cancelled")
    end
    return type(f2t_map_speedwalk_stop) == "function" and f2t_map_speedwalk_stop() or false
end
function adapter.navState()
    return {
        active = F2T_SPEEDWALK_ACTIVE == true,
        paused = F2T_SPEEDWALK_PAUSED == true
            or (active(F2T_MAP_EXPLORE_STATE) and F2T_MAP_EXPLORE_STATE.paused == true),
        result = F2T_SPEEDWALK_LAST_RESULT,
        owner = F2T_SPEEDWALK_OWNER,
        exploring = active(F2T_MAP_EXPLORE_STATE),
        circuit_active = active(F2T_MAP_CIRCUIT_STATE),
        destination_room_id = tonumber(F2T_SPEEDWALK_DESTINATION_ROOM_ID),
        current_step = tonumber(F2T_SPEEDWALK_CURRENT_STEP) or 0,
        total_steps = type(F2T_SPEEDWALK_DIR) == "table" and #F2T_SPEEDWALK_DIR or 0,
        interruption_pending = F2T_SPEEDWALK_CUSTOMS_PENDING == true,
        room_id = tonumber(F2T_MAP_CURRENT_ROOM_ID),
        waiting = F2T_SPEEDWALK_WAITING_FOR_MOVE,
        waiting_for_arrival = F2T_SPEEDWALK_WAITING_FOR_ARRIVAL == true,
        expected_room_id = tonumber(F2T_SPEEDWALK_EXPECTED_ROOM_ID),
        before_room_id = tonumber(F2T_SPEEDWALK_ROOM_BEFORE_MOVE),
    }
end

function adapter.navDestinationReached(destination)
    if type(f2t_map_resolve_location) ~= "function" then return false end
    local target_id = f2t_map_resolve_location(destination)
    return target_id ~= nil
        and tonumber(F2T_MAP_CURRENT_ROOM_ID) == tonumber(target_id)
end

function adapter.priceCheck(commodity, options, done)
    if type(f2t_price_check_commodity) ~= "function" then done(nil, "built-in price provider unavailable"); return false end
    f2t_price_check_commodity(commodity, function(canonical, parsed, analysis)
        if parsed == nil or analysis == nil then done(nil, "built-in price request failed"); return end
        done({ commodity = canonical or commodity, parsed = clone(parsed), analysis = clone(analysis), provider = "f2ce.builtin", scope = options and options.scope })
    end)
    return true
end

function adapter.priceCommandDescription(commodity)
    local canonical = commodity
    if type(f2t_resolve_commodity) == "function" then canonical = f2t_resolve_commodity(commodity) or commodity end
    return string.format("check price %s cartel", string.lower(tostring(canonical)))
end

function adapter.haulingStatus()
    local state = type(F2T_HAULING_STATE) == "table" and clone(F2T_HAULING_STATE) or {}
    state.active = state.active == true
    state.available = type(f2t_hauling_start) == "function"
    return state
end
adapter.haulingTopBase21 = true
adapter.haulingCustomsMax5 = true
function adapter.haulingStart(mode, rotation)
    if type(f2t_hauling_start) ~= "function" then
        return false, "f2t_hauling_start is unavailable"
    end
    if active(F2T_HAULING_STATE) then return false, "hauling is already active" end
    f2t_hauling_start(mode, rotation)
    if active(F2T_HAULING_STATE) then return true end
    return false, "native hauling start was rejected"
end
function adapter.haulingPause(immediate) if type(f2t_hauling_pause) ~= "function" then return false end; f2t_hauling_pause(immediate); return true end
function adapter.haulingResume() if type(f2t_hauling_resume) ~= "function" then return false end; f2t_hauling_resume(); return true end
function adapter.haulingStop() if type(f2t_hauling_stop) ~= "function" then return false end; f2t_hauling_stop(); return true end
function adapter.haulingTerminate() if type(f2t_hauling_terminate) ~= "function" then return false end; f2t_hauling_terminate(); return true end

function adapter.mapRoomHasFlag(room_id, flag)
    return type(f2t_map_room_has_flag) == "function" and f2t_map_room_has_flag(room_id, flag) or false
end
function adapter.mapFindRoomsWithFlag(area, flag)
    local area_id = tonumber(area)
    if not area_id and type(f2t_map_get_area_id) == "function" then area_id = f2t_map_get_area_id(area) end
    return type(f2t_map_find_all_rooms_with_flag) == "function" and clone(f2t_map_find_all_rooms_with_flag(area_id, flag)) or {}
end
function adapter.mapFindExchange(area)
    local rooms = adapter.mapFindRoomsWithFlag(area, "exchange")
    local results = {}
    for _, room_id in ipairs(rooms) do
        results[#results + 1] = {
            room_id = room_id,
            name = type(getRoomName) == "function" and getRoomName(room_id) or nil,
            area_id = type(getRoomArea) == "function" and getRoomArea(room_id) or nil,
        }
    end
    return results
end
function adapter.mapResolve(location)
    if type(f2t_map_resolve_location) ~= "function" then return nil, "resolver unavailable" end
    local room_id, err, hint = f2t_map_resolve_location(location)
    return { room_id = room_id, error = err, hint = clone(hint) }
end
function adapter.mapAreas()
    if type(getAreaTable) ~= "function" then return {} end
    local source, result = getAreaTable() or {}, {}
    for name, id in pairs(source) do result[#result + 1] = { id = id, name = name } end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end
function adapter.mapSystems()
    local result, seen = {}, {}
    local galaxy = type(F2T_GALAXY) == "table" and F2T_GALAXY or {}
    local systems = galaxy.systems or galaxy.system or {}
    for key, value in pairs(systems) do
        local name = type(value) == "table" and (value.name or key) or key
        if name and not seen[name] then result[#result + 1] = clone(value); if type(result[#result]) ~= "table" then result[#result] = { name = name } else result[#result].name = result[#result].name or name end; seen[name] = true end
    end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end
function adapter.mapReachability(from_room, to_room)
    from_room, to_room = tonumber(from_room), tonumber(to_room)
    if not from_room or not to_room or type(getPath) ~= "function" then return { reachable = false, reason = "valid room ids and getPath are required" } end
    local reachable = getPath(from_room, to_room) == true
    return { reachable = reachable, from_room = from_room, to_room = to_room, directions = reachable and clone(speedWalkDir) or {}, rooms = reachable and clone(speedWalkPath) or {} }
end

function adapter.mapRoomIdentity(room)
    if type(room) ~= "table" then return nil end
    if room.num ~= nil or room.vnum ~= nil then
        local num = tonumber(room.num or room.vnum)
        if not num or num ~= math.floor(num) or type(room.system) ~= "string" or room.system == ""
            or type(room.area) ~= "string" or room.area == "" or type(getRoomIDbyHash) ~= "function" then return nil end
        local ok, id = pcall(getRoomIDbyHash, string.format("%s.%s.%d", room.system, room.area, num))
        id = ok and tonumber(id) or nil
        return id and id > 0 and id or nil
    end
    return tonumber(room.id)
end
function adapter.setting(component, key)
    if type(f2t_settings_get) == "function" then return clone(f2t_settings_get(component, key)) end
end
function adapter.rankAtLeast(rank)
    return type(f2t_is_rank_or_above) == "function" and f2t_is_rank_or_above(rank) == true
end
function adapter.deathState()
    local state = clone(F2T_DEATH_STATE)
    return type(state) == "table" and state or nil
end
function adapter.staminaState()
    if type(F2T_STAMINA_STATE) ~= "table" then return nil end
    local state = clone(F2T_STAMINA_STATE)
    state.has_client = F2T_STAMINA_STATE.client_check_active ~= nil
    state.client_check_active, state.client_pause_callback, state.client_resume_callback = nil, nil, nil
    return state
end
function adapter.staminaOwns(callback)
    return type(F2T_STAMINA_STATE) == "table" and F2T_STAMINA_STATE.client_check_active == callback
end
function adapter.staminaRegister(config)
    return f2t_stamina_register_client(config)
end
function adapter.staminaUnregister(callback)
    if adapter.staminaOwns(callback) then
        if type(f2t_stamina_cancel_client_trip) == "function" then f2t_stamina_cancel_client_trip(callback) end
        f2t_stamina_unregister_client(); return true
    end
    return false
end
function adapter.staminaStart() f2t_stamina_start_monitoring(); return true end
function adapter.staminaCheck() f2t_stamina_check_vitals(); return true end
function adapter.consumerCapabilities()
    return {
        ["protection.stamina"] = type(f2t_stamina_register_client) == "function"
            and type(f2t_stamina_unregister_client) == "function" and type(f2t_stamina_check_vitals) == "function"
            and type(f2t_stamina_start_monitoring) == "function" and type(f2t_settings_get) == "function",
        ["protection.death"] = type(F2T_DEATH_STATE) == "table",
        ["po.discovery"] = type(f2t_map_di_system_capture_start) == "function" and type(f2t_capture_close) == "function",
        ["trading.bulk"] = type(f2t_bulk_buy_start) == "function" and type(f2t_bulk_sell_start) == "function"
            and type(f2t_bulk_buy_error) == "function" and type(f2t_bulk_sell_error) == "function",
        ["prices.analysis"] = type(f2t_price_parse_data) == "function" and type(f2t_price_get_top_exchanges) == "function"
            and type(f2t_price_calculate_average) == "function",
        ["settings.read"] = type(f2t_settings_get) == "function",
    }
end
function adapter.systemStart(system, callback) f2t_map_di_system_capture_start(system, callback); return true end
function adapter.systemCancel(callback)
    if type(F2T_MAP_DI_SYSTEM_CAPTURE) == "table" and F2T_MAP_DI_SYSTEM_CAPTURE.callback == callback then
        f2t_capture_close("di_system"); F2T_MAP_DI_SYSTEM_CAPTURE = { active = false }
    end
    return true
end
function adapter.bulkStart(kind, commodity, lots, callback)
    local fn = kind == "buy" and f2t_bulk_buy_start or f2t_bulk_sell_start
    return fn(commodity, lots, callback) ~= false
end
function adapter.bulkCancel(callback, reason)
    if type(F2T_BULK_STATE) == "table" and F2T_BULK_STATE.callback == callback and F2T_BULK_STATE.active then
        local kind = F2T_BULK_STATE.command
        if kind == "buy" then f2t_bulk_buy_error(reason) elseif kind == "sell" then f2t_bulk_sell_error(reason)
        else return false end
    end
    return true
end
function adapter.priceAnalyze(commodity, lines, count)
    count = tonumber(count) or tonumber(adapter.setting("commodities", "results_count")) or 5
    if count ~= count or count ~= math.floor(count) or count < 1 or count > 50 then return nil, "invalid price result count" end
    local parsed = f2t_price_parse_data(lines)
    if type(parsed) ~= "table" or type(parsed.buy) ~= "table" or type(parsed.sell) ~= "table"
        or (#parsed.buy == 0 and #parsed.sell == 0) then return nil, "price response contains no usable rows" end
    for _, rows in ipairs({ parsed.buy, parsed.sell }) do
        for _, row in ipairs(rows) do
            local price = type(row) == "table" and tonumber(row.price)
            if not price or price ~= price or price <= 0 or price == math.huge then return nil, "invalid price row" end
        end
    end
    local top = f2t_price_get_top_exchanges(parsed, count)
    local buy, sell = f2t_price_calculate_average(top.buy), f2t_price_calculate_average(top.sell)
    return { commodity = commodity, parsed = clone(parsed), analysis = { commodity = commodity,
        avg_buy_price = buy, avg_sell_price = sell, profit = buy - sell,
        margin = sell > 0 and ((buy - sell) / sell) * 100 or 0, result_count = count,
        top_buy = clone(top.buy), top_sell = clone(top.sell) } }
end
function adapter.priceDisplay(commodity, analysis) f2t_price_display_commodity(commodity, clone(analysis)); return true end

local function install()
    local current = F2CE and F2CE.API and F2CE.API.v1
    if current and current._install then
        current._install(adapter)
        if type(raiseEvent) == "function" then raiseEvent("f2ceApiReady") end
    end
end

-- Package scripts are evaluated before a zero-delay timer fires, so the
-- adapter observes all native F2CE functions regardless of folder ordering.
if type(tempTimer) == "function" then tempTimer(0, install) else install() end
