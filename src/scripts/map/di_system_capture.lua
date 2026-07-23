-- f2ce-tools map — DI system capture (ported from map_di_system_capture.lua)

F2T_MAP_DI_SYSTEM_CAPTURE = F2T_MAP_DI_SYSTEM_CAPTURE or {
    active = false, system_name = nil, planet_names = {}, timer_id = nil,
}

F2T_MAP_SOL_EXCLUDED_PLANETS = {
    ["graveyard"] = true, ["hunt"] = true, ["magrathea"] = true, ["starbase1"] = true,
}

function f2t_map_di_system_capture_start(system_name, callback)
    F2T_MAP_DI_SYSTEM_CAPTURE = {
        active = true, system_name = system_name,
        planet_names = {}, timer_id = nil, callback = callback,
    }
    send(string.format("di system %s", system_name), false)
end

function f2t_map_di_system_reset_timer()
    if F2T_MAP_DI_SYSTEM_CAPTURE.timer_id then
        killTimer(F2T_MAP_DI_SYSTEM_CAPTURE.timer_id)
    end
    F2T_MAP_DI_SYSTEM_CAPTURE.timer_id = tempTimer(0.5, function()
        if F2T_MAP_DI_SYSTEM_CAPTURE.active then
            f2t_map_di_system_capture_complete()
        end
    end)
end

function f2t_map_di_system_capture_complete()
    local planet_lines = F2T_MAP_DI_SYSTEM_CAPTURE.planet_names
    local system_name  = F2T_MAP_DI_SYSTEM_CAPTURE.system_name
    local callback     = F2T_MAP_DI_SYSTEM_CAPTURE.callback

    F2T_MAP_DI_SYSTEM_CAPTURE = {active = false}

    local planets = {}
    local planet_set = {}
    local planets_without_exchange = {}

    local i = 1
    while i <= #planet_lines do
        local planet_line = planet_lines[i]
        local planet_name = planet_line:match("^([^,]+),")
        if planet_name and not planet_line:match("^%s") then
            planet_name = planet_name:match("^%s*(.-)%s*$")
            if planet_name:match(" Space$") then
                i = i + 2
            else
                local has_exchange = true
                local detail_index = i + 1
                while detail_index <= #planet_lines do
                    local detail_line = planet_lines[detail_index]
                    if not detail_line:match("^%s") then break end
                    if detail_line:match("Economy:%s*None") then has_exchange = false end
                    detail_index = detail_index + 1
                end
                if planet_name ~= "" and not planet_set[planet_name] then
                    table.insert(planets, planet_name)
                    planet_set[planet_name] = true
                    if not has_exchange then planets_without_exchange[planet_name] = true end
                end
                i = detail_index
            end
        else
            i = i + 1
        end
    end

    if system_name and system_name:lower() == "sol" then
        local filtered_planets = {}
        for _, planet_name in ipairs(planets) do
            if not F2T_MAP_SOL_EXCLUDED_PLANETS[planet_name:lower()] then
                table.insert(filtered_planets, planet_name)
            else
                planets_without_exchange[planet_name] = nil
            end
        end
        planets = filtered_planets
    end

    if callback then callback(planets, planets_without_exchange) end
end

f2t_debug_log("[map] Loaded di_system_capture.lua")
