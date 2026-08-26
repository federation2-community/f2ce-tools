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

    local cartel = room_data.cartel or getRoomUserData(room_id, "fed2_cartel")
    if f2t_map_topology_apply_gmcp(system, cartel, room_data.jumps) then
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
    return f2t_map_find_room_with_flag(area_id, "link")
end

f2t_debug_log("[map-special] Special navigation system initialized")
