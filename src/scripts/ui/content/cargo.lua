-- Registers content that renders the ship's cargo from GMCP. Doesn't create a
-- pane or define a condition: for a cargo window that appears only when the
-- hold has cargo, create a floating pane, assign it this "fed2_cargo" content,
-- and set a Rule: Show when -> GMCP has value -> char.ship.cargo.
--
-- A floating pane showing this content docks under the Player Info strip's Hold
-- cell: it re-anchors to that cell's screen position on every strip re-flow and
-- sizes itself to the manifest, so it lines up at any resolution or layout.
--
-- GMCP shape (fed2): gmcp.char.ship = { hold = {cur,max},
--   cargo = { {commodity, base, cost, origin}, ... } }   -- each entry = one 75-ton lot.
-- hold.cur is FREE space, not space used.

local LOT_TONS = 75
local CONSOLE_FONT_SIZE = 9
local PAD_X, PAD_Y = 8, 4

-- Continues the Hold cell: same base colour as the bottom of its gradient and
-- the strip's divider colour, open at the top where it meets the cell.
local FRAME_CSS = [[
    background-color: #16161e;
    border: 1px solid #3a3a4a;
    border-top: none;
    border-bottom-left-radius: 4px;
    border-bottom-right-radius: 4px;
]]

local views = {}   -- target._gid -> { target, frame, console }
local docking = false

local function shipData() return gmcp and gmcp.char and gmcp.char.ship or nil end

local function summarise(cargo)
    local order, byName = {}, {}
    for _, item in ipairs(cargo or {}) do
        local name = item.commodity or "Unknown"
        local row  = byName[name]
        if not row then
            row = { name = name, lots = 0, tons = 0, cost = tonumber(item.cost) or 0 }
            byName[name] = row; order[#order+1] = row
        end
        row.lots = row.lots + 1
        row.tons = row.tons + LOT_TONS
    end
    table.sort(order, function(a, b) return a.name < b.name end)
    return order
end

local function plural(count) return count == 1 and "" or "s" end

-- Visible character count of a cecho string: tags stripped, UTF-8 continuation
-- bytes not counted.
local function visibleLength(text)
    local plain = text:gsub("<[^>]+>", "")
    return select(2, plain:gsub("[^\128-\191]", ""))
end

-- Manifest as cecho lines; `false` marks a divider, drawn at render width.
local function buildLines()
    local ship = shipData()
    local rows = summarise(ship and ship.cargo)
    if #rows == 0 then return { "<grey>Hold is empty.<reset>" } end

    local lines, totalTons, totalLots = {}, 0, 0
    for _, row in ipairs(rows) do
        totalTons = totalTons + row.tons
        totalLots = totalLots + row.lots
        lines[#lines+1] = string.format("<ansiYellow><b>%s</b><reset>", row.name)
        local detail = string.format("  <grey>%d lot%s · %d tons<reset>", row.lots, plural(row.lots), row.tons)
        if row.cost > 0 then
            detail = detail .. string.format("  <grey>@<reset> <green>%d<reset><grey>/ton<reset>", row.cost)
        end
        lines[#lines+1] = detail
    end
    lines[#lines+1] = false
    local total = string.format("<white>Total:<reset> <ansiCyan>%d tons<reset> <grey>(%d lot%s)<reset>",
        totalTons, totalLots, plural(totalLots))
    local free = ship and ship.hold and tonumber(ship.hold.cur)
    if free then total = total .. string.format(" <grey>·<reset> <white>%d<reset> <grey>free<reset>", free) end
    lines[#lines+1] = total
    return lines
end

-- Character cell size of the console's font, in px.
local function fontMetrics(view)
    local ok, width, height = pcall(calcFontSize, view.console.name)
    if ok and tonumber(width) and width > 0 and tonumber(height) and height > 0 then return width, height end
    local px = view.fontSize * 4 / 3
    return px * 0.6, px * 1.3
end

-- Anchor a floating host pane under the Hold cell, sized to the manifest. Wider
-- than the cell only when the manifest needs it, growing leftward so the right
-- edges stay flush.
local function dock(view, needW, needH)
    local pane = view.target
    if not (pane.floating and pane.outer and f2tPlayerInfoHoldRect and Mux._paneEdges) then return end
    local hold = f2tPlayerInfoHoldRect()
    local edges = hold and Mux._paneEdges(hold.paneId)
    if not edges then return end
    if pane.bordered and pane.setBordered then pane:setBordered(false) end

    local chromeW = pane.outer:get_width() - pane.content:get_width()
    local chromeH = pane.outer:get_height() - pane.content:get_height()
    -- Starts 1px left of the cell so its left border overlays the strip divider.
    local cellLeft, cellRight = hold.x - 1, hold.x + hold.width
    local width  = math.max(cellRight - cellLeft, math.ceil(needW) + chromeW)
    local height = math.ceil(needH) + chromeH
    local alongH = cellRight - width - edges.left

    local A = pane.anchor
    if pane._atAnchor and A and A.h and not A.v and A.h.ref == hold.paneId and A.h.targetEdge == "bottom"
        and A.alongH == alongH and pane.floatW == width and pane.floatH == height then
        return
    end
    pane.anchor = { h = { ref = hold.paneId, targetEdge = "bottom", myEdge = "top" }, alongH = alongH }
    pane.floatW, pane.floatH = width, height
    local x, y = Mux._anchorGeom(pane)
    if not x then return end
    pane.floatX, pane.floatY = x, y
    pane._atAnchor = true
    pane.outer:move(x, y)
    pane.outer:resize(width, height)
    pane.outer:reposition()
    if not (pane.hidden or pane._conditionHidden) and pane.raise then pane:raise() end
end

local function render(view)
    if not (view and view.console) then return end
    local lines = buildLines()
    local charW, lineH = fontMetrics(view)

    local longest = 0
    for _, line in ipairs(lines) do
        if line then longest = math.max(longest, visibleLength(line)) end
    end
    if not docking then
        docking = true
        local ok, err = pcall(dock, view, (longest + 1) * charW + 2 * PAD_X, #lines * lineH + 2 * PAD_Y)
        docking = false
        if not ok and f2t_debug_log then f2t_debug_log("[cargo] dock error: %s", tostring(err)) end
    end

    local content = view.target.content
    local innerW = math.max(10, content:get_width() - 2 * PAD_X)
    local innerH = math.max(10, content:get_height() - 2 * PAD_Y)
    view.frame:move(0, 0); view.frame:resize("100%", "100%")
    view.console:move(PAD_X, PAD_Y); view.console:resize(innerW, innerH)

    local mc = view.console
    mc:clear()
    local divider = "<grey>" .. string.rep("─", math.max(4, math.floor(innerW / charW) - 1)) .. "<reset>"
    for i, line in ipairs(lines) do
        mc:cecho((line or divider) .. (i < #lines and "\n" or ""))
    end
end

function f2t_cargo_refresh_open()
    for _, view in pairs(views) do pcall(render, view) end
end

local function buildCargoDef()
    return {
        name        = "Cargo",
        description = "Live ship cargo manifest from gmcp.char.ship.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            if target.contentBg then
                target.contentBg:echo("")
                target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
                target.contentBg:hide()
            end
            local view = views[target._gid]
            if not view then
                local frame = Geyser.Label:new({
                    name = target._gid .. "_cargoframe", x = 0, y = 0, width = "100%", height = "100%",
                }, target.content)
                frame:setStyleSheet(FRAME_CSS)
                local fontSize = Mux.scaledFontSize(target, CONSOLE_FONT_SIZE)
                local console = Geyser.MiniConsole:new({
                    name = target._gid .. "_cargomc", x = PAD_X, y = PAD_Y, width = 10, height = 10,
                    scrollBar = false, fontSize = fontSize,
                }, target.content)
                console:setColor(22, 22, 30)
                view = { target = target, frame = frame, console = console, fontSize = fontSize }
                views[target._gid] = view
            else
                view.target = target
                view.frame:show(); view.console:show(); view.console:raise()
            end
            render(view)
        end,
        remove = function(target)
            local view = views[target._gid]
            if view then
                for _, widget in ipairs({ view.console, view.frame }) do
                    if widget.delete then widget:delete() else widget:hide() end
                end
            end
            views[target._gid] = nil
        end,
        resize    = function(target) render(views[target._gid]) end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) render(views[target._gid]) end,
        onTextScale = function(target)
            local view = views[target._gid]
            if not view then return end
            view.fontSize = Mux.scaledFontSize(target, CONSOLE_FONT_SIZE)
            view.console:setFontSize(view.fontSize)
            render(view)
        end,
    }
end

-- Called from init.lua muxletReady: register the content. That's the whole job.
function f2tRegisterCargo()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[cargo] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_cargo", buildCargoDef())
    if f2t_debug_log then f2t_debug_log("[cargo] registered fed2_cargo content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterCargo)

-- Keep any open cargo window current as ship data arrives.
registerAnonymousEventHandler("gmcp.char.ship", function() f2t_cargo_refresh_open() end)

if f2t_debug_log then f2t_debug_log("[cargo] module loaded") end
