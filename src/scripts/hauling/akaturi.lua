-- Akaturi helpers: map search for a contract's room title and the player's
-- Akaturi credits.

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

    local results = f2t_map_search_planet_or_system(planet, room_title)
    if not results then
        f2t_debug_log("[hauling/akaturi] Planet '%s' not mapped", planet)
        return nil
    end

    local exact_matches = {}
    for _, result in ipairs(results) do
        if result.name == room_title then
            table.insert(exact_matches, result)
        end
    end

    f2t_debug_log("[hauling/akaturi] %d exact match(es) for '%s' on %s", #exact_matches, room_title, planet)
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

f2t_debug_log("[hauling/akaturi] Akaturi module loaded")
