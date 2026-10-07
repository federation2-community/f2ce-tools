-- Stamina monitor: when stamina falls to the threshold, walks to a bar, eats
-- until full and walks back, pausing and resuming whatever automation
-- (hauling, exploring) registered itself as the client.

-- What each sustenance buys, per the server (Player::BuyFood/BuyPizza/BuyRound).
-- All three only work in a bar-flagged room. Pizza and round also feed
-- everyone else in the room, at the same price per head.
F2T_STAMINA_FOOD_TYPES = {
    food  = { command = "buy food",  gain = 5, icon = "🍴",
              desc = "a slice of pizza for you: +5 stamina for 10ig" },
    pizza = { command = "buy pizza", gain = 5, icon = "🍕",
              desc = "pizza for the whole room: +5 stamina each, 10ig a head" },
    round = { command = "buy round", gain = 2, icon = "🍺",
              desc = "ale for the whole room: +2 stamina each, 5ig a head" },
}
F2T_STAMINA_FOOD_ORDER = { "food", "pizza", "round" }

-- Used when the food source is "nearest" and no mapped bar is reachable.
F2T_STAMINA_FALLBACK_SOURCE = "Sol.Earth.454"

F2T_STAMINA_DISMISS_COOLDOWN = 300
F2T_STAMINA_PROMPT_TIMEOUT   = 30
-- Polls are 0.5s: ask for an immediate pause at 60s, give up at 120s.
local WAIT_IMMEDIATE_POLLS = 120
local WAIT_GIVE_UP_POLLS   = 240
-- A buy whose stamina change hasn't shown up by then counts as having failed.
local BUY_TIMEOUT          = 3
local MAX_BUYS_WITHOUT_GAIN = 2

local PHASE_TEXT = {
    idle      = "idle",
    waiting   = "waiting for activity to pause",
    toFood    = "walking to the bar",
    eating    = "eating",
    returning = "walking back",
}

-- Replace any previous load's state: its handlers would call functions that
-- no longer exist, and a phase left over from it would block every new trip.
do
    local previous = F2T_STAMINA_STATE
    if previous then
        for _, key in ipairs({ "gmcp_handler_id", "nav_handler_id", "vitalsHandlerId", "walkHandlerId" }) do
            if previous[key] then killAnonymousEventHandler(previous[key]) end
        end
        for _, aliasId in ipairs(previous.standalone_prompt_aliases or (previous.prompt or {}).aliases or {}) do
            killAlias(aliasId)
        end
        local promptTimer = previous.standalone_prompt_timer or (previous.prompt or {}).timer
        if promptTimer then killTimer(promptTimer) end
    end

    local client = previous and previous.client
    if not client and previous and previous.client_check_active then
        client = {
            pause    = previous.client_pause_callback,
            resume   = previous.client_resume_callback,
            isActive = previous.client_check_active,
        }
    end

    F2T_STAMINA_STATE = {
        phase           = "idle",
        client          = client,
        clientPaused    = false,
        manual          = false,
        returnRoom      = nil,
        destinationName = nil,
        failure         = nil,
        waitPolls       = 0,
        buys            = 0,
        buysWithoutGain = 0,
        lastStamina     = nil,
        buyTimer        = nil,
        prompt          = { active = false, aliases = {}, timer = nil, dismissedAt = nil },
    }
end

local state = F2T_STAMINA_STATE

-- Readings

local function readStamina()
    local vitals = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.stamina
    local current = vitals and tonumber(vitals.cur)
    local maximum = vitals and tonumber(vitals.max)
    if not current or not maximum or maximum <= 0 then return nil end
    return current, maximum, math.floor(current / maximum * 100)
end

local function threshold()
    return tonumber(f2t_settings_get("stamina", "threshold")) or 0
end

function f2tStaminaFoodType()
    local key = string.lower(f2t_settings_get("stamina", "sustenance") or "food")
    if not F2T_STAMINA_FOOD_TYPES[key] then key = "food" end
    return key, F2T_STAMINA_FOOD_TYPES[key]
end

local function atBar()
    local info = gmcp.room and gmcp.room.info
    if info and info.flags and f2t_has_value(info.flags, "bar") then return true end
    return f2t_map_room_has_flag ~= nil and f2t_map_room_has_flag(F2T_MAP_CURRENT_ROOM_ID, "bar")
end

local function clientActive()
    return state.client ~= nil and state.client.isActive() == true
end

function f2tStaminaTripActive()
    return state.phase ~= "idle"
end

function f2tStaminaPhaseText()
    return PHASE_TEXT[state.phase] or state.phase
end

local function setPhase(phase)
    f2t_debug_log("[stamina] Phase: %s -> %s", state.phase, phase)
    state.phase = phase
    raiseEvent("f2tStaminaChanged", phase)
end

-- The closest mapped bar by walking steps, or nil when none is reachable.
function f2tStaminaNearestBar(fromRoom)
    return f2t_map_nearest_room_with_flag("bar", fromRoom)
end

-- Destination string for f2t_map_navigate plus a name to show the player.
function f2tStaminaResolveFoodSource()
    local setting = f2t_settings_get("stamina", "food_source") or "nearest"
    if setting ~= "" and string.lower(setting) ~= "nearest" then
        return setting, setting
    end
    local roomId = f2tStaminaNearestBar()
    if roomId then
        return tostring(roomId), getRoomName(roomId) or ("room " .. roomId)
    end
    return F2T_STAMINA_FALLBACK_SOURCE, "the Starship Cantina on Earth (no closer bar mapped)"
end

-- Standalone prompt

function f2t_stamina_cancel_standalone_prompt()
    local prompt = state.prompt
    if not prompt.active then return end
    prompt.active = false
    for _, aliasId in ipairs(prompt.aliases) do killAlias(aliasId) end
    prompt.aliases = {}
    if prompt.timer then killTimer(prompt.timer); prompt.timer = nil end
end

local function dismissPrompt(message)
    f2t_stamina_cancel_standalone_prompt()
    state.prompt.dismissedAt = os.time()
    cecho(string.format("\n<dim_grey>[stamina]<reset> %s Will remind again in 5 minutes.\n", message))
end

local function showPrompt(percent)
    local prompt = state.prompt
    if prompt.active then return end
    if prompt.dismissedAt and os.time() - prompt.dismissedAt < F2T_STAMINA_DISMISS_COOLDOWN then return end

    prompt.active = true
    cecho(string.format("\n<yellow>[stamina]<reset> Low stamina: <red>%d%%<reset> (threshold %d%%). "
        .. "Go eat? Type <green>yes<reset> or <red>no<reset>, or ", percent, threshold()))
    cechoLink("<green>[go eat]<reset>", function()
        if state.prompt.active then f2t_stamina_cancel_standalone_prompt(); f2tStaminaEat() end
    end, "Walk to a bar, eat until full and come back", true)
    echo("\n")

    prompt.aliases = {
        tempAlias("^yes$", function() f2t_stamina_cancel_standalone_prompt(); f2tStaminaEat() end),
        tempAlias("^no$", function() dismissPrompt("Dismissed.") end),
    }
    prompt.timer = tempTimer(F2T_STAMINA_PROMPT_TIMEOUT, function()
        state.prompt.timer = nil
        if state.prompt.active then dismissPrompt("No answer.") end
    end)
end

-- Trip

local function takeNavOwnership()
    if f2t_map_clear_nav_owner then f2t_map_clear_nav_owner() end
    if f2t_map_set_nav_owner then
        f2t_map_set_nav_owner("stamina", function(reason)
            f2t_debug_log("[stamina] Navigation interrupted by %s", reason)
            return { auto_resume = true }
        end)
    end
end

local function killBuyTimer()
    if state.buyTimer then killTimer(state.buyTimer); state.buyTimer = nil end
end

local function resetTrip()
    killBuyTimer()
    state.returnRoom, state.destinationName, state.failure = nil, nil, nil
    state.waitPolls, state.buys, state.buysWithoutGain, state.lastStamina = 0, 0, 0, nil
    state.manual = false
    setPhase("idle")
end

local function resumeClient()
    if state.clientPaused and state.client then
        state.clientPaused = false
        state.client.resume()
    end
    state.clientPaused = false
end

-- Ends the trip. On failure the client stays paused while stamina is at or
-- below the threshold, since resuming would walk it into starvation.
local function endTrip(failure)
    if f2t_map_clear_nav_owner then f2t_map_clear_nav_owner() end
    local wasPaused = state.clientPaused
    resetTrip()

    if not failure then
        cecho("\n<green>[stamina]<reset> Stamina restored\n")
        resumeClient()
        return
    end

    local _, _, percent = readStamina()
    local safe = threshold() <= 0 or (percent and percent > threshold())
    cecho(string.format("\n<red>[stamina]<reset> Food run failed: %s\n", failure))
    state.prompt.dismissedAt = os.time()
    if wasPaused and safe then
        resumeClient()
    elseif wasPaused then
        cecho("<yellow>[stamina]<reset> Activity stays paused so you don't starve. "
            .. "Check <white>stamina<reset> for the food source, then resume it.\n")
    end
end

-- Ends the trip once back, reporting any failure that sent us back early.
local function finishTrip()
    endTrip(state.failure)
end

local function goBack()
    local here = F2T_MAP_CURRENT_ROOM_ID
    if not state.returnRoom or state.returnRoom == here or not roomExists(state.returnRoom) then
        finishTrip()
        return
    end
    setPhase("returning")
    takeNavOwnership()
    cecho("\n<cyan>[stamina]<reset> Returning to where you were\n")
    f2t_map_navigate(tostring(state.returnRoom), {
        suppress_hint = true,
        on_result = function(ok, status)
            if state.phase ~= "returning" then return end
            if not ok then
                cecho("\n<yellow>[stamina]<reset> No way back from here; carrying on from this room\n")
                finishTrip()
            elseif status == "arrived" then
                finishTrip()
            end
        end,
    })
end

local function abortTrip(failure)
    f2t_debug_log("[stamina] Aborting food run: %s", failure)
    killBuyTimer()
    state.failure = failure
    if state.phase ~= "returning" then
        goBack()
    else
        finishTrip()
    end
end

local function eatStep()
    killBuyTimer()
    if state.phase ~= "eating" then return end

    local current, maximum = readStamina()
    if not current then
        abortTrip("no stamina reading from the game")
        return
    end
    if current >= maximum then
        goBack()
        return
    end

    if state.buys > 0 then
        if current > (state.lastStamina or current) then
            state.buysWithoutGain = 0
        else
            state.buysWithoutGain = state.buysWithoutGain + 1
            if state.buysWithoutGain >= MAX_BUYS_WITHOUT_GAIN then
                abortTrip("buying isn't raising stamina (out of groats?)")
                return
            end
        end
    end

    local _, food = f2tStaminaFoodType()
    state.lastStamina = current
    state.buys = state.buys + 1
    f2t_debug_log("[stamina] %s (%d/%d, buy %d)", food.command, current, maximum, state.buys)
    send(food.command, false)
    state.buyTimer = tempTimer(BUY_TIMEOUT, function()
        state.buyTimer = nil
        eatStep()
    end)
end

local function startEating()
    if not atBar() then
        abortTrip(string.format("%s is not a bar", state.destinationName or "this room"))
        return
    end
    local key = f2tStaminaFoodType()
    cecho(string.format("\n<cyan>[stamina]<reset> Eating (%s)\n", key))
    state.buys, state.buysWithoutGain, state.lastStamina = 0, 0, nil
    setPhase("eating")
    eatStep()
end

local function travel()
    if atBar() then
        state.destinationName = getRoomName(F2T_MAP_CURRENT_ROOM_ID or -1) or "this bar"
        startEating()
        return
    end

    state.returnRoom = F2T_MAP_CURRENT_ROOM_ID
    local destination, name = f2tStaminaResolveFoodSource()
    state.destinationName = name
    setPhase("toFood")
    takeNavOwnership()
    cecho(string.format("\n<cyan>[stamina]<reset> Heading to <white>%s<reset> to eat\n", name))
    f2t_map_navigate(destination, {
        suppress_hint = true,
        on_result = function(ok, status)
            if state.phase ~= "toFood" then return end
            if not ok then
                abortTrip(string.format("no route to %s", name))
            elseif status == "arrived" then
                startEating()
            end
        end,
    })
end

local function waitForClient()
    if state.phase ~= "waiting" then return end
    if not state.client then
        cecho("\n<yellow>[stamina]<reset> Activity stopped, cancelling food run\n")
        state.clientPaused = false
        resetTrip()
        return
    end
    if not clientActive() then
        travel()
        return
    end

    state.waitPolls = state.waitPolls + 1
    if state.waitPolls == WAIT_IMMEDIATE_POLLS then
        cecho("\n<yellow>[stamina]<reset> Still waiting for activity to pause; pausing it now\n")
        state.client.pause(true)
    elseif state.waitPolls >= WAIT_GIVE_UP_POLLS then
        endTrip("activity never paused")
        return
    end
    tempTimer(0.5, waitForClient)
end

-- Starts a food run. manual is true for the Eat button and `stamina eat`.
function f2tStaminaStartTrip(manual)
    if state.phase ~= "idle" then return false end
    if not f2t_map_navigate then
        cecho("\n<red>[stamina]<reset> The map component isn't loaded, so there's no way to walk to a bar\n")
        return false
    end
    f2t_stamina_cancel_standalone_prompt()
    state.manual = manual == true

    if clientActive() then
        state.clientPaused = true
        state.waitPolls = 0
        setPhase("waiting")
        state.client.pause()
        waitForClient()
    else
        travel()
    end
    return true
end

function f2tStaminaEat()
    if state.phase ~= "idle" then
        cecho(string.format("\n<yellow>[stamina]<reset> A food run is already under way (%s)\n", f2tStaminaPhaseText()))
        return false
    end
    local current, maximum = readStamina()
    if current and current >= maximum then
        cecho("\n<green>[stamina]<reset> Stamina is already full\n")
        return false
    end
    return f2tStaminaStartTrip(true)
end

-- Stops a food run where it stands. A paused client stays paused.
function f2tStaminaCancelTrip(quiet)
    if state.phase == "idle" then return false end
    local walking = state.phase == "toFood" or state.phase == "returning"
    if walking and F2T_SPEEDWALK_ACTIVE and f2t_map_speedwalk_stop then f2t_map_speedwalk_stop() end
    if f2t_map_clear_nav_owner then f2t_map_clear_nav_owner() end
    local wasPaused = state.clientPaused
    state.clientPaused = false
    resetTrip()
    if not quiet then
        cecho("\n<yellow>[stamina]<reset> Food run cancelled\n")
        if wasPaused then cecho("<dim_grey>  The paused activity stays paused; resume it when ready<reset>\n") end
    end
    return true
end

-- Low-stamina check, run on every vitals push and when a client registers.
function f2tStaminaCheck()
    if state.phase ~= "idle" then return end
    local limit = threshold()
    if limit <= 0 then return end
    local current, _, percent = readStamina()
    -- 0 or below is death or room damage; there's nothing to eat our way out of.
    if not current or current <= 0 or percent > limit then return end

    if clientActive() then
        cecho(string.format("\n<yellow>[stamina]<reset> Low stamina: %d%% (threshold %d%%)\n", percent, limit))
        f2tStaminaStartTrip(false)
    elseif f2t_settings_get("stamina", "unattended") then
        local dismissedAt = state.prompt.dismissedAt
        if dismissedAt and os.time() - dismissedAt < F2T_STAMINA_DISMISS_COOLDOWN then return end
        cecho(string.format("\n<yellow>[stamina]<reset> Low stamina: %d%% (threshold %d%%)\n", percent, limit))
        f2tStaminaStartTrip(false)
    else
        showPrompt(percent)
    end
end

-- Client registration

-- config: {pause_callback(immediate), resume_callback(), check_active() -> boolean}
function f2t_stamina_register_client(config)
    if not config or not config.pause_callback or not config.resume_callback or not config.check_active then
        cecho("\n<red>[stamina]<reset> Invalid client registration: missing required callbacks\n")
        return false
    end
    state.client = {
        pause    = config.pause_callback,
        resume   = config.resume_callback,
        isActive = config.check_active,
    }
    f2t_debug_log("[stamina] Client registered")
    -- Stamina may already be low; don't wait for the next drop to notice.
    tempTimer(0.5, f2tStaminaCheck)
    return true
end

function f2t_stamina_unregister_client()
    state.client = nil
    f2t_debug_log("[stamina] Client unregistered")
end

-- Event handlers

local function onVitals()
    if state.phase == "eating" then
        local current = readStamina()
        if state.buyTimer and current and current ~= state.lastStamina then
            killBuyTimer()
            tempTimer(0.1, eatStep)
        end
        return
    end
    tempTimer(0.1, f2tStaminaCheck)
end

-- A walk ended. A customs stop or a recompute leg is still under way when
-- either flag below is set, and finishes with its own event.
local function onWalkFinished(_, result)
    if state.phase ~= "toFood" and state.phase ~= "returning" then return end
    if F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_CUSTOMS_PENDING then return end

    if result == "stopped" then
        f2tStaminaCancelTrip()
    elseif state.phase == "toFood" then
        if result == "completed" then
            startEating()
        else
            abortTrip(string.format("couldn't reach %s (%s)", state.destinationName or "the bar", tostring(result)))
        end
    else
        finishTrip()
    end
end

state.vitalsHandlerId = registerAnonymousEventHandler("gmcp.char.vitals", onVitals)
state.walkHandlerId   = registerAnonymousEventHandler("f2tSpeedwalkFinished", onWalkFinished)

f2t_debug_log("[stamina] Stamina monitor initialized")
