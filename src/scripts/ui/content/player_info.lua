-- Live stat labels (Rank, Fuel, Stamina, Groats, Slithies, Hold) plus a Buy Fuel
-- button, colored from gmcp.char.vitals and gmcp.char.ship.
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
--
-- FITTING THE STRIP. Six readouts in one thin row is tight, and the web client
-- gives the pane less room than desktop does. Four things keep it legible, in
-- order of how much they buy:
--   1. Font size goes through setFontSize (see f2t_ui_fs) -- a font-size in the
--      stylesheet does nothing to a label you :echo() to.
--   2. Web drops the Slithies cell entirely: it is the slowest-changing readout,
--      and `score` still reports it.
--   3. Cells are weighted by how long their text actually gets, not split evenly.
--   4. Stamina shortens to STM, and padding tightens, on web.
--
-- Everything downstream is driven off the CELLS table, so a cell that is absent
-- on one platform costs nothing but its entry.

local WEB      = f2t_is_web()
local CELL_PAD = WEB and "3px 5px" or "4px 8px"

local H_LABEL_CSS = string.format([[
    background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e);
    color: #c8c8d0;
    border: none;
    border-right: 1px solid #3a3a4a;
    padding: %s;
    font-family: "Consolas","Monaco",monospace;
]], CELL_PAD)

local BUTTON_CSS = [[
    QLabel{
        background-color: rgba(40, 40, 45, 200);
        border: 1px solid rgba(100, 100, 110, 180);
        border-radius: 3px;
        color: rgba(200, 200, 210, 255);
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover{
        background-color: rgba(60, 60, 70, 220);
        border-color: rgba(120, 180, 255, 200);
        color: white;
    }
]]

-- Point sizes, applied with setFontSize. 11 on desktop is exactly what the strip
-- rendered before; the readouts scale down on web via F2T_UI_FONT_SCALE.
local CELL_PT = f2t_ui_fs(11)
-- The button does NOT scale. It is the only thing here you click, it sits in a
-- fixed-width cell so shrinking it buys the other cells nothing, and 7pt (what
-- the scale gives) is too small to read comfortably.
local BTN_PT  = 8


-- Fuel cell is a fixed width sized to its readout + Buy Fuel button (see layout
-- note in buildContent). The readout must fit "Fuel: 999/999" -- 94px at 9pt and
-- 115px at 11pt (measured, see CH_W) plus the cell's padding -- and the button
-- keeps a real margin to its right rather than the 2px it used to have, which
-- left it looking jammed against the next cell's divider.
--
-- Three digits is enough: the widest max_fuel in the live ship table is 589.
-- The old 96/104 was too narrow at BOTH sizes, so the button overlapped the
-- readout and ate its last digit ("Fuel: 360/40").
local FUEL_READOUT_W = WEB and 112 or 136
local FUEL_BTN_X     = FUEL_READOUT_W + 2
local FUEL_BTN_W     = WEB and 90 or 84
local FUEL_RIGHT_PAD = 8
local FUEL_CELL_W    = FUEL_BTN_X + FUEL_BTN_W + FUEL_RIGHT_PAD  -- 230 desktop, 212 web

-- The cells, left to right. All but Fuel share the leftover width in proportion
-- to how long their text actually gets, rather than splitting it evenly -- the
-- even split this replaced clipped Rank and Groats while Slithies sat half empty.
--
-- `tail` is the widest value a cell ever shows, in characters, including the
-- ": " (Groats tops out at "27.4 m/27.5 m", Hold carries a cargo glyph). Adding
-- the label length gives the weight, so changing a label automatically re-divides
-- the space instead of needing the numbers re-tuned by hand.
--
-- It also gives each cell a CAP (see maxW below). Proportional shares alone left
-- Rank and Groats visibly padded out: with the row wider than the text needs,
-- every cell grew in proportion, so the surplus appeared as a dead gap after each
-- readout. Capping each cell at its own longest value keeps them hugging their
-- text and pushes the leftover into Hold, the last cell, which absorbs the
-- remainder. One open area at the end of the row beats four ragged gaps in it.
--
-- The cap is deliberately static — derived from these worst-case lengths, not
-- from the live value — so cells keep still. Sizing to the current text would
-- make the whole row twitch every time Groats ticked over.
--
-- Appended rather than written inline with a conditional: a nil in the middle of
-- a table constructor leaves a hole that stops ipairs dead at the gap.
local CELLS = {
    { key = "rank", label = "Rank",                      tail = 15 },
    { key = "fuel", label = "Fuel",                      fixed = FUEL_CELL_W },
    { key = "stam", label = WEB and "STM" or "Stamina",  tail =  9 },
    { key = "cash", label = "Groats",                    tail = 15 },
}
-- Slithies: desktop only. Rarely changes, and the pane is too narrow on web to
-- carry it without squeezing the four readouts you actually fly by.
if not WEB then
    CELLS[#CELLS + 1] = { key = "slith", label = "Slithies", tail = 9 }
end
-- Hold stays last: the rightmost cell absorbs the rounding remainder.
-- ": 5000/5000 " is 12 -- max_hold really does reach 5000 in the live ship
-- table -- plus 2 for the cargo glyph, which is a double-width character and
-- measures about one extra cell beyond its single count.
CELLS[#CELLS + 1] = { key = "hold", label = "Hold", tail = 14 }

-- One character's width in the strip's font. Geyser sizes labels in POINTS and
-- the browser lays them out in px, hence the 4/3.
--
-- 0.600 em is MEASURED, not guessed: rendering this exact font stack and markup
-- in Chromium gives 7.2px/char at 9pt and 8.8px/char at 11pt, dead flat across
-- every readout. The previous 0.55 guess was 9% light, which is precisely how a
-- cap ends up sitting on top of the last character of its own text.
local CH_W    = CELL_PT * (4 / 3) * 0.600
local CELL_PX = (WEB and 10 or 16) + 4   -- cell padding, both sides, plus air

local LBL, FLEX_TOTAL = {}, 0
for _, c in ipairs(CELLS) do
    LBL[c.key] = c.label
    c.weight   = c.tail and (#c.label + c.tail) or nil
    c.maxW     = c.weight and (math.ceil(c.weight * CH_W) + CELL_PX) or nil
    FLEX_TOTAL = FLEX_TOTAL + (c.weight or 0)
end

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

    -- Labels are keyed, not indexed: a cell absent on this platform (Slithies on
    -- web) is simply a nil lookup, with no positions to renumber.
    local function put(key, text)
        if L[key] then L[key]:echo(LBL[key] .. ": " .. text) end
    end

    put("rank", "<b>" .. rank .. "</b>")

    if tonumber(fuel_cur) then
        put("fuel", string.format("<b><font color=%s>%s</font></b>/%s",
            colorPercent(fuel_cur, fuel_max), fuel_cur, fuel_max))
    else
        put("fuel", "-")
    end

    if tonumber(stam_cur) then
        put("stam", string.format("<b><font color=%s>%s</font></b>/%s",
            colorPercent(stam_cur, stam_max), stam_cur, stam_max))
    else
        put("stam", "-")
    end

    if groats_max == "-" then
        put("cash", "<b>" .. cash .. "</b>")
    else
        put("cash", "<b>" .. cash .. "</b>/" .. groats_max)
    end

    put("slith", "<b>" .. tostring(slith) .. "</b>")

    if tonumber(hold_cur) then
        local has_cargo = ship.cargo and next(ship.cargo) ~= nil
        local disp = string.format("<b><font color=%s>%s</font></b>/%s",
            colorPercent(hold_cur, hold_max), hold_cur, hold_max)
        if has_cargo then disp = disp .. " 📦" end
        put("hold", disp)
    else
        put("hold", "-")
    end
end

local function refreshAll()
    for gid in pairs(instances) do pcall(refreshInstance, gid) end
end

-- Position the six cells: fuel is a fixed width; the rest share what's left in
-- proportion to CELLS[].weight, and the last cell takes the rounding remainder so
-- there is never a gap on the right.
local function layoutCells(inst)
    if not inst or not inst.cells or not inst.host then return end
    local W = inst.host.get_width and inst.host:get_width() or 0
    if not W or W <= 0 then return end
    local flex = math.max(0, W - FUEL_CELL_W)
    local x, last = 0, #CELLS
    for i, spec in ipairs(CELLS) do
        local w
        if spec.fixed then
            w = spec.fixed
        elseif i == last then
            w = math.max(40, W - x)                     -- fill remainder
        else
            w = math.max(40, math.floor(flex * spec.weight / FLEX_TOTAL))
            -- Never wider than the longest value it can hold: past that the
            -- extra is dead space, and belongs to the last cell instead.
            if w > spec.maxW then w = spec.maxW end
        end
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
        ' padding: ' .. CELL_PAD .. '; font-family: "Consolas","Monaco",monospace;'

    -- Cells laid out manually (NOT an HBox): the fuel cell is a FIXED width sized
    -- to its readout + button, and the rest share the remaining width by weight.
    -- An HBox would size every cell proportionally, which forces the fuel cell to
    -- either clip the fixed-size button or leave a growing empty gap to its right
    -- as the bar widens.  layoutCells() (re)positions them.
    --
    -- `cells` is positional (layoutCells walks it alongside CELLS); `labels` is
    -- keyed, so refreshInstance never has to know which platform dropped what.
    local cells, labels, fuelCell = {}, {}, nil
    for i, spec in ipairs(CELLS) do
        local cell = Geyser.Label:new({ name = wid(), x = 0, y = 0, width = 10, height = "100%" }, target.content)
        cell:setStyleSheet(H_LABEL_CSS)
        cells[i] = cell
        if spec.key == "fuel" then
            fuelCell = cell            -- gets inner widgets below, not text of its own
        else
            pcall(function() cell:setFontSize(CELL_PT) end)
            labels[spec.key] = cell
        end
    end

    -- Fuel cell: inner readout (left) + small Buy Fuel button right after it.
    local fuelText = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = FUEL_READOUT_W, height = "100%",
    }, fuelCell)
    fuelText:setStyleSheet(CELL_TEXT_CSS)
    pcall(function() fuelText:setFontSize(CELL_PT) end)
    labels.fuel = fuelText

    local buyBtn = Geyser.Label:new({
        name = wid(), x = FUEL_BTN_X, y = "20%", width = FUEL_BTN_W, height = "60%",
    }, fuelCell)
    buyBtn:setStyleSheet(BUTTON_CSS)
    pcall(function() buyBtn:setFontSize(BTN_PT) end)
    buyBtn:echo("<center>⛽&nbsp;Buy&nbsp;Fuel</center>")
    buyBtn:setToolTip("Buy fuel at a shuttlepad")
    buyBtn:setClickCallback(function() send("buy fuel") end)

    labels.hold:setToolTip("Cargo hold")   -- legacy inline cargo panel is now fed2_cargo

    instances[gid] = { labels = labels, buyBtn = buyBtn, cells = cells, host = target.content }
    layoutCells(instances[gid])
    refreshInstance(gid)
end

local function buildPlayerInfoDef()
    return {
        name        = "Player Info",
        description = "Live rank / fuel / stamina / groats / hold strip with Buy Fuel.",
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