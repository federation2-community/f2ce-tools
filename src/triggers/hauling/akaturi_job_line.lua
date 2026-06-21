-- hauling_akaturi_job_line — patterns declared in triggers.json
-- Capture all lines during Akaturi job assignment
-- Don't delete - user wants to see the job details

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_parsing_pickup" then
    if f2t_akaturi_is_capturing_job() then
        -- Capture for parsing (but don't hide from user)
        f2t_akaturi_add_job_line(line)
    end
end