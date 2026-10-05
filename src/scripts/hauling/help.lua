-- Hauling Component Help Registration

f2t_register_help("haul", {
    description = "Automated hauling and trading (mode depends on rank)",
    usage = {
        {cmd = "haul start [mode]", desc = "Start hauling in the given mode, or the 'haul mode' default"},
        {cmd = "haul stop", desc = "Gracefully stop (finish the current job or cargo first)"},
        {cmd = "haul terminate", desc = "Stop immediately without finishing cycle"},
        {cmd = "", desc = ""},
        {cmd = "haul pause", desc = "Pause hauling (can resume)"},
        {cmd = "haul resume", desc = "Resume paused hauling"},
        {cmd = "", desc = ""},
        {cmd = "haul mode [mode]", desc = "Show or set what 'haul start' runs"},
        {cmd = "haul status", desc = "Show current hauling state and statistics"},
        {cmd = "haul settings", desc = "List or change hauling settings (mode, thresholds, safe room, ...)"},
        {cmd = "", desc = ""},
        {cmd = "Modes:", desc = ""},
        {cmd = "  auto", desc = "Your rank's default (the one listed first below)"},
        {cmd = "  ac", desc = "Armstrong Cuthbert cargo jobs (Commander, Captain)"},
        {cmd = "  akaturi", desc = "Akaturi courier contracts (Adventurer)"},
        {cmd = "  exchange", desc = "Exchange trading (Merchant to Manufacturer, Founder+; not Financier)"},
        {cmd = "  planet", desc = "Supply your planets' deficits, sell their excesses (Founder+)"},
        {cmd = "  deficit", desc = "Supply your planets' deficits only (Founder+)"},
    },
    examples = {
        "haul start              # Start in your 'haul mode' default",
        "haul start exchange     # Trade the cartel's exchanges this session (Founder+)",
        "haul mode deficit       # Make deficits-only the default (Founder+)",
        "haul pause              # Pause at current step",
        "haul resume             # Continue from pause",
        "",
        "haul stop               # Finish cycle then stop",
        "haul term               # Stop immediately",
        "",
        "haul settings           # List all settings",
        "haul settings set margin_threshold 25  # Set min profit margin to 25%",
        "haul settings set cycle_pause 60      # Pause 60s after trading 5 commodities"
    }
})
