-- Insurance: whether the player is insured, getting them insured, and the
-- check that stands between an uninsured player and anything risky. An
-- uninsured death is permanent, so exploration (every kind, see
-- f2t_map_explore_next_step) and resuming work after a death go through here.
--
-- GMCP char.vitals.insured is the source. Servers without it fall back on the
-- game's own text (insure replies, score, the login and wake-up warnings),
-- read by the insured/uninsured triggers.
-- Raises "f2tInsuranceChanged" (insured) when the status changes.

F2T_INSURANCE = F2T_INSURANCE or {}
F2T_INSURANCE.insured = nil       -- true, false, or nil while unknown
F2T_INSURANCE.riskAccepted = false -- "Go anyway" chosen while uninsured

-- Earth's Emergency Ward, where an insured death in Sol wakes up; it sells insurance.
local FALLBACK_BROKER = "Sol.Earth.1433"
local REPLY_WAIT = 4

local function setStatus(insured)
    if insured then F2T_INSURANCE.riskAccepted = false end
    if F2T_INSURANCE.insured == insured then return end
    F2T_INSURANCE.insured = insured
    f2t_debug_log("[insurance] %s", insured and "insured" or "not insured")
    raiseEvent("f2tInsuranceChanged", insured)
end

--- Record insurance status read from game text (insured/uninsured triggers)
--- @param insured boolean
function f2t_insurance_note(insured)
    setStatus(insured)
end

--- @return boolean|nil insured, nil while unknown
function f2t_insurance_status()
    return F2T_INSURANCE.insured
end

registerAnonymousEventHandler("gmcp.char.vitals", function()
    local value = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.insured
    if value ~= nil then setStatus(value == true or value == "true") end
end)

registerAnonymousEventHandler("f2tCharacterChanged", function()
    F2T_INSURANCE.insured = nil
    F2T_INSURANCE.riskAccepted = false
end)

-- A death always spends the insurance (the server clears it on waking).
registerAnonymousEventHandler("f2tDeathDetected", function()
    F2T_INSURANCE.riskAccepted = false
    setStatus(false)
end)

-- Run onSettled(insured) once the status is known, asking the game via score
-- when it isn't. Still unknown after the wait counts as not insured.
local scoreAsked = false
local function whenKnown(onSettled)
    if F2T_INSURANCE.insured ~= nil then onSettled(F2T_INSURANCE.insured) return end
    local handlerId, timerId
    local function settle()
        if not handlerId then return end
        killAnonymousEventHandler(handlerId)
        killTimer(timerId)
        handlerId, timerId = nil, nil
        scoreAsked = false
        onSettled(F2T_INSURANCE.insured == true)
    end
    handlerId = registerAnonymousEventHandler("f2tInsuranceChanged", settle)
    timerId = tempTimer(REPLY_WAIT, settle)
    if not scoreAsked then
        scoreAsked = true
        send("score", false)
    end
end

local function atBroker()
    local info = gmcp and gmcp.room and gmcp.room.info
    if info and info.flags and f2t_has_value(info.flags, "insure") then return true end
    return F2T_MAP_CURRENT_ROOM_ID ~= nil and f2t_map_room_has_flag(F2T_MAP_CURRENT_ROOM_ID, "insure")
end

local function buyHere(onDone)
    local handlerId, timerId, failId
    local function finish(ok)
        if handlerId then killAnonymousEventHandler(handlerId) end
        if timerId then killTimer(timerId) end
        if failId then killTrigger(failId) end
        handlerId, timerId, failId = nil, nil, nil
        if onDone then onDone(ok) end
    end
    handlerId = registerAnonymousEventHandler("f2tInsuranceChanged", function(_, insured)
        if insured then finish(true) end
    end)
    failId = tempTrigger("cash to reinsure yourself", function()
        cecho("\n<red>[insurance]<reset> Not enough cash to insure. Earn some before taking risks.\n")
        finish(false)
    end)
    timerId = tempTimer(REPLY_WAIT, function() finish(F2T_INSURANCE.insured == true) end)
    send("insure")
end

--- Get insured: buy it here at a broker, or walk to the nearest mapped broker
--- (Earth's Emergency Ward when none is mapped) and buy it there
--- @param onDone function|nil onDone(insured)
function f2t_insurance_get_insured(onDone)
    if F2T_INSURANCE.insured == true then
        if onDone then onDone(true) end
        return
    end
    if atBroker() then
        buyHere(onDone)
        return
    end
    local broker = f2t_map_nearest_room_with_flag("insure")
    local destination = broker or FALLBACK_BROKER
    cecho(string.format("\n<cyan>[insurance]<reset> Heading to %s to insure\n",
        broker and (getRoomName(broker) or "the nearest broker") or "Earth's Emergency Ward"))
    f2tNav.go(destination, { owner = "insurance", onDone = function(result)
        if result.status == "arrived" and atBroker() then
            buyHere(onDone)
        else
            cecho("\n<red>[insurance]<reset> Couldn't reach an insurance broker; insure by hand.\n")
            if onDone then onDone(false) end
        end
    end })
end

-- ── The check ────────────────────────────────────────────────────────────────

-- One warning at a time; checks that arrive while it is open share its answer.
local waiting = nil

local function answer(choice)
    local callers = waiting or {}
    waiting = nil
    if choice == "anyway" then
        F2T_INSURANCE.riskAccepted = true
        cecho("\n<red>[insurance]<reset> Going on uninsured. Another death would be permanent.\n")
        for _, caller in ipairs(callers) do caller.onAllowed() end
    elseif choice == "insure" then
        f2t_insurance_get_insured(function(insured)
            for _, caller in ipairs(callers) do
                if insured then caller.onAllowed() elseif caller.onCancel then caller.onCancel() end
            end
        end)
    else
        for _, caller in ipairs(callers) do
            if caller.onCancel then caller.onCancel() end
        end
    end
end

local function showWarning(what)
    if f2tShowInsuranceConfirm and Mux and Mux.createDialog then
        f2tShowInsuranceConfirm(what, answer)
        return
    end
    cecho(string.format("\n<red>[insurance]<reset> You aren't insured, and %s could kill you for good. ", what))
    cechoLink("<cyan>[Get insured]<reset>", function() answer("insure") end,
        "Walk to the nearest broker and insure", true)
    cecho(" ")
    cechoLink("<yellow>[Go anyway]<reset>", function() answer("anyway") end, "Carry on uninsured", true)
    cecho(" ")
    cechoLink("<grey>[Cancel]<reset>", function() answer("cancel") end, "Don't do it", true)
    cecho("\n")
end

--- Allow something risky only while insured, or once the player has chosen to
--- go on uninsured; otherwise warn and let them insure, go anyway or cancel
--- @param what string what is about to happen, e.g. "exploring"
--- @param onAllowed function
--- @param onCancel function|nil
function f2t_insurance_check(what, onAllowed, onCancel)
    whenKnown(function(insured)
        if insured or F2T_INSURANCE.riskAccepted then
            onAllowed()
            return
        end
        local first = waiting == nil
        waiting = waiting or {}
        table.insert(waiting, { onAllowed = onAllowed, onCancel = onCancel })
        if first then showWarning(what) end
    end)
end

--- Whether risky things may go ahead right now without asking
--- @return boolean
function f2t_insurance_allows()
    return F2T_INSURANCE.insured == true or F2T_INSURANCE.riskAccepted
end

f2t_debug_log("[insurance] module loaded")
