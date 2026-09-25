-- Premium navigation recovery only. Never restart a stopped session or replay
-- a trade: status must produce a fresh, reconciled ship before choosing a route.
if f2t_hauling_navigation_recovery_cancel then f2t_hauling_navigation_recovery_cancel(true) end
local pending
local function norm(v) return tostring(v or ""):lower() end
local function room_key()
    local r = gmcp and gmcp.room and gmcp.room.info
    if not r or not r.system or not r.area or r.num == nil then return nil end
    return norm(r.system) .. "\t" .. norm(r.area) .. "\t" .. tostring(r.num)
end
local function protected()
    return (F2T_DEATH_STATE and F2T_DEATH_STATE.active)
        or (F2T_STAMINA_STATE and F2T_STAMINA_STATE.current_phase and F2T_STAMINA_STATE.current_phase ~= "idle")
        or (f2t_hauling_teleport_uncertain and f2t_hauling_teleport_uncertain())
        or (f2t_hauling_teleport_busy and f2t_hauling_teleport_busy())
        or (F2T_BULK_STATE and F2T_BULK_STATE.active)
        or F2T_HAULING_STATE.purchase_settlement
end
local function moving()
    return F2T_SPEEDWALK_ACTIVE or F2T_SPEEDWALK_WAITING_FOR_MOVE or F2T_SPEEDWALK_CUSTOMS_PENDING
        or (F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active)
        or (F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active)
end
local function number(v)
    local n = tonumber(v)
    return n and n == n and n >= 0 and n < 2^53 and n or nil
end
local function cargo_signature()
    local state = F2T_HAULING_STATE
    local ship = gmcp and gmcp.char and gmcp.char.ship
    if type(ship) ~= "table" or type(ship.cargo) ~= "table" or type(ship.hold) ~= "table" then return nil end
    local maximum, free = number(ship.hold.max), number(ship.hold.cur)
    if not maximum or maximum == 0 or not free or free > maximum then return nil end
    local rows, count = {}, 0
    for index, lot in pairs(ship.cargo) do
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or index > #ship.cargo
            or type(lot) ~= "table" or norm(lot.commodity) ~= norm(state.current_commodity)
            or type(lot.origin) ~= "string" or lot.origin == "" or not number(lot.cost) then return nil end
        count = count + 1
        rows[#rows+1] = norm(lot.commodity) .. "\t" .. norm(lot.origin) .. "\t" .. tostring(number(lot.cost))
    end
    if count ~= #ship.cargo or maximum - free ~= count * 75 then return nil end
    local stats = state.current_commodity_stats
    if not stats or not number(stats.lots_bought) or not number(stats.lots_sold)
        or stats.lots_bought - stats.lots_sold ~= count then return nil end
    if count > 0 and not f2t_hauling_cargo_floor() then return nil end
    table.sort(rows)
    return table.concat(rows, "\n") .. "\n" .. maximum .. ":" .. free, count
end

function f2t_hauling_navigation_recovery_cancel(clear)
    local p = pending; pending = nil
    if p then
        if p.timer then killTimer(p.timer) end
        if p.handler then killAnonymousEventHandler(p.handler) end
    end
    if clear and F2T_HAULING_STATE then
        F2T_HAULING_STATE.navigation_recovery_side = nil
        F2T_HAULING_STATE.navigation_recovery_snapshot = nil
    end
end

function f2t_hauling_navigation_recovery_cargo_valid()
    local state = F2T_HAULING_STATE
    local snapshot = state.navigation_recovery_snapshot
    return snapshot and not protected() and not moving() and room_key() == snapshot.room
        and gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name == snapshot.name
        and cargo_signature() == snapshot.signature
end

function f2t_hauling_navigation_recover(side)
    local state = F2T_HAULING_STATE
    if not state or state.mode ~= "exchange" or state.rotation ~= "top_base_21"
        or not state.active or state.paused or (side ~= "buy" and side ~= "sell") then return false end
    if state.current_phase ~= "navigating_to_" .. side
        and not (state.current_phase == "recovering_navigation" and state.navigation_recovery_side == side) then return false end
    if pending then return true end
    if state.stopping then f2t_hauling_do_stop(); return true end
    if state.pause_requested or protected() then f2t_hauling_pause(true); return true end
    local name = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if type(name) ~= "string" or name == "" or not room_key() then f2t_hauling_pause(true); return true end
    state.navigation_recovery_side = side
    state.navigation_recovery_snapshot = nil
    state.teleport_ship_route, state.exchange_route = nil, nil
    state.current_phase = "recovering_navigation"
    local p = {state=state, side=side, name=name, room=room_key(), polls=0}
    pending = p
    local function current()
        return pending == p and F2T_HAULING_STATE == state and state.active and not state.paused
            and not state.pause_requested and not state.stopping and state.current_phase == "recovering_navigation"
            and gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name == name
    end
    local function pause(message)
        f2t_hauling_navigation_recovery_cancel()
        cecho("\n<yellow>[hauling]<reset> " .. message .. " Cargo preserved; recovery paused.\n")
        f2t_hauling_pause(true)
    end
    local function cancel_changed()
        if F2T_HAULING_STATE == state and state.active and not state.paused
            and state.current_phase == "recovering_navigation" then
            pause("Recovery context changed; fresh validation is required.")
        else f2t_hauling_navigation_recovery_cancel() end
    end
    local function request()
        if pending ~= p then return end
        if not current() then cancel_changed(); return end
        if protected() then pause("Protection or an unfinished operation blocks navigation recovery."); return end
        if moving() then
            p.polls = p.polls + 1
            if p.polls >= 40 then pause("Navigation did not settle within 10 seconds."); return end
            p.timer = tempTimer(0.25, request); return
        end
        p.room = room_key()
        if not p.room then pause("Current location is unavailable."); return end
        p.handler = registerAnonymousEventHandler("gmcp.char.ship", function(event)
            if pending ~= p then return end
            if event and event ~= "gmcp.char.ship" then return end
            if not current() then cancel_changed(); return end
            if protected() or moving() or room_key() ~= p.room then pause("Location or protection changed during cargo check."); return end
            local signature, lots = cargo_signature()
            if not signature then pause("Fresh cargo, hold capacity and the confirmed trade ledger disagree."); return end
            f2t_hauling_navigation_recovery_cancel()
            state.navigation_recovery_snapshot = {signature=signature, room=p.room, name=name}
            f2t_hauling_navigation_recovered(side, lots)
        end)
        p.timer = tempTimer(8, function()
            if pending ~= p then return end
            if current() then pause("Fresh ship GMCP did not arrive after status.")
            else cancel_changed() end
        end)
        cecho("\n<cyan>[hauling]<reset> Navigation failed; checking fresh cargo before choosing another exchange.\n")
        send("status", false)
    end
    -- Allow the failing mapper/command callback to release its ownership first.
    p.timer = tempTimer(0.25, request)
    return true
end
