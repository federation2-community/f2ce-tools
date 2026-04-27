-- =============================================================================
-- ui_settings.lua  —  Floating settings window
-- Driven entirely by F2T_SETTINGS_REGISTRY / F2T_SETTINGS_ORDER.
-- Widget type is inferred from registration metadata; no component-specific code.
--
-- Uses Adjustable.Container for drag/resize.  All child widgets are parented
-- to the AC's .Inside container so they render *inside* the window.
--
-- All content uses percentage-based sizing so it resizes with the AC.
-- Row content is rebuilt on tab switch using the current interior dimensions.
--
-- Settings are applied via _apply_setting() with console echo and
-- side-effect dispatch so the UI behaves identically to CLI commands.
--
-- NOTE: Geyser.CommandLine does not support setStyleSheet() — this is a known
-- Mudlet limitation.  The input fields will use the default system appearance.
-- We use setFont() where possible.
-- =============================================================================

UI.settings_window         = nil
UI.settings_window_visible = false
UI.settings_tabs           = {}
UI.settings_content        = nil
UI.settings_content_w      = 400
UI.settings_rows           = {}
UI.settings_draw_epoch     = 0
UI.settings_current_tab    = nil
UI.settings_components     = {}
UI.settings_open_dropdown  = nil
UI.settings_tooltip        = nil

local _ROW_H      = 56   -- standard row height (toggle/stepper/dropdown)
local _ROW_H_WIDE = 64   -- taller row for string text entries (name + input)
local _TAB_H      = 28   -- tab bar height
local _WIDGET_W   = 130  -- default widget area width
local _WIDGET_H   = 26   -- widget height
local _PAD_L      = 10   -- left-side text padding
local _PAD_R      = 6    -- right padding after reset icon
local _RESET_W    = 20   -- width of the reset-to-default icon
local _TAB_CHAR_W = 8
local _TAB_PAD    = 24
local _FOOTER_PAD = 16

local _SETTINGS_FRAME_CSS = [[
    background-color: rgb(18, 18, 26);
    border: 2px solid rgba(255,255,255,0.46);
    border-radius: 4px;
]]

-- High-contrast row alternation
local _CSS_ODD  = "background:rgb(16,16,24); border:none; border-bottom:2px solid rgba(255,255,255,0.18);"
local _CSS_EVEN = "background:rgb(34,34,50); border:none; border-bottom:2px solid rgba(255,255,255,0.18);"

-- ── Known side-effect dispatch ────────────────────────────────────────────────
local _SIDE_EFFECTS = {
    ["shared.debug"] = function(value)
        F2T_DEBUG = value
    end,
    ["ui.enabled"] = function(value)
        expandAlias("ui " .. (value and "on" or "off"))
    end,
}

-- ── Close any open dropdown ──────────────────────────────────────────────────
local function _close_dropdown()
    if UI.settings_open_dropdown then
        UI.settings_open_dropdown:hide()
        UI.settings_open_dropdown = nil
    end
end

-- ── Instant tooltip ──────────────────────────────────────────────────────────
local function _show_tooltip(text, abs_x, abs_y)
    if not UI.settings_tooltip then
        UI.settings_tooltip = Geyser.Label:new({
            name = "ui_set_tooltip", x = 0, y = 0, width = 300, height = 40,
        })
    end
    local tt = UI.settings_tooltip
    local w = math.max(200, math.min(450, #text * 6 + 24))
    tt:resize(w, 36)
    tt:move(abs_x + 20, abs_y - 10)
    tt:setStyleSheet([[
        background-color: rgb(40,40,60);
        color: #e0e0f0;
        font-size: 10px;
        font-family: "Consolas", "Monaco", monospace;
        border: 1px solid rgba(120,180,255,0.5);
        border-radius: 4px;
        padding: 4px 8px;
    ]])
    tt:echo(text)
    tt:show()
    tt:raise()
end

local function _hide_tooltip()
    if UI.settings_tooltip then
        UI.settings_tooltip:hide()
    end
end

-- ── Apply a setting ──────────────────────────────────────────────────────────
local function _apply_setting(comp, name, value)
    local ok, err = f2t_settings_set(comp, name, value)
    if ok then
        cecho(string.format("\n<green>[%s]<reset> Setting <cyan>%s<reset> set to <yellow>%s<reset>\n",
            comp, name, tostring(value)))
        local key = comp .. "." .. name
        if _SIDE_EFFECTS[key] then _SIDE_EFFECTS[key](value) end
    else
        cecho(string.format("\n<red>[%s]<reset> %s.%s: %s\n", comp, comp, name, err or "invalid"))
    end
    return ok, err
end

-- ── Widget type inference ────────────────────────────────────────────────────
local function _widget_type(cfg)
    if cfg.choices then return "dropdown" end
    if type(cfg.default) == "boolean" then return "toggle" end
    if type(cfg.default) == "number"
        and cfg.min ~= nil and cfg.max ~= nil
        and (cfg.max - cfg.min) <= 100
    then
        return "stepper"
    end
    return "textentry"
end

local function _widget_width(cfg, content_w)
    local wt = _widget_type(cfg)
    if wt == "textentry" and type(cfg.default) == "string" then
        return content_w - _PAD_L * 2 - _RESET_W - _PAD_R
    end
    return _WIDGET_W
end

-- ── Individual widget builders ────────────────────────────────────────────────

local function _make_toggle(parent, wx, wy, uid, comp, name, widget_w)
    local css_on  = [[QLabel{background:rgb(30,70,40);color:#88ee88;font-size:10px;font-weight:bold;border:1px solid rgba(80,180,80,0.5);border-radius:3px;}QLabel::hover{background:rgb(40,90,50);}]]
    local css_off = [[QLabel{background:rgb(65,30,30);color:rgba(220,120,120,0.9);font-size:10px;font-weight:bold;border:1px solid rgba(180,80,80,0.4);border-radius:3px;}QLabel::hover{background:rgb(85,40,40);}]]

    local w = Geyser.Label:new({
        name=uid.."_tog", x=wx, y=wy, width=widget_w, height=_WIDGET_H
    }, parent)

    local function _ref()
        local v = f2t_settings_get(comp, name)
        w:setStyleSheet(v and css_on or css_off)
        w:echo("<center>" .. (v and "ON" or "OFF") .. "</center>")
    end
    _ref()
    w:setClickCallback(function()
        _close_dropdown()
        _apply_setting(comp, name, not f2t_settings_get(comp, name))
        _ref()
    end)
    return _ref
end

local function _make_dropdown(parent, wx, wy, uid, comp, name, choices, widget_w, row_abs_y, btn_abs_x)
    local css_btn = [[QLabel{background:rgb(38,38,58);color:#d8d8f0;font-size:10px;border:1px solid rgba(255,255,255,0.22);border-radius:3px;font-family:"Consolas","Monaco",monospace;}QLabel::hover{background:rgb(55,55,80);border-color:rgba(120,180,255,0.5);}]]

    local btn = Geyser.Label:new({
        name=uid.."_dd_btn", x=wx, y=wy, width=widget_w, height=_WIDGET_H
    }, parent)
    btn:setStyleSheet(css_btn)

    local function _ref()
        local v = tostring(f2t_settings_get(comp, name) or "")
        local disp = #v > 16 and v:sub(1,15).."…" or v
        btn:echo("<center>" .. disp .. " ▾</center>")
    end
    _ref()

    local overlay_name = uid .. "_dd_ov"
    local overlay = nil

    local function _destroy_overlay()
        if overlay then
            overlay:hide()
            for ci = 1, #choices do
                local n = overlay_name .. "_o" .. ci
                if Geyser.windowList[n] then Geyser.windowList[n]:hide() end
            end
            overlay = nil
        end
        if UI.settings_open_dropdown == overlay then UI.settings_open_dropdown = nil end
    end

    local function _open_overlay()
        local css_panel = "background:rgb(28,28,44); border:1px solid rgba(255,255,255,0.3); border-radius:3px;"
        local css_opt   = [[QLabel{background:rgb(32,32,50);color:#d8d8f0;font-size:10px;border:none;border-bottom:1px solid rgba(255,255,255,0.08);font-family:"Consolas","Monaco",monospace;padding-left:6px;}QLabel::hover{background:rgb(50,60,90);color:white;}]]
        local oh = _WIDGET_H
        overlay = Geyser.Label:new({
            name=overlay_name, x=btn_abs_x, y=row_abs_y+wy+_WIDGET_H,
            width=widget_w, height=#choices*oh
        })
        overlay:setStyleSheet(css_panel)
        overlay:show(); overlay:raise()
        for ci, choice in ipairs(choices) do
            local opt = Geyser.Label:new({
                name=overlay_name.."_o"..ci, x=0, y=(ci-1)*oh, width=widget_w, height=oh
            }, overlay)
            opt:setStyleSheet(css_opt)
            opt:echo("  " .. tostring(choice))
            opt:show(); opt:raise()
            local _c = choice
            opt:setClickCallback(function()
                _apply_setting(comp, name, _c); _ref()
                _destroy_overlay(); UI.settings_open_dropdown = nil
            end)
        end
        UI.settings_open_dropdown = overlay
    end

    btn:setClickCallback(function()
        if UI.settings_open_dropdown then
            local was = (UI.settings_open_dropdown == overlay)
            _close_dropdown(); _destroy_overlay()
            if was then return end
        end
        _open_overlay()
    end)
    return _ref
end

local function _make_stepper(parent, wx, wy, uid, comp, name, cfg, widget_w)
    local css_btn = [[QLabel{background:rgb(45,45,68);color:#c0c8e8;font-size:13px;font-weight:bold;border:1px solid rgba(255,255,255,0.2);border-radius:2px;font-family:"Consolas","Monaco",monospace;}QLabel::hover{background:rgb(62,62,90);}]]
    local css_val = [[background:transparent; color:#e8e8f8; font-size:11px; font-weight:bold; font-family:"Consolas","Monaco",monospace;]]
    local bw = 26
    local vw = widget_w - bw*2 - 4
    local minus = Geyser.Label:new({name=uid.."_sm", x=wx,           y=wy, width=bw, height=_WIDGET_H}, parent)
    local vl    = Geyser.Label:new({name=uid.."_sv", x=wx+bw+2,      y=wy, width=vw, height=_WIDGET_H}, parent)
    local plus  = Geyser.Label:new({name=uid.."_sp", x=wx+bw+2+vw+2, y=wy, width=bw, height=_WIDGET_H}, parent)
    minus:setStyleSheet(css_btn); minus:echo("<center>−</center>")
    vl:setStyleSheet(css_val)
    plus:setStyleSheet(css_btn);  plus:echo("<center>+</center>")
    local function _ref()
        vl:echo("<center>" .. tostring(f2t_settings_get(comp, name)) .. "</center>")
    end
    _ref()
    minus:setClickCallback(function()
        _close_dropdown()
        _apply_setting(comp, name, math.max(cfg.min, (f2t_settings_get(comp,name) or cfg.min)-1)); _ref()
    end)
    plus:setClickCallback(function()
        _close_dropdown()
        _apply_setting(comp, name, math.min(cfg.max, (f2t_settings_get(comp,name) or cfg.min)+1)); _ref()
    end)
    return _ref
end

-- Text entry + Apply button
-- NOTE: Geyser.CommandLine cannot be styled via setStyleSheet() — Mudlet limitation.
-- We use setFont() for the font, and accept the system input appearance.
local function _make_textentry(parent, wx, wy, uid, comp, name, cfg, widget_w)
    local apply_w = 46
    local gap     = 3
    local input_w = widget_w - apply_w - gap

    local css_apply = [[QLabel{
        background-color: rgba(40, 40, 45, 200);
        border: 1px solid rgba(100, 100, 110, 180);
        border-radius: 3px;
        color: rgba(200, 200, 210, 255);
        font-size: 9px; font-weight: bold;
        font-family: "Consolas", "Monaco", monospace;
    }QLabel::hover{
        background-color: rgba(60, 60, 70, 220);
        border-color: rgba(120, 180, 255, 200);
        color: white;
    }]]

    local input_name = uid .. "_input"
    local input = Geyser.CommandLine:new({
        name=input_name, x=wx, y=wy, width=input_w, height=_WIDGET_H
    }, parent)

    -- Style: darker than even-rows so it stands out, with visible border
    input:setStyleSheet([[
        background-color: rgb(12, 12, 18);
        color: #c8c8d0;
        font-size: 12px;
        font-family: "Consolas", "Monaco", monospace;
        border: 1px solid rgba(255, 255, 255, 0.46);
        border-radius: 3px;
        padding-left: 6px;
        padding-right: 4px;
    ]])

    local cur = tostring(f2t_settings_get(comp, name) or "")
    input:print(cur)

    local apply_btn = Geyser.Label:new({
        name=uid.."_apply", x=wx+input_w+gap, y=wy, width=apply_w, height=_WIDGET_H
    }, parent)
    apply_btn:setStyleSheet(css_apply)
    apply_btn:echo("<center>Apply</center>")

    local function _commit()
        _close_dropdown()
        local text = input:getText()
        if text == nil or text == "" then return end
        local ok = _apply_setting(comp, name, text)
        if ok then input:print(tostring(f2t_settings_get(comp, name) or "")) end
    end
    input:setAction(_commit)
    apply_btn:setClickCallback(_commit)

    -- Return a refresh function
    return function()
        input:print(tostring(f2t_settings_get(comp, name) or ""))
    end
end

-- ── Reset-to-default icon ────────────────────────────────────────────────────
local function _make_reset_icon(parent, rx, ry, uid, comp, name, refresh_fn)
    local css_reset = [[
      QLabel{
          background: transparent;
          color: rgba(180,180,200,0.5);
          font-size: 12px;
          font-family: "Consolas","Monaco",monospace;
          border: 1px solid rgba(180,180,200,0.2);
          border-radius: 3px;
      }
      QLabel::hover{
          color: rgba(255,180,100,1.0);
          border-color: rgba(255,180,100,0.5);
          background: rgba(255,180,100,0.1);
      }
    ]]

    local icon = Geyser.Label:new({
        name=uid.."_reset", x=rx, y=ry, width=_RESET_W, height=_WIDGET_H
    }, parent)
    icon:setStyleSheet(css_reset)
    icon:echo("<center>↺</center>")
    icon:setOnEnter(function()
        _show_tooltip("Reset to default", parent:get_x() + rx, parent:get_y() + ry)
    end)
    icon:setOnLeave(function() _hide_tooltip() end)
    icon:setClickCallback(function()
        _close_dropdown()
        local ok, err = f2t_settings_clear(comp, name)
        if ok then
            local default_val = f2t_settings_get(comp, name)
            cecho(string.format("\n<green>[%s]<reset> Setting <cyan>%s<reset> reset to default: <yellow>%s<reset>\n",
                comp, name, tostring(default_val)))
            local key = comp .. "." .. name
            if _SIDE_EFFECTS[key] then _SIDE_EFFECTS[key](default_val) end
            if refresh_fn then refresh_fn() end
        else
            cecho(string.format("\n<red>[%s]<reset> %s\n", comp, err or "error"))
        end
    end)
end

-- ── Build all rows ───────────────────────────────────────────────────────────

local function _build_rows(comp, content_lbl)
    local content_w = content_lbl:get_width()
    if content_w < 50 then content_w = UI.settings_content_w end

    local order = (F2T_SETTINGS_ORDER and F2T_SETTINGS_ORDER[comp]) or {}
    if #order == 0 then
        for k in pairs(F2T_SETTINGS_REGISTRY[comp] or {}) do table.insert(order, k) end
        table.sort(order)
    end

    local epoch = UI.settings_draw_epoch
    -- Bold white name
    local css_name = [[
        background: transparent;
        color: #ffffff;
        font-size: 13px;
        font-weight: bold;
        font-family: "Consolas", "Monaco", monospace;
    ]]
    local css_help = [[
      QLabel{
        background: rgba(60,80,120,0.25);
        color: rgba(140,175,230,0.85);
        font-size: 11px;
        font-weight: bold;
        font-family: "Consolas", "Monaco", monospace;
        border: 1px solid rgba(100,140,200,0.35);
        border-radius: 8px;
      }
      QLabel::hover{
        color: rgba(180,210,255,1.0);
        border-color: rgba(150,200,255,0.7);
        background: rgba(60,80,120,0.5);
      }
    ]]

    local content_abs_x = content_lbl:get_x()
    local content_abs_y = content_lbl:get_y()

    local y = 2

    for i, setting_name in ipairs(order) do
        local cfg = F2T_SETTINGS_REGISTRY[comp] and F2T_SETTINGS_REGISTRY[comp][setting_name]
        if cfg then
            local uid = string.format("set_%d_%s_%s", epoch, comp, setting_name):gsub("[^%w_]", "_")

            local wt = _widget_type(cfg)
            local ww = _widget_width(cfg, content_w)
            local is_wide = (wt == "textentry" and type(cfg.default) == "string")

            local row_h = is_wide and _ROW_H_WIDE or _ROW_H
            local row = Geyser.Label:new({
                name=uid.."_row", x=0, y=y, width=content_w, height=row_h
            }, content_lbl)
            row:setStyleSheet((i%2==1) and _CSS_ODD or _CSS_EVEN)
            table.insert(UI.settings_rows, row)

            local wy_widget = math.floor((row_h - _WIDGET_H) / 2)
            local icon_abs_x = content_abs_x + _PAD_L
            local icon_abs_y = content_abs_y + y
            local desc = cfg.description or setting_name

            -- The available width for the widget column, minus reset icon on the right
            local reset_x = content_w - _RESET_W - _PAD_R
            local refresh_fn = nil

            if is_wide then
                -- [ⓘ] name                            [↺]
                -- [  input field  ] [Apply]

                local help_icon = Geyser.Label:new({
                    name=uid.."_help", x=_PAD_L, y=6, width=16, height=16
                }, row)
                help_icon:setStyleSheet(css_help)
                help_icon:echo("<center>i</center>")
                help_icon:setOnEnter(function() _show_tooltip(desc, icon_abs_x, icon_abs_y) end)
                help_icon:setOnLeave(function() _hide_tooltip() end)

                local nl = Geyser.Label:new({
                    name=uid.."_n", x=_PAD_L+20, y=4, width=content_w-_PAD_L-60, height=20
                }, row)
                nl:setStyleSheet(css_name)
                nl:echo(setting_name)

                local input_y = 32
                refresh_fn = _make_textentry(row, _PAD_L, input_y, uid, comp, setting_name, cfg, ww)

                _make_reset_icon(row, reset_x, 4, uid, comp, setting_name, refresh_fn)
            else
                -- [ⓘ] name ......... [widget] [↺]
                local wx = content_w - _WIDGET_W - _RESET_W - _PAD_R - 10
                local label_w = wx - _PAD_L - 24

                local help_icon = Geyser.Label:new({
                    name=uid.."_help", x=_PAD_L, y=math.floor((row_h-16)/2), width=16, height=16
                }, row)
                help_icon:setStyleSheet(css_help)
                help_icon:echo("<center>i</center>")
                help_icon:setOnEnter(function() _show_tooltip(desc, icon_abs_x, icon_abs_y) end)
                help_icon:setOnLeave(function() _hide_tooltip() end)

                local nl = Geyser.Label:new({
                    name=uid.."_n", x=_PAD_L+20, y=math.floor((row_h-20)/2), width=label_w, height=20
                }, row)
                nl:setStyleSheet(css_name)
                nl:echo(setting_name)

                local row_abs_y = content_abs_y + y
                local btn_abs_x = content_abs_x + wx

                if     wt == "toggle"    then refresh_fn = _make_toggle(row, wx, wy_widget, uid, comp, setting_name, _WIDGET_W)
                elseif wt == "dropdown"  then refresh_fn = _make_dropdown(row, wx, wy_widget, uid, comp, setting_name, cfg.choices, _WIDGET_W, row_abs_y, btn_abs_x)
                elseif wt == "stepper"   then refresh_fn = _make_stepper(row, wx, wy_widget, uid, comp, setting_name, cfg, _WIDGET_W)
                else                          refresh_fn = _make_textentry(row, wx, wy_widget, uid, comp, setting_name, cfg, _WIDGET_W)
                end

                _make_reset_icon(row, reset_x, wy_widget, uid, comp, setting_name, refresh_fn)
            end

            y = y + row_h
        end
    end

    return y
end

-- ── Count max rows ───────────────────────────────────────────────────────────

local function _max_rows_across_tabs()
    local max_rows = 0
    for comp, settings in pairs(F2T_SETTINGS_REGISTRY) do
        local count = 0
        for _ in pairs(settings) do count = count + 1 end
        if count > max_rows then max_rows = count end
    end
    return max_rows
end

-- ── Tab switching ────────────────────────────────────────────────────────────

function ui_settings_show_tab(comp)
    _close_dropdown()
    _hide_tooltip()
    for _, r in ipairs(UI.settings_rows) do r:hide() end
    UI.settings_rows = {}
    UI.settings_draw_epoch = UI.settings_draw_epoch + 1
    for c, tab in pairs(UI.settings_tabs) do
        tab:setStyleSheet(c == comp and UI.style.active_tab_css or UI.style.inactive_tab_css)
    end
    _build_rows(comp, UI.settings_content)
    UI.settings_current_tab = comp
end

-- ── Rebuild on resize ────────────────────────────────────────────────────────

function ui_settings_on_reposition(_, container_name)
    if container_name ~= "f2t_settings_window" then return end
    if not UI.settings_window or not UI.settings_window_visible then return end
    if not UI.settings_current_tab then return end
    ui_settings_show_tab(UI.settings_current_tab)
end

-- ── Build the window ─────────────────────────────────────────────────────────

local function _build_settings_window()
    local sw, sh = getMainWindowSize()
    local w = math.floor(sw * 0.30)
    local max_rows    = _max_rows_across_tabs()
    local ac_overhead = 30
    -- Use _ROW_H_WIDE for worst case per row
    local content_h   = max_rows * _ROW_H_WIDE + _FOOTER_PAD
    local h = _TAB_H + content_h + ac_overhead
    h = math.min(h, math.floor(sh * 0.85))
    local x = math.floor((sw - w) / 2)
    local y = math.floor((sh - h) / 2)

    UI.settings_window = Adjustable.Container:new({
        name           = "f2t_settings_window",
        x = x, y = y, width = w, height = h,
        titleText      = "⚙  Settings",
        titleTxtColor  = "white",
        adjLabelstyle  = _SETTINGS_FRAME_CSS,
        buttonstyle    = [[QLabel{background:rgba(180,50,50,200);color:white;font-size:12px;
                           font-weight:bold;border-radius:3px;}
                           QLabel::hover{background:rgb(220,60,60);}]],
        lockStyle      = "border",
        raiseOnClick   = true,
        autoSave       = false,
        autoLoad       = false,
    })

    local interior = UI.settings_window.Inside

    local tab_bar = Geyser.Label:new({
        name="ui_set_tabbar", x=0, y=0, width="100%", height=_TAB_H,
    }, interior)
    tab_bar:setStyleSheet([[background:rgb(18,18,26); border:none; border-bottom:1px solid rgba(255,255,255,0.15); font-family:"Consolas","Monaco",monospace;]])

    local components = {}
    for comp in pairs(F2T_SETTINGS_REGISTRY) do table.insert(components, comp) end
    table.sort(components)

    UI.settings_tabs = {}
    local tx = 0
    for _, comp in ipairs(components) do
        local tw = #comp * _TAB_CHAR_W + _TAB_PAD
        local tab = Geyser.Label:new({
            name="ui_set_tab_"..comp, x=tx, y=0, width=tw, height=_TAB_H,
        }, tab_bar)
        tab:echo("<center>" .. comp .. "</center>")
        local _comp = comp
        tab:setClickCallback(function() ui_settings_show_tab(_comp) end)
        UI.settings_tabs[comp] = tab
        tx = tx + tw
    end

    UI.settings_content = Geyser.Label:new({
        name="ui_set_content", x=0, y=_TAB_H, width="100%", height="-".._TAB_H,
    }, interior)
    UI.settings_content:setStyleSheet("background:rgb(18,18,26); border:none;")

    UI.settings_rows       = {}
    UI.settings_components = components
    if #components > 0 then ui_settings_show_tab(components[1]) end
    UI.settings_window:raise()
end

-- ── Public toggle ────────────────────────────────────────────────────────────

function ui_toggle_settings()
    if not UI.settings_window then
        _build_settings_window()
        UI.settings_window_visible = true
        return
    end
    if UI.settings_window_visible then
        _close_dropdown(); _hide_tooltip()
        UI.settings_window:hide()
        UI.settings_window_visible = false
    else
        UI.settings_window:show()
        UI.settings_window_visible = true
        UI.settings_window:raise()
        if UI.settings_current_tab then ui_settings_show_tab(UI.settings_current_tab) end
    end
end