-- =============================================================================
-- INITIALIZE TRADING TABLE
-- =============================================================================

function ui_trading_init()
    -- Define columns for trading data
    local trading_columns = {
        {
            key = "system",
            label = "System",
            width = 10,
            align = "left",
            header_align = "center",
            sortable = true,
            format = function(value) return "<white>" .. value .. "<reset>" end,
            link = function(value) expandAlias("nav " .. value .. " space link") end,
            linkHint = "Jump to %s",
            sort_value = function(row) return row.system:lower() end
        },
        {
            key = "planet",
            label = "Planet",
            width = 10,
            align = "left",
            header_align = "center",
            sortable = true,
            format = function(value) return "<ansiCyan>" .. value .. "<reset>" end,
            link = function(value, row) 
                send("whereis " .. row.planet, false)
                expandAlias("nav " .. row.planet .. " exchange")
            end,
            linkHint = "Go to %s",
            sort_value = function(row) return row.planet:lower() end
        },
        {
            key = "action",
            label = "Action",
            width = 6,
            align = "center",
            header_align = "center",
            sortable = true,
            format = function(value, row)
                if value == "buying" then
                    return "<green>[SELL]<reset>"
                else
                    return "<yellow>[BUY]<reset>"
                end
            end,
            link = function(value, row)
                local cmd = (value == "buying") and "sell " or "buy "
                send(cmd .. (UI.trading.current_commodity or ""))
            end,
            sort_value = function(row) return row.action end
        },
        {
            key = "quantity",
            label = "Qty",
            width = 6,
            align = "right",
            header_align = "center",
            sortable = true,
            format = function(value) return "<white>" .. value .. "<reset>" end,
            sort_value = function(row) return row.quantity end
        },
        {
            key = "price",
            label = "Price",
            width = 8,
            align = "right",
            header_align = "center",
            sortable = true,
            default_sort = "asc",
            format = function(value, row)
                -- Dynamically calculate best prices from current table data
                local tbl = UI.tables["trading_data"]
                if not tbl then return "<white>" .. value .. "ig<reset>" end
                
                local best_buy = math.huge
                local best_sell = -1
                
                for _, r in ipairs(tbl.data) do
                    if r.action == "selling" and r.price < best_buy then
                        best_buy = r.price
                    elseif r.action == "buying" and r.price > best_sell then
                        best_sell = r.price
                    end
                end
                
                local price_str = value .. "ig"
                -- Highlight best prices
                if (row.action == "selling" and row.price == best_buy) then
                    return "<yellow><b>" .. price_str .. "</b><reset>"
                elseif (row.action == "buying" and row.price == best_sell) then
                    return "<green><b>" .. price_str .. "</b><reset>"
                else
                    return "<white>" .. price_str .. "<reset>"
                end
            end,
            sort_value = function(row) return row.price end
        }
    }
    
    local separators = {
        column = " ",
        header = nil,
        row = nil
    }
    
    -- Create the table
    ui_table_create("trading_data", UI.trading_window, trading_columns, separators)
end

-- =============================================================================
-- Trading Trigger Function
-- =============================================================================

-- Handler for trading data lines
function ui_on_trading_line(system, planet, action, quantity, price)
    local trade_data = {
        system = system,
        planet = planet,
        action = action,
        quantity = tonumber(quantity),
        price = tonumber(price)
    }
    
    -- If in profit search mode, store for processing
    if UI.trading.profit_search and UI.trading.profit_search.active then
        UI.trading.data = UI.trading.data or {}
        table.insert(UI.trading.data, trade_data)
    else
        -- Add to table and render
        local tbl = UI.tables["trading_data"]
        if tbl then
            table.insert(tbl.data, trade_data)
            ui_table_render("trading_data")
        end
    end
end

-- =============================================================================
-- TRADING UI ELEMENTS
-- =============================================================================

function ui_trading()
    -- Initialize the trading table system
    ui_trading_init()
    
    ------------- Trading Commodity Dropdown ---------------
    UI.trading_drop_down_button = Geyser.Label:new(
        {
            name    = "UI.trading_drop_down_button",
            message = "<center>Select Commodity ▼</center>",
        },
        UI.trading_button_bar
    )
    UI.trading_drop_down_button:setStyleSheet(UI.style.button_css)
    UI.trading_drop_down_button:setClickCallback("ui_show_trading_drop_down")

    UI.check_price_button = Geyser.Label:new(
        {
            name    = "UI.check_price_button",
            width   = "30%",
            height  = "100%",
            message = "<center>CP</center>",
        },
        UI.trading_button_bar
    )
    UI.check_price_button:setStyleSheet(UI.style.button_css)
    UI.check_price_button:setClickCallback("ui_check_price")

    UI.cartel_toggle_button = Geyser.Label:new(
        {
            name    = "UI.cartel_toggle_button",
            message = "<center>☑ Cartel</center>",
        },
        UI.trading_button_bar
    )
    UI.cartel_toggle_button:setStyleSheet(UI.style.button_css)
    UI.cartel_toggle_button:setClickCallback("ui_toggle_cartel")

    -- Initialize trading state
    UI.trading = {
        selected_commodity = nil,
        use_cartel         = true,
        profit_search      = {
            active                = false,
            commodities_to_search = {},
            current_index         = 1,
            results               = {},
            best_commodity        = nil,
            best_profit           = -math.huge,
        }
    }

    -- Best Profit button
    UI.best_profit_button = Geyser.Label:new(
        {
            name    = "UI.best_profit_button",
            message = "<center>Find Best</center>",
        },
        UI.trading_button_bar
    )
    UI.best_profit_button:setStyleSheet(UI.style.button_css)
    UI.best_profit_button:setClickCallback("ui_find_best_profit")
end

-- Responsible for formatting and displaying the commodity dropdown
function ui_show_trading_drop_down()
    if UI.commodity_popup then
        UI.commodity_popup:hide()
        UI.commodity_popup = nil

        return
    end

    UI.commodity_popup = Geyser.Container:new(
        {
            name   = "UI.commodity_popup",
            x      = "10%",
            y      = 30,
            width  = 220,
            height = 400,
        },
        UI.trading_container
    )

    local commodityBox = Geyser.ScrollBox:new(
        {
            name            = "commodityBox",
            x               = 0,
            y               = 0,
            width           = "100%",
            height          = "100%",
            fontSize        = 10,
            backgroundColor = "black",
        },
        UI.commodity_popup
    )

    local row_height = 24
    local y_offset   = 0
    local commods    = {}

    local commodity_list = ui_commodities_load()

    for i, item in ipairs(commodity_list) do
        local labelName = "commod" .. i

        commods[i] = Geyser.Label:new(
            {
                name    = labelName,
                x       = 0,
                y       = y_offset,
                width   = "100%",
                height  = row_height,
                message = "<center>" .. item.name .. " (" .. item.basePrice .. ")</center>",
            },
            commodityBox
        )

        commods[i]:setStyleSheet(UI.style.button_css)

        commods[i]:setClickCallback(
            function()
                UI.trading.selected_commodity = item.name
                UI.trading_drop_down_button:echo("<center>" .. item.name .. " ▼</center>")
                UI.commodity_popup:hide()
                UI.commodity_popup = nil
            end
        )

        y_offset = y_offset + row_height
    end

    UI.commodity_popup:show()
    UI.commodity_popup:raise()
end

function ui_toggle_cartel()
    UI.trading.use_cartel = not UI.trading.use_cartel

    local checkbox = UI.trading.use_cartel and "☑" or "☐"

    UI.cartel_toggle_button:echo("<center>" .. checkbox .. " Cartel</center>")
end

function ui_check_price()
    if not UI.trading.selected_commodity then
        cecho("\n<red>Please select a commodity first!\n")
        return
    end

    local cmd = "c price " .. UI.trading.selected_commodity:lower()

    if UI.trading.use_cartel then
        UI.trading = UI.trading or {}
        UI.trading.current_commodity = UI.trading.selected_commodity:lower()
        
        -- Clear the table instead of manual window clear
        ui_table_clear("trading_data")
        
        cmd = cmd .. " cartel"
    end

    send(cmd, false)
end

-- =============================================================================
-- FIND BEST PROFIT FUNCTIONS
-- =============================================================================

function ui_find_best_profit()
    -- Clear previous results
    UI.trading.profit_search = {
        active                = true,
        commodities_to_search = {},
        current_index         = 1,
        results               = {},
        best_commodity        = nil,
        best_profit           = -math.huge,
        total_count           = 0
    }

    -- Build list of all commodities
    for _, commodity in ipairs(ui_commodities_load()) do
        table.insert(UI.trading.profit_search.commodities_to_search, commodity.name:lower())
    end

    table.sort(UI.trading.profit_search.commodities_to_search, function(a, b) return a < b end)

    UI.trading.profit_search.total_count = #UI.trading.profit_search.commodities_to_search

    UI.trading_window:clear()
    UI.trading_window:cecho("<yellow>Searching " .. #UI.trading.profit_search.commodities_to_search .. " commodities for best profit...\n\n")

     -- Create progress bar anchored to bottom of main window, between left and right frames
    if not UI.profit_progress_bar then
        UI.profit_progress_bar = Geyser.Gauge:new(
            {
                name   = "UI.profit_progress_bar",
                x      = UI.trading_button_bar:get_x(),
                y      = UI.trading_button_bar:get_y(),
                width  = UI.trading_button_bar:get_width(),
                height = UI.trading_button_bar:get_height()
            }
        )

        UI.profit_progress_bar:setFgColor("red")
        UI.profit_progress_bar:setColor(0, 0, 0)
    end

    UI.profit_progress_bar:setValue(1, UI.trading.profit_search.total_count,"Scanning commodities... 1/" .. UI.trading.profit_search.total_count)

    UI.trading_button_bar:lower()
    UI.profit_progress_bar:show()
    UI.profit_progress_bar:raise()

    -- Start searching
    ui_search_next_commodity()
end

function ui_search_next_commodity()
    if not UI.trading.profit_search.active then return end

    local commodity = UI.trading.profit_search.commodities_to_search[UI.trading.profit_search.current_index]

    if not commodity then
        -- Done searching, display results
        ui_display_best_profit()
        return
    end

    -- Clear data for this search
    UI.trading.data = {}
    UI.trading.current_commodity = commodity

    -- Send the search command
    send("c price " .. commodity:lower() .. " cartel", false)
end

function ui_process_profit_search_results()
    -- Calculate profit for current commodity
    local best_buy  = math.huge
    local best_sell = -1

    for _, item in ipairs(UI.trading.data) do
        if item.action == "selling" then
            if item.price < best_buy then best_buy = item.price end
        elseif item.action == "buying" then
            if item.price > best_sell then best_sell = item.price end
        end
    end

    local profit = (best_buy ~= math.huge and best_sell ~= -1) and (best_sell - best_buy) or -math.huge

    local commodity = UI.trading.current_commodity

    -- Store result
    table.insert(
        UI.trading.profit_search.results,
        {
            commodity = commodity,
            profit    = profit,
            best_buy  = best_buy,
            best_sell = best_sell
        }
    )

    -- Update if this is the best
    if profit > UI.trading.profit_search.best_profit then
        UI.trading.profit_search.best_profit    = profit
        UI.trading.profit_search.best_commodity = commodity
    end

    -- Update progress bar BEFORE incrementing current_index
    if UI.profit_progress_bar then
        local current = UI.trading.profit_search.current_index
        local total   = UI.trading.profit_search.total_count

        UI.profit_progress_bar:setValue(current, total,"Scanning commodities... " .. current .. "/" .. total)
    end

    -- Update display
    UI.trading_window:cecho(string.format(
        "<%s>%-20s: %+4dig/ton<reset>\n",
        profit > 0 and "green" or "red",
        commodity,
        profit
    ))

    -- Move to next
    UI.trading.profit_search.current_index = UI.trading.profit_search.current_index + 1

    -- Small delay before next search to avoid flooding
    tempTimer(0.5, function() ui_search_next_commodity() end)
end

function ui_display_best_profit()
    UI.trading.profit_search.active = false
    UI.profit_progress_bar:hide()

    -- Sort results by profit
    table.sort(UI.trading.profit_search.results, function(a, b)
        return a.profit > b.profit
    end)

    UI.trading_window:cecho("\n<white>==========================================\n")
    UI.trading_window:cecho("<yellow>BEST PROFIT: <reset>")

    if UI.trading.profit_search.best_commodity then
        local best = UI.trading.profit_search.results[1]

        UI.trading_window:cechoLink(
            "<green><b>" .. best.commodity .. "</b><reset>",
            function()
                UI.trading.selected_commodity = best.commodity
                UI.trading_drop_down_button:echo("<center>" .. best.commodity .. " ▼</center>")
                send("c price " .. best.commodity:lower() .. " cartel")
            end,
            "Search " .. best.commodity,
            true
        )
        UI.trading_window:cecho(string.format(
            " | <green>%dig/ton profit<reset>\n",
            best.profit
        ))
        UI.trading_window:cecho(string.format(
            "Buy at %dig, Sell at %dig\n",
            best.best_buy,
            best.best_sell
        ))

        -- Auto-select it
        UI.trading.selected_commodity = best.commodity
        UI.trading_drop_down_button:echo("<center>" .. best.commodity .. " ▼</center>")
    else
        UI.trading_window:cecho("<red>No profitable commodities found<reset>\n")
    end

    UI.trading_window:cecho("<white>==========================================\n\n")
    UI.trading_window:cecho("<dim_grey>Click commodity name to view full cartel prices<reset>\n")
end
