-- Sortable, scrollable tables backed by Geyser Labels.
--
-- Public API:
--   f2tTableCreate(tableId, columns)
--   f2tTableDestroy(tableId)
--   f2tTableSetScrollbox(tableId, contentLabel, contentW, rowH, scrollWidget, cellPt)
--   f2tTableSetColHdrs(tableId, colHdrs)
--   f2tTableSetData(tableId, data)
--   f2tTableToggleSort(tableId, colKey)
--   f2tTableOnResize(tableId, newContentW)
--   f2tTableUpdateScrollboxHeader(tableId, colHdrs)
--
-- Text size comes from each label's fontSize (cells: cellPt; headers: whatever
-- the caller built them with), not from these stylesheets: Geyser.Label:echo()
-- wraps every message in an inline font-size that overrides the stylesheet.

local _tables = {}

local _SCROLLBAR_W = 17   -- vertical scrollbar width (px)

-- A table destroyed and recreated under the same id (content rebuilt at a new
-- text size) keeps the sort the user picked.
local _sortMemory = {}

local _HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]
local _HDR_ACTIVE_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(120,230,120,240);
        font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: rgba(180,255,180,255); }
]]
-- The QToolTip rule keeps cell tooltips readable; without it Qt draws them
-- solid black. It only takes when the label's own rule is a QLabel{} block.
local _CELL_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        padding: 0 3px; color: #c8c8c8;
    }
    QToolTip {
        background-color: #1d2030; color: #e8ebf5;
        border: 1px solid rgba(255,255,255,0.18); padding: 3px;
    }
]]

function f2tTableCreate(tableId, columns)
    _tables[tableId] = {
        columns = columns,
        data    = {},
        sort    = { column = nil, ascending = true },
    }
    local remembered = _sortMemory[tableId]
    if remembered then
        _tables[tableId].sort = { column = remembered.column, ascending = remembered.ascending }
        return
    end
    for _, col in ipairs(columns) do
        if col.default_sort then
            _tables[tableId].sort.column    = col.key
            _tables[tableId].sort.ascending = (col.default_sort == "asc")
            break
        end
    end
end

function f2tTableDestroy(tableId)
    local t = _tables[tableId]
    if t then _sortMemory[tableId] = t.sort end
    _tables[tableId] = nil
end

-- cellPt: cell label fontSize in points (defaults to f2t_ui_pt(10)'s size).
function f2tTableSetScrollbox(tableId, contentLabel, contentW, rowH, scrollWidget, cellPt)
    local t = _tables[tableId]
    if not t then return end
    t.scrollbox = {
        contentLabel = contentLabel,
        contentW     = contentW,
        rowH         = rowH,
        cellPt       = cellPt or 10 * F2T_UI_FONT_SCALE,
        rows         = {},
        colHdrs      = nil,
        scrollWidget = scrollWidget or nil,
        minHeight    = nil,
    }
end

function f2tTableSetColHdrs(tableId, colHdrs)
    local t = _tables[tableId]
    if t and t.scrollbox then t.scrollbox.colHdrs = colHdrs end
end

function f2tTableSetData(tableId, data)
    local t = _tables[tableId]
    if not t then return end
    t.data = data
    if t.scrollbox then f2tTableRenderScrollbox(tableId) end
end

local function _sort(tableId)
    local t = _tables[tableId]
    if not t or not t.sort.column then return end
    local colDef
    for _, col in ipairs(t.columns) do
        if col.key == t.sort.column then colDef = col; break end
    end
    if not colDef then return end
    local asc = t.sort.ascending
    table.sort(t.data, function(a, b)
        local va = colDef.sort_value and colDef.sort_value(a) or a[colDef.key]
        local vb = colDef.sort_value and colDef.sort_value(b) or b[colDef.key]
        if va == nil and vb == nil then return false end
        if va == nil then return not asc end
        if vb == nil then return asc end
        if type(va) == "string" then va, vb = va:lower(), vb:lower() end
        if va < vb then return asc elseif va > vb then return not asc else return false end
    end)
end

function f2tTableToggleSort(tableId, colKey)
    local t = _tables[tableId]
    if not t then return end
    local colDef
    for _, col in ipairs(t.columns) do
        if col.key == colKey then colDef = col; break end
    end
    if not colDef or not colDef.sortable then return end
    if t.sort.column == colKey then
        t.sort.ascending = not t.sort.ascending
    else
        t.sort.column    = colKey
        t.sort.ascending = (colDef.default_sort == nil) or (colDef.default_sort == "asc")
    end
    if t.scrollbox then f2tTableRenderScrollbox(tableId) end
end

function f2tTableUpdateScrollboxHeader(tableId, colHdrs)
    local t = _tables[tableId]
    if not t or not colHdrs then return end
    local active = t.sort.column
    local asc    = t.sort.ascending
    for _, col in ipairs(t.columns) do
        local lbl = colHdrs[col.key]
        if lbl then
            if col.key == active then
                lbl:setStyleSheet(_HDR_ACTIVE_CSS)
                lbl:echo(col.label .. (asc and " ▲" or " ▼"))
            else
                lbl:setStyleSheet(_HDR_CSS)
                lbl:echo(col.label)
            end
            if col.sortable then
                local tid, key = tableId, col.key
                lbl:setClickCallback(function() f2tTableToggleSort(tid, key) end)
            end
        end
    end
end

local function _colWidths(t)
    local cw = t.scrollbox.contentW
    local colWs, used = {}, 0
    for i, col in ipairs(t.columns) do
        if i < #t.columns then
            local w = math.floor(cw * (col.scrollbox_pct or 0) / 100)
            colWs[i] = w; used = used + w
        else
            colWs[i] = math.max(1, cw - used)
        end
    end
    return colWs
end

local function _layoutRows(t, contentW)
    t.scrollbox.contentW = contentW
    local colWs = _colWidths(t)
    for _, rowLbl in ipairs(t.scrollbox.rows) do
        rowLbl:resize(contentW, t.scrollbox.rowH)
        local x = 0
        for j = 1, #t.columns do
            local cell = rowLbl.cells and rowLbl.cells[j]
            if cell then
                cell:move(x, 0)
                cell:resize(colWs[j], t.scrollbox.rowH)
                x = x + colWs[j]
            end
        end
    end
end

-- Fits the content label to the scroll viewport as it is now: at least the
-- viewport's height, and its full width unless rows overflow and a vertical
-- scrollbar takes its slice. Returns the content height to use.
local function _fitToViewport(t, contentH)
    local sb = t.scrollbox
    if sb.scrollWidget then
        local viewH = sb.scrollWidget:get_height()
        if viewH > 30 then sb.minHeight = viewH end
        local viewW = sb.scrollWidget:get_width()
        if viewW > 30 and sb.minHeight then
            local overflows = contentH > sb.minHeight
            local w = math.max(100, overflows and (viewW - _SCROLLBAR_W) or viewW)
            if w ~= sb.contentW then _layoutRows(t, w) end
        end
    end
    return math.max(contentH, sb.minHeight or 1000)
end

-- Call when the pane is resized so row/cell Labels track the new width.
function f2tTableOnResize(tableId, newContentW)
    local t = _tables[tableId]
    if not t or not t.scrollbox then return end
    local rowCount = #t.scrollbox.rows
    if f2t_debug_log then
        f2t_debug_log("[table_system] onResize %s newContentW=%s rows=%d scrollWidget.w=%s scrollWidget.h=%s",
            tostring(tableId), tostring(newContentW), rowCount,
            tostring(t.scrollbox.scrollWidget and t.scrollbox.scrollWidget:get_width()),
            tostring(t.scrollbox.scrollWidget and t.scrollbox.scrollWidget:get_height()))
    end
    local _t0 = f2t_debug_log and os.clock() or nil
    _layoutRows(t, newContentW)
    f2tTableRenderScrollbox(tableId)
    if _t0 then
        f2t_debug_log("[table_system] onResize %s took %.1fms for %d rows",
            tostring(tableId), (os.clock() - _t0) * 1000, rowCount)
    end
end

function f2tTableRenderScrollbox(tableId)
    local t = _tables[tableId]
    if not t or not t.scrollbox then return end
    local sb = t.scrollbox
    if not sb.contentLabel then return end

    local rowH = sb.rowH

    if not t.data or #t.data == 0 then
        for i = 1, #sb.rows do sb.rows[i]:hide() end
        local contentH = _fitToViewport(t, 4)
        sb.contentLabel:resize(sb.contentW, contentH)
        if sb.colHdrs then f2tTableUpdateScrollboxHeader(tableId, sb.colHdrs) end
        return
    end

    _sort(tableId)
    local dataLen  = #t.data
    local contentH = _fitToViewport(t, dataLen * rowH + 4)
    local cw       = sb.contentW
    local colWs    = _colWidths(t)

    for i, row in ipairs(t.data) do
        local y = (i - 1) * rowH
        local rowLbl = sb.rows[i]
        if not rowLbl then
            rowLbl = Geyser.Label:new({
                name = string.format("f2tsb_%s_r%d", tableId, i),
                x = 0, y = y, width = cw, height = rowH,
            }, sb.contentLabel)
            rowLbl:setStyleSheet(
                "background-color:transparent;border:none;" ..
                "border-bottom:1px solid rgba(255,255,255,0.06);")
            rowLbl.cells = {}
            local x = 0
            for j in ipairs(t.columns) do
                local cell = Geyser.Label:new({
                    name = string.format("f2tsb_%s_r%d_c%d", tableId, i, j),
                    x = x, y = 0, width = colWs[j], height = rowH, fontSize = sb.cellPt,
                }, rowLbl)
                cell:setStyleSheet(_CELL_CSS)
                rowLbl.cells[j] = cell
                x = x + colWs[j]
            end
            sb.rows[i] = rowLbl
        else
            rowLbl:move(0, y); rowLbl:show()
        end
        for j, col in ipairs(t.columns) do
            local cell = rowLbl.cells and rowLbl.cells[j]
            if cell and col.render_label then
                col.render_label(row[col.key], row, cell, col)
            elseif cell then
                cell:echo(tostring(row[col.key] or ""))
            end
        end
    end

    for i = dataLen + 1, #sb.rows do sb.rows[i]:hide() end
    sb.contentLabel:resize(cw, contentH)
    if sb.colHdrs then f2tTableUpdateScrollboxHeader(tableId, sb.colHdrs) end

    -- A growing row count creates brand-new row/cell Labels above (the `if not
    -- rowLbl` branch). Geyser shows a freshly created widget unconditionally
    -- regardless of its parent's hidden state, so if this table's pane/tab is
    -- condition-hidden when new rows appear, they'd otherwise leak visible
    -- until the next full hide/show cycle. sb.contentLabel is the long-lived
    -- container created once at apply() time, so its hidden/auto_hidden flags
    -- reflect the real state.
    if Mux and Mux.reassertHidden then Mux.reassertHidden(sb.contentLabel) end
end

if f2t_debug_log then f2t_debug_log("[table_system] module loaded") end
