-- price_checker_line — patterns declared in triggers.json
--
-- One `c price`/`c premium` result row: "System: Planet is buying|selling N tons at Mig/ton".
-- Gagged only when the Check button or a Find Best scan sent this command; a manually
-- typed `c price`/`c premium` always prints normally.
-- The Exchange pane's commodity-name click sends a plain spot check that produces
-- this same line shape; skip capture then so it prints as on-screen confirmation.
-- Spot-check active: let it print normally (no capture, no gag).
if not (f2tExchangeSpotCheckActive and f2tExchangeSpotCheckActive())
   and ((f2tPriceCheckerAwaitingCommand and f2tPriceCheckerAwaitingCommand())
        or (f2tPriceCheckerIsSearching and f2tPriceCheckerIsSearching())) then
    f2tPriceCheckerLine(matches[2], matches[3], matches[4], matches[5], matches[6])
    deleteLine()
end
