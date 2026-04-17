-- =============================================================================
-- ui_chat_core  —  persistent chat history, styled rendering, timestamp toggle
-- =============================================================================

UI      = UI or {}
UI.chat = UI.chat or {
    history      = {},
    loaded       = false,
    show_ts      = false,
    last_speaker = nil,   -- "from..type" key for grouping consecutive messages
}

local _MAX_DAYS = 7
local _MAX_MSGS = 2000

-- ── Visual style per message type ─────────────────────────────────────────
-- gutter : colored left bar character (▎ for received, ▎▸ for self)
-- name   : speaker name color
-- text   : message body color

local _STYLE = {
    com      = { gutter = "#4fa3a3", glyph = "▎ ", name = "#7fd4d4", text = "#b8e8e8" },
    say      = { gutter = "#4fa3a3", glyph = "▎ ", name = "#7fd4d4", text = "#b8e8e8" },
    tell_in  = { gutter = "#FF5C5C", glyph = "▎ ", name = "#FF8888", text = "#FFcece" },
    self_com = { gutter = "#70c890", glyph = "▎▸", name = "#90dca8", text = "#bce8cc" },
    self_tell= { gutter = "#FF9040", glyph = "▎▸", name = "#FFb060", text = "#FFd4a8" },
}

-- Exported so aliases can reference exact sender color without hardcoding
UI.chat.colors = {
    com       = _STYLE.com.gutter,
    tell_in   = _STYLE.tell_in.gutter,
    self_com  = _STYLE.self_com.gutter,
    self_tell = _STYLE.self_tell.gutter,
}

-- ── Persistence paths ─────────────────────────────────────────────────────

local function _chat_dir()  return getMudletHomeDir() .. "/fed2-tools/chat" end
local function _chat_path() return _chat_dir() .. "/history" end
local function _ensure_dir()
    lfs.mkdir(getMudletHomeDir() .. "/fed2-tools")
    lfs.mkdir(_chat_dir())
end

-- ── Persistence ───────────────────────────────────────────────────────────

function ui_chat_save()
    _ensure_dir()
    local cutoff = os.time() - (_MAX_DAYS * 86400)
    local kept = {}
    for _, r in ipairs(UI.chat.history) do
        if r.t and r.t >= cutoff then table.insert(kept, r) end
    end
    while #kept > _MAX_MSGS do table.remove(kept, 1) end
    UI.chat.history = kept
    local ok, err = pcall(table.save, _chat_path(), UI.chat.history)
    if not ok then f2t_debug_log("[chat] save error: %s", tostring(err)) end
end

function ui_chat_load()
    local buf = {}
    local ok  = pcall(table.load, _chat_path(), buf)
    if ok and type(buf) == "table" then
        local cutoff = os.time() - (_MAX_DAYS * 86400)
        for _, r in ipairs(buf) do
            if r.t and r.t >= cutoff then
                table.insert(UI.chat.history, r)
            end
        end
    end
    UI.chat.loaded = true
    f2t_debug_log("[chat] loaded %d records", #UI.chat.history)
end

-- ── Line formatter ────────────────────────────────────────────────────────
-- Produces an hecho-format string for one record.
-- Status records: always use pre-formatted r.line.
-- Chat records:   build from style table; respect grouping and timestamps.

local function _format_line(r, is_continuation, show_ts)
    if r.type == "status" then
        return r.line or ""
    end

    local st = _STYLE[r.type] or _STYLE.com

    local ts_str = ""
    if show_ts and r.t then
        ts_str = "#404040[" .. os.date("%H:%M", r.t) .. "] "
    end

    local gutter = st.gutter .. st.glyph .. " "

    if is_continuation then
        return ts_str .. gutter .. "#383838  " .. st.text .. r.msg .. "\n"
    end

    local name_part
    if r.type == "self_tell" then
        -- You → Recipient
        name_part = st.name .. "You #606060→ " .. st.name .. r.from .. " #505050» "
    elseif r.type == "tell_in" then
        -- Sender → you
        name_part = st.name .. r.from .. " #606060→ you #505050» "
    else
        name_part = st.name .. r.from .. " #505050» "
    end

    return ts_str .. gutter .. name_part .. st.text .. r.msg .. "\n"
end

-- ── Echo one record ───────────────────────────────────────────────────────

local function _echo_record(r, is_continuation)
    if not UI.chat_window then return end
    local show_ts = UI.chat.show_ts
    -- Never group when timestamps are shown (every message gets full attribution)
    local group = is_continuation and not show_ts
    UI.chat_window:hecho(_format_line(r, group, show_ts))
end

-- ── Replay ────────────────────────────────────────────────────────────────
-- Clears the window and replays history.
-- The "Chat History" / date dividers / "Live" chrome only appear when
-- timestamps are toggled on; the default view is clean undecorated scrollback.

function ui_chat_replay()
    if not UI.chat_window then return end
    UI.chat_window:clear()
    if #UI.chat.history == 0 then return end

    local show_ts = UI.chat.show_ts

    if show_ts then
        UI.chat_window:hecho("#383838─── Chat History ──────────────────────────\n")
    end

    local last_day = ""
    local prev     = nil

    for _, r in ipairs(UI.chat.history) do
        -- Date group header (timestamps-on only)
        if show_ts and r.t and r.type ~= "status" then
            local day = os.date("%Y-%m-%d", r.t)
            if day ~= last_day then
                UI.chat_window:hecho(
                    "#1e3a4a── " .. os.date("%A, %b %d", r.t) .. " ──\n")
                last_day = day
            end
        end

        -- Grouping: suppress sender when consecutive same speaker + same type
        local is_cont = prev
            and (r.type ~= "status") and (prev.type ~= "status")
            and (prev.from == r.from) and (prev.type == r.type)

        _echo_record(r, is_cont)
        prev = r
    end

    if show_ts then
        UI.chat_window:hecho("#383838─── Live ─────────────────────────────────\n")
    end

    -- Seed last_speaker so live messages group correctly after replay
    if prev and prev.type ~= "status" then
        UI.chat.last_speaker = prev.from .. prev.type
    else
        UI.chat.last_speaker = nil
    end
end

-- ── Timestamp toggle ──────────────────────────────────────────────────────

function ui_chat_toggle_timestamps()
    UI.chat.show_ts = not UI.chat.show_ts
    if UI.chat_ts_btn then
        if UI.chat.show_ts then
            UI.chat_ts_btn:echo("<center><font color='#78c8c8'>⏱</font></center>")
            UI.chat_ts_btn:setToolTip("Timestamps ON — click to hide")
        else
            UI.chat_ts_btn:echo("<center><font color='#3a3a3a'>⏱</font></center>")
            UI.chat_ts_btn:setToolTip("Timestamps OFF — click to show")
        end
    end
    ui_chat_replay()
end

-- ── Public write API ──────────────────────────────────────────────────────
-- Handlers and aliases call this. hecho_line is accepted but ignored —
-- we regenerate format dynamically so stored records remain format-agnostic.

function ui_chat_add(mtype, from, message, _ignored)
    local r = { t = os.time(), type = mtype, from = from, msg = message }
    table.insert(UI.chat.history, r)

    local is_cont = false
    if mtype ~= "status" then
        local key = from .. mtype
        is_cont = (UI.chat.last_speaker == key)
        UI.chat.last_speaker = key
    else
        UI.chat.last_speaker = nil
    end

    _echo_record(r, is_cont)
    ui_chat_save()
end

-- ── Connection status markers ─────────────────────────────────────────────
-- Always written regardless of timestamp mode.

function ui_chat_on_connect()
    local ts = os.date("%H:%M")
    local r  = {
        t    = os.time(), type = "status", from = "", msg = "Connected",
        line = string.format("#3a7a3a── Connected %s ─────────────────────────\n", ts),
    }
    table.insert(UI.chat.history, r)
    UI.chat.last_speaker = nil
    if UI.chat_window then UI.chat_window:hecho(r.line) end
    ui_chat_save()
end

function ui_chat_on_disconnect()
    local ts = os.date("%H:%M")
    local r  = {
        t    = os.time(), type = "status", from = "", msg = "Disconnected",
        line = string.format("#7a3a3a── Disconnected %s ──────────────────────\n", ts),
    }
    table.insert(UI.chat.history, r)
    UI.chat.last_speaker = nil
    if UI.chat_window then UI.chat_window:hecho(r.line) end
    ui_chat_save()
end

-- ── Init ──────────────────────────────────────────────────────────────────

function ui_chat_init()
    if not UI.chat.loaded then ui_chat_load() end
    ui_chat_replay()
    f2t_debug_log("[chat] init complete, %d records", #UI.chat.history)
end

function ui_echo_com()
    ui_chat_add("com", gmcp.comm.com.from, gmcp.comm.com.message)
end
 
function ui_echo_tell()
    ui_chat_add("tell_in", gmcp.comm.tell.from, gmcp.comm.tell.message)
end
 
function ui_echo_say()
    ui_chat_add("say", gmcp.comm.say.from, gmcp.comm.say.message)
end
 