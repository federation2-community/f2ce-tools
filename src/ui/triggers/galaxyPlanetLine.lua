-- @patterns:
--   - pattern: ^(.+),·(.+)·system,·(.+)·cartel$
--     type: regex

if UI.galaxy and UI.galaxy.planet_capture_active then
    ui_galaxy_capture_planet_line(matches[2], matches[3], matches[4])
end