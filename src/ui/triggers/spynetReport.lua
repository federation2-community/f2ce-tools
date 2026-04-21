-- @patterns:
--   - pattern: SPYNET REPORT: (\w+) (\w+)( \[[^\]]+\])? has (entered|left) Federation DataSpace
--     type: regex

local rank   = matches[2]
local name   = matches[3]
local role   = (matches[4] and matches[4] ~= "") and matches[4] or ""
local action = matches[5]

ui_general_add("spynet", function(win)
    local nc
    if UI.who and UI.who.name_colors and UI.who.name_colors[name] then
        nc = "<" .. UI.who.name_colors[name] .. ">"
    else
        if ui_who_request_refresh then ui_who_request_refresh() end
        nc = "<light_gray>"
    end
    win:cecho("<white>SPYNET REPORT: " .. nc .. "<b>" .. rank .. " " .. name .. "</b><white>" .. role .. " has <b>" .. action .. "</b> Federation DataSpace.\n<reset>")
end)

tempLineTrigger(0, 2, [[deleteLine()]])