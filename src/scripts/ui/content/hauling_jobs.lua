-- hauling_jobs.lua — Armstrong Cuthbert job board content for fed2-tools.
--
-- Sortable table of AC courier jobs captured from `work` output, with computed
-- route distance and effective pay (20% bonus when the route beats the allowed
-- GTU, 50% penalty when it exceeds it).  Job numbers accept the job; origin
-- and destination navigate.  A button strip triggers work/collect/deliver.
--
-- Data flow: the ui triggers (triggers/ui/hauling_work_*.lua) call
-- f2tHaulingJobsHeader()/f2tHaulingJobsLine() and gag the raw listing — but
-- only while at least one panel is open AND the hauling automation is not
-- running (the automation's own capture owns the output then).
--
-- Ported from archive's ui_hauling.lua + haulingStart/haulingJob triggers.

local H_BAR  = 26    -- button strip height (px)
local H_COL  = 20    -- column header bar height (px)
local ROW_H  = 20    -- row height (px)
local SB_W   = 17    -- scrollbar pixel allowance

local CELL_FONT = "font-size:10pt;font-family:Consolas,Monaco,monospace;"

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

-- Accent-colored action buttons: a left accent bar plus a tinted hover state,
-- distinct per action so Work/Collect/Deliver read apart at a glance.
local function actionBtnCss(accent, accentHover)
    return string.format([[
        QLabel {
            background-color: rgba(26,30,46,220);
            color: rgba(210,220,240,255);
            border: 1px solid rgba(72,85,128,180);
            border-left: 3px solid %s;
            border-radius: 4px;
            font-size: 10px; font-weight: bold; font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(38,44,66,235);
            border-left: 3px solid %s;
            color: white;
        }
    ]], accent, accentHover)
end

local _BTN_WORK_CSS    = actionBtnCss("#3aa0ff", "#5cb8ff")
local _BTN_COLLECT_CSS = actionBtnCss("#3ecf5e", "#5ce87c")
local _BTN_DELIVER_CSS = actionBtnCss("#e0b84d", "#f0cc66")

-- Per-pane state, keyed by target._gid
local instances = {}

-- Job rows captured from the current `work` listing (shared by all instances).
local jobs = {}

local function stripThe(name)
    if not name then return "" end
    return (name:gsub("^The ", ""))
end

local function navigateTo(location)
    if not f2t_map_navigate then return end
    -- Sol locations have dedicated AC offices; prefer the "<planet> ac" target.
    local resolved = f2t_map_resolve_location and f2t_map_resolve_location(location)
    if resolved and getRoomUserData(resolved, "fed2_system") == "Sol" then
        if not f2t_map_navigate(location .. " ac") then
            f2t_map_navigate(location)
        end
    else
        f2t_map_navigate(location)
    end
end

local function buildCols()
    return {
        {
            key           = "jobNumber",
            label         = "Job",
            sortable      = true,
            sort_value    = function(row) return tonumber(row.jobNumber) or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#7aa2ff;text-decoration:underline;'>%s</span>",
                    CELL_FONT, v or ""))
                cell:setToolTip("Accept job " .. tostring(v))
                cell:setClickCallback(function() send("ac " .. v, false) end)
            end,
        },
        {
            key           = "originDisplay",
            label         = "Origin",
            sortable      = true,
            sort_value    = function(row) return row.origin:lower() end,
            scrollbox_pct = 22,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Go to " .. row.origin)
                cell:setClickCallback(function() navigateTo(row.origin) end)
            end,
        },
        {
            key           = "destDisplay",
            label         = "Dest",
            sortable      = true,
            sort_value    = function(row) return row.dest:lower() end,
            scrollbox_pct = 22,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Go to " .. row.dest)
                cell:setClickCallback(function() navigateTo(row.dest) end)
            end,
        },
        {
            key           = "moves",
            label         = "GTU",
            sortable      = false,
            scrollbox_pct = 16,
            header_tooltip = "Allowed/actual route GTU. A bare number with no slash means the route isn't in your map yet, so it can't be checked.",
            render_label  = function(_v, row, cell)
                local html
                if row.distance then
                    local distColor
                    if row.distance < row.allowedMoves then
                        distColor = "#00cc44"
                    elseif row.distance > row.allowedMoves then
                        distColor = "#ff5555"
                    else
                        distColor = "#ffffff"
                    end
                    html = string.format(
                        "<span style='%scolor:#c8c8c8;'><b>%d</b>/</span>" ..
                        "<span style='%scolor:%s;'><b>%d</b></span>",
                        CELL_FONT, row.allowedMoves, CELL_FONT, distColor, row.distance)
                    cell:setToolTip("Allowed GTU / actual route distance")
                else
                    html = string.format(
                        "<span style='%scolor:#c8c8c8;'><b>%d</b></span>",
                        CELL_FONT, row.allowedMoves)
                    cell:setToolTip("Allowed GTU (route unknown — no slash shown because origin or destination isn't in your map yet)")
                end
                cell:echo(html)
            end,
        },
        {
            key           = "pay",
            label         = "Pay",
            sortable      = true,
            default_sort  = "desc",
            sort_value    = function(row) return row.effectivePay end,
            scrollbox_pct = 30,
            render_label  = function(_v, row, cell)
                local payColor
                if row.payType == "bonus" then
                    payColor = "#00cc44"
                elseif row.payType == "penalty" then
                    payColor = "#ff5555"
                else
                    payColor = "#ffffff"
                end
                cell:echo(string.format(
                    "<span style='%scolor:#c8c8c8;'><b>%d</b>ig (</span>" ..
                    "<span style='%scolor:%s;'><b>%d</b></span>" ..
                    "<span style='%scolor:#c8c8c8;'>)</span>",
                    CELL_FONT, row.basePay, CELL_FONT, payColor, row.effectivePay, CELL_FONT))
                cell:setToolTip("Base pay (effective pay after route bonus/penalty)")
            end,
        },
    }
end

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    f2tTableSetData(inst.tableId, jobs)
end

local _renderTimer = nil
local function refreshAllDebounced()
    -- Job lines arrive in a burst; draw once after the listing settles.
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.15, function()
        _renderTimer = nil
        for gid in pairs(instances) do pcall(refreshInstance, gid) end
    end)
end

-- ── Trigger entry points ──────────────────────────────────────────────────────

-- True when at least one panel is placed; the ui work triggers use this to
-- decide whether to capture/gag the listing at all.
function f2tHaulingJobsHasOpenPanels()
    return next(instances) ~= nil
end

function f2tHaulingJobsHeader()
    jobs = {}
    refreshAllDebounced()
end

function f2tHaulingJobsLine(jobNumber, origin, dest, allowedMoves, payPerTon)
    local basePay      = (tonumber(payPerTon) or 0) * 75
    local allowedNum   = tonumber(allowedMoves) or 0

    -- The cartel-bounded BFS is fast but depends on areas being tagged with
    -- fed2_cartel (from the galaxy/cartel scraper); on a map that hasn't been
    -- scraped yet it fails for every job, silently collapsing the GTU/Pay
    -- color signal to plain white for every row. Fall back to the slower
    -- whole-galaxy pathfinder so distance (and therefore the colors) still
    -- resolve even when cartel tagging is missing or the route genuinely
    -- crosses a cartel boundary.
    local distance
    if f2t_map_get_cartel_route_info then
        local info = f2t_map_get_cartel_route_info(origin, dest)
        if info and info.success then distance = info.space_moves end
    end
    if not distance and f2t_map_get_route_info then
        local info = f2t_map_get_route_info(origin, dest)
        if info and info.success then distance = info.space_moves end
    end

    local effectivePay, payType
    if not distance then
        effectivePay, payType = basePay, "unknown"
    elseif distance < allowedNum then
        effectivePay, payType = math.floor(basePay * 1.20), "bonus"
    elseif distance > allowedNum then
        effectivePay, payType = math.floor(basePay * 0.50), "penalty"
    else
        effectivePay, payType = basePay, "normal"
    end

    jobs[#jobs + 1] = {
        jobNumber     = jobNumber,
        origin        = origin,
        dest          = dest,
        originDisplay = stripThe(origin),
        destDisplay   = stripThe(dest),
        allowedMoves  = allowedNum,
        basePay       = basePay,
        distance      = distance,
        effectivePay  = effectivePay,
        payType       = payType,
        pay           = basePay,
        moves         = allowedNum,
    }
    refreshAllDebounced()
end

-- ── Content build ─────────────────────────────────────────────────────────────

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
        return string.format("%s_hj_%d", gid, wc)
    end

    -- ── Button strip ──────────────────────────────────────────────────────────
    local bar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_BAR,
    }, target.content)
    bar:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local buttons = {
        { label = "Work",    cmd = "work",    tip = "List available AC jobs",              css = _BTN_WORK_CSS },
        { label = "Collect", cmd = "collect", tip = "Collect cargo for the accepted job",   css = _BTN_COLLECT_CSS },
        { label = "Deliver", cmd = "deliver", tip = "Deliver cargo at the destination",     css = _BTN_DELIVER_CSS },
    }
    local btnW = 76
    for i, b in ipairs(buttons) do
        local btn = Geyser.Label:new({
            name = wid(), x = 6 + (i - 1) * (btnW + 8), y = 4, width = btnW, height = H_BAR - 8,
        }, bar)
        btn:setStyleSheet(b.css)
        btn:echo("<center>" .. b.label .. "</center>")
        btn:setToolTip(b.tip)
        local cmd = b.cmd
        btn:setClickCallback(function() send(cmd, false) end)
    end

    -- ── Column header bar ─────────────────────────────────────────────────────
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_BAR, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    -- ── ScrollBox ─────────────────────────────────────────────────────────────
    local scrollTop = H_BAR + H_COL
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
    local tableId = "hauling_jobs_" .. gid
    local cols    = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, ROW_H, scroll)

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
            lbl:setToolTip(col.header_tooltip or ("Sort by " .. col.label))
        elseif col.header_tooltip then
            lbl:setToolTip(col.header_tooltip)
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    instances[gid] = {
        tableId      = tableId,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
    }

    refreshInstance(gid)
end

local function buildHaulingJobsDef()
    return {
        name        = "Hauling Jobs",
        description = "Armstrong Cuthbert job board with route distance and effective pay.",
        group       = "Fed2 Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[hauling_jobs] apply error: %s", tostring(err))
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

function f2tRegisterHaulingJobs()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[hauling_jobs] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_hauling_jobs", buildHaulingJobsDef())
    if f2t_debug_log then f2t_debug_log("[hauling_jobs] registered fed2_hauling_jobs content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterHaulingJobs)

if f2t_debug_log then f2t_debug_log("[hauling_jobs] module loaded") end
