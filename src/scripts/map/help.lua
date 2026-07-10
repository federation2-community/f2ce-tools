-- fed2-tools map — help registration (ported from map_help_init.lua)

f2t_register_help("map", {
    description = "Federation 2 Mapper - Auto-mapping, navigation, and destinations",
    usage = {
        {cmd="Map Control:", desc=""},
        {cmd="map on", desc="Enable auto-mapping"},
        {cmd="map off", desc="Disable auto-mapping"},
        {cmd="map sync", desc="Force sync current location with GMCP"},
        {cmd="map resync jumps", desc="Force re-probe of every mapped link room's jump exits"},
        {cmd="map resync here", desc="Force re-probe of the current link room's jump exits"},
        {cmd="map clear", desc="Clear entire map (requires confirmation)"},
        {cmd="map confirm", desc="Confirm pending destructive operation"},
        {cmd="map cancel", desc="Cancel pending confirmation"},
        {cmd="", desc=""},
        {cmd="Diagnostics:", desc=""},
        {cmd="map raw", desc="Show raw mapper + GMCP data (current room)"},
        {cmd="map raw <room_id>", desc="Show raw mapper data for specified room"},
        {cmd="map restyle", desc="Re-apply correct styling to every room in the database"},
        {cmd="", desc=""},
        {cmd="Settings:", desc=""},
        {cmd="map settings", desc="List all mapper settings"},
        {cmd="map settings get <name>", desc="Get a specific setting"},
        {cmd="map settings set <name> <value>", desc="Set a setting"},
        {cmd="map settings clear <name>", desc="Reset to default"},
        {cmd="", desc=""},
        {cmd="Saved Destinations:", desc=""},
        {cmd="map dest", desc="List all saved destinations"},
        {cmd="map dest add <name>", desc="Save current location"},
        {cmd="map dest remove <name>", desc="Remove destination"},
        {cmd="", desc=""},
        {cmd="Search Rooms:", desc=""},
        {cmd="map search <text>", desc="Search current area for room name"},
        {cmd="map search <planet|system> <text>", desc="Search planet or system"},
        {cmd="map search all <text>", desc="Search all areas"},
        {cmd="", desc=""},
        {cmd="Exploration:", desc=""},
        {cmd="map explore", desc="Context-aware exploration (brief mode)"},
        {cmd="map explore [target]", desc="Explore planet or system (auto-detect, brief)"},
        {cmd="map explore full [target]", desc="Full exploration (all rooms)"},
        {cmd="map explore brief [target]", desc="Brief exploration (flag discovery)"},
        {cmd="map explore cartel [name]", desc="Explore all systems in cartel"},
        {cmd="map explore galaxy", desc="Explore all cartels in galaxy"},
        {cmd="", desc=""},
        {cmd="Import/Export:", desc=""},
        {cmd="map export", desc="Export map to JSON file (file dialog)"},
        {cmd="map import", desc="Import map (shows summary, use 'map confirm')"},
        {cmd="", desc=""},
        {cmd="Manual Mapping:", desc=""},
        {cmd="map room", desc="Create/delete/edit/lock rooms"},
        {cmd="map exit", desc="Add/remove/lock exits (standard + special)"},
        {cmd="", desc=""},
        {cmd="Special Navigation:", desc=""},
        {cmd="map special arrival", desc="Configure on-arrival commands"},
        {cmd="map special circuit", desc="Configure circuit travel"},
    },
    examples = {
        "map dest add home                   # Save current room as 'home' destination",
        "nav home                            # Navigate to saved destination",
        "nav Earth                           # Navigate to Earth",
        "map explore                         # Context-aware brief exploration",
        "map settings set planet_nav_default orbit     # Default to orbit",
        "map search exchange                 # Search for exchange in current area",
    },
})

f2t_register_help("map resync", {
    description = "Force a re-probe of mapped jump exits (link rooms only re-probe once by default)",
    usage = {
        {cmd="map resync jumps", desc="Re-probe every mapped link room's jump destinations"},
        {cmd="map resync here", desc="Re-probe just the current room's jump destinations"},
    },
    examples = {
        "map resync jumps   # After a syndicate beacon build changes routing",
        "map resync here    # Force-refresh just this link room",
    },
})

f2t_register_help("map dest", {
    description = "Manage saved destinations for quick navigation",
    usage = {
        {cmd="map dest", desc="List all saved destinations"},
        {cmd="map dest add <name>", desc="Save current location as destination"},
        {cmd="map dest remove <name>", desc="Remove a saved destination"},
    },
    examples = {"map dest add home", "map dest remove home", "map dest"},
})

f2t_register_help("map settings", {
    description = "Manage mapper settings",
    usage = {
        {cmd="map settings", desc="List all mapper settings"},
        {cmd="map settings get <name>", desc="Get a specific setting"},
        {cmd="map settings set <name> <value>", desc="Set a setting"},
        {cmd="map settings clear <name>", desc="Reset setting to default"},
    },
    examples = {
        "map settings",
        "map settings set planet_nav_default orbit",
        "map settings set enabled false",
    },
})

f2t_register_help("map raw", {
    description = "Display raw mapper and GMCP data for diagnostics",
    usage = {
        {cmd="map raw", desc="Show mapper + GMCP data for current room"},
        {cmd="map raw <room_id>", desc="Show mapper data for specified room"},
    },
    examples = {"map raw", "map raw 1234"},
})

f2t_register_help("map restyle", {
    description = "Re-apply correct visual styling to every room in the map database",
    usage = {{cmd="map restyle", desc="Scan all rooms and update icons/colors based on metadata"}},
    examples = {"map restyle"},
})

f2t_register_help("nav", {
    description = "Navigate to a destination using speedwalk",
    usage = {
        {cmd="nav <destination>",         desc="Navigate to saved destination"},
        {cmd="nav <room_id>",             desc="Navigate to Mudlet room ID"},
        {cmd="nav <system>.<area>.<num>", desc="Navigate to Fed2 hash"},
        {cmd="nav <planet>",              desc="Navigate to planet's shuttlepad"},
        {cmd="nav <system>",              desc="Navigate to system's link"},
        {cmd="nav <flag>",                desc="Navigate to flag in current area"},
        {cmd="nav <area> <flag>",         desc="Navigate to flag in specified area"},
        {cmd="", desc=""},
        {cmd="nav info <location>",                       desc="Get navigation info from current room"},
        {cmd="nav info <locationA> to <locationB>",       desc="Get navigation info between two points"},
        {cmd="", desc=""},
        {cmd="nav stop",   desc="Stop active speedwalk"},
        {cmd="nav pause",  desc="Pause active speedwalk"},
        {cmd="nav resume", desc="Resume paused speedwalk"},
    },
    examples = {
        "nav earth_ex         # Navigate to saved 'earth_ex' destination",
        "nav Earth            # Navigate to Earth's shuttlepad",
        "nav Sol              # Navigate to Sol system link",
        "nav exchange         # Navigate to exchange in current area",
        "nav Earth exchange   # Navigate to Earth's exchange",
        "nav Coffee.Latte.459 # Navigate to specific Fed2 hash",
        "",
        "nav stop   # Cancel speedwalk completely",
    },
})

f2t_register_help("nav stop",   {description="Stop active speedwalk navigation",   usage={{cmd="nav stop",   desc="Stop speedwalk completely"}}, examples={"nav stop"}})
f2t_register_help("nav pause",  {description="Pause active speedwalk navigation",   usage={{cmd="nav pause",  desc="Pause speedwalk (keeps path for resume)"}}, examples={"nav pause"}})
f2t_register_help("nav resume", {description="Resume paused speedwalk navigation",  usage={{cmd="nav resume", desc="Resume paused speedwalk from current position"}}, examples={"nav resume"}})

f2t_register_help("map search", {
    description = "Search for rooms by name in the map database",
    usage = {
        {cmd="map search <text>", desc="Search current area for matching rooms"},
        {cmd="map search <planet|system> <text>", desc="Search planet or system for rooms"},
        {cmd="map search all <text>", desc="Search all areas for matching rooms"},
    },
    examples = {"map search exchange", "map search Earth park", "map search all depot"},
})

f2t_register_help("map explore", {
    description = "Automatically discover unmapped rooms (planet/system/cartel/galaxy)",
    usage = {
        {cmd="map explore", desc="Context-aware exploration (brief mode)"},
        {cmd="map explore [target]", desc="Explore target (auto-detect planet/system)"},
        {cmd="map explore full [target]", desc="Full exploration (all rooms)"},
        {cmd="map explore brief [target]", desc="Brief exploration (flag discovery)"},
        {cmd="map explore cartel [name]", desc="Explore all systems in cartel"},
        {cmd="map explore galaxy", desc="Explore all cartels in galaxy"},
        {cmd="", desc=""},
        {cmd="map explore stop", desc="Stop exploration"},
        {cmd="map explore pause", desc="Pause exploration"},
        {cmd="map explore resume", desc="Resume paused exploration"},
        {cmd="map explore status", desc="Show current progress"},
    },
    examples = {
        "map explore                      # Context-aware brief exploration",
        "map explore Earth                # Explore Earth (auto-detect planet)",
        "map explore Coffee               # Explore Coffee (auto-detect system)",
        "map explore full                 # Full exploration of current area",
        "map explore stop                 # Stop and show statistics",
    },
})

f2t_register_help("map export", {
    description = "Export the map to a JSON file for backup or sharing",
    usage = {{cmd="map export", desc="Opens file dialog to select save location"}},
    examples = {"map export"},
})

f2t_register_help("map import", {
    description = "Import a map from a JSON file or a bundled map database",
    usage = {
        {cmd="map import", desc="Select file and show summary"},
        {cmd="map import db", desc="Open the bundled map database picker"},
        {cmd="map confirm", desc="Confirm and execute the import"},
        {cmd="map cancel", desc="Cancel the import"},
    },
    examples = {"map import", "map import db", "map confirm", "map cancel"},
})

f2t_register_help("map special", {
    description = "Configure special navigation behaviors (on-arrival commands, circuit travel)",
    usage = {
        {cmd="map special arrival", desc="Configure on-arrival commands"},
        {cmd="map special circuit", desc="Configure circuit travel"},
    },
    examples = {"map special arrival wear tabi"},
})

f2t_register_help("map special arrival", {
    description = "Configure commands that execute when entering a room",
    usage = {
        {cmd="map special arrival <command>", desc="Set command (always run)"},
        {cmd="map special arrival <type> <command>", desc="Set command with exec type"},
        {cmd="map special arrival remove", desc="Remove on-arrival command"},
        {cmd="map special arrival list", desc="List all rooms with on-arrival commands"},
        {cmd="", desc=""},
        {cmd="Execution Types:", desc=""},
        {cmd="  always", desc="Run every time (default)"},
        {cmd="  once-room", desc="Run once, then disable"},
        {cmd="  once-area", desc="Run once per area visit"},
        {cmd="  once-ever", desc="Run once ever, then disable"},
    },
    examples = {
        "map special arrival wear tabi",
        "map special arrival once-area buy permit",
        "map special arrival once-ever register",
        "map special arrival remove",
        "map special arrival list",
    },
})

f2t_register_help("map special circuit", {
    description = "Configure circuit travel systems (trains, tubes, shuttles)",
    usage = {
        {cmd="map special circuit create <id>", desc="Create new circuit"},
        {cmd="map special circuit delete <id>", desc="Delete circuit"},
        {cmd="map special circuit list", desc="List all circuits"},
        {cmd="map special circuit show <id>", desc="Show circuit details"},
        {cmd="map special circuit set <id> board <cmd>", desc="Set boarding command"},
        {cmd="map special circuit set <id> exit <cmd>", desc="Set exit command"},
        {cmd="map special circuit stop add <id> <name>", desc="Add stop to circuit"},
        {cmd="map special circuit connect <id>", desc="Connect circuit stops"},
    },
    examples = {
        "map special circuit create metro",
        "map special circuit set metro board 'board train'",
        "map special circuit stop add metro exchange",
        "map special circuit connect metro",
    },
})

f2t_register_help("map room", {
    description = "Create, delete, and edit rooms (supplement auto-mapping)",
    usage = {
        {cmd="map room add <system> <area> <num> [name]", desc="Create new room"},
        {cmd="map room delete [room_id]", desc="Delete room (requires confirmation)"},
        {cmd="map room info [room_id]", desc="Display room properties"},
        {cmd="", desc=""},
        {cmd="map room set name [room_id] <name>", desc="Set room name"},
        {cmd="map room set area [room_id] <area>", desc="Move to different area"},
        {cmd="map room set coords [room_id] <x> <y> <z>", desc="Set coordinates"},
        {cmd="map room set symbol [room_id] <char>", desc="Set symbol (1 char)"},
        {cmd="map room set color [room_id] <r> <g> <b>", desc="Set color (RGB 0-255)"},
        {cmd="map room set env [room_id] <env_id>", desc="Set environment ID"},
        {cmd="map room set weight [room_id] <weight>", desc="Set pathfinding weight"},
        {cmd="", desc=""},
        {cmd="map room lock [room_id]", desc="Lock room — navigation avoids"},
        {cmd="map room unlock [room_id]", desc="Unlock room and clear death/danger metadata"},
        {cmd="map room death <room_id>", desc="Mark room as death/danger — locked with skull icon"},
        {cmd="map room safe [room_id]", desc="Mark room safe — death monitor never auto-locks"},
        {cmd="map room unsafe [room_id]", desc="Remove safe mark and mark as death/danger"},
    },
    examples = {
        "map room add Coffee Latte 459 'Exchange Room'",
        "map room info",
        "map room lock",
        "map room death 1234",
    },
})

f2t_register_help("map exit", {
    description = "Manage exits (standard and special)",
    usage = {
        {cmd="map exit add <from> <to> <dir>", desc="Create one-way exit"},
        {cmd="map exit remove <room> <dir>", desc="Remove exit (requires confirmation)"},
        {cmd="map exit list <room>", desc="List all exits (standard + special)"},
        {cmd="", desc=""},
        {cmd="map exit lock [room] <dir>", desc="Lock exit — navigation avoids"},
        {cmd="map exit unlock [room] <dir>", desc="Unlock exit"},
        {cmd="map exit death [room] <dir>", desc="Mark exit as danger"},
        {cmd="", desc=""},
        {cmd="map exit stub create [room] <dir>", desc="Create stub exit"},
        {cmd="map exit stub delete [room] <dir>", desc="Delete stub exit"},
        {cmd="map exit stub connect [room] <dir>", desc="Connect stub to destination"},
        {cmd="map exit stub list [room]", desc="List all stub exits"},
        {cmd="", desc=""},
        {cmd="map exit special <command>", desc="Test command, auto-create exit"},
        {cmd="map exit special reverse [cmd]", desc="Create return exit"},
        {cmd="map exit special list [room]", desc="List special exits"},
        {cmd="map exit special remove <cmd>", desc="Remove from current"},
    },
    examples = {
        "map exit add 123 456 north",
        "map exit lock north",
        "map exit special press touchpad",
        "map exit special reverse",
        "map exit stub create north",
    },
})

f2t_register_help("map exit special", {
    description = "Manage special exits (custom commands, auto-transit)",
    usage = {
        {cmd="map exit special <command>", desc="Test command, auto-create exit on room change"},
        {cmd="map exit special reverse [cmd]", desc="Create return exit (uses last discovery)"},
        {cmd="map exit special noop", desc="Auto-transit (wait for GMCP, no command)"},
        {cmd="map exit special <dest> <cmd>", desc="Create from current room to dest"},
        {cmd="map exit special <src> <dest> <cmd>", desc="Create from src to dest"},
        {cmd="map exit special list [room]", desc="List special exits"},
        {cmd="map exit special remove <cmd>", desc="Remove from current room"},
    },
    examples = {
        "map exit special press touchpad",
        "map exit special reverse",
        "map exit special 1235 press touchpad",
    },
})

f2t_register_help("map exit stub", {
    description = "Manage stub exits (placeholders for unexplored directions)",
    usage = {
        {cmd="map exit stub create [room] <dir>", desc="Create stub exit"},
        {cmd="map exit stub delete [room] <dir>", desc="Delete stub exit"},
        {cmd="map exit stub connect [room] <dir>", desc="Connect stub to destination room"},
        {cmd="map exit stub list [room]", desc="List all stub exits"},
    },
    examples = {
        "map exit stub create north",
        "map exit stub connect north",
        "map exit stub list",
    },
})

f2t_debug_log("[map] Registered help for all map commands")
