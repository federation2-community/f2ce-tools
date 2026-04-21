-- @patterns:
--   - pattern: ^Your comm unit signals a tight beam message from (\w+), "(.+)"$
--     type: regex
--   - pattern: ^Your comm unit crackles with a message from (\w+), "(.+)"$
--     type: regex
--   - pattern: ^(\w+) says, "(.+)"$
--     type: regex
--   - pattern: ^You say, "(.+)"$
--     type: regex
--   - pattern: ^There is a brief hum from your comm unit\.$
--     type: regex

local hide = f2t_settings_get("ui", "hide_chat_messages")

-- "Hum" is the tb-send confirmation; no message content to route, just suppress.
if line:match("^There is a brief hum from your comm unit") then
    if hide then deleteLine() end
    return
end

-- Your own say echo: alias already recorded it as self_com, just suppress.
if line:match("^You say,") then
    if hide then deleteLine() end
    return
end

local mtype, name, msg

if line:match("^Your comm unit signals") then
    -- Inbound tight beam tell: "Your comm unit signals a tight beam message from Name, "msg""
    mtype = "tell_in"
    name  = matches[2]
    msg   = matches[3]
elseif line:match("^Your comm unit crackles") then
    -- Inbound com: "Your comm unit crackles with a message from Name, "msg""
    mtype = "com"
    name  = matches[2]
    msg   = matches[3]
else
    -- Inbound say: "Name says, "msg""
    mtype = "say"
    name  = matches[2]
    msg   = matches[3]
end

ui_chat_add(mtype, name, msg)

if hide then deleteLine() end
