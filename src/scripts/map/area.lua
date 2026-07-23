-- f2ce-tools map — area management (ported from map_area.lua)

function f2t_map_get_or_create_area(area_name, area_data)
    if not area_name or area_name == "" then
        f2t_debug_log("[map] ERROR: Cannot create area with empty name")
        return nil
    end
    local areas = getAreaTable()
    local area_id = areas[area_name]
    if area_id then
        f2t_debug_log("[map] Area found: %s (ID: %d)", area_name, area_id)
        return area_id
    end
    area_id = addAreaName(area_name)
    if not area_id then
        f2t_debug_log("[map] ERROR: Failed to create area: %s", area_name)
        return nil
    end
    local zoom = f2t_settings_get("map", "area_zoom")
    setMapZoom(zoom, area_id)
    f2t_debug_log("[map] Area created: %s (ID: %d, zoom: %d)", area_name, area_id, zoom)
    if area_data then
        if area_data.system then setAreaUserData(area_id, "fed2_system", area_data.system) end
        if area_data.cartel then setAreaUserData(area_id, "fed2_cartel", area_data.cartel) end
        if area_data.owner  then setAreaUserData(area_id, "fed2_owner",  area_data.owner)  end
    end
    return area_id
end

function f2t_map_get_area_id(area_name)
    if not area_name or area_name == "" then return nil end
    local areas = getAreaTable()
    local area_id = areas[area_name]
    if area_id then
        f2t_debug_log("[map_area] get_area_id('%s') -> %d (exact match)", area_name, area_id)
        return area_id
    end
    local search_lower = string.lower(area_name)
    for name, id in pairs(areas) do
        if string.lower(name) == search_lower then
            f2t_debug_log("[map_area] get_area_id('%s') -> %d (case-insensitive match: '%s')", area_name, id, name)
            return id
        end
    end
    f2t_debug_log("[map_area] get_area_id('%s') -> nil (not found)", area_name)
    return nil
end

function f2t_map_get_area_name(area_id)
    return getRoomAreaName(area_id)
end

function f2t_map_get_system_from_space_area(area_name)
    return string.match(area_name, "^(.+)%s+Space$")
end

function f2t_map_get_system_space_area(system)
    return string.format("%s Space", system)
end

function f2t_map_get_system_space_area_actual(system_name)
    local areas = getAreaTable()
    local search_lower = string.lower(system_name)
    for area_name, _ in pairs(areas) do
        local system = f2t_map_get_system_from_space_area(area_name)
        if system and string.lower(system) == search_lower then
            return area_name
        end
    end
    return nil
end

function f2t_map_parse_location_prefix(input)
    if not input or input == "" then return nil, "" end
    local words = {}
    for word in string.gmatch(input, "%S+") do table.insert(words, word) end
    if #words < 2 then return nil, input end
    for i = #words - 1, 1, -1 do
        local potential_location = table.concat(words, " ", 1, i)
        local area_id   = f2t_map_get_area_id(potential_location)
        local space_area = f2t_map_get_system_space_area_actual(potential_location)
        if area_id or space_area then
            local remaining = table.concat(words, " ", i + 1)
            f2t_debug_log("[map_area] parse_location_prefix('%s') -> location='%s', remaining='%s'",
                input, potential_location, remaining)
            return potential_location, remaining
        end
    end
    f2t_debug_log("[map_area] parse_location_prefix('%s') -> no location found", input)
    return nil, input
end
