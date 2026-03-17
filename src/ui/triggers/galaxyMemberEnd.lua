-- @patterns:
--   - pattern: ^   (Cartel is|Cartel queues|Blish Cities:|The cartel has)
--     type: regex

if UI.galaxy and UI.galaxy.member_capture_active then
    ui_galaxy_finish_member_capture()
end