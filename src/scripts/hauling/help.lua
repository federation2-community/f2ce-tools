-- Hauling Component Help Registration

f2t_register_help("haul", {
    description = "Automated commodity trading (rank-dependent mode)",
    usage = {
        {cmd = "haul start", desc = "Start hauling (auto-detects mode by rank)"},
        {cmd = "haul start exchange", desc = "Force exchange mode (Founder+ only)"},
        {cmd = "haul stop", desc = "Gracefully stop (finish selling cargo first)"},
        {cmd = "haul terminate", desc = "Stop immediately without finishing cycle"},
        {cmd = "", desc = ""},
        {cmd = "haul pause", desc = "Pause hauling (can resume)"},
        {cmd = "haul resume", desc = "Resume paused hauling"},
        {cmd = "", desc = ""},
        {cmd = "haul status", desc = "Show current hauling state and statistics"},
        {cmd = "", desc = ""},
        {cmd = "haul settings", desc = "Manage settings (margin_threshold, cycle_pause)"}
    },
    examples = {
        "haul start              # Begin automated trading",
        "haul start exchange     # Force exchange mode (Founder+)",
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