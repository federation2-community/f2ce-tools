-- @patterns:
--   - pattern: ^$
--     type: regex

if UI.galaxy and UI.galaxy.capture_active then
  ui_galaxy_finish_capture()
  deleteLine()
end