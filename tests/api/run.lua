local api_source = arg and arg[1] or "src/scripts/api/v1.lua"
local Mock = dofile("tests/api/mock_adapter.lua")
dofile(api_source)

local API = assert(F2CE and F2CE.API and F2CE.API.v1, "API did not load")
local passed, failed = 0, 0

local function equal(actual, expected, message)
    if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function truthy(value, message) if not value then error(message or "expected truthy value", 2) end end
local function code(err, expected) equal(type(err) == "table" and err.code or nil, expected, "error code") end

local mock
local function reset()
    API:_reload()
    mock = Mock.new()
    API._install({
        name = mock.name,
        f2ceVersion = function() return mock:f2ceVersion() end,
        registerEvent = function(...) return mock:registerEvent(...) end,
        unregisterEvent = function(...) return mock:unregisterEvent(...) end,
        timer = function(...) return mock:timer(...) end,
        cancelTimer = function(...) return mock:cancelTimer(...) end,
        muxletContentAvailable = function(...) return mock:muxletContentAvailable(...) end,
        sendCommand = function(...) return mock:sendCommand(...) end,
        gmcpSnapshot = function(...) return mock:gmcpSnapshot(...) end,
        nativeCommandBlocker = function(...) return mock:nativeCommandBlocker(...) end,
        navAcquireOwner = function(...) return mock:navAcquireOwner(...) end,
        navReleaseOwner = function(...) return mock:navReleaseOwner(...) end,
        navSetOwner = function(...) return mock:navSetOwner(...) end,
        navClearOwner = function(...) return mock:navClearOwner(...) end,
        navigate = function(...) return mock:navigate(...) end,
        navPause = function(...) return mock:navPause(...) end,
        navResume = function(...) return mock:navResume(...) end,
        navStop = function(...) return mock:navStop(...) end,
        navState = function(...) return mock:navState(...) end,
        navDestinationReached = function(...) return mock:navDestinationReached(...) end,
        priceCheck = function(...) return mock:priceCheck(...) end,
        priceCommandDescription = function(...) return mock:priceCommandDescription(...) end,
        haulingStatus = function(...) return mock:haulingStatus(...) end,
        haulingStart = function(...) return mock:haulingStart(...) end,
        haulingTopBase21 = true,
        haulingSessionPolicy = true,
        haulingPause = function(...) return mock:haulingPause(...) end,
        haulingResume = function(...) return mock:haulingResume(...) end,
        haulingStop = function(...) return mock:haulingStop(...) end,
        haulingTerminate = function(...) return mock:haulingTerminate(...) end,
        mapRoomHasFlag = function(...) return mock:mapRoomHasFlag(...) end,
        mapFindRoomsWithFlag = function(...) return mock:mapFindRoomsWithFlag(...) end,
        mapFindExchange = function(...) return mock:mapFindExchange(...) end,
        mapResolve = function(...) return mock:mapResolve(...) end,
        mapAreas = function(...) return mock:mapAreas(...) end,
        mapSystems = function(...) return mock:mapSystems(...) end,
        mapReachability = function(...) return mock:mapReachability(...) end,
    })
end

local function enabled(id, extra)
    local spec = extra or {}; spec.id = id; spec.version = spec.version or "1.0.0"
    assert(API.modules.register(spec)); return assert(API.modules.enable(id))
end

local tests = {}
function tests.version_and_capability_failure()
    reset()
    equal(API.integration.ui.provider, "Muxlet")
    truthy(not API.hasCapability("muxlet.content"))
    truthy(API.hasCapability("navigation.status.v33"))
    truthy(API.hasCapability("commands.native_contention"))
    truthy(API.versions.satisfies("1.2.3", ">=1.0.0")); truthy(not API.versions.satisfies("1.2.3", ">=2.0.0"))
    local ok, err = API.validateDependency({ api = ">=2.0.0" }); equal(ok, nil); code(err, "E_API_VERSION")
    API.capabilities["test.missing"] = { available = false }
    ok, err = API.requireCapabilities({ "test.missing" }); equal(ok, nil); code(err, "E_CAPABILITY")
end

function tests.navigation_interruption_policy()
    reset(); local context = enabled("test.nav.interrupt")
    local lease = assert(API.navigation.acquire(context))
    local handle = assert(lease:request("market", {
        on_interrupt = function(event)
            equal(event.interruption_reason, "customs")
            return { auto_resume = true }
        end,
    }))
    local response = mock.nav.interrupt("customs")
    truthy(response and response.auto_resume); equal(handle:status().state, "running")
    handle:cancelImmediate("test_cleanup")

    lease = assert(API.navigation.acquire(context))
    handle = assert(lease:request("market"))
    mock.nav.interrupt("combat")
    equal(handle:status().state, "failed"); equal(handle:status().reason, "combat")
end

function tests.duplicate_module_ids()
    reset(); assert(API.modules.register({ id = "test.duplicate" }))
    local context, err = API.modules.register({ id = "test.duplicate" }); equal(context, nil); code(err, "E_DUPLICATE_MODULE")
end

function tests.reload_idempotence()
    reset(); local cleanups = 0
    local spec = { id = "test.reload", auto_enable = true, initialize = function(context) context:own("custom", true, function() cleanups = cleanups + 1 end) end }
    assert(API.modules.reload(spec)); assert(API.modules.reload(spec)); equal(cleanups, 1)
    equal(API.modules.status("test.reload").state, "enabled")
end

function tests.scoped_cleanup()
    reset(); local context = enabled("test.resources"); local cleanups = 0
    assert(context:own("host_resource", "resource-id", function() cleanups = cleanups + 1 end))
    assert(context:on("test.event", function() end)); API.modules.disable("test.resources")
    equal(cleanups, 1)
end

function tests.navigation_contention_and_callbacks()
    reset(); local a, b = enabled("test.nav.a"), enabled("test.nav.b")
    local lease = assert(API.navigation.acquire(a)); local other, err = API.navigation.acquire(b); equal(other, nil); code(err, "E_NAV_CONTENTION")
    local completed = false; local handle = assert(lease:request("market", { on_complete = function() completed = true end }))
    mock:completeNavigation(true); API.navigation._tick(); truthy(completed); equal(handle:status().state, "completed")
end

function tests.arrival_waits_for_native_teardown()
    for _, field in ipairs({"active", "waiting", "waiting_for_arrival", "interruption_pending", "exploring", "circuit_active"}) do
        reset(); local context = enabled("test.nav.settle")
        local completed = 0
        local lease = assert(API.navigation.acquire(context))
        local handle = assert(lease:request("market", {on_complete=function() completed=completed+1 end}))
        mock.nav.current, mock.nav.active = "market", false
        mock.nav[field] = true
        API.navigation._tick()
        equal(completed, 0, field .. " must settle before arrival")
        equal(lease.active, true, "keep ownership while native work is pending")
        local denied = API.commands.acquire(context); equal(denied, nil)
        mock.nav[field], mock.nav.result = false, "completed"
        API.navigation._tick()
        equal(completed, 1); equal(handle:status().state, "completed")
        local commands = assert(API.commands.acquire(context)); commands:release()
    end
end

function tests.native_arrived_callback_does_not_bypass_teardown()
    reset(); local context = enabled("test.nav.callback-settle")
    local completed = 0
    local lease = assert(API.navigation.acquire(context))
    local handle = assert(lease:request("market", {on_complete=function() completed=completed+1 end}))
    mock:resolveNavigation("arrived")
    equal(completed, 0, "arrived status is not permission to ignore an active speedwalk")
    mock.nav.active = false; API.navigation._tick()
    equal(completed, 1); equal(handle:status().state, "completed")
end

function tests.navigation_completion_event_observes_released_lease()
    reset(); local context = enabled("test.nav.event-release")
    local acquired
    API.events.subscribe("navigation.completed", function()
        acquired = API.commands.acquire(context)
    end)
    local lease = assert(API.navigation.acquire(context))
    assert(lease:request("market"))
    mock:completeNavigation(true); API.navigation._tick()
    truthy(acquired, "completed subscribers may acquire commands after native teardown")
    acquired:release()
end

function tests.navigation_v33_status_contract()
    reset(); local context = enabled("test.nav.status")
    local lease = assert(API.navigation.acquire(context)); local handle = assert(lease:request("here"))
    equal(handle:status().state, "completed")

    lease = assert(API.navigation.acquire(context)); local rejected, err = lease:request("bad")
    equal(rejected, nil); code(err, "E_NAV_START")

    lease = assert(API.navigation.acquire(context)); handle = assert(lease:request("pending"))
    equal(handle:status().state, "pending")
    mock.nav.result = "completed"
    API.navigation._tick()
    equal(handle:status().state, "pending", "intermediate completion must not settle a pending route")
    mock:resolveNavigation("walking")
    equal(handle:status().state, "running")
    mock:completeNavigation(true); API.navigation._tick()
    equal(handle:status().state, "completed")
end

function tests.navigation_native_owner_is_not_overwritten_or_cleared()
    reset(); local context = enabled("test.nav.native-owner")
    mock.nav.owner = "hauling"
    local lease, err = API.navigation.acquire(context)
    equal(lease, nil); code(err, "E_NAV_CONTENTION"); equal(mock.nav.owner, "hauling")

    mock.nav.owner = nil
    lease = assert(API.navigation.acquire(context))
    mock.nav.owner = "stamina"
    assert(lease:release("ownership_changed"))
    equal(mock.nav.owner, "stamina", "release must not clear a replacement owner")
end

function tests.navigation_graceful_and_immediate_cancel()
    reset(); local context = enabled("test.nav.cancel")
    local lease = assert(API.navigation.acquire(context)); local request = assert(lease:request("market"))
    assert(request:cancel("test_graceful")); equal(request:status().state, "cancelling"); mock:runTimers()
    equal(request:status().state, "cancelled"); equal(mock.nav_stop_count, 1)
    lease = assert(API.navigation.acquire(context)); request = assert(lease:request("market"))
    assert(request:cancelImmediate("test_immediate")); equal(request:status().state, "cancelled"); equal(mock.nav_stop_count, 2)
end

function tests.command_denial_and_zero_transmission()
    reset(); local context = enabled("test.command")
    local lease = assert(API.commands.acquire(context, { purpose = "test" }))
    local ack = assert(lease:send("look", { reason = "offline test" })); equal(ack.status, "sent"); equal(#mock.sent, 1)
    API.modules.disable("test.command"); local result, err = lease:send("buy fuel", { reason = "must be denied" })
    equal(result, nil); code(err, "E_COMMAND_LEASE"); equal(#mock.sent, 1)
    local disabled_context = API._modules["test.command"].context
    local denied; denied, err = API.commands.acquire(disabled_context); equal(denied, nil); code(err, "E_MODULE_DISABLED"); equal(#mock.sent, 1)
end

function tests.native_command_contention_is_fail_closed()
    reset(); local context = enabled("test.command.native")
    mock.native_blocker = { kind = "hauling" }
    local lease, err = API.commands.acquire(context)
    equal(lease, nil); code(err, "E_COMMAND_CONTENTION"); equal(#mock.sent, 0)

    mock.native_blocker = nil
    lease = assert(API.commands.acquire(context))
    mock.native_blocker = { kind = "map_exploration" }
    local ack; ack, err = lease:send("buy fuel", { reason = "must remain blocked" })
    equal(ack, nil); code(err, "E_COMMAND_CONTENTION"); equal(#mock.sent, 0)
end

function tests.builtin_provider_rechecks_native_contention()
    reset(); local context = enabled("test.provider.native-blocker")
    assert(API.prices.registerProvider(context, {
        id = "test.provider.activates-native", priority = 100,
        request = function()
            mock.native_blocker = { kind = "hauling" }
            return false
        end,
    }))
    local observed_error
    assert(API.prices.request(context, "water", {}, function(_, err) observed_error = err end))
    truthy(observed_error); code(observed_error, "E_PROVIDER"); equal(#mock.sent, 0)
end

function tests.provider_registration_and_fallback()
    reset(); local context = enabled("test.provider")
    assert(API.prices.registerProvider(context, { id = "test.provider.primary", priority = 100, scopes = { "cartel" }, request = function(request, done) return false end }))
    local result; assert(API.prices.request(context, "petroleum", { scope = "cartel" }, function(value, err) assert(not err); result = value end))
    truthy(result); equal(result.provider, "f2ce.builtin"); equal(mock.builtin_price_calls, 1); equal(#mock.sent, 1)
    truthy(#API.commands.audit() >= 1)
end

function tests.provider_timeout_ignores_late_callback()
    reset(); local context = enabled("test.provider.timeout"); local late_done
    assert(API.prices.registerProvider(context, { id = "test.provider.slow", priority = 200, request = function(request, done) late_done = done; return true end }))
    local result; assert(API.prices.request(context, "water", { timeout = 1 }, function(value) result = value end))
    mock:runTimers(); equal(result.provider, "f2ce.builtin")
    late_done({ commodity = "water", provider = "late" }); equal(result.provider, "f2ce.builtin")
end

function tests.provider_builtin_delegates_once_without_a_nested_queue()
    reset(); local context = enabled("test.provider.filter"); local saved, completed
    assert(API.prices.registerProvider(context, { id="test.filter", request=function(request, done)
        saved = request
        assert(request:useBuiltin(function(value, err)
            truthy(value); equal(err,nil); value.filtered=true; done(value)
        end))
        return true
    end }))
    assert(API.prices.request(context,"water",{fallback=false},function(value) completed=value end))
    truthy(completed.filtered); equal(mock.builtin_price_calls,1); equal(#mock.sent,1)
    equal(#API.prices._queue,0); equal(API.commands._lease,nil)
    local ok, err = saved:useBuiltin(function() error("stale callback") end)
    equal(ok,nil); code(err,"E_PROVIDER_STALE")
end

function tests.provider_builtin_blocks_duplicate_or_mixed_dispatch()
    reset(); local context = enabled("test.provider.duplicate"); local delivered, saved
    API._adapter.priceCheck=function(_,_,callback) delivered=callback; return true end
    assert(API.prices.registerProvider(context,{id="test.filter",request=function(request,done)
        saved=request
        assert(request:useBuiltin(function(value) done(value) end))
        local ok,err=request:useBuiltin(function() end); equal(ok,nil); code(err,"E_PROVIDER_STATE")
        ok,err=request:send("check premium water all"); equal(ok,nil); code(err,"E_PROVIDER_STATE")
        return true
    end}))
    local count=0
    assert(API.prices.request(context,"water",{fallback=false},function() count=count+1 end))
    delivered({commodity="water"}); delivered({commodity="water"})
    equal(count,1); equal(#mock.sent,0); equal(API.commands._lease,nil)
    reset(); context=enabled("test.provider.mixed")
    assert(API.prices.registerProvider(context,{id="test.filter",request=function(request,done)
        assert(request:send("check premium water all"))
        local ok,err=request:useBuiltin(function() end); equal(ok,nil); code(err,"E_PROVIDER_STATE")
        done({commodity="water"}); return true
    end}))
    assert(API.prices.request(context,"water",{fallback=false},function() end))
    equal(mock.builtin_price_calls,0); equal(#mock.sent,1)
end

function tests.provider_builtin_rechecks_contention()
    reset(); local context=enabled("test.provider.blocked"); local observed
    assert(API.prices.registerProvider(context,{id="test.filter",request=function(request,done)
        mock.native_blocker={kind="map_exploration"}
        assert(request:useBuiltin(function(value,err) observed=err; done(value,err) end))
        return true
    end}))
    assert(API.prices.request(context,"water",{fallback=false},function(value,err) equal(value,nil); truthy(err) end))
    code(observed,"E_COMMAND_CONTENTION"); equal(#mock.sent,0); equal(mock.builtin_price_calls,0)
end

function tests.provider_builtin_late_results_after_cancel_or_timeout_are_ignored()
    for _,cancel in ipairs({true,false}) do
        reset(); local context=enabled("test.provider.late"); local late, called= nil,0
        API._adapter.priceCheck=function(_,_,callback) late=callback; return true end
        assert(API.prices.registerProvider(context,{id="test.filter",request=function(request,done)
            assert(request:useBuiltin(function(value) called=called+1; done(value) end)); return true
        end}))
        local finished=0
        local handle=assert(API.prices.request(context,"water",{fallback=false,timeout=1},function() finished=finished+1 end))
        if cancel then handle:cancel("test") else mock:runTimers() end
        late({commodity="water"}); equal(called,0); equal(finished,1); equal(API.commands._lease,nil)
    end
end

function tests.callback_errors_are_contained()
    reset(); local observed = false
    API.events.subscribe("api.callback_error", function() observed = true end)
    API.events.subscribe("test.explode", function() error("boom") end)
    API.events.emit("test.explode", {}); truthy(observed, "callback error event not emitted")
end

function tests.nil_and_partial_gmcp_are_copied()
    reset(); equal(API.data.refresh("futures_market"), nil)
    mock.gmcp = { room = { info = { id = 7, flags = { "exchange" } } }, char = {} }
    local room = API.data.refresh("room"); equal(room.id, 7); room.id = 999
    equal(API.data.get("room").id, 7); equal(API.data.refresh("cargo"), nil)
end

function tests.reconnect_reset()
    reset(); local context = enabled("test.reconnect"); local lease = assert(API.navigation.acquire(context)); assert(lease:request("market"))
    mock:fireEvent("sysDisconnectionEvent"); equal(API.navigation.status().state, "idle"); equal(mock.nav_stop_count, 1)
end

function tests.unload_during_active_work()
    reset(); local context = enabled("test.unload"); local lease = assert(API.navigation.acquire(context)); assert(lease:request("market"))
    API.modules.unregister("test.unload"); equal(API.modules.status("test.unload"), nil); equal(API.navigation.status().state, "idle"); equal(mock.nav_stop_count, 1)
end

function tests.hauling_modes_and_release()
    reset(); local context = enabled("test.haul")
    local handle, err = API.hauling.start(context, { mode = "po" }); equal(handle, nil); code(err, "E_HAUL_MODE")
    handle = assert(API.hauling.start(context, { mode = "exchange" })); equal(mock.haul.mode, "exchange")
    mock.haul.active = false; API.hauling._refresh(); equal(API.commands._lease, nil)
end
function tests.hauling_session_policy_is_validated_and_copied()
    reset(); local context=enabled("hauling-policy",{capabilities={"hauling"}})
    local handle,err=API.hauling.start(context,{mode="exchange",rotation="top_base_21",
        customs_max_percent=4,excluded_commodities={"Woods","Firewalls"}})
    truthy(handle,tostring(err)); equal(mock.haul.policy.customs_max_percent,4)
    equal(mock.haul.policy.excluded_commodities[2],"Firewalls")
    API.hauling.terminate(); mock.haul.active=false
    handle,err=API.hauling.start(context,{mode="exchange",customs_max_percent=101})
    equal(handle,nil); code(err,"E_HAUL_POLICY")
end


function tests.hauling_rejection_releases_command_lease()
    reset(); local context = enabled("test.haul.reject")
    mock.haul.reject = true
    local handle, err = API.hauling.start(context)
    equal(handle, nil); code(err, "E_HAUL_START"); equal(API.commands._lease, nil); equal(API.hauling._owner, nil)
end

local names = {}; for name in pairs(tests) do names[#names + 1] = name end; table.sort(names)
for _, name in ipairs(names) do
    local ok, err = xpcall(tests[name], function(value) return debug.traceback(tostring(value), 2) end)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n") else failed = failed + 1; io.write("FAIL ", name, "\n", err, "\n") end
end
io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
