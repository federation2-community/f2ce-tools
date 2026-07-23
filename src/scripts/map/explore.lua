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
    cartel_name=nil,system_list={},current_system_index=0,cartel_target_system=nil,
    cartel_stats={total_systems=0,systems_explored=0,total_planets=0,total_exchanges=0,total_planets_skipped=0},
    galaxy_cartel_list={},galaxy_current_cartel_index=0,galaxy_target_cartel=nil,
    galaxy_stats={total_cartels=0,cartels_explored=0,cartels_skipped=0,total_systems=0,total_planets=0},
}

F2T_EXPLORE_BRIEF_OWNER = false

function f2t_map_explore_brief_mode_start()
    if not f2t_settings_get("map", "speedwalk_brief") then return end
    F2T_EXPLORE_BRIEF_OWNER = true
    send("brief")
end

function f2t_map_explore_brief_mode_restore()
    if not F2T_EXPLORE_BRIEF_OWNER then return end
    F2T_EXPLORE_BRIEF_OWNER = false
    local after_mode = f2t_settings_get("map", "speedwalk_after_mode") or "full"
    send(after_mode)
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

function f2t_map_explore_planet_start(planet_mode, planet_name, on_complete_callback, override_flags)
    if not planet_mode or (planet_mode ~= "full" and planet_mode ~= "brief") then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid planet mode '%s'\n", tostring(planet_mode)))
        return false
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
        local brief_flags = {"shuttlepad"}
        if override_flags then
            for _, flag in ipairs(override_flags) do
                if flag ~= "shuttlepad" then table.insert(brief_flags, flag) end
            end
        else
            local additional_flags_str = f2t_settings_get("map", "brief_additional_flags") or "exchange"
            for flag in string.gmatch(additional_flags_str, "[^,]+") do
                local trimmed = flag:match("^%s*(.-)%s*$")
                if trimmed ~= "" and trimmed ~= "shuttlepad" then table.insert(brief_flags, trimmed) end
            end
        end
        local system_name = getAreaUserData(current_area, "fed2_system") or ""
        if string.lower(system_name) ~= "sol" then
            for i = #brief_flags, 1, -1 do
                if brief_flags[i] == "courier" then table.remove(brief_flags, i) end
            end
        end
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
    end

    if on_complete_callback then
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
    end

    if planet_mode == "brief" then
        f2t_map_explore_brief_check_room_flags(current_room)
        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 then
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
                    if string.lower(system_name) ~= "sol" then
                        local non_courier = 0
                        for rf, _ in pairs(F2T_MAP_EXPLORE_STATE.brief_flags_set) do
                            if not flags_found[rf] and rf ~= "courier" then non_courier = non_courier + 1 end
                        end
                        if non_courier == 0 then effective_remaining = 0 end
                    end
                end
                if effective_remaining == 0 then
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

    f2t_map_set_nav_owner("map-explore", function(reason)
        if reason == "customs" then
            F2T_MAP_EXPLORE_STATE.paused = true
            F2T_MAP_EXPLORE_STATE.paused_reason = reason
        end
        return {auto_resume = true}
    end)

    -- Stamina monitor integration (no-op if not available)
    if f2t_stamina_register_client then
        f2t_stamina_register_client({
            pause_callback  = f2t_map_explore_pause,
            resume_callback = f2t_map_explore_resume,
            check_active = function()
                return F2T_MAP_EXPLORE_STATE.active and not F2T_MAP_EXPLORE_STATE.paused
            end,
        })
    end

    if name and name ~= "" then
        local is_planet = f2t_map_lookup_planet(name)
        local is_system = f2t_map_lookup_system(name)
        if is_system and is_planet then
            local system_fully_mapped = f2t_map_explore_is_system_fully_mapped(name)
            if system_fully_mapped then return f2t_map_explore_planet_start(mode, name)
            else return f2t_map_explore_system_start(name, mode)
            end
        elseif is_system then
            return f2t_map_explore_system_start(name, mode)
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
        return f2t_map_explore_system_start(system, mode)
    end

    local planet = f2t_get_current_planet()
    return f2t_map_explore_planet_start(mode, planet)
end

function f2t_map_explore_is_system_fully_mapped(system_name)
    local space_area_name = f2t_map_get_system_space_area_actual(system_name)
    if not space_area_name then return false end
    local space_area_id = f2t_map_get_area_id(space_area_name)
    if not space_area_id then return false end
    local rooms_in_area = getAreaRooms(space_area_id)
    if not rooms_in_area then return false end
    local planets_found = {}
    for _, room_id in pairs(rooms_in_area) do
        local planet_name = getRoomUserData(room_id, "fed2_planet")
        if planet_name and planet_name ~= "" then planets_found[planet_name] = true end
    end
    if next(planets_found) == nil then return false end
    for planet_name, _ in pairs(planets_found) do
        local planet_area_id = f2t_map_get_area_id(planet_name)
        if not planet_area_id then return false end
        local sp = f2t_map_find_all_rooms_with_flag(planet_area_id, "shuttlepad")
        if not sp or #sp == 0 then return false end
        local ex = f2t_map_find_all_rooms_with_flag(planet_area_id, "exchange")
        if not ex or #ex == 0 then return false end
    end
    return true
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
        galaxy_cartel_list={},galaxy_current_cartel_index=0,galaxy_target_cartel=nil,
        galaxy_stats={total_cartels=0,cartels_explored=0,cartels_skipped=0,total_systems=0,total_planets=0},
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

    -- Galaxy phase transitions
    if F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
        if F2T_MAP_EXPLORE_STATE.phase == "jumping_to_cartel" then
            f2t_map_explore_jump_to_cartel(F2T_MAP_EXPLORE_STATE.galaxy_target_cartel); return
        elseif F2T_MAP_EXPLORE_STATE.phase == "arriving_in_cartel" then
            local target_cartel  = F2T_MAP_EXPLORE_STATE.galaxy_target_cartel
            local current_cartel = f2t_map_get_current_cartel()
            if not current_cartel or current_cartel:lower() ~= target_cartel:lower() then
                cecho(string.format("  <red>Error:<reset> Jump failed (expected %s, got %s)\n",
                    target_cartel, current_cartel or "unknown"))
                F2T_MAP_EXPLORE_STATE.phase = nil
                f2t_map_explore_galaxy_next_cartel(); return
            end
            cecho(string.format("  <green>Arrived in %s!<reset>\n", target_cartel))
            F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored =
                F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored + 1
            F2T_MAP_EXPLORE_STATE.phase = nil
            F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_galaxy_start_cartel_mode(target_cartel) end
            end)
            return
        end
    end

    -- System/Cartel phase transitions
    if F2T_MAP_EXPLORE_STATE.mode == "system" or F2T_MAP_EXPLORE_STATE.mode == "cartel" or
       F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
        if F2T_MAP_EXPLORE_STATE.phase == "jumping_to_system" then
            f2t_map_explore_jump_to_system(F2T_MAP_EXPLORE_STATE.cartel_target_system); return
        elseif F2T_MAP_EXPLORE_STATE.phase == "arriving_in_system" then
            local target_system  = F2T_MAP_EXPLORE_STATE.cartel_target_system
            local current_system = getRoomUserData(current_room, "fed2_system")
            if current_system ~= target_system then
                cecho(string.format("  <red>Error:<reset> Jump failed\n"))
                F2T_MAP_EXPLORE_STATE.phase = nil
                f2t_map_explore_cartel_next_system(); return
            end
            cecho(string.format("  <green>Arrived in %s!<reset>\n", target_system))
            F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored =
                F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1
            F2T_MAP_EXPLORE_STATE.phase = nil
            F2T_MAP_EXPLORE_STATE.cartel_target_system = nil
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then f2t_map_explore_cartel_start_system_mode(target_system) end
            end)
            return
        elseif F2T_MAP_EXPLORE_STATE.phase == "navigating_to_orbit" then
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
