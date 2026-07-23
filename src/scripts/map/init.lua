-- f2ce-tools map — initialization
--
-- Declares this package as the Mudlet mapper controller and initializes
-- global map state variables.  Settings are registered in settings.lua.

mudlet = mudlet or {}
mudlet.mapper_script = true

-- ── Globals ───────────────────────────────────────────────────────────────────

F2T_MAP_ENABLED            = f2t_settings_get("map", "enabled")
F2T_MAP_PLANET_NAV_DEFAULT = f2t_settings_get("map", "planet_nav_default")
F2T_MAP_MOVEMENT_KEYS      = f2t_settings_get("map", "movement_keys")
F2T_MAP_CURRENT_ROOM_ID    = nil

f2t_debug_log("[map] Mapper initialized (enabled=%s)", tostring(F2T_MAP_ENABLED))
