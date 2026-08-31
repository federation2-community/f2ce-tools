-- f2ce-tools map — whereis capture
--
-- Resolves a bare planet name to its system via the game's own `whereis`
-- command, for planets that have never been locally mapped at all (so
-- f2t_map_lookup_planet/f2t_map_get_system_space_area_actual have nothing to
-- go on). This is the oracle that tells a typo from a real, unvisited place.

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
    F2T_MAP_WHEREIS_CAPTURE = {active = true, callback = callback, timer_id = timer_id}
    send(string.format("whereis %s", planet_name), false)
end

function f2t_map_whereis_capture_complete(system_name, cartel_name, syndicate_name)
    local callback = F2T_MAP_WHEREIS_CAPTURE.callback
    if F2T_MAP_WHEREIS_CAPTURE.timer_id then killTimer(F2T_MAP_WHEREIS_CAPTURE.timer_id) end
    F2T_MAP_WHEREIS_CAPTURE = {active = false}
    if callback then callback(system_name, cartel_name, syndicate_name) end
end

f2t_debug_log("[map] Loaded whereis_capture.lua")
