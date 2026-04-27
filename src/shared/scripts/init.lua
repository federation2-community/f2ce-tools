-- Initialize fed2-tools shared utilities
-- This script loads first and sets up core functionality

-- generic_mapper conflicts with fed2-tools map system.
-- Uninstall it automatically if present.
if table.contains(getPackages(), "generic_mapper") then
    cecho("\n<yellow>[fed2-tools]<reset> Removing incompatible package: generic_mapper\n")
    uninstallPackage("generic_mapper")
end

-- ========================================
-- Persistent Settings File Path
-- ========================================

-- Note: @PKGNAME@ substitution only works in XML, use actual package name
F2T_SETTINGS_FILE = getMudletHomeDir() .. "/fed2-tools_settings.json"

-- ========================================
-- Load Saved Settings
-- ========================================

-- Initialize settings table
f2t_settings = f2t_settings or {}

-- Load settings from file if it exists (using JSON format)
if io.exists(F2T_SETTINGS_FILE) then
    local success, err = pcall(function()
        local file = io.open(F2T_SETTINGS_FILE, "r")
        local json_str = file:read("*all")
        file:close()

        local loaded_settings = yajl.to_value(json_str)

        -- Merge loaded settings
        for k, v in pairs(loaded_settings) do
            f2t_settings[k] = v
        end
    end)

    if success then
        cecho("\n<dim_grey>[fed2-tools]<reset> Settings loaded from disk\n")
    else
        cecho(string.format("\n<yellow>[fed2-tools]<reset> Could not load settings: %s\n", tostring(err)))
        cecho("\n<dim_grey>[fed2-tools]<reset> Using defaults\n")
    end
else
    cecho("\n<dim_grey>[fed2-tools]<reset> No saved settings found, using defaults\n")
end

-- ========================================
-- Register Shared Settings
-- ========================================

-- Initialize registry (defined in f2t_settings_manager.lua)
F2T_SETTINGS_REGISTRY = F2T_SETTINGS_REGISTRY or {}

-- Register debug setting
f2t_settings_register("shared", "debug", {
    description = "Enable debug logging for all fed2-tools components",
    default = false,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

-- Load debug setting into global
F2T_DEBUG = f2t_settings_get("shared", "debug")

-- Limit column count for formatting
COLS = getColumnCount() > 100 and 100 or getColumnCount()

-- Initialize message
if F2T_DEBUG then
    cecho("\n<green>[fed2-tools-debug]<reset> Debug mode is currently <yellow>ON<reset> (persists between sessions)\n")
end

-- ========================================
-- Auto-Start Stamina Monitoring
-- ========================================

-- Start stamina monitoring if enabled (delay to ensure all scripts loaded)
tempTimer(1, function()
    local threshold = f2t_settings_get("shared", "stamina_threshold") or 0
    if threshold > 0 and f2t_stamina_start_monitoring then
        f2t_stamina_start_monitoring()
        f2t_debug_log("[shared] Stamina monitoring auto-started (threshold=%d)", threshold)
    end
end)

-- ========================================
-- Auto-Start Death Monitoring
-- ========================================

-- Start death monitoring if enabled (delay to ensure all scripts loaded)
tempTimer(1, function()
    if f2t_settings_get("shared", "death_monitor_enabled") and f2t_death_start_monitoring then
        f2t_death_start_monitoring()
        f2t_debug_log("[shared] Death monitoring auto-started")
    end
end)