-- @patterns:
--   - pattern: ^(?:(?i:(com|comm|say))\s+(.*)|(''|'|")\s*(.*))$

local display
local text = ""

if matches[2] ~= "" then
    text = matches[3] or ""
else
    text = matches[5] or ""
end

local speaker = gmcp.char.vitals.name

send(matches[1], false)

-- Self com: green gutter ▎▸ distinguishes from received teal ▎
ui_chat_add("self_com", speaker, text)