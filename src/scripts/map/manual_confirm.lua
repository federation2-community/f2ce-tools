-- f2ce-tools map — confirmation system (ported from map_manual_confirm.lua)

F2T_MAP_MANUAL_PENDING_ACTION = nil

function f2t_map_manual_request_confirmation(action, callback, data)
    local confirm_enabled = f2t_settings_get("map", "map_manual_confirm")
    if not confirm_enabled then
        callback(data); return false
    end
    if F2T_MAP_MANUAL_PENDING_ACTION then
        if F2T_MAP_MANUAL_PENDING_ACTION.timer_id then
            killTimer(F2T_MAP_MANUAL_PENDING_ACTION.timer_id)
        end
        cecho("\n<yellow>[map]<reset> Previous confirmation cancelled\n")
    end
    local timer_id = tempTimer(30, function()
        if F2T_MAP_MANUAL_PENDING_ACTION then
            cecho("\n<red>[map]<reset> Confirmation expired\n")
            F2T_MAP_MANUAL_PENDING_ACTION = nil
        end
    end)
    F2T_MAP_MANUAL_PENDING_ACTION = {
        action = action, callback = callback, data = data,
        timer_id = timer_id, expires_at = os.time() + 30,
    }
    cecho(string.format("\n<yellow>[map]<reset> Confirm action: <white>%s<reset>\n", action))
    cecho("\n<dim_grey>Use 'map confirm' within 30 seconds to proceed<reset>\n")
    return true
end

function f2t_map_manual_confirm()
    if not F2T_MAP_MANUAL_PENDING_ACTION then
        cecho("\n<red>[map]<reset> No pending action to confirm\n")
        cecho("\n<dim_grey>Run a destructive command first<reset>\n")
        return false
    end
    if os.time() > F2T_MAP_MANUAL_PENDING_ACTION.expires_at then
        cecho("\n<red>[map]<reset> Confirmation expired\n")
        F2T_MAP_MANUAL_PENDING_ACTION = nil; return false
    end
    local action   = F2T_MAP_MANUAL_PENDING_ACTION.action
    local callback = F2T_MAP_MANUAL_PENDING_ACTION.callback
    local data     = F2T_MAP_MANUAL_PENDING_ACTION.data
    if F2T_MAP_MANUAL_PENDING_ACTION.timer_id then
        killTimer(F2T_MAP_MANUAL_PENDING_ACTION.timer_id)
    end
    F2T_MAP_MANUAL_PENDING_ACTION = nil
    cecho(string.format("\n<green>[map]<reset> Confirmed: <white>%s<reset>\n", action))
    callback(data)
    return true
end

function f2t_map_manual_cancel_confirmation()
    if not F2T_MAP_MANUAL_PENDING_ACTION then
        cecho("\n<yellow>[map]<reset> No pending confirmation to cancel\n")
        return false
    end
    local action = F2T_MAP_MANUAL_PENDING_ACTION.action
    if F2T_MAP_MANUAL_PENDING_ACTION.timer_id then
        killTimer(F2T_MAP_MANUAL_PENDING_ACTION.timer_id)
    end
    F2T_MAP_MANUAL_PENDING_ACTION = nil
    cecho(string.format("\n<yellow>[map]<reset> Confirmation cancelled: <white>%s<reset>\n", action))
    return true
end
