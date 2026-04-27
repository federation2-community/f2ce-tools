-- @patterns:
--   - pattern: ^(?:nav|go|goto)(?:\s+(.+))?$

-- Navigation command with subcommands
-- Usage: nav <destination>
-- Usage: nav info <destination>
-- Usage: nav info <origin> to <destination>
-- Usage: nav stop/pause/resume

local args = matches[2]

-- No arguments - show help
if not args or args == "" then
    f2t_show_registered_help("nav")
    return
end

-- Check for help request
if f2t_handle_help("nav", args) then
    return
end

-- Parse subcommand
local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "stop" then
    -- nav stop - Stop active speedwalk
    local stop_rest = args:match("^stop%s+(.+)") or ""
    if f2t_handle_help("nav stop", stop_rest) then
        return
    end
    if not F2T_SPEEDWALK_ACTIVE then
        cecho("\n<yellow>[map]<reset> No active speedwalk to stop\n")
        return
    end
    f2t_map_speedwalk_stop()

elseif subcommand == "pause" then
    -- nav pause - Pause active speedwalk
    local pause_rest = args:match("^pause%s+(.+)") or ""
    if f2t_handle_help("nav pause", pause_rest) then
        return
    end
    if not F2T_SPEEDWALK_ACTIVE then
        cecho("\n<yellow>[map]<reset> No active speedwalk to pause\n")
        return
    end
    f2t_map_speedwalk_pause()

elseif subcommand == "resume" then
    -- nav resume - Resume paused speedwalk
    local resume_rest = args:match("^resume%s+(.+)") or ""
    if f2t_handle_help("nav resume", resume_rest) then
        return
    end
    if not F2T_SPEEDWALK_ACTIVE then
        cecho("\n<yellow>[map]<reset> No speedwalk to resume\n")
        return
    end
    f2t_map_speedwalk_resume()

elseif subcommand == "info" then
    -- nav info - Show route information
    local info_rest = args:match("^info%s+(.+)$")
    
    if f2t_handle_help("nav info", info_rest or "") then
        return
    end
    
    if not info_rest or info_rest == "" then
        cecho("\n<red>[map]<reset> Usage: nav info <destination>\n")
        cecho("<red>[map]<reset>        nav info <origin> to <destination>\n")
        return
    end
    
    -- Parse origin and destination using "to" as delimiter
    local origin, destination
    
    -- Check for "to" delimiter (case insensitive, with spaces around it)
    local before_to, after_to = info_rest:match("^(.-)%s+[Tt][Oo]%s+(.+)$")
    
    if before_to and after_to then
        -- Format: origin to destination
        origin = before_to
        destination = after_to
    else
        -- No "to" delimiter - entire string is destination
        origin = nil
        destination = info_rest
    end
    
    f2t_map_show_route_info(origin, destination)

else
    -- Default: treat as destination and navigate
    f2t_map_navigate(args)
end