-- f2ce-tools map — room search (ported from map_search.lua)

function f2t_map_search_area(area_id, search_text)
    if not area_id or not search_text or search_text == "" then return {} end
    local results = {}
    local room_ids = getAreaRooms(area_id)
    if not room_ids then return results end
    local search_lower = string.lower(search_text)
    if room_ids[0] then
        local room_name = getRoomName(room_ids[0])
        if room_name and string.find(string.lower(room_name), search_lower, 1, true) then
            table.insert(results, {
                room_id = room_ids[0], name = room_name,
                hash = f2t_map_generate_hash_from_room(room_ids[0]),
                system = getRoomUserData(room_ids[0], "fed2_system"),
                area   = getRoomUserData(room_ids[0], "fed2_area"),
            })
        end
    end
    for _, room_id in ipairs(room_ids) do
        local room_name = getRoomName(room_id)
        if room_name and string.find(string.lower(room_name), search_lower, 1, true) then
            table.insert(results, {
                room_id = room_id, name = room_name,
                hash = f2t_map_generate_hash_from_room(room_id),
                system = getRoomUserData(room_id, "fed2_system"),
                area   = getRoomUserData(room_id, "fed2_area"),
            })
        end
    end
    return results
end

function f2t_map_search_all(search_text)
    if not search_text or search_text == "" then return {} end
    local results = {}
    local matching_rooms = searchRoom(search_text, false, false)
    if not matching_rooms then return results end
    for room_id, room_name in pairs(matching_rooms) do
        table.insert(results, {
            room_id = room_id, name = room_name,
            hash   = f2t_map_generate_hash_from_room(room_id),
            system = getRoomUserData(room_id, "fed2_system"),
            area   = getRoomUserData(room_id, "fed2_area"),
        })
    end
    return results
end

function f2t_map_search_current_area(search_text)
    if not search_text or search_text == "" then return {} end
    if not F2T_MAP_CURRENT_ROOM_ID or not roomExists(F2T_MAP_CURRENT_ROOM_ID) then return nil end
    local current_area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
    if not current_area_id then return nil end
    return f2t_map_search_area(current_area_id, search_text)
end

function f2t_map_search_planet_or_system(location, search_text)
    if not location or location == "" or not search_text or search_text == "" then return nil end
    local results = {}
    local planet_data = f2t_map_lookup_planet(location)
    if planet_data then
        local planet_area_id = f2t_map_get_area_id(location)
        if planet_area_id then return f2t_map_search_area(planet_area_id, search_text) end
    end
    local system_data = f2t_map_lookup_system(location)
    if system_data then
        local search_lower = string.lower(location)
        local space_area = f2t_map_get_system_space_area_actual(location)
        if space_area then
            local space_area_id = f2t_map_get_area_id(space_area)
            if space_area_id then
                for _, result in ipairs(f2t_map_search_area(space_area_id, search_text)) do
                    table.insert(results, result)
                end
            end
        end
        local all_areas = getAreaTable()
        for area_name, area_id in pairs(all_areas) do
            if area_name ~= space_area then
                local area_rooms = getAreaRooms(area_id)
                if area_rooms and next(area_rooms) then
                    local sample_room = area_rooms[0] or area_rooms[1] or area_rooms[next(area_rooms)]
                    local room_system = getRoomUserData(sample_room, "fed2_system")
                    if room_system and string.lower(room_system) == search_lower then
                        for _, result in ipairs(f2t_map_search_area(area_id, search_text)) do
                            table.insert(results, result)
                        end
                    end
                end
            end
        end
        return results
    end
    return nil
end

function f2t_map_search_display(results, search_text, scope)
    if not results then
        cecho("\n<red>[map]<reset> Search location not found or not yet mapped\n")
        cecho("\n<dim_grey>Visit the location first to add it to the map<reset>\n"); return
    end
    if #results == 0 then
        cecho(string.format("\n<yellow>[map]<reset> No rooms found matching '%s' in %s\n", search_text, scope)); return
    end
    table.sort(results, function(a, b)
        if a.system ~= b.system then return (a.system or "") < (b.system or "") end
        if a.area   ~= b.area   then return (a.area   or "") < (b.area   or "") end
        return (a.name or "") < (b.name or "")
    end)
    cecho(string.format("\n<green>[map]<reset> Found <yellow>%d<reset> room(s) matching '<white>%s<reset>' in %s:\n",
        #results, search_text, scope))
    f2t_render_table({
        columns = {
            {header = "ID",     field = "room_id", align = "right", width = 6},
            {header = "System", field = "system",  width = 15},
            {header = "Area",   field = "area",    width = 20},
            {header = "Name",   field = "name",    max_width = 40},
            {header = "Hash",   field = "hash",    color = "dim_grey", max_width = 30},
        },
        data = results,
    })
end
