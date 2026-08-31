-- f2ce-tools map — initialization
--
-- Declares this package as the Mudlet mapper controller and initializes
-- global map state variables.  Settings are registered in settings.lua.

mudlet = mudlet or {}
mudlet.mapper_script = true

-- ── Globals ───────────────────────────────────────────────────────────────────

-- F2T_MAP_ENABLED is a global because "map on"/"map off" assign it by hand.
-- The other two settings have no such writer, so they are read where they are
-- used instead of snapshotted here - a snapshot goes stale the moment the
-- settings tab changes them, and both are consulted on cold paths where the
-- lookup costs nothing.
F2T_MAP_ENABLED         = f2t_settings_get("map", "enabled")
F2T_MAP_CURRENT_ROOM_ID = nil

-- Rooms are the unit of every routing decision, so debug output names them
-- the same way everywhere: "4630 (Stellar Solar Orbit and ISL, Stellar Space
-- / Stellar)". An id on its own says nothing about whether it is the room the
-- caller meant.
function f2t_map_describe_room(room_id)
    if not room_id then return "none" end
    if not roomExists(room_id) then return string.format("%s (does not exist)", tostring(room_id)) end
    local area_id = getRoomArea(room_id)
    return string.format("%d (%s, %s / %s)", room_id,
        getRoomName(room_id) or "unnamed",
        area_id and getRoomAreaName(area_id) or "no area",
        getRoomUserData(room_id, "fed2_system") or "no system")
end

-- Where "nav <planet>" lands by default: shuttlepad, orbit or exchange.
function f2t_map_planet_nav_default()
    return f2t_settings_get("map", "planet_nav_default") or "shuttlepad"
end

function f2t_map_movement_keys_enabled()
    return f2t_settings_get("map", "movement_keys") and true or false
end

f2t_debug_log("[map] Mapper initialized (enabled=%s)", tostring(F2T_MAP_ENABLED))
