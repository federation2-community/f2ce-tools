-- Works one leg of an Akaturi contract: the game names only a planet and a
-- room title, and titles repeat. Walks to each mapped room with that title,
-- nearest first, and tries pickup/dropoff there; once those run out, explores
-- the planet for rooms with the title it hasn't tried. Shared by hauling and
-- the Akaturi tab, one visit at a time.
--
-- f2t_akaturi_visit(kind, opts) starts a visit; opts.onDone(outcome) gets one of
--   "done"      the game accepted the command
--   "notFound"  every room with the title was tried and the planet explored
--   "stopped"   the walk was stopped by hand
--   "busy"      another exploration is running, so the search can't explore
--   "failed"    exploring couldn't start (no mapped position)
-- Raises "f2tAkaturiVisitChanged" whenever a visit starts, moves on or ends.

local COMMAND = { pickup = "pickup", delivery = "dropoff" }
local REPLY_TIMEOUT = 5

local visit = nil
local nextToken = 0

local function changed() raiseEvent("f2tAkaturiVisitChanged") end

local function clearReplyTimer(current)
    if current.replyTimer then killTimer(current.replyTimer) end
    current.replyTimer = nil
end

local function finish(outcome)
    local current = visit
    if not current then return end
    visit = nil
    clearReplyTimer(current)
    f2t_debug_log("[akaturi/finder] %s visit ended: %s", current.kind, outcome)
    changed()
    if current.onDone then current.onDone(outcome) end
end

local function hereKey()
    return F2T_MAP_CURRENT_ROOM_ID or f2t_get_current_room_hash()
end

--- Whether the player stands in a room with this title on this planet
--- @param planet string
--- @param room string
--- @return boolean
function f2t_akaturi_at_room(planet, room)
    local info = gmcp and gmcp.room and gmcp.room.info
    return info ~= nil and room ~= nil and info.area == planet and info.name == room
end

local step

local function tryHere()
    local current = visit
    if not current then return end
    current.tried[hereKey() or "?"] = true
    current.stage = "trying"
    changed()
    send(COMMAND[current.kind])
    local token = current.token
    current.replyTimer = tempTimer(REPLY_TIMEOUT, function()
        if visit and visit.token == token and visit.stage == "trying" then
            visit.replyTimer = nil
            f2t_debug_log("[akaturi/finder] no reply to %s, moving on", COMMAND[visit.kind])
            step()
        end
    end)
end

-- Untried mapped rooms with the title, nearest first; unreachable ones last.
local function candidates(current)
    local matches = f2t_akaturi_search_room(current.planet, current.room) or {}
    local here = F2T_MAP_CURRENT_ROOM_ID
    local list = {}
    for _, match in ipairs(matches) do
        if not current.tried[match.room_id] then
            local steps = math.huge
            if here and getPath(here, match.room_id) then steps = #speedWalkDir end
            list[#list + 1] = { roomId = match.room_id, steps = steps }
        end
    end
    table.sort(list, function(a, b) return a.steps < b.steps end)
    return list, #matches
end

local function explore(current)
    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        cecho("\n<yellow>[akaturi]<reset> An exploration is already running; finish or stop it first.\n")
        finish("busy")
        return
    end
    current.stage = "exploring"
    current.explores = current.explores + 1
    changed()
    cecho(string.format("\n<cyan>[akaturi]<reset> Exploring %s for another '%s'\n", current.planet, current.room))
    local token = current.token
    local started = f2t_map_explore_planet_start("brief", current.planet, function(foundRoomId)
        if not visit or visit.token ~= token then return end
        if foundRoomId then
            tryHere()
        else
            visit.exhausted = true
            step()
        end
    end, nil, current.room, true, current.tried)
    if not started and visit and visit.token == token then
        finish("failed")
    end
end

step = function()
    local current = visit
    if not current then return end
    clearReplyTimer(current)

    local here = hereKey()
    if f2t_akaturi_at_room(current.planet, current.room) and here and not current.tried[here] then
        tryHere()
        return
    end

    local list, total = candidates(current)
    local target = list[1]
    if target then
        current.stage = "walking"
        current.index, current.total = total - #list + 1, total
        changed()
        cecho(string.format("\n<cyan>[akaturi]<reset> Heading to '%s' on %s%s\n", current.room, current.planet,
            total > 1 and string.format(" (%d of %d rooms with that name)", current.index, total) or ""))
        f2t_map_walk_to(target.roomId, function(_, result)
            if visit ~= current or current.stage ~= "walking" then return end
            if result == "stopped" then
                finish("stopped")
            elseif F2T_MAP_CURRENT_ROOM_ID == target.roomId then
                tryHere()
            else
                -- Unreachable for now; step() still tries an untried room with the title if we stopped in one
                current.tried[target.roomId] = true
                step()
            end
        end)
        return
    end

    if not current.exhausted then
        explore(current)
        return
    end

    cecho(string.format("\n<yellow>[akaturi]<reset> Tried every '%s' on %s and explored the planet; " ..
        "the %s isn't in any of them.\n", current.room, current.planet,
        current.kind == "pickup" and "package" or "dropoff"))
    finish("notFound")
end

-- The contract moving on (GMCP) confirms the command even if its text was missed.
registerAnonymousEventHandler("f2tAkaturiContractChanged", function()
    local current = visit
    if not current then return end
    local contract = f2t_akaturi_contract()
    if (current.kind == "pickup" and (not contract or contract.collected))
        or (current.kind == "delivery" and not contract) then
        finish("done")
    end
end)

--- Start working one leg, replacing any visit already running
--- @param kind string "pickup" or "delivery"
--- @param opts table { planet, room, owner, onDone }
--- @return boolean started
function f2t_akaturi_visit(kind, opts)
    if not COMMAND[kind] or not opts.planet or not opts.room then return false end
    f2t_akaturi_visit_cancel()
    nextToken = nextToken + 1
    visit = {
        token = nextToken, kind = kind, planet = opts.planet, room = opts.room,
        owner = opts.owner or "manual", onDone = opts.onDone,
        tried = {}, explores = 0, exhausted = false, stage = "starting",
    }
    f2t_debug_log("[akaturi/finder] %s visit: '%s' on %s for %s", kind, opts.room, opts.planet, visit.owner)
    step()
    return true
end

--- Drop the visit in progress without reporting an outcome, stopping its walk
--- or exploration
--- @param owner string|nil only cancel a visit started by this owner
function f2t_akaturi_visit_cancel(owner)
    local current = visit
    if not current or (owner and current.owner ~= owner) then return end
    visit = nil
    clearReplyTimer(current)
    -- A walk can be exploring too, when navigation self-heals an unmapped route
    if current.stage ~= "trying" and F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        f2t_map_explore_stop("Akaturi room search stopped")
    end
    if current.stage == "walking" and F2T_SPEEDWALK_ACTIVE then
        f2t_map_speedwalk_stop()
    end
    changed()
end

-- A stopped exploration never reports back, so a search waiting on one ends here.
registerAnonymousEventHandler("f2tExploreStopped", function()
    local current = visit
    if current and (current.stage == "exploring" or current.stage == "walking") then
        finish("stopped")
    end
end)

-- Deaths. A hauling search is hauling's to restart (f2t_hauling_on_death); a
-- search started by hand is remembered and picked up again once death recovery
-- reports the player insured, unless the contract has moved on or this is a
-- second death on it.
local resumeAfterDeath = nil

registerAnonymousEventHandler("f2tDeathDetected", function()
    local current = visit
    if current and current.owner == "manual" then
        resumeAfterDeath = current.kind
        f2t_akaturi_visit_cancel()
    end
end)

registerAnonymousEventHandler("f2tDeathRecovered", function(_, insured)
    local kind = resumeAfterDeath
    resumeAfterDeath = nil
    if not kind then return end
    local contract = f2t_akaturi_contract()
    if contract and f2t_akaturi_leg(contract) ~= kind then return end
    local reason = f2t_akaturi_death_hold_reason(insured)
    if reason then
        cecho(string.format("\n<yellow>[akaturi]<reset> Not carrying on with the search after the death: %s.\n",
            reason))
        return
    end
    cecho("\n<green>[akaturi]<reset> Insured again; carrying on with the search from here\n")
    f2t_akaturi_work_leg()
end)

--- The visit in progress, or nil
--- @return table|nil { kind, owner, stage, planet, room, index, total }; index/total
--- count the mapped rooms with the title while walking to one
function f2t_akaturi_visit_current()
    local current = visit
    if not current then return nil end
    return { kind = current.kind, owner = current.owner, stage = current.stage,
        planet = current.planet, room = current.room, index = current.index, total = current.total }
end

--- The game refused pickup/dropoff in this room (success arrives as GMCP).
--- Returns true when a visit was waiting on it, so the refusal can be hidden
--- while the search carries on.
--- @param kind string "pickup" or "delivery"
--- @return boolean consumed
function f2t_akaturi_visit_refused(kind)
    local current = visit
    if not current or current.kind ~= kind or current.stage ~= "trying" then return false end
    clearReplyTimer(current)
    tempTimer(0.3, function() if visit == current then step() end end)
    return true
end

f2t_debug_log("[akaturi] room finder loaded")
