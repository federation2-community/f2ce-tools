-- f2ce-tools map — Layer 2 system exploration (ported from map_explore_system.lua)
--
-- Two phases: explore "{System} Space" (delegates to Layer 1), then brief
-- exploration of each discovered planet. Runs standalone (mode="system") or
-- nested under cartel/galaxy exploration (parent mode preserved, callback
-- chains back up).

function f2t_map_explore_system_start(system_name, system_mode, on_complete_callback)
    if not system_name or system_name == "" then
        cecho("\n<red>[map-explore]<reset> Error: No system specified\n")
        return false
    end

    system_mode = string.lower(system_mode or "brief")
    if system_mode ~= "full" and system_mode ~= "brief" then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid system mode '%s'\n", system_mode))
        return false
    end
    if on_complete_callback and system_mode ~= "brief" then
        system_mode = "brief"
    end

    system_name = system_name:gsub("^%l", string.upper)

    if system_mode == "brief" then
        cecho(string.format(
            "\n<green>[map-explore]<reset> Starting system exploration: <white>%s<reset> (<cyan>brief mode<reset>)\n",
            system_name))
        cecho("  <dim_grey>Capturing expected planet list...<reset>\n")
        f2t_map_di_system_capture_start(system_name, function(expected_planet_names, planets_without_exchange)
            f2t_map_explore_system_start_with_planets(system_name, system_mode,
                expected_planet_names, planets_without_exchange, on_complete_callback)
        end)
        return true
    end

    f2t_map_explore_system_start_with_planets(system_name, system_mode, nil, nil, on_complete_callback)
    return true
end

function f2t_map_explore_system_start_with_planets(system_name, system_mode, expected_planet_names,
                                                   planets_without_exchange, on_complete_callback)
    local expected_planets_set = nil
    local expected_planets_found_set = nil
    local expected_planets_remaining_count = nil

    if system_mode == "brief" and expected_planet_names then
        if #expected_planet_names == 0 then
            cecho(string.format("\n<yellow>[map-explore]<reset> No planets found in %s via DI system\n", system_name))
            cecho("<dim_grey>Falling back to full space exploration<reset>\n")
            system_mode = "full"
        else
            expected_planets_set = {}
            expected_planets_found_set = {}
            for _, planet_name in ipairs(expected_planet_names) do
                expected_planets_set[planet_name] = true
            end

            -- Orbit rooms carry fed2_planet userdata; check the system's own
            -- space area rather than scanning the whole room database.
            local space_area_check = f2t_map_get_system_space_area_actual(system_name)
            local space_area_check_id = space_area_check and f2t_map_get_area_id(space_area_check)
            local known_count = 0
            if space_area_check_id then
                for _, room_id in pairs(getAreaRooms(space_area_check_id) or {}) do
                    local room_planet = getRoomUserData(room_id, "fed2_planet")
                    if room_planet and expected_planets_set[room_planet]
                       and not expected_planets_found_set[room_planet] then
                        expected_planets_found_set[room_planet] = true
                        known_count = known_count + 1
                    end
                end
            end
            expected_planets_remaining_count = #expected_planet_names - known_count

            cecho(string.format("  <green>Found %d expected planet(s)<reset>\n", #expected_planet_names))
            if known_count > 0 then
                cecho(string.format("  <cyan>Already mapped:<reset> %d planet(s)\n", known_count))
            end
        end
    end

    local space_area_name = f2t_map_get_system_space_area_actual(system_name)
    if not space_area_name then
        cecho(string.format("\n<yellow>[map-explore]<reset> System '%s' space not mapped yet\n", system_name))
        cecho(string.format("<dim_grey>Visit at least one room in '%s Space' first<reset>\n", system_name))
        return false
    end
    local space_area_id = f2t_map_get_area_id(space_area_name)
    if not space_area_id then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Could not find area ID for '%s'\n", space_area_name))
        return false
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local current_area = current_room and getRoomArea(current_room)
    if current_area ~= space_area_id then
        cecho(string.format("\n<yellow>[map-explore]<reset> Not in %s, please navigate there first\n", space_area_name))
        cecho(string.format("<dim_grey>Use: nav %s<reset>\n", system_name))
        return false
    end

    if system_mode == "full" then
        cecho(string.format(
            "\n<green>[map-explore]<reset> Starting system exploration: <white>%s<reset> (<cyan>full mode<reset>)\n",
            system_name))
        cecho(string.format("  <dim_grey>Phase 1: Exploring entire %s area<reset>\n", space_area_name))
    else
        cecho(string.format("  <dim_grey>Phase 1: Exploring %s to find expected planets<reset>\n", space_area_name))
    end

    local system_stats = {
        total_planets = 0, planets_explored = 0, exchanges_found = 0, planets_skipped = 0,
    }

    if on_complete_callback then
        -- Nested: preserve parent mode (cartel/galaxy), just add Layer 2 fields.
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        F2T_MAP_EXPLORE_STATE.system_name = system_name
        F2T_MAP_EXPLORE_STATE.system_mode = system_mode
        F2T_MAP_EXPLORE_STATE.space_area_id = space_area_id
        F2T_MAP_EXPLORE_STATE.space_area_name = space_area_name
        F2T_MAP_EXPLORE_STATE.planet_list = {}
        F2T_MAP_EXPLORE_STATE.current_planet_index = 0
        F2T_MAP_EXPLORE_STATE.system_phase = "exploring_space"
        F2T_MAP_EXPLORE_STATE.expected_planets = expected_planets_set
        F2T_MAP_EXPLORE_STATE.expected_planets_found = expected_planets_found_set
        F2T_MAP_EXPLORE_STATE.expected_planets_remaining = expected_planets_remaining_count
        F2T_MAP_EXPLORE_STATE.planets_without_exchange = planets_without_exchange
        F2T_MAP_EXPLORE_STATE.system_stats = system_stats
        F2T_MAP_EXPLORE_STATE.brief_planet_name = nil
        F2T_MAP_EXPLORE_STATE.brief_flags = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_set = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_found = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count = nil
        F2T_MAP_EXPLORE_STATE.brief_target_planet = nil
        F2T_MAP_EXPLORE_STATE.system_complete_callback = on_complete_callback
        F2T_MAP_EXPLORE_STATE.on_complete_callback = function()
            f2t_map_explore_system_space_complete()
        end
        F2T_MAP_EXPLORE_STATE.starting_room_id = current_room
        F2T_MAP_EXPLORE_STATE.starting_area_id = space_area_id
        F2T_MAP_EXPLORE_STATE.visited_rooms = {[current_room] = true}
        F2T_MAP_EXPLORE_STATE.frontier_stack = {}
    else
        f2t_map_explore_init_area(space_area_id, {
            mode = "system",
            system_name = system_name,
            system_mode = system_mode,
            space_area_id = space_area_id,
            space_area_name = space_area_name,
            planet_list = {},
            current_planet_index = 0,
            system_phase = "exploring_space",
            expected_planets = expected_planets_set,
            expected_planets_found = expected_planets_found_set,
            expected_planets_remaining = expected_planets_remaining_count,
            planets_without_exchange = planets_without_exchange,
            system_stats = system_stats,
            on_complete_callback = function()
                f2t_map_explore_system_space_complete()
            end,
        })
    end

    f2t_map_explore_recompute_frontier()

    local room_name = getRoomName(F2T_MAP_CURRENT_ROOM_ID) or "Unknown"
    cecho(string.format("  Starting room: <white>%s<reset> (ID: %d)\n", room_name, F2T_MAP_CURRENT_ROOM_ID))

    if system_mode == "brief" and
       F2T_MAP_EXPLORE_STATE.expected_planets_remaining and
       F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 then
        cecho("  <green>All expected planets already mapped!<reset> Skipping space exploration.\n")
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active then
                f2t_map_explore_system_space_complete()
            end
        end)
    else
        f2t_map_explore_next_step()
    end

    return true
end

function f2t_map_explore_system_space_complete()
    local space_area_id = F2T_MAP_EXPLORE_STATE.space_area_id
    local planets = {}

    if F2T_MAP_EXPLORE_STATE.system_mode == "brief" and F2T_MAP_EXPLORE_STATE.expected_planets_found then
        for planet_name, _ in pairs(F2T_MAP_EXPLORE_STATE.expected_planets_found) do
            local orbit_room_id = nil
            for _, room_id in pairs(getAreaRooms(space_area_id) or {}) do
                if getRoomUserData(room_id, "fed2_planet") == planet_name then
                    orbit_room_id = room_id
                    break
                end
            end
            if orbit_room_id then
                table.insert(planets, {name = planet_name, orbit_room_id = orbit_room_id})
            else
                f2t_debug_log("[map-explore-system] WARNING: Expected planet %s has no orbit room", planet_name)
            end
        end
    else
        local seen = {}
        for _, room_id in pairs(getAreaRooms(space_area_id) or {}) do
            local planet_name = getRoomUserData(room_id, "fed2_planet")
            if planet_name and planet_name ~= "" and not seen[planet_name] then
                seen[planet_name] = true
                table.insert(planets, {name = planet_name, orbit_room_id = room_id})
            end
        end
    end

    if #planets == 0 then
        cecho("\n<yellow>[map-explore]<reset> No planets identified in this system's space\n")
        f2t_map_explore_system_return_to_link_and_complete()
        return
    end

    table.sort(planets, function(a, b) return a.name < b.name end)

    -- Skip planets that already have all required brief flags mapped.
    local additional_flags_str = f2t_settings_get("map", "brief_additional_flags") or "exchange"
    local required_flags = {"shuttlepad"}
    for flag in string.gmatch(additional_flags_str, "[^,]+") do
        local trimmed = flag:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed ~= "shuttlepad" then table.insert(required_flags, trimmed) end
    end
    local system_name = F2T_MAP_EXPLORE_STATE.system_name or ""
    if system_name:lower() ~= "sol" then
        for i = #required_flags, 1, -1 do
            if required_flags[i] == "courier" then table.remove(required_flags, i) end
        end
    end

    local planets_to_explore = {}
    local already_explored = 0
    for _, planet in ipairs(planets) do
        local planet_area_id = f2t_map_get_area_id(planet.name)
        local all_flags_found = false
        if planet_area_id then
            all_flags_found = true
            for _, flag in ipairs(required_flags) do
                local skip_flag = flag == "exchange" and
                    F2T_MAP_EXPLORE_STATE.planets_without_exchange and
                    F2T_MAP_EXPLORE_STATE.planets_without_exchange[planet.name]
                if not skip_flag and not f2t_map_find_room_with_flag(planet_area_id, flag) then
                    all_flags_found = false
                    break
                end
            end
        end
        if all_flags_found then
            already_explored = already_explored + 1
        else
            table.insert(planets_to_explore, planet)
        end
    end

    F2T_MAP_EXPLORE_STATE.planet_list = planets_to_explore
    F2T_MAP_EXPLORE_STATE.current_planet_index = 0
    F2T_MAP_EXPLORE_STATE.system_stats.total_planets = #planets
    for _ = 1, already_explored do
        F2T_MAP_EXPLORE_STATE.system_stats.planets_explored = F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
        F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found = F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
    end

    cecho(string.format("\n  <green>Space exploration complete!<reset> Discovered %d planet(s)\n", #planets))
    if already_explored > 0 then
        cecho(string.format("  <cyan>Already explored:<reset> %d planet(s) (skipping)\n", already_explored))
    end

    if #planets_to_explore == 0 then
        cecho("\n<green>[map-explore]<reset> All planets already explored! System exploration complete.\n")
        f2t_map_explore_system_return_to_link_and_complete()
        return
    end

    cecho(string.format("  <white>To explore:<reset> %d planet(s)\n", #planets_to_explore))
    cecho("  <dim_grey>Phase 2: Brief exploration of each planet<reset>\n\n")
    F2T_MAP_EXPLORE_STATE.system_phase = "running_brief"
    f2t_map_explore_system_brief_next_planet()
end

function f2t_map_explore_system_next_planet()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local mode = F2T_MAP_EXPLORE_STATE.mode
    if mode ~= "system" and mode ~= "cartel" and mode ~= "galaxy" then return end
    -- Brief workflow is the only supported per-planet path; route back into it.
    F2T_MAP_EXPLORE_STATE.system_phase = "running_brief"
    f2t_map_explore_system_brief_next_planet()
end

function f2t_map_explore_system_board_planet()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.phase ~= "at_orbit" then return end
    local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]
    if not planet then return end
    cecho("  <dim_grey>Boarding planet...<reset>\n")
    F2T_MAP_EXPLORE_STATE.phase = "boarding_planet"
    send("board")
end

function f2t_map_explore_system_brief_next_planet()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.system_phase ~= "running_brief" then return end
    if f2t_map_explore_check_deferred_pause() then return end

    F2T_MAP_EXPLORE_STATE.current_planet_index = F2T_MAP_EXPLORE_STATE.current_planet_index + 1
    local index = F2T_MAP_EXPLORE_STATE.current_planet_index
    local planets = F2T_MAP_EXPLORE_STATE.planet_list

    if index > #planets then
        f2t_map_explore_system_return_to_link_and_complete()
        return
    end

    local planet = planets[index]
    cecho(string.format("\n<green>[map-explore]<reset> Brief %d/%d: <white>%s<reset>\n",
        index, #planets, planet.name))

    F2T_MAP_EXPLORE_STATE.phase = "navigating_to_orbit"
    F2T_MAP_EXPLORE_STATE.brief_target_planet = planet.name

    local success = f2t_map_navigate(tostring(planet.orbit_room_id))
    if not success then
        cecho(string.format("  <yellow>Warning:<reset> Cannot navigate to orbit for '%s', skipping...\n", planet.name))
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_brief_next_planet()
        return
    end

    -- Already at the orbit: no room change will fire, board directly.
    if F2T_MAP_CURRENT_ROOM_ID == planet.orbit_room_id then
        F2T_MAP_EXPLORE_STATE.phase = "at_orbit"
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.phase == "at_orbit" then
                f2t_map_explore_system_board_planet()
            end
        end)
    end
end

function f2t_map_explore_planet_find_exchange()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.phase ~= "finding_exchange" then return end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]
    if not current_room or not planet then
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_next_planet()
        return
    end

    cecho("  <dim_grey>Searching for exchange...<reset>\n")
    local exchange_room = f2t_map_explore_bfs_find_flag(current_room, "exchange", 20)
    if exchange_room then
        cecho("  <green>Exchange found!<reset> Navigating...\n")
        F2T_MAP_EXPLORE_STATE.phase = "planet_complete"
        f2t_map_navigate(tostring(exchange_room))
    else
        cecho(string.format("  <yellow>Warning:<reset> Exchange not found on '%s', skipping...\n", planet.name))
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_next_planet()
    end
end

-- After system completion, return to the link room before calling back up so
-- the next phase (cartel/galaxy jump) starts from a jump-capable location.
function f2t_map_explore_system_return_to_link_and_complete()
    if not F2T_MAP_EXPLORE_STATE.active then return end

    local link_room = nil
    local space_area_id = F2T_MAP_EXPLORE_STATE.space_area_id
    if space_area_id then
        link_room = f2t_map_find_room_with_flag(space_area_id, "link")
    end
    if not link_room then
        f2t_map_explore_system_call_callback()
        return
    end
    if F2T_MAP_CURRENT_ROOM_ID == link_room then
        f2t_map_explore_system_call_callback()
        return
    end

    cecho("  <dim_grey>Returning to link room...<reset>\n")
    f2t_map_explore_escape_start(
        link_room,
        function() f2t_map_explore_system_call_callback() end,
        function(reason) f2t_map_explore_pause_stranded(reason, link_room) end
    )
end

function f2t_map_explore_system_call_callback()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local callback = F2T_MAP_EXPLORE_STATE.system_complete_callback
    if callback then
        F2T_MAP_EXPLORE_STATE.system_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        callback()
    else
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
    end
end

f2t_debug_log("[map] Loaded explore_system.lua")
