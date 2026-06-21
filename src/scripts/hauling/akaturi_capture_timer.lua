-- Akaturi pickup capture completion timer
-- Uses 0.5s silence detection to determine when pickup output is complete

local akaturi_pickup_timer_id = nil

--- Start/reset the Akaturi pickup capture completion timer
--- Timer fires after 0.5s of silence to process captured pickup data
function f2t_akaturi_reset_pickup_timer()
    -- Cancel existing timer
    if akaturi_pickup_timer_id then
        killTimer(akaturi_pickup_timer_id)
        akaturi_pickup_timer_id = nil
    end

    -- Start new timer - if no more lines arrive in 0.5s, we're done
    akaturi_pickup_timer_id = tempTimer(0.5, function()
        -- CRITICAL: Always finish capture when timer expires, even with zero data
        if F2T_AKATURI_STATE.capturing_pickup then
            f2t_debug_log("[hauling/akaturi] Pickup capture timeout - processing %d lines",
                #F2T_AKATURI_STATE.pickup_buffer)
            f2t_akaturi_process_pickup_capture()
        end
        akaturi_pickup_timer_id = nil
    end)
end

--- Process captured pickup data and transition to delivery search
function f2t_akaturi_process_pickup_capture()
    -- Stop capture and get lines
    local lines = f2t_akaturi_stop_pickup_capture()

    if not lines or #lines == 0 then
        cecho("\n<red>[hauling]<reset> No pickup data captured\n")
        f2t_hauling_stop()
        return
    end

    -- Parse delivery location
    local planet, room, item = f2t_akaturi_parse_pickup(lines)

    if not planet or not room then
        cecho("\n<red>[hauling]<reset> Failed to parse delivery location from pickup output\n")
        f2t_hauling_stop()
        return
    end

    -- Store delivery location
    F2T_HAULING_STATE.akaturi_contract.delivery_planet = planet
    F2T_HAULING_STATE.akaturi_contract.delivery_room = room
    F2T_HAULING_STATE.akaturi_contract.item = item

    cecho(string.format("\n<green>[hauling]<reset> Deliver %s to '%s' on %s\n", item or "package", room, planet))

    -- Reset for delivery search
    f2t_akaturi_reset_match_index()

    -- Search for delivery room (synchronous)
    F2T_HAULING_STATE.current_phase = "akaturi_searching_delivery"
    cecho(string.format("\n<cyan>[hauling]<reset> Searching map for '%s' on %s...\n", room, planet))

    local matches = f2t_akaturi_search_room(planet, room)

    -- Check if planet not mapped
    if matches == nil then
        cecho(string.format("\n<yellow>[hauling]<reset> Planet '%s' not yet mapped\n", planet))
        cecho(string.format("\n<yellow>[hauling]<reset> Navigating to %s. Please find the room manually and resume hauling.\n", planet))

        -- Navigate to planet (will pause after arrival via special phase)
        F2T_HAULING_STATE.current_phase = "akaturi_navigating_to_planet_for_delivery"
        f2t_map_navigate(planet)
        return
    end

    -- Check if no matches found
    if #matches == 0 then
        -- No exact matches found
        cecho(string.format("\n<yellow>[hauling]<reset> Could not find '%s' on %s in map database\n", room, planet))
        cecho(string.format("\n<yellow>[hauling]<reset> Navigating to %s. Please find the room manually and resume hauling.\n", planet))

        -- Navigate to planet (will pause after arrival via special phase)
        F2T_HAULING_STATE.current_phase = "akaturi_navigating_to_planet_for_delivery"
        f2t_map_navigate(planet)
        return
    end

    if #matches == 1 then
        cecho(string.format("\n<green>[hauling]<reset> Found delivery room: %s (ID: %s)\n", matches[1].name, matches[1].room_id))
    else
        cecho(string.format("\n<yellow>[hauling]<reset> Found %d rooms matching '%s', will try each one\n", #matches, room))
    end

    -- Store matches and transition
    F2T_AKATURI_STATE.delivery_matches = matches
    F2T_HAULING_STATE.current_phase = "akaturi_navigating_delivery"
    f2t_hauling_phase_akaturi_navigate_delivery()
end

f2t_debug_log("[hauling/akaturi] Pickup capture timer module loaded")