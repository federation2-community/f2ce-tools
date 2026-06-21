-- fed2-tools — haul command
--
-- Automated, rank-adaptive hauling. Inert until `haul start`; resets on
-- `haul stop` / `haul terminate`.

local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("haul")
    return
end

if f2t_handle_help("haul", args) then return end

local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "start" then
    local rest = args:match("^%S+%s+(%S+)")
    f2t_hauling_start(rest)

elseif subcommand == "stop" then
    f2t_hauling_stop()

elseif subcommand == "terminate" or subcommand == "term" then
    f2t_hauling_terminate()

elseif subcommand == "pause" then
    f2t_hauling_pause()

elseif subcommand == "resume" then
    f2t_hauling_resume()

elseif subcommand == "status" then
    f2t_hauling_show_status()

elseif subcommand == "settings" then
    f2t_handle_settings_command("hauling", f2t_parse_subcommand(args, "settings") or "")

else
    cecho(string.format("\n<red>[hauling]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("haul")
end