-- Shared settings management system for fed2-tools components
-- Provides consistent interface for component settings

-- ========================================
-- Settings Registry
-- ========================================

-- Component settings definitions
-- Format: [component_name] = {[setting_name] = {description, default, validator_fn, choices, min, max}}
F2T_SETTINGS_REGISTRY = F2T_SETTINGS_REGISTRY or {}

-- Insertion-order index: F2T_SETTINGS_ORDER[component] = {"setting1", "setting2", ...}
-- Used by the settings UI to display rows in registration order.
F2T_SETTINGS_ORDER = F2T_SETTINGS_ORDER or {}

-- Register a setting for a component
-- component: component name (e.g., "map", "refuel")
-- setting_name: setting key (e.g., "planet_nav_default")
-- config: {description, default, validator, choices, min, max}
--   - description: user-facing description
--   - default: default value
--   - validator: optional function(value) -> boolean, error_msg
--   - choices: optional array of allowed string values (drives cycle widget in settings UI)
--   - min, max: optional numeric bounds (drives stepper widget in settings UI when range <= 100)
function f2t_settings_register(component, setting_name, config)
    F2T_SETTINGS_REGISTRY[component] = F2T_SETTINGS_REGISTRY[component] or {}
    F2T_SETTINGS_ORDER[component]    = F2T_SETTINGS_ORDER[component]    or {}

    F2T_SETTINGS_REGISTRY[component][setting_name] = {
        description = config.description or "",
        default     = config.default,
        validator   = config.validator,
        choices     = config.choices,
        min         = config.min,
        max         = config.max,
    }

    -- Track insertion order; guard against duplicate registration on package reload.
    local already = false
    for _, n in ipairs(F2T_SETTINGS_ORDER[component]) do
        if n == setting_name then already = true; break end
    end
    if not already then
        table.insert(F2T_SETTINGS_ORDER[component], setting_name)
    end

    f2t_debug_log("[settings] Registered: %s.%s (default: %s)", component, setting_name, tostring(config.default))
end

-- ========================================
-- Settings Access
-- ========================================

-- Get a setting value (returns actual value or default)
function f2t_settings_get(component, setting_name)
    f2t_settings = f2t_settings or {}
    f2t_settings[component] = f2t_settings[component] or {}

    local value = f2t_settings[component][setting_name]
    if value ~= nil then
        return value
    end

    -- Return default if registered
    if F2T_SETTINGS_REGISTRY[component] and F2T_SETTINGS_REGISTRY[component][setting_name] then
        return F2T_SETTINGS_REGISTRY[component][setting_name].default
    end

    return nil
end

-- Set a setting value
function f2t_settings_set(component, setting_name, value)
    -- Reject unregistered settings
    if not F2T_SETTINGS_REGISTRY[component] or not F2T_SETTINGS_REGISTRY[component][setting_name] then
        return false, string.format("Unknown setting '%s'", setting_name)
    end

    f2t_settings = f2t_settings or {}
    f2t_settings[component] = f2t_settings[component] or {}

    -- Get default type from registry
    local default_type = type(F2T_SETTINGS_REGISTRY[component][setting_name].default)

    -- Convert string input to proper type
    if type(value) == "string" then
        if default_type == "number" then
            value = tonumber(value)
        elseif default_type == "boolean" then
            if value == "true" then
                value = true
            elseif value == "false" then
                value = false
            end
        end
    end

    -- Validate if validator exists
    local validator = F2T_SETTINGS_REGISTRY[component][setting_name].validator
    if validator then
        local valid, error_msg = validator(value)
        if not valid then
            return false, error_msg
        end
    end

    f2t_settings[component][setting_name] = value
    f2t_save_settings()
    f2t_debug_log("[settings] Set: %s.%s = %s", component, setting_name, tostring(value))
    return true
end

-- Clear a setting (revert to default)
-- Returns: true on success, false and error message on failure
function f2t_settings_clear(component, setting_name)
    -- Reject unregistered settings
    if not F2T_SETTINGS_REGISTRY[component] or not F2T_SETTINGS_REGISTRY[component][setting_name] then
        return false, string.format("Unknown setting '%s'", setting_name)
    end

    f2t_settings = f2t_settings or {}
    f2t_settings[component] = f2t_settings[component] or {}

    f2t_settings[component][setting_name] = nil
    f2t_save_settings()
    f2t_debug_log("[settings] Cleared: %s.%s", component, setting_name)
    return true
end

-- List all settings for a component
function f2t_settings_list(component)
    local settings = {}
    if F2T_SETTINGS_REGISTRY[component] then
        for setting_name, config in pairs(F2T_SETTINGS_REGISTRY[component]) do
            local current_value = f2t_settings_get(component, setting_name)
            local is_default = f2t_settings[component] and f2t_settings[component][setting_name] == nil
            table.insert(settings, {
                name = setting_name,
                description = config.description,
                value = current_value,
                default = config.default,
                is_default = is_default
            })
        end
    end

    -- Sort by name
    table.sort(settings, function(a, b) return a.name < b.name end)
    return settings
end

-- ========================================
-- Display Helpers
-- ========================================

-- Show settings list for a component
function f2t_settings_show_list(component)
    local settings = f2t_settings_list(component)

    if #settings == 0 then
        cecho(string.format("\n<yellow>[%s]<reset> No settings registered\n", component))
        return
    end

    cecho(string.format("\n<green>[%s]<reset> Settings:\n\n", component))

    for _, setting in ipairs(settings) do
        local value_str = tostring(setting.value)
        local default_marker = setting.is_default and " <dim_grey>(default)<reset>" or ""
        
        cecho(string.format("  <cyan>%s<reset>: <yellow>%s<reset>%s\n", 
            setting.name, value_str, default_marker))
        
        if setting.description and setting.description ~= "" then
            cecho(string.format("    <dim_grey>%s<reset>\n", setting.description))
        end
    end

    cecho("\n")
end

-- Show a specific setting
function f2t_settings_show_get(component, setting_name)
    local value = f2t_settings_get(component, setting_name)
    local config = F2T_SETTINGS_REGISTRY[component] and F2T_SETTINGS_REGISTRY[component][setting_name]

    if not config then
        cecho(string.format("\n<red>[%s]<reset> Unknown setting: %s\n", component, setting_name))
        return
    end

    local is_default = f2t_settings[component] and f2t_settings[component][setting_name] == nil
    local default_marker = is_default and " <dim_grey>(default)<reset>" or ""

    cecho(string.format("\n<green>[%s]<reset> <cyan>%s<reset>: <yellow>%s<reset>%s\n",
        component, setting_name, tostring(value), default_marker))

    if config.description and config.description ~= "" then
        cecho(string.format("  <dim_grey>%s<reset>\n", config.description))
    end

    cecho("\n")
end

-- ========================================
-- Command Handler
-- ========================================

-- Handle settings command parsing and execution
-- Parameters:
--   component: component name (e.g., "map", "refuel", "shared")
--   args_str: arguments string after "settings" (e.g., "", "list", "get debug", "set threshold 80")
-- Returns: true if handled successfully, false otherwise
--
-- Replaces duplicated settings parsing logic across components
-- Usage in aliases:
--   if subcommand == "settings" then
--       f2t_handle_settings_command("component", rest_of_args)
--       return
--   end
function f2t_handle_settings_command(component, args_str)
    -- No arguments or "list" - show all settings
    if not args_str or args_str == "" or args_str == "list" then
        f2t_settings_show_list(component)
        return true
    end

    -- Parse arguments into words
    local words = {}
    for word in string.gmatch(args_str, "%S+") do
        table.insert(words, word)
    end

    local subcmd = words[1]

    -- Handle list subcommand
    if subcmd == "list" then
        f2t_settings_show_list(component)
        return true
    end

    -- Handle get subcommand
    if subcmd == "get" then
        if not words[2] then
            cecho(string.format("\n<red>[%s]<reset> Usage: settings get <name>\n", component))
            return false
        end
        f2t_settings_show_get(component, words[2])
        return true
    end

    -- Handle set subcommand
    if subcmd == "set" then
        if not words[2] or not words[3] then
            cecho(string.format("\n<red>[%s]<reset> Usage: settings set <name> <value>\n", component))
            return false
        end

        -- Join all remaining words as the value (supports multi-word values like "artifacts, firewalls")
        local value = f2t_parse_rest(words, 3)

        local success, error_msg = f2t_settings_set(component, words[2], value)
        if success then
            cecho(string.format("\n<green>[%s]<reset> Setting <cyan>%s<reset> set to <yellow>%s<reset>\n",
                component, words[2], value))
            return true
        else
            cecho(string.format("\n<red>[%s]<reset> Failed to set %s: %s\n",
                component, words[2], error_msg or "unknown error"))
            return false
        end
    end

    -- Handle clear subcommand
    if subcmd == "clear" then
        if not words[2] then
            cecho(string.format("\n<red>[%s]<reset> Usage: settings clear <name>\n", component))
            return false
        end

        local success, error_msg = f2t_settings_clear(component, words[2])
        if success then
            local default_value = f2t_settings_get(component, words[2])
            cecho(string.format("\n<green>[%s]<reset> Setting <cyan>%s<reset> cleared (reverted to default: <yellow>%s<reset>)\n",
                component, words[2], tostring(default_value)))
            return true
        else
            cecho(string.format("\n<red>[%s]<reset> %s\n", component, error_msg))
            return false
        end
    end

    -- Unknown subcommand
    cecho(string.format("\n<red>[%s]<reset> Unknown settings command: %s\n", component, subcmd))
    cecho("<cyan>Available commands: list, get, set, clear<reset>\n")
    return false
end
