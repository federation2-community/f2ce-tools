-- f2ce-tools map — navigation (ported from map_navigate.lua)
--
-- f2t_map_navigate(destination, opts) is the shared speedwalk entry point.
-- opts (all optional):
--   interactive   - show a confirm dialog before auto-exploring an unmapped
--                   destination (used by the `nav` alias; a typed name could
--                   be a typo). Automated callers omit this and self-heal
--                   immediately instead.
--   on_result(ok) - fired once, asynchronously, with the final outcome, but
--                   only on the hint-driven (auto-explore) or whereis-fallback
--                   path. Sync true/false returns already tell the caller
--                   everything.
--   suppress_hint - skip hint handling entirely, behave like plain failure.
--   compensate_incomplete_map - when getPath() finds no route through
--                   locally-mapped rooms to an otherwise-known destination,
--                   fall back to ordinary local pathing toward the
--                   destination system's link room, then to auto-exploring
--                   the remaining gap (asking `whereis` only as a last
--                   resort, for the system name) rather than just failing.
--                   Off by default: many callers pass room ids/hashes rather
--                   than real place names, for which asking `whereis`
--                   wouldn't make sense.

function f2t_map_navigate(destination, opts)
    opts = opts or {}
    f2t_debug_log("[map] f2t_map_navigate destination is '%s'", destination)
    if not destination or destination == "" then
        cecho("\n<red>[map]<reset> No destination specified\n"); return false
    end
    local target_id, error_msg, hint = f2t_map_resolve_location(destination)
    if not target_id then
        -- Never launch a new hint-driven explore while one is already active -
        -- it would stomp the single global F2T_MAP_EXPLORE_STATE mid-sweep.
        local exploring_already = F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active
        if hint and not opts.suppress_hint and not exploring_already then
            f2t_map_navigate_handle_hint(destination, hint, error_msg, opts)
            return nil
        end
        cecho(string.format("\n<red>[map]<reset> %s\n", error_msg or "Could not find destination")); return false
    end
    if not f2t_map_ensure_current_location(f2t_map_navigate, {destination, opts}) then
        return false
    end
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    if current_room_id == target_id then
        cecho("\n<green>[map]<reset> You are already at the destination\n")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return true
    end
    local success = getPath(current_room_id, target_id)
    if not success then
        if opts.compensate_incomplete_map then
            f2t_map_navigate_compensate(destination, target_id, opts)
            return nil
        end
        local current_area = getRoomArea(current_room_id)
        local target_area  = getRoomArea(target_id)
        cecho("\n<red>[map]<reset> No path found to destination\n")
        cecho(string.format("\n<dim_grey>Current: Room %d (%s)<reset>\n",
            current_room_id, current_area and getRoomAreaName(current_area) or "unknown"))
        cecho(string.format("<dim_grey>Target: Room %d (%s)<reset>\n",
            target_id, target_area and getRoomAreaName(target_area) or "unknown"))
        if current_area ~= target_area then
            cecho("\n<yellow>[map]<reset> Rooms are in different areas - make sure areas are connected\n")
        end
        return false
    end
    if #speedWalkDir == 0 then
        cecho("\n<green>[map]<reset> Already at destination\n")
        F2T_SPEEDWALK_LAST_RESULT = "completed"
        return true
    end
    doSpeedWalk()
    return true
end

-- ── Hint handling ────────────────────────────────────────────────────────────
-- resolve_location couldn't find the destination outright, but returned a hint
-- worth acting on: a locally-known-but-incomplete planet/system, or a bare
-- name worth asking the game's `whereis` about before giving up on it.

function f2t_map_navigate_handle_hint(destination, hint, error_msg, opts)
    if hint.kind == "whereis_pending" then
        cecho(string.format("\n<dim_grey>[map] Checking whereis for '%s'...<reset>\n", hint.name))
        f2t_map_whereis_lookup(hint.name, function(system_name)
            if system_name then
                local system_hint = {kind = "system", name = system_name}
                f2t_map_navigate_handle_hint(destination, system_hint, error_msg, opts)
            else
                cecho(string.format("\n<red>[map]<reset> %s\n", error_msg))
                if opts.on_result then opts.on_result(false) end
            end
        end)
        return
    end

    if opts.interactive then
        f2tShowNavHintConfirm(destination, hint, error_msg,
            function() f2t_map_navigate_explore_hint(destination, hint, opts) end,
            function()
                cecho(string.format("\n<red>[map]<reset> %s\n", error_msg))
                if opts.on_result then opts.on_result(false) end
            end)
        return
    end

    f2t_map_navigate_explore_hint(destination, hint, opts)
end

function f2t_map_navigate_explore_hint(destination, hint, opts)
    local settled = false
    local timer_id

    local function finish(success)
        if settled then return end
        settled = true
        if timer_id then killTimer(timer_id); timer_id = nil end
        if opts.on_result then opts.on_result(success) end
    end

    local function on_complete()
        local result = f2t_map_navigate(destination, {
            suppress_hint = true,
            compensate_incomplete_map = opts.compensate_incomplete_map,
        })
        finish(result == true)
    end

    local started = false
    if hint.kind == "planet" then
        started = f2t_map_explore_planet_start("brief", hint.name, on_complete, {hint.flag})
    elseif hint.kind == "system" then
        started = f2t_map_explore_system_start("brief", hint.name, on_complete)
    end

    if not started then
        finish(false)
        return
    end

    timer_id = tempTimer(180, function() finish(false) end)
end

-- ── Compensating for an incomplete map ──────────────────────────────────────
-- getPath() only knows rooms/exits this map has actually recorded, and it's
-- all-or-nothing: it won't hand back a route that gets partway there even
-- when most of the journey - the jump chain into the destination's system -
-- is already well mapped and has worked before. So always try ordinary local
-- pathing to the destination system's link room first; that's the reliable
-- part, and it's just getPath()/doSpeedWalk doing their normal job, nothing
-- game-text-driven about it. `whereis` only enters the picture as a last
-- resort, and only ever to learn the destination's system NAME - never to
-- have its suggested command text parsed or sent. That text isn't meant to
-- be executed verbatim (this game has no ";"-style command chaining, client
-- or server side) and once the system name is known, ordinary local pathing
-- to that system's link room already does the job more reliably anyway.

function f2t_map_navigate_compensate(destination, target_id, opts)
    opts = opts or {}
    local target_area_id = target_id and roomExists(target_id) and getRoomArea(target_id)
    local target_system   = target_area_id and getAreaUserData(target_area_id, "fed2_system")
    if target_system and target_system ~= "" then
        f2t_map_navigate_reach_system(destination, target_id, target_system, opts)
        return
    end
    f2t_map_navigate_whereis_for_system(destination, target_id, opts)
end

-- Ordinary getPath()/speedwalk to a known system's link room. If we're
-- already standing at it, the gap is purely the ground-level stretch beyond
-- it (a planet's shuttlepad, reached via "board" from its orbit - system
-- exploration alone never lands), so hand that straight to the same
-- confirm-then-explore flow used for any unmapped destination
-- (f2t_map_navigate_handle_hint), scoped to just that planet's own area
-- rather than sweeping the whole system.
function f2t_map_navigate_reach_system(destination, target_id, system_name, opts)
    local current_room_id = F2T_MAP_CURRENT_ROOM_ID
    local link_room = f2t_map_find_link_room_in_system(system_name)
    if link_room and link_room == current_room_id then
        local hint = f2t_map_navigate_target_hint(target_id, system_name)
        f2t_map_navigate_handle_hint(destination, hint, "No path found to destination", opts)
        return
    end
    if not link_room or not roomExists(link_room) or not getPath(current_room_id, link_room) then
        f2t_map_navigate_whereis_for_system(destination, target_id, opts)
        return
    end
    cecho(string.format(
        "\n<dim_grey>[map] No mapped route to the exact destination yet - heading to %s's link room first...<reset>\n",
        system_name))
    doSpeedWalk()
    local function poll()
        if F2T_SPEEDWALK_ACTIVE then
            tempTimer(0.5, poll)
            return
        end
        if F2T_SPEEDWALK_LAST_RESULT ~= "completed" then
            cecho("\n<red>[map]<reset> No path found to destination\n")
            if opts.on_result then opts.on_result(false) end
            return
        end
        local result = f2t_map_navigate(destination, {
            suppress_hint             = true,
            compensate_incomplete_map = true,
            on_result                 = opts.on_result,
        })
        if result ~= nil and opts.on_result then opts.on_result(result == true) end
    end
    tempTimer(0.5, poll)
end

-- Last resort: the destination's system isn't known locally at all, or
-- local pathing can't reach its link room through the mapped jump graph.
-- Ask whereis purely for the system's name, then hand off to the same
-- confirm-then-explore flow as any other unmapped destination.
function f2t_map_navigate_whereis_for_system(destination, target_id, opts)
    cecho(string.format(
        "\n<dim_grey>[map] No mapped route yet - checking whereis for '%s'...<reset>\n", destination))
    f2t_map_whereis_lookup(destination, function(system_name)
        if not system_name then
            cecho("\n<red>[map]<reset> No path found to destination\n")
            if opts.on_result then opts.on_result(false) end
            return
        end
        local hint = f2t_map_navigate_target_hint(target_id, system_name)
        f2t_map_navigate_handle_hint(destination, hint, "No path found to destination", opts)
    end)
end

-- Picks the right scope of exploration to fill the gap: the target's own
-- planet-surface area when that's distinct from the system's space area (a
-- planet's shuttlepad, say), or the system space area itself when the target
-- lives there directly (an orbit room, or the link room).
function f2t_map_navigate_target_hint(target_id, system_name)
    local target_area_id   = target_id and roomExists(target_id) and getRoomArea(target_id)
    local target_area_name = target_area_id and getRoomAreaName(target_area_id)
    local space_area_name  = f2t_map_get_system_space_area_actual(system_name)
    if target_area_name and target_area_name ~= space_area_name then
        return {kind = "planet", name = target_area_name, flag = F2T_MAP_PLANET_NAV_DEFAULT or "shuttlepad"}
    end
    return {kind = "system", name = system_name}
end
