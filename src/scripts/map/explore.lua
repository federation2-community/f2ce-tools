-- f2ce-tools map — Layer 1 core exploration engine (ported from map_explore.lua)

F2T_MAP_EXPLORE_STATE = F2T_MAP_EXPLORE_STATE or {
    active = false, paused = false, pause_requested = false, phase = nil, mode = nil, planet_mode = nil,
    starting_room_id = nil, starting_area_id = nil,
    visited_rooms = {}, frontier_stack = {},
    special_exit_patterns = {}, special_exit_attempts = {}, suspected_special_exits = {},
    death_room_id = nil, recovery_in_progress = false,
    last_room_before_move = nil, last_direction_attempted = nil,
    navigating_to_room_id = nil, temp_locked_exits = {},
    planned_exit = nil, escape_state = nil,
    stats = {rooms_discovered=0,special_exits_found=0,suspected_special_exits=0,blocked_exits=0,deaths=0},
    system_name=nil,system_mode=nil,space_area_id=nil,space_area_name=nil,system_phase=nil,
    planet_list={},current_planet_index=0,
    expected_planets=nil,expected_planets_found=nil,expected_planets_remaining=nil,planets_without_exchange=nil,
    system_stats={planets_explored=0,exchanges_found=0,planets_skipped=0},
    cartel_name=nil,system_list={},current_system_index=0,
    cartel_stats={total_systems=0,systems_explored=0,total_planets=0,total_exchanges=0,total_planets_skipped=0},
    galaxy_cartel_list={},galaxy_current_cartel_index=0,
    galaxy_stats={total_cartels=0,cartels_explored=0,cartels_skipped=0,total_systems=0,total_planets=0},
    travel_kind=nil,travel_target=nil,travel_on_arrived=nil,travel_on_failed=nil,
}

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
    F2T_MAP_EXPLORE_STATE = {
        active=true, paused=false, pause_requested=false, phase="navigating",
        starting_room_id=current_room, starting_area_id=area_id,
        visited_rooms={[current_room]=true}, frontier_stack={}, planned_exit=nil,
        special_exit_patterns={}, special_exit_attempts={}, suspected_special_exits={},
        death_room_id=nil, recovery_in_progress=false,
        last_room_before_move=nil, last_direction_attempted=nil,
        temp_locked_exits={},
        stats={rooms_discovered=1,special_exits_found=0,suspected_special_exits=0,blocked_exits=0,deaths=0},
    }
    if mode_fields then
        for k, v in pairs(mode_fields) do F2T_MAP_EXPLORE_STATE[k] = v end
    end
    f2t_map_explore_recompute_frontier()
    return #F2T_MAP_EXPLORE_STATE.frontier_stack
end

-- Walk to a mapped planet before starting Layer 1 exploration there. This is
-- a plain getPath() walk, not a jump chain - any topology-modeled system
-- already has "jump <system>" special exits on its link room (see
-- topology.lua's f2t_map_topology_rebuild_exits), so ordinary pathfinding
-- already crosses legal jumps on its own. The blind jump-chain builder is
-- only needed to reach territory with no rooms mapped yet at all, which a
-- single named planet can't be (f2t_map_lookup_planet already requires the
-- planet's area to exist).
function f2t_map_explore_travel_to_planet(planet_mode, planet_name, on_complete_callback, override_flags,
                                           target_room_name, target_room_exact)
    local function start_here()
        return f2t_map_explore_planet_start(planet_mode, planet_name, on_complete_callback,
            override_flags, target_room_name, target_room_exact)
    end

    local function await_arrival()
        local handler_id
        handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
            if F2T_SPEEDWALK_ACTIVE then return end
            killAnonymousEventHandler(handler_id)
            local area = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
            local arrived_planet = area and getRoomAreaName(area)
            if not arrived_planet or arrived_planet:lower() ~= planet_name:lower() then
                cecho(string.format("\n<red>[map-explore]<reset> Could not reach %s\n", planet_name))
                return
            end
            start_here()
        end)
    end

    -- Not given suppress_hint: this is exactly the case that should be allowed
    -- to auto-resolve a totally-unmapped planet via whereis (f2t_map_navigate's
    -- own guard already refuses to do this while a sweep is already active).
    local nav_result = f2t_map_navigate(planet_name, {
        on_result = function(success)
            -- Only fires for the async (hint-driven) path: whereis/auto-explore
            -- either got us resolvable (arrival may still be in flight) or didn't.
            if not success then
                cecho(string.format("\n<red>[map-explore]<reset> Cannot reach %s\n", planet_name))
                return
            end
            if F2T_SPEEDWALK_ACTIVE then await_arrival() else start_here() end
        end,
    })

    if nav_result == nil then
        return true -- resolving asynchronously; on_result above continues the pipeline
    end
    if not nav_result then
        cecho(string.format("\n<red>[map-explore]<reset> Cannot reach %s\n", planet_name))
        return false
    end
    if not F2T_SPEEDWALK_ACTIVE then
        return start_here()
    end
    await_arrival()
    return true
end

function f2t_map_explore_planet_start(planet_mode, planet_name, on_complete_callback, override_flags,
                                       target_room_name, target_room_exact)
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
                target_room_name, target_room_exact)
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
        local brief_flags_set = {}
        for _, flag in ipairs(brief_flags) do brief_flags_set[flag] = true end
        local brief_flags_found = {}
        local flags_already_found = 0
        for _, flag in ipairs(brief_flags) do
            local existing_room = f2t_map_find_room_with_flag(current_area, flag)
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
        end
    end

    if on_complete_callback then
        -- Nested (parent sweep already has .active/hooks) or a standalone
        -- callback-driven call (e.g. f2t_map_navigate's hint resolver, or an
        -- Akaturi target-room search) that hasn't started anything yet -
        -- ensure both here too, and unwind them once completion fires, same
        -- as f2t_map_explore_system_start_with_planets does for system-level.
        local started_standalone = not F2T_MAP_EXPLORE_STATE.active
        if started_standalone then
            F2T_MAP_EXPLORE_STATE.active = true
            f2t_map_explore_register_safety_hooks()
            local real_callback = on_complete_callback
            on_complete_callback = function(...)
                F2T_MAP_EXPLORE_STATE.active = false
                f2t_map_clear_nav_owner()
                if f2t_stamina_unregister_client then f2t_stamina_unregister_client() end
                real_callback(...)
            end
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

function f2t_map_explore_brief_call_callback()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback
    if callback then callback()
    else f2t_map_explore_complete()
    end
end

-- Nav-owner + stamina-monitor safety hooks shared by every standalone explore
-- entry point (system/cartel/galaxy/syndicate all register the same pair;
-- nested layers skip this since the parent that started the sweep already holds it).
function f2t_map_explore_register_safety_hooks()
    f2t_map_set_nav_owner("map-explore", function(reason)
        if reason == "customs" then
            F2T_MAP_EXPLORE_STATE.paused = true
            F2T_MAP_EXPLORE_STATE.paused_reason = reason
        end
        return {auto_resume = true}
    end)

    if f2t_stamina_register_client then
        f2t_stamina_register_client({
            pause_callback  = f2t_map_explore_pause,
            resume_callback = f2t_map_explore_resume,
            check_active = function()
                return F2T_MAP_EXPLORE_STATE.active and not F2T_MAP_EXPLORE_STATE.paused
            end,
        })
    end
end

-- Shared travel-to-container primitive: reach an unmapped system or cartel
-- hub via a blind jump chain built from the topology model, or a plain walk
-- when we're already in the target's home system/cartel. Used standalone or
-- nested under any layer's sweep. on_arrived()/on_failed() are stored on
-- state and fired once the gmcp.room.info dispatcher (below) confirms
-- arrival or a failure; on_failed is optional (a no-op if omitted).

--- @param kind string "system" or "cartel"
--- @param target string Target system or cartel name
function f2t_map_explore_await_arrival(kind, target, on_arrived, on_failed)
    F2T_MAP_EXPLORE_STATE.travel_kind = kind
    F2T_MAP_EXPLORE_STATE.travel_target = target
    F2T_MAP_EXPLORE_STATE.travel_on_arrived = on_arrived
    F2T_MAP_EXPLORE_STATE.travel_on_failed = on_failed
    F2T_MAP_EXPLORE_STATE.phase = "explore_travel_arriving"
end

function f2t_map_explore_travel_to(kind, target, on_arrived, on_failed)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room and f2t_map_room_has_flag(current_room, "link") then
        f2t_map_explore_await_arrival(kind, target, on_arrived, on_failed)
        f2t_map_explore_travel_jump()
        return
    end

    local current_system = current_room and getRoomUserData(current_room, "fed2_system")
    local link_destination = current_system and (current_system .. " Space link") or "link"
    cecho(string.format("  <dim_grey>Navigating to link to jump to %s<reset>\n", target))
    f2t_map_explore_await_arrival(kind, target, on_arrived, on_failed)
    F2T_MAP_EXPLORE_STATE.phase = "explore_travel_jumping"
    local nav_result = f2t_map_navigate(link_destination)
    if nav_result == nil then
        cecho(string.format("  <red>Error:<reset> Cannot navigate to a link room to reach %s\n", target))
        f2t_map_explore_travel_finish(false)
    end
    -- true/false (already there / speedwalk or retry-pending): wait for the
    -- room-change dispatcher to drive the next step.
end

-- Issue the blind jump chain toward the stored travel target from the link
-- room we're standing in. Falls back to a single direct jump when the model
-- can't build a chain (it may still be legal, just not modeled yet).
function f2t_map_explore_travel_jump()
    local target = F2T_MAP_EXPLORE_STATE.travel_target
    local current_system = f2t_get_current_system()
    local chain = current_system and f2t_map_topology_jump_chain(current_system, target)
    if not chain or #chain == 0 then
        chain = {string.format("jump %s", target)}
    end
    cecho(string.format("  <dim_grey>Jumping: %s<reset>\n", table.concat(chain, "; ")))
    speedWalkDir = chain
    speedWalkPath = {}
    doSpeedWalk()
    F2T_MAP_EXPLORE_STATE.phase = "explore_travel_arriving"
end

-- Fire the stored callback for the outcome and clear travel state either way.
function f2t_map_explore_travel_finish(arrived)
    local on_arrived = F2T_MAP_EXPLORE_STATE.travel_on_arrived
    local on_failed = F2T_MAP_EXPLORE_STATE.travel_on_failed
    local target = F2T_MAP_EXPLORE_STATE.travel_target
    F2T_MAP_EXPLORE_STATE.travel_kind = nil
    F2T_MAP_EXPLORE_STATE.travel_target = nil
    F2T_MAP_EXPLORE_STATE.travel_on_arrived = nil
    F2T_MAP_EXPLORE_STATE.travel_on_failed = nil
    F2T_MAP_EXPLORE_STATE.phase = nil

    if not arrived then
        if on_failed then on_failed() end
        return
    end

    cecho(string.format("  <green>Arrived at %s!<reset>\n", target))
    tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_STATE.active and on_arrived then on_arrived() end
    end)
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

function f2t_map_explore_unlock_temp_exits()
    if not F2T_MAP_EXPLORE_STATE.temp_locked_exits then return end
    for room_id, directions in pairs(F2T_MAP_EXPLORE_STATE.temp_locked_exits) do
        for _, direction in ipairs(directions) do lockExit(room_id, direction, false) end
    end
    F2T_MAP_EXPLORE_STATE.temp_locked_exits = {}
end

local function CLEAR_STATE()
    return {
        active=false,paused=false,pause_requested=false,phase=nil,
        visited_rooms={},frontier_stack={},planned_exit=nil,
        special_exit_patterns={},special_exit_attempts={},suspected_special_exits={},
        death_room_id=nil,recovery_in_progress=false,
        last_room_before_move=nil,last_direction_attempted=nil,temp_locked_exits={},
        stats={rooms_discovered=0,special_exits_found=0,suspected_special_exits=0,blocked_exits=0,deaths=0},
        mode=nil,system_name=nil,system_mode=nil,expected_planets=nil,
        expected_planets_found=nil,expected_planets_remaining=nil,planets_without_exchange=nil,
        cartel_name=nil,planet_list={},current_planet_index=0,system_list={},current_system_index=0,
        system_stats={planets_explored=0,exchanges_found=0,planets_skipped=0},
        cartel_stats={total_systems=0,systems_explored=0,total_planets=0,total_exchanges=0,total_planets_skipped=0},
        galaxy_cartel_list={},galaxy_current_cartel_index=0,
        galaxy_stats={total_cartels=0,cartels_explored=0,cartels_skipped=0,total_systems=0,total_planets=0},
        travel_kind=nil,travel_target=nil,travel_on_arrived=nil,travel_on_failed=nil,
    }
end

function f2t_map_explore_stop()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n"); return
    end
    f2t_map_clear_nav_owner()
    if f2t_stamina_unregister_client then f2t_stamina_unregister_client() end
    f2t_map_explore_unlock_temp_exits()
    cecho("\n<yellow>[map]<reset> Exploration stopped by user\n")
    f2t_map_explore_show_statistics()
    f2t_map_explore_brief_mode_restore()
    F2T_MAP_EXPLORE_STATE = CLEAR_STATE()
end

function f2t_map_explore_pause()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n"); return
    end
    if F2T_MAP_EXPLORE_STATE.paused or F2T_MAP_EXPLORE_STATE.pause_requested then
        cecho("\n<yellow>[map-explore]<reset> Exploration already paused\n"); return
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
    if F2T_MAP_EXPLORE_STATE.paused_reason == "stranded" then
        F2T_MAP_EXPLORE_STATE.paused_reason = nil
        local destination = F2T_MAP_EXPLORE_STATE.paused_destination
        F2T_MAP_EXPLORE_STATE.paused_destination = nil
        if F2T_MAP_EXPLORE_STATE.brief_flags_found then
            f2t_map_explore_brief_return_to_shuttlepad(); return
        elseif destination then
            if f2t_map_navigate(tostring(destination)) then
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
    local state_str = "ACTIVE"
    if F2T_MAP_EXPLORE_STATE.paused then
        state_str = F2T_MAP_EXPLORE_STATE.paused_reason == "stranded" and "PAUSED (stranded)" or "PAUSED"
    end
    cecho(string.format("  State: <white>%s<reset>\n", state_str))
    cecho(string.format("  Phase: <white>%s<reset>\n", F2T_MAP_EXPLORE_STATE.phase or "unknown"))
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
    if f2t_stamina_unregister_client then f2t_stamina_unregister_client() end
    f2t_map_explore_unlock_temp_exits()
    cecho("\n<green>[map]<reset> Exploration Complete!\n")
    f2t_map_explore_show_statistics()
    if #F2T_MAP_EXPLORE_STATE.suspected_special_exits > 0 then
        cecho("\n  <yellow>Suspected Special Exits<reset> (manual mapping recommended):\n")
        for _, suspect in ipairs(F2T_MAP_EXPLORE_STATE.suspected_special_exits) do
            cecho(string.format("    - <white>%s<reset>\n", suspect.room_name or "Unknown"))
        end
    end
    cecho("\n")
    f2t_map_explore_brief_mode_restore()
    F2T_MAP_EXPLORE_STATE = CLEAR_STATE()
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

function f2t_map_explore_next_step()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.paused then return end
    if f2t_map_explore_check_deferred_pause() then return end
    if F2T_MAP_EXPLORE_STATE.phase == "paused_death" then return end

    local phase = F2T_MAP_EXPLORE_STATE.phase

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
    if F2T_MAP_EXPLORE_STATE.paused then return end
    if F2T_SPEEDWALK_ACTIVE then return end

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
            if failed_room and failed_dir then
                lockExit(failed_room, failed_dir, true)
                cecho(string.format(
                    "\n<yellow>[map-explore]<reset> Locked blocked exit %s from room %d, trying next...\n",
                    failed_dir, failed_room))
                if not F2T_MAP_EXPLORE_STATE.temp_locked_exits[failed_room] then
                    F2T_MAP_EXPLORE_STATE.temp_locked_exits[failed_room] = {}
                end
                table.insert(F2T_MAP_EXPLORE_STATE.temp_locked_exits[failed_room], failed_dir)
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
            if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 then return end
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

    -- Shared travel-to-container phase transitions (system or cartel target,
    -- used standalone or nested under any layer's sweep).
    if F2T_MAP_EXPLORE_STATE.phase == "explore_travel_jumping" then
        f2t_map_explore_travel_jump(); return
    elseif F2T_MAP_EXPLORE_STATE.phase == "explore_travel_arriving" then
        local kind = F2T_MAP_EXPLORE_STATE.travel_kind
        local target = F2T_MAP_EXPLORE_STATE.travel_target
        local arrived
        if kind == "cartel" then
            local current_cartel = f2t_map_get_current_cartel()
            arrived = current_cartel ~= nil and current_cartel:lower() == target:lower()
        else
            arrived = getRoomUserData(current_room, "fed2_system") == target
        end
        if not arrived then
            cecho(string.format("  <red>Error:<reset> Jump failed, could not reach %s\n", target))
        end
        f2t_map_explore_travel_finish(arrived)
        return
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
