-- hauling_akaturi_pickup_error — patterns declared in triggers.json
-- Handle error when pickup command is used in wrong room

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_collecting" then
    deleteLine()
    cecho("\n<yellow>[hauling]<reset> Wrong pickup location, trying next match...\n")
    F2T_HAULING_STATE.akaturi_pickup_error = true
    f2t_debug_log("[hauling/akaturi] Pickup failed - wrong room")

    -- Re-run collect phase to try next match
    tempTimer(0.5, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "akaturi_collecting" then
            f2t_hauling_phase_akaturi_collect()
        end
    end)
end