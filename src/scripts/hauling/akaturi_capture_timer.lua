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

    -- Known planet but the room genuinely isn't in the map database yet (or
    -- the planet itself isn't mapped at all) - explore for the exact room
    -- name instead of giving up immediately. f2t_map_explore_planet_start's
    -- own travel step self-heals an unmapped planet via f2t_map_navigate's
    -- whereis support.
    if matches == nil or #matches == 0 then
        cecho(string.format(
            "\n<yellow>[hauling]<reset> '%s' not found on %s, exploring to look for it...\n", room, planet))
        F2T_HAULING_STATE.current_phase = "akaturi_searching_delivery"
        f2t_map_explore_planet_start("brief", planet, function(found_room_id)
            if not F2T_HAULING_STATE.active or F2T_HAULING_STATE.paused then
                return
            end
            if found_room_id then
                cecho(string.format("\n<green>[hauling]<reset> Found delivery room: %s (ID: %s)\n",
                    room, found_room_id))
                F2T_AKATURI_STATE.delivery_matches = {{name = room, room_id = found_room_id}}
                f2t_akaturi_reset_match_index()
                F2T_HAULING_STATE.current_phase = "akaturi_navigating_delivery"
                f2t_hauling_phase_akaturi_navigate_delivery()
            else
                cecho(string.format("\n<yellow>[hauling]<reset> Still could not find '%s' on %s\n", room, planet))
                cecho(string.format(
                    "\n<yellow>[hauling]<reset> Navigating to %s. Please find the room manually and resume hauling.\n",
                    planet))
                F2T_HAULING_STATE.current_phase = "akaturi_navigating_to_planet_for_delivery"
                f2t_map_navigate(planet)
            end
        end, nil, room, true)
        return
    end

    if #matches == 1 then
        cecho(string.format(
            "\n<green>[hauling]<reset> Found delivery room: %s (ID: %s)\n", matches[1].name, matches[1].room_id))
    else
        cecho(string.format(
            "\n<yellow>[hauling]<reset> Found %d rooms matching '%s', will try each one\n", #matches, room))
    end

    -- Store matches and transition
    F2T_AKATURI_STATE.delivery_matches = matches
    F2T_HAULING_STATE.current_phase = "akaturi_navigating_delivery"
    f2t_hauling_phase_akaturi_navigate_delivery()
end

f2t_debug_log("[hauling/akaturi] Pickup capture timer module loaded")