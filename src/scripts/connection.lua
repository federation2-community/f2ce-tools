-- fed2-tools — connection state tracking

F2T_CONNECTED = false

function f2t_check_connection()
    local _, _, connected = getConnectionInfo()
    F2T_CONNECTED = connected and true or false
    return F2T_CONNECTED
end

f2t_check_connection()

registerAnonymousEventHandler("sysConnectionEvent", function()
    f2t_check_connection()
    f2t_debug_log("[connection] Connected")
end)

registerAnonymousEventHandler("sysDisconnectionEvent", function()
    f2t_check_connection()
    f2t_debug_log("[connection] Disconnected")
end)
