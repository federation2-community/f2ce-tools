-- f2ce-tools — factory command
--
-- Usage: factory|fac <status|flush|settings>
-- Rank-gated to Industrialist / Manufacturer (the only ranks that own factories)
-- and feature-gated by the factory/enabled setting.

local args = matches[2]

if not f2t_settings_get("factory", "enabled") then
    cecho("\n<yellow>[factory]<reset> Factory tools are disabled. Enable them in settings (F2CE-Tools/Factory).\n")
    return
end

-- Rank requirement: only Industrialist or Manufacturer own factories.
if not (f2t_is_rank_exactly("Industrialist") or f2t_is_rank_exactly("Manufacturer")) then
    cecho("\n<red>[factory]<reset> Factory commands require <cyan>Industrialist<reset> or <cyan>Manufacturer<reset> rank\n")
    local rank = f2t_get_rank()
    if rank then
        cecho(string.format("<dim_grey>Your current rank: <white>%s<reset>\n", rank))
    end
    return
end

-- No args → help (no default action).
if not args or args == "" then
    f2t_show_registered_help("factory")
    return
end

if f2t_handle_help("factory", args) then return end

local subcommand = f2t_parse_words(args)[1]

if subcommand == "status" then
    cecho("\n<green>[factory]<reset> Gathering factory data...\n")
    f2t_debug_log("[factory] status command")
    f2t_factory_start_capture()

elseif subcommand == "flush" then
    cecho("\n<green>[factory]<reset> Flushing all factories...\n")
    f2t_debug_log("[factory] flush command")
    f2t_factory_start_flush()

elseif subcommand == "settings" then
    local settings_args = f2t_parse_subcommand(args, "settings") or ""
    f2t_handle_settings_command("factory", settings_args)

else
    cecho(string.format("\n<red>[factory]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("factory")
end