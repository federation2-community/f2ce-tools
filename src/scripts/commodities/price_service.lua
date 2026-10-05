-- Remote price service: the one path every `check price` request goes through
-- (the price/pr commands, exchange and PO hauling, the Commerce > Trading panel).
--
-- Requests queue and run one at a time, so callers never read each other's
-- output. Each asks for a scope and gets the best command the player's price
-- services allow from where they stand:
--
--   service (GMCP tool)                 command                    reach
--   Remote Price Check (remote-access-cert)  check price X cartel  the cartel; refused in Sol
--   Upgrade (price-check-upgrade)       check price X              this system; not inside an exchange
--   Premium Ticker (price-check-premium) check premium X           every open planet; anywhere, any rank
--
--   cartel scope: the cartel check; in Sol the upgraded system check, else the
--                 premium ticker filtered to the current cartel
--   galaxy scope: the premium ticker, unfiltered
--
-- Capture starts on the brokers' intro line (the premium ticker has none, so it
-- starts on sending), collects the price rows, and ends on the blank line after
-- them, or after a short quiet spell if none is seen. A request with no reply is
-- retried once, then fails rather than stalling.
--
-- Results land in a timestamped cache per scope (raising f2tPriceUpdated) so any
-- view can show what any caller last saw. A full scan checks every commodity in
-- turn; callers may accept a recent scan of the same scope instead.
--
-- Callbacks always receive tables: on failure, parsed/analysis are empty and
-- err names the reason.

local TOOL_REMOTE  = "remote-access-cert"
local TOOL_UPGRADE = "price-check-upgrade"
local TOOL_PREMIUM = "price-check-premium"

local QUIET_SECONDS   = 0.5   -- capture ends this long after the last row if no blank line comes
local TIMEOUT_SECONDS = 8     -- no reply by then
local REQUEST_GAP     = 0.3   -- pause between queued requests

-- How old a scan may be and still stand in for a new one (seconds).
F2T_PRICE_SCAN_REUSE_SECONDS = 600

F2T_PRICE = {
    queue    = {},    -- pending requests
    current  = nil,   -- request awaiting or capturing its reply
    cache    = {},    -- [scope][lowercase commodity] = { commodity, scope, form, parsed, analysis, rows, at }
    scan     = nil,   -- running full scan
    lastScan = {},    -- [scope] = { results, at } of the last completed scan
}

-- ── Commodity list ────────────────────────────────────────────────────────────

local _commodities = nil

--- Every tradeable commodity from commodities.json, sorted by name
--- @return table Array of { name = ProperCase, basePrice = number }
function f2tCommodityList()
    if _commodities then return _commodities end
    local file = io.open(getMudletHomeDir() .. "/f2ce-tools/commodities.json", "r")
    if not file then return {} end
    local raw = file:read("*all")
    file:close()
    local ok, data = pcall(yajl.to_value, raw)
    if not ok or not data or not data.groups then return {} end
    local list = {}
    for _, group in ipairs(data.groups) do
        for _, c in ipairs(group.commodities) do
            list[#list + 1] = { name = c.name, basePrice = c.basePrice }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    _commodities = list
    return list
end

local function emptyResult(commodity)
    local parsed = { buy = {}, sell = {} }
    return parsed, f2t_price_analyze_commodity(commodity, parsed)
end

-- ── Routing ───────────────────────────────────────────────────────────────────

local function atExchange()
    return f2t_has_room_flag and f2t_has_room_flag("exchange") or false
end

--- Which price services the player owns
--- @return table { remote = bool, upgrade = bool, premium = bool }
function f2tPriceServices()
    local remote = f2t_has_tool(TOOL_REMOTE)
    return {
        remote  = remote,
        -- Both add-ons only work alongside the base subscription.
        upgrade = remote and f2t_has_tool(TOOL_UPGRADE),
        premium = remote and f2t_has_tool(TOOL_PREMIUM),
    }
end

--- The command form a remote check of a scope would use here, or nil and why not
--- @param scope string|nil "cartel" (default) or "galaxy"
--- @return string|nil form "cartel", "system", "premium" or "premiumCartel"
--- @return string|nil reason Player-facing reason when form is nil
function f2tPriceRemoteForm(scope)
    local services = f2tPriceServices()

    if scope == "galaxy" then
        if services.premium then return "premium", nil end
        return nil, "Galaxy-wide checks need the Premium Ticker"
    end

    if not services.remote then
        return nil, "Remote price checks need the Remote Price Check Service"
    end
    local merchant = f2t_is_rank_or_above("Merchant")

    if f2t_map_get_current_cartel() ~= "Sol" then
        if merchant then return "cartel", nil end
        if services.premium then return "premiumCartel", nil end
        return nil, "Remote price checks need Merchant rank"
    end

    if merchant and services.upgrade and not atExchange() then return "system", nil end
    if services.premium then return "premiumCartel", nil end
    if services.upgrade then
        return nil, "In Sol the upgraded check only works outside an exchange (the Premium Ticker works anywhere)"
    end
    return nil, "Cartel checks don't work in Sol: the Upgrade checks the Sol system from outside an exchange, " ..
        "the Premium Ticker from anywhere"
end

local function commandFor(form, commodity)
    local name = commodity:lower()
    if form == "system" then return "check price " .. name end
    if form == "premium" or form == "premiumCartel" then return "check premium " .. name end
    return "check price " .. name .. " cartel"
end

local function introless(form)
    return form == "premium" or form == "premiumCartel"
end

-- Systems the map places in the player's cartel, plus the current system.
local function cartelSystems()
    local systems = {}
    local here = f2t_get_current_system and f2t_get_current_system()
    if here then systems[here] = true end
    local cartel = f2t_map_get_current_cartel()
    if not cartel then return systems end
    for _, areaId in pairs(getAreaTable()) do
        if getAreaUserData(areaId, "fed2_cartel") == cartel then
            local system = getAreaUserData(areaId, "fed2_system")
            if system and system ~= "" then systems[system] = true end
        end
    end
    return systems
end

local function filterToCartel(parsed)
    local systems = cartelSystems()
    local function keep(list)
        local out = {}
        for _, e in ipairs(list) do
            if systems[e.system] then out[#out + 1] = e end
        end
        return out
    end
    return { buy = keep(parsed.buy), sell = keep(parsed.sell) }
end

-- ── Request queue ─────────────────────────────────────────────────────────────

local startNext

local function killTimers(req)
    if req.timeoutTimer then killTimer(req.timeoutTimer); req.timeoutTimer = nil end
    if req.quietTimer then killTimer(req.quietTimer); req.quietTimer = nil end
    if req.blankTrigger then killTrigger(req.blankTrigger); req.blankTrigger = nil end
end

local function rowsFrom(parsed)
    local rows = {}
    for _, e in ipairs(parsed.buy) do
        rows[#rows + 1] = { system = e.system, planet = e.planet, action = "buying",
            quantity = e.quantity, price = e.price }
    end
    for _, e in ipairs(parsed.sell) do
        rows[#rows + 1] = { system = e.system, planet = e.planet, action = "selling",
            quantity = e.quantity, price = e.price }
    end
    return rows
end

local function finish(req, parsed, analysis, err)
    killTimers(req)
    if F2T_PRICE.current == req then F2T_PRICE.current = nil end

    if not parsed then parsed, analysis = emptyResult(req.commodity) end
    if not err then
        F2T_PRICE.cache[req.scope] = F2T_PRICE.cache[req.scope] or {}
        F2T_PRICE.cache[req.scope][req.commodity:lower()] = {
            commodity = req.commodity,
            scope     = req.scope,
            form      = req.form,
            parsed    = parsed,
            analysis  = analysis,
            rows      = rowsFrom(parsed),
            at        = os.time(),
        }
        raiseEvent("f2tPriceUpdated", req.commodity, req.scope)
    end

    if req.callback and not req.cancelled then
        local ok, cbErr = pcall(req.callback, req.commodity, parsed, analysis, err)
        if not ok then f2t_debug_log("[price] callback error for %s: %s", req.commodity, tostring(cbErr)) end
    end

    tempTimer(REQUEST_GAP, function() if not F2T_PRICE.current then startNext() end end)
end

local function complete(req)
    if req.done then return end
    req.done = true
    local parsed = f2t_price_parse_data(req.lines)
    if req.form == "premiumCartel" then parsed = filterToCartel(parsed) end
    finish(req, parsed, f2t_price_analyze_commodity(req.commodity, parsed), nil)
end

local function sendRequest(req)
    req.lines, req.replied, req.done = {}, false, false
    -- The premium ticker sends rows with no intro, so its capture opens now.
    req.capturing = introless(req.form)
    req.timeoutTimer = tempTimer(TIMEOUT_SECONDS, function()
        req.timeoutTimer = nil
        if F2T_PRICE.current ~= req or req.replied then return end
        if not req.retried then
            req.retried = true
            f2t_debug_log("[price] no reply for %s, retrying", req.commodity)
            sendRequest(req)
        else
            req.done = true
            finish(req, nil, nil, "No reply from the brokers")
        end
    end)
    send(req.command, false)
end

startNext = function()
    if F2T_PRICE.current then return end
    local req = table.remove(F2T_PRICE.queue, 1)
    if not req then return end

    local form, reason = f2tPriceRemoteForm(req.scope)
    if not form then
        F2T_PRICE.current = req
        finish(req, nil, nil, reason)
        return
    end

    req.form    = form
    req.command = commandFor(form, req.commodity)
    F2T_PRICE.current = req
    f2t_debug_log("[price] sending: %s (%s)", req.command, req.owner)
    sendRequest(req)
end

--- Queue a remote price check
--- @param owner string Who asked ("hauling", "panel", "command", ...) so it can cancel its own
--- @param commodity string Commodity name (short names accepted)
--- @param callback function|nil fn(commodity, parsed, analysis, err)
--- @param scope string|nil "cartel" (default) or "galaxy"
function f2t_price_check_for(owner, commodity, callback, scope)
    local canonical = f2t_resolve_commodity and f2t_resolve_commodity(commodity) or commodity
    table.insert(F2T_PRICE.queue, {
        owner = owner, commodity = canonical, callback = callback, scope = scope or "cartel",
    })
    startNext()
end

--- Queue a cartel-scope price check on behalf of a script or command
--- @param commodity string
--- @param callback function|nil fn(commodity, parsed, analysis, err)
function f2t_price_check_commodity(commodity, callback)
    f2t_price_check_for("command", commodity, callback)
end

--- True while any price request is queued, in flight, or a scan is running
function f2tPriceServiceBusy()
    return F2T_PRICE.current ~= nil or #F2T_PRICE.queue > 0 or F2T_PRICE.scan ~= nil
end

--- Last cached result for a commodity, or nil
--- @param scope string|nil "cartel" (default) or "galaxy"
function f2tPriceCached(commodity, scope)
    local byScope = F2T_PRICE.cache[scope or "cartel"]
    return commodity and byScope and byScope[commodity:lower()] or nil
end

-- ── Capture (called from the commodities triggers) ───────────────────────────

-- Pattern triggers never fire on an empty line (Mudlet skips matching then), so
-- the blank line ending a reply is watched for with a one-line line trigger,
-- re-armed after every captured line. The quiet timer covers a reply with none.
local function armEndWatch(req)
    if req.quietTimer then killTimer(req.quietTimer) end
    req.quietTimer = tempTimer(QUIET_SECONDS, function()
        req.quietTimer = nil
        if F2T_PRICE.current == req and req.capturing then complete(req) end
    end)

    if req.blankTrigger then killTrigger(req.blankTrigger) end
    req.blankTrigger = tempLineTrigger(1, 1, function()
        req.blankTrigger = nil
        if getCurrentLine():match("^%s*$") and F2T_PRICE.current == req and req.capturing and not req.done then
            deleteLine()
            if #req.lines > 0 then complete(req) end
        end
    end)
end

local function markReplied(req)
    if req.replied then return end
    req.replied = true
    if req.timeoutTimer then killTimer(req.timeoutTimer); req.timeoutTimer = nil end
end

--- Brokers' intro line: the reply to the in-flight request has started
--- @return boolean True when the line belongs to a request (caller gags it)
function f2tPriceCaptureStart()
    local req = F2T_PRICE.current
    if not req or req.replied or req.done or introless(req.form) then return false end
    req.capturing = true
    markReplied(req)
    armEndWatch(req)
    return true
end

--- One price row
--- @return boolean True when the line was captured (caller gags it)
function f2tPriceCaptureLine(line)
    local req = F2T_PRICE.current
    if not (req and req.capturing and not req.done) then return false end
    markReplied(req)
    table.insert(req.lines, line)
    armEndWatch(req)
    return true
end

--- Any other line of a captured reply (intro continuation)
--- @return boolean True while a reply is being captured
function f2tPriceCapturing()
    local req = F2T_PRICE.current
    return req ~= nil and req.capturing and req.replied and not req.done
end

--- A refusal from the brokers or the game (no subscription, Sol, unknown commodity)
--- @return boolean True when it answered the in-flight request (caller gags it)
function f2tPriceCaptureError(line)
    local req = F2T_PRICE.current
    if not req or req.done then return false end
    req.done = true
    finish(req, nil, nil, line)
    return true
end

-- ── Full scan ─────────────────────────────────────────────────────────────────

local function scanSubscribersDone(scan, results, err)
    for _, sub in ipairs(scan.subscribers) do
        local ok, cbErr = pcall(sub.callback, results, err)
        if not ok then f2t_debug_log("[price] scan callback error: %s", tostring(cbErr)) end
    end
end

local function scanNext()
    local scan = F2T_PRICE.scan
    if not scan then return end

    scan.index = scan.index + 1
    local commodity = scan.list[scan.index]
    if not commodity then
        F2T_PRICE.scan = nil
        F2T_PRICE.lastScan[scan.scope] = { results = scan.results, at = os.time() }
        raiseEvent("f2tPriceScanFinished", #scan.results, scan.scope)
        scanSubscribersDone(scan, scan.results, nil)
        return
    end

    raiseEvent("f2tPriceScanProgress", scan.index, #scan.list, commodity, scan.scope)
    f2t_price_check_for("scan", commodity, function(_name, _parsed, analysis, err)
        if F2T_PRICE.scan ~= scan then return end
        if err then
            -- A refusal that applies to every commodity ends the scan.
            if not f2tPriceRemoteForm(scan.scope) then
                F2T_PRICE.scan = nil
                raiseEvent("f2tPriceScanFinished", #scan.results, scan.scope)
                scanSubscribersDone(scan, scan.results, err)
                return
            end
            f2t_debug_log("[price] scan skipping %s: %s", commodity, err)
        else
            table.insert(scan.results, analysis)
        end
        scanNext()
    end, scan.scope)
end

--- Last completed scan of a scope, or nil
--- @param scope string|nil "cartel" (default) or "galaxy"
--- @return table|nil { results, at }
function f2tPriceLastScan(scope)
    return F2T_PRICE.lastScan[scope or "cartel"]
end

--- Price every commodity
--- @param callback function fn(results, err): results is an array of analyses
--- @param opts table|nil { owner = string, scope = "cartel"|"galaxy",
---   maxAge = seconds a finished scan of the same scope may be reused }
--- @return boolean started, string|nil "reused" when a recent scan answered immediately
function f2t_price_get_all_data(callback, opts)
    opts = opts or {}
    local owner = opts.owner or "command"
    local scope = opts.scope or "cartel"

    local last = F2T_PRICE.lastScan[scope]
    if opts.maxAge and last and os.time() - last.at <= opts.maxAge then
        tempTimer(0, function() callback(last.results, nil) end)
        return true, "reused"
    end

    local form, reason = f2tPriceRemoteForm(scope)
    if not form then
        cecho(string.format("\n<red>[price]<reset> %s\n", reason))
        return false
    end

    if F2T_PRICE.scan then
        if F2T_PRICE.scan.scope ~= scope then
            cecho(string.format("\n<yellow>[price]<reset> A %s price scan is already running\n", F2T_PRICE.scan.scope))
            return false
        end
        table.insert(F2T_PRICE.scan.subscribers, { owner = owner, callback = callback })
        return true
    end

    local list = {}
    for _, c in ipairs(f2tCommodityList()) do list[#list + 1] = c.name end
    if #list == 0 then
        cecho("\n<red>[price]<reset> Commodity list unavailable\n")
        return false
    end

    F2T_PRICE.scan = {
        scope       = scope,
        list        = list,
        index       = 0,
        results     = {},
        subscribers = { { owner = owner, callback = callback } },
        startedAt   = os.time(),
    }
    scanNext()
    return true
end

--- Progress of the running scan, or nil
--- @return table|nil { scope, index, total, commodity, results }
function f2tPriceScanState()
    local scan = F2T_PRICE.scan
    if not scan then return nil end
    return {
        scope = scan.scope, index = scan.index, total = #scan.list,
        commodity = scan.list[scan.index], results = scan.results,
    }
end

--- Withdraw an owner's pending requests and scan subscription
--- @param owner string|nil nil withdraws everyone's
--- @return boolean True when anything was withdrawn
function f2t_price_cancel_all(owner)
    local withdrew = false

    for i = #F2T_PRICE.queue, 1, -1 do
        local req = F2T_PRICE.queue[i]
        if owner == nil or req.owner == owner then
            table.remove(F2T_PRICE.queue, i)
            withdrew = true
        end
    end
    local current = F2T_PRICE.current
    if current and (owner == nil or current.owner == owner) then
        current.cancelled = true
        withdrew = true
    end

    local scan = F2T_PRICE.scan
    if scan then
        for i = #scan.subscribers, 1, -1 do
            if owner == nil or scan.subscribers[i].owner == owner then
                table.remove(scan.subscribers, i)
                withdrew = true
            end
        end
        if #scan.subscribers == 0 then
            F2T_PRICE.scan = nil
            f2t_price_cancel_all("scan")
            raiseEvent("f2tPriceScanFinished", #scan.results, scan.scope)
        end
    end
    return withdrew
end

-- ── Console commands ──────────────────────────────────────────────────────────

--- `price <commodity> [galaxy]`
--- @param scope string|nil "cartel" (default) or "galaxy"
function f2t_price_show(commodity, scope)
    f2t_price_check_for("command", commodity, function(name, _parsed, analysis, err)
        if err then
            cecho(string.format("\n<red>[price]<reset> %s: %s\n", name, err))
            return
        end
        f2t_price_display_commodity(name, analysis)
    end, scope)
end

--- `price all [galaxy]`
--- @param scope string|nil "cartel" (default) or "galaxy"
function f2t_price_show_all(scope)
    local started = f2t_price_get_all_data(function(results, err)
        if err then cecho(string.format("\n<red>[price]<reset> Scan stopped: %s\n", err)) end
        f2t_price_display_all(results)
    end, { owner = "command", scope = scope })
    if started then
        cecho("\n<green>[commodities]<reset> Checking prices for all commodities...\n")
        cecho("<dim_grey>This may take a moment...<reset>\n")
    end
end

f2t_debug_log("[commodities] Price service loaded")
