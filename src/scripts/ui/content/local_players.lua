-- Renders gmcp.room.info.players (players in the current room) as a stack of
-- styled Geyser.Label rows (rank-colored clickable name + examine button), no
-- MiniConsole involved.
--
-- Only registers content; doesn't manage visibility. To show/hide as players
-- come and go, place "fed2_local_players" in a pane and add a rule: Show
-- when -> GMCP has value -> room.info.players. When the hosting pane is
-- floating, this also asks Muxlet to keep the pane height fitted to the row
-- count live via Mux.requestAutoFit.

local H_HDR = 24   -- header strip height (px)
local ROW_H = 26   -- player row height (px)

local RC_DEFAULT = "#c8c8c8"

local NAME_CSS = [[
    QLabel {
        background: transparent; border: none;
        font-size: 11px; font-weight: bold;
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
        font-size: 11px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(42,48,78,230); }
]]

local headers  = {}   -- target._gid → header Geyser.Label
local rows     = {}   -- target._gid → list of row Geyser.Label widgets
local targets  = {}   -- target._gid → target (pane/tab), for live auto-fit requests
local rendered = {}   -- target._gid → fingerprint of the player list last drawn

local function roomPlayers()
    return gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.players or nil
end

-- gmcp.room.info fires on every room move, but the local player list is
-- usually unchanged (and usually empty). Fingerprint it so the widget rebuild
-- only runs when the list actually differs from what's on screen.
local function playersFingerprint()
    local players = roomPlayers()
    if not players or #players == 0 then return "" end
    local parts = {}
    for i, p in ipairs(players) do
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
end

-- Rebuild the header + row widgets for one pane's content area.  Returns the
-- total pixel height needed to show every row without clipping/scrolling —
-- feeds Mux.requestAutoFit so the hosting floating pane can track it live.
local function render(target)
    local gid = target._gid
    clearRows(gid)

    if headers[gid] then destroyWidget(headers[gid]) end

    local players = roomPlayers()
    local count   = players and #players or 0

    local header = Geyser.Label:new({
        name = gid .. "_lphdr", x = 0, y = 0, width = "100%", height = H_HDR,
    }, target.content)
    header:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])
    header:echo(string.format(
        "<font color='#8c96c3' size='2'>&nbsp;&nbsp;Local Players (%d)</font>", count))
    headers[gid] = header

    if count == 0 then
        local empty = Geyser.Label:new({
            name = gid .. "_lpempty", x = 0, y = H_HDR, width = "100%", height = ROW_H,
        }, target.content)
        empty:setStyleSheet("background: transparent; border: none;")
        empty:echo("<center><font color='#707070' size='2'>No one else is here.</font></center>")
        rows[gid] = { empty }
        return H_HDR + ROW_H
    end

    for i, player in ipairs(players) do
        local name = player.name or "Unknown"
        local rank = player.rank or ""
        local rc   = f2t_rank_color_hex(rank) or RC_DEFAULT
        local hint = rank ~= "" and (rank .. " " .. name) or name

        local rowBg = Geyser.Label:new({
            name = string.format("%s_lprow_%d", gid, i),
            x = 0, y = H_HDR + (i - 1) * ROW_H, width = "100%", height = ROW_H,
        }, target.content)
        rowBg:setStyleSheet(string.format([[
            background-color: rgba(255,255,255,%s);
            border: none;
            border-bottom: 1px solid rgba(255,255,255,0.08);
        ]], (i % 2 == 0) and "0.015" or "0.0"))

        local nameLbl = Geyser.Label:new({
            name = string.format("%s_lpname_%d", gid, i),
            x = 6, y = 2, width = "-32", height = ROW_H - 4,
        }, rowBg)
        nameLbl:setStyleSheet(NAME_CSS)
        nameLbl:echo(string.format("<font color='%s'>%s</font>", rc, name))
        nameLbl:setToolTip(hint)
        nameLbl:setClickCallback(function()
            if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(name) end
        end)

        local eyeLbl = Geyser.Label:new({
            name = string.format("%s_lpeye_%d", gid, i),
            x = "-26", y = 3, width = 20, height = ROW_H - 6,
        }, rowBg)
        eyeLbl:setStyleSheet(EYE_CSS)
        eyeLbl:echo("👁")
        eyeLbl:setToolTip("Examine " .. name)
        eyeLbl:setClickCallback(function() send("ex " .. name, false) end)

        table.insert(rows[gid], rowBg)
    end

    return H_HDR + count * ROW_H
end

local function refreshAll()
    local fp = playersFingerprint()
    local anyRendered = false
    for gid, target in pairs(targets) do
        if rendered[gid] ~= fp then
            local ok, height = pcall(render, target)
            if ok then
                rendered[gid] = fp
                anyRendered = true
                if Mux and Mux.requestAutoFit then Mux.requestAutoFit(target, height) end
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
                        if target._conditionHidden and target.outer then
                            target.outer:hide()
                            if Mux.reassertHidden then Mux.reassertHidden(target.content) end
                        end
                    end)
                end
            end
        end
    end
    -- Freshly recreated widgets land on top of the Qt stacking order, so
    -- re-assert dialogs/floats above content — but only when something rebuilt.
    if anyRendered and Mux and Mux.raiseFloatingPanes then Mux.raiseFloatingPanes() end
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
            target._autoFitHeight = render(target)
            rendered[target._gid] = playersFingerprint()
        end,
        remove = function(target)
            local gid = target._gid
            clearRows(gid)
            if headers[gid] then destroyWidget(headers[gid]); headers[gid] = nil end
            targets[gid]  = nil
            rendered[gid] = nil
        end,
        resize    = function(target) render(target) end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) render(target) end,
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

-- Room changes (and player arrivals/departures) arrive as gmcp.room.info pushes.
registerAnonymousEventHandler("gmcp.room.info", function() refreshAll() end)

if f2t_debug_log then f2t_debug_log("[local_players] module loaded") end
