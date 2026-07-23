-- f2ce-tools factory — output parser
--
-- Converts a captured "display factory N" block (capture_buffer) into a single
-- structured factory record.  Field patterns match Fed2's facility display:
-- the trailing "ig" on money values is the in-game currency suffix.
--
-- The legacy version logged every field probe on every line; that per-line
-- debug spam has been removed in favour of one summary log per factory.

function f2t_factory_parse_buffer()
    local buffer  = f2t_factory.capture_buffer
    local factory = {
        number           = f2t_factory.current_number,
        commodity        = "",
        location         = "",
        status           = "",
        working_capital  = 0,
        income           = 0,
        expenditure      = 0,
        profit           = 0,
        efficiency       = 0,
        efficiency_max   = 100,
        wages            = 0,
        workers_required = 0,
        workers_hired    = 0,
        storage_available = 0,
        storage_max      = 0,
        inputs_met       = true,
        batch_completion = 0,
    }

    for _, line in ipairs(buffer) do
        -- Header: "<company>: <Commodity> Production Facility #<N>"
        local commodity = line:match(".-:%s+(%w+)%s+Production Facility")
        if commodity then factory.commodity = commodity end

        -- "Location: <loc>   Status: <status>"
        local loc, stat = line:match("Location:%s*(.-)%s+Status:%s*(.+)")
        if loc then
            factory.location = loc
            factory.status   = stat
        end

        -- "Working Capital: <n>ig"
        local wc = line:match("Working Capital:%s*([0-9,]+)ig")
        if wc then factory.working_capital = tonumber((wc:gsub(",", ""))) end

        -- "Income: <n>ig   Expenditure: <n>ig"
        local inc, exp = line:match("Income:%s*([0-9,]+)ig%s+Expenditure:%s*([0-9,]+)ig")
        if inc and exp then
            factory.income      = tonumber((inc:gsub(",", "")))
            factory.expenditure = tonumber((exp:gsub(",", "")))
        end

        -- "Efficiency: <cur>/<max>"
        local eff, eff_max = line:match("Efficiency:%s*(%d+)/(%d+)")
        if eff then
            factory.efficiency     = tonumber(eff)
            factory.efficiency_max = tonumber(eff_max)
        end

        -- "Storage: <avail>/<max> tons"
        local storage_available, storage_max = line:match("Storage:%s*(%d+)/(%d+)%s+tons")
        if storage_available then
            factory.storage_available = tonumber(storage_available)
            factory.storage_max       = tonumber(storage_max)
        end

        -- "Required: <r>   Hired: <h>   Wages: <w>ig"
        local req, hired, wages = line:match("Required:%s*(%d+)%s+Hired:%s*(%d+)%s+Wages:%s*(%d+)ig")
        if req then
            factory.workers_required = tonumber(req)
            factory.workers_hired    = tonumber(hired)
            factory.wages            = tonumber(wages)
        end

        -- Input shortfall: "Required: <r> ... Available: <a>" with a < r
        local input_req, input_avail = line:match("Required:%s*(%d+)%s+Available:%s*(%d+)")
        if input_req and tonumber(input_avail) < tonumber(input_req) then
            factory.inputs_met = false
        end

        -- "Next batch is <n>%"
        local batch = line:match("Next batch is (%d+)%%")
        if batch then factory.batch_completion = tonumber(batch) end
    end

    f2t_debug_log("[factory] Parsed factory #%d - %s", factory.number, factory.location)
    return factory
end

-- Finalise the current factory's data and advance to the next.
function f2t_factory_process_capture()
    local factory = f2t_factory_parse_buffer()
    factory.profit = factory.income - factory.expenditure
    table.insert(f2t_factory.factories, factory)

    f2t_debug_log("[factory] Stored factory #%d, total: %d", factory.number, #f2t_factory.factories)

    f2t_factory_query_next()
end