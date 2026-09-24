-- Opt-in empty seller legs only. Runs inside the native hauling command owner;
-- FedHauler never sends competing inv/status/tp commands through another lease.
if type(f2t_hauling_teleport_cancel) == "function" then f2t_hauling_teleport_cancel() end
local pending, inventory, uncertain
local function norm(value) return tostring(value or ""):lower() end
local function room() return gmcp and gmcp.room and gmcp.room.info or {} end
local function flag(info, wanted)
    if type(info.flags) ~= "table" then return false end
    for key, value in pairs(info.flags or {}) do
        if value == wanted or (key == wanted and value == true) then return true end
    end
    return false
end
local function same_place(a, b)
    return a and b and a.num ~= nil and tonumber(a.num) == tonumber(b.num)
        and norm(a.system) == norm(b.system) and norm(a.area) == norm(b.area)
end
local function empty_ship()
    local ship = gmcp and gmcp.char and gmcp.char.ship
    if type(ship) ~= "table" or type(ship.hold) ~= "table" then return false end
    local hold = ship.hold
    local maximum, free = hold and tonumber(hold.max), hold and tonumber(hold.cur)
    return ship and type(ship.cargo) == "table" and next(ship.cargo) == nil
        and maximum and maximum > 0 and maximum < math.huge and free == maximum
end
local function message(text) cecho("\n<cyan>[hauling]<reset> " .. text .. "\n") end
local function protected()
    return (F2T_DEATH_STATE and F2T_DEATH_STATE.active)
        or (F2T_STAMINA_STATE and F2T_STAMINA_STATE.current_phase
            and F2T_STAMINA_STATE.current_phase ~= "idle")
end

function f2t_hauling_teleport_cancel()
    local p = pending; pending = nil
    if not p then return end
    if p.sent and not p.settled then uncertain = true end
    if p.timer then killTimer(p.timer) end
    if p.trigger then killTrigger(p.trigger) end
    for _, id in ipairs(p.handlers) do killAnonymousEventHandler(id) end
end
function f2t_hauling_teleport_reset()
    f2t_hauling_teleport_cancel()
    inventory, uncertain = nil, nil
end
function f2t_hauling_teleport_busy() return pending ~= nil end
function f2t_hauling_teleport_uncertain() return uncertain == true end

-- Kept separate so normal-navigation fallback is also prevented from buying
-- at an unrelated exchange on a stale speedwalk completion notification.
function f2t_hauling_teleport_at_seller()
    local state, info = F2T_HAULING_STATE, room()
    local target = state and state.buy_location
    return target and norm(info.system) == norm(target.system)
        and norm(info.area) == norm(target.planet) and info.num ~= nil and flag(info, "exchange")
end

function f2t_hauling_teleport_try()
    local state = F2T_HAULING_STATE
    if not state or not state.active or state.paused or state.stopping then return false end
    if not state.session_policy or state.session_policy.teleport_to_seller ~= true then return false end
    if pending then return true end
    if uncertain then
        message("Teleport outcome remains uncertain. Inspect your location, then stop/start explicitly; no movement or buy was sent.")
        f2t_hauling_pause(true); return true
    end
    if protected() then f2t_hauling_pause(true); return true end
    if f2t_hauling_teleport_at_seller() then return false end
    local target = f2t_map_teleport_exchange_target(state.buy_location)
    if not target then message("Seller exchange has no verified mapped teleport address; using ship navigation/discovery."); return false end
    if not empty_ship() then message("Empty hold is not confirmed; using ordinary navigation."); return false end
    if F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_WAITING_FOR_MOVE or F2T_SPEEDWALK_CUSTOMS_PENDING
        or (F2T_BULK_STATE and F2T_BULK_STATE.active) then return false end
    local info = room()
    if not info.num or not info.system or not info.area or norm(info.area):match(" space$") then return false end
    local name = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if type(name) ~= "string" or name == "" then return false end
    if inventory and (inventory.name ~= name or os.time() >= inventory.until_time) then inventory = nil end
    if inventory and not inventory.owned then return false end

    local p = {state=state, target=target, name=name, location=state.buy_location,
        handlers={}, stage="inventory", origin={system=info.system,area=info.area,num=info.num}}
    if norm(info.system) == norm(target.system) and norm(info.area) == norm(target.planet) then
        p.local_origin = p.origin -- Already on the seller planet: only the local hop is needed.
    end
    pending = p
    local function current()
        return pending == p and state == F2T_HAULING_STATE and state.active and not state.paused
            and not state.stopping and state.buy_location == p.location
            and state.current_phase == "navigating_to_buy"
            and gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name == name
    end
    local function finish(kind, reason)
        if pending ~= p then return end
        local valid = current()
        p.settled = kind ~= "uncertain"
        f2t_hauling_teleport_cancel()
        if not valid then return end
        if reason then message(reason) end
        if kind == "arrived" then f2t_hauling_transition("buying")
        elseif kind == "fallback" then f2t_hauling_phase_navigate_to_buy(true)
        elseif kind == "skip" then f2t_hauling_retry_exchange("buy")
        else f2t_hauling_pause(true) end
    end
    local function deadline(seconds, kind, reason)
        if p.timer then killTimer(p.timer) end
        p.timer = tempTimer(seconds, function() finish(kind, reason) end)
    end
    local function request_ship()
        if not current() then f2t_hauling_teleport_cancel(); return end
        p.stage = p.local_origin and "local_ship" or "ship"
        deadline(8, "fallback", "Fresh ship GMCP did not arrive; using ordinary navigation without another teleport.")
        send("status", false) -- The server sends char.ship with this display.
    end
    p.handlers[#p.handlers+1] = registerAnonymousEventHandler("gmcp.char.ship", function(event_name)
        if event_name and event_name ~= "gmcp.char.ship" then return end
        if not current() or (p.stage ~= "ship" and p.stage ~= "local_ship" and p.stage ~= "seller_ship") then return end
        local at_seller = p.stage == "seller_ship"
        if protected() then finish("pause", "Protection recovery takes priority; no teleport or purchase sent."); return end
        if not empty_ship() then finish("pause", "Fresh ship data did not confirm an empty hold; no teleport or purchase sent."); return end
        if at_seller then
            if not f2t_hauling_teleport_at_seller() or tonumber(room().num) ~= target.num then
                finish("pause", "Seller location changed before purchase; paused without buying."); return
            end
        elseif not same_place(room(), p.local_origin or p.origin) then
            finish("fallback", "Location changed during teleport checks; using normal navigation."); return
        end
        -- Re-resolve just before sending: map edits and destination policy must
        -- not turn a previously reviewed hash into a different target.
        local fresh = f2t_map_teleport_exchange_target(p.location)
        if not fresh or fresh.hash ~= target.hash then
            if at_seller then finish("pause", "Mapped seller address changed before purchase; paused without buying.")
            else finish("fallback", "Mapped seller address changed; using normal navigation.") end
            return
        end
        if f2t_hauling_customs_system_blocked and f2t_hauling_customs_system_blocked(target.system) then
            finish("skip", "Seller system is excluded by route policy; skipping it."); return
        end
        if at_seller then
            finish("arrived", "Seller arrival and fresh empty hold confirmed; continuing bulk purchase."); return
        end
        p.stage, p.sent, p.settled = p.local_origin and "local_teleport" or "teleport", true, false
        deadline(15, "uncertain", "Teleport arrival was not confirmed; paused without retrying or buying.")
        local address = p.local_origin and string.format("%d", target.num) or target.address
        message(p.local_origin and ("Teleporting locally to seller exchange: " .. address)
            or ("Teleporting empty ship to seller's shuttle pad: " .. address))
        send("tp " .. address, false)
    end)
    p.handlers[#p.handlers+1] = registerAnonymousEventHandler("gmcp.room.info", function()
        if not current() or (p.stage ~= "teleport" and p.stage ~= "local_teleport" and p.stage ~= "seller_ship") then return end
        local live = room()
        if p.stage ~= "teleport" and same_place(live, {system=target.system,area=target.planet,num=target.num})
            and flag(live, "exchange") then
            if p.stage == "seller_ship" then return end
            p.stage, p.settled = "seller_ship", true
            if protected() then finish("pause", "Protection recovery takes priority; no purchase sent."); return end
            if not empty_ship() then finish("pause", "Cargo changed during teleport; paused with cargo preserved."); return end
            -- Local teleport and look send room data, not a guaranteed commodity
            -- snapshot. The existing bulk buyer needs ship capacity, not that
            -- snapshot: confirm it afresh after arrival without polling prices.
            deadline(8, "pause", "Seller arrival confirmed, but fresh ship GMCP is missing; paused before buying.")
            send("status", false)
        elseif p.stage == "teleport" and norm(live.system) == norm(target.system) and norm(live.area) == norm(target.planet)
            and tonumber(live.num) and flag(live, "shuttlepad") then
            if protected() then finish("pause", "Protection recovery takes priority; no local navigation or purchase sent."); return end
            if not empty_ship() then finish("pause", "Cargo changed during teleport; paused with cargo preserved."); return end
            p.settled = true
            p.local_origin = {system=live.system,area=live.area,num=live.num}
            message("Seller shuttle pad confirmed; checking empty hold before the local exchange hop.")
            request_ship()
        elseif p.stage == "seller_ship" then
            finish("pause", "Seller location changed before purchase; paused without buying.")
        elseif not same_place(live, p.local_origin or p.origin) then
            finish("uncertain", "Teleport reached an unexpected room; inspect location before resuming. No purchase sent.")
        end
    end)
    p.trigger = tempRegexTrigger("^.*$", function()
        if not current() then return end
        local text = tostring(line or ""):gsub("\27%[[%d;]*m", ""):match("^%s*(.-)%s*$")
        if p.stage == "inventory" then
            if text:find("You check out your personal kit -", 1, true) == 1 then p.kit = text
            elseif p.kit then p.kit = p.kit .. " " .. text else return end
            if #p.kit > 8192 then finish("fallback", "Inventory response was invalid; using normal navigation."); return end
            if not p.kit:find("and that seems to be it.", 1, true) then return end
            local days = tonumber(p.kit:match("an Mk1 teleporter control%s*%((%d+)%s+days? until expiry%)"))
            -- The display rounds remaining days up. Recheck at least hourly,
            -- and never cache past the conservative lower bound of expiry.
            inventory = {name=name,owned=days ~= nil and days > 0,
                until_time=os.time() + (days and math.min(3600, math.max(0, days-1)*86400) or 3600)}
            if inventory.owned then request_ship()
            else finish("fallback", "No active Mk1 teleporter in inventory; using ship navigation.") end
        elseif p.stage == "teleport" or p.stage == "local_teleport" then
            if text:match("^You are carrying at least one object that interferes with")
                or text:match("^Your ship is carrying at least one object that interferes with")
                or text:match("^I can't find a planet called ") then p.refusal = text
            elseif p.refusal then p.refusal = p.refusal .. " " .. text end
            local refusal = text == "You don't have a teleporter!"
                or text == "You can't teleport while you are in your spaceship."
                or text == "You can't teleport now!"
                or text == "You are in a teleport shielded location!"
                or text == "Your destination planet is teleport shielded!"
                or text == "The location you are trying to access is teleport shielded!"
                or text:match("^This star system doesn't have a planet called .+!$")
                or (p.refusal and (p.refusal:match("teleport transmissions!$")
                    or p.refusal:match(" in a star system called .+!$")))
            if text == "You cannot teleport while your ship is carrying cargo!" then
                finish("pause", "Teleport refused because cargo is aboard; paused with cargo preserved.")
            elseif text:match("^You are exiled from this system!") then
                finish("pause", "Exile refusal: stopped before further travel; inspect the server notice.")
            elseif text:match("^I'm afraid the .+ system is closed to visitors at the moment%.$") then
                finish("skip", "Seller system is closed; skipping this supplier.")
            elseif refusal then
                if text == "You don't have a teleporter!" then inventory = {name=name,owned=false,until_time=os.time()+3600} end
                finish("fallback", "Teleport was refused; using normal navigation.")
            end
        end
    end)
    if inventory and inventory.owned then request_ship()
    else
        deadline(8, "fallback", "Complete inventory response did not arrive; using normal navigation.")
        send("inv", false)
    end
    return true
end

registerAnonymousEventHandler("sysDisconnectionEvent", function()
    f2t_hauling_teleport_cancel(); inventory = nil
end)
