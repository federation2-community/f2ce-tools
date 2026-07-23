-- f2ce-tools map — Layer 4 galaxy/syndicate exploration (ported from map_explore_galaxy.lua)
--
-- Galaxy mode explores every cartel in the galaxy; syndicate mode explores
-- only the cartels of one syndicate. Both start with a topology sync
-- ("display cartels" + "display syndicates"), which supplies the cartel list
-- AND brings the jump model current before any travel. Travel between cartels
-- uses topology jump chains, legal under syndicate beacon rules.

function f2t_map_explore_galaxy_start()
    return f2t_map_explore_galaxy_begin(nil)
end

function f2t_map_explore_syndicate_start(syndicate_name)
    if not syndicate_name or syndicate_name == "" then
        -- Default to the syndicate we are standing in, if the model knows it.
        f2t_map_topology_ensure_loaded()
        local cartel = f2t_map_get_current_cartel()
        local syndicate = cartel and F2T_MAP_TOPOLOGY.cartels[cartel]
        if type(syndicate) ~= "string" then
            cecho("\n<red>[map-explore]<reset> No syndicate specified and current syndicate unknown\n")
            cecho("<dim_grey>Usage: map explore syndicate <name>  (or run 'map topology sync' first)<reset>\n")
            return false
        end
        syndicate_name = syndicate
    end
    syndicate_name = syndicate_name:gsub("^%l", string.upper)
    return f2t_map_explore_galaxy_begin(syndicate_name)
end

function f2t_map_explore_galaxy_begin(syndicate_filter)
    if F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[map-explore]<reset> Exploration already in progress\n")
        return false
    end

    if syndicate_filter then
        cecho(string.format(
            "\n<green>[map-explore]<reset> Starting syndicate exploration: <white>%s<reset>\n", syndicate_filter))
    else
        cecho("\n<green>[map-explore]<reset> Starting galaxy exploration\n")
    end
    cecho("  <dim_grey>Syncing galaxy topology...<reset>\n")

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
    F2T_MAP_EXPLORE_STATE.mode = "galaxy"
    F2T_MAP_EXPLORE_STATE.starting_room_id = F2T_MAP_CURRENT_ROOM_ID
    F2T_MAP_EXPLORE_STATE.galaxy_cartel_list = {}
    F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index = 0
    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
    F2T_MAP_EXPLORE_STATE.galaxy_syndicate_filter = syndicate_filter
    F2T_MAP_EXPLORE_STATE.galaxy_stats = {
        total_cartels = 0, cartels_explored = 0, cartels_skipped = 0,
        total_systems = 0, total_planets = 0,
    }
    f2t_map_explore_brief_mode_start()

    local sync_started = f2t_map_topology_sync(function(ok)
        if not F2T_MAP_EXPLORE_STATE.active or F2T_MAP_EXPLORE_STATE.mode ~= "galaxy" then return end
        if not ok then
            cecho("\n<red>[map-explore]<reset> Topology sync failed, cannot enumerate cartels\n")
            f2t_map_explore_galaxy_abort()
            return
        end
        f2t_map_explore_galaxy_build_cartel_list()
    end)
    if not sync_started then
        f2t_map_explore_galaxy_abort()
        return false
    end
    return true
end

function f2t_map_explore_galaxy_build_cartel_list()
    local filter = F2T_MAP_EXPLORE_STATE.galaxy_syndicate_filter
    local cartel_names = {}
    for cartel, syndicate in pairs(F2T_MAP_TOPOLOGY.cartels) do
        if not filter or syndicate == filter then
            table.insert(cartel_names, cartel)
        end
    end

    if #cartel_names == 0 then
        if filter then
            cecho(string.format("\n<red>[map-explore]<reset> No cartels found in the %s syndicate\n", filter))
        else
            cecho("\n<red>[map-explore]<reset> No cartels found\n")
        end
        f2t_map_explore_galaxy_abort()
        return
    end

    -- Alphabetical, but start with the cartel we are already in (no travel).
    table.sort(cartel_names)
    local current_cartel = f2t_map_get_current_cartel()
    if current_cartel then
        for i, name in ipairs(cartel_names) do
            if name:lower() == current_cartel:lower() then
                table.remove(cartel_names, i)
                table.insert(cartel_names, 1, name)
                break
            end
        end
    end

    F2T_MAP_EXPLORE_STATE.galaxy_cartel_list = cartel_names
    F2T_MAP_EXPLORE_STATE.galaxy_stats.total_cartels = #cartel_names
    cecho(string.format("  <green>Found %d cartel(s) to explore<reset>\n\n", #cartel_names))
    f2t_map_explore_galaxy_next_cartel()
end

function f2t_map_explore_galaxy_next_cartel()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.mode ~= "galaxy" then return end
    if f2t_map_explore_check_deferred_pause() then return end

    F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index = F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index + 1
    local index = F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index
    local cartels = F2T_MAP_EXPLORE_STATE.galaxy_cartel_list

    if index > #cartels then
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
        return
    end

    local cartel_name = cartels[index]
    cecho(string.format("\n<green>[map-explore]<reset> Cartel %d/%d: <white>%s<reset>\n",
        index, #cartels, cartel_name))

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local current_cartel = f2t_map_get_current_cartel()

    if current_cartel and current_cartel:lower() == cartel_name:lower() then
        F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored =
            F2T_MAP_EXPLORE_STATE.galaxy_stats.cartels_explored + 1
        f2t_map_explore_galaxy_start_cartel_mode(cartel_name)
        return
    end

    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = cartel_name

    -- Any link room works as a jump chain start; use the current system's.
    local current_system = current_room and getRoomUserData(current_room, "fed2_system")
    if current_room and f2t_map_room_has_flag(current_room, "link") then
        f2t_map_explore_jump_to_cartel(cartel_name)
        return
    end

    local link_destination = current_system and (current_system .. " Space link") or "link"
    cecho(string.format("  <dim_grey>Navigating to link to jump to %s<reset>\n", cartel_name))
    if not f2t_map_navigate(link_destination) then
        cecho(string.format("  <red>Error:<reset> Cannot navigate to a link room, skipping %s\n", cartel_name))
        F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
        f2t_map_explore_galaxy_next_cartel()
        return
    end
    F2T_MAP_EXPLORE_STATE.phase = "jumping_to_cartel"
end

-- Issue the blind jump chain toward a target cartel's hub system from the
-- link room we are standing in.
function f2t_map_explore_jump_to_cartel(target_cartel)
    local current_system = f2t_get_current_system()
    local chain = current_system and f2t_map_topology_jump_chain(current_system, target_cartel)
    if not chain or #chain == 0 then
        chain = {string.format("jump %s", target_cartel)}
    end
    cecho(string.format("  <dim_grey>Jumping: %s<reset>\n", table.concat(chain, "; ")))
    speedWalkDir = chain
    speedWalkPath = {}
    doSpeedWalk()
    F2T_MAP_EXPLORE_STATE.phase = "arriving_in_cartel"
end

function f2t_map_explore_galaxy_start_cartel_mode(cartel_name)
    local success = f2t_map_explore_cartel_start(cartel_name, function()
        f2t_map_explore_galaxy_cartel_complete()
    end)
    if not success then
        cecho(string.format("  <red>Error:<reset> Cartel exploration failed to start for %s\n", cartel_name))
        f2t_map_explore_galaxy_next_cartel()
    end
end

function f2t_map_explore_galaxy_cartel_complete()
    local cartel_stats = F2T_MAP_EXPLORE_STATE.cartel_stats
    if cartel_stats then
        F2T_MAP_EXPLORE_STATE.galaxy_stats.total_systems =
            F2T_MAP_EXPLORE_STATE.galaxy_stats.total_systems + (cartel_stats.total_systems or 0)
        F2T_MAP_EXPLORE_STATE.galaxy_stats.total_planets =
            F2T_MAP_EXPLORE_STATE.galaxy_stats.total_planets + (cartel_stats.total_planets or 0)
    end
    f2t_map_explore_galaxy_next_cartel()
end

function f2t_map_explore_galaxy_abort()
    f2t_map_clear_nav_owner()
    if f2t_stamina_unregister_client then f2t_stamina_unregister_client() end
    f2t_map_explore_brief_mode_restore()
    F2T_MAP_EXPLORE_STATE.active = false
    F2T_MAP_EXPLORE_STATE.mode = nil
    F2T_MAP_EXPLORE_STATE.galaxy_cartel_list = {}
    F2T_MAP_EXPLORE_STATE.galaxy_current_cartel_index = 0
    F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
    F2T_MAP_EXPLORE_STATE.galaxy_syndicate_filter = nil
end

f2t_debug_log("[map] Loaded explore_galaxy.lua")
