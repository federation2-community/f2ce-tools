-- =============================================================================
-- ui_general  —  General tab in-memory history and filter
-- =============================================================================

UI           = UI or {}
UI.general_tab = UI.general_tab or {
    history    = {},
    filter_idx = 1,
}

local _MAX_ENTRIES = 500

-- ── Filter states ─────────────────────────────────────────────────────────

local _GENERAL_FILTER = {
    {
        id = "all", label = "A", matches = nil,
        css = [[QLabel{
            background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(100,100,110,180);
            color:rgba(160,160,170,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }]],
    },
    {
        id = "movement", label = "M", matches = { movement = true },
        css = [[QLabel{
            background-color:rgba(15,45,15,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(45,110,45,200);
            color:rgba(80,180,80,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(25,65,25,240); color:white; }]],
    },
    {
        id = "spynet", label = "S", matches = { spynet = true },
        css = [[QLabel{
            background-color:rgba(255,255,255,80); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(0,0,0,160);
            color:black !important; font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(255,255,255,120); color:black !important; }]],
    },
    {
        id = "promotion", label = "P", matches = { promotion = true },
        css = [[QLabel{
            background-color:rgba(45,40,10,220); border-style:solid; border-width:1px;
            border-radius:3px; border-color:rgba(160,140,30,200);
            color:rgba(220,200,60,255); font-size:10px; font-weight:bold;
        } QLabel::hover{ background-color:rgba(65,60,15,240); color:white; }]],
    },
}

-- ── Public write API ──────────────────────────────────────────────────────

-- render_fn receives the window as its sole argument
function ui_general_add(entry_type, render_fn)
    table.insert(UI.general_tab.history, { type = entry_type, render = render_fn })
    while #UI.general_tab.history > _MAX_ENTRIES do
        table.remove(UI.general_tab.history, 1)
    end
    local fstate = _GENERAL_FILTER[UI.general_tab.filter_idx]
    if (not fstate.matches or fstate.matches[entry_type]) and UI.general_window then
        render_fn(UI.general_window)
    end
end

-- ── Replay ────────────────────────────────────────────────────────────────

function ui_general_replay()
    if not UI.general_window then return end
    UI.general_window:clear()
    local fstate = _GENERAL_FILTER[UI.general_tab.filter_idx]
    for _, entry in ipairs(UI.general_tab.history) do
        if not fstate.matches or fstate.matches[entry.type] then
            entry.render(UI.general_window)
        end
    end
end

-- ── Filter cycle ──────────────────────────────────────────────────────────

function ui_general_cycle_filter()
    UI.general_tab.filter_idx = (UI.general_tab.filter_idx % #_GENERAL_FILTER) + 1
    local state = _GENERAL_FILTER[UI.general_tab.filter_idx]
    if UI.general_filter_btn then
        UI.general_filter_btn:setStyleSheet(state.css)
        UI.general_filter_btn:echo("<center>" .. state.label .. "</center>")
        local tips = {
            all       = "Show all",
            movement  = "Movement only",
            spynet    = "Spynet only",
            promotion = "Promotions only",
        }
        UI.general_filter_btn:setToolTip(tips[state.id] or "Filter")
    end
    ui_general_replay()
end
