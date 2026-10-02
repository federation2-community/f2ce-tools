-- po_stockpile_ack — patterns declared in triggers.json
local value = tonumber((matches[4]:gsub(",", "")))
if f2tStockpileOnAck(string.lower(matches[2]), matches[3], value) then deleteLine() end
