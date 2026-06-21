-- hauling_ac_collect_success — patterns declared in triggers.json
-- Successfully collected cargo
f2t_debug_log("[hauling/ac] Cargo collected successfully")

-- Notify hauling system if active and in collecting phase
if F2T_HAULING_STATE and F2T_HAULING_STATE.active and
   F2T_HAULING_STATE.current_phase == "ac_collecting" then
    F2T_HAULING_STATE.ac_cargo_collected = true

    -- Schedule phase processing after brief delay to let trigger exit
    -- This prevents race conditions with output capture
    tempTimer(0.1, function()
        if F2T_HAULING_STATE and F2T_HAULING_STATE.active and
           F2T_HAULING_STATE.current_phase == "ac_collecting" then
            f2t_hauling_phase_ac_collect()
        end
    end)
end