-- @patterns:
--   - pattern: ^(?i:tb|tell)\s+(\w+)\s+(.+)$

local speaker = gmcp.char.vitals.name

send(matches[1], false)

-- Self tell: orange gutter ▎▸; from field holds the RECIPIENT for "You → Recipient" format
ui_chat_add("self_tell", matches[2], matches[3])