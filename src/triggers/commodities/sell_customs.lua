-- commodities_sell_customs — patterns declared in triggers.json
-- Customs is printed just before the sale line it applies to
f2t_bulk_sell_customs(tonumber((matches[2]:gsub(",", ""))) or 0)
