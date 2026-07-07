-- trading.lua — Cartel price / best-profit trading content for fed2-tools.
--
-- Panel layout per instance:
--   H_BAR  px — controls: commodity selector ▼ · CP · ☑ Cartel · Find Best
--   H_STAT px — status strip (search progress / best-profit summary)
--   H_COL  px — sortable column header bar
--   rest      — price table (System | Planet | Action | Qty | Price)
--
-- CP sends `c price <commodity> [cartel]`; the trading_line trigger captures
-- each result row into the table (gagged only while a panel is open).
--
-- Find Best iterates every commodity with `c price <c> cartel`, computes
-- best sell−buy spread per commodity, and shows the scan log + verdict in a
-- console that overlays the table during the search.
--
-- Ported from archive's ui_trading.lua + tradingLine/tradingProfitSearch/
-- findBestProfitHide triggers.

local H_BAR  = 26
local H_STAT = 18
local H_COL  = 20
local ROW_H  = 20
local SB_W   = 17

local CELL_FONT = "font-size:10pt;font-family:Consolas,Monaco,monospace;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

local _BTN_CSS = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(150,165,205,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 3px;
        font-size: 10px; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(42,48,78,230);
        color: rgba(200,215,255,255);
    }
]]

-- ── Shared state (triggers read this) ────────────────────────────────────────

F2T_TRADING = F2T_TRADING or {
    currentCommodity  = nil,   -- commodity of the in-flight/last cp
    selectedCommodity = nil,
    useCartel         = true,
    rows              = {},    -- current price table rows
    profitSearch      = {
        active      = false,
        list        = {},
        index       = 1,
        results     = {},
        best        = nil,
        bestProfit  = -math.huge,
        totalCount  = 0,
        data        = {},      -- rows captured for the commodity being scanned
    },
}

-- Per-pane state, keyed by target._gid
local instances = {}

-- ── Commodity list (from resources/commodities.json) ─────────────────────────

local _commodities = nil
local function commodityList()
    if _commodities then return _commodities end
    local filePath = getMudletHomeDir() .. "/fed2-tools/commodities.json"
    local file = io.open(filePath, "r")
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

-- ── Table columns ─────────────────────────────────────────────────────────────

local function buildCols()
    return {
        {
            key           = "system",
            label         = "System",
            sortable      = true,
            sort_value    = function(r) return r.system:lower() end,
            scrollbox_pct = 22,
            render_label  = function(v, row, cell)
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
                cell:setToolTip(v == "buying"
                    and "Exchange is buying — click to sell here"
                    or  "Exchange is selling — click to buy here")
                cell:setClickCallback(function()
                    local cmd = (v == "buying") and "sell " or "buy "
                    send(cmd .. (F2T_TRADING.currentCommodity or ""), false)
                end)
            end,
        },
        {
            key           = "quantity",
            label         = "Qty",
            sortable      = true,
            sort_value    = function(r) return r.quantity or 0 end,
            scrollbox_pct = 14,
            render_label  = function(v, row, cell)
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
                for _, r in ipairs(F2T_TRADING.rows) do
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

-- ── Instance refresh ──────────────────────────────────────────────────────────

local function setStatus(text)
    for _, inst in pairs(instances) do
        if inst.status then inst.status:echo(text or "") end
    end
end

local _renderTimer = nil
local function refreshAllDebounced()
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.15, function()
        _renderTimer = nil
        for _, inst in pairs(instances) do
            pcall(f2tTableSetData, inst.tableId, F2T_TRADING.rows)
        end
    end)
end

local function updateSelectorButtons()
    local label = F2T_TRADING.selectedCommodity or "Select Commodity"
    for _, inst in pairs(instances) do
        if inst.dropBtn then inst.dropBtn:echo("<center>" .. label .. " ▼</center>") end
        if inst.cartelBtn then
            inst.cartelBtn:echo("<center>" .. (F2T_TRADING.useCartel and "☑" or "☐") .. " Cartel</center>")
        end
    end
end

-- ── Trigger entry points ──────────────────────────────────────────────────────

function f2tTradingHasOpenPanels()
    return next(instances) ~= nil
end

function f2tTradingIsSearching()
    return F2T_TRADING.profitSearch.active
end

function f2tTradingLine(system, planet, action, quantity, price)
    local row = {
        system   = system,
        planet   = planet,
        action   = action,
        quantity = tonumber(quantity),
        price    = tonumber(price),
    }
    if F2T_TRADING.profitSearch.active then
        table.insert(F2T_TRADING.profitSearch.data, row)
    else
        table.insert(F2T_TRADING.rows, row)
        refreshAllDebounced()
    end
end

-- ── Best-profit search ────────────────────────────────────────────────────────

local function searchConsoles(fn)
    for _, inst in pairs(instances) do
        if inst.searchConsole then pcall(fn, inst.searchConsole) end
    end
end

local function searchNext()
    local ps = F2T_TRADING.profitSearch
    if not ps.active then return end

    local commodity = ps.list[ps.index]
    if not commodity then
        -- Done: show verdict.
        ps.active = false
        pcall(disableTrigger, "trading_profit_tick")   -- catch-all ^$ pattern; armed only while scanning
        table.sort(ps.results, function(a, b) return a.profit > b.profit end)
        searchConsoles(function(mc)
            mc:cecho("\n<white>==========================================\n")
            if ps.best then
                local best = ps.results[1]
                mc:cecho("<yellow>BEST PROFIT: <reset>")
                mc:cechoLink("<green><b>" .. best.commodity .. "</b><reset>",
                    function()
                        F2T_TRADING.selectedCommodity = best.commodity
                        updateSelectorButtons()
                        if f2tTradingCheckPrice then f2tTradingCheckPrice() end
                    end,
                    "View full cartel prices for " .. best.commodity, true)
                mc:cecho(string.format(" | <green>%dig/ton profit<reset>\n", best.profit))
                mc:cecho(string.format("Buy at %dig, sell at %dig\n", best.bestBuy, best.bestSell))
                F2T_TRADING.selectedCommodity = best.commodity
                updateSelectorButtons()
            else
                mc:cecho("<red>No profitable commodities found<reset>\n")
            end
            mc:cecho("<white>==========================================<reset>\n")
            mc:cecho("<dim_grey>Click the commodity name to load full cartel prices.<reset>\n")
        end)
        setStatus(string.format(
            "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>Scan complete — best: %s</span>",
            ps.best or "none"))
        return
    end

    ps.data = {}
    F2T_TRADING.currentCommodity = commodity
    setStatus(string.format(
        "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>Scanning %d/%d — %s</span>",
        ps.index, ps.totalCount, commodity))
    send("c price " .. commodity:lower() .. " cartel", false)
end

-- Called by the trading_profit_tick trigger on the blank line ending a cp burst.
function f2tTradingProfitTick()
    local ps = F2T_TRADING.profitSearch
    if not ps.active or #ps.data == 0 then return false end

    local bestBuy, bestSell = math.huge, -1
    for _, item in ipairs(ps.data) do
        if item.action == "selling" and item.price < bestBuy  then bestBuy  = item.price end
        if item.action == "buying"  and item.price > bestSell then bestSell = item.price end
    end
    local profit = (bestBuy ~= math.huge and bestSell ~= -1) and (bestSell - bestBuy) or -math.huge

    local commodity = F2T_TRADING.currentCommodity
    table.insert(ps.results, {
        commodity = commodity, profit = profit, bestBuy = bestBuy, bestSell = bestSell,
    })
    if profit > ps.bestProfit then
        ps.bestProfit = profit
        ps.best       = commodity
    end

    searchConsoles(function(mc)
        mc:cecho(string.format("<%s>%-20s: %+5dig/ton<reset>\n",
            profit > 0 and "green" or "red", commodity,
            profit ~= -math.huge and profit or 0))
    end)

    ps.data  = {}
    ps.index = ps.index + 1
    tempTimer(0.5, searchNext)
    return true
end

local function findBestProfit()
    local ps = {
        active     = true,
        list       = {},
        index      = 1,
        results    = {},
        best       = nil,
        bestProfit = -math.huge,
        totalCount = 0,
        data       = {},
    }
    for _, c in ipairs(commodityList()) do
        table.insert(ps.list, c.name:lower())
    end
    table.sort(ps.list)
    ps.totalCount = #ps.list
    F2T_TRADING.profitSearch = ps

    if ps.totalCount == 0 then
        cecho("\n<red>[trading]<reset> Commodity list unavailable\n")
        ps.active = false
        return
    end

    searchConsoles(function(mc)
        mc:clear()
        mc:show()
        mc:raise()
        mc:cecho(string.format("<yellow>Searching %d commodities for best profit...\n\n", ps.totalCount))
    end)
    pcall(enableTrigger, "trading_profit_tick")
    searchNext()
end

-- ── CP button ─────────────────────────────────────────────────────────────────

function f2tTradingCheckPrice()
    if not F2T_TRADING.selectedCommodity then
        cecho("\n<red>[trading]<reset> Select a commodity first\n")
        return
    end
    F2T_TRADING.currentCommodity = F2T_TRADING.selectedCommodity:lower()
    F2T_TRADING.rows = {}
    refreshAllDebounced()
    for _, inst in pairs(instances) do
        if inst.searchConsole then inst.searchConsole:hide() end
    end
    setStatus(string.format(
        "<span style='font-size:9px;color:#8896c0;padding-left:6px;'>Prices: %s%s</span>",
        F2T_TRADING.selectedCommodity, F2T_TRADING.useCartel and " (cartel)" or ""))

    local cmd = "c price " .. F2T_TRADING.selectedCommodity:lower()
    if F2T_TRADING.useCartel then cmd = cmd .. " cartel" end
    send(cmd, false)
end

-- ── Commodity dropdown ────────────────────────────────────────────────────────

local function toggleDropdown(inst, target)
    if inst.dropdown then
        inst.dropdown:hide()
        inst.dropdown = nil
        return
    end

    inst.dropGen = (inst.dropGen or 0) + 1
    local gen  = inst.dropGen
    local list = commodityList()
    local rowH = 22
    local ddH  = math.min(#list * rowH, math.max(80, target.content:get_height() - H_BAR - 4))

    local dd = Geyser.Container:new({
        name = string.format("%s_tddd_%d", target._gid, gen),
        x = 4, y = H_BAR, width = 190, height = ddH,
    }, target.content)

    local bg = Geyser.Label:new({
        name = string.format("%s_tdddbg_%d", target._gid, gen),
        x = 0, y = 0, width = "100%", height = "100%",
    }, dd)
    bg:setStyleSheet([[
        background-color: rgba(20, 22, 32, 250);
        border: 1px solid rgba(100, 100, 110, 200);
        border-radius: 3px;
    ]])

    local sbx = Geyser.ScrollBox:new({
        name = string.format("%s_tdddsb_%d", target._gid, gen),
        x = 1, y = 1, width = "100%-2px", height = "100%-2px",
    }, dd)

    for i, item in ipairs(list) do
        local lbl = Geyser.Label:new({
            name = string.format("%s_tdddi_%d_%d", target._gid, gen, i),
            x = 0, y = (i - 1) * rowH, width = "100%-17px", height = rowH,
        }, sbx)
        lbl:setStyleSheet(_BTN_CSS)
        lbl:echo("<center>" .. item.name .. " (" .. item.basePrice .. ")</center>")
        local name = item.name
        lbl:setClickCallback(function()
            F2T_TRADING.selectedCommodity = name
            updateSelectorButtons()
            if inst.dropdown then inst.dropdown:hide(); inst.dropdown = nil end
        end)
    end

    dd:show()
    dd:raise()
    inst.dropdown = dd
end

-- ── Content build ─────────────────────────────────────────────────────────────

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        f2tTableSetData(instances[gid].tableId, F2T_TRADING.rows)
        updateSelectorButtons()
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_td_%d", gid, wc)
    end

    -- ── Controls bar ──────────────────────────────────────────────────────────
    local bar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_BAR,
    }, target.content)
    bar:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local dropBtn = Geyser.Label:new({
        name = wid(), x = 4, y = 3, width = "40%", height = H_BAR - 6,
    }, bar)
    dropBtn:setStyleSheet(_BTN_CSS)
    dropBtn:setToolTip("Select a commodity")

    local cpBtn = Geyser.Label:new({
        name = wid(), x = "42%", y = 3, width = "14%", height = H_BAR - 6,
    }, bar)
    cpBtn:setStyleSheet(_BTN_CSS)
    cpBtn:echo("<center>CP</center>")
    cpBtn:setToolTip("Check prices for the selected commodity")
    cpBtn:setClickCallback(function() f2tTradingCheckPrice() end)

    local cartelBtn = Geyser.Label:new({
        name = wid(), x = "58%", y = 3, width = "18%", height = H_BAR - 6,
    }, bar)
    cartelBtn:setStyleSheet(_BTN_CSS)
    cartelBtn:setToolTip("Toggle cartel-wide price check")
    cartelBtn:setClickCallback(function()
        F2T_TRADING.useCartel = not F2T_TRADING.useCartel
        updateSelectorButtons()
    end)

    local bestBtn = Geyser.Label:new({
        name = wid(), x = "78%", y = 3, width = "20%", height = H_BAR - 6,
    }, bar)
    bestBtn:setStyleSheet(_BTN_CSS)
    bestBtn:echo("<center>Find Best</center>")
    bestBtn:setToolTip("Scan every commodity for the best cartel profit spread")
    bestBtn:setClickCallback(function()
        if not F2T_TRADING.profitSearch.active then findBestProfit() end
    end)

    -- ── Status strip ──────────────────────────────────────────────────────────
    local status = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = H_STAT,
    }, target.content)
    status:setStyleSheet([[
        background-color: rgba(12, 14, 24, 220);
        border: none;
        color: rgba(136, 150, 192, 255);
    ]])

    -- ── Column header bar ─────────────────────────────────────────────────────
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR + H_STAT, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    -- ── ScrollBox table ───────────────────────────────────────────────────────
    local scrollTop = H_BAR + H_STAT + H_COL
    local scroll = Geyser.ScrollBox:new({
        name   = wid(),
        x = 0, y = scrollTop,
        width  = "100%",
        height = "100%-" .. scrollTop .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    -- Search console overlays the table area during a best-profit scan.
    local searchConsole = Geyser.MiniConsole:new({
        name = wid(), x = 0, y = scrollTop, width = "100%",
        height = "100%-" .. scrollTop .. "px", fontSize = 9,
    }, target.content)
    searchConsole:setColor(18, 18, 26)
    searchConsole:hide()

    local tableId = "trading_" .. gid
    local cols    = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, ROW_H, scroll)

    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name  = wid(),
            x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%",
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local tid, key = tableId, col.key
            lbl:setClickCallback(function() f2tTableToggleSort(tid, key) end)
            lbl:setToolTip("Sort by " .. col.label)
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    local inst = {
        tableId       = tableId,
        dropBtn       = dropBtn,
        cartelBtn     = cartelBtn,
        status        = status,
        scroll        = scroll,
        contentLabel  = contentLabel,
        contentW      = contentW,
        searchConsole = searchConsole,
        dropdown      = nil,
    }
    instances[gid] = inst

    dropBtn:setClickCallback(function() toggleDropdown(inst, target) end)

    updateSelectorButtons()
    f2tTableSetData(tableId, F2T_TRADING.rows)
end

-- ── Content registration ──────────────────────────────────────────────────────

local function buildTradingDef()
    return {
        name        = "Trading",
        description = "Cartel price checks and best-profit commodity scanning.",
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[trading] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableDestroy(inst.tableId)
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            if newCw ~= inst.contentW then
                inst.contentW = newCw
                inst.contentLabel:resize(newCw, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
        end,
        serialize = function(_t)
            return {
                selectedCommodity = F2T_TRADING.selectedCommodity,
                useCartel         = F2T_TRADING.useCartel,
            }
        end,
        restore = function(_t, data)
            if type(data.selectedCommodity) == "string" then
                F2T_TRADING.selectedCommodity = data.selectedCommodity
            end
            if type(data.useCartel) == "boolean" then
                F2T_TRADING.useCartel = data.useCartel
            end
            updateSelectorButtons()
        end,
        onReveal = function(target)
            local inst = instances[target._gid]
            if inst then f2tTableSetData(inst.tableId, F2T_TRADING.rows) end
        end,
    }
end

function f2tRegisterTrading()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[trading] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_trading", buildTradingDef())
    -- Package (re)install re-enables all triggers; the profit-tick trigger is a
    -- catch-all blank-line pattern, so park it unless a scan is actually running.
    if not (F2T_TRADING.profitSearch and F2T_TRADING.profitSearch.active) then
        pcall(disableTrigger, "trading_profit_tick")
    end
    if f2t_debug_log then f2t_debug_log("[trading] registered fed2_trading content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterTrading)

if f2t_debug_log then f2t_debug_log("[trading] module loaded") end
