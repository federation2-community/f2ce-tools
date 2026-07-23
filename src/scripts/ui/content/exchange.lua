-- Live exchange board content. One registered content, pure GMCP (no game
-- commands, no triggers):
--
-- fed2_exchange - board for the exchange you're standing in, with a
-- rank-aware main table and a live price ticker strip:
--   Prices  - every commodity the exchange lists: base, Buying/Selling price,
--             stock. Deltas vs base are colored from the player's side
--             (green = exchange pays a premium / charges under base). Click
--             Buying to sell a 75-ton lot, Selling to buy one.
--   Futures - for Traders/Financiers, the futures market table shared with
--             fed2_futures_market (f2tFuturesMarketCols/Rows from
--             content/futures.lua); these ranks default to this view, with a
--             header button to flip between the two.
--   Ticker  - each exchange.commodity announcement rolls into a strip at the
--             bottom, newest last; hover a sell price for stock on hand.
--             Overlays the Prices rows between full pushes. Collapsible,
--             cleared on leaving the exchange.
--
-- The exchange/console_spam setting (below, enforced by
-- triggers/ui/exchange_spam.lua) controls whether the +++ ticker
-- announcements still show in the main console.

local H_HDR      = 20    -- status header strip height (px)
local H_COL      = 20    -- column header bar height (px)
local ROW_H      = 18    -- table row height (px)
local SB_W       = 17    -- scrollbar pixel allowance
local TICK_HDR_H = 16    -- ticker column-header console height (px)
local TICK_H     = 88    -- ticker console height (px)
local TICKER_MAX = 30    -- ticker ring-buffer depth
local BUY_COL_W  = 12    -- visible chars for the ticker's fixed-width buy column

local LAYOUT_TOP  = H_HDR + H_COL
local TICK_TOTAL  = TICK_HDR_H + TICK_H

local CELL_FONT = "font-size:10pt;font-family:Consolas,Monaco,monospace;"
local C_W  = "#d8d8d8"
local C_GR = "#888888"
local C_G  = "#44cc44"
local C_R  = "#cc4444"
local C_NM = "#e6d28c"

local COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

local BTN_CSS = [[
    QLabel{
        background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
        border-radius:3px; border-color:rgba(100,100,110,180);
        color:rgba(160,160,170,255); font-size:10px; font-weight:bold;
    } QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }
]]

-- Per-commodity emoji icons; keyed by exact commodity name from commodities.json.
local COMMOD_ICONS = {
    -- Agricultural
    Cereals         = "🌾", Fruit           = "🍎", Furs            = "🐾",
    Hides           = "🐃", Livestock       = "🐄", Meats           = "🍖",
    Soya            = "🌱", Spices          = "🌶️", Textiles        = "📜",
    Woods           = "🪵",
    -- Resource
    Alloys          = "🥈", Clays           = "🏺", Crystals        = "💎",
    Gold            = "🏆", Monopoles       = "🔮", Nickel          = "⚪",
    Petrochemicals  = "🛢️",  Radioactives    = "☢️",  Semiconductors  = "💽",
    Xmetals         = "🔩",
    -- Industrial
    Explosives      = "💣", Generators      = "⚡", LanzariK        = "💫",
    LubOils         = "💧", Mechparts       = "⚙️",  Munitions       = "🎯",
    Nitros          = "💨", Pharmaceuticals = "💊", Polymers        = "🔗",
    Propellants     = "🚀", RNA             = "🧬",
    -- Technological
    AntiMatter      = "✨", Controllers     = "🎮", Droids          = "🤖",
    Electros        = "🔌", GAsChips        = "📟", Lasers          = "🔦",
    NanoFabrics     = "🕸️",  Nanos           = "🔬", Powerpacks      = "🔋",
    Synths          = "🎹", Tools           = "🛠️",  TQuarks         = "⚛️",
    Vidicasters     = "📺", Weapons         = "⚔️",
    -- Biological
    BioChips        = "💉", BioComponents   = "🦠", Clinics         = "🏥",
    Laboratories    = "🧪", MicroScalpels   = "🔪", Probes          = "🛸",
    Proteins        = "🍗", Sensors         = "📡", ToxicMunchers   = "☣️",
    Tracers         = "🔍",
    -- Leisure
    Artifacts       = "🏛️",  Firewalls       = "🔥", Games           = "🎲",
    Holos           = "🌀", Hypnotapes      = "📼", Katydidics      = "🦗",
    Libraries       = "📚", Musiks          = "🎵", Sensamps        = "📻",
    Simulations     = "🎭", Studios         = "🎬", Univators       = "🌍",
}

-- Icons Mudlet's MiniConsole measures as 1 column wide; they get an extra
-- trailing space so the icon slot stays 4 visual chars.
local NARROW_ICONS = {
    ["⚙️"] = true, ["☢️"] = true, ["⚛️"] = true, ["⚔️"] = true, ["☣️"] = true,
    ["🌶️"] = true, ["🛢️"] = true, ["🕸️"] = true, ["🛠️"] = true, ["🏛️"] = true,
}

-- Per-pane state, keyed by target._gid
local instances = {}

-- Ticker state shared by all panes: ring buffer + latest tick per commodity.
local tickerEntries = {}
local tickerLatest  = {}

-- ── Shared helpers ────────────────────────────────────────────────────────────

local function atExchange()
    return gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange") or false
end

local function futuresRankQualifies()
    return f2t_is_rank_exactly("trader") or f2t_is_rank_exactly("financier")
end

-- A commodity-name click sends a plain "check price" spot check so its result
-- shows in the console as confirmation. The result line ("System: Planet is
-- buying|selling N tons at Pig/ton") is the same shape the price_checker_line
-- trigger captures/gags for its own panels, so that trigger checks this guard
-- first and lets the spot-check line through untouched.
function f2tExchangeSpotCheckActive()
    return F2T_EXCHANGE_SPOT_CHECK_UNTIL ~= nil and os.time() < F2T_EXCHANGE_SPOT_CHECK_UNTIL
end

local function iconsEnabled()
    return f2t_settings_get("exchange", "show_icons") ~= false
end

-- Shared with content/futures.lua (loaded before this file — resolved lazily
-- at call time, not chunk-load time) so its commodity column can show icons
-- without duplicating the icon table.
function f2tCommodityIconPrefix(name)
    if not iconsEnabled() then return "" end
    local icon = COMMOD_ICONS[name]
    if not icon then return "" end
    return icon .. (NARROW_ICONS[icon] and "  " or " ")
end

local function fmtIg(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1000000 then return string.format("%.1fM", n / 1e6)
    elseif a >= 1000 then return string.format("%.1fk", n / 1e3)
    else                  return tostring(math.floor(n)) end
end

local function spanRaw(align, inner)
    return string.format(
        "<p style='text-align:%s;margin:0;padding:0 3px;'>%s</p>", align, inner)
end

local function coloredSpan(color, text)
    return string.format("<span style='%scolor:%s;'>%s</span>", CELL_FONT, color, text)
end

-- Price + (delta vs base).  Buying column: green when the exchange pays base
-- or better.  Selling column (goodWhenAtOrBelow): green when it charges base
-- or less.
local function priceDeltaHtml(price, base, goodWhenAtOrBelow)
    local html = coloredSpan(C_W, tostring(math.floor(price)))
    if not base then return html end
    local delta = price - base
    local good
    if goodWhenAtOrBelow then good = (delta <= 0) else good = (delta >= 0) end
    return html .. " " .. coloredSpan(good and C_G or C_R, string.format("(%+d)", delta))
end

-- Commodity name → group name from commodities.json, for tooltips.
local _commodGroups = nil
local function commodGroups()
    if _commodGroups then return _commodGroups end
    local groups = {}
    local file = io.open(getMudletHomeDir() .. "/f2ce-tools/commodities.json", "r")
    if file then
        local raw = file:read("*all")
        file:close()
        local ok, data = pcall(yajl.to_value, raw)
        if ok and data and data.groups then
            for _, group in ipairs(data.groups) do
                for _, c in ipairs(group.commodities) do
                    if c.name then groups[c.name] = group.name end
                end
            end
        end
    end
    _commodGroups = groups
    return groups
end

-- ── Prices table ──────────────────────────────────────────────────────────────

local function buildPriceRows()
    if not atExchange() then return {} end
    local comms = gmcp and gmcp.exchange and gmcp.exchange.commodities
    if type(comms) ~= "table" then return {} end

    local rows = {}
    for name, d in pairs(comms) do
        if type(d) == "table" then
            local row = {
                name  = name,
                base  = tonumber(d.base),
                buy   = tonumber(d.buy)   or 0,
                sell  = tonumber(d.sell)  or 0,
                stock = tonumber(d.stock) or 0,
            }
            -- Overlay the latest ticker announcement — fresher than the last
            -- full commodities push.  Only fields the tick carried.
            local tick = tickerLatest[name]
            if tick then
                if tick.buy   then row.buy   = tick.buy   end
                if tick.sell  then row.sell  = tick.sell  end
                if tick.stock then row.stock = tick.stock end
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function priceCols()
    return {
        {
            key           = "name",
            label         = "Commodity",
            sortable      = true,
            default_sort  = "asc",
            sort_value    = function(r) return (r.name or ""):lower() end,
            scrollbox_pct = 26,
            render_label  = function(v, row, cell)
                local icon = iconsEnabled() and COMMOD_ICONS[v] or nil
                local text = icon and (icon .. " " .. tostring(v or "")) or tostring(v or "")
                cell:echo(spanRaw("left", coloredSpan(C_NM, text)))
                local group = commodGroups()[v]
                cell:setToolTip(string.format(
                    "%s%s — click for a spot price check", tostring(v or ""),
                    group and (" — " .. group .. " group") or ""))
                local name = tostring(v or ""):lower()
                cell:setClickCallback(function()
                    F2T_EXCHANGE_SPOT_CHECK_UNTIL = os.time() + 2
                    send("check price " .. name, false)
                end)
            end,
        },
        {
            key           = "base",
            label         = "Base",
            sortable      = true,
            sort_value    = function(r) return r.base or 0 end,
            scrollbox_pct = 14,
            render_label  = function(v, row, cell)
                local n = tonumber(v)
                cell:echo(spanRaw("right", coloredSpan(C_GR, n and tostring(math.floor(n)) or "n/a")))
                cell:setToolTip("Base price — exchange prices drift toward it over time")
                cell:setClickCallback(function() end)
            end,
        },
        {
            key           = "buy",
            label         = "Buying",
            sortable      = true,
            sort_value    = function(r) return r.buy or 0 end,
            scrollbox_pct = 20,
            render_label  = function(v, row, cell)
                local n = tonumber(v) or 0
                if n <= 0 then
                    cell:echo(spanRaw("right", coloredSpan(C_GR, "—")))
                    cell:setToolTip("Exchange is not buying " .. tostring(row.name or ""))
                    cell:setClickCallback(function() end)
                    return
                end
                cell:echo(spanRaw("right", priceDeltaHtml(n, row.base, false)))
                cell:setToolTip(string.format(
                    "Exchange pays %dig/ton — click to SELL a 75-ton lot from your hold", n))
                local name = tostring(row.name or ""):lower()
                cell:setClickCallback(function() send("sell " .. name, false) end)
            end,
        },
        {
            key           = "sell",
            label         = "Selling",
            sortable      = true,
            sort_value    = function(r) return r.sell or 0 end,
            scrollbox_pct = 20,
            render_label  = function(v, row, cell)
                local n = tonumber(v) or 0
                if n <= 0 then
                    cell:echo(spanRaw("right", coloredSpan(C_GR, "—")))
                    cell:setToolTip("Exchange is not selling " .. tostring(row.name or ""))
                    cell:setClickCallback(function() end)
                    return
                end
                cell:echo(spanRaw("right", priceDeltaHtml(n, row.base, true)))
                cell:setToolTip(string.format(
                    "Exchange charges %dig/ton — click to BUY a 75-ton lot", n))
                local name = tostring(row.name or ""):lower()
                cell:setClickCallback(function() send("buy " .. name, false) end)
            end,
        },
        {
            key           = "stock",
            label         = "Stock",
            sortable      = true,
            sort_value    = function(r) return r.stock or 0 end,
            scrollbox_pct = 20,
            render_label  = function(v, row, cell)
                local n = tonumber(v) or 0
                cell:echo(spanRaw("right", coloredSpan(C_GR, fmtIg(n))))
                cell:setToolTip("Stock on hand — high stock pushes prices down, low pulls them up")
                cell:setClickCallback(function() end)
            end,
        },
    }
end

-- ── Ticker rendering ──────────────────────────────────────────────────────────

local function truncateName(s, n)
    if #s <= n then return string.format("%-" .. n .. "s", s) end
    return s:sub(1, n - 1) .. "…"
end

-- Fixed-width buy column; padding sits outside the parentheses.
local function tickerBuyCol(price, base)
    local priceStr = tostring(price)
    if not base then return string.format("%-" .. BUY_COL_W .. "s", priceStr) end
    local delta = string.format("(%+d)", price - base)
    local color = (price >= base) and "<green>" or "<red>"
    local pad   = math.max(0, BUY_COL_W - (#priceStr + 1 + #delta))
    return string.format("%s %s%s<reset>%s", priceStr, color, delta, string.rep(" ", pad))
end

-- Variable-width sell column (last on the line).
local function tickerSellCol(price, base)
    local priceStr = tostring(price)
    if not base then return priceStr end
    local color = (price <= base) and "<green>" or "<red>"
    return string.format("%s %s(%+d)<reset>", priceStr, color, price - base)
end

local function appendTicker(inst, e)
    local mc = inst.tickerMc
    if not mc then return end
    if inst.tickerIdle then
        mc:clear()
        inst.tickerIdle = false
    end

    local iconSlot = ""
    if iconsEnabled() then
        local icon = COMMOD_ICONS[e.name] or "⬛"
        iconSlot = icon .. (NARROW_ICONS[icon] and "  " or " ")
    end
    local prefix = string.format(" %s<white>%s<reset> <gray>%-6s<reset> ",
        iconSlot, truncateName(e.name or "?", 12),
        e.base and string.format("(%d)", e.base) or "(?)")

    if not e.buy and not e.sell then
        mc:cecho(prefix .. "---\n")
        return
    end

    local function emitSell()
        local txt = tickerSellCol(e.sell, e.base)
        if e.stock then
            mc:cechoLink(txt, "", string.format("%s tons in stock", fmtIg(e.stock)), true)
        else
            mc:cecho(txt)
        end
    end

    if e.buy and e.sell then
        mc:cecho(prefix .. tickerBuyCol(e.buy, e.base) .. " ")
        emitSell()
        mc:cecho("\n")
    elseif e.buy then
        mc:cecho(prefix .. tickerBuyCol(e.buy, e.base) .. "\n")
    else
        -- Sell-only: "---" in the Buying column keeps Selling aligned.
        mc:cecho(prefix .. string.format("%-" .. BUY_COL_W .. "s ", "---"))
        emitSell()
        mc:cecho("\n")
    end
end

local function renderTickerHeader(inst)
    local mc = inst.tickerHdrMc
    if not mc then return end
    mc:clear()
    -- Offsets match appendTicker: leading space + 3-char icon slot (when
    -- enabled) + name(12) + base(6).
    mc:cecho(string.format(
        "%s<dim_grey>%-12s %-6s %-12s Selling<reset>\n",
        iconsEnabled() and "    " or " ", "Commodity", "Base", "Buying"))
end

local function renderTicker(inst)
    local mc = inst.tickerMc
    if not mc then return end
    mc:clear()
    if #tickerEntries == 0 then
        inst.tickerIdle = true
        mc:cecho("<dim_grey>  Exchange ticker idle — announcements appear here.<reset>\n")
        return
    end
    inst.tickerIdle = false
    for _, e in ipairs(tickerEntries) do appendTicker(inst, e) end
end

-- ── Layout / header controls ──────────────────────────────────────────────────

local function scrollHeightFor(inst)
    local reserved = inst.showTicker and (LAYOUT_TOP + TICK_TOTAL) or LAYOUT_TOP
    return "100%-" .. reserved .. "px"
end

local function showStack(stack, visible)
    if not stack then return end
    if visible then
        stack.colBar:show()
        stack.scroll:show()
    else
        stack.colBar:hide()
        stack.scroll:hide()
    end
end

local function updateTickerButton(inst)
    if not inst.tickerBtn then return end
    if inst.showTicker then
        inst.tickerBtn:echo("<center><font color='#78c878'>📈</font></center>")
        inst.tickerBtn:setToolTip("Ticker ON — click to hide")
    else
        inst.tickerBtn:echo("<center><font color='#3a3a3a'>📈</font></center>")
        inst.tickerBtn:setToolTip("Ticker OFF — click to show")
    end
end

local function updateViewButton(inst)
    if not inst.viewBtn then return end
    if not futuresRankQualifies() then
        inst.viewBtn:hide()
        return
    end
    inst.viewBtn:show()
    local other = (inst.view == "prices") and "Futures" or "Prices"
    inst.viewBtn:echo("<center>" .. other .. "</center>")
    inst.viewBtn:setToolTip("Switch to the " .. other:lower() .. " view")
end

local function applyLayout(inst)
    local h = scrollHeightFor(inst)
    if inst.prices  then inst.prices.scroll:resize("100%", h) end
    if inst.futures then inst.futures.scroll:resize("100%", h) end
    if inst.showTicker then
        inst.tickerHdrMc:show()
        inst.tickerMc:show()
    else
        inst.tickerHdrMc:hide()
        inst.tickerMc:hide()
    end
    updateTickerButton(inst)
end

-- ── Table stack construction ──────────────────────────────────────────────────

local function buildStack(inst, idPrefix, cols)
    local target = inst.target
    local gid    = inst.gid
    local wc     = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_%s_%d", gid, idPrefix, wc)
    end

    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_HDR, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scroll = Geyser.ScrollBox:new({
        name   = wid(),
        x = 0, y = LAYOUT_TOP,
        width  = "100%",
        height = scrollHeightFor(inst),
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
        lbl:setStyleSheet(COL_HDR_CSS)
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

    return {
        colBar       = colBar,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
        tableId      = tableId,
    }
end

local function setView(inst, view)
    if view == "futures" and not inst.futures then
        inst.futures = buildStack(inst, "exfut", f2tFuturesMarketCols())
    end
    inst.view = view
    showStack(inst.prices,  view == "prices")
    showStack(inst.futures, view == "futures")
    updateViewButton(inst)
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

local function refresh(gid)
    local inst = instances[gid]
    if not inst then return end

    -- Rank-aware view: T/F default to futures until the user flips; anyone
    -- else is forced back to prices once rank is known.
    local rank = f2t_get_rank()
    if rank then
        if inst.view == "futures" and not futuresRankQualifies() then
            setView(inst, "prices")
        elseif inst.autoView and inst.view == "prices" and futuresRankQualifies() then
            setView(inst, "futures")
        end
    end
    updateViewButton(inst)

    local atEx = atExchange()
    if inst.title then
        if atEx then
            local planet = gmcp.room.info.area or gmcp.room.info.system or "?"
            inst.title:echo(string.format(
                "<span style='font-size:10px;color:#cccc44;'>%s</span>" ..
                " <span style='font-size:10px;color:#888888;'>live · %s</span>",
                planet, inst.view))
        else
            inst.title:echo(
                "<span style='font-size:10px;color:#888888;'>Step into an exchange for live prices.</span>")
        end
    end

    if inst.view == "futures" and inst.futures then
        f2tTableSetData(inst.futures.tableId, atEx and f2tFuturesMarketRows() or {})
    else
        f2tTableSetData(inst.prices.tableId, atEx and buildPriceRows() or {})
    end
end

local function refreshAll()
    for gid in pairs(instances) do pcall(refresh, gid) end
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
        refresh(gid)
        return
    end

    local hdr = Geyser.Label:new({
        name = gid .. "_exhdr", x = 0, y = 0, width = "100%", height = H_HDR,
    }, target.content)
    hdr:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local title = Geyser.Label:new({
        name = gid .. "_extitle", x = 6, y = 0, width = "-92", height = H_HDR,
    }, hdr)
    title:setStyleSheet("background: transparent; border: none;")

    local viewBtn = Geyser.Label:new({
        name = gid .. "_exview", x = "-86", y = 2, width = 56, height = H_HDR - 4,
    }, hdr)
    viewBtn:setStyleSheet(BTN_CSS)

    local tickerBtn = Geyser.Label:new({
        name = gid .. "_extickbtn", x = "-26", y = 2, width = 22, height = H_HDR - 4,
    }, hdr)
    tickerBtn:setStyleSheet(BTN_CSS)

    local inst = {
        gid        = gid,
        target     = target,
        hdr        = hdr,
        title      = title,
        viewBtn    = viewBtn,
        tickerBtn  = tickerBtn,
        view       = "prices",
        autoView   = true,
        showTicker = true,
        tickerIdle = true,
    }
    instances[gid] = inst

    inst.prices = buildStack(inst, "exprc", priceCols())

    inst.tickerHdrMc = Geyser.MiniConsole:new({
        name = gid .. "_extickhdr",
        x = 0, y = "100%-" .. TICK_TOTAL .. "px",
        width = "100%", height = TICK_HDR_H,
        fontSize = 9,
    }, target.content)
    inst.tickerHdrMc:setColor(12, 14, 22)

    inst.tickerMc = Geyser.MiniConsole:new({
        name = gid .. "_extick",
        x = 0, y = "100%-" .. TICK_H .. "px",
        width = "100%", height = TICK_H,
        fontSize = 9,
    }, target.content)
    inst.tickerMc:setColor(18, 18, 26)
    inst.tickerMc:enableAutoWrap()
    -- Strip the hover-link underline on stock tooltips where supported.
    pcall(setLinkStyleSheet,
        [[color: inherit; text-decoration: none;]],
        [[color: inherit; text-decoration: none;]],
        inst.tickerMc.name)

    viewBtn:setClickCallback(function()
        inst.autoView = false
        setView(inst, inst.view == "prices" and "futures" or "prices")
        refresh(gid)
    end)

    tickerBtn:setClickCallback(function()
        inst.showTicker = not inst.showTicker
        applyLayout(inst)
        if inst.showTicker then renderTicker(inst) end
    end)

    setView(inst, "prices")
    applyLayout(inst)
    renderTickerHeader(inst)
    renderTicker(inst)
    refresh(gid)
end

-- ── Content registration ──────────────────────────────────────────────────────

local function buildExchangeDef()
    return {
        name        = "Exchange",
        description = "Live board for the exchange you are in: prices (or futures for Traders/Financiers) plus a price ticker.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[exchange] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                if inst.prices  then f2tTableDestroy(inst.prices.tableId)  end
                if inst.futures then f2tTableDestroy(inst.futures.tableId) end
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            for _, stack in pairs({ inst.prices, inst.futures }) do
                if stack.contentW ~= newCw then
                    stack.contentW = newCw
                    stack.contentLabel:resize(newCw, stack.contentLabel:get_height())
                    f2tTableOnResize(stack.tableId, newCw)
                end
            end
        end,
        serialize = function(target)
            local inst = instances[target._gid]
            if not inst then return {} end
            return { view = inst.view, showTicker = inst.showTicker, autoView = inst.autoView }
        end,
        restore = function(target, data)
            local inst = instances[target._gid]
            if not inst or type(data) ~= "table" then return end
            if type(data.showTicker) == "boolean" then inst.showTicker = data.showTicker end
            if type(data.autoView)   == "boolean" then inst.autoView   = data.autoView   end
            if data.view == "futures" or data.view == "prices" then
                setView(inst, data.view)
            end
            applyLayout(inst)
            refresh(target._gid)
        end,
        onReveal = function(target)
            refresh(target._gid)
        end,
    }
end

function f2tRegisterExchange()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[exchange] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_exchange", buildExchangeDef())
    if f2t_debug_log then f2t_debug_log("[exchange] registered fed2_exchange content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterExchange)

-- ── Live updates ──────────────────────────────────────────────────────────────
-- Specific sub-events, not "gmcp.exchange": the parent event also fires for
-- every ticker tick, which would re-render the table every few seconds.

registerAnonymousEventHandler("gmcp.exchange.commodities", refreshAll)
registerAnonymousEventHandler("gmcp.exchange.futures",     refreshAll)

local TICK_REFRESH_THROTTLE = 5   -- min seconds between ticker-driven table refreshes
local lastTickRefresh = 0

registerAnonymousEventHandler("gmcp.exchange.commodity", function()
    local e = gmcp and gmcp.exchange and gmcp.exchange.commodity
    if type(e) ~= "table" or not e.name then return end

    local entry = {
        name  = e.name,
        base  = tonumber(e.base),
        buy   = tonumber(e.buy),
        sell  = tonumber(e.sell),
        stock = tonumber(e.stock),
    }
    tickerEntries[#tickerEntries + 1] = entry
    while #tickerEntries > TICKER_MAX do table.remove(tickerEntries, 1) end
    tickerLatest[entry.name] = entry

    for gid, inst in pairs(instances) do
        if inst.showTicker then
            local ok = pcall(appendTicker, inst, entry)
            if not ok then instances[gid] = nil end
        end
    end

    local now = os.time()
    if now - lastTickRefresh >= TICK_REFRESH_THROTTLE then
        lastTickRefresh = now
        refreshAll()
    end
end)

registerAnonymousEventHandler("gmcp.room.info", function()
    if not atExchange() and (#tickerEntries > 0 or next(tickerLatest)) then
        tickerEntries = {}
        tickerLatest  = {}
        for _, inst in pairs(instances) do pcall(renderTicker, inst) end
    end
    refreshAll()
end)

-- ── Settings ──────────────────────────────────────────────────────────────────

f2t_settings_register("exchange", "console_spam", {
    tab         = "F2CE-Tools/Exchange",
    label       = "Ticker spam to console",
    description = "Show the +++ exchange ticker announcements in the main console (the Exchange content gets them via GMCP either way)",
    default     = false,
})

f2t_settings_register("exchange", "show_icons", {
    tab         = "F2CE-Tools/Exchange",
    label       = "Commodity icons",
    description = "Show emoji icons next to commodity names in the prices table and ticker",
    default     = true,
})

-- Re-render live when the icon setting flips.  Hooked once Mux is up; the
-- f2t settings layer has no onChange passthrough.
local function hookIconSetting()
    if not (Mux and Mux.settings and Mux.settings.onChange) then return false end
    Mux.settings.onChange("exchange", "show_icons", function()
        for _, inst in pairs(instances) do
            pcall(renderTickerHeader, inst)
            pcall(renderTicker, inst)
        end
        refreshAll()
    end)
    return true
end

if not hookIconSetting() then
    registerAnonymousEventHandler("muxletReady", hookIconSetting)
end

if f2t_debug_log then f2t_debug_log("[exchange] content module loaded") end
