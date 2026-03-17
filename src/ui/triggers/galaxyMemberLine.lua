-- @patterns:
--   - pattern: ^······(.+)$
--     type: regex

if UI.galaxy and UI.galaxy.member_capture_active then
    ui_galaxy_capture_member_line(matches[2])
end