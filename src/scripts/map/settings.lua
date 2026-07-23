-- f2ce-tools map — settings registration

f2t_settings_register("map", "enabled", {
    tab         = "F2CE-Tools/Map",
    label       = "Enable mapping",
    description = "Enable/disable auto-mapping",
    default     = true,
})

f2t_settings_register("map", "planet_nav_default", {
    label       = "Planet nav default",
    description = "Default destination when navigating to a planet (shuttlepad, orbit, or exchange)",
    default     = "shuttlepad",
    choices     = {"shuttlepad", "orbit", "exchange"},
})

f2t_settings_register("map", "speedwalk_timeout", {
    label       = "Speedwalk timeout (s)",
    description = "Seconds to wait for movement confirmation before treating speedwalk as stuck",
    default     = 3,
    min = 1, max = 10,
})

f2t_settings_register("map", "speedwalk_max_retries", {
    label       = "Speedwalk max retries",
    description = "Maximum retry attempts before stopping a stuck speedwalk",
    default     = 3,
    min = 1, max = 10,
})

f2t_settings_register("map", "speedwalk_brief", {
    label       = "Brief during speedwalk",
    description = "Use brief room descriptions during speedwalk",
    default     = true,
})

f2t_settings_register("map", "speedwalk_after_mode", {
    label       = "Mode after speedwalk",
    description = "Room description mode to restore after speedwalk ends",
    default     = "full",
    choices     = {"brief", "full"},
})

f2t_settings_register("map", "map_manual_confirm", {
    label       = "Confirm manual ops",
    description = "Require confirmation for destructive manual mapping operations",
    default     = true,
})

f2t_settings_register("map", "area_zoom", {
    label       = "Default area zoom",
    description = "Default zoom level for new map areas",
    default     = 10,
    min = 3, max = 50,
})

f2t_settings_register("map", "brief_additional_flags", {
    label       = "Brief extra flags",
    description = "Extra room flags to capture in brief mode (shuttlepad always included)",
    default     = "exchange, courier",
})

f2t_settings_register("map", "orbit_planet_initial", {
    label       = "Orbit room initial",
    description = "Use the first letter of the planet name as the orbit room label instead of 'O'",
    default     = true,
})

f2t_settings_register("map", "movement_keys", {
    label       = "Numpad movement",
    description = "Enable numpad keys for directional movement",
    default     = true,
})

f2t_settings_register("map", "topology_auto_sync", {
    label       = "Topology auto-sync",
    description = "Automatically run 'display cartels'/'display syndicates' when the jump model proves stale",
    default     = true,
})

-- Gates the map import dialog. Independent of the Mudlet map's actual room
-- count — the map always has at least the current room once mapping is
-- enabled, so room count can't signal "first run". A plain on/off toggle
-- (rather than a version-number stepper) so it's an intuitive control from
-- F2CE-Tools/Map: turn it on to see the import prompt again next time the map
-- content loads. import_check.lua flips it back on by itself whenever a newer
-- bundled map database ships, even if the user had turned it off.
f2t_settings_register("map", "show_import_prompt", {
    label       = "Show map import prompt",
    description = "Offer the bundled map-database import dialog next time the map loads. "
        .. "Turns itself back on when a new map database ships.",
    default     = true,
})
