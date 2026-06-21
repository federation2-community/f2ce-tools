-- hauling_daily_limit_error — patterns declared in triggers.json
-- Handle daily gross income limit error during hauling
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    cecho("\n<red>[hauling]<reset> DAILY INCOME LIMIT REACHED - Cannot continue trading\n")
    cecho("\n<dim_grey>You have hit the maximum daily gross income for commodity trading.<reset>\n")
    cecho("\n<yellow>[hauling]<reset> Stopping hauling automation...\n")

    f2t_debug_log("[hauling] Daily gross income limit reached, stopping hauling")

    -- Stop hauling immediately
    f2t_hauling_do_stop()
end