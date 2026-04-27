-- Calculate route information between two locations

-- Parameters:
--   origin: Origin location string (same formats as nav command) or nil for current room
--   destination: Destination location string (same formats as nav command)

-- Returns: table with route info or nil, error_message
--   {
--     origin_room_id = number,
--     dest_room_id   = number,
--     total_moves    = number, -- Total path length (#speedWalkDir)
--     space_moves    = number, -- Moves in space only (for GTU calculation)
--     success        = boolean
--   }

function f2t_map_get_route_info(origin, destination)
  -- Resolve origin
  local origin_room_id, origin_err

  if origin and origin ~= "" then
    -- This function is in map_room_query and uses various methods to get mudlet room ID from a name input
    origin_room_id, origin_err = f2t_map_resolve_location(origin)

    if not origin_room_id then
      return nil, string.format("Cannot resolve origin: %s", origin_err or "unknown error")
    end
  else
    -- Use current room as origin
    origin_room_id = F2T_MAP_CURRENT_ROOM_ID

    if not origin_room_id then
      return nil, "Current location unknown (no origin specified)"
    end
  end

  -- Resolve destination
  local dest_room_id, dest_err = f2t_map_resolve_location(destination)

  if not dest_room_id then
    return nil, string.format("Cannot resolve destination: %s", dest_err or "unknown error")
  end

  -- Same room check
  if origin_room_id == dest_room_id then
    return {
      origin_room_id = origin_room_id,
      dest_room_id = dest_room_id,
      total_moves = 0,
      space_moves = 0,
      success = true
    }
  end

  -- Calculate path using Mudlet's pathfinding
  local success, cost = getPath(origin_room_id, dest_room_id)

  if not success then
    return nil, "No path found between origin and destination"
  end

  -- Count total moves
  local total_moves = #speedWalkDir

  -- Count space moves (GTU only counts spaceship movements)
  -- Space moves are moves where the room has the "space" flag
  local space_moves = 0

  for i, room_id in ipairs(speedWalkPath) do
    if room_id then
      local is_space = getRoomUserData(room_id, "fed2_flag_space")

      if is_space == "true" then space_moves = space_moves + 1 end
    end
  end

  f2t_debug_log("[map] Route calculated: %d -> %d, total=%d, space=%d", origin_room_id, dest_room_id, total_moves, space_moves)

  return {
    origin_room_id = origin_room_id,
    dest_room_id = dest_room_id,
    total_moves = total_moves,
    space_moves = space_moves,
    success = true
  }
end

-- Display route information between two locations
-- Parameters:
--   origin: Origin location string (optional, defaults to current location)
--   destination: Destination location string

function f2t_map_show_route_info(origin, destination)
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n")
        return
    end
    
    -- Get route info using the existing function
    local route_info, err = f2t_map_get_route_info(origin, destination)
    
    if not route_info then
        cecho(string.format("\n<red>[map]<reset> %s\n", err or "Could not calculate route"))
        return
    end
    
    -- Get readable names for the locations
    local origin_name
    if origin and origin ~= "" then
        origin_name = origin
    else
        origin_name = "Current location"
    end
    
    -- Get room names from Mudlet if available
    local origin_room_name = getRoomName(route_info.origin_room_id) or "Unknown"
    local dest_room_name   = getRoomName(route_info.dest_room_id)   or "Unknown"
    
    -- Get area names
    local origin_area_id   = getRoomArea(route_info.origin_room_id)
    local dest_area_id     = getRoomArea(route_info.dest_room_id)
    local origin_area_name = origin_area_id and getRoomAreaName(origin_area_id) or "Unknown"
    local dest_area_name   = dest_area_id   and getRoomAreaName(dest_area_id)   or "Unknown"
    
    -- Display the route information
    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
    cecho("<cyan>                      Route Information<reset>\n")
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n\n")
    
    -- Origin details
    cecho("<yellow>Origin:<reset>\n")
    cecho(string.format("  <white>Query:<reset>    %s\n", origin_name))
    cecho(string.format("  <white>Room:<reset>     %s <dim_grey>(ID: %d)<reset>\n", origin_room_name, route_info.origin_room_id))
    cecho(string.format("  <white>Area:<reset>     %s\n", origin_area_name))
    cecho("\n")
    
    -- Destination details
    cecho("<yellow>Destination:<reset>\n")
    cecho(string.format("  <white>Query:<reset>    %s\n", destination))
    cecho(string.format("  <white>Room:<reset>     %s <dim_grey>(ID: %d)<reset>\n", dest_room_name, route_info.dest_room_id))
    cecho(string.format("  <white>Area:<reset>     %s\n", dest_area_name))
    cecho("\n")
    
    -- Route statistics
    cecho("<yellow>Route Statistics:<reset>\n")
    cecho(string.format("  <white>Total Moves:<reset>  <green>%d<reset>\n", route_info.total_moves))
    cecho(string.format("  <white>Space Moves:<reset>  <ansiCyan>%d<reset> <dim_grey>(GTU)<reset>\n", route_info.space_moves))
    
    local ground_moves = route_info.total_moves - route_info.space_moves
    cecho(string.format("  <white>Ground Moves:<reset> %d\n", ground_moves))
    
    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
end

f2t_debug_log("[map] Route calculation functions loaded")