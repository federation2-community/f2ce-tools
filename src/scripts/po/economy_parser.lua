-- Parser for exchange and production game output
-- Exchange output is one line per commodity, which the server wraps after
-- "Efficiency:" at narrow terminal widths:
--   Line 1: "  Alloys: value 137ig/ton  Spread: 20%   Stock: current 800/min 100/max 800  Efficiency:"
--   Line 2: "105%  Net: 44"
-- Production output is one line per commodity:
--   "  Alloys: production 45, consumption 1 (44), efficiency 105%"

local EXCHANGE_LINE = "^%s+(.-):%s+value%s+(%d+)ig/ton%s+Spread:%s+(%d+)%%%s+Stock:%s+current%s+"
    .. "(%-?%d+)/min%s+(%-?%d+)/max%s+(%-?%d+)%s+Efficiency:%s*(.*)$"
local EFFICIENCY_NET = "^(%d+)%%%s+Net:%s+(%-?%d+)"

--- Parse exchange buffer into structured data
--- @param buffer table Array of captured lines
--- @return table Array of {name, value, spread, stock_current, stock_min, stock_max, efficiency, net}
function f2t_po_parse_exchange_buffer(buffer)
    local results = {}
    local i = 1

    while i <= #buffer do
        local name, value, spread, stockCurrent, stockMin, stockMax, rest = buffer[i]:match(EXCHANGE_LINE)
        local consumed = 1
        local efficiency, net
        if name then
            efficiency, net = rest:match(EFFICIENCY_NET)
            if not efficiency and buffer[i + 1] then
                efficiency, net = buffer[i + 1]:match(EFFICIENCY_NET)
                if efficiency then consumed = 2 end
            end
        end

        if efficiency then
            table.insert(results, {
                name = name,
                value = tonumber(value),
                spread = tonumber(spread),
                stock_current = tonumber(stockCurrent),
                stock_min = tonumber(stockMin),
                stock_max = tonumber(stockMax),
                efficiency = tonumber(efficiency),
                net = tonumber(net)
            })
        elseif name then
            f2t_debug_log("[po] Exchange line for %s has no efficiency/net", name)
        end
        i = i + consumed
    end

    f2t_debug_log("[po] Parsed %d commodities from exchange data", #results)
    return results
end

--- Parse production buffer into a lookup table keyed by commodity name
--- @param buffer table Array of captured lines
--- @return table {["Alloys"] = {production=45, consumption=1}, ...}
function f2t_po_parse_production_buffer(buffer)
    local results = {}

    for _, line in ipairs(buffer) do
        local name, prod, cons =
            line:match("^%s+(.-):%s+production%s+(%d+),%s+consumption%s+(%d+)")

        if name then
            results[name] = {
                production = tonumber(prod),
                consumption = tonumber(cons)
            }
        end
    end

    f2t_debug_log("[po] Parsed %d commodities from production data",
        f2t_table_count_keys(results))
    return results
end

--- Merge exchange and production data with base prices from commodities.json
--- @param exchange_data table Array from f2t_po_parse_exchange_buffer
--- @param production_data table Table from f2t_po_parse_production_buffer
--- @return table Array of merged commodity records
function f2t_po_merge_economy_data(exchange_data, production_data)
    local merged = {}

    for _, ex in ipairs(exchange_data) do
        local record = {
            name = ex.name,
            value = ex.value,
            spread = ex.spread,
            stock_current = ex.stock_current,
            stock_min = ex.stock_min,
            stock_max = ex.stock_max,
            efficiency = ex.efficiency,
            net = ex.net,
            production = 0,
            consumption = 0,
            base_price = 0,
            diff = 0,
            group = "Unknown"
        }

        -- Merge production data
        local prod = production_data[ex.name]
        if prod then
            record.production = prod.production
            record.consumption = prod.consumption
        end

        -- Look up base price and group from commodities.json
        local info = f2t_po_get_commodity_info(ex.name)
        if info then
            record.base_price = info.base_price
            record.diff = ex.value - info.base_price
            record.group = info.group
        end

        table.insert(merged, record)
    end

    f2t_debug_log("[po] Merged %d commodity records", #merged)
    return merged
end

f2t_debug_log("[po] Economy parser loaded")