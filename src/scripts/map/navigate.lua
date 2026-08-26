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
--                   fall back to the game's own `whereis` for the next hop
--                   (and to auto-exploring the destination system once
--                   whereis runs out of hops to suggest) rather than just
--                   failing. Off by default: many callers pass room ids/
--                   hashes rather than real place names, for which asking
--                   `whereis` wouldn't make sense.

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
            f2t_map_navigate_whereis_fallback(destination, opts)
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

-- ── Whereis-guided fallback ──────────────────────────────────────────────────
-- getPath() only knows rooms/exits this map has actually recorded. A known,
-- valid destination can still be unreachable through it purely because
-- nobody has walked (and thus mapped) the connecting stretch yet - Fed2
-- planets sit arbitrarily deep behind their system's link room, and that
-- depth isn't explored for its own sake. Rather than surface that as a dead
-- end, ask the game's own `whereis` for the next hop and follow it: it knows
-- the legal jump graph regardless of what our map has recorded. Once whereis
-- runs out of hops to suggest (you're in the right system, just not at the
-- exact room), fall back to auto-exploring that system to fill the gap.
-- Bounded by hop count so a stuck/looping suggestion can't spin forever.

local F2T_MAP_WHEREIS_FALLBACK_MAX_HOPS = 8

function f2t_map_navigate_whereis_fallback(destination, opts)
    opts = opts or {}
    local hop_count = (opts.whereis_hops or 0) + 1
    if hop_count > F2T_MAP_WHEREIS_FALLBACK_MAX_HOPS then
        cecho("\n<red>[map]<reset> No path found to destination (gave up chaining whereis hops)\n")
        if opts.on_result then opts.on_result(false) end
        return
    end
    cecho(string.format(
        "\n<dim_grey>[map] No mapped route yet - checking whereis for the next step toward '%s'...<reset>\n",
        destination))
    f2t_map_whereis_lookup(destination, function(system_name, route_command)
        if not system_name then
            cecho("\n<red>[map]<reset> No path found to destination\n")
            if opts.on_result then opts.on_result(false) end
            return
        end
        if route_command and route_command ~= "" then
            f2t_map_navigate_follow_whereis_hop(destination, route_command, opts, hop_count)
        else
            f2t_map_navigate_explore_hint(destination, {kind = "system", name = system_name},
                "No path found to destination", opts)
        end
    end)
end

-- jump/j only works from a link-flagged room ("You jump up and down, but
-- nothing happens." is the game's own response to trying it anywhere else).
-- whereis's suggested command assumes you're already standing in one, but
-- the fallback can trigger from anywhere in the system's space area. Get to
-- the current system's link room first using the ordinary, already-reliable
-- local map (never whereis - that stretch is exactly what the map already
-- knows) before acting on the hint.
function f2t_map_navigate_ensure_at_link_room(on_ready)
    local current_room = F2T_MAP_CURRENT_ROOM_ID
    if current_room and f2t_map_room_has_flag(current_room, "link") then
        on_ready(true)
        return
    end
    local current_system = f2t_get_current_system()
    local link_room = current_system and f2t_map_find_link_room_in_system(current_system)
    if not link_room or not roomExists(link_room) or link_room == current_room then
        on_ready(false)
        return
    end
    cecho("\n<dim_grey>[map] Moving to this system's link room before jumping...<reset>\n")
    if not f2t_map_navigate(tostring(link_room)) then
        on_ready(false)
        return
    end
    local function poll()
        if F2T_SPEEDWALK_ACTIVE then
            tempTimer(0.5, poll)
            return
        end
        on_ready(F2T_SPEEDWALK_LAST_RESULT == "completed" and F2T_MAP_CURRENT_ROOM_ID == link_room)
    end
    tempTimer(0.5, poll)
end

function f2t_map_navigate_follow_whereis_hop(destination, route_command, opts, hop_count)
    f2t_map_navigate_ensure_at_link_room(function(ready)
        if not ready then
            cecho("\n<red>[map]<reset> Couldn't reach a link room to act on whereis's suggestion, stopping\n")
            if opts.on_result then opts.on_result(false) end
            return
        end
        local room_before = F2T_MAP_CURRENT_ROOM_ID
        cecho(string.format("\n<yellow>[map]<reset> Following whereis: <white>%s<reset>\n", route_command))
        send(route_command)
        local timeout_seconds = f2t_settings_get("map", "speedwalk_timeout") or 3
        tempTimer(timeout_seconds, function()
            if F2T_MAP_CURRENT_ROOM_ID == room_before then
                cecho("\n<red>[map]<reset> Whereis-guided move didn't change location, stopping\n")
                if opts.on_result then opts.on_result(false) end
                return
            end
            local result = f2t_map_navigate(destination, {
                suppress_hint             = true,
                compensate_incomplete_map = true,
                whereis_hops              = hop_count,
                on_result                 = opts.on_result,
            })
            if result ~= nil and opts.on_result then opts.on_result(result == true) end
        end)
    end)
end
