-- who.lua — Online player list content for fed2-tools.
--
-- Reads from F2T_PLAYER_DB (player_db.lua) kept current by the always-on GMCP
-- handler.  Refreshes all open panes on f2tPlayerDbUpdated.
--
-- Layout per pane:
--   H_HDR px  — header strip: online count + Online/All toggle button
--   H_COL px  — sortable column header bar (Rank | Name | Location)
--   remainder — ScrollBox driven by the table system (f2t_table_system.lua)
--
-- Ported from archive's ui_players.lua (ui_who_init + ui_who_set_table_data).

local H_HDR     = 24    -- header strip height (px)
local H_COL     = 20    -- column header bar height (px)
local WHO_ROW_H = 22    -- row height (px)
local SB_W      = 17    -- scrollbar pixel allowance

-- Rank → HTML hex color (inline-style in Labels; mirrors archive's RANK_COLOR + _html_cc)
local RANK_COLOR = {
    ["Trader"]        = "#f5fffa",
    ["Merchant"]      = "#f5fffa",
    ["Engineer"]      = "#00cccc",
    ["Mogul"]         = "#00cccc",
    ["Magnate"]       = "#00cccc",
    ["Technocrat"]    = "#00cccc",
    ["Gengineer"]     = "#00cccc",
    ["Founder"]       = "#00cccc",
    ["Manufacturer"]  = "#00cc44",
    ["Industrialist"] = "#00cc44",
    ["Financier"]     = "#00cc44",
    ["Plutocrat"]     = "#ff5555",
    ["Syndicrat"]     = "#808000",
    ["Commander"]     = "#9932cc",
    ["Groundhog"]     = "#9932cc",
}
local RC_DEFAULT = "#c8c8c8"
local RC_OFFLINE = "#888888"
local RC_STAFF   = "#6b8e23"   -- Plutocrat with a staff role

local CELL_FONT = "font-size:12pt;font-family:Consolas,Monaco,monospace;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

-- Per-pane state, keyed by target._gid
local instances = {}

local function rankColor(row)
    if row.is_online == false then return RC_OFFLINE end
    if row.rank == "Plutocrat" and (row.staff or "") ~= "" then return RC_STAFF end
    return RANK_COLOR[row.rank] or RC_DEFAULT
end

local function buildTableData(showAll)
    local rows = {}
    for _, e in pairs(F2T_PLAYER_DB or {}) do
        if e.is_online then rows[#rows + 1] = e end
    end
    if showAll then
        for _, e in ipairs(f2t_player_db_get_offline()) do
            rows[#rows + 1] = e
        end
    end
    return rows
end

local function onlineCount()
    local n = 0
    for _, e in pairs(F2T_PLAYER_DB or {}) do
        if e.is_online then n = n + 1 end
    end
    return n
end

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    if inst.hdrCount then
        inst.hdrCount:echo(string.format("  👥  Online: %d", onlineCount()))
    end
    f2tTableSetData(inst.tableId, buildTableData(inst.showAll))
end

local function refreshAll()
    for gid in pairs(instances) do
        pcall(refreshInstance, gid)
    end
    if f2tPlayerCardsRefreshAll then f2tPlayerCardsRefreshAll() end
end

-- Column definitions — produced per-pane so closures reference the correct tableId.
local function buildCols(tableId)
    return {
        {
            key           = "rank",
            label         = "Rank",
            sortable      = true,
            sort_value    = function(row) return row.rank_order or 0 end,
            scrollbox_pct = 30,
            render_label  = function(v, row, cell)
                local rc = rankColor(row)
                cell:echo(string.format(
                    "<span style='%scolor:%s;'>%s</span>",
                    CELL_FONT, rc, v or ""))
                if row.is_online == false and row.last_seen then
                    cell:setToolTip("Last seen " .. f2t_player_db_last_seen_str(row.last_seen))
                end
                cell:setClickCallback(function()
                    if f2tPlayerCardShowOrRaise then f2tPlayerCardShowOrRaise(row) end
                end)
            end,
        },
        {
            key           = "name",
            label         = "Name",
            sortable      = true,
            default_sort  = "asc",
            scrollbox_pct = 38,
            render_label  = function(v, row, cell)
                local rc      = rankColor(row)
                local staffSfx = (row.staff and row.staff ~= "")
                    and string.format("<span style='%scolor:#ffff55;'> [%s]</span>",
                        CELL_FONT, row.staff:sub(1, 3))
                    or ""
                cell:echo(string.format(
                    "<span style='%scolor:%s;'><b>%s</b></span>%s",
                    CELL_FONT, rc, v or "", staffSfx))
                cell:setToolTip("Click to view player card")
                cell:setClickCallback(function()
                    if f2tPlayerCardShowOrRaise then f2tPlayerCardShowOrRaise(row) end
                end)
            end,
        },
        {
            key           = "location",
            label         = "Location",
            sortable      = true,
            scrollbox_pct = 32,
            render_label  = function(v, row, cell)
                if not v or v == "" then return end
                local lcc    = (row.is_online == false) and RC_OFFLINE or "#00cccc"
                cell:echo(string.format(
                    "<span style='%scolor:%s;'>%s</span>",
                    CELL_FONT, lcc, v))
                local locSys = v:match("^(.+) Space$")
                cell:setClickCallback(function()
                    if locSys then expandAlias("nav " .. locSys .. " link")
                    else            expandAlias("nav " .. v) end
                end)
                local dest = locSys or v
                if row.is_online == false and row.last_seen then
                    cell:setToolTip(f2t_player_db_last_seen_str(row.last_seen) ..
                        " — navigate to " .. dest)
                else
                    cell:setToolTip("Navigate to " .. dest)
                end
            end,
        },
    }
end

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    -- Re-show if already built (e.g. apply called without prior remove)
    if instances[gid] then
        refreshInstance(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_who_%d", gid, wc)
    end

    -- ── Header strip (count + toggle) ────────────────────────────────────────
    local hdrStrip = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_HDR,
    }, target.content)
    hdrStrip:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local hdrCount = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "-80", height = H_HDR,
    }, hdrStrip)
    hdrCount:setStyleSheet([[
        background: transparent; border: none;
        color: rgba(140, 150, 195, 255);
        font-size: 10px; font-family: "Consolas","Monaco",monospace;
        padding: 0 6px;
    ]])
    hdrCount:echo("  👥  Online: —")

    local toggleBtn = Geyser.Label:new({
        name = wid(), x = "-76", y = 2, width = 72, height = H_HDR - 4,
    }, hdrStrip)
    toggleBtn:setStyleSheet([[
        QLabel {
            background-color: rgba(28,32,50,210);
            color: rgba(150,165,205,255);
            border: 1px solid rgba(72,85,128,180);
            border-radius: 3px;
            font-size: 9px; font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(42,48,78,230);
            color: rgba(200,215,255,255);
        }
    ]])
    toggleBtn:echo("<center>Online</center>")
    toggleBtn:setToolTip("Showing online only — click to show all known players")

    -- ── Column header bar ─────────────────────────────────────────────────────
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_HDR, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    -- ── ScrollBox ─────────────────────────────────────────────────────────────
    local scrollTop = H_HDR + H_COL
    local scroll = Geyser.ScrollBox:new({
        name   = wid(),
        x = 0, y = scrollTop,
        width  = "100%",
        height = "100%-" .. scrollTop .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    -- ── Table system ──────────────────────────────────────────────────────────
    local tableId = "who_" .. gid
    local cols    = buildCols(tableId)
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, WHO_ROW_H, scroll)

    -- Column header labels (sortable, click to toggle sort)
    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name  = wid(),
            x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%",
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local tid, key = tableId, col.key
            lbl:setClickCallback(function() f2tTableToggleSort(tid, key) end)
            lbl:setToolTip("Sort by " .. col.label)
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    -- ── Per-instance state ────────────────────────────────────────────────────
    instances[gid] = {
        tableId      = tableId,
        colHdrs      = colHdrs,
        showAll      = false,
        toggleBtn    = toggleBtn,
        hdrCount     = hdrCount,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
    }

    -- Toggle click: switch Online ↔ All, update button label and table data
    toggleBtn:setClickCallback(function()
        local inst = instances[gid]
        if not inst then return end
        inst.showAll = not inst.showAll
        if inst.showAll then
            toggleBtn:echo("<center>All</center>")
            toggleBtn:setToolTip("Showing all known players — click for Online only")
        else
            toggleBtn:echo("<center>Online</center>")
            toggleBtn:setToolTip("Showing online only — click for All known players")
        end
        f2tTableSetData(inst.tableId, buildTableData(inst.showAll))
    end)

    refreshInstance(gid)
end

local function buildWhoDef()
    return {
        name        = "Who",
        description = "Online player list from gmcp.players.",
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[who] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableDestroy(inst.tableId)
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            if newCw ~= inst.contentW then
                inst.contentW = newCw
                inst.contentLabel:resize(newCw, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) refreshInstance(target._gid) end,
    }
end

function f2tRegisterWho()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[who] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_who", buildWhoDef())
    if f2t_debug_log then f2t_debug_log("[who] registered fed2_who content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterWho)

-- Coalesce repaints: gmcp.players deltas can arrive several times a second with
-- many players online. One repaint per 0.2s window keeps the list effectively
-- realtime at a fraction of the render cost.
local _refreshTimer = nil
registerAnonymousEventHandler("f2tPlayerDbUpdated", function()
    if _refreshTimer then return end
    _refreshTimer = tempTimer(0.2, function()
        _refreshTimer = nil
        refreshAll()
    end)
end)

if f2t_debug_log then f2t_debug_log("[who] module loaded") end
