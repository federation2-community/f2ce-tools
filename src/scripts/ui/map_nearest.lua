-- f2tBuildMapNearest(parent, gid) creates a "Nearest ▾" button in the top-left
-- of the F2CE Map pane, just below the map info lines. Clicking it toggles a
-- dropdown of the legend's room types; picking one walks to the closest mapped
-- room of that type (f2t_map_nearest_room_with_flag + f2tNav.go).

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
local _CSS_MENU_ITEM = [[
    QLabel {
        background-color: rgba(28,32,48,220);
        color: rgba(205,215,225,255);
        border: 1px solid rgba(80,90,120,170);
        border-radius: 3px;
        font-family: "Consolas","Monaco",monospace;
        font-size: 12px;
        qproperty-alignment: AlignVCenter;
        padding: 0 4px;
    }
    QLabel::hover {
        background-color: rgba(56,68,104,240);
        border-color: rgba(100,160,255,220);
        color: white;
    }
]]

local BUTTON_WIDTH  = 78
local BUTTON_HEIGHT = 22
local MARGIN        = 3    -- gap from the pane's left border and from the info lines
local MENU_WIDTH    = 170
local ITEM_HEIGHT   = 26
local GAP           = 4
local PAD           = 6

-- Mudlet paints each info line from y=20 down as a box word-wrapped to the
-- map width minus 40px, its wrapped text height plus 10px tall. Emoji fall
-- back to a colour emoji font with taller lines than the display font, so the
-- tallest of those sets the line height, and each is taken as two cells wide.
local INFO_KEYS = { "fed2_bc", "fed2_rm" }
local INFO_LINE_COUNT = 2   -- assumed before the map has painted any
local EMOJI_FONTS = { "Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji" }

-- Last-built pane's button and its parent; the move handler targets these.
local _current = nil
local _infoHandlerId = nil

local function fontMetrics()
    local size = getFontSize()
    local charWidth, lineHeight = 8, 16
    local ok, width, height = pcall(calcFontSize, size, getFont())
    if ok and tonumber(width) then charWidth = width end
    if ok and tonumber(height) then lineHeight = height end
    for _, font in ipairs(EMOJI_FONTS) do
        local fontOk, _, fontHeight = pcall(calcFontSize, size, font)
        if fontOk and tonumber(fontHeight) and fontHeight > lineHeight then lineHeight = fontHeight end
    end
    return charWidth, lineHeight
end

local function codepointOf(character)
    local lead = string.byte(character, 1)
    if lead < 0x80 then return lead end
    local codepoint = lead % (lead >= 0xF0 and 0x08 or lead >= 0xE0 and 0x10 or 0x20)
    for index = 2, #character do
        codepoint = codepoint * 0x40 + string.byte(character, index) % 0x40
    end
    return codepoint
end

-- Joiners and variation selectors take no space.
local function cellCount(text)
    local cells = 0
    for character in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do
        local codepoint = codepointOf(character)
        local zeroWidth = codepoint == 0x200D or (codepoint >= 0xFE00 and codepoint <= 0xFE0F)
        if codepoint >= 0x1F000 or (codepoint >= 0x2600 and codepoint <= 0x2BFF) then
            cells = cells + 2
        elseif not zeroWidth then
            cells = cells + 1
        end
    end
    return cells
end

local function wrappedLineCount(text, availableWidth, charWidth)
    local lines, lineWidth = 1, 0
    for word, spaces in string.gmatch(text, "(%S+)(%s*)") do
        local wordWidth = cellCount(word) * charWidth
        if lineWidth > 0 and lineWidth + wordWidth > availableWidth then
            lines = lines + 1
            lineWidth = 0
        end
        lineWidth = lineWidth + wordWidth + #spaces * charWidth
    end
    return lines
end

local function infoBarBottom(mapWidth)
    local charWidth, lineHeight = fontMetrics()
    local texts = F2T_MAP_INFO_TEXT
    if not texts or next(texts) == nil or not mapWidth then
        return 20 + INFO_LINE_COUNT * (lineHeight + 10)
    end
    local bottom = 20
    for _, key in ipairs(INFO_KEYS) do
        local text = string.match(texts[key] or "", "^%s*(.-)%s*$")
        if text ~= "" then
            bottom = bottom + wrappedLineCount(text, mapWidth - 40, charWidth) * lineHeight + 10
        end
    end
    return bottom
end

function f2tMapNearestReposition()
    if not _current then return end
    local y = infoBarBottom(_current.parent:get_width()) + MARGIN
    if y ~= _current.button:get_y() - _current.parent:get_y() then
        _current.button:move(MARGIN, y)
    end
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
    f2tNav.go(roomId, { onDone = function(result)
        if result.status == "unreachable" then
            cecho(string.format("\n<red>[map]<reset> Couldn't reach the %s.\n", label))
        end
    end })
end

function f2tBuildMapNearest(parent, gid)
    local pfx = gid .. "_near_"
    local buttonY = infoBarBottom(parent:get_width()) + MARGIN

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
    local menuVisible = false

    local function closeMenu()
        if menu then menu:hide() end
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
        menu:raiseAll()
        menuVisible = true
    end)

    _current = { button = button, parent = parent }
    if _infoHandlerId then killAnonymousEventHandler(_infoHandlerId) end
    _infoHandlerId = registerAnonymousEventHandler("f2tMapInfoChanged", f2tMapNearestReposition)

    return button
end
