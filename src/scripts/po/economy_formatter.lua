-- Display formatted economy table using f2t_render_table

--- Display the economy summary table
--- @param planet_name string Planet name for title
--- @param commodities table Array of merged commodity records
--- @param group_filter string|nil Canonical group name to filter by, or nil for all
function f2t_po_economy_display(planet_name, commodities, group_filter)
    -- Apply group filter if set
    local filtered = commodities
    if group_filter then
        filtered = {}
        for _, record in ipairs(commodities) do
            if record.group == group_filter then
                table.insert(filtered, record)
            end
        end
    end

    f2t_debug_log("[po] Displaying %d/%d commodities (filter: %s)",
        #filtered, #commodities, tostring(group_filter))

    if #filtered == 0 then
        if group_filter then
            cecho(string.format("\n<yellow>[po]<reset> No %s commodities found\n", group_filter))
        else
            cecho("\n<yellow>[po]<reset> No commodities found\n")
        end
        return
    end

    -- Build title
    local title = string.format("%s Economy", planet_name)
    if group_filter then
        title = string.format("%s Economy - %s", planet_name, group_filter)
    end

    f2t_render_table({
        title = title,
        max_width = COLS or 100,
        columns = {
            {
                header = "Commodity",
                field = "name",
                max_width = 15,
                truncate = true
            },
            {
                header = "Val",
                field = "value",
                align = "right",
                width = 4,
                format = "number"
            },
            {
                header = "Diff",
                field = "diff",
                align = "right",
                width = 5,
                formatter = function(val)
                    if val > 0 then
                        return string.format("+%d", val)
                    else
                        return tostring(val)
                    end
                end,
                color_fn = function(val)
                    if val > 0 then return "green"
                    elseif val < 0 then return "red"
                    else return nil end
                end
            },
            {
                header = "Spd",
                field = "spread",
                align = "right",
                width = 3,
                format = "number"
            },
            {
                header = "Ef%",
                field = "efficiency",
                align = "right",
                width = 4,
                format = "number",
                color_fn = function(val)
                    if val > 100 then return "green"
                    elseif val < 100 then return "red"
                    else return nil end
                end
            },
            {
                header = "Prd",
                field = "production",
                align = "right",
                width = 3,
                format = "number"
            },
            {
                header = "Cns",
                field = "consumption",
                align = "right",
                width = 3,
                format = "number"
            },
            {
                header = "Net",
                field = "net",
                align = "right",
                width = 4,
                format = "number",
                color_fn = function(val)
                    if val > 0 then return "green"
                    elseif val < 0 then return "red"
                    else return nil end
                end
            },
            {
                header = "Stock",
                field = "stock_current",
                align = "right",
                width = 5,
                format = "number",
                color_fn = function(val, row)
                    if val >= row.stock_max then return "green"
                    elseif val < row.stock_min then return "red"
                    else return nil end
                end
            },
            {
                header = "Min",
                field = "stock_min",
                align = "right",
                width = 5,
                format = "number"
            },
            {
                header = "Max",
                field = "stock_max",
                align = "right",
                width = 5,
                format = "number"
            }
        },
        data = filtered,
        footer = nil
    })

    -- Summary line
    cecho(string.format("<cyan>%d commodities<reset>", #filtered))
    if group_filter then
        cecho(string.format(" <dim_grey>(%s)<reset>", group_filter))
    end
    cecho("\n")

    -- Legend
    cecho("<dim_grey>Val=Value Diff=Val-Base Spd=Spread Ef%=Efficiency Prd=Production Cns=Consumption<reset>\n\n")
end

f2t_debug_log("[po] Economy formatter loaded")