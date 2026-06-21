-- hauling_akaturi_job_start — patterns declared in triggers.json
-- Detect start of Akaturi job assignment output
-- Don't delete - user wants to see the job details

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_parsing_pickup" then
    if f2t_akaturi_is_capturing_job() then
        f2t_akaturi_add_job_line(line)
        f2t_debug_log("[hauling/akaturi] Captured job header")
    end
end