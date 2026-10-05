-- hauling_daily_limit_error — patterns declared in triggers.json
-- A Trader past the daily gross income limit for commodity trading: every buy
-- and sell is refused until the next day, so end any bulk trade and hauling.
if f2t_bulk_buy_error then f2t_bulk_buy_error("Daily gross income limit for commodity trading reached") end
if f2t_bulk_sell_error then f2t_bulk_sell_error("Daily gross income limit for commodity trading reached") end

if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    cecho("\n<red>[hauling]<reset> DAILY INCOME LIMIT REACHED - Cannot continue trading\n")
    cecho("\n<dim_grey>You have hit the maximum daily gross income for commodity trading.<reset>\n")
    cecho("\n<yellow>[hauling]<reset> Stopping hauling automation...\n")

    f2t_debug_log("[hauling] Daily gross income limit reached, stopping hauling")

    -- Stop hauling immediately
    f2t_hauling_do_stop()
end
