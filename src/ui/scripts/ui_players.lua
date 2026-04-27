-- =============================================================================
-- ui_players  —  online player list (uses ui_table_system)
-- Mudlet Script location: ui > ui_players
-- =============================================================================

UI     = UI or {}
UI.who = UI.who or {
    players       = {},
    parsing       = false,
    ui_requested  = false,  -- true only when a UI button/tab initiated the who command
    count         = 0,
    staff_count   = 0,
    name_colors   = {},   -- name → cecho color string (shared with ui_chat)
    name_rawlines = {},   -- name → full raw who line  (shared with ui_chat)
    _line_buffer  = "",   -- accumulates the current (possibly wrapped) player line
}

-- ── Rank ordering ─────────────────────────────────────────────────────────

local RANK_ORDER = {
    ["Groundhog"]     = 1,
    ["Commander"]     = 2,
    ["Captain"]       = 3,
    ["Adventurer"]    = 4,
    ["Merchant"]      = 5,
    ["Trader"]        = 6,
    ["Industrialist"] = 7,
    ["Manufacturer"]  = 8,
    ["Financier"]     = 9,
    ["Founder"]       = 10,
    ["Engineer"]      = 11,
    ["Mogul"]         = 12,
    ["Technocrat"]    = 13,
    ["Gengineer"]     = 14,
    ["Magnate"]       = 15,
    ["Plutocrat"]     = 16,
}

-- ── Rank → cecho color ────────────────────────────────────────────────────

local RANK_COLOR = {
    ["Trader"]        = "mint_cream",
    ["Engineer"]      = "ansiCyan",
    ["Merchant"]      = "mint_cream",
    ["Manufacturer"]  = "ansiGreen",
    ["Industrialist"] = "ansiGreen",
    ["Financier"]     = "ansiGreen",
    ["Mogul"]         = "ansiCyan",
    ["Magnate"]       = "ansiCyan",
    ["Technocrat"]    = "ansiCyan",
    ["Gengineer"]     = "ansiCyan",
    ["Founder"]       = "ansiCyan",
    ["Plutocrat"]     = "ansiRed",
    ["Commander"]     = "dark_violet",
    ["Groundhog"]     = "dark_violet",
}
local RANK_COLOR_DEFAULT = "ansi_white"

local function _color_for(row)
    if row.rank == "Plutocrat" and row.staff and row.staff ~= "" then
        return "olive_drab"
    end
    return RANK_COLOR[row.rank] or RANK_COLOR_DEFAULT
end

-- ── Parser ────────────────────────────────────────────────────────────────

function ui_who_parse_line(raw)
    local line = raw:match("^%s*(.-)%s*$")
    if line == "" then return nil end

    local staff = ""
    line = line:gsub("%s+%[(%a+)%]%s*$", function(b) staff = b; return "" end)
    line = line:match("^%s*(.-)%s*$")

    local rank = line:match("^(%a+)")
    if not rank then return nil end

    local after_rank = line:sub(#rank + 1):match("^%s*(.*)")
    local name = after_rank and after_rank:match("^(%a+)") or ""
    if name == "" then return nil end

    local after_name = after_rank:sub(#name + 1):match("^%s*(.*)")
    local location, location_is_space = "", false

    if rank == "Groundhog" then
        location = "Earth"
    elseif after_name then
        -- "in SystemName Space" at end of line (player is in system space, not on a planet)
        local sys = after_name:match(".*%sin%s+(.-)%s+[Ss]pace%s*$")
        if sys and sys ~= "" then
            location         = sys
            location_is_space = true
        else
            -- "on PlanetName" at end of line — greedy .* finds the LAST "on"
            local planet = after_name:match(".*%son%s+(.-)%s*$")
            if planet and planet ~= "" then
                location = planet
            end
        end
    end

    return {
        rank             = rank,
        rank_order       = RANK_ORDER[rank] or 0,
        name             = name,
        location         = location,
        location_is_space = location_is_space,
        staff            = staff,
        raw_line         = "",
    }
end

-- ── Line buffer helpers ───────────────────────────────────────────────────
-- The game may wrap a long player line across two console lines.
-- We buffer partial lines and flush them when a new player entry begins
-- or when parsing ends.

local function _flush_buffer()
    local buf = UI.who._line_buffer
    if buf == "" then return end
    UI.who._line_buffer = ""

    local trimmed = buf:match("^  (.+)") or buf:match("^%s*(.-)%s*$")
    local parsed  = ui_who_parse_line(buf)
    if parsed then
        parsed.raw_line    = trimmed or ""
        parsed.cecho_color = _color_for(parsed)
        table.insert(UI.who.players, parsed)
    end
end

-- ── Trigger callbacks ─────────────────────────────────────────────────────

-- Pattern: People in Federation II dataspace:  (substring)
-- Only begins parsing when the who was UI-initiated; leaves manual who output alone.
function ui_who_start()
    if not UI.who.ui_requested then
        f2t_debug_log("[who] ignoring manual who command")
        return
    end
    UI.who.ui_requested = false
    UI.who.parsing      = true
    UI.who.players      = {}
    UI.who._line_buffer = ""
    f2t_debug_log("[who] parse start (UI-initiated)")
end

-- Pattern: .*  (matches every line — fast no-op when not parsing)
--
-- Called on every incoming line while parsing is active.
-- Handles four cases:
--   1. New player line  (starts with "  [Rank]") → flush previous buffer, start new one
--   2. Wrapped continuation (no leading spaces, not a badge/summary) → append to buffer
--   3. Standalone [Badge] line → update the most recently completed player
--   4. Summary / header / blank lines → skip (summary also flushes buffer first)
function ui_who_line()
    if not UI.who.parsing then return end

    local full = getCurrentLine()

    -- Skip blank lines
    if full:match("^%s*$") then return end

    -- Skip the "People in Federation II dataspace:" header line
    if full:match("People in Federation II dataspace:") then return end

    -- Summary line: flush the last buffered player first, then let whoListEnd handle it
    if full:match("^%d+ players, %d+ staff") then
        _flush_buffer()
        return
    end

    -- Standalone [Badge] line e.g. "[Navigator]"
    -- The game sometimes puts this on its own line below the player it belongs to.
    local solo = full:match("^%s*%[(%a+)%]%s*$")
    if solo then
        -- The badge may belong to a buffered-but-not-yet-flushed entry (most common)
        -- OR the last already-flushed entry.
        if UI.who._line_buffer ~= "" then
            -- Still buffering: append inline so parse captures it correctly
            UI.who._line_buffer = UI.who._line_buffer .. " [" .. solo .. "]"
        elseif #UI.who.players > 0 then
            local last = UI.who.players[#UI.who.players]
            if last.staff == "" then
                last.staff       = solo
                last.raw_line    = last.raw_line .. " [" .. solo .. "]"
                last.cecho_color = _color_for(last)
            end
        end
        return
    end

    -- New player line: starts with two spaces followed by an uppercase letter.
    -- The first word must be a known rank (guards against stray indented game text).
    if full:match("^  %u") then
        local first_word = full:match("^%s*(%a+)")
        if RANK_ORDER[first_word] then
            _flush_buffer()
            UI.who._line_buffer = full
            return
        end
    end

    -- Continuation line: part of the previous player's line that wrapped.
    -- Append it (trimmed) to the current buffer.
    if UI.who._line_buffer ~= "" then
        local cont = full:match("^%s*(.-)%s*$")
        if cont ~= "" then
            UI.who._line_buffer = UI.who._line_buffer .. " " .. cont
        end
    end
end

-- Pattern: ^\d+ players, \d+ staff  (regex)
function ui_who_end()
    if not UI.who.parsing then return end

    -- Flush any final buffered player (in case _flush wasn't triggered by a new entry)
    _flush_buffer()

    UI.who.parsing = false

    local full             = getCurrentLine()
    local total, stf       = full:match("(%d+) players, (%d+) staff")
    UI.who.count           = tonumber(total) or #UI.who.players
    UI.who.staff_count     = tonumber(stf)   or 0

    -- Populate maps shared with ui_chat for rank-colored speaker names
    UI.who.name_colors   = {}
    UI.who.name_rawlines = {}
    for _, p in ipairs(UI.who.players) do
        UI.who.name_colors[p.name]   = p.cecho_color
        UI.who.name_rawlines[p.name] = p.raw_line
    end

    -- Delete trailing blank line that the game outputs after the summary
    tempLineTrigger(1, 1, function()
        if getCurrentLine():match("^%s*$") then deleteLine() end
    end)

    f2t_debug_log("[who] parsed %d players", #UI.who.players)

    if UI.who_header then
        UI.who_header:echo(string.format(
            "  👥  Online: %d players, %d staff",
            UI.who.count, UI.who.staff_count))
    end

    ui_table_set_data("who_list", UI.who.players)

    -- Replay chat and general so speaker names pick up the freshly populated rank colors
    if ui_chat_replay    then ui_chat_replay()    end
    if ui_general_replay then ui_general_replay() end
end

-- ── Refresh ───────────────────────────────────────────────────────────────

function ui_who_refresh()
    UI.who.ui_requested = true
    if UI.who_header then UI.who_header:echo("  👥  Refreshing…") end
    send("who", false)
end

-- Debounced auto-refresh triggered when an unknown name is encountered during
-- rendering. Guards against firing before login and has a 60-second cooldown to
-- break the who-end → replay → unknown-name → who loop.
local _auto_refresh_pending = false
local _last_auto_refresh    = 0
function ui_who_request_refresh()
    if _auto_refresh_pending or UI.who.parsing then return end
    -- Only fire when logged in (GMCP vitals present)
    if not (gmcp and gmcp.char and gmcp.char.vitals) then return end
    -- Cooldown: at most one auto-refresh per 5 seconds
    if os.time() - _last_auto_refresh < 5 then return end
    _auto_refresh_pending = true
    tempTimer(1.5, function()
        _auto_refresh_pending  = false
        _last_auto_refresh     = os.time()
        ui_who_refresh()
    end)
end

-- Fires on first gmcp.char.vitals after a new connection; sends who once the
-- login sequence has settled so rank colors populate immediately.
function ui_who_on_login_vitals()
    if not UI.who._needs_login_refresh then return end
    UI.who._needs_login_refresh = false
    tempTimer(3, function()
        ui_who_refresh()
    end)
end

-- ── Table init ────────────────────────────────────────────────────────────

function ui_who_init()
    if not UI.who_window then
        f2t_debug_log("[who] who_window not available — skipping table init")
        return
    end

    local cols = {
        {
            key          = "rank",
            label        = "Rank",
            width        = 13,
            align        = "left",
            sortable     = true,
            sort_value   = function(row) return row.rank_order or 0 end,
            format       = function(v, row)
                local cc = row.cecho_color or RANK_COLOR_DEFAULT
                return "<" .. cc .. ">" .. v .. "<reset>"
            end,
        },
        {
            key          = "name",
            label        = "Name",
            width        = 16,
            align        = "left",
            sortable     = true,
            default_sort = "asc",
            render       = function(value, row, window, col)
                local cc    = row.cecho_color or RANK_COLOR_DEFAULT
                local raw   = row.raw_line or ""
                local staff = (row.staff and row.staff ~= "")

                local name_str = "<" .. cc .. "><b>" .. (value or "") .. "</b><reset>"
                if staff then
                    name_str = name_str .. " <ansiYellow>[" .. row.staff:sub(1,3) .. "]<reset>"
                end

                local visible_len = #(value or "") + (staff and 6 or 0)
                local pad = (col.width or 16) - visible_len
                if pad > 0 then name_str = name_str .. string.rep(" ", pad) end

                window:cechoLink(
                    name_str,
                    function() printCmdLine("tb " .. (value or "") .. " ") end,
                    raw,
                    true
                )
            end,
        },
        {
            key      = "location",
            label    = "Location",
            width    = 12,
            align    = "left",
            sortable = true,
            format   = function(v, row)
                if not v or v == "" then return "" end
                return "<ansiCyan>" .. v .. "<reset>"
            end,
            link = function(value, row)
                if not value or value == "" then return end
                if row.location_is_space then
                    expandAlias("nav " .. value .. " space link")
                else
                    expandAlias("nav " .. value)
                end
            end,
            linkHint = "Go to %s",
        },
    }

    ui_table_create("who_list", UI.who_window, cols, {
        column = "  ",
        row    = nil,
        header = " ",
    })

    -- Tab-click auto-refresh: sets ui_requested then fires who
    local tw  = UI.tab_top_left
    local tab = tw and tw.Who
    if tab and tab.adjLabel then
        tab.adjLabel:setClickCallback(function(event)
            tw:onClick("Who", event)
            ui_who_refresh()
        end)
        f2t_debug_log("[who] tab auto-refresh wired")
    end

    -- Periodic auto-refresh every 60 seconds; only fires when logged in
    local function schedule_who_periodic()
        UI.who._periodic_timer = tempTimer(60, function()
            if gmcp and gmcp.char and gmcp.char.vitals and not UI.who.parsing then
                ui_who_refresh()
            end
            schedule_who_periodic()
        end)
    end
    schedule_who_periodic()

    f2t_debug_log("[who] init complete")
end