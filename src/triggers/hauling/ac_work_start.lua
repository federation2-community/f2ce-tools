-- hauling_ac_work_start — patterns declared in triggers.json
-- Trigger when work command output starts
-- Only hide the header line if hauling is active
-- Note: f2t_ac_start_capture() is called by the phase function before sending "work"
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    deleteLine()
    f2t_debug_log("[hauling/ac] Work output header detected")

    -- Reset the capture timer to prevent premature timeout
    -- This gives the job lines time to arrive after the header
    f2t_ac_reset_capture_timer()
end