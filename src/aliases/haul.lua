-- f2ce-tools — haul command
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

-- `haul mode` with no argument: what start would run and what else this rank can pick.
local function showMode()
    local setting = f2t_settings_get("hauling", "mode") or "auto"
    local strategy, note = f2t_hauling_default_strategy()
    cecho(string.format("\n<green>[hauling]<reset> Mode setting: <cyan>%s<reset>\n", setting))
    if note then cecho(string.format("  <yellow>%s<reset>\n", note)) end
    if strategy then
        cecho(string.format("  'haul start' runs: <cyan>%s<reset> <dim_grey>(%s)<reset>\n",
            f2t_hauling_strategy_label(strategy), F2T_HAUL_STRATEGIES[strategy].desc))
    end
    local available = f2t_hauling_available_strategies()
    if #available > 1 then
        cecho("  Available at your rank:\n")
        for _, id in ipairs(available) do
            cecho(string.format("    <cyan>%-9s<reset> %s\n", id, F2T_HAUL_STRATEGIES[id].desc))
        end
    end
    cecho("<dim_grey>  haul mode <name> to change, haul mode auto for your rank's default<reset>\n")
end

if subcommand == "start" then
    if f2tControlBlocks("Hauling") then return end
    local rest = args:match("^%S+%s+(%S+)")
    f2t_hauling_start(rest)

elseif subcommand == "mode" then
    local requested = args:match("^%S+%s+(%S+)")
    if not requested then
        showMode()
        return
    end
    local strategy = f2t_hauling_normalize_strategy(requested)
    if not strategy then
        cecho(string.format("\n<red>[hauling]<reset> Unknown mode '%s'. Modes: auto, %s\n",
            requested, table.concat(F2T_HAUL_STRATEGY_ORDER, ", ")))
        return
    end
    if strategy ~= "auto" and not f2t_hauling_strategy_available(strategy) then
        cecho(string.format("\n<red>[hauling]<reset> %s isn't available at %s rank\n",
            f2t_hauling_strategy_label(strategy), f2t_get_rank() or "your"))
        return
    end
    f2t_settings_set("hauling", "mode", strategy)
    cecho(string.format("\n<green>[hauling]<reset> Mode set to <cyan>%s<reset>%s\n", strategy,
        F2T_HAULING_STATE.active and " <dim_grey>(applies from the next 'haul start')<reset>" or ""))

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
