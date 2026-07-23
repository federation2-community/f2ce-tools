-- f2ce-tools factory — help registration

f2t_register_help("factory", {
    description = "Manage your factories: view status, flush production, and configure settings",
    usage = {
        { cmd = "factory status",   desc = "Display all factory statuses" },
        { cmd = "factory flush",    desc = "Flush all factories to market" },
        { cmd = "factory settings", desc = "Manage factory settings" },
        { cmd = "", desc = "" },
        { cmd = "fac status",       desc = "Short form" },
        { cmd = "fac flush",        desc = "Short form" },
    },
    examples = {
        "factory status              # View comprehensive factory table",
        "factory flush               # Send all production to market",
        "factory settings            # View all settings",
        "factory settings set auto_flush_before_reset true",
        "                            # Enable auto-flush before game reset",
        "",
        "fac status                  # Quick status check",
        "fac flush                   # Quick flush all",
    },
})

f2t_debug_log("[factory] Registered help")