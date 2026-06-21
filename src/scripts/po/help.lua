-- Help registration for planet owner commands
f2t_register_help("po", {
    description = "Planet owner tools for managing your planets",
    usage = {
        {cmd = "po economy", desc = "Show exchange economy for current planet"},
        {cmd = "po economy <planet>", desc = "Show economy for a specific planet"},
        {cmd = "po economy <group>", desc = "Filter by commodity group"},
        {cmd = "po economy <planet> <group>", desc = "Planet + group filter"},
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

f2t_debug_log("[po] Help registered")