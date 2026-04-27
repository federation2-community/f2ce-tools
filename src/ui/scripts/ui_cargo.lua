function ui_toggle_cargo_display()
    local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo

    if not cargo or not next(cargo) then return end

    if UI.cargo_display_visible then
        UI.cargo_manually_hidden = true
        ui_hide_cargo_display()
    else
        UI.cargo_manually_hidden = false
        ui_show_cargo_display()
    end

end

function ui_show_cargo_display()
    if not UI.cargo_dropdown then return end

    UI.cargo_display_visible = true

    if UI.cargo_gap_filler then
        UI.cargo_gap_filler:show()
        UI.cargo_gap_filler:raise()
    end

    UI.cargo_dropdown:show()
    UI.cargo_dropdown:raise()

    if UI.top_right_frame then UI.top_right_frame:raise() end

    ui_update_cargo_display()
    if ui_update_local_players then ui_update_local_players() end

    -- Re-raise galaxy after all widget creation (immediate + deferred for Qt finalization)
    if UI.galaxy_dropdown and UI.galaxy.visible then
        UI.galaxy_dropdown:raiseAll()
        tempTimer(0.1, function()
            if UI.galaxy_dropdown and UI.galaxy.visible then
                UI.galaxy_dropdown:raiseAll()
            end
        end)
    end
end

function ui_hide_cargo_display()
    if not UI.cargo_dropdown then return end

    UI.cargo_display_visible = false

    UI.cargo_dropdown:hide()

    if UI.cargo_gap_filler then UI.cargo_gap_filler:hide() end

    if ui_update_local_players then ui_update_local_players() end

    if UI.cargo_buttons then
        for _, button_set in ipairs(UI.cargo_buttons) do
            if button_set.check_price then button_set.check_price:hide() end
            if button_set.sell        then button_set.sell:hide()        end
            if button_set.deliver     then button_set.deliver:hide()     end
        end
    end
end

function ui_update_cargo_display()
    if not UI.cargo_dropdown then return end

    local cargo = gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo

    -- Clean up old elements COMPLETELY (destroy, not just hide)
    if UI.cargo_entries then
        for _, entry_container in ipairs(UI.cargo_entries) do
            entry_container:hide()
        end
    end
    UI.cargo_entries = {}
    
    if UI.cargo_buttons then
        for _, button_set in ipairs(UI.cargo_buttons) do
            if button_set.check_price then button_set.check_price:hide() end
            if button_set.sell        then button_set.sell:hide()        end
            if button_set.deliver     then button_set.deliver:hide()     end
        end
    end
    UI.cargo_buttons = {}

    -- Clean up old separators and footer
    if UI.cargo_separators then
        for _, sep in ipairs(UI.cargo_separators) do
            sep:hide()
        end
    end
    UI.cargo_separators = {}
    
    if UI.cargo_footer then
        UI.cargo_footer:hide()
    end

    -- Count cargo entries
    local cargo_count = 0
    for _ in pairs(cargo) do cargo_count = cargo_count + 1 end

    -- Calculate dropdown height in PIXELS (only dimension that uses pixels)
    local entry_height_px = 60        -- pixels per entry
    local separator_height_px = 2     -- pixels per separator
    local footer_height_px = 30       -- pixels for footer
    
    local max_entries = 8
    local visible_entries = math.min(cargo_count, max_entries)
    
    local total_height_px = (visible_entries * entry_height_px) + 
                           ((visible_entries - 1) * separator_height_px) + 
                           footer_height_px
    
    -- Set dropdown height in PIXELS - this is the only fixed pixel dimension
    UI.cargo_dropdown:resize(nil, total_height_px)
    UI.cargo_height_px = total_height_px

    -- Now calculate percentages WITHIN the dropdown
    local entry_height_pct = (entry_height_px / total_height_px) * 100
    local separator_height_pct = (separator_height_px / total_height_px) * 100
    local footer_height_pct = (footer_height_px / total_height_px) * 100

    -- Calculate total tons
    local total_tons = cargo_count * 75

    local current_y_pct = 0
    local entry_num = 0

    for key, value in pairs(cargo) do
        entry_num = entry_num + 1
        local is_delivery = value.destination ~= nil

        -- Create entry container with UNIQUE name using entry_num
        local entry = Geyser.Container:new(
            {
                name   = "cargo_entry_container_" .. entry_num,
                x      = "0%",
                y      = current_y_pct .. "%",
                width  = "100%",
                height = entry_height_pct .. "%",
            },
            UI.cargo_dropdown
        )
        
        -- Track the container for cleanup
        table.insert(UI.cargo_entries, entry)

        -- Text miniconsole (left side, 65% width) with UNIQUE name
        local entry_text = Geyser.MiniConsole:new(
            {
                name      = "cargo_entry_text_" .. entry_num,
                x         = "0%",
                y         = "15%",
                width     = "65%",
                height    = "100%",
                autoWrap  = true,
                scrollBar = false,
                fontSize  = text_size,
                color     = "black",
            },
            entry
        )
        entry_text:clear()

        -- Commodity name in cyan
        entry_text:cecho("<ansiCyan><b>" .. (value.commodity or "Unknown") .. "</b><reset>")
        
        if is_delivery then
            entry_text:cecho(" → ")
            entry_text:cechoLink(
                "<yellow>" .. (value.destination or "Unknown") .. "<reset>",
                function()
                    if getRoomUserData(f2t_map_resolve_location(value.destination), "fed2_system") == "Sol" then
                        local success = f2t_map_navigate(value.destination .. " ac")
                        if not success then f2t_map_navigate(value.destination) end
                    else
                        f2t_map_navigate(value.destination)
                    end
                end,
                "Go to " .. value.destination,
                true
            )
        else
            -- Price info
            local cost = tonumber(value.cost) or 0
            local base = tonumber(value.base) or 0
            local diff = base - cost

            entry_text:cecho("\n<white><b>" .. cost .. "</b>ig<reset> ")
            entry_text:cecho("(base: <dim_grey>" .. base .. "ig<reset>) ")

            if diff > 0 then
                entry_text:cecho("<green>+<b>" .. diff .. "</b>ig<reset>")
            elseif diff < 0 then
                entry_text:cecho("<red><b>" .. diff .. "</b>ig<reset>")
            else
                entry_text:cecho("<white>0ig<reset>")
            end

            local origin = value.origin
            if origin then
                entry_text:cechoLink(
                    "\n<yellow>" .. origin .. "<reset>",
                    function() send("nav " .. origin .. " exchange", false) end,
                    "Nav to " .. origin .. " exchange",
                    true
                )
            else
                entry_text:cecho("\n<yellow>Unknown<reset>")
            end
        end

        -- Buttons (right side, starting at 60%)
        local buttons = {}

        if is_delivery then
            buttons.deliver = Geyser.Label:new(
                {
                    name    = "cargo_deliver_" .. entry_num,
                    x       = "60%",
                    y       = "25%",
                    width   = "19%",
                    height  = "50%",
                    message = "<center>Deliver</center>"
                },
                entry
            )
            buttons.deliver:setStyleSheet(UI.style.button_css)
            buttons.deliver:setClickCallback(function() send("deliver", false) end)
        else
            buttons.check_price = Geyser.Label:new(
                {
                    name    = "cargo_check_" .. entry_num,
                    x       = "60%",
                    y       = "25%",
                    width   = "19%",
                    height  = "50%",
                    message = "<center>Check Price</center>"
                },
                entry
            )
            buttons.check_price:setStyleSheet(UI.style.button_css)
            buttons.check_price:setClickCallback(function() 
                send("c price " .. (value.commodity or ""):lower(), false) 
            end)

            buttons.sell = Geyser.Label:new(
                {
                    name    = "cargo_sell_" .. entry_num,
                    x       = "80%",
                    y       = "25%",
                    width   = "9%",
                    height  = "50%",
                    message = "<center>Sell</center>"
                },
                entry
            )
            buttons.sell:setStyleSheet(UI.style.button_css)
            buttons.sell:setClickCallback(function() 
                send("sell " .. (value.commodity or ""):lower(), false) 
            end)
        end

        table.insert(UI.cargo_buttons, buttons)

        current_y_pct = current_y_pct + entry_height_pct

        -- Add separator line (except after last entry)
        if entry_num < visible_entries then
            local separator = Geyser.Label:new(
                {
                    name = "cargo_separator_" .. entry_num,
                    x    = "0%",
                    y    = current_y_pct .. "%",
                    width = "100%",
                    height = separator_height_pct .. "%",
                },
                UI.cargo_dropdown
            )
            separator:setStyleSheet([[
                background-color: rgba(255,255,255,0.46)
            ]])
            
            table.insert(UI.cargo_separators, separator)
            current_y_pct = current_y_pct + separator_height_pct
        end
    end

    local bump = 0
    if cargo_count == 1 then bump = 10 end
    
    -- Footer with total tonnage
    UI.cargo_footer = Geyser.MiniConsole:new(
        {
            name      = "cargo_footer",
            x         = "0%",
            y         = current_y_pct + 2 .. "%",
            width     = "100%",
            height    = footer_height_pct + bump .. "%",
            autoWrap  = false,
            scrollBar = false,
            fontSize  = text_size,
            color     = "black",
        },
        UI.cargo_dropdown
    )
    UI.cargo_footer:clear()
    UI.cargo_footer:cecho("<dim_grey>─────────────────────────<reset>\n")
    UI.cargo_footer:cecho("<dim_grey>Total: <white><b>" .. total_tons .. "</b> tons<reset>")
end