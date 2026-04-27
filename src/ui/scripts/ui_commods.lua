-- =============================================================================
-- Commodities - Using UI Table System
-- =============================================================================

-- =============================================================================
-- INITIALIZE COMMODITIES TABLE
-- =============================================================================

function ui_commodities_init()
    -- Define columns for commodities
    local commodity_columns = {
        {
            key          = "name",
            label        = "Commodity",
            width        = 40,
            align        = "left",
            sortable     = true,
            default_sort = "asc",
            format       = function(value, row)
                if row.shortName then
                    return string.format("%s (%s)", value, row.shortName)
                else
                    return value
                end
            end
        },
        {
            key      = "basePrice",
            label    = "Price",
            width    = 6,
            align    = "right",
            sortable = true,
            format   = function(value, row) return tostring(value) end
        }
    }

        -- Optional: Configure separators
    local separators = {
        column = " ",    -- Single space between columns (default)
        header = "-",    
        row    = nil     -- No row separators
    }

    -- Create the table
    ui_table_create("commodities", UI.commodities_window, commodity_columns, separators)
end

-- =============================================================================
-- DATA LOADING
-- =============================================================================

function ui_commodities_load()
    -- Load commodity data from JSON
    local filePath = getMudletHomeDir() .. "/fed2-tools/shared/commodities.json"
    local file = io.open(filePath, "r")
    
    if not file then
        f2t_debug_log("[ui] ERROR: Could not open commodities.json")
        return
    end
    
    local jsonString = file:read("*all")
    file:close()
    
    local data = yajl.to_value(jsonString)
    if not data or not data.groups then
        f2t_debug_log("[ui] ERROR: Invalid commodities.json format")
        return
    end
    
    -- Extract all commodities into a flat list
    local commodities = {}
    for _, group in ipairs(data.groups) do
        for _, commodity in ipairs(group.commodities) do
            table.insert(commodities, {
                name = commodity.name,
                shortName = commodity.shortName,
                basePrice = commodity.basePrice
            })
        end
    end

    table.sort(commodities, function(a, b) return a.name < b.name end)

    return commodities
end

function ui_commodities()
    ui_commodities_init()

    if not UI.commodities_window then
        f2t_debug_log("[ui] commodities_window not available")
        return
    end
    
    local commodityData = ui_commodities_load()
    
    if not commodityData then
        f2t_debug_log("[ui] Failed to load commodity data")
        return
    end
    
    -- Set data in table (this will automatically render)
    ui_table_set_data("commodities", commodityData)
    
    f2t_debug_log("[ui] Displayed %d commodities", #commodityData)
end