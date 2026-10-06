-- Hauling control strip shared by every Commerce panel: a Haul menu (actions
-- valid for the current state), the mode `haul start` runs (a menu when the
-- rank has more than one), and a status readout that runs `haul status` on
-- click. Every menu item runs the `haul` command it names, so the panel and
-- the command line stay one interface. The Haul menu is left out when there
-- is nothing it could do, and the status says why.

local CELL_PT  = 10   -- status font size (pt)
local LABEL_PT = 8    -- button and menu font size (pt)

local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

local _HDR_BAR_CSS = [[
    background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1, stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e);
    border: none;
    border-bottom: 1px solid rgba(70, 75, 110, 150);
]]

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

local _BTN_HAUL_CSS = actionBtnCss("#7aa2ff", "#9cb8ff")
local _BTN_MODE_CSS = actionBtnCss("#b48cff", "#c8a8ff")

local _MENU_ITEM_CSS = [[
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

local STATE_STYLE = {
    stopped  = { label = "STOPPED",   color = "#888888" },
    stopping = { label = "STOPPING…", color = "#ff5555" },
    paused   = { label = "PAUSED",    color = "#e0b84d" },
    pausing  = { label = "PAUSING…",  color = "#e0b84d" },
    running  = { label = "RUNNING",   color = "#3ecf5e" },
}

-- Live strips, keyed by the owning panel's _gid.
local strips = {}

local function haulCommand(command)
    expandAlias(command)
end

--- Haul menu entries valid for the current state
local function haulMenuItems(snap)
    if not snap.active then
        if snap.strategy and f2t_hauling_strategy_ready(snap.strategy) then
            return { { label = "▶ Start", command = "haul start" } }
        end
        return {}
    end

    local items = {}
    if snap.runState == "paused" then
        items[#items + 1] = { label = "▶ Resume", command = "haul resume" }
    elseif snap.runState == "pausing" then
        items[#items + 1] = { label = "✕ Cancel Pause", command = "haul resume" }
    else
        items[#items + 1] = { label = "⏸ Pause", command = "haul pause" }
    end
    items[#items + 1] = { label = "■ Stop",      command = "haul stop" }
    items[#items + 1] = { label = "⏹ Terminate", command = "haul terminate" }
    return items
end

--- Mode menu entries: every strategy this rank may run, current one marked
local function modeMenuItems(snap)
    local items = {}
    local setting = f2t_hauling_normalize_strategy(f2t_settings_get("hauling", "mode")) or "auto"
    for _, id in ipairs(f2t_hauling_available_strategies()) do
        local marked = (setting == id) or (setting == "auto" and id == snap.strategy and not snap.active)
        items[#items + 1] = {
            label   = (marked and "● " or "○ ") .. f2t_hauling_strategy_label(id),
            command = "haul mode " .. id,
        }
    end
    return items
end

local function closeMenu(strip)
    if strip.menu then
        strip.menu:hide()
        strip.menu = nil
    end
end

local function openMenu(strip, x, items)
    if strip.menu then
        closeMenu(strip)
        return
    end
    if #items == 0 then return end

    local target = strip.target
    local rowH   = f2tScaled(target, 22)
    local menuW  = f2tScaled(target, 250)
    local itemPt = f2tTextPt(target, LABEL_PT)

    strip.menuGen = strip.menuGen + 1
    local gen = strip.menuGen

    local menu = Geyser.Container:new({
        name = string.format("%s_hsm_%d", target._gid, gen),
        x = x, y = strip.height, width = menuW, height = #items * rowH,
    }, target.content)

    local bg = Geyser.Label:new({
        name = string.format("%s_hsmbg_%d", target._gid, gen),
        x = 0, y = 0, width = "100%", height = "100%",
    }, menu)
    bg:setStyleSheet([[
        background-color: rgba(20, 22, 32, 250);
        border: 1px solid rgba(100, 100, 110, 200);
        border-radius: 4px;
    ]])

    for i, item in ipairs(items) do
        local lbl = Geyser.Label:new({
            name = string.format("%s_hsmi_%d_%d", target._gid, gen, i),
            x = 1, y = (i - 1) * rowH, width = "100%-2px", height = rowH, fontSize = itemPt,
        }, menu)
        lbl:setStyleSheet(_MENU_ITEM_CSS)
        lbl:echo(string.format(
            "<table width='100%%'><tr><td style='%s'>%s</td>" ..
            "<td align='right' style='%scolor:#6f7896;'>%s</td></tr></table>",
            CELL_FONT, item.label, CELL_FONT, item.command))
        local command = item.command
        lbl:setClickCallback(function()
            closeMenu(strip)
            haulCommand(command)
        end)
    end

    menu:show()
    menu:raise()
    strip.menu = menu
end

-- Why hauling can't start, as a short note for the strip and the full reason
-- for its hover box; nil when it can (or is running).
local function blocker(snap)
    if snap.active then return nil end
    if snap.strategy then
        local ready, reason = f2t_hauling_strategy_ready(snap.strategy)
        if not ready then return "needs a price service", reason end
        return nil
    end
    local reason = f2t_hauling_unavailable_reason()
    if reason then return "no hauling at this rank", reason end
    return nil
end

local function statusHtml(snap)
    local style = STATE_STYLE[snap.runState] or STATE_STYLE.stopped
    local detail = ""
    local short = blocker(snap)
    if short then
        detail = string.format(" <span style='%scolor:#c09060;'>%s</span>", CELL_FONT, short)
    elseif snap.active and snap.phaseLabel then
        detail = string.format(" <span style='%scolor:#888888;'>%s</span>", CELL_FONT, snap.phaseLabel)
    elseif snap.totalCycles > 0 then
        detail = string.format(" <span style='%scolor:#666666;'>last: %d cycle%s</span>",
            CELL_FONT, snap.totalCycles, snap.totalCycles == 1 and "" or "s")
    end
    return string.format("<span style='%scolor:%s;font-weight:bold;'>&#9679; %s</span>%s",
        CELL_FONT, style.color, style.label, detail)
end

local function statusTooltip(snap)
    local sessionStrategy = snap.active and snap.strategy or snap.lastStrategy
    local mode = f2t_hauling_strategy_label(sessionStrategy)
    local stats
    if sessionStrategy == "planet" or sessionStrategy == "deficit" then
        stats = string.format("Cycles: %d (deficit %d, excess %d)",
            snap.totalCycles, snap.deficitCycles, snap.excessCycles)
    else
        stats = string.format("Cycles: %d  |  Profit: %d ig", snap.totalCycles, snap.sessionProfit)
    end
    if snap.active then
        return string.format("%s  |  %s", mode, stats)
    elseif snap.totalCycles > 0 then
        return string.format("Last session (%s): %s", mode, stats)
    end
    return snap.strategyNote or "Not running"
end

local function render(strip)
    local snap = f2tHaulingSnapshot()
    strip.statusLbl:echo(statusHtml(snap))
    local _, reason = blocker(snap)
    strip.tooltipText = (reason or statusTooltip(snap)) .. ". Click for haul status."

    local x = 6
    if #haulMenuItems(snap) > 0 then
        strip.haulBtn:move(x, nil)
        strip.haulBtn:show()
        x = x + strip.haulBtnW + 6
    else
        strip.haulBtn:hide()
    end

    strip.multiMode = #f2t_hauling_available_strategies() > 1
    if snap.strategy then
        strip.modeBtn:echo(string.format("<center>%s%s</center>", f2t_hauling_strategy_label(snap.strategy),
            strip.multiMode and " ▾" or ""))
        strip.modeBtn:move(x, nil)
        strip.modeBtn:show()
        strip.modeBtnX = x
        x = x + strip.modeBtnW + 8
    else
        strip.modeBtn:hide()
    end

    strip.statusLbl:move(x, nil)
    strip.statusLbl:resize("100%-" .. (x + 6) .. "px", nil)
end

local function renderAll()
    for _, strip in pairs(strips) do pcall(render, strip) end
end

registerAnonymousEventHandler("f2tHaulingStatusChanged", renderAll)
-- Price services decide whether exchange and planet hauling can start.
registerAnonymousEventHandler("gmcp.char.vitals.tools", renderAll)
registerAnonymousEventHandler("gmcp.char.vitals", function()
    -- Only the rank matters here; skip the redraw for every other vitals tick.
    local rank = f2t_get_rank()
    for _, strip in pairs(strips) do
        if strip.rank ~= rank then
            strip.rank = rank
            pcall(render, strip)
        end
    end
end)

-- Hover text drawn with a Geyser label: per-widget QToolTip rules proved
-- unreliable on these dark labels.
local function showHoverTip(strip, x, text)
    if not text or text == "" then return end
    local target = strip.target
    -- Wrapped to fit the panel, and tall enough for the lines the text needs.
    local width = math.min(f2tScaled(target, 300), math.max(120, target.content:get_width() - x - 6))
    local charPx = f2tUiPt(target, CELL_PT) * 1.33 * 0.6
    local perLine = math.max(10, math.floor((width - 14) / charPx))
    local lines = math.ceil(#text / perLine)
    local height = lines * math.ceil(f2tUiPt(target, CELL_PT) * 1.33 * 1.35) + 8
    if not strip.hoverTip then
        strip.hoverTip = Geyser.Label:new({
            name = target._gid .. "_hstip", x = x, y = strip.height, width = width, height = height,
            fontSize = f2tUiPt(target, CELL_PT),
        }, target.content)
        strip.hoverTip:setStyleSheet(string.format([[
            QLabel {
                background-color: rgba(29, 32, 48, 250);
                border: 1px solid rgba(255,255,255,0.18);
                border-radius: 3px;
                color: #e8ebf5;
                padding: 2px 6px;
                qproperty-wordWrap: true;
                %s
            }
        ]], CELL_FONT))
    end
    strip.hoverTip:move(x, nil)
    strip.hoverTip:resize(width, height)
    strip.hoverTip:echo(text)
    strip.hoverTip:show()
    strip.hoverTip:raise()
end

local function hideHoverTip(strip)
    if strip.hoverTip then strip.hoverTip:hide() end
end

--- Build the strip across the top of a panel
--- @param target table Muxlet content target
--- @return table strip Handle with .height (px) for laying out the rest of the panel
function f2tHaulStripCreate(target)
    local gid    = target._gid
    local height = f2tScaled(target, 26)
    local labelPt = f2tTextPt(target, LABEL_PT)

    local bar = Geyser.Label:new({
        name = gid .. "_hs_bar", x = 0, y = 0, width = "100%", height = height,
    }, target.content)
    bar:setStyleSheet(_HDR_BAR_CSS)

    local haulBtnX = 6
    local haulBtnW = f2tScaled(target, 70)
    local haulBtn = Geyser.Label:new({
        name = gid .. "_hs_haul", x = haulBtnX, y = 4, width = haulBtnW, height = height - 8, fontSize = labelPt,
    }, bar)
    haulBtn:setStyleSheet(_BTN_HAUL_CSS)
    haulBtn:echo("<center>Haul ▾</center>")

    local modeBtnW = f2tScaled(target, 92)
    local modeBtn = Geyser.Label:new({
        name = gid .. "_hs_mode", x = haulBtnX + haulBtnW + 6, y = 4, width = modeBtnW, height = height - 8,
        fontSize = labelPt,
    }, bar)
    modeBtn:setStyleSheet(_BTN_MODE_CSS)

    local statusLbl = Geyser.Label:new({
        name = gid .. "_hs_status", x = 0, y = 0, width = "100%", height = "100%",
        fontSize = f2tUiPt(target, CELL_PT),
    }, bar)
    statusLbl:setStyleSheet("background-color: transparent; border: none;")

    local strip = {
        target    = target,
        height    = height,
        bar       = bar,
        haulBtn   = haulBtn,
        haulBtnW  = haulBtnW,
        modeBtn   = modeBtn,
        modeBtnW  = modeBtnW,
        modeBtnX  = haulBtnX + haulBtnW + 6,
        statusLbl = statusLbl,
        menu      = nil,
        menuGen   = 0,
        rank      = f2t_get_rank(),
    }
    strips[gid] = strip

    haulBtn:setClickCallback(function()
        hideHoverTip(strip)
        openMenu(strip, haulBtnX, haulMenuItems(f2tHaulingSnapshot()))
    end)
    haulBtn:setOnEnter(function() showHoverTip(strip, haulBtnX, "Start, pause or stop hauling (haul ...)") end)
    haulBtn:setOnLeave(function() hideHoverTip(strip) end)

    modeBtn:setClickCallback(function()
        hideHoverTip(strip)
        if strip.multiMode then openMenu(strip, strip.modeBtnX, modeMenuItems(f2tHaulingSnapshot())) end
    end)
    modeBtn:setOnEnter(function()
        showHoverTip(strip, strip.modeBtnX, strip.multiMode and "What 'haul start' runs (haul mode ...)"
            or "What 'haul start' runs at your rank")
    end)
    modeBtn:setOnLeave(function() hideHoverTip(strip) end)

    statusLbl:setClickCallback(function()
        hideHoverTip(strip)
        haulCommand("haul status")
    end)
    statusLbl:setOnEnter(function()
        showHoverTip(strip, strip.statusLbl:get_x() - target.content:get_x(), strip.tooltipText)
    end)
    statusLbl:setOnLeave(function() hideHoverTip(strip) end)

    render(strip)
    return strip
end

--- Forget a panel's strip (its widgets go with the panel)
--- @param gid string Owning panel's _gid
function f2tHaulStripRemove(gid)
    strips[gid] = nil
end

if f2t_debug_log then f2t_debug_log("[haul_strip] module loaded") end
