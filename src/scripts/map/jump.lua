-- Two layers keep the jump graph correct:
--   1. gmcp.room.info.jumps lists the jump destinations available to you
--      from the link room you are standing in right now: merged into that
--      room's special exits on entry, never used to blank out what's
--      already mapped there. The list is a snapshot of what's offered to
--      you at this moment (rank/standing/permit-gated), not a complete
--      enumeration of every edge that has ever been legal from this room -
--      an edge missing from one snapshot is not proof it's gone, so it's
--      left alone. Only the game's own explicit refusal (see
--      jump_no_direct_link.lua) or a destination room that no longer exists
--      is good enough evidence to remove an edge.
--   2. The same payload feeds the topology model (topology.lua), which
--      derives every OTHER link room's exits so getPath() plans over the
--      legal jump graph galaxy-wide, not just where you last stood.
-- Jump edges are directed (beacon rules are asymmetric), so no reverse exit
-- is ever created by symmetry; the model derives each room's own outgoing
-- set instead.

-- Systems whose interstellar link has refused to let us out at all, as
-- opposed to refusing one destination: [system] = reason. Sol gates every
-- outbound jump on hauler credits, so one refusal condemns the lot, and
-- walking back to the link to try another is fifteen wasted moves.
--
-- Session-scoped on purpose: it is a fact about the commander, not the map,
-- and it stops being true the moment the credits are earned - so it is never
-- saved, and any successful jump out clears it.
F2T_MAP_LINK_BARRED = F2T_MAP_LINK_BARRED or {}

function f2t_map_link_barred(system)
    if not system or system == "" then return nil end
    if F2T_MAP_LINK_BARRED[system] then return F2T_MAP_LINK_BARRED[system] end
    local lowered = string.lower(system)
    for key, reason in pairs(F2T_MAP_LINK_BARRED) do
        if string.lower(key) == lowered then return reason end
    end
    return nil
end

function f2t_map_mark_link_barred(system, reason)
    if not system or system == "" then return end
    F2T_MAP_LINK_BARRED[system] = reason or "the link refused to let you out"
    f2t_debug_log("[map/jump] %s's link is barred to us: %s", system, tostring(reason))
end

function f2t_map_clear_link_barred(system)
    if not system or system == "" then return end
    local lowered = string.lower(system)
    for key in pairs(F2T_MAP_LINK_BARRED) do
        if string.lower(key) == lowered then
            F2T_MAP_LINK_BARRED[key] = nil
            f2t_debug_log("[map/jump] %s's link is open to us again", key)
        end
    end
end

-- getSpecialExits(room_id) is keyed by DESTINATION ROOM NUMBER, with each
-- value a table of command strings leading there — NOT keyed by command
-- text. getSpecialExitsSwap(room_id) is the one keyed by command string
-- (confirmed via direct testing: its keys are the "jump ___" text).
function f2t_map_apply_gmcp_jumps(room_id, jumps)
    if not room_id or not roomExists(room_id) or not jumps then return end
    local existing = getSpecialExitsSwap(room_id) or {}
    local created_count, total = 0, 0
    local missing_dests = {}
    for _, category in ipairs({"inter_syndicate", "intra_syndicate", "local"}) do
        for _, dest_system in ipairs(jumps[category] or {}) do
            total = total + 1
            local command = string.format("jump %s", dest_system)
            local existing_dest = existing[command]
            if existing_dest and roomExists(existing_dest) then
                -- Already mapped and still points somewhere real: leave it.
                created_count = created_count + 1
            else
                if existing_dest then
                    -- Points at a room that's gone - that's actual staleness.
                    removeSpecialExit(room_id, command)
                end
                if f2t_map_create_jump_special_exit(room_id, dest_system) then
                    created_count = created_count + 1
                else
                    table.insert(missing_dests, dest_system)
                end
            end
        end
    end
    if #missing_dests > 0 then
        f2t_debug_log("[map/jump] apply_gmcp_jumps(room=%s): not yet mapped: %s",
            tostring(room_id), table.concat(missing_dests, ", "))
    end
    setRoomUserData(room_id, "fed2_jump_synced_at", tostring(os.time()))
    f2t_debug_log("[map/jump] apply_gmcp_jumps(room=%s): %d/%d special exits from GMCP data",
        tostring(room_id), created_count, total)
end

function f2t_map_process_link_room(room_id, room_data)
    if not room_id or not roomExists(room_id) then return end
    if not room_data or not room_data.flags or not f2t_has_value(room_data.flags, "link") then return end
    if not room_data.jumps then return end
    local system = room_data.system or getRoomUserData(room_id, "fed2_system")
    if not system then return end

    f2t_map_apply_gmcp_jumps(room_id, room_data.jumps)

    local cartel    = room_data.cartel or getRoomUserData(room_id, "fed2_cartel")
    local syndicate = room_data.syndicate
    if not syndicate or syndicate == "" then syndicate = getRoomUserData(room_id, "fed2_syndicate") end
    if f2t_map_topology_apply_gmcp(system, cartel, syndicate, room_data.jumps) then
        f2t_map_topology_request_rebuild()
    end
end

-- Forward exit only: jump legality is directional under beacon rules, so the
-- reverse direction is derived (or not) from the destination's own rules.
function f2t_map_create_jump_special_exit(from_room_id, to_system)
    local to_room_id = f2t_map_find_link_room_in_system(to_system)
    if not to_room_id or to_room_id == from_room_id then return false end
    addSpecialExit(from_room_id, to_room_id, string.format("jump %s", to_system))
    return true
end

function f2t_map_find_link_room_in_system(system)
    if not system or system == "" then return nil end
    local space_area_name = f2t_map_get_system_space_area_actual(system)
    if not space_area_name then return nil end
    local area_id = f2t_map_get_area_id(space_area_name)
    if not area_id then return nil end
    return f2t_map_find_link_room(area_id)
end

-- Drop a "jump <dest>" special exit from a room, whatever case the game used
-- when it named the system back at us.
function f2t_map_jump_drop_exit(room_id, dest_system)
    if not room_id or not roomExists(room_id) then return 0 end
    local wanted = string.lower(string.format("jump %s", dest_system))
    local dropped = 0
    local to_remove = {}
    for command in pairs(getSpecialExitsSwap(room_id) or {}) do
        if type(command) == "string" and string.lower(command) == wanted then
            table.insert(to_remove, command)
        end
    end
    for _, command in ipairs(to_remove) do
        removeSpecialExit(room_id, command)
        dropped = dropped + 1
        f2t_debug_log("[map/jump] Removed refused jump exit '%s' from room %d", command, room_id)
    end
    return dropped
end

-- Common tail for every "the server just refused this jump" trigger: no
-- direct link, system closed, exiled. The edge has already been recorded
-- against the model by the caller; this only unwinds the movement that was
-- waiting on it, so nothing sits out the 3s move timeout and then spends its
-- retry budget re-sending the identical command.
--
-- An explorer blind-jump chain has no destination room id to recompute
-- against, so it skips to its next target instead of replanning.
function f2t_map_jump_abort_after_refusal(dest_system, reason)
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end

    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        local mode = F2T_MAP_EXPLORE_STATE.mode
        local phase = F2T_MAP_EXPLORE_STATE.phase

        -- A travel leg's jump chain. Nothing downstream knows how to recover
        -- one - next_step has no branch for these phases - so a refusal here
        -- leaves the whole exploration active with a target it can never
        -- reach, and every later navigate refuses to start because it thinks
        -- a sweep is running. End the leg.
        if phase == "explore_travel_jumping" or phase == "explore_travel_arriving" then
            cecho(string.format("\n<yellow>[map-explore]<reset> Jump to '%s' refused, giving up on %s\n",
                dest_system, tostring(F2T_MAP_EXPLORE_STATE.travel_target or dest_system)))
            F2T_SPEEDWALK_WAITING_FOR_MOVE = false
            F2T_SPEEDWALK_ACTIVE = false
            f2t_map_explore_travel_finish(false)
            return true
        end
        local jumping_to_cartel = mode == "galaxy" and
            (phase == "arriving_in_cartel" or phase == "jumping_to_cartel")
        local jumping_to_system = (mode == "cartel" or mode == "galaxy") and
            (phase == "arriving_in_system" or phase == "jumping_to_system")

        if jumping_to_cartel or jumping_to_system then
            cecho(string.format("\n<yellow>[map-explore]<reset> Jump to '%s' %s, skipping...\n",
                dest_system, reason))
            F2T_SPEEDWALK_WAITING_FOR_MOVE = false
            F2T_SPEEDWALK_ACTIVE = false
            F2T_MAP_EXPLORE_STATE.phase = nil

            if jumping_to_cartel then
                F2T_MAP_EXPLORE_STATE.galaxy_target_cartel = nil
                tempTimer(0.5, function()
                    if F2T_MAP_EXPLORE_STATE.active and F2T_MAP_EXPLORE_STATE.mode == "galaxy" then
                        f2t_map_explore_galaxy_next_cartel()
                    end
                end)
            else
                F2T_MAP_EXPLORE_STATE.cartel_target_system = nil
                tempTimer(0.5, function()
                    if F2T_MAP_EXPLORE_STATE.active and
                       (F2T_MAP_EXPLORE_STATE.mode == "cartel" or F2T_MAP_EXPLORE_STATE.mode == "galaxy") then
                        f2t_map_explore_cartel_next_system()
                    end
                end)
            end
            return true
        end
    end

    -- Ordinary planned speedwalk: replan now rather than waiting out the
    -- timeout. The edge is already gone from the map, so this is progress and
    -- goes through the refusal budget rather than the blocked-path one.
    if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
        F2T_SPEEDWALK_WAITING_FOR_MOVE = false
        F2T_SPEEDWALK_EXPECTED_ROOM_ID = nil
        F2T_SPEEDWALK_ROOM_BEFORE_MOVE = nil
        f2t_map_speedwalk_handle_refusal()
        return true
    end

    return false
end

f2t_debug_log("[map-special] Special navigation system initialized")
