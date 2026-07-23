-- f2ce-tools map — GMCP and map lookup helpers (ported from map_helpers.lua)

function f2t_get_current_system()
    if not gmcp or not gmcp.room or not gmcp.room.info then return nil end
    return gmcp.room.info.system
end

function f2t_get_current_planet()
    if not gmcp or not gmcp.room or not gmcp.room.info then return nil end
    return gmcp.room.info.area
end

function f2t_get_current_room_num()
    if not gmcp or not gmcp.room or not gmcp.room.info then return nil end
    return gmcp.room.info.num
end

function f2t_get_current_room_hash()
    if not gmcp or not gmcp.room or not gmcp.room.info then return nil end
    local info = gmcp.room.info
    if not info.system or not info.area or not info.num then return nil end
    return string.format("%s.%s.%s", info.system, info.area, info.num)
end

function f2t_map_get_current_cartel()
    if F2T_MAP_CURRENT_ROOM_ID then
        local area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
        if area_id then
            local cartel = getAreaUserData(area_id, "fed2_cartel")
            if cartel and cartel ~= "" then return cartel end
        end
    end
    if gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.cartel then
        return gmcp.room.info.cartel
    end
    return nil
end

function f2t_has_room_flag(flag)
    if not gmcp or not gmcp.room or not gmcp.room.info or not gmcp.room.info.flags then
        return false
    end
    return f2t_has_value(gmcp.room.info.flags, flag)
end

function f2t_is_in_system(system_name)
    return f2t_get_current_system() == system_name
end

function f2t_is_at_planet(planet_name)
    return f2t_get_current_planet() == planet_name
end

function f2t_map_lookup_planet(planet_name)
    local area_id = f2t_map_get_area_id(planet_name)
    if not area_id then return nil end
    local area_rooms = getAreaRooms(area_id)
    if area_rooms then
        local sample_room = area_rooms[0] or area_rooms[1] or area_rooms[next(area_rooms)]
        if sample_room then
            local system = getRoomUserData(sample_room, "fed2_system")
            return {name = planet_name, system = system}
        end
    end
    return {name = planet_name}
end

function f2t_map_lookup_system(system_name)
    local space_area = f2t_map_get_system_space_area_actual(system_name)
    if space_area then return {name = system_name} end
    return nil
end

f2t_debug_log("[map] Map helper functions initialized")
