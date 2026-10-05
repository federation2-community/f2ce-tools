-- price — regex declared in aliases.json
-- Consolidated price command alias
local args = matches[2]

-- No arguments - show help
if not args or args == "" then
    f2t_show_registered_help("price")
    return
end

-- Check for help request
if f2t_handle_help("price", args) then
    return
end

-- Parse subcommand
local subcommand = f2t_parse_words(args)[1]

if subcommand == "all" then
    -- Check for help on "price all"
    local rest = f2t_parse_subcommand(args, "all")
    if rest and f2t_is_help_request(rest) then
        f2t_show_registered_help("price")
        return
    end

    f2t_price_show_all(rest and rest:lower():match("^%s*galaxy%s*$") and "galaxy" or nil)

elseif subcommand == "settings" then
    -- Handle settings subcommands
    local settings_args = f2t_parse_subcommand(args, "settings") or ""
    f2t_handle_settings_command("commodities", settings_args)

else
    -- Commodity name, optionally followed by the galaxy scope
    local commodity, scope = args:match("^(%S+)%s+(galaxy)%s*$")
    f2t_price_show(commodity or args, scope)
end