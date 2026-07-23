-- f2ce-tools death monitor — bootstrap
--
-- Auto-starts monitoring when death_monitor_enabled is true.  Deferred inside
-- the muxletReady handler (after the settings flush) so the persisted value is
-- read.  start_monitoring is self-contained: it registers both the previous-room
-- tracking handler and the critical-stamina vitals handler.
--
-- Recovery calls into hauling and the map explorer to halt automation on death;
-- those calls are all guarded, so this module runs fine standalone.

registerAnonymousEventHandler("muxletReady", function()
    tempTimer(0.5, function()
        if f2t_settings_get("death", "enabled") and f2t_death_start_monitoring then
            f2t_death_start_monitoring()
            f2t_debug_log("[death] Monitoring auto-started")
        else
            f2t_debug_log("[death] Monitoring not started (disabled)")
        end
    end)
end)