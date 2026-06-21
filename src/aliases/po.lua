-- po — regex declared in aliases.json
local args = matches[2]

-- Rank check: Founder+
if not f2t_check_rank_requirement("Founder", "Planet owner tools") then
    return
end

-- No arguments - show help
if not args or args == "" then
    f2t_show_registered_help("po")
    return
end

-- Check for help request
if f2t_handle_help("po", args) then return end

-- Parse subcommand
local words = f2t_parse_words(args)
local subcommand = string.lower(words[1])

if subcommand == "economy" or subcommand == "econ" then
    -- Extract remaining args after the subcommand (preserve original case for planet names)
    local economy_args = f2t_parse_rest(words, 2)

    if economy_args == "" then
        -- No planet, no group
        f2t_po_economy_start(nil, nil)
        return
    end

    local economy_words = f2t_parse_words(economy_args)

    -- Check if last word is a commodity group
    local last_word = economy_words[#economy_words]
    local group = f2t_po_resolve_group(last_word)

    if group and #economy_words == 1 then
        -- Single word that IS a group: no planet, just group filter
        f2t_debug_log("[po] Parsed args: planet=nil, group=%s", group)
        f2t_po_economy_start(nil, group)
    elseif group and #economy_words > 1 then
        -- Last word is group, everything before is planet
        local planet = table.concat(economy_words, " ", 1, #economy_words - 1)
        f2t_debug_log("[po] Parsed args: planet=%s, group=%s", planet, group)
        f2t_po_economy_start(planet, group)
    else
        -- No group match: everything is planet name
        f2t_debug_log("[po] Parsed args: planet=%s, group=nil", economy_args)
        f2t_po_economy_start(economy_args, nil)
    end

elseif subcommand == "settings" then
    local settings_args = f2t_parse_subcommand(args, "settings") or ""
    f2t_handle_settings_command("po", settings_args)

else
    cecho(string.format("\n<red>[po]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("po")
end