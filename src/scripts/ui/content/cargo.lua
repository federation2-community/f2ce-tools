-- Registers content that renders the ship's cargo from GMCP. Doesn't create a
-- pane or define a condition: for a cargo window that appears only when the
-- hold has cargo, create a pane, assign it this "fed2_cargo" content, and set
-- a Rule: Show when -> GMCP has value -> char.ship.cargo.
--
-- GMCP shape (fed2): gmcp.char.ship = { hold = {cur,max},
--   cargo = { {commodity, base, cost, origin}, ... } }   -- each entry = one 75-ton lot.

local LOT_TONS = 75
local consoles = {}   -- target._gid → MiniConsole

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

local function renderConsole(mc)
    if not mc then return end
    mc:clear()
    local ship = shipData()
    local cur  = ship and ship.hold and ship.hold.cur
    local max  = ship and ship.hold and ship.hold.max

    mc:cecho("<ansiCyan><b>  Cargo Hold</b><reset>\n")
    if cur and max then
        mc:cecho(string.format("  <grey>Hold:<reset> <white>%s<reset>/<grey>%s tons<reset>\n", tostring(cur), tostring(max)))
    end
    mc:cecho("  <grey>" .. string.rep("─", 34) .. "<reset>\n")

    local rows = summarise(ship and ship.cargo)
    if #rows == 0 then
        mc:cecho("\n  <grey>Hold is empty.<reset>\n")
        return
    end

    local totalTons, totalLots = 0, 0
    for _, r in ipairs(rows) do
        totalTons = totalTons + r.tons
        totalLots = totalLots + r.lots
        mc:cecho(string.format("  <ansiYellow><b>%s<reset>\n    <grey>%d lot%s · %d tons<reset>",
            r.name, r.lots, r.lots == 1 and "" or "s", r.tons))
        if r.cost > 0 then mc:cecho(string.format("  <grey>@<reset> <green>%d<reset><grey>/ton<reset>", r.cost)) end
        mc:cecho("\n")
    end
    mc:cecho("  <grey>" .. string.rep("─", 34) .. "<reset>\n")
    mc:cecho(string.format("  <white>Total:<reset> <ansiCyan>%d tons<reset> <grey>(%d lots)<reset>\n", totalTons, totalLots))
end

function f2t_cargo_refresh_open()
    for _, mc in pairs(consoles) do if mc then pcall(renderConsole, mc) end end
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
            local mc = consoles[target._gid]
            if not mc then
                mc = Geyser.MiniConsole:new({
                    name = target._gid .. "_cargomc", x = 0, y = 0, width = "100%", height = "100%",
                    scrollBar = false, fontSize = 9,
                }, target.content)
                mc:setColor(18, 18, 26)
                consoles[target._gid] = mc
            else
                mc:show(); mc:raise()
            end
            renderConsole(mc)
        end,
        remove = function(target)
            local mc = consoles[target._gid]
            if mc then if mc.delete then mc:delete() else mc:hide() end end
            consoles[target._gid] = nil
        end,
        resize   = function(target) renderConsole(consoles[target._gid]) end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) renderConsole(consoles[target._gid]) end,
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