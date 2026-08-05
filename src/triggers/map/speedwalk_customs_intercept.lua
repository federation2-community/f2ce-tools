if not F2T_SPEEDWALK_ACTIVE then
    return
end

cecho("\n<yellow>[map]<reset> Customs inspection - stopping speedwalk\n")
f2t_debug_log("[map] Customs started, stopping speedwalk to prevent command queue issues")

local saved_destination = F2T_SPEEDWALK_DESTINATION_ROOM_ID
local saved_owner = F2T_SPEEDWALK_OWNER
local saved_callback = F2T_SPEEDWALK_ON_INTERRUPT

local auto_resume = false
if saved_callback then
    local success, result = pcall(saved_callback, "customs")
    if success then
        if result and result.auto_resume then
            auto_resume = true
            f2t_debug_log("[map] Owner requested auto-resume after customs")
        end
    else
        f2t_debug_log("[map] Callback error during customs: %s", tostring(result))
        auto_resume = true
    end
else
    auto_resume = true
    f2t_debug_log("[map] Standalone navigation, will auto-resume after customs")
end

if saved_destination and auto_resume then
    -- Block owners' nav-complete checks from treating the stop below as a
    -- real user cancel until the recovery navigate is issued (or abandoned).
    F2T_SPEEDWALK_CUSTOMS_PENDING = true
end

f2t_map_speedwalk_stop()

if saved_destination and auto_resume then
    f2t_debug_log("[map] Saved destination %d, will attempt recovery after customs", saved_destination)

    tempTimer(1.0, function()
        f2t_debug_log("[map] Customs complete, issuing look to get current location")
        send("look")

        tempTimer(1.0, function()
            local current_room = F2T_MAP_CURRENT_ROOM_ID

            if not current_room then
                cecho("\n<yellow>[map]<reset> Cannot determine current location after customs\n")
                f2t_debug_log("[map] No current room ID after customs, cannot resume")
                F2T_SPEEDWALK_CUSTOMS_PENDING = false
                -- The gmcp.room.info event that would normally prompt the owner's
                -- nav-complete check already fired and was blocked while pending
                -- was still true. Re-raise it now so the owner re-evaluates
                -- (falling back to its "unknown result" handling) instead of
                -- stalling silently forever.
                raiseEvent("gmcp.room.info")
                return
            end

            if current_room == saved_destination then
                f2t_debug_log("[map] Already at destination %d after customs", saved_destination)
                F2T_SPEEDWALK_LAST_RESULT = "completed"
                F2T_SPEEDWALK_CUSTOMS_PENDING = false
                raiseEvent("gmcp.room.info")
                return
            end

            f2t_debug_log("[map] Resuming navigation from room %d to %d", current_room, saved_destination)
            cecho("\n<yellow>[map]<reset> Resuming navigation after customs...\n")

            if saved_owner and saved_callback then
                f2t_map_set_nav_owner(saved_owner, saved_callback)
                f2t_debug_log("[map] Ownership restored for post-customs recovery: %s", saved_owner)
            end

            F2T_SPEEDWALK_CUSTOMS_PENDING = false
            f2t_map_navigate(tostring(saved_destination))
        end)
    end)
end
