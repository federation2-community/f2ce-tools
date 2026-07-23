-- Futures market + owned-contracts content. Two registered contents, both
-- pure GMCP (no game commands, no triggers):
--
-- fed2_futures_market - contracts on offer at the current exchange
--   (gmcp.exchange.futures + .commodities). Click a commodity to buy. P&L:
--     BΔ (Base Δ) = base − futures (LONG) / futures − base (SHORT); positive
--       = favorable ticks ahead (price converges toward base ~1ig/ton/tick).
--     EΔ (Exch Δ) = exch − futures (LONG) / futures − exch (SHORT); positive
--       = profitable to liquidate now.
--     Score 1-10 = (BΔ+EΔ)/2 normalised over ±200ig.
--
-- fed2_futures - contracts the player holds (gmcp.char.futures).
--   P&L = margin − 4,000ig starting margin; margin call below min_margin.
--
-- Market columns/rows are exposed as f2tFuturesMarketCols/f2tFuturesMarketRows
-- so content/exchange.lua can host the same table.

local H_HDR = 20    -- status header strip height (px)
local H_COL = 20    -- column header bar height (px)
local ROW_H = 18    -- row height (px)
local SB_W  = 17    -- scrollbar pixel allowance

local SF   = "font-size:10pt;font-family:Consolas,Monaco,monospace;"
local C_W  = "#d8d8d8"
local C_GR = "#888888"
local C_G  = "#44cc44"
local C_Y  = "#cccc44"
local C_R  = "#cc4444"
local C_CY = "#00cccc"
local C_MA = "#ffa366"   -- suspended-row text: warm/bright so it stays legible over BG_SUSPENDED's dark red

-- Every cell background carries its own QToolTip rule — without one, a cell's
-- own dark background can bleed into the native tooltip box (black text on a
-- black/dark-red tooltip, unreadable) instead of Qt/OS tooltip defaults.
local TOOLTIP_CSS = "QToolTip{background-color:#1d2030;color:#e8ebf5;border:1px solid rgba(255,255,255,0.18);padding:3px;}"

local BG_NORMAL    = "background-color:transparent; border:none; padding:0;" .. TOOLTIP_CSS
local BG_OWNED     = "background-color:rgba(25,25,50,160); border:none; padding:0;" .. TOOLTIP_CSS
local BG_SUSPENDED = "background-color:rgba(60,12,12,140); border:none; padding:0;" .. TOOLTIP_CSS

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

-- Per-pane state, keyed by target._gid (separate registries per content type)
local marketInstances = {}
local ownedInstances  = {}

-- ── Formatting / math helpers ─────────────────────────────────────────────────

local function fmtIg(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1000000 then return string.format("%.1fM", n / 1e6)
    elseif a >= 1000 then return string.format("%.1fk", n / 1e3)
    else                  return tostring(math.floor(n)) end
end

local function fmtIgSigned(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    return (n >= 0 and "+" or "") .. fmtIg(n)
end

local function fmtGap(n)
    if math.abs(n) < 10000 then
        return string.format("%+d", math.floor(n))
    end
    return string.format("%+.1fk", n / 1000)
end

local function gapColor(n)
    if not n        then return C_GR end
    if n >= 100     then return C_G
    elseif n >= 20  then return C_Y
    elseif n >= -20 then return C_GR
    else                 return C_R end
end

local function calcBaseDelta(contractType, futuresPrice, basePrice)
    if not basePrice then return nil end
    return contractType == "long" and (basePrice - futuresPrice) or (futuresPrice - basePrice)
end

local function calcScore(bDelta, eDelta)
    if not bDelta then return nil end
    local composite = eDelta and (bDelta + eDelta) / 2 or bDelta * 0.6
    local clamped   = math.max(-200, math.min(200, composite))
    return math.max(1, math.min(10, math.floor(((clamped + 200) / 400) * 9 + 1.5)))
end

-- HTML span helpers.  State-aware: maroon = suspended, strikethrough = owned.
local function span(align, color, text)
    return string.format(
        "<p style='text-align:%s;margin:0;padding:0 3px;'><span style='%scolor:%s;'>%s</span></p>",
        align, SF, color, text)
end

local function spanState(align, row, text, normalColor)
    if row.suspended then
        return span(align, C_MA, text)
    elseif row.owned then
        return string.format(
            "<p style='text-align:%s;margin:0;padding:0 3px;'><span style='%scolor:%s;text-decoration:line-through;'>%s</span></p>",
            align, SF, C_GR, text)
    end
    return span(align, normalColor, text)
end

local function cellBg(row)
    if     row.suspended then return BG_SUSPENDED
    elseif row.owned     then return BG_OWNED
    else                      return BG_NORMAL end
end

-- ── Dialogs (Muxlet primitives, mirrors content/company.lua) ─────────────────

local _pendingDialog = nil

local function openDialog(opts, buildFn)
    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho("\n<yellow>[futures]<reset> Dialogs require Muxlet.\n")
        return
    end
    if not Mux._content or not Mux._content["f2t_futures_dialog"] then
        Mux.registerContent("f2t_futures_dialog", {
            internal = true,
            name     = "Futures Action",
            apply    = function(target)
                target.contentBg:echo("")
                target.contentBg:setStyleSheet("background-color:rgba(0,0,0,0);border:none;")
                target.contentBg:hide()
                local fn = _pendingDialog
                _pendingDialog = nil
                if fn then fn(target) end
            end,
        })
    end
    _pendingDialog = buildFn
    local d = Mux.createDialog({
        title     = opts.title,
        width     = opts.width  or 420,
        height    = opts.height or 210,
        singleton = "f2t_futures_dialog",
    })
    Mux._applyContent(d, "f2t_futures_dialog")
    d:show()
    d:raise()
    return d
end

local function dialogButtons(target, dlgW, dlgH, okLabel, okFn, danger)
    local c = target.content
    local w = dlgW - 4
    local y = (dlgH - 26) - 42

    local cancel = Geyser.Label:new({
        name = target._gid .. "_fdlg_cancel", x = 14, y = y, width = 120, height = 32,
    }, c)
    cancel:setStyleSheet(Mux.dialogCss.button)
    cancel:echo("<center>Cancel</center>")
    Mux.wireDialogButton(cancel, Mux.dialogCss.button, Mux.dialogCss.buttonHover)
    cancel:setClickCallback(function() target:close() end)

    local okCss, okHover
    if danger then okCss, okHover = Mux.dialogCss.buttonDanger,  Mux.dialogCss.buttonDangerHover
    else           okCss, okHover = Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover end
    local ok = Geyser.Label:new({
        name = target._gid .. "_fdlg_ok", x = w - 134, y = y, width = 120, height = 32,
    }, c)
    ok:setStyleSheet(okCss)
    ok:echo("<center>" .. okLabel .. "</center>")
    Mux.wireDialogButton(ok, okCss, okHover)
    ok:setClickCallback(function()
        target:close()
        okFn()
    end)
end

local function dialogConfirm(title, body, okLabel, okFn, danger)
    openDialog({ title = title, width = 420, height = 210 }, function(target)
        local msg = Geyser.Label:new({
            name = target._gid .. "_fdlg_body", x = 0, y = 8, width = "100%", height = 104,
        }, target.content)
        msg:setStyleSheet(Mux.dialogCss.body)
        msg:echo(body)
        dialogButtons(target, 420, 210, okLabel, okFn, danger)
    end)
end

-- ── Commodity display-name lookup (GMCP sends lowercase) ─────────────────────

local _commodsLookup = nil
local function commodsLookup()
    if _commodsLookup then return _commodsLookup end
    local lookup = {}
    local file = io.open(getMudletHomeDir() .. "/f2ce-tools/commodities.json", "r")
    if file then
        local raw = file:read("*all")
        file:close()
        local ok, data = pcall(yajl.to_value, raw)
        if ok and data and data.groups then
            for _, group in ipairs(data.groups) do
                for _, c in ipairs(group.commodities) do
                    if c.name then lookup[c.name:lower()] = c.name end
                end
            end
        end
    end
    _commodsLookup = lookup
    return lookup
end

-- ══ MARKET TABLE ══════════════════════════════════════════════════════════════

-- Exchange presence must come from room flags: gmcp.exchange keys persist
-- (stale, from the last exchange visited) after leaving an exchange, so their
-- mere existence can't be trusted as "live data here".
local function inExchangeRoom()
    local flags = gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.flags
    if type(flags) == "table" then
        for _, f in ipairs(flags) do
            if tostring(f):lower() == "exchange" then return true end
        end
        return false
    end
    if type(flags) == "string" then
        return flags:lower():find("exchange", 1, true) ~= nil
    end
    return false
end

function f2tFuturesMarketRows()
    local exchange = gmcp and gmcp.exchange
    if not exchange or not exchange.futures then return {} end

    local comms  = exchange.commodities or {}
    local rows   = {}
    local planet = gmcp.room and gmcp.room.info and
        (gmcp.room.info.area or gmcp.room.info.system) or ""

    for nameLower, contract in pairs(exchange.futures) do
        local commName, excData = nil, nil
        for cname, cdata in pairs(comms) do
            if cname:lower() == nameLower then
                commName, excData = cname, cdata
                break
            end
        end

        local base   = excData and excData.base or nil
        local fp     = contract.price
        local bDelta = calcBaseDelta(contract.type, fp, base)

        local exc, excHidden = nil, false
        if excData then
            if contract.type == "long" then
                local sell = excData.sell
                if sell and sell > 0 then exc = sell else excHidden = true end
            else
                local buy = excData.buy
                if buy and buy > 0 then exc = buy else excHidden = true end
            end
        end

        local eDelta = nil
        if exc then
            eDelta = contract.type == "long" and (exc - fp) or (fp - exc)
        end

        -- Mark contracts already held at this exchange.
        local owned = false
        local cf = gmcp.char and gmcp.char.futures
        if type(cf) == "table" then
            for _, f in ipairs(cf) do
                if (f.commodity or ""):lower() == nameLower and
                   (f.exchange  or ""):lower() == planet:lower() then
                    owned = true; break
                end
            end
        end

        rows[#rows + 1] = {
            commodity = commName or nameLower,
            type      = contract.type,
            price     = fp,
            base      = base,
            b_delta   = bDelta,
            exc       = exc,
            excHidden = excHidden,
            e_delta   = eDelta,
            stock     = excData and (tonumber(excData.stock) or 0) or nil,
            suspended = (contract.status == "suspended"),
            owned     = owned,
        }
    end
    return rows
end

function f2tFuturesMarketCols()
    return {
        {
            key           = "commodity",
            label         = "Commodity",
            sortable      = true,
            sort_value    = function(r) return (r.commodity or ""):lower() end,
            scrollbox_pct = 22,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local icon = f2tCommodityIconPrefix and f2tCommodityIconPrefix(v) or ""
                cell:echo(spanState("left", row, icon .. tostring(v or ""), C_W))
                if row.suspended then
                    cell:setClickCallback(function() end)
                    cell:setToolTip("Trading suspended — price frozen until hour end.")
                elseif row.owned then
                    cell:setClickCallback(function() end)
                    cell:setToolTip("Already held at this exchange — one contract per commodity per exchange.")
                else
                    cell:setClickCallback(function()
                        local commodity = tostring(v or "")
                        local typeLabel = row.type == "long" and "Long" or "Short"
                        dialogConfirm("Buy Futures Contract",
                            string.format(
                                "<b>%s</b> — %s contract<br>Futures price: <b>%dig/ton</b>%s<br>" ..
                                "Margin: <b>4,000ig</b> deposit from your bank account.",
                                commodity, typeLabel, math.floor(tonumber(row.price) or 0),
                                row.base and string.format("  (base %dig)", math.floor(row.base)) or ""),
                            "Buy",
                            function() send("buy futures " .. commodity:lower(), false) end)
                    end)
                    cell:setToolTip(string.format("Buy %s futures contract", v))
                end
            end,
        },
        {
            key           = "type",
            label         = "T",
            sortable      = true,
            sort_value    = function(r) return r.type end,
            scrollbox_pct = 5,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                cell:echo(spanState("center", row, v == "long" and "L" or "S",
                    v == "long" and C_CY or C_Y))
                cell:setClickCallback(function() end)
                cell:setToolTip(v == "long"
                    and "Long — profit when price rises toward base"
                    or  "Short — profit when price falls toward base")
            end,
        },
        {
            key           = "price",
            label         = "Fut",
            sortable      = true,
            sort_value    = function(r) return r.price or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = tonumber(v)
                cell:echo(spanState("right", row, n and tostring(math.floor(n)) or "?", C_W))
                cell:setClickCallback(function() end)
                cell:setToolTip("Futures price per ton — locked in at purchase")
            end,
        },
        {
            key           = "base",
            label         = "Base",
            sortable      = true,
            sort_value    = function(r) return r.base or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = tonumber(v)
                cell:echo(spanState("right", row, n and tostring(math.floor(n)) or "n/a", C_GR))
                cell:setClickCallback(function() end)
                cell:setToolTip("Commodity base price — futures converge toward it ~1ig/ton per tick")
            end,
        },
        {
            key           = "b_delta",
            label         = "BΔ",
            sortable      = true,
            sort_value    = function(r) return r.b_delta or -9999 end,
            scrollbox_pct = 13,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = tonumber(v)
                if not n then
                    cell:echo(spanState("right", row, "n/a", C_GR))
                    cell:setToolTip("Base delta — base price unavailable")
                else
                    cell:echo(spanState("right", row, fmtGap(n), gapColor(n)))
                    cell:setToolTip(string.format("BΔ=%+d: each unit ≈ 1 favorable tick (~5-10 min)", n))
                end
                cell:setClickCallback(function() end)
            end,
        },
        {
            key           = "exc",
            label         = "Exch",
            sortable      = true,
            sort_value    = function(r) return r.exc or -1 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = tonumber(v)
                if not n then
                    cell:echo(spanState("right", row, row.excHidden and "?" or "n/a", C_GR))
                    cell:setToolTip(row.excHidden
                        and "Price exists but not visible in GMCP."
                        or  "Not traded at this exchange")
                else
                    cell:echo(spanState("right", row, tostring(math.floor(n)), C_W))
                    cell:setToolTip("Exchange price at liquidation")
                end
                cell:setClickCallback(function() end)
            end,
        },
        {
            key           = "stock",
            label         = "Stk",
            sortable      = true,
            sort_value    = function(r) return r.stock or -1 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = tonumber(v)
                cell:echo(spanState("right", row, n and fmtIg(n) or "n/a", C_GR))
                cell:setClickCallback(function() end)
                cell:setToolTip("Exchange stock on hand — high pushes price down, low pushes it up")
            end,
        },
        {
            key           = "e_delta",
            label         = "EΔ",
            sortable      = true,
            sort_value    = function(r) return r.e_delta or -9999 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = tonumber(v)
                if not n then
                    cell:echo(spanState("right", row, row.excHidden and "?" or "n/a", C_GR))
                    cell:setToolTip(row.excHidden and "Exch not in GMCP." or "No exchange price")
                else
                    cell:echo(spanState("right", row, fmtGap(n), gapColor(n)))
                    cell:setToolTip(string.format("EΔ=%+d: positive = profitable to liquidate now", n))
                end
                cell:setClickCallback(function() end)
            end,
        },
        {
            key           = "score",
            label         = "S",
            sortable      = true,
            default_sort  = "desc",
            sort_value    = function(r) return calcScore(r.b_delta, r.e_delta) or 0 end,
            scrollbox_pct = 10,
            render_label  = function(_v, row, cell)
                cell:setStyleSheet(cellBg(row))
                local n = calcScore(row.b_delta, row.e_delta)
                if not n then
                    cell:echo(spanState("right", row, "?", C_GR))
                    cell:setToolTip("Score unavailable — base price missing")
                else
                    local color = n >= 7 and C_G or (n >= 5 and C_Y or C_R)
                    cell:echo(spanState("right", row, tostring(n), color))
                    cell:setToolTip(string.format("Score %d/10: ≥7 strong · 5-6 neutral · ≤4 poor", n))
                end
                cell:setClickCallback(function() end)
            end,
        },
    }
end

local function refreshMarket(gid)
    local inst = marketInstances[gid]
    if not inst then return end
    -- Outside an exchange room the gmcp.exchange keys are stale leftovers from
    -- the last exchange visited — never render them as live. Draw the away
    -- state once, then skip further room moves entirely.
    if not inExchangeRoom() then
        if inst.mode == "away" then return end
        inst.mode = "away"
        if inst.hdr then
            inst.hdr:echo("<span style='font-size:9px;color:#888888;padding-left:6px;'>"
                .. "Not at an exchange — contracts show live at an exchange.</span>")
        end
        f2tTableSetData(inst.tableId, {})
        return
    end
    inst.mode = "live"
    local planet = gmcp and gmcp.room and gmcp.room.info and
        (gmcp.room.info.area or gmcp.room.info.system)
    local hasData = gmcp and gmcp.exchange and gmcp.exchange.futures
    if inst.hdr then
        if hasData then
            inst.hdr:echo(string.format(
                "<span style='font-size:9px;color:#cccc44;padding-left:6px;'>%s</span>" ..
                " <span style='font-size:9px;color:#888888;'>live</span>", planet or "?"))
        else
            inst.hdr:echo(
                "<span style='font-size:9px;color:#888888;padding-left:6px;'>No exchange data — visit an exchange.</span>")
        end
    end
    f2tTableSetData(inst.tableId, f2tFuturesMarketRows())
end

local function refreshAllMarkets()
    for gid in pairs(marketInstances) do pcall(refreshMarket, gid) end
end

-- ══ OWNED CONTRACTS TABLE ═════════════════════════════════════════════════════

local function buildOwnedRows()
    local cf = gmcp and gmcp.char and gmcp.char.futures
    if type(cf) ~= "table" then return {}, 0 end

    local lookup  = commodsLookup()
    local rows    = {}
    local totalPl = 0
    for _, f in ipairs(cf) do
        local margin  = tonumber(f.margin)     or 4000
        local minM    = tonumber(f.min_margin) or 2000
        local maxLoss = tonumber(f.max_loss)   or 15000
        local pl      = margin - 4000

        local risk
        if margin < minM then
            risk = "call"
        elseif margin < minM + 1000 then
            risk = "warn"
        elseif (4000 - margin) > maxLoss * 0.7 then
            risk = "danger"
        else
            risk = "ok"
        end

        local commodityRaw = f.commodity or "?"
        rows[#rows + 1] = {
            exchange  = f.exchange or "?",
            commodity = lookup[commodityRaw:lower()] or commodityRaw,
            position  = f.position or "?",
            cost      = tonumber(f.cost)  or 0,
            value     = tonumber(f.value) or 0,
            pl        = pl,
            margin    = margin,
            risk      = risk,
        }
        totalPl = totalPl + pl
    end
    return rows, totalPl
end

local function ownedCols()
    return {
        {
            key           = "exchange",
            label         = "Exchange",
            sortable      = true,
            sort_value    = function(r) return (r.exchange or ""):lower() end,
            scrollbox_pct = 19,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                cell:echo(span("left", C_CY, tostring(v or "?")))
                cell:setToolTip("Navigate to " .. tostring(v or "?") .. " exchange")
                cell:setClickCallback(function()
                    expandAlias("nav " .. tostring(v or "") .. " exchange")
                end)
            end,
        },
        {
            key           = "commodity",
            label         = "Commodity",
            sortable      = true,
            sort_value    = function(r) return (r.commodity or ""):lower() end,
            scrollbox_pct = 19,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                local icon = f2tCommodityIconPrefix and f2tCommodityIconPrefix(v) or ""
                cell:echo(span("left", C_W, icon .. tostring(v or "?")))
                cell:setClickCallback(function() end)
            end,
        },
        {
            key           = "position",
            label         = "T",
            sortable      = true,
            sort_value    = function(r) return r.position end,
            scrollbox_pct = 5,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                local isLong = (v == "long")
                cell:echo(span("center", isLong and C_CY or C_Y, isLong and "L" or "S"))
                cell:setClickCallback(function() end)
                cell:setToolTip(isLong and "Long contract" or "Short contract")
            end,
        },
        {
            key           = "cost",
            label         = "Cost",
            sortable      = true,
            sort_value    = function(r) return r.cost or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                cell:echo(span("right", C_GR, fmtIg(tonumber(v))))
                cell:setClickCallback(function() end)
                cell:setToolTip("Original contract cost")
            end,
        },
        {
            key           = "value",
            label         = "Value",
            sortable      = true,
            sort_value    = function(r) return r.value or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                local n    = tonumber(v) or 0
                local cost = tonumber(row.cost) or 0
                cell:echo(span("right", n >= cost and C_G or C_R, fmtIg(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip("Current mark-to-market value")
            end,
        },
        {
            key           = "pl",
            label         = "P&L",
            sortable      = true,
            default_sort  = "asc",
            sort_value    = function(r) return r.pl or 0 end,
            scrollbox_pct = 12,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                local n = tonumber(v) or 0
                local color = n > 0 and C_G or (n < 0 and C_R or C_GR)
                cell:echo(span("right", color, fmtIgSigned(n)))
                cell:setClickCallback(function() end)
                cell:setToolTip("P&L = margin − 4,000ig starting margin")
            end,
        },
        {
            key           = "margin",
            label         = "Margin",
            sortable      = true,
            sort_value    = function(r) return r.margin or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                local color = (row.risk == "call" or row.risk == "danger") and C_R
                           or row.risk == "warn" and C_Y or C_GR
                cell:echo(span("right", color, fmtIg(tonumber(v) or 4000)))
                cell:setClickCallback(function() end)
                cell:setToolTip("Broker margin — margin call below minimum (4,000ig charge, −4 rating)")
            end,
        },
        {
            key           = "risk",
            label         = "M",
            sortable      = false,
            scrollbox_pct = 5,
            render_label  = function(v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                local icons = { ok = {"✓", C_G}, warn = {"!", C_Y}, call = {"✗", C_R}, danger = {"✗", C_R} }
                local tips  = {
                    ok     = "Margin healthy",
                    warn   = "Approaching minimum margin",
                    call   = "Margin call — below minimum margin (4,000ig charge pending)",
                    danger = "Danger — losses approaching maximum",
                }
                local d = icons[v] or { "?", C_GR }
                cell:echo(span("center", d[2], d[1]))
                cell:setClickCallback(function() end)
                cell:setToolTip(tips[v] or "Unknown")
            end,
        },
        {
            key           = "close",
            label         = "Close",
            sortable      = false,
            scrollbox_pct = 10,
            render_label  = function(_v, row, cell)
                cell:setStyleSheet(BG_NORMAL)
                cell:echo(string.format(
                    "<p style='text-align:center;margin:0;'><span style='%scolor:#ff8866;'>✕ Close</span></p>", SF))
                cell:setToolTip("Liquidate this contract — you must be at the " ..
                    tostring(row.exchange or "?") .. " exchange")
                cell:setClickCallback(function()
                    dialogConfirm("Liquidate Futures Contract",
                        string.format(
                            "<b>%s</b> — %s contract at <b>%s</b><br>" ..
                            "Cost <b>%sig</b> &nbsp; Value <b>%sig</b> &nbsp; P&amp;L <b>%s</b><br>" ..
                            "You must be standing in the %s exchange for this to work.",
                            row.commodity, row.position == "long" and "Long" or "Short",
                            tostring(row.exchange or "?"), fmtIg(row.cost), fmtIg(row.value),
                            fmtIgSigned(row.pl), tostring(row.exchange or "?")),
                        "Liquidate",
                        function() send("liquidate " .. tostring(row.commodity or ""):lower(), false) end,
                        true)
                end)
            end,
        },
    }
end

local function refreshOwned(gid)
    local inst = ownedInstances[gid]
    if not inst then return end
    local rows, totalPl = buildOwnedRows()
    if inst.hdr then
        if #rows == 0 then
            inst.hdr:echo("<span style='font-size:9px;color:#888888;padding-left:6px;'>No contracts held.</span>")
        else
            local plColor = totalPl > 0 and C_G or (totalPl < 0 and C_R or C_GR)
            inst.hdr:echo(string.format(
                "<span style='font-size:9px;color:#888888;padding-left:6px;'>%d contract%s &nbsp; Total P&amp;L:</span>" ..
                " <span style='font-size:9px;color:%s;'>%s</span>",
                #rows, #rows ~= 1 and "s" or "", plColor, fmtIgSigned(totalPl)))
        end
    end
    f2tTableSetData(inst.tableId, rows)
end

local function refreshAllOwned()
    for gid in pairs(ownedInstances) do pcall(refreshOwned, gid) end
end

-- ══ Shared build/def plumbing ═════════════════════════════════════════════════

local function buildPanel(target, registry, idPrefix, cols, refreshFn)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if registry[gid] then
        refreshFn(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_%s_%d", gid, idPrefix, wc)
    end

    local hdr = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_HDR,
    }, target.content)
    hdr:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_HDR, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scrollTop = H_HDR + H_COL
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

    local tableId = idPrefix .. "_" .. gid
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

    registry[gid] = {
        tableId      = tableId,
        hdr          = hdr,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
    }
    refreshFn(gid)
end

local function makeDef(name, description, registry, idPrefix, colsFn, refreshFn)
    return {
        name        = name,
        description = description,
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildPanel, target, registry, idPrefix, colsFn(), refreshFn)
            if not ok then
                f2t_debug_log("[futures] %s apply error: %s", idPrefix, tostring(err))
            end
        end,
        remove = function(target)
            local inst = registry[target._gid]
            if inst then
                f2tTableDestroy(inst.tableId)
                registry[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = registry[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            if newCw ~= inst.contentW then
                inst.contentW = newCw
                inst.contentLabel:resize(newCw, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) refreshFn(target._gid) end,
    }
end

function f2tRegisterFutures()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[futures] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_futures_market", makeDef(
        "Futures Market",
        "Futures contracts on offer at the current exchange, scored by profit potential.",
        marketInstances, "fut_mkt", f2tFuturesMarketCols, refreshMarket))
    Mux.registerContent("fed2_futures", makeDef(
        "Futures (Owned)",
        "Your open futures contracts with P&L and margin health.",
        ownedInstances, "fut_own", ownedCols, refreshOwned))
    if f2t_debug_log then f2t_debug_log("[futures] registered fed2_futures_market + fed2_futures") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterFutures)

-- Live updates: market on exchange/room pushes, owned on char.futures pushes.
registerAnonymousEventHandler("gmcp.exchange",     function() refreshAllMarkets(); refreshAllOwned() end)
registerAnonymousEventHandler("gmcp.room.info",    function() refreshAllMarkets() end)
registerAnonymousEventHandler("gmcp.char.futures", function() refreshAllOwned(); refreshAllMarkets() end)

-- Re-render live when the shared exchange/show_icons setting flips.  Hooked
-- once Mux is up; the f2t settings layer has no onChange passthrough.
local function hookIconSetting()
    if not (Mux and Mux.settings and Mux.settings.onChange) then return false end
    Mux.settings.onChange("exchange", "show_icons", function()
        refreshAllMarkets()
        refreshAllOwned()
    end)
    return true
end

if not hookIconSetting() then
    registerAnonymousEventHandler("muxletReady", hookIconSetting)
end

if f2t_debug_log then f2t_debug_log("[futures] module loaded") end
