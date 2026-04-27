-- Register help for all map component commands
-- This file runs during initialization to populate the help registry

-- ========================================
-- Map Command
-- ========================================

f2t_register_help("map", {
    description = "Federation 2 Mapper - Auto-mapping, navigation, and destinations",
    usage = {
        {cmd = "Map Control:", desc = ""},
        {cmd = "map on", desc = "Enable auto-mapping"},
        {cmd = "map off", desc = "Disable auto-mapping"},
        {cmd = "map sync", desc = "Force sync current location with GMCP"},
        {cmd = "map clear", desc = "Clear entire map (requires confirmation)"},
        {cmd = "map confirm", desc = "Confirm pending destructive operation"},
        {cmd = "map cancel", desc = "Cancel pending confirmation"},
        {cmd = "", desc = ""},
        {cmd = "Diagnostics:", desc = ""},
        {cmd = "map raw", desc = "Show raw mapper + GMCP data (current room)"},
        {cmd = "map raw <room_id>", desc = "Show raw mapper data for specified room"},
        {cmd = "", desc = ""},
        {cmd = "Settings:", desc = ""},
        {cmd = "map settings", desc = "List all mapper settings"},
        {cmd = "map settings get <name>", desc = "Get a specific setting"},
        {cmd = "map settings set <name> <value>", desc = "Set a setting"},
        {cmd = "map settings clear <name>", desc = "Reset to default"},
        {cmd = "", desc = ""},
        {cmd = "Saved Destinations:", desc = ""},
        {cmd = "map dest", desc = "List all saved destinations"},
        {cmd = "map dest add <name>", desc = "Save current location"},
        {cmd = "map dest remove <name>", desc = "Remove destination"},
        {cmd = "", desc = ""},
        {cmd = "Search Rooms:", desc = ""},
        {cmd = "map search <text>", desc = "Search current area for room name"},
        {cmd = "map search <planet|system> <text>", desc = "Search planet or system"},
        {cmd = "map search all <text>", desc = "Search all areas"},
        {cmd = "", desc = ""},
        {cmd = "Exploration:", desc = ""},
        {cmd = "map explore", desc = "Context-aware exploration (brief mode)"},
        {cmd = "map explore [target]", desc = "Explore planet or system (auto-detect, brief)"},
        {cmd = "map explore full [target]", desc = "Full exploration (all rooms)"},
        {cmd = "map explore brief [target]", desc = "Brief exploration (flag discovery)"},
        {cmd = "map explore cartel [name]", desc = "Explore all systems in cartel"},
        {cmd = "map explore galaxy", desc = "Explore all cartels in galaxy"},
        {cmd = "", desc = ""},
        {cmd = "Import/Export:", desc = ""},
        {cmd = "map export", desc = "Export map to JSON file (file dialog)"},
        {cmd = "map import", desc = "Import map (shows summary, use 'map confirm')"},
        {cmd = "", desc = ""},
        {cmd = "Manual Mapping (Supplement Auto-Map):", desc = ""},
        {cmd = "map room", desc = "Create/delete/edit/lock rooms"},
        {cmd = "map exit", desc = "Add/remove/lock exits (standard + special)"},
        {cmd = "", desc = ""},
        {cmd = "Special Navigation:", desc = ""},
        {cmd = "map special arrival", desc = "Configure on-arrival commands"},
        {cmd = "map special circuit", desc = "Configure circuit travel"}
    },
    examples = {
        "map dest add home                   # Save current room as \"home\" destination",
        "nav home                            # Navigate to saved destination",
        "nav Earth                           # Navigate to Earth",
        "map explore                         # Context-aware brief exploration",
        "map explore Coffee                  # Explore Coffee (auto-detect system)",
        "map explore full                    # Full exploration of current area",
        "map explore brief Earth             # Brief exploration of Earth",
        "map settings set planet_nav_default orbit  # Default to orbit",
        "map search exchange                 # Search for exchange in current area",
        "map search Earth landing            # Search for landing on Earth",
        "map search all park                 # Search all areas for park"
    }
})

-- ========================================
-- Saved Destinations
-- ========================================

f2t_register_help("map dest", {
    description = "Manage saved destinations for quick navigation",
    usage = {
        {cmd = "map dest", desc = "List all saved destinations"},
        {cmd = "map dest add <name>", desc = "Save current location as destination"},
        {cmd = "map dest remove <name>", desc = "Remove a saved destination"},
        {cmd = "map dest list", desc = "List all saved destinations"}
    },
    examples = {
        "map dest add home         # Save current room as 'home'",
        "map dest add earth_ex     # Save current room as 'earth_ex'",
        "map dest remove home      # Remove 'home' destination",
        "map dest                  # List all destinations"
    }
})

-- ========================================
-- Settings
-- ========================================

f2t_register_help("map settings", {
    description = "Manage mapper settings",
    usage = {
        {cmd = "map settings", desc = "List all mapper settings"},
        {cmd = "map settings get <name>", desc = "Get a specific setting"},
        {cmd = "map settings set <name> <value>", desc = "Set a setting"},
        {cmd = "map settings clear <name>", desc = "Reset setting to default"}
    },
    examples = {
        "map settings                              # List all settings",
        "map settings get planet_nav_default       # Check planet navigation default",
        "map settings set planet_nav_default orbit # Default to orbit",
        "map settings set enabled false            # Disable auto-mapping",
        "map settings clear planet_nav_default     # Reset to default"
    }
})

-- ========================================
-- Raw Diagnostics
-- ========================================

f2t_register_help("map raw", {
    description = "Display raw mapper and GMCP data for diagnostics",
    usage = {
        {cmd = "map raw", desc = "Show mapper + GMCP data for current room"},
        {cmd = "map raw <room_id>", desc = "Show mapper data for specified room"}
    },
    examples = {
        "map raw        # Show current room's raw data",
        "map raw 1234   # Show room 1234's raw data"
    }
})

-- ========================================
-- Navigation Commands
-- ========================================

f2t_register_help("nav", {
    description = "Navigate to a destination using speedwalk",
    usage = {
        {cmd = "nav <destination>",         desc = "Navigate to saved destination"},
        {cmd = "nav <room_id>",             desc = "Navigate to Mudlet room ID"},
        {cmd = "nav <system>.<area>.<num>", desc = "Navigate to Fed2 hash"},
        {cmd = "nav <planet>",              desc = "Navigate to planet's shuttlepad"},
        {cmd = "nav <system>",              desc = "Navigate to system's link"},
        {cmd = "nav <flag>",                desc = "Navigate to flag in current area"},
        {cmd = "nav <area> <flag>",         desc = "Navigate to flag in specified area"},
        {cmd = "", desc = ""},
        {cmd = "nav info <location>",                       desc = "Get navigation info from current room to location"},
        {cmd = "nav info <area> <flag>",                    desc = "Get navigation info from current room to flag in specified area"},
        {cmd = "nav info <locationA> to <locationB>",       desc = "Get navigation info from locationA to locationB"},
        {cmd = "nav info <areaA> <flag> to <areaB> <flag>", desc = "Get navigation info from flag in areaA to flag in areaB"},
        {cmd = "", desc = ""},
        {cmd = "nav stop",   desc = "Stop active speedwalk"},
        {cmd = "nav pause",  desc = "Pause active speedwalk"},
        {cmd = "nav resume", desc = "Resume paused speedwalk"}
    },
    examples = {
        "nav earth_ex         # Navigate to saved 'earth_ex' destination",
        "nav Earth            # Navigate to Earth's shuttlepad",
        "nav Sol              # Navigate to Sol system link",
        "nav exchange         # Navigate to exchange in current area",
        "nav Earth exchange   # Navigate to Earth's exchange",
        "nav Coffee.Latte.459 # Navigate to specific Fed2 hash",
        "",
        "nav info exchange              # Get navigation info to exchange in current area",
        "nav info mars sp               # Get navigation info from current location to shuttlepad in mars area",
        "nav info brass to vega         # Get navigation info from brass to vega",
        "nav info titan ac to earth bar # Get navigation info from Armstrong Cuthbert office in titan area to Starship Cantina in earth area",
        "",
        "nav pause  # Pause current speedwalk",
        "nav resume # Continue paused speedwalk",
        "nav stop   # Cancel speedwalk completely"
    }
})

f2t_register_help("nav stop", {
    description = "Stop active speedwalk navigation",
    usage = {
        {cmd = "nav stop", desc = "Stop speedwalk completely (clears path)"}
    },
    examples = {
        "nav stop    # Cancel speedwalk and clear path"
    }
})

f2t_register_help("nav pause", {
    description = "Pause active speedwalk navigation",
    usage = {
        {cmd = "nav pause", desc = "Pause speedwalk (keeps path for resume)"}
    },
    examples = {
        "nav pause    # Pause speedwalk, use 'nav resume' to continue"
    }
})

f2t_register_help("nav resume", {
    description = "Resume paused speedwalk navigation",
    usage = {
        {cmd = "nav resume", desc = "Resume paused speedwalk from current position"}
    },
    examples = {
        "nav resume    # Continue paused speedwalk from current position"
    }
})

-- ========================================
-- Search Rooms
-- ========================================

f2t_register_help("map search", {
    description = "Search for rooms by name in the map database",
    usage = {
        {cmd = "map search <text>", desc = "Search current area for matching rooms"},
        {cmd = "map search <planet|system> <text>", desc = "Search planet or system for rooms"},
        {cmd = "map search all <text>", desc = "Search all areas for matching rooms"}
    },
    examples = {
        "map search exchange        # Find exchange in current area",
        "map search landing          # Find rooms with 'landing' in current area",
        "map search Earth park       # Find park on Earth",
        "map search Sol customs      # Find customs in Sol system (all planets + space)",
        "map search all depot        # Find all depots across entire map"
    }
})

-- ========================================
-- Exploration
-- ========================================

f2t_register_help("map explore", {
    description = "Automatically discover unmapped rooms (planet/system/cartel/galaxy)",
    usage = {
        {cmd = "Commands:", desc = ""},
        {cmd = "map explore", desc = "Context-aware exploration (brief mode)"},
        {cmd = "map explore [target]", desc = "Explore target (auto-detect planet/system)"},
        {cmd = "map explore full [target]", desc = "Full exploration (all rooms)"},
        {cmd = "map explore brief [target]", desc = "Brief exploration (flag discovery)"},
        {cmd = "map explore cartel [name]", desc = "Explore all systems in cartel"},
        {cmd = "map explore galaxy", desc = "Explore all cartels in galaxy"},
        {cmd = "", desc = ""},
        {cmd = "Control:", desc = ""},
        {cmd = "map explore stop", desc = "Stop exploration (shows statistics)"},
        {cmd = "map explore pause", desc = "Pause exploration"},
        {cmd = "map explore resume", desc = "Resume paused exploration"},
        {cmd = "map explore status", desc = "Show current progress and statistics"},
        {cmd = "map explore suspected", desc = "List suspected special exits"},
        {cmd = "", desc = ""},
        {cmd = "Mode Options:", desc = ""},
        {cmd = "  full:  Complete DFS exploration (discovers all rooms)", desc = ""},
        {cmd = "  brief: Quick discovery (stops when targets found)", desc = ""},
        {cmd = "", desc = ""},
        {cmd = "Brief Mode Targets:", desc = ""},
        {cmd = "  Planet: Find shuttlepad + exchange, then stop", desc = ""},
        {cmd = "  System: Find expected planets, brief each planet", desc = ""},
        {cmd = "", desc = ""},
        {cmd = "Auto-Detection:", desc = ""},
        {cmd = "  Target names are auto-detected as planet or system.", desc = ""},
        {cmd = "  If a name matches both, prefer unexplored system.", desc = ""},
        {cmd = "", desc = ""},
        {cmd = "Exploration Layers:", desc = ""},
        {cmd = "  Planet (Layer 1): Single area, full or brief mode", desc = ""},
        {cmd = "  System (Layer 2): Space area + brief each planet", desc = ""},
        {cmd = "  Cartel (Layer 3): All systems, brief mode only", desc = ""},
        {cmd = "  Galaxy (Layer 4): All cartels, brief mode only", desc = ""}
    },
    examples = {
        "map explore                      # Context-aware brief exploration",
        "map explore Earth                # Explore Earth (auto-detect planet)",
        "map explore Coffee               # Explore Coffee (auto-detect system)",
        "map explore full                 # Full exploration of current area",
        "map explore brief Earth          # Brief exploration of Earth",
        "map explore full Sol             # Full exploration of Sol system",
        "map explore cartel Frontier      # Explore Frontier cartel",
        "map explore galaxy               # Explore all cartels in galaxy",
        "map explore status               # Check progress",
        "map explore pause                # Pause exploration",
        "map explore stop                 # Stop and show statistics"
    }
})

-- ========================================
-- Import/Export
-- ========================================

f2t_register_help("map export", {
    description = "Export the map to a JSON file for backup or sharing",
    usage = {
        {cmd = "map export", desc = "Opens file dialog to select save location"}
    },
    examples = {
        "map export    # Opens dialog to choose where to save the map"
    }
})

f2t_register_help("map import", {
    description = "Import a map from a JSON file",
    usage = {
        {cmd = "map import", desc = "Select file and show summary"},
        {cmd = "map confirm", desc = "Confirm and execute the import"},
        {cmd = "map cancel", desc = "Cancel the import"}
    },
    examples = {
        "map import    # Opens file dialog and shows import summary",
        "map confirm   # Confirms and imports the map (replaces current)",
        "map cancel    # Cancels the pending import"
    }
})

-- ========================================
-- Special Navigation
-- ========================================

f2t_register_help("map special", {
    description = "Configure special navigation behaviors (on-arrival commands, circuit travel)",
    usage = {
        {cmd = "map special arrival", desc = "Configure on-arrival commands"},
        {cmd = "map special circuit", desc = "Configure circuit travel"},
        {cmd = "", desc = ""},
        {cmd = "Note: For special exits, use 'map exit special' command", desc = ""}
    },
    examples = {
        "map special arrival wear tabi     # Set on-arrival command",
        "map special circuit create metro  # Create circuit for metro system"
    }
})

-- ========================================
-- On-Arrival Commands
-- ========================================

f2t_register_help("map special arrival", {
    description = "Configure commands that execute when entering a room",
    usage = {
        {cmd = "map special arrival <command>", desc = "Set command (always run)"},
        {cmd = "map special arrival <type> <command>", desc = "Set command with exec type"},
        {cmd = "map special arrival remove", desc = "Remove on-arrival command"},
        {cmd = "map special arrival list", desc = "List all rooms with on-arrival commands"},
        {cmd = "", desc = ""},
        {cmd = "Execution Types:", desc = ""},
        {cmd = "  always", desc = "Run every time (default)"},
        {cmd = "  once-room", desc = "Run once, then disable"},
        {cmd = "  once-area", desc = "Run once per area visit"},
        {cmd = "  once-ever", desc = "Run once ever, then disable"}
    },
    examples = {
        "map special arrival wear tabi              # Run every time (default)",
        "map special arrival once-room look         # Run once in this room",
        "map special arrival once-area buy permit   # Run once per area visit",
        "map special arrival once-ever register     # Run once ever",
        "map special arrival remove                 # Remove on-arrival command",
        "map special arrival list                   # Show all on-arrival commands"
    }
})

-- ========================================
-- Circuit Travel
-- ========================================

f2t_register_help("map special circuit", {
    description = "Configure circuit travel systems (trains, tubes, shuttles)",
    usage = {
        {cmd = "Circuit Management:", desc = ""},
        {cmd = "map special circuit create <id>", desc = "Create new circuit"},
        {cmd = "map special circuit delete <id>", desc = "Delete circuit"},
        {cmd = "map special circuit list", desc = "List all circuits"},
        {cmd = "map special circuit show <id>", desc = "Show circuit details"},
        {cmd = "", desc = ""},
        {cmd = "Circuit Configuration:", desc = ""},
        {cmd = "map special circuit set <id> board <cmd>", desc = "Set boarding command"},
        {cmd = "map special circuit set <id> exit <cmd>", desc = "Set exit command"},
        {cmd = "", desc = ""},
        {cmd = "Stop Management:", desc = ""},
        {cmd = "map special circuit stop add <id> <name>", desc = "Add stop to circuit"},
        {cmd = "map special circuit stop set <id> <name> arrival_pattern <pattern>", desc = "Set stop arrival pattern"},
        {cmd = "", desc = ""},
        {cmd = "Circuit Connection:", desc = ""},
        {cmd = "map special circuit connect <id>", desc = "Connect circuit stops (creates special exits)"}
    },
    examples = {
        "# Create and configure a circuit:",
        "map special circuit create metro           # Create circuit",
        "map special circuit set metro board 'board train'",
        "map special circuit set metro exit 'disembark'",
        "",
        "# Add stops (at each stop room):",
        "map special circuit stop add metro exchange",
        "map special circuit stop set metro exchange arrival_pattern 'arrived at Exchange Station'",
        "",
        "# After configuring all stops:",
        "map special circuit connect metro          # Creates all special exits",
        "",
        "# View and manage:",
        "map special circuit list                   # Show all circuits",
        "map special circuit show metro             # Show circuit details"
    }
})

-- ========================================
-- Manual Mapping Commands
-- ========================================

f2t_register_help("map room", {
    description = "Create, delete, and edit rooms (supplement auto-mapping)",
    usage = {
        {cmd = "map room add <system> <area> <num> [name]", desc = "Create new room"},
        {cmd = "map room delete <room_id>", desc = "Delete room (requires confirmation)"},
        {cmd = "map room info <room_id>", desc = "Display room properties and lock status"},
        {cmd = "", desc = ""},
        {cmd = "map room set name <room_id> <name>", desc = "Set room name"},
        {cmd = "map room set area <room_id> <area>", desc = "Move to different area"},
        {cmd = "map room set coords <room_id> <x> <y> <z>", desc = "Set coordinates"},
        {cmd = "map room set symbol <room_id> <char>", desc = "Set symbol (1 char)"},
        {cmd = "map room set color <room_id> <r> <g> <b>", desc = "Set color (RGB 0-255)"},
        {cmd = "map room set env <room_id> <env_id>", desc = "Set environment ID"},
        {cmd = "map room set weight <room_id> <weight>", desc = "Set pathfinding weight"},
        {cmd = "", desc = ""},
        {cmd = "map room lock <room_id>", desc = "Lock room (navigation avoids)"},
        {cmd = "map room unlock <room_id>", desc = "Unlock room"}
    },
    examples = {
        "map room add Coffee Latte 459 'Exchange Room'  # Create room",
        "map room info 1234                             # View room details + lock status",
        "map room set name 1234 New Name                # Rename room",
        "map room set coords 1234 10 20 0               # Reposition room",
        "map room lock 1234                             # Lock dangerous room",
        "map room delete 1234                           # Delete (requires confirm)"
    }
})

f2t_register_help("map exit", {
    description = "Manage exits (standard and special)",
    usage = {
        {cmd = "Standard Exits:", desc = ""},
        {cmd = "map exit add <from> <to> <dir>", desc = "Create one-way exit"},
        {cmd = "map exit remove <room> <dir>", desc = "Remove exit (requires confirmation)"},
        {cmd = "map exit list <room>", desc = "List all exits (standard + special)"},
        {cmd = "", desc = ""},
        {cmd = "Note: For bidirectional, use two add commands", desc = ""},
        {cmd = "", desc = ""},
        {cmd = "map exit lock [room] <dir>", desc = "Lock exit (navigation avoids)"},
        {cmd = "map exit unlock [room] <dir>", desc = "Unlock exit"},
        {cmd = "", desc = ""},
        {cmd = "Stub Exits:", desc = ""},
        {cmd = "map exit stub create [room] <dir>", desc = "Create stub exit"},
        {cmd = "map exit stub delete [room] <dir>", desc = "Delete stub exit"},
        {cmd = "map exit stub connect [room] <dir>", desc = "Connect stub to destination"},
        {cmd = "map exit stub list [room]", desc = "List all stub exits"},
        {cmd = "", desc = ""},
        {cmd = "Special Exits (Discovery Method):", desc = ""},
        {cmd = "map exit special <command>", desc = "Test command, auto-create exit"},
        {cmd = "map exit special reverse [cmd]", desc = "Create return exit"},
        {cmd = "", desc = ""},
        {cmd = "Special Exits (Manual Method):", desc = ""},
        {cmd = "map exit special <dest> <cmd>", desc = "From current to dest"},
        {cmd = "map exit special <src> <dest> <cmd>", desc = "From src to dest"},
        {cmd = "", desc = ""},
        {cmd = "Special Exits (Management):", desc = ""},
        {cmd = "map exit special list [room]", desc = "List special exits"},
        {cmd = "map exit special remove <cmd>", desc = "Remove from current"},
        {cmd = "map exit special remove <room> <cmd>", desc = "Remove from room"}
    },
    examples = {
        "# Standard exits:",
        "map exit add 123 456 north                   # One-way",
        "map exit add 456 123 south                   # Reverse (for bidirectional)",
        "map exit remove 123 north                     # Delete",
        "map exit lock north                           # Lock exit in current room",
        "map exit lock 123 north                       # Lock exit in room 123",
        "",
        "# Stub exits (placeholders for unexplored exits):",
        "map exit stub create north                   # Create stub in current room",
        "map exit stub connect north                  # Connect stub in current room",
        "map exit stub list                           # List stubs in current room",
        "",
        "# Special exits (Sumatra airlock example):",
        "map exit special press touchpad    # Discovery method",
        "map exit special reverse           # Create return",
        "map exit special noop               # Auto-transit",
        "",
        "# Manual method:",
        "map exit special 1235 press touchpad  # Current -> 1235",
        "map exit special 1235 1236 noop       # 1235 -> 1236"
    }
})

f2t_register_help("map exit special", {
    description = "Manage special exits (custom commands, auto-transit)",
    usage = {
        {cmd = "Discovery Method (RECOMMENDED):", desc = ""},
        {cmd = "map exit special <command>", desc = "Test command, auto-create exit on room change"},
        {cmd = "map exit special reverse [cmd]", desc = "Create return exit (uses last discovery)"},
        {cmd = "map exit special noop", desc = "Auto-transit (wait for GMCP, no command)"},
        {cmd = "", desc = ""},
        {cmd = "Manual Method:", desc = ""},
        {cmd = "map exit special <dest> <cmd>", desc = "Create from current room to dest"},
        {cmd = "map exit special <src> <dest> <cmd>", desc = "Create from src to dest"},
        {cmd = "", desc = ""},
        {cmd = "Management:", desc = ""},
        {cmd = "map exit special list [room]", desc = "List special exits"},
        {cmd = "map exit special remove <cmd>", desc = "Remove from current room"},
        {cmd = "map exit special remove <room> <cmd>", desc = "Remove from specified room"}
    },
    examples = {
        "# Discovery workflow (at source room):",
        "map exit special press touchpad    # Test command, exit auto-created",
        "map exit special reverse           # At dest, create return exit",
        "map exit special noop              # For auto-transit rooms",
        "",
        "# Manual method:",
        "map exit special 1235 press touchpad  # Current -> room 1235",
        "map exit special 1234 1235 noop       # Room 1234 -> room 1235",
        "",
        "# Management:",
        "map exit special list              # List exits in current room",
        "map exit special remove press touchpad  # Remove exit"
    }
})

f2t_register_help("map exit stub", {
    description = "Manage stub exits (placeholders for unexplored directions)",
    usage = {
        {cmd = "map exit stub create [room] <dir>", desc = "Create stub exit"},
        {cmd = "map exit stub delete [room] <dir>", desc = "Delete stub exit"},
        {cmd = "map exit stub connect [room] <dir>", desc = "Connect stub to destination room"},
        {cmd = "map exit stub list [room]", desc = "List all stub exits"}
    },
    examples = {
        "map exit stub create north        # Create stub in current room",
        "map exit stub create 1234 north   # Create stub in room 1234",
        "map exit stub connect north       # Connect stub to matching room",
        "map exit stub list                # List stubs in current room",
        "map exit stub delete north        # Delete stub in current room"
    }
})

f2t_debug_log("[map] Registered help for navigation and manual mapping commands")
