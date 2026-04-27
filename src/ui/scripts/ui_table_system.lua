-- =============================================================================
-- UI Table System - Federation 2 Mudlet Package
-- Unified column display and sorting for tabular data
-- =============================================================================

UI = UI or {}
UI.tables = UI.tables or {}

-- =============================================================================
-- TABLE CONFIGURATION
-- =============================================================================

--[[
    Column Definition Structure:
    {
        key              = "field_name",            -- Key in data row to display
        label            = "Display Name",          -- Header text
        width            = 10,                      -- Fixed width for padding (ENFORCED - data truncated if too long)
        align            = "left"|"right"|"center", -- Text alignment for data rows
        header_align     = "left"|"right"|"center", -- Header text alignment (optional, defaults to align)
        sortable         = true|false,              -- Can this column be sorted?
        default_sort     = "asc"|"desc",            -- Default sort direction (optional)
        allowed_sort     = "asc"|"desc"|"both",     -- Allowed sort direction (optional, defaults to both)
        separator        = " | ",                   -- Column separator for data rows (optional, overrides table default)
        header_separator = " | ",                   -- Column separator for header (optional, overrides separator and table default)
        format           = function(value, row) return formatted_string end, -- Custom formatting function (optional)
        render           = function(value, row, window, col) end,            -- Custom render function (optional)        
        link             = function(value, row) end,                         -- Click callback for column (optional)
        linkHint         = "tooltip text",                                   -- Tooltip for link (optional, can use %s for value)
        sort_value       = function(row) return comparable_value end         -- Custom sort value extraction (optional)
    }

    Table Configuration Structure:
    {
        window     = window_object,
        columns    = {...},
        data       = {...},
        sort       = {...},
        separators = {    -- Optional separator configuration
            column = " ", -- Between columns (default: single space)
            row    = nil, -- Between rows (nil = none, or string like "---")
            header = nil  -- After header row (nil = none, or string like "===")
        }
    }
]]

-- =============================================================================
-- CORE TABLE FUNCTIONS
-- =============================================================================

function ui_table_create(table_id, window, columns, separators)
    UI.tables[table_id] = {
        window = window,
        columns = columns,
        data = {},
        sort = {
            column = nil,
            ascending = true
        },
        separators = separators or {
            column = " ", -- Default: single space between columns
            row    = nil, -- Default: no row separators
            header = nil  -- Default: no header separator
        }
    }

    -- Set default sort if specified in columns
    for _, col in ipairs(columns) do
        if col.default_sort then
            UI.tables[table_id].sort.column = col.key
            UI.tables[table_id].sort.ascending = (col.default_sort == "asc")
            break
        end
    end
end

function ui_table_set_data(table_id, data)
    if not UI.tables[table_id] then
        cecho("\n<red>Error: Table '" .. table_id .. "' not found!\n")
        return
    end

    UI.tables[table_id].data = data
    ui_table_render(table_id)
end

function ui_table_clear(table_id)
    if not UI.tables[table_id] then return end
    UI.tables[table_id].data = {}
end

-- =============================================================================
-- SORTING
-- =============================================================================

function ui_table_sort(table_id)
    local tbl = UI.tables[table_id]
    if not tbl or not tbl.sort.column then return end

    local col_def = nil
    for _, col in ipairs(tbl.columns) do
        if col.key == tbl.sort.column then
            col_def = col
            break
        end
    end

    if not col_def then return end

    local asc = tbl.sort.ascending

    table.sort(tbl.data, function(a, b)
        local valA, valB

        -- Use custom sort_value function if provided
        if col_def.sort_value then
            valA = col_def.sort_value(a)
            valB = col_def.sort_value(b)
        else
            valA = a[col_def.key]
            valB = b[col_def.key]
        end

        -- Handle nil values
        if valA == nil and valB == nil then return false end
        if valA == nil then return not asc end
        if valB == nil then return asc end

        -- String comparison (case-insensitive)
        if type(valA) == "string" then
            valA = valA:lower()
            valB = valB:lower()
        end

        if valA < valB then
            return asc
        elseif valA > valB then
            return not asc
        else
            return false
        end
    end)
end

function ui_table_toggle_sort(table_id, column_key)
    local tbl = UI.tables[table_id]
    if not tbl then return end

    -- Find the column definition
    local col_def
    for _, col in ipairs(tbl.columns) do
        if col.key == column_key then
            col_def = col
            break
        end
    end

    if not col_def or not col_def.sortable then return end

    local allowed = col_def.allowed_sort or "both"

    -- If this column is already the active sort column
    if tbl.sort.column == column_key then
        if allowed == "both" then
            tbl.sort.ascending = not tbl.sort.ascending
        elseif allowed == "asc" then
            tbl.sort.ascending = true
        elseif allowed == "desc" then
            tbl.sort.ascending = false
        end
    else
        -- Switching to a new column
        tbl.sort.column = column_key

        if allowed == "asc" then
            tbl.sort.ascending = true
        elseif allowed == "desc" then
            tbl.sort.ascending = false
        elseif col_def.default_sort then
            tbl.sort.ascending = (col_def.default_sort == "asc")
        else
            tbl.sort.ascending = true
        end
    end

    ui_table_render(table_id)
end

-- =============================================================================
-- RENDERING
-- =============================================================================

function ui_table_render_header(table_id)
    local tbl = UI.tables[table_id]
    local window = tbl.window

    for i, col in ipairs(tbl.columns) do
        local isActive = (tbl.sort.column == col.key)
        local color    = isActive and "<ansiGreen>" or "<white>"

        -- Determine display text with padding
        local display_text = col.label
        if col.width then
            -- Use header_align if specified, otherwise fall back to align and then left
            local header_align = col.header_align or col.align or "left"

            display_text = f2t_padding(display_text, col.width, header_align)
        end

        if col.sortable then
            window:cechoLink(
                color .. display_text .. "<reset>",
                function() ui_table_toggle_sort(table_id, col.key) end,
                "Sort by " .. col.label,
                true
            )
        else
            window:cecho(color .. display_text .. "<reset>")
        end

        -- Add column separator (except after last column)
        if i < #tbl.columns then
            -- Use header_separator if defined, otherwise separator, otherwise table default
            local separator = col.header_separator or col.separator or tbl.separators.column
            window:cecho(separator)
        end
    end

    window:cecho("\n")

    -- Add header separator line if configured
    if tbl.separators.header then
        -- Calculate total width
        local total_width = 0

        for i, col in ipairs(tbl.columns) do
            total_width = total_width + (col.width or 0)

            if i < #tbl.columns then
                -- Use header_separator for width calculation too
                local sep = col.header_separator or col.separator or tbl.separators.column
                total_width = total_width + #sep
            end
        end

        -- Render separator line
        if type(tbl.separators.header) == "string" then
            -- Repeat the separator string to fill width
            local sep_char = tbl.separators.header
            local repeated = string.rep(sep_char, math.ceil(total_width / #sep_char))

            window:cecho(repeated:sub(1, total_width) .. "\n")
        end
    end
end

function ui_table_render_row(table_id, row)
    local tbl    = UI.tables[table_id]
    local window = tbl.window

    for i, col in ipairs(tbl.columns) do
        local value = row[col.key]

        -- Use custom render function if provided
        if col.render then
            col.render(value, row, window, col)  -- Pass column definition
        else
            local display_text

            -- STEP 1: Get raw value as string
            local raw_value = tostring(value or "")

            -- STEP 2: Apply formatting to raw value (colors, markup, etc)
            -- Format function should return ONLY the visible content, no padding
            if col.format then
                display_text = col.format(raw_value, row)
            else
                display_text = raw_value
            end

            -- STEP 3: Apply padding/alignment to formatted text
            -- This isolates column width and handles truncation
            if col.width then
                -- Calculate visible length (strip ANSI codes for accurate measurement)
                local visible_text = display_text:gsub("<[^>]+>", "")
                local visible_len  = #visible_text

                -- Determine padding needed
                if visible_len < col.width then
                    -- Need to pad
                    local padding_needed = col.width + (#display_text - visible_len)
                    local row_align      = col.align or "left"

                    display_text = f2t_padding(display_text, padding_needed, row_align)
                elseif visible_len > col.width then
                    -- Need to truncate - preserve formatting up to truncation point
                    local truncated     = ""
                    local visible_count = 0
                    local i = 1

                    while i <= #display_text do
                        if display_text:sub(i, i) == '<' then
                            -- Found start of a tag, find the complete tag
                            local tag_end = display_text:find('>', i + 1)
                            if tag_end then
                                local tag = display_text:sub(i, tag_end)
                                truncated = truncated .. tag
                                i = tag_end + 1
                            else
                                -- Malformed tag, skip the '<'
                                i = i + 1
                            end
                        else
                            -- Regular character
                            if visible_count < col.width then
                                truncated = truncated .. display_text:sub(i, i)
                                visible_count = visible_count + 1
                                i = i + 1
                            else
                                -- Reached truncation point
                                break
                            end
                        end
                    end

                    -- Add reset at the end to close any open formatting
                    display_text = truncated .. "<reset>"
                end
                -- If visible_len == col.width, display_text is perfect as-is
            end

            -- STEP 4: Apply link if specified
            if col.link then
                local hint = col.linkHint or ""
                if hint:find("%%s") then
                    hint = string.format(hint, value)
                end
                window:cechoLink(display_text, function() col.link(value, row) end, hint, true)
            else
                window:cecho(display_text)
            end
        end

        -- Add column separator (except after last column)
        if i < #tbl.columns then
            -- Use column-specific separator if defined, otherwise table default
            local separator = col.separator or tbl.separators.column
            window:cecho(separator)
        end
    end

    window:cecho("\n")
end

function ui_table_render(table_id)
    local tbl = UI.tables[table_id]
    if not tbl or not tbl.window then
        cecho("\n<red>Error: Table '" .. table_id .. "' not configured!\n")
        return
    end

    clearWindow(tbl.window.name)

    if #tbl.data == 0 then
        tbl.window:cecho("No data available.\n")
        return
    end

    ui_table_sort(table_id)
    ui_table_render_header(table_id)

    for i, row in ipairs(tbl.data) do
        ui_table_render_row(table_id, row)

        -- Add row separator (except after last row)
        if i < #tbl.data and tbl.separators.row then
            -- Calculate total width
            local total_width = 0
            for j, col in ipairs(tbl.columns) do
                total_width = total_width + (col.width or 0)
                if j < #tbl.columns then
                    local sep = col.separator or tbl.separators.column
                    total_width = total_width + #sep
                end
            end

            -- Render row separator
            if type(tbl.separators.row) == "string" then
                local sep_char = tbl.separators.row
                local repeated = string.rep(sep_char, math.ceil(total_width / #sep_char))
                tbl.window:cecho(repeated:sub(1, total_width) .. "\n")
            end
        end
    end
end
