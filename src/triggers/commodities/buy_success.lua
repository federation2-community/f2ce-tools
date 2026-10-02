-- commodities_buy_success — patterns declared in triggers.json
-- Detect successful commodity purchase
-- Pattern stops at the price: the tail wording varies ("your ship" / "your spaceship")
-- Deferred a tick: Mudlet wraps this long line only after triggers finish, so output
-- echoed or sent from inside the trigger would land between its wrapped halves.
tempTimer(0, f2t_bulk_buy_success)