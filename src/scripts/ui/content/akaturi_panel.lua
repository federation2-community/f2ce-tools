-- Commerce > Akaturi: the Adventurer's courier contract at a glance. Shows
-- Akaturi points toward promotion, the contract hauling is working (pickup,
-- dropoff, package, progress; planets navigate on click), and the session's
-- contracts and earnings. Contract details come from the hauling automation,
-- which captures them as it takes each contract.

local CELL_PT = 10
local ROW_H   = 24

local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

local _CARD_CSS = [[
    background-color: rgba(18, 18, 26, 255);
    border: none;
]]

local _ROW_CSS = [[
    QLabel {
        background-color: transparent;
        border: none; border-bottom: 1px solid rgba(255,255,255,0.05);
        padding-left: 8px;
    }
]]

local _LINK_ROW_CSS = _ROW_CSS .. [[
    QLabel::hover { background-color: rgba(38,44,66,235); }
]]

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

local function pointsHtml()
    local points = f2t_akaturi_get_points and f2t_akaturi_get_points()
    if not points then
        return field("Points", span("#666666", "shown at Adventurer rank"))
    end
    local color = points >= AKATURI_GOAL and "#3ecf5e" or "#e8ebf5"
    local note = points >= AKATURI_GOAL and span("#3ecf5e", "  ready to promote") or ""
    return field("Points", span(color, tostring(points), true) .. span("#888888", "/" .. AKATURI_GOAL) .. note)
end

-- The contract hauling is working, or nil when there isn't one.
local function currentContract()
    local state = F2T_HAULING_STATE
    if not (state and state.active and state.mode == "akaturi") then return nil end
    local contract = state.akaturi_contract
    if not (contract and contract.pickup_planet) then return nil end
    return contract, state.akaturi_package_collected
end

local function render(inst)
    inst.points:echo(pointsHtml())

    local contract, collected = currentContract()
    if contract then
        inst.pickup:echo(field("Pickup", span("#00cccc", contract.pickup_planet) ..
            span("#888888", "  " .. (contract.pickup_room or ""))))
        inst.dropoff:echo(field("Dropoff", contract.delivery_planet
            and (span("#00cccc", contract.delivery_planet) .. span("#888888", "  " .. (contract.delivery_room or "")))
            or span("#666666", "revealed at pickup")))
        inst.item:echo(field("Package", contract.item and span("#e6d28c", contract.item) or span("#666666", "—")))
        inst.progress:echo(field("Progress", collected
            and span("#e0b84d", "carrying to dropoff", true)
            or span("#7aa2ff", "heading to pickup", true)))
    else
        inst.pickup:echo(field("Pickup", span("#666666", "—")))
        inst.dropoff:echo(field("Dropoff", span("#666666", "—")))
        inst.item:echo(field("Package", span("#666666", "—")))
        inst.progress:echo(field("Progress", span("#666666",
            "no contract. Haul ▾ starts taking them; or type ak at an AC office")))
    end

    local state = F2T_HAULING_STATE
    local cycles = state and state.total_cycles or 0
    local earned = state and state.session_profit or 0
    local lastAkaturi = state and state.strategy == "akaturi"
    if lastAkaturi and cycles > 0 then
        inst.session:echo(field(state.active and "Session" or "Last run",
            span("#e8ebf5", string.format("%d contract%s", cycles, cycles == 1 and "" or "s")) ..
            span("#888888", " · ") .. span("#3ecf5e", string.format("%d ig", earned))))
    else
        inst.session:echo(field("Session", span("#666666", "—")))
    end
end

local function renderAll()
    for _, inst in pairs(instances) do pcall(render, inst) end
end

registerAnonymousEventHandler("f2tHaulingStatusChanged", renderAll)
registerAnonymousEventHandler("gmcp.char.vitals", renderAll)

local function navigateToPlanet(contractKey)
    local contract = currentContract()
    local planet = contract and contract[contractKey]
    if planet and f2t_map_navigate then f2t_map_navigate(planet) end
end

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

    local strip = f2tHaulStripCreate(target)
    local top   = strip.height
    local rowH  = f2tScaled(target, ROW_H)
    local cellPt = f2tUiPt(target, CELL_PT)

    local card = Geyser.Label:new({
        name = gid .. "_ak_card", x = 0, y = top, width = "100%", height = "100%-" .. top .. "px",
    }, target.content)
    card:setStyleSheet(_CARD_CSS)

    local rows = {}
    local order = { "points", "progress", "pickup", "dropoff", "item", "session" }
    for i, key in ipairs(order) do
        local lbl = Geyser.Label:new({
            name = gid .. "_ak_" .. key, x = 0, y = 4 + (i - 1) * rowH, width = "100%", height = rowH,
            fontSize = cellPt,
        }, card)
        lbl:setStyleSheet(_ROW_CSS)
        rows[key] = lbl
    end

    rows.pickup:setStyleSheet(_LINK_ROW_CSS)
    rows.pickup:setToolTip("Go to the pickup planet")
    rows.pickup:setClickCallback(function() navigateToPlanet("pickup_planet") end)
    rows.dropoff:setStyleSheet(_LINK_ROW_CSS)
    rows.dropoff:setToolTip("Go to the dropoff planet")
    rows.dropoff:setClickCallback(function() navigateToPlanet("delivery_planet") end)

    local inst = rows
    instances[gid] = inst
    render(inst)
end

local function buildAkaturiDef()
    return {
        name        = "Akaturi",
        description = "Akaturi courier contract, points toward promotion, and session earnings.",
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
