-- hauling_akaturi_dropoff_success — patterns declared in triggers.json
-- Detect successful package delivery

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_delivering" then
    deleteLine()
    F2T_HAULING_STATE.akaturi_package_delivered = true
    f2t_debug_log("[hauling/akaturi] Package delivered successfully")

    -- Re-run deliver phase to process success
    tempTimer(0.1, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
           F2T_HAULING_STATE.current_phase == "akaturi_delivering" then
            f2t_hauling_phase_akaturi_deliver()
        end
    end)
end