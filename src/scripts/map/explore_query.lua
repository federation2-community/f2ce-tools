-- f2ce-tools map — exploration query functions (ported from map_explore_query.lua)

function f2t_map_explore_has_unlocked_stubs(area_id)
    local rooms_in_area = getAreaRooms(area_id)
    if not rooms_in_area then return false end
    for _, room_id in pairs(rooms_in_area) do
        local stubs = getExitStubs(room_id)
        if stubs then
            for _, stub_dir_num in pairs(stubs) do
                local direction = f2t_map_explore_direction_number_to_name(stub_dir_num)
                if direction and not hasExitLock(room_id, direction) then return true end
            end
        end
    end
    return false
end

function f2t_map_explore_planet_has_flags(area_id, required_flags)
    local rooms_in_area = getAreaRooms(area_id)
    if not rooms_in_area then return false end
    local found_flags = {}
    for _, room_id in pairs(rooms_in_area) do
        for _, flag in ipairs(required_flags) do
            if not found_flags[flag] then
                if getRoomUserData(room_id, string.format("fed2_flag_%s", flag)) == "true" then
                    found_flags[flag] = true
                end
            end
        end
    end
    for _, flag in ipairs(required_flags) do
        if not found_flags[flag] then return false end
    end
    return true
end

function f2t_map_explore_is_system_fully_mapped(system_name)
    local space_area_name = f2t_map_get_system_space_area_actual(system_name)
    if not space_area_name then return false end
    local space_area_id = f2t_map_get_area_id(space_area_name)
    if not space_area_id then return false end
    if f2t_map_explore_has_unlocked_stubs(space_area_id) then return false end

    local orbit_rooms = {}
    local rooms_in_area = getAreaRooms(space_area_id)
    for _, room_id in pairs(rooms_in_area) do
        local planet = getRoomUserData(room_id, "fed2_planet")
        if planet then
            local planet_area_id = f2t_map_get_area_id(planet)
            if planet_area_id then
                table.insert(orbit_rooms, {name = planet, area_id = planet_area_id})
            end
        end
    end
    if #orbit_rooms == 0 then return false end

    local required_flags = {"shuttlepad"}
    local additional_flags_str = f2t_settings_get("map", "brief_additional_flags") or "exchange"
    for flag in string.gmatch(additional_flags_str, "[^,]+") do
        local trimmed = flag:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed ~= "shuttlepad" then
            table.insert(required_flags, trimmed)
        end
    end

    for _, planet in ipairs(orbit_rooms) do
        if not f2t_map_explore_planet_has_flags(planet.area_id, required_flags) then return false end
    end
    return true
end

f2t_debug_log("[map] Loaded explore_query.lua")
