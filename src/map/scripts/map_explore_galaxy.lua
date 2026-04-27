-- ================================================================================
-- LAYER 4: GALAXY ORCHESTRATION (MULTI-CARTEL)
-- ================================================================================
-- Iterates through all cartels in the galaxy.
-- Captures cartel list from "display cartels" command, then triggers cartel exploration
-- for each cartel.
-- Entry point: f2t_map_explore_galaxy_start()
-- Delegates to Layer 3 (map_explore_cartel.lua) for each cartel.
-- ================================================================================

-- ========================================
-- Galaxy Capture State
-- ========================================

F2T_MAP_EXPLORE_GALAXY_CAPTURE = F2T_MAP_EXPLORE_GALAXY_CAPTURE or {
    active = false,
    lines = {},  -- Cartel names captured
    timer_id = nil
}

-- ========================================
-- Galaxy Exploration Entry Point
-- ========================================

function f2t_map_explore_galaxy_start()
    -- Check if exploration already active
    if F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n")
        cecho("\n<dim_grey>Use 'map explore stop' to stop current exploration<reset>\n")
        return false
    end

    f2t_debug_log("[map-explore-galaxy] Starting galaxy exploration")

    cecho("\n<green>[map-explore]<reset> Starting galaxy exploration\n")
    cecho("  <dim_grey>Capturing cartel list...<reset>\n")

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

    -- Initialize exploration state for galaxy mode
    F2T_MAP_EXPLORE_STATE.active = true
    F2T_MAP_EXPLORE_STATE.mode = "galaxy"
    F2T_MAP_EXPLORE_STATE.starting_room_id = F2T_MAP_CURRENT_ROOM_ID

    F2T_MAP_EXPLORE_STATE.galaxy_cartel_list = {}
    F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index = 0
    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil

    F2T_MAP_EXPLORE_STATE.galaxy_stats = {
        total_cartels = 0,
        cartels_explored = 0,
        cartels_skipped = 0,
        total_systems = 0,
        total_planets = 0
    }

    -- Start galaxy capture
    f2t_map_explore_galaxy_capture_start()

    return true
end

-- ========================================
-- Begin Capturing Display Cartels Output
-- ========================================

function f2t_map_explore_galaxy_capture_start()
    F2T_MAP_EXPLORE_GALAXY_CAPTURE = {
        active = true,
        lines = {},
        timer_id = nil
    }

    f2t_debug_log("[map-explore-galaxy] Starting capture for display cartels")

    -- Send display cartels command
    send("display cartels")
end

-- ========================================
-- Reset Capture Timer
-- ========================================

function f2t_map_explore_galaxy_reset_timer()
    -- Kill existing timer
    if F2T_MAP_EXPLORE_GALAXY_CAPTURE.timer_id then
        killTimer(F2T_MAP_EXPLORE_GALAXY_CAPTURE.timer_id)
    end

    -- Start timer to process capture after 0.5s of silence
    F2T_MAP_EXPLORE_GALAXY_CAPTURE.timer_id = tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_GALAXY_CAPTURE.active then
            f2t_debug_log("[map-explore-galaxy] Timer expired, processing capture")
            f2t_map_explore_galaxy_capture_complete()
        end
    end)
end

-- ========================================
-- Process Captured Output
-- ========================================

function f2t_map_explore_galaxy_capture_complete()
    local cartel_names = F2T_MAP_EXPLORE_GALAXY_CAPTURE.lines

    f2t_debug_log("[map-explore-galaxy] Processing %d captured cartel names", #cartel_names)

    -- Cleanup capture state
    F2T_MAP_EXPLORE_GALAXY_CAPTURE = {active = false}

    if #cartel_names == 0 then
        cecho("\n<red>[map-explore]<reset> No cartels found\n")
        cecho("\n<dim_grey>The capture may have failed or there are no cartels<reset>\n")

        -- Abort galaxy exploration (clean up state)
        f2t_map_explore_galaxy_abort()
        return
    end

    -- Sort alphabetically (they may already be sorted, but ensure consistency)
    table.sort(cartel_names)

    -- Store all cartels
    F2T_MAP_EXPLORE_STATE.galaxy_cartel_list = cartel_names
    F2T_MAP_EXPLORE_STATE.galaxy_stats.total_cartels = #cartel_names

    cecho(string.format("  <green>Found %d cartel(s) to explore<reset>\n\n", #cartel_names))

    f2t_debug_log("[map-explore-galaxy] Starting iteration over %d cartels", #cartel_names)

    -- Start with first cartel
    f2t_map_explore_galaxy_next_cartel()
end

-- ========================================
-- Move to Next Cartel in Galaxy
-- ========================================

function f2t_map_explore_galaxy_next_cartel()
    -- Guard: Check if galaxy exploration active
    if not F2T_MAP_EXPLORE_STATE.active then
        return
    end

    if F2T_MAP_EXPLORE_STATE.mode ~= "galaxy" then
        return
    end

    -- Deferred pause: pause between cartels
    if f2t_map_explore_check_deferred_pause() then
        return
    end

    -- Increment cartel index
    F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index = F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index + 1
    local index = F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index
    local cartels = F2T_MAP_EXPLORE_STATE.galaxy_cartel_list

    -- Check if all cartels complete
    if index > #cartels then
        f2t_debug_log("[map-explore-galaxy] All cartels explored in galaxy")

        -- Return to start
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
        return
    end

    local cartel_name = cartels[index]

    cecho(string.format("\n<green>[map-explore]<reset> Cartel %d/%d: <white>%s<reset>\n",
        index, #cartels, cartel_name))

    -- Check if cartel is already fully explored (optimization - skip if done)
    if f2t_map_explore_is_cartel_fully_explored(cartel_name) then
        cecho(string.format("  <green>Cartel already fully explored, skipping<reset>\n"))
        f2t_debug_log("[map-explore-galaxy] Cartel %s already fully explored, skipping", cartel_name)

        -- Update stats (skipped cartels are NOT counted as explored - mutually exclusive)
        F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_skipped = F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_skipped + 1

        -- Move to next cartel
        f2t_map_explore_galaxy_next_cartel()
        return
    end

    -- Cartel needs exploration - navigate to it and invoke cartel mode
    f2t_debug_log("[map-explore-galaxy] Cartel %s needs exploration, navigating...", cartel_name)

    -- Check if we're already in this cartel (by checking current system's cartel)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room then
        local current_cartel = f2t_map_get_current_cartel()
        if current_cartel and current_cartel:lower() == cartel_name:lower() then
            -- Already in the cartel, start cartel exploration directly
            f2t_debug_log("[map-explore-galaxy] Already in %s, starting cartel exploration", cartel_name)
            cecho(string.format("  <dim_grey>Already in cartel, starting exploration<reset>\n"))

            -- Update stats
            F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored = F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored + 1

            -- Invoke cartel mode with callback
            f2t_map_explore_galaxy_start_cartel_mode(cartel_name)
            return
        end
    end

    -- Not in cartel - need to jump there from CURRENT cartel's main system
    -- Inter-cartel jumps require being at the main system's link (cartel name = main system)
    local current_cartel = f2t_map_get_current_cartel()
    if not current_cartel then
        cecho(string.format("  <red>Error:<reset> Cannot determine current cartel, skipping\n"))
        f2t_debug_log("[map-explore-galaxy] Cannot determine current cartel for jump to %s", cartel_name)
        f2t_map_explore_galaxy_next_cartel()
        return
    end

    -- Store which cartel we're jumping to
    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = cartel_name

    -- Check if we're already at the main system's link BEFORE starting navigation
    -- (must check first to avoid race condition with navigation)
    local current_system = getRoomUserData(current_room, "fed2_system")
    local at_main_link = current_room
        and f2t_map_room_has_flag(current_room, "link")
        and current_system
        and current_system:lower() == current_cartel:lower()

    if at_main_link then
        -- Already at main system's link, jump immediately
        f2t_debug_log("[map-explore-galaxy] Already at %s link, jumping to %s", current_cartel, cartel_name)
        cecho(string.format("  <dim_grey>Already at link, jumping to %s<reset>\n", cartel_name))

        -- Use speedwalk pattern for jump command (protections: timeout, retry, etc.)
        speedWalkDir = {string.format("jump %s", cartel_name)}
        speedWalkPath = {nil}  -- Blind movement, destination unknown
        doSpeedWalk()

        -- Update phase to wait for arrival in new cartel
        F2T_MAP_EXPLORE_STATE.phase = "arriving_in_cartel"
        return
    end

    -- Not at link yet, navigate there
    cecho(string.format("  <dim_grey>Navigating to %s link (main system) to jump to %s<reset>\n",
        current_cartel, cartel_name))

    -- Navigate to main system's space link using explicit "area flag" format
    -- (NOT just "link" which finds current area's link, and NOT cartel name which might resolve to planet)
    local success = f2t_map_navigate(current_cartel .. " Space link")
    if not success then
        cecho(string.format("  <red>Error:<reset> Cannot navigate to %s link, skipping cartel\n", current_cartel))
        f2t_debug_log("[map-explore-galaxy] Failed to navigate to %s link for jump to %s", current_cartel, cartel_name)

        -- Skip this cartel and move to next
        f2t_map_explore_galaxy_next_cartel()
        return
    end

    -- Navigation in progress, set phase to jump when we arrive
    F2T_MAP_EXPLORE_STATE.phase = "jumping_to_cartel"
end

-- ========================================
-- Check if Cartel is Fully Explored
-- ========================================

function f2t_map_explore_is_cartel_fully_explored(cartel_name)
    -- A cartel is fully explored if ALL its systems pass f2t_map_explore_is_system_fully_mapped()
    -- Since we don't have the system list cached, we check the primary system first
    -- (primary system name = cartel name)
    --
    -- For full check, we'd need to capture "display cartel <name>" which is expensive.
    -- Instead, we do a quick check: if primary system isn't even mapped, definitely not explored.
    -- If primary system IS mapped, we let the cartel layer do the full check.

    f2t_debug_log("[map-explore-galaxy] Checking if cartel '%s' is fully explored", cartel_name)

    -- Quick check: is the primary system mapped?
    local primary_system = cartel_name  -- Primary system = cartel name
    if not f2t_map_explore_is_system_fully_mapped(primary_system) then
        f2t_debug_log("[map-explore-galaxy] Primary system '%s' not fully mapped, cartel needs exploration", primary_system)
        return false
    end

    -- Primary system is mapped. For now, we'll let cartel layer check other systems.
    -- This is an optimization tradeoff: we could capture "display cartel" to get full list,
    -- but that adds latency. Instead, we delegate to cartel layer which will skip any
    -- already-mapped systems anyway.
    --
    -- NOTE: This means we might jump to a cartel that ends up being fully explored
    -- (if primary is mapped but we didn't check all systems). The cartel layer will
    -- complete quickly in that case.

    f2t_debug_log("[map-explore-galaxy] Primary system '%s' is mapped, but other systems may need exploration", primary_system)
    return false  -- Conservative: explore the cartel, let cartel layer handle skipping
end

-- ========================================
-- Start Cartel Mode for Current Cartel
-- ========================================

function f2t_map_explore_galaxy_start_cartel_mode(cartel_name)
    -- Invokes cartel mode (Layer 3) which will:
    -- 1. Capture system list
    -- 2. Explore each system (brief mode)
    -- 3. Call back to galaxy mode when complete

    f2t_debug_log("[map-explore-galaxy] Starting cartel mode for: %s", cartel_name)

    -- Cartel mode expects to be in the cartel already
    -- Pass callback so cartel mode calls back to us when complete
    local success = f2t_map_explore_cartel_start(cartel_name, function()
        -- Callback when cartel exploration completes
        f2t_map_explore_galaxy_cartel_complete()
    end)

    if not success then
        -- Cartel mode couldn't start
        cecho(string.format("  <red>Error:<reset> Cartel exploration failed to start for %s\n", cartel_name))
        f2t_debug_log("[map-explore-galaxy] Cartel mode failed to start for %s", cartel_name)

        -- Move to next cartel
        f2t_map_explore_galaxy_next_cartel()
    end
end

-- ========================================
-- Handle Cartel Exploration Complete
-- ========================================

function f2t_map_explore_galaxy_cartel_complete()
    -- Called by cartel layer when it finishes exploring a cartel

    f2t_debug_log("[map-explore-galaxy] Cartel exploration complete, aggregating stats")

    -- Aggregate cartel stats to galaxy stats
    local cartel_stats = F2T_MAP_EXPLORE_STATE.cartel_stats
    if cartel_stats then
        F2T_MAP_EXPLORE_STATE.galaxy_stats.total_systems =
            F2T_MAP_EXPLORE_STATE.galaxy_stats.total_systems + cartel_stats.total_systems
        F2T_MAP_EXPLORE_STATE.galaxy_stats.total_planets =
            F2T_MAP_EXPLORE_STATE.galaxy_stats.total_planets + cartel_stats.total_planets
    end

    -- Move to next cartel
    f2t_map_explore_galaxy_next_cartel()
end

-- ========================================
-- Abort Galaxy Exploration (Error Cleanup)
-- ========================================

function f2t_map_explore_galaxy_abort()
    -- Clean up state when galaxy exploration can't proceed
    -- (called during initialization errors, before actual exploration starts)

    f2t_debug_log("[map-explore-galaxy] Aborting galaxy exploration")

    -- Clean up navigation ownership and stamina registration
    f2t_map_clear_nav_owner()
    f2t_stamina_unregister_client()

    -- Reset all galaxy-related state
    F2T_MAP_EXPLORE_STATE.active = false
    F2T_MAP_EXPLORE_STATE.mode = nil
    F2T_MAP_EXPLORE_STATE.galaxy_cartel_list = {}
    F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index = 0
    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
    F2T_MAP_EXPLORE_STATE.galaxy_stats = {
        total_cartels = 0,
        cartels_explored = 0,
        cartels_skipped = 0,
        total_systems = 0,
        total_planets = 0
    }
end

f2t_debug_log("[map] Loaded map_explore_galaxy.lua")
