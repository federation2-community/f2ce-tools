-- @patterns:
--   - pattern: ^([A-Z]\w+) has (?:left|(?:just )?arrived|departed|boarded)
--     type: regex
--   - pattern: ^([A-Z]\w+)'s spaceship (?:dis)?appears .+hyperspace link
--     type: regex
--   - pattern: ^([A-Z]\w+)'s ship has (?:left|(?:just )?entered) the sector
--     type: regex

local name = matches[2]
local rest = line:sub(#name + 1)

local name_color = (UI.who and UI.who.name_colors and UI.who.name_colors[name])
    and "<" .. UI.who.name_colors[name] .. ">"
    or "<white>"

UI.general_window:cecho(name_color .. "<b>" .. name .. "</b><reset>")
UI.general_window:hecho("#2d6e2d" .. rest .. "\n")

if f2t_settings_get("ui", "hide_movement_messages") then
    tempLineTrigger(0, 2, [[deleteLine()]])
end
