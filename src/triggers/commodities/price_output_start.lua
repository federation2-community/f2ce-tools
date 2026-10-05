-- commodities_price_output_start — patterns declared in triggers.json
-- Brokers' intro to a price reply. Starts capture when a queued request is
-- waiting on it (see price_service.lua); a typed `check price` prints normally.
if f2tPriceCaptureStart() then
    deleteLine()
end
