-- fed2-tools map — jump exit management (ported from map_jump.lua)

F2T_MAP_JUMP_CAPTURE = {
    expecting = false,
    active    = false,
    room_id   = nil,
    source_system = nil,
    destinations  = {},
    in_output = false,
}

local jump_timer_id   = nil
local giveup_timer_id = nil
local afterCaptureCycle   -- forward decl; assigned in the resync section below

-- room_id -> os.time() of the last silent "jump" probe sent for that link room.
-- GMCP room events can re-fire repeatedly for the same room (another player
-- entering, "look" resending room data, etc). Without this throttle, every
-- re-fire would restart the probe, and overlapping probes made
-- jump_capture_line's deleteLine() eat real console output (including the
-- player's own "look") instead of just the probe's.
local last_attempt_at   = {}
local ATTEMPT_COOLDOWN  = 60

-- A room's jump exits are considered fresh for this long after a successful
-- probe; process_link_room won't re-check them again until it's stale. This
-- is what lets the map catch up on its own after a syndicate builds or loses
-- a Hub/Distant Beacon (which changes valid "jump" destinations from an
-- already-mapped link room) just by the player passing back through later,
-- instead of that room's jump exits being probed once and then never again.
local JUMP_SYNC_TTL = 3600

local function clearJumpExits(room_id)
    if not room_id or not roomExists(room_id) then return end
    for command, _ in pairs(getSpecialExits(room_id)) do
        if string.match(command, "^jump ") then
            removeSpecialExit(room_id, command)
        end
    end
end

function f2t_map_process_link_room(room_id, flags)
    if not room_id or not roomExists(room_id) then return end
    if not flags or not f2t_has_value(flags, "link") then return end
    if F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active then return end
    local last = last_attempt_at[room_id]
    if last and os.time() - last < ATTEMPT_COOLDOWN then return end
    local synced_at = tonumber(getRoomUserData(room_id, "fed2_jump_synced_at"))
    if synced_at and os.time() - synced_at < JUMP_SYNC_TTL then return end
    local system = getRoomUserData(room_id, "fed2_system")
    if not system then return end
    last_attempt_at[room_id] = os.time()
    clearJumpExits(room_id)   -- routes may have changed since the last sync, not just grown
    f2t_map_start_jump_capture(room_id, system)
end

function f2t_map_start_jump_capture(room_id, source_system)
    F2T_MAP_JUMP_CAPTURE.expecting     = true
    F2T_MAP_JUMP_CAPTURE.active        = false
    F2T_MAP_JUMP_CAPTURE.room_id       = room_id
    F2T_MAP_JUMP_CAPTURE.source_system = source_system
    F2T_MAP_JUMP_CAPTURE.destinations  = {}
    F2T_MAP_JUMP_CAPTURE.in_output     = false
    send("jump", false)
    -- Safety net: if "jump" never produces the expected header (unexpected
    -- game response), don't leave "expecting" stuck forever blocking every
    -- other link room's probe for the rest of the session.
    if giveup_timer_id then killTimer(giveup_timer_id) end
    giveup_timer_id = tempTimer(3, function()
        giveup_timer_id = nil
        if F2T_MAP_JUMP_CAPTURE.expecting and not F2T_MAP_JUMP_CAPTURE.active then
            F2T_MAP_JUMP_CAPTURE.expecting = false
            if afterCaptureCycle then afterCaptureCycle() end
        end
    end)
end

function f2t_map_add_jump_destination(system_name)
    if not F2T_MAP_JUMP_CAPTURE.active then return end
    table.insert(F2T_MAP_JUMP_CAPTURE.destinations, system_name)
end

function f2t_map_finish_jump_capture()
    if not F2T_MAP_JUMP_CAPTURE.active then return end
    local room_id      = F2T_MAP_JUMP_CAPTURE.room_id
    local source_system = F2T_MAP_JUMP_CAPTURE.source_system
    local destinations  = F2T_MAP_JUMP_CAPTURE.destinations
    local created_count = 0
    for _, dest_system in ipairs(destinations) do
        if f2t_map_create_jump_special_exit(room_id, source_system, dest_system) then
            created_count = created_count + 1
        end
    end
    if room_id then setRoomUserData(room_id, "fed2_jump_synced_at", tostring(os.time())) end
    F2T_MAP_JUMP_CAPTURE.expecting     = false
    F2T_MAP_JUMP_CAPTURE.active        = false
    F2T_MAP_JUMP_CAPTURE.in_output     = false
    F2T_MAP_JUMP_CAPTURE.room_id       = nil
    F2T_MAP_JUMP_CAPTURE.source_system = nil
    F2T_MAP_JUMP_CAPTURE.destinations  = {}
    if afterCaptureCycle then afterCaptureCycle() end
end

function f2t_map_create_jump_special_exit(from_room_id, from_system, to_system)
    local to_room_id = f2t_map_find_link_room_in_system(to_system)
    if not to_room_id then return false end
    local forward_command = string.format("jump %s", to_system)
    addSpecialExit(from_room_id, to_room_id, forward_command)
    local reverse_command = string.format("jump %s", from_system)
    addSpecialExit(to_room_id, from_room_id, reverse_command)
    return true
end

function f2t_map_find_link_room_in_system(system)
    if not system or system == "" then return nil end
    local rooms = getRooms()
    for room_id, room_name in pairs(rooms) do
        local room_system = getRoomUserData(room_id, "fed2_system")
        local has_link    = getRoomUserData(room_id, "fed2_flag_link")
        if room_system == system and has_link == "true" then return room_id end
    end
    return nil
end

function f2t_map_jump_reset_timer()
    if jump_timer_id then killTimer(jump_timer_id) end
    jump_timer_id = tempTimer(0.5, function()
        if F2T_MAP_JUMP_CAPTURE.active then
            f2t_map_finish_jump_capture()
        end
        jump_timer_id = nil
    end)
end

-- ── Manual resync ────────────────────────────────────────────────────────────
-- process_link_room already re-checks a link room's jump exits on its own
-- once JUMP_SYNC_TTL has passed (see above) — no command needed for the
-- normal case. These exist only to force it sooner than that, e.g. right
-- after hearing a syndicate just finished a beacon build.
local resync_queue          = nil   -- array of room_ids pending resync; nil = idle
local resync_continue_timer = nil

-- Force a re-probe of one link room's jump destinations right now, ignoring
-- JUMP_SYNC_TTL and the retry cooldown (both exist for the passive check, not
-- a deliberate manual resync). Returns false without doing anything if a
-- capture is already in flight.
function f2t_map_resync_jump_exits(room_id)
    if not room_id or not roomExists(room_id) then return false end
    if F2T_MAP_JUMP_CAPTURE.expecting or F2T_MAP_JUMP_CAPTURE.active then return false end
    local system = getRoomUserData(room_id, "fed2_system")
    if not system then return false end
    clearJumpExits(room_id)
    last_attempt_at[room_id] = os.time()
    f2t_map_start_jump_capture(room_id, system)
    return true
end

local function resyncProcessNext()
    if not resync_queue then return end
    if #resync_queue == 0 then
        cecho("\n<green>[map]<reset> Jump-exit resync complete.\n")
        resync_queue = nil
        return
    end
    local room_id = table.remove(resync_queue, 1)
    if not f2t_map_resync_jump_exits(room_id) then
        table.insert(resync_queue, 1, room_id)   -- still busy elsewhere; retry shortly
        if resync_continue_timer then killTimer(resync_continue_timer) end
        resync_continue_timer = tempTimer(1, resyncProcessNext)
    end
    -- on success, afterCaptureCycle() advances the queue once this probe ends
end

-- Re-probe every mapped link room's jump destinations, one at a time (probes
-- can't overlap — there's only one shared capture state). Run after a
-- syndicate beacon build changes routing, or any time you suspect the mapped
-- jump exits are stale.
function f2t_map_resync_all_jump_exits()
    if resync_queue then
        cecho("\n<orange>[map]<reset> Jump-exit resync already in progress.\n")
        return
    end
    local link_rooms = {}
    for room_id in pairs(getRooms()) do
        if getRoomUserData(room_id, "fed2_flag_link") == "true" then
            link_rooms[#link_rooms + 1] = room_id
        end
    end
    if #link_rooms == 0 then
        cecho("\n<orange>[map]<reset> No mapped link rooms found.\n")
        return
    end
    resync_queue = link_rooms
    cecho(string.format("\n<green>[map]<reset> Resyncing jump exits for %d link room(s)...\n", #link_rooms))
    resyncProcessNext()
end

afterCaptureCycle = function()
    if not resync_queue then return end
    if resync_continue_timer then killTimer(resync_continue_timer) end
    resync_continue_timer = tempTimer(1, resyncProcessNext)
end
