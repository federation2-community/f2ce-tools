-- The `map` command. Each subcommand is an entry in the dispatch table
-- below rather than a rung in a 900-line if/elseif ladder; the three
-- largest (room, exit, special) live in the map modules they drive.
local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("map")
    return
end

if f2t_handle_help("map", args) then
    return
end

local handlers = {}

handlers["on"] = function()
    F2T_MAP_ENABLED = true
    f2t_settings_set("map", "enabled", true)
    cecho("\n<green>[map]<reset> Auto-mapping <yellow>ENABLED<reset>\n")
    f2t_debug_log("[map] Mapper enabled by user")
end

handlers["off"] = function()
    F2T_MAP_ENABLED = false
    f2t_settings_set("map", "enabled", false)
    cecho("\n<green>[map]<reset> Auto-mapping <red>DISABLED<reset>\n")
    f2t_debug_log("[map] Mapper disabled by user")
end

handlers["sync"] = function()
    f2t_map_sync()
end

handlers["status"] = function()
    f2t_map_status()
end

handlers["clear"] = function()
    local confirm = args:match("^clear%s+(.+)")

    if not confirm or confirm ~= "confirm" then
        cecho("\n<yellow>[map]<reset> This will delete the ENTIRE map!\n")
        cecho("\n<yellow>[map]<reset> Type <white>map clear confirm<reset> to proceed.\n")
        return
    end

    local rooms = getRooms()
    local room_count = 0
    for room_id, _ in pairs(rooms) do
        deleteRoom(room_id)
        room_count = room_count + 1
    end

    F2T_MAP_CURRENT_ROOM_ID = nil
    updateMap()
    raiseEvent("f2tMapDataChanged")

    cecho(string.format("\n<green>[map]<reset> Map cleared. %d rooms deleted.\n", room_count))

    if F2T_MAP_ENABLED then
        cecho("\n<green>[map]<reset> Synchronizing with current location...\n")
        f2t_map_sync()
    end
end

handlers["dest"] = function()
    local rest = args:match("^dest%s*(.*)") or args:match("^destination%s*(.*)") or ""

    if f2t_handle_help("map dest", rest) then return end

    if rest == "" or rest == "list" then
        f2t_map_destination_list()
        return
    end

    local dest_subcommand, dest_rest = string.match(rest, "^(%S+)%s*(.*)$")
    if not dest_subcommand then
        dest_subcommand = rest
        dest_rest = ""
    end
    dest_subcommand = string.lower(dest_subcommand)

    if dest_subcommand == "add" then
        if dest_rest == "" then
            cecho("\n<red>[map]<reset> Usage: map dest add <name>\n")
            return
        end
        f2t_map_destination_add(dest_rest)

    elseif dest_subcommand == "remove" or dest_subcommand == "rm" then
        if dest_rest == "" then
            cecho("\n<red>[map]<reset> Usage: map dest remove <name>\n")
            return
        end
        f2t_map_destination_remove(dest_rest)

    elseif dest_subcommand == "list" then
        f2t_map_destination_list()

    else
        cecho(string.format("\n<red>[map]<reset> Unknown dest command: %s\n", dest_subcommand))
        f2t_show_help_hint("map dest")
    end
end
handlers["destination"] = handlers["dest"]

handlers["settings"] = function()
    local settings_args = args:match("^settings%s*(.*)") or ""
    if f2t_handle_help("map settings", settings_args) then return end
    f2t_handle_settings_command("map", settings_args)
end

handlers["search"] = function()
    local rest = args:match("^search%s+(.+)") or ""

    if f2t_handle_help("map search", rest) then return end

    if rest == "" then
        f2t_show_registered_help("map search")
        return
    end

    local words = f2t_parse_words(rest)

    if string.lower(words[1]) == "all" then
        if #words < 2 then
            cecho("\n<red>[map]<reset> Missing search text after 'all'\n")
            return
        end
        local search_text = table.concat(words, " ", 2)
        local results = f2t_map_search_all(search_text)
        f2t_map_search_display(results, search_text, "all areas")
    else
        local location, search_text = f2t_map_parse_location_prefix(rest)

        if location then
            local results = f2t_map_search_planet_or_system(location, search_text)
            f2t_map_search_display(results, search_text, location)
        else
            search_text = rest

            if not f2t_map_ensure_current_location() then
                cecho("\n<yellow>[map]<reset> Current location unknown. Refreshing...\n")
                send("look")
                tempTimer(0.5, function()
                    expandAlias(string.format("map search %s", search_text))
                end)
                return
            end

            local results = f2t_map_search_current_area(search_text)
            if results == nil then
                cecho("\n<red>[map]<reset> Cannot determine current area\n")
                return
            end

            local current_area_id = getRoomArea(F2T_MAP_CURRENT_ROOM_ID)
            local area_name = f2t_map_get_area_name(current_area_id) or "current area"
            f2t_map_search_display(results, search_text, area_name)
        end
    end
end

handlers["explore"] = function()
    local rest = args:match("^explore%s*(.*)") or ""

    if f2t_handle_help("map explore", rest) then return end

    if rest == "" then
        f2t_map_explore_start("brief")
        return
    end

    local words = f2t_parse_words(rest)
    local first = string.lower(words[1])

    if first == "full" or first == "brief" then
        local mode = first
        local target = words[2] and f2t_parse_rest(words, 2) or nil
        f2t_map_explore_start(mode, target)

    elseif first == "system" then
        -- f2t_map_explore_system_start defaults to the current system itself
        -- when no name is given, same as the cartel/planet/syndicate forms.
        f2t_map_explore_system_start("brief", f2t_parse_rest(words, 2))

    elseif first == "planet" then
        -- f2t_map_explore_planet_start defaults to the current planet itself
        -- when no name is given, same as the system/cartel/syndicate forms.
        f2t_map_explore_planet_start("brief", f2t_parse_rest(words, 2))

    elseif first == "cartel" then
        -- f2t_map_explore_cartel_start defaults to the current cartel itself
        -- when no name is given, same as the system/planet/syndicate forms.
        f2t_map_explore_cartel_start(f2t_parse_rest(words, 2))

    elseif first == "room" then
        -- Walks the current planet room-by-room until a room whose name
        -- contains this text is found (same case-insensitive substring match
        -- as `map search`), instead of the flag-based (shuttlepad/exchange/etc)
        -- search every other form here does.
        local room_name = f2t_parse_rest(words, 2)
        if room_name == "" then
            cecho("\n<red>[map]<reset> Usage: map explore room <text>\n")
        else
            f2t_map_explore_planet_start("brief", nil, nil, nil, room_name)
        end

    elseif first == "galaxy" then
        f2t_map_explore_galaxy_start()

    elseif first == "syndicate" then
        local syndicate_name = f2t_parse_rest(words, 2)
        f2t_map_explore_syndicate_start(syndicate_name)

    elseif first == "stop" then
        f2t_map_explore_stop()

    elseif first == "pause" then
        f2t_map_explore_pause()

    elseif first == "resume" then
        f2t_map_explore_resume()

    elseif first == "status" then
        f2t_map_explore_status()

    elseif first == "suspected" then
        f2t_map_explore_list_suspected()

    else
        local target = f2t_parse_rest(words, 1)
        f2t_map_explore_start("brief", target)
    end
end

handlers["room"] = function()
    return f2t_map_room_command(args)
end

handlers["confirm"] = function()
    f2t_map_manual_confirm()
end

handlers["cancel"] = function()
    f2t_map_manual_cancel_confirmation()
end

handlers["restyle"] = function()
    f2t_map_restyle_all()
end

handlers["raw"] = function()
    local rest = args:match("^raw%s*(.*)") or ""
    if f2t_handle_help("map raw", rest) then return end

    if rest == "" then
        f2t_map_raw_display_room(nil, true)
    else
        local room_id = tonumber(rest)
        if room_id then
            f2t_map_raw_display_room(room_id, false)
        else
            cecho("\n<red>[map]<reset> Usage: map raw [room_id]\n")
        end
    end
end

handlers["exit"] = function()
    return f2t_map_exit_command(args)
end

handlers["special"] = function()
    return f2t_map_special_command(args)
end

handlers["topology"] = function()
    local rest = args:match("^topology%s*(.*)") or ""
    if f2t_handle_help("map topology", rest) then return end

    if rest == "" or rest == "show" then
        f2t_map_topology_show()
    elseif rest == "links" then
        f2t_map_topology_show_links()
    elseif rest == "sync" then
        cecho("\n<green>[map]<reset> Syncing galaxy topology...\n")
        f2t_map_topology_sync()
    elseif rest == "rebuild" then
        local rebuilt, skipped, changed = f2t_map_topology_rebuild_exits()
        cecho(string.format(
            "\n<green>[map]<reset> Jump exits rebuilt: <white>%d<reset> system(s), %d exit change(s)%s\n",
            rebuilt, changed,
            skipped > 0 and string.format(", <yellow>%d skipped<reset> (syndicate unknown)", skipped) or ""))
    else
        cecho(string.format("\n<red>[map]<reset> Unknown topology command: %s\n", rest))
        f2t_show_help_hint("map topology")
    end
end

handlers["export"] = function()
    local rest = args:match("^export%s*(.*)") or ""
    if f2t_handle_help("map export", rest) then return end
    f2t_map_export()
end

handlers["import"] = function()
    local rest = args:match("^import%s*(.*)") or ""
    if f2t_handle_help("map import", rest) then return end
    if rest == "" then
        f2t_map_import()
    elseif rest:lower() == "db" then
        -- Open the bundled-resource picker directly, regardless of the
        -- first-run gate (useful for re-importing or testing). The picker
        -- renders inside the live F2CE Map pane's own slot (not a standalone
        -- dialog), so it needs that pane to be open somewhere first.
        local slotContent, gid
        if f2tGetMapSlotInfo then
            slotContent, gid = f2tGetMapSlotInfo()
        end
        if f2tShowMapImportOverlay and slotContent then
            f2tShowMapImportOverlay(slotContent, gid, "manual")
        else
            cecho("\n<yellow>[map]<reset> Map database picker unavailable — open the F2CE Map pane first.\n")
        end
    else
        cecho(string.format("\n<red>[map]<reset> Unknown import option: %s\n", rest))
        f2t_show_help_hint("map import")
        return
    end
end

local subcommand = string.lower(args):match("^(%S+)")
local handler = subcommand and handlers[subcommand]
if handler then
    return handler()
end

cecho(string.format("\n<red>[map]<reset> Unknown command: %s\n", subcommand))
f2t_show_help_hint("map")
