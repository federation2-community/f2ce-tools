-- f2ce-tools map — GMCP event handler registration (ported from map_events.lua)

local success, handler_id = pcall(registerAnonymousEventHandler, "gmcp.room.info", "f2t_map_handle_gmcp_room")

if success and handler_id then
    f2t_debug_log("[map] Registered GMCP event handler for gmcp.room.info (ID: %s)", tostring(handler_id))
else
    f2t_debug_log("[map] WARNING: Failed to register GMCP event handler: %s", tostring(handler_id))
end

-- Startup topology sync
--
-- Once per login, re-ground the jump model (cartel->syndicate groupings and
-- syndicate beacon builds) with a single "display cartels" / "display
-- syndicates" pass, so speedwalk jump planning is correct from the first
-- jump even though galaxy politics drift between sessions.
--
-- Runs in every startup mode, including Minimal: it's a plain GMCP handler
-- that only sends game commands (swallowed by capture triggers, opts.silent),
-- needing no map pane or mapper widget.
--
-- Gated to fire once per connection, keyed off gmcp.char.vitals with a flag
-- that re-arms on disconnect. The sync is deferred a few seconds so its
-- commands never land mid-login.
local topology_startup_synced = false

local function f2t_map_startup_topology_sync()
    if topology_startup_synced then return end
    local name = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end   -- not logged in yet; wait for vitals
    topology_startup_synced = true
    tempTimer(3, function()
        if type(f2t_map_topology_sync) == "function" then
            f2t_map_topology_sync(nil, { silent = true })
        end
    end)
end

registerAnonymousEventHandler("gmcp.char.vitals", f2t_map_startup_topology_sync)

-- gmcp.char.vitals may already have fired before this script (re)loaded — e.g.
-- a dev-mode rebuild while connected. gmcp.char survives that, so check now too.
f2t_map_startup_topology_sync()

-- Re-arm so the next login after a reconnect syncs once again.
registerAnonymousEventHandler("sysDisconnectionEvent", function()
    topology_startup_synced = false
end)