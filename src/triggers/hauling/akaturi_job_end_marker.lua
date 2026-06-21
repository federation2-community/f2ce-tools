-- hauling_akaturi_job_end_marker — patterns declared in triggers.json
-- Detect completion of Akaturi job assignment output (explicit end marker)
-- This is the PRIMARY completion trigger for job capture

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_parsing_pickup" then
    if f2t_akaturi_is_capturing_job() then
        -- Capture this line
        f2t_akaturi_add_job_line(line)

        f2t_debug_log("[hauling/akaturi] Job output end marker detected")

        -- Trigger parsing phase immediately
        tempTimer(0.1, function()
            if F2T_HAULING_STATE.active and not F2T_HAULING_STATE.paused and
               F2T_HAULING_STATE.current_phase == "akaturi_parsing_pickup" then
                f2t_hauling_phase_akaturi_parse_pickup()
            end
        end)
    end
end