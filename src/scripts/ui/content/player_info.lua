-- Six live stat labels (Rank, Fuel, Stamina, Groats, Slithies, Hold) plus a
-- Buy Fuel button, colored from gmcp.char.vitals and gmcp.char.ship.
--
-- Registered as "fed2_player_info" content so it can be applied to any pane
-- or tab. The stat labels live in a Geyser.HBox spanning the content area, so
-- the row scales with placement automatically; Buy Fuel is anchored a fixed
-- width from the right edge.
--
-- Every widget lives inside target.content (the disposable slot), so
-- teardown is automatic on content change/removal. Live updates use
-- session-level GMCP handlers that iterate existing instances, so there's
-- nothing per-instance to unregister.

local H_LABEL_CSS = [[
    background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e);
    color: #c8c8d0;
    border: none;
    border-right: 1px solid #3a3a4a;
    padding: 4px 8px;
    font-family: "Consolas","Monaco",monospace;
]]

local BUTTON_CSS = [[
    QLabel{
        background-color: rgba(40, 40, 45, 200);
        border: 1px solid rgba(100, 100, 110, 180);
        border-radius: 3px;
        color: rgba(200, 200, 210, 255);
        font-size: 11px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover{
        background-color: rgba(60, 60, 70, 220);
        border-color: rgba(120, 180, 255, 200);
        color: white;
    }
]]


-- Fuel cell is a fixed width sized to its readout + Buy Fuel button (see layout
-- note in buildContent). The readout region must fit "Fuel: 999/999".
local FUEL_READOUT_W = 104
local FUEL_BTN_X     = 106
local FUEL_BTN_W     = 84
local FUEL_CELL_W    = FUEL_BTN_X + FUEL_BTN_W + 2   -- = 192

-- Groats target per rank (archive UI.magic_cash_numbers): the "promotion cash"
-- threshold shown as Groats: cur/target.  Ranks past Financier have no fixed
-- target, so only the current cash is shown.
local MAGIC_CASH = {
    Commander     = 250000,
    Captain       = 400000,
    Adventurer    = 600000,
    Adventuress   = 600000,
    Merchant      = 7500000,
    Trader        = 12500000,
    Industrialist = 17500000,
    Manufacturer  = 22500000,
    Financier     = 27500000,
}

-- Per-placement state, keyed by target._gid
local instances = {}

-- Format long numbers with thousands separators, or "N.N m" above a million.
-- (Ported from archive ui_convert_value.)
local function convertValue(amount)
    if amount == nil then return nil end
    local formatted = tostring(amount)
    if tonumber(formatted) == nil then return nil end
    if tonumber(formatted) <= 1000000 then
        while true do
            local k
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end
    else
        formatted = math.floor(tonumber(formatted) / 100000) / 10 .. " m"
    end
    return formatted
end

-- Colour a value on a red→green gradient by its percentage of max.
-- (Ported from archive ui_color_percent.)
local COLOR_GRAD = {
    [0]="#800000",[1]="#801a00",[2]="#803400",[3]="#804e00",[4]="#806800",
    [5]="#808000",[6]="#668000",[7]="#4c8000",[8]="#328000",[9]="#008000",[10]="#FFFFFF",
}
local function colorPercent(cur, max)
    local c, m = tonumber(cur), tonumber(max)
    if not c or not m or m == 0 then return "#FFFFFF" end
    local pct = math.floor((c / m) * 10)
    if pct < 0 then pct = 0 elseif pct > 10 then pct = 10 end
    return COLOR_GRAD[pct]
end

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst or not inst.labels then return end
    local L = inst.labels

    local vitals = (gmcp.char and gmcp.char.vitals) or {}
    local ship   = (gmcp.char and gmcp.char.ship)   or {}

    local rank     = vitals.rank or "-"
    local hold_cur = (ship.hold and ship.hold.cur) or "-"
    local hold_max = (ship.hold and ship.hold.max) or "-"
    local fuel_cur = (ship.fuel and ship.fuel.cur) or "-"
    local fuel_max = (ship.fuel and ship.fuel.max) or "-"
    local stam_cur = (vitals.stamina and vitals.stamina.cur) or "-"
    local stam_max = (vitals.stamina and vitals.stamina.max) or "-"
    local cash     = convertValue(vitals.cash) or "-"
    local slith    = vitals.slithies or "-"
    local groats_max = convertValue(MAGIC_CASH[rank]) or "-"

    L[1]:echo("Rank: <b>" .. rank .. "</b>")

    if tonumber(fuel_cur) then
        L[2]:echo(string.format("Fuel: <b><font color=%s>%s</font></b>/%s",
            colorPercent(fuel_cur, fuel_max), fuel_cur, fuel_max))
    else
        L[2]:echo("Fuel: -")
    end

    if tonumber(stam_cur) then
        L[3]:echo(string.format("Stamina: <b><font color=%s>%s</font></b>/%s",
            colorPercent(stam_cur, stam_max), stam_cur, stam_max))
    else
        L[3]:echo("Stamina: -")
    end

    if groats_max == "-" then
        L[4]:echo("Groats: <b>" .. cash .. "</b>")
    else
        L[4]:echo("Groats: <b>" .. cash .. "</b>/" .. groats_max)
    end

    L[5]:echo("Slithies: <b>" .. tostring(slith) .. "</b>")

    if tonumber(hold_cur) then
        local has_cargo = ship.cargo and next(ship.cargo) ~= nil
        local disp = string.format("Hold: <b><font color=%s>%s</font></b>/%s",
            colorPercent(hold_cur, hold_max), hold_cur, hold_max)
        if has_cargo then disp = disp .. " 📦" end
        L[6]:echo(disp)
    else
        L[6]:echo("Hold: -")
    end
end

local function refreshAll()
    for gid in pairs(instances) do pcall(refreshInstance, gid) end
end

-- Position the six cells: fuel (cell 2) fixed; the other five split the rest, the
-- last cell taking the rounding remainder so there is never a gap on the right.
local function layoutCells(inst)
    if not inst or not inst.cells or not inst.host then return end
    local W = inst.host.get_width and inst.host:get_width() or 0
    if not W or W <= 0 then return end
    local flexW = math.max(40, math.floor((W - FUEL_CELL_W) / 5))
    local x = 0
    for i = 1, 6 do
        local w
        if i == 2 then        w = FUEL_CELL_W
        elseif i == 6 then    w = math.max(40, W - x)   -- fill remainder
        else                  w = flexW end
        local cell = inst.cells[i]
        if cell then pcall(function() cell:move(x, 0); cell:resize(w, "100%") end) end
        x = x + w
    end
end

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    -- Re-show if already built (apply called without a prior remove).
    if instances[gid] then
        refreshInstance(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_pinfo_%d", gid, wc)
    end

    -- Transparent text sub-label CSS (lets the cell's gradient show through).
    local CELL_TEXT_CSS =
        "background: transparent; border: none; color: #c8c8d0;" ..
        ' padding: 4px 6px; font-family: "Consolas","Monaco",monospace;'

    -- Six cells laid out manually (NOT an HBox): the fuel cell is a FIXED width
    -- sized to its readout + button, and the other five split the remaining width
    -- evenly.  An HBox would size every cell proportionally, which forces the fuel
    -- cell to either clip the fixed-size button or leave a growing empty gap to its
    -- right as the bar widens.  layoutCells() (re)positions them on build/resize.
    local cells = {}
    for i = 1, 6 do
        local cell = Geyser.Label:new({ name = wid(), x = 0, y = 0, width = 10, height = "100%" }, target.content)
        cell:setStyleSheet(H_LABEL_CSS)
        cells[i] = cell
    end

    local labels = {}
    -- Plain stat cells (1,3,4,5,6): the cell itself shows the text.
    for _, i in ipairs({ 1, 3, 4, 5, 6 }) do
        pcall(function() cells[i]:setFontSize(11) end)
        labels[i] = cells[i]
    end

    -- Fuel cell (2): inner readout (left) + small Buy Fuel button right after it.
    local fuelText = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = FUEL_READOUT_W, height = "100%",
    }, cells[2])
    fuelText:setStyleSheet(CELL_TEXT_CSS)
    pcall(function() fuelText:setFontSize(11) end)
    labels[2] = fuelText

    local buyBtn = Geyser.Label:new({
        name = wid(), x = FUEL_BTN_X, y = "20%", width = FUEL_BTN_W, height = "60%",
    }, cells[2])
    buyBtn:setStyleSheet(BUTTON_CSS)
    buyBtn:echo("<center>⛽&nbsp;Buy&nbsp;Fuel</center>")
    buyBtn:setToolTip("Buy fuel at a shuttlepad")
    buyBtn:setClickCallback(function() send("buy fuel") end)

    labels[6]:setToolTip("Cargo hold")   -- legacy inline cargo panel is now fed2_cargo

    instances[gid] = { labels = labels, buyBtn = buyBtn, cells = cells, host = target.content }
    layoutCells(instances[gid])
    refreshInstance(gid)
end

local function buildPlayerInfoDef()
    return {
        name        = "Player Info",
        description = "Live rank / fuel / stamina / groats / slithies / hold strip with Buy Fuel.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok and f2t_debug_log then
                f2t_debug_log("[player_info] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            -- Widgets are torn down with the slot; just drop per-instance state.
            instances[target._gid] = nil
        end,
        resize = function(target)
            -- Re-flow the fixed/flex cell layout, then re-echo (text may depend on width).
            local inst = instances[target._gid]
            if inst then layoutCells(inst) end
            refreshInstance(target._gid)
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) refreshInstance(target._gid) end,
    }
end

function f2tRegisterPlayerInfo()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[player_info] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_player_info", buildPlayerInfoDef())
    if f2t_debug_log then f2t_debug_log("[player_info] registered fed2_player_info content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterPlayerInfo)

-- Session-level live updates: refresh every open header on the relevant GMCP
-- pushes.  Iterates only existing instances, so it is a no-op when no header is
-- placed and needs no per-instance teardown.
registerAnonymousEventHandler("gmcp.char.vitals", refreshAll)
registerAnonymousEventHandler("gmcp.char.ship",   refreshAll)

if f2t_debug_log then f2t_debug_log("[player_info] module loaded") end