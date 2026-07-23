-- Company / business management content. Four separate registered contents,
-- all rendered from gmcp.char.company, each placeable in its own pane/subtab:
--   fed2_company_overview   - identity, status, repair alerts, key figures
--   fed2_company_factories  - sortable factory table with inline actions, depot list
--   fed2_company_financials - share stats, dividend/purchase actions, shareholder table
--   fed2_company_portfolio  - holdings in other companies (Financier+), sortable table
--
-- Action dialogs use Muxlet primitives throughout (Mux.createDialog,
-- Mux.dialogCss, Mux.wireDialogButton, Mux.ui.buildForm).
--
-- gmcp.char.company is realtime (a fresh copy pushes after every action that
-- changes it), so panels just re-render on that event; nothing polls here.
-- Each panel's header carries a small icon button that sends `di company` /
-- `di business` / `di accounts` visibly, drawn in-content so it's always
-- visible regardless of the hosting pane/tab chrome.

local H_BAR = 24    -- header strip height (px): houses the report/accounts icon button
local H_COL = 20    -- column header bar height (px)
local ROW_H = 20    -- table row height (px)
local SB_W  = 17    -- scrollbar pixel allowance
local H_FIN = 210   -- financials stats block height (px): stats + analysis, sized to fit without scrolling
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

local function reportCommand()
    return f2t_is_rank_or_above("Manufacturer") and "di company" or "di business"
end

-- Icon button CSS (mirrors player_card.lua's _CSS_ICON, used there for the
-- same "view accounts" action) — a bordered square with a hover state.
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
local _ICON_BTN_CSS = [[
    QLabel {
        background-color: rgba(32, 36, 58, 220);
        color: rgba(165, 180, 220, 255);
        border: 1px solid rgba(80, 92, 140, 210);
        border-radius: 4px;
        font-size: 14px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(50, 58, 95, 240);
        border-color: rgba(120, 150, 220, 230);
        color: white;
    }
]]

-- Slim header strip: optional left-aligned status text + a right-aligned
-- icon button that sends `cmdFn()` (evaluated at click time, since the
-- report command depends on the player's live rank). Visible in-content —
-- NOT a titlebar element — so it always shows regardless of pane chrome.
-- Returns the bar and the title label (the latter used by Portfolio to show
-- a live holdings summary).
local function buildHeaderStrip(target, wid, icon, tooltip, cmdFn, titleText)
    local bar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_BAR,
    }, target.content)
    bar:setStyleSheet(_HDR_STRIP_CSS)

    local titleLbl = Geyser.Label:new({
        name = wid(), x = 6, y = 0, width = "-28", height = H_BAR,
    }, bar)
    titleLbl:setStyleSheet(_HDR_TITLE_CSS)
    if titleText then titleLbl:echo(titleText) end

    local btn = Geyser.Label:new({
        name = wid(), x = "-25", y = 2, width = 20, height = H_BAR - 4,
    }, bar)
    btn:setStyleSheet(_ICON_BTN_CSS)
    btn:echo("<center>" .. icon .. "</center>")
    btn:setToolTip(tooltip)
    btn:setClickCallback(function() send(cmdFn(), false) end)

    return bar, titleLbl
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

-- ── Stat tile grid (shared by Overview, Financials, Portfolio) ──────────────
-- Widget-based stat display, NOT text-in-a-console: every tile's x/y/width/
-- height is a percentage of its container, so a grid of N tiles always
-- exactly fills whatever space it's given — nothing is ever clipped and
-- nothing ever needs a scrollbar. Panels rebuild their grid every render
-- (delete old tiles, create new ones) since item count varies with the data,
-- the same delete/recreate approach galaxy.lua uses for its row tree.

local _TILE_CSS = [[
    QLabel {
        background-color: rgba(24, 28, 46, 220);
        border: 1px solid rgba(72, 85, 128, 160);
        border-radius: 5px;
    }
]]
local TILE_GUTTER = 1.5   -- percent gap between tiles, both axes

local function tileHtml(icon, value, valueColor, caption)
    return string.format(
        "<div style='text-align:center;padding-top:5px;'>" ..
        "<span style='font-size:16px;font-weight:bold;color:%s;'>%s %s</span><br>" ..
        "<span style='font-size:9px;color:#888899;letter-spacing:1px;'>%s</span></div>",
        valueColor, icon, value, caption)
end

-- Lays out `items` ({icon,value,color,caption,tooltip,onClick}) as a grid of
-- tile Labels filling `container`, `cols` wide. Returns the created tiles;
-- callers own their own widget-list bookkeeping (delete last render's tiles
-- before calling this again).
local function buildTileGrid(container, wid, items, cols)
    local made = {}
    local n = #items
    if n == 0 then return made end
    local rows  = math.max(1, math.ceil(n / cols))
    local tileW = 100 / cols
    local tileH = 100 / rows
    for i, item in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local tile = Geyser.Label:new({
            name   = wid(),
            x      = (col * tileW + TILE_GUTTER) .. "%",
            y      = (row * tileH + TILE_GUTTER) .. "%",
            width  = (tileW - 2 * TILE_GUTTER) .. "%",
            height = (tileH - 2 * TILE_GUTTER) .. "%",
        }, container)
        tile:setStyleSheet(_TILE_CSS)
        tile:echo(tileHtml(item.icon, item.value, item.color or "#e8e8f0", item.caption))
        if item.tooltip then tile:setToolTip(item.tooltip) end
        if item.onClick then tile:setClickCallback(item.onClick) end
        made[#made + 1] = tile
    end
    return made
end

local _BADGE_RUN_CSS = [[
    QLabel {
        background-color: rgba(20, 50, 30, 200);
        border: 1px solid rgba(60, 180, 90, 180);
        border-radius: 4px;
        color: #6bffa0;
        font-size: 12px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(30, 70, 40, 230); }
]]
local _BADGE_FROZEN_CSS = [[
    QLabel {
        background-color: rgba(55, 45, 15, 200);
        border: 1px solid rgba(200, 160, 60, 180);
        border-radius: 4px;
        color: #ffd980;
        font-size: 12px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(70, 58, 20, 230); }
]]
local _ALERT_CSS = [[
    QLabel {
        background-color: rgba(60, 24, 24, 210);
        border: 1px solid rgba(200, 80, 80, 200);
        border-radius: 5px;
        color: #ff9a9a;
        font-size: 12px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(80, 30, 30, 230); }
]]

-- Accent-colored action buttons (same left-accent-bar pattern as
-- hauling_jobs.lua / price_checker.lua's Work/Collect/Check buttons) —
-- used by Financials' Issue Dividend / Buy Shares / Buy Treasury row.
local function actionBtnCss(accent, accentHover)
    return string.format([[
        QLabel {
            background-color: rgba(26,30,46,220);
            color: rgba(210,220,240,255);
            border: 1px solid rgba(72,85,128,180);
            border-left: 3px solid %s;
            border-radius: 4px;
            font-size: 11px; font-weight: bold; font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(38,44,66,235);
            border-left: 3px solid %s;
            color: white;
        }
    ]], accent, accentHover)
end
local _BTN_DIVIDEND_CSS = actionBtnCss("#e0b84d", "#f0cc66")
local _BTN_BUY_CSS      = actionBtnCss("#3aa0ff", "#5cb8ff")
local _BTN_TREASURY_CSS = actionBtnCss("#8888aa", "#aaaacc")

-- ── Data rows (Overview + Financials' stat blocks) ───────────────────────────
-- Dense label:value rows — closer to the original console's packed text
-- layout than a grid of bordered tiles, but real widgets (an HTML <table> per
-- row for font-independent column alignment, not console text), so
-- percentage geometry still guarantees an exact fit with nothing to scroll.

local _SECTION_HDR_CSS = [[
    background: transparent; border: none;
    border-bottom: 1px solid rgba(90, 100, 140, 140);
]]

local function rowCellHtml(label, value, color)
    return string.format(
        "<td style='padding:2px 8px;color:rgba(155,165,200,220);font-size:11px;white-space:nowrap;'>%s</td>" ..
        "<td style='padding:2px 16px 2px 4px;color:%s;font-size:13px;font-weight:bold;white-space:nowrap;'>%s</td>",
        label, color or "#e8e8f0", value)
end

-- Builds an optional section header ("icon TITLE" + divider) followed by
-- `items` ({label,value,color}) packed `perRow` to a row, each row a single
-- HTML-table Label (striped for readability). All widgets are appended
-- directly to inst.widgets. Pass title=nil to skip the header entirely
-- (used for the identity block, which reads fine without one).
local function buildStatSection(inst, container, wid, icon, title, items, perRow)
    perRow = perRow or 2
    local yTop, hAvail = 0, 100
    if title then
        local hdr = Geyser.Label:new({ name = wid(), x = 0, y = 0, width = "100%", height = "22%" }, container)
        hdr:setStyleSheet(_SECTION_HDR_CSS)
        hdr:echo(string.format(
            "<span style='font-size:11px;font-weight:bold;letter-spacing:1px;color:rgba(150,165,210,235);'>" ..
            "%s&nbsp;%s</span>", icon, title))
        inst.widgets[#inst.widgets + 1] = hdr
        yTop, hAvail = 22, 78
    end

    local n = #items
    if n == 0 then return end
    local rowCount = math.max(1, math.ceil(n / perRow))
    local rowH = hAvail / rowCount
    for r = 0, rowCount - 1 do
        local cells = ""
        for c = 1, perRow do
            local item = items[r * perRow + c]
            cells = cells .. (item
                and rowCellHtml(item.label, item.value, item.color)
                or  "<td width='50%'></td><td></td>")
        end
        local row = Geyser.Label:new({
            name = wid(), x = 0, y = (yTop + r * rowH) .. "%", width = "100%", height = rowH .. "%",
        }, container)
        row:setStyleSheet(r % 2 == 1
            and "background-color: rgba(255,255,255,12); border:none;"
            or  "background: transparent; border:none;")
        row:echo(string.format("<table width='100%%' cellspacing='0' cellpadding='0'><tr>%s</tr></table>", cells))
        inst.widgets[#inst.widgets + 1] = row
    end
end

-- ── Overview panel ────────────────────────────────────────────────────────────

-- Company name (left, the largest text on the panel) + running/frozen status
-- pill (right, click to freeze) — sized to hug its text, not stretch to fill
-- the row.
local function buildStatusRow(inst, box, wid, c)
    local nameLbl = Geyser.Label:new({ name = wid(), x = "2%", y = 0, width = "70%", height = "100%" }, box)
    nameLbl:setStyleSheet("background: transparent; border: none; color: #ffffff; font-size: 22px; font-weight: bold;")
    nameLbl:echo(c.name or "Unknown Company")
    inst.widgets[#inst.widgets + 1] = nameLbl

    local running = (c.status == "running")
    local badge = Geyser.Label:new({ name = wid(), x = "76%", y = "26%", width = "20%", height = "48%" }, box)
    badge:setStyleSheet(running and _BADGE_RUN_CSS or _BADGE_FROZEN_CSS)
    badge:echo(running and "<center>● RUNNING</center>" or "<center>⊘ FROZEN</center>")
    badge:setToolTip("Click to freeze/unfreeze")
    badge:setClickCallback(function() dialogFreeze() end)
    inst.widgets[#inst.widgets + 1] = badge
end

local function renderOverview(inst)
    local body = inst.body
    if not body then return end

    for _, w2 in ipairs(inst.widgets or {}) do pcall(function() w2:delete() end) end
    inst.widgets = {}

    local c = companyData()
    if not c then
        inst.emptyLbl:show()
        return
    end
    inst.emptyLbl:hide()

    inst.epoch = (inst.epoch or 0) + 1
    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_covd_%d_%d", inst.gid, inst.epoch, wc)
    end

    local isMfr  = f2t_is_rank_or_above("Manufacturer")
    local profit = c.profit or 0

    local alertCount = 0
    if isMfr and c.factories then
        for _, fac in ipairs(c.factories) do
            if effPct(fac) < 80 then alertCount = alertCount + 1 end
        end
    end

    -- Vertical sections, weighted so the body always sums to exactly 100% —
    -- nothing is ever clipped or needs to scroll, regardless of which
    -- optional sections (alerts, investors) are present this render.
    -- Weights are in "row units" — financials/investors carry a header plus
    -- up to 4 packed rows each, roughly twice identity's row count, so they
    -- get proportionally more of the body.
    local sections = { { key = "status", weight = 1.3 }, { key = "identity", weight = 0.6 } }
    if alertCount > 0 then sections[#sections + 1] = { key = "alerts", weight = 0.6 } end
    sections[#sections + 1] = { key = "financials", weight = 2.2 }
    if isMfr then sections[#sections + 1] = { key = "investors", weight = 2.2 } end

    local totalWeight = 0
    for _, s in ipairs(sections) do totalWeight = totalWeight + s.weight end
    local yPct = 0
    for _, s in ipairs(sections) do
        s.yPct = yPct
        s.hPct = s.weight / totalWeight * 100
        yPct = yPct + s.hPct
    end

    local function sectionBox(s)
        local box = Geyser.Label:new({
            name = wid(), x = 0, y = s.yPct .. "%", width = "100%", height = s.hPct .. "%",
        }, body)
        box:setStyleSheet("background-color: transparent; border: none;")
        inst.widgets[#inst.widgets + 1] = box
        return box
    end

    for _, s in ipairs(sections) do
        if s.key == "status" then
            buildStatusRow(inst, sectionBox(s), wid, c)

        elseif s.key == "identity" then
            local box = sectionBox(s)
            local rank  = f2t_get_rank()
            local items = {}
            if c.ceo then
                items[#items + 1] = { label = "CEO", value = rank and (rank .. " " .. c.ceo) or c.ceo }
            end
            items[#items + 1] = { label = "Cycles Run", value = tostring(c.total_cycles or 0) }
            if c.ac_cycle then
                local col = c.ac_cycle <= 1 and "#ff5555" or (c.ac_cycle <= 3 and "#cccc44" or "#00cc44")
                items[#items + 1] = { label = "Accounts Due", value = c.ac_cycle .. " days", color = col }
            end
            buildStatSection(inst, box, wid, nil, nil, items, 2)

        elseif s.key == "alerts" then
            local box = sectionBox(s)
            local badge = Geyser.Label:new({ name = wid(), x = "2%", y = "10%", width = "96%", height = "80%" }, box)
            badge:setStyleSheet(_ALERT_CSS)
            badge:echo(string.format("<center>⚠  %d factor%s under 80%% efficiency — click for detail</center>",
                alertCount, alertCount == 1 and "y" or "ies"))
            badge:setToolTip("Show raw report for full factory list")
            badge:setClickCallback(function() send(reportCommand(), false) end)
            inst.widgets[#inst.widgets + 1] = badge

        elseif s.key == "financials" then
            local box = sectionBox(s)
            local pc = profit >= 0 and "#00cc44" or "#ff5555"
            local items = {
                { label = "Cash",   value = fmtComma(c.cash) .. "ig", color = "#00cccc" },
                { label = "Profit", value = fmtComma(profit) .. "ig", color = pc },
            }
            if c.tax then
                items[#items + 1] = { label = "Tax Paid", value = fmtComma(c.tax) .. "ig" }
            end
            if c.revenue and c.revenue.income then
                items[#items + 1] = { label = "Revenue", value = "+" .. fmtComma(c.revenue.income) .. "ig",
                    color = "#00cc44" }
            end
            if c.revenue and c.revenue.expenses then
                items[#items + 1] = { label = "Expenses", value = "-" .. fmtComma(c.revenue.expenses) .. "ig",
                    color = "#ff5555" }
            end
            if c.capital then
                local ce = tonumber(c.capital.expenditure) or 0
                local cr = tonumber(c.capital.receipts)    or 0
                items[#items + 1] = { label = "Capital Exp", value = (ce > 0 and "-" or "") .. fmtComma(ce) .. "ig",
                    color = ce > 0 and "#ff5555" or nil }
                items[#items + 1] = { label = "Capital Rec", value = (cr > 0 and "+" or "") .. fmtComma(cr) .. "ig",
                    color = cr > 0 and "#00cc44" or nil }
            end
            buildStatSection(inst, box, wid, "💰", "FINANCIALS", items, 2)

        elseif s.key == "investors" then
            local box = sectionBox(s)
            local shares = sumShares(c)
            local sv, div, da = c.share_value or 0, c.dividend or 0, c.disaffection or 0
            local eps   = shares > 0 and math.floor(profit / shares) or 0
            local peStr = (sv > 0 and eps > 0) and string.format("%.1f", sv / eps) or "N/A"
            local daCol = da < 20 and "#00cc44" or (da < 50 and "#cccc44" or "#ff5555")
            local items = {
                { label = "Disaffection", value = da .. "%", color = daCol },
                { label = "Share Price",  value = fmtComma(sv) .. "ig" },
                { label = "EPS",          value = fmtComma(eps) .. "ig/sh" },
                { label = "P/E",          value = peStr },
                { label = "Dividend",     value = fmtComma(div) .. "ig/sh" },
                { label = "Shares",       value = fmtComma(shares) },
                { label = "Market Cap",   value = fmtCompact(sv * shares) },
            }
            if (c.total_cycles or 0) >= 4 and profit > 0 then
                items[#items + 1] = { label = "Fin. Promotion", value = "★ Eligible", color = "#00cc44" }
            end
            buildStatSection(inst, box, wid, "📈", "INVESTORS", items, 2)
        end
    end

    -- This render is independent of Mux._applyContent's own apply-time
    -- rebuild — it re-fires on every gmcp.char.company push, regardless of
    -- whether this panel's tab is currently active. Geyser shows freshly
    -- created widgets unconditionally, ignoring an ancestor's hidden state
    -- (see Mux.reassertHidden's docstring in Muxlet's content.lua, and
    -- table_system.lua / galaxy.lua for the same pattern), so a rebuild
    -- while hidden would otherwise leak the new tiles visible over whatever
    -- tab actually is showing.
    if Mux and Mux.reassertHidden then Mux.reassertHidden(body) end
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

    buildHeaderStrip(target, wid, "📋", "Show raw company report (di company / di business)", reportCommand)

    local body = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = "100%-" .. H_BAR .. "px",
    }, target.content)
    body:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local emptyLbl = Geyser.Label:new({ name = wid(), x = 0, y = 0, width = "100%", height = "100%" }, body)
    emptyLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    emptyLbl:echo(emptyStateHtml("No company data yet."))
    emptyLbl:hide()

    instances[gid] = { kind = "overview", gid = gid, body = body, emptyLbl = emptyLbl, widgets = {}, epoch = 0 }
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

    buildHeaderStrip(target, wid, "📋", "Show raw company report (di company / di business)", reportCommand)

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
    local statsBox = inst.statsBox
    if not statsBox then return end

    for _, w2 in ipairs(inst.widgets or {}) do pcall(function() w2:delete() end) end
    inst.widgets = {}

    local c = companyData()
    if not c then
        inst.emptyLbl:show()
        f2tTableSetData(inst.tableId, {})
        return
    end
    inst.emptyLbl:hide()

    inst.epoch = (inst.epoch or 0) + 1
    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cfid_%d_%d", inst.gid, inst.epoch, wc)
    end

    local shares = sumShares(c)
    local sv     = c.share_value or 0
    local div    = c.dividend    or 0
    local profit = c.profit      or 0
    local eps    = shares > 0 and math.floor(profit / shares) or 0
    local pd     = div > 0 and string.format("%.1f", sv / div) or "∞"
    local pdCol  = div > 0 and nil or "#ff5555"
    local pe     = (sv > 0 and eps > 0) and string.format("%.1f", sv / eps) or "N/A"

    local payout    = profit > 0 and (div * shares / profit * 100) or nil
    local payoutStr = payout and string.format("%.0f%%", payout) or "N/A"
    local payoutCol
    if payout then
        payoutCol = payout > 100 and "#ff5555" or (payout > 50 and "#cccc44" or "#00cc44")
    end

    local tax     = c.tax or 0
    local pretax  = profit + tax
    local taxRate = pretax > 0 and (tax / pretax * 100) or nil
    local taxStr  = taxRate and string.format("%.0f%%", taxRate) or "N/A"

    local netCapStr, netCapCol = "N/A", nil
    if c.capital then
        local netCap = (tonumber(c.capital.receipts) or 0) - (tonumber(c.capital.expenditure) or 0)
        netCapStr = fmtComma(netCap) .. "ig"
        netCapCol = netCap < 0 and "#ff5555" or "#00cc44"
    end

    -- Two stacked sections (each 50% of statsBox) mirror the original
    -- console's Share Stats / Analysis blocks.
    local shareBox = Geyser.Label:new({
        name = wid(), x = 0, y = "0%", width = "100%", height = "50%",
    }, statsBox)
    shareBox:setStyleSheet("background: transparent; border: none;")
    inst.widgets[#inst.widgets + 1] = shareBox
    buildStatSection(inst, shareBox, wid, "💹", "SHARE STATS", {
        { label = "Share Price",   value = fmtComma(sv) .. "ig" },
        { label = "Market Cap",    value = fmtCompact(sv * shares) },
        { label = "EPS",           value = fmtComma(eps) .. "ig/sh" },
        { label = "P/E",           value = pe },
        { label = "Dividend",      value = fmtComma(div) .. "ig/sh" },
        { label = "P/D",           value = pd, color = pdCol },
        { label = "Total Shares",  value = fmtComma(shares) },
    }, 2)

    local analysisBox = Geyser.Label:new({
        name = wid(), x = 0, y = "50%", width = "100%", height = "50%",
    }, statsBox)
    analysisBox:setStyleSheet("background: transparent; border: none;")
    inst.widgets[#inst.widgets + 1] = analysisBox
    buildStatSection(inst, analysisBox, wid, "📐", "ANALYSIS", {
        { label = "Payout Ratio", value = payoutStr, color = payoutCol },
        { label = "Tax Rate",     value = taxStr },
        { label = "Net Capital",  value = netCapStr, color = netCapCol },
    }, 2)

    -- See the matching comment in renderOverview: a live gmcp.char.company
    -- rebuild must reassert hidden state or freshly created tiles leak
    -- visible over whatever tab is actually active.
    if Mux and Mux.reassertHidden then Mux.reassertHidden(statsBox) end

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

    buildHeaderStrip(target, wid, "📊", "View accounts (di accounts)", function() return "di accounts" end)

    local statsH = math.floor(H_FIN * 0.76)
    local btnH   = H_FIN - statsH

    local statsBox = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = statsH,
    }, target.content)
    statsBox:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local emptyLbl = Geyser.Label:new({ name = wid(), x = 0, y = 0, width = "100%", height = "100%" }, statsBox)
    emptyLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    emptyLbl:echo(emptyStateHtml("No company data yet."))
    emptyLbl:hide()

    -- Action buttons: built once (static — dialogDividend/dialogBuyShares
    -- pull live data themselves), same accent-bar hover style as
    -- hauling_jobs.lua / price_checker.lua's action buttons.
    local btnBox = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR + statsH, width = "100%", height = btnH,
    }, target.content)
    btnBox:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local buttons = {
        { label = "🎁 Issue Dividend", css = _BTN_DIVIDEND_CSS, fn = function() dialogDividend() end,
          tip = "Issue a dividend to all shareholders" },
        { label = "📈 Buy Shares",     css = _BTN_BUY_CSS,      fn = function() dialogBuyShares(false, nil) end,
          tip = "Buy personal shares" },
        { label = "🏦 Buy Treasury",   css = _BTN_TREASURY_CSS, fn = function() dialogBuyShares(true, nil) end,
          tip = "Buy treasury shares" },
    }
    for i, b in ipairs(buttons) do
        local btn = Geyser.Label:new({
            name = wid(), x = ((i - 1) * 100 / 3 + 1) .. "%", y = "10%", width = (100 / 3 - 2) .. "%", height = "80%",
        }, btnBox)
        btn:setStyleSheet(b.css)
        btn:echo("<center>" .. b.label .. "</center>")
        btn:setToolTip(b.tip)
        btn:setClickCallback(b.fn)
    end

    local tableId = "co_shareholders_" .. gid
    local area = buildTableArea(target.content, wid, tableId, shareholderCols(),
        H_BAR + H_FIN, "100%-" .. (H_BAR + H_FIN + H_COL) .. "px")

    instances[gid] = {
        kind      = "financials",
        gid       = gid,
        statsBox  = statsBox,
        emptyLbl  = emptyLbl,
        tableId   = tableId,
        area      = area,
        widgets   = {},
        epoch     = 0,
    }
    renderFinancials(instances[gid])
end

-- ── Portfolio panel ───────────────────────────────────────────────────────────
-- Your holdings in OTHER companies (gmcp.char.company.portfolio) — a
-- Financier-rank concept, so gated separately from the other three panels
-- (Industrialist/Manufacturer companies don't carry this data).

local H_SUM = 60    -- portfolio summary strip height (px): two stat tiles

local function portfolioCols()
    return {
        {
            key           = "company",
            label         = "Company",
            sortable      = true,
            sort_value    = function(r) return r.company:lower() end,
            scrollbox_pct = 70,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#00cccc;text-decoration:underline;'>%s</span>", CELL_FONT, v))
                cell:setToolTip("di company " .. tostring(v))
                cell:setClickCallback(function() send("di company " .. row.company, false) end)
            end,
        },
        {
            key           = "quantity",
            label         = "Shares",
            sortable      = true,
            default_sort  = "desc",
            sort_value    = function(r) return r.quantity or 0 end,
            scrollbox_pct = 30,
            render_label  = function(v, row, cell)
                cell:echo(string.format("<span style='%scolor:#ffffff;'>%s</span>", CELL_FONT, fmtComma(v)))
            end,
        },
    }
end

local function renderPortfolio(inst)
    local summaryBar = inst.summaryBar
    if not summaryBar then return end

    for _, w2 in ipairs(inst.widgets or {}) do pcall(function() w2:delete() end) end
    inst.widgets = {}

    local c     = companyData()
    local isFin = f2t_is_rank_or_above("Financier")

    local rows, total = {}, 0
    if isFin and c and c.portfolio then
        for _, h in ipairs(c.portfolio) do
            rows[#rows + 1] = { company = h.company, quantity = h.quantity }
            total = total + (h.quantity or 0)
        end
    end
    f2tTableSetData(inst.tableId, rows)

    inst.epoch = (inst.epoch or 0) + 1
    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cpfd_%d_%d", inst.gid, inst.epoch, wc)
    end

    local items
    if not isFin then
        items = {
            { icon = "💼", value = "—", color = "#666677", caption = "TOTAL SHARES" },
            { icon = "🔒", value = "—", color = "#666677", caption = "FINANCIER RANK" },
        }
    else
        items = {
            { icon = "💼", value = fmtComma(total), color = "#00cccc", caption = "TOTAL SHARES" },
            { icon = "🏢", value = tostring(#rows), color = "#00cc44",
              caption = #rows == 1 and "COMPANY" or "COMPANIES" },
        }
    end
    local tiles = buildTileGrid(summaryBar, wid, items, 2)
    for _, t in ipairs(tiles) do inst.widgets[#inst.widgets + 1] = t end

    -- See the matching comment in renderOverview: a live gmcp.char.company
    -- rebuild must reassert hidden state or freshly created tiles leak
    -- visible over whatever tab is actually active.
    if Mux and Mux.reassertHidden then Mux.reassertHidden(summaryBar) end

    if inst.emptyLbl then
        if #rows == 0 then
            inst.emptyLbl:echo(emptyStateHtml(isFin
                and "No portfolio holdings."
                or  "Portfolio holdings are shown here at Financier rank and above."))
            inst.emptyLbl:show()
        else
            inst.emptyLbl:hide()
        end
    end
end

local function buildPortfolio(target)
    local gid = target._gid
    primeCompanyDataIfMissing()
    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end
    if instances[gid] then
        renderPortfolio(instances[gid])
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cpf_%d", gid, wc)
    end

    buildHeaderStrip(target, wid, "📋",
        "Show raw company report (di company / di business)", reportCommand)

    local summaryBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = H_SUM,
    }, target.content)
    summaryBar:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local tableId = "co_portfolio_" .. gid
    local area = buildTableArea(target.content, wid, tableId, portfolioCols(),
        H_BAR + H_SUM, "100%-" .. (H_BAR + H_SUM + H_COL) .. "px")

    -- Overlays the table area when there are no holdings (or below Financier
    -- rank); f2tTableSetData leaves an empty scrollbox with no message of its own.
    local emptyLbl = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR + H_SUM + H_COL, width = "100%",
        height = "100%-" .. (H_BAR + H_SUM + H_COL) .. "px",
    }, target.content)
    emptyLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    emptyLbl:hide()

    instances[gid] = {
        kind        = "portfolio",
        gid         = gid,
        summaryBar  = summaryBar,
        tableId     = tableId,
        area        = area,
        emptyLbl    = emptyLbl,
        widgets     = {},
        epoch       = 0,
    }
    renderPortfolio(instances[gid])
end

-- ── Render dispatch + registration ────────────────────────────────────────────

local RENDERERS = {
    overview   = renderOverview,
    factories  = renderFactories,
    financials = renderFinancials,
    portfolio  = renderPortfolio,
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
        group       = "F2CE Tools",
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
        "Share stats, dividend/share actions, and the shareholder table.",
        buildFinancials))
    Mux.registerContent("fed2_company_portfolio", makeDef(
        "Company Portfolio",
        "Your shareholdings in other companies (Financier rank and above).",
        buildPortfolio))
    if f2t_debug_log then
        f2t_debug_log("[company] registered fed2_company_overview/_factories/_financials/_portfolio")
    end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterCompany)

-- Live re-render on every company GMCP push — the only data source; there is
-- no polling or forced refresh.
registerAnonymousEventHandler("gmcp.char.company", function() refreshAll() end)

if f2t_debug_log then f2t_debug_log("[company] module loaded") end
