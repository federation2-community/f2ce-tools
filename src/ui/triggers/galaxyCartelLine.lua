-- @patterns:
--   - pattern: ^···(.+)$
--     type: regex

if UI.galaxy and UI.galaxy.cartel_capture_active then
    ui_galaxy_capture_cartel_line(matches[2])
end