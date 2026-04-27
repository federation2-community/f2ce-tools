function ui_convert_value(amount) --format very long numbers
    local formatted = amount

    if tonumber(formatted) == nil then return nil end

    if tonumber(formatted) <= 1000000 then --we are below or just equal to a meg
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')

            if (k==0) then
                break
            end
        end
    else --we are above a meg
        --divide by 100,000 so the decimal is shifted
        --floor the result to throw away everything after the decimal
        --divide by 10 to put the decimal in the right spot
        formatted = math.floor(tonumber(formatted)/100000) / 10 .. " m"
    end

    return formatted
end

function ui_color_percent(num_cur, num_max) --colorize based on a percentage
    --0 is ansiRed, 5 is ansiYellow, 9 is ansiGreen, 10 is default white
    --unfortunately mudlet's color table doesn't have a good gradiant 
    --so hexcodes from a random online gradiant tool it is
    local color_grad = {[0] = "#800000", [1] = "#801a00", [2] = "#803400", [3] = "#804e00", [4] = "#806800", 
        [5] = "#808000", [6] = "#668000", [7] = "#4c8000", [8] = "#328000", [9] = "#008000", [10] = "#FFFFFF"
    }
    --divide the current value by the max value to get a percentage
    --then multiply it by ten to shift the decimal
    --then floor it to chop off everything after the decimal
    --should result in a number between 0 and 10
    percent = math.floor((tonumber(num_cur) / tonumber(num_max)) * 10)
    color   = color_grad[percent]

    return color
end

UI.magic_cash_numbers = {
  ["Commander"]     = 250000,
  ["Captain"]       = 400000,
  ["Adventurer"]    = 600000,
  ["Adventuress"]   = 600000,
  ["Merchant"]      = 7500000,
  ["Trader"]        = 12500000,
  ["Industrialist"] = 17500000,
  ["Manufacturer"]  = 22500000,
  ["Financier"]     = 27500000,
}

-- Populate the top status frame with labels
function ui_build_header()
    -- build the hbox the stat labels will go into
    UI.header = Geyser.HBox:new(
        {
            name   = "UI.header",
            x      = 0,
            y      = 0,
            width  = "100%",
            height = "100%",
        },
        UI.top_left_frame
    )

    -- Create the six stat labels inside the stats container
    for i = 1, 6 do
        UI["Label"..i] = Geyser.Label:new(
            {
                name = "UI.Label"..i,
            },
            UI.header
        )
        UI["Label"..i]:setStyleSheet(UI.style.header_label_css)
        UI["Label"..i]:setFontSize(12)
    end

    ------------- Buy Fuel Button ------------------------------
    UI.button_buy_fuel = Geyser.Label:new(
        {
            name    = "UI.button_buy_fuel",
            x       = "26%",
            y       = "20%",
            width   = "5%",
            height  = "60%",
            message = "<center>Buy Fuel</center>"
        },
        UI.top_left_frame
    )
    UI.button_buy_fuel:setStyleSheet(UI.style.button_css)
    UI.button_buy_fuel:setClickCallback("ui_buy_fuel")

    -- Make the Hold label (Label6) clickable
    UI.Label6:setClickCallback("ui_toggle_cargo_display")

    -- Track cargo display state
    UI.cargo_display_visible = false
    UI.cargo_manually_hidden = false
end

function ui_update_header()
    -- Safety check: don't update if UI hasn't been built yet
    if not UI.Label1 then
        return
    end

    local vitals = (gmcp.char and gmcp.char.vitals) or {}
    local ship   = (gmcp.char and gmcp.char.ship) or {}

    local rank       = vitals.rank or "-"
    local hold_cur   = (ship.hold and ship.hold.cur) or "-"
    local hold_max   = (ship.hold and ship.hold.max) or "-"
    local fuel_cur   = (ship.fuel and ship.fuel.cur) or "-"
    local fuel_max   = (ship.fuel and ship.fuel.max) or "-"
    local stam_cur   = (vitals.stamina and vitals.stamina.cur) or "-"
    local stam_max   = (vitals.stamina and vitals.stamina.max) or "-"
    local cash       = ui_convert_value(vitals.cash) or "-"
    local slith      = vitals.slithies or "-"
    local groats_max = ui_convert_value(UI.magic_cash_numbers[rank]) or "-"

    -- Label1: Rank
    UI.Label1:echo("Rank: " .. [[<b>]] .. rank .. [[</b>]])

    -- Label2: Fuel
    if tonumber(fuel_cur) then 
        UI.Label2:echo("Fuel: " .. [[<b><font color=]] .. ui_color_percent(fuel_cur, fuel_max) .. [[>]] .. fuel_cur .. [[</font></b>]] .. "/" .. fuel_max) 
    end

    -- Label3: Stamina
    if tonumber(stam_cur) then 
        UI.Label3:echo("Stamina: " .. [[<b><font color=]] .. ui_color_percent(stam_cur, stam_max) .. [[>]] .. stam_cur .. [[</font></b>]] .. "/" .. stam_max) 
    end

    -- Label4: Groats
    if groats_max == "-" then
        UI.Label4:echo("Groats: " .. [[<b>]] .. cash .. [[</b>]])
    else
        UI.Label4:echo("Groats: " .. [[<b>]] .. cash .. [[</b>]] .. "/" .. groats_max)
    end

    -- Label5: Slithies
    UI.Label5:echo("Slithies: " .. [[<b>]] .. slith .. [[</b>]])

    -- Label6: Hold (clickable)
    if tonumber(hold_cur) then 
        local hold_display = "Hold: " .. [[<b><font color=]] .. ui_color_percent(hold_cur, hold_max) .. [[>]] .. hold_cur .. [[</font></b>]] .. "/" .. hold_max
        
        -- Check if cargo exists
        local has_cargo = ship.cargo and next(ship.cargo) ~= nil
        
        -- Add indicator if cargo exists
        if has_cargo then
            hold_display = hold_display .. " 📦"
        end

        UI.Label6:echo(hold_display)

        -- Auto-show logic
        if has_cargo and not UI.cargo_manually_hidden then
            if not UI.cargo_display_visible then
                ui_show_cargo_display()
            else
                ui_update_cargo_display()
            end
        elseif not has_cargo and UI.cargo_display_visible then
            -- Auto-hide when cargo is empty
            ui_hide_cargo_display()
            UI.cargo_manually_hidden = false  -- Reset manual hide state
        end
    end

    ui_fuel_status()
    ui_update_for_rank()
end