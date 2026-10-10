if not F2T_SPEEDWALK_ACTIVE then
    return
end

f2t_debug_log("[map] Speedwalk interrupted: out of fuel")
cecho("\n<yellow>[map]<reset> Speedwalk interrupted - out of fuel\n")

if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
    killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    f2t_debug_log("[map] Cancelled movement verification timeout")
end

F2T_SPEEDWALK_WAITING_FOR_MOVE = false

tempTimer(1.5, function()
    if F2T_SPEEDWALK_ACTIVE then
        f2t_debug_log("[map] Attempting to resume speedwalk after refuel")
        cecho("\n<green>[map]<reset> Resuming speedwalk after refuel...\n")

        F2T_SPEEDWALK_WAITING_FOR_MOVE = true
        F2T_SPEEDWALK_ROOM_BEFORE_MOVE = F2T_MAP_CURRENT_ROOM_ID

        local timeout_seconds = f2t_settings_get("map", "speedwalk_timeout")
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = tempTimer(timeout_seconds, function()
            f2t_map_speedwalk_on_move_timeout()
        end)

        f2t_debug_log("[map] Movement verification restarted (timeout %ds)", timeout_seconds)
        send(F2T_SPEEDWALK_LAST_COMMAND)
    end
end)
