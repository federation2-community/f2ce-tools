-- @patterns:
--   - pattern: SPYNET REPORT: (\w+) (\w+) has (entered|left) Federation DataSpace
--     type: regex

--does some basic formatting and redirects the login/logout notice to the overflow window.
--does not catch players with [ ] titles
--matches[2] is the player rank, matches[3] is the player name, matches[4] is login / logout
UI.general_window:cecho("SPYNET REPORT: <b>" .. matches[2] .. " " .. matches[3] .. "</b> has <b>" .. matches[4] .."</b> Federation DataSpace.\n")
tempLineTrigger(0, 2, [[deleteLine()]]) --delete the current line and the next line, to catch the newline after every SPYNET REPORT