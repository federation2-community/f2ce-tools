-- commodities_price_output_blank — patterns declared in triggers.json
-- Swallow blank lines only while an automated price capture is active, to
-- avoid spamming the console once per commodity during "price all" loops.
-- Manual "check price" (F2T_PRICE_CAPTURE_ACTIVE never set) is unaffected.
if F2T_PRICE_CAPTURE_ACTIVE then
    deleteLine()
end
