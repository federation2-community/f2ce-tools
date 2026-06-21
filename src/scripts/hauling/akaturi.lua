-- Akaturi contract management
-- Provides data structures, parsing functions, and helper functions for Akaturi jobs

-- Akaturi contract state
F2T_AKATURI_STATE = {
    capturing_job = false,
    capturing_pickup = false,
    job_buffer = {},       -- Lines from job assignment
    pickup_buffer = {},    -- Lines from pickup confirmation

    -- Current contract details
    contract = {
        pickup_planet = nil,
        pickup_room = nil,
        delivery_planet = nil,
        delivery_room = nil,
        item = nil  -- Item being transported (from pickup message)
    },

    -- Room search and matching
    pickup_matches = {},      -- Array of room IDs matching pickup location
    delivery_matches = {},    -- Array of room IDs matching delivery location
    current_match_index = 0   -- Which match we're currently trying
}

--- Parse job assignment output to extract pickup location
--- Format:
---   Your task is to pick up a package on Pearl. The package can be picked up from:
---     -----
---   Shrine of the Sunbeam
---     ...room description...
---   You can see one exit: southeast.
---     -----
---   Delivery details will be provided when you collect the package.
--- @param lines table Array of captured lines
--- @return string|nil planet Planet name
--- @return string|nil room Room title
function f2t_akaturi_parse_job(lines)
    if not lines or #lines == 0 then
        f2t_debug_log("[hauling/akaturi] No job lines to parse")
        return nil, nil
    end

    local planet = nil
    local room = nil
    local in_room_section = false

    for _, line in ipairs(lines) do
        -- Extract planet from first line: "Your task is to pick up a package on Pearl."
        if not planet then
            local match = line:match("Your task is to pick up a package on ([^%.]+)%.")
            if match then
                planet = match
                f2t_debug_log("[hauling/akaturi] Parsed pickup planet: %s", planet)
            end
        end

        -- Detect room section start
        if line:match("^%s*%-%-%-%-%-%s*$") then
            in_room_section = not in_room_section
            if not in_room_section and room then
                -- Exiting room section, we're done
                break
            end
        elseif in_room_section and not room then
            -- First line after opening ----- is the room title
            room = line:match("^(.+)$")
            if room then
                f2t_debug_log("[hauling/akaturi] Parsed pickup room: %s", room)
            end
        end
    end

    if not planet or not room then
        f2t_debug_log("[hauling/akaturi] Failed to parse job assignment (planet=%s, room=%s)",
            tostring(planet), tostring(room))
    end

    return planet, room
end

--- Parse pickup confirmation to extract delivery location
--- Format:
---   You pickup the valuable package and sign for it.
---   You need to take the violin entrusted to you to Titan. When you get there you must drop it off at:
---     -----
---   Store
---     ...room description...
---   You can see two exits: west and out.
---     -----
---   This very fine violin requires care to transport. No wonder they shipped it by courier.
--- @param lines table Array of captured lines
--- @return string|nil planet Planet name
--- @return string|nil room Room title
--- @return string|nil item Item name
function f2t_akaturi_parse_pickup(lines)
    if not lines or #lines == 0 then
        f2t_debug_log("[hauling/akaturi] No pickup lines to parse")
        return nil, nil, nil
    end

    local planet = nil
    local room = nil
    local item = nil
    local in_room_section = false

    for _, line in ipairs(lines) do
        -- Extract item and planet: "You need to take the klein bottle entrusted to you to The Lattice."
        -- Note: Item can be multi-word (klein bottle), planet can have spaces (The Lattice)
        -- Text might wrap, so period or "When you get there" might be on next line
        if not planet then
            local item_match, planet_match = line:match("You need to take the (.+) entrusted to you to (.+)")
            if item_match and planet_match then
                item = item_match
                -- Clean up planet: remove period, "When you get there", and trailing whitespace
                planet = planet_match:gsub("%..*", ""):gsub("%s*When you get there.*", ""):match("^%s*(.-)%s*$")
                f2t_debug_log("[hauling/akaturi] Parsed delivery planet: %s, item: %s", planet, item)
            end
        end

        -- Detect room section start
        if line:match("^%s*%-%-%-%-%-%s*$") then
            in_room_section = not in_room_section
            if not in_room_section and room then
                -- Exiting room section, we're done
                break
            end
        elseif in_room_section and not room then
            -- First line after opening ----- is the room title
            room = line:match("^(.+)$")
            if room then
                f2t_debug_log("[hauling/akaturi] Parsed delivery room: %s", room)
            end
        end
    end

    if not planet or not room or not item then
        f2t_debug_log("[hauling/akaturi] Failed to parse pickup confirmation (planet=%s, room=%s, item=%s)",
            tostring(planet), tostring(room), tostring(item))
    end

    return planet, room, item
end

--- Search map for exact room title match on a specific planet
--- Uses f2t_map_search_planet_or_system() to find rooms
--- @param planet string Planet name to search
--- @param room_title string Room title to match exactly
--- @return table Array of {room_id, name, hash, system, area} matches, or nil if planet not mapped
function f2t_akaturi_search_room(planet, room_title)
    if not planet or not room_title then
        f2t_debug_log("[hauling/akaturi] Invalid search parameters: planet=%s, room=%s",
            tostring(planet), tostring(room_title))
        return {}
    end

    f2t_debug_log("[hauling/akaturi] Searching for room '%s' on %s", room_title, planet)

    -- Use map search to find potential matches (synchronous)
    local results = f2t_map_search_planet_or_system(planet, room_title)

    if not results then
        -- Planet not mapped yet
        f2t_debug_log("[hauling/akaturi] Planet '%s' not mapped", planet)
        return nil
    end

    if #results == 0 then
        f2t_debug_log("[hauling/akaturi] No map search results for '%s' on %s", room_title, planet)
        return {}
    end

    -- Filter for exact room title matches
    local exact_matches = {}
    for _, result in ipairs(results) do
        if result.name == room_title then
            table.insert(exact_matches, result)
            f2t_debug_log("[hauling/akaturi] Found exact match: %s (ID: %s)", result.name, result.room_id)
        end
    end

    if #exact_matches == 0 then
        f2t_debug_log("[hauling/akaturi] No exact matches for '%s' on %s", room_title, planet)
    else
        f2t_debug_log("[hauling/akaturi] Found %d exact match(es) for '%s' on %s",
            #exact_matches, room_title, planet)
    end

    return exact_matches
end

--- Get Akaturi points from GMCP data
--- @return number|nil Akaturi points or nil if not available
function f2t_akaturi_get_points()
    if not gmcp or not gmcp.char or not gmcp.char.vitals or not gmcp.char.vitals.points then
        return nil
    end

    local points = gmcp.char.vitals.points
    if points.type == "ak" then
        return tonumber(points.amt) or 0
    end

    return nil
end

--- Check if player has completed all Akaturi contracts
--- @return boolean True if has 25+ points
function f2t_akaturi_is_complete()
    local points = f2t_akaturi_get_points()
    if not points then
        return false
    end
    return points >= 25
end

--- Start capturing job assignment output
function f2t_akaturi_start_job_capture()
    F2T_AKATURI_STATE.capturing_job = true
    F2T_AKATURI_STATE.job_buffer = {}
    f2t_debug_log("[hauling/akaturi] Started capturing job assignment")
end

--- Stop capturing job output and return lines
--- @return table Array of captured lines
function f2t_akaturi_stop_job_capture()
    F2T_AKATURI_STATE.capturing_job = false
    local lines = F2T_AKATURI_STATE.job_buffer
    f2t_debug_log("[hauling/akaturi] Stopped job capture, found %d lines", #lines)
    return lines
end

--- Add a line to job capture buffer
--- @param line string Line from game output
function f2t_akaturi_add_job_line(line)
    if not F2T_AKATURI_STATE.capturing_job then
        return
    end

    table.insert(F2T_AKATURI_STATE.job_buffer, line)
end

--- Check if currently capturing job
--- @return boolean True if capturing
function f2t_akaturi_is_capturing_job()
    return F2T_AKATURI_STATE.capturing_job
end

--- Start capturing pickup confirmation output
function f2t_akaturi_start_pickup_capture()
    F2T_AKATURI_STATE.capturing_pickup = true
    F2T_AKATURI_STATE.pickup_buffer = {}
    f2t_debug_log("[hauling/akaturi] Started capturing pickup confirmation")
end

--- Stop capturing pickup output and return lines
--- @return table Array of captured lines
function f2t_akaturi_stop_pickup_capture()
    F2T_AKATURI_STATE.capturing_pickup = false
    local lines = F2T_AKATURI_STATE.pickup_buffer
    f2t_debug_log("[hauling/akaturi] Stopped pickup capture, found %d lines", #lines)
    return lines
end

--- Add a line to pickup capture buffer
--- @param line string Line from game output
function f2t_akaturi_add_pickup_line(line)
    if not F2T_AKATURI_STATE.capturing_pickup then
        return
    end

    table.insert(F2T_AKATURI_STATE.pickup_buffer, line)
end

--- Check if currently capturing pickup
--- @return boolean True if capturing
function f2t_akaturi_is_capturing_pickup()
    return F2T_AKATURI_STATE.capturing_pickup
end

--- Reset contract state for new job
function f2t_akaturi_reset_contract()
    F2T_AKATURI_STATE.contract = {
        pickup_planet = nil,
        pickup_room = nil,
        delivery_planet = nil,
        delivery_room = nil,
        item = nil
    }
    F2T_AKATURI_STATE.pickup_matches = {}
    F2T_AKATURI_STATE.delivery_matches = {}
    F2T_AKATURI_STATE.current_match_index = 0
    f2t_debug_log("[hauling/akaturi] Reset contract state")
end

--- Get next match to try from the matches array
--- @param matches table Array of room matches
--- @return string|nil Room ID of next match, or nil if no more matches
function f2t_akaturi_get_next_match(matches)
    if not matches or #matches == 0 then
        return nil
    end

    F2T_AKATURI_STATE.current_match_index = F2T_AKATURI_STATE.current_match_index + 1

    if F2T_AKATURI_STATE.current_match_index > #matches then
        f2t_debug_log("[hauling/akaturi] No more matches to try (%d/%d)",
            F2T_AKATURI_STATE.current_match_index - 1, #matches)
        return nil
    end

    local match = matches[F2T_AKATURI_STATE.current_match_index]
    f2t_debug_log("[hauling/akaturi] Trying match %d/%d: %s (ID: %s)",
        F2T_AKATURI_STATE.current_match_index, #matches, match.name, match.room_id)

    return match.room_id
end

--- Reset match index for new search
function f2t_akaturi_reset_match_index()
    F2T_AKATURI_STATE.current_match_index = 0
end

f2t_debug_log("[hauling/akaturi] Akaturi module loaded")