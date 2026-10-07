-- Commerce > Akaturi: the Adventurer's courier work, by hand or automated.
-- A contract runs in three steps: take it at an Armstrong Cuthbert office (ak),
-- pick the package up in a room named by the contract (pickup), then drop it
-- off in a room on another Sol planet revealed at pickup (dropoff). The panel
-- shows credits toward promotion, the three steps with the current one lit,
-- and one button for the next step. Rooms are found by the shared finder
-- (akaturi_finder.lua), which hauling uses too.

local CELL_PT  = 10
local LABEL_PT = 8
local ROW_H    = 24
local STEP_H   = 42
local H_ACT    = 26
local BAR_H    = 5

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

local _PLAIN_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        padding-left: 8px; padding-right: 8px;
        qproperty-wordWrap: true;
    }
]] .. _TOOLTIP_CSS

local function stepCss(state, accent)
    local background, edge = "transparent", "rgba(0,0,0,0)"
    if state == "current" then
        background, edge = "rgba(30,34,52,235)", accent
    end
    return string.format([[
        QLabel {
            background-color: %s;
            border: none; border-left: 3px solid %s;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            padding-left: 8px; padding-right: 8px;
            qproperty-wordWrap: true;
        }
    ]], background, edge) .. _TOOLTIP_CSS
end

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

local ACCENT = {
    take     = { "#3aa0ff", "#5cb8ff" },
    find     = { "#00b8b8", "#33d6d6" },
    pickup   = { "#3ecf5e", "#5ce87c" },
    delivery = { "#e0b84d", "#f0cc66" },
    stop     = { "#e05d5d", "#f07a7a" },
    details  = { "#8a7ae0", "#a596f0" },
}

local _BTN_CSS = {}
for key, colors in pairs(ACCENT) do _BTN_CSS[key] = actionBtnCss(colors[1], colors[2]) end

local GREEN, DIM, MUTED, TEXT, PLANET = "#3ecf5e", "#666666", "#8a8fa3", "#e8ebf5", "#00cccc"

-- Per-pane state, keyed by target._gid
local instances = {}

local function span(color, text, bold)
    return string.format("<span style='%scolor:%s;%s'>%s</span>",
        CELL_FONT, color, bold and "font-weight:bold;" or "", text)
end

local function escape(text)
    return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Hauling is driving Akaturi contracts right now (not paused or stopped).
local function automationRunning()
    local state = F2T_HAULING_STATE
    return state and state.active and state.mode == "akaturi" and not state.paused
end

-- ── Credits ──────────────────────────────────────────────────────────────────

local function promotionTip()
    return string.format(
        "Promotion to Merchant needs %d Akaturi credits and %s ig in the bank; apply at the " ..
        "Trading Guild HQ on Earth.\nContracts keep paying and earning credits after %d. " ..
        "An Adventurer's cash over %s ig is taxed at the next login.",
        F2T_AKATURI_PROMOTE_AT, f2t_format_number(F2T_AKATURI_PROMOTE_CASH), F2T_AKATURI_PROMOTE_AT,
        f2t_format_number(F2T_AKATURI_CASH_CAP))
end

local function renderCredits(inst)
    local points = f2t_akaturi_get_points()
    local goal = F2T_AKATURI_PROMOTE_AT
    inst.credits:setToolTip(promotionTip())
    if not points then
        inst.credits:echo(span(MUTED, "Akaturi credits show at Adventurer rank"))
        inst.bar:hide()
        return
    end

    local note
    if points < goal then
        note = span(MUTED, string.format("%d to Merchant", goal - points))
    else
        local short = F2T_AKATURI_PROMOTE_CASH - (f2t_ac_get_cash() or 0)
        note = short > 0 and span("#e0b84d", string.format("%s ig short", f2t_format_number(short)))
            or span(GREEN, "ready to promote", true)
    end
    inst.credits:echo(span(points >= goal and GREEN or TEXT, tostring(points), true) ..
        span(MUTED, string.format("/%d credits · ", goal)) .. note)

    local fill = math.min(points / goal, 1)
    local fillColor = points >= goal and "#3ecf5e" or "#3aa0ff"
    local track = "rgba(60,65,90,180)"
    local css
    if fill <= 0 then
        css = string.format("background-color: %s;", track)
    elseif fill >= 1 then
        css = string.format("background-color: %s;", fillColor)
    else
        css = string.format("background-color: qlineargradient(x1:0, y1:0, x2:1, y2:0, " ..
            "stop:0 %s, stop:%.3f %s, stop:%.3f %s, stop:1 %s);",
            fillColor, fill, fillColor, fill + 0.001, track, track)
    end
    inst.bar:setStyleSheet(css .. " border: none; border-radius: 2px;")
    inst.bar:show()
end

-- ── Steps ────────────────────────────────────────────────────────────────────

-- Live progress of a room search on this leg, or "you're here".
local function legNote(kind, planet, room)
    local visit = f2t_akaturi_visit_current()
    if visit and visit.kind == kind then
        if visit.stage == "walking" then
            local which = (visit.total or 0) > 1
                and string.format(" · %d of %d rooms with this name", visit.index, visit.total) or ""
            return span("#7aa2ff", "  ← heading there" .. which)
        elseif visit.stage == "exploring" then
            return span("#7aa2ff", "  ← exploring " .. escape(planet) .. " for it")
        elseif visit.stage == "trying" then
            return span("#7aa2ff", "  ← trying this room")
        end
    end
    if room and f2t_akaturi_at_room(planet, room) then
        return span(GREEN, "  ← you're here")
    end
    return ""
end

local function placeHtml(planet, room, missing)
    return span(PLANET, escape(planet)) .. span(MUTED, " · ") ..
        (room and span(TEXT, escape(room)) or span(MUTED, missing or "room not read yet · 🔎 Details reads it"))
end

local MARK = { done = { "✓", GREEN }, current = { "▸", "#7aa2ff" }, todo = { "○", DIM } }

local function stepHtml(state, title, detail)
    local mark = MARK[state]
    local titleColor = state == "todo" and DIM or (state == "done" and MUTED or TEXT)
    return span(mark[2], mark[1] .. " ", true) .. span(titleColor, title, state == "current") ..
        "<br>" .. span(MUTED, "&nbsp;&nbsp;") .. detail
end

-- Rows show where the contract stands; the buttons above do the acting.
local function setStep(lbl, state, accentKey, title, detail, tip)
    lbl:setStyleSheet(stepCss(state, ACCENT[accentKey][1]))
    lbl:echo(stepHtml(state, title, detail))
    lbl:setToolTip(tip or "")
end

local SEARCH_TIP = "%s on %s. %s finds it: rooms sharing the name are tried nearest first, " ..
    "then the planet is explored."

local function renderSteps(inst, contract)
    if contract then
        setStep(inst.stepTake, "done", "take", "Take a contract", span(MUTED, "contract in hand"))
    elseif not f2t_akaturi_rank_ok() then
        setStep(inst.stepTake, "todo", "take", "Take a contract",
            span(MUTED, "Akaturi contracts are for Adventurers"))
    elseif f2t_akaturi_at_office() then
        setStep(inst.stepTake, "current", "take", "Take a contract",
            span(GREEN, "you're in an Armstrong Cuthbert office"))
    else
        local _, label = f2t_akaturi_office_target()
        setStep(inst.stepTake, "current", "take", "Take a contract",
            span(MUTED, "at an Armstrong Cuthbert office · nearest ") .. span(PLANET, escape(label)),
            "Akaturi work is all in Sol: contracts come from an Armstrong Cuthbert office there.")
    end

    if not contract then
        setStep(inst.stepPickup, "todo", "pickup", "Pick up the package",
            span(DIM, "a room on a Sol planet, named in the contract"))
    elseif contract.collected then
        setStep(inst.stepPickup, "done", "pickup", "Pick up the package",
            span(MUTED, "collected on " .. escape(contract.pickupPlanet)))
    else
        setStep(inst.stepPickup, "current", "pickup", "Pick up the package",
            placeHtml(contract.pickupPlanet, contract.pickupRoom) ..
                legNote("pickup", contract.pickupPlanet, contract.pickupRoom),
            string.format(SEARCH_TIP, contract.pickupRoom or "The room", contract.pickupPlanet,
                "Find & pick up"))
    end

    if not contract then
        setStep(inst.stepDropoff, "todo", "delivery", "Drop it off",
            span(DIM, "a room on another Sol planet"))
    elseif not contract.collected then
        -- The game names the dropoff planet up front; only the room waits for the pickup
        setStep(inst.stepDropoff, "todo", "delivery", "Drop it off",
            placeHtml(contract.deliveryPlanet, nil, "room revealed at pickup"))
    else
        setStep(inst.stepDropoff, "current", "delivery", "Drop it off",
            placeHtml(contract.deliveryPlanet, contract.deliveryRoom) ..
                legNote("delivery", contract.deliveryPlanet, contract.deliveryRoom),
            string.format(SEARCH_TIP, contract.deliveryRoom or "The room", contract.deliveryPlanet,
                "Find & drop off"))
    end
end

-- ── Action row ───────────────────────────────────────────────────────────────

-- The one next step, plus Details while a contract is held.
local function actionSpecs(contract)
    local visit = f2t_akaturi_visit_current()
    if visit and visit.owner == "manual" then
        return {
            { key = "stop", label = "■ Stop", tip = "Stop looking for the room",
              run = function() f2t_akaturi_visit_cancel() end },
        }
    end

    local specs = {}
    if not contract then
        if f2t_akaturi_rank_ok() then
            specs[1] = { key = "take", label = "📋 Take contract",
                tip = "Walk to an Armstrong Cuthbert office and take a contract (ak)",
                run = f2t_akaturi_take_contract }
        end
        return specs
    end

    -- Find walks there itself (searching and exploring as needed); the second
    -- button only acts in the current room, for hunting it down by hand.
    local kind, planet = f2t_akaturi_leg(contract)
    local verb = kind == "pickup" and "pick up" or "drop off"
    specs[1] = { key = "find", label = kind == "pickup" and "🧭 Find & pick up" or "🧭 Find & drop off",
        tip = string.format("Walk to the room on %s and %s, trying rooms that share its name nearest " ..
            "first and exploring the planet if needed", planet, verb),
        run = f2t_akaturi_work_leg }
    specs[2] = { key = kind, label = kind == "pickup" and "📦 Pick up" or "✅ Drop off",
        tip = string.format("%s here (%s), for when you find the room yourself",
            kind == "pickup" and "Pick up the package" or "Hand over the package",
            kind == "pickup" and "pickup" or "dropoff"),
        run = f2t_akaturi_act_here }
    specs[3] = { key = "details", label = "🔎 Details", tip = "Show the contract in the game (di ak)",
        run = function() send("di ak") end }
    return specs
end

local function renderButtons(inst, contract)
    local specs = actionSpecs(contract)
    local busy = automationRunning()
    for i, btn in ipairs(inst.buttons) do
        local spec = specs[i]
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

-- ── Footer ───────────────────────────────────────────────────────────────────

local VOID_TIP = "void cancels a contract: a 10,000 ig fine and 5 credits lost."

local function renderFooter(inst, contract)
    if contract then
        inst.footer:echo(span(MUTED, "Package ") ..
            span("#e6d28c", escape(contract.package or "valuable")) ..
            span(MUTED, " · pays ") .. span(GREEN, f2t_format_number(contract.payment) .. " ig") ..
            span(MUTED, " + 1 credit"))
    else
        inst.footer:echo(span(MUTED, "Pays 1,501–2,300 ig + 1 credit · no time limit"))
    end
    inst.footer:setToolTip(VOID_TIP)

    local state = F2T_HAULING_STATE
    local cycles = state and state.total_cycles or 0
    if state and state.strategy == "akaturi" and cycles > 0 then
        inst.session:echo(span(MUTED, state.active and "This session " or "Last run ") ..
            span(TEXT, string.format("%d contract%s", cycles, cycles == 1 and "" or "s")) ..
            span(MUTED, " · ") .. span(GREEN, f2t_format_number(state.session_profit or 0) .. " ig"))
        inst.session:show()
    else
        inst.session:hide()
    end
end

-- Only when the game says uninsured: a death would then be permanent.
local function renderInsurance(inst)
    if f2t_insurance_status() ~= false then
        inst.insurance:hide()
        return
    end
    inst.insurance:echo(span("#ff6b6b", "⚠ Not insured: a death now is permanent", true) ..
        span(MUTED, " · click to go and insure"))
    inst.insurance:setToolTip("Walk to the nearest insurance broker and buy a policy")
    inst.insurance:show()
end

local function render(inst)
    local contract = f2t_akaturi_contract()
    renderInsurance(inst)
    renderCredits(inst)
    renderSteps(inst, contract)
    renderButtons(inst, contract)
    renderFooter(inst, contract)
end

local function renderAll()
    for _, inst in pairs(instances) do pcall(render, inst) end
end

registerAnonymousEventHandler("f2tAkaturiContractChanged", renderAll)
registerAnonymousEventHandler("f2tAkaturiVisitChanged", renderAll)
registerAnonymousEventHandler("f2tHaulingStatusChanged", renderAll)
registerAnonymousEventHandler("gmcp.char.vitals", renderAll)
registerAnonymousEventHandler("gmcp.room.info", renderAll)
registerAnonymousEventHandler("f2tInsuranceChanged", renderAll)

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
    local stepH   = f2tScaled(target, STEP_H)
    local actH    = f2tScaled(target, H_ACT)
    local barH    = math.max(3, f2tScaled(target, BAR_H))
    local cellPt  = f2tUiPt(target, CELL_PT)
    local labelPt = f2tTextPt(target, LABEL_PT)

    -- ── Action row ───────────────────────────────────────────────────────────
    local actBar = Geyser.Label:new({
        name = gid .. "_ak_act", x = 0, y = strip.height, width = "100%", height = actH,
    }, target.content)
    actBar:setStyleSheet(_ACT_BAR_CSS)

    local widths = { f2tScaled(target, 140), f2tScaled(target, 96), f2tScaled(target, 88) }
    local buttons, x = {}, 6
    for i, width in ipairs(widths) do
        buttons[i] = Geyser.Label:new({
            name = gid .. "_ak_btn" .. i, x = x, y = 4, width = width, height = actH - 8, fontSize = labelPt,
        }, actBar)
        x = x + width + 6
    end

    -- ── Card ─────────────────────────────────────────────────────────────────
    local top = strip.height + actH
    local card = Geyser.Label:new({
        name = gid .. "_ak_card", x = 0, y = top, width = "100%", height = "100%-" .. top .. "px",
    }, target.content)
    card:setStyleSheet(_CARD_CSS)

    local y = 6
    local function add(key, height)
        local lbl = Geyser.Label:new({
            name = gid .. "_ak_" .. key, x = 0, y = y, width = "100%", height = height, fontSize = cellPt,
        }, card)
        lbl:setStyleSheet(_PLAIN_CSS)
        y = y + height
        return lbl
    end

    local inst = { buttons = buttons }
    inst.credits = add("credits", rowH)
    inst.bar = Geyser.Label:new({
        name = gid .. "_ak_bar", x = 8, y = y, width = "100%-16px", height = barH,
    }, card)
    y = y + barH + 8
    inst.stepTake    = add("take", stepH)
    inst.stepPickup  = add("pickup", stepH)
    inst.stepDropoff = add("dropoff", stepH)
    y = y + 4
    inst.footer  = add("footer", stepH)
    inst.session = add("session", rowH)
    inst.insurance = add("insurance", stepH)
    inst.insurance:setClickCallback(function() f2t_insurance_get_insured() end)

    instances[gid] = inst
    render(inst)
end

local function buildAkaturiDef()
    return {
        name        = "Akaturi",
        description = "Akaturi courier contracts: credits toward Merchant, take, pick up and drop off.",
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
