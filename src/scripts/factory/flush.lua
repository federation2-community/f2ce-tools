-- f2ce-tools factory — flush sequence
--
-- Sends "flush factory N" for N = 1..max_factories.  Success and empty-slot
-- responses are handled by the flush triggers, which call back into
-- f2t_factory_flush_next() to advance.  Completion reports how many slots were
-- actually cleared.  A watchdog aborts the sequence if a step gets no
-- recognised response, so a missed line can't leave the flush stuck.

local FLUSH_STEP_TIMEOUT = 10

local function killFlushWatchdog()
    if f2t_factory.flush_watchdog_id then
        killTimer(f2t_factory.flush_watchdog_id)
        f2t_factory.flush_watchdog_id = nil
    end
end

function f2t_factory_flush_stop()
    killFlushWatchdog()
    f2t_factory.flushing       = false
    f2t_factory.current_number = 0
    f2t_factory.flush_count    = 0
end

function f2t_factory_start_flush()
    if f2t_factory.flushing then
        cecho("\n<yellow>[factory]<reset> Factory flush already in progress, please wait...\n")
        return false
    end
    if f2t_factory.capturing then
        cecho("\n<yellow>[factory]<reset> Factory status in progress, please wait...\n")
        return false
    end

    -- A manual flush supersedes any pending pre-reset auto-flush timer.
    if f2t_factory.shutdown_timer_id then
        killTimer(f2t_factory.shutdown_timer_id)
        f2t_factory.shutdown_timer_id = nil
        f2t_debug_log("[factory] Cancelled pending auto-flush timer")
    end

    f2t_factory.flushing       = true
    f2t_factory.current_number = 0
    f2t_factory.flush_count    = 0
    f2t_factory.max_factories  = f2t_is_rank_exactly("Manufacturer") and 15 or 8

    f2t_debug_log("[factory] Starting flush sequence (max: %d)", f2t_factory.max_factories)

    f2t_factory_flush_next()
    return true
end

function f2t_factory_flush_next()
    if not f2t_factory.flushing then
        f2t_debug_log("[factory] WARNING: flush_next called while not flushing")
        return
    end

    killFlushWatchdog()
    f2t_factory.current_number = f2t_factory.current_number + 1

    if f2t_factory.current_number > f2t_factory.max_factories then
        f2t_debug_log("[factory] Reached max factories (%d), completing flush", f2t_factory.max_factories)
        f2t_factory_flush_complete()
        return
    end

    local number = f2t_factory.current_number
    f2t_debug_log("[factory] Flushing factory %d", number)

    send(string.format("flush factory %d", number), false)
    deleteLine()

    f2t_factory.flush_watchdog_id = tempTimer(FLUSH_STEP_TIMEOUT, function()
        f2t_factory.flush_watchdog_id = nil
        if not f2t_factory.flushing or f2t_factory.current_number ~= number then return end

        local count = f2t_factory.flush_count
        f2t_debug_log("[factory] No response flushing factory %d, aborting", number)
        f2t_factory_flush_stop()
        cecho(string.format(
            "\n<red>[factory]<reset> No response flushing factory %d; flush stopped after %d cleared\n",
            number, count))
    end)
end

function f2t_factory_flush_complete()
    local count = f2t_factory.flush_count

    f2t_factory_flush_stop()

    f2t_debug_log("[factory] Completed flushing %d factories", count)

    if count == 0 then
        cecho("\n<yellow>[factory]<reset> No factories found to flush\n")
    elseif count == 1 then
        cecho("\n<green>[factory]<reset> Flushed 1 factory\n")
    else
        cecho(string.format("\n<green>[factory]<reset> Flushed %d factories\n", count))
    end
end
