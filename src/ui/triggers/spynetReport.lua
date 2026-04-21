-- @patterns:
--   - pattern: SPYNET REPORT: (\w+) (\w+) has (entered|left) Federation DataSpace
--     type: regex

--does some basic formatting and redirects the login/logout notice to the overflow window.
--does not catch players with [ ] titles
local rank   = matches[2]
local name   = matches[3]
local action = matches[4]

local name_color = (UI.who and UI.who.name_colors and UI.who.name_colors[name])
    and "<" .. UI.who.name_colors[name] .. ">"
    or "<white>"

UI.general_window:cecho("<white>SPYNET REPORT: <b>" .. rank .. " </b>" .. name_color .. "<b>" .. name .. "</b><white> has <b>" .. action .. "</b> Federation DataSpace.\n<reset>")
tempLineTrigger(0, 2, [[deleteLine()]]) --delete the current line and the next line, to catch the newline after every SPYNET REPORT