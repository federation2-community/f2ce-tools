-- f2ce-tools map — Layer 1 core exploration engine (ported from map_explore.lua)

-- The state's shape lives here and only here. Layer 1 (the room-walking
-- engine) is reset on every area; the layer 2-4 fields and the travel and
-- callback slots outlive it. Splitting them means init and reset build from
-- the same lists instead of each enumerating fifty fields and drifting.
-- Fields set to nil are declaring the shape, not populating it.
local function engineFields()
    return {
        active = false, paused = false, pause_requested = false,
        paused_reason = nil, paused_destination = nil,
        phase = nil, planet_mode = nil,
        starting_room_id = nil, starting_area_id = nil,
        visited_rooms = {}, frontier_stack = {}, planned_exit = nil,
        suspected_special_exits = {}, temp_locked_exits = {}, escape_state = nil,
        refuel_state = nil, refuel_declined = nil, refuel_detours = 0,
        stop_when = nil, stop_reason = nil, on_stop_early = nil,
        last_room_before_move = nil, last_direction_attempted = nil,
        stats = {rooms_discovered=0,special_exits_found=0,suspected_special_exits=0,blocked_exits=0,deaths=0},
    }
end

local function layerFields()
    return {
        mode = nil, on_complete_callback = nil,
        brief_flags = nil, brief_flags_set = nil, brief_flags_found = nil,
        brief_flags_remaining_count = nil, brief_planet_name = nil, brief_target_planet = nil,
        target_room_name = nil, target_room_exact = nil, target_room_found_id = nil, target_room_skip = nil,
        system_name = nil, system_mode = nil, system_phase = nil,
        space_area_id = nil, space_area_name = nil, system_complete_callback = nil,
        planet_list = {}, current_planet_index = 0,
        expected_planets = nil, expected_planets_found = nil,
        expected_planets_remaining = nil, planets_without_exchange = nil,
        system_stats = {planets_explored=0,exchanges_found=0,planets_skipped=0},
        cartel_name = nil, cartel_target_system = nil, cartel_complete_callback = nil,
        system_list = {}, current_system_index = 0,
        cartel_stats = {total_systems=0,systems_explored=0,total_planets=0,total_exchanges=0,total_planets_skipped=0},
        galaxy_cartel_list = {}, galaxy_current_cartel_index = 0,
        galaxy_target_cartel = nil, galaxy_syndicate_filter = nil,
        galaxy_stats = {total_cartels=0,cartels_explored=0,cartels_skipped=0,total_systems=0,total_planets=0},
        travel = nil,
    }
end

local function blankState()
    local state = engineFields()
    for field, value in pairs(layerFields()) do state[field] = value end
    return state
end

F2T_MAP_EXPLORE_STATE = F2T_MAP_EXPLORE_STATE or blankState()

-- Layer entry and exit for a callback-driven caller. Only the call that finds
-- the state idle owns the run: it claims .active and the safety hooks, and
-- its completion is what releases them again. A call nested under a parent
-- sweep finds .active already true and leaves all of that to the parent.
function f2t_map_explore_claim_run(mode)
    -- A finished run only goes inactive; start clean so nothing it left behind
    -- (a pause, a stop condition, a detour) holds up this one.
    F2T_MAP_EXPLORE_STATE = blankState()
    F2T_MAP_EXPLORE_STATE.active = true
    if mode then F2T_MAP_EXPLORE_STATE.mode = mode end
    local pending = F2T_MAP_EXPLORE_PENDING_STOP
    if pending then
        F2T_MAP_EXPLORE_STATE.stop_when = pending.stop_when
        F2T_MAP_EXPLORE_STATE.stop_reason = pending.stop_reason
        F2T_MAP_EXPLORE_STATE.on_stop_early = pending.on_stop_early
    end
    f2t_map_explore_register_safety_hooks()
end

-- An early stop for the run about to start. A sweep can claim its run only
-- after an asynchronous step (capturing a system's planet list), so the
-- condition waits here as well as on the state until the caller clears it.
function f2t_map_explore_set_stop_condition(stopWhen, reason, onStopEarly)
    F2T_MAP_EXPLORE_PENDING_STOP = stopWhen and {
        stop_when = stopWhen, stop_reason = reason, on_stop_early = onStopEarly,
    } or nil
    F2T_MAP_EXPLORE_STATE.stop_when = stopWhen
    F2T_MAP_EXPLORE_STATE.stop_reason = reason
    F2T_MAP_EXPLORE_STATE.on_stop_early = onStopEarly
end

function f2t_map_explore_release_run()
    F2T_MAP_EXPLORE_STATE.active = false
    f2t_map_explore_release_stamina()
    f2t_map_explore_unlock_temp_exits()
    f2t_map_explore_brief_mode_restore()
end

-- Wrap a completion callback so it releases the run this call claimed.
function f2t_map_explore_wrap_release(callback)
    if not callback then return callback end
    return function(...)
        f2t_map_explore_release_run()
        callback(...)
    end
end

-- Explore takes the shared brief hold for the length of a run. When something
-- longer-lived already holds it (an explore driven by hauling), these are no-ops
-- and that owner decides when the mode goes back.
function f2t_map_explore_brief_mode_start()
    f2t_map_brief_hold_acquire("explore")
end

function f2t_map_explore_brief_mode_restore()
    f2t_map_brief_hold_release("explore")
end

function f2t_map_explore_init_area(area_id, mode_fields)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    -- The early-stop condition belongs to the run, not to the area being
    -- swept, and this replaces the whole state table - so carry it across or
    -- a system sweep loses it the moment it starts on its space area.
    local stopWhen   = F2T_MAP_EXPLORE_STATE.stop_when
    local stopReason = F2T_MAP_EXPLORE_STATE.stop_reason
    local onStopEarly = F2T_MAP_EXPLORE_STATE.on_stop_early

    local state = engineFields()
    state.active = true
    state.phase = "navigating"
    state.starting_room_id = current_room
    state.starting_area_id = area_id
    state.visited_rooms = {[current_room] = true}
    state.stats.rooms_discovered = 1
    state.stop_when = stopWhen
    state.stop_reason = stopReason
    state.on_stop_early = onStopEarly
    F2T_MAP_EXPLORE_STATE = state
    if mode_fields then
        for k, v in pairs(mode_fields) do F2T_MAP_EXPLORE_STATE[k] = v end
    end
    f2t_map_explore_recompute_frontier()
    return #F2T_MAP_EXPLORE_STATE.frontier_stack
end

-- Get somewhere before a sweep starts. A standalone sweep travels as an
-- ordinary trip before it claims its run, so navigation can explore its way
-- there; a sweep nested in a bigger one travels inside that run.
function f2t_map_explore_go(destination, on_arrived, on_failed)
    if F2T_MAP_EXPLORE_STATE.active then
        f2t_map_explore_travel(destination, on_arrived, on_failed)
        return
    end
    f2tNav.go(destination, { owner = "explore", onDone = function(result)
        if result.status == "arrived" then
            on_arrived()
            return
        end
        if result.status == "unreachable" then
            cecho(string.format("\n<red>[map-explore]<reset> Couldn't reach %s: %s\n",
                tostring(destination), result.reason or "no route"))
        end
        if on_failed then on_failed() end
    end })
end

-- Reach a planet, then start Layer 1 exploration there. A planet's area can
-- be a lone stub room, wired from its orbit's "board" before anyone landed,
-- with no flags for a name lookup to find; going to that room by id lands
-- there all the same.
function f2t_map_explore_travel_to_planet(planet_mode, planet_name, on_complete_callback, override_flags,
                                           target_room_name, target_room_exact, target_room_skip)
    local standalone = not F2T_MAP_EXPLORE_STATE.active
    local destination = planet_name
    local planet_area_id = f2t_map_get_area_id(planet_name)
    if planet_area_id then
        destination = f2t_map_find_room_with_flag(planet_area_id, "shuttlepad")
            or f2t_map_area_room_list(planet_area_id)[1] or planet_name
    end

    -- Failing to get there ends a standalone search without its callback, like a stop does
    local function failed()
        if standalone then raiseEvent("f2tExploreStopped", "failed") end
    end

    f2t_map_explore_go(destination, function()
        local area = F2T_MAP_CURRENT_ROOM_ID and getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
        local arrived_planet = area and getRoomAreaName(area)
        if not arrived_planet or arrived_planet:lower() ~= planet_name:lower() then
            cecho(string.format("\n<red>[map-explore]<reset> Could not reach %s\n", planet_name))
            failed()
            return
        end
        f2t_map_explore_planet_start(planet_mode, planet_name, on_complete_callback,
            override_flags, target_room_name, target_room_exact, target_room_skip)
    end, failed)
    return true
end

function f2t_map_explore_planet_start(planet_mode, planet_name, on_complete_callback, override_flags,
                                       target_room_name, target_room_exact, target_room_skip)
    if not planet_mode or (planet_mode ~= "full" and planet_mode ~= "brief") then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid planet mode '%s'\n", tostring(planet_mode)))
        return false
    end

    -- A named target we aren't already standing on has to be reached first -
    -- otherwise this would silently explore wherever we happen to be instead.
    if planet_name and planet_name ~= "" then
        local room = F2T_MAP_CURRENT_ROOM_ID
        local area = room and getRoomArea(room)
        local current_planet = area and getRoomAreaName(area)
        if not current_planet or current_planet:lower() ~= planet_name:lower() then
            return f2t_map_explore_travel_to_planet(planet_mode, planet_name, on_complete_callback, override_flags,
                target_room_name, target_room_exact, target_room_skip)
        end
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map-explore]<reset> Error: Not in a mapped room\n"); return false end
    local current_area = getRoomArea(current_room)
    if not current_area then cecho("\n<red>[map-explore]<reset> Error: Room has no area\n"); return false end
    if not planet_name or planet_name == "" then
        planet_name = getRoomAreaName(current_area) or "Unknown"
    end

    local brief_fields = {}
    if planet_mode == "brief" then
        local brief_flags
        if override_flags then
            brief_flags = {"shuttlepad"}
            for _, flag in ipairs(override_flags) do
                if flag ~= "shuttlepad" then table.insert(brief_flags, flag) end
            end
        else
            brief_flags = f2t_map_explore_default_required_flags()
        end
        local system_name = getAreaUserData(current_area, "fed2_system") or ""
        brief_flags = f2t_map_explore_strip_courier_outside_sol(brief_flags, system_name)
        -- The game files say what a Sol planet has; don't search for the rest
        local area_name = getRoomAreaName(current_area)
        for i = #brief_flags, 1, -1 do
            if f2t_map_sol_planet_has_flag(area_name, brief_flags[i]) == false then
                table.remove(brief_flags, i)
            end
        end
        local brief_flags_set = {}
        for _, flag in ipairs(brief_flags) do brief_flags_set[flag] = true end
        local brief_flags_found = {}
        local flags_already_found = 0
        for _, flag in ipairs(brief_flags) do
            local existing_room = f2t_map_find_reachable_room_with_flag(current_area, flag, current_room)
            if existing_room then
                brief_flags_found[flag] = existing_room
                flags_already_found = flags_already_found + 1
            end
        end
        brief_fields = {
            brief_planet_name = planet_name,
            brief_flags = brief_flags,
            brief_flags_set = brief_flags_set,
            brief_flags_found = brief_flags_found,
            brief_flags_remaining_count = #brief_flags - flags_already_found,
        }
        if target_room_name and target_room_name ~= "" then
            brief_fields.target_room_name = target_room_name
            brief_fields.target_room_exact = target_room_exact and true or false
            brief_fields.target_room_found_id = nil
            brief_fields.target_room_skip = target_room_skip
        end
    end

    if on_complete_callback then
        -- Nested (parent sweep already has .active/hooks) or a standalone
        -- callback-driven call (a navigation sweep, an Akaturi room search) that
        -- hasn't started anything yet - ensure both here too, and unwind them
        -- once completion fires, as the system-level start does.
        local started_standalone = not F2T_MAP_EXPLORE_STATE.active
        if started_standalone then
            f2t_map_explore_claim_run()
            on_complete_callback = f2t_map_explore_wrap_release(on_complete_callback)
        end
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        F2T_MAP_EXPLORE_STATE.planet_mode = planet_mode
        F2T_MAP_EXPLORE_STATE.on_complete_callback = on_complete_callback
        F2T_MAP_EXPLORE_STATE.starting_room_id = current_room
        F2T_MAP_EXPLORE_STATE.starting_area_id = current_area
        F2T_MAP_EXPLORE_STATE.visited_rooms = {[current_room]=true}
        F2T_MAP_EXPLORE_STATE.frontier_stack = {}
        F2T_MAP_EXPLORE_STATE.planned_exit = nil
        for k, v in pairs(brief_fields) do F2T_MAP_EXPLORE_STATE[k] = v end
    else
        f2t_map_explore_register_safety_hooks()
        local mode_fields = {mode="planet", planet_mode=planet_mode, on_complete_callback=on_complete_callback}
        for k, v in pairs(brief_fields) do mode_fields[k] = v end
        f2t_map_explore_init_area(current_area, mode_fields)
    end

    f2t_map_explore_recompute_frontier()

    local room_name = getRoomName(current_room) or "Unknown"
    local area_name = getRoomAreaName(current_area) or "Unknown"
    if planet_mode == "full" then
        cecho("\n<green>[map]<reset> Exploration started (<cyan>full mode<reset>)\n")
        cecho(string.format("  Starting room: <white>%s<reset> (ID: %d)\n", room_name, current_room))
        cecho(string.format("  Starting area: <white>%s<reset> (ID: %d)\n", area_name, current_area))
    else
        cecho("\n<green>[map-explore]<reset> Brief exploration started\n")
        cecho(string.format("  Starting room: <white>%s<reset>\n", room_name))
        cecho(string.format("  Starting area: <white>%s<reset>\n", area_name))
        cecho(string.format("  Target flags: <yellow>%s<reset>\n", table.concat(brief_fields.brief_flags or {}, ", ")))
        for flag in pairs(brief_fields.brief_flags_found or {}) do
            cecho(string.format("  <green>+<reset> <yellow>%s<reset> already mapped\n", flag))
        end
        if brief_fields.brief_flags_remaining_count == 0 then
            cecho("  <green>All target flags already discovered!<reset>\n\n")
        end
        if brief_fields.target_room_name then
            cecho(string.format("  Target room: <yellow>%s<reset>\n", brief_fields.target_room_name))
        end
    end

    if planet_mode == "brief" then
        if F2T_MAP_EXPLORE_STATE.target_room_name then
            f2t_map_explore_brief_check_target_room(current_room)
            if F2T_MAP_EXPLORE_STATE.target_room_found_id then
                return true
            end
        end
        f2t_map_explore_brief_check_room_flags(current_room)
        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 and not F2T_MAP_EXPLORE_STATE.target_room_name then
            if on_complete_callback then on_complete_callback()
            else f2t_map_explore_complete()
            end
            return true
        end
    end

    f2t_map_explore_next_step()
    return true
end

function f2t_map_explore_brief_check_room_flags(room_id)
    if not F2T_MAP_EXPLORE_STATE.active or not F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count then return end
    local flags_set   = F2T_MAP_EXPLORE_STATE.brief_flags_set
    local flags_found = F2T_MAP_EXPLORE_STATE.brief_flags_found
    for flag, _ in pairs(flags_set) do
        if not flags_found[flag] then
            if getRoomUserData(room_id, string.format("fed2_flag_%s", flag)) == "true" then
                flags_found[flag] = room_id
                F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count =
                    F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count - 1
                local room_name = getRoomName(room_id) or "Unknown"
                cecho(string.format("  <green>✓<reset> Found <yellow>%s<reset> at: %s\n", flag, room_name))
                local effective_remaining = F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count
                if effective_remaining > 0 then
                    local area_id = F2T_MAP_EXPLORE_STATE.starting_area_id
                    local system_name = area_id and getAreaUserData(area_id, "fed2_system") or ""
                    if not f2t_map_explore_is_sol(system_name) then
                        local non_courier = 0
                        for rf, _ in pairs(F2T_MAP_EXPLORE_STATE.brief_flags_set) do
                            if not flags_found[rf] and rf ~= "courier" then non_courier = non_courier + 1 end
                        end
                        if non_courier == 0 then effective_remaining = 0 end
                    end
                end
                if effective_remaining == 0 then
                    -- A target-room search (e.g. Akaturi hunting a specific
                    -- randomized room name) keeps walking past "all flags
                    -- found" - the room name, not the flags, is the real goal.
                    if F2T_MAP_EXPLORE_STATE.target_room_name then
                        cecho("\n<green>[map-explore]<reset> All target flags found, still hunting for target room\n")
                        return
                    end
                    cecho("\n<green>[map-explore]<reset> All target flags found!\n\n")
                    if F2T_MAP_EXPLORE_STATE.system_stats then
                        local sys_stats = F2T_MAP_EXPLORE_STATE.system_stats
                        sys_stats.planets_explored = sys_stats.planets_explored + 1
                        sys_stats.exchanges_found  = sys_stats.exchanges_found  + 1
                        if F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
                            local c_stats = F2T_MAP_EXPLORE_STATE.cartel_stats
                            c_stats.total_planets   = c_stats.total_planets   + 1
                            c_stats.total_exchanges = c_stats.total_exchanges + 1
                        end
                    end
                    tempTimer(0.5, function()
                        if not F2T_MAP_EXPLORE_STATE.active then return end
                        f2t_map_explore_brief_return_to_shuttlepad()
                    end)
                    return
                end
            end
        end
    end
end

-- Unlike brief_check_room_flags, a target-room match completes immediately
-- (no return-to-shuttlepad step) - arriving at the found room is the goal,
-- not returning to the landing pad. on_complete_callback is called with the
-- found room_id so the caller (e.g. Akaturi's pickup/delivery search) knows
-- exactly where it ended up without re-querying the map.
--
-- target_room_exact selects exact (case-sensitive) equality, matching
-- Akaturi's own static search (f2t_akaturi_search_room requires an exact
-- name since it's matching text the game itself reported). Otherwise this
-- does the same case-insensitive substring match as f2t_map_search_area,
-- so `map explore room <text>` behaves like `map search` but walks instead
-- of only checking rooms already in the local map.
function f2t_map_explore_brief_check_target_room(room_id)
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local target_name = F2T_MAP_EXPLORE_STATE.target_room_name
    if not target_name or F2T_MAP_EXPLORE_STATE.target_room_found_id then return end
    local skip = F2T_MAP_EXPLORE_STATE.target_room_skip
    if skip and skip[room_id] then return end
    local room_name = getRoomName(room_id)
    if not room_name then return end

    local matched
    if F2T_MAP_EXPLORE_STATE.target_room_exact then
        matched = room_name == target_name
    else
        matched = string.find(string.lower(room_name), string.lower(target_name), 1, true) ~= nil
    end
    if not matched then return end

    F2T_MAP_EXPLORE_STATE.target_room_found_id = room_id
    cecho(string.format("\n<green>[map-explore]<reset> Found target room: <yellow>%s<reset>!\n\n", room_name))

    local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback
    if callback then callback(room_id)
    else f2t_map_explore_complete() end
end

function f2t_map_explore_brief_return_to_shuttlepad()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local shuttlepad_room = F2T_MAP_EXPLORE_STATE.brief_flags_found and
                            F2T_MAP_EXPLORE_STATE.brief_flags_found["shuttlepad"]
    if not shuttlepad_room then
        f2t_map_explore_brief_call_callback(); return
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room == shuttlepad_room then
        f2t_map_explore_brief_call_callback(); return
    end
    cecho("  <dim_grey>Returning to shuttlepad...<reset>\n")
    f2t_map_explore_escape_start(
        shuttlepad_room,
        function() f2t_map_explore_brief_call_callback() end,
        function(reason) f2t_map_explore_pause_stranded(reason, shuttlepad_room) end
    )
end

-- Records on a planet's area how far it has been explored ("brief": its
-- required rooms found, "full": every exit walked), for the galaxy navigator.
-- F2T_MAP_EXPLORED_EPOCH tells readers caching the mark that one changed.
function f2t_map_explore_mark_planet_explored(area_id, depth)
    local area_name = area_id and getRoomAreaName(area_id)
    if not area_name or f2t_map_get_system_from_space_area(area_name) then return end
    local current = getAreaUserData(area_id, "fed2_explored")
    if current == "full" or current == depth then return end
    setAreaUserData(area_id, "fed2_explored", depth)
    F2T_MAP_EXPLORED_EPOCH = (F2T_MAP_EXPLORED_EPOCH or 0) + 1
end

function f2t_map_explore_brief_call_callback()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 then
        f2t_map_explore_mark_planet_explored(F2T_MAP_EXPLORE_STATE.starting_area_id, "brief")
    end
    local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback
    if callback then callback()
    else f2t_map_explore_complete()
    end
end

-- Whether this exploration is the stamina monitor's client. A sweep run as a
-- navigation self-heal under hauling leaves hauling as the client.
local exploreHoldsStamina = false

function f2t_map_explore_release_stamina()
    if exploreHoldsStamina and f2t_stamina_unregister_client then f2t_stamina_unregister_client() end
    exploreHoldsStamina = false
end

-- Stamina-monitor hook shared by every standalone explore entry point (nested
-- layers skip this since the parent that started the sweep already holds it).
function f2t_map_explore_register_safety_hooks()
    if f2t_stamina_has_client and f2t_stamina_has_client() then return end
    if f2t_stamina_register_client then
        exploreHoldsStamina = true
        f2t_stamina_register_client({
            pause_callback  = f2t_map_explore_pause,
            resume_callback = f2t_map_explore_resume,
            check_active = function()
                return F2T_MAP_EXPLORE_STATE.active and not F2T_MAP_EXPLORE_STATE.paused
            end,
        })
    end
end

-- A sweep's travel is a navigation trip like any other. The sweep waits in the
-- "travelling" phase, which its own room-change handling leaves alone, and
-- carries on from on_arrived. The player taking navigation over stops the
-- sweep; anything else taking it over pauses it, and resuming travels again.
function f2t_map_explore_travel(destination, on_arrived, on_failed)
    F2T_MAP_EXPLORE_STATE.phase = "travelling"
    F2T_MAP_EXPLORE_STATE.travel = { destination = destination, on_arrived = on_arrived, on_failed = on_failed }
    f2tNav.go(destination, { owner = "explore", onDone = function(result)
        local state = F2T_MAP_EXPLORE_STATE
        if not state.active or state.phase ~= "travelling" or state.paused then return end
        if result.status == "arrived" then
            state.phase = nil
            state.travel = nil
            if on_arrived then on_arrived() end
        elseif result.status == "superseded" and result.by ~= "player" then
            state.paused = true
            state.paused_reason = "travel"
            cecho("\n<yellow>[map-explore]<reset> Paused while navigation is needed elsewhere\n")
        elseif result.status == "stopped" or result.status == "superseded" then
            f2t_map_explore_stop()
        else
            state.phase = nil
            state.travel = nil
            cecho(string.format("\n<red>[map-explore]<reset> Couldn't reach %s: %s\n",
                destination, result.reason or "no route"))
            if on_failed then on_failed() end
        end
    end })
end

function f2t_map_explore_start(mode, name)
    mode = mode or "brief"
    if mode ~= "full" and mode ~= "brief" then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid mode '%s'\n", mode)); return false
    end
    if F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n"); return false
    end
    if not gmcp or not gmcp.room or not gmcp.room.info then
        cecho("\n<red>[map-explore]<reset> Error: GMCP room data unavailable\n"); return false
    end
    if not f2t_map_ensure_current_location() then
        cecho("\n<red>[map-explore]<reset> Error: Current location unknown\n"); return false
    end
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then cecho("\n<red>[map-explore]<reset> Error: Not in a mapped room\n"); return false end
    local current_area = getRoomArea(current_room)
    if not current_area then cecho("\n<red>[map-explore]<reset> Error: Room has no area\n"); return false end

    -- Each underlying _start function registers its own safety hooks when run
    -- standalone (on_complete_callback nil), so a mode-dispatcher like this
    -- one that only ever delegates doesn't need to register here too.

    if name and name ~= "" then
        local is_planet = f2t_map_lookup_planet(name)
        local is_system = f2t_map_lookup_system(name)
        if is_system and is_planet then
            local system_fully_mapped = f2t_map_explore_is_system_fully_mapped(name)
            if system_fully_mapped then return f2t_map_explore_planet_start(mode, name)
            else return f2t_map_explore_system_start(mode, name)
            end
        elseif is_system then
            return f2t_map_explore_system_start(mode, name)
        elseif is_planet then
            return f2t_map_explore_planet_start(mode, name)
        else
            cecho(string.format("\n<red>[map]<reset> Unknown planet or system: %s\n", name)); return false
        end
    end

    local area_name = getRoomAreaName(current_area)
    if area_name and area_name:match(" Space$") then
        local system = f2t_get_current_system()
        if not system then
            cecho("\n<red>[map-explore]<reset> Error: In space but couldn't detect system\n")
            return false
        end
        return f2t_map_explore_system_start(mode, system)
    end

    local planet = f2t_get_current_planet()
    return f2t_map_explore_planet_start(mode, planet)
end

-- Lock an exit for the duration of the run and record it so teardown can
-- unlock it. Stored as a set: re-locking is idempotent, and every entry stays
-- visible to the pairs() walk in unlock_temp_exits.
function f2t_map_explore_temp_lock_exit(room_id, direction)
    lockExit(room_id, direction, true)
    local locked = F2T_MAP_EXPLORE_STATE.temp_locked_exits
    if not locked then
        locked = {}
        F2T_MAP_EXPLORE_STATE.temp_locked_exits = locked
    end
    if not locked[room_id] then locked[room_id] = {} end
    locked[room_id][direction] = true
end

function f2t_map_explore_unlock_temp_exits()
    if not F2T_MAP_EXPLORE_STATE.temp_locked_exits then return end
    for room_id, directions in pairs(F2T_MAP_EXPLORE_STATE.temp_locked_exits) do
        for direction in pairs(directions) do lockExit(room_id, direction, false) end
    end
    F2T_MAP_EXPLORE_STATE.temp_locked_exits = {}
end

-- `reason` is for the times the client ends a sweep itself - having found
-- what the sweep was for, say. Without one this is a user stop, which is the
-- only case where a statistics dump is worth printing.
function f2t_map_explore_stop(reason)
    if not F2T_MAP_EXPLORE_STATE.active then
        -- A standalone sweep still travelling to where it starts
        if f2tNav.stop("explore") then
            cecho("\n<yellow>[map]<reset> Exploration stopped before it started\n")
        else
            cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n")
        end
        return
    end
    f2tNav.stop("explore")
    f2t_map_explore_release_stamina()
    f2t_map_explore_unlock_temp_exits()
    if reason then
        cecho(string.format("\n<green>[map-explore]<reset> %s\n", reason))
    else
        cecho("\n<yellow>[map]<reset> Exploration stopped by user\n")
        f2t_map_explore_show_statistics()
    end
    f2t_map_explore_brief_mode_restore()
    F2T_MAP_EXPLORE_STATE = blankState()
    -- A stopped run never calls its completion callback; callers waiting on one listen for this.
    raiseEvent("f2tExploreStopped", reason)
end

-- Deletes every room in an area and reports how many. Shared by the manual
-- 'map explore reset' command and the automatic reset-and-re-explore flow a
-- system sweep offers when it can't find every expected planet.
function f2t_map_explore_delete_area_rooms(area_id)
    local rooms = f2t_map_area_room_list(area_id)
    for _, room_id in ipairs(rooms) do
        deleteRoom(room_id)
    end
    return #rooms
end

-- Wipes every room in a system's space area or a planet's own surface area,
-- so the next explore rebuilds it from a completely clean slate. This is the
-- nuclear option: unlike 'map topology stranded purge' (which only removes
-- rooms it can prove are unreachable duplicates), this deletes everything,
-- live rooms included, for when the map for a whole context is suspect
-- enough that partial cleanup isn't confidence-inspiring.
function f2t_map_explore_reset(target_name)
    if F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<red>[map-explore]<reset> An exploration is running - use 'map explore stop' first\n")
        return
    end
    if not target_name or target_name == "" then
        cecho("\n<red>[map-explore]<reset> Usage: map explore reset <system or planet name>\n")
        return
    end
    target_name = target_name:gsub("^%l", string.upper)

    local area_id, area_kind
    local space_area_name = f2t_map_get_system_space_area_actual(target_name)
    if space_area_name then
        area_id = f2t_map_get_area_id(space_area_name)
        area_kind = "system"
    else
        area_id = f2t_map_get_area_id(target_name)
        area_kind = "planet"
    end

    if not area_id then
        cecho(string.format("\n<red>[map-explore]<reset> No mapped system or planet called '%s'\n", target_name))
        return
    end

    local rooms = f2t_map_area_room_list(area_id)
    if #rooms == 0 then
        cecho(string.format("\n<yellow>[map-explore]<reset> %s has no mapped rooms - nothing to reset\n",
            target_name))
        return
    end
    if F2T_MAP_CURRENT_ROOM_ID and getRoomArea(F2T_MAP_CURRENT_ROOM_ID) == area_id then
        cecho(string.format(
            "\n<red>[map-explore]<reset> You are currently standing in %s's %s area - move elsewhere" ..
            " first, deleting the room you're in would leave your position unknown\n",
            target_name, area_kind == "system" and "space" or "surface"))
        return
    end

    local area_word = area_kind == "system" and "space" or "surface"
    f2t_map_manual_request_confirmation(
        string.format("delete all %d room(s) in %s's %s area", #rooms, target_name, area_word),
        function()
            local deleted = f2t_map_explore_delete_area_rooms(area_id)
            cecho(string.format(
                "\n<green>[map-explore]<reset> Reset complete: %d room(s) removed from %s's %s area." ..
                " The next explore starts from a clean slate.<reset>\n",
                deleted, target_name, area_word))
        end)
end

function f2t_map_explore_pause()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n"); return
    end
    if F2T_MAP_EXPLORE_STATE.paused or F2T_MAP_EXPLORE_STATE.pause_requested then
        cecho("\n<yellow>[map-explore]<reset> Exploration already paused\n"); return
    end
    -- Nothing steps the sweep while it travels, so a pause stops the trip now and resuming travels again
    if F2T_MAP_EXPLORE_STATE.phase == "travelling" then
        F2T_MAP_EXPLORE_STATE.paused = true
        F2T_MAP_EXPLORE_STATE.paused_reason = "travel"
        f2tNav.stop("explore")
        cecho("\n<yellow>[map]<reset> Exploration paused while travelling\n")
        cecho("  Use <white>map explore resume<reset> to continue\n")
        return
    end
    F2T_MAP_EXPLORE_STATE.pause_requested = true
    cecho(string.format("\n<yellow>[map]<reset> Will pause after current operation... (phase: <cyan>%s<reset>)\n",
        F2T_MAP_EXPLORE_STATE.phase or "unknown"))
end

function f2t_map_explore_check_deferred_pause()
    if not F2T_MAP_EXPLORE_STATE.pause_requested then return false end
    F2T_MAP_EXPLORE_STATE.pause_requested = false
    F2T_MAP_EXPLORE_STATE.paused = true
    cecho(string.format("\n<yellow>[map]<reset> Exploration paused at phase: <cyan>%s<reset>\n",
        F2T_MAP_EXPLORE_STATE.phase or "unknown"))
    cecho("  Use <white>map explore resume<reset> to continue\n")
    return true
end

function f2t_map_explore_resume()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n"); return
    end
    if F2T_MAP_EXPLORE_STATE.pause_requested then
        F2T_MAP_EXPLORE_STATE.pause_requested = false
        cecho("\n<green>[map]<reset> Pending pause cancelled\n"); return
    end
    if not F2T_MAP_EXPLORE_STATE.paused then
        cecho("\n<yellow>[map-explore]<reset> Exploration not paused\n"); return
    end
    F2T_MAP_EXPLORE_STATE.paused = false
    cecho("\n<green>[map]<reset> Exploration resumed\n")
    local travel = F2T_MAP_EXPLORE_STATE.travel
    if F2T_MAP_EXPLORE_STATE.paused_reason == "travel" and travel then
        F2T_MAP_EXPLORE_STATE.paused_reason = nil
        f2t_map_explore_travel(travel.destination, travel.on_arrived, travel.on_failed)
        return
    end
    if F2T_MAP_EXPLORE_STATE.paused_reason == "stranded" then
        F2T_MAP_EXPLORE_STATE.paused_reason = nil
        local destination = F2T_MAP_EXPLORE_STATE.paused_destination
        F2T_MAP_EXPLORE_STATE.paused_destination = nil
        if F2T_MAP_EXPLORE_STATE.brief_flags_found then
            f2t_map_explore_brief_return_to_shuttlepad(); return
        elseif destination then
            if f2t_map_walk_room(destination) then
                F2T_MAP_EXPLORE_STATE.phase = "navigating"; return
            end
            f2t_map_explore_escape_start(destination,
                function() f2t_map_explore_next_step() end,
                function(reason) f2t_map_explore_pause_stranded(reason, destination) end)
            return
        end
    end
    if F2T_MAP_EXPLORE_STATE.escape_state then F2T_MAP_EXPLORE_STATE.escape_state = nil end
    if F2T_MAP_EXPLORE_STATE.phase == "brief_escaping" then F2T_MAP_EXPLORE_STATE.phase = "navigating" end
    F2T_MAP_EXPLORE_STATE.paused_reason = nil
    F2T_MAP_EXPLORE_STATE.paused_destination = nil
    f2t_map_explore_next_step()
end

function f2t_map_explore_status()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n"); return
    end
    cecho("\n<green>[map]<reset> Exploration Status\n\n")
    local state = F2T_MAP_EXPLORE_STATE
    local state_str = "ACTIVE"
    if state.paused then
        state_str = string.format("PAUSED (%s)", state.paused_reason or "no reason recorded")
    elseif state.pause_requested then
        state_str = "PAUSING after this step"
    end
    cecho(string.format("  State: <white>%s<reset>\n", state_str))
    cecho(string.format("  Phase: <white>%s<reset>  Mode: <white>%s<reset>\n", state.phase or "unknown",
        state.mode or "planet"))
    if state.stop_when then cecho("  Ends early once its route is found\n") end
    if state.refuel_state then cecho(string.format("  Refuel detour: <white>%s<reset>\n", state.refuel_state.phase)) end
    if state.planned_exit then
        cecho(string.format("  Heading for: room %s, then %s\n", tostring(state.planned_exit.room_id),
            tostring(state.planned_exit.direction)))
    end
    if F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_CUSTOMS_PENDING then
        cecho(string.format("  Walk in progress%s\n", F2T_SPEEDWALK_CUSTOMS_PENDING and " (customs recovery)" or ""))
    end
    f2t_map_explore_show_statistics()
    cecho(string.format("  Unexplored exits: <white>%d<reset>\n", #F2T_MAP_EXPLORE_STATE.frontier_stack))
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room then
        cecho(string.format("  Current room: <white>%s<reset> (ID: %d)\n",
            getRoomName(current_room) or "Unknown", current_room))
    end
end

function f2t_map_explore_show_statistics()
    local stats = F2T_MAP_EXPLORE_STATE.stats
    local mode  = F2T_MAP_EXPLORE_STATE.mode or "planet"
    local planet_mode = F2T_MAP_EXPLORE_STATE.planet_mode
    cecho("\n  Statistics:\n")
    if mode == "planet" then
        if planet_mode == "full" then
            cecho(string.format("    Rooms discovered: <white>%d<reset>\n", stats.rooms_discovered))
            cecho(string.format("    Blocked exits: <white>%d<reset>\n", stats.blocked_exits))
        else
            local flags_found = F2T_MAP_EXPLORE_STATE.brief_flags_found or {}
            local total_flags = #(F2T_MAP_EXPLORE_STATE.brief_flags or {})
            local found_count = 0
            for _ in pairs(flags_found) do found_count = found_count + 1 end
            cecho(string.format("    Flags found: <white>%d/%d<reset>\n", found_count, total_flags))
        end
    elseif mode == "system" then
        local sys_stats = F2T_MAP_EXPLORE_STATE.system_stats
        local total_planets = sys_stats.total_planets or #F2T_MAP_EXPLORE_STATE.planet_list
        cecho(string.format("    Planets explored: <white>%d/%d<reset>\n", sys_stats.planets_explored, total_planets))
        cecho(string.format("    Exchanges found: <white>%d<reset>\n", sys_stats.exchanges_found))
    elseif mode == "cartel" then
        local cartel_stats = F2T_MAP_EXPLORE_STATE.cartel_stats
        cecho(string.format("    Systems explored: <white>%d/%d<reset>\n",
            cartel_stats.systems_explored, cartel_stats.total_systems))
        cecho(string.format("    Total planets: <white>%d<reset>\n", cartel_stats.total_planets))
    elseif mode == "galaxy" then
        local galaxy_stats = F2T_MAP_EXPLORE_STATE.galaxy_stats
        local syndicate_filter = F2T_MAP_EXPLORE_STATE.galaxy_syndicate_filter
        if syndicate_filter then
            cecho(string.format("    Scope: <white>%s<reset> syndicate\n", syndicate_filter))
        else
            cecho("    Scope: <white>entire galaxy<reset>\n")
        end
        cecho(string.format("    Cartels explored: <white>%d/%d<reset>\n",
            galaxy_stats.cartels_explored, galaxy_stats.total_cartels))
    end
end

function f2t_map_explore_complete()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    f2t_map_explore_release_stamina()
    f2t_map_explore_unlock_temp_exits()
    cecho("\n<green>[map]<reset> Exploration Complete!\n")
    f2t_map_explore_show_statistics()
    -- Anything set here (a system sweep's expected-planet gap, currently the
    -- only user) is a result of the run, not a mid-run status update, and
    -- belongs after every last bit of movement (a return-to-link leg, a
    -- return-to-start leg) has actually finished - not wherever in the
    -- middle of that movement it happened to be detected.
    if F2T_MAP_EXPLORE_STATE.deferred_report then
        cecho("\n")
        cecho(F2T_MAP_EXPLORE_STATE.deferred_report)
    end
    if #F2T_MAP_EXPLORE_STATE.suspected_special_exits > 0 then
        cecho("\n  <yellow>Suspected Special Exits<reset> (manual mapping recommended):\n")
        for _, suspect in ipairs(F2T_MAP_EXPLORE_STATE.suspected_special_exits) do
            cecho(string.format("    - <white>%s<reset>\n", suspect.room_name or "Unknown"))
        end
    end
    cecho("\n")
    f2t_map_explore_brief_mode_restore()
    F2T_MAP_EXPLORE_STATE = blankState()
end

function f2t_map_explore_list_suspected()
    if #F2T_MAP_EXPLORE_STATE.suspected_special_exits == 0 then
        cecho("\n<yellow>[map-explore]<reset> No suspected special exits recorded\n"); return
    end
    cecho("\n<green>[map]<reset> Suspected Special Exits\n\n")
    for i, suspect in ipairs(F2T_MAP_EXPLORE_STATE.suspected_special_exits) do
        cecho(string.format("%d. <white>%s<reset>\n", i, suspect.room_name or "Unknown"))
    end
end

-- Whoever asked for this sweep may only have wanted something out of it, not
-- all of it. Returns true when the sweep has been ended.
--
-- Asked from two places, because a sweep is steered from two: the move loop
-- below, and the arrival handler, where the layered explorers make their own
-- decisions - "all expected planets found, start landing on them" among them.
-- Checking only in the move loop let a system sweep finish its space phase
-- and set off for the first planet before anyone asked whether the answer was
-- already in.
function f2t_map_explore_check_stop_condition()
    local stopWhen = F2T_MAP_EXPLORE_STATE.stop_when
    if not stopWhen then return false end
    local ok, done = pcall(stopWhen)
    if not ok or not done then return false end

    local onStop = F2T_MAP_EXPLORE_STATE.on_stop_early
    local reason = F2T_MAP_EXPLORE_STATE.stop_reason
    f2t_map_explore_set_stop_condition(nil)
    f2t_map_explore_stop(reason or "Found what this sweep was for - ending it early")
    if onStop then onStop() end
    return true
end

-- Watchdog: a run navigating with nothing in flight (no walk, customs, refuel
-- or escape) should always be on its way somewhere. One that has gone quiet
-- takes its next step rather than sitting there; the message marks where.
local STALL_SECONDS = 10
local lastActivity = os.time()

local function noteActivity() lastActivity = os.time() end

local function checkForStall()
    local state = F2T_MAP_EXPLORE_STATE
    if not state.active or state.paused or state.pause_requested or state.phase ~= "navigating"
        or state.refuel_state or state.escape_state
        or F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_CUSTOMS_PENDING then
        noteActivity()
        return
    end
    if os.time() - lastActivity < STALL_SECONDS then return end
    cecho("\n<yellow>[map-explore]<reset> Exploring had stalled; taking the next step\n")
    noteActivity()
    f2t_map_explore_next_step()
end

if F2T_EXPLORE_WATCHDOG_ID then killTimer(F2T_EXPLORE_WATCHDOG_ID) end
F2T_EXPLORE_WATCHDOG_ID = tempTimer(5, checkForStall, true)

function f2t_map_explore_next_step()
    noteActivity()
    if not F2T_MAP_EXPLORE_STATE.active then
        f2t_debug_log("[map/explore] next step: no run active")
        return
    end
    if F2T_MAP_EXPLORE_STATE.paused then
        f2t_debug_log("[map/explore] next step: paused (%s)", tostring(F2T_MAP_EXPLORE_STATE.paused_reason))
        return
    end
    if f2t_map_explore_check_deferred_pause() then return end
    if F2T_MAP_EXPLORE_STATE.phase == "paused_death" then
        f2t_debug_log("[map/explore] next step: paused for a death")
        return
    end

    -- Every kind of exploration steps through here, so this is where an
    -- uninsured player is stopped and asked before walking into the unknown.
    if f2t_insurance_allows and not f2t_insurance_allows() then
        F2T_MAP_EXPLORE_STATE.paused = true
        F2T_MAP_EXPLORE_STATE.paused_reason = "uninsured"
        cecho("\n<yellow>[map-explore]<reset> Paused: not insured\n")
        f2t_insurance_check("exploring", function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.paused_reason == "uninsured" then
                f2t_map_explore_resume()
            end
        end, function()
            if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_stop("Exploration stopped: not insured") end
        end)
        return
    end

    if f2t_map_explore_check_stop_condition() then return end

    -- Before committing to another move: if fuel has dropped to where refuel
    -- would buy, and we are in orbit over somewhere that sells it, go and get
    -- it. Left alone a big system runs the tank dry and the emergency trigger
    -- buys in space, which is the dearest fuel there is.
    if F2T_MAP_EXPLORE_STATE.phase ~= "refuelling"
        and f2t_map_explore_refuel_maybe_start() then
        return
    end

    local phase = F2T_MAP_EXPLORE_STATE.phase
    f2t_debug_log("[map/explore] next step: phase %s, mode %s, %d unexplored exits", tostring(phase),
        tostring(F2T_MAP_EXPLORE_STATE.mode), #F2T_MAP_EXPLORE_STATE.frontier_stack)

    -- Travel is navigation's; the trip's outcome drives the next step
    if phase == "travelling" then return end

    if phase == "navigating" then
        f2t_map_explore_navigate_to_next()
    elseif phase == "discovering_special" then
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        f2t_map_explore_next_step()
    -- system-specific phases (navigating_to_orbit, finding_exchange,
    -- planet_complete, finding_flags, navigating_to_flag) are handled in
    -- on_room_change
    elseif phase == "returning" then
        f2t_map_explore_return_to_start()
    end
end

function f2t_map_explore_on_room_change()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    noteActivity()
    if F2T_MAP_EXPLORE_STATE.paused then return end
    if F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_CUSTOMS_PENDING then return end
    if F2T_MAP_EXPLORE_STATE.phase == "travelling" then return end

    -- Before any layer acts on this arrival: it may have been the one that
    -- made the destination reachable, and everything below here is the sweep
    -- carrying on with work nobody needs any more.
    if not F2T_MAP_EXPLORE_STATE.refuel_state
        and f2t_map_explore_check_stop_condition() then
        return
    end

    -- Refuel detour: owns the explorer for its two moves, so the landing pad
    -- it visits never lands in a space sweep's visited rooms or frontier.
    if F2T_MAP_EXPLORE_STATE.refuel_state then
        F2T_SPEEDWALK_LAST_RESULT = nil
        if f2t_map_explore_refuel_on_room_change() then return end
    end

    -- Escape handling
    if F2T_MAP_EXPLORE_STATE.phase == "brief_escaping" and F2T_MAP_EXPLORE_STATE.escape_state then
        if F2T_SPEEDWALK_LAST_RESULT then
            local result = F2T_SPEEDWALK_LAST_RESULT
            F2T_SPEEDWALK_LAST_RESULT = nil
            if f2t_map_explore_escape_on_speedwalk_complete(result) then return end
        else
            if f2t_map_explore_escape_on_room_change() then return end
        end
    end

    -- Speedwalk result handling
    if F2T_SPEEDWALK_LAST_RESULT then
        local result = F2T_SPEEDWALK_LAST_RESULT
        F2T_SPEEDWALK_LAST_RESULT = nil
        if result == "failed" then
            local failed_room = F2T_SPEEDWALK_FAILED_EXIT_ROOM
            local failed_dir  = F2T_SPEEDWALK_FAILED_EXIT_DIR
            F2T_SPEEDWALK_FAILED_EXIT_ROOM = nil
            F2T_SPEEDWALK_FAILED_EXIT_DIR  = nil
            -- Only real directions can be locked; a special exit's command
            -- ("jump Maverick") is not one, and lockExit would either do
            -- nothing or corrupt the room's exit locks.
            if failed_dir and string.find(failed_dir, " ", 1, true) then
                f2t_debug_log("[map/explore] Not locking special exit '%s' as a direction", failed_dir)
                failed_dir = nil
            end
            if failed_room and failed_dir then
                f2t_map_explore_temp_lock_exit(failed_room, failed_dir)
                cecho(string.format(
                    "\n<yellow>[map-explore]<reset> Locked blocked exit %s from room %d, trying next...\n",
                    failed_dir, failed_room))
                F2T_MAP_EXPLORE_STATE.stats.blocked_exits = F2T_MAP_EXPLORE_STATE.stats.blocked_exits + 1
            end
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_next_step() end
            end)
            return
        elseif result == "stopped" then
            if F2T_MAP_EXPLORE_STATE.paused then return end
            cecho("\n<yellow>[map-explore]<reset> Navigation stopped by user, stopping exploration\n")
            f2t_map_explore_stop(); return
        end
    end

    if F2T_MAP_EXPLORE_STATE.paused or F2T_MAP_EXPLORE_STATE.phase == "paused_death" then return end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then return end

    -- Connect stub exit from previous move
    if F2T_MAP_EXPLORE_STATE.last_room_before_move and F2T_MAP_EXPLORE_STATE.last_direction_attempted then
        f2t_map_resolve_stub_exit(F2T_MAP_EXPLORE_STATE.last_room_before_move, current_room,
            F2T_MAP_EXPLORE_STATE.last_direction_attempted)
    end
    F2T_MAP_EXPLORE_STATE.last_room_before_move    = nil
    F2T_MAP_EXPLORE_STATE.last_direction_attempted = nil

    local is_first_visit = not F2T_MAP_EXPLORE_STATE.visited_rooms[current_room]
    if is_first_visit then
        F2T_MAP_EXPLORE_STATE.visited_rooms[current_room] = true
        F2T_MAP_EXPLORE_STATE.stats.rooms_discovered = F2T_MAP_EXPLORE_STATE.stats.rooms_discovered + 1

        if F2T_MAP_EXPLORE_STATE.target_room_name and F2T_MAP_EXPLORE_STATE.phase == "navigating" then
            f2t_map_explore_brief_check_target_room(current_room)
            if F2T_MAP_EXPLORE_STATE.target_room_found_id then return end
        end

        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count and F2T_MAP_EXPLORE_STATE.phase == "navigating" then
            f2t_map_explore_brief_check_room_flags(current_room)
            -- A named-room search keeps walking once the flags are all found
            if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0
                and not F2T_MAP_EXPLORE_STATE.target_room_name then
                return
            end
        end

        if F2T_MAP_EXPLORE_STATE.system_mode == "brief" and
           F2T_MAP_EXPLORE_STATE.system_phase == "exploring_space" and
           F2T_MAP_EXPLORE_STATE.phase == "navigating" then
            f2t_map_explore_system_check_room_for_planets(current_room)
            if F2T_MAP_EXPLORE_STATE.expected_planets_remaining and
               F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 then return end
        end

        if F2T_MAP_EXPLORE_STATE.phase == "navigating" and not F2T_MAP_EXPLORE_STATE.planned_exit then
            f2t_map_explore_recompute_frontier()
        end
    end

    -- System/Cartel phase transitions
    if F2T_MAP_EXPLORE_STATE.mode == "system" or F2T_MAP_EXPLORE_STATE.mode == "cartel" or
       F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
        if F2T_MAP_EXPLORE_STATE.phase == "navigating_to_orbit" then
            F2T_MAP_EXPLORE_STATE.phase = "at_orbit"
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.phase == "at_orbit" then
                    f2t_map_explore_system_board_planet()
                end
            end)
            return
        elseif F2T_MAP_EXPLORE_STATE.phase == "boarding_planet" then
            local planet_name = F2T_MAP_EXPLORE_STATE.brief_target_planet
            tempTimer(0.5, function()
                if not F2T_MAP_EXPLORE_STATE.active then return end
                if F2T_MAP_EXPLORE_STATE.system_phase == "running_brief" then
                    local override_flags = nil
                    if F2T_MAP_EXPLORE_STATE.planets_without_exchange and
                       F2T_MAP_EXPLORE_STATE.planets_without_exchange[planet_name] then
                        override_flags = {}
                        cecho("  <yellow>Note:<reset> Planet has no exchange, skipping exchange flag\n")
                    end
                    f2t_map_explore_planet_start("brief", planet_name, function()
                        f2t_map_explore_system_brief_next_planet()
                    end, override_flags)
                end
            end)
            return
        elseif F2T_MAP_EXPLORE_STATE.phase == "planet_complete" then
            local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]
            if planet then cecho(string.format("  <green>Exchange found on %s!<reset>\n", planet.name)) end
            local sys_stats = F2T_MAP_EXPLORE_STATE.system_stats
            sys_stats.planets_explored = sys_stats.planets_explored + 1
            sys_stats.exchanges_found  = sys_stats.exchanges_found  + 1
            if F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
                local c_stats = F2T_MAP_EXPLORE_STATE.cartel_stats
                c_stats.total_planets   = c_stats.total_planets   + 1
                c_stats.total_exchanges = c_stats.total_exchanges + 1
            end
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_system_next_planet() end
            end)
            return
        end
    end

    -- Area mode phase transitions
    if F2T_MAP_EXPLORE_STATE.phase == "navigating" then
        F2T_MAP_EXPLORE_STATE.phase = "discovering_special"
        f2t_map_explore_next_step()
    elseif F2T_MAP_EXPLORE_STATE.phase == "returning" then
        if current_room == F2T_MAP_EXPLORE_STATE.starting_room_id then
            f2t_map_explore_return_to_start()
        else
            f2t_map_explore_next_step()
        end
    end
end

f2t_debug_log("[map] Loaded explore.lua")
