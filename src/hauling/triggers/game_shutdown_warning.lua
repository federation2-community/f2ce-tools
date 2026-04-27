-- Trigger for game shutdown warning to immediately stop hauling
-- @patterns:
--   - pattern: ^Federation II will be closing down for a short while in six minutes time\.$
--     type: regex

-- Only act if hauling is currently active
if not F2T_HAULING_STATE or not F2T_HAULING_STATE.active then
    return
end

f2t_debug_log("[hauling] Shutdown warning received, stopping immediately")
cecho("\n<yellow>[hauling]<reset> Game shutdown warning - stopping hauling immediately\n")
f2t_hauling_stop()
