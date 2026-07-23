-- Price all commodities functionality
-- Iterates through all commodities and displays profit analysis

-- Load commodities list from JSON
local function load_commodities_list()
    -- Note: @PKGNAME@ substitution only works in XML, use actual package name
    local file_path = string.format("%s/f2ce-tools/commodities.json", getMudletHomeDir())

    local file, err = io.open(file_path, "r")
    if not file then
        cecho(string.format("\n<red>[commodities]<reset> Error loading commodities list: %s\n", err))
        return nil
    end

    local json_string = file:read("*all")
    file:close()

    local data = yajl.to_value(json_string)
    if not data or not data.groups then
        cecho("\n<red>[commodities]<reset> Error parsing commodities.json\n")
        return nil
    end

    -- Extract all commodity names
    local commodities = {}
    for _, group in ipairs(data.groups) do
        for _, commodity in ipairs(group.commodities) do
            table.insert(commodities, string.lower(commodity.name))
        end
    end

    return commodities
end

-- State for "price all" operation
local price_all_state = {
    active = false,
    commodities = {},
    current_index = 0,
    results = {},
    commodity_data = {},
    completion_callback = nil
}

-- Callback for processing individual commodity results during "price all"
local function price_all_callback(commodity, parsed_data, analysis)
    f2t_debug_log(string.format("[commodities] price all: processed %s", commodity))

    -- Store the results
    price_all_state.commodity_data[commodity] = parsed_data
    table.insert(price_all_state.results, analysis)

    -- Check if we're done
    if price_all_state.current_index >= #price_all_state.commodities then
        -- All commodities processed
        f2t_debug_log("[commodities] price all: complete")

        -- Call completion callback with results
        if price_all_state.completion_callback then
            price_all_state.completion_callback(price_all_state.results)
        end

        -- Reset state
        price_all_state.active = false
        price_all_state.commodities = {}
        price_all_state.current_index = 0
        price_all_state.results = {}
        price_all_state.commodity_data = {}
        price_all_state.completion_callback = nil
    else
        -- Process next commodity
        tempTimer(0.5, function()
            price_all_check_next()
        end)
    end
end

-- Check next commodity in the list
function price_all_check_next()
    if not price_all_state.active then
        return
    end

    price_all_state.current_index = price_all_state.current_index + 1
    local commodity = price_all_state.commodities[price_all_state.current_index]

    if not commodity then
        f2t_debug_log("[commodities] price all: no more commodities")
        return
    end

    f2t_debug_log(string.format("[commodities] price all: checking %s (%d/%d)",
        commodity, price_all_state.current_index, #price_all_state.commodities))

    -- Check this commodity with callback
    f2t_price_check_commodity(commodity, price_all_callback)
end

-- Get price data for all commodities (programmatic use)
-- callback: function(results) called when complete with array of analysis data
function f2t_price_get_all_data(callback)
    -- Check prerequisites before starting
    if not f2t_check_rank_requirement("Merchant", "Price checking") then return false end
    if not f2t_check_tool_requirement("remote-access-cert", "Price checking", "Remote Price Check Service") then return false end

    if price_all_state.active then
        cecho("\n<yellow>[commodities]<reset> Price all operation already in progress\n")
        return false
    end

    -- Load commodities list
    local commodities = load_commodities_list()
    if not commodities then
        return false
    end

    -- Initialize state
    price_all_state.active = true
    price_all_state.commodities = commodities
    price_all_state.current_index = 0
    price_all_state.results = {}
    price_all_state.commodity_data = {}
    price_all_state.completion_callback = callback

    -- Start processing
    price_all_check_next()
    return true
end

-- Display all commodities with price analysis (user-facing)
function f2t_price_show_all()
    -- f2t_price_get_all_data checks prerequisites and returns false on failure
    local started = f2t_price_get_all_data(function(results)
        f2t_price_display_all(results)
    end)

    if started then
        cecho(string.format("\n<green>[commodities]<reset> Checking prices for all commodities...\n"))
        cecho("<dim_grey>This may take a moment...<reset>\n")
    end
end

-- Cancel any active price all operation
function f2t_price_cancel_all()
    if price_all_state.active then
        f2t_debug_log("[commodities] Cancelling price all operation")
        price_all_state.active = false
        price_all_state.commodities = {}
        price_all_state.current_index = 0
        price_all_state.results = {}
        price_all_state.commodity_data = {}
        price_all_state.completion_callback = nil
        return true
    end
    return false
end

f2t_debug_log("[commodities] Price all functionality loaded")