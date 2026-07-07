-- fed2-tools chat — persistent chat history store
--
-- Owns F2T_CHAT.history: an ordered list of chat records persisted per
-- character under fed2-tools_persistent/<char>/chat_history.  This module is
-- pure data — it never touches widgets.  Consumers (the fed2_chat content in
-- ui/content/chat.lua) listen for the f2tChatUpdated event:
--
--   raiseEvent("f2tChatUpdated", "append")   one record appended (history tail)
--   raiseEvent("f2tChatUpdated", "replay")   history restructured — re-render all
--
-- Record shape: { t = unixTime, type = <see below>, from = name, msg = text }
--   com / say / tell_in       inbound traffic
--   self_com / self_say / self_tell   the local player's own messages
--   status                    connect/disconnect markers (pre-rendered r.line)
--
-- Ported from archive's ui_chat.lua with the rendering half split out.

F2T_CHAT = F2T_CHAT or {
    history     = {},
    loaded      = false,
    pendingTell = nil,   -- staged outgoing tell awaiting the "hum" confirmation
}

local MAX_DAYS = 7
local MAX_MSGS = 2000

local function chatPath()
    return f2t_get_char_persistent_dir() .. "/chat_history"
end

function f2tChatSave()
    if not F2T_CHAR_NAME or F2T_CHAR_NAME == "" then return end
    local cutoff = os.time() - (MAX_DAYS * 86400)
    local kept   = {}
    for _, r in ipairs(F2T_CHAT.history) do
        if r.t and r.t >= cutoff then table.insert(kept, r) end
    end
    while #kept > MAX_MSGS do table.remove(kept, 1) end
    F2T_CHAT.history = kept
    local ok, err = pcall(table.save, chatPath(), F2T_CHAT.history)
    if not ok then f2t_debug_log("[chat] save error: %s", tostring(err)) end
end

-- Debounced save: rendering stays realtime (records append in memory and the
-- f2tChatUpdated event fires immediately); only the disk write is deferred, so
-- a busy com channel doesn't rewrite the whole history file per message.
-- Guardrails: f2tChatFlush() runs on disconnect and Mudlet exit.
local SAVE_DEBOUNCE = 10
local _saveTimer = nil

local function scheduleSave()
    if _saveTimer then return end
    _saveTimer = tempTimer(SAVE_DEBOUNCE, function()
        _saveTimer = nil
        f2tChatSave()
    end)
end

function f2tChatFlush()
    if _saveTimer then killTimer(_saveTimer); _saveTimer = nil end
    f2tChatSave()
end

-- Drop a pending write without saving — used when history is about to be
-- replaced wholesale (character change); the old character's data was already
-- flushed by the disconnect guardrail.
local function cancelPendingSave()
    if _saveTimer then killTimer(_saveTimer); _saveTimer = nil end
end

function f2tChatLoad()
    local buf = {}
    local ok  = pcall(table.load, chatPath(), buf)
    if ok and type(buf) == "table" then
        local cutoff = os.time() - (MAX_DAYS * 86400)
        for _, r in ipairs(buf) do
            if r.t and r.t >= cutoff and type(r.type) == "string" and type(r.msg) == "string" then
                r.from = r.from or ""   -- status/cycle records have no sender
                table.insert(F2T_CHAT.history, r)
            end
        end
    end
    F2T_CHAT.loaded = true
    f2t_debug_log("[chat] loaded %d records", #F2T_CHAT.history)
end

--- Append one live message and notify renderers.
function f2tChatAdd(mtype, from, message)
    local r = { t = os.time(), type = mtype, from = from or "", msg = message or "" }
    table.insert(F2T_CHAT.history, r)
    scheduleSave()
    raiseEvent("f2tChatUpdated", "append")
end

function f2tChatWipe()
    F2T_CHAT.history = {}
    f2tChatFlush()
    raiseEvent("f2tChatUpdated", "replay")
    cecho("\n<yellow>[chat]<reset> Chat history wiped.\n")
end

-- Discard in-memory history and reload from the (possibly different) per-char
-- path.  Called when the logged-in character changes.
function f2tChatReload()
    cancelPendingSave()
    F2T_CHAT.history = {}
    F2T_CHAT.loaded  = false
    f2tChatLoad()
    raiseEvent("f2tChatUpdated", "replay")
    f2t_debug_log("[chat] reloaded for char %s, %d records", F2T_CHAR_NAME or "?", #F2T_CHAT.history)
end

-- ── Connection status markers ─────────────────────────────────────────────────
-- Pre-rendered with a hecho hex prefix; the content module echoes r.line when
-- timestamps are enabled.  Always stored so replays show session boundaries.

local function addStatus(msg, line)
    local r = {
        t = os.time(), type = "status", from = "", msg = msg, line = line,
    }
    table.insert(F2T_CHAT.history, r)
    scheduleSave()
    raiseEvent("f2tChatUpdated", "append")
end

registerAnonymousEventHandler("sysConnectionEvent", function()
    addStatus("Connected", string.format(
        "#2d6e2d── Connected %s ─────────────────────────\n", os.date("%H:%M")))
end)

registerAnonymousEventHandler("sysDisconnectionEvent", function()
    addStatus("Disconnected", string.format(
        "#6e2d2d── Disconnected %s ──────────────────────\n", os.date("%H:%M")))
    f2tChatFlush()   -- session ending: persist everything now, marker included
end)

registerAnonymousEventHandler("sysExitEvent", function()
    f2tChatFlush()
end)

registerAnonymousEventHandler("f2tCharacterChanged", function()
    f2tChatReload()
end)

-- Load at startup for the pre-login shared path; f2tCharacterChanged reloads
-- from the per-char path once the character is known.
if not F2T_CHAT.loaded then f2tChatLoad() end

-- ── Settings ──────────────────────────────────────────────────────────────────

f2t_settings_register("chat", "show_timestamps", {
    tab         = "Fed2-Tools/Chat",
    label       = "Show timestamps",
    description = "Show [HH:MM] timestamps and day dividers in chat panels",
    default     = false,
})

f2t_settings_register("chat", "fetch_history", {
    label       = "Fetch com history on login",
    description = "Auto-run comhistory after login and merge missed messages into the chat log",
    default     = true,
})

f2t_debug_log("[chat] history module loaded")
