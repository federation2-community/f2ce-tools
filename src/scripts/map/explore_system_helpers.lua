-- f2ce-tools map — system exploration helpers (ported from map_explore_system_helpers.lua)

function f2t_map_explore_system_check_room_for_planets(room_id)
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if not F2T_MAP_EXPLORE_STATE.system_mode or F2T_MAP_EXPLORE_STATE.system_mode ~= "brief" then return end
    if F2T_MAP_EXPLORE_STATE.system_phase ~= "exploring_space" then return end
    if not F2T_MAP_EXPLORE_STATE.expected_planets or not F2T_MAP_EXPLORE_STATE.expected_planets_remaining then return end

    local planet_name = getRoomUserData(room_id, "fed2_planet")
    if not planet_name or planet_name == "" then return end

    if F2T_MAP_EXPLORE_STATE.expected_planets[planet_name] then
        if not F2T_MAP_EXPLORE_STATE.expected_planets_found[planet_name] then
            F2T_MAP_EXPLORE_STATE.expected_planets_found[planet_name] = true
            F2T_MAP_EXPLORE_STATE.expected_planets_remaining = F2T_MAP_EXPLORE_STATE.expected_planets_remaining - 1
            cecho(string.format("  <green>✓<reset> Found orbit for expected planet: <yellow>%s<reset>\n", planet_name))
            if F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 then
                cecho("\n<green>[map-explore]<reset> All expected planets found! Space exploration complete.\n\n")
                F2T_MAP_EXPLORE_STATE.frontier_stack = {}
                f2t_map_explore_system_space_complete()
                return
            end
        end
    end
end

f2t_debug_log("[map] Loaded explore_system_helpers.lua")
