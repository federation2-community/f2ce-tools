-- hauling_akaturi_job_error — patterns declared in triggers.json
-- ak refused outside an Armstrong Cuthbert office

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.mode == "akaturi"
    and F2T_HAULING_STATE.current_phase == "akaturi_reading_contract" then
    cecho("\n<yellow>[hauling]<reset> Not at an Armstrong Cuthbert office; heading to one\n")
    F2T_HAULING_STATE.current_phase = "akaturi_getting_job"
    tempTimer(1, function()
        if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused
            and F2T_HAULING_STATE.current_phase == "akaturi_getting_job" then
            f2t_akaturi_go_to_office(function() f2t_hauling_phase_akaturi_get_job() end)
        end
    end)
end
