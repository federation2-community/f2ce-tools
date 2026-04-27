-- Register help for all ui component commands
-- This file runs during initialization to populate the help registry

-- ========================================
-- ui Command
-- ========================================

f2t_register_help("ui", {
    description = "Federation 2 UI - Frames, Movable Tabs, Status Displays, Output Windows, and Helpful Buttons",
    usage = {
        {cmd = "ui", desc = "Show UI status"},
        {cmd = "ui on", desc = "Enable UI (show elements, enable triggers/aliases/events)"},
        {cmd = "ui off", desc = "Disable UI (hide elements, disable triggers/aliases/events)"},
        {cmd = "ui status", desc = "Show detailed UI status"},
        {cmd = "ui settings", desc = "List all UI settings"},
        {cmd = "ui settings set hide_movement_messages <true|false>", desc = "Hide player/ship movement messages from main console (default: true)"},
    },
    examples = {
        "ui off    # Hide UI for clean gameplay",
        "ui on     # Restore UI",
        "ui settings set hide_movement_messages false  # Show movements in main console too",
    }
})

f2t_register_help("ui settings", {
    description = "Manage UI component settings",
    usage = {
        {cmd = "ui settings", desc = "List all settings"},
        {cmd = "ui settings get <name>", desc = "Get a setting value"},
        {cmd = "ui settings set <name> <value>", desc = "Set a setting value"},
        {cmd = "ui settings clear <name>", desc = "Reset a setting to default"},
    },
    examples = {
        "ui settings set hide_movement_messages false  # Show movements in main console",
        "ui settings set hide_movement_messages true   # Route movements to General tab only",
        "ui settings clear hide_movement_messages      # Reset to default (true)",
    }
})

f2t_debug_log("[ui] Registered help for ui commands")
