-- Navigation command
-- Usage: nav <destination>
-- Usage: nav info <destination>
-- Usage: nav info <origin> to <destination>
-- Usage: nav stop/pause/resume

local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("nav")
    return
end

if f2t_handle_help("nav", args) then
    return
end

local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "stop" then
    local stop_rest = args:match("^stop%s+(.+)") or ""
    if f2t_handle_help("nav stop", stop_rest) then return end
    if not F2T_SPEEDWALK_ACTIVE then
        cecho("\n<yellow>[map]<reset> No active speedwalk to stop\n")
        return
    end
    f2t_map_speedwalk_stop()

elseif subcommand == "pause" then
    local pause_rest = args:match("^pause%s+(.+)") or ""
    if f2t_handle_help("nav pause", pause_rest) then return end
    if not F2T_SPEEDWALK_ACTIVE then
        cecho("\n<yellow>[map]<reset> No active speedwalk to pause\n")
        return
    end
    f2t_map_speedwalk_pause()

elseif subcommand == "resume" then
    local resume_rest = args:match("^resume%s+(.+)") or ""
    if f2t_handle_help("nav resume", resume_rest) then return end
    if not F2T_SPEEDWALK_ACTIVE then
        cecho("\n<yellow>[map]<reset> No speedwalk to resume\n")
        return
    end
    f2t_map_speedwalk_resume()

elseif subcommand == "info" then
    local info_rest = args:match("^info%s+(.+)$")

    if f2t_handle_help("nav info", info_rest or "") then return end

    if not info_rest or info_rest == "" then
        cecho("\n<red>[map]<reset> Usage: nav info <destination>\n")
        cecho("<red>[map]<reset>        nav info <origin> to <destination>\n")
        return
    end

    local origin, destination
    local before_to, after_to = info_rest:match("^(.-)%s+[Tt][Oo]%s+(.+)$")

    if before_to and after_to then
        origin = before_to
        destination = after_to
    else
        origin = nil
        destination = info_rest
    end

    f2t_map_show_route_info(origin, destination)

else
    f2t_map_navigate(args, {interactive = true})
end
