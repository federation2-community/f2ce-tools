-- fed2-tools — component status display

function f2t_show_status()
    local version = F2T_VERSION or "unknown"
    cecho(string.format("\n<green>[fed2-tools]<reset> v%s\n\n", version))

    -- Map component
    local mapEnabled = F2T_MAP_ENABLED
    if mapEnabled == nil then
        mapEnabled = f2t_settings_get("map", "enabled")
    end
    local mapStatus = mapEnabled and "<green>ENABLED<reset>" or "<red>DISABLED<reset>"
    cecho(string.format("  <yellow>%-15s<reset> %s\n", "Map", mapStatus))

    -- Muxlet
    if Mux and Mux._version then
        local d         = Mux.settings and Mux.settings._data
        local autostart = d and d["f2t"] and d["f2t"]["mux_autostart"]
        local muxMode
        if autostart == true then
            muxMode = "<green>Full<reset>"
        elseif autostart == false then
            muxMode = "<yellow>Minimal<reset>"
        else
            muxMode = "<dim_grey>Not configured<reset>"
        end
        cecho(string.format("  <yellow>%-15s<reset> v%s (%s)\n", "Muxlet", Mux._version, muxMode))
    end

    -- Character
    if F2T_CHAR_NAME then
        cecho(string.format("  <yellow>%-15s<reset> %s\n", "Character", F2T_CHAR_NAME))
    end

    -- Debug mode
    local debugStatus = F2T_DEBUG and "<yellow>ON<reset>" or "<dim_grey>OFF<reset>"
    cecho(string.format("\n  <yellow>%-15s<reset> %s\n\n", "Debug", debugStatus))
end
