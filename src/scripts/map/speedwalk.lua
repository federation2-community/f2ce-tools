-- f2ce-tools map — speedwalk (ported from map_speedwalk.lua)

F2T_SPEEDWALK_ACTIVE               = false
F2T_SPEEDWALK_PAUSED               = false
F2T_SPEEDWALK_DIR                  = {}
F2T_SPEEDWALK_PATH                 = {}
F2T_SPEEDWALK_CURRENT_STEP         = 0
F2T_SPEEDWALK_WAITING_FOR_ARRIVAL  = false
F2T_SPEEDWALK_DESTINATION_ROOM_ID  = nil
F2T_SPEEDWALK_LAST_COMMAND         = nil
F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
-- True for a walk issued as raw commands with no mapped destination behind
-- it: a single exploratory step, or a jump chain into unmapped territory.
-- Movement is still tracked and timed out; there is just no route to replan.
F2T_SPEEDWALK_BLIND                = false
F2T_SPEEDWALK_MOVE_TIMEOUT_ID      = nil
F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
F2T_SPEEDWALK_LAST_RESULT          = nil
-- [roomId|command] = times that exact move has failed during this walk. The
-- consecutive counter alone cannot bound a replan loop: a route that
-- alternates a step that works with one that doesn't zeroes it on every lap.
F2T_SPEEDWALK_FAILED_MOVES         = {}
-- Jumps the game refused during this walk. Counted apart from failures: see
-- f2t_map_speedwalk_handle_refusal.
F2T_SPEEDWALK_REFUSALS             = 0
-- The navigate() call this walk came from, when that call was allowed to
-- compensate for an incomplete map. A planned route can evaporate mid-walk
-- (an exit gets corrected and the map turns out never to have had a real
-- route at all), and stopping there strands the user halfway; this is what
-- lets the walk hand back to navigation instead.
F2T_SPEEDWALK_NAV_REQUEST          = nil
F2T_SPEEDWALK_FAILED_EXIT_ROOM     = nil
F2T_SPEEDWALK_FAILED_EXIT_DIR      = nil
F2T_SPEEDWALK_OWNER                = nil
F2T_SPEEDWALK_ON_INTERRUPT         = nil
F2T_SPEEDWALK_BRIEF_SWITCHED       = false
-- True between a customs interception stopping the old route and the
-- recovery navigate being issued. Owners' nav-complete checks must not
-- treat the "stopped" result during this window as a real user stop.
F2T_SPEEDWALK_CUSTOMS_PENDING      = false
-- True while paused specifically because the socket dropped mid-move, as
-- opposed to a manual f2t_map_speedwalk_pause(). Distinguishes "resume when
-- the connection comes back" from "wait for the user to resume".
F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT = false

function f2t_map_set_nav_owner(owner, on_interrupt)
    F2T_SPEEDWALK_OWNER        = owner
    F2T_SPEEDWALK_ON_INTERRUPT = on_interrupt
end

function f2t_map_clear_nav_owner()
    F2T_SPEEDWALK_OWNER        = nil
    F2T_SPEEDWALK_ON_INTERRUPT = nil
end

-- Name of whoever holds a long-lived "stay in brief" claim (explore, hauling),
-- or nil. While held, individual speedwalks skip their own brief/full toggling
-- so a run made of many short legs isn't flipping the mode between each one.
F2T_MAP_BRIEF_HOLD_OWNER = nil

--- @return boolean true if the hold is now held by owner
function f2t_map_brief_hold_acquire(owner)
    if F2T_MAP_BRIEF_HOLD_OWNER then return F2T_MAP_BRIEF_HOLD_OWNER == owner end
    if not f2t_settings_get("map", "speedwalk_brief") then return false end
    F2T_MAP_BRIEF_HOLD_OWNER = owner
    send("brief")
    return true
end

function f2t_map_brief_hold_release(owner)
    if F2T_MAP_BRIEF_HOLD_OWNER ~= owner then return end
    F2T_MAP_BRIEF_HOLD_OWNER = nil
    send(f2t_settings_get("map", "speedwalk_after_mode") or "full")
end

function f2t_map_speedwalk_restore_mode()
    if not F2T_MAP_BRIEF_HOLD_OWNER and F2T_SPEEDWALK_BRIEF_SWITCHED then
        local after_mode = f2t_settings_get("map", "speedwalk_after_mode") or "full"
        send(after_mode)
        F2T_SPEEDWALK_BRIEF_SWITCHED = false
    end
end

-- Issue a sequence of commands as a blind walk. Callers used to signal this
-- by assigning the Mudlet globals directly and leaving speedWalkPath empty,
-- so "no mapped destination" had to be inferred from an absent array element.
function f2t_map_speedwalk_send_blind(commands)
    if not commands or #commands == 0 then return false end
    speedWalkDir  = commands
    speedWalkPath = {}
    return doSpeedWalk(true)
end

function doSpeedWalk(blind)
    if not speedWalkDir or #speedWalkDir == 0 then
        cecho("\n<red>[map]<reset> No path available - call getPath() first\n"); return false
    end
    F2T_SPEEDWALK_ACTIVE               = true
    F2T_SPEEDWALK_PAUSED               = false
    F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT = false
    F2T_SPEEDWALK_DIR                  = speedWalkDir
    F2T_SPEEDWALK_PATH                 = speedWalkPath
    F2T_SPEEDWALK_CURRENT_STEP         = 0
    F2T_SPEEDWALK_BLIND                = blind and true or false
    F2T_SPEEDWALK_DESTINATION_ROOM_ID  = tonumber(speedWalkPath[#speedWalkPath])
    F2T_SPEEDWALK_LAST_COMMAND         = nil
    F2T_SPEEDWALK_LAST_RESULT          = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID      = nil
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
    F2T_SPEEDWALK_BRIEF_SWITCHED       = false
    local path_length = #speedWalkDir
    f2t_debug_log("[map/walk] walk: %s%s -> %s", blind and "blind " or "",
        table.concat(speedWalkDir, ", "),
        f2t_map_describe_room(F2T_SPEEDWALK_DESTINATION_ROOM_ID))
    cecho(string.format("\n<green>[map]<reset> Speedwalking (%d steps)\n", path_length))
    if path_length >= 3 and f2t_settings_get("map", "speedwalk_brief") and not F2T_MAP_BRIEF_HOLD_OWNER then
        send("brief")
        F2T_SPEEDWALK_BRIEF_SWITCHED = true
    end
    f2t_map_speedwalk_next_step()
    return true
end

function f2t_map_handle_special_movement(direction)
    if direction:match("^__circuit:") then
        if f2t_map_circuit_begin(direction) then
            F2T_SPEEDWALK_LAST_COMMAND = nil
        else
            cecho("\n<red>[map]<reset> Circuit travel failed, stopping speedwalk\n")
            f2t_map_speedwalk_stop()
        end
        return true
    end
    if direction:match("^__move_no_op_%d+$") then
        F2T_SPEEDWALK_LAST_COMMAND = nil
        return true
    end
    return false
end

function f2t_map_speedwalk_next_step()
    if not F2T_SPEEDWALK_ACTIVE then return end
    if F2T_SPEEDWALK_PAUSED then return end
    if F2T_SPEEDWALK_WAITING_FOR_ARRIVAL then return end
    F2T_SPEEDWALK_CURRENT_STEP = F2T_SPEEDWALK_CURRENT_STEP + 1
    if F2T_SPEEDWALK_CURRENT_STEP > #F2T_SPEEDWALK_DIR then
        f2t_map_speedwalk_complete(); return
    end
    local direction = F2T_SPEEDWALK_DIR[F2T_SPEEDWALK_CURRENT_STEP]
    if f2t_map_handle_special_movement(direction) then return end
    F2T_SPEEDWALK_LAST_COMMAND      = direction
    F2T_SPEEDWALK_EXPECTED_ROOM_ID  = tonumber(F2T_SPEEDWALK_PATH[F2T_SPEEDWALK_CURRENT_STEP])
    F2T_SPEEDWALK_WAITING_FOR_MOVE  = true
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE  = F2T_MAP_CURRENT_ROOM_ID
    f2t_debug_log("[map/walk]   step %d/%d '%s': from %s, expecting %s",
        F2T_SPEEDWALK_CURRENT_STEP, #F2T_SPEEDWALK_DIR, tostring(direction),
        f2t_map_describe_room(F2T_SPEEDWALK_ROOM_BEFORE_MOVE),
        f2t_map_describe_room(F2T_SPEEDWALK_EXPECTED_ROOM_ID))
    local timeout_seconds = f2t_settings_get("map", "speedwalk_timeout")
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = tempTimer(timeout_seconds, function()
        f2t_map_speedwalk_on_move_timeout()
    end)
    send(direction)
end

-- Every route teardown ends the same way, and the three that used to write it
-- out longhand drifted apart over which globals they remembered to clear.
-- `result` is what owners read back as the last result; `abandonCircuit` is
-- for the two paths that give up on a circuit rather than finishing it.
local function resetSpeedwalkState(result, abandonCircuit)
    F2T_SPEEDWALK_LAST_RESULT = result
    f2t_map_speedwalk_restore_mode()
    if abandonCircuit and F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then
        f2t_map_circuit_delete_triggers()
        F2T_MAP_CIRCUIT_STATE = {active = false}
    end
    F2T_SPEEDWALK_ACTIVE               = false
    F2T_SPEEDWALK_PAUSED               = false
    F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT = false
    F2T_SPEEDWALK_DIR                  = {}
    F2T_SPEEDWALK_PATH                 = {}
    F2T_SPEEDWALK_CURRENT_STEP         = 0
    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL  = false
    F2T_SPEEDWALK_DESTINATION_ROOM_ID  = nil
    F2T_SPEEDWALK_LAST_COMMAND         = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE     = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
    F2T_SPEEDWALK_BLIND                = false
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
    F2T_SPEEDWALK_FAILED_MOVES         = {}
    F2T_SPEEDWALK_REFUSALS             = 0
    F2T_SPEEDWALK_NAV_REQUEST          = nil
    f2t_map_clear_nav_owner()
end

function f2t_map_speedwalk_complete()
    if not F2T_SPEEDWALK_ACTIVE then return end
    local dest_name = F2T_MAP_CURRENT_ROOM_ID and getRoomName(F2T_MAP_CURRENT_ROOM_ID)
    cecho(string.format("\n<green>[map]<reset> Arrived at <white>%s<reset>\n", dest_name or "destination"))
    resetSpeedwalkState("completed", false)
    local arrival_room = F2T_MAP_CURRENT_ROOM_ID
    if arrival_room then tempTimer(0.05, function() centerview(arrival_room) end) end
end

function f2t_map_speedwalk_stop()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    cecho("\n<yellow>[map]<reset> Speedwalk stopped\n")
    resetSpeedwalkState(F2T_SPEEDWALK_LAST_RESULT == "failed" and "failed" or "stopped", true)
    return true
end

function f2t_map_speedwalk_pause()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    if F2T_SPEEDWALK_PAUSED then cecho("\n<yellow>[map]<reset> Speedwalk is already paused\n"); return false end
    F2T_SPEEDWALK_PAUSED = true
    local remaining = #F2T_SPEEDWALK_DIR - F2T_SPEEDWALK_CURRENT_STEP
    cecho(string.format("\n<yellow>[map]<reset> Speedwalk paused (%d steps remaining)\n", remaining))
    return true
end

function f2t_map_speedwalk_resume()
    if not F2T_SPEEDWALK_ACTIVE then return false end
    if not F2T_SPEEDWALK_PAUSED then cecho("\n<yellow>[map]<reset> Speedwalk is not paused\n"); return false end
    F2T_SPEEDWALK_PAUSED = false
    local remaining = #F2T_SPEEDWALK_DIR - F2T_SPEEDWALK_CURRENT_STEP
    cecho(string.format("\n<green>[map]<reset> Speedwalk resumed (%d steps remaining)\n", remaining))
    f2t_map_speedwalk_next_step()
    return true
end

-- Called from the sysDisconnectionEvent handler. A dead socket looks
-- identical to a blocked exit to the timeout-driven failure path below --
-- "attempt 1/3", recompute, resend into the void, "attempt 2/3"... -- and
-- eventually gives up claiming the path is blocked when actually nothing
-- was ever wrong with the route. Catch it before that timeout fires instead.
function f2t_map_speedwalk_pause_for_disconnect()
    if not F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_PAUSED then return end
    F2T_SPEEDWALK_PAUSED                = true
    F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT = true
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    cecho("\n<yellow>[map]<reset> Connection lost, speedwalk paused\n")
end

-- Called once GMCP confirms a room again after a reconnect (see
-- f2t_map_handle_gmcp_room in core.lua). The move sent right before the
-- drop may or may not have landed server-side, so recompute from wherever
-- we actually are rather than assuming the old path is still valid.
function f2t_map_speedwalk_resume_after_disconnect()
    if not F2T_SPEEDWALK_ACTIVE or not F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT then return end
    F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT = false
    if not f2t_settings_get("map", "speedwalk_resume_on_reconnect") then
        cecho("\n<yellow>[map]<reset> Connection restored, speedwalk still paused (resume manually)\n")
        return
    end
    F2T_SPEEDWALK_PAUSED               = false
    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
    cecho("\n<green>[map]<reset> Connection restored, resuming speedwalk...\n")
    -- A reconnect is a fresh server session, so re-assert brief for whoever
    -- still holds it rather than walking the rest of the route in full.
    if F2T_MAP_BRIEF_HOLD_OWNER then send("brief") end
    f2t_map_speedwalk_recompute_path()
end

function f2t_map_speedwalk_on_room_change()
    if not F2T_SPEEDWALK_ACTIVE then return end
    if F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active then return end
    if F2T_SPEEDWALK_WAITING_FOR_MOVE then
        if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
            killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
            F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
        end
        F2T_SPEEDWALK_WAITING_FOR_MOVE = false
        local current_room  = F2T_MAP_CURRENT_ROOM_ID
        local expected_room = F2T_SPEEDWALK_EXPECTED_ROOM_ID
        local movement_success = false
        if current_room == expected_room then
            movement_success = true
        elseif expected_room == nil and current_room ~= F2T_SPEEDWALK_ROOM_BEFORE_MOVE then
            movement_success = true
        end
        f2t_debug_log("[map/walk]   '%s' arrived at %s (expected %s) - %s",
            tostring(F2T_SPEEDWALK_LAST_COMMAND), f2t_map_describe_room(current_room),
            f2t_map_describe_room(expected_room), movement_success and "as planned" or "MISMATCH")
        -- The map said this "jump X" led to one room and the game put us in
        -- another one in the same system. That is not a failed move: it is
        -- first-hand evidence that the exit's stored destination is stale,
        -- which beats whatever the map was built from. Repoint it and carry
        -- on. Replanning instead just routes back over the same wrong edge,
        -- lands here again, and loops - and because the detour step itself
        -- succeeds each lap, the retry budget never depletes.
        local repointed = false
        if not movement_success and F2T_SPEEDWALK_LAST_COMMAND and current_room then
            local jumped_to = string.match(F2T_SPEEDWALK_LAST_COMMAND, "^jump%s+(.+)$")
            local from_room = F2T_SPEEDWALK_ROOM_BEFORE_MOVE
            local arrived_system = getRoomUserData(current_room, "fed2_system")
            if jumped_to and from_room and current_room ~= from_room and arrived_system ~= ""
                and arrived_system and string.lower(arrived_system) == string.lower(jumped_to) then
                removeSpecialExit(from_room, F2T_SPEEDWALK_LAST_COMMAND)
                addSpecialExit(from_room, current_room, F2T_SPEEDWALK_LAST_COMMAND)
                cecho(string.format(
                    "\n<yellow>[map]<reset> '%s' actually arrives at room %d - map corrected\n",
                    F2T_SPEEDWALK_LAST_COMMAND, current_room))
                f2t_debug_log("[map] Repointed '%s' from room %s: %s -> %d",
                    F2T_SPEEDWALK_LAST_COMMAND, tostring(from_room),
                    tostring(expected_room), current_room)
                -- A system has exactly one interstellar link, so "jump X"
                -- arrives at the same room whoever jumps and from wherever.
                -- Correcting only the edge we just came over leaves every
                -- other one still pointing into the stale room - and the
                -- replan a moment from now will happily jump back out and in
                -- again to use one. Re-derive now, not on the usual debounce:
                -- the replan is the very next thing that happens.
                if f2t_map_topology_rebuild_exits then
                    f2t_map_topology_rebuild_exits()
                end
                movement_success = true
                repointed = true
            end
        end

        if movement_success and F2T_SPEEDWALK_LAST_COMMAND
            and string.match(F2T_SPEEDWALK_LAST_COMMAND, "^jump%s") then
            local leftFrom = F2T_SPEEDWALK_ROOM_BEFORE_MOVE
                and getRoomUserData(F2T_SPEEDWALK_ROOM_BEFORE_MOVE, "fed2_system")
            if leftFrom and f2t_map_clear_link_barred then f2t_map_clear_link_barred(leftFrom) end
        end

        if movement_success then
            F2T_SPEEDWALK_CONSECUTIVE_FAILURES = 0
            F2T_SPEEDWALK_EXPECTED_ROOM_ID     = nil
            F2T_SPEEDWALK_ROOM_BEFORE_MOVE     = nil
            if F2T_SPEEDWALK_CURRENT_STEP == #F2T_SPEEDWALK_DIR - 1 then
                f2t_map_speedwalk_restore_mode()
            end
            -- A route is planned once, up front, using whatever's cached
            -- for every room along it — including rooms not yet visited
            -- this session, whose "jump ___" exits could be incomplete.
            -- GMCP just merged this room's currently-offered jump
            -- destinations on arrival (see apply_gmcp_jumps in jump.lua,
            -- additive only — it never removes a previously-mapped edge),
            -- but nothing re-consults that before continuing unless we do
            -- it here: silently recompute the remaining route against the
            -- data we just received, in case it now offers a better plan
            -- than what the original one assumed for this room.
            -- Blind walks (jump chains into unmapped territory) have no
            -- destination room id; recomputing would abort them, so only
            -- re-verify planned routes.
            local replan = F2T_SPEEDWALK_DESTINATION_ROOM_ID
                and (repointed or f2t_map_room_has_flag(current_room, "link"))
            f2t_debug_log("[map/walk]   %s", replan
                and (repointed and "replanning: an exit was just corrected"
                     or "replanning: link room, re-checking against the jumps GMCP just sent")
                or "continuing with the existing plan")
            if replan then
                f2t_map_speedwalk_recompute_path(true)
            else
                f2t_map_speedwalk_next_step()
            end
        else
            if F2T_SPEEDWALK_ROOM_BEFORE_MOVE and current_room == F2T_SPEEDWALK_ROOM_BEFORE_MOVE then
                cecho(string.format("\n<yellow>[map]<reset> Exit blocked: <white>%s<reset> from room %d\n",
                    F2T_SPEEDWALK_LAST_COMMAND or "unknown", current_room))
            end
            local from_room = F2T_SPEEDWALK_ROOM_BEFORE_MOVE or current_room
            F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
            F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
            f2t_map_speedwalk_handle_move_failure(from_room)
        end
    else
        f2t_map_speedwalk_next_step()
    end
end

function f2t_map_speedwalk_retry_last_command()
    if not F2T_SPEEDWALK_ACTIVE or not F2T_SPEEDWALK_LAST_COMMAND then return false end
    cecho("\n<yellow>[map]<reset> Retrying movement...\n")
    send(F2T_SPEEDWALK_LAST_COMMAND)
    return true
end

-- silent: skip the "recomputing.../recomputed..." messages. Used when
-- re-verifying the remaining route on ordinary arrival at a link room (see
-- f2t_map_speedwalk_on_room_change) rather than recovering from a failure —
-- nothing has actually gone wrong yet in that case, so it shouldn't look
-- like it has.
function f2t_map_speedwalk_recompute_path(silent)
    if not F2T_SPEEDWALK_ACTIVE then return false end
    if F2T_SPEEDWALK_BLIND or not F2T_SPEEDWALK_DESTINATION_ROOM_ID then
        cecho("\n<red>[map]<reset> Unable to recover speedwalk: no mapped destination to replan against\n")
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_MAP_CURRENT_ROOM_ID
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_stop(); return false
    end
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    if not current_room_id then
        cecho("\n<red>[map]<reset> Unable to recover speedwalk: current location unknown\n")
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_SPEEDWALK_ROOM_BEFORE_MOVE
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_stop(); return false
    end
    if not silent then
        cecho("\n<yellow>[map]<reset> Recomputing path from current location...\n")
    end
    local success = getPath(current_room_id, F2T_SPEEDWALK_DESTINATION_ROOM_ID)
    f2t_debug_log("[map/walk] replan: %s -> %s: %s", f2t_map_describe_room(current_room_id),
        f2t_map_describe_room(F2T_SPEEDWALK_DESTINATION_ROOM_ID),
        success and string.format("%d steps (%s)", #speedWalkDir,
            table.concat(speedWalkDir, ", ")) or "NO ROUTE")
    if not success then
        -- The route the walk set out on no longer exists. When the navigate
        -- that started it was allowed to compensate, that is a job for
        -- navigation - explore the gap - rather than a dead end to stop at.
        local request = F2T_SPEEDWALK_NAV_REQUEST
        if request and request.destination then
            F2T_SPEEDWALK_NAV_REQUEST = nil
            cecho("\n<yellow>[map]<reset> The mapped route no longer exists - re-planning\n")
            f2t_map_speedwalk_stop()
            f2t_map_navigate(request.destination, request.opts)
            return false
        end
        cecho("\n<red>[map]<reset> Unable to find path from current location\n")
        F2T_SPEEDWALK_LAST_RESULT     = "failed"
        F2T_SPEEDWALK_FAILED_EXIT_ROOM = current_room_id
        F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
        f2t_map_speedwalk_stop(); return false
    end
    if #speedWalkDir == 0 then
        -- Already there, not stopped: this recompute can fire after the final
        -- step of a route lands us at a link-flagged room (see the "refresh
        -- jump data" check in f2t_map_speedwalk_on_room_change), so 0 steps
        -- remaining here often means the walk just genuinely finished.
        -- f2t_map_speedwalk_stop() sets result "stopped" - indistinguishable
        -- downstream from a real user interruption - so callers like
        -- explore's escape handler wrongly treat a completed arrival as a
        -- failure and pause instead of continuing.
        f2t_map_speedwalk_complete(); return true
    end
    F2T_SPEEDWALK_DIR              = speedWalkDir
    F2T_SPEEDWALK_PATH             = speedWalkPath
    F2T_SPEEDWALK_CURRENT_STEP     = 0
    F2T_SPEEDWALK_LAST_COMMAND     = nil
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    if not silent then
        cecho(string.format("\n<green>[map]<reset> Path recomputed (%d steps), resuming...\n", #speedWalkDir))
    end
    f2t_map_speedwalk_next_step()
    return true
end

-- Shared "give up now" path for both the retry-budget exhaustion below and
-- triggers that recognize a failure as permanent (e.g. a rank/credits gate
-- that no route recompute could ever get around) and want to skip straight
-- to stopping instead of burning through retries first.
function f2t_map_speedwalk_fail(reason)
    if not F2T_SPEEDWALK_ACTIVE then return end
    cecho(string.format("\n<red>[map]<reset> %s\n", reason))
    F2T_SPEEDWALK_FAILED_EXIT_ROOM = F2T_MAP_CURRENT_ROOM_ID
    F2T_SPEEDWALK_FAILED_EXIT_DIR  = F2T_SPEEDWALK_LAST_COMMAND
    cecho("\n<yellow>[map]<reset> Speedwalk stopped\n")
    resetSpeedwalkState("failed", true)
    tempTimer(0, function()
        if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
            f2t_map_explore_on_room_change()
        end
    end)
end

-- A refused move is not a blocked one. The trigger that saw the refusal has
-- already dropped that edge from the map and recorded it against the model,
-- so the next plan cannot pick it again and every refusal is real progress
-- toward a legal route. Spending the "path appears blocked" budget on them
-- gives up after three - which a freshly imported map carrying someone else's
-- jump graph exhausts long before it has finished pruning it. Hence a
-- separate, looser bound, and no recompute message shouting about failure.
local MAX_REFUSALS_PER_WALK = 12

function f2t_map_speedwalk_handle_refusal()
    if not F2T_SPEEDWALK_ACTIVE then return end
    if F2T_SPEEDWALK_BLIND then
        f2t_map_speedwalk_fail("Jump refused and this walk has no route to replan")
        return
    end
    f2t_debug_log("[map/walk] refused: '%s' from %s", tostring(F2T_SPEEDWALK_LAST_COMMAND),
        f2t_map_describe_room(F2T_MAP_CURRENT_ROOM_ID))
    F2T_SPEEDWALK_REFUSALS = (F2T_SPEEDWALK_REFUSALS or 0) + 1
    if F2T_SPEEDWALK_REFUSALS >= MAX_REFUSALS_PER_WALK then
        f2t_map_speedwalk_fail(string.format(
            "%d jumps refused on this route, stopping speedwalk", F2T_SPEEDWALK_REFUSALS))
        return
    end
    cecho(string.format("\n<yellow>[map]<reset> Jump refused - routing around it (%d)\n",
        F2T_SPEEDWALK_REFUSALS))
    f2t_map_speedwalk_recompute_path(true)
end

-- `from_room` is the room the failed move was issued from, passed in because
-- callers clear F2T_SPEEDWALK_ROOM_BEFORE_MOVE before getting here.
function f2t_map_speedwalk_handle_move_failure(from_room)
    if not F2T_SPEEDWALK_ACTIVE then return end
    local max_retries = f2t_settings_get("map", "speedwalk_max_retries")

    -- Budget retries per (room, command) across the whole walk, not just
    -- consecutively: the same move failing from the same room again means the
    -- replan went in a circle, however many steps of it happened to work.
    local key = string.format("%s|%s",
        tostring(from_room or F2T_SPEEDWALK_ROOM_BEFORE_MOVE or F2T_MAP_CURRENT_ROOM_ID),
        tostring(F2T_SPEEDWALK_LAST_COMMAND))
    local repeats = (F2T_SPEEDWALK_FAILED_MOVES[key] or 0) + 1
    F2T_SPEEDWALK_FAILED_MOVES[key] = repeats
    f2t_debug_log("[map/walk] failed move: '%s' from %s (%d time(s) this walk)",
        tostring(F2T_SPEEDWALK_LAST_COMMAND),
        f2t_map_describe_room(from_room or F2T_SPEEDWALK_ROOM_BEFORE_MOVE), repeats)
    if repeats >= max_retries then
        f2t_map_speedwalk_fail(string.format(
            "'%s' has failed %d times from the same room, stopping speedwalk",
            F2T_SPEEDWALK_LAST_COMMAND or "movement", repeats))
        return
    end

    F2T_SPEEDWALK_CONSECUTIVE_FAILURES = F2T_SPEEDWALK_CONSECUTIVE_FAILURES + 1
    if F2T_SPEEDWALK_CONSECUTIVE_FAILURES >= max_retries then
        f2t_map_speedwalk_fail(string.format("Path appears blocked after %d attempts, stopping speedwalk",
            max_retries))
        return
    end
    cecho(string.format("\n<yellow>[map]<reset> Movement erred, recomputing path... (attempt %d/%d)\n",
        F2T_SPEEDWALK_CONSECUTIVE_FAILURES, max_retries))
    f2t_map_speedwalk_recompute_path()
end

function f2t_map_speedwalk_on_move_timeout()
    if not F2T_SPEEDWALK_ACTIVE or not F2T_SPEEDWALK_WAITING_FOR_MOVE then return end
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID  = nil
    local from_room = F2T_SPEEDWALK_ROOM_BEFORE_MOVE
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
    f2t_map_speedwalk_handle_move_failure(from_room)
end
