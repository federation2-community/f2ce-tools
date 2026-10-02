-- Stockpiles tab for planet owners: preview a planet's planned min/max stock
-- and spread changes (po/stockpile.lua), apply them, and toggle auto mode.
-- Changed values show old→new in yellow; unchanged values are dimmed.
--
-- Everything here reads F2T_STOCKPILE and redraws on f2tStockpileChanged;
-- the commands (`po stockpile ...`) work the same whether or not it's open.

local H_BAR  = 26
local H_COL  = 20
local ROW_H  = 20
local SB_W   = 17
local CELL_PT  = 10   -- cell, status and empty-state font size (pt)
local LABEL_PT = 8    -- column header, button and menu font size (pt)

-- Size comes from the label's fontSize (cells: f2tTableSetScrollbox's cellPt).
local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

local _HDR_BAR_CSS = [[
    background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1, stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e);
    border: none;
    border-bottom: 1px solid rgba(70, 75, 110, 150);
]]

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

local function buttonCss(accent, accentHover)
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

local _BTN_PREVIEW_CSS = buttonCss("#7aa2ff", "#9cb8ff")
local _BTN_APPLY_CSS   = buttonCss("#3ecf5e", "#5ce87c")
local _BTN_CANCEL_CSS  = buttonCss("#ff5555", "#ff7777")
local _BTN_AUTO_CSS    = buttonCss("#e0b84d", "#f0cc66")

local _MENU_ITEM_CSS = [[
    QLabel {
        background-color: rgba(24,26,38,220);
        border: none; border-bottom: 1px solid rgba(255,255,255,0.05);
        font-family: "Consolas","Monaco",monospace;
        padding: 0 6px;
    }
    QLabel::hover { background-color: rgba(48,56,88,230); color: white; }
]]

local POLICY_COLORS = {
    deficit = "#ff7777", breakeven = "#c8c8c8", growing = "#7aa2ff", reserve = "#3ecf5e", excluded = "#666666",
}

local instances = {}

local function emptyStateHtml(text)
    return string.format("<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT, text)
end

local function changeHtml(old, new, suffix)
    suffix = suffix or ""
    if old == new then
        return string.format("<span style='%scolor:#777777;'>%s%s</span>", CELL_FONT, old, suffix)
    end
    return string.format("<span style='%scolor:#888888;'>%s%s→</span><span style='%scolor:#e0b84d;'><b>%s%s</b></span>",
        CELL_FONT, old, suffix, CELL_FONT, new, suffix)
end

local function buildCols()
    return {
        {
            key = "commodity", label = "Commodity", sortable = true, scrollbox_pct = 20,
            render_label = function(v, row, cell)
                local color = row.changed and "#e8ebf5" or "#888888"
                cell:echo(string.format("<span style='%scolor:%s;'>%s</span>", CELL_FONT, color, v))
            end,
        },
        {
            key = "net", label = "Net", sortable = true, default_sort = "desc", scrollbox_pct = 10,
            header_tooltip = "Production minus consumption per update",
            render_label = function(v, _row, cell)
                local color = v < 0 and "#ff5555" or (v > 0 and "#3ecf5e" or "#c8c8c8")
                cell:echo(string.format("<span style='%scolor:%s;'>%d</span>", CELL_FONT, color, v))
            end,
        },
        {
            key = "stock", label = "Stock", sortable = true, scrollbox_pct = 11,
            render_label = function(v, _row, cell)
                cell:echo(string.format("<span style='%scolor:#c8c8c8;'>%d</span>", CELL_FONT, v))
            end,
        },
        {
            key = "newMin", label = "Min", sortable = false, scrollbox_pct = 17,
            render_label = function(_v, row, cell) cell:echo(changeHtml(row.oldMin, row.newMin)) end,
        },
        {
            key = "newMax", label = "Max", sortable = false, scrollbox_pct = 17,
            render_label = function(_v, row, cell) cell:echo(changeHtml(row.oldMax, row.newMax)) end,
        },
        {
            key = "newSpread", label = "Spread", sortable = false, scrollbox_pct = 12,
            render_label = function(_v, row, cell) cell:echo(changeHtml(row.oldSpread, row.newSpread, "%")) end,
        },
        {
            key = "policy", label = "Policy", sortable = true, scrollbox_pct = 13,
            header_tooltip = "deficit: net < 0, breakeven: net = 0, growing: surplus below the reserve "
                .. "trigger, reserve: surplus at or above it",
            render_label = function(v, _row, cell)
                cell:echo(string.format("<span style='%scolor:%s;'>%s</span>", CELL_FONT,
                    POLICY_COLORS[v] or "#c8c8c8", v))
            end,
        },
    }
end

-- ── Header state ──────────────────────────────────────────────────────────────

local function statusHtml()
    local state, plan = F2T_STOCKPILE, F2T_STOCKPILE.plan
    local text, color
    if state.applying and plan then
        text, color = string.format("Applying %d/%d to %s…", plan.appliedCount, #plan.actions, plan.planet), "#3ecf5e"
    elseif state.previewing then
        text, color = "Reading exchange…", "#7aa2ff"
    elseif plan then
        local problem = f2tStockpilePlanProblem(plan)
        if plan.applied then
            text, color = string.format("%s: %d applied", plan.planet, plan.appliedCount), "#888888"
        elseif problem and #plan.actions > 0 then
            text, color = string.format("%s: %s", plan.planet, problem), "#e0b84d"
        else
            text, color = string.format("%s: %d change%s planned", plan.planet, #plan.actions,
                #plan.actions == 1 and "" or "s"), "#e8ebf5"
        end
    else
        text, color = "No preview yet", "#888888"
    end
    local auto = state.autoEnabled and string.format(
        " <span style='%scolor:#e0b84d;'>· auto every %s min</span>", CELL_FONT,
        tostring(f2t_settings_get("po", "stockpile_auto_interval"))) or ""
    return string.format("<span style='%scolor:%s;'>%s</span>%s", CELL_FONT, color, text, auto)
end

local function closeMenu(inst)
    if inst.menu then
        inst.menu:hide()
        inst.menu = nil
    end
end

local function togglePreviewMenu(inst, target)
    if inst.menu then
        closeMenu(inst)
        return
    end
    local items = { { label = "This planet", planet = nil } }
    for _, planet in ipairs(f2tStockpileGetList("stockpile_targets")) do
        items[#items + 1] = { label = planet, planet = planet }
    end

    local rowH, menuW = f2tScaled(target, 22), f2tScaled(target, 160)
    local labelPt = f2tTextPt(target, LABEL_PT)
    inst.menuGen = inst.menuGen + 1
    local menu = Geyser.Container:new({
        name = string.format("%s_spm_%d", target._gid, inst.menuGen),
        x = 6, y = inst.barH, width = menuW, height = #items * rowH,
    }, target.content)
    local background = Geyser.Label:new({
        name = string.format("%s_spmbg_%d", target._gid, inst.menuGen),
        x = 0, y = 0, width = "100%", height = "100%",
    }, menu)
    background:setStyleSheet([[
        background-color: rgba(20, 22, 32, 250);
        border: 1px solid rgba(100, 100, 110, 200);
        border-radius: 4px;
    ]])
    for i, item in ipairs(items) do
        local label = Geyser.Label:new({
            name = string.format("%s_spmi_%d_%d", target._gid, inst.menuGen, i),
            x = 1, y = (i - 1) * rowH, width = "100%-2px", height = rowH, fontSize = labelPt,
        }, menu)
        label:setStyleSheet(_MENU_ITEM_CSS)
        label:echo(item.label)
        local planet = item.planet
        label:setClickCallback(function()
            closeMenu(inst)
            f2tStockpilePreview(planet)
        end)
    end
    menu:show()
    menu:raise()
    inst.menu = menu
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    local state, plan = F2T_STOCKPILE, F2T_STOCKPILE.plan

    inst.statusLbl:echo(statusHtml())
    if state.applying then
        inst.applyBtn:setStyleSheet(_BTN_CANCEL_CSS)
        inst.applyBtn:echo("<center>Cancel</center>")
    else
        inst.applyBtn:setStyleSheet(_BTN_APPLY_CSS)
        inst.applyBtn:echo("<center>Apply</center>")
    end
    inst.autoBtn:echo(state.autoEnabled and "<center>Auto: on</center>" or "<center>Auto: off</center>")

    local rows = plan and plan.rows or {}
    f2tTableSetData(inst.tableId, rows)
    if #rows == 0 then
        inst.emptyLbl:echo(emptyStateHtml(
            "Preview a planet you own to plan its stock levels and spreads. Nothing changes until you Apply."
            .. "<br><br>Add planets to the Preview menu with <b>po sp target add &lt;planet&gt;</b>; "
            .. "set the policy in Settings › F2CE-Tools › Planet Owner."))
        inst.emptyLbl:show()
    else
        inst.emptyLbl:hide()
    end
end

local function refreshAll()
    for gid in pairs(instances) do pcall(refreshInstance, gid) end
end

registerAnonymousEventHandler("f2tStockpileChanged", refreshAll)

-- Plan age only changes with time, so status needs a slow tick while open
local _pollTimer = nil
local function ensurePoll()
    if _pollTimer then return end
    local function tick()
        for _, inst in pairs(instances) do pcall(function() inst.statusLbl:echo(statusHtml()) end) end
        _pollTimer = next(instances) and tempTimer(15, tick) or nil
    end
    _pollTimer = tempTimer(15, tick)
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
        refreshInstance(gid)
        return
    end

    local widgetCount = 0
    local function widgetName()
        widgetCount = widgetCount + 1
        return string.format("%s_sp_%d", gid, widgetCount)
    end

    local barH    = f2tScaled(target, H_BAR)
    local cellPt  = f2tUiPt(target, CELL_PT)
    local labelPt = f2tTextPt(target, LABEL_PT)

    local bar = Geyser.Label:new({ name = widgetName(), x = 0, y = 0, width = "100%", height = barH },
        target.content)
    bar:setStyleSheet(_HDR_BAR_CSS)

    -- Buttons left to right, then the status readout in the remaining width.
    local buttonX = 6
    local function headerButton(width)
        local scaledWidth = f2tScaled(target, width)
        local button = Geyser.Label:new({
            name = widgetName(), x = buttonX, y = 4, width = scaledWidth, height = barH - 8, fontSize = labelPt,
        }, bar)
        buttonX = buttonX + scaledWidth + 6
        return button
    end

    local previewBtn = headerButton(80)
    previewBtn:setStyleSheet(_BTN_PREVIEW_CSS)
    previewBtn:echo("<center>Preview ▾</center>")
    previewBtn:setToolTip("Read an exchange and plan its changes")

    local applyBtn = headerButton(64)
    applyBtn:setToolTip("Send the planned changes, one confirmed command at a time")

    local autoBtn = headerButton(72)
    autoBtn:setStyleSheet(_BTN_AUTO_CSS)
    autoBtn:setToolTip("Preview and apply every target planet on a timer (this session only)")

    local statusLbl = Geyser.Label:new({
        name = widgetName(), x = buttonX + 2, y = 0, width = "100%-" .. (buttonX + 8) .. "px", height = "100%",
        fontSize = cellPt,
    }, bar)
    statusLbl:setStyleSheet("background-color: transparent; border: none;")

    local colH = f2tScaled(target, H_COL)
    local colBar = Geyser.Label:new({ name = widgetName(), x = 0, y = barH, width = "100%", height = colH },
        target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scrollTop = barH + colH
    local scroll = Geyser.ScrollBox:new({
        name = widgetName(), x = 0, y = scrollTop, width = "100%", height = "100%-" .. scrollTop .. "px",
    }, target.content)
    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({ name = widgetName(), x = 0, y = 0, width = contentW, height = 1000 },
        scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local emptyLbl = Geyser.Label:new({
        name = widgetName(), x = 0, y = scrollTop, width = "100%", height = "100%-" .. scrollTop .. "px",
        fontSize = cellPt,
    }, target.content)
    emptyLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;"
        .. " qproperty-alignment: 'AlignLeft|AlignTop'; qproperty-wordWrap: true;")

    local tableId = "stockpiles_" .. gid
    local cols = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, f2tScaled(target, ROW_H), scroll, cellPt)
    local colHdrs, xPct = {}, 0
    for _, col in ipairs(cols) do
        local label = Geyser.Label:new({
            name = widgetName(), x = xPct .. "%", y = 0, width = col.scrollbox_pct .. "%", height = "100%",
            fontSize = labelPt,
        }, colBar)
        label:setStyleSheet(_COL_HDR_CSS)
        label:echo(col.label)
        if col.sortable then
            local key = col.key
            label:setClickCallback(function() f2tTableToggleSort(tableId, key) end)
            label:setToolTip(col.header_tooltip or ("Sort by " .. col.label))
        elseif col.header_tooltip then
            label:setToolTip(col.header_tooltip)
        end
        colHdrs[col.key] = label
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    instances[gid] = {
        tableId = tableId, statusLbl = statusLbl, applyBtn = applyBtn, autoBtn = autoBtn, barH = barH,
        contentLabel = contentLabel, contentW = contentW, emptyLbl = emptyLbl, menu = nil, menuGen = 0,
    }

    previewBtn:setClickCallback(function() togglePreviewMenu(instances[gid], target) end)
    applyBtn:setClickCallback(function()
        if F2T_STOCKPILE.applying then f2tStockpileCancel() else f2tStockpileApply() end
    end)
    autoBtn:setClickCallback(function()
        if F2T_STOCKPILE.autoEnabled then f2tStockpileAutoStop() else f2tStockpileAutoStart() end
    end)

    ensurePoll()
    refreshInstance(gid)
end

local function buildStockpilesDef()
    return {
        name        = "Stockpiles",
        description = "Plan and apply owned-exchange stock levels and spreads.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then f2t_debug_log("[stockpiles] apply error: %s", tostring(err)) end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                closeMenu(inst)
                f2tTableDestroy(inst.tableId)
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newContentW = math.max(100, target.content:get_width() - SB_W)
            if newContentW ~= inst.contentW then
                inst.contentW = newContentW
                inst.contentLabel:resize(newContentW, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newContentW)
            end
        end,
        serialize = function(_target) return {} end,
        restore   = function(_target, _data) end,
        onReveal  = function(target) refreshInstance(target._gid) end,
        onTextScale = function(target) f2tRebuildForTextScale(target) end,
    }
end

function f2tRegisterStockpiles()
    if not (Mux and Mux.registerContent) then
        f2t_debug_log("[stockpiles] Muxlet content API unavailable; skipping")
        return
    end
    Mux.registerContent("fed2_stockpiles", buildStockpilesDef())
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterStockpiles)
