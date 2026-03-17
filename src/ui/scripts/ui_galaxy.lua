-- ============================================================================
-- GALAXY DATA MANAGEMENT WITH PERSISTENCE (v3)
-- ============================================================================

UI.galaxy = UI.galaxy or {
    cartels             = {},
    loaded              = false,
    loading             = false,
    loading_automated   = false,
    is_full_refresh     = false,   -- true only during a full "di cartels" reload
    current_cartel_loading = nil,
    current_system_loading = nil,
    load_queue          = {},
    expanded            = {},
    last_updated        = nil,     -- timestamp of last FULL refresh (not displayed)
    cartel_timestamps   = {},      -- per-cartel refresh timestamp
    system_timestamps   = {},      -- per-system refresh timestamp (key = "cartel:system")
    visible             = false,

    cartel_capture_active = false,
    cartel_list           = {},
    member_capture_active = false,
    member_list           = {},
    member_capturing      = false,
    planet_capture_active = false,
    planet_list           = {}
}

-- ── Settings registration ────────────────────────────────────────────────────

f2t_settings_register("galaxy", "data", {
    description = "Cached galaxy navigation data",
    default     = {},
    validator   = function(v) return type(v) == "table", "Must be a table" end
})
f2t_settings_register("galaxy", "last_updated", {
    description = "Timestamp of last full galaxy data refresh",
    default     = 0,
    validator   = function(v) return type(v) == "number", "Must be a number" end
})
f2t_settings_register("galaxy", "expanded", {
    description = "Expanded nodes in galaxy tree",
    default     = {},
    validator   = function(v) return type(v) == "table", "Must be a table" end
})
f2t_settings_register("galaxy", "cartel_timestamps", {
    description = "Per-cartel refresh timestamps",
    default     = {},
    validator   = function(v) return type(v) == "table", "Must be a table" end
})
f2t_settings_register("galaxy", "system_timestamps", {
    description = "Per-system refresh timestamps",
    default     = {},
    validator   = function(v) return type(v) == "table", "Must be a table" end
})

-- ── Persistence ──────────────────────────────────────────────────────────────

function ui_galaxy_save()
    f2t_settings_set("galaxy", "data",               UI.galaxy.cartels)
    f2t_settings_set("galaxy", "last_updated",       UI.galaxy.last_updated or 0)
    f2t_settings_set("galaxy", "expanded",           UI.galaxy.expanded)
    f2t_settings_set("galaxy", "cartel_timestamps",  UI.galaxy.cartel_timestamps)
    f2t_settings_set("galaxy", "system_timestamps",  UI.galaxy.system_timestamps)
    f2t_debug_log("[galaxy] Data saved to disk")
end

function ui_galaxy_load()
    local saved_data      = f2t_settings_get("galaxy", "data")
    local saved_time      = f2t_settings_get("galaxy", "last_updated")
    local saved_expanded  = f2t_settings_get("galaxy", "expanded")
    local saved_c_stamps  = f2t_settings_get("galaxy", "cartel_timestamps")
    local saved_s_stamps  = f2t_settings_get("galaxy", "system_timestamps")

    if saved_data and type(saved_data) == "table" then
        UI.galaxy.cartels           = saved_data
        UI.galaxy.last_updated      = saved_time or 0
        UI.galaxy.expanded          = saved_expanded or {}
        UI.galaxy.cartel_timestamps = saved_c_stamps or {}
        UI.galaxy.system_timestamps = saved_s_stamps or {}

        local n = 0
        for _ in pairs(UI.galaxy.cartels) do n = n + 1 end

        if n > 0 then
            UI.galaxy.loaded = true
            f2t_debug_log("[galaxy] Loaded %d cartels from disk", n)
            cecho(string.format("\n<green>[Galaxy]<reset> Loaded %d cartels from cache\n", n))
            return true
        end
    end
    return false
end

-- ── Age helpers ───────────────────────────────────────────────────────────────
-- Returns a concise age string from a unix timestamp, or "Never" if nil.

local function _age_str(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    local age = os.time() - timestamp
    if age < 60       then return "Just now"
    elseif age < 3600 then return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then return string.format("%dh ago", math.floor(age / 3600))
    else                   return string.format("%dd ago", math.floor(age / 86400))
    end
end

-- Per-item age with explicit fallback chain:
--   Cartel  : own timestamp  →  overall last_updated  →  "Never"
--   System  : own timestamp  →  parent cartel timestamp  →  overall last_updated  →  "Never"
-- This means that after a full refresh every item immediately shows a real age,
-- and after a cartel refresh all of that cartel's systems show the cartel age
-- (until individually refreshed).
-- row_type : "cartel" | "system"
function ui_galaxy_get_item_age(row_type, cartel_name, system_name)
    if row_type == "cartel" then
        local ts = UI.galaxy.cartel_timestamps[cartel_name]
        if not ts or ts == 0 then ts = UI.galaxy.last_updated end
        return _age_str(ts)
    elseif row_type == "system" and cartel_name and system_name then
        local ts = UI.galaxy.system_timestamps[cartel_name .. ":" .. system_name]
        if not ts or ts == 0 then ts = UI.galaxy.cartel_timestamps[cartel_name] end
        if not ts or ts == 0 then ts = UI.galaxy.last_updated end
        return _age_str(ts)
    end
    return "Never"
end

-- ── Init / queue ─────────────────────────────────────────────────────────────

function ui_galaxy_init(refresh_type, target_name)
    if UI.galaxy.loading then
        cecho("\n<yellow>[Galaxy]<reset> Already loading data...\n")
        return
    end

    -- Attempt cache load for a cold "all" request before hitting the server.
    if refresh_type == "all" and not target_name then
        if ui_galaxy_load() then
            if UI.galaxy_dropdown and UI.galaxy.visible then
                ui_populate_galaxy_dropdown()
            end
            return
        end
    end

    UI.galaxy.loading           = true
    UI.galaxy.loading_automated = true
    UI.galaxy.load_queue        = {}
    UI.galaxy.is_full_refresh   = (refresh_type == "all")

    if refresh_type == "all" then
        cecho("\n<cyan>[Galaxy]<reset> Loading galaxy data (1-2 minutes)...\n")
        UI.galaxy.cartel_capture_active = true
        UI.galaxy.cartel_list           = {}
        sendAll("di cartels", false)

    elseif refresh_type == "cartel" and target_name then
        UI.galaxy.current_cartel_loading = target_name
        UI.galaxy.member_capture_active  = true
        UI.galaxy.member_list            = {}
        UI.galaxy.member_capturing       = false
        sendAll("di cartel " .. target_name, false)

    elseif refresh_type == "system" and target_name then
        for cartel_name, cartel_data in pairs(UI.galaxy.cartels) do
            if cartel_data.systems and cartel_data.systems[target_name] then
                UI.galaxy.current_system_loading = {cartel = cartel_name, system = target_name}
                UI.galaxy.planet_capture_active  = true
                UI.galaxy.planet_list            = {}
                sendAll("di system " .. target_name, false)
                return
            end
        end
        UI.galaxy.loading           = false
        UI.galaxy.loading_automated = false
    end
end

function ui_galaxy_parse_cartels(cartel_list)
    if not UI.galaxy.loading_automated then return end
    for _, cn in ipairs(cartel_list) do
        UI.galaxy.cartels[cn]         = UI.galaxy.cartels[cn] or {}
        UI.galaxy.cartels[cn].name    = cn
        UI.galaxy.cartels[cn].systems = UI.galaxy.cartels[cn].systems or {}
        table.insert(UI.galaxy.load_queue, {type = "cartel", name = cn})
    end
    f2t_debug_log("[galaxy] Found %d cartels", #cartel_list)
    ui_galaxy_process_queue()
end

function ui_galaxy_process_queue()
    if #UI.galaxy.load_queue == 0 then
        UI.galaxy.loading           = false
        UI.galaxy.loading_automated = false

        -- Only stamp the overall DB timestamp on a full refresh.
        if UI.galaxy.is_full_refresh then
            UI.galaxy.last_updated  = os.time()
            UI.galaxy.is_full_refresh = false
        end

        ui_galaxy_save()
        cecho("\n<green>[Galaxy]<reset> Galaxy data loaded successfully!\n")
        UI.galaxy.loaded = true

        if UI.galaxy_dropdown and UI.galaxy.visible then
            ui_populate_galaxy_dropdown()
        end
        return
    end

    local item = table.remove(UI.galaxy.load_queue, 1)

    if item.type == "cartel" then
        UI.galaxy.current_cartel_loading = item.name
        UI.galaxy.member_capture_active  = true
        UI.galaxy.member_list            = {}
        UI.galaxy.member_capturing       = false
        tempTimer(0.3, function() sendAll("di cartel " .. item.name, false) end)

    elseif item.type == "system" then
        UI.galaxy.current_system_loading = {cartel = item.cartel, system = item.name}
        UI.galaxy.planet_capture_active  = true
        UI.galaxy.planet_list            = {}
        tempTimer(0.3, function() sendAll("di system " .. item.name, false) end)
    end
end

function ui_galaxy_parse_cartel_info(cartel_name, members)
    if not UI.galaxy.loading_automated then return end
    if not UI.galaxy.cartels[cartel_name] then return end

    UI.galaxy.cartels[cartel_name].members   = members
    -- Stamp ONLY this cartel; do not touch other cartels' timestamps.
    UI.galaxy.cartel_timestamps[cartel_name] = os.time()

    for _, sn in ipairs(members) do
        table.insert(UI.galaxy.load_queue, {type = "system", name = sn, cartel = cartel_name})
    end

    f2t_debug_log("[galaxy] Cartel %s has %d systems", cartel_name, #members)
    tempTimer(0.3, function() ui_galaxy_process_queue() end)
end

function ui_galaxy_parse_system_info(system_name, cartel_name, planets)
    if not UI.galaxy.loading_automated then return end
    if not UI.galaxy.cartels[cartel_name] then return end

    UI.galaxy.cartels[cartel_name].systems[system_name] = {
        name    = system_name,
        cartel  = cartel_name,
        planets = planets
    }
    -- Stamp ONLY this system.
    UI.galaxy.system_timestamps[cartel_name .. ":" .. system_name] = os.time()

    f2t_debug_log("[galaxy] System %s has %d planets", system_name, #planets)
    tempTimer(0.3, function() ui_galaxy_process_queue() end)
end

-- ── Navigation / info ────────────────────────────────────────────────────────

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
    local was = UI.galaxy.loading_automated
    UI.galaxy.loading_automated = false
    if location_type == "cartel" then
        send("di cartel " .. location_name)
    elseif location_type == "system" then
        send("di system " .. location_name)
    elseif location_type == "planet" then
        send("di planet " .. location_name)
    end
    tempTimer(0.5, function() UI.galaxy.loading_automated = was end)
end

-- ============================================================================
-- LINE CAPTURE HANDLERS
-- ============================================================================

function ui_galaxy_capture_cartel_line(line)
    if not UI.galaxy.cartel_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    local cartel = line:match("^%s*(.-)%s*$")
    if cartel and cartel ~= "" then
        table.insert(UI.galaxy.cartel_list, cartel)
    end
end

function ui_galaxy_finish_cartel_capture()
    if not UI.galaxy.cartel_capture_active then return end
    UI.galaxy.cartel_capture_active = false
    if #UI.galaxy.cartel_list > 0 then
        ui_galaxy_parse_cartels(UI.galaxy.cartel_list)
    else
        cecho("\n<red>[Galaxy]<reset> No cartels captured!\n")
        UI.galaxy.loading           = false
        UI.galaxy.loading_automated = false
    end
end

function ui_galaxy_start_member_capturing()
    if not UI.galaxy.member_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    UI.galaxy.member_capturing = true
end

function ui_galaxy_capture_member_line(line)
    if not UI.galaxy.member_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    if not UI.galaxy.member_capturing then return end
    if line and line ~= "" then
        table.insert(UI.galaxy.member_list, line)
    end
end

function ui_galaxy_finish_member_capture()
    if not UI.galaxy.member_capture_active then return end
    UI.galaxy.member_capture_active = false
    UI.galaxy.member_capturing      = false
    local cn = UI.galaxy.current_cartel_loading
    if cn then
        if #UI.galaxy.member_list > 0 then
            ui_galaxy_parse_cartel_info(cn, UI.galaxy.member_list)
        else
            tempTimer(0.3, function() ui_galaxy_process_queue() end)
        end
    end
end

function ui_galaxy_capture_planet_line(planet_name, system_name, cartel_name)
    if not UI.galaxy.planet_capture_active then return end
    if not UI.galaxy.loading_automated then return end
    table.insert(UI.galaxy.planet_list, {name = planet_name, system = system_name, cartel = cartel_name})
end

function ui_galaxy_finish_planet_capture()
    if not UI.galaxy.planet_capture_active then return end
    UI.galaxy.planet_capture_active = false
    local si = UI.galaxy.current_system_loading
    if si and #UI.galaxy.planet_list > 0 then
        ui_galaxy_parse_system_info(si.system, si.cartel, UI.galaxy.planet_list)
    elseif si then
        tempTimer(0.3, function() ui_galaxy_process_queue() end)
    end
end

-- ============================================================================
-- CONFIRMATION POPUP
-- ============================================================================

function ui_show_refresh_confirmation()
    if UI.galaxy_confirm_popup then UI.galaxy_confirm_popup:hide() end

    UI.galaxy_confirm_popup = Geyser.Label:new({
        name = "galaxy_confirm_popup",
        x = "35%", y = "40%", width = "30%", height = "20%"
    })
    UI.galaxy_confirm_popup:setStyleSheet([[
        background-color: rgb(25, 25, 35);
        border: 2px solid rgba(255, 255, 255, 0.46);
        border-radius: 5px;
    ]])

    local title = Geyser.Label:new({x=0, y="5%", width="100%", height="25%"}, UI.galaxy_confirm_popup)
    title:setStyleSheet("background-color:transparent; color:rgba(200,200,210,255); font-size:14px; font-weight:bold;")
    title:echo("<center>Refresh All Galaxy Data?</center>")

    local msg = Geyser.Label:new({x="5%", y="30%", width="90%", height="30%"}, UI.galaxy_confirm_popup)
    msg:setStyleSheet("background-color:transparent; color:rgba(200,200,210,200); font-size:11px;")
    msg:echo("<center>This will take 1-2 minutes</center>")

    local ok = Geyser.Label:new({x="15%", y="65%", width="30%", height="25%"}, UI.galaxy_confirm_popup)
    ok:setStyleSheet(UI.style.button_css)
    ok:echo("<center>OK</center>")
    ok:setClickCallback(function()
        UI.galaxy_confirm_popup:hide()
        UI.galaxy.loaded  = false
        UI.galaxy.cartels = {}
        ui_galaxy_init("all")
    end)

    local cancel = Geyser.Label:new({x="55%", y="65%", width="30%", height="25%"}, UI.galaxy_confirm_popup)
    cancel:setStyleSheet(UI.style.button_css)
    cancel:echo("<center>Cancel</center>")
    cancel:setClickCallback(function() UI.galaxy_confirm_popup:hide() end)

    UI.galaxy_confirm_popup:show()
    UI.galaxy_confirm_popup:raise()
end

-- ============================================================================
-- GALAXY UI
-- ============================================================================

UI.galaxy_button_active = false

-- Shared style constants
local _BG  = "background-color: rgb(18, 18, 26); border: none;"
local _ROW = "background-color: rgb(22, 22, 30); border: none; border-bottom: 1px solid rgba(255,255,255,10);"

-- ── Column/layout constants (all in % of row width) ──────────────────────────
--
-- EVERY row is positioned at x=0 to prevent horizontal overflow.
-- Indentation is achieved purely via the x-position of internal children,
-- never by offsetting the row itself.
--
-- Fixed right-edge columns ensure buttons align vertically across all tiers:
--   Refresh col : 93–98%   (cartel and system only)
--   Nav col     : 87–92%   (system and planet only)
--   Name ends at 86%       (shrinks with indent so it never pushes buttons right)
--
-- Per-level indent = 4%. Expand slot = 5%. Icon slot = 5%.
-- name_x = indent*4 + 10,  name_w = 86 - name_x
--
--   Cartel (0): expand@0, icon@5,  name@10 w=76, refresh@93
--   System (1): expand@4, icon@9,  name@14 w=72, nav@87, refresh@93
--   Planet (2): (expand reserved), icon@13, name@18 w=68, nav@87
--
local INDENT_PCT   = 4    -- percent per indent level
local EXPAND_PCT   = 5    -- expand button slot width %
local ICON_PCT     = 5    -- icon slot width %
local NAME_END_PCT = 86   -- name label right edge %
local NAV_X        = "87%"
local REFRESH_X    = "93%"
local BTN_W        = "5%"
-- Row height in pixels — this is the one necessary pixel value because it is
-- coupled to font size, not window size.  Content label height is also pixels
-- for the same reason (Geyser.ScrollBox needs a pixel-taller child to scroll).
local ROW_H = 23

-- ── Build the panel ──────────────────────────────────────────────────────────

function ui_build_galaxy_dropdown()
    if UI.galaxy_dropdown then
        UI.galaxy_dropdown:hide()
        return
    end

    -- ── Compute position from neighbouring UI objects ─────────────────────
    -- Right edge abuts UI.right_frame left edge.
    -- Top edge sits immediately below UI.top_right_frame bottom edge.
    local main_w, main_h = getMainWindowSize()

    local rf_x_px    = UI.right_frame:get_x()
    local trf_bot_px = UI.top_right_frame:get_y() + UI.top_right_frame:get_height()

    -- Panel is 18% of main window width.
    local panel_w_pct = 18
    local panel_w_px  = math.floor(main_w * panel_w_pct / 100)
    local panel_x_px  = rf_x_px - panel_w_px
    local panel_y_px  = trf_bot_px

    -- Height: from below top_right_frame to 97% of the main window.
    local panel_bot_px = math.floor(main_h * 0.97)
    local panel_h_px   = math.max(100, panel_bot_px - panel_y_px)

    local panel_x_str = string.format("%.2f%%", panel_x_px / main_w * 100)
    local panel_y_str = string.format("%.2f%%", panel_y_px / main_h * 100)
    local panel_h_str = string.format("%.2f%%", panel_h_px / main_h * 100)

    UI.galaxy_dropdown = Adjustable.Container:new({
        name          = "galaxy_dropdown",
        x             = panel_x_str,
        y             = panel_y_str,
        width         = panel_w_pct .. "%",
        height        = panel_h_str,
        adjLabelstyle = UI.style.frame_css,
        autoSave      = false,
        autoLoad      = false
    })
    UI.galaxy_dropdown:lockContainer("border")
    f2t_ui_register_container("galaxy_dropdown", UI.galaxy_dropdown)

    -- Fully opaque background — eliminates any transparency in frame_css.
    local bg = Geyser.Label:new({
        name = "galaxy_panel_bg", x=0, y=0, width="100%", height="100%"
    }, UI.galaxy_dropdown)
    bg:setStyleSheet("background-color: rgb(20, 20, 28); border: none;")

    -- ── Header (3%) ───────────────────────────────────────────────────────
    UI.galaxy_topbar = Geyser.Label:new({
        name = "galaxy_topbar", x=0, y=0, width="100%", height="3%"
    }, UI.galaxy_dropdown)
    UI.galaxy_topbar:setStyleSheet(UI.style.header_label_css)

    -- Title
    UI.galaxy_title = Geyser.Label:new({
        x="2%", y=0, width="64%", height="100%"
    }, UI.galaxy_topbar)
    UI.galaxy_title:setStyleSheet(
        "background-color:transparent; color:#c8c8d0; font-size:11px; font-weight:bold;")
    UI.galaxy_title:echo("Galaxy Navigator")

    -- Collapse all (−)  – clears UI.galaxy.expanded and redraws
    UI.galaxy_collapse_btn = Geyser.Label:new({
        x="67%", y="5%", width="9%", height="90%"
    }, UI.galaxy_topbar)
    UI.galaxy_collapse_btn:setStyleSheet(UI.style.button_css)
    UI.galaxy_collapse_btn:echo("<center>−</center>")
    UI.galaxy_collapse_btn:setClickCallback(function()
        UI.galaxy.expanded = {}
        ui_galaxy_save()
        ui_populate_galaxy_dropdown()
    end)
    UI.galaxy_collapse_btn:setToolTip("Collapse all")

    -- Refresh all (⟳)
    UI.galaxy_refresh_icon = Geyser.Label:new({
        x="77%", y="5%", width="9%", height="90%"
    }, UI.galaxy_topbar)
    UI.galaxy_refresh_icon:setStyleSheet(UI.style.button_css)
    UI.galaxy_refresh_icon:echo("<center>⟳</center>")
    UI.galaxy_refresh_icon:setClickCallback(function()
        ui_show_refresh_confirmation()
    end)
    UI.galaxy_refresh_icon:setToolTip("Refresh all galaxy data")

    -- Close (✕)
    UI.galaxy_close = Geyser.Label:new({
        x="88%", y="5%", width="10%", height="90%"
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
    end)

    -- ── Scroll area (3%–94%) ──────────────────────────────────────────────
    -- Do NOT call setStyleSheet on ScrollBox — it is unsupported and raises
    -- a runtime error.  Dark background comes from the content Label child.
    UI.galaxy_scroll = Geyser.ScrollBox:new({
        name = "galaxy_scroll",
        x="0%", y="3%", width="100%", height="94%"
    }, UI.galaxy_dropdown)

    -- ── Footer / legend (94%–100%, 6% total → 3% visible text row) ────────
    -- Shows the icon legend instead of a DB age (per-item ages are on each ⟳ tooltip).
    UI.galaxy_footer = Geyser.Label:new({
        name = "galaxy_footer",
        x=0, y="97%", width="100%", height="3%"
    }, UI.galaxy_dropdown)
    UI.galaxy_footer:setStyleSheet(UI.style.header_label_css)

    UI.galaxy_legend = Geyser.Label:new({
        x="1%", y=0, width="98%", height="100%"
    }, UI.galaxy_footer)
    UI.galaxy_legend:setStyleSheet(
        "background-color:transparent; color:rgba(160,160,170,190); font-size:9px;")
    UI.galaxy_legend:echo("<center>🌌 Cartel  ⭐ System  🌍 Planet</center>")

    -- Hide last, after all children exist, so nothing re-shows it mid-build.
    UI.galaxy_dropdown:hide()
end

-- ── Row builder ───────────────────────────────────────────────────────────────
-- y_px      : pixel y within the content label (necessary; see header comment)
-- row_type  : "cartel" | "system" | "planet"
-- data      : corresponding data table
function ui_create_galaxy_row(parent, name, row_type, indent_level, y_px, data)
    -- Row always at x=0 so it never overflows the content label width.
    local row = Geyser.Label:new({
        x = 0, y = y_px, width = "100%", height = ROW_H
    }, parent)
    row:setStyleSheet(_ROW)

    local indent_pct = indent_level * INDENT_PCT  -- e.g. 0, 4, 8

    -- ── Expand / collapse slot ───────────────────────────────────────────────
    -- Reserved for all row types (even planet) to keep icon column aligned.
    local exp_key
    if row_type == "cartel" then
        exp_key = name
    elseif row_type == "system" then
        exp_key = ((data and data.cartel) or "") .. ":" .. name
    end

    if exp_key then
        local is_exp = UI.galaxy.expanded[exp_key] or false
        local ebtn = Geyser.Label:new({
            x = indent_pct .. "%", y = 1,
            width = EXPAND_PCT .. "%", height = ROW_H - 2
        }, row)
        ebtn:setStyleSheet(UI.style.button_css)
        ebtn:echo(is_exp and "<center>−</center>" or "<center>+</center>")
        ebtn:setClickCallback(function()
            UI.galaxy.expanded[exp_key] = not UI.galaxy.expanded[exp_key]
            ui_galaxy_save()
            ui_populate_galaxy_dropdown()
        end)
    end
    -- (no expand for planet — slot is simply empty, preserving column alignment)

    -- ── Icon ─────────────────────────────────────────────────────────────────
    local icon_x_pct = indent_pct + EXPAND_PCT   -- just right of the expand slot

    local icon_map = {
        cartel = { "🌌", "#ff6b9d" },
        system = { "⭐",  "#ffd700" },
        planet = { "🌍", "#4ecdc4" }
    }
    local id = icon_map[row_type]
    local icon = Geyser.Label:new({
        x = icon_x_pct .. "%", y = 1,
        width = ICON_PCT .. "%", height = ROW_H - 2
    }, row)
    icon:setStyleSheet(string.format(
        "background-color:transparent; color:%s; font-size:11px;", id[2]))
    icon:echo("<center>" .. id[1] .. "</center>")

    -- ── Name label ───────────────────────────────────────────────────────────
    -- Width calculated so the RIGHT edge always lands at NAME_END_PCT,
    -- regardless of indent level — buttons therefore stay in fixed columns.
    local name_x_pct = icon_x_pct + ICON_PCT
    local name_w_pct = math.max(5, NAME_END_PCT - name_x_pct)

    local nlbl = Geyser.Label:new({
        x = name_x_pct .. "%", y = 1,
        width = name_w_pct .. "%", height = ROW_H - 2
    }, row)
    nlbl:setStyleSheet(UI.style.button_css)
    nlbl:echo(name)
    nlbl:setClickCallback(function() ui_galaxy_get_info(row_type, name) end)
    nlbl:setToolTip("Click for info")

    -- ── Nav button (→)  –  system and planet only, fixed column ─────────────
    if row_type == "system" or row_type == "planet" then
        local nbtn = Geyser.Label:new({
            x = NAV_X, y = 1, width = BTN_W, height = ROW_H - 2
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

    -- ── Refresh button (⟳)  –  cartel and system only, fixed column ─────────
    -- Tooltip shows ONLY this item's own timestamp; no cascading to parent/DB.
    if row_type == "cartel" or row_type == "system" then
        local cartel_for_age = (row_type == "cartel") and name or (data and data.cartel or name)
        local system_for_age = (row_type == "system") and name or nil
        local age_tip = ui_galaxy_get_item_age(row_type, cartel_for_age, system_for_age)

        local rbtn = Geyser.Label:new({
            x = REFRESH_X, y = 1, width = BTN_W, height = ROW_H - 2
        }, row)
        rbtn:setStyleSheet(UI.style.button_css)
        rbtn:echo("<center>⟳</center>")
        rbtn:setToolTip(age_tip)
        rbtn:setClickCallback(function()
            ui_galaxy_init(row_type, name)
            tempTimer(0.5, function()
                if UI.galaxy_dropdown and UI.galaxy.visible then
                    ui_populate_galaxy_dropdown()
                end
            end)
        end)
    end

    return row
end

-- ── Count visible rows (excluding cartel-name systems) ───────────────────────
local function _count_visible_rows(sorted_cartels)
    local n = 0
    for _, cn in ipairs(sorted_cartels) do
        n = n + 1  -- cartel header row
        if UI.galaxy.expanded[cn] then
            local cd = UI.galaxy.cartels[cn]
            for sn in pairs(cd.systems or {}) do
                -- Skip exact-name match and "[CartelName] Space" entry.
                if sn ~= cn and sn ~= (cn .. " Space") then
                    n = n + 1
                    local sys_key = cn .. ":" .. sn
                    if UI.galaxy.expanded[sys_key] then
                        local sd = cd.systems[sn]
                        for _, pd in ipairs((sd or {}).planets or {}) do
                            -- Skip "SystemName Space" pseudo-planet only
                            if pd.name ~= (sn .. " Space") then
                                n = n + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return n
end

-- ── Populate the scrollable tree ──────────────────────────────────────────────
function ui_populate_galaxy_dropdown()
    if not UI.galaxy_scroll then return end

    -- Destroy previous content label
    if UI.galaxy_scroll_content then
        UI.galaxy_scroll_content:hide()
        UI.galaxy_scroll_content = nil
    end

    -- Keep the refresh-all tooltip current with the overall DB age
    if UI.galaxy_refresh_icon then
        local overall_age = _age_str(UI.galaxy.last_updated)
        UI.galaxy_refresh_icon:setToolTip("Last full refresh: " .. overall_age)
    end

    -- ── Loading / empty states ───────────────────────────────────────────────
    if UI.galaxy.loading then
        UI.galaxy_scroll_content = Geyser.Label:new({
            name = "galaxy_scroll_content",
            x=0, y=0, width="96%", height=2000
        }, UI.galaxy_scroll)
        UI.galaxy_scroll_content:setStyleSheet(_BG)
        local lbl = Geyser.Label:new({x=0, y="40%", width="100%", height=40}, UI.galaxy_scroll_content)
        lbl:setStyleSheet("background-color:transparent; color:rgba(200,200,100,220); font-size:11px;")
        lbl:echo("<center>Loading galaxy data…</center>")
        return

    elseif not UI.galaxy.loaded then
        UI.galaxy_scroll_content = Geyser.Label:new({
            name = "galaxy_scroll_content",
            x=0, y=0, width="96%", height=2000
        }, UI.galaxy_scroll)
        UI.galaxy_scroll_content:setStyleSheet(_BG)
        local lbl = Geyser.Label:new({x=0, y="40%", width="100%", height=50}, UI.galaxy_scroll_content)
        lbl:setStyleSheet("background-color:transparent; color:rgba(200,100,100,220); font-size:11px;")
        lbl:echo("<center>No galaxy data<br/>Click ⟳ to load</center>")
        return
    end

    -- ── Sort cartels ─────────────────────────────────────────────────────────
    local sorted_cartels = {}
    for cn in pairs(UI.galaxy.cartels) do table.insert(sorted_cartels, cn) end
    table.sort(sorted_cartels)

    -- ── Size the content label to exactly fit all visible rows ───────────────
    -- Pixel height is required here so the ScrollBox knows the scroll range.
    -- Width is 96% to leave room for the vertical scrollbar; this prevents
    -- the horizontal scrollbar that would appear if content fills 100%.
    local visible_rows = _count_visible_rows(sorted_cartels)
    -- Minimum of 2000px ensures the dark background always fills the full
    -- visible scroll area even when the list is short, preventing white gaps.
    local content_h    = math.max(visible_rows * ROW_H + 4, 2000)

    UI.galaxy_scroll_content = Geyser.Label:new({
        name   = "galaxy_scroll_content",
        x=0, y=0, width="96%", height=content_h
    }, UI.galaxy_scroll)
    UI.galaxy_scroll_content:setStyleSheet(_BG)

    -- ── Render tree ──────────────────────────────────────────────────────────
    local y_px = 2

    for _, cartel_name in ipairs(sorted_cartels) do
        local cartel_data = UI.galaxy.cartels[cartel_name]

        ui_create_galaxy_row(UI.galaxy_scroll_content, cartel_name, "cartel", 0, y_px, cartel_data)
        y_px = y_px + ROW_H

        if UI.galaxy.expanded[cartel_name] then
            local sorted_sys = {}
            for sn in pairs(cartel_data.systems or {}) do
                table.insert(sorted_sys, sn)
            end
            table.sort(sorted_sys)

            for _, system_name in ipairs(sorted_sys) do
                -- Skip exact-name match and "[CartelName] Space" entry.
                if system_name ~= cartel_name and system_name ~= (cartel_name .. " Space") then
                    local system_data = cartel_data.systems[system_name]

                    ui_create_galaxy_row(UI.galaxy_scroll_content, system_name, "system", 1, y_px, system_data)
                    y_px = y_px + ROW_H

                    local sys_key = cartel_name .. ":" .. system_name
                    if UI.galaxy.expanded[sys_key] then
                        for _, planet_data in ipairs(system_data.planets or {}) do
                            -- Skip "SystemName Space" pseudo-planet only
                            if planet_data.name ~= (system_name .. " Space") then
                                ui_create_galaxy_row(UI.galaxy_scroll_content, planet_data.name, "planet", 2, y_px, planet_data)
                                y_px = y_px + ROW_H
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ── Toggle visibility ─────────────────────────────────────────────────────────
function ui_toggle_galaxy()
    if not UI.galaxy_dropdown then
        ui_build_galaxy_dropdown()
        -- build ends with hide(); UI.galaxy.visible is false by initialisation.
        -- Fall straight through to the show branch below.
    end

    if UI.galaxy.visible then
        UI.galaxy_dropdown:hide()
        UI.galaxy.visible       = false
        UI.galaxy_button_active = false
    else
        if not UI.galaxy.loaded and not UI.galaxy.loading then
            if not ui_galaxy_load() then
                ui_galaxy_init("all")
            end
        end
        ui_populate_galaxy_dropdown()
        UI.galaxy_dropdown:show()
        UI.galaxy_dropdown:raise()
        UI.galaxy.visible       = true
        UI.galaxy_button_active = true
    end
end