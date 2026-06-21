-- hauling_ac_deliver_error — patterns declared in triggers.json
-- Error delivering cargo
-- Notify hauling system if active
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    deleteLine()  -- Only hide when automation is active
    cecho("\n<red>[hauling]<reset> Deliver error: You don't have a cargo to deliver\n")
    F2T_HAULING_STATE.ac_deliver_error = "no cargo"
    f2t_debug_log("[hauling/ac] Deliver error: no cargo to deliver")
end