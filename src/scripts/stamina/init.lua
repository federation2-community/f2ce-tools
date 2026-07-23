-- f2ce-tools stamina monitor — bootstrap
--
-- Auto-starts monitoring when stamina_threshold > 0.  The read is deferred to a
-- short timer inside the muxletReady handler so it runs after init.lua's
-- settings flush, giving the persisted threshold rather than a default.
--
-- The monitor also exposes a client API (register/unregister/cancel) that the
-- map explorer and hauling engine call when present; installing this module is
-- what lights up their auto-pause-to-eat behaviour.

registerAnonymousEventHandler("muxletReady", function()
    tempTimer(0.5, function()
        local threshold = f2t_settings_get("stamina", "threshold") or 0
        if threshold > 0 and f2t_stamina_start_monitoring then
            f2t_stamina_start_monitoring()
            f2t_debug_log("[stamina] Monitoring auto-started (threshold=%d%%)", threshold)
        else
            f2t_debug_log("[stamina] Monitoring not started (threshold=%d)", threshold)
        end
    end)
end)