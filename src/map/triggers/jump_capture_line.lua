-- Capture indented destination lines during jump output
-- @patterns:
--   - pattern: ^\s+(\S.*)$
--     type: regex

if F2T_MAP_JUMP_CAPTURE and F2T_MAP_JUMP_CAPTURE.active and F2T_MAP_JUMP_CAPTURE.in_output then
    tempLineTrigger(0, 2, [[deleteLine()]])
    local destination = matches[2]:match("^(.-)%s*$")  -- Trim trailing whitespace
    if destination and destination ~= "" then
        f2t_debug_log("[map] Captured destination: %s", destination)
        f2t_map_add_jump_destination(destination)
    end
    f2t_map_jump_reset_timer()
end
