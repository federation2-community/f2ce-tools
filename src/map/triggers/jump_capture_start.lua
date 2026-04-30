-- Detect start of jump output (Inter-Cartel or Local destinations header)
-- @patterns:
--   - pattern: Inter-Cartel destinations available:
--     type: substring
--   - pattern: Local destinations available:
--     type: substring

-- Fire on first header (expecting) or subsequent headers (active)
if F2T_MAP_JUMP_CAPTURE and (F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active) then
    tempLineTrigger(0, 2, [[deleteLine()]])
    F2T_MAP_JUMP_CAPTURE.active = true
    F2T_MAP_JUMP_CAPTURE.expecting = false
    F2T_MAP_JUMP_CAPTURE.in_output = true
    f2t_debug_log("[map] Jump capture: header detected")
    f2t_map_jump_reset_timer()
end
