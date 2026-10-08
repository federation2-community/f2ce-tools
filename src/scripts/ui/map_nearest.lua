-- f2tBuildMapNearest(parent, gid) creates a "Nearest ▾" button in the top-left
-- of the F2CE Map pane, just below the map info lines. Clicking it toggles a
-- dropdown of the legend's room types; picking one walks to the closest mapped
-- room of that type (f2t_map_nearest_room_with_flag + f2t_map_walk_to).

local _CSS_BTN = [[
    QLabel {
        background-color: rgba(28,32,48,200);
        color: rgba(200,210,230,255);
        border: 1px solid rgba(80,90,120,180);
        border-radius: 3px;
        font-size: 11px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(50,60,90,220);
        border-color: rgba(100,160,255,200);
        color: white;
    }
]]
local _CSS_MENU_BG = [[
    background-color: rgba(16,20,34,235);
    border: 1px solid rgba(80,95,140,200);
    border-radius: 5px;
]]
local function menuItemCss(background, border, color)
    return string.format([[
        QLabel {
            background-color: %s;
            color: %s;
            border: 1px solid %s;
            border-radius: 3px;
            font-family: "Consolas","Monaco",monospace;
            font-size: 12px;
            qproperty-alignment: AlignVCenter;
            padding: 0 4px;
        }
    ]], background, color, border)
end

-- Hover is applied from enter/leave callbacks: the menu is reused across opens
-- and stacked over the dropdown backdrop, where Qt's :hover state doesn't track.
local _CSS_MENU_ITEM       = menuItemCss("rgba(28,32,48,220)", "rgba(80,90,120,170)", "rgba(205,215,225,255)")
local _CSS_MENU_ITEM_HOVER = menuItemCss("rgba(56,68,104,240)", "rgba(100,160,255,220)", "white")

local BUTTON_WIDTH  = 78
local BUTTON_HEIGHT = 22
local MARGIN        = 3    -- gap from the pane's left border and from the info lines
local MENU_WIDTH    = 170
local ITEM_HEIGHT   = 26
local GAP           = 4
local PAD           = 6

-- Mudlet paints the info lines from y=10 down: each is one display-font line
-- plus 10px, starting at y=20. fed2_bc and fed2_rm make two lines. Their
-- emoji fall back to a colour emoji font with taller lines than the display
-- font, so the tallest of those sets the line height.
local INFO_LINE_COUNT = 2
local EMOJI_FONTS = { "Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji" }

local function infoBarBottom()
    local size = getFontSize()
    local lineHeight = 16
    local fonts = { getFont() }
    for _, font in ipairs(EMOJI_FONTS) do table.insert(fonts, font) end
    for _, font in ipairs(fonts) do
        local ok, _, height = pcall(calcFontSize, size, font)
        if ok and tonumber(height) and height > lineHeight then lineHeight = height end
    end
    return 20 + INFO_LINE_COUNT * (lineHeight + 10)
end

local function nearestTypes()
    local types = {}
    if type(f2t_map_get_legend_data) ~= "function" then return types end
    for _, entry in ipairs(f2t_map_get_legend_data()) do
        if entry.flag then table.insert(types, entry) end
    end
    return types
end

local function rowHtml(entry)
    return string.format(
        "<table cellspacing='0' cellpadding='2'><tr>"
        .. "<td width='34' align='center' style='background-color:%s;color:%s;'>%s</td>"
        .. "<td style='padding-left:8px;'>%s</td>"
        .. "</tr></table>",
        entry.html_color, entry.text_color or "#ddeeff",
        entry.menu_symbol or entry.symbol, entry.menu_label or entry.label)
end

local function goToNearest(entry)
    local label = entry.menu_label or entry.label
    if not F2T_MAP_CURRENT_ROOM_ID or not roomExists(F2T_MAP_CURRENT_ROOM_ID) then
        cecho("\n<yellow>[map]<reset> Your current room isn't mapped yet.\n")
        return
    end
    local roomId, steps = f2t_map_nearest_room_with_flag(entry.flag)
    if not roomId then
        cecho(string.format("\n<yellow>[map]<reset> No mapped %s you can walk to from here.\n", label))
        return
    end
    if steps == 0 then
        cecho(string.format("\n<cyan>[map]<reset> You're already at a %s.\n", label))
        return
    end
    cecho(string.format("\n<cyan>[map]<reset> Heading to the nearest %s: %s (%d steps)\n",
        label, getRoomName(roomId) or ("room " .. roomId), steps))
    f2t_map_walk_to(roomId, function(arrived, result)
        if not arrived and result ~= "stopped" then
            cecho(string.format("\n<red>[map]<reset> Couldn't reach the %s.\n", label))
        end
    end)
end

function f2tBuildMapNearest(parent, gid)
    local pfx = gid .. "_near_"
    local buttonY = infoBarBottom() + MARGIN

    local button = Geyser.Label:new({
        name   = pfx .. "button",
        x      = MARGIN,
        y      = buttonY,
        width  = BUTTON_WIDTH,
        height = BUTTON_HEIGHT,
    }, parent)
    button:setStyleSheet(_CSS_BTN)
    button:echo("<center>Nearest ▾</center>")

    local menu        = nil
    local menuItems   = {}
    local menuVisible = false

    local function closeMenu()
        if menu then menu:hide() end
        for _, item in ipairs(menuItems) do item:setStyleSheet(_CSS_MENU_ITEM) end
        if menuVisible then f2tHideDropdownBackdrop() end
        menuVisible = false
    end

    -- Top-level so it stacks above the dropdown backdrop; placed under the
    -- button's current screen position on every open.
    local function placeMenu()
        menu:move(button:get_x(), button:get_y() + BUTTON_HEIGHT + 3)
    end

    local function buildMenu()
        local types = nearestTypes()
        local panelHeight = PAD * 2 + #types * ITEM_HEIGHT + math.max(0, #types - 1) * GAP

        menu = Geyser.Container:new({
            name   = pfx .. "menu",
            x      = 0,
            y      = 0,
            width  = MENU_WIDTH,
            height = panelHeight,
        }, Geyser)

        local background = Geyser.Label:new({
            name = pfx .. "menuBg", x = 0, y = 0, width = "100%", height = "100%",
        }, menu)
        background:setStyleSheet(_CSS_MENU_BG)

        for i, entry in ipairs(types) do
            local item = Geyser.Label:new({
                name   = string.format("%smenuItem%d", pfx, i),
                x      = PAD,
                y      = PAD + (i - 1) * (ITEM_HEIGHT + GAP),
                width  = string.format("100%%-%dpx", PAD * 2),
                height = ITEM_HEIGHT,
            }, menu)
            item:setStyleSheet(_CSS_MENU_ITEM)
            item:echo(rowHtml(entry))
            item:setOnEnter(function() item:setStyleSheet(_CSS_MENU_ITEM_HOVER) end)
            item:setOnLeave(function() item:setStyleSheet(_CSS_MENU_ITEM) end)
            table.insert(menuItems, item)
            item:setClickCallback(function()
                closeMenu()
                goToNearest(entry)
            end)
        end
    end

    button:setClickCallback(function()
        if menuVisible then closeMenu(); return end
        if not menu then buildMenu() end
        f2tShowDropdownBackdrop(closeMenu)
        placeMenu()
        menu:show()
        menu:raise()
        menuVisible = true
    end)

    return button
end
