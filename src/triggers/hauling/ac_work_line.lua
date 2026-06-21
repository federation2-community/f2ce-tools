-- hauling_ac_work_line — patterns declared in triggers.json
-- Capture each job line from work command output
-- Only capture and hide if actively capturing
if f2t_ac_is_capturing() then
    deleteLine()
    f2t_ac_add_job_line(line)

    -- Reset the capture timer since we got new data
    f2t_ac_reset_capture_timer()
end