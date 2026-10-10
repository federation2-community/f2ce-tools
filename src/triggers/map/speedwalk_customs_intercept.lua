if not F2T_SPEEDWALK_ACTIVE then
    return
end

cecho("\n<yellow>[map]<reset> Customs inspection - stopping speedwalk\n")
f2t_debug_log("[map] Customs started, stopping speedwalk to prevent command queue issues")

if f2tNav.holdForCustoms() then
    return
end

-- A walk no trip owns (an exploration's own legs): resume it toward the same room.
local saved_destination = F2T_SPEEDWALK_DESTINATION_ROOM_ID
if saved_destination then
    -- Keeps the explorer from treating the stop below as a user cancel
    F2T_SPEEDWALK_CUSTOMS_PENDING = true
end

f2t_map_speedwalk_stop()

if saved_destination then
    f2t_debug_log("[map] Saved destination %d, will attempt recovery after customs", saved_destination)

    tempTimer(1.0, function()
        send("look")

        tempTimer(1.0, function()
            F2T_SPEEDWALK_CUSTOMS_PENDING = false
            local current_room = F2T_MAP_CURRENT_ROOM_ID
            if not current_room then
                cecho("\n<yellow>[map]<reset> Cannot determine current location after customs\n")
                raiseEvent("gmcp.room.info")
                return
            end
            if current_room == saved_destination then
                F2T_SPEEDWALK_LAST_RESULT = "completed"
                raiseEvent("gmcp.room.info")
                return
            end
            cecho("\n<yellow>[map]<reset> Resuming navigation after customs...\n")
            f2t_map_walk_room(saved_destination)
        end)
    end)
end
