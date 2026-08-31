-- "Your request to make a hyperspace jump to the X system has been denied
-- because they consider you an undesirable element!" Exile is per-player and
-- is deliberately left visible in the server's jump lists, so nothing but
-- this refusal reveals it. Kept apart from closure for that reason: only
-- actually arriving in the system retires it.
local exiled_system = matches[2]

if f2t_map_topology_mark_exiled(exiled_system) then
    f2t_map_topology_commit(true)
end

local room_id = F2T_MAP_CURRENT_ROOM_ID
if room_id and roomExists(room_id) then
    f2t_map_jump_drop_exit(room_id, exiled_system)
end

if not f2t_map_jump_abort_after_refusal(exiled_system, "barred - you are exiled") then
    cecho(string.format("\n<yellow>[map]<reset> You are exiled from '%s'\n", exiled_system))
end
