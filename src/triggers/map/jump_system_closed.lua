-- "I'm afraid the X system is closed to visitors at the moment." Closure is a
-- property of the destination's space map that any traveller but its owner
-- shares, and it is checked when the jump executes, not when the destination
-- lists are built - so an ordinary nav can be routed straight into one.
-- Record it so replans route around it, then unwind the waiting movement.
local closed_system = matches[2]

if f2t_map_topology_mark_closed(closed_system) then
    f2t_map_topology_commit(true)
end

local room_id = F2T_MAP_CURRENT_ROOM_ID
if room_id and roomExists(room_id) then
    f2t_map_jump_drop_exit(room_id, closed_system)
end

if not f2t_map_jump_abort_after_refusal(closed_system, "closed to visitors") then
    cecho(string.format("\n<yellow>[map]<reset> System '%s' is closed to visitors\n", closed_system))
end
