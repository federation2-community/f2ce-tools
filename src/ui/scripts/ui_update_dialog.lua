-- =============================================================================
-- UPDATE NOTIFICATION DIALOG
-- Rebuilt on each show so height can fit content exactly.
-- =============================================================================

UI = UI or {}

local _FRAME_CSS = [[
    background-color: rgba(10, 12, 22, 254);
    border: 2px solid rgba(255, 255, 255, 0.42);
    border-radius: 6px;
]]
local _CSS_HDR = [[
    background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
        stop:0 rgba(44,50,78,255), stop:1 rgba(22,26,44,255));
    color: rgba(220,230,255,255);
    font-size: 15px; font-weight: bold;
    font-family: "Consolas","Monaco",monospace;
    border-radius: 4px 4px 0 0;
    border-bottom: 1px solid rgba(255,255,255,0.16);
    padding: 0 12px;
]]
local _CSS_BODY = [[
    background: transparent;
    color: rgba(198,210,238,255);
    font-size: 13px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 14px;
]]
local _CSS_SUB = [[
    background: transparent;
    color: rgba(105,125,180,255);
    font-size: 11px;
    font-family: "Consolas","Monaco",monospace;
    padding: 0 14px;
]]
local _CSS_BTN = [[
    QLabel {
        background-color: rgba(36,40,62,230);
        color: rgba(178,190,225,255);
        border: 1px solid rgba(85,98,140,210);
        border-radius: 5px;
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(52,60,95,245);
        border-color: rgba(105,158,255,210);
        color: white;
    }
]]
local _CSS_OK = [[
    QLabel {
        background-color: rgba(18,58,34,240);
        color: rgba(115,222,148,255);
        border: 1px solid rgba(48,152,78,215);
        border-radius: 5px;
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(26,82,46,255);
        border-color: rgba(65,210,108,235);
        color: rgba(178,255,200,255);
    }
]]
local _CSS_DANGER = [[
    QLabel {
        background-color: rgba(52,18,18,230);
        color: rgba(210,120,115,255);
        border: 1px solid rgba(140,48,48,200);
        border-radius: 5px;
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(82,22,22,245);
        border-color: rgba(200,70,68,220);
        color: rgba(255,160,155,255);
    }
]]
local _CSS_XBTN = [[
    QLabel {
        background-color: transparent;
        color: rgba(200,210,240,160);
        font-size: 17px; font-weight: bold;
        border-radius: 3px;
    }
    QLabel::hover {
        background-color: rgba(200,50,50,200);
        color: white;
    }
]]

-- Unique name counter — each show call gets fresh widget names so Geyser's
-- registry never collides with the hidden widgets from the previous show.
local _n = 0

-- ── Close ─────────────────────────────────────────────────────────────────────

local function _close()
    if UI.update_dialog then
        UI.update_dialog:hide()
        UI.update_dialog  = nil
        UI.update_ver_lbl = nil
        UI.update_console = nil
    end
end

-- ── Height estimation ─────────────────────────────────────────────────────────
-- Estimates the pixel height needed for the MiniConsole to display the full
-- changelog without scrolling. Uses conservative char-per-line and px-per-line
-- values so the real render is very unlikely to exceed our estimate.

local _LINE_H     = 14   -- px per line at fontSize=10, Consolas
local _CHARS_LINE = 65   -- conservative chars-per-line at ~460px width

local function _estimate_console_h()
    local lines = 0
    if F2T_CHANGELOG and #F2T_CHANGELOG > 0 then
        for _, entry in ipairs(F2T_CHANGELOG) do
            lines = lines + 1  -- version header line
            local body = ((entry.body or ""):gsub("\r", ""))
            -- Split on explicit newlines; estimate wrapping for each segment.
            for seg in (body .. "\n"):gmatch("([^\n]*)\n") do
                lines = lines + math.max(1, math.ceil(math.max(1, #seg) / _CHARS_LINE))
            end
            lines = lines + 1  -- blank separator between entries
        end
    else
        lines = 2
    end
    return math.max(60, lines * _LINE_H + 8)
end

-- ── Public entry point ────────────────────────────────────────────────────────

function ui_update_show_dialog(current_version, new_version)
    _close()
    _n = _n + 1
    local n = _n

    local sw, sh = getMainWindowSize()
    local dw = 500

    -- Console height: fit content, capped at 80% screen height.
    --
    -- Fixed vertical budget within the AC's Inside (which is outer minus the
    -- 2px border on each side, so inner_h = outer_h - 4):
    --   0–44   : header
    --   44–45  : divider
    --   54–80  : "new version" body text
    --   80–102 : version label
    --   112–132: "What's New:" label
    --   136    : MiniConsole starts        (height = console_h)
    --   +10    : gap
    --   +1     : footer divider
    --   +14    : gap
    --   +34    : update note label (2 lines)
    --   +8     : gap
    --   +32    : buttons
    --   +12    : bottom padding
    -- Total inner = 136 + console_h + 111 = 247 + console_h
    -- Total outer = inner + 4             = 251 + console_h

    local needed_con_h = _estimate_console_h()
    local max_con_h    = math.floor(sh * 0.8) - 251
    local console_h    = math.min(needed_con_h, math.max(60, max_con_h))

    local dh    = 251 + console_h
    local div_y = 136 + console_h + 10
    local note_y = div_y + 14
    local btn_y = note_y + 42   -- 34px note + 8px gap

    local cx = math.floor((sw - dw) / 2)
    local cy = math.floor((sh - dh) / 2)

    -- ── Build the Adjustable.Container ────────────────────────────────────────
    UI.update_dialog = Adjustable.Container:new({
        name          = "f2t_upd_ac_" .. n,
        x             = cx, y = cy,
        width         = dw, height = dh,
        adjLabelstyle = _FRAME_CSS,
        autoSave      = false,
        autoLoad      = false,
    })
    UI.update_dialog:lockContainer("border")
    UI.update_dialog.locked = false   -- keep draggable

    local _in = UI.update_dialog.Inside

    -- ── Header ────────────────────────────────────────────────────────────────
    local hdr = Geyser.Label:new({
        name="f2t_upd_hdr_"..n, x=0, y=0, width="100%", height=44,
    }, _in)
    hdr:setStyleSheet(_CSS_HDR)
    hdr:echo("  🔔  Update Available")

    local xbtn = Geyser.Label:new({
        name="f2t_upd_xbtn_"..n, x="92%", y=8, width=30, height=28,
    }, _in)
    xbtn:setStyleSheet(_CSS_XBTN)
    xbtn:echo("<center>×</center>")
    xbtn:setClickCallback(_close)

    -- ── Top divider ───────────────────────────────────────────────────────────
    local div1 = Geyser.Label:new({
        name="f2t_upd_div1_"..n, x=0, y=44, width="100%", height=1,
    }, _in)
    div1:setStyleSheet("background-color: rgba(255,255,255,0.1); border:none;")

    -- ── Static body text ──────────────────────────────────────────────────────
    local body = Geyser.Label:new({
        name="f2t_upd_body_"..n, x=0, y=54, width="100%", height=26,
    }, _in)
    body:setStyleSheet(_CSS_BODY)
    body:echo("A new version of <b>fed2-tools</b> is available.")

    -- ── Version line (dynamic) ────────────────────────────────────────────────
    UI.update_ver_lbl = Geyser.Label:new({
        name="f2t_upd_ver_"..n, x=0, y=80, width="100%", height=22,
    }, _in)
    UI.update_ver_lbl:setStyleSheet(_CSS_SUB)
    UI.update_ver_lbl:echo(string.format(
        "You have <b>v%s</b>.  Latest is <b>v%s</b>.",
        current_version or "???", new_version
    ))

    -- ── "What's New:" label ───────────────────────────────────────────────────
    local wnlbl = Geyser.Label:new({
        name="f2t_upd_wnlbl_"..n, x="3%", y=112, width="94%", height=20,
    }, _in)
    wnlbl:setStyleSheet(_CSS_SUB)
    wnlbl:echo("<b>What's New:</b>")

    -- ── Changelog console ─────────────────────────────────────────────────────
    UI.update_console = Geyser.MiniConsole:new({
        name      = "f2t_upd_con_" .. n,
        x         = "3%", y = 136,
        width     = "94%", height = console_h,
        autoWrap  = true,
        fontSize  = 10,
        scrollBar = true,
        color     = "black",
    }, _in)

    clearWindow(UI.update_console.name)

    if F2T_CHANGELOG and #F2T_CHANGELOG > 0 then
        for _, entry in ipairs(F2T_CHANGELOG) do
            UI.update_console:hecho("#73de94[ v" .. entry.version .. " ]\n")
            UI.update_console:hecho("#c6d2ee" .. entry.body .. "\n\n")
        end
    else
        UI.update_console:hecho("#697db4No specific release notes found.\n")
    end

    -- Scroll to top so the newest release is the first thing visible.
    -- scrollTo(name, 1) positions line 1 at the top of the viewport.
    scrollTo(UI.update_console.name, 1)

    -- ── Footer divider ────────────────────────────────────────────────────────
    local div2 = Geyser.Label:new({
        name="f2t_upd_div2_"..n, x=0, y=div_y, width="100%", height=1,
    }, _in)
    div2:setStyleSheet("background-color: rgba(255,255,255,0.1); border:none;")

    -- ── "Update Note:" label ───────────────────────────────────────────────────
    local unlbl = Geyser.Label:new({
        name="f2t_upd_unlbl_"..n, x="3%", y=note_y, width="94%", height=34,
    }, _in)
    unlbl:setStyleSheet(_CSS_SUB)
    unlbl:echo("<b>Note:</b> When updating, it is recommended to close the session and<br>reopen it. Not all elements redraw as expected.")
    
    -- ── Buttons ───────────────────────────────────────────────────────────────
    local btn_never = Geyser.Label:new({
        name="f2t_upd_btn_nv_"..n, x="2%", y=btn_y, width="28%", height=32,
    }, _in)
    btn_never:setStyleSheet(_CSS_DANGER)
    btn_never:echo("<center>Never</center>")
    btn_never:setClickCallback(function()
        _close()
        f2t_settings_set("shared", "update_check_enabled", false)
        f2t_settings_set("shared", "update_check_remind_skip", 0)
    end)

    local btn_later = Geyser.Label:new({
        name="f2t_upd_btn_rm_"..n, x="36%", y=btn_y, width="28%", height=32,
    }, _in)
    btn_later:setStyleSheet(_CSS_BTN)
    btn_later:echo("<center>Remind Later</center>")
    btn_later:setClickCallback(function()
        _close()
        f2t_settings_set("shared", "update_check_enabled", true)
        f2t_settings_set("shared", "update_check_remind_skip", 5)
    end)

    local btn_update = Geyser.Label:new({
        name="f2t_upd_btn_up_"..n, x="70%", y=btn_y, width="28%", height=32,
    }, _in)
    btn_update:setStyleSheet(_CSS_OK)
    btn_update:echo("<center>Update Now</center>")
    btn_update:setClickCallback(function()
        _close()
        mpkg.upgrade("fed2-tools")
    end)

    -- Hide LAST then show immediately — the galaxy pattern ensures all children
    -- are visible (and Qt-parented correctly) during construction before the
    -- container is hidden and reshown.
    UI.update_dialog:hide()
    UI.update_dialog:show()
    UI.update_dialog:raiseAll()
end
