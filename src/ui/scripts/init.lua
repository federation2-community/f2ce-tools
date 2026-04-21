-- Initialize UI component
UI = UI or {}

f2t_settings_register("ui", "enabled", {
    description = "Enable/disable ui",
    default = true,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

f2t_settings_register("ui", "hide_chat_messages", {
    description = "Hide inbound chat (com/tell/say) from main console (route to Chat tab only)",
    default = true,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

f2t_settings_register("ui", "hide_movement_messages", {
    description = "Hide player/ship movement messages from main console (route to General tab only)",
    default = true,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

-- Load saved state (default to enabled)
local saved_enabled = f2t_settings_get("ui", "enabled")
if saved_enabled == nil then
    saved_enabled = true
end

-- UI Manager: Central control for showing/hiding UI and enabling/disabling triggers
-- Following the persistent state pattern from shared/CLAUDE.md
F2T_UI_STATE = F2T_UI_STATE or {
    enabled = saved_enabled,

    -- Track created UI elements (populate during creation)
    containers   = {}, -- {name = container_object, ...}

    -- Track trigger/alias names to toggle (strings, not IDs)
    -- These are PERMANENT triggers/aliases from the ui component
    triggers = {}, -- {"trigger_name_1", "trigger_name_2", ...}
    aliases  = {}, -- {"alias_name_1", "alias_name_2", ...}
    events   = {}  -- {name = "event_name", id = event_object, ...}
}

function f2t_ui_register_container(name, container_object)
    F2T_UI_STATE.containers[name] = container_object
end

-- Register triggers/aliases that should be toggled with UI
function f2t_ui_register_trigger(trigger_name)
    if not f2t_has_value(F2T_UI_STATE.triggers, trigger_name) then
        table.insert(F2T_UI_STATE.triggers, trigger_name)
    end
end

function f2t_ui_register_alias(alias_name)
    if not f2t_has_value(F2T_UI_STATE.aliases, alias_name) then
        table.insert(F2T_UI_STATE.aliases, alias_name)
    end
end

-- Registers an event with mudlet and also stores it in a UI registry for enable/disable
function f2t_ui_register_event(trigger, action)
    f2t_debug_log("registering event with trigger: %s and action: %s action is type: %s", trigger, action, type(action))

    if type(action) ~= "string" then error("action function must be given in string form") end

    F2T_UI_STATE.events[action]         = {}
    F2T_UI_STATE.events[action].trigger = trigger

    if F2T_UI_STATE.events[action].id then killAnonymousEventHandler(F2T_UI_STATE.events[action].id) end

    F2T_UI_STATE.events[action].id = registerAnonymousEventHandler(trigger, action)
end

-- Enable UI (show elements, enable triggers/aliases/events)
function f2t_ui_enable()
    f2t_debug_log("[ui] f2t_ui_enable CALLED")

    if F2T_UI_STATE.enabled then
        f2t_debug_log("[ui] UI already enabled")
        return
    end

    -- Since we do mapper in UI, we dont want any existing map widget present
    closeMapWidget()

    F2T_UI_STATE.enabled = true

    -- If we never ran the usual initial startup, then do that
    if not ui_built     then ui_build()            end
    if not ui_triggered then ui_register_trigger() end
    if not ui_evented   then ui_register_event()   end
    if not ui_aliased   then ui_register_alias()   end

    -- If there were any previously-registered elements, just enable them, the above probably wont have run
    -- Enable UI
    for name, container in pairs(F2T_UI_STATE.containers) do
        container:show()

        f2t_debug_log("[ui] Showing container: %s", name)
    end

    -- Enable triggers
    for _, trigger_name in ipairs(F2T_UI_STATE.triggers) do
        enableTrigger(trigger_name)
        f2t_debug_log("[ui] Enabled trigger: %s", trigger_name)
    end

    -- Enable aliases
    for _, alias_name in ipairs(F2T_UI_STATE.aliases) do
        enableAlias(alias_name)
        f2t_debug_log("[ui] Enabled alias: %s", alias_name)
    end

    -- Enable events
    for action, data in pairs(F2T_UI_STATE.events) do
        if data.id then killAnonymousEventHandler(data.id) end

        F2T_UI_STATE.events[action].id = registerAnonymousEventHandler(data.trigger, action)
        f2t_debug_log("[ui] Enabled event with trigger: %s and action: %s", data.trigger, action)
    end

    -- Save state
    f2t_settings_set("ui", "enabled", true)

    cecho("\n<green>[ui]<reset> UI enabled\n")
end

-- Disable UI (hide elements, disable triggers/aliases/events)
function f2t_ui_disable()
    if not F2T_UI_STATE.enabled then
        f2t_debug_log("[ui] UI already disabled")
        return
    end

    -- If we disable ui, give them their map widget back
    openMapWidget()

    F2T_UI_STATE.enabled = false

    -- Hide all UI elements (don't destroy them!)
    for name, container in pairs(F2T_UI_STATE.containers) do
        container:hide()
        
        f2t_debug_log("[ui] Hiding container: %s", name)
    end

    -- Disable triggers
    for _, trigger_name in ipairs(F2T_UI_STATE.triggers) do
        disableTrigger(trigger_name)
        f2t_debug_log("[ui] Disabled trigger: %s", trigger_name)
    end

    -- Disable aliases
    for _, alias_name in ipairs(F2T_UI_STATE.aliases) do
        disableAlias(alias_name)
        f2t_debug_log("[ui] Disabled alias: %s", alias_name)
    end

    -- Disable events
    for action, data in pairs(F2T_UI_STATE.events) do
        if data.id then killAnonymousEventHandler(data.id) end

        f2t_debug_log("[ui] Disabled event with trigger: %s and action: %s", data.trigger, action)
    end

    -- Save state
    f2t_settings_set("ui", "enabled", false)

    cecho("\n<yellow>[ui]<reset> UI disabled\n")
end

-- Status display
function f2t_ui_status()
    local status = F2T_UI_STATE.enabled and "<green>ENABLED<reset>" or "<red>DISABLED<reset>"

    cecho(string.format("\n<cyan>[ui]<reset> Status: %s\n", status))

    cecho(string.format("  Containers: %d\n", f2t_table_count_keys(F2T_UI_STATE.containers)))

    cecho(string.format("  Triggers: %d | Aliases: %d | Events: %d\n", 
        f2t_table_count_keys(F2T_UI_STATE.triggers),
        f2t_table_count_keys(F2T_UI_STATE.aliases),
        f2t_table_count_keys(F2T_UI_STATE.events)
    ))
end

f2t_debug_log("[ui] Component initialized, enabled=%s", tostring(saved_enabled))
