-- Stamina Component Help Registration

f2t_register_help("stamina", {
    description = "Stamina monitor: walks to a bar and eats when stamina runs low",
    usage = {
        {cmd = "stamina", desc = "Show stamina, settings and any food run under way"},
        {cmd = "stamina eat", desc = "Eat until full now: walk to the bar, eat, walk back"},
        {cmd = "stamina cancel", desc = "Stop a food run (a paused haul stays paused)"},
        {cmd = "stamina settings", desc = "List or change stamina settings"},
        {cmd = "", desc = ""},
        {cmd = "Settings:", desc = ""},
        {cmd = "  threshold", desc = "Stamina % that starts a food run (0 = only when you ask)"},
        {cmd = "  food_source", desc = "nearest, a saved destination, or system.planet.num"},
        {cmd = "  sustenance", desc = "food, pizza or round (see below)"},
        {cmd = "  unattended", desc = "Go eat without asking when nothing automated is running"},
        {cmd = "", desc = ""},
        {cmd = "Sustenance (bars only):", desc = ""},
        {cmd = "  food", desc = "+5 stamina for 10ig, just you"},
        {cmd = "  pizza", desc = "+5 for everyone in the bar, 10ig a head"},
        {cmd = "  round", desc = "+2 for everyone in the bar, 5ig a head"},
        {cmd = "", desc = ""},
        {cmd = "Stamina drops by 1 every 80 moves on a planet surface, never in space.", desc = ""},
        {cmd = "Hauling and exploring pause for the food run and resume after it.", desc = ""},
    },
    examples = {
        "stamina                              # Where things stand",
        "stamina eat                          # Top up now",
        "stamina settings set sustenance round # Buy the bar a round instead",
        "stamina settings set food_source nearest",
    }
})
