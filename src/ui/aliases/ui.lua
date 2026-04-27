-- @patterns:
--   - pattern: ^ui(?:\s+(.+))?$

local args = matches[2]

-- No args = show status
if not args or args == "" then
    f2t_ui_status()
    return
end

if f2t_handle_help("ui", args) then return end

local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "on" then
    f2t_ui_enable()
elseif subcommand == "off" then
    f2t_ui_disable()
elseif subcommand == "toggle" then
    f2t_ui_toggle()
elseif subcommand == "status" then
    f2t_ui_status()
elseif subcommand == "settings" then
    -- ui settings [list|get|set|clear] [args]
    local settings_args = args:match("^settings%s*(.*)") or ""

    -- Check for help request
    if f2t_handle_help("ui settings", settings_args) then
        return
    end

    f2t_handle_settings_command("ui", settings_args)
else
    cecho(string.format("\n<red>[ui]<reset> Unknown subcommand: %s\n", subcommand))
    f2t_show_help_hint("ui")
end