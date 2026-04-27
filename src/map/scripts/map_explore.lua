-- ================================================================================
-- MAP EXPLORATION - FOUR-LAYER ARCHITECTURE
-- ================================================================================
--
-- LAYER 1: Core Exploration Engine (Single Area)
--   - Operates on ONE area at a time
--   - Two algorithms: DFS (full mapping) or distance-sorted DFS (flag finding)
--   - Mode: "planet" with planet_mode = "full" or "brief"
--   - NEVER crosses area boundaries
--   - Entry point: f2t_map_explore_planet_start(planet_mode, planet_name, callback, flags)
--
-- LAYER 2: System Orchestration (Multi-Area)
--   - Coordinates exploration of multiple areas within a system
--   - Two phases:
--     1. Explore "{System} Space" area (DFS)
--     2. For each discovered planet, trigger brief/full exploration (Layer 1)
--   - Navigates between areas (space → planet → space)
--   - Entry point: f2t_map_explore_system_start()
--   - Delegates to Layer 1 for actual exploration
--
-- LAYER 3: Cartel Orchestration (Multi-System)
--   - Iterates through systems in a cartel
--   - For each system, triggers system exploration (Layer 2)
--   - Entry point: f2t_map_explore_cartel_start()
--   - Delegates to Layer 2 for each system
--
-- LAYER 4: Galaxy Orchestration (Multi-Cartel)
--   - Iterates through all cartels in the galaxy
--   - For each cartel, triggers cartel exploration (Layer 3)
--   - Entry point: f2t_map_explore_galaxy_start()
--   - Delegates to Layer 3 for each cartel
--
-- CRITICAL RULES:
--   - Higher layers call lower layers (never bypass)
--   - Layer 1 NEVER checks for system/cartel/galaxy modes
--   - Layer 1 functions are area-scoped only
--   - Each layer has its own state fields
-- ================================================================================

-- ========================================
-- Global State Object
-- ========================================

F2T_MAP_EXPLORE_STATE = F2T_MAP_EXPLORE_STATE or {
    -- ========================================
    -- COMMON STATE (All Layers)
    -- ========================================
    active = false,
    paused = false,
    phase = nil,
    mode = nil,  -- "planet", "system", "cartel", "galaxy"
    planet_mode = nil,  -- "full" or "brief" (Layer 1 only)

    -- ========================================
    -- LAYER 1 STATE (Single Area Exploration)
    -- ========================================

    -- Origin tracking
    starting_room_id = nil,
    starting_area_id = nil,

    -- Exploration data structures
    visited_rooms = {},
    frontier_stack = {},  -- DFS: stack of unexplored exits

    -- Special exit discovery
    special_exit_patterns = {},
    special_exit_attempts = {},
    suspected_special_exits = {},

    -- Death tracking
    death_room_id = nil,
    recovery_in_progress = false,

    -- Movement tracking (for blocked exit detection)
    last_room_before_move = nil,
    last_direction_attempted = nil,

    -- Navigation tracking (for speedwalk failure handling)
    navigating_to_room_id = nil,

    -- Temporarily locked exits (unlocked on completion)
    temp_locked_exits = {},  -- {room_id = {direction1, direction2, ...}}

    -- Statistics
    stats = {
        rooms_discovered = 0,
        special_exits_found = 0,
        suspected_special_exits = 0,
        blocked_exits = 0,
        deaths = 0
    },

    -- ========================================
    -- LAYER 2 STATE (System Orchestration)
    -- ========================================

    system_name = nil,
    system_mode = nil,  -- "full", "brief" - controls Phase 1 space exploration
    space_area_id = nil,
    space_area_name = nil,
    system_phase = nil,  -- "exploring_space", "boarding_planets", "running_brief"

    planet_list = {},  -- Array of {name = "Earth", area_id = 123}
    current_planet_index = 0,

    -- Brief mode: Expected planets from DI system (for early exit)
    expected_planets = nil,  -- Set: {planet_name = true, ...} or nil in full mode
    expected_planets_found = nil,  -- Set: {planet_name = true, ...} (what we've discovered)
    expected_planets_remaining = nil,  -- Number: count of planets not yet found
    planets_without_exchange = nil,  -- Set: {planet_name = true} for planets with no exchange

    -- System statistics
    system_stats = {
        planets_explored = 0,
        exchanges_found = 0,
        planets_skipped = 0
    },

    -- ========================================
    -- LAYER 3 STATE (Cartel Orchestration)
    -- ========================================

    cartel_name = nil,
    system_list = {},  -- Array of system names
    current_system_index = 0,
    cartel_target_system = nil,  -- System we're jumping to

    -- Cartel statistics
    cartel_stats = {
        total_systems = 0,
        systems_explored = 0,
        total_planets = 0,
        total_exchanges = 0,
        total_planets_skipped = 0
    },

    -- ========================================
    -- LAYER 4 STATE (Galaxy Orchestration)
    -- ========================================

    galaxy_cartel_list = {},  -- Array of cartel names
    galaxy_current_cartel_index = 0,
    galaxy_target_cartel = nil,  -- Cartel we're jumping to

    -- Galaxy statistics
    galaxy_stats = {
        total_cartels = 0,
        cartels_explored = 0,
        cartels_skipped = 0,
        total_systems = 0,
        total_planets = 0
    }
}

-- ================================================================================
-- LAYER 1: CORE EXPLORATION ENGINE (SINGLE AREA)
-- ================================================================================
-- Functions in this section operate on a single area and never cross boundaries.
-- Entry point: f2t_map_explore_planet_start(planet_mode, planet_name, callback, flags)
-- ================================================================================

-- ========================================
-- Core Initialization (Shared by All Modes)
-- ========================================

function f2t_map_explore_init_area(area_id, mode_fields)
    -- Core initialization that all exploration modes use
    -- mode_fields: optional table with mode-specific fields to add to state
    --
    -- Note: Frontier is initialized empty and populated by recompute_frontier()
    -- which is called after initialization. This ensures direction priority
    -- and other optimizations are applied from the start.

    local current_room = F2T_MAP_CURRENT_ROOM_ID

    -- Initialize base state with empty frontier
    -- (will be populated by recompute_frontier() after initialization)
    F2T_MAP_EXPLORE_STATE = {
        active = true,
        paused = false,
        pause_requested = false,
        phase = "navigating",

        starting_room_id = current_room,
        starting_area_id = area_id,

        visited_rooms = {[current_room] = true},
        frontier_stack = {},  -- Empty, populated by recompute_frontier()

        planned_exit = nil,

        special_exit_patterns = {},
        special_exit_attempts = {},
        suspected_special_exits = {},

        death_room_id = nil,
        recovery_in_progress = false,

        last_room_before_move = nil,
        last_direction_attempted = nil,

        temp_locked_exits = {},

        stats = {
            rooms_discovered = 1,
            special_exits_found = 0,
            suspected_special_exits = 0,
            blocked_exits = 0,
            deaths = 0
        }
    }

    -- Add mode-specific fields if provided
    if mode_fields then
        for k, v in pairs(mode_fields) do
            F2T_MAP_EXPLORE_STATE[k] = v
        end
    end

    -- Recompute frontier to populate with all stubs (sorted, optimized)
    f2t_debug_log("[map-explore] Recomputing initial frontier")
    f2t_map_explore_recompute_frontier()

    return #F2T_MAP_EXPLORE_STATE.frontier_stack  -- Return stub count for reporting
end

-- ========================================
-- Entry Point: Planet Exploration (Layer 1 - Full or Brief)
-- ========================================

function f2t_map_explore_planet_start(planet_mode, planet_name, on_complete_callback, override_flags)
    -- LAYER 1: Single area exploration using DFS (full) or distance-sorted DFS (brief)
    -- Operates on current area only, never crosses boundaries
    --
    -- Parameters:
    --   planet_mode: "full" or "brief" (required)
    --                - full: Complete DFS exploration (all rooms)
    --                - brief: Distance-sorted DFS with early stop when flags found
    --   planet_name: Optional planet name (for display, defaults to current area)
    --   on_complete_callback: Optional callback for nested mode (Layer 2+)
    --                         If nil, runs in standalone mode with completion message
    --   override_flags: Optional array of flags to search for (brief mode only)
    --                   If provided, replaces brief_additional_flags from settings
    --                   Shuttlepad is always included regardless

    -- Validate planet_mode
    if not planet_mode or (planet_mode ~= "full" and planet_mode ~= "brief") then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid planet mode '%s'\n", tostring(planet_mode)))
        cecho("\n<dim_grey>Valid modes: full, brief<reset>\n")
        return false
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then
        cecho("\n<red>[map-explore]<reset> Error: Not in a mapped room\n")
        return false
    end

    local current_area = getRoomArea(current_room)
    if not current_area then
        cecho("\n<red>[map-explore]<reset> Error: Room has no area\n")
        return false
    end

    -- Default planet name to current area
    if not planet_name or planet_name == "" then
        planet_name = getRoomAreaName(current_area) or "Unknown"
    end

    f2t_debug_log("[map-explore] [Layer 1] Planet exploration starting (mode: %s, planet: %s)",
        planet_mode, planet_name)

    -- Build brief mode fields if in brief mode
    local brief_fields = {}
    if planet_mode == "brief" then
        -- Determine target flags
        local brief_flags = {"shuttlepad"}  -- Always include shuttlepad

        if override_flags then
            -- Use override flags provided by caller
            for _, flag in ipairs(override_flags) do
                if flag ~= "shuttlepad" then
                    table.insert(brief_flags, flag)
                end
            end
            f2t_debug_log("[map-explore] Using override flags: %s", table.concat(override_flags, ", "))
        else
            -- Get brief flags from settings (default behavior)
            local additional_flags_str = f2t_settings_get("map", "brief_additional_flags") or "exchange"

            -- Parse additional flags (comma-separated)
            for flag in string.gmatch(additional_flags_str, "[^,]+") do
                local trimmed = flag:match("^%s*(.-)%s*$")  -- Trim whitespace
                if trimmed ~= "" and trimmed ~= "shuttlepad" then
                    table.insert(brief_flags, trimmed)
                end
            end
        end

        f2t_debug_log("[map-explore] Target flags: %s", table.concat(brief_flags, ", "))

        -- Build set of flags we're looking for (for O(1) lookup)
        local brief_flags_set = {}
        for _, flag in ipairs(brief_flags) do
            brief_flags_set[flag] = true
        end

        -- Pre-check: Find flags that already exist in this area (from previous exploration)
        -- Brief mode only walks stub exits, so already-mapped rooms won't be visited
        local brief_flags_found = {}
        local flags_already_found = 0
        for _, flag in ipairs(brief_flags) do
            local existing_room = f2t_map_find_room_with_flag(current_area, flag)
            if existing_room then
                brief_flags_found[flag] = existing_room
                flags_already_found = flags_already_found + 1
                local room_name = getRoomName(existing_room) or "Unknown"
                f2t_debug_log("[map-explore] Pre-check: flag '%s' already exists at room %d (%s)", flag, existing_room, room_name)
            end
        end

        if flags_already_found > 0 then
            f2t_debug_log("[map-explore] Pre-check found %d of %d target flags already mapped", flags_already_found, #brief_flags)
        end

        brief_fields = {
            brief_planet_name = planet_name,
            brief_flags = brief_flags,
            brief_flags_set = brief_flags_set,
            brief_flags_found = brief_flags_found,
            brief_flags_remaining_count = #brief_flags - flags_already_found
        }
    end

    -- Nested mode vs standalone mode initialization
    if on_complete_callback then
        -- NESTED MODE: Preserve parent state, only add Layer 1 fields
        f2t_debug_log("[map-explore] Nested mode - preserving parent state")

        -- Add Layer 1 fields to existing state (preserve parent mode!)
        -- DON'T overwrite mode in nested mode - parent needs it for transitions
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        F2T_MAP_EXPLORE_STATE.planet_mode = planet_mode
        F2T_MAP_EXPLORE_STATE.on_complete_callback = on_complete_callback
        F2T_MAP_EXPLORE_STATE.starting_room_id = current_room
        F2T_MAP_EXPLORE_STATE.starting_area_id = current_area
        F2T_MAP_EXPLORE_STATE.visited_rooms = {[current_room] = true}
        F2T_MAP_EXPLORE_STATE.frontier_stack = {}  -- Empty, populated by recompute
        F2T_MAP_EXPLORE_STATE.planned_exit = nil

        -- Add brief fields if in brief mode
        for k, v in pairs(brief_fields) do
            F2T_MAP_EXPLORE_STATE[k] = v
        end

    else
        -- STANDALONE MODE: Full initialization
        f2t_debug_log("[map-explore] Standalone mode - full initialization")

        local mode_fields = {
            mode = "planet",
            planet_mode = planet_mode,
            on_complete_callback = on_complete_callback
        }

        -- Add brief fields if in brief mode
        for k, v in pairs(brief_fields) do
            mode_fields[k] = v
        end

        f2t_map_explore_init_area(current_area, mode_fields)
    end

    -- Recompute frontier to populate/optimize (applies direction priority in brief mode)
    f2t_debug_log("[map-explore] Recomputing initial frontier")
    f2t_map_explore_recompute_frontier()

    -- Display start message (after frontier is built)
    local room_name = getRoomName(current_room) or "Unknown"
    local area_name = getRoomAreaName(current_area) or "Unknown"

    if planet_mode == "full" then
        cecho("\n<green>[map]<reset> Exploration started (<cyan>full mode<reset>)\n")
        cecho(string.format("  Starting room: <white>%s<reset> (ID: %d)\n", room_name, current_room))
        cecho(string.format("  Starting area: <white>%s<reset> (ID: %d)\n", area_name, current_area))
        cecho("  Special exit discovery: <yellow>ENABLED<reset>\n")
        cecho(string.format("  Frontier seeded: <white>%d<reset> exits (sorted by distance)\n", #F2T_MAP_EXPLORE_STATE.frontier_stack))
    else
        cecho("\n<green>[map-explore]<reset> Brief exploration started\n")
        cecho(string.format("  Starting room: <white>%s<reset>\n", room_name))
        cecho(string.format("  Starting area: <white>%s<reset>\n", area_name))
        cecho(string.format("  Target flags: <yellow>%s<reset>\n", table.concat(brief_fields.brief_flags, ", ")))

        -- Show pre-found flags (discovered in previous explorations)
        local pre_found_count = 0
        for flag, flag_room_id in pairs(brief_fields.brief_flags_found) do
            pre_found_count = pre_found_count + 1
            local flag_room_name = getRoomName(flag_room_id) or "Unknown"
            cecho(string.format("  <green>+<reset> <yellow>%s<reset> already mapped at: %s\n", flag, flag_room_name))
        end

        if pre_found_count == #brief_fields.brief_flags then
            cecho("  <green>All target flags already discovered!<reset>\n\n")
        else
            cecho(string.format("  Stub exits: <white>%d<reset>\n\n", #F2T_MAP_EXPLORE_STATE.frontier_stack))
        end
    end

    f2t_debug_log("[map-explore] [Layer 1] Planet exploration started from room %d (area %d, mode: %s)",
        current_room, current_area, planet_mode)

    -- Brief mode: Check if starting room has any target flags
    if planet_mode == "brief" then
        f2t_map_explore_brief_check_room_flags(current_room)

        -- If all flags already found at start, complete immediately
        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 then
            f2t_debug_log("[map-explore] All flags found at starting room!")

            if on_complete_callback then
                f2t_debug_log("[map-explore] Nested mode - calling parent callback")
                on_complete_callback()
            else
                f2t_debug_log("[map-explore] Standalone mode - showing completion")
                f2t_map_explore_complete()
            end
            return true
        end
    end

    -- Start exploration
    f2t_map_explore_next_step()

    return true
end

-- ========================================
-- Check Room for Target Flags (Brief Mode)
-- ========================================

function f2t_map_explore_brief_check_room_flags(room_id)
    -- Called after discovering/entering a room
    -- Checks if room has any of our target flags
    -- Stops exploration if all flags found

    -- Detect brief mode by presence of brief_flags_remaining_count (works in nested mode)
    if not F2T_MAP_EXPLORE_STATE.active or not F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count then
        return
    end

    local flags_set = F2T_MAP_EXPLORE_STATE.brief_flags_set
    local flags_found = F2T_MAP_EXPLORE_STATE.brief_flags_found

    f2t_debug_log("[map-explore-brief] Checking room %d for target flags", room_id)

    -- Check each target flag
    for flag, _ in pairs(flags_set) do
        -- Skip if already found
        if not flags_found[flag] then
            local flag_key = string.format("fed2_flag_%s", flag)
            local has_flag = getRoomUserData(room_id, flag_key)

            f2t_debug_log("[map-explore-brief] Room %d: %s = '%s'", room_id, flag_key, has_flag or "nil")

            if has_flag == "true" then
                -- Found a target flag!
                flags_found[flag] = room_id
                F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count = F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count - 1

                local room_name = getRoomName(room_id) or "Unknown"
                cecho(string.format("  <green>✓<reset> Found <yellow>%s<reset> at: %s\n", flag, room_name))
                f2t_debug_log("[map-explore-brief] Found flag '%s' at room %d (%s)", flag, room_id, room_name)

                -- Check if all flags found
                if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 then
                    f2t_debug_log("[map-explore-brief] All flags found! Brief exploration complete")
                    cecho("\n<green>[map-explore]<reset> All target flags found!\n\n")

                    -- Update system/cartel stats if in nested mode
                    if F2T_MAP_EXPLORE_STATE.system_stats then
                        F2T_MAP_EXPLORE_STATE.system_stats.planets_explored = F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
                        F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found = F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1

                        -- Aggregate to cartel stats if in cartel mode
                        if F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
                            F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets = F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets + 1
                            F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges = F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges + 1
                        end

                        f2t_debug_log("[map-explore-brief] Updated stats - planets: %d, exchanges: %d",
                            F2T_MAP_EXPLORE_STATE.system_stats.planets_explored,
                            F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found)
                    end

                    -- Brief delay to let output settle
                    tempTimer(0.5, function()
                        if not F2T_MAP_EXPLORE_STATE.active then return end

                        -- Navigate to shuttlepad before calling callback
                        -- This ensures we're in a navigable location for the next phase
                        f2t_map_explore_brief_return_to_shuttlepad()
                    end)
                    return
                end
            end
        end
    end
end

-- ========================================
-- Brief Mode: Return to Shuttlepad Before Callback
-- ========================================

function f2t_map_explore_brief_return_to_shuttlepad()
    -- After brief exploration finds all flags, navigate to shuttlepad
    -- before calling the completion callback. This ensures we're in a
    -- navigable location for the next phase (system/cartel/galaxy mode).

    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    -- Get shuttlepad room ID from found flags
    local shuttlepad_room = F2T_MAP_EXPLORE_STATE.brief_flags_found and
                            F2T_MAP_EXPLORE_STATE.brief_flags_found["shuttlepad"]

    if not shuttlepad_room then
        -- No shuttlepad found (shouldn't happen, it's a default target)
        -- Fall back to calling callback directly
        f2t_debug_log("[map-explore-brief] No shuttlepad found, calling callback directly")
        f2t_map_explore_brief_call_callback()
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID

    -- Check if already at shuttlepad
    if current_room == shuttlepad_room then
        f2t_debug_log("[map-explore-brief] Already at shuttlepad, calling callback")
        f2t_map_explore_brief_call_callback()
        return
    end

    -- Navigate to shuttlepad using escape logic (handles stranded case)
    f2t_debug_log("[map-explore-brief] Returning to shuttlepad (room %d) before callback", shuttlepad_room)
    cecho("  <dim_grey>Returning to shuttlepad...<reset>\n")

    f2t_map_explore_escape_start(
        shuttlepad_room,
        -- On success: call callback
        function()
            f2t_debug_log("[map-explore-brief] Arrived at shuttlepad, calling callback")
            f2t_map_explore_brief_call_callback()
        end,
        -- On failure: pause exploration
        function(reason)
            f2t_debug_log("[map-explore-brief] Failed to return to shuttlepad: %s", reason)
            f2t_map_explore_pause_stranded(reason, shuttlepad_room)
        end
    )
end

function f2t_map_explore_brief_call_callback()
    -- Called after arriving at shuttlepad (or if already there)
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    local callback = F2T_MAP_EXPLORE_STATE.on_complete_callback

    if callback then
        -- Nested mode: call parent (Layer 2 maintains active flag)
        f2t_debug_log("[map-explore-brief] Calling parent callback")
        callback()
    else
        -- Standalone mode: show completion (this clears active flag)
        f2t_debug_log("[map-explore-brief] Standalone mode - showing completion")
        f2t_map_explore_complete()
    end
end

-- ========================================
-- Router: Context-Aware Entry Point
-- ========================================

function f2t_map_explore_start(mode, name)
    -- Router function: Detects context and delegates to appropriate layer
    --
    -- Parameters:
    --   mode: "full" or "brief" (default: "brief")
    --   name: optional planet/system name to explore (auto-detected if nil)
    --
    -- Command patterns:
    --   map explore                      → context-aware, brief mode
    --   map explore <mode>               → context-aware, explicit mode
    --   map explore <mode> <target>      → explicit target, detect planet/system
    --   map explore <target>             → explicit target, brief mode (shorthand)

    -- Default mode to brief
    mode = mode or "brief"

    -- Validate mode
    if mode ~= "full" and mode ~= "brief" then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid mode '%s'\n", mode))
        cecho("\n<dim_grey>Valid modes: full, brief<reset>\n")
        return false
    end

    -- Check if already active
    if F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n")
        cecho("\n<yellow>[map-explore]<reset> Use <white>map explore stop<reset> to stop current exploration\n")
        return false
    end

    -- Check GMCP availability
    if not gmcp or not gmcp.room or not gmcp.room.info then
        cecho("\n<red>[map-explore]<reset> Error: GMCP room data unavailable\n")
        return false
    end

    -- Ensure we know current location
    if not f2t_map_ensure_current_location() then
        cecho("\n<red>[map-explore]<reset> Error: Current location unknown\n")
        return false
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then
        cecho("\n<red>[map-explore]<reset> Error: Not in a mapped room\n")
        return false
    end

    -- Get current area
    local current_area = getRoomArea(current_room)
    if not current_area then
        cecho("\n<red>[map-explore]<reset> Error: Room has no area\n")
        return false
    end

    -- ========================================
    -- Navigation Ownership
    -- ========================================

    -- Set navigation ownership for map-explore
    -- Callback handles interrupts (customs, out_of_fuel) by pausing exploration
    f2t_map_set_nav_owner("map-explore", function(reason)
        f2t_debug_log("[map-explore] Navigation interrupted by %s", reason)

        if reason == "customs" then
            -- Customs stops speedwalk - pause exploration so completion handler
            -- doesn't misinterpret the stop as "user stopped"
            F2T_MAP_EXPLORE_STATE.paused = true
            F2T_MAP_EXPLORE_STATE.paused_reason = reason
        end
        -- out_of_fuel: speedwalk stays active, just retries after refuel

        -- Request auto-resume for all interrupt types
        return { auto_resume = true }
    end)

    -- Register with stamina monitor for this session
    f2t_stamina_register_client({
        pause_callback = f2t_map_explore_pause,
        resume_callback = f2t_map_explore_resume,
        check_active = function()
            return F2T_MAP_EXPLORE_STATE.active and not F2T_MAP_EXPLORE_STATE.paused
        end
    })

    -- ========================================
    -- Context-Aware Routing
    -- ========================================

    -- If name provided, auto-detect target type
    if name and name ~= "" then
        -- Check if it's a planet (using map lookup helper)
        local is_planet = f2t_map_lookup_planet(name)

        -- Check if it's a system (using map lookup helper)
        local is_system = f2t_map_lookup_system(name)

        f2t_debug_log("[map-explore] [Router] Target '%s': is_planet=%s, is_system=%s",
            name, tostring(is_planet ~= nil), tostring(is_system ~= nil))

        if is_system and is_planet then
            -- Name collision: prefer unexplored system over planet
            -- Check if system is fully mapped (all expected planets have shuttlepad+exchange)
            local system_fully_mapped = f2t_map_explore_is_system_fully_mapped(name)

            if system_fully_mapped then
                -- System already explored, explore the planet
                f2t_debug_log("[map-explore] [Router] Name collision '%s': system fully mapped → planet mode", name)
                return f2t_map_explore_planet_start(mode, name)
            else
                -- System not fully mapped, explore the system
                f2t_debug_log("[map-explore] [Router] Name collision '%s': system not fully mapped → system mode", name)
                return f2t_map_explore_system_start(name, mode)
            end

        elseif is_system then
            -- It's a system
            f2t_debug_log("[map-explore] [Router] Name '%s' resolved to system → Layer 2", name)
            return f2t_map_explore_system_start(name, mode)

        elseif is_planet then
            -- It's a planet
            f2t_debug_log("[map-explore] [Router] Name '%s' resolved to planet → Layer 1", name)
            return f2t_map_explore_planet_start(mode, name)

        else
            -- Unknown target
            cecho(string.format("\n<red>[map]<reset> Unknown planet or system: %s\n", name))
            return false
        end
    end

    -- No name provided - detect context from current location
    local area_name = getRoomAreaName(current_area)
    if area_name and area_name:match(" Space$") then
        -- We're in space → Layer 2 (system exploration)
        local system = f2t_get_current_system()
        if not system then
            cecho("\n<red>[map-explore]<reset> Error: In space but couldn't detect system\n")
            return false
        end

        f2t_debug_log("[map-explore] [Router] Context: space (system: %s) → Layer 2 (%s mode)", system, mode)
        return f2t_map_explore_system_start(system, mode)
    end

    -- We're on a planet → Layer 1 (planet exploration)
    local planet = f2t_get_current_planet()
    f2t_debug_log("[map-explore] [Router] Context: planet (%s) → Layer 1 (%s mode)", planet or "unknown", mode)
    return f2t_map_explore_planet_start(mode, planet)
end

-- ========================================
-- Check if System is Fully Mapped
-- ========================================

function f2t_map_explore_is_system_fully_mapped(system_name)
    -- Returns true if system has all planets mapped with shuttlepad+exchange
    -- Used for name collision handling (prefer unexplored system)

    -- Find the system's space area
    local space_area_name = f2t_map_get_system_space_area_actual(system_name)
    if not space_area_name then
        return false  -- No space area = not mapped at all
    end

    local space_area_id = f2t_map_get_area_id(space_area_name)
    if not space_area_id then
        return false
    end

    -- Get all orbit rooms (planets) in the space area
    local rooms_in_area = getAreaRooms(space_area_id)
    if not rooms_in_area then
        return false
    end

    local planets_found = {}
    for _, room_id in pairs(rooms_in_area) do
        local planet_name = getRoomUserData(room_id, "fed2_planet")
        if planet_name and planet_name ~= "" then
            planets_found[planet_name] = true
        end
    end

    -- If no planets found, system is not fully mapped
    if next(planets_found) == nil then
        return false
    end

    -- Check each planet for shuttlepad and exchange
    for planet_name, _ in pairs(planets_found) do
        local planet_area_id = f2t_map_get_area_id(planet_name)
        if not planet_area_id then
            return false  -- Planet area not mapped
        end

        -- Check for shuttlepad
        local shuttlepad_rooms = f2t_map_find_all_rooms_with_flag(planet_area_id, "shuttlepad")
        if not shuttlepad_rooms or #shuttlepad_rooms == 0 then
            return false  -- No shuttlepad found
        end

        -- Check for exchange
        local exchange_rooms = f2t_map_find_all_rooms_with_flag(planet_area_id, "exchange")
        if not exchange_rooms or #exchange_rooms == 0 then
            return false  -- No exchange found
        end
    end

    -- All planets have shuttlepad and exchange
    return true
end

-- ========================================
-- Unlock Temporarily Locked Exits
-- ========================================

function f2t_map_explore_unlock_temp_exits()
    if not F2T_MAP_EXPLORE_STATE.temp_locked_exits then
        return
    end

    local unlock_count = 0

    for room_id, directions in pairs(F2T_MAP_EXPLORE_STATE.temp_locked_exits) do
        for _, direction in ipairs(directions) do
            lockExit(room_id, direction, false)
            unlock_count = unlock_count + 1
            f2t_debug_log("[map-explore] Unlocked temporary exit: room=%d, direction=%s", room_id, direction)
        end
    end

    if unlock_count > 0 then
        f2t_debug_log("[map-explore] Unlocked %d temporarily locked exits", unlock_count)
    end

    F2T_MAP_EXPLORE_STATE.temp_locked_exits = {}
end

-- ========================================
-- Stop Exploration
-- ========================================

function f2t_map_explore_stop()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n")
        return
    end

    -- Clear navigation ownership
    f2t_map_clear_nav_owner()

    -- Unregister from stamina monitor (monitoring continues in standalone mode)
    f2t_stamina_unregister_client()

    -- Unlock temporarily locked exits
    f2t_map_explore_unlock_temp_exits()

    -- Show statistics
    cecho("\n<yellow>[map]<reset> Exploration stopped by user\n")
    f2t_map_explore_show_statistics()

    -- Clear state
    F2T_MAP_EXPLORE_STATE = {
        active = false,
        paused = false,
        pause_requested = false,
        phase = nil,
        visited_rooms = {},
        frontier_stack = {},
        planned_exit = nil,
        special_exit_patterns = {},
        special_exit_attempts = {},
        suspected_special_exits = {},
        death_room_id = nil,
        recovery_in_progress = false,
        last_room_before_move = nil,
        last_direction_attempted = nil,
        temp_locked_exits = {},
        stats = {rooms_discovered = 0, special_exits_found = 0, suspected_special_exits = 0, blocked_exits = 0, deaths = 0},
        -- System/cartel state
        mode = nil,
        system_name = nil,
        system_mode = nil,
        expected_planets = nil,
        expected_planets_found = nil,
        expected_planets_remaining = nil,
        planets_without_exchange = nil,
        cartel_name = nil,
        planet_list = {},
        current_planet_index = 0,
        system_list = {},
        current_system_index = 0,
        system_stats = {planets_explored = 0, exchanges_found = 0, planets_skipped = 0},
        cartel_stats = {total_systems = 0, systems_explored = 0, total_planets = 0, total_exchanges = 0, total_planets_skipped = 0},
        -- Galaxy state
        galaxy_cartel_list = {},
        galaxy_current_cartel_index = 0,
        galaxy_target_cartel = nil,
        galaxy_stats = {total_cartels = 0, cartels_explored = 0, cartels_skipped = 0, total_systems = 0, total_planets = 0}
    }

    f2t_debug_log("[map-explore] Stopped by user")
end

-- ========================================
-- Pause/Resume Exploration
-- ========================================

function f2t_map_explore_pause()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n")
        return
    end

    if F2T_MAP_EXPLORE_STATE.paused or F2T_MAP_EXPLORE_STATE.pause_requested then
        cecho("\n<yellow>[map-explore]<reset> Exploration already paused\n")
        return
    end

    -- Deferred pause: let current operation complete, pause at next phase boundary
    F2T_MAP_EXPLORE_STATE.pause_requested = true
    cecho(string.format("\n<yellow>[map]<reset> Will pause after current operation... (phase: <cyan>%s<reset>)\n",
        F2T_MAP_EXPLORE_STATE.phase or "unknown"))

    f2t_debug_log("[map-explore] Deferred pause requested (phase: %s)", F2T_MAP_EXPLORE_STATE.phase or "unknown")
end

-- Check and activate deferred pause at a phase boundary
-- Returns true if pause was activated (caller should return early)
function f2t_map_explore_check_deferred_pause()
    if not F2T_MAP_EXPLORE_STATE.pause_requested then
        return false
    end

    F2T_MAP_EXPLORE_STATE.pause_requested = false
    F2T_MAP_EXPLORE_STATE.paused = true
    cecho(string.format("\n<yellow>[map]<reset> Exploration paused at phase: <cyan>%s<reset>\n",
        F2T_MAP_EXPLORE_STATE.phase or "unknown"))
    cecho("  Use <white>map explore resume<reset> to continue\n")
    f2t_debug_log("[map-explore] Deferred pause activated at phase: %s", F2T_MAP_EXPLORE_STATE.phase or "unknown")
    return true
end

function f2t_map_explore_resume()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n")
        return
    end

    -- Cancel a pending deferred pause that hasn't activated yet
    if F2T_MAP_EXPLORE_STATE.pause_requested then
        F2T_MAP_EXPLORE_STATE.pause_requested = false
        cecho("\n<green>[map]<reset> Pending pause cancelled\n")
        f2t_debug_log("[map-explore] Pending pause cancelled")
        return
    end

    if not F2T_MAP_EXPLORE_STATE.paused then
        cecho("\n<yellow>[map-explore]<reset> Exploration not paused\n")
        return
    end

    F2T_MAP_EXPLORE_STATE.paused = false
    cecho("\n<green>[map]<reset> Exploration resumed\n")

    f2t_debug_log("[map-explore] Resumed (paused_reason: %s)", F2T_MAP_EXPLORE_STATE.paused_reason or "none")

    -- Check if we were paused due to stranded state
    if F2T_MAP_EXPLORE_STATE.paused_reason == "stranded" then
        -- Clear stranded state
        F2T_MAP_EXPLORE_STATE.paused_reason = nil
        local destination = F2T_MAP_EXPLORE_STATE.paused_destination
        F2T_MAP_EXPLORE_STATE.paused_destination = nil

        -- If we have brief flags (we were in brief mode), try returning to shuttlepad again
        if F2T_MAP_EXPLORE_STATE.brief_flags_found then
            f2t_debug_log("[map-explore] Resuming from stranded - retrying return to shuttlepad")
            f2t_map_explore_brief_return_to_shuttlepad()
            return
        elseif destination then
            -- Try to navigate to the original destination
            f2t_debug_log("[map-explore] Resuming from stranded - retrying navigation to %d", destination)
            if f2t_map_navigate(tostring(destination)) then
                -- Navigation working now, wait for arrival
                F2T_MAP_EXPLORE_STATE.phase = "navigating"
                return
            end
            -- Still can't navigate - try escape procedure
            f2t_map_explore_escape_start(
                destination,
                function()
                    f2t_debug_log("[map-explore] Successfully reached destination after resume")
                    f2t_map_explore_next_step()
                end,
                function(reason)
                    f2t_debug_log("[map-explore] Still cannot navigate after resume: %s", reason)
                    f2t_map_explore_pause_stranded(reason, destination)
                end
            )
            return
        end
    end

    -- Clear any orphaned escape state (if user paused during active escape)
    if F2T_MAP_EXPLORE_STATE.escape_state then
        f2t_debug_log("[map-explore] Clearing orphaned escape state from interrupted escape")
        F2T_MAP_EXPLORE_STATE.escape_state = nil
    end

    -- Reset phase if it was in escape mode
    if F2T_MAP_EXPLORE_STATE.phase == "brief_escaping" then
        f2t_debug_log("[map-explore] Resetting phase from brief_escaping to navigating")
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
    end

    -- Clear any leftover stranded state
    F2T_MAP_EXPLORE_STATE.paused_reason = nil
    F2T_MAP_EXPLORE_STATE.paused_destination = nil

    -- Continue exploration normally
    f2t_map_explore_next_step()
end

-- ========================================
-- Show Status
-- ========================================

function f2t_map_explore_status()
    if not F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> No exploration in progress\n")
        return
    end

    cecho("\n<green>[map]<reset> Exploration Status\n\n")

    -- Current state
    local state_str = "ACTIVE"
    if F2T_MAP_EXPLORE_STATE.paused then
        if F2T_MAP_EXPLORE_STATE.paused_reason == "stranded" then
            state_str = "PAUSED (stranded - manual intervention required)"
        else
            state_str = "PAUSED"
        end
    end
    cecho(string.format("  State: <white>%s<reset>\n", state_str))
    cecho(string.format("  Phase: <white>%s<reset>\n", F2T_MAP_EXPLORE_STATE.phase or "unknown"))

    -- Show stranded destination if applicable
    if F2T_MAP_EXPLORE_STATE.paused_reason == "stranded" and F2T_MAP_EXPLORE_STATE.paused_destination then
        local dest_room = F2T_MAP_EXPLORE_STATE.paused_destination
        local dest_name = getRoomName(dest_room) or "Unknown"
        cecho(string.format("  Target: <yellow>%s<reset> (room %d)\n", dest_name, dest_room))
    end

    -- Statistics
    f2t_map_explore_show_statistics()

    -- Frontier info
    local frontier_count = #F2T_MAP_EXPLORE_STATE.frontier_stack
    cecho(string.format("  Unexplored exits: <white>%d<reset>\n", frontier_count))

    -- Current room
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room then
        local room_name = getRoomName(current_room) or "Unknown"
        cecho(string.format("  Current room: <white>%s<reset> (ID: %d)\n", room_name, current_room))
    end
end

-- ========================================
-- Show Statistics
-- ========================================

function f2t_map_explore_show_statistics()
    local stats = F2T_MAP_EXPLORE_STATE.stats
    local mode = F2T_MAP_EXPLORE_STATE.mode or "planet"
    local planet_mode = F2T_MAP_EXPLORE_STATE.planet_mode

    cecho("\n  Statistics:\n")

    -- Mode-specific statistics
    if mode == "planet" then
        if planet_mode == "full" then
            -- Planet full exploration (DFS)
            cecho(string.format("    Rooms discovered: <white>%d<reset>\n", stats.rooms_discovered))
            cecho(string.format("    Special exits found: <white>%d<reset>\n", stats.special_exits_found))
            cecho(string.format("    Suspected special exits: <white>%d<reset>\n", stats.suspected_special_exits))
            cecho(string.format("    Blocked exits: <white>%d<reset>\n", stats.blocked_exits))
            cecho(string.format("    Deaths: <white>%d<reset>\n", stats.deaths))
        else
            -- Planet brief exploration (flag finding)
            local flags_found = F2T_MAP_EXPLORE_STATE.brief_flags_found or {}
            local total_flags = #(F2T_MAP_EXPLORE_STATE.brief_flags or {})
            local found_count = 0
            local found_names = {}
            for flag, _ in pairs(flags_found) do
                found_count = found_count + 1
                table.insert(found_names, flag)
            end
            cecho(string.format("    Flags found: <white>%d/%d<reset>\n", found_count, total_flags))
            if found_count > 0 then
                cecho(string.format("    Found: <white>%s<reset>\n", table.concat(found_names, ", ")))
            end
        end

    elseif mode == "system" then
        -- System exploration
        local sys_stats = F2T_MAP_EXPLORE_STATE.system_stats
        local total_planets = sys_stats.total_planets or #F2T_MAP_EXPLORE_STATE.planet_list
        cecho(string.format("    Planets explored: <white>%d/%d<reset>\n",
            sys_stats.planets_explored, total_planets))
        cecho(string.format("    Exchanges found: <white>%d<reset>\n", sys_stats.exchanges_found))
        cecho(string.format("    Planets skipped: <white>%d<reset>\n", sys_stats.planets_skipped))
        if sys_stats.planets_incomplete and sys_stats.planets_incomplete > 0 then
            cecho(string.format("    Planets incomplete: <yellow>%d<reset>\n", sys_stats.planets_incomplete))
            for _, planet_info in ipairs(sys_stats.incomplete_planets or {}) do
                cecho(string.format("      - <white>%s<reset>: missing <yellow>%s<reset>\n",
                    planet_info.name, table.concat(planet_info.missing_flags, ", ")))
            end
        end
        cecho(string.format("    Rooms discovered: <white>%d<reset>\n", stats.rooms_discovered))
        cecho(string.format("    Blocked exits: <white>%d<reset>\n", stats.blocked_exits))

    elseif mode == "cartel" then
        -- Cartel exploration
        local cartel_stats = F2T_MAP_EXPLORE_STATE.cartel_stats
        cecho(string.format("    Systems explored: <white>%d/%d<reset>\n",
            cartel_stats.systems_explored, cartel_stats.total_systems))
        cecho(string.format("    Total planets: <white>%d<reset>\n", cartel_stats.total_planets))
        cecho(string.format("    Total exchanges: <white>%d<reset>\n", cartel_stats.total_exchanges))
        cecho(string.format("    Planets skipped: <white>%d<reset>\n", cartel_stats.total_planets_skipped))
        if cartel_stats.total_planets_incomplete and cartel_stats.total_planets_incomplete > 0 then
            cecho(string.format("    Planets incomplete: <yellow>%d<reset>\n",
                cartel_stats.total_planets_incomplete))
            for _, planet_info in ipairs(cartel_stats.incomplete_planets or {}) do
                cecho(string.format("      - <white>%s<reset>: missing <yellow>%s<reset>\n",
                    planet_info.name, table.concat(planet_info.missing_flags, ", ")))
            end
        end
        cecho(string.format("    Rooms discovered: <white>%d<reset>\n", stats.rooms_discovered))

    elseif mode == "galaxy" then
        -- Galaxy exploration
        local galaxy_stats = F2T_MAP_EXPLORE_STATE.galaxy_stats
        cecho(string.format("    Cartels explored: <white>%d/%d<reset>\n",
            galaxy_stats.cartels_explored, galaxy_stats.total_cartels))
        cecho(string.format("    Cartels skipped: <white>%d<reset>\n", galaxy_stats.cartels_skipped))
        cecho(string.format("    Total systems: <white>%d<reset>\n", galaxy_stats.total_systems))
        cecho(string.format("    Total planets: <white>%d<reset>\n", galaxy_stats.total_planets))
        cecho(string.format("    Rooms discovered: <white>%d<reset>\n", stats.rooms_discovered))
    end
end

-- ========================================
-- Show Completion Report
-- ========================================

function f2t_map_explore_complete()
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    -- Unregister from stamina monitor (monitoring continues in standalone mode)
    f2t_stamina_unregister_client()

    -- Unlock temporarily locked exits
    f2t_map_explore_unlock_temp_exits()

    cecho("\n<green>[map]<reset> Exploration Complete!\n")

    -- Statistics
    f2t_map_explore_show_statistics()

    -- Suspected special exits
    if #F2T_MAP_EXPLORE_STATE.suspected_special_exits > 0 then
        cecho("\n  <yellow>Suspected Special Exits<reset> (manual mapping recommended):\n")
        for _, suspect in ipairs(F2T_MAP_EXPLORE_STATE.suspected_special_exits) do
            cecho(string.format("    - <white>%s<reset> (Keywords: %s)\n",
                suspect.room_name or "Unknown",
                table.concat(suspect.keywords or {}, ", ")))
        end
    end

    cecho("\n")

    f2t_debug_log("[map-explore] Exploration complete: %d rooms, %d special exits, %d suspected, %d blocked",
        F2T_MAP_EXPLORE_STATE.stats.rooms_discovered,
        F2T_MAP_EXPLORE_STATE.stats.special_exits_found,
        F2T_MAP_EXPLORE_STATE.stats.suspected_special_exits,
        F2T_MAP_EXPLORE_STATE.stats.blocked_exits)

    -- Clear state
    F2T_MAP_EXPLORE_STATE = {
        active = false,
        paused = false,
        pause_requested = false,
        phase = nil,
        visited_rooms = {},
        frontier_stack = {},
        planned_exit = nil,
        special_exit_patterns = {},
        special_exit_attempts = {},
        suspected_special_exits = {},
        death_room_id = nil,
        recovery_in_progress = false,
        last_room_before_move = nil,
        last_direction_attempted = nil,
        temp_locked_exits = {},
        stats = {rooms_discovered = 0, special_exits_found = 0, suspected_special_exits = 0, blocked_exits = 0, deaths = 0},
        -- System/cartel state
        mode = nil,
        system_name = nil,
        system_mode = nil,
        expected_planets = nil,
        expected_planets_found = nil,
        expected_planets_remaining = nil,
        planets_without_exchange = nil,
        cartel_name = nil,
        planet_list = {},
        current_planet_index = 0,
        system_list = {},
        current_system_index = 0,
        system_stats = {planets_explored = 0, exchanges_found = 0, planets_skipped = 0},
        cartel_stats = {total_systems = 0, systems_explored = 0, total_planets = 0, total_exchanges = 0, total_planets_skipped = 0},
        -- Galaxy state
        galaxy_cartel_list = {},
        galaxy_current_cartel_index = 0,
        galaxy_target_cartel = nil,
        galaxy_stats = {total_cartels = 0, cartels_explored = 0, cartels_skipped = 0, total_systems = 0, total_planets = 0}
    }
end

-- ========================================
-- Show Suspected Exits
-- ========================================

function f2t_map_explore_list_suspected()
    if #F2T_MAP_EXPLORE_STATE.suspected_special_exits == 0 then
        cecho("\n<yellow>[map-explore]<reset> No suspected special exits recorded\n")
        return
    end

    cecho("\n<green>[map]<reset> Suspected Special Exits\n\n")

    for i, suspect in ipairs(F2T_MAP_EXPLORE_STATE.suspected_special_exits) do
        cecho(string.format("%d. <white>%s<reset>\n", i, suspect.room_name or "Unknown"))
        cecho(string.format("   Keywords: %s\n", table.concat(suspect.keywords or {}, ", ")))
        if suspect.tried_commands and #suspect.tried_commands > 0 then
            cecho(string.format("   Tried: %s\n", table.concat(suspect.tried_commands, ", ")))
        end
        cecho("\n")
    end
end

-- ========================================
-- Main Exploration Loop
-- ========================================

function f2t_map_explore_next_step()
    -- Guard: Check if active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    -- Guard: Check if paused
    if F2T_MAP_EXPLORE_STATE.paused then
        return
    end

    -- Deferred pause: convert pause_requested to actual pause at phase boundary
    if f2t_map_explore_check_deferred_pause() then
        return
    end

    -- Guard: Check if waiting for death recovery
    if F2T_MAP_EXPLORE_STATE.phase == "paused_death" then
        return
    end

    f2t_debug_log("[map-explore] Next step: phase=%s", F2T_MAP_EXPLORE_STATE.phase or "nil")

    -- Phase-based dispatch
    if F2T_MAP_EXPLORE_STATE.phase == "navigating" then
        f2t_map_explore_navigate_to_next()

    elseif F2T_MAP_EXPLORE_STATE.phase == "discovering_special" then
        -- Special exit discovery (Phase 2) - stub for now
        -- For Phase 1, just continue navigation
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        f2t_map_explore_next_step()

    -- ========================================
    -- System/Cartel Exploration Phases (NEW)
    -- ========================================

    elseif F2T_MAP_EXPLORE_STATE.phase == "navigating_to_orbit" then
        -- Handled by speedwalk + room change event
        -- Just wait for arrival
        return

    elseif F2T_MAP_EXPLORE_STATE.phase == "finding_exchange" then
        -- Run BFS search from shuttlepad
        f2t_map_explore_planet_find_exchange()

    elseif F2T_MAP_EXPLORE_STATE.phase == "planet_complete" then
        -- Move to next planet
        f2t_map_explore_system_next_planet()

    -- ========================================
    -- Brief Exploration Phases (NEW)
    -- ========================================

    elseif F2T_MAP_EXPLORE_STATE.phase == "finding_flags" then
        -- Run BFS search for next flag
        f2t_map_explore_brief_find_next_flag()

    elseif F2T_MAP_EXPLORE_STATE.phase == "navigating_to_flag" then
        -- Handled by speedwalk + room change event
        -- Just wait for arrival
        return

    -- ========================================

    elseif F2T_MAP_EXPLORE_STATE.phase == "returning" then
        f2t_map_explore_return_to_start()
    end
end

-- ========================================
-- GMCP Room Change Handler
-- ========================================

function f2t_map_explore_on_room_change()
    -- Guard: Check if active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    -- Skip if paused (another system like stamina monitor is navigating)
    if F2T_MAP_EXPLORE_STATE.paused then
        return
    end

    -- Skip if speedwalk is active (we're navigating)
    if F2T_SPEEDWALK_ACTIVE then
        return
    end

    -- Handle escape mode: delegate to escape handler
    if F2T_MAP_EXPLORE_STATE.phase == "brief_escaping" and F2T_MAP_EXPLORE_STATE.escape_state then
        -- Check if speedwalk just finished during escape
        if F2T_SPEEDWALK_LAST_RESULT then
            local result = F2T_SPEEDWALK_LAST_RESULT
            F2T_SPEEDWALK_LAST_RESULT = nil  -- Consume the result
            f2t_debug_log("[map-explore] Speedwalk finished during escape with result: %s", result)

            if f2t_map_explore_escape_on_speedwalk_complete(result) then
                return
            end
        else
            -- Room changed during escape (not speedwalk completion)
            if f2t_map_explore_escape_on_room_change() then
                return
            end
        end
    end

    -- Check if speedwalk just finished (completed, stopped, or failed)
    -- This happens when we're NOT navigating manually but speedwalk was active and now isn't
    if F2T_SPEEDWALK_LAST_RESULT then
        local result = F2T_SPEEDWALK_LAST_RESULT
        F2T_SPEEDWALK_LAST_RESULT = nil  -- Consume the result

        f2t_debug_log("[map-explore] Speedwalk finished with result: %s", result)

        if result == "failed" then
            -- Lock the exit that speedwalk couldn't traverse
            local failed_room = F2T_SPEEDWALK_FAILED_EXIT_ROOM
            local failed_dir = F2T_SPEEDWALK_FAILED_EXIT_DIR
            F2T_SPEEDWALK_FAILED_EXIT_ROOM = nil  -- Consume
            F2T_SPEEDWALK_FAILED_EXIT_DIR = nil   -- Consume

            if failed_room and failed_dir then
                lockExit(failed_room, failed_dir, true)
                cecho(string.format("\n<yellow>[map-explore]<reset> Locked blocked exit %s from room %d, trying next exit...\n",
                    failed_dir, failed_room))
                f2t_debug_log("[map-explore] Locked blocked exit: room=%d, direction=%s", failed_room, failed_dir)

                -- Track the lock for cleanup
                if not F2T_MAP_EXPLORE_STATE.temp_locked_exits[failed_room] then
                    F2T_MAP_EXPLORE_STATE.temp_locked_exits[failed_room] = {}
                end
                table.insert(F2T_MAP_EXPLORE_STATE.temp_locked_exits[failed_room], failed_dir)
                F2T_MAP_EXPLORE_STATE.stats.blocked_exits = F2T_MAP_EXPLORE_STATE.stats.blocked_exits + 1
            else
                cecho("\n<yellow>[map-explore]<reset> Navigation failed, trying next exit...\n")
                f2t_debug_log("[map-explore] Speedwalk failed (no exit info available)")
            end

            -- Continue with next exit
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then
                    f2t_map_explore_next_step()
                end
            end)
            return

        elseif result == "stopped" then
            -- Speedwalk was stopped - check if we intentionally paused
            if F2T_MAP_EXPLORE_STATE.paused then
                -- We paused intentionally (e.g., stamina food trip, customs inspection)
                -- Don't stop exploration, just wait for resume
                f2t_debug_log("[map-explore] Speedwalk stopped while paused - waiting for resume")
                return
            end

            -- User stopped speedwalk manually
            cecho("\n<yellow>[map-explore]<reset> Navigation stopped by user, stopping exploration\n")
            f2t_debug_log("[map-explore] Speedwalk stopped by user")
            f2t_map_explore_stop()
            return
        end

        -- If result == "completed", continue with normal room change handling below
    end

    -- Skip if paused or waiting for death recovery
    if F2T_MAP_EXPLORE_STATE.paused or F2T_MAP_EXPLORE_STATE.phase == "paused_death" then
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if not current_room then
        return
    end

    f2t_debug_log("[map-explore] Room changed: room_id=%d, phase=%s", current_room, F2T_MAP_EXPLORE_STATE.phase or "nil")

    -- Connect stub exit if we just moved through one
    -- (Blocked exits now handled by speedwalk failure detection)
    if F2T_MAP_EXPLORE_STATE.last_room_before_move and F2T_MAP_EXPLORE_STATE.last_direction_attempted then
        f2t_map_resolve_stub_exit(
            F2T_MAP_EXPLORE_STATE.last_room_before_move,
            current_room,
            F2T_MAP_EXPLORE_STATE.last_direction_attempted
        )
    end

    -- Clear movement tracking (successful move)
    F2T_MAP_EXPLORE_STATE.last_room_before_move = nil
    F2T_MAP_EXPLORE_STATE.last_direction_attempted = nil

    -- Check if this is the first visit (before marking as visited)
    local is_first_visit = not F2T_MAP_EXPLORE_STATE.visited_rooms[current_room]

    -- Mark room as visited
    if is_first_visit then
        F2T_MAP_EXPLORE_STATE.visited_rooms[current_room] = true
        F2T_MAP_EXPLORE_STATE.stats.rooms_discovered = F2T_MAP_EXPLORE_STATE.stats.rooms_discovered + 1

        f2t_debug_log("[map-explore] New room visited: %d (%s)", current_room, getRoomName(current_room) or "unknown")

        -- Brief mode: Check if this room has any target flags
        -- Only check during active brief exploration (phase = "navigating")
        -- Detect brief mode by presence of brief_flags_remaining_count field
        f2t_debug_log("[map-explore] Room visit check - brief_flags_remaining_count: %s, phase: %s",
            tostring(F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count), tostring(F2T_MAP_EXPLORE_STATE.phase))

        if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count and F2T_MAP_EXPLORE_STATE.phase == "navigating" then
            f2t_debug_log("[map-explore] Calling brief_check_room_flags for room %d", current_room)
            f2t_map_explore_brief_check_room_flags(current_room)

            -- If all flags found, brief mode will call callback - don't continue exploring
            if F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count == 0 then
                f2t_debug_log("[map-explore] Brief complete, waiting for callback execution")
                return
            end
        end

        -- System brief mode: Check if this room is an orbit for an expected planet
        -- Only check during Phase 1 (exploring_space) when in brief mode
        if F2T_MAP_EXPLORE_STATE.system_mode == "brief" and
           F2T_MAP_EXPLORE_STATE.system_phase == "exploring_space" and
           F2T_MAP_EXPLORE_STATE.phase == "navigating" then
            f2t_debug_log("[map-explore] Calling system_check_room_for_planets for room %d", current_room)
            f2t_map_explore_system_check_room_for_planets(current_room)

            -- If all expected planets found, system mode will call completion - don't continue
            if F2T_MAP_EXPLORE_STATE.expected_planets_remaining and
               F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 then
                f2t_debug_log("[map-explore] System brief complete (all planets found), waiting for callback")
                return
            end
        end

        -- Recompute frontier after each new room visit (if still navigating)
        -- BUT: Don't recompute if we have a planned_exit - we navigated here specifically
        -- to take that exit, and recomputing would change distances before we use it
        if F2T_MAP_EXPLORE_STATE.phase == "navigating" and not F2T_MAP_EXPLORE_STATE.planned_exit then
            f2t_debug_log("[map-explore] Recomputing frontier after visiting room %d", current_room)
            f2t_map_explore_recompute_frontier()
        elseif F2T_MAP_EXPLORE_STATE.planned_exit then
            f2t_debug_log("[map-explore] Skipping frontier recompute (have planned_exit: room=%d, dir=%s)",
                F2T_MAP_EXPLORE_STATE.planned_exit.room_id, F2T_MAP_EXPLORE_STATE.planned_exit.direction)
        end
    end


    -- ========================================
    -- Galaxy Mode: Phase Transitions
    -- ========================================

    if F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
        if F2T_MAP_EXPLORE_STATE.phase == "jumping_to_cartel" then
            -- Arrived at main system's link room, now jump to target cartel
            local target_cartel = F2T_MAP_EXPLORE_STATE.galaxy_target_cartel
            local current_system = getRoomUserData(current_room, "fed2_system")
            f2t_debug_log("[map-explore] Arrived at %s link, jumping to cartel %s", current_system or "unknown", target_cartel)

            cecho(string.format("  <dim_grey>Jumping to %s<reset>\n", target_cartel))

            -- Use speedwalk pattern for jump command (protections: timeout, retry, etc.)
            speedWalkDir = {string.format("jump %s", target_cartel)}
            speedWalkPath = {nil}  -- Blind movement, destination unknown
            doSpeedWalk()

            -- Update phase to wait for arrival in new cartel
            F2T_MAP_EXPLORE_STATE.phase = "arriving_in_cartel"
            return

        elseif F2T_MAP_EXPLORE_STATE.phase == "arriving_in_cartel" then
            -- Arrived in new cartel after jump (GMCP will auto-map first room)
            local target_cartel = F2T_MAP_EXPLORE_STATE.galaxy_target_cartel
            local current_cartel = f2t_map_get_current_cartel()

            f2t_debug_log("[map-explore] Arrived in cartel: %s (target was: %s)",
                current_cartel or "unknown", target_cartel)

            -- Verify we arrived in the right cartel (case-insensitive)
            if not current_cartel or current_cartel:lower() ~= target_cartel:lower() then
                cecho(string.format("  <red>Error:<reset> Jump failed or arrived in wrong cartel (%s instead of %s)\n",
                    current_cartel or "unknown", target_cartel))
                f2t_debug_log("[map-explore] Jump failed: expected %s, got %s", target_cartel, current_cartel or "nil")

                -- Skip this cartel and move to next
                F2T_MAP_EXPLORE_STATE.phase = nil
                f2t_map_explore_galaxy_next_cartel()
                return
            end

            -- Success! Start cartel exploration
            cecho(string.format("  <green>Arrived in %s!<reset>\n", target_cartel))

            -- Update galaxy stats
            F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored = F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored + 1

            -- Clear phase and invoke cartel mode
            F2T_MAP_EXPLORE_STATE.phase = nil
            F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil

            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then
                    f2t_map_explore_galaxy_start_cartel_mode(target_cartel)
                end
            end)
            return
        end
    end

    -- ========================================
    -- System/Cartel Mode: Phase Transitions
    -- ========================================

    if F2T_MAP_EXPLORE_STATE.mode == "system" or F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
        if F2T_MAP_EXPLORE_STATE.phase == "jumping_to_system" then
            -- Arrived at link room, now jump to target system
            local target_system = F2T_MAP_EXPLORE_STATE.cartel_target_system
            f2t_debug_log("[map-explore] Arrived at link, jumping to %s", target_system)

            cecho(string.format("  <dim_grey>Jumping to %s<reset>\n", target_system))

            -- Use speedwalk pattern for jump command (protections: timeout, retry, etc.)
            speedWalkDir = {string.format("jump %s", target_system)}
            speedWalkPath = {nil}  -- Blind movement, destination unknown
            doSpeedWalk()

            -- Update phase to wait for arrival in new system
            F2T_MAP_EXPLORE_STATE.phase = "arriving_in_system"
            return

        elseif F2T_MAP_EXPLORE_STATE.phase == "arriving_in_system" then
            -- Arrived in new system after jump (GMCP will auto-map first room)
            local target_system = F2T_MAP_EXPLORE_STATE.cartel_target_system
            local current_system = getRoomUserData(current_room, "fed2_system")

            f2t_debug_log("[map-explore] Arrived in system: %s (target was: %s)",
                current_system or "unknown", target_system)

            -- Verify we arrived in the right system
            if current_system ~= target_system then
                cecho(string.format("  <red>Error:<reset> Jump failed or arrived in wrong system (%s instead of %s)\n",
                    current_system or "unknown", target_system))
                f2t_debug_log("[map-explore] Jump failed: expected %s, got %s", target_system, current_system or "nil")

                -- Skip this system and move to next
                F2T_MAP_EXPLORE_STATE.phase = nil
                f2t_map_explore_cartel_next_system()
                return
            end

            -- Success! Start system exploration
            cecho(string.format("  <green>Arrived in %s!<reset>\n", target_system))

            -- Update cartel stats
            F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored = F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1

            -- Clear phase and invoke system mode
            F2T_MAP_EXPLORE_STATE.phase = nil
            F2T_MAP_EXPLORE_STATE.cartel_target_system = nil

            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then
                    f2t_map_explore_cartel_start_system_mode(target_system)
                end
            end)
            return

        elseif F2T_MAP_EXPLORE_STATE.phase == "navigating_to_orbit" then
            -- Arrived at orbit room, board the planet
            f2t_debug_log("[map-explore] Arrived at orbit, boarding planet")
            F2T_MAP_EXPLORE_STATE.phase = "at_orbit"
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.phase == "at_orbit" then
                    f2t_map_explore_system_board_planet()
                end
            end)
            return

        elseif F2T_MAP_EXPLORE_STATE.phase == "boarding_planet" then
            -- Arrived on planet surface - delegate to Layer 1 (brief or full)
            local planet_name = F2T_MAP_EXPLORE_STATE.brief_target_planet
            f2t_debug_log("[map-explore] Arrived on planet surface: %s (system_phase: %s)",
                planet_name or "unknown", F2T_MAP_EXPLORE_STATE.system_phase or "nil")

            tempTimer(0.5, function()
                if not F2T_MAP_EXPLORE_STATE.active then return end

                if F2T_MAP_EXPLORE_STATE.system_phase == "running_brief" then
                    -- Start brief exploration from shuttlepad (Layer 2 → Layer 1)
                    -- System and cartel modes ONLY do brief discovery (flag finding)
                    f2t_debug_log("[map-explore] Starting brief exploration on %s", planet_name)

                    -- Check if this planet has no exchange (skip exchange flag)
                    local override_flags = nil
                    if F2T_MAP_EXPLORE_STATE.planets_without_exchange and
                       F2T_MAP_EXPLORE_STATE.planets_without_exchange[planet_name] then
                        -- Planet has no exchange - only search for shuttlepad
                        override_flags = {}  -- Empty array = shuttlepad only
                        f2t_debug_log("[map-explore] Planet %s has no exchange, skipping exchange flag", planet_name)
                        cecho(string.format("  <yellow>Note:<reset> Planet has no exchange (Economy: None or Workforce: 0/0)\n"))
                    end

                    -- Start brief exploration with callback (Layer 2 delegates to Layer 1)
                    f2t_map_explore_planet_start("brief", planet_name, function()
                        f2t_map_explore_system_brief_next_planet()
                    end, override_flags)
                end
            end)
            return

        elseif F2T_MAP_EXPLORE_STATE.phase == "planet_complete" then
            -- Arrived at exchange, planet exploration complete
            local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]
            cecho(string.format("  <green>Exchange found on %s!<reset>\n", planet.name))
            f2t_debug_log("[map-explore] Arrived at exchange on %s", planet.name)

            -- Update statistics
            F2T_MAP_EXPLORE_STATE.system_stats.planets_explored = F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
            F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found = F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1

            -- Aggregate to cartel stats if in cartel mode
            if F2T_MAP_EXPLORE_STATE.mode == "cartel" then
                F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets = F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets + 1
                F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges = F2T_MAP_EXPLORE_STATE.cartel_stats.total_exchanges + 1
            end

            -- Move to next planet
            tempTimer(0.5, function()
                if F2T_MAP_EXPLORE_STATE.active then
                    f2t_map_explore_system_next_planet()
                end
            end)
            return
        end
    end

    -- ========================================
    -- Area Mode: Phase Transitions (existing)
    -- ========================================

    -- Phase transitions
    if F2T_MAP_EXPLORE_STATE.phase == "navigating" then
        -- Continue with next exit from frontier
        -- Frontier is always up-to-date from recomputation after each visit
        F2T_MAP_EXPLORE_STATE.phase = "discovering_special"
        f2t_map_explore_next_step()

    elseif F2T_MAP_EXPLORE_STATE.phase == "returning" then
        -- Check if we're back at start
        f2t_debug_log("[map-explore] In returning phase, current_room=%d, starting_room=%d",
            current_room, F2T_MAP_EXPLORE_STATE.starting_room_id)
        if current_room == F2T_MAP_EXPLORE_STATE.starting_room_id then
            -- Call return_to_start which checks for callback vs completion
            f2t_debug_log("[map-explore] At starting room, calling return_to_start")
            f2t_map_explore_return_to_start()
        else
            -- Continue returning
            f2t_debug_log("[map-explore] Not at start yet, continuing navigation")
            f2t_map_explore_next_step()
        end
    end
end

f2t_debug_log("[map] Loaded map_explore.lua")
