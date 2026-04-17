-- @patterns:
--   - pattern: ^(.+)$
--     type: regex

if UI.galaxy and UI.galaxy.capture_active then
  ui_galaxy_capture_line(matches[2])
  deleteLine()
end