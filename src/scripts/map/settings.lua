-- fed2-tools map — settings registration

f2t_settings_register("map", "enabled", {
    tab         = "Fed2-Tools/Map",
    description = "Enable/disable auto-mapping",
    default     = true,
})

f2t_settings_register("map", "planet_nav_default", {
    description = "Default destination when navigating to a planet (shuttlepad, orbit, or exchange)",
    default     = "shuttlepad",
    choices     = {"shuttlepad", "orbit", "exchange"},
})

f2t_settings_register("map", "speedwalk_timeout", {
    description = "Seconds to wait for movement confirmation before treating speedwalk as stuck",
    default     = 3,
    min = 1, max = 10,
})

f2t_settings_register("map", "speedwalk_max_retries", {
    description = "Maximum retry attempts before stopping a stuck speedwalk",
    default     = 3,
    min = 1, max = 10,
})

f2t_settings_register("map", "speedwalk_brief", {
    description = "Use brief room descriptions during speedwalk",
    default     = true,
})

f2t_settings_register("map", "speedwalk_after_mode", {
    description = "Room description mode to restore after speedwalk ends",
    default     = "full",
    choices     = {"brief", "full"},
})

f2t_settings_register("map", "map_manual_confirm", {
    description = "Require confirmation for destructive manual mapping operations",
    default     = true,
})

f2t_settings_register("map", "area_zoom", {
    description = "Default zoom level for new map areas",
    default     = 10,
    min = 3, max = 50,
})

f2t_settings_register("map", "brief_additional_flags", {
    description = "Extra room flags to capture in brief mode (shuttlepad always included)",
    default     = "exchange, courier",
})

f2t_settings_register("map", "orbit_planet_initial", {
    description = "Use the first letter of the planet name as the orbit room label instead of 'O'",
    default     = true,
})

f2t_settings_register("map", "movement_keys", {
    description = "Enable numpad keys for directional movement",
    default     = true,
})
