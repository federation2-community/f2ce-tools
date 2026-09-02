-- f2ce-tools map — Layer 3 cartel exploration (ported from map_explore_cartel.lua)
--
-- Captures the system list from "display cartel <name>", then explores each
-- system (brief mode) via Layer 2. Runs standalone (mode="cartel") or nested
-- under galaxy/syndicate exploration. Travel between systems uses the
-- topology model's jump chains, which are legal under syndicate beacon rules
-- wherever the chain starts.

F2T_MAP_EXPLORE_CARTEL_CAPTURE = F2T_MAP_EXPLORE_CARTEL_CAPTURE or {
    active = false, cartel_name = nil, lines = {}, in_members = false,
}

function f2t_map_explore_cartel_start(cartel_name, on_complete_callback)
    if not on_complete_callback and F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n")
        return false
    end

    if not cartel_name or cartel_name == "" then
        -- Default to the cartel we are standing in, if detectable.
        cartel_name = f2t_map_get_current_cartel()
    end
    if not cartel_name or cartel_name == "" then
        cecho("\n<red>[map-explore]<reset> Error: No cartel specified and couldn't detect current cartel\n")
        cecho("<dim_grey>Usage: map explore cartel <cartel><reset>\n")
        return false
    end

    cartel_name = cartel_name:gsub("^%l", string.upper)

    -- A standalone run (typed directly, or the Galaxy Navigator's dot click -
    -- both just expand to this same call) can be a long, many-system sweep
    -- from a single click with no chance to back out. A cartel nested under
    -- a syndicate/galaxy sweep already got its one confirmation at that
    -- larger run's own start and shouldn't ask again per cartel.
    if not on_complete_callback and f2tShowExploreScopeConfirm then
        f2tShowExploreScopeConfirm("cartel", cartel_name,
            function() f2t_map_explore_cartel_start_confirmed(cartel_name, on_complete_callback) end,
            function() cecho("\n<yellow>[map-explore]<reset> Cartel exploration cancelled\n") end)
        return true
    end

    return f2t_map_explore_cartel_start_confirmed(cartel_name, on_complete_callback)
end

function f2t_map_explore_cartel_start_confirmed(cartel_name, on_complete_callback)
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
        f2t_map_explore_register_safety_hooks()

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
    f2t_capture_close("cartel_roster")
    F2T_MAP_EXPLORE_CARTEL_CAPTURE = {
        active = true, cartel_name = cartel_name, lines = {}, in_members = false,
    }
    send(string.format("display cartel %s", cartel_name), false)
    f2t_map_explore_cartel_reset_timer()
end

function f2t_map_explore_cartel_reset_timer()
    f2t_capture_arm("cartel_roster", function()
        if F2T_MAP_EXPLORE_CARTEL_CAPTURE.active then
            f2t_map_explore_cartel_capture_complete()
        end
    end)
end

function f2t_map_explore_cartel_capture_complete()
    local system_names = F2T_MAP_EXPLORE_CARTEL_CAPTURE.lines
    local cartel_name = F2T_MAP_EXPLORE_CARTEL_CAPTURE.cartel_name
    f2t_capture_close("cartel_roster")
    F2T_MAP_EXPLORE_CARTEL_CAPTURE = {active = false}

    if #system_names == 0 then
        cecho(string.format("\n<red>[map-explore]<reset> No systems found for cartel '%s'\n", cartel_name))
        f2t_map_explore_cartel_abort()
        return
    end

    -- The roster is the authoritative accepted-member list: feed the model.
    local topology_changed = false
    for _, system_name in ipairs(system_names) do
        if f2t_map_topology_learn(system_name, cartel_name, nil) then topology_changed = true end
    end
    f2t_map_topology_commit(topology_changed)

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

    -- No travel here (there used to be one): f2t_map_explore_system_start
    -- below already owns the whole decision, checking against a freshly
    -- captured 'di system' roster (not a local-only guess - see the fix in
    -- f2t_map_explore_is_system_fully_mapped for why a local check can be
    -- blind to a planet with zero rooms at all) before it ever travels, and
    -- skips travelling entirely when every expected planet is already
    -- mapped, reachable, and fully flagged. Jumping first here, like the
    -- old code did, would burn the travel on every system regardless,
    -- since by the time system_start got a look the sweep had already
    -- arrived.
    f2t_map_explore_cartel_start_system_mode(system_name)
end

function f2t_map_explore_cartel_start_system_mode(system_name)
    F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored =
        F2T_MAP_EXPLORE_STATE.cartel_stats.systems_explored + 1
    local success = f2t_map_explore_system_start("brief", system_name, function()
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
