-- f2ce-tools factory — initialization and capture control
--
-- Owns the factory state table and the capture/query state machine.  Display
-- formatting lives in formatter.lua, line parsing in parser.lua, the capture
-- completion timer in capture_timer.lua, and the flush sequence in flush.lua.
--
-- Capture model: "display factory N" is sent for N = 1..max_factories, one at a
-- time.  Output lines are gathered by the capture trigger into capture_buffer;
-- a debounce timer (capture_timer.lua) decides when one factory's block is done
-- and advances to the next.  max_factories is rank-derived (Manufacturer = 15,
-- Industrialist = 8).

-- f2ce-tools factory — settings registration
--
-- Registered into the Muxlet settings system via the shared settings layer.
-- The "enabled" toggle makes the whole feature optional and consistent with
-- the map module's F2T_*_ENABLED pattern; "auto_flush_before_reset" preserves
-- the legacy auto-flush behaviour.

f2t_settings_register("factory", "enabled", {
    tab         = "F2CE-Tools/Misc",
    order       = 5,
    label       = "Factory commands",
    description = "Enable factory status/flush commands and the pre-reset auto-flush",
    default     = true,
})

f2t_settings_register("factory", "auto_flush_before_reset", {
    label       = "Auto-flush before reset",
    description = "Automatically flush all factories before the daily game reset",
    default     = false,
})

F2T_FACTORY_ENABLED = f2t_settings_get("factory", "enabled")

f2t_factory = f2t_factory or {
    capturing         = false,
    current_number    = 0,
    max_factories     = 8,   -- rank-derived at capture/flush start
    current_data      = {},
    factories         = {},
    capture_buffer    = {},
    flushing          = false,
    flush_count       = 0,
    shutdown_timer_id = nil,
}

f2t_debug_log("[factory] Initialized (enabled=%s, auto_flush=%s)",
    tostring(F2T_FACTORY_ENABLED),
    f2t_settings_get("factory", "auto_flush_before_reset") and "ENABLED" or "DISABLED")

-- ── Rank-derived factory slot count ───────────────────────────────────────────

local function factorySlotCount()
    return f2t_is_rank_exactly("Manufacturer") and 15 or 8
end

-- ── State reset ───────────────────────────────────────────────────────────────

function f2t_factory_reset()
    f2t_factory.capturing      = false
    f2t_factory.current_number = 0
    f2t_factory.max_factories  = 8
    f2t_factory.current_data   = {}
    f2t_factory.factories      = {}
    f2t_factory.capture_buffer = {}
    f2t_factory.flushing       = false
    f2t_factory.flush_count    = 0
    f2t_debug_log("[factory] Reset factory data")
end

-- ── Capture sequence ──────────────────────────────────────────────────────────

function f2t_factory_start_capture()
    if f2t_factory.capturing then
        cecho("\n<yellow>[factory]<reset> Factory status already in progress, please wait...\n")
        return false
    end
    if f2t_factory.flushing then
        cecho("\n<yellow>[factory]<reset> Factory flush in progress, please wait...\n")
        return false
    end

    f2t_factory_reset()
    f2t_factory.capturing     = true
    f2t_factory.capture_buffer = {}
    f2t_factory.max_factories  = factorySlotCount()

    f2t_debug_log("[factory] Starting capture (max: %d)", f2t_factory.max_factories)

    f2t_factory_query_next()
    return true
end

function f2t_factory_query_next()
    if not f2t_factory.capturing then
        f2t_debug_log("[factory] WARNING: query_next called while not capturing")
        return
    end

    f2t_factory.current_number = f2t_factory.current_number + 1
    f2t_factory.capture_buffer = {}

    if f2t_factory.current_number > f2t_factory.max_factories then
        f2t_debug_log("[factory] Reached max factories (%d), completing", f2t_factory.max_factories)
        f2t_factory_complete()
        return
    end

    f2t_debug_log("[factory] Querying factory %d", f2t_factory.current_number)

    send(string.format("display factory %d", f2t_factory.current_number), false)
    deleteLine()
end
