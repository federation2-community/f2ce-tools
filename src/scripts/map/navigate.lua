-- f2ce-tools map — navigation (ported from map_navigate.lua)
--
-- f2t_map_navigate(destination, opts) is the shared speedwalk entry point.
-- opts (all optional):
--   interactive   - show a confirm dialog before auto-exploring an unmapped
--                   destination (used by the `nav` alias; a typed name could
--                   be a typo). Automated callers omit this and self-heal
--                   immediately instead.
--   on_result(ok) - fired once, asynchronously, with the final outcome, but
--                   only on the hint-driven (auto-explore) path. Sync true/
--                   false returns already tell the caller everything.
--   suppress_hint - skip hint handling entirely, behave like plain failure.

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
        local result = f2t_map_navigate(destination, {suppress_hint = true})
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
