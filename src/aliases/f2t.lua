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

elseif subcommand == "version" then
    f2t_check_latest_version()

elseif subcommand == "reload" then
    local reload_args = args:match("^reload%s*(.*)") or ""
    local is_fresh = reload_args:match("^fresh") ~= nil
    f2t_devmode_reload(is_fresh)

else
    cecho(string.format("\n<red>[f2t]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("f2t")
end
