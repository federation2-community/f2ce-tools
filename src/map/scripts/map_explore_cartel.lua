-- ================================================================================
-- LAYER 3: CARTEL ORCHESTRATION (MULTI-SYSTEM)
-- ================================================================================
-- Iterates through systems in a cartel.
-- Captures system list from "display cartel" command, then triggers system exploration
-- for each system.
-- Entry point: f2t_map_explore_cartel_start()
-- Delegates to Layer 2 (map_explore_system.lua) for each system.
-- ================================================================================

-- ========================================
-- Cartel Capture State
-- ========================================

F2T_MAP_EXPLORE_CARTEL_CAPTURE = F2T_MAP_EXPLORE_CARTEL_CAPTURE or {
    active = false,
    cartel_name = nil,
    lines = {},  -- System names captured from Members section
    in_members = false,  -- Whether we're currently in the Members section
    timer_id = nil
}

-- ========================================
-- Cartel Exploration Entry Point
-- ========================================

function f2t_map_explore_cartel_start(cartel_name, on_complete_callback)
    -- LAYER 3: Cartel exploration (all systems in cartel, brief mode)
    -- Can run in nested mode (galaxy → cartel) or standalone mode
    --
    -- Parameters:
    --   cartel_name: Name of cartel to explore
    --   on_complete_callback: Optional callback for nested mode (Layer 4: galaxy)
    --                         If nil, runs in standalone mode with return to start

    -- Standalone mode: Check if exploration already active
    if not on_complete_callback and F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n")
        cecho("\n<dim_grey>Use 'map explore stop' to stop current exploration<reset>\n")
        return false
    end

    -- Validate cartel name provided
    if not cartel_name or cartel_name == "" then
        cecho("\n<red>[map-explore]<reset> Error: No cartel specified\n")
        cecho("\n<dim_grey>Usage: map explore cartel <cartel><reset>\n")
        return false
    end

    -- Capitalize first letter for consistency
    cartel_name = cartel_name:gsub("^%l", string.upper)

    f2t_debug_log("[map-explore-cartel] Starting cartel exploration for: %s (nested: %s)",
        cartel_name, on_complete_callback and "yes" or "no")

    cecho(string.format("\n<green>[map-explore]<reset> Starting cartel exploration: <white>%s<reset>\n", cartel_name))
    cecho("  <dim_grey>Capturing system list...<reset>\n")

    -- Nested mode vs standalone mode initialization
    if on_complete_callback then
        -- NESTED MODE: Preserve parent state (galaxy), only add cartel fields
        f2t_debug_log("[map-explore-cartel] Nested mode - preserving parent state")

        -- DON'T overwrite mode in nested mode - parent (galaxy) needs it
        F2T_MAP_EXPLORE_STATE.cartel_name = cartel_name
        F2T_MAP_EXPLORE_STATE.system_list = {}
        F2T_MAP_EXPLORE_STATE.current_system_index = 0

        F2T_MAP_EXPLORE_STATE.cartel_stats = {
            total_systems = 0,
            systems_explored = 0,
            total_planets = 0,
            total_exchanges = 0,
            total_planets_skipped = 0
        }

        -- Store parent callback
        F2T_MAP_EXPLORE_STATE.cartel_complete_callback = on_complete_callback
    else
        -- STANDALONE MODE: Full initialization with mode = "cartel"
        f2t_debug_log("[map-explore-cartel] Standalone mode - full initialization")

        -- Set navigation ownership for map-explore
        f2t_map_set_nav_owner("map-explore", function(reason)
            f2t_debug_log("[map-explore] Navigation interrupted by %s", reason)
            if reason == "customs" then
                F2T_MAP_EXPLORE_STATE.paused = true
                F2T_MAP_EXPLORE_STATE.paused_reason = reason
            end
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

        F2T_MAP_EXPLORE_STATE.active = true
        F2T_MAP_EXPLORE_STATE.mode = "cartel"
        F2T_MAP_EXPLORE_STATE.cartel_name = cartel_name
        F2T_MAP_EXPLORE_STATE.system_list = {}
        F2T_MAP_EXPLORE_STATE.current_system_index = 0
        F2T_MAP_EXPLORE_STATE.starting_room_id = F2T_MAP_CURRENT_ROOM_ID

        F2T_MAP_EXPLORE_STATE.cartel_stats = {
            total_systems = 0,
            systems_explored = 0,
            total_planets = 0,
            total_exchanges = 0,
            total_planets_skipped = 0
        }

        -- Clear any leftover callback
        F2T_MAP_EXPLORE_STATE.cartel_complete_callback = nil
    end

    -- Start cartel capture
    f2t_map_explore_cartel_capture_start(cartel_name)

    return true
end

-- ========================================
-- Begin Capturing Display Cartel Output
-- ========================================

function f2t_map_explore_cartel_capture_start(cartel_name)
    F2T_MAP_EXPLORE_CARTEL_CAPTURE = {
        active = true,
        cartel_name = cartel_name,
        lines = {},
        in_members = false,
        timer_id = nil
    }

    f2t_debug_log("[map-explore-cartel] Starting capture for: %s", cartel_name)

    -- Send display cartel command
    send(string.format("display cartel %s", cartel_name))
end

-- ========================================
-- Reset Capture Timer
-- ========================================

function f2t_map_explore_cartel_reset_timer()
    -- Kill existing timer
    if F2T_MAP_EXPLORE_CARTEL_CAPTURE.timer_id then
        killTimer(F2T_MAP_EXPLORE_CARTEL_CAPTURE.timer_id)
    end

    -- Start timer to process capture after 0.5s of silence
    F2T_MAP_EXPLORE_CARTEL_CAPTURE.timer_id = tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
            f2t_debug_log("[map-explore-cartel] Timer expired, processing capture")
            f2t_map_explore_cartel_capture_complete()
        end
    end)
end

-- ========================================
-- Process Captured Output
-- ========================================

function f2t_map_explore_cartel_capture_complete()
    local system_names = F2T_MAP_EXPLORE_CARTEL_CAPTURE.lines
    local cartel_name = F2T_MAP_EXPLORE_CARTEL_CAPTURE.cartel_name

    f2t_debug_log("[map-explore-cartel] Processing %d captured system names", #system_names)

    -- Cleanup capture state
    F2T_MAP_EXPLORE_CARTEL_CAPTURE = {active = false}

    -- Parse/validate system names
    local systems = f2t_map_explore_parse_cartel_systems(system_names)

    if #systems == 0 then
        cecho(string.format("\n<red>[map-explore]<reset> No systems found for cartel '%s'\n", cartel_name))
        cecho("\n<dim_grey>The cartel may not exist or has no systems<reset>\n")

        -- Abort cartel exploration (clean up state)
        f2t_map_explore_cartel_abort()
        return
    end

    -- Store all systems - we'll explore/map each one (skip fully mapped ones in iteration)
    F2T_MAP_EXPLORE_STATE.system_list = systems
    F2T_MAP_EXPLORE_STATE.cartel_stats.total_systems = #systems

    cecho(string.format("  <green>Found %d system(s) to explore<reset>\n\n", #systems))

    f2t_debug_log("[map-explore-cartel] Starting iteration over %d systems", #systems)

    -- Start with first system
    f2t_map_explore_cartel_next_system()
end

-- ========================================
-- Parse System Names from Cartel Output
-- ========================================

function f2t_map_explore_parse_cartel_systems(system_names)
    -- System names are already extracted by triggers (just the names)
    -- This function just validates and returns them

    f2t_debug_log("[map-explore-cartel] Received %d system names from capture", #system_names)

    local cartel_name = F2T_MAP_EXPLORE_STATE.cartel_name

    -- Sort with cartel's main system first, then alphabetically
    table.sort(system_names, function(a, b)
        -- Main system (matching cartel name) always goes first
        if a == cartel_name then return true end
        if b == cartel_name then return false end
        -- Otherwise sort alphabetically
        return a < b
    end)

    f2t_debug_log("[map-explore-cartel] Sorted systems (main system '%s' first)", cartel_name)

    return system_names
end

-- ========================================
-- Move to Next System in Cartel
-- ========================================

function f2t_map_explore_cartel_next_system()
    -- Guard: Check if cartel exploration active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    -- Accept both "cartel" (standalone) and "galaxy" (nested) modes
    if F2T_MAP_EXPLORE_STATE.mode ~= "cartel" and F2T_MAP_EXPLORE_STATE.mode ~= "galaxy" then
        return
    end

    -- Deferred pause: pause between systems
    if f2t_map_explore_check_deferred_pause() then
        return
    end

    -- Increment system index
    F2T_MAP_EXPLORE_STATE.current_system_index = F2T_MAP_EXPLORE_STATE.current_system_index + 1
    local index = F2T_MAP_EXPLORE_STATE.current_system_index
    local systems = F2T_MAP_EXPLORE_STATE.system_list

    -- Check if all systems complete
    if index > #systems then
        f2t_debug_log("[map-explore-cartel] All systems explored in cartel")

        -- Check for callback (nested mode) vs standalone
        if F2T_MAP_EXPLORE_STATE.cartel_complete_callback then
            -- Nested mode - call parent callback (galaxy)
            f2t_debug_log("[map-explore-cartel] Nested mode - calling parent callback")
            local callback = F2T_MAP_EXPLORE_STATE.cartel_complete_callback
            F2T_MAP_EXPLORE_STATE.cartel_complete_callback = nil
            callback()
            return
        end

        -- Standalone mode - clear callback and return to start
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
        return
    end

    local system_name = systems[index]

    cecho(string.format("\n<green>[map-explore]<reset> System %d/%d: <white>%s<reset>\n",
        index, #systems, system_name))

    -- Check if system is already fully mapped (optimization - skip if done)
    if f2t_map_explore_is_system_fully_mapped(system_name) then
        cecho(string.format("  <green>System already fully mapped, skipping<reset>\n"))
        f2t_debug_log("[map-explore-cartel] System %s already fully mapped, skipping", system_name)

        -- Move to next system
        F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored = F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1
        f2t_map_explore_cartel_next_system()
        return
    end

    -- System needs exploration - navigate to it and invoke system mode
    f2t_debug_log("[map-explore-cartel] System %s needs mapping, navigating...", system_name)

    -- Check if we're already in this system's space
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room then
        local current_system = getRoomUserData(current_room, "fed2_system")
        if current_system == system_name then
            -- Already in the system, start system exploration directly
            f2t_debug_log("[map-explore-cartel] Already in %s, starting system exploration", system_name)
            cecho(string.format("  <dim_grey>Already in system, starting exploration<reset>\n"))

            -- Update cartel stats
            F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored = F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1

            -- Invoke system mode (which will callback to cartel mode when done)
            f2t_map_explore_cartel_start_system_mode(system_name)
            return
        end
    end

    -- Not in system - need to jump there (blind movement)
    cecho(string.format("  <dim_grey>Navigating to link and jumping to %s<reset>\n", system_name))

    -- Navigate to link room
    local success = f2t_map_navigate("link")
    if not success then
        cecho(string.format("  <red>Error:<reset> Cannot navigate to link, skipping system\n"))
        f2t_debug_log("[map-explore-cartel] Failed to navigate to link for %s", system_name)

        -- Skip this system and move to next
        f2t_map_explore_cartel_next_system()
        return
    end

    -- Store which system we're jumping to
    F2T_MAP_EXPLORE_STATE.cartel_target_system = system_name

    -- Check if we're already at the link (navigation returned success but no room change)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room and f2t_map_room_has_flag(current_room, "link") then
        -- Already at link, jump immediately (don't wait for room change)
        f2t_debug_log("[map-explore-cartel] Already at link, jumping to %s", system_name)

        -- Use speedwalk pattern for jump command (protections: timeout, retry, etc.)
        speedWalkDir = {string.format("jump %s", system_name)}
        speedWalkPath = {nil}  -- Blind movement, destination unknown
        doSpeedWalk()

        -- Update phase to wait for arrival in new system
        F2T_MAP_EXPLORE_STATE.phase = "arriving_in_system"
    else
        -- Not at link yet, navigation in progress
        -- Set phase to jump when we arrive
        F2T_MAP_EXPLORE_STATE.phase = "jumping_to_system"
    end
end

-- ========================================
-- Start System Mode for Current System
-- ========================================

function f2t_map_explore_cartel_start_system_mode(system_name)
    -- Invokes system mode (Layer 2) which will:
    -- 1. Explore space area
    -- 2. Discover planets
    -- 3. Explore each planet in brief mode
    -- 4. Call back to cartel mode when complete

    f2t_debug_log("[map-explore-cartel] Starting system mode for: %s (brief mode)", system_name)

    -- System mode will call f2t_map_explore_system_start() internally
    -- It expects to be in the system's space area already
    -- Pass callback so system mode calls back to us when complete
    -- Force brief mode for cartel exploration (requirement)

    local success = f2t_map_explore_system_start(system_name, "brief", function()
        -- Callback when system exploration completes
        f2t_map_explore_cartel_next_system()
    end)

    if not success then
        -- System mode couldn't start (no space area, etc.)
        cecho(string.format("  <red>Error:<reset> System exploration failed to start for %s\n", system_name))
        f2t_debug_log("[map-explore-cartel] System mode failed to start for %s", system_name)

        -- Move to next system
        f2t_map_explore_cartel_next_system()
    end
end

-- ========================================
-- Abort Cartel Exploration (Error Cleanup)
-- ========================================

function f2t_map_explore_cartel_abort()
    -- Clean up state when cartel exploration can't proceed
    -- (called during initialization errors, before actual exploration starts)

    f2t_debug_log("[map-explore-cartel] Aborting cartel exploration")

    -- Check for nested mode - call parent callback instead of full reset
    if F2T_MAP_EXPLORE_STATE.cartel_complete_callback then
        f2t_debug_log("[map-explore-cartel] Nested mode - calling parent callback to continue")
        local callback = F2T_MAP_EXPLORE_STATE.cartel_complete_callback
        F2T_MAP_EXPLORE_STATE.cartel_complete_callback = nil

        -- Clear cartel-specific state but preserve parent state
        F2T_MAP_EXPLORE_STATE.cartel_name = nil
        F2T_MAP_EXPLORE_STATE.system_list = {}
        F2T_MAP_EXPLORE_STATE.current_system_index = 0
        F2T_MAP_EXPLORE_STATE.cartel_stats = {
            total_systems = 0,
            systems_explored = 0,
            total_planets = 0,
            total_exchanges = 0,
            total_planets_skipped = 0
        }

        -- Let parent (galaxy) continue to next cartel
        callback()
        return
    end

    -- Standalone mode - full reset
    f2t_map_clear_nav_owner()
    f2t_stamina_unregister_client()
    F2T_MAP_EXPLORE_STATE.active = false
    F2T_MAP_EXPLORE_STATE.mode = nil
    F2T_MAP_EXPLORE_STATE.cartel_name = nil
    F2T_MAP_EXPLORE_STATE.system_list = {}
    F2T_MAP_EXPLORE_STATE.current_system_index = 0
    F2T_MAP_EXPLORE_STATE.cartel_stats = {
        total_systems = 0,
        systems_explored = 0,
        total_planets = 0,
        total_exchanges = 0,
        total_planets_skipped = 0
    }
end

f2t_debug_log("[map] Loaded map_explore_cartel.lua")
