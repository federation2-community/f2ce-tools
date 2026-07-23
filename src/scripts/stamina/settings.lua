-- f2ce-tools stamina monitor — settings registration
--
-- Namespace "stamina" (own module).  Muxlet stores the settings-UI tab path
-- per namespace on first registration, so each module must use its own
-- namespace to get its own tab — see note below.  Legacy `validator` closures
-- are dropped; the widget enforces min/max and the game rejects bad locations.
--
-- threshold = 0 disables stamina monitoring; 1-99 enables auto-eat at that %.

f2t_settings_register("stamina", "threshold", {
    tab         = "F2CE-Tools/Misc",
    order       = 3,
    label       = "Auto-eat threshold (%)",
    description = "Stamina % that triggers food buying (0 = disabled, 1-99 = trigger at this %)",
    default     = 25,
    min = 0, max = 99,
})

f2t_settings_register("stamina", "food_source", {
    label       = "Food source",
    description = "Food source location: Fed2 room hash (system.planet.num) or a saved destination name",
    default     = "Sol.Earth.454",
})