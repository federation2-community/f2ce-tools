-- f2ce-tools map — topology sync capture
--
-- Two-phase capture that rebuilds the whole topology model from the server:
--   Phase "cartels":    "display cartels" lists every cartel grouped by
--                       syndicate — the complete cartel->syndicate mapping.
--   Phase "syndicates": "display syndicates" lists every syndicate with its
--                       beacon builds.
-- Completion is silence-timer based (0.5s), same as the other captures.
-- System->cartel membership is NOT captured here; it accrues from GMCP as you
-- travel, from map area userdata, and from cartel exploration.

F2T_MAP_TOPOLOGY_CAPTURE = F2T_MAP_TOPOLOGY_CAPTURE or {active = false}

-- opts.silent suppresses every console message this sync would print (used by
-- the once-per-login startup sync in map/events.lua). Debug logging and the
-- callback are unaffected; the game replies are swallowed by the capture
-- triggers either way, so a silent sync produces no output at all.
function f2t_map_topology_sync(callback, opts)
    opts = opts or {}
    local silent = opts.silent and true or false
    if F2T_MAP_TOPOLOGY_CAPTURE.active then
        if not silent then
            cecho("\n<yellow>[map]<reset> Topology sync already in progress\n")
        end
        return false
    end
    F2T_MAP_TOPOLOGY_CAPTURE = {
        active = true,
        phase = "cartels",
        current_syndicate = nil,
        cartels = {},
        syndicates = {},
        seen_start = false,
        timer_id = nil,
        callback = callback,
        silent = silent,
    }
    f2t_debug_log("[map/topology] Sync started: capturing display cartels (silent=%s)", tostring(silent))
    send("display cartels", false)
    f2t_map_topology_capture_reset_timer()
    return true
end

function f2t_map_topology_capture_reset_timer()
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if capture.timer_id then killTimer(capture.timer_id) end
    capture.timer_id = tempTimer(0.5, function()
        if F2T_MAP_TOPOLOGY_CAPTURE.active then
            f2t_map_topology_capture_phase_complete()
        end
    end)
end

function f2t_map_topology_capture_phase_complete()
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if capture.phase == "cartels" then
        capture.phase = "syndicates"
        capture.seen_start = false
        f2t_debug_log("[map/topology] Sync: capturing display syndicates")
        send("display syndicates", false)
        f2t_map_topology_capture_reset_timer()
        return
    end
    f2t_map_topology_capture_finish()
end

function f2t_map_topology_capture_finish()
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    F2T_MAP_TOPOLOGY_CAPTURE = {active = false}

    local cartel_count, syndicate_count = 0, 0
    for _ in pairs(capture.cartels) do cartel_count = cartel_count + 1 end
    for _ in pairs(capture.syndicates) do syndicate_count = syndicate_count + 1 end

    if cartel_count == 0 or syndicate_count == 0 then
        if not capture.silent then
            cecho("\n<red>[map]<reset> Topology sync failed (no data captured)\n")
        end
        f2t_debug_log("[map/topology] Sync failed: %d cartels, %d syndicates captured",
            cartel_count, syndicate_count)
        if capture.callback then capture.callback(false) end
        return
    end

    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY

    -- Both listings are complete, so replace grouping and beacon facts
    -- wholesale and prune anything that no longer exists.
    t.cartels = {}
    for cartel, syndicate in pairs(capture.cartels) do
        t.cartels[cartel] = syndicate
    end

    local new_syndicates = {}
    for syndicate, info in pairs(capture.syndicates) do
        new_syndicates[syndicate] = {
            hub_beacon = info.hub_beacon or false,
            distant_beacon = info.distant_beacon or false,
        }
    end
    -- Syndicates seen in the cartel roster but missing a stats row keep their
    -- previous (or default) beacon facts.
    for _, syndicate in pairs(t.cartels) do
        if not new_syndicates[syndicate] then
            new_syndicates[syndicate] = t.syndicates[syndicate]
                or {hub_beacon = false, distant_beacon = false}
        end
    end
    t.syndicates = new_syndicates

    for system, cartel in pairs(t.systems) do
        if t.cartels[cartel] == nil then t.systems[system] = nil end
    end
    for cartel in pairs(t.cartels) do
        if not t.systems[cartel] then t.systems[cartel] = cartel end
    end

    t.synced_at = os.time()
    f2t_map_topology_save()
    f2t_map_topology_request_rebuild()

    if not capture.silent then
        cecho(string.format(
            "\n<green>[map]<reset> Topology synced: <white>%d<reset> syndicate(s), <white>%d<reset> cartel(s)\n",
            syndicate_count, cartel_count))
    end
    if capture.callback then capture.callback(true) end
end

-- Trigger entry points ------------------------------------------------------

function f2t_map_topology_capture_cartels_start()
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if not capture.active or capture.phase ~= "cartels" then return false end
    deleteLine()
    capture.seen_start = true
    f2t_map_topology_capture_reset_timer()
    return true
end

function f2t_map_topology_capture_cartels_syndicate(name)
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if not capture.active or capture.phase ~= "cartels" or not capture.seen_start then return false end
    deleteLine()
    capture.current_syndicate = name
    f2t_map_topology_capture_reset_timer()
    return true
end

function f2t_map_topology_capture_cartels_line(line)
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if not capture.active or capture.phase ~= "cartels" or not capture.current_syndicate then return false end
    deleteLine()
    local cartel = line:match("^(.-)%s+%-%s") or line
    cartel = cartel:match("^%s*(.-)%s*$")
    if cartel ~= "" then
        capture.cartels[cartel] = capture.current_syndicate
    end
    f2t_map_topology_capture_reset_timer()
    return true
end

function f2t_map_topology_capture_syndicates_start()
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if not capture.active or capture.phase ~= "syndicates" then return false end
    deleteLine()
    capture.seen_start = true
    f2t_map_topology_capture_reset_timer()
    return true
end

-- Row format: "#1 Name - Owner (Hub Beacon, Distant Beacon) - score ..., N cartels"
function f2t_map_topology_capture_syndicates_line(rest)
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if not capture.active or capture.phase ~= "syndicates" or not capture.seen_start then return false end
    deleteLine()
    local name = rest:match("^(.-)%s+%-%s") or rest
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then
        capture.syndicates[name] = {
            hub_beacon = rest:find("Hub Beacon", 1, true) ~= nil,
            distant_beacon = rest:find("Distant Beacon", 1, true) ~= nil,
        }
    end
    f2t_map_topology_capture_reset_timer()
    return true
end

-- Neither "display cartels" nor "display syndicates" is a single unbroken
-- block — a blank line separates the header from the listing and each
-- syndicate group from the next. None of the other capture triggers above
-- match a blank line, so without this one those blanks print through to the
-- console on every login.
function f2t_map_topology_capture_blank()
    local capture = F2T_MAP_TOPOLOGY_CAPTURE
    if not capture.active then return false end
    deleteLine()
    f2t_map_topology_capture_reset_timer()
    return true
end

f2t_debug_log("[map] Loaded topology_capture.lua")