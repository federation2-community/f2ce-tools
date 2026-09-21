-- F2CE-Tools stable module API v1
-- Candidate for adoption into the official F2CE source tree.
-- No license is asserted; source ownership/licensing must be confirmed upstream.

F2CE = type(F2CE) == "table" and F2CE or {}
F2CE.API = type(F2CE.API) == "table" and F2CE.API or {}

local existing = F2CE.API.v1
if type(existing) == "table" and type(existing._reload) == "function" then
    existing:_reload()
end

local API = {
    _build = "1.2.0-candidate.4",
    version = "1.2.0",
    f2ce_version = "unknown",
    capabilities = {},
    schemas = {},
    _adapter = nil,
    _modules = {},
    _subscriptions = {},
    _next_id = 0,
}
F2CE.API.v1 = API

API.integration = {
    scope = "F2CE gameplay services",
    ui = {
        provider = "Muxlet",
        registration = "Mux.registerContent",
        note = "Register visual content and workspace layouts directly with Muxlet.",
    },
}

local unpack_values = table.unpack or unpack

local function next_id(prefix)
    API._next_id = API._next_id + 1
    return string.format("%s:%d", prefix, API._next_id)
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function readonly_copy(value)
    -- A copy is the cross-version contract. Lua 5.1 cannot make nested tables
    -- reliably immutable, so callers may mutate their copy without affecting F2CE.
    return copy(value)
end

local function api_error(code, message, details)
    return setmetatable({ code = code, message = message, details = readonly_copy(details) }, {
        __tostring = function(err) return string.format("%s: %s", err.code, err.message) end,
    })
end

local function safe_call(label, fn, ...)
    if type(fn) ~= "function" then return true end
    local args = { ... }
    local function invoke() return fn(unpack_values(args)) end
    local ok, a, b, c = xpcall(invoke, function(err)
        local trace = debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
        return api_error("E_CALLBACK", label .. " callback failed", { traceback = trace })
    end)
    if not ok then
        API.events.emit("api.callback_error", { label = label, error = tostring(a), detail = a })
        return false, a
    end
    return true, a, b, c
end

local function parse_semver(value)
    if type(value) ~= "string" then return nil end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function compare_versions(left, right)
    local a, b = parse_semver(left), parse_semver(right)
    if not a or not b then return nil end
    for index = 1, 3 do
        if a[index] < b[index] then return -1 end
        if a[index] > b[index] then return 1 end
    end
    return 0
end

API.errors = { new = api_error }
API.versions = {
    compare = compare_versions,
    satisfies = function(actual, requirement)
        if requirement == nil or requirement == "" then return true end
        local operator, wanted = "=", requirement
        local prefixes = { ">=", "<=", ">", "<", "=", "~" }
        for _, prefix in ipairs(prefixes) do
            if requirement:sub(1, #prefix) == prefix then
                operator, wanted = prefix, requirement:sub(#prefix + 1):gsub("^%s+", "")
                break
            end
        end
        local cmp = compare_versions(actual, wanted)
        if cmp == nil then return false end
        if operator == ">=" then return cmp >= 0 end
        if operator == "<=" then return cmp <= 0 end
        if operator == ">" then return cmp > 0 end
        if operator == "<" then return cmp < 0 end
        if operator == "~" then
            local a, b = parse_semver(actual), parse_semver(wanted)
            return a and b and a[1] == b[1] and a[2] == b[2] and cmp >= 0
        end
        return cmp == 0
    end,
}

API.events = {}
function API.events.subscribe(event_name, callback, owner)
    if type(event_name) ~= "string" or event_name == "" or type(callback) ~= "function" then
        return nil, api_error("E_ARGUMENT", "event name and callback are required")
    end
    local token = { id = next_id("event"), event = event_name, owner = owner, active = true }
    API._subscriptions[event_name] = API._subscriptions[event_name] or {}
    API._subscriptions[event_name][token.id] = { token = token, callback = callback }
    function token:cancel()
        if not self.active then return true end
        self.active = false
        local bucket = API._subscriptions[self.event]
        if bucket then bucket[self.id] = nil end
        return true
    end
    return token
end

function API.events.emit(event_name, payload)
    local bucket = API._subscriptions[event_name]
    if not bucket then return end
    local snapshot = {}
    for _, item in pairs(bucket) do snapshot[#snapshot + 1] = item end
    for _, item in ipairs(snapshot) do
        if item.token.active then safe_call("event " .. event_name, item.callback, readonly_copy(payload)) end
    end
end

local function capability(name, available, detail)
    API.capabilities[name] = { available = not not available, detail = detail }
end

function API.hasCapability(name)
    if name == "muxlet.content" and API._adapter and API._adapter.muxletContentAvailable then
        API.capabilities[name] = API.capabilities[name] or {}
        API.capabilities[name].available = API._adapter.muxletContentAvailable() == true
        API.capabilities[name].detail = "UI content belongs in Mux.registerContent"
    end
    local item = API.capabilities[name]
    return item ~= nil and item.available == true
end

function API.getCapabilities()
    API.hasCapability("muxlet.content")
    return readonly_copy(API.capabilities)
end

function API.requireCapabilities(requirements)
    local missing = {}
    for _, name in ipairs(requirements or {}) do
        if not API.hasCapability(name) then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        return nil, api_error("E_CAPABILITY", "required F2CE API capabilities are unavailable", { missing = missing })
    end
    return true
end

function API.validateDependency(spec)
    spec = spec or {}
    if spec.api and not API.versions.satisfies(API.version, spec.api) then
        return nil, api_error("E_API_VERSION", "incompatible F2CE API version", { actual = API.version, required = spec.api })
    end
    if spec.f2ce and not API.versions.satisfies(API.f2ce_version, spec.f2ce) then
        return nil, api_error("E_F2CE_VERSION", "incompatible F2CE-Tools version", { actual = API.f2ce_version, required = spec.f2ce })
    end
    return API.requireCapabilities(spec.capabilities)
end

local Context = {}
Context.__index = Context

function Context:_live()
    local record = API._modules[self.module_id]
    return record and record.generation == self.generation and record.state == "enabled"
end

function Context:_guard(callback, label)
    return function(...)
        if not self:_live() then return nil end
        return safe_call(label or (self.module_id .. " callback"), callback, ...)
    end
end

function Context:own(kind, resource, cleanup)
    if self._cleaned then return nil, api_error("E_CONTEXT_CLOSED", "module context is closed") end
    local token = { id = next_id(kind or "resource"), kind = kind or "resource", resource = resource, active = true }
    function token:cancel()
        if not self.active then return true end
        self.active = false
        if cleanup then safe_call("cleanup " .. self.kind, cleanup, self.resource) end
        return true
    end
    self._resources[#self._resources + 1] = token
    return token
end

function Context:on(event_name, callback)
    local token, err = API.events.subscribe(event_name, self:_guard(callback, self.module_id .. " event " .. event_name), self.module_id)
    if not token then return nil, err end
    self._resources[#self._resources + 1] = token
    return token
end

function Context:cleanup(reason)
    if self._cleaned then return true end
    self._cleaned = true
    for index = #self._resources, 1, -1 do self._resources[index]:cancel(reason) end
    self._resources = {}
    return true
end

local function new_context(module_id, generation)
    return setmetatable({ module_id = module_id, generation = generation, _resources = {}, _cleaned = false }, Context)
end

API.modules = {}
local function module_record(id) return API._modules[id] end
local function valid_module_id(id) return type(id) == "string" and id:match("^[a-z][a-z0-9_.-]*$") ~= nil end

function API.modules.register(spec)
    if type(spec) ~= "table" or not valid_module_id(spec.id) then
        return nil, api_error("E_MODULE_ID", "module id must be a lowercase dotted identifier")
    end
    if API._modules[spec.id] then return nil, api_error("E_DUPLICATE_MODULE", "module id is already registered", { id = spec.id }) end
    local ok, err = API.validateDependency(spec.requires)
    if not ok then return nil, err end
    local record = { id = spec.id, spec = spec, state = "registered", generation = 1 }
    record.context = new_context(spec.id, record.generation)
    API._modules[spec.id] = record
    API.events.emit("module.state", { module_id = spec.id, previous = nil, state = "registered", reason = "register" })
    return record.context
end

local function transition(record, state, reason)
    local previous = record.state
    record.state = state
    API.events.emit("module.state", { module_id = record.id, previous = previous, state = state, reason = reason })
end

function API.modules.initialize(id)
    local record = module_record(id)
    if not record then return nil, api_error("E_MODULE_UNKNOWN", "module is not registered", { id = id }) end
    if record.state == "initialized" or record.state == "enabled" then return record.context end
    if record.state ~= "registered" then return nil, api_error("E_MODULE_STATE", "module cannot initialize from current state", { state = record.state }) end
    local ok, err = safe_call(id .. " initialize", record.spec.initialize, record.context)
    if not ok then
        record.context:cleanup("initialize_error")
        record.generation = record.generation + 1
        record.context = new_context(id, record.generation)
        return nil, err
    end
    transition(record, "initialized", "initialize")
    return record.context
end

function API.modules.enable(id)
    local record = module_record(id)
    if not record then return nil, api_error("E_MODULE_UNKNOWN", "module is not registered", { id = id }) end
    if record.state == "enabled" then return record.context end
    if record.state == "registered" then
        local _, err = API.modules.initialize(id)
        if err then return nil, err end
    end
    local previous = record.state
    record.state = "enabled" -- enable callback resources must be live immediately
    local ok, err = safe_call(id .. " enable", record.spec.enable, record.context)
    if not ok then
        record.context:cleanup("enable_error")
        record.generation = record.generation + 1
        record.context = new_context(id, record.generation)
        record.state = "registered"
        return nil, err
    end
    API.events.emit("module.state", { module_id = id, previous = previous, state = "enabled", reason = "enable" })
    return record.context
end

function API.modules.disable(id, reason)
    local record = module_record(id)
    if not record then return nil, api_error("E_MODULE_UNKNOWN", "module is not registered", { id = id }) end
    if record.state ~= "enabled" then return true end
    -- Revoke callback authority before cleanup; a disable callback can call
    -- back into its controller without recursively disabling the same record.
    record.state = "disabling"
    safe_call(id .. " disable", record.spec.disable, record.context, reason or "disabled")
    API.navigation._revokeModule(id, reason or "module_disabled")
    API.commands._revokeModule(id, reason or "module_disabled")
    API.prices._revokeModule(id, reason or "module_disabled")
    if API.hauling._owner == id then API.hauling.terminate() end
    record.context:cleanup(reason or "disabled")
    record.generation = record.generation + 1
    record.context = new_context(id, record.generation)
    transition(record, "registered", reason or "disable")
    return true
end

function API.modules.unload(id, reason)
    local record = module_record(id)
    if not record then return true end
    if record.state == "enabled" then API.modules.disable(id, reason or "unload") end
    safe_call(id .. " unload", record.spec.unload, record.context, reason or "unload")
    record.context:cleanup(reason or "unload")
    transition(record, "unloaded", reason or "unload")
    return true
end

function API.modules.unregister(id, reason)
    local record = module_record(id)
    if not record then return true end
    API.modules.unload(id, reason or "unregister")
    API._modules[id] = nil
    API.events.emit("module.state", { module_id = id, previous = "unloaded", state = "unregistered", reason = reason or "unregister" })
    return true
end

function API.modules.reload(spec)
    if type(spec) ~= "table" or not spec.id then return nil, api_error("E_ARGUMENT", "module spec with id is required") end
    local previous = module_record(spec.id)
    local was_enabled = previous and previous.state == "enabled"
    if previous then API.modules.unregister(spec.id, "reload") end
    local context, err = API.modules.register(spec)
    if not context then return nil, err end
    if was_enabled or spec.auto_enable then return API.modules.enable(spec.id) end
    return context
end

function API.modules.status(id)
    local record = module_record(id)
    if not record then return nil end
    return { id = id, state = record.state, version = record.spec.version, generation = record.generation }
end

local function require_live_context(context)
    if getmetatable(context) ~= Context then return nil, api_error("E_CONTEXT", "scoped module context is required") end
    if not context:_live() then return nil, api_error("E_MODULE_DISABLED", "module is not enabled", { module_id = context.module_id }) end
    return true
end

API.navigation = { _lease = nil, _request = nil }
local navigation = API.navigation

local function nav_status()
    local request = navigation._request
    return request and readonly_copy(request.public) or { state = "idle" }
end

function navigation.status() return nav_status() end
function navigation.environment()
    return readonly_copy(API._adapter and API._adapter.navState and API._adapter.navState() or {})
end

local function release_nav_lease(reason)
    local lease = navigation._lease
    if not lease then return end
    navigation._lease = nil
    lease.active = false
    if API._adapter and API._adapter.navReleaseOwner then
        safe_call("release navigation owner", API._adapter.navReleaseOwner, lease.native_owner)
    elseif API._adapter and API._adapter.navClearOwner then
        safe_call("clear navigation owner", API._adapter.navClearOwner)
    end
    API.events.emit("navigation.lease_released", { module_id = lease.module_id, lease_id = lease.id, reason = reason })
end

local function finish_navigation(state, reason, detail)
    local request = navigation._request
    if not request or request.finished then return end
    request.finished = true
    request.public.state = state
    request.public.reason = reason
    request.public.detail = readonly_copy(detail)
    request.public.finished_at = os.time()
    navigation._request = nil
    local callback = state == "completed" and request.on_complete or request.on_failure
    release_nav_lease(reason or state)
    API.events.emit(state == "completed" and "navigation.completed" or "navigation.failed", request.public)
    safe_call("navigation result", callback, readonly_copy(request.public))
end

local function interrupt_navigation(lease, reason)
    if navigation._lease ~= lease then return nil end
    local request = navigation._request
    if not request or request.finished then return nil end
    request.public.interruption_reason = reason or "interrupted"
    API.events.emit("navigation.interrupted", request.public)
    local ok, response = safe_call("navigation interruption", request.on_interrupt, readonly_copy(request.public))
    if ok and type(response) == "table" and response.auto_resume then return { auto_resume = true } end
    finish_navigation("failed", reason or "interrupted")
    return response
end

local function foreign_navigation()
    local lease = navigation._lease
    local state = navigation.environment()
    return state.owner ~= nil and (not lease or state.owner ~= lease.native_owner)
end

local Lease = {}
Lease.__index = Lease
function Lease:_valid()
    return self.active and navigation._lease == self and API._modules[self.module_id] and API._modules[self.module_id].state == "enabled"
end
function Lease:request(destination, options)
    if not self:_valid() then return nil, api_error("E_NAV_LEASE", "navigation lease is inactive") end
    if navigation._request then return nil, api_error("E_NAV_BUSY", "navigation request already active") end
    if not API._adapter or not API._adapter.navigate then return nil, api_error("E_CAPABILITY", "navigation adapter unavailable") end
    options = options or {}
    local handle = { id = next_id("nav-request"), lease_id = self.id, module_id = self.module_id, active = true }
    local request = {
        handle = handle,
        public = { request_id = handle.id, lease_id = self.id, module_id = self.module_id, destination = destination, state = "starting", started_at = os.time() },
        on_complete = options.on_complete,
        on_failure = options.on_failure,
        on_interrupt = options.on_interrupt,
        finished = false,
    }
    navigation._request = request
    function handle:status() return readonly_copy(request.public) end
    function handle:pause() return navigation.pause(self) end
    function handle:resume() return navigation.resume(self) end
    function handle:cancel(reason) return navigation.cancel(self, false, reason) end
    function handle:cancelImmediate(reason) return navigation.cancel(self, true, reason) end
    local function native_result(success, status)
        if request.finished then return end
        if status == nil then
            if success then request.public.native_status = "arrived"; navigation._tick()
            else finish_navigation("failed", "unmapped_or_unreachable") end
            return
        end
        request.public.native_status = status
        if status == "arrived" then
            navigation._tick()
        elseif status == "failed" then
            finish_navigation("failed", "unmapped_or_unreachable")
        elseif status == "walking" then
            request.public.state = "running"
        elseif status == "pending" then
            request.public.state = "pending"
        elseif success == false then
            finish_navigation("failed", tostring(status))
        end
    end
    local ok, result, err = pcall(API._adapter.navigate, destination, {
        suppress_hint = options.suppress_hint,
        interactive = options.interactive == true,
        compensate_incomplete_map = options.compensate_incomplete_map == true,
        on_result = native_result,
    })
    if not ok then
        finish_navigation("failed", "adapter_error", result)
        return nil, api_error("E_NAV_START", tostring(result))
    end
    if request.finished then
        if request.public.state == "completed" then return handle end
        return nil, api_error("E_NAV_START", "F2CE navigation rejected destination", { detail = request.public.detail })
    end
    if result == false or result == "failed" then
        finish_navigation("failed", "unmapped_or_unreachable", err)
        return nil, api_error("E_NAV_START", "F2CE navigation rejected destination", { detail = err })
    end
    if result ~= true and result ~= nil and result ~= "walking" and result ~= "arrived" and result ~= "pending" then
        finish_navigation("failed", "invalid_adapter_result", result)
        return nil, api_error("E_NAV_START", "navigation adapter returned an unknown status", { status = result })
    end
    request.public.native_status = type(result) == "string" and result or nil
    request.public.state = (result == "pending" or result == nil) and "pending" or "running"
    API.events.emit("navigation.started", request.public)
    navigation._tick()
    return handle
end
function Lease:release(reason)
    if navigation._request and navigation._request.handle.lease_id == self.id then
        return nil, api_error("E_NAV_BUSY", "cancel active request before releasing lease")
    end
    if navigation._lease == self then release_nav_lease(reason or "released") end
    return true
end

function navigation.acquire(context, options)
    local ok, err = require_live_context(context)
    if not ok then return nil, err end
    if navigation._lease then
        return nil, api_error("E_NAV_CONTENTION", "navigation lease is owned", {
            owner = navigation._lease.module_id,
        })
    end
    if API.commands._lease then
        return nil, api_error("E_COMMAND_CONTENTION", "command broker is leased; navigation cannot start", {
            owner = API.commands._lease.module_id,
        })
    end
    local lease = setmetatable({
        id = next_id("nav-lease"),
        module_id = context.module_id,
        active = true,
        metadata = readonly_copy(options),
    }, Lease)
    lease.native_owner = "api:" .. context.module_id .. ":" .. lease.id
    local function interrupted(reason) return interrupt_navigation(lease, reason) end
    local claimed, detail
    if API._adapter and API._adapter.navAcquireOwner then
        local call_ok
        call_ok, claimed, detail = pcall(API._adapter.navAcquireOwner, lease.native_owner, interrupted)
        if not call_ok then claimed, detail = false, claimed end
    elseif API._adapter and API._adapter.navSetOwner then
        local call_ok
        call_ok, claimed, detail = pcall(API._adapter.navSetOwner, lease.native_owner, interrupted)
        if not call_ok then claimed, detail = false, claimed end
    else
        return nil, api_error("E_CAPABILITY", "navigation ownership adapter unavailable")
    end
    if claimed ~= true then
        lease.active = false
        return nil, api_error("E_NAV_CONTENTION", "native navigation is already owned or active", { blocker = detail })
    end
    navigation._lease = lease
    API.events.emit("navigation.lease_acquired", {
        module_id = lease.module_id,
        lease_id = lease.id,
        metadata = lease.metadata,
    })
    return lease
end

function navigation.pause(handle)
    local request = navigation._request
    if not request or request.handle ~= handle then return nil, api_error("E_NAV_REQUEST", "request is not active") end
    if foreign_navigation() then return nil, api_error("E_NAV_OWNERSHIP", "foreign navigation owner") end
    if not API._adapter.navPause or not API._adapter.navPause() then return nil, api_error("E_NAV_STATE", "request could not be paused") end
    request.public.state = "paused"; API.events.emit("navigation.paused", request.public); return true
end
function navigation.resume(handle)
    local request = navigation._request
    if not request or request.handle ~= handle then return nil, api_error("E_NAV_REQUEST", "request is not active") end
    if foreign_navigation() then return nil, api_error("E_NAV_OWNERSHIP", "foreign navigation owner") end
    if not API._adapter.navResume or not API._adapter.navResume() then return nil, api_error("E_NAV_STATE", "request could not be resumed") end
    request.public.state = "running"; API.events.emit("navigation.resumed", request.public); return true
end
function navigation.cancel(handle, immediate, reason)
    local request = navigation._request
    if not request or request.handle ~= handle then return true end
    if foreign_navigation() then finish_navigation("cancelled", "foreign navigation owner"); return true end
    reason = reason or (immediate and "cancelled_immediate" or "cancelled_graceful")
    if immediate then
        if API._adapter.navStop then safe_call("immediate navigation cancel", API._adapter.navStop) end
        finish_navigation("cancelled", reason)
    else
        request.cancel_requested = reason
        request.public.state = "cancelling"
        if API._adapter.navPause then safe_call("graceful navigation pause", API._adapter.navPause) end
        API.events.emit("navigation.cancelling", request.public)
        if API._adapter.timer then API._adapter.timer(0, navigation._tick, false) end
    end
    return true
end

function navigation._tick()
    local request = navigation._request
    if not request then return end
    if foreign_navigation() then finish_navigation("failed", "foreign navigation owner"); return end
    if request.cancel_requested then
        if API._adapter and API._adapter.navStop then safe_call("graceful navigation cancel", API._adapter.navStop) end
        finish_navigation("cancelled", request.cancel_requested)
        return
    end
    local state = API._adapter and API._adapter.navState and API._adapter.navState() or nil
    if not state then return end
    request.public.progress = readonly_copy(state)
    -- Room GMCP can reach the target before the mapper processes the final
    -- step or an arrival/customs continuation finishes. Retain the lease until
    -- native movement is idle, for both polling and native on_result paths.
    if state.active or state.waiting or state.waiting_for_arrival
        or state.exploring or state.circuit_active or state.interruption_pending then
        request.public.state = state.paused and "paused"
            or (request.public.native_status == "pending" and "pending" or "running")
        return
    end
    if API._adapter and API._adapter.navDestinationReached then
        local ok, reached = pcall(API._adapter.navDestinationReached, request.public.destination)
        if ok and reached then finish_navigation("completed", "arrived", state); return end
    end
    if request.public.native_status == "arrived"
        or (request.public.native_status ~= "pending" and state.result == "completed") then
        finish_navigation("completed", "arrived", state)
    elseif request.public.native_status ~= "pending" and (state.result == "failed" or state.result == "stopped") then
        finish_navigation("failed", state.reason or state.result, state)
    end
end

function navigation._revokeModule(module_id, reason)
    if navigation._lease and navigation._lease.module_id == module_id then
        if navigation._request and not foreign_navigation() and API._adapter and API._adapter.navStop then safe_call("navigation revoke", API._adapter.navStop) end
        if navigation._request then finish_navigation("cancelled", reason or "module_disabled") else release_nav_lease(reason or "module_disabled") end
    end
end

API.commands = { _lease = nil, _audit = {}, _limit = 500 }
local commands = API.commands
local CommandLease = {}; CommandLease.__index = CommandLease

function commands._nativeBlocker(owned_hauling_price)
    if not API._adapter or not API._adapter.nativeCommandBlocker then return nil end
    local ok, blocker = pcall(API._adapter.nativeCommandBlocker, owned_hauling_price == true)
    if ok then return blocker end
    return { kind = "adapter_error", detail = tostring(blocker) }
end

function CommandLease:_valid()
    return self.active and commands._lease == self and API._modules[self.module_id] and API._modules[self.module_id].state == "enabled"
end
function CommandLease:send(command, metadata)
    metadata = metadata or {}
    local entry = {
        id = next_id("command"),
        module_id = self.module_id,
        lease_id = self.id,
        command = tostring(command or ""),
        metadata = readonly_copy(metadata),
        timestamp = os.time(),
    }
    if not self:_valid() then
        entry.status = "denied"; entry.reason = "inactive_or_disabled"; commands._record(entry)
        return nil, api_error("E_COMMAND_LEASE", "active command lease is required")
    end
    if entry.command == "" or type(metadata.reason) ~= "string" or metadata.reason == "" then
        entry.status = "denied"; entry.reason = "missing_command_or_reason"; commands._record(entry)
        return nil, api_error("E_COMMAND_METADATA", "command and metadata.reason are required")
    end
    local blocker = commands._nativeBlocker(self._hauling_price == true)
    if blocker then
        entry.status = "denied"
        entry.reason = "native_automation_active"
        entry.blocker = readonly_copy(blocker)
        commands._record(entry)
        return nil, api_error("E_COMMAND_CONTENTION", "native automation became active; command denied", {
            blocker = blocker,
        })
    end
    if not API._adapter or not API._adapter.sendCommand then return nil, api_error("E_CAPABILITY", "command transport unavailable") end
    local ok, result = pcall(API._adapter.sendCommand, entry.command, { echo = metadata.echo == true })
    entry.status = ok and result ~= false and "sent" or "failed"
    entry.reason = ok and nil or tostring(result)
    commands._record(entry)
    API.events.emit(entry.status == "sent" and "command.sent" or "command.failed", entry)
    -- Legacy event name retained for compatibility. This is a transport
    -- receipt, NOT confirmation that the game accepted the command.
    API.events.emit("command.acknowledged", entry)
    if entry.status ~= "sent" then return nil, api_error("E_COMMAND_SEND", "command transport failed", entry) end
    return readonly_copy(entry)
end
function CommandLease:release(reason)
    if commands._lease == self then commands._lease = nil end
    self.active = false
    API.events.emit("command.lease_released", { module_id = self.module_id, lease_id = self.id, reason = reason or "released" })
    return true
end

function commands._record(entry)
    commands._audit[#commands._audit + 1] = readonly_copy(entry)
    if #commands._audit > commands._limit then table.remove(commands._audit, 1) end
end
function commands.audit() return readonly_copy(commands._audit) end
function commands.acquire(context, metadata)
    local ok, err = require_live_context(context); if not ok then return nil, err end
    if commands._lease then
        return nil, api_error("E_COMMAND_CONTENTION", "command broker is leased", {
            owner = commands._lease.module_id,
        })
    end
    if API.navigation._lease then
        return nil, api_error("E_NAV_CONTENTION", "navigation is leased; arbitrary commands are denied", {
            owner = API.navigation._lease.module_id,
        })
    end
    local blocker = commands._nativeBlocker()
    if blocker then
        return nil, api_error("E_COMMAND_CONTENTION", "native automation is active", { blocker = blocker })
    end
    local lease = setmetatable({
        id = next_id("command-lease"),
        module_id = context.module_id,
        active = true,
        metadata = readonly_copy(metadata),
    }, CommandLease)
    commands._lease = lease
    API.events.emit("command.lease_acquired", { module_id = lease.module_id, lease_id = lease.id, metadata = lease.metadata })
    return lease
end
function commands._revokeModule(module_id, reason)
    if commands._lease and commands._lease.module_id == module_id then commands._lease:release(reason or "module_disabled") end
end

API.data = { _cache = {}, _receipts = {}, _sequence = 0 }
API.character = {}
function API.character.hasRank(rank)
    return API._adapter and API._adapter.rankAtLeast and API._adapter.rankAtLeast(rank) == true or false
end
local data = API.data
local DATA_CHANNELS = {
    room = { path = {"room", "info"}, event = "data.room" },
    vitals = { path = {"char", "vitals"}, event = "data.vitals" },
    cash = { path = {"char", "vitals", "cash"}, event = "data.cash" },
    stamina = { path = {"char", "vitals", "stamina"}, event = "data.stamina" },
    ship = { path = {"char", "ship"}, event = "data.ship" },
    cargo = { path = {"char", "ship", "cargo"}, event = "data.cargo" },
    jobs_board = { path = {"jobs", "board"}, event = "data.jobs_board" },
    job = { path = {"char", "job"}, event = "data.job" },
    commodities = { path = {"exchange", "commodities"}, event = "data.commodities" },
    futures_market = { path = {"exchange", "futures"}, event = "data.futures_market" },
    futures_owned = { path = {"char", "futures"}, event = "data.futures_owned" },
    company = { path = {"char", "company"}, event = "data.company" },
    business = { path = {"char", "business"}, event = "data.business" },
}
function data.get(channel)
    if not DATA_CHANNELS[channel] then return nil, api_error("E_DATA_CHANNEL", "unknown data channel", { channel = channel }) end
    return readonly_copy(data._cache[channel])
end
function data.mapRoomId(room)
    return API._adapter and API._adapter.mapRoomIdentity and API._adapter.mapRoomIdentity(room) or nil
end
function data.receipt(channel)
    local result = readonly_copy(data._receipts[channel])
    if result and not result.room_id then result.room_id = data.mapRoomId(result.room) end
    return result
end
function data.refresh(channel, received)
    local definition = DATA_CHANNELS[channel]
    if not definition then return nil, api_error("E_DATA_CHANNEL", "unknown data channel", { channel = channel }) end
    local snapshot = API._adapter and API._adapter.gmcpSnapshot and API._adapter.gmcpSnapshot(definition.path) or nil
    data._cache[channel] = readonly_copy(snapshot)
    local payload = { channel = channel, available = snapshot ~= nil, value = readonly_copy(snapshot), timestamp = os.time() }
    -- Cache reads/refreshes are not proof of a new server response. Freeze
    -- room identity only on a real GMCP event, before any consumer callback.
    if received == true then
        local room = API._adapter.gmcpSnapshot(DATA_CHANNELS.room.path)
        data._sequence = data._sequence + 1
        local previous = data._receipts[channel]
        data._receipts[channel] = { generation = previous and previous.generation + 1 or 1,
            sequence = data._sequence, received_at = payload.timestamp, data = readonly_copy(snapshot),
            room = readonly_copy(room), room_id = data.mapRoomId(room) }
        payload.receipt = data.receipt(channel)
    end
    payload.received = received == true
    API.events.emit(definition.event, payload)
    return readonly_copy(snapshot)
end
function data.channels() local result = {}; for name in pairs(DATA_CHANNELS) do result[#result + 1] = name end; table.sort(result); return result end

API.prices = { _providers = {}, _queue = {}, _active = nil }
local prices = API.prices
local function sorted_providers(request)
    local result = {}
    for _, provider in pairs(prices._providers) do
        local scope_ok = not provider.scopes or provider.scopes[request.options.scope or "default"] or provider.scopes["*"]
        if provider.active and scope_ok and (not request.options.provider or request.options.provider == provider.id) then result[#result + 1] = provider end
    end
    table.sort(result, function(a, b) if a.priority == b.priority then return a.id < b.id end; return a.priority > b.priority end)
    result[#result + 1] = { id = "f2ce.builtin", priority = -math.huge, builtin = true, active = true }
    return result
end
local function price_finish(request, result, err)
    if request.finished then return end
    request.finished = true; request.public.state = err and "failed" or "completed"; request.public.result = readonly_copy(result); request.public.error = err and tostring(err) or nil
    if request.timer then request.timer:cancel() end
    if request.command_lease then
        request.command_lease._hauling_price = nil
        if not request.borrowed then request.command_lease:release("price_request_complete") end
    end
    prices._active = nil
    API.events.emit(err and "provider.failed" or "provider.completed", request.public)
    safe_call("price request completion", request.callback, readonly_copy(result), err)
    prices._pump()
end
local function try_provider(request)
    request.index = request.index + 1
    if request.index > 1 and request.options.fallback == false then
        return price_finish(request, nil, api_error("E_PROVIDER", "selected price provider failed; fallback disabled"))
    end
    request.attempt_generation = (request.attempt_generation or 0) + 1
    local attempt_generation = request.attempt_generation
    local provider = request.providers[request.index]
    if not provider then return price_finish(request, nil, api_error("E_PROVIDER", "all price providers failed", { attempts = request.attempts })) end
    request.public.provider = provider.id
    request.attempts[#request.attempts + 1] = provider.id
    API.events.emit("provider.started", request.public)
    local timeout = tonumber(request.options.timeout) or 15
    local context_record = API._modules[request.module_id]
    if API._adapter and API._adapter.timer then
        local id = API._adapter.timer(timeout, function()
            if request.finished or prices._active ~= request then return end
            API.events.emit("provider.timed_out", request.public); try_provider(request)
        end, false)
        request.timer = { cancel = function() if id and API._adapter.cancelTimer then API._adapter.cancelTimer(id); id = nil end end }
    end
    local function done(result, err)
        if request.finished or prices._active ~= request or request.attempt_generation ~= attempt_generation then return end
        if request.timer then request.timer:cancel(); request.timer = nil end
        if err or result == nil then try_provider(request) else price_finish(request, result, nil) end
    end
    local function builtin_check(callback)
        if not API._adapter or not API._adapter.priceCheck then return callback(nil, "built-in provider unavailable") end
        local blocker = commands._nativeBlocker(request.borrowed)
        if blocker then
            return callback(nil, api_error(
                "E_COMMAND_CONTENTION",
                "native automation became active; built-in price command denied",
                { blocker = blocker }
            ))
        end
        commands._record({
            id = next_id("command"), module_id = request.module_id, lease_id = request.command_lease.id,
            command = API._adapter.priceCommandDescription and API._adapter.priceCommandDescription(request.commodity) or "f2t_price_check_commodity",
            metadata = { reason = "built-in F2CE price provider", service = "prices", provider = provider.id },
            timestamp = os.time(), status = "delegated",
        })
        local ok, accepted = pcall(API._adapter.priceCheck, request.commodity, request.options, callback)
        if not ok or accepted == false then callback(nil, ok and "built-in provider declined" or accepted) end
    end
    if provider.builtin then
        builtin_check(done)
        return
    end
    local delegated, provider_sent, delivered = false, false, false
    local function current_attempt()
        return not request.finished and prices._active == request and request.attempt_generation == attempt_generation
    end
    local provider_request = {
        id = request.public.request_id, commodity = request.commodity, options = readonly_copy(request.options),
        send = function(_, command, metadata)
            if request.finished or prices._active ~= request or request.attempt_generation ~= attempt_generation then
                return nil, api_error("E_PROVIDER_STALE", "provider attempt is no longer active")
            end
            if delegated then return nil, api_error("E_PROVIDER_STATE", "built-in delegation already owns this attempt") end
            metadata = metadata or {}; metadata.reason = metadata.reason or ("price provider " .. provider.id)
            provider_sent = true
            return request.command_lease:send(command, metadata)
        end,
        -- Transform built-in results without queuing behind our own request or
        -- surrendering its command lease. Exactly one query per attempt.
        useBuiltin = function(_, callback)
            if not current_attempt() then return nil, api_error("E_PROVIDER_STALE", "provider attempt is no longer active") end
            if delegated or provider_sent then return nil, api_error("E_PROVIDER_STATE", "price attempt already dispatched") end
            if type(callback) ~= "function" then return nil, api_error("E_ARGUMENT", "built-in completion callback required") end
            delegated = true
            builtin_check(function(value, err)
                if delivered or not current_attempt() then return end
                delivered = true
                local ok = safe_call("delegated built-in completion", callback, readonly_copy(value), err)
                if not ok then done(nil, "built-in result callback failed") end
            end)
            return true
        end,
        isCancelled = function() return request.cancelled end,
    }
    local ok, accepted = safe_call("price provider " .. provider.id, provider.request, provider_request, done)
    if not ok or accepted == false then done(nil, "provider declined") end
end
function prices._pump()
    if prices._active or #prices._queue == 0 then return end
    local request = table.remove(prices._queue, 1); prices._active = request
    local record = API._modules[request.module_id]
    if not record or record.state ~= "enabled" then return price_finish(request, nil, api_error("E_MODULE_DISABLED", "requesting module is disabled")) end
    local lease, err
    if request.options._nativeHauling == true and API.hauling._owner == request.module_id then
        lease = API.hauling._command_lease
        if not lease or not lease:_valid() then return price_finish(request, nil, api_error("E_COMMAND_LEASE", "hauling price lease is unavailable")) end
        request.borrowed = true
        lease._hauling_price = true
    else
        lease, err = commands.acquire(record.context, { service = "prices", request_id = request.public.request_id })
    end
    if not lease then return price_finish(request, nil, err) end
    request.command_lease = lease; request.providers = sorted_providers(request); request.index = 0; try_provider(request)
end
function prices.registerProvider(context, spec)
    local ok, err = require_live_context(context); if not ok then return nil, err end
    if type(spec) ~= "table" or not valid_module_id(spec.id) or type(spec.request) ~= "function" then return nil, api_error("E_PROVIDER_SPEC", "provider id and request function are required") end
    if prices._providers[spec.id] then return nil, api_error("E_DUPLICATE_PROVIDER", "provider id is already registered") end
    local scopes = nil; if spec.scopes then scopes = {}; for _, scope in ipairs(spec.scopes) do scopes[scope] = true end end
    local provider = { id = spec.id, module_id = context.module_id, priority = tonumber(spec.priority) or 0, scopes = scopes, capabilities = readonly_copy(spec.capabilities), request = spec.request, active = true }
    prices._providers[spec.id] = provider
    local token; token = context:own("price_provider", spec.id, function(id)
        local item = prices._providers[id]; if item then item.active = false; prices._providers[id] = nil end
    end)
    API.events.emit("provider.registered", { id = spec.id, module_id = context.module_id, priority = provider.priority, scopes = spec.scopes, capabilities = spec.capabilities })
    return token
end
function prices.request(context, commodity, options, callback)
    local ok, err = require_live_context(context); if not ok then return nil, err end
    if type(commodity) ~= "string" or commodity == "" then return nil, api_error("E_ARGUMENT", "commodity is required") end
    local handle = { id = next_id("price-request"), module_id = context.module_id, active = true }
    local request = { module_id = context.module_id, commodity = commodity, options = options or {}, callback = callback, attempts = {}, public = { request_id = handle.id, module_id = context.module_id, commodity = commodity, state = "queued", queued_at = os.time() }, finished = false }
    function handle:status() return readonly_copy(request.public) end
    function handle:cancel(reason)
        if request.finished then return true end
        request.cancelled = true; request.public.state = "cancelled"; request.public.reason = reason or "cancelled"
        if prices._active == request then price_finish(request, nil, api_error("E_CANCELLED", request.public.reason)) else
            for i, queued in ipairs(prices._queue) do if queued == request then table.remove(prices._queue, i); break end end
            request.finished = true; safe_call("price cancellation", callback, nil, api_error("E_CANCELLED", request.public.reason))
        end
        return true
    end
    prices._queue[#prices._queue + 1] = request; API.events.emit("provider.queued", request.public); prices._pump(); return handle
end
function prices._revokeModule(module_id, reason)
    local ids = {}; for id, provider in pairs(prices._providers) do if provider.module_id == module_id then ids[#ids + 1] = id end end
    for _, id in ipairs(ids) do prices._providers[id] = nil end
    if prices._active and prices._active.module_id == module_id then prices._active.public.reason = reason; price_finish(prices._active, nil, api_error("E_CANCELLED", reason)) end
    for i = #prices._queue, 1, -1 do if prices._queue[i].module_id == module_id then local item = table.remove(prices._queue, i); item.finished = true; safe_call("price cancellation", item.callback, nil, api_error("E_CANCELLED", reason)) end end
end

API.hauling = { _owner = nil, _command_lease = nil }
local hauling = API.hauling
function hauling.status()
    return API._adapter and API._adapter.haulingStatus and readonly_copy(API._adapter.haulingStatus()) or { active = false, available = false }
end
function hauling.start(context, options)
    local ok, err = require_live_context(context); if not ok then return nil, err end
    options = options or {}; local mode = options.mode or "auto"
    if mode ~= "auto" and mode ~= "exchange" then
        return nil, api_error("E_HAUL_MODE", "only rank-aware auto and exchange override are stable API modes")
    end
    if options.rotation ~= nil and (options.rotation ~= "top_base_21" or mode ~= "exchange") then
        return nil, api_error("E_HAUL_ROTATION", "top_base_21 is an exchange-only rotation")
    end
    if options.rotation and not API.hasCapability("hauling.rotation_top_base21") then
        return nil, api_error("E_CAPABILITY", "top-base-price rotation is unavailable")
    end
    if hauling._owner then
        return nil, api_error("E_HAUL_BUSY", "hauling is already API-owned", { owner = hauling._owner })
    end
    local current = hauling.status()
    if current.active then return nil, api_error("E_HAUL_BUSY", "native hauling is already active") end
    if navigation._lease then return nil, api_error("E_NAV_CONTENTION", "navigation is leased by another module") end
    local command_lease
    command_lease, err = commands.acquire(context, { service = "hauling" })
    if not command_lease then return nil, err end
    if not API._adapter or not API._adapter.haulingStart then
        command_lease:release("unavailable")
        return nil, api_error("E_CAPABILITY", "hauling adapter unavailable")
    end
    hauling._owner, hauling._command_lease = context.module_id, command_lease
    local call_ok, accepted, detail = pcall(API._adapter.haulingStart, mode == "exchange" and "exchange" or nil, options.rotation)
    if not call_ok or accepted ~= true then
        hauling._owner = nil; command_lease:release("start_rejected"); hauling._command_lease = nil
        return nil, api_error("E_HAUL_START", call_ok and (detail or "hauling start rejected") or tostring(accepted))
    end
    API.events.emit("hauling.started", { module_id = context.module_id, mode = mode, status = hauling.status() })
    return {
        status = hauling.status,
        pause = hauling.pause,
        resume = hauling.resume,
        cancel = hauling.stop,
        cancelImmediate = hauling.terminate,
    }
end
function hauling.pause(immediate) if not hauling._owner then return nil, api_error("E_HAUL_STATE", "hauling is not API-owned") end; return API._adapter.haulingPause(immediate == true) end
function hauling.resume() if not hauling._owner then return nil, api_error("E_HAUL_STATE", "hauling is not API-owned") end; return API._adapter.haulingResume() end
function hauling.stop() if not hauling._owner then return true end; return API._adapter.haulingStop() end
function hauling.terminate() if not hauling._owner then return true end; local result = API._adapter.haulingTerminate(); hauling._release("terminated"); return result end
function hauling._release(reason)
    local owner = hauling._owner; hauling._owner = nil
    if hauling._command_lease then hauling._command_lease:release(reason or "hauling_stopped"); hauling._command_lease = nil end
    if owner then API.events.emit("hauling.stopped", { module_id = owner, reason = reason, status = hauling.status() }) end
end
function hauling._refresh()
    local status = hauling.status(); API.events.emit("hauling.state", status)
    if hauling._owner and status.active == false then hauling._release("completed") end
end

API.map = {}
local map = API.map
local function map_call(name, ...)
    if not API._adapter or type(API._adapter[name]) ~= "function" then return nil, api_error("E_CAPABILITY", "map operation unavailable", { operation = name }) end
    local ok, a, b = pcall(API._adapter[name], ...); if not ok then return nil, api_error("E_MAP", tostring(a), { operation = name }) end
    return readonly_copy(a), readonly_copy(b)
end
function map.roomHasFlag(room_id, flag) return map_call("mapRoomHasFlag", room_id, flag) end
function map.findRoomsWithFlag(area, flag) return map_call("mapFindRoomsWithFlag", area, flag) end
function map.findExchange(area) return map_call("mapFindExchange", area) end
function map.resolve(location) return map_call("mapResolve", location) end
function map.areas() return map_call("mapAreas") end
function map.systems() return map_call("mapSystems") end
function map.reachability(from_room, to_room) return map_call("mapReachability", from_room, to_room) end

API.schemas = {
    ["module.state"] = { required = {"module_id", "state", "reason"} },
    ["navigation.*"] = { required = {"module_id", "lease_id"}, request = {"request_id", "destination", "state", "reason", "interruption_reason"} },
    ["hauling.*"] = { fields = {"active", "paused", "mode", "current_phase", "stopping", "cycle_count"} },
    ["provider.*"] = { required = {"request_id", "module_id", "commodity", "state"} },
    ["command.acknowledged"] = { required = {"id", "module_id", "lease_id", "command", "metadata", "status", "timestamp"} },
    ["data.*"] = { required = {"channel", "available", "value", "timestamp"} },
    ["reconnect.reset"] = { required = {"reason", "timestamp"} },
}

function API._install(adapter)
    if type(adapter) ~= "table" then return nil, api_error("E_ADAPTER", "adapter table is required") end
    API._adapter = adapter
    API.f2ce_version = tostring(adapter.f2ceVersion and adapter.f2ceVersion() or "unknown")
    local v33 = compare_versions(API.f2ce_version, "3.3.0")
    local navigation_available = type(adapter.navigate) == "function"
        and (type(adapter.navAcquireOwner) == "function" or type(adapter.navSetOwner) == "function")
    capability("modules", true, "v1 scoped lifecycle")
    capability("events", true, "normalized copied payloads")
    capability("navigation", navigation_available, adapter.name)
    capability("navigation.status.v33", v33 ~= nil and v33 >= 0, "explicit walking/arrived/pending/failed statuses")
    capability("commands", type(adapter.sendCommand) == "function", adapter.name)
    capability("commands.native_contention", type(adapter.nativeCommandBlocker) == "function", adapter.name)
    capability("gmcp.snapshots", type(adapter.gmcpSnapshot) == "function", adapter.name)
    capability("prices.providers", type(adapter.priceCheck) == "function", adapter.name)
    capability("prices.provider_builtin", type(adapter.priceCheck) == "function", adapter.name)
    capability("hauling", type(adapter.haulingStart) == "function", adapter.name)
    capability("hauling.exchange_override", type(adapter.haulingStart) == "function", adapter.name)
    capability("hauling.rotation_top_base21", adapter.haulingTopBase21 == true, "session-local top 21 fixed base prices")
    capability("hauling.customs_max5", adapter.haulingCustomsMax5 == true,
        "persistent cartel scan excludes systems above five percent customs")
    capability("map.queries", type(adapter.mapResolve) == "function", adapter.name)
    capability("exchange.capture", type(adapter.exchangeCapture) == "function"
        and type(adapter.exchangeCancel) == "function", "serialized native PO capture")
    capability("exchange.settings", API.exchange ~= nil, "typed stockpile/spread commands")
    capability("company.read", API.company ~= nil and type(adapter.observeLine) == "function"
        and type(adapter.unobserveLine) == "function" and type(adapter.parseFactory) == "function",
        "owner-bound company GMCP and bounded factory displays")
    capability("company.system.read", API.company ~= nil and type(API.company.system)=="function"
        and type(adapter.observeLine)=="function" and type(adapter.unobserveLine)=="function",
        "system workforce/economy snapshot with ordered company read fence")
    capability("company.factory.build", API.company ~= nil and type(API.company.prepareFactory)=="function",
        "explicit current-exchange single-factory preview/confirm")
    capability("company.factory.site", API.company ~= nil and API.company.factorySiteVersion==1,
        "bounded factory plus missing depot, or owned-factory depot backfill; explicit preview/confirm")
    capability("company.depot.read", API.company ~= nil and type(API.company.depot) == "function"
        and type(adapter.observeLine) == "function" and type(adapter.unobserveLine) == "function"
        and type(adapter.parseDepot) == "function", "owner-bound depot display with ordered read fence")
    capability("company.depot.transfer", API.company ~= nil and type(API.company.prepareTransfer)=="function",
        "single-bay preview/confirm with ship, depot and cash reconciliation")
    capability("company.cargo.transfer", API.company ~= nil and type(API.company.prepareCargo)=="function",
        "single-bay market preview/confirm with fresh GMCP and exact cargo/cash reconciliation")
    capability("muxlet.content", adapter.muxletContentAvailable and adapter.muxletContentAvailable() or false,
        "UI content belongs in Mux.registerContent")
    if adapter.registerEvent then
        local bindings = {
            ["gmcp.room.info"] = { "room", navigation._tick }, ["gmcp.char.vitals"] = { "vitals" },
            ["gmcp.char.ship"] = { "ship", "cargo" }, ["gmcp.jobs.board"] = { "jobs_board" }, ["gmcp.char.job"] = { "job" },
            ["gmcp.exchange.commodities"] = { "commodities" }, ["gmcp.exchange.futures"] = { "futures_market" }, ["gmcp.char.futures"] = { "futures_owned" },
            ["gmcp.char.company"] = { "company" },
            ["gmcp.char.business"] = { "business" },
            ["gmcp.char.vitals.cash"] = { "cash", "vitals" },
            ["gmcp.char.vitals.stamina"] = { "stamina", "vitals" },
        }
        API._adapter_tokens = API._adapter_tokens or {}
        for event_name, channels in pairs(bindings) do
            local id = adapter.registerEvent(event_name, function()
                for _, channel in ipairs(channels) do if type(channel) == "string" then data.refresh(channel, true) else channel() end end
            end)
            API._adapter_tokens[#API._adapter_tokens + 1] = { id = id, cancel = adapter.unregisterEvent }
        end
        local haul_id = adapter.registerEvent("f2tHaulingStatusChanged", hauling._refresh)
        API._adapter_tokens[#API._adapter_tokens + 1] = { id = haul_id, cancel = adapter.unregisterEvent }
        local disconnect_id = adapter.registerEvent("sysDisconnectionEvent", function() API._reconnectReset("disconnect") end)
        API._adapter_tokens[#API._adapter_tokens + 1] = { id = disconnect_id, cancel = adapter.unregisterEvent }
    end
    for channel in pairs(DATA_CHANNELS) do data.refresh(channel) end
    if API.services then API.services.install() end
    API.events.emit("api.ready", API.info())
    return API
end

function API.info()
    return {
        api_version = API.version,
        api_build = API._build,
        f2ce_version = API.f2ce_version,
        adapter = API._adapter and API._adapter.name or nil,
        capabilities = API.getCapabilities(),
        integration = readonly_copy(API.integration),
    }
end

function API._reconnectReset(reason)
    -- Reconnect never carries automation authority into another connection.
    local enabled = {}
    for id, record in pairs(API._modules) do
        if record.state == "enabled" then enabled[#enabled + 1] = id end
    end
    for _, id in ipairs(enabled) do API.modules.disable(id, reason or "reconnect_reset") end
    if navigation._request and API._adapter and API._adapter.navStop then safe_call("reconnect navigation stop", API._adapter.navStop) end
    if navigation._request then finish_navigation("cancelled", "reconnect_reset") elseif navigation._lease then release_nav_lease("reconnect_reset") end
    if commands._lease then commands._lease:release("reconnect_reset") end
    local queued = prices._queue
    prices._queue = {}
    if prices._active then price_finish(prices._active, nil, api_error("E_RECONNECT", "request cancelled by reconnect")) end
    for _, request in ipairs(queued) do
        request.finished = true
        request.public.state = "failed"
        request.public.reason = "reconnect_reset"
        safe_call("price reconnect cancellation", request.callback, nil, api_error("E_RECONNECT", "request cancelled by reconnect"))
    end
    hauling._release("reconnect_reset")
    data._cache, data._receipts, data._sequence = {}, {}, 0
    API.events.emit("reconnect.reset", { reason = reason or "reconnect", timestamp = os.time() })
end

function API:_reload()
    local ids = {}; for id in pairs(self._modules) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do self.modules.unregister(id, "api_reload") end
    if self._adapter_tokens then
        for _, token in ipairs(self._adapter_tokens) do if token.id and token.cancel then safe_call("adapter handler cleanup", token.cancel, token.id) end end
    end
    self._adapter_tokens = {}
    self._subscriptions = {}
    self.navigation._lease, self.navigation._request = nil, nil
    self.commands._lease = nil
    self.prices._providers, self.prices._queue, self.prices._active = {}, {}, nil
    self.hauling._owner, self.hauling._command_lease = nil, nil
end

capability("modules", true, "core loaded; adapter not installed")
capability("events", true, "core loaded; adapter not installed")
