-- f2ce-tools map — opportunistic refuelling during exploration
--
-- Space moves burn fuel and a system sweep makes a lot of them, so a large
-- system can run the tank dry mid-run. The emergency trigger then buys in
-- space, which is the most expensive fuel in the game - automation should not
-- put a player there.
--
-- Landing is what makes fuel cheap, and the refuel module already buys on its
-- own the moment it sees a shuttlepad with fuel at or below its threshold
-- (f2t_refuel_on_room_change). So this module never buys anything itself: it
-- only arranges to be standing somewhere the existing rule fires - board down
-- from an orbit room, let refuel do its job, board back up, resume the sweep.
--
-- Takes over the explorer for those few moves the same way explore_escape.lua
-- does: a phase checked at the top of f2t_map_explore_on_room_change, so the
-- landing pad never enters a space sweep's visited rooms or frontier.

-- Enough of a wait for "buy fuel" to be sent and answered before we leave.
local PURCHASE_WAIT = 2.0
-- A sweep that keeps detouring is worse than one that runs out; each planet
-- is tried once, and the run as a whole gets a ceiling.
local MAX_DETOURS_PER_RUN = 6

-- Fuel as a percentage, or nil when the ship isn't reporting any.
function f2t_map_explore_fuel_percent()
    local fuel = gmcp.char and gmcp.char.ship and gmcp.char.ship.fuel
    if not fuel or not fuel.cur or not fuel.max or fuel.max <= 0 then return nil end
    return math.floor((fuel.cur / fuel.max) * 100 + 0.5)
end

-- One knob, honoured everywhere: the detour only happens when the refuel
-- module would itself buy on arrival, so turning refuel off turns this off.
function f2t_map_explore_refuel_wanted()
    if not f2t_settings_get("refuel", "enabled") then return false end
    local threshold = f2t_settings_get("refuel", "threshold") or 0
    if threshold <= 0 then return false end
    local percent = f2t_map_explore_fuel_percent()
    return percent ~= nil and percent <= threshold
end

-- The room a "board" special exit from here leads to, if any. Orbit rooms
-- carry one down to their planet's landing pad (wired by exit.lua from the
-- GMCP board/orbit hash), which is exactly where fuel is cheap.
local function boardDestination(room_id)
    if not room_id or not roomExists(room_id) then return nil end
    for dest_room_id, commands in pairs(getSpecialExits(room_id) or {}) do
        if type(commands) == "table" and roomExists(dest_room_id) then
            for command in pairs(commands) do
                if type(command) == "string" and string.lower(command) == "board" then
                    return dest_room_id
                end
            end
        end
    end
    return nil
end

-- Called by the explorer before it picks its next move. Returns true when a
-- detour has been started and the caller should stand down.
function f2t_map_explore_refuel_maybe_start()
    local state = F2T_MAP_EXPLORE_STATE
    if not state.active or state.refuel_state then return false end
    if not f2t_map_explore_refuel_wanted() then return false end

    state.refuel_declined = state.refuel_declined or {}
    state.refuel_detours  = state.refuel_detours or 0
    if state.refuel_detours >= MAX_DETOURS_PER_RUN then return false end

    local orbit_room = F2T_MAP_CURRENT_ROOM_ID
    -- Already on a pad: the refuel module handles this arrival itself, and
    -- "board" from here would take us up rather than down.
    if f2t_map_room_has_flag(orbit_room, "shuttlepad") then return false end

    local pad_room = boardDestination(orbit_room)
    if not pad_room then return false end
    -- "board" is the command in both directions, so only follow it when it
    -- leads somewhere fuel is actually sold.
    if not f2t_map_room_has_flag(pad_room, "shuttlepad") then return false end
    if state.refuel_declined[pad_room] then return false end

    state.refuel_detours = state.refuel_detours + 1
    state.refuel_state = {
        orbit_room = orbit_room,
        pad_room   = pad_room,
        phase      = "descending",
        fuel_before = f2t_map_explore_fuel_percent(),
        resume_phase = state.phase,
    }
    state.phase = "refuelling"
    cecho(string.format(
        "\n<cyan>[map-explore]<reset> Fuel at %d%% - landing to refuel before carrying on\n",
        state.refuel_state.fuel_before or 0))
    f2t_map_speedwalk_send_blind({"board"})
    return true
end

local function finish(message)
    local state = F2T_MAP_EXPLORE_STATE
    local refuel = state.refuel_state
    if not refuel then return end
    state.refuel_state = nil
    state.phase = refuel.resume_phase or "navigating"
    if message then cecho(string.format("\n<cyan>[map-explore]<reset> %s\n", message)) end
    tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_next_step() end
    end)
end

-- Give up on this planet but not on the run: another orbit later may work.
function f2t_map_explore_refuel_abandon(reason)
    local refuel = F2T_MAP_EXPLORE_STATE.refuel_state
    if not refuel then return false end
    F2T_MAP_EXPLORE_STATE.refuel_declined = F2T_MAP_EXPLORE_STATE.refuel_declined or {}
    F2T_MAP_EXPLORE_STATE.refuel_declined[refuel.pad_room] = true
    finish(string.format("Refuelling here didn't work (%s), carrying on", reason or "unknown"))
    return true
end

-- Drives the two-move detour. Returns true while it owns the explorer.
function f2t_map_explore_refuel_on_room_change()
    local state = F2T_MAP_EXPLORE_STATE
    local refuel = state.refuel_state
    if not refuel then return false end
    local current_room = F2T_MAP_CURRENT_ROOM_ID

    if refuel.phase == "descending" then
        if current_room ~= refuel.pad_room then
            -- Landing refused, or it put us somewhere unexpected.
            return f2t_map_explore_refuel_abandon("landing did not reach the pad")
        end
        -- f2t_refuel_on_room_change is its own GMCP handler and has already
        -- seen this arrival; if fuel is low and this pad sells any, "buy fuel"
        -- is in flight. Wait for it rather than racing it back into orbit.
        refuel.phase = "buying"
        tempTimer(PURCHASE_WAIT, function()
            local live = F2T_MAP_EXPLORE_STATE.refuel_state
            if not live or live ~= refuel or not F2T_MAP_EXPLORE_STATE.active then return end
            local after = f2t_map_explore_fuel_percent()
            if after and refuel.fuel_before and after <= refuel.fuel_before then
                f2t_map_explore_refuel_abandon("no fuel bought here")
                return
            end
            refuel.phase = "ascending"
            cecho(string.format("\n<cyan>[map-explore]<reset> Refuelled to %d%%, returning to orbit\n",
                after or 0))
            f2t_map_speedwalk_send_blind({"board"})
        end)
        return true
    end

    if refuel.phase == "buying" then return true end

    if refuel.phase == "ascending" then
        if current_room ~= refuel.orbit_room then
            -- Back in space but not where we left: the sweep replans from
            -- wherever it is anyway, so this is not worth failing over.
            f2t_debug_log("[map/explore] Refuel detour returned to %s, expected %s",
                f2t_map_describe_room(current_room), f2t_map_describe_room(refuel.orbit_room))
        end
        finish("Back in orbit, resuming exploration")
        return true
    end

    return true
end

f2t_debug_log("[map] Loaded explore_refuel.lua")
