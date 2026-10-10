-- Commerce > Planets: planet-owner hauling at a glance. A summary of the
-- system being supplied (owned planets, deficits and excesses found, scan
-- count) above the job queue hauling is working through, current job marked.
-- Planets in the queue navigate to their exchange on click. After hauling
-- stops, the last session's queue stays visible, dimmed.

local H_SUM  = 54    -- summary block height (px): two lines, room for one to wrap
local H_COL  = 20
local ROW_H  = 20
local SB_W   = 17
local CELL_PT  = 10
local LABEL_PT = 8

local CELL_FONT = "font-family:Consolas,Monaco,monospace;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
]]

-- Per-pane state, keyed by target._gid
local instances = {}

local function span(color, text, bold)
    return string.format("<span style='%scolor:%s;%s'>%s</span>",
        CELL_FONT, color, bold and "font-weight:bold;" or "", text)
end

-- Planets the map records as owned by this character.
local function mappedOwnedPlanets()
    local me = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not me then return {} end
    local list = {}
    for name, areaId in pairs(getAreaTable()) do
        if getAreaUserData(areaId, "fed2_owner") == me and not f2t_map_get_system_from_space_area(name) then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

-- Queue rows plus whether they belong to a running session.
local function queueRows()
    local state = F2T_HAULING_STATE
    if not state then return {}, false end
    local live  = state.active and state.mode == "po"
    local queue = live and state.po_job_queue or state.po_last_queue or {}
    local rows = {}
    for i, job in ipairs(queue) do
        rows[#rows + 1] = {
            index     = i,
            current   = live and i == state.po_job_index,
            done      = live and i < state.po_job_index,
            type      = job.type,
            commodity = job.commodity,
            bundled   = job.bundled_commodity,
            lots      = (job.lots or 0) + (job.bundled_lots or 0),
            from      = job.buy_planet,
            to        = job.sell_planet,
            stale     = not live,
        }
    end
    return rows, live
end

local function summaryHtml()
    local state = F2T_HAULING_STATE or {}
    local live = state.active and state.mode == "po"
    local planets = live and state.po_owned_planets or state.po_last_planets or {}
    if #planets == 0 then planets = mappedOwnedPlanets() end

    local line1 = span("#888888", "Planets ") .. (#planets > 0
        and span("#00cccc", table.concat(planets, ", "))
        or span("#666666", "none mapped yet"))
    if live and state.po_current_system then
        line1 = span("#888888", "System ") .. span("#e8ebf5", state.po_current_system, true)
            .. span("#888888", " · ") .. line1
    end

    local line2
    if live then
        line2 = span("#ff9955", string.format("%d deficit%s", state.po_deficit_count or 0,
                (state.po_deficit_count or 0) == 1 and "" or "s"))
            .. span("#888888", " · ")
            .. (state.po_deficit_only and span("#666666", "excesses skipped")
                or span("#e0b84d", string.format("%d excess%s", state.po_excess_count or 0,
                    (state.po_excess_count or 0) == 1 and "" or "es")))
            .. span("#888888", string.format(" · scan %d · %d lots", state.po_scan_count or 0,
                state.po_ship_lots or 0))
    elseif (state.po_deficit_cycles or 0) + (state.po_excess_cycles or 0) > 0 then
        line2 = span("#888888", string.format("Last run: %d deficit and %d excess cycles",
            state.po_deficit_cycles or 0, state.po_excess_cycles or 0))
    else
        line2 = span("#666666", "Start planet hauling to scan your system")
    end
    return "<div style='padding:3px 6px;'>" .. line1 .. "<br>" .. line2 .. "</div>", planets
end

local function navigateExchange(planet)
    if planet then f2tNav.go(planet .. " exchange") end
end

local function planetCell(key)
    return function(v, row, cell)
        local color = row.stale and "#557777" or "#00cccc"
        cell:echo(span(color, v or "?"))
        cell:setToolTip(v and ("Go to " .. v .. " exchange") or "")
        cell:setClickCallback(function() navigateExchange(row[key]) end)
    end
end

local function buildCols()
    return {
        {
            key = "index", label = "#", scrollbox_pct = 8,
            render_label = function(v, row, cell)
                local marker = row.current and span("#3ecf5e", "▶", true)
                    or span(row.done and "#555555" or "#888888", tostring(v))
                cell:echo(marker)
            end,
        },
        {
            key = "type", label = "Type", scrollbox_pct = 16,
            render_label = function(v, row, cell)
                local color = v == "deficit" and "#ff9955" or "#e0b84d"
                if row.stale or row.done then color = "#776655" end
                cell:echo(span(color, v or ""))
            end,
        },
        {
            key = "commodity", label = "Commodity", scrollbox_pct = 30,
            render_label = function(v, row, cell)
                local icon = f2tCommodityIconPrefix and f2tCommodityIconPrefix(v or "") or ""
                local text = icon .. (v or "")
                if row.bundled then text = text .. " + " .. row.bundled end
                cell:echo(span((row.stale or row.done) and "#777777" or "#e6d28c", text))
                cell:setToolTip(string.format("%d lots%s", row.lots,
                    row.bundled and (" (bundled with " .. row.bundled .. ")") or ""))
            end,
        },
        { key = "from", label = "From", scrollbox_pct = 23, render_label = planetCell("from") },
        { key = "to",   label = "To",   scrollbox_pct = 23, render_label = planetCell("to") },
    }
end

local function refreshInstance(inst)
    local html, planets = summaryHtml()
    inst.summary:echo(html)
    -- A long planet list wraps within the block; the full list is in its tooltip.
    inst.summary:setToolTip(#planets > 0 and ("Planets: " .. table.concat(planets, ", ")) or "")
    local rows, live = queueRows()
    f2tTableSetData(inst.tableId, rows)
    if #rows == 0 then
        inst.emptyLbl:echo(string.format("<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT,
            live and "Scanning: no jobs queued yet." or "No queued jobs. Start planet hauling to scan for some."))
        inst.emptyLbl:show()
    else
        inst.emptyLbl:hide()
    end
end

local function refreshAll()
    for _, inst in pairs(instances) do pcall(refreshInstance, inst) end
end

registerAnonymousEventHandler("f2tHaulingStatusChanged", refreshAll)

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        refreshInstance(instances[gid])
        return
    end

    local strip  = f2tHaulStripCreate(target)
    local top    = strip.height
    local sumH   = f2tScaled(target, H_SUM)
    local colH   = f2tScaled(target, H_COL)
    local cellPt = f2tUiPt(target, CELL_PT)
    local labelPt = f2tTextPt(target, LABEL_PT)

    local summary = Geyser.Label:new({
        name = gid .. "_ps_sum", x = 0, y = top, width = "100%", height = sumH, fontSize = cellPt,
    }, target.content)
    summary:setStyleSheet([[
        QLabel {
            background-color: rgba(16, 18, 28, 230);
            border: none;
            border-bottom: 1px solid rgba(60, 65, 100, 150);
            qproperty-wordWrap: true;
            qproperty-alignment: 'AlignLeft | AlignTop';
        }
        QToolTip {
            background-color: #1d2030; color: #e8ebf5;
            border: 1px solid rgba(255,255,255,0.18); padding: 3px;
        }
    ]])

    local colY = top + sumH
    local colBar = Geyser.Label:new({
        name = gid .. "_ps_cols", x = 0, y = colY, width = "100%", height = colH,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scrollTop = colY + colH
    local scroll = Geyser.ScrollBox:new({
        name = gid .. "_ps_scroll", x = 0, y = scrollTop, width = "100%", height = "100%-" .. scrollTop .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = gid .. "_ps_rows", x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local emptyLbl = Geyser.Label:new({
        name = gid .. "_ps_empty", x = 0, y = scrollTop, width = "100%", height = "100%-" .. scrollTop .. "px",
        fontSize = cellPt,
    }, target.content)
    emptyLbl:setStyleSheet("QLabel{background-color: rgba(18, 18, 26, 255); border: none; " ..
        "qproperty-wordWrap: true; qproperty-alignment: 'AlignLeft | AlignTop';}")
    emptyLbl:hide()

    local tableId = "planet_supply_" .. gid
    local cols = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, f2tScaled(target, ROW_H), scroll, cellPt)

    local colHdrs, xPct = {}, 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name = gid .. "_ps_h_" .. col.key, x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%", fontSize = labelPt,
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    local inst = {
        tableId      = tableId,
        summary      = summary,
        contentLabel = contentLabel,
        contentW     = contentW,
        emptyLbl     = emptyLbl,
    }
    instances[gid] = inst
    refreshInstance(inst)
end

local function buildPlanetSupplyDef()
    return {
        name        = "Planets",
        description = "Planet-owner hauling: owned planets, deficits and excesses, and the job queue.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[planet_supply] apply error: %s", tostring(err))
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
        serialize   = function(_t) return {} end,
        restore     = function(_t, _d) end,
        onReveal    = function(target)
            local inst = instances[target._gid]
            if inst then refreshInstance(inst) end
        end,
        onTextScale = function(target) f2tRebuildForTextScale(target) end,
    }
end

function f2tRegisterPlanetSupply()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[planet_supply] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_planet_supply", buildPlanetSupplyDef())
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterPlanetSupply)

if f2t_debug_log then f2t_debug_log("[planet_supply] module loaded") end
