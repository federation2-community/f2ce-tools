-- =============================================================================
-- Hauling Jobs - Using UI Table System
-- =============================================================================

-- Helper function
function stripThe(name)
    if not name then return "" end
    local result = string.gsub(name, "^The ", "")
    return result
end

-- =============================================================================
-- INITIALIZE HAULING TABLE
-- =============================================================================

function ui_hauling_init()
    -- Define columns for hauling jobs
    local hauling_columns = {
        {
            key          = "job_number",
            label        = "Job",
            width        = 4,
            align        = "center",
            header_align = "center",
            sortable     = true,
            format       = function(value) return "<blue><u>" .. value .. "</u><reset>" end,
            link         = function(value) send("ac " .. value) end,
            linkHint     = "Accept job %s",
            sort_value   = function(row) return tonumber(row.job_number) end
        },
        {
            key              = "origin_display",
            label            = "Origin",
            width            = 10,
            align            = "left",
            header_align     = "center",
            sortable         = true,
            separator        = " > ",        -- Arrow separator between origin and dest in DATA
            header_separator = "   ",
            format           = function(value) return "<ansiCyan>" .. value .. "<reset>" end,

            link = function(value, row)
                if getRoomUserData(f2t_map_resolve_location(row.origin), "fed2_system") == "Sol" then
                    local success = f2t_map_navigate(row.origin .. " ac")

                    if not success then f2t_map_navigate(row.origin) end
                else
                    f2t_map_navigate(row.origin)
                end
            end,

            linkHint   = "Go to %s",
            sort_value = function(row) return row.origin:lower() end
        },
        {
            key          = "dest_display",
            label        = "Dest",
            width        = 10,
            align        = "left",
            header_align = "center",
            sortable     = true,
            format       = function(value) return "<ansiCyan>" .. value .. "<reset>" end,

            link = function(value, row)
                if getRoomUserData(f2t_map_resolve_location(row.dest), "fed2_system") == "Sol" then
                    local success = f2t_map_navigate(row.dest .. " ac")

                    if not success then f2t_map_navigate(row.dest) end
                else
                    f2t_map_navigate(row.dest)
                end
            end,

            linkHint   = "Go to %s",
            sort_value = function(row) return row.dest:lower() end
        },
        {
            key          = "moves",
            label        = "GTU",
            width        = 4,
            align        = "center",
            header_align = "center",
            sortable     = false,

            format = function(value, row)
                local dist    = row.distance
                local allowed = row.allowed_moves

                if dist then
                    local dist_color

                    if dist < allowed then
                        dist_color = "<ansiGreen>"
                    elseif dist > allowed then
                        dist_color = "<ansiRed>"
                    else
                        dist_color = "<white>"
                    end

                    return "<b>" .. allowed .. "</b>/" .. dist_color .. "<b>" .. dist .. "</b><reset>"
                else
                    return "<b>" .. allowed .. "</b>"
                end
            end
        },
        {
            key          = "pay",
            label        = "Pay",
            width        = 13,
            align        = "left",
            header_align = "center",
            sortable     = true,
            default_sort = "desc",
            allowed_sort = "desc",

            format = function(value, row)
                local base_text = tostring(row.base_pay) .. "ig"
                local pay_color

                if row.pay_type == "bonus" then
                    pay_color = "<ansiGreen>"
                elseif row.pay_type == "penalty" then
                    pay_color = "<ansiRed>"
                else
                    pay_color = "<white>"
                end

                return "<b>" .. row.base_pay .. "</b>ig (" .. pay_color .. "<b>" .. row.effective_pay .. "</b><reset>)"
            end,

            sort_value = function(row) return row.effective_pay end
        }
    }
    
    -- Optional: Configure separators
    local separators = {
        column = " ", -- Single space between columns (default)
        header = nil, -- No header separator
        row    = nil  -- No row separators
    }
    
    -- Create the table
    ui_table_create("hauling_jobs", UI.hauling_window, hauling_columns, separators)
end

-- =============================================================================
-- TRIGGER HANDLERS
-- =============================================================================

function ui_on_hauling_header()
    ui_table_clear("hauling_jobs")
end

function ui_on_hauling_job(job_number, origin, dest, allowed_moves, pay_per_ton)
    local effective_pay, pay_type
    local base_pay          = tonumber(pay_per_ton) * 75
    local allowed_moves_num = tonumber(allowed_moves)
    local distance, err     = f2t_map_get_route_info(origin, dest)

    if distance and distance.success then distance = distance.space_moves end

    if not distance then
        effective_pay = base_pay
        pay_type      = "unknown"
    elseif distance < allowed_moves_num then
        effective_pay = math.floor(base_pay * 1.20)
        pay_type      = "bonus"
    elseif distance > allowed_moves_num then
        effective_pay = math.floor(base_pay * 0.50)
        pay_type      = "penalty"
    else
        effective_pay = base_pay
        pay_type = "normal"
    end
    
    local job_data = {
        job_number     = job_number,
        origin         = origin,
        dest           = dest,
        origin_display = stripThe(origin),
        dest_display   = stripThe(dest),
        allowed_moves  = allowed_moves_num,
        base_pay       = base_pay,
        distance       = distance,
        effective_pay  = effective_pay,
        pay_type       = pay_type,
        moves          = allowed_moves_num .. "/" .. (distance or "?"),
        pay            = base_pay
    }
    
    -- Add to table data
    local tbl = UI.tables["hauling_jobs"]
    if tbl then
        table.insert(tbl.data, job_data)
        ui_table_render("hauling_jobs")
    end
end

-- =============================================================================
-- UI BUTTONS
-- =============================================================================

function ui_hauling()
    ui_hauling_init()

    UI.button_work = Geyser.Label:new(
        {
            name    = "UI.button_work",
            message = "<center>Work</center>"
        },
        UI.hauling_button_bar
    )
    UI.button_work:setStyleSheet(UI.style.button_css)
    UI.button_work:setClickCallback("ui_work")

    UI.button_collect = Geyser.Label:new(
        {
            name    = "UI.button_collect",
            message = "<center>Collect</center>"
        },
        UI.hauling_button_bar
    )
    UI.button_collect:setStyleSheet(UI.style.button_css)
    UI.button_collect:setClickCallback("ui_collect")

    UI.button_deliver = Geyser.Label:new(
        {
            name    = "UI.button_deliver",
            message = "<center>Deliver</center>"
        },
        UI.hauling_button_bar
    )
    UI.button_deliver:setStyleSheet(UI.style.button_css)
    UI.button_deliver:setClickCallback("ui_deliver")
end

function ui_work()
    send("work", false)
end

function ui_collect()
    send("collect", false)
end

function ui_deliver()
    send("deliver", false)
end