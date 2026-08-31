-- "There isn't a direct link to X from here." The map believed this edge was
-- legal, so the model is stale (usually a membership change). Record the
-- refusal against the model rather than only against the room - a room-only
-- removal is undone by the next rebuild, which re-derives from the same
-- unchanged facts - then unwind the movement waiting on it.
local dest = matches[2]
local room_id = F2T_MAP_CURRENT_ROOM_ID

if room_id and roomExists(room_id) then
    f2t_map_jump_drop_exit(room_id, dest)
end

local from_system = f2t_get_current_system()
if from_system and f2t_map_topology_mark_refused(from_system, dest) then
    f2t_map_topology_commit(true)
end

if f2t_map_topology_auto_sync then
    f2t_map_topology_auto_sync(string.format("jump to %s refused", dest))
end

f2t_map_jump_abort_after_refusal(dest, "refused")
