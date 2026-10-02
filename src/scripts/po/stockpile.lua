-- SPDX-License-Identifier: GPL-2.0-only
-- f2ce-tools po — stockpile manager
--
-- Plans and applies min/max stock levels and price spreads for an owned
-- exchange from each commodity's net production. Planning policy adapted from
-- Exchange Walker Live (https://github.com/ralphcma/fed2-exchange-walker-live)
-- by Ersella, GPL-2.0-only.
--
-- Flow: preview (one "display exchange" capture -> plan) -> apply (one set
-- command at a time, each confirmed by the server before the next is sent).
-- Auto mode repeats preview+apply over a saved list of remote planets; it is
-- session-only and turns itself off on the first failure.

F2T_STOCKPILE = F2T_STOCKPILE or {
    plan        = nil,    -- {planet, remote, createdAt, rows, actions, applied, appliedCount}
    previewing  = false,
    applying    = false,
    applyIndex  = 0,
    pending     = nil,    -- action awaiting its server acknowledgement
    timeoutId   = nil,
    onApplied   = nil,
    autoEnabled = false,
    autoTimerId = nil,
    autoRunning = false,
    lastMessage = nil,
}

local PLAN_MAX_AGE   = 300  -- seconds a preview stays applicable
local ACK_TIMEOUT    = 8
local COMMAND_SPACING = 0.2

local SPREAD_RANGE = { 6, 40 }
local MIN_RANGE    = { 0, 10000 }
local MAX_RANGE    = { 0, 20000 }

-- ── Settings ──────────────────────────────────────────────────────────────────

local function registerNumber(key, label, description, default, range)
    f2t_settings_register("po", key, {
        tab = "F2CE-Tools/Planet Owner", label = label, description = description,
        default = default, min = range[1], max = range[2],
    })
end

registerNumber("stockpile_deficit_spread", "Deficit spread (%)",
    "Spread for commodities the planet consumes more of than it produces", 6, SPREAD_RANGE)
registerNumber("stockpile_deficit_min", "Deficit min stock", "Min stock for deficit commodities", 0, MIN_RANGE)
registerNumber("stockpile_deficit_max", "Deficit max stock", "Max stock for deficit commodities", 0, MAX_RANGE)
registerNumber("stockpile_breakeven_spread", "Breakeven spread (%)",
    "Spread for commodities with zero net production", 6, SPREAD_RANGE)
registerNumber("stockpile_breakeven_min", "Breakeven min stock", "Min stock for breakeven commodities", 0, MIN_RANGE)
registerNumber("stockpile_breakeven_max", "Breakeven max stock", "Max stock for breakeven commodities", 0, MAX_RANGE)
registerNumber("stockpile_surplus_spread", "Surplus spread (%)",
    "Spread for commodities the planet produces more of than it consumes", 40, SPREAD_RANGE)
registerNumber("stockpile_growth_buffer", "Surplus growth buffer",
    "Below the reserve trigger, a surplus keeps min at current stock and max this far above it", 1000, MAX_RANGE)
registerNumber("stockpile_reserve_trigger", "Surplus reserve trigger",
    "Stock level at which a surplus switches to the reserve min/max", 10000, MIN_RANGE)
registerNumber("stockpile_reserve_min", "Surplus reserve min", "Min stock for a surplus at the reserve trigger",
    10000, MIN_RANGE)
registerNumber("stockpile_reserve_max", "Surplus reserve max", "Max stock for a surplus at the reserve trigger",
    20000, MAX_RANGE)
registerNumber("stockpile_auto_interval", "Auto interval (min)",
    "Minutes between automatic stockpile runs over the target planets", 30, { 5, 1440 })

f2t_settings_register("po", "stockpile_targets", {
    tab = "F2CE-Tools/Planet Owner", label = "Stockpile target planets",
    description = "Comma-separated owned planets for stockpile auto mode and the Stockpiles preview menu",
    default = "",
})

f2t_settings_register("po", "stockpile_excluded", {
    tab = "F2CE-Tools/Planet Owner", label = "Stockpile excluded commodities",
    description = "Comma-separated commodities the stockpile manager never changes",
    default = "",
})

-- ── List settings ─────────────────────────────────────────────────────────────

local function splitList(text)
    local items = {}
    for item in tostring(text or ""):gmatch("[^,]+") do
        item = item:match("^%s*(.-)%s*$")
        if item ~= "" then items[#items + 1] = item end
    end
    return items
end

function f2tStockpileGetList(key)
    return splitList(f2t_settings_get("po", key))
end

--- Add or remove one entry of a comma-separated list setting (case-insensitive)
--- @return boolean changed
function f2tStockpileEditList(key, item, add)
    local items, kept, found = f2tStockpileGetList(key), {}, false
    for _, existing in ipairs(items) do
        if existing:lower() == item:lower() then
            found = true
            if add then kept[#kept + 1] = existing end
        else
            kept[#kept + 1] = existing
        end
    end
    if add and found then return false end
    if not add and not found then return false end
    if add then kept[#kept + 1] = item end
    f2t_settings_set("po", key, table.concat(kept, ", "))
    raiseEvent("f2tStockpileChanged")
    return true
end

-- ── Planning ──────────────────────────────────────────────────────────────────

local function setting(key) return tonumber(f2t_settings_get("po", key)) or 0 end

local function clamp(value, range) return math.max(range[1], math.min(range[2], value)) end

--- Validate the saved policy; returns nil or a message naming the first problem
function f2tStockpilePolicyError()
    if setting("stockpile_deficit_min") > setting("stockpile_deficit_max") then
        return "deficit min stock is above deficit max stock"
    end
    if setting("stockpile_breakeven_min") > setting("stockpile_breakeven_max") then
        return "breakeven min stock is above breakeven max stock"
    end
    if setting("stockpile_reserve_min") > setting("stockpile_reserve_max") then
        return "surplus reserve min is above surplus reserve max"
    end
    return nil
end

--- Target min/max/spread and policy name for one exchange row
local function targetFor(row)
    if row.net < 0 then
        return setting("stockpile_deficit_min"), setting("stockpile_deficit_max"),
            setting("stockpile_deficit_spread"), "deficit"
    elseif row.net == 0 then
        return setting("stockpile_breakeven_min"), setting("stockpile_breakeven_max"),
            setting("stockpile_breakeven_spread"), "breakeven"
    elseif row.stock_current < setting("stockpile_reserve_trigger") then
        local targetMin = clamp(row.stock_current, MIN_RANGE)
        local targetMax = clamp(targetMin + setting("stockpile_growth_buffer"), MAX_RANGE)
        return targetMin, targetMax, setting("stockpile_surplus_spread"), "growing"
    end
    return setting("stockpile_reserve_min"), setting("stockpile_reserve_max"),
        setting("stockpile_surplus_spread"), "reserve"
end

--- Build a plan from parsed exchange rows (f2t_po_parse_exchange_buffer)
--- @param exchangeRows table
--- @param planet string Planet the rows came from
--- @param remote boolean True when commands must name the planet
--- @return table|nil plan, string|nil error
function f2tStockpileBuildPlan(exchangeRows, planet, remote)
    local policyError = f2tStockpilePolicyError()
    if policyError then return nil, "Stockpile policy is invalid: " .. policyError end

    local excluded = {}
    for _, name in ipairs(f2tStockpileGetList("stockpile_excluded")) do excluded[name:lower()] = true end

    local rows, actions = {}, {}
    for _, exchange in ipairs(exchangeRows) do
        local row = {
            commodity = exchange.name, net = exchange.net, stock = exchange.stock_current,
            oldMin = exchange.stock_min, oldMax = exchange.stock_max, oldSpread = exchange.spread,
        }
        if excluded[exchange.name:lower()] then
            row.policy, row.newMin, row.newMax, row.newSpread = "excluded", row.oldMin, row.oldMax, row.oldSpread
        else
            row.newMin, row.newMax, row.newSpread, row.policy = targetFor(exchange)
        end
        rows[#rows + 1] = row
    end

    table.sort(rows, function(left, right)
        if left.net ~= right.net then return left.net > right.net end
        return left.commodity:lower() < right.commodity:lower()
    end)

    for _, row in ipairs(rows) do
        local function add(kind, value)
            actions[#actions + 1] = { kind = kind, commodity = row.commodity, value = value }
        end
        local minChanged, maxChanged = row.newMin ~= row.oldMin, row.newMax ~= row.oldMax
        -- The server checks each bound against the other's live value: lowering
        -- max below the current min needs the min lowered first, else max goes first.
        if minChanged and maxChanged and row.newMax < row.oldMin then
            add("min", row.newMin)
            add("max", row.newMax)
        else
            if maxChanged then add("max", row.newMax) end
            if minChanged then add("min", row.newMin) end
        end
        if row.newSpread ~= row.oldSpread then add("spread", row.newSpread) end
        row.changed = minChanged or maxChanged or row.newSpread ~= row.oldSpread
    end

    return {
        planet = planet, remote = remote, createdAt = os.time(),
        rows = rows, actions = actions, applied = false, appliedCount = 0,
    }
end

-- Always names the planet so moving mid-update can't retarget another exchange
local function commandFor(action, plan)
    local commodity = action.commodity:lower()
    if action.kind == "spread" then
        return string.format("set spread %d %s %s", action.value, commodity, plan.planet)
    end
    return string.format("set stockpile %s %d %s %s", action.kind, action.value, commodity, plan.planet)
end

-- ── Status helpers ────────────────────────────────────────────────────────────

local function report(message, color)
    F2T_STOCKPILE.lastMessage = message
    cecho(string.format("\n<%s>[stockpiles]<reset> %s\n", color or "green", message))
    raiseEvent("f2tStockpileChanged")
end

--- @return string|nil reason the plan can't be applied right now
function f2tStockpilePlanProblem(plan)
    plan = plan or F2T_STOCKPILE.plan
    if not plan then return "No preview yet" end
    if plan.applied then return "This preview was already applied; preview again" end
    if os.time() - plan.createdAt > PLAN_MAX_AGE then return "Preview is out of date; preview again" end
    if #plan.actions == 0 then return "Nothing to change" end
    return nil
end

function f2tStockpileBusy()
    return F2T_STOCKPILE.previewing or F2T_STOCKPILE.applying
end

-- ── Preview ───────────────────────────────────────────────────────────────────

--- Capture an exchange and build a plan
--- @param planet string|nil Remote planet name, nil for the planet you're on
--- @param onDone function|nil Called with (plan) or (nil, error)
--- @return boolean started
function f2tStockpilePreview(planet, onDone)
    local function fail(message)
        report(message, "red")
        if onDone then onDone(nil, message) end
        return false
    end
    if f2tStockpileBusy() then return fail("A stockpile preview or update is already running") end
    if f2t_po.phase ~= "idle" then return fail("Another planet capture is in progress") end

    local remote = planet ~= nil and planet ~= ""
    local planetName = planet
    if not remote then
        local info = gmcp and gmcp.room and gmcp.room.info
        local playerName = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
        if not info or not info.owner or info.owner ~= playerName then
            return fail(string.format("You don't own this planet (owner: %s)", info and info.owner or "unknown"))
        end
        planetName = info.area
    end

    F2T_STOCKPILE.previewing = true
    raiseEvent("f2tStockpileChanged")
    local started = f2t_po_capture_exchange(remote and planetName or nil, function(exchangeRows)
        F2T_STOCKPILE.previewing = false
        if #exchangeRows == 0 then
            fail("No exchange data captured for " .. tostring(planetName))
            return
        end
        local plan, planError = f2tStockpileBuildPlan(exchangeRows, planetName, remote)
        if not plan then
            fail(planError)
            return
        end
        F2T_STOCKPILE.plan = plan
        F2T_STOCKPILE.lastMessage = string.format("%s: %d change%s planned", plan.planet,
            #plan.actions, #plan.actions == 1 and "" or "s")
        raiseEvent("f2tStockpileChanged")
        if onDone then onDone(plan) end
    end)
    if not started then
        F2T_STOCKPILE.previewing = false
        return fail("Couldn't start the exchange capture")
    end
    return true
end

-- ── Apply ─────────────────────────────────────────────────────────────────────

local function stopTimeout()
    if F2T_STOCKPILE.timeoutId then
        killTimer(F2T_STOCKPILE.timeoutId)
        F2T_STOCKPILE.timeoutId = nil
    end
end

local function finishApply(errorMessage)
    stopTimeout()
    local plan = F2T_STOCKPILE.plan
    F2T_STOCKPILE.applying = false
    F2T_STOCKPILE.pending = nil
    local onApplied = F2T_STOCKPILE.onApplied
    F2T_STOCKPILE.onApplied = nil
    if plan then plan.applied = true end
    local done = plan and plan.appliedCount or 0
    local total = plan and #plan.actions or 0
    if errorMessage then
        report(string.format("%s: stopped after %d of %d changes: %s",
            plan and plan.planet or "?", done, total, errorMessage), "red")
    else
        report(string.format("%s: applied %d change%s", plan.planet, done, done == 1 and "" or "s"))
    end
    if onApplied then onApplied(errorMessage == nil, errorMessage) end
end

local function sendNext()
    if not F2T_STOCKPILE.applying then return end
    local plan = F2T_STOCKPILE.plan
    F2T_STOCKPILE.applyIndex = F2T_STOCKPILE.applyIndex + 1
    local action = plan.actions[F2T_STOCKPILE.applyIndex]
    if not action then
        finishApply(nil)
        return
    end
    F2T_STOCKPILE.pending = action
    local command = commandFor(action, plan)
    f2t_debug_log("[stockpiles] sending %s", command)
    send(command, false)
    F2T_STOCKPILE.timeoutId = tempTimer(ACK_TIMEOUT, function()
        F2T_STOCKPILE.timeoutId = nil
        finishApply("no response to '" .. command .. "'")
    end)
    raiseEvent("f2tStockpileChanged")
end

--- Apply the current plan
--- @param onApplied function|nil Called with (ok, error)
--- @return boolean started
function f2tStockpileApply(onApplied)
    local problem = F2T_STOCKPILE.applying and "An update is already running" or f2tStockpilePlanProblem()
    if problem then
        report(problem, "yellow")
        if onApplied then onApplied(false, problem) end
        return false
    end
    F2T_STOCKPILE.applying = true
    F2T_STOCKPILE.applyIndex = 0
    F2T_STOCKPILE.onApplied = onApplied
    cecho(string.format("\n<green>[stockpiles]<reset> Applying %d change%s to %s...\n",
        #F2T_STOCKPILE.plan.actions, #F2T_STOCKPILE.plan.actions == 1 and "" or "s", F2T_STOCKPILE.plan.planet))
    sendNext()
    return true
end

--- Server confirmed a change; returns true when it belonged to this update
--- @param kind string "max", "min" or "spread"
function f2tStockpileOnAck(kind, commodity, value)
    local action = F2T_STOCKPILE.pending
    if not F2T_STOCKPILE.applying or not action then return false end
    if action.kind ~= kind or action.commodity:lower() ~= tostring(commodity):lower() then return false end
    stopTimeout()
    F2T_STOCKPILE.pending = nil
    if value ~= action.value then
        finishApply(string.format("server set %s %s to %d instead of %d", action.commodity, kind, value, action.value))
        return true
    end
    F2T_STOCKPILE.plan.appliedCount = F2T_STOCKPILE.plan.appliedCount + 1
    tempTimer(COMMAND_SPACING, sendNext)
    return true
end

--- Server refused a change; returns true when an update was running
function f2tStockpileOnError(message)
    if not F2T_STOCKPILE.applying then return false end
    finishApply(message)
    return true
end

function f2tStockpileCancel()
    if F2T_STOCKPILE.applying then
        finishApply("cancelled")
        return true
    end
    return false
end

-- ── Auto mode ─────────────────────────────────────────────────────────────────

local function autoStop(message, color)
    F2T_STOCKPILE.autoEnabled = false
    F2T_STOCKPILE.autoRunning = false
    if F2T_STOCKPILE.autoTimerId then
        killTimer(F2T_STOCKPILE.autoTimerId)
        F2T_STOCKPILE.autoTimerId = nil
    end
    report(message, color)
end

--- Preview and apply every target planet in turn
function f2tStockpileAutoRun()
    if F2T_STOCKPILE.autoRunning or f2tStockpileBusy() or f2t_po.phase ~= "idle" then
        f2t_debug_log("[stockpiles] auto run skipped: busy")
        return false
    end
    local targets = f2tStockpileGetList("stockpile_targets")
    if #targets == 0 then
        autoStop("Auto mode needs target planets: po stockpile target add <planet>", "red")
        return false
    end

    F2T_STOCKPILE.autoRunning = true
    local index, changes = 0, 0
    local function nextTarget()
        if not F2T_STOCKPILE.autoEnabled and not F2T_STOCKPILE.autoRunning then return end
        index = index + 1
        local planet = targets[index]
        if not planet then
            F2T_STOCKPILE.autoRunning = false
            report(string.format("Auto run done: %d planet%s checked, %d change%s applied",
                #targets, #targets == 1 and "" or "s", changes, changes == 1 and "" or "s"))
            return
        end
        f2tStockpilePreview(planet, function(plan, previewError)
            if not plan then
                autoStop("Auto mode turned off: " .. tostring(previewError), "red")
                return
            end
            if #plan.actions == 0 then
                tempTimer(1, nextTarget)
                return
            end
            f2tStockpileApply(function(ok, applyError)
                changes = changes + plan.appliedCount
                if not ok then
                    autoStop("Auto mode turned off: " .. tostring(applyError), "red")
                    return
                end
                tempTimer(1, nextTarget)
            end)
        end)
    end
    nextTarget()
    return true
end

function f2tStockpileAutoStart()
    if F2T_STOCKPILE.autoEnabled then
        report("Auto mode is already on", "yellow")
        return false
    end
    if #f2tStockpileGetList("stockpile_targets") == 0 then
        report("Auto mode needs target planets: po stockpile target add <planet>", "red")
        return false
    end
    local minutes = setting("stockpile_auto_interval")
    F2T_STOCKPILE.autoEnabled = true
    F2T_STOCKPILE.autoTimerId = tempTimer(minutes * 60, f2tStockpileAutoRun, true)
    report(string.format("Auto mode on: every %d min until you turn it off or log out", minutes))
    f2tStockpileAutoRun()
    return true
end

function f2tStockpileAutoStop()
    if not F2T_STOCKPILE.autoEnabled then return false end
    f2tStockpileCancel()
    autoStop("Auto mode off")
    return true
end

-- ── Console display ───────────────────────────────────────────────────────────

local function changeText(old, new, width)
    if old == new then return string.format("<dim_grey>%" .. width .. "s<reset>", tostring(old)) end
    -- Widths count bytes and the arrow is three
    return string.format("<yellow>%" .. (width + 2) .. "s<reset>", string.format("%s→%s", old, new))
end

function f2tStockpileShowPlan(plan)
    plan = plan or F2T_STOCKPILE.plan
    if not plan then
        cecho("\n<yellow>[stockpiles]<reset> No preview yet: po stockpile preview [planet]\n")
        return
    end
    cecho(string.format("\n<green>[stockpiles]<reset> %s%s: %d change%s planned\n\n",
        plan.planet, plan.remote and " (remote)" or "", #plan.actions, #plan.actions == 1 and "" or "s"))
    cecho(string.format("<white>%-15s %6s %7s %13s %13s %8s  %s<reset>\n",
        "Commodity", "Net", "Stock", "Min", "Max", "Spread", "Policy"))
    for _, row in ipairs(plan.rows) do
        local netColor = row.net < 0 and "red" or (row.net > 0 and "green" or "white")
        cecho(string.format("%-15s <%s>%6d<reset> %7d %s %s %s  <dim_grey>%s<reset>\n",
            row.commodity, netColor, row.net, row.stock,
            changeText(row.oldMin, row.newMin, 13), changeText(row.oldMax, row.newMax, 13),
            changeText(row.oldSpread .. "%", row.newSpread .. "%", 8), row.policy))
    end
    local problem = f2tStockpilePlanProblem(plan)
    if problem then
        cecho(string.format("\n<dim_grey>%s<reset>\n", problem))
    else
        cecho("\n<dim_grey>Type <green>po stockpile apply<dim_grey> to make these changes.<reset>\n")
    end
end

function f2tStockpileShowStatus()
    local plan = F2T_STOCKPILE.plan
    local state = F2T_STOCKPILE.applying and "applying" or (F2T_STOCKPILE.previewing and "previewing" or "idle")
    cecho(string.format("\n<green>[stockpiles]<reset> State: <white>%s<reset>   Auto: %s\n", state,
        F2T_STOCKPILE.autoEnabled and string.format("<green>on<reset> (every %d min)",
            setting("stockpile_auto_interval")) or "<dim_grey>off<reset>"))
    if plan then
        cecho(string.format("  Last preview: <white>%s<reset>, %d change%s, %s\n", plan.planet, #plan.actions,
            #plan.actions == 1 and "" or "s",
            plan.applied and string.format("%d applied", plan.appliedCount) or "not applied"))
    end
    local targets = f2tStockpileGetList("stockpile_targets")
    cecho(string.format("  Targets: %s\n", #targets > 0 and table.concat(targets, ", ") or "<dim_grey>none<reset>"))
    local excluded = f2tStockpileGetList("stockpile_excluded")
    cecho(string.format("  Excluded: %s\n", #excluded > 0 and table.concat(excluded, ", ") or "<dim_grey>none<reset>"))
    if F2T_STOCKPILE.lastMessage then
        cecho(string.format("  <dim_grey>%s<reset>\n", F2T_STOCKPILE.lastMessage))
    end
end

registerAnonymousEventHandler("sysDisconnectionEvent", function()
    if F2T_STOCKPILE.applying then finishApply("disconnected") end
    if F2T_STOCKPILE.autoEnabled then autoStop("Auto mode off: disconnected", "yellow") end
end)

f2t_debug_log("[po] Stockpile manager loaded")
