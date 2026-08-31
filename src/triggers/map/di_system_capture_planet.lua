-- "Planet, X system, Y cartel[, Z syndicate]" - the listing names the
-- system's grouping on every planet line, so feed it to the model too.
local planet_line = matches[2]

local system_name, cartel_name = planet_line:match("^[^,]+,%s*(.-) system,%s*(.-) cartel")
if system_name and f2t_map_topology_learn then
    local syndicate_name = planet_line:match(" cartel,%s*(.-) syndicate%s*$")
    f2t_map_topology_commit(f2t_map_topology_learn(system_name, cartel_name, syndicate_name))
end

if not F2T_MAP_DI_SYSTEM_CAPTURE or not F2T_MAP_DI_SYSTEM_CAPTURE.active then
    return
end

deleteLine()

table.insert(F2T_MAP_DI_SYSTEM_CAPTURE.planet_names, planet_line)

f2t_debug_log("[map-di-system] Captured planet line: %s", planet_line)

f2t_map_di_system_reset_timer()
