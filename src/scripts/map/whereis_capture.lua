-- f2ce-tools map — whereis capture
--
-- Resolves a bare planet name to its system via the game's own `whereis`
-- command, for planets that have never been locally mapped at all (so
-- f2t_map_lookup_planet/f2t_map_get_system_space_area_actual have nothing to
-- go on). This is the oracle that tells a typo from a real, unvisited place.
--
-- When queried from a specific location, `whereis` can also volunteer a
-- second line naming the next command toward the destination (e.g. "From
-- Types Space to Pisces: j Stellar") - the game's own routing, independent
-- of whatever our local map graph does or doesn't know. That line, if any,
-- arrives right after the first and is passed as a second argument to the
-- callback so callers can use it to keep moving even when getPath() can't
-- find a route through locally-mapped rooms alone.

F2T_MAP_WHEREIS_CAPTURE = F2T_MAP_WHEREIS_CAPTURE or {active = false}

function f2t_map_whereis_lookup(planet_name, callback)
    if F2T_MAP_WHEREIS_CAPTURE.active then
        callback(nil)
        return
    end
    local timer_id = tempTimer(5, function()
        if F2T_MAP_WHEREIS_CAPTURE.active then
            f2t_map_whereis_capture_complete(nil)
        end
    end)
    F2T_MAP_WHEREIS_CAPTURE = {active = true, callback = callback, timer_id = timer_id, route_command = nil}
    send(string.format("whereis %s", planet_name), false)
end

-- Called by the whereis_found trigger once the "X is in the Y system..."
-- line lands. Doesn't resolve the capture immediately - holds it open
-- briefly in case the optional route-hint line follows right behind, which
-- whereis_route_hint.lua (below) attaches before the grace timer fires.
function f2t_map_whereis_capture_system(system_name)
    if not F2T_MAP_WHEREIS_CAPTURE.active then return end
    F2T_MAP_WHEREIS_CAPTURE.system_name = system_name
    if F2T_MAP_WHEREIS_CAPTURE.timer_id then killTimer(F2T_MAP_WHEREIS_CAPTURE.timer_id) end
    F2T_MAP_WHEREIS_CAPTURE.timer_id = tempTimer(0.3, function()
        if F2T_MAP_WHEREIS_CAPTURE.active then
            f2t_map_whereis_capture_complete(F2T_MAP_WHEREIS_CAPTURE.system_name, F2T_MAP_WHEREIS_CAPTURE.route_command)
        end
    end)
end

-- Called by the whereis_route_hint trigger if the "From X to Y: <command>"
-- line shows up while a capture is still open.
function f2t_map_whereis_capture_route(route_command)
    if not F2T_MAP_WHEREIS_CAPTURE.active then return end
    F2T_MAP_WHEREIS_CAPTURE.route_command = route_command
    if F2T_MAP_WHEREIS_CAPTURE.timer_id then killTimer(F2T_MAP_WHEREIS_CAPTURE.timer_id) end
    f2t_map_whereis_capture_complete(F2T_MAP_WHEREIS_CAPTURE.system_name, route_command)
end

function f2t_map_whereis_capture_complete(system_name, route_command)
    local callback = F2T_MAP_WHEREIS_CAPTURE.callback
    if F2T_MAP_WHEREIS_CAPTURE.timer_id then killTimer(F2T_MAP_WHEREIS_CAPTURE.timer_id) end
    F2T_MAP_WHEREIS_CAPTURE = {active = false}
    if callback then callback(system_name, route_command) end
end

f2t_debug_log("[map] Loaded whereis_capture.lua")
