-- ============================================================================
-- GALAXY DATA MANAGEMENT  —  powered by "di systems"
-- ============================================================================
--
-- TRIGGERS REQUIRED (replace all previous galaxy triggers):
--
--   galaxySystemsLine   (fires while capture is active)
--     type    : regex
--     pattern : ^(.+)$          ← any non-blank line
--     script  : if UI.galaxy and UI.galaxy.capture_active then
--                   ui_galaxy_capture_line(matches[2])
--               end
--
--   galaxySystemsEnd    (blank line signals end of "di systems" output)
--     type    : regex
--     pattern : ^$
--     script  : if UI.galaxy and UI.galaxy.capture_active then
--                   ui_galaxy_finish_capture()
--               end
--
-- ============================================================================

UI.galaxy = UI.galaxy or {
    cartels        = {},    -- [cartel_name] = { name, systems = { [sys_name] = {...} } }
    loaded         = false,
    loading        = false,
    last_updated   = nil,   -- unix timestamp of last successful load
    visible        = false,
    expanded       = {},    -- [key] = true/false; persists in-session only

    capture_active = false,
    capture_lines  = {},    -- raw lines buffered during capture

    _search_text   = "",    -- current filter string (set by search alias)
}

UI.galaxy_button_active = false

-- ── Age helper ───────────────────────────────────────────────────────────────

local function _age_str(ts)
    if not ts or ts == 0 then return "Never" end
    local age = os.time() - ts
    if age < 60       then return "Just now"
    elseif age < 3600 then return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then return string.format("%dh ago", math.floor(age / 3600))
    else                   return string.format("%dd ago", math.floor(age / 86400))
    end
end

-- ── Search filter helpers ─────────────────────────────────────────────────────

local function _q_matches(name, q)
    return name:lower():find(q:lower(), 1, true) ~= nil
end

local function _planet_matches(pd, q)
    return _q_matches(pd.name, q)
end

local function _system_has_match(sd, q)
    if _q_matches(sd.name, q) then return true end
    for _, pd in ipairs(sd.planets or {}) do
        if _planet_matches(pd, q) then return true end
    end
    return false
end

local function _cartel_has_match(cd, q)
    if _q_matches(cd.name, q) then return true end
    for _, sd in pairs(cd.systems or {}) do
        if _system_has_match(sd, q) then return true end
    end
    return false
end

-- ── Data loading ──────────────────────────────────────────────────────────────

-- Send "di systems" and begin capturing output.
function ui_galaxy_init()
    if UI.galaxy.loading then
        cecho("\n<yellow>[Galaxy]<reset> Already loading...\n")
        return
    end
    UI.galaxy.loading        = true
    UI.galaxy.loaded         = false
    UI.galaxy.capture_active = true
    UI.galaxy.capture_lines  = {}
    UI.galaxy.cartels        = {}

    -- Show loading state immediately if the panel is open
    if UI.galaxy.visible then ui_populate_galaxy_dropdown() end

    sendAll("di systems", false)
end

-- Called by the galaxySystemsLine trigger for every non-blank line.
-- Handles both full system lines and wrapped continuation lines.
function ui_galaxy_capture_line(line)
    if not UI.galaxy.capture_active then return end
    line = line:match("^%s*(.-)%s*$")   -- trim
    if line == "" then return end

    -- A system line contains " - <name> cartel - "
    if line:match(" %- .+ cartel %- ") then
        table.insert(UI.galaxy.capture_lines, line)
    elseif #UI.galaxy.capture_lines > 0 then
        -- Continuation: wrap-around planet list from the previous system.
        -- Append with a space so the parser sees an unbroken planet string.
        local n = #UI.galaxy.capture_lines
        UI.galaxy.capture_lines[n] = UI.galaxy.capture_lines[n] .. " " .. line
    end
    -- Lines that match neither (e.g. command echo, stray text) are ignored.
end

-- Parse one combined system line into its components.
-- Format: "SystemName - CartelName cartel - Rank Owner[tag]: Planet(T) ..."
local function _parse_system_line(line)
    local system_name, cartel_name, planet_str =
        line:match("^(.+) %- (.+) cartel %- [^:]+: (.*)$")
    if not system_name then return nil end

    system_name = system_name:match("^%s*(.-)%s*$")
    cartel_name = cartel_name:match("^%s*(.-)%s*$")

    local planets = {}
    -- Matches "Planet Name(T)" where T is one or more uppercase letters/digits
    for planet_name in (planet_str or ""):gmatch("(.-)%([^%)]+%)%s*") do
        planet_name = planet_name:match("^%s*(.-)%s*$")
        if planet_name ~= "" then
            table.insert(planets, {
                name   = planet_name,
                system = system_name,
                cartel = cartel_name,
            })
        end
    end

    return system_name, cartel_name, planets
end

-- Called by the galaxySystemsEnd trigger on a blank line.
function ui_galaxy_finish_capture()
    if not UI.galaxy.capture_active then return end
    UI.galaxy.capture_active = false

    if #UI.galaxy.capture_lines == 0 then
        cecho("\n<red>[Galaxy]<reset> No data captured from 'di systems'.\n")
        UI.galaxy.loading = false
        if UI.galaxy.visible then ui_populate_galaxy_dropdown() end
        return
    end

    -- Build the cartels/systems structure from captured lines
    local cartels = {}
    for _, line in ipairs(UI.galaxy.capture_lines) do
        local system_name, cartel_name, planets = _parse_system_line(line)
        if system_name and cartel_name then
            if not cartels[cartel_name] then
                cartels[cartel_name] = { name = cartel_name, systems = {} }
            end
            cartels[cartel_name].systems[system_name] = {
                name    = system_name,
                cartel  = cartel_name,
                planets = planets,
            }
        end
    end

    UI.galaxy.cartels      = cartels
    UI.galaxy.loading      = false
    UI.galaxy.loaded       = true
    UI.galaxy.last_updated = os.time()

    local nc = 0; for _ in pairs(cartels) do nc = nc + 1 end
    f2t_debug_log("[galaxy] Loaded %d cartels from di systems", nc)

    if UI.galaxy.visible then ui_populate_galaxy_dropdown() end
end

-- ── Navigation ────────────────────────────────────────────────────────────────

function ui_galaxy_nav_to(location_type, location_name)
    if location_type == "planet" then
        expandAlias("nav " .. location_name)
    elseif location_type == "system" then
        expandAlias("nav " .. location_name .. " link")
    end
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    end
end

function ui_galaxy_get_info(location_type, location_name)
    if location_type == "cartel" then
        send("di cartel " .. location_name)
    elseif location_type == "system" then
        send("di system " .. location_name)
    elseif location_type == "planet" then
        send("di planet " .. location_name)
    end
end

-- ============================================================================
-- GALAXY UI
-- ============================================================================

-- Shared style constants
local _BG      = "background-color: rgb(18, 18, 26); border: none;"
local _ROW     = "background-color: rgb(22, 22, 30); border: none; border-bottom: 1px solid rgba(255,255,255,35);"
local _BTN_CUR = [[
    QLabel{
        background-color: rgba(40, 40, 45, 200);
        border-style: solid;
        border-width: 1px;
        border-radius: 3px;
        border-color: rgba(255, 140, 0, 200);
        color: rgba(200, 200, 210, 255);
        font-size: 11px;
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover{
        background-color: rgba(60, 60, 70, 220);
        border-color: rgba(255, 165, 0, 255);
        color: white;
        qproperty-alignment: AlignCenter;
    }
]]

-- Layout constants (% of row width)
-- Rows are always x=0; indentation is via child widget x-position only.
--
--   Cartel (indent 0): expand@0%, icon@5%, name@10%→96%   (no nav button)
--   System (indent 1): expand@4%, icon@9%, name@14%→91%,  nav@93%
--   Planet (indent 2): (no expand), icon@13%, name@18%→91%, nav@93%
--
local INDENT_PCT = 4    -- % per indent level
local EXPAND_PCT = 5    -- expand button slot width %
local ICON_PCT   = 5    -- icon slot width %
local NAV_X      = "93%"
local NAV_W      = "5%"
local ROW_H      = 24   -- pixels (tied to font size, not window size)

-- Draw epoch: incremented each redraw so widget names are always unique,
-- preventing Geyser registry collisions from stale hidden widgets.
UI.galaxy_draw_epoch = UI.galaxy_draw_epoch or 0

-- ── Build the panel (called once) ────────────────────────────────────────────

function ui_build_galaxy_dropdown()
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        return
    end

    -- Position: right edge abuts UI.right_frame; top edge below UI.top_right_frame
    local main_w, main_h = getMainWindowSize()
    local rf_x_px    = UI.right_frame:get_x()
    local trf_bot_px = UI.top_right_frame:get_y() + UI.top_right_frame:get_height()

    local panel_w_pct = 18
    local panel_w_px  = math.floor(main_w * panel_w_pct / 100)
    local panel_x_px  = rf_x_px - panel_w_px
    local panel_y_px  = trf_bot_px
    local panel_h_px  = math.max(100, math.floor(main_h * 0.97) - panel_y_px)

    local panel_x_str = string.format("%.2f%%", panel_x_px / main_w * 100)
    local panel_y_str = string.format("%.2f%%", panel_y_px / main_h * 100)
    local panel_h_str = string.format("%.2f%%", panel_h_px / main_h * 100)

    UI.galaxy_dropdown = Adjustable.Container:new({
        name          = "galaxy_dropdown",
        x             = panel_x_str,
        y             = panel_y_str,
        width         = panel_w_pct .. "%",
        height        = panel_h_str,
        adjLabelstyle = "background-color: rgb(18, 18, 26); border: 1px solid rgba(255,255,255,0.46);",
        autoSave      = false,
        autoLoad      = false,
    })
    UI.galaxy_dropdown:lockContainer("border")
    -- Re-enable dragging after lock: lockContainer sets locked=true which disables
    -- mouse drag/resize, but the "border" style already applied the correct visual
    -- layout (Inside inset by padding, title cleared, buttons hidden).
    UI.galaxy_dropdown.locked = false
    f2t_ui_register_container("galaxy_dropdown", UI.galaxy_dropdown)

    -- Parent all children to Inside so they automatically clear the 1-px border.
    local _in = UI.galaxy_dropdown.Inside

    -- Layout: two-row header, scroll fills middle, fixed footer at bottom.
    -- ppct() converts pixels to % of the inner height (panel minus 2px borders).
    local topbar_h = 60
    local footer_h = 20
    local pad      = 4

    local inner_h  = panel_h_px - 2
    local function ppct(px) return string.format("%.2f%%", px / inner_h * 100) end

    local scroll_y_pct = ppct(topbar_h)
    local footer_y_pct = ppct(inner_h - footer_h - pad)
    local scroll_h_pct = ppct(inner_h - footer_h - pad - topbar_h)

    -- ── Header ───────────────────────────────────────────────────────────
    UI.galaxy_topbar = Geyser.Label:new({
        name = "galaxy_topbar", x=0, y=0, width="100%", height=topbar_h
    }, _in)
    UI.galaxy_topbar:setStyleSheet(UI.style.header_label_css)

    -- Row 1 (y=4, h=24): title left, refresh + close right
    UI.galaxy_title = Geyser.Label:new({
        name = "galaxy_title", x="1%", y=4, width="61%", height=24
    }, UI.galaxy_topbar)
    UI.galaxy_title:setStyleSheet(
        "background-color:transparent; color:#c8c8d0; font-size:11px; font-weight:bold;")
    UI.galaxy_title:echo("🔭 Galaxy Navigator")

    -- Refresh (⟳)
    UI.galaxy_refresh_icon = Geyser.Label:new({
        name = "galaxy_refresh_icon", x="63%", y=4, width="17%", height=24
    }, UI.galaxy_topbar)
    UI.galaxy_refresh_icon:setStyleSheet(UI.style.button_css)
    UI.galaxy_refresh_icon:echo("<center>⟳</center>")
    UI.galaxy_refresh_icon:setClickCallback(function()
        ui_galaxy_init()
    end)
    UI.galaxy_refresh_icon:setToolTip("Refresh: " .. _age_str(UI.galaxy.last_updated))

    -- Close (✕)
    UI.galaxy_close = Geyser.Label:new({
        name = "galaxy_close", x="81%", y=4, width="18%", height=24
    }, UI.galaxy_topbar)
    UI.galaxy_close:setStyleSheet([[
        QLabel {
            background-color: rgba(180, 50, 50, 220);
            border: 1px solid rgba(200, 80, 80, 180);
            border-radius: 3px;
            color: white;
            font-size: 12px;
        }
        QLabel::hover { background-color: rgba(210, 60, 60, 240); }
    ]])
    UI.galaxy_close:echo("<center>✕</center>")
    UI.galaxy_close:setClickCallback(function()
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
        UI.galaxy._poll_active  = false
        if UI.galaxy._search_debounce then
            killTimer(UI.galaxy._search_debounce)
            UI.galaxy._search_debounce = nil
        end
    end)

    -- Row 2 (y=32, h=24): collapse-all (small square, above the per-row expand buttons),
    -- "Search:" label, and CommandLine
    UI.galaxy_collapse_btn = Geyser.Label:new({
        name = "galaxy_collapse_btn", x="1%", y=32, width="8%", height=24
    }, UI.galaxy_topbar)
    UI.galaxy_collapse_btn:setStyleSheet(UI.style.button_css)
    UI.galaxy_collapse_btn:echo("<center>⊟</center>")
    UI.galaxy_collapse_btn:setClickCallback(function()
        UI.galaxy.expanded = {}
        tempTimer(0, ui_populate_galaxy_dropdown)
    end)
    UI.galaxy_collapse_btn:setToolTip("Collapse all")

    local search_lbl = Geyser.Label:new({
        name = "galaxy_search_label", x="10%", y=32, width="13%", height=24
    }, UI.galaxy_topbar)
    search_lbl:setStyleSheet(
        "background-color:transparent; color:rgba(160,160,170,200); font-size:10px;")
    search_lbl:echo("<right>Search:</right>")

    UI.galaxy_search_cmd = Geyser.CommandLine:new({
        name   = "galaxy_search_cmd",
        x      = "24%", y = 32, width = "75%", height = 24,
    }, UI.galaxy_topbar)
    UI.galaxy_search_cmd:setStyleSheet([[
        background-color: rgb(10, 10, 16);
        color: rgba(200, 200, 210, 255);
        font-size: 11px;
        font-weight: bold;
        border: 1px solid rgba(100, 100, 110, 180);
        border-radius: 3px;
        padding-left: 4px;
        padding-right: 4px;
    ]])
    -- Prevent the search box from submitting text to the game on Enter
    UI.galaxy_search_cmd:setAction(function() end)

    -- ── Scroll area ───────────────────────────────────────────────────────
    UI.galaxy_scroll = Geyser.ScrollBox:new({
        name   = "galaxy_scroll",
        x      = 0, y = scroll_y_pct,
        width  = "100%", height = scroll_h_pct,
    }, _in)

    -- Content width must be strictly less than the ScrollBox viewport width
    -- (viewport = scrollbox width minus vertical scrollbar ~17px).
    -- adjLabel and galaxy_scroll are siblings in the main Qt window, so CSS
    -- set on adjLabel cannot cascade to the ScrollBox's scrollbars.
    -- Using actual scrollbox width minus 20px guarantees no horizontal scroll.
    local sb_w = UI.galaxy_scroll:get_width()
    UI.galaxy.content_w_px = math.max(50, sb_w - 20)

    -- ── Footer legend ─────────────────────────────────────────────────────
    UI.galaxy_footer = Geyser.Label:new({
        name = "galaxy_footer", x=0, y=footer_y_pct, width="100%", height=footer_h
    }, _in)
    UI.galaxy_footer:setStyleSheet(UI.style.header_label_css)

    UI.galaxy_legend = Geyser.Label:new({
        name = "galaxy_legend", x="1%", y=0, width="98%", height="100%"
    }, UI.galaxy_footer)
    UI.galaxy_legend:setStyleSheet(
        "background-color:transparent; color:rgba(160,160,170,190); font-size:9px;")
    UI.galaxy_legend:echo("<center>🌌 Cartel  ⭐ System  🌍 Planet</center>")

    -- Hide LAST so nothing re-shows it during child creation.
    UI.galaxy_dropdown:hide()
end

-- ── Row builder ──────────────────────────────────────────────────────────────

function ui_create_galaxy_row(parent, name, row_type, indent_level, y_px, data, is_current)
    local cartel_ctx = (data and data.cartel) or ""
    -- Suffix "_r" prevents the uid from ever ending with "Class" (or any Class$ variant),
    -- which Geyser.Container:new() treats as a class definition and skips container:add().
    local uid = (string.format("gxrow_%d_%s_%s_%s",
        UI.galaxy_draw_epoch, row_type, cartel_ctx, name)
        :gsub("[^%w_]", "_")) .. "_r"

    local row = Geyser.Label:new({
        name = uid, x=0, y=y_px, width="100%", height=ROW_H
    }, parent)
    row:setStyleSheet(_ROW)

    local indent_pct = 1 + indent_level * INDENT_PCT

    -- Expand / collapse (cartel and system only)
    local exp_key
    if row_type == "cartel" then
        exp_key = name
    elseif row_type == "system" then
        exp_key = (cartel_ctx ~= "" and cartel_ctx or "") .. ":" .. name
    end

    if exp_key then
        local is_exp = UI.galaxy.expanded[exp_key] or false
        local ebtn = Geyser.Label:new({
            name  = uid .. "_exp",
            x     = indent_pct .. "%", y = 1,
            width = EXPAND_PCT .. "%", height = ROW_H - 2
        }, row)
        ebtn:setStyleSheet(UI.style.button_css)
        ebtn:echo(is_exp and "<center>−</center>" or "<center>+</center>")
        ebtn:setClickCallback(function()
            UI.galaxy.expanded[exp_key] = not UI.galaxy.expanded[exp_key]
            -- Defer to let Geyser finish click-event propagation before rebuilding the tree.
            -- Calling populate() synchronously from inside a click callback causes Geyser to
            -- try to propagate the click through container refs on widgets we just hid/replaced.
            tempTimer(0, ui_populate_galaxy_dropdown)
        end)
    end

    -- Icon
    local icon_x_pct = indent_pct + EXPAND_PCT
    local icon_map = {
        cartel = { "🌌", "#ff6b9d" },
        system = { "⭐",  "#ffd700" },
        planet = { "🌍", "#4ecdc4" },
    }
    local id = icon_map[row_type]
    local icon = Geyser.Label:new({
        name  = uid .. "_ico",
        x     = icon_x_pct .. "%", y = 1,
        width = ICON_PCT .. "%", height = ROW_H - 2
    }, row)
    icon:setStyleSheet(string.format(
        "background-color:transparent; color:%s; font-size:11px;", id[2]))
    icon:echo("<center>" .. id[1] .. "</center>")

    -- Name label — width fills right up to the nav button (or edge for cartels)
    local name_x_pct = icon_x_pct + ICON_PCT
    local has_nav    = (row_type == "system" or row_type == "planet")
    local name_end   = has_nav and 91 or 97
    local name_w_pct = math.max(5, name_end - name_x_pct)

    local nlbl = Geyser.Label:new({
        name  = uid .. "_name",
        x     = name_x_pct .. "%", y = 1,
        width = name_w_pct .. "%", height = ROW_H - 2
    }, row)
    nlbl:setStyleSheet(is_current and _BTN_CUR or UI.style.button_css)
    nlbl:echo(name)
    nlbl:setClickCallback(function() ui_galaxy_get_info(row_type, name) end)
    nlbl:setToolTip("Click for info")

    -- Nav button → (system and planet only, fixed column)
    if has_nav then
        local nbtn = Geyser.Label:new({
            name  = uid .. "_nav",
            x     = NAV_X, y = 1, width = NAV_W, height = ROW_H - 2
        }, row)
        nbtn:setStyleSheet([[
            QLabel {
                background-color: rgba(40, 120, 80, 210);
                border: 1px solid rgba(60, 140, 100, 180);
                border-radius: 3px;
                color: white;
                font-size: 10px;
                font-weight: bold;
            }
            QLabel::hover { background-color: rgba(55, 150, 95, 230); }
        ]])
        nbtn:echo("<center>→</center>")
        nbtn:setClickCallback(function() ui_galaxy_nav_to(row_type, name) end)
        nbtn:setToolTip("Navigate here")
    end

    return row
end

-- ── Populate the scrollable tree ──────────────────────────────────────────────
--
-- SCROLL POSITION STRATEGY
-- Destroying and recreating the content label creates a new Qt widget, which
-- always starts at scroll offset 0.  Instead we keep ONE permanent content
-- label (galaxy_main_content) and only RESIZE it on each redraw.  Qt's
-- QScrollArea preserves its vertical scroll offset as long as the same child
-- widget is in place.  Old row labels are hidden (not destroyed) and new ones
-- are created with epoch-suffixed names so the Geyser registry never collides.

function ui_populate_galaxy_dropdown()
    if not UI.galaxy_scroll then return end

    UI.galaxy_draw_epoch = UI.galaxy_draw_epoch + 1

    -- Update ⟳ tooltip with current data age
    if UI.galaxy_refresh_icon then
        UI.galaxy_refresh_icon:setToolTip("Refresh: " .. _age_str(UI.galaxy.last_updated))
    end

    -- Hide all rows from the previous draw pass.
    -- Row labels are children of galaxy_main_content; hiding each row also
    -- hides its children (expand btn, icon, name, nav) in Qt.
    UI.galaxy_rows = UI.galaxy_rows or {}
    for _, r in ipairs(UI.galaxy_rows) do r:hide() end
    UI.galaxy_rows = {}

    -- ── Ensure the two permanent sibling labels exist ────────────────────────
    -- galaxy_scroll_state  : shown for loading / no-data messages
    -- galaxy_main_content  : shown when data is available; never destroyed
    if not UI.galaxy_scroll_state then
        local cw = UI.galaxy.content_w_px or 200
        UI.galaxy_scroll_state = Geyser.Label:new({
            name="galaxy_scroll_state", x=0, y=0, width=cw, height=2000
        }, UI.galaxy_scroll)
        UI.galaxy_scroll_state:setStyleSheet(_BG)

        UI.galaxy_state_msg = Geyser.Label:new({
            name="galaxy_state_msg", x=0, y="40%", width="100%", height=60
        }, UI.galaxy_scroll_state)
        UI.galaxy_state_msg:setStyleSheet(
            "background-color:transparent; font-size:11px;")
    end

    if not UI.galaxy_scroll_content then
        local cw = UI.galaxy.content_w_px or 200
        UI.galaxy_scroll_content = Geyser.Label:new({
            name="galaxy_main_content", x=0, y=0, width=cw, height=2000
        }, UI.galaxy_scroll)
        UI.galaxy_scroll_content:setStyleSheet(_BG)
    end

    -- ── Loading state ────────────────────────────────────────────────────────
    if UI.galaxy.loading then
        UI.galaxy_scroll_content:hide()
        UI.galaxy_state_msg:setStyleSheet(
            "background-color:transparent; color:rgba(200,200,100,220); font-size:11px;")
        UI.galaxy_state_msg:echo("<center>Loading galaxy data…</center>")
        UI.galaxy_scroll_state:show()
        return
    end

    -- ── No-data state ────────────────────────────────────────────────────────
    if not UI.galaxy.loaded then
        UI.galaxy_scroll_content:hide()
        UI.galaxy_state_msg:setStyleSheet(
            "background-color:transparent; color:rgba(180,180,190,210); font-size:11px;")
        UI.galaxy_state_msg:echo(
            "<center>Galaxy data is not loaded.<br/>Click ⟳ in the header to load it.</center>")
        UI.galaxy_scroll_state:show()
        return
    end

    -- ── Render tree ──────────────────────────────────────────────────────────
    UI.galaxy_scroll_state:hide()
    UI.galaxy_scroll_content:show()

    -- Read current search query
    local q = ""
    if UI.galaxy_search_cmd then
        q = (UI.galaxy_search_cmd:getText() or ""):match("^%s*(.-)%s*$")
    end
    local searching = q ~= ""

    local sorted_cartels = {}
    for cn in pairs(UI.galaxy.cartels) do table.insert(sorted_cartels, cn) end
    table.sort(sorted_cartels)

    -- Determine current location for row highlighting
    local ri          = gmcp and gmcp.room and gmcp.room.info
    local cur_cartel  = ri and ri.cartel or ""
    local cur_system  = ri and ri.system or ""
    local cur_area    = ri and ri.area   or ""

    -- Check whether cur_area is a known planet in cur_system.
    -- If it is, highlight that planet row; otherwise highlight the system row.
    local cur_planet = ""
    local _ccd = cur_cartel ~= "" and UI.galaxy.cartels[cur_cartel]
    local _csd = _ccd and _ccd.systems[cur_system]
    if _csd then
        for _, pd in ipairs(_csd.planets or {}) do
            if pd.name == cur_area then
                cur_planet = cur_area
                break
            end
        end
    end

    local y_px = 2

    for _, cartel_name in ipairs(sorted_cartels) do
        local cartel_data = UI.galaxy.cartels[cartel_name]

        if not searching or _cartel_has_match(cartel_data, q) then
            local r = ui_create_galaxy_row(UI.galaxy_scroll_content, cartel_name, "cartel", 0, y_px, cartel_data)
            table.insert(UI.galaxy_rows, r)
            y_px = y_px + ROW_H

            if searching or UI.galaxy.expanded[cartel_name] then
                local sorted_sys = {}
                for sn in pairs(cartel_data.systems or {}) do table.insert(sorted_sys, sn) end
                table.sort(sorted_sys)

                for _, system_name in ipairs(sorted_sys) do
                    if system_name ~= (cartel_name .. " Space") then
                        local system_data = cartel_data.systems[system_name]

                        if not searching or _system_has_match(system_data, q) then
                            local sys_is_cur = (system_name == cur_system)
                                and (cartel_name == cur_cartel)
                                and (cur_planet == "")
                            local sr = ui_create_galaxy_row(UI.galaxy_scroll_content, system_name, "system", 1, y_px, system_data, sys_is_cur)
                            table.insert(UI.galaxy_rows, sr)
                            y_px = y_px + ROW_H

                            local sys_key = cartel_name .. ":" .. system_name
                            if searching or UI.galaxy.expanded[sys_key] then
                                for _, planet_data in ipairs(system_data.planets or {}) do
                                    if planet_data.name ~= (system_name .. " Space") then
                                        if not searching or _planet_matches(planet_data, q) then
                                            local pl_is_cur = (planet_data.name == cur_planet)
                                                and (system_name == cur_system)
                                            local pr = ui_create_galaxy_row(UI.galaxy_scroll_content, planet_data.name, "planet", 2, y_px, planet_data, pl_is_cur)
                                            table.insert(UI.galaxy_rows, pr)
                                            y_px = y_px + ROW_H
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Resize after all rows are created. Resizing before creation triggers Qt
    -- layout events mid-loop on large cartels, corrupting container references
    -- and cutting the render short (only the first row survives).
    UI.galaxy_scroll_content:resize(UI.galaxy.content_w_px or 200, math.max(y_px + 4, 2000))
end

-- ── Toggle visibility ─────────────────────────────────────────────────────────

function ui_toggle_galaxy()
    if not UI.galaxy_dropdown then
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
        ui_build_galaxy_dropdown()
        if not UI.galaxy_dropdown then return end
    end

    if UI.galaxy.visible then
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
        UI.galaxy._poll_active  = false
        if UI.galaxy._search_debounce then
            killTimer(UI.galaxy._search_debounce)
            UI.galaxy._search_debounce = nil
        end
    else
        -- Auto-load on first open if not yet loaded and not already loading
        if not UI.galaxy.loaded and not UI.galaxy.loading then
            ui_galaxy_init()
        end
        -- Auto-expand current cartel and system on each open
        local ri = gmcp and gmcp.room and gmcp.room.info
        local cur_cartel = ri and ri.cartel
        local cur_system = ri and ri.system
        if cur_cartel and cur_cartel ~= "" then
            UI.galaxy.expanded[cur_cartel] = true
            if cur_system and cur_system ~= "" then
                UI.galaxy.expanded[cur_cartel .. ":" .. cur_system] = true
            end
        end
        ui_populate_galaxy_dropdown()
        UI.galaxy_dropdown:show()
        UI.galaxy_dropdown:raiseAll()
        UI.galaxy.visible       = true
        UI.galaxy_button_active = true
        -- Start search polling: single loop with debounce to limit redraws.
        -- Without debounce, every keystroke triggers a full tree rebuild (hundreds
        -- of new Geyser objects accumulate), causing lag and visual garbage.
        if not UI.galaxy._poll_active then
            UI.galaxy._poll_active = true
            UI.galaxy._last_search = nil
            local _spoll
            _spoll = function()
                if not UI.galaxy.visible then
                    UI.galaxy._poll_active = false
                    return
                end
                local q = ""
                if UI.galaxy_search_cmd then
                    q = (UI.galaxy_search_cmd:getText() or ""):match("^%s*(.-)%s*$")
                end
                if q ~= UI.galaxy._last_search then
                    UI.galaxy._last_search = q
                    if UI.galaxy._search_debounce then
                        killTimer(UI.galaxy._search_debounce)
                    end
                    UI.galaxy._search_debounce = tempTimer(0.35, function()
                        UI.galaxy._search_debounce = nil
                        if UI.galaxy.visible then ui_populate_galaxy_dropdown() end
                    end)
                end
                tempTimer(0.15, _spoll)
            end
            tempTimer(0.15, _spoll)
        end
    end
end