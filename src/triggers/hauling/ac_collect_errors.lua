-- hauling_ac_collect_errors — patterns declared in triggers.json
-- Error collecting cargo
local error_msg = line

-- Notify hauling system if active
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    deleteLine()  -- Only hide error when automation is active
    cecho(string.format("\n<red>[hauling]<reset> Collect error: %s\n", error_msg))
    F2T_HAULING_STATE.ac_collect_error = error_msg
    f2t_debug_log("[hauling/ac] Collect error: %s", error_msg)
end