-- hauling_ac_deliver_waiting — patterns declared in triggers.json
-- Stevedores are busy - need to wait for delivery to complete
-- This can take 10-15 seconds of waiting messages

-- Only process if hauling is active and we're delivering
if not (F2T_HAULING_STATE and F2T_HAULING_STATE.active and
        F2T_HAULING_STATE.current_phase == "ac_delivering") then
    return
end

f2t_debug_log("[hauling/ac] Stevedores busy, waiting for unloading crew")

-- Set flag to indicate we're in extended wait
F2T_HAULING_STATE.ac_deliver_waiting = true