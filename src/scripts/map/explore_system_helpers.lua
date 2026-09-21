-- f2ce-tools map — system exploration helpers (ported from map_explore_system_helpers.lua)

local function normalized_planet_name(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name:lower()
end

local function expected_planet_name(observed_name)
    local observed_key = normalized_planet_name(observed_name)
    if not observed_key then return nil end
    for name in pairs(F2T_MAP_EXPLORE_STATE.expected_planets or {}) do
        if normalized_planet_name(name) == observed_key then return name end
    end
    return nil
end

local function live_orbit_planet(room_id)
    if room_id ~= F2T_MAP_CURRENT_ROOM_ID then return nil end
    local room_info = gmcp and gmcp.room and gmcp.room.info
    local orbit_hash = room_info and room_info.orbit
    if type(orbit_hash) ~= "string" then return nil end
    -- The first and final fields are system and room number; retain the
    -- complete middle field so a valid area name containing a dot survives.
    return orbit_hash:match("^[^.]+%.(.+)%.%-?%d+$")
end

function f2t_map_explore_system_check_room_for_planets(room_id)
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.system_mode ~= "brief" and
       F2T_MAP_EXPLORE_STATE.system_mode ~= "full" then return end
    if F2T_MAP_EXPLORE_STATE.system_phase ~= "exploring_space" then return end
    if not F2T_MAP_EXPLORE_STATE.expected_planets or not F2T_MAP_EXPLORE_STATE.expected_planets_remaining then
        return
    end

    local observed_name = getRoomUserData(room_id, "fed2_planet")
    if not observed_name or observed_name == "" then
        observed_name = live_orbit_planet(room_id)
        if observed_name then
            -- The live `orbit` field is authoritative.  Repair the room too,
            -- because Phase 2 resolves the discovered orbit from this same
            -- userdata after the frontier sweep finishes.
            setRoomUserData(room_id, "fed2_planet", observed_name)
            setRoomUserData(room_id, "fed2_flag_orbit", "true")
        end
    end
    local planet_name = expected_planet_name(observed_name)
    if not planet_name then return end

    F2T_MAP_EXPLORE_STATE.expected_planets_found =
        F2T_MAP_EXPLORE_STATE.expected_planets_found or {}
    if not F2T_MAP_EXPLORE_STATE.expected_planets_found[planet_name] then
        F2T_MAP_EXPLORE_STATE.expected_planets_found[planet_name] = true
        F2T_MAP_EXPLORE_STATE.expected_planets_remaining =
            math.max(0, F2T_MAP_EXPLORE_STATE.expected_planets_remaining - 1)
        cecho(string.format("  <green>✓<reset> Found orbit for expected planet: <yellow>%s<reset>\n", planet_name))
        if F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 and
           F2T_MAP_EXPLORE_STATE.system_mode == "brief" then
            cecho("\n<green>[map-explore]<reset> All expected planets found! Space exploration complete.\n\n")
            F2T_MAP_EXPLORE_STATE.frontier_stack = {}
            f2t_map_explore_system_space_complete()
            return
        end
    end
end

f2t_debug_log("[map] Loaded explore_system_helpers.lua")
