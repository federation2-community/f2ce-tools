-- "X is in the Y system in the Z cartel of the W syndicate." - three model
-- facts in one line, worth learning whether or not a lookup asked for it.
local system_name    = matches[2]
local cartel_name    = matches[3]
local syndicate_name = matches[4]

if f2t_map_topology_learn then
    f2t_map_topology_commit(f2t_map_topology_learn(system_name, cartel_name, syndicate_name))
end

if not F2T_MAP_WHEREIS_CAPTURE or not F2T_MAP_WHEREIS_CAPTURE.active then
    return
end

deleteLine()

f2t_map_whereis_capture_complete(system_name, cartel_name, syndicate_name)
