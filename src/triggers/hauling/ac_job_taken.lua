-- hauling_ac_job_taken — patterns declared in triggers.json
-- Job is no longer available - someone else took it
local job_number = tonumber(matches[2])

-- Notify hauling system if active
if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.ac_job then
    if F2T_HAULING_STATE.ac_job.number == job_number then
        deleteLine()  -- Only hide when automation is tracking this job
        cecho(string.format("\n<yellow>[hauling]<reset> Job %d was taken, will fetch new jobs\n", job_number))
        F2T_HAULING_STATE.ac_job_taken = true
        f2t_debug_log("[hauling/ac] Job %d was taken by someone else", job_number)
    end
end