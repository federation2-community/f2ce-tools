-- Commerce > Trading: a view over the price service (commodities/price_service.lua)
-- plus exchange hauling's live cycle.
--
-- Scope: Cartel (the cartel check, or in Sol the Upgrade's system check or the
-- Premium Ticker filtered to Sol) or Galaxy (the Premium Ticker). The service
-- picks the command from the price services the player owns.
--
-- Prices view: the selected commodity's most recent prices, the scope's from
-- the service's cache (whoever checked them, hauling included) or this
-- exchange's. Check queues a remote check, or with no price service, at an
-- exchange, a check of that exchange. The Exchange content's commodity names
-- open them here (f2tPriceCheckerFocus).
--
-- Scan, Results and the scope button only appear with a service that makes
-- them work; the panel rebuilds when the player's services change.
--
-- Results view: the service's full scan, the same one `price all` and exchange
-- hauling use, as a sortable table scored both ways: best single spread and
-- hauling's top-exchange average. Exchange hauling's picks are starred and
-- excluded commodities dimmed; Haul these starts hauling on that scan.
--
-- While exchange hauling runs, a row under the controls shows the commodity it
-- is trading and where; clicking it loads that commodity's prices.

local H_BAR  = 28
local H_STAT = 18
local H_RUN  = 20
local H_COL  = 20
local ROW_H  = 20
local SB_W   = 17
local CELL_PT    = 10     -- cell, dropdown and empty-state font size (pt)
local LABEL_PT   = 8      -- column header and button font size (pt)
local STATUS_PT  = 6.75   -- status strip font size (pt): 9px

-- Size comes from the label's fontSize (cells: f2tTableSetScrollbox's cellPt).
local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

-- Same vertical gradient as Galaxy Navigator's header strip, for a
-- consistent header look across content types.
local _HDR_BAR_CSS = [[
    background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1, stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e);
    border: none;
    border-bottom: 1px solid rgba(70, 75, 110, 150);
]]

local function emptyStateHtml(text)
    return string.format(
        "<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT, text)
end

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

local _COL_BAR_CSS = [[
    background-color: rgba(18, 20, 35, 200);
    border: none;
    border-bottom: 1px solid rgba(60, 65, 100, 180);
]]

local _DROP_CSS = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(210,220,240,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 4px;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 8px;
    }
    QLabel::hover {
        background-color: rgba(42,48,78,230);
        border-color: rgba(120,150,220,220);
    }
]]

-- Accent-colored action buttons: a left accent bar plus a tinted hover state,
-- distinct per action so they read apart at a glance.
local function actionBtnCss(accent, accentHover)
    return string.format([[
        QLabel {
            background-color: rgba(26,30,46,220);
            color: rgba(210,220,240,255);
            border: 1px solid rgba(72,85,128,180);
            border-left: 3px solid %s;
            border-radius: 4px;
            font-weight: bold; font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(38,44,66,235);
            border-left: 3px solid %s;
            color: white;
        }
    ]], accent, accentHover)
end

local _CHECK_BTN_CSS = actionBtnCss("#3aa0ff", "#5cb8ff")
local _SCAN_BTN_CSS  = actionBtnCss("#e0b84d", "#f0cc66")
local _VIEW_BTN_CSS  = actionBtnCss("#8a8fb0", "#b0b5d8")
local _SCOPE_BTN_CSS = actionBtnCss("#b48cff", "#c8a8ff")
local _HAUL_BTN_CSS  = actionBtnCss("#3ecf5e", "#5ce87c")

local _ITEM_CSS = [[
    QLabel {
        background-color: rgba(24,26,38,220);
        border: none; border-bottom: 1px solid rgba(255,255,255,0.05);
        font-family: "Consolas","Monaco",monospace;
        padding: 0 6px;
    }
    QLabel::hover {
        background-color: rgba(48,56,88,230);
        color: white;
    }
]]

local _RUN_ROW_CSS = [[
    QLabel {
        background-color: rgba(20, 30, 46, 230);
        border: none;
        border-bottom: 1px solid rgba(70, 90, 140, 160);
        border-left: 3px solid #7aa2ff;
        padding-left: 6px;
    }
    QLabel::hover { background-color: rgba(30, 44, 68, 240); }
]]

-- ── Shared state ──────────────────────────────────────────────────────────────

F2T_PRICE_CHECKER = {
    selectedCommodity = F2T_PRICE_CHECKER and F2T_PRICE_CHECKER.selectedCommodity or nil,
    view       = "prices",   -- "prices" or "results"
    scope      = F2T_PRICE_CHECKER and F2T_PRICE_CHECKER.scope or "cartel",   -- "cartel" or "galaxy"
    pendingFor = nil,        -- commodity whose check this panel is waiting on
    lastError  = nil,        -- reason the last Check or scan couldn't run
}

-- Per-pane state, keyed by target._gid
local instances = {}

local function atExchange()
    return f2t_has_room_flag and f2t_has_room_flag("exchange") or false
end

local function canonicalCommodityName(name)
    if not name then return name end
    for _, c in ipairs(f2tCommodityList()) do
        if c.name:lower() == name:lower() then return c.name end
    end
    return name
end

local function ageText(at)
    local secs = os.time() - at
    if secs < 60 then return "just now" end
    if secs < 3600 then return string.format("%dm ago", math.floor(secs / 60)) end
    return string.format("%dh ago", math.floor(secs / 3600))
end

-- ── Data ──────────────────────────────────────────────────────────────────────

-- The selected commodity's most recent cached prices: the scope's or this
-- exchange's, whichever was checked last.
local function shownEntry()
    local selected = F2T_PRICE_CHECKER.selectedCommodity
    if not selected then return nil end
    local scoped = f2tPriceCached(selected, F2T_PRICE_CHECKER.scope)
    local here = f2tPriceCached(selected, "exchange")
    if scoped and here then return here.at > scoped.at and here or scoped end
    return scoped or here
end

local function priceRows()
    local entry = shownEntry()
    return entry and entry.rows or {}
end

-- Which optional controls this player's price services make usable.
local function capabilities()
    local services = f2tPriceServices()
    return { scan = services.remote or services.premium, scope = services.premium }
end

-- Analyses of the running scan, else the last finished one, plus when it finished.
local function scanResults()
    local scope = F2T_PRICE_CHECKER.scope
    local running = f2tPriceScanState()
    if running and running.scope == scope then return running.results, nil end
    local last = f2tPriceLastScan(scope)
    if last then return last.results, last.at end
    return {}, nil
end

local function resultRows()
    local results = scanResults()
    local picks = {}
    -- Hauling trades within the cartel, so only a cartel scan has its picks.
    if f2t_hauling_rank_commodities and F2T_PRICE_CHECKER.scope == "cartel"
        and f2t_hauling_strategy_available and f2t_hauling_strategy_available("exchange") then
        for i, analysis in ipairs(f2t_hauling_rank_commodities(results)) do
            picks[analysis.commodity] = i
        end
    end
    local rows = {}
    for _, a in ipairs(results) do
        rows[#rows + 1] = {
            commodity = a.commodity,
            bestBuy   = a.bestBuyPrice,
            bestSell  = a.bestSellPrice,
            spread    = a.spread,
            profit    = (#a.top_buy > 0 and #a.top_sell > 0) and a.profit or nil,
            margin    = (#a.top_buy > 0 and #a.top_sell > 0) and a.margin or nil,
            pick      = picks[a.commodity],
            excluded  = f2t_hauling_commodity_excluded and f2t_hauling_commodity_excluded(a.commodity),
        }
    end
    return rows
end

-- ── Status line ───────────────────────────────────────────────────────────────

local SCOPE_LABEL = { cartel = "Cartel", galaxy = "Galaxy" }

local FORM_LABEL = {
    cartel        = "Cartel prices",
    system        = "System prices",
    premiumCartel = "Cartel (Premium)",
    premium       = "Galaxy prices",
    exchange      = "This exchange",
}

local function servicesText()
    local services = f2tPriceServices()
    local function mark(owned, name) return (owned and "✓ " or "✗ ") .. name end
    return "Price services: " .. mark(services.remote, "Remote Price Check") .. ", " ..
        mark(services.upgrade, "Upgrade") .. ", " .. mark(services.premium, "Premium Ticker")
end

-- The status strip is one short line; anything longer goes in its tooltip.
local function setError(short, detail)
    F2T_PRICE_CHECKER.lastError = short
    F2T_PRICE_CHECKER.lastErrorDetail = detail
end

--- @return string html Short status line
--- @return string tooltip Fuller explanation
local function statusHtml(checkable)
    local state = F2T_PRICE_CHECKER
    local function line(color, text)
        return string.format("<span style='color:%s;padding-left:6px;'>%s</span>", color, text)
    end

    local running = f2tPriceScanState()
    if running then
        return line("#8896c0", string.format("Scanning %d/%d — %s", running.index, running.total,
            running.commodity or "")), string.format("%s scan in progress", SCOPE_LABEL[running.scope] or "")
    end
    if state.lastError then
        return line("#c09060", state.lastError), state.lastErrorDetail or state.lastError
    end

    if state.view == "results" then
        local _, at = scanResults()
        if not at then return line("#5a6488", "No scan yet"), "Scan prices every commodity" end
        return line("#8896c0", string.format("%s scan · %s", SCOPE_LABEL[state.scope], ageText(at))),
            state.scope == "cartel" and "★ marks the commodities exchange hauling would trade" or ""
    end

    if not checkable then
        return line("#c09060", "Not at an exchange"), servicesText()
    end
    local selected = state.selectedCommodity
    if not selected then return line("#5a6488", "Pick a commodity, then Check"), servicesText() end
    if state.pendingFor == selected then return line("#8896c0", "Checking " .. selected .. "…"), "" end
    local cached = shownEntry()
    if cached then
        return line("#8896c0", string.format("%s: %s · %s", FORM_LABEL[cached.form] or "Prices", selected,
            ageText(cached.at))), servicesText()
    end
    return line("#5a6488", "No prices yet — Check"), servicesText()
end

-- ── Exchange hauling row ──────────────────────────────────────────────────────

-- Exchange hauling's current cycle, or nil when it isn't trading.
local function runRowHtml()
    local state = F2T_HAULING_STATE
    if not (state and state.active and state.mode == "exchange") then return nil end
    if not state.current_commodity then
        return string.format("<span style='%scolor:#8896c0;'>Exchange hauling: %s</span>",
            CELL_FONT, f2t_hauling_phase_label(state.current_phase) or "starting")
    end
    local icon = f2tCommodityIconPrefix and f2tCommodityIconPrefix(state.current_commodity) or ""
    local route = ""
    if state.buy_location and state.sell_location then
        route = string.format(
            " <span style='color:#cccc44;'>%s %dig</span> → <span style='color:#00cc44;'>%s %dig</span>",
            state.buy_location.planet or "?", state.buy_location.price or 0,
            state.sell_location.planet or "?", state.sell_location.price or 0)
    end
    local queue = ""
    if state.commodity_queue and #state.commodity_queue > 0 then
        queue = string.format(" <span style='color:#5a6488;'>· %d/%d · cycle %d</span>",
            state.queue_index or 1, #state.commodity_queue, (state.commodity_cycles or 0) + 1)
    end
    return string.format("<span style='%scolor:#e8ebf5;'><b>%s%s</b>%s%s</span>",
        CELL_FONT, icon, state.current_commodity, route, queue)
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function canHaulScan()
    local _, at = scanResults()
    return at ~= nil and F2T_PRICE_CHECKER.scope == "cartel"
        and f2t_hauling_strategy_available and f2t_hauling_strategy_available("exchange")
        and not (F2T_HAULING_STATE and F2T_HAULING_STATE.active)
end

local function layout(inst)
    local html = runRowHtml()
    local runH = html and inst.runH or 0
    if html then
        inst.runRow:echo(html)
        inst.runRow:show()
    else
        inst.runRow:hide()
    end

    local statusY = inst.barH + runH
    inst.status:move(nil, statusY)
    local tableTop = statusY + inst.statH
    for _, view in ipairs({ inst.prices, inst.results }) do
        view.colBar:move(nil, tableTop)
        local scrollTop = tableTop + inst.colH
        view.scroll:move(nil, scrollTop)
        view.scroll:resize(nil, "100%-" .. scrollTop .. "px")
    end
    inst.tableTop = tableTop
end

-- With no price service a check only works inside an exchange.
local function canCheckHere(caps)
    return caps.scan or atExchange()
end

local function render(inst)
    local state = F2T_PRICE_CHECKER
    local caps = capabilities()
    local checkable = canCheckHere(caps)
    if checkable then inst.checkBtn:show() else inst.checkBtn:hide() end
    if not caps.scan then state.view = "prices" end
    if not caps.scope then state.scope = "cartel" end
    local showResults = state.view == "results"

    local label = state.selectedCommodity or "Select Commodity"
    local icon = (f2tCommodityIconPrefix and state.selectedCommodity)
        and f2tCommodityIconPrefix(state.selectedCommodity) or ""
    inst.dropBtn:echo("<center>" .. icon .. label .. " ▼</center>")
    if inst.scanBtn then
        inst.scanBtn:echo(f2tPriceScanState() and "<center>■ Stop</center>" or "<center>💹 Scan</center>")
        inst.viewBtn:echo(showResults and "<center>≡ Prices</center>" or "<center>≡ Results</center>")
    end
    if inst.scopeBtn then inst.scopeBtn:echo("<center>◎ " .. SCOPE_LABEL[state.scope] .. "</center>") end

    local statusText, statusTip = statusHtml(checkable)
    inst.status:echo(statusText)
    inst.status:setToolTip(statusTip or "")
    if showResults and canHaulScan() then inst.haulBtn:show() else inst.haulBtn:hide() end

    local active, idle = inst.prices, inst.results
    if showResults then active, idle = inst.results, inst.prices end
    idle.colBar:hide(); idle.scroll:hide()
    active.colBar:show(); active.scroll:show()

    local rows = showResults and resultRows() or priceRows()
    f2tTableSetData(active.tableId, rows)
    -- Nothing to check from here: the message takes the table's place, headers included.
    local blank = not checkable and #rows == 0
    if blank then active.colBar:hide() end
    local emptyTop = inst.tableTop + (blank and 0 or inst.colH)
    inst.emptyLbl:move(nil, emptyTop)
    inst.emptyLbl:resize(nil, "100%-" .. emptyTop .. "px")
    if blank then
        inst.emptyLbl:echo(emptyStateHtml("Go to an exchange to check its prices." ..
            "<br><br>For prices across the cartel without travelling, buy the Remote Price Check Service " ..
            "from the brokers on Earth (BUY REMOTE SERVICE)."))
        inst.emptyLbl:show()
        inst.emptyLbl:raise()
    elseif #rows == 0 then
        inst.emptyLbl:echo(emptyStateHtml(showResults
            and "No scan yet. Scan checks every commodity (Remote Price Check Service)."
            or "No prices yet — pick a commodity and Check."))
        inst.emptyLbl:show()
        inst.emptyLbl:raise()
    else
        inst.emptyLbl:hide()
    end
end

local _renderTimer = nil
local function renderAll()
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.1, function()
        _renderTimer = nil
        for _, inst in pairs(instances) do pcall(render, inst) end
    end)
end

registerAnonymousEventHandler("f2tPriceUpdated", function(_, commodity)
    if commodity == F2T_PRICE_CHECKER.pendingFor then F2T_PRICE_CHECKER.pendingFor = nil end
    renderAll()
end)

-- Stepping in or out of an exchange decides whether Check works without a
-- price service; redraw only when that flips, not on every move.
local wasAtExchange = nil
registerAnonymousEventHandler("gmcp.room.info", function()
    local now = atExchange()
    if now ~= wasAtExchange then
        wasAtExchange = now
        if next(instances) then renderAll() end
    end
end)

-- Buying or letting lapse a price service changes which controls exist.
registerAnonymousEventHandler("gmcp.char.vitals.tools", function()
    local caps = capabilities()
    for _, inst in pairs(instances) do
        if inst.caps.scan ~= caps.scan or inst.caps.scope ~= caps.scope then
            f2tRebuildForTextScale(inst.target)
        end
    end
end)
registerAnonymousEventHandler("f2tPriceScanProgress", renderAll)
registerAnonymousEventHandler("f2tPriceScanFinished", renderAll)
registerAnonymousEventHandler("f2tHaulingStatusChanged", function()
    for _, inst in pairs(instances) do pcall(layout, inst) end
    renderAll()
end)

-- ── Actions ───────────────────────────────────────────────────────────────────

local function selectCommodity(name)
    F2T_PRICE_CHECKER.selectedCommodity = canonicalCommodityName(name)
    F2T_PRICE_CHECKER.view = "prices"
    F2T_PRICE_CHECKER.lastError = nil
    renderAll()
end

function f2tPriceCheckerCheck()
    local state = F2T_PRICE_CHECKER
    local selected = state.selectedCommodity
    state.view = "prices"
    state.lastError = nil
    if not selected then
        setError("Select a commodity first")
        renderAll()
        return
    end

    local form, reason = f2tPriceRemoteForm(state.scope)
    if form then
        state.pendingFor = selected
        f2t_price_check_for("panel", selected, function(_name, _parsed, _analysis, err)
            if state.pendingFor == selected then state.pendingFor = nil end
            if err then setError(selected .. ": check failed", err) end
            renderAll()
        end, state.scope)
    elseif atExchange() then
        state.pendingFor = selected
        f2t_price_check_here("panel", selected, function(_name, _parsed, _analysis, err)
            if state.pendingFor == selected then state.pendingFor = nil end
            if err then setError(selected .. ": check failed", err) end
            renderAll()
        end)
    else
        setError("No price check here", reason .. ". At an exchange, Check shows that exchange's prices.")
    end
    renderAll()
end

local function toggleScan()
    local state = F2T_PRICE_CHECKER
    state.lastError = nil
    if f2tPriceScanState() then
        f2t_price_cancel_all("panel")
    else
        local started = f2t_price_get_all_data(function(_results, err)
            if err then setError("Scan stopped", err) end
            renderAll()
        end, { owner = "panel", scope = state.scope })
        if not started then
            local _, reason = f2tPriceRemoteForm(state.scope)
            setError("Scan couldn't start", reason)
        end
    end
    state.view = "results"
    renderAll()
end

-- Visible Trading panel's target, or nil. Rule-hidden tabs (the panel or any
-- tab above it) can't be brought forward.
local function visibleTarget()
    for _, inst in pairs(instances) do
        local node, hidden = inst.target, false
        while node do
            if node._conditionHidden then hidden = true; break end
            node = node.pane
        end
        if not hidden then return inst.target end
    end
    return nil
end

--- Bring a Trading panel forward with a commodity's cartel prices
--- @param commodity string
--- @return boolean False when no Trading panel can be shown
function f2tPriceCheckerFocus(commodity)
    local target = visibleTarget()
    if not target then return false end

    F2T_PRICE_CHECKER.scope = "cartel"
    selectCommodity(commodity)
    local cached = shownEntry()
    if not cached or os.time() - cached.at > F2T_PRICE_SCAN_REUSE_SECONDS then f2tPriceCheckerCheck() end

    -- Activate the tab at each level, innermost first, up to its pane.
    local tab, host = target, target.pane
    while host do
        if host.activateTab then host:activateTab(tab.id) end
        tab, host = host, host.pane
    end
    return true
end

local function toggleScope()
    local state = F2T_PRICE_CHECKER
    state.lastError = nil
    if state.scope == "galaxy" then
        state.scope = "cartel"
    elseif f2tPriceServices().premium then
        state.scope = "galaxy"
    else
        setError("Galaxy needs the Premium Ticker", "Galaxy-wide checks need the Premium Ticker (BUY PREMIUM TICKER)")
    end
    renderAll()
end

-- ── Table columns ─────────────────────────────────────────────────────────────

local function priceCols()
    return {
        {
            key           = "system",
            label         = "System",
            sortable      = true,
            sort_value    = function(r) return r.system:lower() end,
            scrollbox_pct = 22,
            render_label  = function(v, _row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#ffffff;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Jump to " .. tostring(v))
                cell:setClickCallback(function() expandAlias("nav " .. v .. " space link") end)
            end,
        },
        {
            key           = "planet",
            label         = "Planet",
            sortable      = true,
            sort_value    = function(r) return r.planet:lower() end,
            scrollbox_pct = 24,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Go to " .. tostring(v) .. " exchange")
                cell:setClickCallback(function()
                    expandAlias("nav " .. row.planet .. " exchange")
                end)
            end,
        },
        {
            key           = "action",
            label         = "Action",
            sortable      = true,
            sort_value    = function(r) return r.action end,
            scrollbox_pct = 16,
            render_label  = function(v, row, cell)
                -- The exchange is buying → the player can SELL there, and vice versa.
                local html
                if v == "buying" then
                    html = string.format("<span style='%scolor:#00cc44;'>[SELL]</span>", CELL_FONT)
                else
                    html = string.format("<span style='%scolor:#cccc44;'>[BUY]</span>", CELL_FONT)
                end
                cell:echo(html)
                local what = v == "buying" and "Exchange is buying" or "Exchange is selling"
                local here = atExchange() and row.planet == f2t_get_current_planet()
                if not f2t_can_trade_on_exchanges() then
                    cell:setToolTip(what .. " — your rank can't trade on the exchanges")
                    cell:setClickCallback(function() end)
                elseif not here then
                    cell:setToolTip(what .. " — trade here from its exchange")
                    cell:setClickCallback(function() end)
                else
                    cell:setToolTip(what .. (v == "buying" and " — click to sell a lot here"
                        or " — click to buy a lot here"))
                    cell:setClickCallback(function()
                        local cmd = (v == "buying") and "sell " or "buy "
                        send(cmd .. (F2T_PRICE_CHECKER.selectedCommodity or ""):lower(), false)
                    end)
                end
            end,
        },
        {
            key           = "quantity",
            label         = "Qty",
            sortable      = true,
            sort_value    = function(r) return r.quantity or 0 end,
            scrollbox_pct = 14,
            render_label  = function(v, _row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#ffffff;'>%s</span>", CELL_FONT, tostring(v or "")))
            end,
        },
        {
            key           = "price",
            label         = "Price",
            sortable      = true,
            default_sort  = "asc",
            sort_value    = function(r) return r.price or 0 end,
            scrollbox_pct = 24,
            render_label  = function(v, row, cell)
                -- Highlight the best buy (lowest selling) and best sell (highest buying).
                local bestBuy, bestSell = math.huge, -1
                for _, r in ipairs(priceRows()) do
                    if r.action == "selling" and r.price < bestBuy  then bestBuy  = r.price end
                    if r.action == "buying"  and r.price > bestSell then bestSell = r.price end
                end
                local color, bold = "#ffffff", ""
                if row.action == "selling" and row.price == bestBuy then
                    color, bold = "#cccc44", "font-weight:bold;"
                elseif row.action == "buying" and row.price == bestSell then
                    color, bold = "#00cc44", "font-weight:bold;"
                end
                cell:echo(string.format(
                    "<span style='%s%scolor:%s;'>%sig</span>", CELL_FONT, bold, color, tostring(v or "")))
            end,
        },
    }
end

local function priceCell(value, dim, color)
    if not value then return string.format("<span style='%scolor:#555555;'>—</span>", CELL_FONT) end
    return string.format("<span style='%scolor:%s;'>%s</span>", CELL_FONT, dim and "#666666" or color,
        tostring(math.floor(value)))
end

local function resultCols()
    local function numberCol(key, label, pct, color, tip, extra)
        local col = {
            key           = key,
            label         = label,
            sortable      = true,
            sort_value    = function(r) return r[key] or -math.huge end,
            scrollbox_pct = pct,
            header_tooltip = tip,
            render_label  = function(v, row, cell)
                cell:echo(priceCell(v, row.excluded, type(color) == "function" and color(v) or color))
            end,
        }
        for k, val in pairs(extra or {}) do col[k] = val end
        return col
    end
    local function gainColor(v) return (v or 0) > 0 and "#00cc44" or "#ff5555" end

    return {
        {
            key           = "commodity",
            label         = "Commodity",
            sortable      = true,
            sort_value    = function(r) return r.commodity:lower() end,
            scrollbox_pct = 28,
            render_label  = function(v, row, cell)
                local icon = f2tCommodityIconPrefix and f2tCommodityIconPrefix(v) or ""
                local star = row.pick and "<span style='color:#e0b84d;'>★</span>" or "&nbsp;&nbsp;"
                cell:echo(string.format("<span style='%scolor:%s;'>%s%s%s</span>",
                    CELL_FONT, row.excluded and "#666666" or "#e6d28c", star, icon, v))
                local tip = "Show " .. v .. "'s prices"
                if row.pick then tip = tip .. " — exchange hauling would trade this (#" .. row.pick .. ")" end
                if row.excluded then tip = tip .. " — excluded from hauling" end
                cell:setToolTip(tip)
                cell:setClickCallback(function() selectCommodity(v) end)
            end,
        },
        numberCol("bestBuy", "Buy", 13, "#cccc44", "Lowest price to buy at"),
        numberCol("bestSell", "Sell", 13, "#00cc44", "Highest price to sell at"),
        numberCol("spread", "Spread", 15, gainColor, "Best single trade: Sell − Buy (ig/ton)"),
        numberCol("profit", "Avg", 16, gainColor,
            "Hauling's score: average of the top exchanges on each side (ig/ton)", { default_sort = "desc" }),
        numberCol("margin", "Margin", 15, gainColor, "Average profit as a percentage of the average buy price"),
    }
end

-- ── Commodity dropdown (icon-aware, matching Exchange's Prices list) ─────────

local function toggleDropdown(inst, target)
    if inst.dropdown then
        inst.dropdown:hide()
        inst.dropdown = nil
        return
    end

    inst.dropGen = (inst.dropGen or 0) + 1
    local gen  = inst.dropGen
    local list = f2tCommodityList()
    local rowH = f2tScaled(target, 22)
    local ddH  = math.min(#list * rowH, math.max(80, target.content:get_height() - inst.barH - 4))
    local cellPt = f2tUiPt(target, CELL_PT)

    local dd = Geyser.Container:new({
        name = string.format("%s_pcddd_%d", target._gid, gen),
        x = 4, y = inst.barH, width = f2tScaled(target, 210), height = ddH,
    }, target.content)

    local bg = Geyser.Label:new({
        name = string.format("%s_pcdddbg_%d", target._gid, gen),
        x = 0, y = 0, width = "100%", height = "100%",
    }, dd)
    bg:setStyleSheet([[
        background-color: rgba(20, 22, 32, 250);
        border: 1px solid rgba(100, 100, 110, 200);
        border-radius: 4px;
    ]])

    local sbx = Geyser.ScrollBox:new({
        name = string.format("%s_pcdddsb_%d", target._gid, gen),
        x = 1, y = 1, width = "100%-2px", height = "100%-2px",
    }, dd)

    for i, item in ipairs(list) do
        local lbl = Geyser.Label:new({
            name = string.format("%s_pcdddi_%d_%d", target._gid, gen, i),
            x = 0, y = (i - 1) * rowH, width = "100%-17px", height = rowH, fontSize = cellPt,
        }, sbx)
        lbl:setStyleSheet(_ITEM_CSS)
        local icon = f2tCommodityIconPrefix and f2tCommodityIconPrefix(item.name) or ""
        lbl:echo(string.format(
            "<span style='%scolor:#e6d28c;'>%s%s</span> <span style='%scolor:#888888;'>(%s)</span>",
            CELL_FONT, icon, item.name, CELL_FONT, item.basePrice or "?"))
        local name = item.name
        lbl:setClickCallback(function()
            if inst.dropdown then inst.dropdown:hide(); inst.dropdown = nil end
            selectCommodity(name)
        end)
    end

    dd:show()
    dd:raise()
    inst.dropdown = dd
end

-- ── Content build ─────────────────────────────────────────────────────────────

-- One sortable table (prices or results) under a column header strip.
local function buildTable(target, wid, tableId, cols, cellPt, labelPt, colH)
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = colH,
    }, target.content)
    colBar:setStyleSheet(_COL_BAR_CSS)

    local scroll = Geyser.ScrollBox:new({
        name = wid(), x = 0, y = colH, width = "100%", height = "100%-" .. colH .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, f2tScaled(target, ROW_H), scroll, cellPt)

    local colHdrs, xPct = {}, 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name = wid(), x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%", fontSize = labelPt,
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local key = col.key
            lbl:setClickCallback(function() f2tTableToggleSort(tableId, key) end)
            lbl:setToolTip(col.header_tooltip or ("Sort by " .. col.label))
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    return { tableId = tableId, colBar = colBar, scroll = scroll, contentLabel = contentLabel, contentW = contentW }
end

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        render(instances[gid])
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_pc_%d", gid, wc)
    end

    local strip   = f2tHaulStripCreate(target)
    local stripH  = strip.height
    local barH    = f2tScaled(target, H_BAR)
    local statH   = f2tScaled(target, H_STAT)
    local runH    = f2tScaled(target, H_RUN)
    local colH    = f2tScaled(target, H_COL)
    local cellPt  = f2tUiPt(target, CELL_PT)
    local labelPt = f2tTextPt(target, LABEL_PT)

    -- ── Controls bar ──────────────────────────────────────────────────────────
    local bar = Geyser.Label:new({
        name = wid(), x = 0, y = stripH, width = "100%", height = barH,
    }, target.content)
    bar:setStyleSheet(_HDR_BAR_CSS)

    local function button(x, w, css, tip)
        local btn = Geyser.Label:new({
            name = wid(), x = x, y = 4, width = w, height = barH - 8, fontSize = labelPt,
        }, bar)
        btn:setStyleSheet(css)
        btn:setToolTip(tip)
        return btn
    end

    -- Right-aligned buttons this player can use; the commodity picker takes the rest.
    local caps = capabilities()
    local specs = {
        { key = "check", pct = 15, css = _CHECK_BTN_CSS,
          tip = "Check the selected commodity with your price service, or at the exchange you're in" },
    }
    if caps.scan then
        specs[#specs + 1] = { key = "scan", pct = 15, css = _SCAN_BTN_CSS,
            tip = "Price every commodity (a Cartel scan is the one exchange hauling uses)" }
    end
    if caps.scope then
        specs[#specs + 1] = { key = "scope", pct = 16, css = _SCOPE_BTN_CSS,
            tip = "Cartel, or the whole galaxy with the Premium Ticker" }
    end
    if caps.scan then
        specs[#specs + 1] = { key = "view", pct = 15, css = _VIEW_BTN_CSS,
            tip = "Switch between prices and scan results" }
    end
    local used = 0
    for _, spec in ipairs(specs) do used = used + spec.pct + 1 end
    local dropBtn = button(5, (99 - used - 1) .. "%", _DROP_CSS, "Select a commodity")
    local btns, x = {}, 100 - used
    for _, spec in ipairs(specs) do
        btns[spec.key] = button(x .. "%", spec.pct .. "%", spec.css, spec.tip)
        x = x + spec.pct + 1
    end
    local checkBtn, scanBtn, scopeBtn, viewBtn = btns.check, btns.scan, btns.scope, btns.view
    checkBtn:echo("<center>🔍 Check</center>")

    -- ── Exchange hauling row (shown only while it trades) ─────────────────────
    local runRow = Geyser.Label:new({
        name = wid(), x = 0, y = stripH + barH, width = "100%", height = runH, fontSize = cellPt,
    }, target.content)
    runRow:setStyleSheet(_RUN_ROW_CSS)
    runRow:setToolTip("Show this commodity's prices")
    runRow:setClickCallback(function()
        local commodity = F2T_HAULING_STATE and F2T_HAULING_STATE.current_commodity
        if commodity then selectCommodity(commodity) end
    end)
    runRow:hide()

    -- ── Status strip ──────────────────────────────────────────────────────────
    local status = Geyser.Label:new({
        name = wid(), x = 0, y = stripH + barH, width = "100%", height = statH,
        fontSize = f2tTextPt(target, STATUS_PT),
    }, target.content)
    status:setStyleSheet([[
        QLabel {
            background-color: rgba(12, 14, 24, 220);
            border: none;
            color: rgba(136, 150, 192, 255);
        }
        QToolTip {
            background-color: #1d2030; color: #e8ebf5;
            border: 1px solid rgba(255,255,255,0.18); padding: 3px;
        }
    ]])

    local haulBtn = Geyser.Label:new({
        name = wid(), x = "-" .. f2tScaled(target, 104) .. "px", y = 1,
        width = f2tScaled(target, 100), height = statH - 2, fontSize = f2tTextPt(target, STATUS_PT),
    }, status)
    haulBtn:setStyleSheet(_HAUL_BTN_CSS)
    haulBtn:echo("<center>▶ Haul these</center>")
    haulBtn:setToolTip("Start exchange hauling on this scan (haul start exchange)")
    haulBtn:setClickCallback(function() expandAlias("haul start exchange") end)
    haulBtn:hide()

    -- ── Tables ────────────────────────────────────────────────────────────────
    local prices  = buildTable(target, wid, "price_checker_" .. gid, priceCols(), cellPt, labelPt, colH)
    local results = buildTable(target, wid, "price_scan_" .. gid, resultCols(), cellPt, labelPt, colH)

    local emptyLbl = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = "100%", fontSize = cellPt,
    }, target.content)
    emptyLbl:setStyleSheet("QLabel{background-color: rgba(18, 18, 26, 255); border: none; " ..
        "qproperty-wordWrap: true; qproperty-alignment: 'AlignLeft | AlignTop';}")
    emptyLbl:hide()

    local inst = {
        target   = target,
        caps     = caps,
        dropBtn  = dropBtn,
        checkBtn = checkBtn,
        scanBtn  = scanBtn,
        scopeBtn = scopeBtn,
        viewBtn  = viewBtn,
        runRow   = runRow,
        status   = status,
        haulBtn  = haulBtn,
        prices   = prices,
        results  = results,
        emptyLbl = emptyLbl,
        dropdown = nil,
        barH     = stripH + barH,
        statH    = statH,
        runH     = runH,
        colH     = colH,
    }
    instances[gid] = inst

    dropBtn:setClickCallback(function() toggleDropdown(inst, target) end)
    checkBtn:setClickCallback(function() f2tPriceCheckerCheck() end)
    if scanBtn then
        scanBtn:setClickCallback(toggleScan)
        viewBtn:setClickCallback(function()
            F2T_PRICE_CHECKER.view = F2T_PRICE_CHECKER.view == "results" and "prices" or "results"
            F2T_PRICE_CHECKER.lastError = nil
            renderAll()
        end)
    end
    if scopeBtn then scopeBtn:setClickCallback(toggleScope) end

    layout(inst)
    render(inst)
end

-- ── Content registration ──────────────────────────────────────────────────────

local function buildPriceCheckerDef()
    return {
        name        = "Trading",
        description = "Price checks, full price scans scored for hauling, and exchange hauling's live cycle.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[price_checker] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableDestroy(inst.prices.tableId)
                f2tTableDestroy(inst.results.tableId)
                instances[target._gid] = nil
            end
            f2tHaulStripRemove(target._gid)
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            for _, view in ipairs({ inst.prices, inst.results }) do
                if newCw ~= view.contentW then
                    view.contentW = newCw
                    view.contentLabel:resize(newCw, view.contentLabel:get_height())
                    f2tTableOnResize(view.tableId, newCw)
                end
            end
        end,
        serialize = function(_t)
            return {
                selectedCommodity = F2T_PRICE_CHECKER.selectedCommodity,
                view              = F2T_PRICE_CHECKER.view,
                scope             = F2T_PRICE_CHECKER.scope,
            }
        end,
        restore = function(_t, data)
            if type(data.selectedCommodity) == "string" then
                F2T_PRICE_CHECKER.selectedCommodity = data.selectedCommodity
            end
            if data.view == "results" or data.view == "prices" then
                F2T_PRICE_CHECKER.view = data.view
            end
            if data.scope == "cartel" or data.scope == "galaxy" then
                F2T_PRICE_CHECKER.scope = data.scope
            end
            renderAll()
        end,
        onReveal = function(target)
            local inst = instances[target._gid]
            if inst then render(inst) end
        end,
        onTextScale = function(target) f2tRebuildForTextScale(target) end,
    }
end

function f2tRegisterPriceChecker()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[price_checker] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_price_checker", buildPriceCheckerDef())
    if f2t_debug_log then f2t_debug_log("[price_checker] registered fed2_price_checker content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterPriceChecker)

if f2t_debug_log then f2t_debug_log("[price_checker] module loaded") end
