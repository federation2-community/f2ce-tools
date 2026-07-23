-- f2ce-tools map — coordinate calculation (ported from map_coords.lua)

function f2t_map_calculate_coords_from_room_num(room_num)
    if not room_num then
        f2t_debug_log("[map] ERROR: Cannot calculate coords from nil room_num")
        return 0, 0, 0
    end
    local x = room_num % 64
    local y = -math.floor(room_num / 64)
    local z = 0
    f2t_debug_log("[map] Calculated coords for room #%d: (%d, %d, %d)", room_num, x, y, z)
    return x, y, z
end

function f2t_map_set_room_coords(room_id, x, y, z)
    if not room_id or not roomExists(room_id) then
        f2t_debug_log("[map] ERROR: Cannot set coords for invalid room: %s", tostring(room_id))
        return false
    end
    setRoomCoordinates(room_id, x, y, z)
    f2t_debug_log("[map] Room %d coordinates set to (%d, %d, %d)", room_id, x, y, z)
    return true
end

function f2t_map_get_opposite_direction(direction)
    local opposites = {
        n = "s", s = "n", e = "w", w = "e",
        ne = "sw", sw = "ne", nw = "se", se = "nw",
        u = "d", d = "u", up = "down", down = "up",
        ["in"] = "out", out = "in",
    }
    return opposites[direction]
end

function f2t_map_direction_to_number(direction)
    local dir_map = {
        n = 1, ne = 2, nw = 3, e = 4, w = 5, s = 6, se = 7, sw = 8,
        u = 9, d = 10, ["in"] = 11, out = 12, up = 9, down = 10,
        north = 1, northeast = 2, northwest = 3, east = 4, west = 5,
        south = 6, southeast = 7, southwest = 8,
    }
    return dir_map[direction]
end

function f2t_map_normalize_direction(direction)
    local normalize_map = {
        north = "n", northeast = "ne", northwest = "nw",
        east = "e", west = "w", south = "s",
        southeast = "se", southwest = "sw",
        up = "u", down = "d",
    }
    return normalize_map[direction] or direction
end
