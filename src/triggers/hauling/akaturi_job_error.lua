-- hauling_akaturi_job_error — patterns declared in triggers.json
-- Handle error when 'ak' command is used outside AC room

if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    cecho("\n<red>[hauling]<reset> Error: Not at Armstrong Cuthbert office\n")
    f2t_debug_log("[hauling/akaturi] Job request failed - not at AC room")

    -- Retry getting job (will navigate to AC room first)
    tempTimer(1.0, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused then
            F2T_HAULING_STATE.current_phase = "akaturi_getting_job"
            f2t_hauling_phase_akaturi_get_job()
        end
    end)
end