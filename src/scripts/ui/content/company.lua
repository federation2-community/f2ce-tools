-- company.lua — Company / business management content for fed2-tools.
--
-- Three SEPARATE registered contents, all rendered from gmcp.char.company, so
-- each can be placed in its own Muxlet pane or subtab (Muxlet owns the tab
-- chrome — no internal section nav here):
--
--   fed2_company_overview   — identity, status (click to freeze), repair
--                             alerts, financial and investor key figures
--   fed2_company_factories  — sortable factory table with inline repair /
--                             start-stop / wages / destroy actions + depot list
--   fed2_company_financials — share stats, dividend and share-purchase
--                             actions, and the shareholder table
--
-- Action dialogs use Muxlet primitives throughout: Mux.createDialog +
-- Mux.dialogCss + Mux.wireDialogButton for confirm/info flows, and
-- Mux.ui.buildForm (number steppers) for wages / dividend / share amounts.
--
-- gmcp.char.company is realtime — the game pushes a fresh copy after every
-- action that changes it (repair, wages, dividend, freeze, ...), so panels
-- just re-render on that event; nothing here polls or force-refreshes it.
-- The DI button is a separate, purely diagnostic action: it sends
-- `di company`/`di business` visibly so the raw text shows in the console.
--
-- Ported from archive's ui_company.lua (its OVERVIEW/FACTORIES/FINANCIALS
-- sections became these three contents).

local H_BAR = 22    -- header strip height (px)
local H_COL = 20    -- column header bar height (px)
local ROW_H = 20    -- table row height (px)
local SB_W  = 17    -- scrollbar pixel allowance
local H_FIN = 96    -- financials stats block height (px)
local DEPOT_PCT = 26 -- depot console share of the factories panel (%)

local CELL_FONT = "font-size:10pt;font-family:Consolas,Monaco,monospace;"

-- Shared "nothing here" look for empty tables (no factories, no depots, ...)
-- so every empty state in this content reads the same way.
local function emptyStateHtml(text)
    return string.format(
        "<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT, text)
end

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
local _HDR_STRIP_CSS = [[
    background-color: rgba(15, 18, 30, 200);
    border: none;
    border-bottom: 1px solid rgba(70, 75, 110, 150);
]]
local _HDR_TITLE_CSS = [[
    background: transparent; border: none;
    color: rgba(140, 150, 195, 255);
    font-size: 10px; font-family: "Consolas","Monaco",monospace;
]]
local _MINI_BTN_CSS = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(150,165,205,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 3px;
        font-size: 10px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(42,48,78,230);
        color: rgba(200,215,255,255);
    }
]]

-- Per-pane state, keyed by target._gid.  Each entry carries `kind`
-- ("overview" | "factories" | "financials") so refreshAll can dispatch.
local instances = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function fmtCompact(n)
    if not n then return "?" end
    n = tonumber(n) or 0
    local abs, sign = math.abs(n), n < 0 and "-" or ""
    if abs >= 1000000 then return string.format("%s%.2fM", sign, abs / 1e6)
    elseif abs >= 1000 then return string.format("%s%.1fk", sign, abs / 1e3)
    else                    return string.format("%s%d",   sign, abs) end
end

local function fmtComma(n)
    if not n then return "?" end
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end

local function sumShares(c)
    if not c or not c.shareholders then return 10000 end
    local t = 0
    for _, sh in ipairs(c.shareholders) do t = t + (sh.quantity or 0) end
    return t > 0 and t or 10000
end

local function effPct(fac)
    if not fac.max_efficiency or fac.max_efficiency == 0 then return 100 end
    return math.floor(fac.efficiency / fac.max_efficiency * 100)
end

local function stripThe(s)
    if not s then return "" end
    return (s:gsub("^[Tt]he ", ""))
end

local function companyData()
    return gmcp and gmcp.char and gmcp.char.company or nil
end

-- ── One-shot GMCP prime ───────────────────────────────────────────────────────
-- gmcp.char.company only exists once the server has answered a di
-- company/business query at least once this session — it doesn't arrive
-- unprompted on login. So the first time a panel opens with no data yet,
-- send that query once (output gagged) purely to populate GMCP; every
-- update after that is the live gmcp.char.company push, same as before —
-- this is priming, not polling, so it never repeats once data exists.
local _priming = false

local function primeCompanyDataIfMissing()
    if companyData() or _priming then return end
    _priming = true

    local triggerId, timerId
    local function finish()
        _priming = false
        if triggerId then killTrigger(triggerId); triggerId = nil end
        if timerId   then killTimer(timerId);     timerId   = nil end
    end
    local function resetTimer()
        if timerId then killTimer(timerId) end
        -- Timer-based completion: always ends the capture when output goes quiet.
        timerId = tempTimer(0.8, finish)
    end
    triggerId = tempRegexTrigger("^.*$", function()
        if _priming then deleteLine(); resetTimer() end
    end)
    resetTimer()
    send(f2t_is_rank_or_above("Manufacturer") and "di company" or "di business", false)
end

-- ── Dialogs (Muxlet primitives) ───────────────────────────────────────────────

-- One transient internal content shared by all company dialogs; the pending
-- closure carries the specific builder (map_import's _pendingReason pattern).
local _pendingDialog = nil

local function openDialog(opts, buildFn)
    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho("\n<yellow>[company]<reset> Dialogs require Muxlet.\n")
        return
    end
    if not Mux._content or not Mux._content["f2t_company_dialog"] then
        Mux.registerContent("f2t_company_dialog", {
            internal = true,
            name     = "Company Action",
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
        width     = opts.width  or 400,
        height    = opts.height or 180,
        singleton = "f2t_company_dialog",
    })
    Mux._applyContent(d, "f2t_company_dialog")
    d:show()
    d:raise()
    return d
end

-- Button row at the bottom of a dialog.  Geometry comes from the declared
-- dialog size (content widgets are laid out before Qt reports real sizes):
-- content width ≈ dlgW − 4 border, content height ≈ dlgH − 26 chrome.
local function dialogButtons(target, dlgW, dlgH, okLabel, okFn, danger)
    local c = target.content
    local w = dlgW - 4
    local y = (dlgH - 26) - 42

    local cancel = Geyser.Label:new({
        name = target._gid .. "_cdlg_cancel", x = 14, y = y, width = 120, height = 32,
    }, c)
    cancel:setStyleSheet(Mux.dialogCss.button)
    cancel:echo("<center>Cancel</center>")
    Mux.wireDialogButton(cancel, Mux.dialogCss.button, Mux.dialogCss.buttonHover)
    cancel:setClickCallback(function() target:close() end)

    local okCss, okHover
    if danger then okCss, okHover = Mux.dialogCss.buttonDanger,  Mux.dialogCss.buttonDangerHover
    else           okCss, okHover = Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover end
    local ok = Geyser.Label:new({
        name = target._gid .. "_cdlg_ok", x = w - 134, y = y, width = 120, height = 32,
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
    openDialog({ title = title, width = 400, height = 190 }, function(target)
        local msg = Geyser.Label:new({
            name = target._gid .. "_cdlg_body", x = 0, y = 8, width = "100%", height = 84,
        }, target.content)
        msg:setStyleSheet(Mux.dialogCss.body)
        msg:echo(body)
        dialogButtons(target, 400, 190, okLabel, okFn, danger)
    end)
end

local function dialogInfo(title, body)
    openDialog({ title = title, width = 400, height = 180 }, function(target)
        local msg = Geyser.Label:new({
            name = target._gid .. "_cdlg_body", x = 0, y = 8, width = "100%", height = 84,
        }, target.content)
        msg:setStyleSheet(Mux.dialogCss.body)
        msg:echo(body)
        local w  = 400 - 4
        local ok = Geyser.Label:new({
            name = target._gid .. "_cdlg_ok",
            x = math.floor((w - 120) / 2), y = (180 - 26) - 42,
            width = 120, height = 32,
        }, target.content)
        ok:setStyleSheet(Mux.dialogCss.button)
        ok:echo("<center>OK</center>")
        Mux.wireDialogButton(ok, Mux.dialogCss.button, Mux.dialogCss.buttonHover)
        ok:setClickCallback(function() target:close() end)
    end)
end

-- Number-entry dialog built on Mux.ui.buildForm (stepper widget).  `presets`
-- (optional) renders quick-set buttons above the form.
local function dialogAmount(opts)
    local dlgH = opts.height or 250
    openDialog({ title = opts.title, width = 440, height = dlgH }, function(target)
        local c = target.content
        local y = 6

        if opts.body then
            local msg = Geyser.Label:new({
                name = target._gid .. "_cdlg_body", x = 0, y = y, width = "100%", height = opts.bodyHeight or 46,
            }, c)
            msg:setStyleSheet(Mux.dialogCss.body)
            msg:echo(opts.body)
            y = y + (opts.bodyHeight or 46) + 4
        end

        local amount = opts.initial

        local formRef = {}
        if opts.presets and #opts.presets > 0 then
            local bw = math.floor((440 - 28 - (#opts.presets - 1) * 8) / #opts.presets)
            for i, p in ipairs(opts.presets) do
                local btn = Geyser.Label:new({
                    name = string.format("%s_cdlg_pre%d", target._gid, i),
                    x = 14 + (i - 1) * (bw + 8), y = y, width = bw, height = 34,
                }, c)
                btn:setStyleSheet(Mux.dialogCss.button)
                btn:echo(string.format("<center>%s<br><b>%s</b></center>", p.label, fmtComma(p.value)))
                Mux.wireDialogButton(btn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)
                local v = p.value
                btn:setClickCallback(function()
                    amount = v
                    if formRef.handle and formRef.handle.refreshAll then formRef.handle.refreshAll() end
                end)
            end
            y = y + 42
        end

        local formHost = Geyser.Label:new({
            name = target._gid .. "_cdlg_form", x = 0, y = y, width = "100%", height = 46,
        }, c)
        formHost:setStyleSheet("background:transparent;border:none;")

        local handle = Mux.ui.buildForm(formHost, {
            {
                label   = opts.fieldLabel or "Amount",
                desc    = opts.fieldDesc,
                type    = "number",
                display = "stepper",
                step    = opts.step or 1,
                min     = opts.min,
                max     = opts.max,
                readFn  = function() return amount end,
                writeFn = function(v) amount = v end,
            },
        }, {
            width  = 440 - 8,
            prefix = target._gid .. "_cdlgf",
        })
        formRef.handle = handle

        dialogButtons(target, 440, dlgH, opts.okLabel, function()
            local v = tonumber(amount)
            if not v or (opts.min and v < opts.min) or (opts.max and v > opts.max) then
                cecho(string.format("\n<red>[company]<reset> %s\n", opts.rangeError or "Invalid amount"))
                return
            end
            opts.okFn(math.floor(v))
        end, false)
    end)
end

local function dialogWages(facNum, curWages)
    dialogAmount({
        title      = "Set Wages — Factory #" .. facNum,
        height     = 210,
        body       = "Wages per cycle. Higher wages improve worker productivity.",
        bodyHeight = 30,
        fieldLabel = "Wages (ig/cycle)",
        fieldDesc  = "Minimum 40ig per cycle",
        initial    = tonumber(curWages) or 40,
        step       = 5,
        min        = 40,
        max        = 2000,
        okLabel    = "Set Wages",
        rangeError = "Wages must be at least 40ig",
        okFn = function(v)
            send(string.format("set factory %d wages %d", facNum, v), false)
        end,
    })
end

local function dialogDividend()
    local c = companyData()
    if not c then return end
    local shares = sumShares(c)
    local profit = c.profit or 0
    local eps    = shares > 0 and math.floor(profit / shares) or 0
    local sv     = c.share_value or 0
    local curDiv = c.dividend or 0
    local s50    = math.max(1, math.min(2000, math.floor(eps * 0.5)))
    local s100   = math.max(1, math.min(2000, eps))
    local pe     = (sv > 0 and eps > 0) and string.format("%.1f", sv / eps) or "N/A"

    dialogAmount({
        title      = "Issue Dividend",
        height     = 290,
        body       = string.format(
            "EPS <b>%sig/sh</b> &nbsp; Share <b>%sig</b> &nbsp; P/E <b>%s</b><br>" ..
            "Current dividend <b>%sig/sh</b> &nbsp; Shares <b>%s</b>",
            fmtComma(eps), fmtComma(sv), pe, fmtComma(curDiv), fmtComma(shares)),
        bodyHeight = 46,
        presets    = {
            { label = "50% of EPS",  value = s50  },
            { label = "100% of EPS", value = s100 },
            { label = "Maximum",     value = 2000 },
        },
        fieldLabel = "Dividend (ig/share)",
        fieldDesc  = "1 – 2000 ig per share, paid to all shareholders",
        initial    = s50,
        step       = 10,
        min        = 1,
        max        = 2000,
        okLabel    = "Issue Dividend",
        rangeError = "Dividend must be 1–2000ig/share",
        okFn = function(v)
            send(string.format("issue dividend %d", v), false)
        end,
    })
end

local function dialogBuyShares(isTreasury, curQty)
    local body = isTreasury
        and "Buy shares into the company treasury.<br>Reduces external shareholder influence.<br>Cost deducted from company cash."
        or  string.format("Buy personal shares.<br>You currently hold <b>%s shares</b>.<br>Increases your dividend payout each cycle.",
            fmtComma(curQty or 0))
    dialogAmount({
        title      = isTreasury and "Buy Treasury Shares" or "Buy Personal Shares",
        height     = 240,
        body       = body,
        bodyHeight = 58,
        fieldLabel = "Shares to buy",
        initial    = 100,
        step       = 50,
        min        = 1,
        max        = 100000,
        okLabel    = "Buy",
        rangeError = "Enter a valid quantity",
        okFn = function(v)
            local cmd = isTreasury
                and string.format("buy %d treasury", v)
                or  string.format("buy %d shares", v)
            send(cmd, false)
        end,
    })
end

local function dialogFreeze()
    local c = companyData()
    if not c then return end
    if c.status ~= "running" then
        dialogInfo("Company Frozen", string.format(
            "<b>%s</b> is currently frozen.<br><br>To unfreeze, you must log out<br>and log back in.",
            c.name or "company"))
        return
    end
    dialogConfirm("Freeze Company",
        string.format("<b>%s</b><br>Pause all factory cycles until unfrozen.<br>Workers remain on idle wages.", c.name or "company"),
        "Freeze",
        function()
            send("freeze company", false)
        end,
        true)
end

-- ── Shared chrome: header strip with title + DI ──────────────────────────────

local function buildHeaderStrip(target, wid, title)
    local bar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_BAR,
    }, target.content)
    bar:setStyleSheet(_HDR_STRIP_CSS)

    local lbl = Geyser.Label:new({
        name = wid(), x = 6, y = 0, width = "-28", height = H_BAR,
    }, bar)
    lbl:setStyleSheet(_HDR_TITLE_CSS)
    lbl:echo(title)

    local diBtn = Geyser.Label:new({
        name = wid(), x = "-25", y = 2, width = 20, height = H_BAR - 4,
    }, bar)
    diBtn:setStyleSheet(_MINI_BTN_CSS)
    diBtn:echo("<center>DI</center>")
    diBtn:setToolTip("Show raw di company / di business output")
    diBtn:setClickCallback(function()
        send(f2t_is_rank_or_above("Manufacturer") and "di company" or "di business", false)
    end)

    return bar
end

-- Column bar + scrollbox table below yTop within `parent`.
local function buildTableArea(parent, wid, tableId, cols, yTop, heightSpec)
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = yTop, width = "100%", height = H_COL,
    }, parent)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scroll = Geyser.ScrollBox:new({
        name = wid(), x = 0, y = yTop + H_COL, width = "100%", height = heightSpec,
    }, parent)

    local contentW = math.max(100, parent:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

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

    return { scroll = scroll, contentLabel = contentLabel, contentW = contentW }
end

-- ── Overview panel ────────────────────────────────────────────────────────────

local function renderOverview(inst)
    local w = inst.console
    if not w then return end
    w:clear()

    local c = companyData()
    if not c then
        w:cecho("\n\n<dim_grey>  No company data yet.\n")
        return
    end

    local isMfr = f2t_is_rank_or_above("Manufacturer")
    local HR    = "<dim_grey>  ──────────────────────────────────────<reset>\n"

    local statusColor = (c.status == "running") and "ansiGreen" or "ansiYellow"
    local statusText  = (c.status == "running") and "● RUNNING" or "⊘ FROZEN"
    w:cecho(string.format("\n  <white><b>%s</b><reset>\n", c.name or "Unknown Company"))
    w:cecho("  ")
    w:cechoLink(string.format("[<%s>%s<reset>]", statusColor, statusText),
        function() dialogFreeze() end, "Click to freeze/unfreeze", true)
    w:cecho("\n" .. HR)

    if c.ceo    then w:cecho(string.format("  <dim_grey>CEO          <reset><white>%s<reset>\n", c.ceo)) end
    if c.planet then w:cecho(string.format("  <dim_grey>HQ Planet    <reset><white>%s<reset>\n", c.planet)) end
    if c.formed then w:cecho(string.format("  <dim_grey>Founded      <reset><white>%s<reset>\n", c.formed)) end
    w:cecho(string.format("  <dim_grey>Cycles Run   <reset><white>%d<reset>\n", c.total_cycles or 0))
    if c.days_left then
        local dc = c.days_left < 10 and "ansiRed" or "ansiYellow"
        w:cecho(string.format("  <dim_grey>Days Left    <reset><%s>%d days<reset>\n", dc, c.days_left))
    end

    if isMfr and c.factories then
        local alerts = {}
        for _, fac in ipairs(c.factories) do
            local pct = effPct(fac)
            if pct < 80 then
                table.insert(alerts, string.format("  <ansiRed>⚠  Factory #%d  (%s)  —  %d%% eff<reset>",
                    fac.number, stripThe(fac.planet or "?"), pct))
            end
        end
        if #alerts > 0 then
            w:cecho("\n" .. HR)
            w:cecho("  <ansiRed><b>⚠  REPAIR ALERTS<reset>\n")
            for _, a in ipairs(alerts) do w:cecho(a .. "\n") end
        end
    end

    local profit = c.profit or 0
    local pc     = profit >= 0 and "ansiGreen" or "ansiRed"
    w:cecho("\n" .. HR)
    w:cecho("  <dim_grey><b>FINANCIALS<reset>\n")
    w:cecho(string.format("  <dim_grey>Cash         <reset><ansiCyan>%sig<reset>\n", fmtComma(c.cash)))
    w:cecho(string.format("  <dim_grey>Profit       <reset><%s>%sig<reset>\n", pc, fmtComma(profit)))
    if c.tax then
        w:cecho(string.format("  <dim_grey>Tax Paid     <reset><white>%sig<reset>\n", fmtComma(c.tax)))
    end
    if c.revenue then
        if c.revenue.income   then w:cecho(string.format("  <dim_grey>Revenue      <reset><ansiGreen>+%sig<reset>\n", fmtComma(c.revenue.income))) end
        if c.revenue.expenses then w:cecho(string.format("  <dim_grey>Expenses     <reset><ansiRed>-%sig<reset>\n",   fmtComma(c.revenue.expenses))) end
    end
    if c.capital then
        local ce = tonumber(c.capital.expenditure) or 0
        local cr = tonumber(c.capital.receipts)    or 0
        if ce > 0 then w:cecho(string.format("  <dim_grey>Capital Exp  <reset><ansiRed>-%sig<reset>\n",   fmtComma(ce))) end
        if cr > 0 then w:cecho(string.format("  <dim_grey>Capital Rec  <reset><ansiGreen>+%sig<reset>\n", fmtComma(cr))) end
    end

    if isMfr then
        local shares = sumShares(c)
        local sv     = c.share_value  or 0
        local div    = c.dividend     or 0
        local da     = c.disaffection or 0
        local eps    = shares > 0 and math.floor(profit / shares) or 0
        local peStr  = (sv > 0 and eps > 0) and string.format("%.1f", sv / eps) or "N/A"
        local pdStr  = div > 0 and string.format("%.1f", sv / div) or "<ansiRed>none<reset>"
        local daCol  = da < 20 and "ansiGreen" or (da < 50 and "ansiYellow" or "ansiRed")

        w:cecho("\n" .. HR)
        w:cecho("  <dim_grey><b>INVESTORS<reset>\n")
        w:cecho(string.format("  <dim_grey>Disaffection <reset><%s>%d%%<reset>\n", daCol, da))
        w:cecho(string.format("  <dim_grey>Share Price  <reset><white>%sig<reset>\n", fmtComma(sv)))
        w:cecho(string.format("  <dim_grey>Dividend     <reset><white>%sig/sh<reset>  <dim_grey>  P/D <reset><white>%s<reset>\n", fmtComma(div), pdStr))
        w:cecho(string.format("  <dim_grey>EPS          <reset><white>%sig/sh<reset>  <dim_grey>  P/E <reset><white>%s<reset>\n", fmtComma(eps), peStr))
        w:cecho(string.format("  <dim_grey>Shares       <reset><white>%s<reset>\n", fmtComma(shares)))
        w:cecho(string.format("  <dim_grey>Market Cap   <reset><white>%s<reset>\n", fmtCompact(sv * shares)))

        if (c.total_cycles or 0) >= 4 and profit > 0 then
            w:cecho("\n  <ansiGreen>★ Eligible for Financier promotion<reset>\n")
        end
    end
end

local function buildOverview(target)
    local gid = target._gid
    primeCompanyDataIfMissing()
    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end
    if instances[gid] then
        renderOverview(instances[gid])
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cov_%d", gid, wc)
    end

    buildHeaderStrip(target, wid, "🏢  Company Overview")

    local console = Geyser.MiniConsole:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = "100%-" .. H_BAR .. "px",
        fontSize = 9, scrollBar = true,
    }, target.content)
    console:setColor(18, 18, 26)
    console:enableAutoWrap()

    instances[gid] = { kind = "overview", console = console }
    renderOverview(instances[gid])
end

-- ── Factories panel ───────────────────────────────────────────────────────────

local function factoryCols()
    return {
        {
            key           = "facNum",
            label         = "#",
            sortable      = true,
            sort_value    = function(r) return tonumber(r.facNum) or 0 end,
            scrollbox_pct = 8,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#00cccc;text-decoration:underline;'>%s</span>", CELL_FONT, v))
                cell:setToolTip("di factory #" .. tostring(v))
                cell:setClickCallback(function() send("di factory " .. v, false) end)
            end,
        },
        {
            key           = "planetShort",
            label         = "Planet",
            sortable      = true,
            sort_value    = function(r) return r.planetShort:lower() end,
            scrollbox_pct = 26,
            render_label  = function(v, row, cell)
                cell:echo(string.format("<span style='%scolor:#ffffff;'>%s</span>", CELL_FONT, v))
                cell:setToolTip("Navigate to " .. tostring(row.planet))
                cell:setClickCallback(function()
                    if row.planet and f2t_map_navigate then f2t_map_navigate(row.planet) end
                end)
            end,
        },
        {
            key           = "outputShort",
            label         = "Output",
            sortable      = true,
            sort_value    = function(r) return r.outputShort:lower() end,
            scrollbox_pct = 24,
            render_label  = function(v, row, cell)
                cell:echo(string.format("<span style='%scolor:#888888;'>%s</span>", CELL_FONT, v))
            end,
        },
        {
            key           = "effNum",
            label         = "Eff",
            sortable      = true,
            sort_value    = function(r) return r.effNum end,
            scrollbox_pct = 12,
            render_label  = function(v, row, cell)
                local color = v >= 90 and "#00cc44" or (v >= 70 and "#cccc44" or "#ff5555")
                local deco  = v < 100 and "text-decoration:underline;" or ""
                cell:echo(string.format(
                    "<span style='%s%scolor:%s;'>%d%%</span>", CELL_FONT, deco, color, v))
                if v < 100 then
                    cell:setToolTip("Click to repair factory (+5% efficiency)")
                    cell:setClickCallback(function()
                        dialogConfirm("Repair Factory",
                            string.format("<b>Factory #%d — %s</b><br>Efficiency: <b>%d%%</b>  (repair restores +5%%)<br>Cost deducted from company cash.",
                                row.facNum, stripThe(row.planet or "?"), v),
                            "Repair",
                            function()
                                send(string.format("repair factory %d", row.facNum), false)
                            end)
                    end)
                else
                    cell:setToolTip("Full efficiency")
                    cell:setClickCallback(function() end)
                end
            end,
        },
        {
            key           = "facStatus",
            label         = "St",
            sortable      = false,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                local running = (v == 0)
                cell:echo(string.format(
                    "<p style='text-align:center;margin:0;'><span style='%scolor:%s;'>%s</span></p>",
                    CELL_FONT, running and "#00cc44" or "#ff5555", running and "▶" or "■"))
                cell:setToolTip(running and "Click to stop factory" or "Click to start factory")
                cell:setClickCallback(function()
                    local verb = running and "Stop" or "Start"
                    dialogConfirm(verb .. " Factory",
                        string.format("<b>Factory #%d — %s</b><br>%s",
                            row.facNum, stripThe(row.planet or "?"),
                            running and "Stop production? Workers idle until restarted." or "Restart production?"),
                        verb,
                        function()
                            send(string.format("set factory %d status %s",
                                row.facNum, running and "stop" or "run"), false)
                        end)
                end)
            end,
        },
        {
            key           = "wages",
            label         = "$",
            sortable      = false,
            scrollbox_pct = 10,
            render_label  = function(_v, row, cell)
                cell:echo(string.format(
                    "<p style='text-align:center;margin:0;'><span style='%scolor:#cccc44;'>$</span></p>", CELL_FONT))
                cell:setToolTip("Set wages — factory #" .. tostring(row.facNum))
                cell:setClickCallback(function() dialogWages(row.facNum, row.wages) end)
            end,
        },
        {
            key           = "destroy",
            label         = "X",
            sortable      = false,
            scrollbox_pct = 10,
            render_label  = function(_v, row, cell)
                cell:echo(string.format(
                    "<p style='text-align:center;margin:0;'><span style='%scolor:#ff5555;'>✕</span></p>", CELL_FONT))
                cell:setToolTip("Destroy factory #" .. tostring(row.facNum))
                cell:setClickCallback(function()
                    dialogConfirm("Destroy Factory",
                        string.format("<b>DESTROY Factory #%d?</b><br>%s on %s<br>This action <b>cannot be undone</b>.",
                            row.facNum, row.output or "?", stripThe(row.planet or "?")),
                        "Destroy",
                        function()
                            send(string.format("destroy factory %d", row.facNum), false)
                        end,
                        true)
                end)
            end,
        },
    }
end

local function depotCols()
    return {
        {
            key           = "name",
            label         = "Depots",
            sortable      = false,
            scrollbox_pct = 100,
            render_label  = function(v, row, cell)
                cell:echo(string.format("<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, v))
                cell:setToolTip("Click to repair depot on " .. tostring(v))
                cell:setClickCallback(function()
                    dialogConfirm("Repair Depot",
                        string.format("<b>Depot on %s</b><br>Repair this depot?", v),
                        "Repair",
                        function() send("repair depot " .. v, false) end)
                end)
            end,
        },
    }
end

local function renderFactories(inst)
    local c = companyData()
    local rows = {}
    for _, fac in ipairs(c and c.factories or {}) do
        local pct = effPct(fac)
        table.insert(rows, {
            facNum      = fac.number,
            planet      = fac.planet,
            planetShort = stripThe(fac.planet or "?"):sub(1, 14),
            output      = fac.output,
            outputShort = (fac.output or "?"):sub(1, 12),
            effNum      = pct,
            facStatus   = fac.status,
            wages       = fac.wages,
        })
    end
    f2tTableSetData(inst.tableId, rows)

    if inst.noFactoriesLbl then
        if #rows == 0 then inst.noFactoriesLbl:show() else inst.noFactoriesLbl:hide() end
    end

    local depotRows = {}
    for _, d in ipairs(c and c.depots or {}) do
        depotRows[#depotRows + 1] = { name = tostring(d) }
    end
    if inst.depotTableId then f2tTableSetData(inst.depotTableId, depotRows) end
    if inst.noDepotsLbl then
        if #depotRows == 0 then inst.noDepotsLbl:show() else inst.noDepotsLbl:hide() end
    end
end

local function buildFactories(target)
    local gid = target._gid
    primeCompanyDataIfMissing()
    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end
    if instances[gid] then
        renderFactories(instances[gid])
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cfa_%d", gid, wc)
    end

    buildHeaderStrip(target, wid, "🏭  Factories")

    local tableId = "co_factories_" .. gid
    local area = buildTableArea(target.content, wid, tableId, factoryCols(),
        H_BAR, (100 - DEPOT_PCT) .. "%-" .. (H_BAR + H_COL) .. "px")

    -- Overlays the table area when there are no factories; f2tTableSetData
    -- leaves an empty scrollbox with no message of its own.
    local noFactoriesLbl = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR + H_COL, width = "100%",
        height = (100 - DEPOT_PCT) .. "%-" .. (H_BAR + H_COL) .. "px",
    }, target.content)
    noFactoriesLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    noFactoriesLbl:echo(emptyStateHtml("No factories."))
    noFactoriesLbl:hide()

    -- Depots reuse the same table system as factories (was a MiniConsole,
    -- which always reserved a scrollbar track even with one line of text or
    -- none at all) so the empty state and row styling both match factories.
    local depotContainer = Geyser.Container:new({
        name = wid(), x = 0, y = (100 - DEPOT_PCT) .. "%", width = "100%", height = DEPOT_PCT .. "%",
    }, target.content)

    local depotTableId = "co_depots_" .. gid
    local depotArea = buildTableArea(depotContainer, wid, depotTableId, depotCols(),
        0, "100%-" .. H_COL .. "px")

    local noDepotsLbl = Geyser.Label:new({
        name = wid(), x = 0, y = H_COL, width = "100%", height = "100%-" .. H_COL .. "px",
    }, depotContainer)
    noDepotsLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    noDepotsLbl:echo(emptyStateHtml("No depots."))
    noDepotsLbl:hide()

    instances[gid] = {
        kind            = "factories",
        tableId         = tableId,
        area            = area,
        noFactoriesLbl  = noFactoriesLbl,
        depotTableId    = depotTableId,
        depotArea       = depotArea,
        noDepotsLbl     = noDepotsLbl,
    }
    renderFactories(instances[gid])
end

-- ── Financials panel ──────────────────────────────────────────────────────────

local function shareholderCols()
    return {
        {
            key           = "name",
            label         = "Shareholder",
            sortable      = true,
            sort_value    = function(r) return r.name:lower() end,
            scrollbox_pct = 42,
            render_label  = function(v, row, cell)
                local deco = (row.isBroker or row.isSelf) and "text-decoration:underline;" or ""
                cell:echo(string.format(
                    "<span style='%s%scolor:%s;'>%s</span>", CELL_FONT, deco, row.color, v))
                if row.isBroker then
                    cell:setToolTip("Click to buy treasury shares")
                    cell:setClickCallback(function() dialogBuyShares(true, 0) end)
                elseif row.isSelf then
                    cell:setToolTip("Click to buy personal shares")
                    cell:setClickCallback(function() dialogBuyShares(false, row.quantity) end)
                else
                    cell:setToolTip("")
                    cell:setClickCallback(function() end)
                end
            end,
        },
        {
            key           = "quantity",
            label         = "Shares",
            sortable      = true,
            default_sort  = "desc",
            sort_value    = function(r) return r.quantity or 0 end,
            scrollbox_pct = 20,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:%s;'>%s</span>", CELL_FONT, row.color, fmtComma(v)))
            end,
        },
        {
            key           = "pctStr",
            label         = "Own%",
            sortable      = false,
            scrollbox_pct = 16,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:%s;'>%s</span>", CELL_FONT, row.color, v))
            end,
        },
        {
            key           = "divPay",
            label         = "Div Pay",
            sortable      = true,
            sort_value    = function(r) return r.divPay or 0 end,
            scrollbox_pct = 22,
            render_label  = function(v, row, cell)
                local n = tonumber(v) or 0
                if n > 0 then
                    cell:echo(string.format(
                        "<span style='%scolor:#00cc44;'>%sig</span>", CELL_FONT, fmtComma(n)))
                else
                    cell:echo(string.format("<span style='%scolor:#888888;'>—</span>", CELL_FONT))
                end
            end,
        },
    }
end

local function renderFinancials(inst)
    local w = inst.console
    if not w then return end
    w:clear()

    local c = companyData()
    if not c then
        w:cecho("\n<dim_grey>  No company data yet.\n")
        f2tTableSetData(inst.tableId, {})
        return
    end

    local shares = sumShares(c)
    local sv     = c.share_value or 0
    local div    = c.dividend    or 0
    local profit = c.profit      or 0
    local eps    = shares > 0 and math.floor(profit / shares) or 0
    local pd     = div > 0 and string.format("%.1f", sv / div) or "∞"
    local pe     = (sv > 0 and eps > 0) and string.format("%.1f", sv / eps) or "N/A"

    w:cecho(string.format(
        "\n  <dim_grey>Share Price  <reset><ansiCyan>%sig<reset>    <dim_grey>Market Cap  <reset><ansiCyan>%s<reset>\n",
        fmtComma(sv), fmtCompact(sv * shares)))
    w:cecho(string.format(
        "  <dim_grey>EPS  <reset><white>%sig/sh<reset>    <dim_grey>P/E  <reset><white>%s<reset>    <dim_grey>P/D  <reset><white>%s<reset>\n",
        fmtComma(eps), pe, pd))
    w:cecho(string.format(
        "  <dim_grey>Dividend  <reset><white>%sig/sh<reset>    <dim_grey>Total Shares  <reset><white>%s<reset>\n",
        fmtComma(div), fmtComma(shares)))

    w:cecho("  ")
    w:cechoLink("<ansiYellow>[ Issue Dividend ]<reset>",
        function() dialogDividend() end, "Issue a dividend to all shareholders", true)
    w:cecho("  ")
    w:cechoLink("<ansiCyan>[ Buy Shares ]<reset>",
        function() dialogBuyShares(false, nil) end, "Buy personal shares", true)
    w:cecho("  ")
    w:cechoLink("<dim_grey>[ Buy Treasury ]<reset>",
        function() dialogBuyShares(true, nil) end, "Buy treasury shares", true)
    w:cecho("\n")

    local rows = {}
    if c.shareholders then
        local myName = c.ceo
        for _, sh in ipairs(c.shareholders) do
            local pct   = shares > 0 and (sh.quantity / shares * 100) or 0
            local isMe  = (sh.name == myName)
            local isBrk = (sh.name == "Broker" or sh.name == "Banking Corporation")
            table.insert(rows, {
                name     = (isMe and (sh.name .. " ★") or sh.name):sub(1, 20),
                quantity = sh.quantity,
                pctStr   = string.format("%.1f%%", pct),
                divPay   = div > 0 and (sh.quantity * div) or 0,
                color    = isMe and "#00cc44" or (isBrk and "#888888" or "#ffffff"),
                isSelf   = isMe,
                isBroker = isBrk,
            })
        end
    end
    f2tTableSetData(inst.tableId, rows)
end

local function buildFinancials(target)
    local gid = target._gid
    primeCompanyDataIfMissing()
    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end
    if instances[gid] then
        renderFinancials(instances[gid])
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cfi_%d", gid, wc)
    end

    buildHeaderStrip(target, wid, "💰  Financials")

    local console = Geyser.MiniConsole:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = H_FIN,
        fontSize = 9, scrollBar = false,
    }, target.content)
    console:setColor(18, 18, 26)
    console:enableAutoWrap()

    local tableId = "co_shareholders_" .. gid
    local area = buildTableArea(target.content, wid, tableId, shareholderCols(),
        H_BAR + H_FIN, "100%-" .. (H_BAR + H_FIN + H_COL) .. "px")

    instances[gid] = {
        kind    = "financials",
        console = console,
        tableId = tableId,
        area    = area,
    }
    renderFinancials(instances[gid])
end

-- ── Render dispatch + registration ────────────────────────────────────────────

local RENDERERS = {
    overview   = renderOverview,
    factories  = renderFactories,
    financials = renderFinancials,
}

local function renderInstance(inst)
    local fn = RENDERERS[inst.kind]
    if fn then fn(inst) end
end

local function refreshAll()
    for _, inst in pairs(instances) do pcall(renderInstance, inst) end
end

local function makeDef(name, description, buildFn)
    return {
        name        = name,
        description = description,
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildFn, target)
            if not ok then
                f2t_debug_log("[company] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                if inst.tableId      then f2tTableDestroy(inst.tableId) end
                if inst.depotTableId then f2tTableDestroy(inst.depotTableId) end
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not (inst and inst.area) then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            if newCw ~= inst.area.contentW then
                inst.area.contentW = newCw
                inst.area.contentLabel:resize(newCw, inst.area.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
            -- The depot container is 100% wide within target.content, so it
            -- tracks the same content width as the main factories table.
            if inst.depotArea and newCw ~= inst.depotArea.contentW then
                inst.depotArea.contentW = newCw
                inst.depotArea.contentLabel:resize(newCw, inst.depotArea.contentLabel:get_height())
                f2tTableOnResize(inst.depotTableId, newCw)
            end
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target)
            local inst = instances[target._gid]
            if inst then renderInstance(inst) end
        end,
    }
end

function f2tRegisterCompany()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[company] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_company_overview", makeDef(
        "Company Overview",
        "Company identity, status, alerts, and key figures from gmcp.char.company.",
        buildOverview))
    Mux.registerContent("fed2_company_factories", makeDef(
        "Company Factories",
        "Factory table with repair/start-stop/wages/destroy actions, plus depots.",
        buildFactories))
    Mux.registerContent("fed2_company_financials", makeDef(
        "Company Financials",
        "Share stats, dividend and share actions, and the shareholder table.",
        buildFinancials))
    if f2t_debug_log then
        f2t_debug_log("[company] registered fed2_company_overview/_factories/_financials")
    end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterCompany)

-- Live re-render on every company GMCP push — the only data source; there is
-- no polling or forced refresh.
registerAnonymousEventHandler("gmcp.char.company", function() refreshAll() end)

if f2t_debug_log then f2t_debug_log("[company] module loaded") end
