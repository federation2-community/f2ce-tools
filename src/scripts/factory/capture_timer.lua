-- f2ce-tools factory — capture completion timer
--
-- After each captured line the timer is reset.  When 0.5 s elapse with no new
-- data the current factory block is considered complete and processed; an empty
-- buffer means the query produced no parseable output, so we advance anyway.
-- The timer MUST always resolve to keep the state machine from stalling.

f2t_factory_timer_id = nil

function f2t_factory_start_capture_timer()
    if f2t_factory_timer_id then killTimer(f2t_factory_timer_id) end

    f2t_factory_timer_id = tempTimer(0.5, function()
        if not f2t_factory.capturing then return end
        if #f2t_factory.capture_buffer > 0 then
            f2t_debug_log("[factory] Timer expired, processing capture")
            f2t_factory_process_capture()
        else
            f2t_debug_log("[factory] Timer expired with empty buffer, advancing")
            f2t_factory.capturing      = false
            f2t_factory.capture_buffer = {}
            f2t_factory_query_next()
        end
    end)
end

-- Called by the capture trigger each time a line is gathered.
function f2t_factory_reset_capture_timer()
    if f2t_factory.capturing then f2t_factory_start_capture_timer() end
end