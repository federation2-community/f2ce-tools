-- =============================================================================
-- ui_chat_who  —  online player list with game colors and sortable header
-- =============================================================================

UI     = UI or {}
UI.who = UI.who or {
    players     = {},
    parsing     = false,
    count       = 0,
    staff_count = 0,
    sort_by     = "rank_order",  -- "rank_order" | "name"
    sort_asc    = false,         -- false = high rank first (the usual view)
}

-- ── Rank tier ─────────────────────────────────────────────────────────────

local RANK_ORDER = {
    ["Trader"]       = 1,  ["Engineer"]     = 2,  ["Merchant"]     = 3,
    ["Manufacturer"] = 4,  ["Industrialist"]= 5,  ["Financier"]    = 6,
    ["Mogul"]        = 7,  ["Magnate"]      = 8,  ["Technocrat"]   = 9,
    ["Gengineer"]    = 10, ["Founder"]      = 11, ["Plutocrat"]    = 12,
    ["Commander"]    = 13,
}

-- ── Hex → cecho named-color map ───────────────────────────────────────────
-- Maps the game's exact ANSI RGB values to cecho-compatible color names.
-- These are the web standard colors that Mudlet's cecho recognises.

local HEX_TO_CECHO = {
    ["#800000"] = "ansiRed",    -- Plutocrat (non-staff)
    ["#808000"] = "olive_drab",     -- Plutocrat (staff) / Navigator
    ["#008000"] = "ansiGreen",     -- Manufacturer, Financier, Industrialist
    ["#008080"] = "ansiCyan",      -- Engineer, Mogul, Magnate, Gengineer, Founder, Technocrat
    ["#800080"] = "dark_violet",    -- Commander
    ["#c0c0c0"] = "mint_cream",    -- Trader, Merchant
    ["#ffffff"] = "white",
}
local function _cecho_color(hex)
    return HEX_TO_CECHO[hex:lower()] or "white"
end

-- ── Parser ────────────────────────────────────────────────────────────────
-- Extracts rank, name, and staff badge only.
-- raw_line and color are stamped on by ui_who_line() after the call.

function ui_who_parse_line(raw)
    local line = raw:match("^%s*(.-)%s*$")
    if line == "" then return nil end

    -- Strip trailing [Badge]
    local staff = ""
    line = line:gsub("%s+%[(%a+)%]%s*$", function(b) staff = b; return "" end)
    line = line:match("^%s*(.-)%s*$")

    -- Rank (first word)
    local rank = line:match("^(%a+)")
    if not rank then return nil end

    -- Name (second word, after rank)
    local after_rank = line:sub(#rank + 1):match("^%s*(.*)")
    local name = after_rank and after_rank:match("^(%a+)") or ""
    if name == "" then return nil end

    return {
        rank       = rank,
        rank_order = RANK_ORDER[rank] or 0,
        name       = name,
        staff      = staff,
        color      = "#c0c0c0",  -- overwritten by trigger
        raw_line   = "",          -- overwritten by trigger
    }
end

-- ── Trigger callbacks ─────────────────────────────────────────────────────

function ui_who_start()
    UI.who.parsing = true
    UI.who.players = {}
    f2t_debug_log("[who] parse start")
end

function ui_who_line()
    if not UI.who.parsing then return end

    -- Capture the game's assigned color for this line before we do anything else
    local hex_color = "#c0c0c0"
    local trimmed   = line:match("^%s+(.+)")
    if trimmed then
        selectString(trimmed, 1)
        local r, g, b = getFgColor()
        deselect()
        hex_color = string.format("#%02x%02x%02x", r, g, b)
    end

    -- Standalone [Badge] line: the game occasionally wraps Navigator/Manager
    -- onto its own line directly below the player it belongs to.
    local solo_badge = line:match("^%s*%[(%a+)%]%s*$")
    if solo_badge and #UI.who.players > 0 then
        local last = UI.who.players[#UI.who.players]
        if last.staff == "" then
            last.staff    = solo_badge
            last.raw_line = last.raw_line .. " [" .. solo_badge .. "]"
        end
        return
    end

    local parsed = ui_who_parse_line(line)
    if parsed then
        parsed.color    = hex_color
        parsed.raw_line = trimmed or line:match("^%s*(.-)%s*$")
        table.insert(UI.who.players, parsed)
    end
end

function ui_who_end()
    if not UI.who.parsing then return end
    UI.who.parsing = false

    local total, stf    = line:match("(%d+) players, (%d+) staff")
    UI.who.count        = tonumber(total) or #UI.who.players
    UI.who.staff_count  = tonumber(stf)   or 0

    f2t_debug_log("[who] parsed %d players", #UI.who.players)

    if UI.who_header then
        UI.who_header:echo(string.format(
            "  👥  Online: %d players, %d staff",
            UI.who.count, UI.who.staff_count))
    end

    ui_who_render()
end

-- ── Sort ──────────────────────────────────────────────────────────────────

function ui_who_sort(field)
    if UI.who.sort_by == field then
        UI.who.sort_asc = not UI.who.sort_asc
    else
        UI.who.sort_by  = field
        -- Name sorts A→Z by default; rank sorts high→low by default
        UI.who.sort_asc = (field == "name")
    end
    ui_who_render()
end

-- ── Render ────────────────────────────────────────────────────────────────

function ui_who_render()
    if not UI.who_window then return end
    UI.who_window:clear()

    local players = UI.who.players
    if #players == 0 then
        UI.who_window:cecho("<dim_grey>No players online.\n")
        return
    end

    -- Sort
    local sorted = {}
    for _, p in ipairs(players) do table.insert(sorted, p) end

    table.sort(sorted, function(a, b)
        if UI.who.sort_by == "name" then
            if UI.who.sort_asc then return a.name < b.name end
            return a.name > b.name
        else
            -- rank_order, with name as tiebreaker (always A→Z within same rank)
            if a.rank_order ~= b.rank_order then
                if UI.who.sort_asc then return a.rank_order < b.rank_order end
                return a.rank_order > b.rank_order
            end
            return a.name < b.name
        end
    end)

    -- Sort indicator arrows
    local function _ind(field)
        if UI.who.sort_by ~= field then return "  " end
        return UI.who.sort_asc and " ↑" or " ↓"
    end

    -- Header row with clickable sort links
    UI.who_window:cechoLink(
        "<white>" .. string.format("%-13s", "Rank") .. _ind("rank_order") .. "<reset>",
        function() ui_who_sort("rank_order") end,
        "Sort by rank",
        true
    )
    UI.who_window:cecho("  ")
    UI.who_window:cechoLink(
        "<white>" .. string.format("%-16s", "Name") .. _ind("name") .. "<reset>",
        function() ui_who_sort("name") end,
        "Sort by name",
        true
    )
    UI.who_window:cecho("\n<dim_grey>" .. string.rep("─", 33) .. "<reset>\n")

    -- Player rows
    for _, row in ipairs(sorted) do
        local cc = _cecho_color(row.color)

        -- Staff chip: small [Nav]/[Mgr] suffix in olive
        local staff_str = ""
        if row.staff and row.staff ~= "" then
            staff_str = " <olive_drab>[" .. row.staff:sub(1, 3) .. "]<reset>"
        end

        -- Each row is a single cechoLink — clicking appends a tell command
        UI.who_window:cechoLink(
            string.format("<%s>%-13s<reset>  <white>%-16s<reset>%s",
                cc, row.rank, row.name, staff_str),
            function() appendCmdLine("tell " .. row.name .. " ") end,
            row.raw_line,
            true
        )
        UI.who_window:cecho("\n")
    end
end

-- ── Refresh ───────────────────────────────────────────────────────────────

function ui_who_refresh()
    if UI.who_window then
        UI.who.parsing = true
        UI.who_window:clear()
        UI.who_window:cecho("<dim_grey>Fetching who list...\n")
    end
    send("who", false)
end

-- ── Init ──────────────────────────────────────────────────────────────────
-- Called from ui_build(). Sets up initial state and wires the tab-switch
-- auto-refresh via the Who tab label's click callback.

function ui_who_init()
    UI.who.sort_by  = UI.who.sort_by  or "rank_order"
    UI.who.sort_asc = (UI.who.sort_asc ~= nil) and UI.who.sort_asc or false

    if UI.who_window then
        UI.who_window:clear()
        UI.who_window:cecho("<dim_grey>Click ⟳ or switch to this tab to load the who list.\n")
    end

    -- Wire auto-refresh on tab switch: preserve TabWindow's own onClick, then refresh
    local tw  = UI.tab_bottom_left
    local tab = tw and tw.Who
    if tab and tab.adjLabel then
        tab.adjLabel:setClickCallback(function(event)
            tw:onClick("Who", event)
            ui_who_refresh()
        end)
        f2t_debug_log("[who] tab click auto-refresh wired")
    end

    f2t_debug_log("[who] init complete")
end