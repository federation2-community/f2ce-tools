-- f2ce-tools — settings layer
--
-- Wraps Mux.settings with the f2t_settings_* API used by all components.
-- Calls are queued when Mux is not yet available and flushed by init.lua's
-- muxletReady handler once Mux is ready.

local _registry      = {}   -- {component → {key → config}}  (always maintained)
local _localData     = {}   -- fallback store when Mux unavailable
-- Every registration in call order. A Muxlet reload wipes its own registry, so
-- the whole list is replayed on each muxletReady; order matters because a
-- namespace's tab path comes from its first registration.
local _registrations = {}

-- ── f2t_settings proxy ───────────────────────────────────────────────────────
-- Scripts that access f2t_settings.map.destinations directly (destinations.lua)
-- resolve through this proxy to Mux.settings._data when available.
f2t_settings = setmetatable({}, {
    __index = function(_, component)
        local store = (Mux and Mux.settings and Mux.settings._data) or _localData
        store[component] = store[component] or {}
        return store[component]
    end,
    __newindex = function(_, component, v)
        local store = (Mux and Mux.settings and Mux.settings._data) or _localData
        store[component] = v
    end,
})

-- ── Persistence ───────────────────────────────────────────────────────────────

function f2t_save_settings()
    if Mux and Mux.settings and Mux.settings.save then
        Mux.settings.save()
    end
end

-- ── Registration ─────────────────────────────────────────────────────────────

local function registerWithMux(component, key, config)
    Mux.settings.register(component, key, {
        tab         = config.tab,
        order       = config.order,
        label       = config.label,
        description = config.description,
        default     = config.default,
        choices     = config.choices,
        min         = config.min,
        max         = config.max,
    })
end

function f2t_settings_register(component, key, config)
    if not (_registry[component] and _registry[component][key]) then
        table.insert(_registrations, {component = component, key = key})
    end
    _registry[component] = _registry[component] or {}
    _registry[component][key] = config

    if Mux and Mux.settings and Mux.settings.register then
        registerWithMux(component, key, config)
    end
end

-- Replay every registration into Mux.settings, called from f2tInit on each
-- muxletReady. Mux.settings.register is idempotent per key.
function f2t_settings_flush_registrations()
    if not (Mux and Mux.settings and Mux.settings.register) then return end
    for _, reg in ipairs(_registrations) do
        registerWithMux(reg.component, reg.key, _registry[reg.component][reg.key])
    end
end

-- ── Access ────────────────────────────────────────────────────────────────────

function f2t_settings_get(component, key)
    if Mux and Mux.settings and Mux.settings.get then
        return Mux.settings.get(component, key)
    end
    local store = _localData[component] or {}
    local v = store[key]
    if v ~= nil then return v end
    local reg = _registry[component] and _registry[component][key]
    return reg and reg.default or nil
end

function f2t_settings_set(component, key, value)
    if Mux and Mux.settings and Mux.settings.set then
        return Mux.settings.set(component, key, value)
    end
    _localData[component] = _localData[component] or {}
    _localData[component][key] = value
    return true
end

-- ── Display / command helpers ─────────────────────────────────────────────────

function f2t_handle_settings_command(component, argsStr)
    if Mux and Mux.settings and Mux.settings.handleCommand then
        return Mux.settings.handleCommand(component, argsStr)
    end
    cecho(string.format("\n<yellow>[%s]<reset> Settings system not yet available\n", component))
end

-- ── Core f2ce-tools settings (f2t namespace) ──────────────────────────────────
--
-- The update-check toggles that used to live here (update_check_enabled,
-- update_check_remind_skip, for the old MPR-based version.lua checker) are now
-- registered by Muxlet's own update system instead, under this same "f2t"
-- namespace but their own "F2CE-Tools/Update" tab, via Mux.configureHost's
-- updateSettingsNamespace/updateSettingsTab (see init.lua) — see Muxlet's
-- update.lua for that logic.
--
-- On web none of that registers: init.lua withholds updateRepo there because the
-- page installs and upgrades the package itself, silently. So the "f2t"
-- namespace is empty on web and no Update tab appears.

