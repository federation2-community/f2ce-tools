-- f2ce-tools — table renderer (ported from shared/scripts/f2t_table_renderer.lua)

-- ── Formatters ────────────────────────────────────────────────────────────────

function f2t_format_compact(num)
    if not num or type(num) ~= "number" then return tostring(num or "") end
    local sign = num < 0 and "-" or ""
    local n = math.abs(num)
    if n >= 1000000000000 then return string.format("%s%.2fT", sign, n / 1000000000000)
    elseif n >= 1000000000 then return string.format("%s%.2fB", sign, n / 1000000000)
    elseif n >= 1000000    then return string.format("%s%.2fM", sign, n / 1000000)
    elseif n >= 1000       then return string.format("%s%dK",   sign, math.floor(n / 1000))
    else return sign .. tostring(n)
    end
end

function f2t_format_percent(num)
    if not num or type(num) ~= "number" then return "0%" end
    return string.format("%d%%", math.floor(num * 100))
end

function f2t_format_boolean(bool) return bool and "Y" or "N" end

local FORMATTERS = {
    string  = function(val) return tostring(val or "") end,
    number  = function(val) return tostring(math.floor(val or 0)) end,
    compact = f2t_format_compact,
    percent = f2t_format_percent,
    boolean = f2t_format_boolean,
}

-- ── Aggregators ───────────────────────────────────────────────────────────────

local AGGREGATORS = {
    sum = function(values)
        local t = 0
        for _, v in ipairs(values) do if type(v) == "number" then t = t + v end end
        return t
    end,
    avg = function(values)
        local t, c = 0, 0
        for _, v in ipairs(values) do if type(v) == "number" then t = t + v; c = c + 1 end end
        return c > 0 and (t / c) or 0
    end,
    min = function(values)
        local m = nil
        for _, v in ipairs(values) do if type(v) == "number" and (not m or v < m) then m = v end end
        return m or 0
    end,
    max = function(values)
        local m = nil
        for _, v in ipairs(values) do if type(v) == "number" and (not m or v > m) then m = v end end
        return m or 0
    end,
    count = function(values)
        local c = 0
        for _, v in ipairs(values) do if v ~= nil then c = c + 1 end end
        return c
    end,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function strip_colors(text)
    if not text then return "" end
    return text:gsub("<[^>]+>", "")
end

function f2t_align_text(text, width, align)
    local stripped = strip_colors(text)
    local len = #stripped
    if len >= width then return stripped:sub(1, width) end
    local padding = width - len
    if align == "right" then
        return string.rep(" ", padding) .. text
    elseif align == "center" then
        local lp = math.floor(padding / 2)
        return string.rep(" ", lp) .. text .. string.rep(" ", padding - lp)
    else
        return text .. string.rep(" ", padding)
    end
end

function f2t_colorize_cell(text, color)
    if not color or color == "" then return text end
    return string.format("<%s>%s<reset>", color, text)
end

function f2t_format_cell(value, column, row)
    if value == nil then return "" end
    if column.formatter then return tostring(column.formatter(value, row)) end
    local formatter = FORMATTERS[column.format or "string"] or FORMATTERS.string
    local formatted = formatter(value)
    if column.truncate ~= false and column.max_width then
        local stripped = strip_colors(formatted)
        if #stripped > column.max_width then
            local ellipsis = column.ellipsis or "..."
            formatted = stripped:sub(1, column.max_width - #ellipsis) .. ellipsis
        end
    end
    return formatted
end

-- ── Width calculation ─────────────────────────────────────────────────────────

local function calc_min(col, data)
    if col.width then return col.width end
    return math.max(col.min_width or 0, #col.header)
end

local function calc_desired(col, data)
    if col.width then return col.width end
    local max_w = #col.header
    local sample = math.min(20, #data)
    for i = 1, sample do
        local v = f2t_format_cell(data[i][col.field], col, data[i])
        max_w = math.max(max_w, #strip_colors(v))
    end
    if #data > 20 then
        for i = 30, #data, 10 do
            local v = f2t_format_cell(data[i][col.field], col, data[i])
            max_w = math.max(max_w, #strip_colors(v))
        end
    end
    if col.max_width then max_w = math.min(max_w, col.max_width) end
    return max_w
end

function f2t_calculate_column_widths(columns, data, max_width, footer_row)
    local mins, desired, fixed = {}, {}, {}
    for i, col in ipairs(columns) do
        if not col.hidden then
            mins[i]    = calc_min(col, data)
            desired[i] = calc_desired(col, data)
            if footer_row and footer_row[col.field] then
                local fv = f2t_format_cell(footer_row[col.field], col, footer_row)
                desired[i] = math.max(desired[i], #strip_colors(fv))
            end
            if col.width then fixed[i] = true end
        else
            mins[i] = 0; desired[i] = 0
        end
    end
    local visible = 0
    for _, col in ipairs(columns) do if not col.hidden then visible = visible + 1 end end
    local spacing = visible > 1 and (visible - 1) or 0
    local total = spacing
    for _, w in ipairs(desired) do total = total + w end
    if total <= max_width then return desired end
    local final = {}
    local flex = {}
    local fixed_total = spacing
    for i, col in ipairs(columns) do
        if fixed[i] then final[i] = desired[i]; fixed_total = fixed_total + desired[i]
        else table.insert(flex, i)
        end
    end
    local avail = max_width - fixed_total
    if #flex > 0 then
        local flex_total = 0
        for _, i in ipairs(flex) do flex_total = flex_total + desired[i] end
        for _, i in ipairs(flex) do
            local prop = desired[i] / flex_total
            final[i] = math.max(math.floor(avail * prop), mins[i])
        end
    end
    return final
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

function f2t_render_row(row, columns, widths)
    local parts = {}
    for i, col in ipairs(columns) do
        if not col.hidden then
            local formatted = f2t_format_cell(row[col.field], col, row)
            local aligned   = f2t_align_text(formatted, widths[i], col.align or "left")
            local color = col.color
            if col.color_fn then color = col.color_fn(row[col.field], row) end
            table.insert(parts, f2t_colorize_cell(aligned, color))
        end
    end
    cecho(table.concat(parts, " ") .. "\n")
end

function f2t_calculate_aggregations(data, aggregations, columns)
    if not aggregations then return nil end
    local agg_row = {}
    for _, agg in ipairs(aggregations) do
        local aggregator = AGGREGATORS[agg.method or "sum"]
        if aggregator then
            local values = {}
            for _, row in ipairs(data) do table.insert(values, row[agg.field]) end
            agg_row[agg.field] = aggregator(values)
        end
    end
    return agg_row
end

function f2t_render_footer(footer_config, agg_row, columns, widths)
    if not footer_config or not agg_row then return end
    local parts = {}
    for i, col in ipairs(columns) do
        if not col.hidden then
            local value = agg_row[col.field]
            if value ~= nil then
                local formatted = f2t_format_cell(value, col, agg_row)
                local aligned   = f2t_align_text(formatted, widths[i], col.align or "left")
                local color = nil
                if footer_config.aggregations then
                    for _, agg in ipairs(footer_config.aggregations) do
                        if agg.field == col.field and agg.color_fn then
                            color = agg.color_fn(value, agg_row)
                            break
                        end
                    end
                end
                table.insert(parts, f2t_colorize_cell(aligned, color))
            else
                table.insert(parts, string.rep(" ", widths[i]))
            end
        end
    end
    cecho(table.concat(parts, " ") .. "\n")
end

-- ── Main function ─────────────────────────────────────────────────────────────

function f2t_render_table(config)
    if not config.columns or #config.columns == 0 then
        cecho("\n<red>[Table Renderer]<reset> Error: No columns defined\n")
        return
    end
    config.data = config.data or {}
    for i, col in ipairs(config.columns) do
        if not col.header or not col.field then
            cecho(string.format("\n<red>[Table Renderer]<reset> Error: Column %d missing header or field\n", i))
            return
        end
    end

    local columns        = config.columns
    local data           = config.data
    local max_width      = config.max_width or COLS or 100
    local show_header    = config.show_header ~= false
    local show_sep       = config.show_separators ~= false
    local sep_char       = config.separator_char or "-"
    local header_color   = config.header_color or "white"

    local agg_row = nil
    if config.footer and config.footer.aggregations then
        agg_row = f2t_calculate_aggregations(data, config.footer.aggregations, columns)
    end

    local widths = f2t_calculate_column_widths(columns, data, max_width, agg_row)

    local table_width = 0
    local visible = 0
    for i, col in ipairs(columns) do
        if not col.hidden then table_width = table_width + widths[i]; visible = visible + 1 end
    end
    if visible > 1 then table_width = table_width + (visible - 1) end

    if config.title then
        cecho(string.format("\n<white>=== %s ===<reset>\n", config.title))
    end

    if show_header then
        local header_parts = {}
        for i, col in ipairs(columns) do
            if not col.hidden then
                local aligned = f2t_align_text(col.header, widths[i], col.align or "left")
                table.insert(header_parts, f2t_colorize_cell(aligned, header_color))
            end
        end
        cecho("\n" .. table.concat(header_parts, " ") .. "\n")
        if show_sep then cecho(string.rep(sep_char, table_width) .. "\n") end
    end

    for _, row in ipairs(data) do
        f2t_render_row(row, columns, widths)
    end

    if show_sep then cecho(string.rep(sep_char, table_width) .. "\n") end

    if config.footer and config.footer.aggregations and agg_row then
        f2t_render_footer(config.footer, agg_row, columns, widths)
    end
end
