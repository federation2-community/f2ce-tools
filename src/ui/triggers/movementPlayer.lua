-- @patterns:
--   - pattern: ^([A-Z]\w+) has (?:left|(?:just )?arrived|departed|boarded)
--     type: regex
--   - pattern: ^([A-Z]\w+)'s spaceship (?:dis)?appears .+hyperspace link
--     type: regex
--   - pattern: ^([A-Z]\w+)'s ship has (?:left|(?:just )?entered) the sector
--     type: regex

local name = matches[2]
local rest = line:sub(#name + 1)

ui_tab_notify("General")

ui_general_add("movement", function(win)
    local nc
    if UI.who and UI.who.name_colors and UI.who.name_colors[name] then
        nc = "<" .. UI.who.name_colors[name] .. ">"
    else
        if ui_who_request_refresh then ui_who_request_refresh() end
        nc = "<dim_gray>"
    end
    local hint = (UI.who and UI.who.name_rawlines and UI.who.name_rawlines[name]) or ("tb " .. name)
    win:cechoLink(nc .. "<b>" .. name .. "</b><reset>", function() printCmdLine("tb " .. name .. " ") end, hint, true)
    win:hecho("#2d6e2d" .. rest .. "\n")
end)

if f2t_settings_get("ui", "hide_movement_messages") then
    tempLineTrigger(0, 2, [[deleteLine()]])
end
