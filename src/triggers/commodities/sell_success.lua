-- commodities_sell_success — patterns declared in triggers.json
-- Detect successful commodity sale and extract price
local commodity = matches[2]
local revenue_total = tonumber((matches[3]:gsub(",", ""))) or 0
local revenue_per_ton = math.floor(revenue_total / 75)

f2t_bulk_sell_success(commodity, revenue_per_ton, revenue_total)