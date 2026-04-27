-- ================================================================================
-- LAYER 2: SYSTEM ORCHESTRATION (MULTI-AREA)
-- ================================================================================
-- Coordinates exploration of multiple areas within a system.
-- Two phases:
--   1. Explore "{System} Space" area (delegates to Layer 1 DFS)
--   2. For each discovered planet, run brief exploration (delegates to Layer 1)
-- NOTE: System and cartel modes ONLY do brief discovery (flag finding)
-- Navigates between areas (space → planet → space).
-- Entry point: f2t_map_explore_system_start()
-- Delegates to Layer 1 (map_explore.lua) for planet exploration.
-- ================================================================================

-- ========================================
-- System Exploration Entry Point
-- ========================================

function f2t_map_explore_system_start(system_name, system_mode, on_complete_callback)
    -- LAYER 2: System exploration (space + brief/full mode for each planet)
    -- Can run in nested mode (cartel → system) or standalone mode
    --
    -- Parameters:
    --   system_name: Name of system to explore
    --   system_mode: "full" or "brief" (default: "brief")
    --                - full: Explore entire space area (all rooms)
    --                - brief: Stop when all expected planets found (from DI system)
    --   on_complete_callback: Optional callback for nested mode (Layer 3: cartel)
    --                         If nil, runs in standalone mode with return to start
    --
    -- IMPORTANT: When invoked from higher layer (cartel), mode is forced to "brief"

    -- Validate system name provided
    if not system_name or system_name == "" then
        cecho("\n<red>[map-explore]<reset> Error: No system specified\n")
        cecho("\n<dim_grey>Usage: map explore system [full|brief] <system><reset>\n")
        return false
    end

    -- Normalize mode parameter
    if not system_mode or system_mode == "" then
        system_mode = "brief"  -- Default
    end
    system_mode = string.lower(system_mode)

    -- Validate mode
    if system_mode ~= "full" and system_mode ~= "brief" then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid system mode '%s'\n", system_mode))
        cecho("\n<dim_grey>Valid modes: full, brief<reset>\n")
        return false
    end

    -- Force brief mode when invoked from higher layer (nested mode)
    if on_complete_callback and system_mode ~= "brief" then
        f2t_debug_log("[map-explore-system] Nested mode detected, forcing brief mode (was: %s)", system_mode)
        system_mode = "brief"
    end

    -- Capitalize first letter for consistency
    system_name = system_name:gsub("^%l", string.upper)

    f2t_debug_log("[map-explore-system] Starting system exploration for: %s (mode: %s)", system_name, system_mode)

    -- Brief mode: Capture expected planets from DI system first
    if system_mode == "brief" then
        cecho(string.format("\n<green>[map-explore]<reset> Starting system exploration: <white>%s<reset> (<cyan>brief mode<reset>)\n", system_name))
        cecho("  <dim_grey>Capturing expected planet list...<reset>\n")

        -- Start DI system capture
        f2t_map_di_system_capture_start(system_name, function(expected_planet_names, planets_without_exchange)
            -- Capture complete, continue with initialization
            f2t_map_explore_system_start_with_planets(system_name, system_mode, expected_planet_names, planets_without_exchange, on_complete_callback)
        end)

        return true
    end

    -- Full mode: No DI capture needed, proceed immediately
    f2t_map_explore_system_start_with_planets(system_name, system_mode, nil, nil, on_complete_callback)
    return true
end

-- ========================================
-- System Exploration Initialization (After DI Capture)
-- ========================================

function f2t_map_explore_system_start_with_planets(system_name, system_mode, expected_planet_names, planets_without_exchange, on_complete_callback)
    -- Second phase of system start - called after DI capture (brief) or immediately (full)
    --
    -- Parameters:
    --   system_name: Name of system
    --   system_mode: "full" or "brief"
    --   expected_planet_names: Array of planet names from DI system (nil in full mode)
    --   planets_without_exchange: Set {planet_name = true} for planets with no exchange (nil in full mode)
    --   on_complete_callback: Optional callback for nested mode

    f2t_debug_log("[map-explore-system] Initializing system exploration (mode: %s, expected planets: %d)",
        system_mode, expected_planet_names and #expected_planet_names or 0)

    -- Convert expected planets to tracking structures (brief mode only)
    local expected_planets_set = nil
    local expected_planets_found_set = nil
    local expected_planets_remaining_count = nil

    if system_mode == "brief" and expected_planet_names then
        if #expected_planet_names == 0 then
            cecho(string.format("\n<yellow>[map-explore]<reset> Warning: No planets found in %s via DI system\n", system_name))
            cecho("\n<dim_grey>Falling back to full mode (will explore entire space area)<reset>\n")
            system_mode = "full"
        else
            -- Build sets for O(1) lookup
            expected_planets_set = {}
            expected_planets_found_set = {}
            for _, planet_name in ipairs(expected_planet_names) do
                expected_planets_set[planet_name] = true
            end

            -- Check which expected planets are already mapped (have orbit rooms)
            local already_known = {}
            local still_searching = {}
            for _, planet_name in ipairs(expected_planet_names) do
                -- Search for orbit room with this planet's fed2_planet userdata
                local found = false
                for room_id, _ in pairs(getRooms()) do
                    local room_planet = getRoomUserData(room_id, "fed2_planet")
                    if room_planet == planet_name then
                        expected_planets_found_set[planet_name] = true
                        table.insert(already_known, planet_name)
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(still_searching, planet_name)
                end
            end

            expected_planets_remaining_count = #still_searching

            cecho(string.format("  <green>Found %d expected planet(s)<reset>\n", #expected_planet_names))
            if #already_known > 0 then
                cecho(string.format("  <cyan>Already mapped:<reset> %d planet(s)\n", #already_known))
            end

            -- Debug: Log what we're looking for
            table.sort(already_known)
            table.sort(still_searching)
            f2t_debug_log("[map-explore-system] Brief mode Phase 1 - searching for planets:")
            f2t_debug_log("[map-explore-system]   Expected planets: %s", table.concat(expected_planet_names, ", "))
            f2t_debug_log("[map-explore-system]   Known planets: %s (%d)",
                #already_known > 0 and table.concat(already_known, ", ") or "none", #already_known)
            f2t_debug_log("[map-explore-system]   Still searching for: %s (%d)",
                #still_searching > 0 and table.concat(still_searching, ", ") or "none", #still_searching)

            -- If all planets already found, skip Phase 1
            if expected_planets_remaining_count == 0 then
                f2t_debug_log("[map-explore-system] All expected planets already mapped, skipping Phase 1")
                cecho("  <green>All expected planets already mapped!<reset> Skipping space exploration.\n")
                -- We'll skip Phase 1 by proceeding directly to Phase 2 after initialization
            end
        end
    end

    -- Find or navigate to system space area
    local space_area_name = f2t_map_get_system_space_area_actual(system_name)

    if not space_area_name then
        -- System not mapped yet
        cecho(string.format("\n<yellow>[map-explore]<reset> System '%s' space not mapped yet\n", system_name))
        cecho("\n<red>[map-explore]<reset> Cannot explore unmapped system\n")
        cecho(string.format("\n<dim_grey>Visit at least one room in '%s Space' first<reset>\n", system_name))
        return false
    end

    local space_area_id = f2t_map_get_area_id(space_area_name)
    if not space_area_id then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Could not find area ID for '%s'\n", space_area_name))
        return false
    end

    -- Check if we're already in the space area
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local current_area = current_room and getRoomArea(current_room)

    if current_area ~= space_area_id then
        cecho(string.format("\n<yellow>[map-explore]<reset> Not in %s, please navigate there first\n", space_area_name))
        cecho(string.format("\n<dim_grey>Use: nav %s<reset>\n", system_name))
        return false
    end

    -- Display exploration start message
    if system_mode == "full" then
        cecho(string.format("\n<green>[map-explore]<reset> Starting system exploration: <white>%s<reset> (<cyan>full mode<reset>)\n", system_name))
        cecho(string.format("  <dim_grey>Phase 1: Exploring entire %s area<reset>\n", space_area_name))
    else
        -- Brief mode message already shown above
        cecho(string.format("  <dim_grey>Phase 1: Exploring %s to find expected planets<reset>\n", space_area_name))
    end

    -- Nested mode vs standalone mode initialization
    if on_complete_callback then
        -- NESTED MODE: Preserve parent state (cartel), only add Layer 2 fields
        f2t_debug_log("[map-explore-system] Nested mode - preserving parent state")

        -- Add Layer 2 fields to existing state (preserve parent mode!)
        -- DON'T overwrite mode in nested mode - parent (cartel) needs it for transitions
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        F2T_MAP_EXPLORE_STATE.system_name = system_name
        F2T_MAP_EXPLORE_STATE.system_mode = system_mode
        F2T_MAP_EXPLORE_STATE.space_area_id = space_area_id
        F2T_MAP_EXPLORE_STATE.space_area_name = space_area_name
        F2T_MAP_EXPLORE_STATE.planet_list = {}
        F2T_MAP_EXPLORE_STATE.current_planet_index = 0
        F2T_MAP_EXPLORE_STATE.system_phase = "exploring_space"

        -- Planet tracking (brief mode only)
        F2T_MAP_EXPLORE_STATE.expected_planets = expected_planets_set
        F2T_MAP_EXPLORE_STATE.expected_planets_found = expected_planets_found_set
        F2T_MAP_EXPLORE_STATE.expected_planets_remaining = expected_planets_remaining_count
        F2T_MAP_EXPLORE_STATE.planets_without_exchange = planets_without_exchange

        F2T_MAP_EXPLORE_STATE.system_stats = {
            total_planets = 0,
            planets_explored = 0,
            exchanges_found = 0,
            planets_skipped = 0,
            planets_incomplete = 0,
            incomplete_planets = {}
        }

        -- Clear brief mode fields (left over from previous brief exploration)
        F2T_MAP_EXPLORE_STATE.brief_planet_name = nil
        F2T_MAP_EXPLORE_STATE.brief_flags = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_set = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_found = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count = nil
        F2T_MAP_EXPLORE_STATE.brief_target_planet = nil

        -- Store parent callback and set space exploration callback
        F2T_MAP_EXPLORE_STATE.system_complete_callback = on_complete_callback
        F2T_MAP_EXPLORE_STATE.on_complete_callback = function()
            f2t_map_explore_system_space_complete()
        end

        -- Update area context for this system's space exploration
        F2T_MAP_EXPLORE_STATE.starting_room_id = current_room
        F2T_MAP_EXPLORE_STATE.starting_area_id = space_area_id
        F2T_MAP_EXPLORE_STATE.visited_rooms = {[current_room] = true}
        F2T_MAP_EXPLORE_STATE.frontier_stack = {}  -- Empty, populated by recompute

    else
        -- STANDALONE MODE: Full initialization with mode = "system"
        f2t_debug_log("[map-explore-system] Standalone mode - full initialization")

        local mode_fields = {
            mode = "system",
            system_name = system_name,
            system_mode = system_mode,
            space_area_id = space_area_id,
            space_area_name = space_area_name,
            planet_list = {},
            current_planet_index = 0,
            system_phase = "exploring_space",

            -- Planet tracking (brief mode only)
            expected_planets = expected_planets_set,
            expected_planets_found = expected_planets_found_set,
            expected_planets_remaining = expected_planets_remaining_count,
            planets_without_exchange = planets_without_exchange,

            system_stats = {
                total_planets = 0,
                planets_explored = 0,
                exchanges_found = 0,
                planets_skipped = 0,
                planets_incomplete = 0,
                incomplete_planets = {}
            },

            -- Callback when space exploration completes
            on_complete_callback = function()
                f2t_map_explore_system_space_complete()
            end
        }

        f2t_map_explore_init_area(space_area_id, mode_fields)
    end

    -- Recompute frontier
    f2t_map_explore_recompute_frontier()

    -- Display start message
    local room_name = getRoomName(F2T_MAP_CURRENT_ROOM_ID) or "Unknown"
    cecho(string.format("  Starting room: <white>%s<reset> (ID: %d)\n", room_name, F2T_MAP_CURRENT_ROOM_ID))

    -- Check if brief mode already found all planets (skip Phase 1)
    if system_mode == "brief" and
       F2T_MAP_EXPLORE_STATE.expected_planets_remaining and
       F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 then
        f2t_debug_log("[map-explore-system] Skipping Phase 1 - all planets already known")
        -- Skip directly to Phase 2 (planet exploration)
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active then
                f2t_map_explore_system_space_complete()
            end
        end)
    else
        -- Start Phase 1 exploration
        f2t_map_explore_next_step()
    end

    return true
end

-- ========================================
-- Complete Space Exploration, Start Planet Boarding
-- ========================================

function f2t_map_explore_system_space_complete()
    f2t_debug_log("[map-explore-system] Space exploration complete, discovering planets")

    local space_area_id = F2T_MAP_EXPLORE_STATE.space_area_id
    local system_name = F2T_MAP_EXPLORE_STATE.system_name
    local planets = {}

    -- Brief mode early exit: Use expected planets we already found
    if F2T_MAP_EXPLORE_STATE.system_mode == "brief" and F2T_MAP_EXPLORE_STATE.expected_planets_found then
        f2t_debug_log("[map-explore-system] Brief mode - using expected planets that were found")

        -- Build planet list from expected_planets_found
        for planet_name, _ in pairs(F2T_MAP_EXPLORE_STATE.expected_planets_found) do
            -- Find the orbit room for this planet
            local orbit_room_id = nil
            local rooms_in_area = getAreaRooms(space_area_id)
            if rooms_in_area then
                for _, room_id in pairs(rooms_in_area) do
                    local room_planet = getRoomUserData(room_id, "fed2_planet")
                    if room_planet == planet_name then
                        orbit_room_id = room_id
                        break
                    end
                end
            end

            if orbit_room_id then
                table.insert(planets, {
                    name = planet_name,
                    orbit_room_id = orbit_room_id
                })
                f2t_debug_log("[map-explore-system] Using expected planet: %s (orbit room: %d)", planet_name, orbit_room_id)
            else
                f2t_debug_log("[map-explore-system] WARNING: Expected planet %s has no orbit room!", planet_name)
            end
        end
    else
        -- Full mode: Scan all rooms to discover planets
        f2t_debug_log("[map-explore-system] Full mode - scanning all rooms to discover planets")

        local orbit_rooms = {}
        local rooms_in_area = getAreaRooms(space_area_id)

        f2t_debug_log("[map-explore-system] Checking rooms in space area %d for planets", space_area_id)

        if rooms_in_area then
            -- getAreaRooms returns 0-indexed table, must use pairs() not ipairs()
            for _, room_id in pairs(rooms_in_area) do
                local planet_name = getRoomUserData(room_id, "fed2_planet")
                f2t_debug_log("[map-explore-system] Room %d: fed2_planet = '%s'", room_id, planet_name or "nil")
                if planet_name and planet_name ~= "" then
                    table.insert(orbit_rooms, room_id)
                end
            end
        end

        if #orbit_rooms == 0 then
            cecho("\n<yellow>[map-explore]<reset> No orbit rooms found in space\n")
            cecho("\n<dim_grey>System may have no planets or they haven't been discovered yet<reset>\n")

            -- Exploration complete with no planets
            F2T_MAP_EXPLORE_STATE.mode = nil
            F2T_MAP_EXPLORE_STATE.system_phase = nil
            return
        end

        -- Build planet list from orbit rooms
        for _, orbit_room_id in ipairs(orbit_rooms) do
            local planet_name = getRoomUserData(orbit_room_id, "fed2_planet")

            -- Check if we already have this planet (avoid duplicates)
            local already_added = false
            for _, p in ipairs(planets) do
                if p.name == planet_name then
                    already_added = true
                    break
                end
            end

            if not already_added then
                table.insert(planets, {
                    name = planet_name,
                    orbit_room_id = orbit_room_id
                })
                f2t_debug_log("[map-explore-system] Discovered planet: %s (orbit room: %d)", planet_name, orbit_room_id)
            end
        end
    end

    if #planets == 0 then
        cecho("\n<yellow>[map-explore]<reset> No planets identified from orbit rooms\n")
        F2T_MAP_EXPLORE_STATE.mode = nil
        F2T_MAP_EXPLORE_STATE.system_phase = nil
        return
    end

    -- Sort planets alphabetically
    table.sort(planets, function(a, b) return a.name < b.name end)

    -- Filter planets: only include those that need brief exploration
    -- Check which planets already have shuttlepad + additional flags
    local planets_to_explore = {}
    local planets_already_explored = {}

    -- Get brief flags from settings
    local additional_flags_str = f2t_settings_get("map", "brief_additional_flags") or "exchange"
    local required_flags = {"shuttlepad"}
    for flag in string.gmatch(additional_flags_str, "[^,]+") do
        local trimmed = flag:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed ~= "shuttlepad" then
            table.insert(required_flags, trimmed)
        end
    end

    f2t_debug_log("[map-explore-system] Phase 2 check - required flags: %s", table.concat(required_flags, ", "))

    for _, planet in ipairs(planets) do
        -- Find planet's area by area name (not fed2_planet which is only on orbit rooms)
        local planet_area_id = f2t_map_get_area_id(planet.name)

        f2t_debug_log("[map-explore-system] Checking planet %s (area_id: %s)",
            planet.name, planet_area_id or "not found")

        if planet_area_id then
            -- Check if all required flags exist in this planet's area
            local all_flags_found = true
            local missing_flags = {}

            for _, flag in ipairs(required_flags) do
                -- Check if we should skip this flag for this planet
                local skip_flag = false

                -- Skip exchange flag if planet has no exchange
                if flag == "exchange" and
                   F2T_MAP_EXPLORE_STATE.planets_without_exchange and
                   F2T_MAP_EXPLORE_STATE.planets_without_exchange[planet.name] then
                    skip_flag = true
                    f2t_debug_log("[map-explore-system]   Planet %s: skipping exchange flag (no exchange)", planet.name)
                end

                if not skip_flag then
                    local flag_found = false
                    local area_rooms = getAreaRooms(planet_area_id)
                    if area_rooms then
                        for _, room_id in pairs(area_rooms) do
                            local flag_key = string.format("fed2_flag_%s", flag)
                            if getRoomUserData(room_id, flag_key) == "true" then
                                flag_found = true
                                f2t_debug_log("[map-explore-system]   Planet %s: found %s flag", planet.name, flag)
                                break
                            end
                        end
                    end

                    if not flag_found then
                        all_flags_found = false
                        table.insert(missing_flags, flag)
                        f2t_debug_log("[map-explore-system]   Planet %s: missing %s flag", planet.name, flag)
                    end
                else
                    -- Skipped flag counts as "found" for our purposes
                    f2t_debug_log("[map-explore-system]   Planet %s: %s flag skipped (counts as found)", planet.name, flag)
                end
            end

            if all_flags_found then
                table.insert(planets_already_explored, planet.name)
                f2t_debug_log("[map-explore-system] Planet %s already has all required flags, SKIPPING", planet.name)
            else
                table.insert(planets_to_explore, planet)
                f2t_debug_log("[map-explore-system] Planet %s missing flags: %s, WILL EXPLORE",
                    planet.name, table.concat(missing_flags, ", "))
            end
        else
            -- Planet not yet mapped (no surface rooms), needs exploration
            table.insert(planets_to_explore, planet)
            f2t_debug_log("[map-explore-system] Planet %s has no mapped area yet, WILL EXPLORE", planet.name)
        end
    end

    -- Update state with filtered list
    F2T_MAP_EXPLORE_STATE.planet_list = planets_to_explore
    F2T_MAP_EXPLORE_STATE.current_planet_index = 0

    -- Track total planets discovered (before filtering) for statistics
    F2T_MAP_EXPLORE_STATE.system_stats.total_planets = #planets

    -- Update stats for planets already explored (pre-filtered - have all required flags)
    -- These count as explored + exchange found + skipped (consistent with iteration path)
    for _, planet_name in ipairs(planets_already_explored) do
        F2T_MAP_EXPLORE_STATE.system_stats.planets_explored = F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
        F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found = F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
    end

    cecho(string.format("\n  <green>Space exploration complete!<reset> Discovered %d planet(s)\n", #planets))
    if #planets_already_explored > 0 then
        cecho(string.format("  <cyan>Already explored:<reset> %d planet(s) (skipping)\n", #planets_already_explored))
        f2t_debug_log("[map-explore-system] Skipping already-explored planets: %s", table.concat(planets_already_explored, ", "))
    end
    if #planets_to_explore > 0 then
        cecho(string.format("  <white>To explore:<reset> %d planet(s)\n", #planets_to_explore))
    end

    if #planets_to_explore == 0 then
        -- No planets need exploration - system exploration complete
        if #planets_already_explored > 0 then
            f2t_debug_log("[map-explore-system] All planets already explored, system complete")
            cecho("\n<green>[map-explore]<reset> All planets already have required flags! System exploration complete.\n")
        else
            f2t_debug_log("[map-explore-system] No planets found in system")
        end

        -- Return to link room before completing (handles stranded case)
        f2t_map_explore_system_return_to_link_and_complete()
        return
    end

    -- Start brief exploration of each planet (ONLY supported mode)
    cecho("  <dim_grey>Phase 2: Brief exploration of each planet<reset>\n\n")
    F2T_MAP_EXPLORE_STATE.system_phase = "running_brief"
    f2t_map_explore_system_brief_next_planet()
end

-- ========================================
-- Navigate to Next Planet
-- ========================================

function f2t_map_explore_system_next_planet()
    -- Guard: Check if system exploration active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    if F2T_MAP_EXPLORE_STATE.mode ~= "system" and F2T_MAP_EXPLORE_STATE.mode ~= "cartel" then
        return
    end

    -- Deferred pause: pause between planets
    if f2t_map_explore_check_deferred_pause() then
        return
    end

    -- Increment planet index
    F2T_MAP_EXPLORE_STATE.current_planet_index = F2T_MAP_EXPLORE_STATE.current_planet_index + 1
    local index = F2T_MAP_EXPLORE_STATE.current_planet_index
    local planets = F2T_MAP_EXPLORE_STATE.planet_list

    -- Check if all planets complete
    if index > #planets then
        f2t_debug_log("[map-explore-system] All planets checked in system")

        -- Start brief exploration workflow (ONLY supported mode)
        if #planets > 0 then
            cecho("\n<green>[map-explore]<reset> Starting brief exploration of discovered planets...\n")
            F2T_MAP_EXPLORE_STATE.system_phase = "running_brief"
            F2T_MAP_EXPLORE_STATE.current_planet_index = 0  -- Reset to start iteration
            f2t_map_explore_system_brief_next_planet()
            return
        end

        -- No planets - system exploration complete

        -- If cartel mode, continue to next system
        if F2T_MAP_EXPLORE_STATE.mode == "cartel" then
            f2t_map_explore_cartel_next_system()
            return
        end

        -- System mode complete - clear callback and return to start
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
        return
    end

    local planet = planets[index]

    cecho(string.format("\n<green>[map-explore]<reset> Planet %d/%d: <white>%s<reset>\n",
        index, #planets, planet.name))

    -- OPTIMIZATION: Skip planet if we already know where the exchange is
    -- Find planet area by checking all areas for matching planet name
    local planet_area_id = nil
    for area_name, area_id in pairs(getAreaTable()) do
        -- Check if this area is the planet (not space)
        local sample_rooms = getAreaRooms(area_id)
        if sample_rooms and #sample_rooms > 0 then
            -- getAreaRooms() is 0-indexed, get first element at index 0
            local sample_room = sample_rooms[0]
            local room_area = getRoomUserData(sample_room, "fed2_area")
            if room_area == planet.name then
                planet_area_id = area_id
                break
            end
        end
    end

    -- If planet area exists, check if we already have an exchange room
    if planet_area_id then
        local exchange_rooms = f2t_map_find_all_rooms_with_flag(planet_area_id, "exchange")
        if exchange_rooms and #exchange_rooms > 0 then
            cecho(string.format("  <dim_grey>Exchange already known on %s (room %d), skipping...<reset>\n",
                planet.name, exchange_rooms[1]))
            f2t_debug_log("[map-explore-system] Skipping planet %s, exchange already mapped at room %d",
                planet.name, exchange_rooms[1])

            -- Update statistics
            F2T_MAP_EXPLORE_STATE.system_stats.planets_explored = F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
            F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found = F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1
            F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1

            -- Aggregate to cartel stats if in cartel mode
            if F2T_MAP_EXPLORE_STATE.mode == "cartel" then
                F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets = F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets + 1
                F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges = F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges + 1
                F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_skipped = F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_skipped + 1
            end

            -- Move to next planet
            f2t_map_explore_system_next_planet()
            return
        end
    end

    -- Navigate to orbit room (Phase 2 only - this function not called during Phase 1)
    f2t_debug_log("[map-explore-system] Navigating to orbit room %d for planet %s", planet.orbit_room_id, planet.name)

    F2T_MAP_EXPLORE_STATE.phase = "navigating_to_orbit"
    local success = f2t_map_navigate(tostring(planet.orbit_room_id))

    if not success then
        cecho(string.format("  <yellow>Warning:<reset> Cannot navigate to orbit for '%s', skipping...\n", planet.name))
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1

        -- Aggregate to cartel stats if in cartel mode
        if F2T_MAP_EXPLORE_STATE.mode == "cartel" then
            F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_skipped = F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets_skipped + 1
        end

        -- Recurse to next planet
        f2t_map_explore_system_next_planet()
        return
    end

    -- Navigation started, waiting for arrival (handled in room change event)
end

-- ========================================
-- Board Planet from Orbit
-- ========================================

function f2t_map_explore_system_board_planet()
    -- Guard: Check state
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    if F2T_MAP_EXPLORE_STATE.phase ~= "at_orbit" then
        return
    end

    local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]

    f2t_debug_log("[map-explore-system] Boarding planet %s", planet.name)
    cecho("  <dim_grey>Boarding planet...<reset>\n")

    -- Send board command
    F2T_MAP_EXPLORE_STATE.phase = "boarding_planet"
    send("board")

    -- Room change event will handle arrival on planet
end

-- ========================================
-- Find Exchange on Current Planet (BFS)
-- ========================================

function f2t_map_explore_planet_find_exchange()
    -- Guard: Check state
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    if F2T_MAP_EXPLORE_STATE.phase ~= "finding_exchange" then
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID

    if not current_room then
        cecho("\n<red>[map-explore]<reset> Error: Current location unknown\n")
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_next_planet()
        return
    end

    local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]

    f2t_debug_log("[map-explore-system] Starting BFS search for exchange on %s from room %d",
        planet.name, current_room)

    cecho("  <dim_grey>Searching for exchange...<reset>\n")

    -- Use BFS to find exchange
    local exchange_room = f2t_map_explore_bfs_find_flag(current_room, "exchange", 20)

    if exchange_room then
        -- Found exchange! Navigate to it
        f2t_debug_log("[map-explore-system] Exchange found on %s at room %d", planet.name, exchange_room)

        cecho(string.format("  <green>Exchange found!<reset> Navigating...\n"))

        F2T_MAP_EXPLORE_STATE.phase = "planet_complete"
        f2t_map_navigate(tostring(exchange_room))
    else
        -- Not found within depth limit
        cecho(string.format("  <yellow>Warning:<reset> Exchange not found on '%s' (searched 20 rooms), skipping...\n", planet.name))
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_debug_log("[map-explore-system] Exchange not found on %s within depth limit", planet.name)

        -- Move to next planet
        f2t_map_explore_system_next_planet()
    end
end

-- ========================================
-- Brief Exploration Iterator
-- ========================================

function f2t_map_explore_system_brief_next_planet()
    -- Guard: Check if active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    if F2T_MAP_EXPLORE_STATE.system_phase ~= "running_brief" then
        return
    end

    -- Increment planet index
    F2T_MAP_EXPLORE_STATE.current_planet_index = F2T_MAP_EXPLORE_STATE.current_planet_index + 1
    local index = F2T_MAP_EXPLORE_STATE.current_planet_index
    local planets = F2T_MAP_EXPLORE_STATE.planet_list

    -- Check if all planets briefed
    if index > #planets then
        f2t_debug_log("[map-explore-system] All planets briefed")

        -- Return to link room before completing (handles stranded case)
        f2t_map_explore_system_return_to_link_and_complete()
        return
    end

    local planet = planets[index]

    cecho(string.format("\n<green>[map-explore]<reset> Brief %d/%d: <white>%s<reset>\n",
        index, #planets, planet.name))

    f2t_debug_log("[map-explore-system] Navigating to %s orbit to board", planet.name)

    -- Navigate to orbit room
    F2T_MAP_EXPLORE_STATE.phase = "navigating_to_orbit"
    F2T_MAP_EXPLORE_STATE.brief_target_planet = planet.name

    local success = f2t_map_navigate(tostring(planet.orbit_room_id))
    if not success then
        cecho(string.format("  <yellow>Warning:<reset> Cannot navigate to orbit for '%s', skipping...\n", planet.name))
        f2t_map_explore_system_brief_next_planet()
        return
    end

    -- Check if we're already at the orbit (navigation returned success but no room change)
    if F2T_MAP_CURRENT_ROOM_ID == planet.orbit_room_id then
        -- Already at orbit, board immediately (don't wait for room change)
        f2t_debug_log("[map-explore-system] Already at orbit, boarding immediately")
        F2T_MAP_EXPLORE_STATE.phase = "at_orbit"
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.phase == "at_orbit" then
                f2t_map_explore_system_board_planet()
            end
        end)
    end

    -- Otherwise: navigation in progress, waiting for arrival (handled in room change event)
end

-- ========================================
-- System Completion: Return to Link Before Callback
-- ========================================

function f2t_map_explore_system_return_to_link_and_complete()
    -- After system exploration completes, navigate to link room before calling
    -- the parent callback. This ensures we're in a navigable location for the
    -- next phase (cartel mode jumping to next system).

    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    -- Get system name
    local system_name = F2T_MAP_EXPLORE_STATE.system_name
    if not system_name then
        f2t_debug_log("[map-explore-system] No system name, calling callback directly")
        f2t_map_explore_system_call_callback()
        return
    end

    -- Find link room in system space
    local space_area = f2t_map_get_system_space_area_actual(system_name)
    if not space_area then
        f2t_debug_log("[map-explore-system] Cannot find space area for %s, calling callback directly", system_name)
        f2t_map_explore_system_call_callback()
        return
    end

    local space_area_id = f2t_map_get_area_id(space_area)
    if not space_area_id then
        f2t_debug_log("[map-explore-system] Cannot find space area ID for %s, calling callback directly", space_area)
        f2t_map_explore_system_call_callback()
        return
    end

    local link_room = f2t_map_find_room_with_flag(space_area_id, "link")
    if not link_room then
        f2t_debug_log("[map-explore-system] Cannot find link room in %s, calling callback directly", space_area)
        f2t_map_explore_system_call_callback()
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID

    -- Check if already at link room
    if current_room == link_room then
        f2t_debug_log("[map-explore-system] Already at link room, calling callback")
        f2t_map_explore_system_call_callback()
        return
    end

    -- Navigate to link room using escape logic (handles stranded case)
    f2t_debug_log("[map-explore-system] Returning to link room (room %d) before callback", link_room)
    cecho("  <dim_grey>Returning to link room...<reset>\n")

    f2t_map_explore_escape_start(
        link_room,
        -- On success: call callback
        function()
            f2t_debug_log("[map-explore-system] Arrived at link room, calling callback")
            f2t_map_explore_system_call_callback()
        end,
        -- On failure: pause exploration
        function(reason)
            f2t_debug_log("[map-explore-system] Failed to return to link room: %s", reason)
            f2t_map_explore_pause_stranded(reason, link_room)
        end
    )
end

function f2t_map_explore_system_call_callback()
    -- Called after arriving at link room (or if already there)
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    local callback = F2T_MAP_EXPLORE_STATE.system_complete_callback

    if callback then
        -- Nested mode: call parent (cartel)
        f2t_debug_log("[map-explore-system] Calling parent callback")
        F2T_MAP_EXPLORE_STATE.system_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        callback()
    else
        -- Standalone mode: return to start
        f2t_debug_log("[map-explore-system] Standalone mode - returning to start")
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
    end
end

f2t_debug_log("[map] Loaded map_explore_system.lua")
