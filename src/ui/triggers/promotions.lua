-- @patterns:
--   - pattern:  has promoted to
--     type: substring
--   - pattern:  has gained promotion to 
--     type: substring
--   - pattern:  has reached Trader rank!
--     type: substring
--   - pattern:  has been acclaimed as Founder of 
--     type: substring
--   - pattern:  and has promoted to Industrialist!
--     type: substring
--   - pattern:  has been elevated to the ranks of the plutocracy!
--     type: substring
--   - pattern:  has joined the Galactic Trading Guild and become a Merchant!
--     type: substring
--   - pattern:  has earned membership in the Adventurer's Guild and become an 
--     type: substring

local captured_line = line
local pname, prest  = captured_line:match("^%s*(%u%a+)(.*)")

ui_tab_notify("General")

ui_general_add("promotion", function(win)
    if pname then
        local nc
        if UI.who and UI.who.name_colors and UI.who.name_colors[pname] then
            nc = "<" .. UI.who.name_colors[pname] .. ">"
        else
            nc = "<dim_gray>"
        end
        local hint = (UI.who and UI.who.name_rawlines and UI.who.name_rawlines[pname]) or ("tb " .. pname)
        win:cechoLink(nc .. "<b>" .. pname .. "</b><reset>", function() printCmdLine("tb " .. pname .. " ") end, hint, true)
        win:cecho(prest .. "\n")
    else
        win:cecho(captured_line .. "\n")
    end
end)

tempLineTrigger(0, 2, [[deleteLine()]])