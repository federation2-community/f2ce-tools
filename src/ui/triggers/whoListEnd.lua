-- @patterns:
--   - pattern: ^\d+ players, \d+ staff
--     type: regex

if UI.who.parsing then
  ui_who_end()
  deleteLine()
end