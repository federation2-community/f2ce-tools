-- @patterns:
--   - pattern: ^(?:(?i:tb|tell)\s+(\w+)\s+(.+)|(?:(?i:com|comm|say))\s+(.*)|([''"]{1,2})\s*(.*))$

local speaker = gmcp.char.vitals.name

send(matches[1], false)

if matches[2] and matches[2] ~= "" then
    -- Tell/TB: matches[2]=recipient, matches[3]=message
    ui_chat_add("self_tell", matches[2], matches[3] or "")
else
    -- Com/Say or quote shortcut: message in matches[4] or matches[6]
    local text = (matches[4] ~= "" and matches[4]) or (matches[6] or "")
    ui_chat_add("self_com", speaker, text)
end
