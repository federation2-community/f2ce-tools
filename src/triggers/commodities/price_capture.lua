-- commodities_price_capture — patterns declared in triggers.json
-- One row of a price reply:
--   "Coffee: Affogato is selling 2780 tons at 643ig/ton"
--   "Coffee: Affogato is buying 75 tons at 526ig/ton"
--   "Updog: Cowhide is not currently trading in this commodity"
-- The Exchange pane's spot-check click answers in the same shape; that one
-- prints as on-screen confirmation.
if f2tExchangeSpotCheckActive and f2tExchangeSpotCheckActive() then
    return
end
if f2tPriceCaptureLine(line) then
    deleteLine()
end
