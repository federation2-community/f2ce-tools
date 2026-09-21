local Mock = {}
Mock.__index = Mock

function Mock.new()
    local self = setmetatable({}, Mock)
    self.name = "offline-mock"
    self.events, self.timers = {}, {}
    self.cancelled = { events = 0, timers = 0 }
    self.sent, self.next_id = {}, 0
    self.gmcp = {}
    self.nav = { active = false, paused = false, result = nil, owner = nil }
    self.native_blocker = nil
    self.nav_stop_count = 0
    self.haul = { active = false, paused = false }
    self.builtin_price_calls = 0
    return self
end

function Mock:_id(prefix)
    self.next_id = self.next_id + 1
    return prefix .. ":" .. self.next_id
end

function Mock:f2ceVersion() return "3.3.0" end
function Mock:registerEvent(name, callback)
    local id = self:_id("event")
    self.events[id] = { name = name, callback = callback }
    return id
end
function Mock:unregisterEvent(id)
    if self.events[id] then self.events[id] = nil; self.cancelled.events = self.cancelled.events + 1 end
end
function Mock:fireEvent(name, ...)
    local list = {}
    for _, item in pairs(self.events) do if item.name == name then list[#list + 1] = item.callback end end
    for _, callback in ipairs(list) do callback(name, ...) end
end

function Mock:timer(delay, callback, repeating)
    local id = self:_id("timer")
    self.timers[id] = { delay = delay, callback = callback, repeating = repeating }
    return id
end
function Mock:cancelTimer(id)
    if self.timers[id] then self.timers[id] = nil; self.cancelled.timers = self.cancelled.timers + 1 end
end
function Mock:runTimers()
    local list = {}
    for id, item in pairs(self.timers) do list[#list + 1] = { id = id, item = item } end
    for _, entry in ipairs(list) do
        if self.timers[entry.id] then
            if not entry.item.repeating then self.timers[entry.id] = nil end
            entry.item.callback()
        end
    end
end

function Mock:muxletContentAvailable() return false end

function Mock:sendCommand(command, options)
    self.sent[#self.sent + 1] = { command = command, options = options }
    return true
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[clone(key)] = clone(item) end
    return result
end

function Mock:gmcpSnapshot(path)
    local node = self.gmcp
    for _, key in ipairs(path or {}) do if type(node) ~= "table" then return nil end; node = node[key] end
    return clone(node)
end

function Mock:nativeCommandBlocker()
    if self.native_blocker then return clone(self.native_blocker) end
    if self.nav.owner then return { kind = "navigation_owner", owner = self.nav.owner } end
    if self.nav.active then return { kind = "speedwalk" } end
    if self.haul.active then return { kind = "hauling" } end
    return nil
end
function Mock:navAcquireOwner(owner, callback)
    local blocker = self:nativeCommandBlocker()
    if blocker then return false, blocker end
    self.nav.owner, self.nav.interrupt = owner, callback
    return true
end
function Mock:navReleaseOwner(owner)
    if self.nav.owner == nil then return true end
    if self.nav.owner ~= owner then return false, { kind = "ownership_changed", owner = self.nav.owner } end
    self.nav.owner, self.nav.interrupt = nil, nil
    return true
end
function Mock:navSetOwner(owner, callback) return self:navAcquireOwner(owner, callback) end
function Mock:navClearOwner() self.nav.owner, self.nav.interrupt = nil, nil; return true end
function Mock:navigate(destination, options)
    self.nav.destination, self.nav.options = destination, options
    if destination == "bad" then return "failed", "unreachable" end
    if destination == "here" then self.nav.active, self.nav.result, self.nav.current = false, "completed", destination; return "arrived" end
    if destination == "pending" then self.nav.active, self.nav.result = false, nil; return "pending" end
    self.nav.active, self.nav.paused, self.nav.result = true, false, nil
    return "walking"
end
function Mock:navPause() if not self.nav.active then return false end; self.nav.paused = true; return true end
function Mock:navResume() if not self.nav.active then return false end; self.nav.paused = false; return true end
function Mock:navStop() self.nav_stop_count = self.nav_stop_count + 1; self.nav.active, self.nav.paused, self.nav.result = false, false, "stopped"; return true end
function Mock:navState() return clone(self.nav) end
function Mock:navDestinationReached(destination) return self.nav.current == destination end
function Mock:completeNavigation(success)
    self.nav.active, self.nav.result = false, success and "completed" or "failed"
    if success then self.nav.current = self.nav.destination end
    self.nav.owner = nil
end
function Mock:resolveNavigation(status)
    if status == "walking" then self.nav.active, self.nav.result = true, nil end
    if status == "arrived" then self.nav.current = self.nav.destination end
    if self.nav.options and self.nav.options.on_result then
        self.nav.options.on_result(status == "walking" or status == "arrived", status)
    end
end

function Mock:priceCheck(commodity, options, done)
    self.builtin_price_calls = self.builtin_price_calls + 1
    self:sendCommand("check price " .. commodity .. " cartel", { service = "price" })
    done({ commodity = commodity, buy = { price = 10 }, sell = { price = 12 }, provider = "f2ce.builtin" })
    return true
end
function Mock:priceCommandDescription(commodity) return "check price " .. commodity .. " cartel" end

function Mock:haulingStatus() return clone(self.haul) end
function Mock:haulingStart(mode, rotation, policy)
    if self.haul.reject then return false, "native hauling start was rejected" end
    self.haul.active, self.haul.mode = true, mode or "auto"
    self.haul.rotation,self.haul.policy=rotation,policy
    return true
end
function Mock:haulingPause() self.haul.paused = true; return true end
function Mock:haulingResume() self.haul.paused = false; return true end
function Mock:haulingStop() self.haul.active = false; return true end
function Mock:haulingTerminate() self.haul.active = false; return true end

function Mock:mapRoomHasFlag(room, flag) return room == 1 and flag == "exchange" end
function Mock:mapFindRoomsWithFlag(area, flag) return flag == "exchange" and { 1, 2 } or {} end
function Mock:mapFindExchange(area) return { { room_id = 1, name = "Mock Exchange", area_id = area } } end
function Mock:mapResolve(location) return { room_id = location == "exchange" and 1 or nil } end
function Mock:mapAreas() return { { id = 10, name = "Mock" } } end
function Mock:mapSystems() return { { name = "Sol" } } end
function Mock:mapReachability(from_room, to_room) return { reachable = from_room ~= to_room, rooms = { to_room }, directions = { "n" } } end

return Mock
