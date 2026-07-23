-- Parse commodity price output from Federation 2 Community Edition
-- Extracts exchange data from "check price <commodity> cartel" output

-- Parse a single price line
-- Example: "Coffee: Affogato is selling 2780 tons at 643ig/ton"
-- Example: "Coffee: Affogato is buying 75 tons at 526ig/ton"
-- Example: "Updog: Cowhide is not currently trading in this commodity"
local function parse_price_line(line)
    -- Check for "not currently trading" message
    if line:match("is not currently trading") then
        local system, planet = line:match("^([^:]+):%s+(.+)%s+is not currently trading")
        if system and planet then
            return {
                system = system,
                planet = planet,
                trading = false
            }
        end
        return nil
    end

    -- Parse regular price line
    -- Format: "System: Planet is buying/selling QUANTITY tons at PRICEig/ton"
    -- Use non-greedy match (.-) for planet name to avoid over-capturing
    -- Note: Lua patterns don't support | alternation, so we try both patterns
    local system, planet, quantity, price

    -- Try "buying" pattern
    system, planet, quantity, price = line:match("^([^:]+):%s+(.-)%s+is%s+buying%s+(%d+)%s+tons%s+at%s+(%d+)ig/ton")
    if system then
        return {
            system = system,
            planet = planet,
            action = "buying",
            quantity = tonumber(quantity),
            price = tonumber(price),
            trading = true
        }
    end

    -- Try "selling" pattern
    system, planet, quantity, price = line:match("^([^:]+):%s+(.-)%s+is%s+selling%s+(%d+)%s+tons%s+at%s+(%d+)ig/ton")
    if system then
        return {
            system = system,
            planet = planet,
            action = "selling",
            quantity = tonumber(quantity),
            price = tonumber(price),
            trading = true
        }
    end

    return nil
end

-- Parse all captured price data
-- Returns: {buy = {}, sell = {}} where each contains sorted arrays of exchange data
function f2t_price_parse_data(raw_lines)
    local buy_exchanges = {}
    local sell_exchanges = {}

    for i, line in ipairs(raw_lines) do
        -- Trim whitespace from captured lines
        line = line:match("^%s*(.-)%s*$")

        f2t_debug_log("[commodities] Parsing line %d: '%s'", i, line:sub(1, 60))
        local data = parse_price_line(line)

        if not data then
            f2t_debug_log("[commodities] Failed to parse line %d", i)
        end

        if data and data.trading then
            local exchange = {
                system = data.system,
                planet = data.planet,
                location = string.format("%s: %s", data.system, data.planet),
                quantity = data.quantity,
                price = data.price
            }

            if data.action == "buying" then
                table.insert(buy_exchanges, exchange)
            elseif data.action == "selling" then
                table.insert(sell_exchanges, exchange)
            end
        end
    end

    -- Sort buy exchanges by price (highest first - we want to sell where they buy highest)
    table.sort(buy_exchanges, function(a, b)
        return a.price > b.price
    end)

    -- Sort sell exchanges by price (lowest first - we want to buy where they sell lowest)
    -- Secondary sort by quantity (highest first - prefer stable prices)
    table.sort(sell_exchanges, function(a, b)
        if a.price == b.price then
            return a.quantity > b.quantity
        end
        return a.price < b.price
    end)

    return {
        buy = buy_exchanges,
        sell = sell_exchanges
    }
end

-- Get top N exchanges from buy/sell data
function f2t_price_get_top_exchanges(parsed_data, count)
    count = count or f2t_settings_get("commodities", "results_count")

    local top_buy = {}
    local top_sell = {}

    -- Get top buy locations (where we can sell for highest price)
    for i = 1, math.min(count, #parsed_data.buy) do
        table.insert(top_buy, parsed_data.buy[i])
    end

    -- Get top sell locations (where we can buy for lowest price)
    for i = 1, math.min(count, #parsed_data.sell) do
        table.insert(top_sell, parsed_data.sell[i])
    end

    return {
        buy = top_buy,
        sell = top_sell
    }
end

-- Calculate average price from top exchanges
function f2t_price_calculate_average(exchanges)
    if #exchanges == 0 then
        return 0
    end

    local total = 0
    for _, exchange in ipairs(exchanges) do
        total = total + exchange.price
    end

    return math.floor(total / #exchanges)
end

f2t_debug_log("[commodities] Price parser loaded")