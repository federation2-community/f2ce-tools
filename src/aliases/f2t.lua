-- Main f2t command - handles all fed2-tools system commands
local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("f2t")
    return
end

if f2t_handle_help("f2t", args) then
    return
end

local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "status" then
    local status_rest = args:match("^status%s+(.+)") or ""
    if f2t_handle_help("f2t status", status_rest) then return end
    f2t_show_status()

elseif subcommand == "debug" then
    local debug_cmd = args:match("^debug%s+(.+)") or ""
    if f2t_handle_help("f2t debug", debug_cmd) then return end

    if debug_cmd == "" then
        cecho(string.format("\n<green>[f2t]<reset> Debug mode: %s\n",
            F2T_DEBUG and "<yellow>ON<reset>" or "<yellow>OFF<reset>"))
        f2t_show_help_hint("f2t debug")
        return
    end

    if debug_cmd == "on" then
        f2t_set_debug(true)
        cecho("\n<green>[f2t]<reset> Debug mode <yellow>ON<reset>\n")
    elseif debug_cmd == "off" then
        f2t_set_debug(false)
        cecho("\n<green>[f2t]<reset> Debug mode <yellow>OFF<reset>\n")
    else
        cecho(string.format("\n<red>[f2t]<reset> Unknown debug option: %s\n", debug_cmd))
        f2t_show_help_hint("f2t debug")
    end

elseif subcommand == "settings" then
    local settings_args = args:match("^settings%s*(.*)") or ""
    if f2t_handle_help("f2t settings", settings_args) then return end
    f2t_handle_settings_command("f2t", settings_args)

elseif subcommand == "chat" then
    local chatArgs = args:match("^chat%s*(.*)") or ""
    if f2t_handle_help("f2t chat", chatArgs) then return end

    if chatArgs == "wipe" then
        f2tChatWipe()
        f2tChatComhistoryRefetch()
    else
        cecho(string.format("\n<red>[f2t]<reset> Unknown chat option: %s\n", chatArgs))
        f2t_show_help_hint("f2t chat")
    end

elseif subcommand == "on" then
    if not (Mux and Mux.fullStart) then
        cecho("\n<red>[f2t]<reset> Muxlet isn't ready yet; try again in a moment.\n")
        return
    end
    f2tSetAutostart(true)
    if not Mux._running then Mux.fullStart() end
    cecho("\n<green>[f2t]<reset> fed2-tools UI is on.\n")

elseif subcommand == "off" then
    if not (Mux and Mux.fullStop) then
        cecho("\n<red>[f2t]<reset> Muxlet isn't ready yet; try again in a moment.\n")
        return
    end
    f2tSetAutostart(false)
    if Mux._running then Mux.fullStop() end
    cecho("\n<yellow>[f2t]<reset> fed2-tools UI is off and won't auto-start next login. "
        .. "Type <green>f2t on<reset> to resume, or <green>f2t mode<reset> to re-pick a startup mode.\n")

elseif subcommand == "mode" then
    if f2tShowModeSelect then
        f2tShowModeSelect(true)
    else
        cecho("\n<red>[f2t]<reset> Mode selection isn't available right now.\n")
    end

elseif subcommand == "version" then
    local info = getPackageInfo("fed2-tools")
    cecho(string.format(
        "\n<green>[fed2-tools]<reset> Version: <white>%s<reset>\n", (info and info.version) or "unknown"))
    if Mux and Mux.checkForUpdates then Mux.checkForUpdates(false) end

elseif subcommand == "credits" then
    cecho("\n<green>[fed2-tools]<reset> Acknowledgments\n\n")
    cecho("  <cyan>Colborn (ping65510)<reset> — original creator of fed2-tools\n")
    cecho("  <cyan>Swift (Ohmi02/Fed2)<reset> — original idea for the multi-window UI layout, later merged in\n")
    cecho("  <cyan>tmtocloud (jackrungh)<reset> — took over maintenance, merged in the UI layout,\n")
    cecho("    and rewrote most of the codebase\n")

else
    cecho(string.format("\n<red>[f2t]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("f2t")
end
