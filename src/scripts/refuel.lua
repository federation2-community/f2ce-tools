-- f2ce-tools refuel — settings registration
--
-- Legacy stored the threshold under the "shared" namespace; the new layout gives
-- refuel its own namespace and settings tab.  An explicit "enabled" toggle makes
-- the feature optional (consistent with map/factory) and gates both the
-- GMCP-driven top-up and the emergency out-of-fuel trigger.

f2t_settings_register("refuel", "enabled", {
    tab         = "F2CE-Tools/Misc",
    order       = 2,
    label       = "Auto refuel",
    description = "Enable automatic refueling at shuttlepads and emergency refueling",
    default     = true,
})

f2t_settings_register("refuel", "threshold", {
    label       = "Refuel threshold (%)",
    description = "Auto-refuel when fuel is at or below this % while at a shuttlepad (0 = never auto-refuel)",
    default     = 50,
    min = 0, max = 99,
})

-- f2ce-tools refuel — automatic refueling
--
-- Listens for GMCP room changes (more reliable than a prompt trigger).  When the
-- player arrives at a shuttlepad and fuel is at/below the configured threshold,
-- "buy fuel" is sent.  Disabled entirely when refuel/enabled is off or the
-- threshold is 0.  Emergency (out-of-fuel) refueling is handled by the trigger.

F2T_REFUEL_ENABLED = f2t_settings_get("refuel", "enabled")

function f2t_refuel_on_room_change()
    if not f2t_settings_get("refuel", "enabled") then return end

    local threshold = f2t_settings_get("refuel", "threshold") or 0
    if threshold <= 0 then return end

    local room_info = gmcp.room and gmcp.room.info
    if not room_info or not room_info.flags then return end
    if not f2t_has_value(room_info.flags, "shuttlepad") then return end

    f2t_debug_log("[refuel] At shuttlepad, checking fuel level")

    local fuel = gmcp.char and gmcp.char.ship and gmcp.char.ship.fuel
    if not fuel or not fuel.cur or not fuel.max then
        f2t_debug_log("[refuel] Fuel data not available")
        return
    end

    local fuel_percent = math.floor((fuel.cur / fuel.max) * 100 + 0.5)

    if fuel_percent <= threshold then
        f2t_debug_log("[refuel] Fuel at %d%% (threshold %d%%), buying fuel", fuel_percent, threshold)
        send("buy fuel", false)
    else
        f2t_debug_log("[refuel] Fuel at %d%% (threshold %d%%), no refuel needed", fuel_percent, threshold)
    end
end

-- (Re)register the GMCP handler, replacing any previous registration on reload.
if F2T_REFUEL_HANDLER_ID then
    killAnonymousEventHandler(F2T_REFUEL_HANDLER_ID)
end
F2T_REFUEL_HANDLER_ID = registerAnonymousEventHandler("gmcp.room.info", "f2t_refuel_on_room_change")

f2t_debug_log("[refuel] Initialized (enabled=%s, threshold=%s%%)",
    tostring(F2T_REFUEL_ENABLED), tostring(f2t_settings_get("refuel", "threshold")))