-- f2ce-tools map — Layer 3 cartel exploration (ported from map_explore_cartel.lua)
--
-- Captures the system list from "display cartel <name>", then explores each
-- system (brief mode) via Layer 2. Runs standalone (mode="cartel") or nested
-- under galaxy/syndicate exploration. Travel between systems uses the
-- topology model's jump chains, which are legal under syndicate beacon rules
-- wherever the chain starts.

F2T_MAP_EXPLORE_CARTEL_CAPTURE = F2T_MAP_EXPLORE_CARTEL_CAPTURE or {
    active = false, cartel_name = nil, lines = {}, in_members = false, timer_id = nil,
}

function f2t_map_explore_cartel_start(cartel_name, on_complete_callback)
    if not on_complete_callback and F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n")
        return false
    end
    if not cartel_name or cartel_name == "" then
        cecho("\n<red>[map-explore]<reset> Error: No cartel specified\n")
        return false
    end

    cartel_name = cartel_name:gsub("^%l", string.upper)

    cecho(string.format("\n<green>[map-explore]<reset> Starting cartel exploration: <white>%s<reset>\n", cartel_name))
    cecho("  <dim_grey>Capturing system list...<reset>\n")

    if on_complete_callback then
        -- Nested under galaxy/syndicate: preserve parent mode and state.
        F2T_MAP_EXPLORE_STATE.cartel_name = cartel_name
        F2T_MAP_EXPLORE_STATE.system_list = {}
        F2T_MAP_EXPLORE_STATE.current_system_index = 0
        F2T_MAP_EXPLORE_STATE.cartel_stats = {
            total_systems = 0, systems_explored = 0,
            total_planets = 0, total_exchanges = 0, total_planets_skipped = 0,
        }
        F2T_MAP_EXPLORE_STATE.cartel_complete_callback = on_complete_callback
    else
        f2t_map_set_nav_owner("map-explore", function(reason)
            if reason == "customs" then
                F2T_MAP_EXPLORE_STATE.paused = true
                F2T_MAP_EXPLORE_STATE.paused_reason = reason
            end
            return {auto_resume = true}
        end)
        if f2t_stamina_register_client then
            f2t_stamina_register_client({
                pause_callback  = f2t_map_explore_pause,
                resume_callback = f2t_map_explore_resume,
                check_active = function()
                    return F2T_MAP_EXPLORE_STATE.active and not F2T_MAP_EXPLORE_STATE.paused
                end,
            })
        end

        F2T_MAP_EXPLORE_STATE.active = true
        F2T_MAP_EXPLORE_STATE.mode = "cartel"
        F2T_MAP_EXPLORE_STATE.cartel_name = cartel_name
        F2T_MAP_EXPLORE_STATE.system_list = {}
        F2T_MAP_EXPLORE_STATE.current_system_index = 0
        F2T_MAP_EXPLORE_STATE.starting_room_id = F2T_MAP_CURRENT_ROOM_ID
        F2T_MAP_EXPLORE_STATE.cartel_stats = {
            total_systems = 0, systems_explored = 0,
            total_planets = 0, total_exchanges = 0, total_planets_skipped = 0,
        }
        F2T_MAP_EXPLORE_STATE.cartel_complete_callback = nil
        f2t_map_explore_brief_mode_start()
    end

    f2t_map_explore_cartel_capture_start(cartel_name)
    return true
end

function f2t_map_explore_cartel_capture_start(cartel_name)
    F2T_MAP_EXPLORE_CARTEL_CAPTURE = {
        active = true, cartel_name = cartel_name, lines = {}, in_members = false, timer_id = nil,
    }
    send(string.format("display cartel %s", cartel_name), false)
    f2t_map_explore_cartel_reset_timer()
end

function f2t_map_explore_cartel_reset_timer()
    if F2T_MAP_EXPLORE_CARTEL_CAPTURE.timer_id then
        killTimer(F2T_MAP_EXPLORE_CARTEL_CAPTURE.timer_id)
    end
    F2T_MAP_EXPLORE_CARTEL_CAPTURE.timer_id = tempTimer(0.5, function()
        if F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
            f2t_map_explore_cartel_capture_complete()
        end
    end)
end

function f2t_map_explore_cartel_capture_complete()
    local system_names = F2T_MAP_EXPLORE_CARTEL_CAPTURE.lines
    local cartel_name = F2T_MAP_EXPLORE_CARTEL_CAPTURE.cartel_name
    F2T_MAP_EXPLORE_CARTEL_CAPTURE = {active = false}

    if #system_names == 0 then
        cecho(string.format("\n<red>[map-explore]<reset> No systems found for cartel '%s'\n", cartel_name))
        f2t_map_explore_cartel_abort()
        return
    end

    -- The roster is the authoritative accepted-member list: feed the model.
    local topology_changed = false
    for _, system_name in ipairs(system_names) do
        if F2T_MAP_TOPOLOGY.systems[system_name] ~= cartel_name then
            F2T_MAP_TOPOLOGY.systems[system_name] = cartel_name
            topology_changed = true
        end
    end
    if topology_changed then
        if F2T_MAP_TOPOLOGY.cartels[cartel_name] == nil then
            F2T_MAP_TOPOLOGY.cartels[cartel_name] = false
        end
        f2t_map_topology_save()
        f2t_map_topology_request_rebuild()
    end

    table.sort(system_names, function(a, b)
        if a == cartel_name then return true end
        if b == cartel_name then return false end
        return a < b
    end)

    F2T_MAP_EXPLORE_STATE.system_list = system_names
    F2T_MAP_EXPLORE_STATE.cartel_stats.total_systems = #system_names

    cecho(string.format("  <green>Found %d system(s) to explore<reset>\n\n", #system_names))
    f2t_map_explore_cartel_next_system()
end

function f2t_map_explore_cartel_next_system()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local mode = F2T_MAP_EXPLORE_STATE.mode
    if mode ~= "cartel" and mode ~= "galaxy" then return end
    if f2t_map_explore_check_deferred_pause() then return end

    F2T_MAP_EXPLORE_STATE.current_system_index = F2T_MAP_EXPLORE_STATE.current_system_index + 1
    local index = F2T_MAP_EXPLORE_STATE.current_system_index
    local systems = F2T_MAP_EXPLORE_STATE.system_list

    if index > #systems then
        if F2T_MAP_EXPLORE_STATE.cartel_complete_callback then
            local callback = F2T_MAP_EXPLORE_STATE.cartel_complete_callback
            F2T_MAP_EXPLORE_STATE.cartel_complete_callback = nil
            callback()
            return
        end
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
        return
    end

    local system_name = systems[index]
    cecho(string.format("\n<green>[map-explore]<reset> System %d/%d: <white>%s<reset>\n",
        index, #systems, system_name))

    if f2t_map_explore_is_system_fully_mapped(system_name) then
        cecho("  <green>System already fully mapped, skipping<reset>\n")
        F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored =
            F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1
        f2t_map_explore_cartel_next_system()
        return
    end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local current_system = current_room and getRoomUserData(current_room, "fed2_system")

    if current_system == system_name then
        local space_area_name = f2t_map_get_system_space_area_actual(system_name)
        local space_area_id = space_area_name and f2t_map_get_area_id(space_area_name)
        if space_area_id and getRoomArea(current_room) == space_area_id then
            F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored =
                F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1
            f2t_map_explore_cartel_start_system_mode(system_name)
        else
            -- In the right system but on a planet: get to its space link first.
            cecho(string.format("  <dim_grey>Navigating to %s space...<reset>\n", system_name))
            F2T_MAP_EXPLORE_STATE.cartel_target_system = system_name
            F2T_MAP_EXPLORE_STATE.phase = "arriving_in_system"
            if not f2t_map_navigate(system_name .. " Space link") then
                cecho(string.format("  <red>Error:<reset> Cannot navigate to %s space link, skipping\n", system_name))
                F2T_MAP_EXPLORE_STATE.phase = nil
                F2T_MAP_EXPLORE_STATE.cartel_target_system = nil
                f2t_map_explore_cartel_next_system()
            end
        end
        return
    end

    -- Different system: navigate to the current system's link, then jump.
    -- The topology jump chain handles cross-cartel/cross-syndicate legality.
    cecho(string.format("  <dim_grey>Navigating to link and jumping to %s<reset>\n", system_name))
    F2T_MAP_EXPLORE_STATE.cartel_target_system = system_name

    local link_destination = current_system and (current_system .. " Space link") or "link"
    if not f2t_map_navigate(link_destination) then
        cecho("  <red>Error:<reset> Cannot navigate to link, skipping system\n")
        F2T_MAP_EXPLORE_STATE.cartel_target_system = nil
        f2t_map_explore_cartel_next_system()
        return
    end

    if current_room and f2t_map_room_has_flag(current_room, "link") then
        f2t_map_explore_jump_to_system(system_name)
    else
        F2T_MAP_EXPLORE_STATE.phase = "jumping_to_system"
    end
end

-- Issue the blind jump chain toward a target system from the link room we
-- are standing in. Falls back to a single direct jump when the model can't
-- build a chain (it may still be legal, e.g. same cartel not yet modeled).
function f2t_map_explore_jump_to_system(target_system)
    local current_system = f2t_get_current_system()
    local chain = current_system and f2t_map_topology_jump_chain(current_system, target_system)
    if not chain or #chain == 0 then
        chain = {string.format("jump %s", target_system)}
    end
    cecho(string.format("  <dim_grey>Jumping: %s<reset>\n", table.concat(chain, "; ")))
    speedWalkDir = chain
    speedWalkPath = {}
    doSpeedWalk()
    F2T_MAP_EXPLORE_STATE.phase = "arriving_in_system"
end

function f2t_map_explore_cartel_start_system_mode(system_name)
    local success = f2t_map_explore_system_start(system_name, "brief", function()
        f2t_map_explore_cartel_next_system()
    end)
    if not success then
        cecho(string.format("  <red>Error:<reset> System exploration failed to start for %s\n", system_name))
        f2t_map_explore_cartel_next_system()
    end
end

function f2t_map_explore_cartel_abort()
    if F2T_MAP_EXPLORE_STATE.cartel_complete_callback then
        local callback = F2T_MAP_EXPLORE_STATE.cartel_complete_callback
        F2T_MAP_EXPLORE_STATE.cartel_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.cartel_name = nil
        F2T_MAP_EXPLORE_STATE.system_list = {}
        F2T_MAP_EXPLORE_STATE.current_system_index = 0
        callback()
        return
    end
    f2t_map_clear_nav_owner()
    if f2t_stamina_unregister_client then f2t_stamina_unregister_client() end
    f2t_map_explore_brief_mode_restore()
    F2T_MAP_EXPLORE_STATE.active = false
    F2T_MAP_EXPLORE_STATE.mode = nil
    F2T_MAP_EXPLORE_STATE.cartel_name = nil
    F2T_MAP_EXPLORE_STATE.system_list = {}
    F2T_MAP_EXPLORE_STATE.current_system_index = 0
end

f2t_debug_log("[map] Loaded explore_cartel.lua")
