-- Verify premium-hauling cartel customs discovery, thresholding and persistence.
local root = tostring(arg and arg[1] or ".")
local passed, failed = 0, 0
local function equal(actual, expected, label)
    if actual ~= expected then error((label or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual), 2) end
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed=passed+1; print("PASS " .. name)
    else failed=failed+1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

local sent, triggers, timers, deleted, stored, encoded_payload = {}, {}, {}, 0, {}, nil
local serial = 0
function cecho() end
function send(command) sent[#sent+1] = command end
function tempRegexTrigger(_, callback)
    serial=serial+1; triggers[serial]=callback; return serial
end
function killTrigger(id) triggers[id]=nil end
function tempTimer(seconds, callback)
    if seconds == 0 then callback(); return 0 end
    serial=serial+1; timers[serial]=callback; return serial
end
function killTimer(id) timers[id]=nil end
function deleteLine() deleted=deleted+1 end
function getMapUserData(key) return stored[key] end
function setMapUserData(key, value) stored[key]=value; return true end
yajl={
    to_string=function(value) encoded_payload=value; return "encoded-policy" end,
    to_value=function(value)
        if value ~= "encoded-policy" then error("unexpected stored value") end
        return encoded_payload
    end,
}
F2T_MAP_TOPOLOGY={cartels={Borderline="Prime", Clear="Prime", Tariff="Other"}}
F2T_MAP_TOPOLOGY_LOADED=true
function f2t_map_topology_ensure_loaded() end

local function active_trigger()
    for _, callback in pairs(triggers) do return callback end
    error("no active capture trigger")
end
local function feed(value)
    line=value
    active_trigger()()
end
local function response(cartel, duty, systems)
    feed(cartel .. " cartel, Prime syndicate")
    feed("   Owner: Tester")
    if duty and duty > 0 then feed("   Customs dues: " .. duty .. "%") end
    feed("   Member systems:")
    for _, system in ipairs(systems) do feed("      " .. system .. " - Founder Owner") end
    feed("   Cartel is open - systems may join without approval")
end

dofile(root .. "/src/scripts/hauling/customs_policy.lua")

test("scanner excludes every system in cartels above five percent", function()
    local callback_ok, callback_result
    local started, why=f2t_hauling_customs_scan_start(function(ok, result)
        callback_ok, callback_result=ok, result
    end)
    equal(started,true,why); equal(sent[1],"di cartel Borderline")
    response("Borderline",5,{"Edge"})
    equal(sent[2],"di cartel Clear")
    response("Clear",0,{"Open"})
    equal(sent[3],"di cartel Tariff")
    -- Exact live wording from `di cartel <cartelname>`.
    response("Tariff",10,{"Tariff","Toll"})
    equal(callback_ok,true)
    equal(callback_result.blocked_cartels,1)
    equal(callback_result.blocked_systems,2)
    equal(f2t_hauling_customs_system_blocked("Tariff"),true)
    equal(f2t_hauling_customs_system_blocked("toll"),true)
    equal(f2t_hauling_customs_system_blocked("Edge"),false,"five percent remains eligible")
    equal(f2t_hauling_customs_system_blocked("Open"),false)
    equal(stored.f2t_hauling_customs_policy_v1,"encoded-policy")
    equal(deleted > 0,true,"captured display suppressed")
end)

test("saved customs exclusions load before a reconnect rescan", function()
    dofile(root .. "/src/scripts/hauling/customs_policy.lua")
    equal(f2t_hauling_customs_system_blocked("TOLL"),true)
    equal(f2t_hauling_customs_system_blocked("Edge"),false)
    local status=f2t_hauling_customs_policy_status()
    equal(status.blocked_cartels,1); equal(status.blocked_systems,2)
    equal(status.scanned_session,false)
end)

print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed > 0 then os.exit(1) end
