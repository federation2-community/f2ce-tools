-- f2ce-tools map — DI system capture (ported from map_di_system_capture.lua)

F2T_MAP_DI_SYSTEM_CAPTURE = F2T_MAP_DI_SYSTEM_CAPTURE or {
    active = false, system_name = nil, planet_names = {},
}

function f2t_map_di_system_capture_start(system_name, callback)
    f2t_capture_close("di_system")
    F2T_MAP_DI_SYSTEM_CAPTURE = {
        active = true, system_name = system_name,
        planet_names = {}, callback = callback,
    }
    send(string.format("di system %s", system_name), false)
    -- Arm before the first line rather than on it, so a server that answers
    -- with nothing at all still closes the capture instead of hanging it.
    f2t_map_di_system_reset_timer()
end

function f2t_map_di_system_reset_timer()
    f2t_capture_arm("di_system", function()
        if F2T_MAP_DI_SYSTEM_CAPTURE.active then
            f2t_map_di_system_capture_complete()
        end
    end)
end

-- Set by the no-such-system trigger while a capture is open. "di system X"
-- is the only thing that can tell us X is not a star system, and finding out
-- is worth more than the planet list we asked for.
function f2t_map_di_system_no_such_system()
    if not F2T_MAP_DI_SYSTEM_CAPTURE or not F2T_MAP_DI_SYSTEM_CAPTURE.active then return false end
    deleteLine()
    F2T_MAP_DI_SYSTEM_CAPTURE.no_such_system = true
    f2t_map_di_system_reset_timer()
    return true
end

function f2t_map_di_system_capture_complete()
    local planet_lines = F2T_MAP_DI_SYSTEM_CAPTURE.planet_names
    local callback       = F2T_MAP_DI_SYSTEM_CAPTURE.callback
    local no_such_system = F2T_MAP_DI_SYSTEM_CAPTURE.no_such_system

    f2t_capture_close("di_system")
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

    -- A hardcoded list of Sol's non-tradeable planets used to be filtered out
    -- here. The listing already publishes the same property per planet as
    -- "Economy: None", which planets_without_exchange above reads: hauling
    -- skips those outright and exploration maps them without hunting an
    -- exchange. Enumerating the names as well only added a second, cruder
    -- copy of that fact, and it had already drifted out of date.
    if callback then callback(planets, planets_without_exchange, no_such_system) end
end

f2t_debug_log("[map] Loaded di_system_capture.lua")
