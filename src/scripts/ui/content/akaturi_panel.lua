-- Commerce > Akaturi: the Adventurer's courier work, by hand or automated.
-- Shows Akaturi points toward promotion and the contract the player holds
-- (from the game itself, akaturi_tracker.lua, so a contract taken by hand
-- shows the same as one hauling took). The AC office, pickup and dropoff
-- rows walk there on click; the action row offers the next step (take a
-- contract, go to the pickup and pick up, go to the dropoff and drop off).
-- Haul ▸ Start in the strip above runs the whole loop instead.

local CELL_PT  = 10
local LABEL_PT = 8
local ROW_H    = 24
local H_ACT    = 26

local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

local _CARD_CSS = [[
    background-color: rgba(18, 18, 26, 255);
    border: none;
]]

local _TOOLTIP_CSS = [[
    QToolTip {
        background-color: #1d2030; color: #e8ebf5;
        border: 1px solid rgba(255,255,255,0.18); padding: 3px;
    }
]]

local _ROW_CSS = [[
    QLabel {
        background-color: transparent;
        border: none; border-bottom: 1px solid rgba(255,255,255,0.05);
        padding-left: 8px;
    }
]] .. _TOOLTIP_CSS

local _LINK_ROW_CSS = _ROW_CSS .. [[
    QLabel::hover { background-color: rgba(38,44,66,235); }
]]

local _ACT_BAR_CSS = [[
    background-color: rgba(16, 18, 28, 230);
    border: none;
    border-bottom: 1px solid rgba(60, 65, 100, 150);
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
    ]], accent, accentHover) .. _TOOLTIP_CSS
end

-- Shown while hauling is working the contract, so clicks don't fight it.
local _BTN_IDLE_CSS = [[
    QLabel {
        background-color: rgba(22,24,34,200);
        color: rgba(120,126,150,255);
        border: 1px solid rgba(60,65,90,150);
        border-left: 3px solid rgba(80,85,110,200);
        border-radius: 4px;
        font-weight: bold; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
]] .. _TOOLTIP_CSS

local _BTN_CSS = {
    take    = actionBtnCss("#3aa0ff", "#5cb8ff"),
    go      = actionBtnCss("#00b8b8", "#33d6d6"),
    pickup  = actionBtnCss("#3ecf5e", "#5ce87c"),
    dropoff = actionBtnCss("#e0b84d", "#f0cc66"),
    details = actionBtnCss("#8a7ae0", "#a596f0"),
}

local BUTTON_SLOTS = 3
local AKATURI_GOAL = 25

-- Per-pane state, keyed by target._gid
local instances = {}

local function span(color, text, bold)
    return string.format("<span style='%scolor:%s;%s'>%s</span>",
        CELL_FONT, color, bold and "font-weight:bold;" or "", text)
end

local function field(label, value)
    return span("#888888", (string.format("%-9s", label):gsub(" ", "&nbsp;"))) .. value
end

local function dash() return span("#666666", "—") end

-- Hauling is driving Akaturi contracts right now (not paused or stopped).
local function automationRunning()
    local state = F2T_HAULING_STATE
    return state and state.active and state.mode == "akaturi" and not state.paused
end

local function pointsHtml()
    local points = f2t_akaturi_get_points and f2t_akaturi_get_points()
    if not points then
        return field("Points", span("#666666", "shown at Adventurer rank"))
    end
    local color = points >= AKATURI_GOAL and "#3ecf5e" or "#e8ebf5"
    local note = points >= AKATURI_GOAL and span("#3ecf5e", "  ready to promote")
        or span("#888888", string.format("  %d more to promote", AKATURI_GOAL - points))
    return field("Points", span(color, tostring(points), true) .. span("#888888", "/" .. AKATURI_GOAL) .. note)
end

local function placeHtml(planet, room)
    return span("#00cccc", planet) .. span("#888888", "  " .. (room or "room not read yet"))
end

-- What the action row offers for where the contract stands.
local function stageButtons(contract)
    if not contract then
        return {
            { key = "take", label = "📋 Take", tip = "Go to an Armstrong Cuthbert office and take a contract (ak)",
              run = f2t_akaturi_take_contract },
        }
    end
    local buttons
    if not contract.collected then
        buttons = {
            { key = "go", label = "🧭 Go", tip = "Walk to the pickup room",
              run = function() f2t_akaturi_go_to_room("pickup") end },
            { key = "pickup", label = "📦 Pickup", tip = "Pick up the package here (pickup)",
              run = function() send("pickup") end },
        }
    else
        buttons = {
            { key = "go", label = "🧭 Go", tip = "Walk to the dropoff room",
              run = function() f2t_akaturi_go_to_room("delivery") end },
            { key = "dropoff", label = "✅ Drop off", tip = "Hand over the package here (dropoff)",
              run = function() send("dropoff") end },
        }
    end
    buttons[#buttons + 1] = { key = "details", label = "🔎 Details",
        tip = "Show the contract in the game (di ak); also reads the room if it isn't known",
        run = function() send("di ak") end }
    return buttons
end

local function renderButtons(inst, contract)
    local buttons = stageButtons(contract)
    local busy = automationRunning()
    for i = 1, BUTTON_SLOTS do
        local btn, spec = inst.buttons[i], buttons[i]
        if spec then
            btn:echo("<center>" .. spec.label .. "</center>")
            if busy then
                btn:setStyleSheet(_BTN_IDLE_CSS)
                btn:setToolTip("Hauling is working this contract. Pause it (Haul ▸ Pause) to work it by hand.")
                btn:setClickCallback(function() end)
            else
                btn:setStyleSheet(_BTN_CSS[spec.key])
                btn:setToolTip(spec.tip)
                btn:setClickCallback(spec.run)
            end
            btn:show()
        else
            btn:hide()
        end
    end
end

local function statusHtml(contract)
    if automationRunning() then
        local snap = f2tHaulingSnapshot()
        return field("Status", span("#3ecf5e", "hauling", true) ..
            span("#888888", "  " .. (snap.phaseLabel or "")))
    end
    if not contract then
        return field("Status", span("#888888", "no contract. Take one at an AC office"))
    end
    if contract.collected then
        return field("Status", span("#e0b84d", "carry the package to the dropoff", true))
    end
    return field("Status", span("#7aa2ff", "go to the pickup", true))
end

local function render(inst)
    local contract = f2t_akaturi_contract()

    inst.info:echo(pointsHtml())
    inst.status:echo(statusHtml(contract))
    renderButtons(inst, contract)

    local office = f2t_akaturi_office_planet()
    if f2t_akaturi_at_office() then
        inst.office:echo(field("AC office", span("#3ecf5e", "you're here")))
        inst.office:setToolTip("ak takes a contract here")
    else
        inst.office:echo(field("AC office", span("#00cccc", office)))
        inst.office:setToolTip("Go to the Armstrong Cuthbert office on " .. office)
    end

    if contract then
        if contract.collected then
            inst.pickup:echo(field("Pickup", span("#3ecf5e", "collected ✓ ") ..
                span("#888888", contract.pickupPlanet)))
            inst.pickup:setToolTip("Go to " .. contract.pickupPlanet .. " — " .. (contract.pickupRoom or "?"))
            inst.dropoff:echo(field("Dropoff", placeHtml(contract.deliveryPlanet, contract.deliveryRoom)))
            inst.dropoff:setToolTip("Go to " .. contract.deliveryPlanet .. " — " .. (contract.deliveryRoom or "?"))
        else
            inst.pickup:echo(field("Pickup", placeHtml(contract.pickupPlanet, contract.pickupRoom)))
            inst.pickup:setToolTip("Go to " .. contract.pickupPlanet .. " — " .. (contract.pickupRoom or "?"))
            inst.dropoff:echo(field("Dropoff", span("#666666", "revealed at pickup")))
            inst.dropoff:setToolTip("Revealed when the package is collected")
        end
        inst.package:echo(field("Package", contract.package and span("#e6d28c", contract.package) or dash()))
        inst.payment:echo(field("Payment", span("#3ecf5e", string.format("%d ig", contract.payment))))
    else
        inst.pickup:echo(field("Pickup", dash()))
        inst.pickup:setToolTip("")
        inst.dropoff:echo(field("Dropoff", dash()))
        inst.dropoff:setToolTip("")
        inst.package:echo(field("Package", dash()))
        inst.payment:echo(field("Payment", dash()))
    end

    local state = F2T_HAULING_STATE
    local cycles = state and state.total_cycles or 0
    local earned = state and state.session_profit or 0
    if state and state.strategy == "akaturi" and cycles > 0 then
        inst.session:echo(field(state.active and "Session" or "Last run",
            span("#e8ebf5", string.format("%d contract%s", cycles, cycles == 1 and "" or "s")) ..
            span("#888888", " · ") .. span("#3ecf5e", string.format("%d ig", earned))))
    else
        inst.session:echo(field("Session", dash()))
    end
end

local function renderAll()
    for _, inst in pairs(instances) do pcall(render, inst) end
end

registerAnonymousEventHandler("f2tAkaturiContractChanged", renderAll)
registerAnonymousEventHandler("f2tHaulingStatusChanged", renderAll)
registerAnonymousEventHandler("gmcp.char.vitals", renderAll)
registerAnonymousEventHandler("gmcp.room.info", renderAll)

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        render(instances[gid])
        return
    end

    local strip   = f2tHaulStripCreate(target)
    local rowH    = f2tScaled(target, ROW_H)
    local actH    = f2tScaled(target, H_ACT)
    local cellPt  = f2tUiPt(target, CELL_PT)
    local labelPt = f2tTextPt(target, LABEL_PT)

    -- ── Action row: next-step buttons, points on the right ───────────────────
    local actBar = Geyser.Label:new({
        name = gid .. "_ak_act", x = 0, y = strip.height, width = "100%", height = actH,
    }, target.content)
    actBar:setStyleSheet(_ACT_BAR_CSS)

    local btnW = f2tScaled(target, 92)
    local buttons = {}
    for i = 1, BUTTON_SLOTS do
        buttons[i] = Geyser.Label:new({
            name = gid .. "_ak_btn" .. i, x = 6 + (i - 1) * (btnW + 8), y = 4,
            width = btnW, height = actH - 8, fontSize = labelPt,
        }, actBar)
    end

    local infoX = 6 + BUTTON_SLOTS * (btnW + 8)
    local info = Geyser.Label:new({
        name = gid .. "_ak_info", x = infoX, y = 0, width = "100%-" .. (infoX + 6) .. "px", height = "100%",
        fontSize = cellPt,
    }, actBar)
    info:setStyleSheet("background-color: transparent; border: none; qproperty-alignment: AlignRight|AlignVCenter;")

    -- ── Contract card ─────────────────────────────────────────────────────────
    local top = strip.height + actH
    local card = Geyser.Label:new({
        name = gid .. "_ak_card", x = 0, y = top, width = "100%", height = "100%-" .. top .. "px",
    }, target.content)
    card:setStyleSheet(_CARD_CSS)

    local inst = { buttons = buttons, info = info }
    local order = { "status", "office", "pickup", "dropoff", "package", "payment", "session" }
    for i, key in ipairs(order) do
        local lbl = Geyser.Label:new({
            name = gid .. "_ak_" .. key, x = 0, y = 4 + (i - 1) * rowH, width = "100%", height = rowH,
            fontSize = cellPt,
        }, card)
        lbl:setStyleSheet(_ROW_CSS)
        inst[key] = lbl
    end

    inst.office:setStyleSheet(_LINK_ROW_CSS)
    inst.office:setClickCallback(function() f2t_akaturi_go_to_office() end)
    inst.pickup:setStyleSheet(_LINK_ROW_CSS)
    inst.pickup:setClickCallback(function() f2t_akaturi_go_to_room("pickup") end)
    inst.dropoff:setStyleSheet(_LINK_ROW_CSS)
    inst.dropoff:setClickCallback(function() f2t_akaturi_go_to_room("delivery") end)

    instances[gid] = inst
    render(inst)
end

local function buildAkaturiDef()
    return {
        name        = "Akaturi",
        description = "Akaturi courier contract by hand or automated: points, pickup and dropoff, next step.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[akaturi_panel] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            instances[target._gid] = nil
            f2tHaulStripRemove(target._gid)
        end,
        serialize   = function(_t) return {} end,
        restore     = function(_t, _d) end,
        onReveal    = function(target)
            local inst = instances[target._gid]
            if inst then render(inst) end
        end,
        onTextScale = function(target) f2tRebuildForTextScale(target) end,
    }
end

function f2tRegisterAkaturiPanel()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[akaturi_panel] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_akaturi", buildAkaturiDef())
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterAkaturiPanel)

if f2t_debug_log then f2t_debug_log("[akaturi_panel] module loaded") end
