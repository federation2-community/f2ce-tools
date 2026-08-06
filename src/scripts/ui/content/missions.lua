-- Missions tab: lists the player's active and available missions from the
-- char.missions GMCP feed. Available missions carry an Accept button
-- (choose <id>); clicking any mission name opens an inline detail panel.
-- Data is push-only from GMCP; Accept just sends the command and the panel
-- refreshes when the engine re-emits char.missions.

local H_COL = 20   -- column header bar height (px)
local ROW_H = 22   -- row height (px)
local SB_W  = 17   -- scrollbar pixel allowance

local CELL_FONT = "font-size:"..f2t_ui_pt(10)..";font-family:Consolas,Monaco,monospace;"

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

local _BTN_ACCEPT_CSS = [[
    QLabel {
        background-color: rgba(26,30,46,220);
        color: rgba(210,220,240,255);
        border: 1px solid rgba(72,85,128,180);
        border-left: 3px solid #3ecf5e;
        border-radius: 4px;
        font-size: 10px; font-weight: bold; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(38,44,66,235); border-left: 3px solid #5ce87c; color: white; }
]]

local _BTN_BACK_CSS = [[
    QLabel {
        background-color: rgba(26,30,46,220);
        color: rgba(210,220,240,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 4px;
        font-size: 11px; font-weight: bold; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(38,44,66,235); color: white; }
]]

local function emptyStateHtml(text)
    return string.format("<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT, text)
end

-- Per-pane state, keyed by target._gid.
local instances = {}
-- Latest mission list from GMCP (shared across panes).
local missions = {}

local STATUS_ORDER = { active = 0, available = 1, completed = 2 }
local STATUS_COLOR = { active = "#7aa2ff", available = "#00cc44", completed = "#888888" }

local function capitalize(s)
    if not s or s == "" then return "" end
    return s:sub(1, 1):upper() .. s:sub(2)
end

local function findMission(id)
    for _, m in ipairs(missions) do
        if m.id == id then return m end
    end
    return nil
end

local function progressText(m)
    if m.global and m.community and m.your_part then
        return string.format("Com %s/%s  You %s/%s",
            m.community.cur, m.community.total, m.your_part.cur, m.your_part.cap)
    elseif m.progress then
        return string.format("%s/%s", m.progress.cur, m.progress.total)
    end
    return ""
end

local function buildRows()
    local rows = {}
    for _, m in ipairs(missions) do
        rows[#rows + 1] = {
            id           = m.id,
            name         = m.name or "",
            status       = m.status,
            statusText   = capitalize(m.status),
            statusOrder  = STATUS_ORDER[m.status] or 9,
            statusColor  = STATUS_COLOR[m.status] or "#c8c8c8",
            progressText = progressText(m),
        }
    end
    -- Group active first, then available, then completed; stable by id within.
    table.sort(rows, function(a, b)
        if a.statusOrder ~= b.statusOrder then return a.statusOrder < b.statusOrder end
        return (a.id or 0) < (b.id or 0)
    end)
    return rows
end

-- ── Inline detail panel ────────────────────────────────────────────────────

local function detailHtml(m)
    local p = {}
    p[#p + 1] = string.format(
        "<div style='%scolor:#e6d28c;font-size:12pt;font-weight:bold;padding:4px 6px;'>#%s  %s</div>",
        CELL_FONT, tostring(m.id), m.name or "")
    if m.desc and m.desc ~= "" then
        p[#p + 1] = string.format("<div style='%scolor:#c8c8c8;padding:2px 6px;'>%s</div>", CELL_FONT, m.desc)
    end
    if m.global and m.community and m.your_part then
        p[#p + 1] = string.format(
            "<div style='%scolor:#7aa2ff;padding:4px 6px;'>Community: %s/%s &nbsp;&nbsp; Your part: %s/%s</div>",
            CELL_FONT, m.community.cur, m.community.total, m.your_part.cur, m.your_part.cap)
    elseif m.progress then
        p[#p + 1] = string.format("<div style='%scolor:#7aa2ff;padding:4px 6px;'>Progress: %s/%s</div>",
            CELL_FONT, m.progress.cur, m.progress.total)
    end
    if m.goals and #m.goals > 0 then
        p[#p + 1] = string.format(
            "<div style='%scolor:#a0a0b9;padding:6px 6px 0;font-weight:bold;'>Goals</div>", CELL_FONT)
        for _, g in ipairs(m.goals) do
            p[#p + 1] = string.format("<div style='%scolor:#c8c8c8;padding:1px 12px;'>&bull; %s &mdash; %s/%s</div>",
                CELL_FONT, g.desc or "", g.cur, g.total)
        end
    end
    local r = m.rewards or {}
    local bits = {}
    if (r.points or 0) > 0 then bits[#bits + 1] = tostring(r.points) .. " Mission Points" end
    if (r.money or 0) > 0 then bits[#bits + 1] = tostring(r.money) .. "ig" end
    if (r.slithy or 0) > 0 then bits[#bits + 1] = tostring(r.slithy) .. " Slithy" end
    p[#p + 1] = string.format("<div style='%scolor:#3ecf5e;padding:6px;'>Reward: %s</div>",
        CELL_FONT, #bits > 0 and table.concat(bits, ", ") or "&mdash;")
    if (m.cycles_left or -1) > 0 then
        p[#p + 1] = string.format("<div style='%scolor:#888888;padding:0 6px 6px;'>Cycles left: %s</div>",
            CELL_FONT, m.cycles_left)
    end
    return table.concat(p)
end

local function hideDetail(inst)
    if inst.detail then inst.detail.box:hide() end
    inst.detailId = nil
    if inst.listBox then inst.listBox:show() end
end

local function showDetail(gid, id)
    local inst = instances[gid]
    if not inst then return end
    local m = findMission(id)
    if not m then return end
    inst.detailId = id

    if not inst.detail then
        local box = Geyser.Container:new({
            name = gid .. "_mdetail", x = 0, y = 0, width = "100%", height = "100%",
        }, inst.content)

        local back = Geyser.Label:new({
            name = gid .. "_mback", x = 6, y = 6, width = 70, height = 22,
        }, box)
        back:setStyleSheet(_BTN_BACK_CSS)
        back:echo("<center>&lsaquo; Back</center>")
        back:setClickCallback(function() hideDetail(instances[gid]) end)

        local accept = Geyser.Label:new({
            name = gid .. "_maccept", x = 84, y = 6, width = 80, height = 22,
        }, box)
        accept:setStyleSheet(_BTN_ACCEPT_CSS)
        accept:echo("<center>Accept</center>")

        local scroll = Geyser.ScrollBox:new({
            name = gid .. "_mdscroll", x = 0, y = 34, width = "100%", height = "100%-34px",
        }, box)
        local body = Geyser.Label:new({
            name = gid .. "_mdbody", x = 0, y = 0, width = "100%-" .. SB_W .. "px", height = 1200,
        }, scroll)
        -- AlignTop: without it the QLabel vertically-centers its HTML inside the
        -- tall (scrollable) body, forcing the reader to scroll down to find the
        -- content. Top-align so the detail starts at the top of the panel.
        body:setStyleSheet("background-color: rgba(18,18,26,255); border: none; qproperty-alignment: AlignTop;")

        inst.detail = { box = box, accept = accept, body = body }
    end

    inst.detail.body:echo(detailHtml(m))
    if m.status == "available" then
        inst.detail.accept:show()
        inst.detail.accept:setClickCallback(function() send("choose " .. id, false) end)
    else
        inst.detail.accept:hide()
    end

    if inst.listBox then inst.listBox:hide() end
    inst.detail.box:show()
    inst.detail.box:raise()
end

-- ── List columns ───────────────────────────────────────────────────────────

local function buildCols(gid)
    return {
        {
            key = "name", label = "Mission", sortable = true,
            sort_value = function(r) return (r.name or ""):lower() end,
            scrollbox_pct = 42,
            render_label = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#7aa2ff;text-decoration:underline;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Click for mission details")
                local id = row.id
                cell:setClickCallback(function() showDetail(gid, id) end)
            end,
        },
        {
            key = "statusText", label = "Status", sortable = true,
            sort_value = function(r) return r.statusOrder end,
            scrollbox_pct = 20,
            render_label = function(v, row, cell)
                cell:echo(string.format("<span style='%scolor:%s;'>%s</span>", CELL_FONT, row.statusColor, v or ""))
            end,
        },
        {
            key = "progressText", label = "Progress", sortable = false,
            scrollbox_pct = 24,
            render_label = function(v, _row, cell)
                cell:echo(string.format("<span style='%scolor:#c8c8c8;'>%s</span>", CELL_FONT, v or ""))
            end,
        },
        {
            key = "action", label = "", sortable = false,
            scrollbox_pct = 14,
            render_label = function(_v, row, cell)
                if row.status == "available" then
                    cell:setStyleSheet(_BTN_ACCEPT_CSS)
                    cell:echo("<center>Accept</center>")
                    local id = row.id
                    cell:setToolTip("Accept mission " .. tostring(id))
                    cell:setClickCallback(function() send("choose " .. id, false) end)
                else
                    cell:echo("")
                end
            end,
        },
    }
end

-- ── Refresh ────────────────────────────────────────────────────────────────

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    local rows = buildRows()
    f2tTableSetData(inst.tableId, rows)
    if inst.emptyLbl then
        if #rows == 0 then inst.emptyLbl:show() else inst.emptyLbl:hide() end
    end
    -- Keep an open detail panel live as progress updates arrive.
    if inst.detailId then
        local m = findMission(inst.detailId)
        if m then showDetail(gid, inst.detailId) else hideDetail(inst) end
    end
end

local _renderTimer = nil
local function refreshAllDebounced()
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.1, function()
        _renderTimer = nil
        for gid in pairs(instances) do pcall(refreshInstance, gid) end
    end)
end

local function onGmcpMissions()
    local data = gmcp and gmcp.char and gmcp.char.missions
    if type(data) ~= "table" then return end
    missions = data
    refreshAllDebounced()
end

registerAnonymousEventHandler("gmcp.char.missions", onGmcpMissions)

-- ── Content build ──────────────────────────────────────────────────────────

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        refreshInstance(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_mi_%d", gid, wc)
    end

    -- Everything below the (host-provided) tab lives inside listBox; the detail
    -- panel is a sibling container that overlays it.
    local listBox = Geyser.Container:new({
        name = wid(), x = 0, y = 0, width = "100%", height = "100%",
    }, target.content)

    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_COL,
    }, listBox)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scroll = Geyser.ScrollBox:new({
        name = wid(), x = 0, y = H_COL, width = "100%", height = "100%-" .. H_COL .. "px",
    }, listBox)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1200,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local emptyLbl = Geyser.Label:new({
        name = wid(), x = 0, y = H_COL, width = "100%", height = "100%-" .. H_COL .. "px",
    }, listBox)
    emptyLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    emptyLbl:echo(emptyStateHtml("No missions yet — check back after you rank up, or type 'display missions'."))
    emptyLbl:hide()

    local tableId = "missions_" .. gid
    local cols    = buildCols(gid)
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, ROW_H, scroll)

    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name = wid(), x = xPct .. "%", y = 0, width = col.scrollbox_pct .. "%", height = "100%",
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

    instances[gid] = {
        content      = target.content,
        listBox      = listBox,
        tableId      = tableId,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
        emptyLbl     = emptyLbl,
    }

    refreshInstance(gid)
end

local function buildMissionsDef()
    return {
        name        = "Missions",
        description = "Your active and available missions, with accept and detail views.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok and f2t_debug_log then
                f2t_debug_log("[missions] apply error: %s", tostring(err))
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

function f2tRegisterMissions()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[missions] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_missions", buildMissionsDef())
    if f2t_debug_log then f2t_debug_log("[missions] registered fed2_missions content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterMissions)

if f2t_debug_log then f2t_debug_log("[missions] module loaded") end
