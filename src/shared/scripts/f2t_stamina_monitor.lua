-- Stamina monitoring system for fed2-tools
-- Monitors character stamina and automatically navigates to food source when low
-- Designed to integrate with components that need stamina management (e.g., hauling)

-- ========================================
-- State Management
-- ========================================

F2T_STAMINA_STATE = F2T_STAMINA_STATE or {
    monitoring_active = false,      -- Is stamina monitoring running?
    current_phase = "idle",          -- Current phase: idle, waiting_for_client_pause, navigating_to_food, buying_food, navigating_back

    -- Client registration (component that called us)
    client_pause_callback = nil,     -- Function to pause client activity
    client_resume_callback = nil,    -- Function to resume client activity
    client_check_active = nil,       -- Function to check if client is active

    -- State before food trip
    return_location = nil,           -- Room hash to return to after eating
    client_was_paused = false,       -- Did we pause the client?
    wait_poll_count = 0,             -- Polls elapsed while waiting for client pause

    -- Current stamina tracking
    current_stamina = 0,
    max_stamina = 1,

    -- GMCP event handler IDs
    gmcp_handler_id = nil,               -- Stamina vitals handler
    nav_handler_id = nil,                -- Navigation completion handler

    -- Standalone mode (yes/no prompt)
    standalone_prompt_active = false,    -- Is prompt showing?
    standalone_prompt_aliases = {},      -- Alias IDs for cleanup
    standalone_prompt_timer = nil,       -- Timeout timer ID
    standalone_dismissed_at = nil        -- Timestamp when user said "no"
}

-- Cooldown before re-prompting after user says "no" (5 minutes)
F2T_STAMINA_DISMISS_COOLDOWN = 300

-- Prompt timeout (30 seconds)
F2T_STAMINA_PROMPT_TIMEOUT = 30

-- ========================================
-- Client Registration
-- ========================================

-- Register a client component with stamina monitor
-- config: {pause_callback, resume_callback, check_active}
--   pause_callback: function() - called to pause client activity
--   resume_callback: function() - called to resume client activity
--   check_active: function() -> boolean - returns true if client is active
function f2t_stamina_register_client(config)
    if not config or not config.pause_callback or not config.resume_callback or not config.check_active then
        cecho("\n<red>[stamina]<reset> Invalid client registration: missing required callbacks\n")
        return false
    end

    F2T_STAMINA_STATE.client_pause_callback = config.pause_callback
    F2T_STAMINA_STATE.client_resume_callback = config.resume_callback
    F2T_STAMINA_STATE.client_check_active = config.check_active

    f2t_debug_log("[stamina] Client registered")
    return true
end

-- Unregister client
function f2t_stamina_unregister_client()
    F2T_STAMINA_STATE.client_pause_callback = nil
    F2T_STAMINA_STATE.client_resume_callback = nil
    F2T_STAMINA_STATE.client_check_active = nil
    f2t_debug_log("[stamina] Client unregistered")
end

-- ========================================
-- Monitoring Control
-- ========================================

-- Start stamina monitoring
function f2t_stamina_start_monitoring()
    if F2T_STAMINA_STATE.monitoring_active then
        f2t_debug_log("[stamina] Already monitoring")
        return
    end

    F2T_STAMINA_STATE.monitoring_active = true
    F2T_STAMINA_STATE.current_phase = "idle"

    -- Register GMCP handler for stamina updates
    f2t_stamina_register_gmcp_handler()

    f2t_debug_log("[stamina] Monitoring started")
end

-- Stop stamina monitoring
function f2t_stamina_stop_monitoring()
    if not F2T_STAMINA_STATE.monitoring_active then
        return
    end

    F2T_STAMINA_STATE.monitoring_active = false
    F2T_STAMINA_STATE.current_phase = "idle"

    -- Unregister GMCP handler
    if F2T_STAMINA_STATE.gmcp_handler_id then
        killAnonymousEventHandler(F2T_STAMINA_STATE.gmcp_handler_id)
        F2T_STAMINA_STATE.gmcp_handler_id = nil
    end

    f2t_debug_log("[stamina] Monitoring stopped")
end

-- ========================================
-- GMCP Event Handlers
-- ========================================

-- Register GMCP event handler for stamina monitoring
function f2t_stamina_register_gmcp_handler()
    -- Kill existing handler if any (prevents duplicates on package reload)
    if F2T_STAMINA_STATE.gmcp_handler_id then
        killAnonymousEventHandler(F2T_STAMINA_STATE.gmcp_handler_id)
        F2T_STAMINA_STATE.gmcp_handler_id = nil
    end

    F2T_STAMINA_STATE.gmcp_handler_id = registerAnonymousEventHandler("gmcp.char.vitals", function()
        tempTimer(0.1, function()
            f2t_stamina_check_vitals()
        end)
    end)

    f2t_debug_log("[stamina] GMCP handler registered")
end

-- Check stamina levels from GMCP
function f2t_stamina_check_vitals()
    if not F2T_STAMINA_STATE.monitoring_active then
        return
    end

    -- Get stamina from GMCP
    local vitals = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.stamina
    if not vitals or not vitals.cur or not vitals.max then
        return
    end

    F2T_STAMINA_STATE.current_stamina = tonumber(vitals.cur) or 0
    F2T_STAMINA_STATE.max_stamina = tonumber(vitals.max) or 1

    local percent = math.floor((F2T_STAMINA_STATE.current_stamina / F2T_STAMINA_STATE.max_stamina) * 100)

    f2t_debug_log("[stamina] Current: %d/%d (%d%%)",
        F2T_STAMINA_STATE.current_stamina,
        F2T_STAMINA_STATE.max_stamina,
        percent)

    -- Check if we need to trigger food buying (only when idle)
    if F2T_STAMINA_STATE.current_phase == "idle" then
        f2t_stamina_check_low_stamina(percent)
    end
end

-- Check if stamina is low and trigger food buying
function f2t_stamina_check_low_stamina(percent)
    -- Check if stamina monitoring is enabled (threshold > 0)
    local threshold = f2t_settings_get("shared", "stamina_threshold") or 0
    if threshold <= 0 then
        f2t_debug_log("[stamina] Low stamina check skipped: monitoring disabled (threshold=0)")
        return
    end

    -- Skip if stamina is 0 (dead - can't refill)
    if percent == 0 then
        f2t_debug_log("[stamina] Low stamina check skipped: stamina is 0 (dead)")
        return
    end

    -- Check threshold
    local threshold = f2t_settings_get("shared", "stamina_threshold")
    if percent > threshold then
        return
    end

    f2t_debug_log("[stamina] Low stamina triggered: %d%% <= threshold %d%%", percent, threshold)

    -- Check if client is active (component mode)
    local has_client = F2T_STAMINA_STATE.client_check_active ~= nil
    local client_active = has_client and F2T_STAMINA_STATE.client_check_active()

    f2t_debug_log("[stamina] Mode check: has_client=%s, client_active=%s",
        tostring(has_client), tostring(client_active))

    if client_active then
        -- Cancel any standalone prompt if active
        f2t_stamina_cancel_standalone_prompt()

        -- Component mode: auto-pause, navigate, buy food, resume
        f2t_debug_log("[stamina] Using COMPONENT mode")
        cecho(string.format("\n<yellow>[stamina]<reset> Low stamina detected: %d%% (threshold: %d%%)\n", percent, threshold))
        f2t_stamina_start_food_trip()
        return
    end

    -- Standalone mode: show y/n prompt
    f2t_debug_log("[stamina] Using STANDALONE mode")
    f2t_stamina_show_standalone_prompt(percent, threshold)
end

-- ========================================
-- Food Trip State Machine
-- ========================================

-- Save current location for return trip
local function f2t_stamina_save_return_location()
    if gmcp.room and gmcp.room.info and gmcp.room.info.num then
        local system = gmcp.room.info.system or ""
        local area = gmcp.room.info.area or ""
        local num = gmcp.room.info.num or ""
        F2T_STAMINA_STATE.return_location = string.format("%s.%s.%s", system, area, num)
        f2t_debug_log("[stamina] Saved return location: %s", F2T_STAMINA_STATE.return_location)
    end
end

-- Start food buying trip
function f2t_stamina_start_food_trip()
    if F2T_STAMINA_STATE.current_phase ~= "idle" then
        f2t_debug_log("[stamina] Already on food trip, ignoring")
        return
    end

    -- Pause client activity (only if client is actually active)
    local client_active = F2T_STAMINA_STATE.client_check_active and F2T_STAMINA_STATE.client_check_active()
    if client_active and F2T_STAMINA_STATE.client_pause_callback then
        f2t_debug_log("[stamina] Pausing client activity (client is active)")
        F2T_STAMINA_STATE.client_pause_callback()
        F2T_STAMINA_STATE.client_was_paused = true
        F2T_STAMINA_STATE.wait_poll_count = 0
        -- Wait for client to actually pause before taking over navigation
        -- Client may use deferred pause (completes current operation first)
        -- return_location is saved AFTER client pauses (player may be mid-transit now)
        f2t_stamina_transition("waiting_for_client_pause")
        return
    else
        f2t_debug_log("[stamina] Standalone mode - no client to pause")
        F2T_STAMINA_STATE.client_was_paused = false
    end

    -- Standalone mode: save location now and go
    f2t_stamina_save_return_location()
    f2t_stamina_take_nav_and_go()
end

-- Take navigation ownership and start navigating to food
function f2t_stamina_take_nav_and_go()
    -- Clear any existing ownership first (important if another component is paused)
    if f2t_map_clear_nav_owner then
        f2t_map_clear_nav_owner()
    end

    -- Set navigation ownership for stamina
    -- Callback handles customs interrupt by requesting auto-resume
    if f2t_map_set_nav_owner then
        f2t_map_set_nav_owner("stamina", function(reason)
            f2t_debug_log("[stamina] Navigation interrupted by %s", reason)
            -- Stamina food trips are simple - just auto-resume after interrupt
            return { auto_resume = true }
        end)
    end

    -- Navigate to food source
    f2t_stamina_transition("navigating_to_food")
end

-- Phase: Wait for client to actually pause before taking over navigation
-- Client may use deferred pause (finishes current operation before pausing)
function f2t_stamina_phase_wait_for_client_pause()
    -- Client was unregistered (e.g., death terminated hauling) — abort food trip
    if not F2T_STAMINA_STATE.client_check_active then
        f2t_debug_log("[stamina] Client unregistered while waiting, aborting food trip")
        cecho("\n<yellow>[stamina]<reset> Activity stopped, cancelling food trip\n")
        F2T_STAMINA_STATE.current_phase = "idle"
        F2T_STAMINA_STATE.client_was_paused = false
        F2T_STAMINA_STATE.return_location = nil
        return
    end

    -- Check if client has stopped running
    local still_active = F2T_STAMINA_STATE.client_check_active()
    if not still_active then
        f2t_debug_log("[stamina] Client paused, proceeding to food trip")
        -- Save location NOW (player is at the correct post-operation spot)
        f2t_stamina_save_return_location()
        f2t_stamina_take_nav_and_go()
        return
    end

    -- Timeout after 60 seconds (120 polls at 0.5s)
    F2T_STAMINA_STATE.wait_poll_count = (F2T_STAMINA_STATE.wait_poll_count or 0) + 1
    if F2T_STAMINA_STATE.wait_poll_count > 120 then
        f2t_debug_log("[stamina] Timed out waiting for client to pause, proceeding anyway")
        cecho("\n<yellow>[stamina]<reset> Timed out waiting for activity to pause, proceeding...\n")
        f2t_stamina_save_return_location()
        f2t_stamina_take_nav_and_go()
        return
    end

    -- Client still active (finishing current operation), poll again
    if F2T_STAMINA_STATE.wait_poll_count == 1 then
        f2t_debug_log("[stamina] Waiting for client to pause...")
    end
    tempTimer(0.5, function()
        if F2T_STAMINA_STATE.current_phase == "waiting_for_client_pause" then
            f2t_stamina_phase_wait_for_client_pause()
        end
    end)
end

-- Finish food trip and resume client
function f2t_stamina_finish_food_trip()
    -- Navigate back to original location if we have one
    if F2T_STAMINA_STATE.return_location then
        f2t_stamina_transition("navigating_back")
    else
        -- No return location, just resume client
        f2t_stamina_resume_client()
    end
end

-- Resume client activity
function f2t_stamina_resume_client()
    -- Clear navigation ownership
    if f2t_map_clear_nav_owner then
        f2t_map_clear_nav_owner()
    end

    -- Check if food trip failed
    local failed = F2T_STAMINA_STATE.food_trip_failed
    F2T_STAMINA_STATE.food_trip_failed = nil
    F2T_STAMINA_STATE.buy_attempts = 0

    -- Reset to idle
    F2T_STAMINA_STATE.current_phase = "idle"
    F2T_STAMINA_STATE.return_location = nil

    if failed then
        -- Food trip failed - do NOT resume client to prevent character death
        -- Client stays paused; user must manually stop or fix and restart
        f2t_debug_log("[stamina] Food trip failed: %s - client NOT resumed (safety stop)", failed)

        cecho("\n<red>╔════════════════════════════════════════════════════════╗<reset>\n")
        cecho(string.format("<red>║<reset>  <white>STAMINA REFILL FAILED:<reset> %s\n", failed))
        cecho("<red>║<reset>  <yellow>Activity stopped to prevent character death.<reset>\n")
        cecho("<red>║<reset>  Fix food source setting and restart, or stop manually.\n")
        cecho("<red>╚════════════════════════════════════════════════════════╝<reset>\n")

        -- Unregister client so stamina monitor doesn't re-trigger food trip
        -- (client remains paused - user must intervene)
        F2T_STAMINA_STATE.client_was_paused = false
        f2t_stamina_unregister_client()
    else
        -- Success - resume client normally
        if F2T_STAMINA_STATE.client_was_paused and F2T_STAMINA_STATE.client_resume_callback then
            f2t_debug_log("[stamina] Resuming client activity")
            F2T_STAMINA_STATE.client_resume_callback()
            F2T_STAMINA_STATE.client_was_paused = false
        else
            f2t_debug_log("[stamina] Standalone mode - no client to resume")
        end

        cecho("\n<green>[stamina]<reset> Stamina restored, resuming normal operations\n")
    end
end

-- Abort food trip due to failure (navigation failed, max buy attempts, etc.)
-- Tries to navigate back first, then resumes client with error
function f2t_stamina_abort_food_trip(reason)
    f2t_debug_log("[stamina] Aborting food trip: %s", reason)
    F2T_STAMINA_STATE.food_trip_failed = reason

    -- Try to navigate back if we have a return location
    if F2T_STAMINA_STATE.return_location then
        f2t_debug_log("[stamina] Attempting to return to %s after abort", F2T_STAMINA_STATE.return_location)
        f2t_stamina_transition("navigating_back")
    else
        -- No return location, resume immediately
        f2t_stamina_resume_client()
    end
end

-- ========================================
-- Phase Transitions
-- ========================================

-- Transition to a new phase
function f2t_stamina_transition(new_phase)
    f2t_debug_log("[stamina] Transition: %s -> %s", F2T_STAMINA_STATE.current_phase, new_phase)
    F2T_STAMINA_STATE.current_phase = new_phase

    -- Execute phase
    if new_phase == "waiting_for_client_pause" then
        f2t_stamina_phase_wait_for_client_pause()
    elseif new_phase == "navigating_to_food" then
        f2t_stamina_phase_navigate_to_food()
    elseif new_phase == "buying_food" then
        f2t_stamina_phase_buy_food()
    elseif new_phase == "navigating_back" then
        f2t_stamina_phase_navigate_back()
    end
end

-- Phase: Navigate to food source
function f2t_stamina_phase_navigate_to_food()
    -- Check if map navigation is available
    if not f2t_map_navigate then
        cecho("\n<red>[stamina]<reset> Map component not loaded, cannot navigate to food source\n")
        f2t_stamina_resume_client()
        return
    end

    local food_source = f2t_settings_get("shared", "food_source")

    f2t_debug_log("[stamina] Navigating to food source: %s", food_source)
    cecho(string.format("\n<cyan>[stamina]<reset> Navigating to food source: %s\n", food_source))

    -- Use map navigation to get to food source
    local success = f2t_map_navigate(food_source)

    if not success then
        f2t_stamina_abort_food_trip("could not find path to food source")
        return
    end

    -- Wait for navigation to complete (checked in GMCP handler)
end

-- Max buy attempts before aborting (each attempt = 0.5s, 25 = 12.5s)
-- Normal 0→100% needs ~15 buys, so 25 gives comfortable margin
F2T_STAMINA_MAX_BUY_ATTEMPTS = 25

-- Phase: Buy food until stamina is full
function f2t_stamina_phase_buy_food()
    -- Track attempts
    F2T_STAMINA_STATE.buy_attempts = (F2T_STAMINA_STATE.buy_attempts or 0) + 1

    if F2T_STAMINA_STATE.buy_attempts > F2T_STAMINA_MAX_BUY_ATTEMPTS then
        f2t_debug_log("[stamina] Max buy attempts (%d) exceeded, aborting", F2T_STAMINA_MAX_BUY_ATTEMPTS)
        f2t_stamina_abort_food_trip("max buy attempts exceeded (not at a food vendor?)")
        return
    end

    local percent = math.floor((F2T_STAMINA_STATE.current_stamina / F2T_STAMINA_STATE.max_stamina) * 100)

    if percent >= 100 then
        -- Stamina full, we're done
        f2t_debug_log("[stamina] Stamina full (%d%%)", percent)
        F2T_STAMINA_STATE.buy_attempts = 0
        f2t_stamina_finish_food_trip()
        return
    end

    f2t_debug_log("[stamina] Buying food (stamina: %d%%, attempt %d/%d)", percent, F2T_STAMINA_STATE.buy_attempts, F2T_STAMINA_MAX_BUY_ATTEMPTS)

    -- Buy food from vendor (automatically consumed, +10 stamina)
    send("buy food")

    -- Wait for GMCP to update stamina, then buy more if needed
    tempTimer(0.5, function()
        if F2T_STAMINA_STATE.current_phase == "buying_food" then
            -- Recursively buy more food until full
            f2t_stamina_phase_buy_food()
        end
    end)
end

-- Phase: Navigate back to original location
function f2t_stamina_phase_navigate_back()
    -- Check if map navigation is available
    if not f2t_map_navigate then
        cecho("\n<yellow>[stamina]<reset> Map component not loaded, resuming at current location\n")
        f2t_stamina_resume_client()
        return
    end

    f2t_debug_log("[stamina] Navigating back to: %s", F2T_STAMINA_STATE.return_location)
    cecho(string.format("\n<cyan>[stamina]<reset> Returning to original location\n"))

    local success = f2t_map_navigate(F2T_STAMINA_STATE.return_location)

    if not success then
        cecho("\n<yellow>[stamina]<reset> Failed to navigate back, resuming at current location\n")
        f2t_stamina_resume_client()
        return
    end

    -- Wait for navigation to complete (checked in GMCP handler)
end

-- ========================================
-- Standalone Mode (y/n prompt)
-- ========================================

-- Show yes/no prompt for standalone stamina refill
function f2t_stamina_show_standalone_prompt(percent, threshold)
    -- Guard: Already showing prompt
    if F2T_STAMINA_STATE.standalone_prompt_active then
        f2t_debug_log("[stamina] Prompt already active, skipping")
        return
    end

    -- Guard: In cooldown (user recently said "no")
    if F2T_STAMINA_STATE.standalone_dismissed_at then
        local elapsed = os.time() - F2T_STAMINA_STATE.standalone_dismissed_at
        if elapsed < F2T_STAMINA_DISMISS_COOLDOWN then
            f2t_debug_log("[stamina] In cooldown, %d seconds remaining", F2T_STAMINA_DISMISS_COOLDOWN - elapsed)
            return
        end
    end

    F2T_STAMINA_STATE.standalone_prompt_active = true

    -- Display prominent prompt
    cecho("\n")
    cecho("<yellow>╔════════════════════════════════════════╗<reset>\n")
    cecho(string.format("<yellow>║<reset>  <white>LOW STAMINA:<reset> <red>%d%%<reset> (threshold: %d%%)      <yellow>║<reset>\n", percent, threshold))
    cecho("<yellow>║<reset>                                        <yellow>║<reset>\n")
    cecho("<yellow>║<reset>  Would you like to go refill?          <yellow>║<reset>\n")
    cecho("<yellow>║<reset>  Type <green>yes<reset> or <red>no<reset>                       <yellow>║<reset>\n")
    cecho("<yellow>╚════════════════════════════════════════╝<reset>\n")

    -- Create temp aliases to capture user input (not game output)
    local yes_alias = tempAlias("^yes$", function()
        f2t_stamina_prompt_accept()
    end)
    local no_alias = tempAlias("^no$", function()
        f2t_stamina_prompt_dismiss()
    end)

    F2T_STAMINA_STATE.standalone_prompt_aliases = {yes_alias, no_alias}

    -- Set timeout timer (auto-dismiss after 30 seconds)
    F2T_STAMINA_STATE.standalone_prompt_timer = tempTimer(F2T_STAMINA_PROMPT_TIMEOUT, function()
        f2t_stamina_prompt_timeout()
    end)

    f2t_debug_log("[stamina] Standalone prompt shown, waiting for 'yes' or 'no' (timeout: %ds)", F2T_STAMINA_PROMPT_TIMEOUT)
end

-- User accepted refill prompt
function f2t_stamina_prompt_accept()
    f2t_debug_log("[stamina] User typed 'yes' - accepting prompt")
    f2t_stamina_cleanup_prompt()
    cecho("\n<green>[stamina]<reset> Starting food trip...\n")
    f2t_stamina_start_food_trip()
end

-- User dismissed refill prompt
function f2t_stamina_prompt_dismiss()
    f2t_debug_log("[stamina] User typed 'no' - dismissing prompt")
    f2t_stamina_cleanup_prompt()
    F2T_STAMINA_STATE.standalone_dismissed_at = os.time()
    cecho("\n<dim_grey>[stamina]<reset> Dismissed. Will remind again in 5 minutes.\n")
    f2t_debug_log("[stamina] Prompt dismissed, cooldown started at %d", F2T_STAMINA_STATE.standalone_dismissed_at)
end

-- Prompt timed out
function f2t_stamina_prompt_timeout()
    if not F2T_STAMINA_STATE.standalone_prompt_active then
        return  -- Already cleaned up
    end
    f2t_debug_log("[stamina] Prompt timed out after %d seconds", F2T_STAMINA_PROMPT_TIMEOUT)
    f2t_stamina_cleanup_prompt()
    F2T_STAMINA_STATE.standalone_dismissed_at = os.time()
    cecho("\n<dim_grey>[stamina]<reset> Prompt timed out. Will remind again in 5 minutes.\n")
end

-- Clean up prompt aliases and timer
function f2t_stamina_cleanup_prompt()
    local alias_count = #(F2T_STAMINA_STATE.standalone_prompt_aliases or {})
    f2t_debug_log("[stamina] Cleaning up prompt: %d aliases to kill", alias_count)

    F2T_STAMINA_STATE.standalone_prompt_active = false

    -- Kill aliases
    for _, alias_id in ipairs(F2T_STAMINA_STATE.standalone_prompt_aliases or {}) do
        killAlias(alias_id)
    end
    F2T_STAMINA_STATE.standalone_prompt_aliases = {}

    -- Kill timeout timer
    if F2T_STAMINA_STATE.standalone_prompt_timer then
        killTimer(F2T_STAMINA_STATE.standalone_prompt_timer)
        F2T_STAMINA_STATE.standalone_prompt_timer = nil
    end

    f2t_debug_log("[stamina] Prompt cleanup complete")
end

-- Cancel prompt if a component becomes active
function f2t_stamina_cancel_standalone_prompt()
    if F2T_STAMINA_STATE.standalone_prompt_active then
        f2t_stamina_cleanup_prompt()
        cecho("\n<dim_grey>[stamina]<reset> Prompt cancelled (component now handling stamina)\n")
        f2t_debug_log("[stamina] Prompt cancelled due to component activation")
    end
end

-- ========================================
-- Navigation Completion Detection
-- ========================================

-- Check if navigation to food is complete
function f2t_stamina_check_nav_to_food_complete()
    if F2T_STAMINA_STATE.current_phase ~= "navigating_to_food" then
        return
    end

    -- Check if speedwalk is no longer active (treat nil as inactive)
    local speedwalk_active = F2T_SPEEDWALK_ACTIVE or false
    if not speedwalk_active then
        local result = F2T_SPEEDWALK_LAST_RESULT
        if result == "completed" then
            f2t_debug_log("[stamina] Arrived at food source")
            f2t_stamina_transition("buying_food")
        else
            -- Navigation failed or was stopped
            f2t_debug_log("[stamina] Navigation to food failed: %s", result or "unknown")
            f2t_stamina_abort_food_trip(string.format("could not reach food source (%s)", result or "unknown"))
        end
    end
end

-- Check if navigation back is complete
function f2t_stamina_check_nav_back_complete()
    if F2T_STAMINA_STATE.current_phase ~= "navigating_back" then
        return
    end

    -- Check if speedwalk is no longer active (treat nil as inactive)
    local speedwalk_active = F2T_SPEEDWALK_ACTIVE or false
    if not speedwalk_active then
        local result = F2T_SPEEDWALK_LAST_RESULT
        if result == "completed" then
            f2t_debug_log("[stamina] Arrived back at original location")
        else
            -- Navigation back failed - resume at current location (best effort)
            f2t_debug_log("[stamina] Navigation back failed: %s - resuming at current location", result or "unknown")
        end
        f2t_stamina_resume_client()
    end
end

-- Register navigation completion handler (with cleanup on reload)
function f2t_stamina_register_nav_handler()
    -- Kill existing handler if any (prevents duplicates on package reload)
    if F2T_STAMINA_STATE.nav_handler_id then
        killAnonymousEventHandler(F2T_STAMINA_STATE.nav_handler_id)
        F2T_STAMINA_STATE.nav_handler_id = nil
    end

    F2T_STAMINA_STATE.nav_handler_id = registerAnonymousEventHandler("gmcp.room.info", function()
        tempTimer(0.3, function()
            f2t_stamina_check_nav_to_food_complete()
            f2t_stamina_check_nav_back_complete()
        end)
    end)
end

-- Register handler on script load
f2t_stamina_register_nav_handler()

f2t_debug_log("[stamina] Stamina monitor initialized")
