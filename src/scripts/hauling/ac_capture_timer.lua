-- Timer-based AC job capture completion detection
-- After capturing starts, if no new data arrives for a short time, consider output complete

f2t_ac_timer_id = nil

function f2t_ac_start_capture_timer()
    -- Cancel existing timer if any
    if f2t_ac_timer_id then
        killTimer(f2t_ac_timer_id)
    end

    -- Increment sequence to invalidate old timers
    F2T_AC_JOB_STATE.timer_sequence = F2T_AC_JOB_STATE.timer_sequence + 1
    local my_sequence = F2T_AC_JOB_STATE.timer_sequence

    -- Start timer to process capture after 0.5 seconds of no new data
    f2t_ac_timer_id = tempTimer(0.5, function()
        -- Only process if this is still the latest timer
        if F2T_AC_JOB_STATE.timer_sequence ~= my_sequence then
            f2t_debug_log("[hauling/ac] Old timer fired (seq %d, current %d), ignoring",
                my_sequence, F2T_AC_JOB_STATE.timer_sequence)
            return
        end

        if f2t_ac_is_capturing() then
            f2t_debug_log("[hauling/ac] Capture timer expired (seq %d), calling select phase", my_sequence)

            -- Call the select phase to process captured jobs
            if F2T_HAULING_STATE and F2T_HAULING_STATE.active and
               F2T_HAULING_STATE.current_phase == "ac_selecting_job" then
                f2t_hauling_phase_ac_select_job()
            end
        end
    end)
end

-- Call this whenever we capture a new job line to reset the timer
function f2t_ac_reset_capture_timer()
    if f2t_ac_is_capturing() then
        f2t_ac_start_capture_timer()
    end
end