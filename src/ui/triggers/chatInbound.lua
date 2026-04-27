-- @patterns:
--   - pattern: ^Your comm unit signals a tight beam message from (\w+), "(.+)$
--     type: regex
--   - pattern: ^Your comm unit crackles with a message from (\w+), "(.+)$
--     type: regex
--   - pattern: ^(\w+) (says|asks), "(.+)$
--     type: regex
--   - pattern: ^There is a brief hum from your comm unit\.$
--     type: regex
--   - pattern: ^\w+ doesn't seem to be around at the moment\.$
--     type: regex

-- "Hum" is the tb-send confirmation; commit the staged outgoing tell to chat history.
if line:match("^There is a brief hum from your comm unit") then
    local pt = UI.chat.pending_tell
    if pt then
        UI.chat.pending_tell = nil
        ui_chat_add("self_tell", pt.from, pt.msg)
    end
    return
end

-- Cancel pending tell because the recipient isnt there
if line:match(" doesn't seem to be around at the moment") then
    UI.chat.pending_tell = nil
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
    msg   = matches[4]
end

-- Fed2 server wraps long lines before the closing quote — capture continuations
-- so the chat tab always receives the complete message.
if not msg:match('"$') then
    local pending = { mtype = mtype, name = name, msg = msg }
    local capture_continuation
    capture_continuation = function()
        tempLineTrigger(1, 1, function()
            local cont = getCurrentLine()
            if cont:match('"$') then
                ui_chat_add(pending.mtype, pending.name, pending.msg .. " " .. cont:gsub('"$', ''))
            else
                pending.msg = pending.msg .. " " .. cont
                capture_continuation()
            end
        end)
    end
    capture_continuation()
    return
end

-- Single-line message: strip the trailing quote captured by (.+)$
msg = msg:gsub('"$', '')

ui_tab_notify("Comm")

ui_chat_add(mtype, name, msg)
