-- Display commodity price data using f2t_render_table
-- Provides formatted output for price analysis

-- Display price table for a single commodity
function f2t_price_display_commodity(commodity, analysis)
    cecho(string.format("\n<green>[commodities]<reset> Price Analysis: <cyan>%s<reset>\n", commodity))

    -- Display summary
    if #analysis.top_sell > 0 and #analysis.top_buy > 0 then
        cecho(string.format(
            "<dim_grey>Avg Buy: <white>%dig/ton<reset>  <dim_grey>Avg Sell: <white>%dig/ton<reset>  " ..
            "<dim_grey>Profit: <white>%dig/ton<reset>  <dim_grey>Margin: <white>%.1f%%<reset>\n",
            analysis.avg_sell_price,
            analysis.avg_buy_price,
            analysis.profit,
            analysis.margin))
    end

    -- Display top selling locations (where we buy)
    if #analysis.top_sell > 0 then
        cecho("\n<yellow>Top Places to Buy<reset> (lowest prices)\n")
        f2t_render_table({
            columns = {
                {header = "Location", field = "location", max_width = 40},
                {header = "Price", field = "price", align = "right", format = "number", suffix = "ig/ton"},
                {
                    header = "Qty",
                    field = "quantity",
                    align = "right",
                    format = "compact",
                    color_fn = function(val)
                        if val >= 15000 then
                            return "green"  -- High quantity, stable pricing
                        elseif val >= 5000 then
                            return "yellow"
                        else
                            return "white"
                        end
                    end
                }
            },
            data = analysis.top_sell
        })
    else
        cecho("\n<red>No exchanges currently selling this commodity<reset>\n")
    end

    -- Display top buying locations (where we sell)
    if #analysis.top_buy > 0 then
        cecho("\n<yellow>Top Places to Sell<reset> (highest prices)\n")
        f2t_render_table({
            columns = {
                {header = "Location", field = "location", max_width = 40},
                {header = "Price", field = "price", align = "right", format = "number", suffix = "ig/ton"}
            },
            data = analysis.top_buy
        })
    else
        cecho("\n<red>No exchanges currently buying this commodity<reset>\n")
    end

    -- Display profit summary
    if analysis.profit > 0 then
        local profit_per_lot = analysis.profit * 75
        cecho(string.format(
            "\n<green>Projected Profit:<reset> <white>%dig/ton<reset> " ..
            "(<white>%dig<reset> per 75-ton lot, <white>%.1f%%<reset> margin)\n",
            analysis.profit, profit_per_lot, analysis.margin))
    elseif analysis.profit == 0 then
        cecho("\n<yellow>No profit opportunity detected<reset>\n")
    else
        cecho(string.format("\n<red>Warning:<reset> Negative profit (<white>%dig/ton<reset>)\n", analysis.profit))
    end
end

-- Display summary table for all commodities
function f2t_price_display_all(all_analysis)
    cecho("\n<green>[commodities]<reset> Commodity Profit Analysis\n")
    cecho("<dim_grey>Comparing average prices across top exchanges<reset>\n\n")

    -- Filter out commodities with no trading data
    local tradeable = {}
    for _, analysis in ipairs(all_analysis) do
        if #analysis.top_buy > 0 or #analysis.top_sell > 0 then
            table.insert(tradeable, analysis)
        end
    end

    if #tradeable == 0 then
        cecho("<red>No commodity price data available<reset>\n")
        return
    end

    -- Sort by profit (descending)
    table.sort(tradeable, function(a, b)
        return a.profit > b.profit
    end)

    -- Add computed profit_per_lot field to each row
    for _, analysis in ipairs(tradeable) do
        analysis.profit_per_lot = analysis.profit * 75
    end

    f2t_render_table({
        columns = {
            {header = "Commodity", field = "commodity", max_width = 20},
            {
                header = "Avg Buy",
                field = "avg_sell_price",
                align = "right",
                format = "number",
                suffix = "ig",
                color_fn = function(val)
                    return val > 0 and "white" or "dim_grey"
                end
            },
            {
                header = "Avg Sell",
                field = "avg_buy_price",
                align = "right",
                format = "number",
                suffix = "ig",
                color_fn = function(val)
                    return val > 0 and "white" or "dim_grey"
                end
            },
            {
                header = "Profit/ton",
                field = "profit",
                align = "right",
                format = "number",
                suffix = "ig",
                color_fn = function(val)
                    if val > 100 then
                        return "green"
                    elseif val > 50 then
                        return "yellow"
                    elseif val > 0 then
                        return "white"
                    else
                        return "red"
                    end
                end
            },
            {
                header = "Margin",
                field = "margin",
                align = "right",
                width = 7,
                formatter = function(val)
                    return string.format("%.1f%%", val)
                end,
                color_fn = function(val)
                    if val >= 40 then
                        return "green"
                    elseif val >= 20 then
                        return "yellow"
                    elseif val > 0 then
                        return "white"
                    else
                        return "red"
                    end
                end
            },
            {
                header = "Profit/lot",
                field = "profit_per_lot",
                align = "right",
                format = "number",
                suffix = "ig",
                color_fn = function(val)
                    if val > 7500 then
                        return "green"
                    elseif val > 3750 then
                        return "yellow"
                    elseif val > 0 then
                        return "white"
                    else
                        return "red"
                    end
                end
            }
        },
        data = tradeable
    })

    cecho(string.format("\n<dim_grey>Showing %d commodities sorted by profit<reset>\n", #tradeable))
end

f2t_debug_log("[commodities] Price display loaded")