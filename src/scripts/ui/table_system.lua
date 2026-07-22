-- Sortable, scrollable tables backed by Geyser Labels.
--
-- Public API:
--   f2tTableCreate(tableId, columns)
--   f2tTableDestroy(tableId)
--   f2tTableSetScrollbox(tableId, contentLabel, contentW, rowH, scrollWidget)
--   f2tTableSetColHdrs(tableId, colHdrs)
--   f2tTableSetData(tableId, data)
--   f2tTableToggleSort(tableId, colKey)
--   f2tTableOnResize(tableId, newContentW)
--   f2tTableUpdateScrollboxHeader(tableId, colHdrs)

local _tables = {}

local _HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]
local _HDR_ACTIVE_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(120,230,120,240);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: rgba(180,255,180,255); }
]]
local _CELL_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        padding: 0 3px; color: #c8c8c8;
    }
]]

function f2tTableCreate(tableId, columns)
    _tables[tableId] = {
        columns = columns,
        data    = {},
        sort    = { column = nil, ascending = true },
    }
    for _, col in ipairs(columns) do
        if col.default_sort then
            _tables[tableId].sort.column    = col.key
            _tables[tableId].sort.ascending = (col.default_sort == "asc")
            break
        end
    end
end

function f2tTableDestroy(tableId)
    _tables[tableId] = nil
end

function f2tTableSetScrollbox(tableId, contentLabel, contentW, rowH, scrollWidget)
    local t = _tables[tableId]
    if not t then return end
    t.scrollbox = {
        contentLabel = contentLabel,
        contentW     = contentW,
        rowH         = rowH,
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

-- Call when the pane is resized so row/cell Labels track the new width.
function f2tTableOnResize(tableId, newContentW)
    local t = _tables[tableId]
    if not t or not t.scrollbox then return end
    if f2t_debug_log then
        f2t_debug_log("[table_system] onResize %s newContentW=%s rows=%d scrollWidget.w=%s scrollWidget.h=%s",
            tostring(tableId), tostring(newContentW), #t.scrollbox.rows,
            tostring(t.scrollbox.scrollWidget and t.scrollbox.scrollWidget:get_width()),
            tostring(t.scrollbox.scrollWidget and t.scrollbox.scrollWidget:get_height()))
    end
    t.scrollbox.contentW = newContentW
    local colWs = _colWidths(t)
    for _, rowLbl in ipairs(t.scrollbox.rows) do
        rowLbl:resize(newContentW, t.scrollbox.rowH)
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
    f2tTableRenderScrollbox(tableId)
end

function f2tTableRenderScrollbox(tableId)
    local t = _tables[tableId]
    if not t or not t.scrollbox then return end
    local sb = t.scrollbox
    if not sb.contentLabel then return end

    local cw   = sb.contentW
    local rowH = sb.rowH

    if not sb.minHeight and sb.scrollWidget then
        local sh = sb.scrollWidget:get_height()
        if sh > 30 then sb.minHeight = sh end
    end
    local minH = sb.minHeight or 1000

    if not t.data or #t.data == 0 then
        for i = 1, #sb.rows do sb.rows[i]:hide() end
        sb.contentLabel:resize(cw, math.max(minH, 4))
        if sb.colHdrs then f2tTableUpdateScrollboxHeader(tableId, sb.colHdrs) end
        return
    end

    _sort(tableId)
    local colWs = _colWidths(t)

    local dataLen = #t.data
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
            for j, col in ipairs(t.columns) do
                local cell = Geyser.Label:new({
                    name = string.format("f2tsb_%s_r%d_c%d", tableId, i, j),
                    x = x, y = 0, width = colWs[j], height = rowH,
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
    sb.contentLabel:resize(cw, math.max(dataLen * rowH + 4, minH))
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
