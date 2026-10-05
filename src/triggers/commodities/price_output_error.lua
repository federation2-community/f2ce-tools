-- commodities_price_output_error — patterns declared in triggers.json
-- The game or brokers refusing a price check; fails the request waiting on it
-- instead of letting it time out.
if f2tPriceCaptureError(line) then
    deleteLine()
end
