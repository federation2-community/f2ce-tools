-- commodities.lua — Commodity reference table content for f2ce-tools.
--
-- Sortable reference of every commodity (name, short code, base price) from
-- resources/commodities.json.  Static data — no triggers, no GMCP.
--
-- Ported from archive's ui_commods.lua, rebuilt on the table system
-- (ui/table_system.lua) the who panel uses.

local H_COL  = 20    -- column header bar height (px)
local ROW_H  = 20    -- row height (px)
local SB_W   = 17    -- scrollbar pixel allowance

local CELL_FONT = "font-size:11pt;font-family:Consolas,Monaco,monospace;"

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

local _rows = nil   -- lazy-loaded, shared by all instances (static data)

local function loadRows()
    if _rows then return _rows end
    local filePath = getMudletHomeDir() .. "/f2ce-tools/commodities.json"
    local file = io.open(filePath, "r")
    if not file then
        f2t_debug_log("[commodities panel] could not open commodities.json")
        return {}
    end
    local jsonString = file:read("*all")
    file:close()

    local ok, data = pcall(yajl.to_value, jsonString)
    if not ok or not data or not data.groups then
        f2t_debug_log("[commodities panel] invalid commodities.json format")
        return {}
    end

    local rows = {}
    for _, group in ipairs(data.groups) do
        for _, commodity in ipairs(group.commodities) do
            rows[#rows + 1] = {
                name      = commodity.name,
                shortName = commodity.shortName,
                basePrice = commodity.basePrice,
                group     = group.name,
            }
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    _rows = rows
    return rows
end

local function buildCols()
    return {
        {
            key           = "name",
            label         = "Commodity",
            sortable      = true,
            default_sort  = "asc",
            scrollbox_pct = 60,
            render_label  = function(v, row, cell)
                local short = row.shortName
                    and string.format("<span style='%scolor:#697db4;'> (%s)</span>", CELL_FONT, row.shortName)
                    or ""
                cell:echo(string.format(
                    "<span style='%scolor:#e6d28c;'>%s</span>%s",
                    CELL_FONT, v or "", short))
                if row.group then cell:setToolTip(row.group) end
                cell:setClickCallback(function() expandAlias("price " .. (row.shortName or v)) end)
            end,
        },
        {
            key           = "basePrice",
            label         = "Base",
            sortable      = true,
            sort_value    = function(row) return tonumber(row.basePrice) or 0 end,
            scrollbox_pct = 40,
            render_label  = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#73de94;'>%s ig</span>",
                    CELL_FONT, tostring(v or "")))
                cell:setToolTip("Base price — click name to check live exchange prices")
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

    if instances[gid] then
        f2tTableSetData(instances[gid].tableId, loadRows())
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_cmd_%d", gid, wc)
    end

    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scroll = Geyser.ScrollBox:new({
        name   = wid(),
        x = 0, y = H_COL,
        width  = "100%",
        height = "100%-" .. H_COL .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local tableId = "commodities_" .. gid
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
            lbl:setToolTip("Sort by " .. col.label)
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

    f2tTableSetData(tableId, loadRows())
end

local function buildCommoditiesDef()
    return {
        name        = "Commodities",
        description = "Commodity reference: names, short codes, and base prices.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[commodities panel] apply error: %s", tostring(err))
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
    }
end

function f2tRegisterCommodities()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[commodities panel] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_commodities", buildCommoditiesDef())
    if f2t_debug_log then f2t_debug_log("[commodities panel] registered fed2_commodities content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterCommodities)

if f2t_debug_log then f2t_debug_log("[commodities panel] module loaded") end
