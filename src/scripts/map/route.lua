-- f2ce-tools map — route calculation (ported from map_route.lua)

function f2t_map_get_route_info(origin, destination)
    local origin_room_id, origin_err
    if origin and origin ~= "" then
        origin_room_id, origin_err = f2t_map_resolve_location(origin)
        if not origin_room_id then
            return nil, string.format("Cannot resolve origin: %s", origin_err or "unknown error")
        end
    else
        origin_room_id = F2T_MAP_CURRENT_ROOM_ID
        if not origin_room_id then return nil, "Current location unknown (no origin specified)" end
    end

    local dest_room_id, dest_err = f2t_map_resolve_location(destination)
    if not dest_room_id then
        return nil, string.format("Cannot resolve destination: %s", dest_err or "unknown error")
    end

    if origin_room_id == dest_room_id then
        return {origin_room_id=origin_room_id, dest_room_id=dest_room_id,
                total_moves=0, space_moves=0, success=true}
    end

    local success, cost = getPath(origin_room_id, dest_room_id)
    if not success then return nil, "No path found between origin and destination" end

    local total_moves = #speedWalkDir
    local space_moves = 0
    for i, room_id in ipairs(speedWalkPath) do
        if room_id and getRoomUserData(room_id, "fed2_flag_space") == "true" then
            space_moves = space_moves + 1
        end
    end

    return {origin_room_id=origin_room_id, dest_room_id=dest_room_id,
            total_moves=total_moves, space_moves=space_moves, success=true}
end

-- Armstrong Cuthbert jobs are always confined to the player's current cartel
-- ("Couldn't find any job in the Sol cartel..."), so a route between two AC
-- job locations never needs to leave that cartel. Mudlet's getPath() searches
-- the whole mapped room graph though (including every system reachable via
-- jump exits), which gets expensive once the galaxy navigator has mapped a
-- lot of the universe. This BFS stays bounded to the current cartel's own
-- rooms so galaxy size doesn't matter for this lookup.
local function cartelRoomSet(cartel)
    local rooms = {}
    for _, areaId in pairs(getAreaTable()) do
        if getAreaUserData(areaId, "fed2_cartel") == cartel then
            for _, roomId in ipairs(getAreaRooms(areaId) or {}) do
                rooms[roomId] = true
            end
        end
    end
    return rooms
end

function f2t_map_get_cartel_route_info(origin, destination)
    local origin_room_id, origin_err
    if origin and origin ~= "" then
        origin_room_id, origin_err = f2t_map_resolve_location(origin)
        if not origin_room_id then
            return nil, string.format("Cannot resolve origin: %s", origin_err or "unknown error")
        end
    else
        origin_room_id = F2T_MAP_CURRENT_ROOM_ID
        if not origin_room_id then return nil, "Current location unknown (no origin specified)" end
    end

    local dest_room_id, dest_err = f2t_map_resolve_location(destination)
    if not dest_room_id then
        return nil, string.format("Cannot resolve destination: %s", dest_err or "unknown error")
    end

    if origin_room_id == dest_room_id then
        return {origin_room_id=origin_room_id, dest_room_id=dest_room_id, space_moves=0, success=true}
    end

    local cartel = f2t_map_get_current_cartel()
    if not cartel then return nil, "Current cartel unknown" end

    local cartelRooms = cartelRoomSet(cartel)
    if not cartelRooms[origin_room_id] or not cartelRooms[dest_room_id] then
        return nil, string.format("Route is not within the %s cartel", cartel)
    end

    local visited = {[origin_room_id] = true}
    local parent  = {}
    local queue   = {origin_room_id}
    local head    = 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        if current == dest_room_id then break end
        for _, neighbors in ipairs({getRoomExits(current) or {}, getSpecialExits(current) or {}}) do
            for _, destId in pairs(neighbors) do
                if destId and destId > 0 and cartelRooms[destId] and not visited[destId] then
                    visited[destId] = true
                    parent[destId]  = current
                    queue[#queue + 1] = destId
                end
            end
        end
    end

    if not visited[dest_room_id] then
        return nil, string.format("No path found within the %s cartel", cartel)
    end

    local space_moves = 0
    local node = dest_room_id
    while node and node ~= origin_room_id do
        if getRoomUserData(node, "fed2_flag_space") == "true" then
            space_moves = space_moves + 1
        end
        node = parent[node]
    end

    return {origin_room_id=origin_room_id, dest_room_id=dest_room_id, space_moves=space_moves, success=true}
end

function f2t_map_show_route_info(origin, destination)
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n"); return
    end
    local route_info, err = f2t_map_get_route_info(origin, destination)
    if not route_info then
        cecho(string.format("\n<red>[map]<reset> %s\n", err or "Could not calculate route")); return
    end
    local origin_name       = origin and origin ~= "" and origin or "Current location"
    local origin_room_name  = getRoomName(route_info.origin_room_id) or "Unknown"
    local dest_room_name    = getRoomName(route_info.dest_room_id)   or "Unknown"
    local origin_area_id    = getRoomArea(route_info.origin_room_id)
    local dest_area_id      = getRoomArea(route_info.dest_room_id)
    local origin_area_name  = origin_area_id and getRoomAreaName(origin_area_id) or "Unknown"
    local dest_area_name    = dest_area_id   and getRoomAreaName(dest_area_id)   or "Unknown"

    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
    cecho("<cyan>                      Route Information<reset>\n")
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n\n")
    cecho("<yellow>Origin:<reset>\n")
    cecho(string.format("  <white>Query:<reset>    %s\n", origin_name))
    cecho(string.format("  <white>Room:<reset>     %s <dim_grey>(ID: %d)<reset>\n", origin_room_name, route_info.origin_room_id))
    cecho(string.format("  <white>Area:<reset>     %s\n\n", origin_area_name))
    cecho("<yellow>Destination:<reset>\n")
    cecho(string.format("  <white>Query:<reset>    %s\n", destination))
    cecho(string.format("  <white>Room:<reset>     %s <dim_grey>(ID: %d)<reset>\n", dest_room_name, route_info.dest_room_id))
    cecho(string.format("  <white>Area:<reset>     %s\n\n", dest_area_name))
    cecho("<yellow>Route Statistics:<reset>\n")
    cecho(string.format("  <white>Total Moves:<reset>  <green>%d<reset>\n", route_info.total_moves))
    cecho(string.format("  <white>Space Moves:<reset>  <ansiCyan>%d<reset> <dim_grey>(GTU)<reset>\n", route_info.space_moves))
    cecho(string.format("  <white>Ground Moves:<reset> %d\n", route_info.total_moves - route_info.space_moves))
    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
end
