-- Initialize Federation 2 mapper component
-- This script loads first and sets up the mapper environment

-- ========================================
-- Mudlet Mapper Registration
-- ========================================

-- Declare this as a custom mapper script to prevent Mudlet warnings
mudlet = mudlet or {}
mudlet.mapper_script = true

f2t_debug_log("[map] Mapper script registered with Mudlet")

-- ========================================
-- Persistent Settings Initialization
-- ========================================

-- Register settings
f2t_settings_register("map", "planet_nav_default", {
    description = "Default destination when navigating to a planet (shuttlepad or orbit)",
    default = "shuttlepad",
    choices = {"shuttlepad", "orbit"},
    validator = function(value)
        if value ~= "shuttlepad" and value ~= "orbit" then
            return false, "Must be 'shuttlepad' or 'orbit'"
        end
        return true
    end
})

f2t_settings_register("map", "enabled", {
    description = "Enable/disable auto-mapping",
    default = true,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

f2t_settings_register("map", "speedwalk_timeout", {
    description = "Timeout in seconds to wait for movement (detects stuck speedwalk)",
    default = 3,
    min = 1, max = 10,
    validator = function(value)
        if type(value) ~= "number" then
            return false, "Must be a number"
        end
        if value < 1 or value > 10 then
            return false, "Must be between 1 and 10 seconds"
        end
        return true
    end
})

f2t_settings_register("map", "speedwalk_max_retries", {
    description = "Maximum retry attempts before stopping speedwalk",
    default = 3,
    min = 1, max = 10,
    validator = function(value)
        if type(value) ~= "number" then
            return false, "Must be a number"
        end
        if value < 1 or value > 10 then
            return false, "Must be between 1 and 10 retries"
        end
        return true
    end
})

f2t_settings_register("map", "map_manual_confirm", {
    description = "Require confirmation for destructive manual mapping operations",
    default = true,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

f2t_settings_register("map", "area_zoom", {
    description = "Default zoom level for new map areas (3-50)",
    default = 10,
    min = 3, max = 50,
    validator = function(value)
        local num = tonumber(value)
        if not num then
            return false, "Must be a number"
        end
        if num < 3 or num > 50 then
            return false, "Must be between 3 and 50"
        end
        return true
    end
})

f2t_settings_register("map", "brief_additional_flags", {
    description = "Additional flags to discover in brief mode (shuttlepad is always included)",
    default = "exchange",
    validator = function(value)
        -- Accept string (single flag) or comma-separated list
        if type(value) ~= "string" then
            return false, "Must be a string (flag name or comma-separated list)"
        end
        return true
    end
})

-- NOTE: System and cartel modes ALWAYS do brief exploration (flag discovery only)
-- There is no user setting for this - it's the only supported mode

-- Load settings into globals
F2T_MAP_ENABLED = f2t_settings_get("map", "enabled")
F2T_MAP_PLANET_NAV_DEFAULT = f2t_settings_get("map", "planet_nav_default")

-- ========================================
-- Mapper State Variables
-- ========================================

-- Track current room
F2T_MAP_CURRENT_ROOM_ID = nil

-- ========================================
-- Map Initialization
-- ========================================

-- Open map widget to initialize the map database
-- This ensures the map database exists for auto-mapping

--If UI is enabled, map will appear in a frame with a movable tab, so there is no need to open default map widget. Unsure if this is important for database at this time
if not F2T_UI_STATE.enabled then
  local success, err = pcall(openMapWidget)
  if success then
      f2t_debug_log("[map] Map widget opened and database initialized")
  else
      f2t_debug_log("[map] WARNING: Failed to open map widget: %s", tostring(err))
  end
else
    f2t_debug_log("[map} map widget opening skipped, mapper initialize in UI]")
end
-- ========================================
-- Initialization Message
-- ========================================

if F2T_MAP_ENABLED then
    cecho("\n<green>[map]<reset> Auto-mapping <yellow>ENABLED<reset>\n")
    f2t_debug_log("[map] Mapper initialized (enabled)")
else
    cecho("\n<dim_grey>[map]<reset> Auto-mapping <red>DISABLED<reset>\n")
    f2t_debug_log("[map] Mapper initialized (disabled)")
end
