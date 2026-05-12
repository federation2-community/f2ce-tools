-- =============================================================================
-- ui_company  —  Company / Business management panel
-- Three visual sections (OVERVIEW · FACTORIES · FINANCIALS) inside one tab.
-- Sections are NOT Adjustable.TabWindow tabs — plain show/hide containers.
-- =============================================================================

UI         = UI or {}
UI.company = UI.company or {
    dialog           = nil,
    capture_triggers = {},
    capture_timer    = nil,
    active_section   = "overview",
    _div_input       = nil,
}

-- =============================================================================
-- HELPERS
-- =============================================================================

local function fmt(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local abs, sign = math.abs(n), n < 0 and "-" or ""
    if abs >= 1000000 then return string.format("%s%.2fM", sign, abs/1e6)
    elseif abs >= 1000 then return string.format("%s%.1fk", sign, abs/1e3)
    else                    return string.format("%s%d",   sign, abs) end
end

local function fmtc(n)
    -- comma-separated integer
    if not n then return "?" end
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,","")
    return (n < 0 and "-" or "") .. s
end

local function sum_shares(c)
    if not c or not c.shareholders then return 10000 end
    local t = 0
    for _, sh in ipairs(c.shareholders) do t = t + (sh.quantity or 0) end
    return t > 0 and t or 10000
end

local function eff_pct(fac)
    if not fac.max_efficiency or fac.max_efficiency == 0 then return 100 end
    return math.floor(fac.efficiency / fac.max_efficiency * 100)
end

local function strip_the(s)
    if not s then return "" end
    return s:gsub("^[Tt]he ", "")
end

local _uid_n = 0
local function _uid(p)
    _uid_n = _uid_n + 1
    return (p or "cow") .. _uid_n
end

-- =============================================================================
-- CAPTURE / REFRESH — hides di company / di business output
-- =============================================================================

local function _cap_end()
    UI.company.capturing = false
    for _, id in ipairs(UI.company.capture_triggers) do killTrigger(id) end
    UI.company.capture_triggers = {}
    if UI.company.capture_timer then killTimer(UI.company.capture_timer) end
    UI.company.capture_timer = nil
end

function ui_company_refresh()
    _cap_end()
    UI.company.capturing = true
    local function reset_t()
        if UI.company.capture_timer then killTimer(UI.company.capture_timer) end
        UI.company.capture_timer = tempTimer(0.8, _cap_end)
    end
    local tid = tempRegexTrigger("^.*$", function()
        if UI.company.capturing then deleteLine(); reset_t() end
    end)
    table.insert(UI.company.capture_triggers, tid)
    reset_t()
    local cmd = f2t_is_rank_or_above("Manufacturer") and "di company" or "di business"
    send(cmd, false)
end

-- =============================================================================
-- SECTION NAV CSS  (slim bottom-border indicator, never looks like a tab)
-- =============================================================================

local _NAV_ACTIVE = [[
    QLabel {
        background-color: rgba(16,20,34,255);
        color: rgba(190,215,255,255);
        border-bottom: 3px solid rgba(90,155,255,240);
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
]]
local _NAV_IDLE = [[
    QLabel {
        background-color: rgba(10,12,22,220);
        color: rgba(75,88,115,220);
        border-bottom: 3px solid transparent;
        font-size: 12px;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(18,22,38,235);
        color: rgba(140,160,205,230);
        border-bottom: 3px solid rgba(60,105,195,150);
    }
]]

-- =============================================================================
-- DIALOG CSS
-- =============================================================================

local _DLG_FRAME = [[
    background-color: rgba(10,12,22,254);
    border: 2px solid rgba(255,255,255,0.42);
    border-radius: 8px;
]]
local _DLG_HDR = [[
    background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
        stop:0 rgba(44,50,78,255), stop:1 rgba(22,26,44,255));
    color: rgba(220,230,255,255);
    font-size: 16px; font-weight: bold;
    font-family: "Consolas","Monaco",monospace;
    border-top-left-radius: 6px; border-top-right-radius: 6px;
    border-bottom: 1px solid rgba(255,255,255,0.16);
    padding: 0 16px;
]]
local _DLG_BODY = [[
    background: transparent;
    color: rgba(198,210,238,255);
    font-size: 14px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 16px;
]]
local _DLG_SUB = [[
    background: transparent;
    color: rgba(105,125,180,255);
    font-size: 12px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 16px;
]]
local _DLG_DIV = [[ background-color: rgba(255,255,255,0.09); border: none; ]]

local _DLG_BTN = [[
    QLabel {
        background-color: rgba(36,40,62,230);
        color: rgba(178,190,225,255);
        border: 1px solid rgba(85,98,140,210);
        border-radius: 5px;
        font-size: 13px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(52,60,95,245);
        border-color: rgba(105,158,255,210);
        color: white;
    }
]]
local _DLG_OK = [[
    QLabel {
        background-color: rgba(18,58,34,240);
        color: rgba(115,222,148,255);
        border: 1px solid rgba(48,152,78,215);
        border-radius: 5px;
        font-size: 13px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(26,82,46,255);
        border-color: rgba(65,210,108,235);
        color: rgba(178,255,200,255);
    }
]]
local _DLG_DANGER = [[
    QLabel {
        background-color: rgba(82,16,16,245);
        color: rgba(255,122,118,255);
        border: 1px solid rgba(175,48,48,215);
        border-radius: 5px;
        font-size: 13px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(124,20,20,255);
        border-color: rgba(222,72,70,235);
        color: rgba(255,172,168,255);
    }
]]
local _DLG_PRESET = [[
    QLabel {
        background-color: rgba(28,42,72,230);
        color: rgba(135,172,255,255);
        border: 1px solid rgba(65,108,200,185);
        border-radius: 5px;
        font-size: 11px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(42,64,118,245);
        border-color: rgba(95,148,255,225);
        color: rgba(178,208,255,255);
    }
]]
local _DLG_INPUT = [[
    background-color: rgba(6,8,18,248);
    color: rgba(208,220,252,255);
    font-size: 14px;
    font-family: "Consolas","Monaco",monospace;
    border: 1px solid rgba(255,255,255,0.36);
    border-radius: 5px;
    padding-left: 12px;
]]

-- =============================================================================
-- DIALOG HELPERS
-- =============================================================================

local function _dlg_close()
    if UI.company.dialog then
        UI.company.dialog:hide()
        UI.company.dialog = nil
    end
    UI.company._div_input = nil
end

local function _dlg_lbl(par, x, y, w, h, txt, css)
    local l = Geyser.Label:new({ name=_uid("cdl"), x=x, y=y, width=w, height=h }, par)
    l:setStyleSheet(css or _DLG_BODY)
    if txt and txt ~= "" then l:echo(txt) end
    return l
end

local function _dlg_btn(par, x, y, w, h, lbl, css, cb)
    local b = Geyser.Label:new({ name=_uid("cdb"), x=x, y=y, width=w, height=h }, par)
    b:setStyleSheet(css)
    b:echo("<center>"..lbl.."</center>")
    b:setClickCallback(cb)
    return b
end

local function _dlg_root(dw, dh)
    _dlg_close()
    local sw, sh = getMainWindowSize()
    local d = Geyser.Label:new({
        name=_uid("cdlg"),
        x=math.floor((sw-dw)/2), y=math.floor((sh-dh)/2),
        width=dw, height=dh,
    })
    d:setStyleSheet(_DLG_FRAME)
    d:raise()
    UI.company.dialog = d
    return d
end

-- =============================================================================
-- DIALOGS
-- =============================================================================

local function _dlg_confirm(title, body, ok_lbl, ok_fn, danger)
    local dw, dh = 400, 178
    local d = _dlg_root(dw, dh)
    _dlg_lbl(d,  0,  0, dw, 44, title,  _DLG_HDR)
    _dlg_lbl(d,  0, 45, dw,  1, "",     _DLG_DIV)
    _dlg_lbl(d,  0, 50, dw, 84, body,   _DLG_BODY)
    _dlg_btn(d, 16, dh-44, 122, 32, "Cancel",   _DLG_BTN,               _dlg_close)
    _dlg_btn(d, dw-138, dh-44, 122, 32, ok_lbl, danger and _DLG_DANGER or _DLG_OK,
        function() _dlg_close(); ok_fn() end)
end

local function _dlg_wages(fac_num, cur_wages)
    local dw, dh = 370, 206
    local d = _dlg_root(dw, dh)
    _dlg_lbl(d, 0,   0, dw, 44, "Set Wages — Factory #"..fac_num, _DLG_HDR)
    _dlg_lbl(d, 0,  45, dw,  1, "",                               _DLG_DIV)
    _dlg_lbl(d, 0,  50, dw, 24, "Wages per cycle (minimum 40ig):", _DLG_BODY)
    _dlg_lbl(d, 0,  72, dw, 20, "Higher wages improve worker productivity.", _DLG_SUB)

    local inp = Geyser.CommandLine:new({ name=_uid("cinp"), x=16, y=96, width=dw-32, height=36 }, d)
    inp:setStyleSheet(_DLG_INPUT)
    inp:print(tostring(cur_wages or 40))

    _dlg_btn(d, 16, dh-44, 122, 32, "Cancel", _DLG_BTN, _dlg_close)
    local ok = _dlg_btn(d, dw-138, dh-44, 122, 32, "Set Wages", _DLG_OK, function() end)
    local function apply()
        local w = tonumber(inp:getText())
        if not w or w < 40 then cecho("\n<red>[company]<reset> Minimum 40ig\n"); return end
        _dlg_close()
        send(string.format("set factory %d wages %d", fac_num, w), false)
        tempTimer(0.5, ui_company_refresh)
    end
    inp:setAction(apply)
    ok:setClickCallback(apply)
end

local function _dlg_dividend()
    _dlg_close()
    local c = gmcp and gmcp.char and gmcp.char.company
    if not c then return end

    local shares  = sum_shares(c)
    local profit  = c.profit or 0
    local eps     = shares > 0 and math.floor(profit / shares) or 0
    local sv      = c.share_value or 0
    local cur_div = c.dividend or 0
    local s50     = math.max(1, math.min(2000, math.floor(eps * 0.5)))
    local s100    = math.max(1, math.min(2000, eps))

    local dw, dh = 440, 310
    local d = _dlg_root(dw, dh)
    _dlg_lbl(d, 0,  0, dw, 44, "Issue Dividend", _DLG_HDR)
    _dlg_lbl(d, 0, 45, dw,  1, "", _DLG_DIV)

    local pe  = (sv > 0 and eps > 0) and string.format("%.1f", sv/eps) or "N/A"
    local pd  = cur_div > 0 and string.format("%.1f", sv/cur_div) or "&#8734;"
    _dlg_lbl(d, 0, 50, dw, 22,
        string.format("EPS  <b>%sig/sh</b>  &nbsp;  Share  <b>%sig</b>  &nbsp;  P/E  <b>%s</b>",
            fmtc(eps), fmtc(sv), pe), _DLG_BODY)
    _dlg_lbl(d, 0, 72, dw, 22,
        string.format("Current dividend  <b>%sig/sh</b>  &nbsp;  P/D  <b>%s</b>  &nbsp;  Shares  <b>%s</b>",
            fmtc(cur_div), pd, fmtc(shares)), _DLG_BODY)
    _dlg_lbl(d, 0, 96, dw,  1, "", _DLG_DIV)
    _dlg_lbl(d, 0,101, dw, 18, "QUICK PRESETS", _DLG_SUB)

    local inp_ref = {}  -- forward ref so presets can fill it

    local PW, PH = 128, 42
    local function make_preset(x, label_top, label_bot, val)
        local b = Geyser.Label:new({ name=_uid("cpr"), x=x, y=120, width=PW, height=PH }, d)
        b:setStyleSheet(_DLG_PRESET)
        b:echo(string.format("<center>%s<br><b>%sig/sh</b></center>", label_top, fmtc(val)))
        b:setClickCallback(function()
            if inp_ref[1] then inp_ref[1]:clear(); inp_ref[1]:print(tostring(val)) end
        end)
    end
    make_preset(14,        "50% of EPS", "",   s50)
    make_preset(14+PW+8,   "100% of EPS", "",  s100)
    make_preset(14+PW*2+16,"Maximum", "",       2000)

    _dlg_lbl(d, 0, 166, dw, 1, "", _DLG_DIV)
    _dlg_lbl(d, 0, 171, dw, 22, "Custom amount per share (1 – 2000 ig):", _DLG_BODY)

    local inp = Geyser.CommandLine:new({ name=_uid("cinp"), x=16, y=196, width=dw-32, height=36 }, d)
    inp:setStyleSheet(_DLG_INPUT)
    inp:print(tostring(s50))
    inp_ref[1] = inp
    UI.company._div_input = inp

    _dlg_btn(d, 16, dh-46, 130, 32, "Cancel", _DLG_BTN, _dlg_close)
    local ok = _dlg_btn(d, dw-146, dh-46, 130, 32, "Issue Dividend", _DLG_OK, function() end)
    local function apply()
        local amt = tonumber(inp:getText())
        if not amt or amt < 1 or amt > 2000 then
            cecho("\n<red>[company]<reset> Dividend must be 1–2000ig/share\n"); return
        end
        _dlg_close()
        send(string.format("issue dividend %d", amt), false)
        tempTimer(0.5, ui_company_refresh)
    end
    inp:setAction(apply)
    ok:setClickCallback(apply)
end

local function _dlg_buy_shares(is_treasury, cur_qty)
    local title = is_treasury and "Buy Treasury Shares" or "Buy Personal Shares"
    local body  = is_treasury
        and "Buy shares into the company treasury.<br>Reduces external shareholder influence.<br>Cost deducted from company cash."
        or  string.format("Buy personal shares.<br>You currently hold <b>%s shares</b>.<br>Increases your dividend payout each cycle.", fmtc(cur_qty or 0))
    local dw, dh = 420, 222
    local d = _dlg_root(dw, dh)
    _dlg_lbl(d, 0,  0, dw, 44, title, _DLG_HDR)
    _dlg_lbl(d, 0, 45, dw,  1, "",    _DLG_DIV)
    _dlg_lbl(d, 0, 50, dw, 70, body,  _DLG_BODY)
    _dlg_lbl(d, 0,122, dw,  1, "",    _DLG_DIV)
    _dlg_lbl(d, 0,127, dw, 22, "Number of shares to buy:", _DLG_BODY)

    local inp = Geyser.CommandLine:new({ name=_uid("cinp"), x=16, y=152, width=dw-32, height=36 }, d)
    inp:setStyleSheet(_DLG_INPUT)
    inp:print("100")

    _dlg_btn(d, 16, dh-44, 122, 32, "Cancel", _DLG_BTN, _dlg_close)
    local ok = _dlg_btn(d, dw-138, dh-44, 122, 32, "Buy", _DLG_OK, function() end)
    local function apply()
        local qty = tonumber(inp:getText())
        if not qty or qty < 1 then cecho("\n<red>[company]<reset> Enter a valid quantity\n"); return end
        _dlg_close()
        local cmd = is_treasury and string.format("buy %d treasury", qty) or string.format("buy %d shares", qty)
        send(cmd, false)
        tempTimer(0.5, ui_company_refresh)
    end
    inp:setAction(apply)
    ok:setClickCallback(apply)
end

local function _dlg_info(title, body)
    local dw, dh = 400, 178
    local d = _dlg_root(dw, dh)
    _dlg_lbl(d,  0,  0, dw, 44, title, _DLG_HDR)
    _dlg_lbl(d,  0, 45, dw,  1, "",    _DLG_DIV)
    _dlg_lbl(d,  0, 50, dw, 84, body,  _DLG_BODY)
    _dlg_btn(d, math.floor((dw-122)/2), dh-44, 122, 32, "OK", _DLG_BTN, _dlg_close)
end

local function _dlg_freeze()
    local c = gmcp and gmcp.char and gmcp.char.company
    if not c then return end
    local freezing = (c.status == "running")
    if not freezing then
        _dlg_info("Company Frozen",
            string.format("<b>%s</b> is currently frozen.<br><br>To unfreeze, you must log out<br>and log back in.", c.name or "company"))
        return
    end
    _dlg_confirm("Freeze Company",
        string.format("<b>%s</b><br>Pause all factory cycles until unfrozen.<br>Workers remain on idle wages.", c.name or "company"),
        "Freeze",
        function()
            send("freeze company", false)
            tempTimer(0.5, ui_company_refresh)
        end,
        true)
end

-- =============================================================================
-- SECTION SWITCHER
-- =============================================================================

local _SECTIONS = { "overview", "factories", "financials" }

local function _show_section(name)
    for _, s in ipairs(_SECTIONS) do
        local panel = UI["co_sec_" .. s]
        local btn   = UI["co_nav_" .. s]
        if panel then if s == name then panel:show() else panel:hide() end end
        if btn   then btn:setStyleSheet(s == name and _NAV_ACTIVE or _NAV_IDLE) end
    end
    UI.company.active_section = name
end

-- =============================================================================
-- OVERVIEW RENDER
-- =============================================================================

local function _render_overview()
    local w = UI.co_ov_win
    if not w then return end
    w:clear()

    local c = gmcp and gmcp.char and gmcp.char.company
    if not c then
        w:cecho("\n\n<dim_grey>  No company data.  Click  ↻  to refresh.\n")
        return
    end

    local is_mfr = f2t_is_rank_or_above("Manufacturer")
    local HR     = "<dim_grey>  ──────────────────────────────────────<reset>\n"

    -- Name + status
    local sc = (c.status == "running") and "ansiGreen" or "ansiYellow"
    local st = (c.status == "running") and "● RUNNING" or "⊘ FROZEN"
    w:cecho(string.format("\n  <white><b>%s</b><reset>\n", c.name or "Unknown Company"))
    w:cecho("  ")
    w:cechoLink(string.format("[<%s>%s<reset>]", sc, st), function() _dlg_freeze() end,
        "Click to freeze/unfreeze", true)
    w:cecho("\n" .. HR)

    -- Identity
    if c.ceo    then w:cecho(string.format("  <dim_grey>CEO          <reset><white>%s<reset>\n", c.ceo)) end
    if c.planet then w:cecho(string.format("  <dim_grey>HQ Planet    <reset><white>%s<reset>\n", c.planet)) end
    if c.formed then w:cecho(string.format("  <dim_grey>Founded      <reset><white>%s<reset>\n", c.formed)) end
    w:cecho(string.format("  <dim_grey>Cycles Run   <reset><white>%d<reset>\n", c.total_cycles or 0))
    if c.days_left then
        local dc = c.days_left < 10 and "ansiRed" or "ansiYellow"
        w:cecho(string.format("  <dim_grey>Days Left    <reset><%s>%d days<reset>\n", dc, c.days_left))
    end

    -- Repair alerts
    if is_mfr and c.factories then
        local alerts = {}
        for _, fac in ipairs(c.factories) do
            local pct = eff_pct(fac)
            if pct < 80 then
                table.insert(alerts, string.format("  <ansiRed>⚠  Factory #%d  (%s)  —  %d%% eff<reset>",
                    fac.number, strip_the(fac.planet or "?"), pct))
            end
        end
        if #alerts > 0 then
            w:cecho("\n" .. HR)
            w:cecho("  <ansiRed><b>⚠  REPAIR ALERTS<reset>\n")
            for _, a in ipairs(alerts) do w:cecho(a .. "\n") end
        end
    end

    -- Financials
    local profit = c.profit or 0
    local pc     = profit >= 0 and "ansiGreen" or "ansiRed"
    w:cecho("\n" .. HR)
    w:cecho("  <dim_grey><b>FINANCIALS<reset>\n")
    w:cecho(string.format("  <dim_grey>Cash         <reset><ansiCyan>%sig<reset>\n", fmtc(c.cash)))
    w:cecho(string.format("  <dim_grey>Profit       <reset><%s>%sig<reset>\n", pc, fmtc(profit)))
    if c.tax then
        w:cecho(string.format("  <dim_grey>Tax Paid     <reset><white>%sig<reset>\n", fmtc(c.tax)))
    end
    if c.revenue then
        if c.revenue.income   then w:cecho(string.format("  <dim_grey>Revenue      <reset><ansiGreen>+%sig<reset>\n", fmtc(c.revenue.income))) end
        if c.revenue.expenses then w:cecho(string.format("  <dim_grey>Expenses     <reset><ansiRed>-%sig<reset>\n",   fmtc(c.revenue.expenses))) end
    end
    if c.capital then
        local ce = tonumber(c.capital.expenditure) or 0
        local cr = tonumber(c.capital.receipts)    or 0
        if ce > 0 then w:cecho(string.format("  <dim_grey>Capital Exp  <reset><ansiRed>-%sig<reset>\n",   fmtc(ce))) end
        if cr > 0 then w:cecho(string.format("  <dim_grey>Capital Rec  <reset><ansiGreen>+%sig<reset>\n", fmtc(cr))) end
    end

    -- Investor KPIs (Manufacturer+)
    if is_mfr then
        local shares = sum_shares(c)
        local sv     = c.share_value  or 0
        local div    = c.dividend     or 0
        local da     = c.disaffection or 0
        local eps    = shares > 0 and math.floor(profit / shares) or 0
        local pe_s   = (sv > 0 and eps > 0) and string.format("%.1f", sv/eps) or "N/A"
        local pd_s   = div > 0 and string.format("%.1f", sv/div) or "<ansiRed>none<reset>"
        local da_c   = da < 20 and "ansiGreen" or (da < 50 and "ansiYellow" or "ansiRed")

        w:cecho("\n" .. HR)
        w:cecho("  <dim_grey><b>INVESTORS<reset>\n")
        w:cecho(string.format("  <dim_grey>Disaffection <reset><%s>%d%%<reset>\n", da_c, da))
        w:cecho(string.format("  <dim_grey>Share Price  <reset><white>%sig<reset>\n", fmtc(sv)))
        w:cecho(string.format("  <dim_grey>Dividend     <reset><white>%sig/sh<reset>  <dim_grey>  P/D <reset><white>%s<reset>\n", fmtc(div), pd_s))
        w:cecho(string.format("  <dim_grey>EPS          <reset><white>%sig/sh<reset>  <dim_grey>  P/E <reset><white>%s<reset>\n", fmtc(eps), pe_s))
        w:cecho(string.format("  <dim_grey>Shares       <reset><white>%s<reset>\n", fmtc(shares)))
        w:cecho(string.format("  <dim_grey>Market Cap   <reset><white>%s<reset>\n", fmt(sv * shares)))

        if (c.total_cycles or 0) >= 4 and profit > 0 then
            w:cecho("\n  <ansiGreen>★ Eligible for Financier promotion<reset>\n")
        end
    end
end

-- =============================================================================
-- FACTORIES RENDER  (table with inline action icons)
-- =============================================================================

local function _init_factory_table()
    local cols = {
        {
            key="fac_num", label="#", width=3, align="right", header_align="right",
            sortable=true, sort_value=function(r) return tonumber(r.fac_num) end,
            format=function(v) return "<ansiCyan><u>"..v.."</u><reset>" end,
            link=function(v, row) send("di factory "..row.fac_num) end,
            linkHint="di factory #%s",
        },
        {
            key="planet_s", label="Planet", width=12, align="left",
            sortable=true, sort_value=function(r) return r.planet_s:lower() end,
            format=function(v) return "<white>"..v.."<reset>" end,
            link=function(v, row) if row.planet_r then f2t_map_navigate(row.planet_r) end end,
            linkHint="Navigate to %s",
        },
        {
            key="output_s", label="Output", width=10, align="left",
            sortable=true, sort_value=function(r) return r.output_s:lower() end,
            format=function(v) return "<dim_grey>"..v.."<reset>" end,
        },
        {
            key="eff_s", label="Eff", width=5, align="right", header_align="right",
            sortable=true, sort_value=function(r) return r.eff_n end,
            format=function(v, row)
                local c = row.eff_n >= 90 and "ansiGreen" or (row.eff_n >= 70 and "ansiYellow" or "ansiRed")
                return row.eff_n < 100
                    and string.format("<%s><u>%s</u><reset>", c, v)
                    or  string.format("<%s>%s<reset>",        c, v)
            end,
            link=function(v, row)
                if row.eff_n < 100 then
                    _dlg_confirm("Repair Factory",
                        string.format("<b>Factory #%d — %s</b><br>Efficiency: <b>%d%%</b>  (repair restores +5%%)<br>Cost deducted from company cash.",
                            row.fac_num, strip_the(row.planet_r or "?"), row.eff_n),
                        "Repair",
                        function()
                            send(string.format("repair factory %d", row.fac_num), false)
                            tempTimer(0.5, ui_company_refresh)
                        end)
                end
            end,
            linkHint="Click to repair factory",
        },
        -- ▶/■  stop/start
        {
            key="fac_num", label="St", width=nil,
            render=function(v, row, window)
                local running = (row.fac_status == 0)
                local icon    = running and "<ansiGreen>▶<reset>" or "<ansiRed>■<reset>"
                window:cechoLink(icon, function()
                    if running then
                        _dlg_confirm("Stop Factory",
                            string.format("<b>Factory #%d — %s</b><br>Stop production? Workers idle until restarted.", row.fac_num, strip_the(row.planet_r or "?")),
                            "Stop",
                            function()
                                send(string.format("set factory %d status stop", row.fac_num), false)
                                tempTimer(0.5, ui_company_refresh)
                            end)
                    else
                        _dlg_confirm("Start Factory",
                            string.format("<b>Factory #%d — %s</b><br>Restart production?", row.fac_num, strip_the(row.planet_r or "?")),
                            "Start",
                            function()
                                send(string.format("set factory %d status run", row.fac_num), false)
                                tempTimer(0.5, ui_company_refresh)
                            end)
                    end
                end, running and "Stop factory" or "Start factory", true)
            end,
        },
        -- $ wages
        {
            key="fac_num", label="$", width=nil,
            render=function(v, row, window)
                window:cechoLink("<ansiYellow>$<reset>", function()
                    _dlg_wages(row.fac_num, row.wages)
                end, "Set wages — factory #"..row.fac_num, true)
            end,
        },
        -- ✕ destroy
        {
            key="fac_num", label="X", width=nil,
            render=function(v, row, window)
                window:cechoLink("<ansiRed>x<reset>", function()
                    _dlg_confirm("Destroy Factory",
                        string.format("<b>DESTROY Factory #%d?</b><br>%s on %s<br>This action <b>cannot be undone</b>.",
                            row.fac_num, row.output_r or "?", strip_the(row.planet_r or "?")),
                        "Destroy",
                        function()
                            send(string.format("destroy factory %d", row.fac_num), false)
                            tempTimer(0.5, ui_company_refresh)
                        end,
                        true)
                end, "Destroy factory #"..row.fac_num, true)
            end,
        },
    }
    ui_table_create("co_factories", UI.co_fac_win, cols, { column=" " })
end

local function _render_factories()
    if not UI.co_fac_win then return end
    local c = gmcp and gmcp.char and gmcp.char.company
    if not c or not c.factories or #c.factories == 0 then
        clearWindow(UI.co_fac_win.name)
        UI.co_fac_win:cecho("\n<dim_grey>  No factories.\n")
        return
    end
    local rows = {}
    for _, fac in ipairs(c.factories) do
        local pct = eff_pct(fac)
        table.insert(rows, {
            fac_num  = fac.number,
            planet_s = strip_the(fac.planet or "?"):sub(1, 12),
            planet_r = fac.planet,
            output_s = (fac.output or "?"):sub(1, 10),
            output_r = fac.output,
            eff_s    = pct .. "%",
            eff_n    = pct,
            fac_status = fac.status,
            wages    = fac.wages,
        })
    end
    ui_table_set_data("co_factories", rows)
end

local function _render_depots()
    if not UI.co_depot_win then return end
    local c = gmcp and gmcp.char and gmcp.char.company
    clearWindow(UI.co_depot_win.name)
    if not c or not c.depots or #c.depots == 0 then
        UI.co_depot_win:cecho("<dim_grey>No depots.\n")
        return
    end
    UI.co_depot_win:cecho("<dim_grey>── DEPOTS<reset>\n")
    for _, d in ipairs(c.depots) do
        local pname = tostring(d)
        UI.co_depot_win:cechoLink(
            string.format("  <ansiCyan>%s<reset>\n", pname),
            function()
                _dlg_confirm("Repair Depot",
                    string.format("<b>Depot on %s</b><br>Repair this depot?", pname),
                    "Repair",
                    function() send("repair depot "..pname, false); tempTimer(0.5, ui_company_refresh) end)
            end,
            "Click to repair depot on "..pname, true)
    end
end

-- =============================================================================
-- FINANCIALS RENDER  (stats header + shareholder table)
-- =============================================================================

local function _init_shareholder_table()
    local cols = {
        {
            key="sh_name", label="Shareholder", width=18, align="left",
            sortable=true, sort_value=function(r) return r.sh_name:lower() end,
            format=function(v, row)
                local c = row.sh_color or "white"
                if row.is_broker or row.is_self then
                    return string.format("<%s><u>%s<reset>", c, v)
                end
                return string.format("<%s>%s<reset>", c, v)
            end,
            link=function(v, row)
                if row.is_broker then
                    _dlg_buy_shares(true, 0)
                elseif row.is_self then
                    _dlg_buy_shares(false, row.quantity)
                end
            end,
            linkHint="Click for share actions",
        },
        {
            key="quantity", label="Shares", width=7, align="right",
            sortable=true, default_sort="desc",
            format=function(v, row)
                return string.format("<%s>%s<reset>", row.sh_color or "white", fmtc(tonumber(v) or 0))
            end,
        },
        {
            key="pct_s", label="Own%", width=6, align="right",
            format=function(v, row)
                return string.format("<%s>%s<reset>", row.sh_color or "white", v)
            end,
        },
        {
            key="div_pay", label="Div Pay", width=9, align="right",
            format=function(v)
                local n = tonumber(v) or 0
                if n > 0 then return string.format("<ansiGreen>%sig<reset>", fmtc(n)) end
                return "<dim_grey>—<reset>"
            end,
        },
    }
    ui_table_create("co_shareholders", UI.co_fin_win, cols, { column=" " })
end

local function _render_financials()
    if not UI.co_fin_win then return end
    local c = gmcp and gmcp.char and gmcp.char.company
    clearWindow(UI.co_fin_win.name)

    if not c then
        UI.co_fin_win:cecho("\n<dim_grey>  No company data.\n")
        return
    end

    local shares = sum_shares(c)
    local sv     = c.share_value or 0
    local div    = c.dividend    or 0
    local profit = c.profit      or 0
    local eps    = shares > 0 and math.floor(profit / shares) or 0
    local pd     = div > 0  and string.format("%.1f", sv/div)  or "∞"
    local pe     = (sv > 0 and eps > 0) and string.format("%.1f", sv/eps) or "N/A"

    -- Stats block
    UI.co_fin_win:cecho(string.format(
        "\n  <dim_grey>Share Price  <reset><ansiCyan>%sig<reset>    <dim_grey>Market Cap  <reset><ansiCyan>%s<reset>\n",
        fmtc(sv), fmt(sv * shares)))
    UI.co_fin_win:cecho(string.format(
        "  <dim_grey>EPS  <reset><white>%sig/sh<reset>    <dim_grey>P/E  <reset><white>%s<reset>    <dim_grey>P/D  <reset><white>%s<reset>\n",
        fmtc(eps), pe, pd))
    UI.co_fin_win:cecho(string.format(
        "  <dim_grey>Dividend  <reset><white>%sig/sh<reset>    <dim_grey>Total Shares  <reset><white>%s<reset>\n",
        fmtc(div), fmtc(shares)))

    -- Inline action links
    UI.co_fin_win:cecho("  ")
    UI.co_fin_win:cechoLink("<ansiYellow>[ Issue Dividend ]<reset>",
        function() _dlg_dividend() end, "Issue a dividend to all shareholders", true)
    UI.co_fin_win:cecho("   ")
    UI.co_fin_win:cechoLink("<ansiCyan>[ Buy Personal Shares ]<reset>",
        function() _dlg_buy_shares(false, nil) end, "Buy personal shares", true)
    UI.co_fin_win:cecho("   ")
    UI.co_fin_win:cechoLink("<dim_grey>[ Buy Treasury ]<reset>",
        function() _dlg_buy_shares(true, nil) end, "Buy treasury shares", true)
    UI.co_fin_win:cecho("\n<dim_grey>  ──────────────────────────────────────<reset>\n")

    if not c.shareholders or #c.shareholders == 0 then
        UI.co_fin_win:cecho("<dim_grey>  No shareholder data.\n")
        return
    end

    local my_name = c.ceo
    local rows    = {}
    for _, sh in ipairs(c.shareholders) do
        local pct    = shares > 0 and (sh.quantity / shares * 100) or 0
        local is_me  = (sh.name == my_name)
        local is_brk = (sh.name == "Broker" or sh.name == "Banking Corporation")
        local color  = is_me and "ansiGreen" or (is_brk and "dim_grey" or "white")
        local label  = is_me and (sh.name .. " ★") or sh.name
        table.insert(rows, {
            sh_name  = label:sub(1, 18),
            quantity = sh.quantity,
            pct_s    = string.format("%.1f%%", pct),
            div_pay  = div > 0 and (sh.quantity * div) or 0,
            sh_color = color,
            is_self  = is_me,
            is_broker= is_brk,
        })
    end
    ui_table_set_data("co_shareholders", rows)
end

-- =============================================================================
-- MASTER RENDER + GMCP HANDLER
-- =============================================================================

function ui_company_render()
    _render_overview()
    _render_factories()
    _render_depots()
    _render_financials()
end

function ui_on_company_gmcp()
    ui_company_render()
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function ui_company()
    -- Root container
    UI.co_root = Geyser.Container:new({
        name="UI.co_root", x="0%", y="0%", width="100%", height="100%",
    }, UI.tab_bottom_right.Companycenter)

    -- ── Section nav bar (28px, slim, bottom-border indicator — NOT tab-shaped) ──
    local NH = 28
    UI.co_nav_bar = Geyser.Container:new({
        name="UI.co_nav_bar", x="0%", y="0", width="100%", height=NH.."px",
    }, UI.co_root)

    UI.co_nav_overview = Geyser.Label:new({
        name="UI.co_nav_overview", x="0%", y="0", width="33%", height=NH.."px",
    }, UI.co_nav_bar)
    UI.co_nav_overview:echo("<center>OVERVIEW</center>")
    UI.co_nav_overview:setClickCallback(function() _show_section("overview") end)

    UI.co_nav_factories = Geyser.Label:new({
        name="UI.co_nav_factories", x="33%", y="0", width="33%", height=NH.."px",
    }, UI.co_nav_bar)
    UI.co_nav_factories:echo("<center>FACTORIES</center>")
    UI.co_nav_factories:setClickCallback(function() _show_section("factories") end)

    UI.co_nav_financials = Geyser.Label:new({
        name="UI.co_nav_financials", x="66%", y="0", width="34%", height=NH.."px",
    }, UI.co_nav_bar)
    UI.co_nav_financials:echo("<center>FINANCIALS</center>")
    UI.co_nav_financials:setClickCallback(function() _show_section("financials") end)

    local CY = NH.."px"
    local CH = "100%-"..NH.."px"

    -- ── Overview section ──────────────────────────────────────────────────────
    UI.co_sec_overview = Geyser.Container:new({
        name="UI.co_sec_overview", x="0%", y=CY, width="100%", height=CH,
    }, UI.co_root)

    -- Floating ↻ and DI buttons, top-right corner
    local di_lbl = f2t_is_rank_or_above("Manufacturer") and "DI Co" or "DI Biz"
    local di_cmd = f2t_is_rank_or_above("Manufacturer") and "di company" or "di business"

    UI.co_ov_di = Geyser.Label:new({ name="UI.co_ov_di", x="-50", y="2", width="24", height="18" }, UI.co_sec_overview)
    UI.co_ov_di:setStyleSheet(UI.style.button_css)
    UI.co_ov_di:echo("<center>DI</center>")
    UI.co_ov_di:setToolTip(di_lbl)
    UI.co_ov_di:setClickCallback(function() send(di_cmd) end)

    UI.co_ov_ref = Geyser.Label:new({ name="UI.co_ov_ref", x="-24", y="2", width="22", height="18" }, UI.co_sec_overview)
    UI.co_ov_ref:setStyleSheet(UI.style.button_css)
    UI.co_ov_ref:echo("<center>↻</center>")
    UI.co_ov_ref:setToolTip("Refresh company data")
    UI.co_ov_ref:setClickCallback(function() ui_company_refresh() end)

    UI.co_ov_win = Geyser.MiniConsole:new({
        name="UI.co_ov_win", x="0%", y="0%", width="100%", height="100%",
        autoWrap=true, scrollBar=true, fontSize=14, color="black",
    }, UI.co_sec_overview)

    -- ── Factories section ─────────────────────────────────────────────────────
    UI.co_sec_factories = Geyser.Container:new({
        name="UI.co_sec_factories", x="0%", y=CY, width="100%", height=CH,
    }, UI.co_root)

    UI.co_fac_win = Geyser.MiniConsole:new({
        name="UI.co_fac_win", x="0%", y="0%", width="100%", height="72%",
        autoWrap=true, scrollBar=true, fontSize=13, color="black",
    }, UI.co_sec_factories)
    _init_factory_table()

    UI.co_depot_win = Geyser.MiniConsole:new({
        name="UI.co_depot_win", x="0%", y="72%", width="100%", height="28%",
        autoWrap=true, scrollBar=true, fontSize=13, color="black",
    }, UI.co_sec_factories)

    -- ── Financials section ────────────────────────────────────────────────────
    UI.co_sec_financials = Geyser.Container:new({
        name="UI.co_sec_financials", x="0%", y=CY, width="100%", height=CH,
    }, UI.co_root)

    UI.co_fin_win = Geyser.MiniConsole:new({
        name="UI.co_fin_win", x="0%", y="0%", width="100%", height="100%",
        autoWrap=true, scrollBar=true, fontSize=13, color="black",
    }, UI.co_sec_financials)
    _init_shareholder_table()

    _show_section("overview")
end

function ui_company_on_connect()
    tempTimer(5, function()
        if UI.co_ov_win and f2t_is_rank_or_above("Industrialist") then
            ui_company_refresh()
        end
    end)
end
