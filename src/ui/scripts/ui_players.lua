-- =============================================================================
-- ui_players  —  online player list backed by gmcp.players
-- Mudlet Script location: ui > ui_players
-- =============================================================================

UI     = UI or {}
UI.who = UI.who or {
    players       = {},
    count         = 0,
    staff_count   = 0,
    name_colors   = {},   -- name → cecho color string  (shared with ui_chat)
    name_rawlines = {},   -- name → summary line         (shared with ui_chat)
}

-- Each open contact card lives here; keyed by card generation number.
UI.player_cards = UI.player_cards or {}
-- name → card generation number (for dedup and refresh lookups)
UI.player_cards_by_name = UI.player_cards_by_name or {}

-- ── Rank ordering ──────────────────────────────────────────────────────────────

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

-- ── Rank → cecho color (table + shared with ui_chat) ──────────────────────────

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

-- ── Rank → CSS accent color (contact card border / name / badges) ─────────────

local RANK_CARD_COLOR = {
    ["Groundhog"]     = "rgba(110, 40, 190, 255)",
    ["Commander"]     = "rgba(110, 40, 190, 255)",
    ["Captain"]       = "rgba(180, 180, 230, 255)",
    ["Adventurer"]    = "rgba(180, 180, 230, 255)",
    ["Merchant"]      = "rgba(195, 235, 195, 255)",
    ["Trader"]        = "rgba(195, 235, 195, 255)",
    ["Industrialist"] = "rgba(50, 205, 90, 255)",
    ["Manufacturer"]  = "rgba(50, 205, 90, 255)",
    ["Financier"]     = "rgba(50, 205, 90, 255)",
    ["Mogul"]         = "rgba(0, 215, 235, 255)",
    ["Engineer"]      = "rgba(0, 215, 235, 255)",
    ["Technocrat"]    = "rgba(0, 215, 235, 255)",
    ["Gengineer"]     = "rgba(0, 215, 235, 255)",
    ["Magnate"]       = "rgba(0, 215, 235, 255)",
    ["Founder"]       = "rgba(0, 215, 235, 255)",
    ["Plutocrat"]     = "rgba(215, 65, 65, 255)",
}
local RANK_CARD_COLOR_DEFAULT = "rgba(120, 125, 155, 255)"

local function _color_for(row)
    if row.rank == "Plutocrat" and (row.staff or "") ~= "" then
        return "olive_drab"
    end
    return RANK_COLOR[row.rank] or RANK_COLOR_DEFAULT
end

-- ── GMCP data handler ─────────────────────────────────────────────────────────

function ui_who_from_gmcp()
    if not (gmcp and gmcp.players and gmcp.players.online) then return end

    local online = gmcp.players.online
    local counts = gmcp.players.count or {}

    -- Mark all DB players offline before processing fresh list
    if ui_player_db_mark_all_offline then ui_player_db_mark_all_offline() end

    UI.who.players = {}
    for _, p in pairs(online) do
        local entry = {
            rank       = p.rank       or "",
            rank_order = RANK_ORDER[p.rank] or 0,
            name       = p.name       or "",
            location   = p.location   or "",
            staff      = p.staff_role or "",
            titles     = p.titles     or {},
            company    = p.company    or "",
            system     = p.system     or "",
            cartel     = p.cartel     or "",
            ship_class = p.ship_class or "",
        }
        entry.cecho_color = _color_for(entry)
        local sum = { entry.rank, entry.name }
        if entry.location ~= "" then sum[#sum + 1] = "at " .. entry.location end
        entry.raw_line = table.concat(sum, " ")
        table.insert(UI.who.players, entry)
        -- Persist to DB
        if ui_player_db_upsert then
            entry.is_online = true
            ui_player_db_upsert(entry)
            entry.is_online = nil  -- strip from the online-list entry
        end
    end

    UI.who.count       = tonumber(counts.players) or #UI.who.players
    UI.who.staff_count = tonumber(counts.staff)   or 0

    UI.who.name_colors   = {}
    UI.who.name_rawlines = {}
    for _, p in ipairs(UI.who.players) do
        UI.who.name_colors[p.name]   = p.cecho_color
        UI.who.name_rawlines[p.name] = p.raw_line
    end

    if UI.who_header then
        UI.who_header:echo(string.format(
            "  👥  Online: %d players, %d staff",
            UI.who.count, UI.who.staff_count))
    end

    ui_who_set_table_data()

    if ui_chat_replay    then ui_chat_replay()    end
    if ui_general_replay then ui_general_replay() end

    if ui_player_db_save then ui_player_db_save() end

    ui_player_cards_refresh_all()

    f2t_debug_log("[who] gmcp update: %d players", #UI.who.players)
end

function ui_who_refresh()
    if UI.who_header then UI.who_header:echo("  👥  Refreshing…") end
    ui_who_from_gmcp()
end

-- Called by ui_chat for unknown names; no-op since GMCP is authoritative.
function ui_who_request_refresh() end

-- Kept as no-op so any lingering event wiring doesn't error.
function ui_who_on_login_vitals() end

-- Push the right dataset into the who_list table depending on toggle state.
function ui_who_set_table_data()
    if UI.who._show_all and ui_player_db_get then
        -- Merge online players with offline DB entries
        local all = {}
        for _, p in ipairs(UI.who.players) do
            all[#all + 1] = p
        end
        if ui_player_db_get_offline then
            for _, e in ipairs(ui_player_db_get_offline()) do
                all[#all + 1] = e
            end
        end
        ui_table_set_data("who_list", all)
    else
        ui_table_set_data("who_list", UI.who.players)
    end
end

-- Toggle between Online-only and All-known-players view.
function ui_who_toggle_view()
    UI.who._show_all = not (UI.who._show_all or false)
    if UI.who_toggle_btn then
        if UI.who._show_all then
            UI.who_toggle_btn:echo("<center>All</center>")
            UI.who_toggle_btn:setToolTip("Showing all known players — click for Online only")
        else
            UI.who_toggle_btn:echo("<center>Online</center>")
            UI.who_toggle_btn:setToolTip("Showing online only — click for All known players")
        end
    end
    ui_who_set_table_data()
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- CONTACT CARD POPUP
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Button styles ─────────────────────────────────────────────────────────────

local _CSS_CLOSE = [[
    QLabel {
        background-color: rgba(180, 50, 50, 220);
        border: 1px solid rgba(200, 80, 80, 180);
        border-radius: 3px;
        color: white;
        font-size: 14px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(215, 60, 60, 245); border-color: rgba(255, 110, 110, 220); }
]]

-- Green nav arrow — matches the galaxy navigator's nav button style
local _CSS_NAV = [[
    QLabel {
        background-color: rgba(40, 120, 80, 210);
        border: 1px solid rgba(60, 140, 100, 180);
        border-radius: 3px;
        color: white;
        font-size: 10px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(55, 150, 95, 230); }
]]

-- Galaxy navigator button (🔭)
local _CSS_GAL = [[
    QLabel {
        background-color: rgba(18, 22, 52, 210);
        color: rgba(120, 155, 255, 255);
        border: 1px solid rgba(75, 95, 200, 200);
        border-radius: 3px;
        font-size: 12px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(30, 40, 90, 235);
        border-color: rgba(110, 140, 255, 255);
        color: rgba(180, 205, 255, 255);
    }
]]

-- Company icon buttons (info / accounts)
local _CSS_ICON = [[
    QLabel {
        background-color: rgba(32, 36, 58, 220);
        color: rgba(165, 180, 220, 255);
        border: 1px solid rgba(80, 92, 140, 210);
        border-radius: 4px;
        font-size: 14px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(50, 58, 95, 240);
        border-color: rgba(110, 125, 195, 255);
        color: rgba(210, 225, 255, 255);
    }
]]

-- ── Card counter (module-level so it persists across multiple opens) ──────────
local _card_n = 0

-- Cheap fingerprint of the fields that affect card layout/content.
-- Only rebuild open cards when this string changes.
local function _player_fingerprint(p)
    return table.concat({
        p.rank or "", p.location or "", p.company or "",
        p.system or "", p.cartel or "", p.ship_class or "",
        p.staff or "", tostring(p.is_online == false),
    }, "\0")
end

-- ── Public: close one card ────────────────────────────────────────────────────

function ui_player_card_close(card_id)
    local c = UI.player_cards[card_id]
    if c then
        for _, h in ipairs(c.resize_handlers or {}) do
            killAnonymousEventHandler(h)
        end
        if c.action_key then
            _G[c.action_key] = nil
        end
        c.container:hide()
        if c.player_name then
            UI.player_cards_by_name[c.player_name] = nil
        end
        UI.player_cards[card_id] = nil
    end
end

-- ── Public: show a new independent card ──────────────────────────────────────

-- pos: optional {x=, y=} to override centered placement (used for in-place refresh)
function ui_player_card_show(player, pos)
    local name = player.name or "Unknown"

    -- Dedup: raise existing card instead of opening a duplicate
    local existing_id = UI.player_cards_by_name[name]
    if existing_id and UI.player_cards[existing_id] then
        UI.player_cards[existing_id].container:raiseAll()
        return
    end

    _card_n = _card_n + 1
    local n = _card_n

    local rank      = player.rank      or "Unknown"
    local loc       = player.location  or ""
    local company   = player.company   or ""
    local system    = player.system    or ""
    local cartel    = player.cartel    or ""
    local staff     = player.staff     or ""
    local ship      = player.ship_class or ""
    local titles    = player.titles    or {}
    local is_offline = (player.is_online == false)
    local last_seen  = player.last_seen   -- nil if online / unknown

    -- Offline cards use a muted grey accent so the border signals status
    local accent = is_offline
        and "rgba(90, 90, 100, 200)"
        or  (RANK_CARD_COLOR[rank] or RANK_CARD_COLOR_DEFAULT)

    -- ── Ownership classification ────────────────────────────────────────────
    local has_company   = company ~= ""
    local is_industrial = rank == "Industrialist"
    local is_mfr_fin    = rank == "Manufacturer" or rank == "Financier"
    local has_system    = system ~= "" and (
        rank == "Engineer"  or rank == "Technocrat" or rank == "Gengineer" or
        rank == "Magnate"   or rank == "Founder"    or rank == "Mogul")
    local has_cartel    = cartel ~= "" and rank == "Plutocrat"
    local has_ship      = ship   ~= ""
    local has_ownership = (has_company and (is_industrial or is_mfr_fin)) or has_system or has_cartel

    -- ── Layout constants ────────────────────────────────────────────────────
    local HDR_H   = 44
    local DIV_H   = 2
    local ROW_H   = 26
    local LOC_GAP = 16   -- space for visible separator line + breathing room between location and ownership
    local BTN_W   = 26   -- nav and galaxy buttons
    local ICON_W  = 30   -- company icon buttons (wider for emoji clarity)
    local GAP     = 3    -- gap between buttons
    local R_M     = 4    -- right margin inside inner container
    local CMD_H   = 30   -- quick-send commandline height
    local SEND_W  = 34   -- quick-send button width
    local CMD_L_M = 4    -- commandline left margin (flush with card border)
    local CMD_R_M = 8    -- send button right margin (keeps button inside card border)

    -- Negative positioning strings (Geyser right-anchor: "-N" = parent_width - N)
    -- Two-button rows (nav + galaxy):
    local NAV_X_2  = tostring(-(BTN_W + GAP + BTN_W + R_M))          -- "-59"
    local GAL_X    = tostring(-(BTN_W + R_M))                          -- "-30" (all gal)
    local TEXT_W_2 = tostring(-(BTN_W + GAP + BTN_W + GAP + R_M))     -- "-62"
    -- One-button rows (galaxy only):
    local TEXT_W_1 = tostring(-(BTN_W + GAP + R_M))                    -- "-33"
    -- Company rows with accounts button:
    local ACCT_X   = tostring(-(ICON_W + R_M))                         -- "-34"
    local TEXT_W_A = tostring(-(ICON_W + GAP + R_M))                   -- "-37"

    -- ── Header width calculation ─────────────────────────────────────────────
    local function _badge_px(s) return math.ceil(#s * 6.5) + 16 end
    local name_lbl_w    = math.ceil(#name * 9.0) + 16
    local rank_badge_w  = _badge_px(rank)
    local staff_badge_w = staff ~= "" and _badge_px("[" .. staff .. "]") or 0
    local close_w       = 28
    local header_need   = 10 + name_lbl_w + 6 + rank_badge_w
        + (staff ~= "" and (4 + staff_badge_w) or 0)
        + 10 + close_w + 6

    -- Body width: longest row text + label prefix + button allowance
    local longest = math.max(
        #(loc ~= "" and loc or "Unknown"),
        has_company and (#company + 10) or 0,
        has_system  and (#system  + 8)  or 0,
        has_cartel  and (#cartel  + 8)  or 0
    )
    local body_need = math.ceil(longest * 7.0) + 30 + 62

    local CARD_W = math.max(360, math.min(580, math.max(header_need, body_need)))

    -- Right-anchored negative-string widths/positions for the quick-send row
    -- (same Geyser convention as nav/galaxy buttons: "-N" = parent_width - N)
    local SEND_X    = tostring(-(SEND_W + CMD_R_M))                   -- send btn left edge
    local CMD_W     = tostring(-(SEND_W + GAP + CMD_R_M + CMD_L_M))   -- cmdline width
    local FRAME_W   = tostring(-(SEND_W + GAP + CMD_R_M + CMD_L_M - 2)) -- frame = 2px wider

    -- ── Height calculation (screen-aware, titles capped to fit) ─────────────
    local sw, sh = getMainWindowSize()

    local body_top = HDR_H + DIV_H
    -- Fixed rows: offline banner (if applicable), location + separator gap + optional ownership/ship
    local OFFLINE_H = is_offline and ROW_H or 0
    local base_h = body_top + OFFLINE_H + ROW_H
    if has_ownership            then base_h = base_h + LOC_GAP end
    if has_company and is_industrial then base_h = base_h + ROW_H end
    if has_company and is_mfr_fin    then base_h = base_h + ROW_H end
    if has_system               then base_h = base_h + ROW_H end
    if has_cartel               then base_h = base_h + ROW_H end
    if has_ship                 then base_h = base_h + ROW_H end

    -- Quick-send area: omitted for offline cards
    local quick_h = is_offline and 0 or (10 + CMD_H + 22)

    -- Titles section overhead (divider + header row)
    local TITLE_OVERHEAD = 10 + ROW_H  -- = 36

    -- Max card height: leave 80px of screen margin
    local max_card_h = sh - 80

    -- How many titles fit in remaining space?
    local avail_for_titles = max_card_h - base_h - quick_h
    local title_count = #titles
    local shown_titles = 0
    if title_count > 0 and avail_for_titles >= (TITLE_OVERHEAD + 22) then
        shown_titles = math.min(title_count, math.floor((avail_for_titles - TITLE_OVERHEAD) / 22))
    end

    local CARD_H = base_h
        + (shown_titles > 0 and (TITLE_OVERHEAD + shown_titles * 22) or 0)
        + quick_h

    -- ── Create Adjustable.Container ─────────────────────────────────────────
    local offset = (_card_n - 1) % 10 * 22
    local cx = pos and pos.x or (math.floor((sw - CARD_W) / 2) + offset)
    local cy = pos and pos.y or (math.floor((sh - CARD_H) / 2) + offset)

    local card_name = string.format("ui_player_card_%d", n)
    local card = Adjustable.Container:new({
        name          = card_name,
        x             = cx, y = cy,
        width         = CARD_W, height = CARD_H,
        adjLabelstyle = string.format([[
            background-color: rgba(10, 12, 22, 252);
            border: 2px solid %s;
            border-radius: 6px;
        ]], accent),
        autoSave = false,
        autoLoad = false,
    })
    card:lockContainer("border")
    card.locked = false   -- keep draggable

    -- Snap back to locked dimensions on resize. Register under several possible
    -- event names because the exact name varies across Mudlet versions.
    local resize_handlers = {}
    local function _snap(_, resized_name)
        if resized_name == card_name then card:resize(CARD_W, CARD_H) end
    end
    for _, evt in ipairs({ "AdjustableContainerResize", "AdjustableContainerResized",
                            "AdjustableContainerResizeFinish" }) do
        table.insert(resize_handlers, registerAnonymousEventHandler(evt, _snap))
    end

    -- quick_cmd_name must be defined here so the action closure can reference it
    local quick_cmd_name = string.format("uipc%d_qcmd", n)

    local action_key = string.format("_ui_qsend_%d", n)
    _G[action_key] = not is_offline and function(text)
        if text and text ~= "" then
            send(string.format("tb %s %s", name, text), false)
            clearCmdLine(quick_cmd_name)
        end
    end or nil

    UI.player_cards[n] = {
        container       = card,
        resize_handlers = resize_handlers,
        action_key      = action_key,
        player_name     = name,
        fingerprint     = _player_fingerprint(player),
    }
    UI.player_cards_by_name[name] = n
    local _in = card.Inside

    local wc = 0
    local function wid() wc = wc + 1; return string.format("uipc%d_%d", n, wc) end

    -- ── Header ──────────────────────────────────────────────────────────────
    local hdr = Geyser.Label:new({ name=wid(), x=0, y=0, width="100%", height=HDR_H }, _in)
    hdr:setStyleSheet([[
        background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
            stop:0 rgba(30,34,54,255), stop:1 rgba(16,18,32,255));
        border: none; border-radius: 4px 4px 0 0;
    ]])

    local hdr_y = math.floor((HDR_H - 22) / 2)

    -- Player name — clicking fills main command line with "tb name "
    local name_lbl = Geyser.Label:new({ name=wid(), x=10, y=hdr_y-2, width=name_lbl_w, height=26 }, hdr)
    name_lbl:setStyleSheet(string.format([[
        background: transparent; border: none;
        color: %s;
        font-size: 14px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
    ]], accent))
    name_lbl:echo("<u>" .. name .. "</u>")
    name_lbl:setClickCallback(function()
        send("spynet report " .. name)
    end)
    name_lbl:setToolTip("Spynet report: " .. name)

    -- Rank badge
    local rank_x = 10 + name_lbl_w + 6
    local rlbl = Geyser.Label:new({ name=wid(), x=rank_x, y=hdr_y, width=rank_badge_w, height=22 }, hdr)
    rlbl:setStyleSheet(string.format([[
        background: rgba(20,22,38,200);
        color: %s;
        font-size: 10px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        border: 1px solid %s;
        border-radius: 3px;
        qproperty-alignment: AlignCenter;
    ]], accent, accent))
    rlbl:echo(rank)

    -- Staff badge (inline, right of rank)
    if staff ~= "" then
        local staff_x = rank_x + rank_badge_w + 4
        local slbl = Geyser.Label:new({ name=wid(), x=staff_x, y=hdr_y, width=staff_badge_w, height=22 }, hdr)
        slbl:setStyleSheet([[
            background: rgba(100, 80, 0, 180);
            color: rgba(255, 215, 70, 255);
            font-size: 9px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            border: 1px solid rgba(200, 165, 0, 160);
            border-radius: 3px;
            qproperty-alignment: AlignCenter;
        ]])
        slbl:echo(string.format("[%s]", staff))
    end

    -- Close button (red, right-anchored via negative x)
    local close_btn = Geyser.Label:new({
        name=wid(), x=tostring(-(close_w + 4)), y=hdr_y-1, width=close_w, height=24
    }, hdr)
    close_btn:setStyleSheet(_CSS_CLOSE)
    close_btn:echo("<center>✕</center>")
    close_btn:setClickCallback(function() ui_player_card_close(n) end)

    -- ── Header divider ───────────────────────────────────────────────────────
    local div = Geyser.Label:new({ name=wid(), x=0, y=HDR_H, width="100%", height=DIV_H }, _in)
    div:setStyleSheet("background-color: rgba(255,255,255,0.09); border: none;")

    -- ── Row helpers ─────────────────────────────────────────────────────────

    local row_y = body_top
    local _TEXT_CSS_BASE = [[
        background: transparent; border: none;
        font-size: 12px; font-family: "Consolas","Monaco",monospace;
        padding: 0 8px;
    ]]
    local _LABEL_HTML = "<span style='color: rgb(120,130,170);'>%s:</span> "

    -- Clickable text row with optional nav (→) and/or galaxy (🔭) buttons.
    -- opts = {
    --   icon, label (optional muted prefix), text, text_color,
    --   di_cmd     = string sent on text click (nil = non-clickable),
    --   nav_cmd    = expandAlias string for → button (nil = no nav button),
    --   galaxy_fn  = function for 🔭 button (nil = no galaxy button),
    --   di_tooltip = override tooltip for text click,
    -- }
    local function add_link_row(opts)
        local has_nav = opts.nav_cmd ~= nil
        local has_gal = opts.galaxy_fn ~= nil

        local text_w, nav_x, gal_x
        if has_nav and has_gal then
            text_w = TEXT_W_2; nav_x = NAV_X_2; gal_x = GAL_X
        elseif has_gal then
            text_w = TEXT_W_1; gal_x = GAL_X
        else
            text_w = tostring(-R_M)
        end

        local label_html = opts.label and string.format(_LABEL_HTML, opts.label) or ""
        local txt = Geyser.Label:new({ name=wid(), x=0, y=row_y, width=text_w, height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. string.format("color: %s;", opts.text_color))
        if opts.di_cmd then
            txt:echo(string.format("  %s  %s<u>%s</u>", opts.icon, label_html, opts.text))
            txt:setClickCallback(function() send(opts.di_cmd) end)
            txt:setToolTip(opts.di_tooltip or opts.di_cmd)
        else
            txt:echo(string.format("  %s  %s%s", opts.icon, label_html, opts.text))
        end

        if has_nav then
            local nb = Geyser.Label:new({ name=wid(), x=nav_x, y=row_y+2, width=BTN_W, height=ROW_H-4 }, _in)
            nb:setStyleSheet(_CSS_NAV)
            nb:echo("<center>→</center>")
            nb:setClickCallback(function() expandAlias(opts.nav_cmd) end)
            nb:setToolTip("Navigate to " .. opts.text)
        end

        if has_gal then
            local gb = Geyser.Label:new({ name=wid(), x=gal_x, y=row_y+2, width=BTN_W, height=ROW_H-4 }, _in)
            gb:setStyleSheet(_CSS_GAL)
            gb:echo("<center>🔭</center>")
            gb:setClickCallback(opts.galaxy_fn)
            gb:setToolTip("View in Galaxy Navigator")
        end

        row_y = row_y + ROW_H
    end

    -- Company row: icon text + optional accounts (📊) button.
    -- opts = { icon, label, text, text_color, di_cmd, di_tooltip, acct_cmd }
    local function add_company_row(opts)
        local has_acct = opts.acct_cmd ~= nil
        local text_w   = has_acct and TEXT_W_A or tostring(-R_M)

        local label_html = opts.label and string.format(_LABEL_HTML, opts.label) or ""
        local txt = Geyser.Label:new({ name=wid(), x=0, y=row_y, width=text_w, height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. string.format("color: %s;", opts.text_color))
        if opts.di_cmd then
            txt:echo(string.format("  %s  %s<u>%s</u>", opts.icon, label_html, opts.text))
            txt:setClickCallback(function() send(opts.di_cmd) end)
            txt:setToolTip(opts.di_tooltip or opts.di_cmd)
        else
            txt:echo(string.format("  %s  %s%s", opts.icon, label_html, opts.text))
        end

        if has_acct then
            local ab = Geyser.Label:new({ name=wid(), x=ACCT_X, y=row_y+2, width=ICON_W, height=ROW_H-4 }, _in)
            ab:setStyleSheet(_CSS_ICON)
            ab:echo("<center>📊</center>")
            ab:setClickCallback(function() send(opts.acct_cmd) end)
            ab:setToolTip("View accounts  (di accounts " .. opts.text .. ")")
        end

        row_y = row_y + ROW_H
    end

    -- ── Offline banner ────────────────────────────────────────────────────────
    if is_offline then
        local ago_str = (ui_player_db_last_seen_str and last_seen)
            and ("Last seen " .. ui_player_db_last_seen_str(last_seen))
            or  "Offline"
        local off_lbl = Geyser.Label:new({ name=wid(), x=0, y=row_y, width="100%", height=ROW_H }, _in)
        off_lbl:setStyleSheet([[
            background: rgba(60, 30, 30, 180);
            border: none;
            color: rgba(200, 140, 140, 255);
            font-size: 11px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        ]])
        off_lbl:echo("⊘ OFFLINE  —  " .. ago_str)
        row_y = row_y + ROW_H
    end

    -- ── Location row ─────────────────────────────────────────────────────────
    local loc_text = loc ~= "" and loc or "Unknown"
    local loc_sys  = loc_text:match("^(.+) Space$")
    local di_loc   = loc_sys and ("di system " .. loc_sys) or ("di planet " .. loc_text)
    local nav_loc  = loc_sys and ("nav " .. loc_sys .. " link") or ("nav " .. loc_text)

    add_link_row({
        icon       = "📍",
        text       = loc_text,
        text_color = "rgba(130, 200, 255, 255)",
        di_cmd     = di_loc,
        di_tooltip = "Get info  (" .. di_loc .. ")",
        nav_cmd    = nav_loc,
        galaxy_fn  = function()
            if loc_sys then
                ui_player_card_open_galaxy(nil, loc_sys)
            else
                ui_player_card_open_galaxy(nil, loc_text)
            end
        end,
    })

    -- Visible separator between location and ownership rows
    if has_ownership then
        local sep = Geyser.Label:new({ name=wid(), x=4, y=row_y+7, width=CARD_W-8, height=1 }, _in)
        sep:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")
        row_y = row_y + LOC_GAP
    end

    -- ── Company section ───────────────────────────────────────────────────────
    if has_company then
        if is_industrial then
            add_company_row({
                icon       = "🏢",
                label      = "Business",
                text       = company,
                text_color = "rgba(160, 255, 160, 255)",
                di_cmd     = "di business " .. company,
                di_tooltip = "Get business info  (di business " .. company .. ")",
            })
        elseif is_mfr_fin then
            add_company_row({
                icon       = "🏭",
                label      = "Company",
                text       = company,
                text_color = "rgba(160, 255, 160, 255)",
                di_cmd     = "di company " .. company,
                di_tooltip = "Get company info  (di company " .. company .. ")",
                acct_cmd   = "di accounts " .. company,
            })
        end
    end

    -- ── System section ────────────────────────────────────────────────────────
    if has_system then
        add_link_row({
            icon       = "⭐",
            label      = "System",
            text       = system,
            text_color = "rgba(255, 228, 100, 255)",
            di_cmd     = "di system " .. system,
            di_tooltip = "Get system info  (di system " .. system .. ")",
            nav_cmd    = "nav " .. system .. " link",
            galaxy_fn  = function() ui_player_card_open_galaxy(nil, system) end,
        })
    end

    -- ── Cartel section ────────────────────────────────────────────────────────
    if has_cartel then
        add_link_row({
            icon       = "🌌",
            label      = "Cartel",
            text       = cartel,
            text_color = "rgba(255, 150, 200, 255)",
            di_cmd     = "di cartel " .. cartel,
            di_tooltip = "Get cartel info  (di cartel " .. cartel .. ")",
            galaxy_fn  = function() ui_player_card_open_galaxy(cartel, nil) end,
        })
    end

    -- ── Ship class ────────────────────────────────────────────────────────────
    if has_ship then
        local txt = Geyser.Label:new({ name=wid(), x=0, y=row_y, width=tostring(-R_M), height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. "color: rgba(160, 165, 215, 255);")
        txt:echo("  🚀  " .. ship)
        row_y = row_y + ROW_H
    end

    -- ── Titles section (capped to shown_titles) ───────────────────────────────
    if shown_titles > 0 then
        local tdiv = Geyser.Label:new({ name=wid(), x=4, y=row_y+4, width=CARD_W-8, height=1 }, _in)
        tdiv:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")
        row_y = row_y + 10

        local thdr = Geyser.Label:new({ name=wid(), x=0, y=row_y, width="100%", height=ROW_H }, _in)
        thdr:setStyleSheet([[
            background: transparent; border: none;
            color: rgba(130, 140, 185, 255);
            font-size: 10px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            padding: 0 10px;
        ]])
        local title_hdr_text = shown_titles < title_count
            and string.format("  Titles  <span style='color: rgb(160,100,100);'>(showing %d of %d)</span>", shown_titles, title_count)
            or  "  Titles"
        thdr:echo(title_hdr_text)
        row_y = row_y + ROW_H

        for i = 1, shown_titles do
            local tl = Geyser.Label:new({ name=wid(), x=0, y=row_y, width="100%", height=22 }, _in)
            tl:setStyleSheet([[
                background: transparent; border: none;
                color: rgba(175, 185, 225, 200);
                font-size: 11px;
                font-family: "Consolas","Monaco",monospace;
                padding: 0 10px;
            ]])
            tl:echo("  · " .. titles[i])
            row_y = row_y + 22
        end
    end

    -- ── Quick-send area (online only) ─────────────────────────────────────────
    if not is_offline then
        local qdiv = Geyser.Label:new({ name=wid(), x=4, y=row_y+4, width=CARD_W-8, height=1 }, _in)
        qdiv:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")

        local cmd_y = row_y + 10

        local cmd_frame = Geyser.Label:new({
            name   = wid(),
            x      = CMD_L_M - 2,
            y      = cmd_y - 2,
            width  = FRAME_W,
            height = CMD_H + 4,
        }, _in)
        cmd_frame:setStyleSheet(string.format([[
            background: rgba(18, 20, 38, 235);
            border: 2px solid %s;
            border-radius: 4px;
        ]], accent))

        local quick_cmd = Geyser.CommandLine:new({
            name   = quick_cmd_name,
            x      = CMD_L_M,
            y      = cmd_y,
            width  = CMD_W,
            height = CMD_H,
        }, _in)
        quick_cmd:setStyleSheet([[
            QPlainTextEdit {
                background: transparent;
                color: rgba(198, 210, 238, 255);
                border: none;
                font-size: 12px;
                font-family: "Consolas","Monaco",monospace;
                padding: 2px 6px;
            }
            QPlainTextEdit::placeholder {
                color: rgba(110, 120, 160, 200);
                font-style: italic;
            }
        ]])
        quick_cmd:setAction(action_key)
        if setCommandLineAction then
            setCommandLineAction(quick_cmd_name, action_key)
        end

        local send_btn = Geyser.Label:new({
            name   = wid(),
            x      = SEND_X,
            y      = cmd_y - 2,
            width  = SEND_W,
            height = CMD_H + 4,
        }, _in)
        send_btn:setStyleSheet(string.format([[
            QLabel {
                background-color: rgba(14, 17, 34, 245);
                color: %s;
                border: 2px solid %s;
                border-radius: 4px;
                font-size: 18px;
                font-weight: bold;
                qproperty-alignment: AlignCenter;
            }
            QLabel::hover {
                background-color: rgba(26, 30, 58, 255);
                color: rgba(220, 235, 255, 255);
            }
        ]], accent, accent))
        send_btn:echo("<center>▶</center>")
        send_btn:setClickCallback(function()
            local text = getCmdLine(quick_cmd_name)
            if text and text ~= "" then
                send(string.format("tb %s %s", name, text), false)
                clearCmdLine(quick_cmd_name)
            end
        end)
    end -- not is_offline

    card:hide()
    card:show()
    card:raiseAll()
end

-- ── Card helpers ─────────────────────────────────────────────────────────────

-- Show a card or raise it if already open (accepts a player data table).
function ui_player_card_show_or_raise(player)
    local name = player and player.name
    if not name then return end
    local existing_id = UI.player_cards_by_name[name]
    if existing_id and UI.player_cards[existing_id] then
        UI.player_cards[existing_id].container:raiseAll()
        return
    end
    ui_player_card_show(player)
end

-- Look up a player by name from the online list (or DB if available), then
-- show or raise their card.  Falls back to a minimal stub when the player is
-- offline and no DB entry exists.
function ui_player_card_show_or_raise_by_name(name)
    if not name or name == "" then return end
    local existing_id = UI.player_cards_by_name[name]
    if existing_id and UI.player_cards[existing_id] then
        UI.player_cards[existing_id].container:raiseAll()
        return
    end
    -- Try online list first
    for _, p in ipairs(UI.who.players) do
        if p.name == name then
            ui_player_card_show(p)
            return
        end
    end
    -- Try persistent DB
    local db_entry = ui_player_db_get and ui_player_db_get(name)
    if db_entry then
        ui_player_card_show(db_entry)
        return
    end
    -- Last resort: open card with just the name
    ui_player_card_show({ name = name })
end

-- Refresh open cards only when their player's data actually changed.
-- Called on every gmcp.players event — must be cheap for the no-change case.
function ui_player_cards_refresh_all()
    local online = {}
    for _, p in ipairs(UI.who.players) do online[p.name] = p end

    for card_id, card_meta in pairs(UI.player_cards) do
        local pname = card_meta.player_name
        if pname then
            local fresh = online[pname]
            if not fresh then
                fresh = ui_player_db_get and ui_player_db_get(pname)
            end
            if fresh then
                local new_fp = _player_fingerprint(fresh)
                if new_fp ~= card_meta.fingerprint then
                    -- Data changed — rebuild in place at current position
                    local px = card_meta.container:get_x()
                    local py = card_meta.container:get_y()
                    ui_player_card_close(card_id)
                    ui_player_card_show(fresh, { x = px, y = py })
                end
                -- fingerprint matches → nothing to do, no rebuild
            end
        end
    end
end

-- ── Galaxy navigator integration ──────────────────────────────────────────────

function ui_player_card_open_galaxy(cartel_name, entity_name)
    if not UI.galaxy_dropdown then ui_build_galaxy_dropdown() end

    if not UI.galaxy.loaded and not UI.galaxy.loading then
        ui_galaxy_init()
    end

    -- Expand the target entity in the galaxy tree.  When the galaxy is still
    -- loading on first open, poll until the data arrives then apply the expand.
    local function _expand_and_populate()
        if cartel_name and cartel_name ~= "" then
            UI.galaxy.expanded[cartel_name] = true
        elseif entity_name and entity_name ~= "" then
            for cn, cd in pairs(UI.galaxy.cartels) do
                if cd.systems and cd.systems[entity_name] then
                    UI.galaxy.expanded[cn] = true
                    UI.galaxy.expanded[cn .. ":" .. entity_name] = true
                    break
                end
                if cd.systems then
                    for sn, sd in pairs(cd.systems) do
                        for _, pd in ipairs(sd.planets or {}) do
                            if pd.name == entity_name then
                                UI.galaxy.expanded[cn] = true
                                UI.galaxy.expanded[cn .. ":" .. sn] = true
                                break
                            end
                        end
                    end
                end
            end
        end
        tempTimer(0, ui_populate_galaxy_dropdown)
    end

    if UI.galaxy.loaded then
        _expand_and_populate()
    else
        -- Still loading (first open) — poll until done then expand
        local function _wait()
            if UI.galaxy.loaded then
                _expand_and_populate()
            elseif UI.galaxy.loading then
                tempTimer(0.25, _wait)
            end
        end
        tempTimer(0.25, _wait)
    end

    UI.galaxy_dropdown:show()
    UI.galaxy.visible       = true
    UI.galaxy_button_active = true
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE INIT
-- ═══════════════════════════════════════════════════════════════════════════════

function ui_who_init()
    if not UI.who_window then
        f2t_debug_log("[who] who_window not available — skipping init")
        return
    end

    -- Load persistent player DB so offline data and chat colors are available
    if ui_player_db_load then ui_player_db_load() end

    -- "Online" / "All" toggle state
    UI.who._show_all = false

    local cols = {
        {
            key        = "rank",
            label      = "Rank",
            width      = 13,
            align      = "left",
            sortable   = true,
            sort_value = function(row) return row.rank_order or 0 end,
            format     = function(v, row)
                -- Offline rows (from DB in "All" view) are rendered dimmer
                if row.is_online == false then
                    return "<dim_gray>" .. v .. "<reset>"
                end
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
                local offline = (row.is_online == false)
                local cc = offline and "dim_gray" or (row.cecho_color or RANK_COLOR_DEFAULT)
                local staff = (row.staff and row.staff ~= "")

                local name_str = "<" .. cc .. "><b>" .. (value or "") .. "</b><reset>"
                if staff then
                    name_str = name_str .. " <ansiYellow>[" .. row.staff:sub(1, 3) .. "]<reset>"
                end
                if offline and row.last_seen then
                    local ago = ui_player_db_last_seen_str and ui_player_db_last_seen_str(row.last_seen) or "?"
                    name_str = name_str .. " <dim_gray>(" .. ago .. ")<reset>"
                end

                local visible_len = #(value or "") + (staff and 6 or 0)
                local pad = (col.width or 16) - visible_len
                if pad > 0 then name_str = name_str .. string.rep(" ", pad) end

                window:cechoLink(
                    name_str,
                    function() ui_player_card_show_or_raise(row) end,
                    (offline and "Offline — " or "") .. "Get Info for " .. (value or ""),
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
                if row.is_online == false then
                    return "<dim_gray>" .. v .. "<reset>"
                end
                return "<ansiCyan>" .. v .. "<reset>"
            end,
            link = function(value)
                if not value or value == "" then return end
                local sys = value:match("^(.+) Space$")
                if sys then
                    expandAlias("nav " .. sys .. " link")
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

    -- Tab-click re-renders from current GMCP snapshot
    local tw  = UI.tab_top_left
    local tab = tw and tw.Who
    if tab and tab.adjLabel then
        tab.adjLabel:setClickCallback(function(event)
            tw:onClick("Who", event)
            ui_who_refresh()
        end)
        f2t_debug_log("[who] tab auto-refresh wired")
    end

    -- Periodic re-render every 60s
    local function schedule_who_periodic()
        UI.who._periodic_timer = tempTimer(60, function()
            if gmcp and gmcp.char and gmcp.char.vitals then
                ui_who_from_gmcp()
            end
            schedule_who_periodic()
        end)
    end
    schedule_who_periodic()

    f2t_debug_log("[who] init complete")
end
