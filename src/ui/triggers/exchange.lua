-- @patterns:
--   - pattern: ^\+{3} The exchange display shows the prices for (.+) \+{3}$
--     type: regex
--   - pattern: ^\+{3} The display shows the prices for (.+) \+{3}$
--     type: regex
--   - pattern: ^\+{3} Exchange will buy \d+ tons at \d+.+ \+{3}
--     type: regex
--   - pattern: ^\+{3} Exchange has .+ for sale \+{3}$
--     type: regex
--   - pattern: ^\+{3} Offer price is \d+.+ for first \d+ tons \+{3}$
--     type: regex

if line:match("shows the prices for") then
    local name        = line:match("for (.+) %+%+%+$")
    local base_price  = "???"
    local commodities = ui_commodities_load()
    for _, commodity in ipairs(commodities) do
        if commodity.name == name then base_price = commodity.basePrice end
    end
    UI.exchange_window:echo("+++\n")
    UI.exchange_window:cecho("<ansiYellow>" .. name .. " (base " .. base_price .. "):\n")

elseif line:match("Exchange will buy") then
    local price = line:match("at (%d+)")
    UI.exchange_window:cecho("<ansiYellow>Buying at: " .. price .. "\n")

elseif line:match("Exchange has") then
    local qty = line:match("has (.+) for sale")
    UI.exchange_window:cecho("<ansiYellow>Available: " .. qty .. "\n")

elseif line:match("Offer price is") then
    local price = line:match("Offer price is (%d+)")
    UI.exchange_window:cecho("<ansiYellow>Selling at: " .. price .. "\n")
end

ui_tab_notify("Exchange")

deleteLine()
tempLineTrigger(1, 1, [[if getCurrentLine() == "" then deleteLine() end]])
