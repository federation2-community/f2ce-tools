-- commodities_trade_not_allowed — patterns declared in triggers.json
-- The game refusing a buy or sell because the rank may not trade on the
-- exchanges (Financier, or below Merchant).
f2t_bulk_buy_error("Your rank can't trade on the commodity exchanges")
f2t_bulk_sell_error("Your rank can't trade on the commodity exchanges")
