-- Per-profile progress only: never saves command authority, cargo or a route.
-- Two verified copies outside the package survive reinstall and interrupted
-- writes. Both must be written before a new commodity attempt may travel/buy.
local function path(slot)
    return getMudletHomeDir() .. "/f2ce-hauling-rotation-v1-" .. slot .. ".json"
end

local function valid(data)
    if type(data) ~= "table" or data.schema ~= 1 or type(data.done) ~= "table" then return false end
    for _, key in ipairs({"revision", "round"}) do
        local n = data[key]
        if type(n) ~= "number" or n < 1 or n > 9007199254740000 or n ~= math.floor(n) then return false end
    end
    local count = 0
    for name, done in pairs(data.done) do
        count = count + 1
        if count > 1000 or type(name) ~= "string" or #name > 80
            or not name:match("^[a-z][a-z0-9]*$") or done ~= true then return false end
    end
    return true
end

local function read(slot)
    local file, err, code = io.open(path(slot), "rb")
    if not file then return nil, code == 2 and "missing" or tostring(err) end
    local bytes = file:read(131073); file:close()
    if not bytes or #bytes > 131072 then return nil, "invalid rotation size" end
    local ok, data = pcall(yajl.to_value, bytes)
    if not ok or not valid(data) then return nil, "invalid rotation data" end
    return data
end

local function load()
    local a, ae = read("a")
    local b, be = read("b")
    if not a and not b then
        if ae == "missing" and be == "missing" then return {schema=1, revision=1, round=1, done={}} end
        return nil, "Cannot read saved commodity rotation; restore a valid checkpoint before hauling."
    end
    if a and b and a.revision == b.revision then
        if a.round ~= b.round then return nil, "Conflicting commodity rotation copies" end
        for name in pairs(a.done) do if not b.done[name] then return nil, "Conflicting commodity rotation copies" end end
        for name in pairs(b.done) do if not a.done[name] then return nil, "Conflicting commodity rotation copies" end end
    end
    return a and (not b or a.revision >= b.revision) and a or b
end

local function save(data)
    data.revision = data.revision + 1
    local ok, bytes = pcall(yajl.to_string, data)
    if not ok or not valid(data) then return nil, "Could not encode commodity rotation" end
    -- Never rotate/delete the previous checkpoint to replace a Windows file.
    -- A short/failed write leaves the other copy recoverable. No orders follow
    -- until both copies have closed and their bytes have been read back.
    local first = data.revision % 2 == 0 and "a" or "b"
    for _, slot in ipairs({first, first == "a" and "b" or "a"}) do
        local file, err = io.open(path(slot), "wb")
        if not file then return nil, "Could not save commodity rotation: " .. tostring(err) end
        local written = file:write(bytes)
        local closed = file:close()
        if not written or not closed then return nil, "Commodity rotation write failed" end
        file = io.open(path(slot), "rb")
        if not file then return nil, "Could not verify commodity rotation" end
        local check = file:read("*a"); file:close()
        if check ~= bytes then return nil, "Commodity rotation verification failed" end
    end
    return true
end

function f2t_hauling_rotation_catalog()
    if F2T_HAULING_STATE.rotation == "top_base_21" then
        return f2t_get_highest_base_commodities(21)
    end
    return f2t_get_all_commodities()
end

-- Premium hauling already knows its fixed base-price catalog. Queue its saved
-- unattempted members without polling every commodity up front; each member is
-- first priced when it becomes current. Exclusions still count as reviewed.
function f2t_hauling_rotation_queue_catalog(excluded)
    excluded = type(excluded) == "table" and excluded or {}
    local data, err = load()
    if not data then return nil, err end
    local catalog, catalog_error = f2t_hauling_rotation_catalog()
    if not catalog then return nil, catalog_error end
    if #catalog == 0 then return nil, "Commodity catalog unavailable" end
    local function queue()
        local rows = {}
        for _, canonical in ipairs(catalog) do
            local name = canonical:lower()
            if excluded[name] then data.done[name] = true
            elseif not data.done[name] then rows[#rows+1] = {commodity=canonical} end
        end
        return rows
    end
    local rows = queue()
    if #rows == 0 then
        data.round = data.round + 1; data.done = {}
        rows = queue()
    end
    local saved, reason = save(data)
    if not saved then return nil, reason end
    return rows, data.round, #catalog
end

-- Only a complete selected catalog review can roll the round over. Unavailable and
-- excluded commodities count as reviewed; they never force an unsafe purchase.
function f2t_hauling_rotation_queue(results, excluded)
    if type(results) ~= "table" then return nil, "Missing commodity review" end
    local data, err = load()
    if not data then return nil, err end
    local catalog, catalog_error = f2t_hauling_rotation_catalog()
    if not catalog then return nil, catalog_error end
    if #catalog == 0 then return nil, "Commodity catalog unavailable" end
    local by_name, eligible = {}, {}
    for _, row in ipairs(results) do
        if type(row) ~= "table" then return nil, "Invalid commodity review" end
        local name = type(row.commodity) == "string" and row.commodity:lower()
        if not name or by_name[name] or type(row.top_buy) ~= "table" or type(row.top_sell) ~= "table" then
            return nil, "Incomplete or duplicate commodity review"
        end
        by_name[name] = row
    end
    for _, name in ipairs(catalog) do
        name = name:lower()
        local row = by_name[name]
        if not row then return nil, "Missing commodity review: " .. name end
        local profit = tonumber(row.profit)
        eligible[name] = not excluded[name] and profit and profit > 0 and profit < math.huge
            and #row.top_buy > 0 and #row.top_sell > 0
    end
    local function queue()
        local rows = {}
        for _, name in ipairs(catalog) do
            name = name:lower()
            if not eligible[name] then data.done[name] = true
            elseif not data.done[name] then rows[#rows+1] = by_name[name] end
        end
        return rows
    end
    local rows = queue()
    -- All current candidates have had a turn and every other commodity was
    -- reviewed in this complete scan. Start the next round, with fresh prices.
    if #rows == 0 then
        data.round = data.round + 1; data.done = {}
        rows = queue()
    end
    local saved, reason = save(data)
    if not saved then return nil, reason end
    return rows, data.round, #catalog
end

function f2t_hauling_rotation_claim(commodity)
    local data, err = load()
    if not data then return nil, err end
    local name = tostring(commodity):lower()
    if data.done[name] then return nil, "Commodity already attempted in this rotation: " .. name end
    data.done[name] = true
    return save(data)
end

function f2t_hauling_rotation_status()
    local data, err = load()
    if not data then cecho("\n<red>[hauling]<reset> " .. err .. "\n"); return end
    local catalog, catalog_error = f2t_hauling_rotation_catalog()
    if not catalog then cecho("\n<red>[hauling]<reset> " .. catalog_error .. "\n"); return end
    local count = 0
    for _, name in ipairs(catalog) do if data.done[name:lower()] then count = count + 1 end end
    cecho(string.format("\n<green>[hauling]<reset> Commodity rotation %d: %d/%d reviewed or attempted. " ..
        "Saved per profile; one load per attempt. Loading never starts automation.\n", data.round, count, #catalog))
end
