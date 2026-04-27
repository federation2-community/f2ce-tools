-- @patterns:
--   - pattern: ^(?:(?i:tb|tell)\s+(\w+)\s+(.+)|(?:(?i:com|comm|say))\s+(.*)|([''"]{1,2})\s*(.*))$

local speaker = gmcp.char.vitals.name

send(matches[1], false)

if matches[2] and matches[2] ~= "" then
    -- Tell/TB: matches[2]=recipient, matches[3]=message
    -- Capitalize first letter so it matches the who-list key (Lua table keys are case-sensitive)
    local recipient = matches[2]:sub(1,1):upper() .. matches[2]:sub(2)
    -- Stage the tell; chatInbound confirms it via the "hum" response so invalid targets are dropped
    UI.chat.pending_tell = { from = recipient, msg = matches[3] or "" }
else
    -- Detect say vs com/comm vs quote shortcut
    local cmd  = matches[1]:lower():match("^%S+")
    local text = (matches[4] and matches[4] ~= "" and matches[4]) or (matches[6] or "")
    -- quote shortcut ('/"): treat as say; "com" and "comm" are com
    if cmd == "say" or (matches[5] and matches[5] ~= "") then
        ui_chat_add("self_say", speaker, text)
    else
        ui_chat_add("self_com", speaker, text)
    end
end
