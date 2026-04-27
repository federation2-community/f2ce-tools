-- @patterns:
--   - pattern: ^$
--     type: regex

-- Only process if we're in profit search mode
if UI.trading.profit_search and UI.trading.profit_search.active and UI.trading.data and #UI.trading.data > 0 then
    ui_process_profit_search_results()
    UI.trading.data = {}
    deleteLine()
end