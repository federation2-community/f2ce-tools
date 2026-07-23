-- Help system: display + registry.

-- Display

function f2t_show_help(command, description, usage, examples)
    cecho(string.format("\n<green>[%s]<reset> %s\n\n", command, description))

    if usage and #usage > 0 then
        cecho("<yellow>Usage:<reset>\n")
        for _, u in ipairs(usage) do
            if u.cmd == "" and (not u.desc or u.desc == "") then
                cecho("\n")
            else
                cecho(string.format("  <cyan>%s<reset>\n", u.cmd))
                if u.desc and u.desc ~= "" then
                    cecho(string.format("    <dim_grey>%s<reset>\n", u.desc))
                end
            end
        end
        cecho("\n")
    end

    if examples and #examples > 0 then
        cecho("<yellow>Examples:<reset>\n")
        for _, example in ipairs(examples) do
            if example == "" then
                cecho("\n")
            else
                cecho(string.format("  <cyan>%s<reset>\n", example))
            end
        end
        cecho("\n")
    end
end

function f2t_is_help_request(args)
    if not args or args == "" then return false end
    return string.lower(args) == "help"
end

function f2t_show_help_hint(command)
    cecho(string.format("\n<dim_grey>Use '%s help' for more information<reset>\n", command))
end

-- Registry

F2T_HELP_REGISTRY = F2T_HELP_REGISTRY or {}

function f2t_register_help(command, config)
    if not command or command == "" then return false end
    if not config or not config.description then return false end
    F2T_HELP_REGISTRY[command] = {
        description = config.description,
        usage       = config.usage   or {},
        examples    = config.examples or {},
    }
    return true
end

function f2t_show_registered_help(command)
    local help_config = F2T_HELP_REGISTRY[command]
    if not help_config then return false end
    f2t_show_help(command, help_config.description, help_config.usage, help_config.examples)
    return true
end

function f2t_handle_help(command, arg)
    if not f2t_is_help_request(arg) then return false end
    return f2t_show_registered_help(command)
end

-- System (f2t) help registration: registers help for the top-level
-- dispatcher and its subcommands. Component settings live under
-- `<component> settings` or the Muxlet settings UI.

f2t_register_help("f2t", {
    description = "Federation 2 Tools Package - System commands and component overview",
    usage = {
        {cmd = "System Commands:", desc = ""},
        {cmd = "f2t", desc = "Show this help"},
        {cmd = "f2t status", desc = "Show component states"},
        {cmd = "f2t version", desc = "Show package version and check for updates"},
        {cmd = "f2t credits", desc = "Show acknowledgments"},
        {cmd = "f2t debug on/off", desc = "Toggle debug logging"},
        {cmd = "f2t on/off", desc = "Start/stop the Muxlet UI (won't auto-start next login if off)"},
        {cmd = "f2t mode", desc = "Re-pick a startup mode (Full/BYOW/Minimal)"},
        {cmd = "f2t settings", desc = "Manage system settings"},
        {cmd = "f2t chat wipe", desc = "Wipe chat history and re-fetch comhistory"},
        {cmd = "", desc = ""},
        {cmd = "Components:", desc = ""},
        {cmd = "map help", desc = "Auto-mapping, navigation, destinations"},
        {cmd = "nav help", desc = "Navigation command formats"},
        {cmd = "factory help", desc = "Factory status display"},
        {cmd = "refuel help", desc = "Automatic ship refueling"},
        {cmd = "bb help", desc = "Bulk buy commodities"},
        {cmd = "bs help", desc = "Bulk sell commodities"},
        {cmd = "price help", desc = "Commodity price analysis"},
        {cmd = "po help", desc = "Planet owner economy tools"},
        {cmd = "haul help", desc = "Automated commodity trading"}
    },
    examples = {
        "f2t status              # Check which components are enabled",
        "f2t version             # Show current package version and check for updates",
        "f2t debug on            # Enable debug logging",
        "f2t settings            # View system settings",
        "map help                # Get help for map component"
    }
})

f2t_register_help("f2t settings", {
    description = "Manage fed2-tools system (f2t) settings",
    usage = {
        {cmd = "f2t settings", desc = "List all system settings"},
        {cmd = "f2t settings get <name>", desc = "Get a specific setting"},
        {cmd = "f2t settings set <name> <value>", desc = "Set a setting"},
        {cmd = "f2t settings clear <name>", desc = "Reset setting to default"},
        {cmd = "", desc = ""},
        {cmd = "Component settings:", desc = "use <component> settings, e.g. 'factory settings'"},
        {cmd = "", desc = "or open the Muxlet settings UI (grouped under Fed2-Tools)"}
    },
    examples = {
        "f2t settings                            # List system settings",
        "f2t settings set update_check_enabled false  # Stop checking for updates",
        "f2t settings clear update_check_enabled # Reset to default",
        "",
        "factory settings                        # Factory component settings",
        "price settings set results_count 10     # Commodities component settings"
    }
})

f2t_register_help("f2t chat", {
    description = "Manage the persistent chat history",
    usage = {
        {cmd = "f2t chat wipe", desc = "Wipe the current character's saved chat history and re-fetch comhistory"}
    },
    examples = {
        "f2t chat wipe    # Start the chat log over from the game's com history"
    }
})

f2t_register_help("f2t debug", {
    description = "Control debug logging for fed2-tools components",
    usage = {
        {cmd = "f2t debug", desc = "Show current debug state"},
        {cmd = "f2t debug on", desc = "Enable debug logging (persists)"},
        {cmd = "f2t debug off", desc = "Disable debug logging (persists)"}
    },
    examples = {
        "f2t debug on     # Enable debug messages",
        "f2t debug off    # Disable debug messages",
        "f2t debug        # Show current state"
    }
})

f2t_register_help("f2t status", {
    description = "Show fed2-tools component status",
    usage = {
        {cmd = "f2t status", desc = "Display all component states"}
    },
    examples = {
        "f2t status       # Show which components are enabled/disabled"
    }
})

f2t_debug_log("[f2t] Registered help for system commands")