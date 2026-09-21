-- Premium-hauling cartel customs scanner and persistent route policy.
-- `di cartel <name>` is the authoritative source for both the current duty and
-- that cartel's member systems. A 5% duty remains eligible; anything above it
-- excludes every member system from supplier and buyer selection.

if type(f2t_hauling_customs_scan_cancel) == "function" then
    pcall(f2t_hauling_customs_scan_cancel, "package reload", false)
end

local STORAGE_KEY = "f2t_hauling_customs_policy_v1"
local POLICY_VERSION = 1
local DEFAULT_MAX_DUTY = 5
local DETAIL_TIMEOUT = 8

F2T_HAULING_CUSTOMS_POLICY = {
    version = POLICY_VERSION,
    max_duty = DEFAULT_MAX_DUTY,
    scanned_at = nil,
    cartels = {},
    blocked_systems = {},
    loaded = false,
    scanned_session = false,
}
F2T_HAULING_CUSTOMS_SCAN = nil

local function normalized(value)
    return tostring(value or ""):match("^%s*(.-)%s*$"):lower()
end

local function valid_name(value)
    return type(value) == "string" and #value >= 1 and #value <= 64
        and value:match("^[%w][%w%s'&%.%-]*$") ~= nil
end

local function clean_systems(values)
    local result, seen = {}, {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        local name = tostring(value or ""):match("^%s*(.-)%s*$")
        local key = normalized(name)
        if valid_name(name) and key ~= "" and not seen[key] then
            seen[key] = true
            result[#result + 1] = name
        end
    end
    table.sort(result, function(a, b) return normalized(a) < normalized(b) end)
    return result
end

local function rebuild_blocked(cartels, max_duty)
    max_duty = tonumber(max_duty) or DEFAULT_MAX_DUTY
    local blocked = {}
    for cartel, record in pairs(type(cartels) == "table" and cartels or {}) do
        local duty = type(record) == "table" and tonumber(record.duty)
        if valid_name(cartel) and duty and duty >= 0 and duty <= 100 and duty > max_duty then
            -- The cartel hub is itself a system even if an unusual response
            -- omits it from the member list.
            blocked[normalized(cartel)] = cartel
            for _, system in ipairs(clean_systems(record.systems)) do
                blocked[normalized(system)] = system
            end
        end
    end
    return blocked
end

local function load_policy()
    local policy = F2T_HAULING_CUSTOMS_POLICY
    if policy.loaded then return true end
    policy.loaded = true
    if type(getMapUserData) ~= "function" or type(yajl) ~= "table"
        or type(yajl.to_value) ~= "function" then return true end
    local raw = getMapUserData(STORAGE_KEY)
    if type(raw) ~= "string" or raw == "" then return true end
    local ok, decoded = pcall(yajl.to_value, raw)
    if not ok or type(decoded) ~= "table" or decoded.version ~= POLICY_VERSION
        or type(decoded.cartels) ~= "table" then return true end
    local cartels = {}
    for name, record in pairs(decoded.cartels) do
        local duty = type(record) == "table" and tonumber(record.duty)
        local systems = type(record) == "table" and clean_systems(record.systems)
        if valid_name(name) and duty and duty >= 0 and duty <= 100 and #systems > 0 then
            cartels[name] = { duty = duty, systems = systems }
        end
    end
    policy.scanned_at = tonumber(decoded.scanned_at)
    policy.cartels = cartels
    policy.blocked_systems = rebuild_blocked(cartels, policy.max_duty)
    return true
end

local function save_policy()
    if type(setMapUserData) ~= "function" or type(yajl) ~= "table"
        or type(yajl.to_string) ~= "function" then return false, "map storage is unavailable" end
    local policy = F2T_HAULING_CUSTOMS_POLICY
    local ok, encoded = pcall(yajl.to_string, {
        version = POLICY_VERSION,
        max_duty = policy.max_duty,
        scanned_at = policy.scanned_at,
        cartels = policy.cartels,
    })
    if not ok or type(encoded) ~= "string" or encoded == "" then return false, "customs policy encoding failed" end
    local saved, result = pcall(setMapUserData, STORAGE_KEY, encoded)
    if not saved or result == false then return false, "customs policy save failed" end
    return true
end

function f2t_hauling_customs_system_blocked(system)
    load_policy()
    local key = normalized(system)
    return key ~= "" and F2T_HAULING_CUSTOMS_POLICY.blocked_systems[key] ~= nil
end

function f2t_hauling_customs_policy_status()
    load_policy()
    local policy, blocked_cartels = F2T_HAULING_CUSTOMS_POLICY, 0
    for _, record in pairs(policy.cartels) do
        if tonumber(record.duty) and tonumber(record.duty) > policy.max_duty then blocked_cartels = blocked_cartels + 1 end
    end
    local blocked_systems = 0
    for _ in pairs(policy.blocked_systems) do blocked_systems = blocked_systems + 1 end
    return {
        max_duty = policy.max_duty,
        scanned_at = policy.scanned_at,
        blocked_cartels = blocked_cartels,
        blocked_systems = blocked_systems,
        scanned_session = policy.scanned_session == true,
    }
end

local function cleanup_scan(scan)
    if scan.timer and type(killTimer) == "function" then pcall(killTimer, scan.timer) end
    if scan.trigger and type(killTrigger) == "function" then pcall(killTrigger, scan.trigger) end
    scan.timer, scan.trigger = nil, nil
    if F2T_HAULING_CUSTOMS_SCAN == scan then F2T_HAULING_CUSTOMS_SCAN = nil end
end

function f2t_hauling_customs_scan_cancel(reason, notify)
    local scan = F2T_HAULING_CUSTOMS_SCAN
    if not scan then return false end
    cleanup_scan(scan)
    if notify ~= false and type(scan.done) == "function" then scan.done(false, reason or "cancelled") end
    return true
end

local function topology_cartels()
    if type(f2t_map_topology_ensure_loaded) == "function" then f2t_map_topology_ensure_loaded() end
    local result = {}
    for cartel in pairs(type(F2T_MAP_TOPOLOGY) == "table" and F2T_MAP_TOPOLOGY.cartels or {}) do
        if valid_name(cartel) then result[#result + 1] = cartel end
    end
    table.sort(result, function(a, b) return normalized(a) < normalized(b) end)
    return result
end

function f2t_hauling_customs_scan_start(done, max_duty)
    load_policy()
    max_duty = tonumber(max_duty) or DEFAULT_MAX_DUTY
    if max_duty ~= math.floor(max_duty) or max_duty < 0 or max_duty > 100 then
        return false, "customs threshold must be an integer from 0 through 100"
    end
    local policy = F2T_HAULING_CUSTOMS_POLICY
    policy.max_duty = max_duty
    policy.blocked_systems = rebuild_blocked(policy.cartels, max_duty)
    if F2T_HAULING_CUSTOMS_SCAN then return false, "cartel customs scan is already active" end
    if type(done) ~= "function" or type(send) ~= "function" or type(tempRegexTrigger) ~= "function"
        or type(tempTimer) ~= "function" then return false, "customs scan capabilities are unavailable" end
    if policy.scanned_session then
        tempTimer(0, function() done(true, f2t_hauling_customs_policy_status()) end)
        return true
    end
    local cartels = topology_cartels()
    if #cartels == 0 then return false, "map topology contains no cartels; run 'map topology sync' first" end

    local scan = { active = true, cartels = cartels, index = 0, records = {}, done = done }
    F2T_HAULING_CUSTOMS_SCAN = scan
    local finish, request_next
    finish = function(ok, detail)
        if not scan.active then return end
        scan.active = false
        cleanup_scan(scan)
        if ok then
            local policy = F2T_HAULING_CUSTOMS_POLICY
            policy.cartels = scan.records
            policy.blocked_systems = rebuild_blocked(scan.records, policy.max_duty)
            policy.scanned_at = os.time()
            policy.scanned_session = true
            local saved, why = save_policy()
            if not saved then return done(false, why) end
            return done(true, f2t_hauling_customs_policy_status())
        end
        done(false, detail or "cartel customs scan failed")
    end
    local function reset_timeout()
        if scan.timer then pcall(killTimer, scan.timer) end
        scan.timer = tempTimer(DETAIL_TIMEOUT, function()
            finish(false, "timed out reading cartel " .. tostring(scan.current))
        end)
    end
    local function complete_current()
        if not scan.started or #scan.systems == 0 then
            finish(false, "incomplete cartel response for " .. tostring(scan.current))
            return
        end
        scan.records[scan.current] = { duty = scan.duty or 0, systems = clean_systems(scan.systems) }
        scan.started, scan.in_members = false, false
        if scan.timer then pcall(killTimer, scan.timer); scan.timer = nil end
        tempTimer(0, request_next)
    end
    scan.trigger = tempRegexTrigger("^.*$", function()
        if not scan.active then return end
        local value = tostring(line or ""):gsub("\r$", "")
        if not scan.started then
            local header = value:match("^%s*(.-)%s+cartel,") or value:match("^%s*(.-)%s+cartel%s*$")
            if normalized(header) ~= normalized(scan.current) then return end
            scan.started, scan.duty, scan.systems = true, 0, {}
        end
        if type(deleteLine) == "function" then pcall(deleteLine) end
        local duty = value:match("^%s*Customs dues:%s*(%d+)%%")
        if duty then scan.duty = tonumber(duty) end
        if value:match("^%s*Member systems:%s*$") then
            scan.in_members = true
        elseif scan.in_members then
            local member = value:match("^%s%s%s%s%s%s(.+)$")
            if member then
                member = member:gsub("%s+%-%s+.*$", ""):match("^%s*(.-)%s*$")
                if valid_name(member) then scan.systems[#scan.systems + 1] = member end
            end
        end
        if value:match("^%s*Cartel is open") or value:match("^%s*Cartel queues membership requests")
            or value:match("^%s*Cartel is not currently accepting additional members") then complete_current() end
    end)
    if not scan.trigger then cleanup_scan(scan); return false, "customs scan trigger could not be created" end
    request_next = function()
        if not scan.active then return end
        scan.index = scan.index + 1
        if scan.index > #scan.cartels then return finish(true) end
        scan.current = scan.cartels[scan.index]
        scan.started, scan.in_members, scan.duty, scan.systems = false, false, 0, {}
        reset_timeout()
        send("di cartel " .. scan.current, false)
    end
    cecho(string.format("\n<cyan>[hauling]<reset> Scanning %d cartels; customs above %d%% will be excluded...\n",
        #cartels, max_duty))
    request_next()
    return true
end
