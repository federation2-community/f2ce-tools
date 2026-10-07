-- Commerce > Jobs: the cartel's Armstrong Cuthbert workboard as a sortable
-- table, with computed route distance and effective pay (20% bonus when the
-- route beats the allowed GTU, 50% penalty when it exceeds it). Origin and
-- destination navigate. Every rank with a ship sees the board; what it can
-- do with it depends on rank:
--   Commander, Captain        job numbers accept; Collect/Deliver buttons
--   Industrialist, Manufacturer  Post Job (to a depot on this planet)
--   Founder+                  Post Job (from this planet), Offer Job
--
-- Data flow: fully live via GMCP, no trigger scraping. gmcp.jobs.board is
-- the job listing, gmcp.char.job is the player's current contract (absent
-- when there isn't one; moves.cur/moves.max update live as the player
-- travels). Both feed this module directly through anonymous event
-- handlers registered once at load time.

local H_ACT  = 26    -- rank action row height (px)
local H_CUR  = 22    -- active-job strip height (px), only shown while a job is accepted
local H_COL  = 20    -- column header bar height (px)
local ROW_H  = 20    -- row height (px)
local SB_W   = 17    -- scrollbar pixel allowance
local CELL_PT  = 10  -- cell, status and active-job font size (pt)
local LABEL_PT = 8   -- column header and button font size (pt)

-- Size comes from the label's fontSize (cells: f2tTableSetScrollbox's cellPt).
local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

local _ACT_BAR_CSS = [[
    background-color: rgba(16, 18, 28, 230);
    border: none;
    border-bottom: 1px solid rgba(60, 65, 100, 150);
]]

local function emptyStateHtml(text)
    return string.format(
        "<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT, text)
end

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

-- Without a QToolTip rule, a widget's own dark background bleeds into its
-- native tooltip box (unreadable black-on-black) instead of Qt/OS defaults.
local _TOOLTIP_CSS = "QToolTip{background-color:#1d2030;color:#e8ebf5;" ..
    "border:1px solid rgba(255,255,255,0.18);padding:3px;}"

-- Accent-colored action buttons: a left accent bar plus a tinted hover state,
-- distinct per action so they read apart at a glance.
local function actionBtnCss(accent, accentHover)
    return string.format([[
        QLabel {
            background-color: rgba(26,30,46,220);
            color: rgba(210,220,240,255);
            border: 1px solid rgba(72,85,128,180);
            border-left: 3px solid %s;
            border-radius: 4px;
            font-weight: bold; font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(38,44,66,235);
            border-left: 3px solid %s;
            color: white;
        }
    ]], accent, accentHover) .. _TOOLTIP_CSS
end

local _BTN_COLLECT_CSS = actionBtnCss("#3ecf5e", "#5ce87c")
local _BTN_DELIVER_CSS = actionBtnCss("#e0b84d", "#f0cc66")
local _BTN_POST_CSS    = actionBtnCss("#3aa0ff", "#5cb8ff")
local _BTN_OFFER_CSS   = actionBtnCss("#e07a4d", "#f09a66")

-- Strip showing the job currently under contract, pinned above the list.
local _CUR_BAR_CSS = [[
    background-color: rgba(24, 40, 30, 220);
    border: none;
    border-bottom: 1px solid rgba(70, 130, 90, 180);
    border-left: 3px solid #3ecf5e;
]]

-- Column layout shared between the table header/rows and the active-job
-- strip, so the pinned strip visually lines up with the columns below it.
local CUR_COLS = {
    { key = "status", pct = 10 },
    { key = "origin", pct = 22 },
    { key = "dest",   pct = 22 },
    { key = "moves",  pct = 16 },
    { key = "pay",    pct = 30 },
}

-- Per-pane state, keyed by target._gid
local instances = {}

-- Job rows from gmcp.jobs.board (shared by all instances).
local jobs = {}

-- The player's current contract from gmcp.char.job, or nil when there isn't
-- one (shared by all instances).
local currentJob = nil

local function stripThe(name)
    if not name then return "" end
    return (name:gsub("^The ", ""))
end

local function navigateTo(location)
    if not f2t_map_navigate then return end
    -- Sol locations have dedicated AC offices; prefer the "<planet> ac" target.
    local resolved = f2t_map_resolve_location and f2t_map_resolve_location(location)
    if resolved and getRoomUserData(resolved, "fed2_system") == "Sol" then
        if not f2t_map_navigate_ok(f2t_map_navigate(location .. " ac")) then
            f2t_map_navigate(location)
        end
    else
        f2t_map_navigate(location)
    end
end

local function acceptJob(jobNumber)
    send("ac " .. jobNumber, false)
end

-- ── Rank capabilities ────────────────────────────────────────────────────────

local function rankLevel()
    return f2t_get_rank_level(f2t_get_rank()) or 0
end

-- Only Commanders and Captains take jobs off the board.
local function canTakeJobs()
    local level = rankLevel()
    return level >= 2 and level <= 3
end

-- "depot": POST JOB <commodity> <origin>, delivered to the company depot here.
-- "planet": POST JOB <commodity> <destination>, shipped from this owned planet.
local function postKind()
    local level = rankLevel()
    if level == 7 or level == 8 then return "depot" end
    if level >= 10 then return "planet" end
    return nil
end

-- ── Post / Offer Job dialog ──────────────────────────────────────────────────

-- Mapped planets in the current cartel, other than the one the player is on.
local function cartelPlanets()
    local cartel = f2t_map_get_current_cartel and f2t_map_get_current_cartel()
    if not cartel then return {} end
    local here = f2t_get_current_planet and f2t_get_current_planet()
    local list = {}
    for name, areaId in pairs(getAreaTable()) do
        if name ~= here and getAreaUserData(areaId, "fed2_cartel") == cartel
            and not f2t_map_get_system_from_space_area(name) then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

local _LIST_ITEM_CSS = [[
    QLabel {
        background-color: rgba(24,26,38,220);
        border: none; border-bottom: 1px solid rgba(255,255,255,0.05);
        font-family: "Consolas","Monaco",monospace;
        padding: 0 6px;
    }
    QLabel::hover { background-color: rgba(48,56,88,230); color: white; }
]]

local _LIST_ITEM_SEL_CSS = [[
    QLabel {
        background-color: rgba(40,70,120,240);
        border: none; border-bottom: 1px solid rgba(255,255,255,0.05);
        font-family: "Consolas","Monaco",monospace;
        color: white;
        padding: 0 6px;
    }
]]

-- A scrollable single-select list of names; onPick(name) fires on click.
local function buildPickList(prefix, parent, geom, names, onPick, decorate)
    local frame = Geyser.Label:new({
        name = prefix .. "_frame", x = geom.x, y = geom.y, width = geom.width, height = geom.height,
    }, parent)
    frame:setStyleSheet("background-color: rgba(18,18,26,255); border: 1px solid rgba(72,85,128,180);")

    local scroll = Geyser.ScrollBox:new({
        name = prefix .. "_scroll", x = geom.x + 1, y = geom.y + 1,
        width = geom.width - 2, height = geom.height - 2,
    }, parent)

    local rowH = 22
    local labels = {}
    for i, name in ipairs(names) do
        local lbl = Geyser.Label:new({
            name = prefix .. "_i" .. i, x = 0, y = (i - 1) * rowH, width = geom.width - 2 - SB_W, height = rowH,
        }, scroll)
        lbl:setStyleSheet(_LIST_ITEM_CSS)
        lbl:echo(string.format("<span style='%scolor:#e6d28c;'>%s%s</span>",
            CELL_FONT, decorate and decorate(name) or "", name))
        labels[name] = lbl
        lbl:setClickCallback(function()
            for other, otherLbl in pairs(labels) do
                otherLbl:setStyleSheet(other == name and _LIST_ITEM_SEL_CSS or _LIST_ITEM_CSS)
            end
            onPick(name)
        end)
    end
end

local _pendingPostDialog = nil

local function postDialogBuild(target)
    local pending = _pendingPostDialog
    _pendingPostDialog = nil
    if not pending then return end

    local c, gid = target.content, target._gid
    local dlgW, dlgH = pending.width, pending.height
    local w = dlgW - 4
    local offer = pending.kind == "offer"

    local intro = Geyser.Label:new({
        name = gid .. "_pj_intro", x = 0, y = 6, width = "100%", height = 34,
    }, c)
    intro:setStyleSheet(Mux.dialogCss.subtext .. "qproperty-wordWrap: true;")
    intro:echo(pending.intro)

    local choice = { commodity = nil, planet = nil }
    local listTop = 64
    local listH   = dlgH - 26 - listTop - (offer and 108 or 74)
    local colW    = math.floor((w - 42) / 2)

    local function heading(id, x, text)
        local lbl = Geyser.Label:new({ name = gid .. id, x = x, y = 44, width = colW, height = 18 }, c)
        lbl:setStyleSheet(Mux.dialogCss.subtext .. "padding:0;")
        lbl:echo(text)
    end
    heading("_pj_hc", 14, "Commodity")
    heading("_pj_hp", 28 + colW, pending.planetHeading)

    local preview = Geyser.Label:new({
        name = gid .. "_pj_preview", x = 14, y = listTop + listH + 6, width = w - 28, height = 22,
    }, c)
    preview:setStyleSheet("background: transparent; color: #8896c0; " .. CELL_FONT)

    local nameInput
    local function commandText()
        local commodity = choice.commodity and choice.commodity:lower() or "<commodity>"
        local planet    = choice.planet or "<planet>"
        if offer then
            local who = nameInput and nameInput:getText() or ""
            if who == "" then who = "<player>" end
            return string.format("offer %s job %s %s", who, commodity, planet)
        end
        return string.format("post job %s %s", commodity, planet)
    end
    local function refreshPreview()
        preview:echo("Sends: <span style='color:#e8ebf5;'>" .. commandText() .. "</span>")
    end

    buildPickList(gid .. "_pjc", c, { x = 14, y = listTop, width = colW, height = listH },
        pending.commodities, function(name) choice.commodity = name; refreshPreview() end,
        f2tCommodityIconPrefix)

    if #pending.planets > 0 then
        buildPickList(gid .. "_pjp", c, { x = 28 + colW, y = listTop, width = colW, height = listH },
            pending.planets, function(name) choice.planet = name; refreshPreview() end)
    else
        local none = Geyser.Label:new({
            name = gid .. "_pj_noplanets", x = 28 + colW, y = listTop, width = colW, height = listH,
        }, c)
        none:setStyleSheet(Mux.dialogCss.subtext .. "qproperty-wordWrap: true;")
        none:echo("No mapped planets in this cartel yet. Explore the cartel (map explore cartel) " ..
            "or type the command instead.")
    end

    if offer then
        local lbl = Geyser.Label:new({
            name = gid .. "_pj_who", x = 14, y = listTop + listH + 34, width = 70, height = 26,
        }, c)
        lbl:setStyleSheet(Mux.dialogCss.subtext .. "padding:0;")
        lbl:echo("Player")
        nameInput = Geyser.CommandLine:new({
            name = gid .. "_pj_whoin", x = 84, y = listTop + listH + 34, width = w - 98, height = 26,
        }, c)
        nameInput:setStyleSheet("background-color: rgba(18,20,32,255); color: #e8ebf5; font-size: 12px; " ..
            "border: 1px solid rgba(72,85,128,180); border-radius: 3px; padding-left: 6px;")
        nameInput:setAction(function() refreshPreview() end)
    end

    refreshPreview()

    local btnY = (dlgH - 26) - 42
    local cancel = Geyser.Label:new({ name = gid .. "_pj_cancel", x = 14, y = btnY, width = 120, height = 32 }, c)
    cancel:setStyleSheet(Mux.dialogCss.button)
    cancel:echo("<center>Cancel</center>")
    Mux.wireDialogButton(cancel, Mux.dialogCss.button, Mux.dialogCss.buttonHover)
    cancel:setClickCallback(function() target:close() end)

    local ok = Geyser.Label:new({ name = gid .. "_pj_ok", x = w - 134, y = btnY, width = 120, height = 32 }, c)
    ok:setStyleSheet(Mux.dialogCss.buttonPrimary)
    ok:echo("<center>" .. pending.okLabel .. "</center>")
    Mux.wireDialogButton(ok, Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover)
    ok:setClickCallback(function()
        local who = nameInput and nameInput:getText() or ""
        if not choice.commodity or not choice.planet or (offer and who == "") then
            refreshPreview()
            preview:echo("<span style='color:#ff7777;'>Pick a commodity and a planet" ..
                (offer and ", and enter the player's name" or "") .. ".</span>")
            return
        end
        target:close()
        send(commandText())
    end)
end

-- kind: "depot" | "planet" | "offer"
local function openPostDialog(kind)
    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho("\n<yellow>[jobs]<reset> Dialogs require Muxlet.\n")
        return
    end
    if not Mux._content or not Mux._content["f2t_post_job_dialog"] then
        Mux.registerContent("f2t_post_job_dialog", {
            internal = true,
            name     = "Post Job",
            apply    = function(target)
                target.contentBg:echo("")
                target.contentBg:setStyleSheet("background-color:rgba(0,0,0,0);border:none;")
                target.contentBg:hide()
                postDialogBuild(target)
            end,
        })
    end

    local commodities = {}
    for _, item in ipairs(f2tCommodityList and f2tCommodityList() or {}) do
        commodities[#commodities + 1] = item.name
    end

    local here = f2t_get_current_planet and f2t_get_current_planet() or "this planet"
    local specs = {
        depot = {
            title = "Post Job", okLabel = "Post Job", planetHeading = "From planet",
            intro = string.format("A 75-ton job, bought at the origin exchange and delivered to your " ..
                "company depot on <b>%s</b>. The cargo and hauling fee are charged now.", here),
        },
        planet = {
            title = "Post Job", okLabel = "Post Job", planetHeading = "To planet",
            intro = string.format("A 75-ton job from <b>%s</b>'s stockpile to another planet's exchange. " ..
                "Only post to planets that are buying it.", here),
        },
        offer = {
            title = "Offer Job", okLabel = "Offer Job", planetHeading = "To planet",
            intro = string.format("Offer a job from <b>%s</b> straight to a Commander or Captain. " ..
                "If they reject it, the goods are lost.", here),
        },
    }
    local spec = specs[kind]
    spec.kind        = kind
    spec.width       = 480
    spec.height      = kind == "offer" and 470 or 430
    spec.commodities = commodities
    spec.planets     = cartelPlanets()
    _pendingPostDialog = spec

    local d = Mux.createDialog({
        title     = spec.title,
        width     = spec.width,
        height    = spec.height,
        singleton = "f2t_post_job_dialog",
    })
    Mux._applyContent(d, "f2t_post_job_dialog")
    d:show()
    d:raise()
end

-- Rank progress for the action row: hauling credits toward promotion.
local function progressHtml()
    local credits = f2t_ac_get_hauling_credits and f2t_ac_get_hauling_credits()
    if not credits then return "" end
    local color = credits >= 500 and "#3ecf5e" or "#c8c8c8"
    return string.format("<span style='%scolor:#888888;'>Hauling credits </span>" ..
        "<span style='%scolor:%s;font-weight:bold;'>%d</span><span style='%scolor:#888888;'>/500</span>",
        CELL_FONT, CELL_FONT, color, credits, CELL_FONT)
end

local function boardSummaryHtml()
    return string.format("<span style='%scolor:#888888;'>%d job%s on the board</span>",
        CELL_FONT, #jobs, #jobs == 1 and "" or "s")
end

local function renderActionInfo(inst)
    if not inst.actInfo then return end
    inst.actInfo:echo(canTakeJobs() and progressHtml() or boardSummaryHtml())
end

-- Computes route distance and bonus/penalty pay for one gmcp.jobs.board entry.
local function buildJobRow(entry)
    local origin      = entry.source
    local dest        = entry.destination
    local allowedNum  = tonumber(entry.gtu) or 0
    local basePay     = tonumber(entry.totalValue) or 0

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

    -- The bank automatically skims 10% off any cargo-job earnings while a
    -- loan is outstanding (fed2_guide.txt: "The Bank will automatically skim
    -- 10% off any money you earn by doing cargo jobs"), regardless of
    -- bonus/penalty outcome. Without this, the estimate overstates take-home
    -- pay for every player who hasn't repaid their starting loan yet.
    local loan = gmcp and gmcp.char and gmcp.char.vitals and tonumber(gmcp.char.vitals.loan)
    if loan and loan > 0 then
        effectivePay = math.floor(effectivePay * 0.90)
    end

    return {
        jobNumber     = entry.id,
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
end

local function buildCols()
    return {
        {
            key           = "jobNumber",
            label         = "Job",
            sortable      = true,
            sort_value    = function(row) return tonumber(row.jobNumber) or 0 end,
            scrollbox_pct = 10,
            render_label  = function(v, _row, cell)
                if canTakeJobs() then
                    cell:echo(string.format(
                        "<span style='%scolor:#7aa2ff;text-decoration:underline;'>%s</span>",
                        CELL_FONT, v or ""))
                    cell:setToolTip("Accept job " .. tostring(v) .. " (ac " .. tostring(v) .. ")")
                    cell:setClickCallback(function() acceptJob(v) end)
                else
                    cell:echo(string.format("<span style='%scolor:#888888;'>%s</span>", CELL_FONT, v or ""))
                    cell:setToolTip("Only Commanders and Captains can take jobs")
                    cell:setClickCallback(function() end)
                end
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
            header_tooltip = "Allowed/actual route GTU. A bare number with no slash means the route isn't " ..
                "in your map yet, so it can't be checked.",
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
                    cell:setToolTip("Allowed GTU (route unknown — no slash shown because origin or " ..
                        "destination isn't in your map yet)")
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
                cell:setToolTip("Base pay (estimated net pay after route bonus/penalty and " ..
                    "the bank's 10% loan repayment skim, if a loan is outstanding)")
            end,
        },
    }
end

-- Fills the active-job strip's per-column cells from currentJob (or blanks
-- them when there isn't one -- layoutInstance() hides the strip in that case).
local function renderCurrentJobBar(inst)
    local c = inst.curCells
    if not c then return end
    if not currentJob then
        for _, spec in ipairs(CUR_COLS) do c[spec.key]:echo("") end
        return
    end

    -- Just the dot -- "Active" doesn't fit in the 10% Job-column-width slot
    -- (unlike short job numbers), and the strip's green border/tint already
    -- says "active" on their own.
    c.status:echo(string.format(
        "<span style='%scolor:#3ecf5e;font-weight:bold;'>&#9679;</span>", CELL_FONT))
    c.status:setToolTip(string.format(
        "Active contract: %d tons of %s", currentJob.quantity or 0, currentJob.commodity or "?"))

    c.origin:echo(string.format("<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, currentJob.originDisplay))
    c.origin:setToolTip("Go to " .. currentJob.origin)
    c.origin:setClickCallback(function() navigateTo(currentJob.origin) end)

    c.dest:echo(string.format("<span style='%scolor:#00cccc;'>%s</span>", CELL_FONT, currentJob.destDisplay))
    c.dest:setToolTip("Go to " .. currentJob.dest)
    c.dest:setClickCallback(function() navigateTo(currentJob.dest) end)

    local movesColor = (currentJob.curMoves > currentJob.maxMoves) and "#ff5555" or "#c8c8c8"
    c.moves:echo(string.format(
        "<span style='%scolor:%s;'><b>%d</b>/<b>%d</b></span>",
        CELL_FONT, movesColor, currentJob.curMoves, currentJob.maxMoves))
    c.moves:setToolTip("Moves used / allowed for this contract")

    local status = currentJob.collected and "in transit" or "awaiting pickup"
    c.pay:echo(string.format(
        "<span style='%scolor:#e0b84d;font-weight:bold;'>%dig</span>" ..
        "<span style='%scolor:#888888;font-size:%dpx;'>&nbsp;(%s)</span>",
        CELL_FONT, currentJob.basePay, CELL_FONT, inst.statusPx, status))
end

-- Repositions the column header/scrollbox below the active-job strip,
-- expanding or collapsing that strip's space depending on whether a job
-- is currently under contract.
local function layoutInstance(gid)
    local inst = instances[gid]
    if not inst then return end

    if currentJob then
        inst.currentJobBar:show()
    else
        inst.currentJobBar:hide()
    end
    renderCurrentJobBar(inst)
    local curH = currentJob and inst.curH or 0
    inst.currentJobBar:resize(nil, curH)

    local colY = inst.topH + curH
    inst.colBar:move(nil, colY)

    local scrollTop = colY + inst.colH
    inst.scroll:move(nil, scrollTop)
    inst.scroll:resize(nil, "100%-" .. scrollTop .. "px")
    inst.noJobsLbl:move(nil, scrollTop)
    inst.noJobsLbl:resize(nil, "100%-" .. scrollTop .. "px")
end

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    layoutInstance(gid)
    renderActionInfo(inst)
    f2tTableSetData(inst.tableId, jobs)
    if inst.noJobsLbl then
        if #jobs == 0 then inst.noJobsLbl:show() else inst.noJobsLbl:hide() end
    end
end

local function refreshAll()
    for gid in pairs(instances) do pcall(refreshInstance, gid) end
end

local _renderTimer = nil
local function refreshAllDebounced()
    -- gmcp.jobs.board can fire multiple times in a burst; draw once things settle.
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.15, function()
        _renderTimer = nil
        refreshAll()
    end)
end

-- ── GMCP feed ──────────────────────────────────────────────────────────────

local function onGmcpJobsBoard()
    local board = gmcp and gmcp.jobs and gmcp.jobs.board
    if type(board) ~= "table" then board = {} end
    local rows = {}
    for _, entry in ipairs(board) do
        rows[#rows + 1] = buildJobRow(entry)
    end
    jobs = rows
    refreshAllDebounced()
end

local function onGmcpCharJob()
    local job = gmcp and gmcp.char and gmcp.char.job
    if not f2t_ac_job_is_active(job) then
        if currentJob then
            currentJob = nil
            refreshAll()
        end
        return
    end
    currentJob = {
        origin        = job.source,
        dest          = job.destination,
        originDisplay = stripThe(job.source),
        destDisplay   = stripThe(job.destination),
        curMoves      = tonumber(job.moves and job.moves.cur) or 0,
        maxMoves      = tonumber(job.moves and job.moves.max) or 0,
        basePay       = tonumber(job.totalValue) or 0,
        commodity     = job.commodity,
        quantity      = tonumber(job.quantity) or 0,
        collected     = job.collected and true or false,
    }
    refreshAll()
end

-- Registered once at module load, same as every other always-on GMCP-fed
-- content module (missions/company/futures/etc.) -- never torn down.
-- Both "gmcp.jobs.board" and "gmcp.jobs" are registered since it's not
-- certain from the wire which level of the tree the server's update event
-- fires on; a redundant call is harmless, it just rebuilds `jobs` again.
registerAnonymousEventHandler("gmcp.jobs.board", onGmcpJobsBoard)
registerAnonymousEventHandler("gmcp.jobs", onGmcpJobsBoard)
registerAnonymousEventHandler("gmcp.char.job", onGmcpCharJob)

-- ── Content build ─────────────────────────────────────────────────────────────

-- Buttons for the rank's action row; empty for ranks that only watch the board.
local function actionButtons()
    if canTakeJobs() then
        return {
            { label = "📦 Collect", tip = "Collect cargo for the accepted job (collect)", css = _BTN_COLLECT_CSS,
              run = function() send("collect", false) end },
            { label = "✅ Deliver", tip = "Deliver cargo at the destination (deliver)", css = _BTN_DELIVER_CSS,
              run = function() send("deliver", false) end },
        }
    end
    local kind = postKind()
    if kind == "depot" then
        return {
            { label = "📮 Post Job", tip = "Post a job delivering to your depot here (post job)", css = _BTN_POST_CSS,
              run = function() openPostDialog("depot") end },
        }
    elseif kind == "planet" then
        return {
            { label = "📮 Post Job", tip = "Post a job from this planet (post job)", css = _BTN_POST_CSS,
              run = function() openPostDialog("planet") end },
            { label = "🤝 Offer Job", tip = "Offer a job to a named hauler (offer ... job)", css = _BTN_OFFER_CSS,
              run = function() openPostDialog("offer") end },
        }
    end
    return {}
end

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

    local colH    = f2tScaled(target, H_COL)
    local cellPt  = f2tUiPt(target, CELL_PT)
    local labelPt = f2tTextPt(target, LABEL_PT)

    local strip = f2tHaulStripCreate(target)
    local barH  = strip.height

    -- ── Rank action row ───────────────────────────────────────────────────────
    local buttons = actionButtons()
    local actH = (#buttons > 0) and f2tScaled(target, H_ACT) or 0
    local actBar, actInfo
    if actH > 0 then
        actBar = Geyser.Label:new({
            name = wid(), x = 0, y = barH, width = "100%", height = actH,
        }, target.content)
        actBar:setStyleSheet(_ACT_BAR_CSS)

        local btnW = f2tScaled(target, 92)
        for i, b in ipairs(buttons) do
            local btn = Geyser.Label:new({
                name = wid(), x = 6 + (i - 1) * (btnW + 8), y = 4, width = btnW, height = actH - 8,
                fontSize = labelPt,
            }, actBar)
            btn:setStyleSheet(b.css)
            btn:echo("<center>" .. b.label .. "</center>")
            btn:setToolTip(b.tip)
            btn:setClickCallback(b.run)
        end

        local infoX = 6 + #buttons * (btnW + 8)
        actInfo = Geyser.Label:new({
            name = wid(), x = infoX, y = 0, width = "100%-" .. (infoX + 6) .. "px", height = "100%",
            fontSize = cellPt,
        }, actBar)
        actInfo:setStyleSheet(
            "background-color: transparent; border: none; qproperty-alignment: 'AlignRight | AlignVCenter';")
    end
    local topH = barH + actH

    -- ── Active-job strip ──────────────────────────────────────────────────────
    -- Hidden/zero-height until gmcp.char.job has a job; layoutInstance() sizes it.
    local currentJobBar = Geyser.Label:new({
        name = wid(), x = 0, y = topH, width = "100%", height = 0,
    }, target.content)
    currentJobBar:setStyleSheet(_CUR_BAR_CSS)
    currentJobBar:hide()

    local curCells = {}
    local curXPct = 0
    for _, spec in ipairs(CUR_COLS) do
        local lbl = Geyser.Label:new({
            name  = wid(),
            x = curXPct .. "%", y = 0,
            width = spec.pct .. "%", height = "100%", fontSize = cellPt,
        }, currentJobBar)
        lbl:setStyleSheet("background-color: transparent; border: none;")
        curCells[spec.key] = lbl
        curXPct = curXPct + spec.pct
    end

    -- ── Column header bar ─────────────────────────────────────────────────────
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = topH, width = "100%", height = colH,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    -- ── ScrollBox ─────────────────────────────────────────────────────────────
    local scrollTop = topH + colH
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

    -- Overlays the table area when no jobs are listed; f2tTableSetData leaves
    -- an empty scrollbox with no message of its own.
    local noJobsLbl = Geyser.Label:new({
        name = wid(), x = 0, y = scrollTop, width = "100%", height = "100%-" .. scrollTop .. "px",
        fontSize = cellPt,
    }, target.content)
    noJobsLbl:setStyleSheet("QLabel{background-color: rgba(18, 18, 26, 255); border: none; " ..
        "qproperty-wordWrap: true; qproperty-alignment: 'AlignLeft | AlignTop';}")
    noJobsLbl:echo(emptyStateHtml("No AC jobs currently listed."))
    noJobsLbl:hide()

    -- ── Table system ──────────────────────────────────────────────────────────
    local tableId = "hauling_jobs_" .. gid
    local cols    = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, f2tScaled(target, ROW_H), scroll, cellPt)

    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name  = wid(),
            x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%", fontSize = labelPt,
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
        target        = target,
        rank          = f2t_get_rank(),
        tableId       = tableId,
        colBar        = colBar,
        currentJobBar = currentJobBar,
        curCells      = curCells,
        scroll        = scroll,
        contentLabel  = contentLabel,
        contentW      = contentW,
        noJobsLbl     = noJobsLbl,
        actInfo       = actInfo,
        topH          = topH,
        curH          = f2tScaled(target, H_CUR),
        colH          = colH,
        statusPx      = f2tScaled(target, 8),
    }

    refreshInstance(gid)
end

-- A promotion changes what the action row offers and whether jobs can be
-- accepted, so the panel rebuilds; any other vitals tick only refreshes the
-- credit readout.
registerAnonymousEventHandler("gmcp.char.vitals", function()
    local rank = f2t_get_rank()
    for _, inst in pairs(instances) do
        if inst.rank ~= rank then
            inst.rank = rank
            f2tRebuildForTextScale(inst.target)
        else
            pcall(renderActionInfo, inst)
        end
    end
end)

local function buildHaulingJobsDef()
    return {
        name        = "Jobs",
        description = "Armstrong Cuthbert workboard with route distance, effective pay, and posting for higher ranks.",
        group       = "F2CE Tools",
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
            f2tHaulStripRemove(target._gid)
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
        onTextScale = function(target) f2tRebuildForTextScale(target) end,
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
