-- Akaturi hauling: take a contract at an AC office, then work its pickup and
-- dropoff through the shared room finder (akaturi_finder.lua). The game's own
-- contract (akaturi_tracker.lua) says where each leg is, so every phase starts
-- from the contract as it stands: one taken, picked up or dropped off by hand
-- carries on from there. Needs no UI.
--
-- Phases: akaturi_getting_job -> akaturi_reading_contract -> akaturi_working_pickup
-- -> akaturi_working_dropoff -> akaturi_getting_job. All of them resume through
-- f2t_hauling_phase_akaturi_get_job.

local CONTRACT_WAIT = 6
local MAX_TAKE_ATTEMPTS = 3

local function running(phase)
    local state = F2T_HAULING_STATE
    return state.active and not state.paused and (phase == nil or state.current_phase == phase)
end

local function setPhase(phase)
    F2T_HAULING_STATE.current_phase = phase
    raiseEvent("f2tHaulingStatusChanged")
end

-- Re-enter the loop after a wait, if nothing moved it on meanwhile.
local function retryAfter(seconds, phase)
    tempTimer(seconds, function()
        if running(phase) then
            setPhase("akaturi_getting_job")
            f2t_hauling_phase_akaturi_get_job()
        end
    end)
end

local function promotionAdvice(cash)
    local short = F2T_AKATURI_PROMOTE_CASH - cash
    if short > 0 then
        return string.format("Promote to Merchant once you have %s ig more in the bank", f2t_format_number(short))
    end
    return "Promote to Merchant at the Trading Guild on Earth"
end

-- A run started below the promotion mark stops on reaching it. Started at or
-- past it, the player wants more contracts (they keep paying and earning
-- credits), so it carries on until more pay would only be taxed.
local function checkPromotion()
    local state = F2T_HAULING_STATE
    local points = f2t_akaturi_get_points()
    if not points or points < F2T_AKATURI_PROMOTE_AT then return false end
    local cash = f2t_ac_get_cash() or 0

    if (state.akaturi_start_points or 0) < F2T_AKATURI_PROMOTE_AT then
        cecho(string.format("\n<green>[hauling]<reset> %d Akaturi credits reached; stopping. %s. " ..
            "'haul start' again keeps doing contracts.\n", points, promotionAdvice(cash)))
        return true
    end
    if cash >= F2T_AKATURI_CASH_CAP then
        cecho(string.format("\n<green>[hauling]<reset> %s ig: an Adventurer's cash over %s ig is taxed at " ..
            "the next login, so stopping here. %s.\n",
            f2t_format_number(cash), f2t_format_number(F2T_AKATURI_CASH_CAP), promotionAdvice(cash)))
        return true
    end
    if not state.akaturi_promotion_noted then
        state.akaturi_promotion_noted = true
        cecho(string.format("\n<green>[hauling]<reset> Already at %d Akaturi credits; doing more contracts " ..
            "until 'haul stop'. %s.\n", points, promotionAdvice(cash)))
    end
    return false
end

local function onLegDone(phase, kind, payment, outcome)
    if not running(phase) then return end
    local state = F2T_HAULING_STATE

    if outcome == "done" then
        if kind == "pickup" then
            f2t_hauling_transition("akaturi_getting_job")
            return
        end
        state.total_cycles = (state.total_cycles or 0) + 1
        state.session_profit = (state.session_profit or 0) + payment
        table.insert(state.commodity_history, { commodity = "Akaturi contract", cycles = 1, profit = payment })
        cecho(string.format("\n<green>[hauling]<reset> Contract complete: %s ig (%d Akaturi credits)\n",
            f2t_format_number(payment), f2t_akaturi_get_points() or 0))
        if state.stopping or checkPromotion() then
            f2t_hauling_do_stop()
            return
        end
        f2t_hauling_transition("akaturi_getting_job")
    elseif outcome == "stopped" then
        cecho("\n<yellow>[hauling]<reset> The room search was stopped, so hauling stops too\n")
        f2t_hauling_stop()
    else
        if outcome == "notFound" then
            cecho("\n<yellow>[hauling]<reset> Find the room by hand, then 'haul resume' there " ..
                "(or pickup/dropoff yourself and resume).\n")
        end
        f2t_hauling_pause(true)
    end
end

--- Work the contract the player holds from the leg it is on
--- @param held table Contract from f2t_akaturi_contract()
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_akaturi_work_held(held)
    local state = F2T_HAULING_STATE
    local kind, planet, room = f2t_akaturi_leg(held)

    if not room then
        -- The room text follows the GMCP update, so wait for it before asking.
        state.akaturi_room_waits = (state.akaturi_room_waits or 0) + 1
        if state.akaturi_room_waits > 2 then
            cecho("\n<red>[hauling]<reset> Couldn't read the contract's room from 'di ak'; stopping.\n")
            f2t_hauling_stop()
            return true
        end
        if state.akaturi_room_waits == 2 then send("di ak", false) end
        setPhase("akaturi_reading_contract")
        retryAfter(CONTRACT_WAIT, "akaturi_reading_contract")
        return false
    end
    state.akaturi_room_waits = 0

    local phase = kind == "pickup" and "akaturi_working_pickup" or "akaturi_working_dropoff"
    setPhase(phase)
    if kind == "pickup" then
        cecho(string.format("\n<green>[hauling]<reset> Pick up the package from '%s' on %s\n", room, planet))
    else
        cecho(string.format("\n<green>[hauling]<reset> Deliver the %s to '%s' on %s\n",
            held.package or "package", room, planet))
    end
    local payment = held.payment or 0
    f2t_akaturi_visit(kind, {
        planet = planet, room = room, owner = "hauling",
        onDone = function(outcome) onLegDone(phase, kind, payment, outcome) end,
    })
    return false
end

--- Phase: hold a contract, taking one at an AC office when there isn't one
--- @return boolean True if phase complete, false if waiting
function f2t_hauling_phase_akaturi_get_job()
    local state = F2T_HAULING_STATE
    if not state.active or state.paused then return false end

    -- Deferred pause lands between contracts
    if state.pause_requested then
        state.pause_requested = false
        state.paused = true
        setPhase("akaturi_getting_job")
        cecho("\n<green>[hauling]<reset> Paused between Akaturi contracts\n")
        return false
    end

    local held = f2t_akaturi_contract()
    if held then
        state.akaturi_take_attempts = 0
        return f2t_hauling_akaturi_work_held(held)
    end

    if not f2t_akaturi_rank_ok() then
        cecho("\n<red>[hauling]<reset> Akaturi contracts are only for Adventurers; stopping.\n")
        f2t_hauling_stop()
        return true
    end
    if checkPromotion() then
        f2t_hauling_stop()
        return true
    end

    if not f2t_akaturi_at_office() then
        f2t_akaturi_go_to_office(function(ok)
            if not running("akaturi_getting_job") then return end
            if ok then
                f2t_hauling_phase_akaturi_get_job()
            else
                cecho("\n<red>[hauling]<reset> Couldn't reach an Armstrong Cuthbert office; stopping.\n")
                f2t_hauling_stop()
            end
        end)
        return false
    end

    state.akaturi_take_attempts = (state.akaturi_take_attempts or 0) + 1
    if state.akaturi_take_attempts > MAX_TAKE_ATTEMPTS then
        cecho("\n<red>[hauling]<reset> The office isn't handing out contracts; stopping.\n")
        f2t_hauling_stop()
        return true
    end
    send("ak")
    cecho("\n<cyan>[hauling]<reset> Requesting an Akaturi contract...\n")
    setPhase("akaturi_reading_contract")
    retryAfter(CONTRACT_WAIT, "akaturi_reading_contract")
    return false
end

-- ========================================
-- Akaturi Event Handlers
-- ========================================

--- Move on as soon as the contract (or its room) is known
--- @return number Event handler ID
function f2t_akaturi_register_handlers()
    F2T_HAULING_STATE.akaturi_promotion_noted = false
    F2T_HAULING_STATE.akaturi_start_points = f2t_akaturi_get_points() or 0
    F2T_HAULING_STATE.akaturi_take_attempts = 0
    F2T_HAULING_STATE.akaturi_room_waits = 0
    return registerAnonymousEventHandler("f2tAkaturiContractChanged", function()
        if not running("akaturi_reading_contract") then return end
        local held = f2t_akaturi_contract()
        if not held then return end
        local _, _, room = f2t_akaturi_leg(held)
        if room then
            setPhase("akaturi_getting_job")
            f2t_hauling_phase_akaturi_get_job()
        end
    end)
end

-- Death recovery paused the run (f2t_hauling_on_death); carry on once it
-- reports the player insured again, from the hospital, contract in hand.
registerAnonymousEventHandler("f2tDeathRecovered", function(_, insured)
    local state = F2T_HAULING_STATE
    if not (state.active and state.paused and state.paused_for_death and state.mode == "akaturi") then return end
    local reason = f2t_akaturi_death_hold_reason(insured)
    if reason then
        cecho(string.format("\n<yellow>[hauling]<reset> Staying paused after the death: %s. " ..
            "'haul resume' carries on.\n", reason))
        return
    end
    cecho("\n<green>[hauling]<reset> Insured again; carrying on with the contract\n")
    f2t_hauling_resume()
end)

--- Cleanup Akaturi event handlers
--- @param handlerId number Event handler ID to kill
function f2t_akaturi_cleanup_handlers(handlerId)
    if handlerId then killAnonymousEventHandler(handlerId) end
    if f2t_akaturi_visit_cancel then f2t_akaturi_visit_cancel("hauling") end
end

f2t_debug_log("[hauling/akaturi] Akaturi phases module loaded")
