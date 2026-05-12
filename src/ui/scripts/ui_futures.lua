-- =============================================================================
-- FUTURES TAB
-- Visible to Trader and Financier ranks.
--
-- Market view (at exchange): reads gmcp.exchange live — no game commands needed.
--   Gap = how far the futures price can move favorably before reaching base:
--     LONG:  gap = base - price  (positive when base > price → price trends up)
--     SHORT: gap = price - base  (positive when price > base → price trends down)
--   Futures price converges toward commodity BASE PRICE at ~1ig/ton per tick
--   (every 5-10 min). Gap tells you how many ticks of headroom remain.
--
-- Portfolio view (outside exchange): di futures → held contracts with P&L,
--   margin health, and liquidate links when at the matching exchange.
--   (Portfolio is not available via GMCP — game limitation.)
--
-- Game mechanics (reference):
--   Cost: original contract value at purchase.
--   Margin: deposit held by broker, starts 4,000ig. Adjusted hourly.
--   P&L = margin − 4,000ig.   Margin call if margin < 2,000ig (costs 4k).
--   Auto-liquidated if losses exceed maximum.
--   Broker fee on liquidation: 5% of profit, min 250ig.
--   Trading Rating goal: 300. +1pt per 1k profit, −1pt per 1k loss, −4pts/call.
-- =============================================================================

UI = UI or {}

-- =============================================================================
-- HELPERS
-- =============================================================================

local function strip_commas(s)
    return s and s:gsub(",", "") or s
end

local function fmt_ig(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1000000 then return string.format("%.1fM", n / 1e6)
    elseif a >= 1000  then return string.format("%.1fk", n / 1e3)
    else                   return tostring(math.floor(n)) end
end

local function fmt_ig_signed(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    return (n >= 0 and "+" or "") .. fmt_ig(n)
end

-- Gap in ig/ton in the direction that benefits the contract type.
-- Positive = price has room to move favourably before reaching base.
-- LONG:  gap = base - price  (want price to rise toward base)
-- SHORT: gap = price - base  (want price to fall toward base)
local function opp_gap(contract_type, futures_price, base_price)
    if not base_price then return nil end
    if contract_type == "long" then
        return base_price - futures_price
    else
        return futures_price - base_price
    end
end

-- Colour for an ig/ton gap value.
local function gap_color(gap)
    if not gap then return "dim_grey" end
    if gap >= 100  then return "green"
    elseif gap >= 20  then return "yellow"
    elseif gap >= -20 then return "dim_grey"
    else                   return "red" end
end

local function fmt_gap_str(n)
    if math.abs(n) < 10000 then
        return string.format("%+d", math.floor(n))
    else
        return string.format("%+.1fk", n / 1000)
    end
end

-- Derive exchange price midpoint from GMCP commodity buy/sell fields.
-- buy  = what the exchange pays you (≈ midpoint × 0.9)
-- sell = what the exchange charges you (≈ midpoint × 1.1)
-- Returns nil when the commodity is not traded at this exchange.
local function exchange_midpoint(comm_data)
    if not comm_data then return nil end
    local buy  = comm_data.buy  or 0
    local sell = comm_data.sell or 0
    if buy > 0 and sell > 0 then
        return math.floor((buy + sell) / 2)
    elseif buy > 0 then
        return math.floor(buy / 0.9)
    elseif sell > 0 then
        return math.floor(sell / 1.1)
    end
    return nil
end

-- =============================================================================
-- STATE
-- =============================================================================

UI.futures = UI.futures or {
    portfolio        = {},
    market           = {},
    market_planet    = nil,
    view             = "portfolio",
    capturing        = false,
    capture_buffer   = {},
    capture_triggers = {},
    capture_timer    = nil,
}

-- =============================================================================
-- GMCP MARKET DATA
-- =============================================================================

-- Build the market table directly from gmcp.exchange.
-- Called when the user opens the market view or when gmcp.exchange updates.
local function build_market_from_gmcp()
    local exchange = gmcp and gmcp.exchange
    if not exchange or not exchange.futures then return {} end

    local comms  = exchange.commodities or {}
    local market = {}

    for name_lower, contract in pairs(exchange.futures) do
        local comm_name = nil
        local exc_data  = nil
        for cname, cdata in pairs(comms) do
            if cname:lower() == name_lower then
                comm_name = cname
                exc_data  = cdata
                break
            end
        end

        local base      = exc_data and exc_data.base or nil
        local exc_price = exchange_midpoint(exc_data)
        local fp        = contract.price
        local gap       = opp_gap(contract.type, fp, base)

        -- Mkt: how far the exchange price still needs to move to reach base,
        -- measured in the same favorable direction as Gap.
        -- Positive = exchange is on the right side of base (confirms direction).
        -- Negative = exchange has already crossed base (stale, higher risk).
        local exc_gap = nil
        if base and exc_price then
            if contract.type == "long" then
                exc_gap = base - exc_price
            else
                exc_gap = exc_price - base
            end
        end

        table.insert(market, {
            commodity = comm_name or name_lower,
            type      = contract.type,
            price     = fp,
            base      = base,
            gap       = gap,
            exc       = exc_price,
            exc_gap   = exc_gap,
            suspended = (contract.status == "suspended"),
        })
    end

    return market
end

-- Called when gmcp.exchange fires. Auto-refreshes the market view if active.
function ui_futures_on_gmcp_exchange()
    if not UI.futures then return end
    if UI.futures.view ~= "market" then return end

    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")
    if not at_ex then return end

    UI.futures.market        = build_market_from_gmcp()
    UI.futures.market_planet = gmcp.room.info.area or gmcp.room.info.system
    ui_futures_render_market()
end

-- =============================================================================
-- PORTFOLIO CAPTURE  (timer-based — hides raw di futures output)
-- Portfolio data is not available via GMCP; must parse 'di futures' text.
-- =============================================================================

local function futures_cap_end()
    UI.futures.capturing = false
    for _, id in ipairs(UI.futures.capture_triggers) do killTrigger(id) end
    UI.futures.capture_triggers = {}
    if UI.futures.capture_timer then
        killTimer(UI.futures.capture_timer)
        UI.futures.capture_timer = nil
    end
end

local function futures_cap_reset_timer(on_done)
    if UI.futures.capture_timer then killTimer(UI.futures.capture_timer) end
    UI.futures.capture_timer = tempTimer(0.6, function()
        futures_cap_end()
        if on_done then on_done() end
    end)
end

local function futures_start_capture(on_done)
    futures_cap_end()
    UI.futures.capturing      = true
    UI.futures.capture_buffer = {}

    local function reset_t() futures_cap_reset_timer(on_done) end

    local tid = tempRegexTrigger("^.*$", function()
        if UI.futures.capturing then
            table.insert(UI.futures.capture_buffer, line)
            deleteLine()
            reset_t()
        end
    end)
    table.insert(UI.futures.capture_triggers, tid)
    reset_t()
end

-- =============================================================================
-- PARSE PORTFOLIO  (di futures outside exchange)
-- =============================================================================

local function parse_portfolio()
    UI.futures.portfolio = {}
    local current = nil

    for _, l in ipairs(UI.futures.capture_buffer) do
        local planet, name = l:match("^(.+) Exchange %- (.+) Futures Contract")
        if planet then
            -- Strip ANSI escape codes and trim whitespace from the colored planet name
            planet = planet:gsub("\27%[[%d;]*m", ""):match("^%s*(.-)%s*$") or planet
            if current then table.insert(UI.futures.portfolio, current) end
            current = { planet = planet, name = name }
        elseif current then
            local pos, val = l:match("^%s*(%a+) position.-Value: ([%d,]+)ig")
            if pos and (pos == "Long" or pos == "Short") then
                current.type  = pos:lower()
                current.value = tonumber(strip_commas(val))
            end
            local cost, margin, min_m =
                l:match("Cost: ([%d,]+)ig.-Margin: ([%d,]+)ig.-minimum ([%d,]+)ig")
            if cost then
                current.cost       = tonumber(strip_commas(cost))
                current.margin     = tonumber(strip_commas(margin))
                current.min_margin = tonumber(strip_commas(min_m))
            end
            local max_loss = l:match("Maximum loss: ([%d,]+)ig")
            if max_loss then current.max_loss = tonumber(strip_commas(max_loss)) end
        end
    end

    if current then table.insert(UI.futures.portfolio, current) end

    -- Deduplicate by planet+name in case two di futures responses landed
    -- in the same capture window (rapid double-click).
    local seen, unique = {}, {}
    for _, c in ipairs(UI.futures.portfolio) do
        local key = (c.planet or "") .. "|" .. (c.name or "")
        if not seen[key] then seen[key] = true; table.insert(unique, c) end
    end
    UI.futures.portfolio = unique

    for _, c in ipairs(UI.futures.portfolio) do
        local margin      = c.margin     or 4000
        local min_m       = c.min_margin or 2000
        local max_loss    = c.max_loss   or 15000
        c.pl              = margin - 4000
        local loss_so_far = 4000 - margin
        if margin < min_m then
            c.risk = "call"
        elseif margin < min_m + 1000 then
            c.risk = "warn"
        elseif loss_so_far > max_loss * 0.7 then
            c.risk = "danger"
        else
            c.risk = "ok"
        end
    end
end

-- =============================================================================
-- TABLE SETUP
-- =============================================================================

local function futures_init_tables()
    -- ── Market table ──────────────────────────────────────────────────────────
    -- Commodity | T | Fut | Base | Gap | Exc | Mkt
    --
    -- Gap: base - futures (Long) or futures - base (Short).
    --   Positive = futures price has room to move favorably. Each unit ≈ 1 tick (~5-10 min).
    -- Exc: exchange price midpoint derived from GMCP buy/sell prices.
    -- Mkt: base - exc (Long) or exc - base (Short).
    --   Positive = exchange also on the favorable side of base (confirms direction).
    --   Negative = exchange has already crossed base (potential reversal risk).

    local function mkt_cell(window, content, row)
        if row.suspended then
            window:cechoLink("<maroon>" .. content .. "<reset>", function() end,
                "Trading suspended — price frozen until hour end. Cannot purchase.", true)
        else
            window:cechoLink("<dim_grey>" .. content .. "<reset>", function() end,
                "Already held at this exchange — one contract per commodity per exchange.", true)
        end
    end

    local market_cols = {
        {
            key            = "commodity",
            label          = "Commodity",
            header_tooltip = "Click to buy. Maroon=trading suspended (price frozen). Grey=already owned at this exchange.",
            width          = 10,
            align          = "left",
            header_align   = "left",
            sortable       = true,
            sort_value     = function(r) return (r.commodity or ""):lower() end,
            render         = function(v, row, window, col)
                local w    = col.width
                local text = (v or ""):sub(1, w)
                local pad  = string.rep(" ", math.max(0, w - #text))
                if row.suspended then
                    window:cechoLink("<maroon>" .. text .. pad .. "<reset>", function() end,
                        "Trading suspended — price frozen until hour end. Cannot purchase.", true)
                elseif row.owned then
                    window:cechoLink("<dim_grey>" .. text .. pad .. "<reset>", function() end,
                        "Already held at this exchange — one contract per commodity per exchange.", true)
                else
                    window:cechoLink("<white>" .. text .. pad .. "<reset>",
                        function()
                            send("buy futures " .. (v or ""):lower())
                            table.insert(UI.futures.portfolio, {
                                planet = UI.futures.market_planet,
                                name   = v,
                                type   = row.type,
                            })
                            tempTimer(1.0, function() ui_futures_show_market() end)
                        end,
                        string.format("Buy %s futures contract", v), true)
                end
            end,
        },
        {
            key            = "type",
            label          = "T",
            header_tooltip = "L=Long (profit when futures price rises toward base). S=Short (profit when it falls).",
            width          = 1,
            align          = "center",
            header_align   = "center",
            sortable       = true,
            sort_value     = function(r) return r.type end,
            render         = function(v, row, window, col)
                local display = v == "long" and "L" or "S"
                if row.suspended or row.owned then
                    mkt_cell(window, display, row)
                else
                    local color = v == "long" and "<ansiCyan>" or "<yellow>"
                    window:cecho(color .. display .. "<reset>")
                end
            end,
        },
        {
            key            = "price",
            label          = "Fut",
            header_tooltip = "Futures price per ton — the price you lock in when buying this contract.",
            width          = 4,
            align          = "right",
            header_align   = "right",
            sortable       = true,
            sort_value     = function(r) return r.price or 0 end,
            render         = function(v, row, window, col)
                local n = tonumber(v)
                local s = n and string.format("%4d", n) or " ???"
                if row.suspended or row.owned then
                    mkt_cell(window, s, row)
                else
                    window:cecho("<white>" .. s .. "<reset>")
                end
            end,
        },
        {
            key            = "base",
            label          = "Base",
            header_tooltip = "Commodity base price — the target the futures price converges toward at ~1ig/ton per tick (every 5-10 min). The gap between Base and Fut determines which direction the futures price moves.",
            width          = 4,
            align          = "right",
            header_align   = "right",
            sortable       = true,
            sort_value     = function(r) return r.base or 0 end,
            render         = function(v, row, window, col)
                local n = tonumber(v)
                local s = n and string.format("%4d", n) or " n/a"
                if row.suspended or row.owned then mkt_cell(window, s, row)
                else window:cecho("<dim_grey>" .. s .. "<reset>") end
            end,
        },
        {
            key            = "gap",
            label          = "Gap",
            header_tooltip = "Ticks of favorable movement remaining before futures price reaches base (LONG=base-Fut, SHORT=Fut-base). Each tick is ~1ig/ton every 5-10 min. Green>=100 Yellow>=20 Grey~0 Red=moving wrong way.",
            width          = 6,
            align          = "right",
            header_align   = "right",
            sortable       = true,
            default_sort   = "desc",
            sort_value     = function(r) return r.gap or -9999 end,
            render         = function(v, row, window, col)
                local n = tonumber(v)
                if not n then
                    local s = "   n/a"
                    if row.suspended or row.owned then mkt_cell(window, s, row)
                    else window:cecho("<dim_grey>" .. s .. "<reset>") end
                    return
                end
                local raw = fmt_gap_str(n)
                local s   = string.rep(" ", math.max(0, 6 - #raw)) .. raw
                if row.suspended or row.owned then
                    mkt_cell(window, s, row)
                else
                    window:cecho(string.format("<%s>%s<reset>", gap_color(n), s))
                end
            end,
        },
        {
            key            = "exc",
            label          = "Exc",
            header_tooltip = "Exchange price midpoint (ig/ton) — derived from GMCP buy/sell prices ((buy+sell)/2 when both available). This is the value the game uses when recalculating futures prices each tick. n/a=not traded at this exchange.",
            width          = 4,
            align          = "right",
            header_align   = "right",
            sortable       = true,
            sort_value     = function(r) return r.exc or -1 end,
            render         = function(v, row, window, col)
                local n = tonumber(v)
                if not n then
                    local s = " n/a"
                    if row.suspended or row.owned then mkt_cell(window, s, row)
                    else window:cecho("<dim_grey>" .. s .. "<reset>") end
                    return
                end
                local s = string.format("%4d", n)
                if row.suspended or row.owned then
                    mkt_cell(window, s, row)
                else
                    window:cecho("<white>" .. s .. "<reset>")
                end
            end,
        },
        {
            key            = "exc_gap",
            label          = "Mkt",
            header_tooltip = "Exchange price gap toward base (LONG=base-Exc, SHORT=Exc-base). Positive=exchange is on the favorable side of base, confirming the trade direction. Negative=STALE: exchange has already crossed base. n/a=not traded here.",
            width          = 5,
            align          = "right",
            header_align   = "right",
            sortable       = true,
            sort_value     = function(r) return r.exc_gap or -9999 end,
            render         = function(v, row, window, col)
                local n = tonumber(v)
                if not n then
                    local s = "  n/a"
                    if row.suspended or row.owned then mkt_cell(window, s, row)
                    else window:cecho("<dim_grey>" .. s .. "<reset>") end
                    return
                end
                local raw = fmt_gap_str(n)
                local s   = string.rep(" ", math.max(0, 5 - #raw)) .. raw
                if row.suspended or row.owned then
                    mkt_cell(window, s, row)
                else
                    window:cecho(string.format("<%s>%s<reset>", gap_color(n), s))
                end
            end,
        },
    }

    ui_table_create("futures_market", UI.futures_window, market_cols,
        { column = " ", header = "-" })

    -- ── Portfolio table ───────────────────────────────────────────────────────
    local portfolio_cols = {
        {
            key          = "planet",
            label        = "Planet",
            width        = 8,
            align        = "left",
            header_align = "left",
            sortable     = true,
            sort_value   = function(r) return r.planet:lower() end,
            format       = function(v) return "<ansiCyan>" .. v .. "<reset>" end,
            link         = function(v) expandAlias("nav " .. v .. " exchange") end,
            linkHint     = "Navigate to %s exchange",
        },
        {
            key          = "name",
            label        = "Commod",
            width        = 10,
            align        = "left",
            sortable     = true,
            sort_value   = function(r) return (r.name or ""):lower() end,
            format       = function(v) return "<white>" .. (v or "?") .. "<reset>" end,
        },
        {
            key          = "type",
            label        = "T",
            width        = 1,
            align        = "center",
            header_align = "center",
            sortable     = true,
            sort_value   = function(r) return r.type end,
            format       = function(v)
                if v == "long" then return "<ansiCyan>L<reset>"
                else                return "<yellow>S<reset>" end
            end,
        },
        {
            key          = "pl",
            label        = "P&L",
            width        = 7,
            align        = "right",
            header_align = "right",
            sortable     = true,
            default_sort = "asc",
            sort_value   = function(r) return r.pl or 0 end,
            format       = function(v, row)
                local n     = tonumber(v) or 0
                local color = n > 0 and "green" or (n < 0 and "red" or "dim_grey")
                return string.format("<%s>%s<reset>", color, fmt_ig_signed(n))
            end,
        },
        {
            key          = "margin",
            label        = "Margin",
            width        = 5,
            align        = "right",
            header_align = "right",
            sortable     = true,
            sort_value   = function(r) return r.margin or 0 end,
            render       = function(v, row, window, col)
                local n     = tonumber(v) or 4000
                local color = (row.risk == "call" or row.risk == "danger") and "red"
                           or row.risk == "warn" and "yellow"
                           or "dim_grey"
                window:cecho(string.format("<%s>%5s<reset>", color, fmt_ig(n)))
            end,
        },
        {
            key    = "risk",
            label  = "M",
            header_tooltip = "Margin health. ✓=healthy  !=approaching minimum  ✗=margin call (below 2,000ig)",
            width  = 1,
            align  = "center",
            render = function(v, row, window, col)
                local tips = {
                    ok     = "Margin healthy",
                    warn   = "Margin warning — approaching minimum (2,000ig)",
                    call   = "Margin call — margin below 2,000ig (4,000ig charge pending)",
                    danger = "Danger — losses approaching maximum",
                }
                local icons = {
                    ok     = "<green>✓<reset>",
                    warn   = "<yellow>!<reset>",
                    call   = "<red>✗<reset>",
                    danger = "<red>✗<reset>",
                }
                window:cechoLink(icons[v] or "<dim_grey>?<reset>", function() end,
                    tips[v] or "Unknown", true)
            end,
        },
        {
            key            = "planet",
            label          = "[-]",
            header_tooltip = "Liquidate contract (must be at matching exchange)",
            width          = 3,
            align          = "center",
            render         = function(planet, row, window, col)
                local room  = gmcp and gmcp.room and gmcp.room.info
                local at_ex = room and (room.area == planet) and
                    f2t_has_value(room.flags or {}, "exchange")
                if at_ex then
                    local comm = (row.name or ""):lower()
                    window:cechoLink("<red>[-]<reset>", function()
                        send("liquidate " .. comm)
                        tempTimer(1.0, function() ui_futures_refresh() end)
                    end, "Liquidate " .. (row.name or "") .. " contract", true)
                else
                    window:cecho("<dim_grey>---<reset>")
                end
            end,
        },
    }

    ui_table_create("futures_portfolio", UI.futures_window, portfolio_cols,
        { column = " ", header = "-" })
end

-- =============================================================================
-- RENDER MARKET
-- =============================================================================

function ui_futures_render_market()
    if not UI.futures_window then return end

    local market = UI.futures.market
    local planet = UI.futures.market_planet or "?"

    UI.futures_window:clear()
    UI.futures_window:cecho(
        string.format("<ansiYellow>%s<reset>  <dim_grey>live<reset>\n", planet)
    )
    UI.futures_window:cecho(
        "<dim_grey>Gap=ticks of favorable movement remaining to base (~1ig/5-10min). " ..
        "Mkt=exchange price gap toward base (neg=exchange already crossed base). " ..
        "Maroon=suspended (price frozen until hour reset). Green≥100 Yellow≥20. Click name to buy.<reset>\n"
    )

    if #market == 0 then
        UI.futures_window:cecho("\n<dim_grey>No contracts available here.<reset>\n")
        return
    end

    -- Cross-reference portfolio to mark contracts already owned at this exchange.
    -- c.planet is the planet name stripped from "X Exchange - Y Futures Contract",
    -- which always matches gmcp.room.info.area for the exchange the player is in.
    local owned_set = {}
    if #UI.futures.portfolio > 0 then
        local ri  = gmcp and gmcp.room and gmcp.room.info or {}
        local loc = (ri.area or UI.futures.market_planet or ""):lower()
        for _, c in ipairs(UI.futures.portfolio) do
            if (c.planet or ""):lower() == loc then
                owned_set[(c.name or ""):lower()] = true
            end
        end
    end
    for _, contract in ipairs(market) do
        contract.owned = owned_set[(contract.commodity or ""):lower()] or false
    end

    ui_table_set_data("futures_market", market)
end

-- =============================================================================
-- RENDER PORTFOLIO
-- =============================================================================

function ui_futures_render_portfolio()
    if not UI.futures_window then return end

    local portfolio = UI.futures.portfolio

    UI.futures_window:clear()

    if #portfolio == 0 then
        UI.futures_window:cecho(
            "\n<dim_grey>No contracts held. " ..
            "At an exchange, click 📈 Market to see available contracts.<reset>\n"
        )
        return
    end

    local total_pl = 0
    for _, c in ipairs(portfolio) do total_pl = total_pl + (c.pl or 0) end
    local pl_color = total_pl > 0 and "green" or (total_pl < 0 and "red" or "dim_grey")
    UI.futures_window:cecho(
        string.format("<dim_grey>%d contract%s  Total P&L: <%s>%s<reset><dim_grey>  " ..
            "⚡=margin health (hover). Planet=nav. Liq=liquidate.<reset>\n",
            #portfolio, #portfolio ~= 1 and "s" or "",
            pl_color, fmt_ig_signed(total_pl))
    )

    ui_table_set_data("futures_portfolio", portfolio)
end

-- =============================================================================
-- SHOW / REFRESH ENTRY POINTS
-- =============================================================================

function ui_futures_show_portfolio()
    if UI.futures.capturing then return end

    UI.futures.view = "portfolio"
    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if at_ex then
        -- di futures inside an exchange shows market data, not portfolio.
        -- Show the last-captured portfolio with a stale notice, or a hint.
        UI.futures_window:clear()
        if #UI.futures.portfolio > 0 then
            UI.futures_window:cecho(
                "<yellow>⚠ Showing last-known contracts. " ..
                "Step outside the exchange to refresh.<reset>\n"
            )
            ui_table_set_data("futures_portfolio", UI.futures.portfolio)
        else
            UI.futures_window:cecho(
                "\n<dim_grey>  Step outside the exchange to load your held contracts.<reset>\n"
            )
        end
    else
        futures_start_capture(function()
            parse_portfolio()
            ui_futures_render_portfolio()
        end)
        send("di futures", false)
    end
end

function ui_futures_show_market()
    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if not at_ex then
        cecho("\n<red>[futures]<reset> Must be at a trading exchange to view the market.\n")
        return
    end

    UI.futures.view          = "market"
    UI.futures.market        = build_market_from_gmcp()
    UI.futures.market_planet = gmcp.room.info.area or gmcp.room.info.system
    ui_futures_render_market()
end

function ui_futures_refresh()
    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if at_ex then
        if UI.futures.view == "portfolio" then
            ui_futures_render_portfolio()
        else
            ui_futures_show_market()
        end
    else
        ui_futures_show_portfolio()
    end
end

-- =============================================================================
-- BUTTON STATE  (called on gmcp.room.info)
-- =============================================================================

function ui_futures_update_buttons()
    if not UI.futures_market_btn then return end

    local at_ex = gmcp and gmcp.room and gmcp.room.info and
        f2t_has_value(gmcp.room.info.flags or {}, "exchange")

    if at_ex then
        UI.futures_market_btn:setStyleSheet(UI.style.button_css)
        UI.futures_market_btn:setClickCallback("ui_futures_show_market")
        UI.futures_market_btn:setToolTip("View contracts available at this exchange (live GMCP data)")
    else
        UI.futures_market_btn:setStyleSheet(UI.style.disabled_button_css)
        UI.futures_market_btn:setClickCallback(function() end)
        UI.futures_market_btn:setToolTip("Enter a trading exchange to view available contracts")
    end
end

-- =============================================================================
-- TAB SETUP  (called from ui_build)
-- =============================================================================

function ui_futures()
    UI.futures_portfolio_btn = Geyser.Label:new({
        name    = "UI.futures_portfolio_btn",
        message = "<center>📋 My Contracts</center>",
    }, UI.futures_button_bar)
    UI.futures_portfolio_btn:setStyleSheet(UI.style.button_css)
    UI.futures_portfolio_btn:setClickCallback("ui_futures_show_portfolio")
    UI.futures_portfolio_btn:setToolTip("Your held contracts and P&L (di futures)")

    UI.futures_market_btn = Geyser.Label:new({
        name    = "UI.futures_market_btn",
        message = "<center>📈 Market</center>",
    }, UI.futures_button_bar)
    UI.futures_market_btn:setStyleSheet(UI.style.disabled_button_css)
    UI.futures_market_btn:setClickCallback(function() end)
    UI.futures_market_btn:setToolTip("Enter a trading exchange to view available contracts")

    UI.futures = {
        portfolio        = {},
        market           = {},
        market_planet    = nil,
        view             = "portfolio",
        capturing        = false,
        capture_buffer   = {},
        capture_triggers = {},
        capture_timer    = nil,
    }

    futures_init_tables()

    ui_futures_render_portfolio()
end
