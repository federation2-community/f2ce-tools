-- f2ce-tools map — Layer 2 system exploration (ported from map_explore_system.lua)
--
-- Two phases: explore "{System} Space" (delegates to Layer 1), then brief
-- exploration of each discovered planet. Runs standalone (mode="system") or
-- nested under cartel/galaxy exploration (parent mode preserved, callback
-- chains back up).

-- Systems whose space was just reset and re-explored via the "Exploration
-- Incomplete" dialog, so the completion handler below can tell a fresh gap
-- from one that already survived a full reset. Checking again would just
-- offer the same dialog forever if the gap is genuinely unfixable client-
-- side (a planet with no server-side route at all) - each entry is cleared
-- the moment it's checked, so it only suppresses the one completion right
-- after a reset, never a later, independent run.
F2T_MAP_EXPLORE_JUST_RESET = F2T_MAP_EXPLORE_JUST_RESET or {}

function f2t_map_explore_system_start(system_mode, system_name, on_complete_callback)
    if not system_name or system_name == "" then
        -- Default to the system we are standing in, if detectable.
        system_name = f2t_get_current_system()
    end
    if not system_name or system_name == "" then
        cecho("\n<red>[map-explore]<reset> Error: No system specified and couldn't detect current system\n")
        cecho("<dim_grey>Usage: map explore system <system><reset>\n")
        return false
    end

    system_mode = string.lower(system_mode or "brief")
    if system_mode ~= "full" and system_mode ~= "brief" then
        cecho(string.format("\n<red>[map-explore]<reset> Error: Invalid system mode '%s'\n", system_mode))
        return false
    end
    if on_complete_callback and system_mode ~= "brief" then
        system_mode = "brief"
    end

    system_name = system_name:gsub("^%l", string.upper)

    if system_mode == "brief" then
        cecho(string.format(
            "\n<green>[map-explore]<reset> Starting system exploration: <white>%s<reset> (<cyan>brief mode<reset>)\n",
            system_name))
        cecho("  <dim_grey>Capturing expected planet list...<reset>\n")
        f2t_map_di_system_capture_start(system_name,
            function(expected_planet_names, planets_without_exchange, no_such_system)
                -- The game says there is no such star system. Sweeping "space"
                -- for it would only walk to a link room and jump at a name
                -- that does not exist, so stop while it is still cheap.
                if no_such_system then
                    cecho(string.format(
                        "\n<red>[map-explore]<reset> There is no star system called '%s'\n", system_name))
                    if on_complete_callback then on_complete_callback() end
                    return
                end
                f2t_map_explore_system_start_with_planets(system_mode, system_name,
                    expected_planet_names, planets_without_exchange, on_complete_callback)
            end)
        return true
    end

    f2t_map_explore_system_start_with_planets(system_mode, system_name, nil, nil, on_complete_callback)
    return true
end

function f2t_map_explore_system_start_with_planets(system_mode, system_name, expected_planet_names,
                                                   planets_without_exchange, on_complete_callback)
    local expected_planets_set = nil
    local expected_planets_found_set = nil
    local expected_planets_remaining_count = nil
    local current_room = F2T_MAP_CURRENT_ROOM_ID

    if system_mode == "brief" and expected_planet_names then
        if #expected_planet_names == 0 then
            cecho(string.format("\n<yellow>[map-explore]<reset> No planets found in %s via DI system\n", system_name))
            cecho("<dim_grey>Falling back to full space exploration<reset>\n")
            system_mode = "full"
        else
            expected_planets_set = {}
            expected_planets_found_set = {}
            for _, planet_name in ipairs(expected_planet_names) do
                expected_planets_set[planet_name] = true
            end

            -- A room bearing this planet's name only counts as "already
            -- mapped" if it is actually reachable from here. A Dyson Sphere
            -- (or similar) rebuild can renumber a system's whole space area
            -- and leave a planet's old orbit room stranded - still carrying
            -- its fed2_planet userdata, but disconnected from everything
            -- live. f2t_map_find_orbit_room already prefers a reachable
            -- candidate over a stale one; still verify what it returns,
            -- since with no reachable candidate at all it falls back to
            -- returning the stale one anyway.
            local space_area_check = f2t_map_get_system_space_area_actual(system_name)
            local known_count = 0
            if space_area_check then
                for planet_name in pairs(expected_planets_set) do
                    local orbit_room = f2t_map_find_orbit_room(space_area_check, planet_name)
                    if orbit_room and current_room
                       and (orbit_room == current_room or getPath(current_room, orbit_room)) then
                        expected_planets_found_set[planet_name] = true
                        known_count = known_count + 1
                    end
                end
            end
            expected_planets_remaining_count = #expected_planet_names - known_count

            cecho(string.format("  <green>Found %d expected planet(s)<reset>\n", #expected_planet_names))
            if known_count > 0 then
                cecho(string.format("  <cyan>Already mapped:<reset> %d planet(s)\n", known_count))
            end

            -- Every expected planet is already known and reachable from here
            -- - checked now, before any travel decision, using the same DI
            -- system list just captured, not a local-only guess. If their
            -- surfaces are also fully explored there is nothing to travel
            -- for at all: this is what lets a cartel/galaxy sweep skip a
            -- genuinely complete system without physically visiting it,
            -- without falling back into the old bug where a local-only
            -- heuristic guessed "done" from whatever few planets it already
            -- had data on and silently ignored the rest.
            if expected_planets_remaining_count == 0 then
                local required_flags = f2t_map_explore_strip_courier_outside_sol(
                    f2t_map_explore_default_required_flags(), system_name)
                local fully_explored = true
                for planet_name in pairs(expected_planets_found_set) do
                    local planet_area_id = f2t_map_get_area_id(planet_name)
                    if not planet_area_id
                       or not f2t_map_explore_planet_has_flags(planet_area_id, required_flags) then
                        fully_explored = false
                        break
                    end
                end
                if fully_explored then
                    cecho(string.format(
                        "\n<green>[map-explore]<reset> %s is already fully explored - nothing to do\n",
                        system_name))
                    if on_complete_callback then on_complete_callback() end
                    return true
                end
            end
        end
    end

    local space_area_name = f2t_map_get_system_space_area_actual(system_name)
    local space_area_id = space_area_name and f2t_map_get_area_id(space_area_name)
    local current_area = current_room and getRoomArea(current_room)

    -- Computed once up front (not re-derived per branch below) so a standalone
    -- call is recognized the same way whether or not it needs to travel first,
    -- and so the completion cleanup wrapped onto on_complete_callback just
    -- below only ever fires for the call that actually flipped .active on.
    local started_standalone = not F2T_MAP_EXPLORE_STATE.active
    if started_standalone and on_complete_callback then
        on_complete_callback = f2t_map_explore_wrap_release(on_complete_callback)
    end

    -- Not there yet: travel first, then retry with the same (already-captured)
    -- expected-planet data rather than repeating the DI system capture.
    if not space_area_id or current_area ~= space_area_id then
        -- The travel dispatcher (explore.lua's gmcp.room.info handler) only
        -- runs while F2T_MAP_EXPLORE_STATE.active is true; a nested call
        -- already has that (and its own safety hooks) from the parent sweep,
        -- but a standalone call hasn't started yet, so ensure both here too.
        if started_standalone then f2t_map_explore_claim_run("system") end

        local function retry()
            f2t_map_explore_system_start_with_planets(system_mode, system_name,
                expected_planet_names, planets_without_exchange, on_complete_callback)
        end
        local function give_up()
            cecho(string.format("\n<red>[map-explore]<reset> Could not reach %s\n", system_name))
            -- Only tear down if we set active ourselves; a nested call must
            -- leave the parent sweep's state alone so it can move on.
            if started_standalone then
                f2t_map_explore_release_run()
                f2t_map_explore_brief_mode_restore()
                F2T_MAP_EXPLORE_STATE.mode = nil
            end
        end

        if space_area_id then
            -- Navigate by room ID within the already-resolved space area, not by
            -- re-guessing system_name through the generic name resolver - a
            -- system name can collide with an unrelated planet of the same name
            -- elsewhere in the galaxy, and that resolver checks planets first.
            local target_room_id = f2t_map_area_entry_room(space_area_id)
            cecho(string.format("\n<green>[map-explore]<reset> Navigating to %s...\n", space_area_name))
            f2t_map_explore_await_arrival("system", system_name, retry, give_up)
            local nav_result = target_room_id and f2t_map_navigate(tostring(target_room_id))
            -- A plain point-to-point path can miss a route that only exists by
            -- jumping (the destination system is already mapped, just not
            -- connected to here by ordinary exits) - fall back to the
            -- jump-capable travel path instead of stalling. nav_result is a
            -- status string ("failed"/"walking"/"arrived"), never nil, so the
            -- previous `== nil` check here never actually fired.
            if not f2t_map_navigate_ok(nav_result) then
                cecho(string.format(
                    "  <dim_grey>No direct path to %s - trying to jump there instead<reset>\n", space_area_name))
                f2t_map_explore_travel_to("system", system_name, retry, give_up)
            end
        else
            cecho(string.format("\n<green>[map-explore]<reset> %s not yet mapped, traveling there...\n", system_name))
            f2t_map_explore_travel_to("system", system_name, retry, give_up)
        end
        return true
    end

    if system_mode == "full" then
        cecho(string.format(
            "\n<green>[map-explore]<reset> Starting system exploration: <white>%s<reset> (<cyan>full mode<reset>)\n",
            system_name))
        cecho(string.format("  <dim_grey>Phase 1: Exploring entire %s area<reset>\n", space_area_name))
    else
        cecho(string.format("  <dim_grey>Phase 1: Exploring %s to find expected planets<reset>\n", space_area_name))
    end

    local system_stats = {
        total_planets = 0, planets_explored = 0, exchanges_found = 0, planets_skipped = 0,
    }

    if on_complete_callback then
        -- Nested (parent sweep already has .active/hooks) or a standalone call
        -- that was already sitting in the target system space, so the
        -- travel branch above never ran: either way, ensure both here too.
        if started_standalone then f2t_map_explore_claim_run("system") end
        F2T_MAP_EXPLORE_STATE.phase = "navigating"
        F2T_MAP_EXPLORE_STATE.system_name = system_name
        F2T_MAP_EXPLORE_STATE.system_mode = system_mode
        F2T_MAP_EXPLORE_STATE.space_area_id = space_area_id
        F2T_MAP_EXPLORE_STATE.space_area_name = space_area_name
        F2T_MAP_EXPLORE_STATE.planet_list = {}
        F2T_MAP_EXPLORE_STATE.current_planet_index = 0
        F2T_MAP_EXPLORE_STATE.system_phase = "exploring_space"
        F2T_MAP_EXPLORE_STATE.expected_planets = expected_planets_set
        F2T_MAP_EXPLORE_STATE.expected_planets_found = expected_planets_found_set
        F2T_MAP_EXPLORE_STATE.expected_planets_remaining = expected_planets_remaining_count
        F2T_MAP_EXPLORE_STATE.planets_without_exchange = planets_without_exchange
        F2T_MAP_EXPLORE_STATE.system_stats = system_stats
        F2T_MAP_EXPLORE_STATE.brief_planet_name = nil
        F2T_MAP_EXPLORE_STATE.brief_flags = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_set = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_found = nil
        F2T_MAP_EXPLORE_STATE.brief_flags_remaining_count = nil
        F2T_MAP_EXPLORE_STATE.brief_target_planet = nil
        F2T_MAP_EXPLORE_STATE.system_complete_callback = on_complete_callback
        F2T_MAP_EXPLORE_STATE.on_complete_callback = function()
            f2t_map_explore_system_space_complete()
        end
        F2T_MAP_EXPLORE_STATE.starting_room_id = current_room
        F2T_MAP_EXPLORE_STATE.starting_area_id = space_area_id
        F2T_MAP_EXPLORE_STATE.visited_rooms = {[current_room] = true}
        F2T_MAP_EXPLORE_STATE.frontier_stack = {}
    else
        f2t_map_explore_register_safety_hooks()
        f2t_map_explore_init_area(space_area_id, {
            mode = "system",
            system_name = system_name,
            system_mode = system_mode,
            space_area_id = space_area_id,
            space_area_name = space_area_name,
            planet_list = {},
            current_planet_index = 0,
            system_phase = "exploring_space",
            expected_planets = expected_planets_set,
            expected_planets_found = expected_planets_found_set,
            expected_planets_remaining = expected_planets_remaining_count,
            planets_without_exchange = planets_without_exchange,
            system_stats = system_stats,
            on_complete_callback = function()
                f2t_map_explore_system_space_complete()
            end,
        })
    end

    f2t_map_explore_recompute_frontier()

    local room_name = getRoomName(F2T_MAP_CURRENT_ROOM_ID) or "Unknown"
    cecho(string.format("  Starting room: <white>%s<reset> (ID: %d)\n", room_name, F2T_MAP_CURRENT_ROOM_ID))

    if system_mode == "brief" and
       F2T_MAP_EXPLORE_STATE.expected_planets_remaining and
       F2T_MAP_EXPLORE_STATE.expected_planets_remaining == 0 then
        cecho("  <green>All expected planets already mapped!<reset> Skipping space exploration.\n")
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active then
                f2t_map_explore_system_space_complete()
            end
        end)
    else
        f2t_map_explore_next_step()
    end

    return true
end

function f2t_map_explore_system_space_complete()
    local space_area_id = F2T_MAP_EXPLORE_STATE.space_area_id
    local planets = {}

    -- Clean up whatever this sweep just proved stale before doing anything
    -- else with the area: a system rebuild (Dyson Sphere, etc.) can leave old
    -- orbit rooms behind under a name this sweep just found a live, reachable
    -- copy of. That reachable copy is the confident case - safe to purge
    -- without asking, unlike a genuinely unreachable name with no live
    -- duplicate at all (map topology stranded remains the tool for that).
    local auto_purged, auto_purged_names = f2t_map_topology_auto_purge_stale_duplicates(space_area_id)
    if auto_purged > 0 then
        cecho(string.format(
            "\n<dim_grey>[map-explore] Cleaned up %d stale duplicate room(s) left over from a system" ..
            " rebuild: %s<reset>\n", auto_purged, table.concat(auto_purged_names, ", ")))
    end

    -- The rest of this function (build the planet list, skip already-fully-
    -- explored ones, start Phase 2) is pulled into a closure so the
    -- reset-confirm dialog below can call it either immediately or only
    -- after the user answers, without duplicating the logic in a second
    -- top-level function - which is how 'local planets' briefly went missing
    -- from an earlier version of this split.
    local function continueCompletion()
        if F2T_MAP_EXPLORE_STATE.system_mode == "brief" and F2T_MAP_EXPLORE_STATE.expected_planets_found then
            local space_area_name = F2T_MAP_EXPLORE_STATE.space_area_name
            for planet_name, _ in pairs(F2T_MAP_EXPLORE_STATE.expected_planets_found) do
                -- Prefer a reachable candidate over a stale duplicate of the
                -- same name (see the reachability check in f2t_map_explore_
                -- system_start_with_planets above) - a hand-rolled "first
                -- match" scan here would happily hand Phase 2 a room nothing
                -- can navigate to.
                local orbit_room_id = space_area_name and f2t_map_find_orbit_room(space_area_name, planet_name)
                if orbit_room_id then
                    table.insert(planets, {name = planet_name, orbit_room_id = orbit_room_id})
                else
                    f2t_debug_log("[map-explore-system] WARNING: Expected planet %s has no orbit room",
                        planet_name)
                end
            end
        else
            local seen = {}
            for _, room_id in ipairs(f2t_map_area_room_list(space_area_id)) do
                local planet_name = getRoomUserData(room_id, "fed2_planet")
                if planet_name and planet_name ~= "" and not seen[planet_name] then
                    seen[planet_name] = true
                    table.insert(planets, {name = planet_name, orbit_room_id = room_id})
                end
            end
        end

        if #planets == 0 then
            cecho("\n<yellow>[map-explore]<reset> No planets identified in this system's space\n")
            f2t_map_explore_system_return_to_link_and_complete()
            return
        end

        table.sort(planets, function(a, b) return a.name < b.name end)

        -- Skip planets that already have all required brief flags mapped.
        local system_name = F2T_MAP_EXPLORE_STATE.system_name or ""
        local required_flags = f2t_map_explore_strip_courier_outside_sol(
            f2t_map_explore_default_required_flags(), system_name)

        local planets_to_explore = {}
        local already_explored = 0
        for _, planet in ipairs(planets) do
            local planet_area_id = f2t_map_get_area_id(planet.name)
            local all_flags_found = false
            if planet_area_id then
                all_flags_found = true
                for _, flag in ipairs(required_flags) do
                    local skip_flag = flag == "exchange" and
                        F2T_MAP_EXPLORE_STATE.planets_without_exchange and
                        F2T_MAP_EXPLORE_STATE.planets_without_exchange[planet.name]
                    if not skip_flag and not f2t_map_find_room_with_flag(planet_area_id, flag) then
                        all_flags_found = false
                        break
                    end
                end
            end
            if all_flags_found then
                already_explored = already_explored + 1
            else
                table.insert(planets_to_explore, planet)
            end
        end

        F2T_MAP_EXPLORE_STATE.planet_list = planets_to_explore
        F2T_MAP_EXPLORE_STATE.current_planet_index = 0
        -- #planets is only what this sweep actually found - when DI system
        -- said there should be more, the true total belongs in the final
        -- stats too, or "12/12" reads as complete when a planet is still
        -- known to be missing.
        local expected_total = 0
        if F2T_MAP_EXPLORE_STATE.expected_planets then
            for _ in pairs(F2T_MAP_EXPLORE_STATE.expected_planets) do expected_total = expected_total + 1 end
        end
        F2T_MAP_EXPLORE_STATE.system_stats.total_planets = expected_total > 0 and expected_total or #planets
        for _ = 1, already_explored do
            F2T_MAP_EXPLORE_STATE.system_stats.planets_explored =
                F2T_MAP_EXPLORE_STATE.system_stats.planets_explored + 1
            F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found =
                F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found + 1
            F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped =
                F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        end

        cecho(string.format("\n  <green>Space exploration complete!<reset> Discovered %d planet(s)\n", #planets))
        if already_explored > 0 then
            cecho(string.format("  <cyan>Already explored:<reset> %d planet(s) (skipping)\n", already_explored))
        end

        if #planets_to_explore == 0 then
            cecho("\n<green>[map-explore]<reset> All planets already explored! System exploration complete.\n")
            f2t_map_explore_system_return_to_link_and_complete()
            return
        end

        cecho(string.format("  <white>To explore:<reset> %d planet(s)\n", #planets_to_explore))
        cecho("  <dim_grey>Phase 2: Brief exploration of each planet<reset>\n\n")
        F2T_MAP_EXPLORE_STATE.system_phase = "running_brief"
        f2t_map_explore_system_brief_next_planet()
    end

    -- The frontier walk can exhaust (no more unknown exits) without ever
    -- finding every expected planet - a genuinely unreachable orbit, not
    -- just a slow search. A standalone run (the user typed 'map explore
    -- system X' directly, not a nested cartel/galaxy/hauling sweep) gets
    -- offered a reset dialog: wiping this system's space and re-walking it
    -- as genuinely new territory can turn up a route the map's current stub
    -- data doesn't show, and it's just the ordinary, already-correct
    -- frontier walker doing that - not a bespoke re-check pass with its own
    -- pacing and fuel logic to get wrong. Only ever offered once per sweep,
    -- since continueCompletion() below runs the rest of this function
    -- exactly once either way.
    if F2T_MAP_EXPLORE_STATE.system_mode == "brief"
       and F2T_MAP_EXPLORE_STATE.expected_planets_remaining
       and F2T_MAP_EXPLORE_STATE.expected_planets_remaining > 0 then
        local missing = {}
        for planet_name, _ in pairs(F2T_MAP_EXPLORE_STATE.expected_planets) do
            if not F2T_MAP_EXPLORE_STATE.expected_planets_found[planet_name] then
                table.insert(missing, planet_name)
            end
        end
        table.sort(missing)

        local system_name = F2T_MAP_EXPLORE_STATE.system_name
        local standalone = F2T_MAP_EXPLORE_STATE.system_complete_callback == nil

        -- Accumulates rather than overwrites: a nested sweep (cartel/galaxy)
        -- can hit this for more than one system before its own true end, and
        -- f2t_map_explore_complete() - the one place this actually prints -
        -- only ever runs once, at the end of the whole outer run.
        local function appendGapReport(text)
            F2T_MAP_EXPLORE_STATE.deferred_report = (F2T_MAP_EXPLORE_STATE.deferred_report or "") .. text
        end

        -- A fresh reset just walked this whole area as genuinely new
        -- territory and still couldn't find it - offering to reset again
        -- would only repeat that exact walk for the same answer, forever if
        -- the user kept saying yes. One reset is the whole test; report the
        -- result instead of asking again.
        if F2T_MAP_EXPLORE_JUST_RESET[system_name] then
            F2T_MAP_EXPLORE_JUST_RESET[system_name] = nil
            appendGapReport(string.format(
                "<red>Still couldn't find %s after a full reset and re-exploration of %s's space: " ..
                "<white>%s<reset>\n<red>This is very likely a server-side location problem, not" ..
                " something exploration can fix by trying again. Please report it to game staff.<reset>\n",
                #missing > 1 and "these planets" or "this planet", system_name, table.concat(missing, ", ")))
            continueCompletion()
            return
        end

        if standalone and f2tShowExploreResetConfirm then
            f2tShowExploreResetConfirm(system_name, missing,
                function()
                    -- f2t_map_explore_stop() replaces F2T_MAP_EXPLORE_STATE
                    -- wholesale, but space_area_id above is a plain number
                    -- captured earlier and stays valid for the delete. The
                    -- room this leaves us standing in also gets deleted, and
                    -- unlike a plain arrival, f2t_map_explore_system_start_
                    -- with_planets never itself calls f2t_map_ensure_current_
                    -- location - it just reads F2T_MAP_CURRENT_ROOM_ID, which
                    -- still points at the now-deleted room. Left alone,
                    -- getRoomArea() on that stale id comes back empty and the
                    -- restart tries to navigate to a system it thinks it
                    -- isn't in, with a blank system name in the error text.
                    -- Clearing it and forcing the resync here (send 'look',
                    -- wait for the answer) before restarting is what actually
                    -- re-establishes where we are before Phase 1 runs.
                    f2t_map_explore_stop(string.format("Resetting %s's space to look for %s",
                        system_name, table.concat(missing, ", ")))
                    local deleted = f2t_map_explore_delete_area_rooms(space_area_id)
                    cecho(string.format(
                        "\n<green>[map-explore]<reset> %d room(s) removed - re-exploring %s from" ..
                        " scratch...<reset>\n", deleted, system_name))
                    F2T_MAP_EXPLORE_JUST_RESET[system_name] = true
                    F2T_MAP_CURRENT_ROOM_ID = nil
                    f2t_map_ensure_current_location(function()
                        f2t_map_explore_system_start("brief", system_name)
                    end)
                end,
                function()
                    appendGapReport(string.format(
                        "<yellow>%d expected planet(s) never found an orbit room in this sweep: " ..
                        "<white>%s<reset>\n", #missing, table.concat(missing, ", ")))
                    continueCompletion()
                end)
            return
        end

        appendGapReport(string.format(
            "<yellow>%d expected planet(s) never found an orbit room in this sweep: " ..
            "<white>%s<reset>\n", #missing, table.concat(missing, ", ")))
        if not standalone then
            appendGapReport(string.format(
                "<dim_grey>Nested under a larger sweep, so not offering a reset here - run" ..
                " 'map explore system %s' on its own to try one.<reset>\n", system_name))
        end
    end

    continueCompletion()
end

function f2t_map_explore_system_next_planet()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local mode = F2T_MAP_EXPLORE_STATE.mode
    if mode ~= "system" and mode ~= "cartel" and mode ~= "galaxy" then return end
    -- Brief workflow is the only supported per-planet path; route back into it.
    F2T_MAP_EXPLORE_STATE.system_phase = "running_brief"
    f2t_map_explore_system_brief_next_planet()
end

function f2t_map_explore_system_board_planet()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.phase ~= "at_orbit" then return end
    local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]
    if not planet then return end
    cecho("  <dim_grey>Boarding planet...<reset>\n")
    F2T_MAP_EXPLORE_STATE.phase = "boarding_planet"
    send("board")
end

function f2t_map_explore_system_brief_next_planet()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.system_phase ~= "running_brief" then return end
    if f2t_map_explore_check_deferred_pause() then return end

    F2T_MAP_EXPLORE_STATE.current_planet_index = F2T_MAP_EXPLORE_STATE.current_planet_index + 1
    local index = F2T_MAP_EXPLORE_STATE.current_planet_index
    local planets = F2T_MAP_EXPLORE_STATE.planet_list

    if index > #planets then
        f2t_map_explore_system_return_to_link_and_complete()
        return
    end

    local planet = planets[index]
    cecho(string.format("\n<green>[map-explore]<reset> Brief %d/%d: <white>%s<reset>\n",
        index, #planets, planet.name))

    F2T_MAP_EXPLORE_STATE.phase = "navigating_to_orbit"
    F2T_MAP_EXPLORE_STATE.brief_target_planet = planet.name

    local success = f2t_map_navigate_ok(f2t_map_navigate(tostring(planet.orbit_room_id)))
    if not success then
        cecho(string.format("  <yellow>Warning:<reset> Cannot navigate to orbit for '%s', skipping...\n", planet.name))
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_brief_next_planet()
        return
    end

    -- Already at the orbit: no room change will fire, board directly.
    if F2T_MAP_CURRENT_ROOM_ID == planet.orbit_room_id then
        F2T_MAP_EXPLORE_STATE.phase = "at_orbit"
        tempTimer(0.5, function()
            if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.phase == "at_orbit" then
                f2t_map_explore_system_board_planet()
            end
        end)
    end
end

function f2t_map_explore_planet_find_exchange()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if F2T_MAP_EXPLORE_STATE.phase ~= "finding_exchange" then return end

    local current_room = F2T_MAP_CURRENT_ROOM_ID
    local planet = F2T_MAP_EXPLORE_STATE.planet_list[F2T_MAP_EXPLORE_STATE.current_planet_index]
    if not current_room or not planet then
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_next_planet()
        return
    end

    cecho("  <dim_grey>Searching for exchange...<reset>\n")
    local exchange_room = f2t_map_explore_bfs_find_flag(current_room, "exchange", 20)
    if exchange_room then
        cecho("  <green>Exchange found!<reset> Navigating...\n")
        F2T_MAP_EXPLORE_STATE.phase = "planet_complete"
        f2t_map_navigate(tostring(exchange_room))
    else
        cecho(string.format("  <yellow>Warning:<reset> Exchange not found on '%s', skipping...\n", planet.name))
        F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped = F2T_MAP_EXPLORE_STATE.system_stats.planets_skipped + 1
        f2t_map_explore_system_next_planet()
    end
end

-- After system completion, return to the link room before calling back up so
-- the next phase (cartel/galaxy jump) starts from a jump-capable location.
-- Only relevant when there is a next phase: a standalone run (the user typed
-- 'map explore system X' directly, no parent sweep) has nowhere to jump on
-- to, so the link-room leg would just be a detour before the ordinary
-- return-to-starting-room courtesy runs anyway. Skip straight there instead.
function f2t_map_explore_system_return_to_link_and_complete()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    if not F2T_MAP_EXPLORE_STATE.system_complete_callback then
        f2t_map_explore_system_call_callback()
        return
    end

    local link_room = nil
    local space_area_id = F2T_MAP_EXPLORE_STATE.space_area_id
    if space_area_id then
        link_room = f2t_map_find_link_room(space_area_id)
    end
    if not link_room then
        f2t_map_explore_system_call_callback()
        return
    end
    if F2T_MAP_CURRENT_ROOM_ID == link_room then
        f2t_map_explore_system_call_callback()
        return
    end

    cecho("  <dim_grey>Returning to link room...<reset>\n")
    f2t_map_explore_escape_start(
        link_room,
        function() f2t_map_explore_system_call_callback() end,
        function(reason) f2t_map_explore_pause_stranded(reason, link_room) end
    )
end

function f2t_map_explore_system_call_callback()
    if not F2T_MAP_EXPLORE_STATE.active then return end
    local callback = F2T_MAP_EXPLORE_STATE.system_complete_callback
    if callback then
        F2T_MAP_EXPLORE_STATE.system_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        callback()
    else
        F2T_MAP_EXPLORE_STATE.on_complete_callback = nil
        F2T_MAP_EXPLORE_STATE.phase = "returning"
        f2t_map_explore_next_step()
    end
end

f2t_debug_log("[map] Loaded explore_system.lua")
