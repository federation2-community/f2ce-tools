-- =============================================================================
-- ui_chat  —  persistent chat history, grouped rendering, filter + timestamps
-- Mudlet Script location: ui > ui_chat
-- =============================================================================

UI      = UI or {}
UI.chat = UI.chat or {
    history    = {},
    loaded     = false,
    show_ts    = false,
    filter_idx = 1,
    last_key   = nil,
}

local _MAX_DAYS = 7
local _MAX_MSGS = 2000

-- ── Style per message type ────────────────────────────────────────────────
-- gutter_hex : hecho #RRGGBB color for the continuation pipe and direction arrows
-- text_hex   : hecho #RRGGBB color for the message body

local _STYLE = {
    com       = { gutter_hex = "#2a7070", text_hex = "#008080" },
    say       = { gutter_hex = "#008000", text_hex = "#008000" },
    tell_in   = { gutter_hex = "#882222", text_hex = "#882222" },
    self_com  = { gutter_hex = "#226622", text_hex = "#00ffff" },
    self_say  = { gutter_hex = "#4caf70", text_hex = "#4caf70" },
    self_tell = { gutter_hex = "#ff8888", text_hex = "#ff8888" },
}

-- Exported so ui_players can reference gutter colors if needed
UI.chat.colors = {
    com       = _STYLE.com.gutter_hex,
    tell_in   = _STYLE.tell_in.gutter_hex,
    self_com  = _STYLE.self_com.gutter_hex,
    self_tell = _STYLE.self_tell.gutter_hex,
}

-- ── Filter states ─────────────────────────────────────────────────────────

local _FILTER = {
    {
        id = "all", label = "A", matches = nil,
        css = [[QLabel{
            background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(100,100,110,180);
            color:rgba(160,160,170,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }]],
    },
    {
        id = "com", label = "C", matches = { com = true, self_com = true },
        css = [[QLabel{
            background-color:rgba(15,50,50,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(50,120,120,200);
            color:rgba(60,170,170,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(25,75,75,240); color:white; }]],
    },
    {
        id = "tell", label = "T", matches = { tell_in = true, self_tell = true },
        css = [[QLabel{
            background-color:rgba(52,18,18,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(140,50,50,200);
            color:rgba(210,80,80,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(75,25,25,240); color:white; }]],
    },
    {
        id = "say", label = "S", matches = { say = true, self_say = true },
        css = [[QLabel{
            background-color:rgba(18,30,52,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(50,90,150,200);
            color:rgba(70,130,210,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(25,45,75,240); color:white; }]],
    },
}

-- ── Persistence ───────────────────────────────────────────────────────────

local function _chat_dir()  return getMudletHomeDir() .. "/fed2-tools/chat" end
local function _chat_path() return _chat_dir() .. "/history" end
local function _ensure_dir()
    lfs.mkdir(getMudletHomeDir() .. "/fed2-tools")
    lfs.mkdir(_chat_dir())
end

function ui_chat_save()
    _ensure_dir()
    local cutoff = os.time() - (_MAX_DAYS * 86400)
    local kept   = {}
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
            if r.t and r.t >= cutoff then table.insert(UI.chat.history, r) end
        end
    end
    UI.chat.loaded = true
    f2t_debug_log("[chat] loaded %d records", #UI.chat.history)
end

-- ── Internal rendering ────────────────────────────────────────────────────

local function _rank_cecho(name)
    if UI.who and UI.who.name_colors then
        if UI.who.name_colors[name] then
            return "<" .. UI.who.name_colors[name] .. ">"
        end
        -- Case-insensitive fallback (e.g. user typed "thomas", list has "Thomas")
        local lower = name:lower()
        for k, v in pairs(UI.who.name_colors) do
            if k:lower() == lower then return "<" .. v .. ">" end
        end
    end
    -- Unknown player — request a background who refresh, render as dim_gray for now
    if ui_who_request_refresh then ui_who_request_refresh() end
    return "<dim_gray>"
end

local function _raw_line(name)
    if UI.who and UI.who.name_rawlines then
        return UI.who.name_rawlines[name]
    end
    return nil
end

-- Render one record into UI.chat_window.
--
-- is_cont = false (new/changed speaker):
--   No pipe. "Name » message" — name is bold, rank-colored, clickable.
--
-- is_cont = true (same speaker, same type, consecutive):
--   Colored pipe glyph only, no name. Visually chains to the message above.
--
-- hecho is used for #hex color prefixes.
-- cecho is used for <colorname> and <reset> tags.
-- They are never mixed in a single call.

local function _render_record(r, is_cont, show_ts)
    if not UI.chat_window then return end

    -- Status lines always pass filter; echo verbatim via hecho (hex prefixed)
    if r.type == "status" then
        UI.chat_window:hecho(r.line or "")
        return
    end

    -- Filter gate
    local fstate = _FILTER[UI.chat.filter_idx]
    if fstate.matches and not fstate.matches[r.type] then return end

    local st = _STYLE[r.type] or _STYLE.com

    -- [HH:MM] timestamp prefix — hex color, hecho
    if show_ts and r.t then
        UI.chat_window:hecho("#404040[" .. os.date("%H:%M", r.t) .. "] ")
    end

    if is_cont then
        -- Continuation: colored pipe, then body — both hex, both hecho
        UI.chat_window:hecho(st.gutter_hex .. "▎  ")
        UI.chat_window:hecho(st.text_hex .. r.msg .. "\n")
        return
    end

    -- New speaker: resolve rank color (cecho tag) then emit name + separator + body
    local nc   = _rank_cecho(r.from)
    local hint = _raw_line(r.from) or ("tb " .. r.from)

    if r.type == "self_tell" then
        -- "❯❯ Recipient » message"
        UI.chat_window:hecho(st.gutter_hex .. "❯❯ ")
        UI.chat_window:cechoLink(
            nc .. "<b>" .. r.from .. "</b><reset>",
            function() printCmdLine("tb " .. r.from .. " ") end,
            hint, true)
        UI.chat_window:cecho(" <dim_gray>»<reset> ")

    elseif r.type == "tell_in" then
        -- "❮❮ Sender » message"
        UI.chat_window:hecho(st.gutter_hex .. "❮❮ ")
        UI.chat_window:cechoLink(
            nc .. "<b>" .. r.from .. "</b><reset>",
            function() printCmdLine("tb " .. r.from .. " ") end,
            hint, true)
        UI.chat_window:cecho(" <dim_gray>»<reset> ")

    else
        -- com / say / self_com: "Name » message"
        UI.chat_window:cechoLink(
            nc .. "<b>" .. r.from .. "</b><reset>",
            function() printCmdLine("tb " .. r.from .. " ") end,
            hint, true)
        UI.chat_window:cecho(" <dim_gray>»<reset> ")
    end

    -- Message body — hex color, hecho
    UI.chat_window:hecho(st.text_hex .. r.msg .. "\n")
end

-- ── Replay ────────────────────────────────────────────────────────────────

function ui_chat_replay()
    if not UI.chat_window then return end
    UI.chat_window:clear()
    if #UI.chat.history == 0 then return end

    local show_ts  = UI.chat.show_ts
    local filtered = (_FILTER[UI.chat.filter_idx].matches ~= nil)

    if show_ts then
        -- Hex prefix separator — hecho
        UI.chat_window:hecho("#303030─── Chat History ──────────────────────────\n")
    end

    local last_day = ""
    local prev     = nil

    for _, r in ipairs(UI.chat.history) do
        if show_ts and r.t and r.type ~= "status" then
            local day = os.date("%Y-%m-%d", r.t)
            if day ~= last_day then
                UI.chat_window:hecho("#1a3040── " .. os.date("%A, %b %d", r.t) .. " ──\n")
                last_day = day
            end
        end

        local is_cont = (not filtered)
            and prev
            and r.type ~= "status" and prev.type ~= "status"
            and prev.from == r.from and prev.type == r.type

        _render_record(r, is_cont, show_ts)
        if r.type ~= "status" then prev = r end
    end

    if show_ts then
        UI.chat_window:hecho("#303030─── Live ─────────────────────────────────\n")
    end

    UI.chat.last_key = prev and (prev.from .. prev.type) or nil
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

-- ── Filter cycle ──────────────────────────────────────────────────────────

function ui_chat_cycle_filter()
    UI.chat.filter_idx = (UI.chat.filter_idx % #_FILTER) + 1
    local state = _FILTER[UI.chat.filter_idx]
    if UI.chat_filter_btn then
        UI.chat_filter_btn:setStyleSheet(state.css)
        UI.chat_filter_btn:echo("<center>" .. state.label .. "</center>")
        local tips = {
            all = "Show all messages", com = "Com channel only",
            tell = "Tells only",       say = "Say only",
        }
        UI.chat_filter_btn:setToolTip(tips[state.id] or "Filter")
    end
    ui_chat_replay()
end

-- ── Public write API ──────────────────────────────────────────────────────

function ui_chat_add(mtype, from, message, _ignored)
    local r = { t = os.time(), type = mtype, from = from, msg = message }
    table.insert(UI.chat.history, r)

    local is_cont = false
    if mtype ~= "status" then
        local key = from .. mtype
        if not _FILTER[UI.chat.filter_idx].matches then
            is_cont = (UI.chat.last_key == key)
        end
        UI.chat.last_key = key
    else
        UI.chat.last_key = nil
    end

    _render_record(r, is_cont, UI.chat.show_ts)
    ui_chat_save()
end

-- ── Connection status markers ─────────────────────────────────────────────
-- Pre-formatted with hex prefix; echoed via hecho.

function ui_chat_on_connect()
    local ts = os.date("%H:%M")
    local r  = {
        t = os.time(), type = "status", from = "", msg = "Connected",
        line = string.format("#2d6e2d── Connected %s ─────────────────────────\n", ts),
    }
    table.insert(UI.chat.history, r)
    UI.chat.last_key = nil
    if UI.chat_window then UI.chat_window:hecho(r.line) end
    ui_chat_save()
    UI.who._needs_login_refresh = true
end

function ui_chat_on_disconnect()
    local ts = os.date("%H:%M")
    local r  = {
        t = os.time(), type = "status", from = "", msg = "Disconnected",
        line = string.format("#6e2d2d── Disconnected %s ──────────────────────\n", ts),
    }
    table.insert(UI.chat.history, r)
    UI.chat.last_key = nil
    if UI.chat_window then UI.chat_window:hecho(r.line) end
    ui_chat_save()
end

-- ── Init ──────────────────────────────────────────────────────────────────

function ui_chat_init()
    if not UI.chat.loaded then ui_chat_load() end
    ui_chat_replay()
    f2t_debug_log("[chat] init complete, %d records", #UI.chat.history)
end

