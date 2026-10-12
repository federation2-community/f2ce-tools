-- Renders gmcp.room.info.players (players in the current room) as a stack of
-- styled Geyser.Label rows (rank-colored clickable name + examine button), no
-- MiniConsole involved.
--
-- When the traffic/show_in setting includes the pane, each row also shows how
-- that player came or went (from traffic.lua's record): arrivals flash green,
-- departures pulse amber and fade before their row folds away, and a drawer
-- at the bottom lists recent traffic.
--
-- Only registers content; doesn't manage visibility. To show/hide as players
-- come and go, place "fed2_local_players" in a pane and add a rule: Show
-- when -> GMCP has value -> room.info.players. When the hosting pane is
-- floating, this also asks Muxlet to keep the pane height fitted to the row
-- count live via Mux.requestAutoFit.

local H_HDR    = 24   -- header strip height (px)
local ROW_H    = 26   -- player row height (px)
local EYE_W    = 20   -- examine button width (px)
local LABEL_PT = 8    -- font size of every label here (pt)

local TRAFFIC_W    = 440   -- pane width with traffic shown (px)
local COMPACT_W    = 150   -- pane width without, when nothing recorded one
local RAIL_W       = 3
local MODE_W       = 22
local NAME_W       = 112
local AGE_W        = 36
local LEFT_DIVIDER_H = 16
local FULL_LOG_W   = 80
local DRAWER_H     = 22
local LOG_ROW_H    = 18
local LOG_SHOWN    = 10

local FLASH_SECONDS  = 1.5
local FRESH_SECONDS  = 20
local LINGER_SECONDS = 15
local PULSE_SECONDS  = 1.1

local RC_DEFAULT = "#c8c8c8"

local NAME_CSS = [[
    QLabel {
        background: transparent; border: none;
        font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding-left: 2px;
    }
    QLabel::hover { color: white; }
]]

local EYE_CSS = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(200,210,230,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 3px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(42,48,78,230); }
]]

local PLAIN_CSS = [[
    QLabel { background: transparent; border: none; font-family: "Consolas","Monaco",monospace; }
]]

local DRAWER_CSS = [[
    QLabel {
        background-color: rgba(255,255,255,0.02);
        border: none; border-top: 1px solid rgba(70, 75, 110, 150);
        font-family: "Consolas","Monaco",monospace;
    }
    QLabel::hover { background-color: rgba(255,255,255,0.06); }
]]

local ARRIVE_RGB = "79,210,122"
local LEAVE_RGB  = "229,163,61"
local CHIP_DIM   = "#8a90a8"
local CHIP_FAINT = "#5c6180"

local headers  = {}   -- target._gid → header Geyser.Label
local rows     = {}   -- target._gid → list of row Geyser.Label widgets
local animated = {}   -- target._gid → list of { movement, widgets } redrawn by the ticker
local targets  = {}   -- target._gid → target (pane/tab), for live auto-fit requests
local rendered = {}   -- target._gid → fingerprint of the player list last drawn
local drawerOpen = {} -- target._gid → true while the recent-traffic drawer is open

local tickTimer = nil

local function roomPlayers()
    return gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.players or nil
end

local function trafficShown()
    return f2tTrafficInPlayers and f2tTrafficInPlayers() or false
end

local function ageText(seconds)
    if seconds < 5 then return "now" end
    if seconds < 60 then return math.floor(seconds) .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

local function hexToRgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- The rows to draw with traffic shown: everyone GMCP lists, newest arrivals
-- first and people already here when you arrived after them, then anyone whose
-- departure is still fading, newest first.
local function trafficRows()
    local now, list, listed = getEpoch(), {}, {}
    local movements = F2T_TRAFFIC and F2T_TRAFFIC.movements or {}
    for _, player in ipairs(roomPlayers() or {}) do
        local name = player.name or "Unknown"
        listed[name:lower()] = true
        local movement = movements[name:lower()]
        local state = "settled"
        if movement then state = movement.sign == "+" and "arriving" or "leaving" end
        list[#list + 1] = { name = name, rank = player.rank or "", movement = movement, state = state }
    end
    for key, movement in pairs(movements) do
        if not listed[key] and movement.sign == "-" and now - movement.at < LINGER_SECONDS then
            list[#list + 1] = { name = movement.name, rank = movement.rank or "", movement = movement,
                                state = "leaving" }
        end
    end
    table.sort(list, function(a, b)
        local goneA, goneB = a.state == "leaving", b.state == "leaving"
        if goneA ~= goneB then return goneB end
        local orderA = a.movement and (goneA and a.movement.at or a.movement.order) or 0
        local orderB = b.movement and (goneB and b.movement.at or b.movement.order) or 0
        if orderA ~= orderB then return orderA > orderB end
        return a.name < b.name
    end)
    return list
end

-- gmcp.room.info fires on every room move, but the local player list is
-- usually unchanged (and usually empty). Fingerprint it so the widget rebuild
-- only runs when the list actually differs from what's on screen.
local function playersFingerprint(gid)
    local parts = {}
    if trafficShown() then
        parts[1] = "traffic"
        for i, row in ipairs(trafficRows()) do
            parts[i + 1] = row.name .. "\1" .. row.rank .. "\1" .. row.state .. "\1"
                .. tostring(row.movement and row.movement.at)
        end
        parts[#parts + 1] = tostring(#F2T_TRAFFIC.log) .. "\1" .. tostring(F2T_TRAFFIC.unseen > 0)
        if drawerOpen[gid] then parts[#parts + 1] = "open" .. tostring(F2T_TRAFFIC.version) end
        return table.concat(parts, "\2")
    end
    for i, p in ipairs(roomPlayers() or {}) do
        parts[i] = (p.name or "") .. "\1" .. (p.rank or "")
    end
    return table.concat(parts, "\2")
end

local function destroyWidget(w)
    if not w then return end
    if w.delete then w:delete() else w:hide() end
end

local function clearRows(gid)
    if rows[gid] then
        for _, w in ipairs(rows[gid]) do destroyWidget(w) end
    end
    rows[gid] = {}
    animated[gid] = {}
end

local function buildHeader(target, count, hdrH, labelPt)
    local header = Geyser.Label:new({
        name = target._gid .. "_lphdr", x = 0, y = 0, width = "100%", height = hdrH, fontSize = labelPt,
    }, target.content)
    header:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])
    header:echo(string.format(
        "<font color='#8c96c3'>&nbsp;&nbsp;Local Players (%d)</font>", count))
    headers[target._gid] = header
end

local function buildRowBackground(target, i, y, rowH)
    local rowBg = Geyser.Label:new({
        name = string.format("%s_lprow_%d", target._gid, i),
        x = 0, y = y, width = "100%", height = rowH,
    }, target.content)
    rowBg:setStyleSheet(string.format([[
        background-color: rgba(255,255,255,%s);
        border: none;
        border-bottom: 1px solid rgba(255,255,255,0.08);
    ]], (i % 2 == 0) and "0.015" or "0.0"))
    return rowBg
end

local function buildEye(target, i, rowBg, name, rowH, eyeW, labelPt)
    local eyeLbl = Geyser.Label:new({
        name = string.format("%s_lpeye_%d", target._gid, i),
        x = "-" .. (eyeW + 6), y = 3, width = eyeW, height = rowH - 6, fontSize = labelPt,
    }, rowBg)
    eyeLbl:setStyleSheet(EYE_CSS)
    eyeLbl:echo("👁")
    eyeLbl:setToolTip("Examine " .. name)
    eyeLbl:setClickCallback(function() send("ex " .. name, false) end)
end

local function bindNameClick(nameLbl, name, rank)
    nameLbl:setToolTip(rank ~= "" and (rank .. " " .. name) or name)
    nameLbl:setClickCallback(function()
        if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(name) end
    end)
end

local function buildEmpty(target, hdrH, rowH, labelPt)
    local empty = Geyser.Label:new({
        name = target._gid .. "_lpempty", x = 0, y = hdrH, width = "100%", height = rowH, fontSize = labelPt,
    }, target.content)
    empty:setStyleSheet("background: transparent; border: none;")
    empty:echo("<center><font color='#707070'>No one else is here.</font></center>")
    table.insert(rows[target._gid], empty)
end

local function renderCompact(target, hdrH, rowH, eyeW, labelPt)
    local players = roomPlayers()
    local count   = players and #players or 0
    buildHeader(target, count, hdrH, labelPt)

    if count == 0 then
        buildEmpty(target, hdrH, rowH, labelPt)
        return hdrH + rowH
    end

    for i, player in ipairs(players) do
        local name = player.name or "Unknown"
        local rank = player.rank or ""
        local rc   = f2t_rank_color_hex(rank) or RC_DEFAULT

        local rowBg = buildRowBackground(target, i, hdrH + (i - 1) * rowH, rowH)

        local nameLbl = Geyser.Label:new({
            name = string.format("%s_lpname_%d", target._gid, i),
            x = 6, y = 2, width = "-" .. (eyeW + 12), height = rowH - 4, fontSize = labelPt,
        }, rowBg)
        nameLbl:setStyleSheet(NAME_CSS)
        nameLbl:echo(string.format("<font color='%s'>%s</font>", rc, name))
        bindNameClick(nameLbl, name, rank)

        buildEye(target, i, rowBg, name, rowH, eyeW, labelPt)
        table.insert(rows[target._gid], rowBg)
    end

    return hdrH + count * rowH
end

-- Repaints one traffic row for the current moment: the arrival flash, the
-- steady green rail of someone still here, the departure pulse and fade, and
-- the age column.
local function paintRow(entry, now)
    local widgets, movement, state = entry.widgets, entry.movement, entry.state
    local age = movement and (now - movement.at) or nil
    local rowCss, chipColor, nameAlpha = "", CHIP_FAINT, 1
    local railCss = string.format("background-color: rgba(%s,0.45);", ARRIVE_RGB)

    if state == "arriving" and age < FRESH_SECONDS then
        local flash = math.max(0, 1 - age / FLASH_SECONDS) * 0.42
        rowCss    = string.format("background-color: rgba(%s,%.3f);", ARRIVE_RGB, flash)
        railCss   = string.format("background-color: rgb(%s);", ARRIVE_RGB)
        chipColor = "rgb(" .. ARRIVE_RGB .. ")"
    elseif state == "arriving" then
        chipColor = CHIP_DIM
    elseif state == "leaving" then
        local pulse = 0.15 + 0.85 * (0.5 + 0.5 * math.cos(2 * math.pi * age / PULSE_SECONDS))
        rowCss    = string.format("background-color: qlineargradient(x1:0, y1:0, x2:1, y2:0, "
            .. "stop:0 rgba(%s,0.30), stop:0.55 rgba(0,0,0,0));", LEAVE_RGB)
        railCss   = string.format("background-color: rgba(%s,%.3f);", LEAVE_RGB, pulse)
        chipColor = "rgb(" .. LEAVE_RGB .. ")"
        nameAlpha = math.max(0.28, 1 - 0.72 * math.min(1, age / LINGER_SECONDS))
    end

    local r, g, b = hexToRgb(entry.nameColor)
    local styles = {
        row  = rowCss .. " border: none; border-bottom: 1px solid rgba(255,255,255,0.05);",
        rail = railCss .. " border: none;",
        name = NAME_CSS .. string.format(" QLabel { color: rgba(%d,%d,%d,%.2f); }", r, g, b, nameAlpha),
        chip = PLAIN_CSS .. string.format(" QLabel { color: %s; }", chipColor),
    }
    for key, css in pairs(styles) do
        if entry.painted[key] ~= css then
            entry.painted[key] = css
            widgets[key]:setStyleSheet(css)
        end
    end

    local ageLabel = state == "settled" and "" or ageText(age)
    if entry.painted.age ~= ageLabel then
        entry.painted.age = ageLabel
        widgets.age:echo(string.format("<p align='right'><font color='%s'>%s</font></p>", CHIP_FAINT, ageLabel))
    end
end

local LOG_AGE_COLUMN  = 4
local LOG_NAME_COLUMN = 16

-- Pads with non-breaking spaces so the recent-traffic columns line up.
local function padded(text, width)
    return text .. string.rep("&nbsp;", math.max(1, width - #text))
end

local function logLineHtml(entry, now)
    if entry.roomBreak then
        return string.format("<center><i><font color='%s'>you moved to %s</font></i></center>", CHIP_FAINT,
            entry.text)
    end
    local signColor = entry.sign == "+" and ("rgb(" .. ARRIVE_RGB .. ")") or ("rgb(" .. LEAVE_RGB .. ")")
    local nameColor = f2t_rank_color_hex(entry.rank) or RC_DEFAULT
    return string.format(
        "&nbsp;<font color='%s'>%s</font><b><font color='%s'>%s</font></b>&nbsp;%s&nbsp;"
            .. "<b><font color='%s'>%s</font></b><font color='%s'>%s</font>",
        CHIP_FAINT, padded(ageText(now - entry.at), LOG_AGE_COLUMN), signColor, entry.sign,
        entry.icon, nameColor, padded(entry.name, LOG_NAME_COLUMN), CHIP_DIM, entry.text)
end

local function buildLeftDivider(target, y, labelPt)
    local height = f2tScaled(target, LEFT_DIVIDER_H)
    local divider = Geyser.Label:new({
        name = target._gid .. "_lpleft", x = 0, y = y, width = "100%", height = height, fontSize = labelPt,
    }, target.content)
    divider:setStyleSheet(PLAIN_CSS .. " QLabel { background-color: rgba(0,0,0,0.35);"
        .. " border-top: 1px solid rgba(" .. LEAVE_RGB .. ",0.35); }")
    divider:echo(string.format("&nbsp;<font color='rgb(%s)'>Just left</font>", LEAVE_RGB))
    table.insert(rows[target._gid], divider)
    return height
end

local function renderTraffic(target, hdrH, rowH, eyeW, labelPt)
    local gid  = target._gid
    local list = trafficRows()
    local now  = getEpoch()
    local here = 0
    for _, row in ipairs(list) do if row.state ~= "leaving" then here = here + 1 end end
    buildHeader(target, here, hdrH, labelPt)

    local y = hdrH
    if #list == 0 then
        buildEmpty(target, hdrH, rowH, labelPt)
        y = y + rowH
    end

    local railW, modeW, nameW, ageW = f2tScaled(target, RAIL_W), f2tScaled(target, MODE_W),
        f2tScaled(target, NAME_W), f2tScaled(target, AGE_W)
    local dividerShown = false
    for i, row in ipairs(list) do
        if row.state == "leaving" and not dividerShown then
            dividerShown = true
            y = y + buildLeftDivider(target, y, labelPt)
        end
        local rowBg = buildRowBackground(target, i, y, rowH)
        local function child(suffix, x, width)
            local label = Geyser.Label:new({
                name = string.format("%s_lp%s_%d", gid, suffix, i),
                x = x, y = 0, width = width, height = rowH, fontSize = labelPt,
            }, rowBg)
            label:setStyleSheet(PLAIN_CSS)
            return label
        end

        local rail = child("rail", 0, railW)
        local mode = child("mode", railW + 2, modeW)
        mode:echo("<center>" .. (row.movement and row.movement.icon or "·") .. "</center>")

        local nameLbl = child("name", railW + modeW + 4, nameW)
        nameLbl:echo(row.state == "leaving" and ("<s>" .. row.name .. "</s>") or row.name, "nocolor")
        bindNameClick(nameLbl, row.name, row.rank)

        local chipX = railW + modeW + nameW + 8
        local chip = child("chip", chipX, "-" .. (ageW + eyeW + 16))
        chip:echo(row.movement and row.movement.text or "here when you arrived", "nocolor")
        if row.movement and row.movement.ship then chip:setToolTip("Ship: " .. row.movement.ship) end

        local age = child("age", "-" .. (ageW + eyeW + 12), ageW)
        buildEye(target, i, rowBg, row.name, rowH, eyeW, labelPt)

        local entry = {
            movement  = row.movement,
            state     = row.state,
            nameColor = f2t_rank_color_hex(row.rank) or RC_DEFAULT,
            widgets   = { row = rowBg, rail = rail, name = nameLbl, chip = chip, age = age },
            painted   = {},
        }
        paintRow(entry, now)
        table.insert(animated[gid], entry)
        table.insert(rows[gid], rowBg)
        y = y + rowH
    end

    local drawerH = f2tScaled(target, DRAWER_H)
    local log = F2T_TRAFFIC.log
    local entries = 0
    for _, entry in ipairs(log) do if not entry.roomBreak then entries = entries + 1 end end
    local drawer = Geyser.Label:new({
        name = gid .. "_lpdrawer", x = 0, y = y, width = "100%", height = drawerH, fontSize = labelPt,
    }, target.content)
    drawer:setStyleSheet(DRAWER_CSS)
    local newDot = (F2T_TRAFFIC.unseen > 0 and not drawerOpen[gid]) and "&nbsp;<font color='#8c96c3'>●</font>" or ""
    drawer:echo(string.format(
        "&nbsp;<font color='#8c96c3'>%s</font>&nbsp;<font color='%s'>Recent traffic (%d)</font>%s",
        drawerOpen[gid] and "▾" or "▸", CHIP_DIM, entries, newDot))
    drawer:setToolTip(drawerOpen[gid] and "Hide recent traffic" or "Show recent traffic")
    drawer:setClickCallback(function()
        drawerOpen[gid] = not drawerOpen[gid] or nil
        if drawerOpen[gid] then F2T_TRAFFIC.unseen = 0 end
        f2tLocalPlayersRefresh()
    end)
    table.insert(rows[gid], drawer)

    local fullLogW = f2tScaled(target, FULL_LOG_W)
    local fullLog = Geyser.Label:new({
        name = gid .. "_lpfulllog", x = "-" .. (fullLogW + 4), y = 0, width = fullLogW, height = drawerH,
        fontSize = labelPt,
    }, drawer)
    fullLog:setStyleSheet(PLAIN_CSS .. " QLabel::hover { background-color: rgba(255,255,255,0.08); }")
    fullLog:echo(string.format("<p align='right'><font color='#8c96c3'>Full log ⤢</font></p>"))
    fullLog:setToolTip("Open every arrival and departure this session in its own window (or type traffic)")
    fullLog:setClickCallback(function()
        if f2tShowTrafficLog then f2tShowTrafficLog() end
    end)
    y = y + drawerH

    if drawerOpen[gid] then
        local logRowH = f2tScaled(target, LOG_ROW_H)
        local shown = math.min(#log, LOG_SHOWN)
        if shown == 0 then
            local none = Geyser.Label:new({
                name = gid .. "_lplog_none", x = 0, y = y, width = "100%", height = logRowH, fontSize = labelPt,
            }, target.content)
            none:setStyleSheet(PLAIN_CSS)
            none:echo(string.format("<center><font color='%s'>Nobody has come or gone yet.</font></center>",
                CHIP_FAINT))
            table.insert(rows[gid], none)
            y = y + logRowH
        end
        for i = 1, shown do
            local line = Geyser.Label:new({
                name = string.format("%s_lplog_%d", gid, i), x = 0, y = y, width = "100%", height = logRowH,
                fontSize = labelPt,
            }, target.content)
            line:setStyleSheet(PLAIN_CSS .. " QLabel { background-color: rgba(0,0,0,0.25); }")
            line:echo(logLineHtml(log[i], now))
            table.insert(rows[gid], line)
            y = y + logRowH
        end
    end

    return y
end

-- Rebuild the header + row widgets for one pane's content area.  Returns the
-- total pixel height needed to show every row without clipping/scrolling, and
-- the width the pane should take (nil to leave it alone) -- both feed
-- Mux.requestAutoFit so the hosting floating pane can track them live.
local function render(target)
    local gid = target._gid
    clearRows(gid)
    if headers[gid] then destroyWidget(headers[gid]) end

    local hdrH    = f2tScaled(target, H_HDR)
    local rowH    = f2tScaled(target, ROW_H)
    local eyeW    = f2tScaled(target, EYE_W)
    local labelPt = f2tTextPt(target, LABEL_PT)

    local trafficWidth = f2tScaled(target, TRAFFIC_W)
    local isWide = target.floatW and target.floatW >= trafficWidth
    if trafficShown() then
        if not isWide then target._f2tCompactWidth = target.floatW end
        return renderTraffic(target, hdrH, rowH, eyeW, labelPt), trafficWidth
    end
    local width = isWide and (target._f2tCompactWidth or COMPACT_W) or nil
    return renderCompact(target, hdrH, rowH, eyeW, labelPt), width
end

-- The pane's own rule hides it as soon as GMCP lists nobody, which would cut a
-- departure's fade short. Only overridden when that rule is all that hides it.
local function hiddenOnlyForEmptyRoom(target)
    if not (target.rules and #target.rules > 0 and Mux and Mux._resolveCond) then return false end
    for _, rule in ipairs(target.rules) do
        if rule.enabled ~= false then
            local cond = Mux._resolveCond(rule.cond)
            local path = cond and cond.path and tostring(cond.path) or ""
            if not (cond and cond.type == "gmcp_exists" and path:find("room%.info%.players$")) then
                return false
            end
        end
    end
    return true
end

local function holdOpen(target)
    local players = roomPlayers()
    if players and #players > 0 then
        target._f2tHeld = nil
        return
    end
    local need = false
    if trafficShown() then
        need = drawerOpen[target._gid] or false
        for _, entry in ipairs(animated[target._gid] or {}) do
            if entry.state == "leaving" then need = true end
        end
    end
    if need and target._conditionHidden and target._conditionShow and hiddenOnlyForEmptyRoom(target) then
        target._f2tHeld = true
        target:_conditionShow()
    elseif not need and target._f2tHeld then
        target._f2tHeld = nil
        if target._conditionHide then target:_conditionHide() end
    end
end

local function refreshAll()
    local anyRendered = false
    for gid, target in pairs(targets) do
        local fp = playersFingerprint(gid)
        if rendered[gid] ~= fp then
            local ok, height, width = pcall(render, target)
            if ok then
                rendered[gid] = fp
                anyRendered = true
                if Mux and Mux.requestAutoFit then Mux.requestAutoFit(target, height, width) end
                -- render() just rebuilt the header/row widgets. If this pane/tab
                -- is condition-hidden (the documented use case in this module's
                -- header comment), those freshly created widgets would otherwise
                -- leak visible -- Geyser shows new widgets unconditionally,
                -- regardless of the hidden ancestor. See Mux.reassertHidden.
                if Mux and Mux.reassertHidden then Mux.reassertHidden(target.content) end
                -- The reassert above is a Geyser-bookkeeping-correct hide, but a
                -- rebuild that lands while this pane is condition-hidden has been
                -- observed to leave the new widgets visually painted a tick behind
                -- the logical hide (native Qt repaint lag, not a logic bug -- see
                -- the matching fix in Muxlet's Mux._applyContent). Re-hide once
                -- more a tick later to clear it.
                if target._conditionHidden then
                    tempTimer(0, function()
                        if target._conditionHidden and target.outer and not target._f2tHeld then
                            target.outer:hide()
                            if Mux.reassertHidden then Mux.reassertHidden(target.content) end
                        end
                    end)
                end
            end
        end
        -- after the pane's own rule has reacted to the same GMCP update
        tempTimer(0, function() if targets[gid] then holdOpen(target) end end)
    end
    -- Freshly recreated widgets land on top of the Qt stacking order, so
    -- re-assert dialogs/floats above content — but only when something rebuilt.
    if anyRendered and Mux and Mux.raiseFloatingPanes then Mux.raiseFloatingPanes() end
end

f2tLocalPlayersRefresh = refreshAll

-- Drives the flash, pulse and fade, and ages. Runs fast only while something is
-- animating; a departure that has finished fading triggers the rebuild that
-- folds its row away.
local function tick()
    tickTimer = nil
    if not trafficShown() or next(targets) == nil then return end
    local now, fast, any, expired = getEpoch(), false, false, false
    for _, entries in pairs(animated) do
        for _, entry in ipairs(entries) do
            any = true
            local age = entry.movement and (now - entry.movement.at) or 0
            if entry.state == "leaving" then
                if age >= LINGER_SECONDS then expired = true else fast = true end
            elseif entry.state == "arriving" and age < FLASH_SECONDS then
                fast = true
            end
            pcall(paintRow, entry, now)
        end
    end
    if expired then refreshAll() end
    if any or expired then tickTimer = tempTimer(fast and 0.08 or 1, tick) end
end

local function ensureTicking()
    if tickTimer then return end
    tickTimer = tempTimer(0.08, tick)
end

local function buildLocalPlayersDef()
    return {
        name        = "Local Players",
        description = "Players in the current room from gmcp.room.info.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            if target.contentBg then
                target.contentBg:echo("")
                target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
                target.contentBg:hide()
            end
            targets[target._gid] = target
            local height, width = render(target)
            target._autoFitHeight = height
            target._autoFitWidth  = width
            rendered[target._gid] = playersFingerprint(target._gid)
            if trafficShown() then ensureTicking() end
        end,
        remove = function(target)
            local gid = target._gid
            clearRows(gid)
            if headers[gid] then destroyWidget(headers[gid]); headers[gid] = nil end
            targets[gid]    = nil
            rendered[gid]   = nil
            animated[gid]   = nil
            drawerOpen[gid] = nil
        end,
        resize    = function(target) render(target) end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) render(target) end,
        onTextScale = function(target)
            local height, width = render(target)
            if Mux and Mux.requestAutoFit then Mux.requestAutoFit(target, height, width) end
            if Mux and Mux.reassertHidden then Mux.reassertHidden(target.content) end
        end,
    }
end

function f2tRegisterLocalPlayers()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[local_players] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_local_players", buildLocalPlayersDef())
    if f2t_debug_log then f2t_debug_log("[local_players] registered fed2_local_players content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterLocalPlayers)

local function refreshAndTick()
    refreshAll()
    if trafficShown() then ensureTicking() end
end

-- Room changes (and player arrivals/departures) arrive as gmcp.room.info pushes.
registerAnonymousEventHandler("gmcp.room.info", function()
    if f2tTrafficSyncRoom then f2tTrafficSyncRoom() end
    refreshAndTick()
end)
registerAnonymousEventHandler("f2tTrafficChanged", refreshAndTick)

-- Re-hooked on every muxletReady because a Muxlet reload clears its onChange listeners.
local function hookTrafficSetting()
    if not (Mux and Mux.settings and Mux.settings.onChange) then return end
    Mux.settings.onChange("traffic", "show_in", refreshAndTick)
end

hookTrafficSetting()
registerAnonymousEventHandler("muxletReady", hookTrafficSetting)

if f2t_debug_log then f2t_debug_log("[local_players] module loaded") end
