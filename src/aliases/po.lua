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

elseif subcommand == "stockpile" or subcommand == "stockpiles" or subcommand == "sp" then
    local rest = f2t_parse_rest(words, 2)
    if f2t_handle_help("po stockpile", rest) then return end
    local action = string.lower(words[2] or "status")
    local value = f2t_parse_rest(words, 3)

    if action == "preview" then
        f2tStockpilePreview(value ~= "" and value or nil, function(plan)
            if plan then f2tStockpileShowPlan(plan) end
        end)
    elseif action == "show" then
        f2tStockpileShowPlan()
    elseif action == "apply" then
        f2tStockpileApply()
    elseif action == "cancel" then
        if not f2tStockpileCancel() then cecho("\n<yellow>[stockpiles]<reset> No update is running\n") end
    elseif action == "status" then
        f2tStockpileShowStatus()
    elseif action == "auto" then
        local mode = string.lower(words[3] or "status")
        if mode == "on" then
            f2tStockpileAutoStart()
        elseif mode == "off" then
            if not f2tStockpileAutoStop() then cecho("\n<yellow>[stockpiles]<reset> Auto mode is already off\n") end
        elseif mode == "run" then
            if not f2tStockpileAutoRun() then cecho("\n<yellow>[stockpiles]<reset> Busy; try again shortly\n") end
        else
            f2tStockpileShowStatus()
        end
    elseif action == "target" or action == "targets" or action == "exclude" then
        local key = action == "exclude" and "stockpile_excluded" or "stockpile_targets"
        local label = action == "exclude" and "Excluded commodities" or "Target planets"
        local verb = string.lower(words[3] or "list")
        local item = f2t_parse_rest(words, 4)
        if (verb == "add" or verb == "remove") and item ~= "" then
            local changed = f2tStockpileEditList(key, item, verb == "add")
            cecho(string.format("\n<green>[stockpiles]<reset> %s %s %s\n", item,
                changed and (verb == "add" and "added to" or "removed from") or
                    (verb == "add" and "is already in" or "isn't in"), label:lower()))
        elseif verb == "clear" then
            f2t_settings_set("po", key, "")
            raiseEvent("f2tStockpileChanged")
            cecho(string.format("\n<green>[stockpiles]<reset> %s cleared\n", label))
        else
            local items = f2tStockpileGetList(key)
            cecho(string.format("\n<green>[stockpiles]<reset> %s: %s\n", label,
                #items > 0 and table.concat(items, ", ") or "none"))
        end
    else
        cecho(string.format("\n<red>[stockpiles]<reset> Unknown command: %s\n", action))
        f2t_show_help_hint("po stockpile")
    end

elseif subcommand == "settings" then
    local settings_args = f2t_parse_subcommand(args, "settings") or ""
    f2t_handle_settings_command("po", settings_args)

else
    cecho(string.format("\n<red>[po]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("po")
end