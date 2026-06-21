-- Commodity group resolver and base price lookup
-- Loads groups and base prices from commodities.json (cached)

local po_commodity_cache = nil

local function load_data()
    if po_commodity_cache then
        return po_commodity_cache
    end

    local file_path = getMudletHomeDir() .. "/fed2-tools/commodities.json"
    local file = io.open(file_path, "r")

    if not file then
        f2t_debug_log("[po] ERROR: Could not open commodities.json")
        return nil
    end

    local json_string = file:read("*all")
    file:close()

    local data = yajl.to_value(json_string)
    if not data or not data.groups then
        f2t_debug_log("[po] ERROR: Invalid commodities.json format")
        return nil
    end

    local by_name = {}
    local group_names = {}
    local valid_groups = {}

    for _, group in ipairs(data.groups) do
        -- Map group full name (lowercase) to canonical
        group_names[string.lower(group.name)] = group.name

        -- Map group short name if available
        if group.shortName then
            group_names[string.lower(group.shortName)] = group.name
        end

        -- Build display string for help text
        if group.shortName then
            table.insert(valid_groups, string.format("%s (%s)", string.lower(group.name), group.shortName))
        else
            table.insert(valid_groups, string.lower(group.name))
        end

        -- Map each commodity to its group and base price
        for _, commodity in ipairs(group.commodities) do
            by_name[string.lower(commodity.name)] = {
                name = commodity.name,
                group = group.name,
                base_price = commodity.basePrice
            }
        end
    end

    po_commodity_cache = {
        by_name = by_name,
        group_names = group_names,
        valid_groups = valid_groups
    }

    f2t_debug_log("[po] Loaded %d commodities across %d groups",
        f2t_table_count_keys(by_name), #data.groups)

    return po_commodity_cache
end

--- Resolve a group input to its canonical name
--- @param input string Group name or short name (case-insensitive)
--- @return string|nil Canonical group name, or nil if not a valid group
function f2t_po_resolve_group(input)
    if not input or input == "" then
        return nil
    end

    local cache = load_data()
    if not cache then return nil end

    return cache.group_names[string.lower(input)]
end

--- Get commodity info by name (base price and group)
--- @param commodity_name string Commodity name from game output
--- @return table|nil {name, group, base_price} or nil
function f2t_po_get_commodity_info(commodity_name)
    if not commodity_name or commodity_name == "" then
        return nil
    end

    local cache = load_data()
    if not cache then return nil end

    return cache.by_name[string.lower(commodity_name)]
end

--- Get list of valid group names for help text
--- @return table Array of display strings like "agricultural (agri)"
function f2t_po_get_valid_groups()
    local cache = load_data()
    if not cache then return {} end

    return cache.valid_groups
end

f2t_debug_log("[po] Commodity groups resolver loaded")