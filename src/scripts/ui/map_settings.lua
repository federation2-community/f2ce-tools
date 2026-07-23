-- f2tBuildMapSettings(parent, gid) creates a gear button in the bottom-right
-- of the F2CE Map pane; clicking it toggles a flyout menu:
--   Import Map Database - bundled-resource picker (f2tShowMapImportOverlay)
--   Import from File     - file-dialog import of external map JSON (f2t_map_import)
--   Export Map           - file-dialog export of current map (f2t_map_export)
--
-- The gear is near-transparent when idle so it doesn't obstruct the map
-- view, opaque on hover.
--
-- Sizing: the gear is a Label (not a Container) so getElementSize() works.
-- A tempTimer(0) reads its rendered pixel size, derives the parent's pixel
-- dimensions (gear = 4% x 4% of parent), and repositions it pixel-perfect in
-- the corner; the lazily-built menu reuses those same coords.

local _CSS_GEAR = [[
    QLabel {
        background-color: rgba(22,26,42,35);
        color: rgba(180,200,240,45);
        border: 1px solid rgba(60,70,100,25);
        border-radius: 0px;
        font-size: 11px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(40,50,80,230);
        color: rgba(255,255,255,255);
        border-color: rgba(100,160,255,200);
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
        color: rgba(200,210,230,255);
        border: 1px solid rgba(80,90,120,170);
        border-radius: 3px;
        font-size: 10px;
        qproperty-alignment: AlignVCenter;
        padding: 0 8px;
    }
    QLabel::hover {
        background-color: rgba(50,60,90,235);
        border-color: rgba(100,160,255,200);
        color: white;
    }
]]

-- Built per-call (inside f2tBuildMapSettings) rather than once at module
-- scope, since the "Import Map Database…" action needs the live parent/gid
-- to build the overlay into (f2tShowMapImportOverlay renders inside the map
-- content's own slot, not a standalone dialog).
local function _buildMenuItems(parent, gid)
    return {
        {
            label  = "  Map Legend…",
            action = function()
                if f2tShowMapLegend then f2tShowMapLegend() end
            end,
        },
        {
            label  = "  Import Map Database…",
            action = function()
                if f2tShowMapImportOverlay then f2tShowMapImportOverlay(parent, gid, "manual") end
            end,
        },
        {
            label  = "  Import from File…",
            action = function()
                if f2t_map_import then f2t_map_import() end
            end,
        },
        {
            label  = "  Export Map…",
            action = function()
                if f2t_map_export then f2t_map_export() end
            end,
        },
    }
end

local GEAR_PX = 22   -- exact square side in pixels after resize
local MARGIN  = 3    -- gap from pane right/bottom borders in pixels
local MENU_W  = 200  -- dropdown width in pixels
local ITEM_H  = 26
local GAP     = 4
local PAD     = 6

function f2tBuildMapSettings(parent, gid)
    local pfx = gid .. "_set_"

    -- Gear is a Label named pfx.."shell" so map.lua's Geyser.windowList lookup
    -- (which uses gid.."_set_shell") finds it on re-apply.
    -- Initial placement uses equal percentages (approximately right corner);
    -- a tempTimer(0) refines to exact square pixels once Qt has the label size.
    local gear = Geyser.Label:new({
        name   = pfx .. "shell",
        x      = "96%",
        y      = "96%",
        width  = "4%",
        height = "4%",
    }, parent)
    gear:setStyleSheet(_CSS_GEAR)
    gear:echo("<center>⚙</center>")

    -- Pixel coords resolved after the label renders; used by buildMenu().
    local resolvedX = nil
    local resolvedY = nil

    -- After one event-loop tick the label has its true pixel geometry.
    -- Gear width = 4% of parent width, so parentW = gearW / 0.04.
    tempTimer(0, function()
        pcall(function()
            local gW, gH = getElementSize(pfx .. "shell")
            if gW and gW > 0 and gH and gH > 0 then
                local pW = math.floor(gW / 0.04)
                local pH = math.floor(gH / 0.04)
                resolvedX = pW - GEAR_PX - MARGIN
                resolvedY = pH - GEAR_PX - MARGIN
                gear:move(resolvedX, resolvedY)
                gear:resize(GEAR_PX, GEAR_PX)
            end
        end)
    end)

    local menu        = nil
    local menuVisible = false

    local function closeMenu()
        if menu then menu:hide() end
        menuVisible = false
    end

    local function buildMenu()
        local menuItems = _buildMenuItems(parent, gid)
        local panelH = PAD * 2 + #menuItems * ITEM_H + (#menuItems - 1) * GAP

        -- Right border of menu = right border of gear; bottom of menu = gear top - 3px.
        local menuX, menuY, menuW
        if resolvedX and resolvedY then
            menuW = MENU_W
            menuX = math.max(0, resolvedX + GEAR_PX - MENU_W)
            menuY = math.max(0, resolvedY - panelH - 3)
        else
            -- Fallback if size measurement unavailable
            menuW = "40%"
            menuX = "58%"
            menuY = "78%"
        end

        menu = Geyser.Container:new({
            name   = pfx .. "menu",
            x      = menuX,
            y      = menuY,
            width  = menuW,
            height = panelH,
        }, parent)

        local bg = Geyser.Label:new({
            name = pfx .. "menuBg", x = 0, y = 0, width = "100%", height = "100%",
        }, menu)
        bg:setStyleSheet(_CSS_MENU_BG)

        for i, item in ipairs(menuItems) do
            local itemY = PAD + (i - 1) * (ITEM_H + GAP)
            local btn = Geyser.Label:new({
                name   = string.format("%smenuItem%d", pfx, i),
                x      = PAD,
                y      = itemY,
                width  = string.format("100%%-%dpx", PAD * 2),
                height = ITEM_H,
            }, menu)
            btn:setStyleSheet(_CSS_MENU_ITEM)
            btn:echo(item.label)
            local action = item.action
            btn:setClickCallback(function()
                closeMenu()
                action()
            end)
        end
    end

    gear:setClickCallback(function()
        if menuVisible then closeMenu(); return end
        if not menu then buildMenu() end
        menu:show()
        menu:raise()
        menuVisible = true
    end)

    return gear
end
