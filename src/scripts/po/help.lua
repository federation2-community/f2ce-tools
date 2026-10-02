-- Help registration for planet owner commands
f2t_register_help("po", {
    description = "Planet owner tools for managing your planets",
    usage = {
        {cmd = "po economy", desc = "Show exchange economy for current planet"},
        {cmd = "po economy <planet>", desc = "Show economy for a specific planet"},
        {cmd = "po economy <group>", desc = "Filter by commodity group"},
        {cmd = "po economy <planet> <group>", desc = "Planet + group filter"},
        {cmd = "", desc = ""},
        {cmd = "po stockpile", desc = "Plan and apply exchange stock levels and spreads (po stockpile help)"},
        {cmd = "", desc = ""},
        {cmd = "po settings", desc = "Manage po settings"}
    },
    examples = {
        "po economy",
        "po economy Earth",
        "po economy agri",
        "po economy Earth tech",
        "",
        "Groups: " .. table.concat(f2t_po_get_valid_groups(), ", ")
    }
})

f2t_register_help("po stockpile", {
    description = "Set each commodity's min/max stock and spread on an owned exchange from its net "
        .. "production. Preview first; nothing changes until you apply.",
    usage = {
        {cmd = "po sp preview", desc = "Plan changes for the planet you're on"},
        {cmd = "po sp preview <planet>", desc = "Plan changes for an owned planet remotely"},
        {cmd = "po sp show", desc = "Show the last preview again"},
        {cmd = "po sp apply", desc = "Apply the last preview (within 5 minutes)"},
        {cmd = "po sp cancel", desc = "Stop an update in progress"},
        {cmd = "po sp status", desc = "Show state, targets and exclusions"},
        {cmd = "", desc = ""},
        {cmd = "po sp target add|remove <planet>", desc = "Planets for auto mode and the Stockpiles tab"},
        {cmd = "po sp target list|clear", desc = ""},
        {cmd = "po sp exclude add|remove <commodity>", desc = "Commodities never changed"},
        {cmd = "po sp exclude list|clear", desc = ""},
        {cmd = "po sp auto on|off", desc = "Preview+apply every target on a timer (this session only)"},
        {cmd = "po sp auto run", desc = "Run one pass over the targets now"},
        {cmd = "", desc = ""},
        {cmd = "Policy:", desc = "po settings (stockpile_*), or Settings > F2CE-Tools > Planet Owner"},
        {cmd = "  Deficit (net < 0)", desc = "deficit min/max/spread (default 0/0/6%)"},
        {cmd = "  Breakeven (net = 0)", desc = "breakeven min/max/spread (default 0/0/6%)"},
        {cmd = "  Surplus, stock < trigger", desc = "min = stock, max = stock + growth buffer, surplus spread"},
        {cmd = "  Surplus, stock >= trigger", desc = "reserve min/max (default 10000/20000), surplus spread"}
    },
    examples = {
        "po sp preview",
        "po sp preview Tempest",
        "po sp apply",
        "po sp target add Tempest",
        "po sp exclude add Gold",
        "po settings set stockpile_surplus_spread 30",
        "",
        "Planning policy adapted from Exchange Walker by Ersella."
    }
})

f2t_debug_log("[po] Help registered")