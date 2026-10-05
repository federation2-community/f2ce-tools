-- f2ce-tools stamina monitor — settings registration
--
-- Namespace "stamina" (own module).  Muxlet stores the settings-UI tab path
-- per namespace on first registration, so each module must use its own
-- namespace to get its own tab.
--
-- threshold = 0 disables automatic food runs; the Eat button still works.

f2t_settings_register("stamina", "threshold", {
    tab         = "F2CE-Tools/Misc",
    order       = 3,
    label       = "Auto-eat threshold (%)",
    description = "Stamina % that triggers a food run (0 = never automatically, 1-99 = at or below this %)",
    default     = 25,
    min = 0, max = 99,
})

f2t_settings_register("stamina", "food_source", {
    label       = "Food source",
    description = "Where to eat: nearest (closest mapped bar), a saved destination name, "
        .. "or a Fed2 room hash (system.planet.num)",
    default     = "nearest",
})

f2t_settings_register("stamina", "sustenance", {
    label       = "Sustenance",
    description = "food: +5 stamina for 10ig, just you. pizza: +5 for everyone in the bar, 10ig a head. "
        .. "round: +2 for everyone in the bar, 5ig a head",
    default     = "food",
    choices     = { "food", "pizza", "round" },
})

f2t_settings_register("stamina", "unattended", {
    label       = "Eat without asking",
    description = "With nothing automated running, go eat at the threshold instead of asking yes/no first",
    default     = false,
})
