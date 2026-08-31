-- Galaxy Navigator content type. Data comes from "di systems", not the map DB,
-- since a player's map can be incomplete but "di systems" always lists everything.

-- cartels[cartel] = { name, syndicate, systems = { [sys] = { name, cartel, syndicate, planets = {...} } } }
-- syndicates[syn] groups the same cartel tables by syndicate (not copies).
F2T_GALAXY = F2T_GALAXY or {
    cartels        = {},
    syndicates     = {},
    loaded         = false,
    loading        = false,
    builtAt        = 0,        -- unix time of last successful scrape
    capture_active = false,
    capture_lines  = {},
    expanded       = {},       -- [key]=true, session-only expand state
}

-- di systems capture

-- Completion is silence-based (0.5s with no new output), not "first blank
-- line ends it": Fed2's login sequence can interleave unrelated blank lines
-- mid-scrape, which would cut capture short.
local function setCaptureTriggers(on)
    local fn = on and enableTrigger or disableTrigger
    pcall(fn, "galaxy_nav_line")
    pcall(fn, "galaxy_nav_end")
end

local function resetFinishTimer()
    f2t_capture_arm("galaxy", function()
        if F2T_GALAXY.capture_active then f2t_galaxy_finish_capture() end
    end)
end

-- Safe to call repeatedly; the loading guard prevents overlap.
function f2t_galaxy_scrape()
    if not F2T_LOGGED_IN then
        f2t_debug_log("[galaxy] scrape skipped (not logged in)")
        return
    end
    if F2T_GALAXY.loading then return end
    -- Refresh the connection flag from the live API before gating. On
    -- mudlet-web the websocket link doesn't always raise sysConnectionEvent, so
    -- the cached F2T_CONNECTED can be stale-false even while getConnectionInfo()
    -- reports connected — which silently killed the scrape (and the refresh
    -- button) on the web client. Re-checking keeps the gate accurate on both
    -- desktop and web, and still bails when genuinely offline.
    if f2t_check_connection then f2t_check_connection() end
    if F2T_CONNECTED == false then
        f2t_debug_log("[galaxy] scrape skipped (offline)")
        return
    end
    f2t_capture_close("galaxy")
    F2T_GALAXY.loading        = true
    F2T_GALAXY.capture_active = true
    F2T_GALAXY.capture_lines  = {}
    setCaptureTriggers(true)
    f2t_galaxy_refresh_open()
    sendAll("di systems", false)   -- don't echo; triggers delete the output
    resetFinishTimer()
end

-- Buffers system lines and folds wrapped continuation lines into the previous one.
function f2t_galaxy_capture_line(line)
    if not F2T_GALAXY.capture_active then return end
    line = (line or ""):match("^%s*(.-)%s*$")
    if line == "" then return end
    resetFinishTimer()
    if line:match(" %- .+ cartel %- ") then
        table.insert(F2T_GALAXY.capture_lines, line)
    elseif #F2T_GALAXY.capture_lines > 0 then
        local n = #F2T_GALAXY.capture_lines
        F2T_GALAXY.capture_lines[n] = F2T_GALAXY.capture_lines[n] .. " " .. line
    end
end

function f2t_galaxy_capture_blank()
    if not F2T_GALAXY.capture_active then return end
    resetFinishTimer()
end

-- "SystemName - SyndicateName syndicate - CartelName cartel - Rank Owner[tag]: Planet(T) Planet(T) ..."
local function parseSystemLine(line)
    local system_name, syndicate_name, cartel_name, planet_str =
        line:match("^(.+) %- (.+) syndicate %- (.+) cartel %- [^:]+: (.*)$")
    if not system_name then return nil end
    system_name    = system_name:match("^%s*(.-)%s*$")
    syndicate_name = syndicate_name:match("^%s*(.-)%s*$")
    cartel_name    = cartel_name:match("^%s*(.-)%s*$")

    local planets = {}
    for planet_name in (planet_str or ""):gmatch("(.-)%([^%)]+%)%s*") do
        planet_name = planet_name:match("^%s*(.-)%s*$")
        if planet_name ~= "" then
            planets[#planets + 1] = {
                name = planet_name, system = system_name, cartel = cartel_name, syndicate = syndicate_name
            }
        end
    end
    return system_name, syndicate_name, cartel_name, planets
end

-- No-op until cartels is populated; f2t_galaxy_finish_capture re-calls this
-- once loading completes.
local function autoExpandCurrentLocation()
    local ri = gmcp and gmcp.room and gmcp.room.info
    if not (ri and ri.cartel and ri.cartel ~= "") then return end
    local cd  = F2T_GALAXY.cartels[ri.cartel]
    local syn = cd and cd.syndicate
    if syn then
        F2T_GALAXY.expanded["syn:" .. syn] = true
        F2T_GALAXY.expanded["cartel:" .. syn .. ":" .. ri.cartel] = true
    end
    if ri.system and ri.system ~= "" then
        F2T_GALAXY.expanded["system:" .. ri.cartel .. ":" .. ri.system] = true
    end
end

function f2t_galaxy_finish_capture()
    if not F2T_GALAXY.capture_active then return end
    F2T_GALAXY.capture_active = false
    setCaptureTriggers(false)
    f2t_capture_close("galaxy")

    if #F2T_GALAXY.capture_lines == 0 then
        F2T_GALAXY.loading = false
        f2t_galaxy_refresh_open()
        return
    end

    local cartels    = {}
    local syndicates = {}
    for _, line in ipairs(F2T_GALAXY.capture_lines) do
        local sys, syn, cart, planets = parseSystemLine(line)
        if sys and syn and cart then
            cartels[cart] = cartels[cart] or { name = cart, syndicate = syn, systems = {} }
            cartels[cart].systems[sys] = { name = sys, cartel = cart, syndicate = syn, planets = planets }
            syndicates[syn] = syndicates[syn] or { name = syn, cartels = {} }
            syndicates[syn].cartels[cart] = cartels[cart]   -- same table object, not a copy
        end
    end

    F2T_GALAXY.cartels    = cartels
    F2T_GALAXY.syndicates = syndicates
    F2T_GALAXY.loading = false
    F2T_GALAXY.loaded  = true
    F2T_GALAXY.builtAt = os.time()

    local nc = 0; for _ in pairs(cartels) do nc = nc + 1 end
    f2t_debug_log("[galaxy] di systems → %d cartels", nc)
    raiseEvent("f2tGalaxyIndexed", nc)
    autoExpandCurrentLocation()
    f2t_galaxy_refresh_open()
end

local scrapeTimer = nil
-- Bounds how long a scrape defers to a pending comhistory backfill (below)
-- before giving up and running anyway, in case that flag ever gets stuck.
local SCRAPE_DEFER_LIMIT = 10

function f2t_galaxy_schedule_scrape(delay, deferCount)
    if scrapeTimer then killTimer(scrapeTimer); scrapeTimer = nil end
    scrapeTimer = tempTimer(delay or 3, function()
        scrapeTimer = nil
        deferCount = deferCount or 0
        -- comhistory's own login-time backfill can still be in flight here;
        -- "di systems" would otherwise steal its lines out from under it
        -- (see F2T_GALAXY.capture_active check in comhistory.lua). Wait for
        -- it to clear rather than racing.
        if deferCount < SCRAPE_DEFER_LIMIT
           and F2T_CHAT_COMHISTORY_PENDING and F2T_CHAT_COMHISTORY_PENDING() then
            f2t_galaxy_schedule_scrape(1, deferCount + 1)
            return
        end
        local ok, err = pcall(f2t_galaxy_scrape)
        if not ok then f2t_debug_log("[galaxy] scrape error: %s", tostring(err)) end
    end)
end

-- Navigation / info

-- A system row means "take me to that system", which is its space area's link
-- room - not the namesake planet a bare name resolves to. Planet rows keep the
-- bare form so they follow the Planet nav default setting, unless a specific
-- point-of-interest flag was requested (a planet row's POI chip), in which
-- case that flag rides along in the same "<place> <flag>" grammar navigate.lua
-- already understands.
function f2t_galaxy_nav_to(kind, name, flag)
    if kind == "system" then
        expandAlias("nav " .. name .. " link")
    elseif flag then
        expandAlias("nav " .. name .. " " .. flag)
    else
        expandAlias("nav " .. name)
    end
    f2t_galaxy_hide_nav()
end

local function galaxyInfo(kind, name)
    send("di " .. kind .. " " .. name)
end

-- Explore button, present on every row type. Goes through expandAlias
-- (same as f2t_galaxy_nav_to) rather than calling the explore_*_start
-- functions directly, so the equivalent typed command echoes to the console
-- - the player can see exactly what ran, same as if they'd typed it. Unlike
-- f2t_galaxy_nav_to, this does NOT hide the navigator: exploring is a
-- longer-running, multi-step process the player wants to watch play out
-- alongside the game's own output, not a one-shot "go there" that's done
-- the moment it's sent.
function f2t_galaxy_explore(kind, name)
    expandAlias("map explore " .. kind .. " " .. name)
end

-- Search match helpers
local function qMatches(name, q)
    return name and q ~= "" and name:lower():find(q:lower(), 1, true) ~= nil
end
local function planetMatches(pd, q) return qMatches(pd.name, q) end
local function systemHasMatch(sd, q)
    if qMatches(sd.name, q) then return true end
    for _, pd in ipairs(sd.planets or {}) do if planetMatches(pd, q) then return true end end
    return false
end
local function systemHasPlanetMatch(sd, q)
    for _, pd in ipairs(sd.planets or {}) do if planetMatches(pd, q) then return true end end
    return false
end
local function cartelHasMatch(cd, q)
    if qMatches(cd.name, q) then return true end
    for _, sd in pairs(cd.systems or {}) do if systemHasMatch(sd, q) then return true end end
    return false
end
local function cartelHasChildrenMatch(cd, q)
    for _, sd in pairs(cd.systems or {}) do if systemHasMatch(sd, q) then return true end end
    return false
end
local function syndicateHasMatch(syd, q)
    if qMatches(syd.name, q) then return true end
    for _, cd in pairs(syd.cartels or {}) do if cartelHasMatch(cd, q) then return true end end
    return false
end
local function syndicateHasChildrenMatch(syd, q)
    for _, cd in pairs(syd.cartels or {}) do if cartelHasMatch(cd, q) then return true end end
    return false
end

-- Coverage: how much of the galaxy actually has map data, computed live
-- against the room DB (not F2T_GALAXY, which only ever knows what "di
-- systems" listed). ctx hoists one getAreaTable() call per populate() so
-- checking a few hundred planets costs plain table lookups, not one Mudlet
-- API round-trip apiece.
local function buildCoverageCtx()
    local ctx = { areas = getAreaTable() or {}, lowerAreas = {} }
    for nm in pairs(ctx.areas) do ctx.lowerAreas[nm:lower()] = true end
    return ctx
end

local function areaKnown(ctx, name)
    if ctx.areas[name] then return true end
    return ctx.lowerAreas[name:lower()] ~= nil
end

local function systemCoverage(ctx, sd)
    local mapped, total = 0, 0
    for _, pd in ipairs(sd.planets or {}) do
        if pd.name ~= (sd.name .. " Space") then
            total = total + 1
            if areaKnown(ctx, pd.name) then mapped = mapped + 1 end
        end
    end
    return mapped, total
end

local function cartelCoverage(ctx, cd)
    local mapped, total = 0, 0
    for sn, sd in pairs(cd.systems or {}) do
        if sn ~= (cd.name .. " Space") then
            local m, t = systemCoverage(ctx, sd)
            mapped = mapped + m; total = total + t
        end
    end
    return mapped, total
end

local function syndicateCoverage(ctx, syd)
    local mapped, total = 0, 0
    for _, cd in pairs(syd.cartels or {}) do
        local m, t = cartelCoverage(ctx, cd)
        mapped = mapped + m; total = total + t
    end
    return mapped, total
end

-- A cartel/syndicate/system with zero planets mapped still counts as
-- "partial" rather than fully unmapped when its own space area is known
-- (e.g. the link room has been logged but no planet visited yet).
local function coverageState(mapped, total, space_known)
    if total > 0 and mapped == total then return "mapped" end
    if mapped > 0 or space_known then return "partial" end
    return "unmapped"
end

-- Points of interest a planet row can offer direct nav to. Room-flag names
-- and symbols/colors come straight from map/style.lua and map/room_query.lua
-- (F2T_MAP_KNOWN_FLAGS et al) so the navigator never drifts from the map's
-- own vocabulary. "link"/"orbit" are space-area concepts, not planet POIs.
local PLANET_POI_FLAGS = { "shuttlepad", "exchange", "shipyard", "hospital", "bar", "courier" }
local FLAG_DISPLAY_NAME = {
    shuttlepad = "Shuttlepad", exchange = "Exchange", shipyard = "Shipyard",
    hospital = "Hospital", bar = "Bar", courier = "Courier",
}

-- One toggle per POI type in the global F2CE-Tools settings window (not the
-- navigator's own wrench dialog), so unchecking all six leaves just the plain
-- nav arrow on every planet row.
for _, flag in ipairs(PLANET_POI_FLAGS) do
    f2t_settings_register("galaxy", "poi_" .. flag, {
        tab         = "F2CE-Tools/Galaxy",
        label       = "Show " .. FLAG_DISPLAY_NAME[flag] .. " icon",
        description = "Show a clickable " .. FLAG_DISPLAY_NAME[flag]
            .. " icon on mapped planet rows in the Galaxy Navigator.",
        default     = true,
    })
end

local function poiVisible(flag)
    local v = f2t_settings_get("galaxy", "poi_" .. flag)
    if v == nil then return true end
    return v and true or false
end

-- Only called for planets already known to be mapped (see areaKnown), so an
-- unmapped planet never pays for a room scan that can't find anything. Most
-- player planets cram every service into the shuttlepad's own room, so a
-- flag whose room matches the shuttlepad's is folded away rather than
-- stacking a redundant chip next to it.
local function planetFlags(name)
    local area_id = f2t_map_get_area_id(name)
    if not area_id then return {} end

    local room_of = {}
    for _, flag in ipairs(PLANET_POI_FLAGS) do
        room_of[flag] = f2t_map_find_room_with_flag(area_id, flag)
    end
    local shuttlepad_room = room_of.shuttlepad

    local present = {}
    for _, flag in ipairs(PLANET_POI_FLAGS) do
        local room_id    = room_of[flag]
        local co_located = shuttlepad_room and flag ~= "shuttlepad" and room_id == shuttlepad_room
        if room_id and not co_located and poiVisible(flag) then
            present[#present + 1] = flag
        end
    end
    return present
end

-- Styles (self-contained)
local ROW_H      = 24    -- px per row (tied to font size, not pane size)
local INDENT_PCT = 4
local EXPAND_PCT = 5
local ICON_PCT   = 5
local NAV_X      = "93%"
local NAV_W      = "5%"

-- Without a QToolTip rule, a widget's own dark background bleeds into its
-- native tooltip box (unreadable/solid-black) instead of a readable one -
-- same fix as hauling_jobs.lua's _TOOLTIP_CSS. Appended to every widget's
-- own stylesheet that carries a tooltip, since Qt scopes it per-widget.
local CSS_TOOLTIP = "QToolTip{background-color:#1d2030;color:#e8ebf5;" ..
    "border:1px solid rgba(255,255,255,0.18);padding:3px;}"

local CSS_BG     = "background-color: rgb(18,18,26); border: none;"
local CSS_ROW    = "background-color: rgb(22,22,30); border: none; border-bottom: 1px solid rgba(255,255,255,35);"
local CSS_HEADER =
    "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1, stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e); " ..
    "border:none;"
local CSS_BTN    = [[
    QLabel{ background-color: rgba(40,40,45,200); border:1px solid rgba(100,100,110,180);
        border-radius:3px; color: rgba(200,200,210,255); font-size:11px; font-weight:bold;
        qproperty-alignment: AlignCenter; }
    QLabel::hover{ background-color: rgba(60,60,70,220); border-color: rgba(120,180,255,200); color:white; }
]]
-- Name-label-only styles, left-aligned so every row's name starts at the
-- same x regardless of how many POI chips (or a badge) shrink the box on
-- its right - center-aligning it (as CSS_BTN does) made the text visibly
-- drift row to row as that box width changed. Not folded into CSS_BTN
-- itself since the expand +/- button shares that constant and should stay
-- centered. No `color:` here - see NAME_COLOR below for why. No explicit
-- qproperty-alignment either: AlignLeft|AlignVCenter is QLabel's own default,
-- and setting it via a piped qproperty-alignment value (unlike every other
-- single-flag AlignCenter in this file) made Qt reject the whole rule and
-- fall back to the native white-on-black QLabel look - the "white boxes"
-- bug. Leaving it unset gets the same alignment for free, safely.
local CSS_NAME = [[
    QLabel{ background-color: rgba(40,40,45,200); border:1px solid rgba(100,100,110,180);
        border-radius:3px; font-size:11px; font-weight:bold; padding-left:4px; }
    QLabel::hover{ background-color: rgba(60,60,70,220); border-color: rgba(120,180,255,200); }
]]
local CSS_NAME_CUR = [[
    QLabel{ background-color: rgba(40,40,45,200); border:1px solid rgba(255,140,0,200);
        border-radius:3px; font-size:11px; font-weight:bold; padding-left:4px; }
    QLabel::hover{ background-color: rgba(60,60,70,220); border-color: rgba(255,165,0,255); }
]]
local CSS_NAV = [[
    QLabel{ background-color: rgba(40,120,80,210); border:1px solid rgba(60,140,100,180);
        border-radius:3px; color:white; font-size:10px; font-weight:bold; qproperty-alignment:AlignCenter; }
    QLabel::hover{ background-color: rgba(55,150,95,230); }
]]
local ICONS = {
    syndicate = { "🏛️", "#a78bfa" },
    cartel    = { "🌌", "#ff6b9d" },
    system    = { "⭐", "#ffd700" },
    planet    = { "🌍", "#4ecdc4" },
}

-- Coverage state colors and row layout for the state-dot/badge/POI-chip
-- columns createRow reserves alongside a row's icon and on its right, before
-- the nav arrow.
local STATE_COLOR = { mapped = "#7ed99a", partial = "#e0b34d", unmapped = "#767b8a" }
local BADGE_W    = 8    -- % width of the "n/m" coverage badge (syndicate/cartel/system rows)
local CHIP_W     = 4    -- % width per POI chip (planet rows)
local STATE_PCT  = 4    -- % width of the state dot, reserved before every row's icon

-- Coverage is shown as its own dot rather than tinting the row-type icon:
-- 🏛️🌌⭐🌍 are color-emoji glyphs, and Qt's QSS `color` property has no
-- effect on them (only on plain/monochrome text) - so tinting the icon
-- silently did nothing. One consistent filled-circle glyph, recolored per
-- state (green/amber/grey, the traffic-light convention), reads as a single
-- status light rather than three unrelated symbols. It doubles as the
-- explore button: clicking it explores that syndicate/cartel/system/planet,
-- so status and action live in one element instead of two.
local STATE_DOT_GLYPH = "●"
local STATE_TOOLTIP = {
    mapped   = "Explored — click to check for anything new",
    partial  = "Partially Explored — click to continue exploring",
    unmapped = "Unexplored — click to explore",
}
local ROW_TYPE_LABEL = { syndicate = "Syndicate", cartel = "Cartel", system = "System", planet = "Planet" }
-- Name text color, inline (see below) since setStyleSheet's `color:` never
-- reaches text set via :echo() in this Mudlet/Qt binding.
local NAME_COLOR = "#c8c8d2"

-- Icon button style (refresh / collapse / clear)
local CSS_ICONBTN = [[
    QLabel{ background-color: rgba(40,40,45,210); border:1px solid rgba(100,100,110,180);
        border-radius:3px; color: rgba(210,210,220,255); font-size:14px; font-weight:bold;
        qproperty-alignment: AlignCenter; }
    QLabel::hover{ background-color: rgba(60,60,70,230); border-color: rgba(120,180,255,210); color:white; }
]]
-- Header/footer heights shared by buildPanel, relayoutTopbar, and populate's autofit report.
local HEADING_ROW_H  = 28    -- vertical space the title row occupies when shown
local TOPBAR_FULL_H  = 86    -- title + search + collapse-all rows
local TOPBAR_MIN_H   = TOPBAR_FULL_H - HEADING_ROW_H   -- search + collapse-all only
local FOOTER_H       = 0     -- was the legend strip's height; kept at 0 rather than reworking
                              -- every "+ FOOTER_H" formula below now that the legend is gone

local function topbarHeightFor(inst)
    return inst.showHeading and TOPBAR_FULL_H or TOPBAR_MIN_H
end

-- Dark viewport, no horizontal bar, fixed 8px vertical bar: avoids the white
-- strip that otherwise shows left of the scrollbar when the pane shrinks.
local CSS_SCROLL = [[
    background: rgb(18,18,26); border: none;
    QScrollBar:horizontal { height: 0px; max-height: 0px; }
    QScrollBar:vertical { background: rgba(20,22,32,0.95); width: 8px; border: none; }
    QScrollBar::handle:vertical { background: rgba(70,90,135,0.85); border-radius: 4px; min-height: 16px; }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0px; border: none; }
    QAbstractScrollArea::corner { background: rgb(18,18,26); }
]]

-- One instance per content target, keyed by the pane/tab's stable _gid.
local instances = {}

-- Display prefs, content-owned (not Mux.settings) since this is a singleton
-- instance's own state; persisted via buildGalaxyDef's serialize/restore.
local GX_PREFS = {
    showHeading     = true,
    showRefreshIcon = true,
    settingsLocked  = false,
}

local function ageStr(ts)
    if not ts or ts == 0 then return "never" end
    local age = os.time() - ts
    if age < 60        then return "just now"
    elseif age < 3600  then return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then return string.format("%dh ago", math.floor(age / 3600))
    else                    return string.format("%dd ago", math.floor(age / 86400)) end
end

-- Styled row: syndicate / cartel / system / planet. cov carries the coverage
-- state populate() already computed for this node: { state, mapped, total }
-- for syndicate/cartel/system rows, { state, flags } for planet rows.
local function createRow(inst, parent, name, row_type, indent_level, y_px, data, is_current, cov)
    cov = cov or { state = "mapped" }
    local cartel_ctx    = (data and data.cartel) or ""
    local syndicate_ctx = (data and data.syndicate) or ""
    -- "_r" suffix keeps the uid from ending in a Class$ pattern Geyser would skip.
    local uid = (string.format("gx_%s_%d_%s_%s_%s", inst.gid, inst.epoch, row_type, cartel_ctx, name)
        :gsub("[^%w_]", "_")) .. "_r"

    local row = Geyser.Label:new({ name = uid, x = 0, y = y_px, width = "100%", height = ROW_H }, parent)
    row:setStyleSheet(CSS_ROW)

    local indent_pct = 1 + indent_level * INDENT_PCT

    -- Namespaced by row type so a cartel key ("cartel:Syn:Name") can never
    -- collide with a system key ("system:Cartel:Name") even when a cartel's
    -- hub system (and its syndicate) all share the same name.
    local exp_key
    if row_type == "syndicate" then exp_key = "syn:" .. name
    elseif row_type == "cartel" then exp_key = "cartel:" .. syndicate_ctx .. ":" .. name
    elseif row_type == "system" then exp_key = "system:" .. cartel_ctx .. ":" .. name end

    if exp_key then
        local is_exp = F2T_GALAXY.expanded[exp_key] or false
        local ebtn = Geyser.Label:new({ name = uid .. "_exp", x = indent_pct .. "%", y = 1,
            width = EXPAND_PCT .. "%", height = ROW_H - 2 }, row)
        ebtn:setStyleSheet(CSS_BTN)
        ebtn:echo(is_exp and "<center>−</center>" or "<center>+</center>")
        ebtn:setClickCallback(function()
            F2T_GALAXY.expanded[exp_key] = not F2T_GALAXY.expanded[exp_key]
            tempTimer(0, f2t_galaxy_refresh_open)   -- defer: don't rebuild mid click-propagation
        end)
    end

    -- Coverage state and the explore trigger live in one element: a single
    -- filled-circle status light (green/amber/grey), clicking it explores
    -- that syndicate/cartel/system/planet. A separate explore button next to
    -- it would just be a second control for information this dot already
    -- carries.
    local dot_x_pct = indent_pct + EXPAND_PCT
    local dot = Geyser.Label:new({ name = uid .. "_state", x = dot_x_pct .. "%", y = 1,
        width = STATE_PCT .. "%", height = ROW_H - 2 }, row)
    -- QLabel{}-wrapped, not a bare declaration list, even though a flat
    -- string normally works fine (see icon/badge elsewhere in this file):
    -- mixing a bare list with the appended QToolTip{} rule below is what
    -- was making Qt fall back to native (solid-black) tooltip styling here.
    dot:setStyleSheet("QLabel{ background-color:transparent; font-size:13px; font-weight:bold; }" .. CSS_TOOLTIP)
    -- The color has to live in the echoed HTML, not the label's stylesheet:
    -- setStyleSheet's `color:` never reaches text set via :echo() in this
    -- Mudlet/Qt binding (see hauling_jobs.lua's colored cells for the same
    -- pattern already proven to work).
    dot:echo(string.format("<center><span style='color:%s;'>%s</span></center>",
        STATE_COLOR[cov.state] or STATE_COLOR.unmapped, STATE_DOT_GLYPH))
    dot:setClickCallback(function() f2t_galaxy_explore(row_type, name) end)
    dot:setToolTip(STATE_TOOLTIP[cov.state] or STATE_TOOLTIP.unmapped)

    local icon_x_pct = dot_x_pct + STATE_PCT
    local ic = ICONS[row_type]
    local icon = Geyser.Label:new({ name = uid .. "_ico", x = icon_x_pct .. "%", y = 1,
        width = ICON_PCT .. "%", height = ROW_H - 2 }, row)
    -- Same QLabel{}-wrapping note as the state dot above: this widget also
    -- carries a tooltip now, so it needs the same fix.
    icon:setStyleSheet(string.format(
        "QLabel{ background-color:transparent; color:%s; font-size:11px; }%s", ic[2], CSS_TOOLTIP))
    icon:echo("<center>" .. ic[1] .. "</center>")
    icon:setToolTip(ROW_TYPE_LABEL[row_type] .. " " .. name)

    local name_x_pct = icon_x_pct + ICON_PCT
    local has_nav    = (row_type == "system" or row_type == "planet")
    local has_badge  = (row_type == "syndicate" or row_type == "cartel" or row_type == "system")
    local num_chips  = (row_type == "planet" and cov.flags) and #cov.flags or 0

    local name_end
    if row_type == "planet" then name_end = 91 - num_chips * CHIP_W
    elseif row_type == "system" then name_end = 83   -- badge occupies 84-92, nav 93-98
    elseif has_badge then name_end = 89               -- badge occupies 90-98 (no nav)
    else name_end = 97 end
    local name_w_pct = math.max(5, name_end - name_x_pct)

    local nlbl = Geyser.Label:new({ name = uid .. "_name", x = name_x_pct .. "%", y = 1,
        width = name_w_pct .. "%", height = ROW_H - 2 }, row)
    nlbl:setStyleSheet((is_current and CSS_NAME_CUR or CSS_NAME) .. CSS_TOOLTIP)
    nlbl:echo(string.format("<span style='color:%s;'>%s</span>", NAME_COLOR, name))
    nlbl:setClickCallback(function() galaxyInfo(row_type, name) end)

    local info_tip = "Click for info (di " .. row_type .. ")"
    if has_badge then
        nlbl:setToolTip(string.format("%d of %d planets mapped\n%s", cov.mapped, cov.total, info_tip))
    elseif row_type == "planet" then
        if cov.state == "unmapped" then
            nlbl:setToolTip("Not yet mapped\n" .. info_tip)
        elseif num_chips > 0 then
            local names = {}
            for _, f in ipairs(cov.flags) do names[#names + 1] = FLAG_DISPLAY_NAME[f] end
            nlbl:setToolTip(table.concat(names, ", ") .. "\n" .. info_tip)
        else
            nlbl:setToolTip("Mapped — no points of interest logged yet\n" .. info_tip)
        end
    else
        nlbl:setToolTip(info_tip)
    end

    if has_badge then
        local badge_x = (row_type == "system") and 84 or 90
        local blbl = Geyser.Label:new({ name = uid .. "_badge", x = badge_x .. "%", y = 1,
            width = BADGE_W .. "%", height = ROW_H - 2 }, row)
        blbl:setStyleSheet(
            "background-color:transparent; font-size:9px; font-weight:bold; " ..
            "qproperty-alignment: AlignRight; padding-right:2px;")
        blbl:echo(string.format("<span style='color:%s;'>%d/%d</span>", STATE_COLOR[cov.state], cov.mapped, cov.total))
    end

    if row_type == "planet" and num_chips > 0 then
        local group_start = 92 - num_chips * CHIP_W
        for i, flag in ipairs(cov.flags) do
            local cx = group_start + (i - 1) * CHIP_W
            local r, g, b = f2t_map_get_flag_badge_rgb(flag)
            r, g, b = r or 60, g or 60, b or 70
            local chip = Geyser.Label:new({ name = uid .. "_flag_" .. flag, x = cx .. "%", y = 1,
                width = CHIP_W .. "%", height = ROW_H - 2 }, row)
            chip:setStyleSheet(string.format([[
                QLabel{ background-color: rgba(%d,%d,%d,170); border:1px solid rgba(255,255,255,50);
                    border-radius:3px; font-size:9px; font-weight:bold;
                    qproperty-alignment:AlignCenter; }
                QLabel::hover{ background-color: rgba(%d,%d,%d,230); border-color: rgba(255,255,255,140); }
            ]], r, g, b, r, g, b) .. CSS_TOOLTIP)
            -- Same as the state dot/badge: color has to be inline in the
            -- echoed HTML, not the stylesheet, for it to actually apply.
            chip:echo(string.format("<span style='color:white;'>%s</span>", f2t_map_get_flag_symbol(flag) or "?"))
            chip:setClickCallback(function() f2t_galaxy_nav_to("planet", name, flag) end)
            chip:setToolTip(FLAG_DISPLAY_NAME[flag] .. " — nav " .. name .. " " .. flag)
        end
    end

    if has_nav then
        local nbtn = Geyser.Label:new({ name = uid .. "_nav", x = NAV_X, y = 1,
            width = NAV_W, height = ROW_H - 2 }, row)
        nbtn:setStyleSheet(CSS_NAV .. CSS_TOOLTIP)
        nbtn:echo("<center>→</center>")
        nbtn:setClickCallback(function() f2t_galaxy_nav_to(row_type, name) end)
        nbtn:setToolTip("Navigate here (planet nav default)")
    end

    inst.rows[#inst.rows + 1] = row
    return row
end

-- Reports total content height (topbar+rows+footer) to Mux.requestAutoFit,
-- which clamps to 85% of screen before the ScrollBox's own scrollbar takes over.
local function reportAutoFit(inst, contentH)
    if not inst.target then return end
    local h = topbarHeightFor(inst) + contentH + FOOTER_H
    inst.target._autoFitHeight = h
    if Mux and Mux.requestAutoFit then Mux.requestAutoFit(inst.target, h) end
end

-- Populate one instance's scroll tree, filtered by search
local function populate(gid)
    local inst = instances[gid]
    if not inst or not inst.scroll then return end
    inst.epoch = (inst.epoch or 0) + 1

    -- Track the live viewport so content fills the full width (no white strip
    -- by the scrollbar) and is never shorter than the viewport when collapsed.
    if inst.scroll.get_width then
        local w = inst.scroll:get_width()
        if w and w > 0 then inst.contentW = math.max(50, w) end
    end
    local viewportH = (inst.scroll.get_height and inst.scroll:get_height()) or 0
    if viewportH <= 0 then viewportH = 200 end
    pcall(function() inst.stateLbl:resize(inst.contentW, viewportH) end)
    pcall(function() inst.content:resize(inst.contentW, viewportH) end)

    for _, r in ipairs(inst.rows) do pcall(function() r:delete() end) end
    inst.rows = {}

    local g = F2T_GALAXY

    local function showState(msg)
        inst.content:hide()
        inst.stateMsg:echo("<center>" .. msg .. "</center>")
        inst.stateLbl:show()
    end

    if g.loading then showState("Loading galaxy data…"); reportAutoFit(inst, 120); return end
    if not g.loaded or not g.cartels or next(g.cartels) == nil then
        showState("Galaxy data is not loaded.<br/>Click ⟳ in the header to load it.")
        reportAutoFit(inst, 120)
        return
    end

    inst.stateLbl:hide()
    inst.content:show()

    local q = ""
    if inst.searchCmd then q = (inst.searchCmd:getText() or ""):match("^%s*(.-)%s*$") end
    local searching = q ~= ""

    local syn_sorted = {}
    for syn in pairs(g.syndicates or {}) do syn_sorted[#syn_sorted + 1] = syn end
    table.sort(syn_sorted)

    local ri         = gmcp and gmcp.room and gmcp.room.info
    local cur_cartel = ri and ri.cartel or ""
    local cur_system = ri and ri.system or ""
    local cur_area   = ri and ri.area   or ""
    local cur_planet = ""
    local _ccd = cur_cartel ~= "" and g.cartels[cur_cartel]
    local _csd = _ccd and _ccd.systems[cur_system]
    if _csd then
        for _, pd in ipairs(_csd.planets or {}) do
            if pd.name == cur_area then cur_planet = cur_area; break end
        end
    end

    -- Single getAreaTable() call for the whole populate() pass; every
    -- mapped/partial/unmapped check below is then a plain table lookup
    -- against ctx, not a fresh Mudlet API round-trip per row.
    local ctx = buildCoverageCtx()

    local y = 2
    for _, syn in ipairs(syn_sorted) do
        local syd = g.syndicates[syn]
        if not searching or syndicateHasMatch(syd, q) then
            local syn_mapped, syn_total = syndicateCoverage(ctx, syd)
            local syn_cov = { state = coverageState(syn_mapped, syn_total, false),
                mapped = syn_mapped, total = syn_total }
            createRow(inst, inst.content, syn, "syndicate", 0, y, syd, nil, syn_cov); y = y + ROW_H
            local auto_syn = searching and syndicateHasChildrenMatch(syd, q)
            local synkey   = "syn:" .. syn
            if g.expanded[synkey] or auto_syn then
                local cn_sorted = {}
                for cn in pairs(syd.cartels or {}) do cn_sorted[#cn_sorted + 1] = cn end
                table.sort(cn_sorted)
                for _, cn in ipairs(cn_sorted) do
                    local cd = syd.cartels[cn]
                    local show_c = not searching or g.expanded[synkey] or cartelHasMatch(cd, q)
                    if show_c then
                        local cart_mapped, cart_total = cartelCoverage(ctx, cd)
                        local cart_cov = { state = coverageState(cart_mapped, cart_total, false),
                            mapped = cart_mapped, total = cart_total }
                        createRow(inst, inst.content, cn, "cartel", 1, y, cd, nil, cart_cov); y = y + ROW_H
                        local ckey = "cartel:" .. syn .. ":" .. cn
                        local c_named = searching and qMatches(cd.name, q)
                        local auto_c  = searching and not c_named and cartelHasChildrenMatch(cd, q)
                        if g.expanded[ckey] or auto_c then
                            local ss = {}
                            for sn in pairs(cd.systems or {}) do ss[#ss + 1] = sn end
                            table.sort(ss)
                            for _, sn in ipairs(ss) do
                                if sn ~= (cn .. " Space") then
                                    local sd = cd.systems[sn]
                                    local show_s = not searching or g.expanded[ckey] or systemHasMatch(sd, q)
                                    if show_s then
                                        local sys_cur = (sn == cur_system) and (cn == cur_cartel) and (cur_planet == "")
                                        local sys_mapped, sys_total = systemCoverage(ctx, sd)
                                        local space_known = areaKnown(ctx, sn .. " Space")
                                        local sys_cov = { state = coverageState(sys_mapped, sys_total, space_known),
                                            mapped = sys_mapped, total = sys_total }
                                        createRow(inst, inst.content, sn, "system", 2, y, sd, sys_cur, sys_cov)
                                        y = y + ROW_H
                                        local skey = "system:" .. cn .. ":" .. sn
                                        local s_named = searching and qMatches(sd.name, q)
                                        local auto_s  = searching and not s_named and systemHasPlanetMatch(sd, q)
                                        if g.expanded[skey] or auto_s then
                                            for _, pd in ipairs(sd.planets or {}) do
                                                if pd.name ~= (sn .. " Space") then
                                                    local show_p =
                                                        not searching or g.expanded[skey] or planetMatches(pd, q)
                                                    if show_p then
                                                        local pcur = (pd.name == cur_planet) and (sn == cur_system)
                                                        local p_mapped = areaKnown(ctx, pd.name)
                                                        local p_cov = { state = p_mapped and "mapped" or "unmapped",
                                                            flags = p_mapped and planetFlags(pd.name) or {} }
                                                        createRow(inst, inst.content, pd.name, "planet", 3, y, pd,
                                                            pcur, p_cov)
                                                        y = y + ROW_H
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Resize AFTER all rows exist; resizing mid-loop corrupts container refs.
    pcall(function() inst.content:resize(inst.contentW or 200, math.max(y + 4, viewportH)) end)
    reportAutoFit(inst, y + 4)

    -- reportAutoFit's pane shrink lands a tick later (async autofit), so the
    -- resize above -- sized against the viewport height read at the TOP of
    -- this call, before the shrink -- can end up shorter than the pane once
    -- it actually settles. That gap exposes the scrollbox's own unstyled
    -- native background (white; Geyser.ScrollBox has no working setStyleSheet)
    -- until something else forces a resize. Re-measure and re-cover once the
    -- shrink has actually landed.
    local epoch = inst.epoch
    tempTimer(0, function()
        local i = instances[gid]
        if not i or i.epoch ~= epoch then return end   -- a newer populate() has since run
        local freshH = (i.scroll.get_height and i.scroll:get_height()) or 0
        if freshH > 0 then
            pcall(function() i.content:resize(i.contentW or 200, math.max(y + 4, freshH)) end)
        end
    end)

    -- New rows are visible by default regardless of parent hidden state, so
    -- re-assert hidden here or they'd flash visible on a condition-hidden pane.
    if Mux and Mux.reassertHidden then Mux.reassertHidden(inst.content) end
end

-- True while the hosting pane/tab (or its owning pane) is condition-hidden;
-- the search poll idles then instead of reading the command line.
local function targetHidden(target)
    local t = target
    while t do
        if t._conditionHidden then return true end
        t = t.pane
    end
    return false
end

-- Resolves the pane/tab a titlebarElements callback's ctx acts on (singleton
-- content still lives on one pane/tab).
local function galaxyTargetFor(ctx)
    return ctx and (ctx.tab or ctx.pane)
end

-- Settings wrench hides once locked; `mux reveal <id>` (onReveal below) is
-- the only way to unlock it.
local function settingsIconLocked()
    return GX_PREFS.settingsLocked
end

-- Forces an immediate titlebar re-layout after a visibility flag changes
-- outside the normal click path (locking/revealing the settings icon).
local function refreshOwningTitlebar(target)
    local p = target and (target.pane or target)
    if p and p._layoutTitlebarButtons then p:_layoutTitlebarButtons() end
end

-- Hiding the title collapses its space instead of leaving it blank;
-- re-fits the scroll area and re-populates to match.
local function relayoutTopbar(inst)
    if not inst.topbar then return end
    local th = topbarHeightFor(inst)
    local searchY, collapseY
    if inst.showHeading then searchY, collapseY = 34, 60 else searchY, collapseY = 6, 32 end

    inst.topbar:resize(nil, th)
    if inst.title then
        if inst.showHeading then inst.title:show() else inst.title:hide() end
    end
    if inst.searchCmd   then inst.searchCmd:move(nil, searchY) end
    if inst.clearBtn    then inst.clearBtn:move(nil, searchY) end
    if inst.collapseBtn then inst.collapseBtn:move(nil, collapseY) end
    if inst.scroll then
        inst.scroll:move(nil, th)
        inst.scroll:resize(nil, "100%-" .. (th + FOOTER_H) .. "px")
    end
    populate(inst.gid)
end

-- Settings dialog
local function openGalaxySettings(target)
    local gid  = target and target._gid
    local inst = gid and instances[gid]
    if not inst then return end

    local d = Mux.createDialog({
        title = "Galaxy Navigator Settings - " .. Mux._targetPath(target),
        width = 380, height = 220, singleton = "f2t_galaxy_settings_" .. (target.id or gid),
        contextMenu = false,
    })
    if not d then return end
    if d.contentBg then d.contentBg:echo(""); d.contentBg:hide() end

    -- Visibility toggles only; Refresh lives in titlebarElements, not here.
    local rows = {
        { label = "Show Heading", type = "toggle",
          desc = "Show the '🔭 Galaxy Navigator' title inside the panel; hiding it collapses that space.",
          readFn = function() return inst.showHeading end,
          writeFn = function(v)
              inst.showHeading = v
              GX_PREFS.showHeading = v
              relayoutTopbar(inst)
          end },
        { label = "Show Refresh Icon", type = "toggle",
          desc = "Show the refresh (🔄) control on the titlebar / right-click menu.",
          readFn = function() return GX_PREFS.showRefreshIcon end,
          writeFn = function(v)
              GX_PREFS.showRefreshIcon = v
              refreshOwningTitlebar(target)
          end },
        { label = "Lock (hide settings icon)", type = "toggle",
          desc = "Hide the settings wrench so the panel looks final. Bring it back with:  mux reveal <pane id>",
          readFn = function() return settingsIconLocked() end,
          writeFn = function(v)
              GX_PREFS.settingsLocked = v
              refreshOwningTitlebar(target)
          end },
    }
    d:mountForm(rows, { prefix = d._gid .. "_gxset" })

    -- Warn before closing while locked, since mux reveal is the only way back.
    if d.closeBtn then
        d.closeBtn:setClickCallback(function(event)
            if event.button ~= "LeftButton" then return end
            if settingsIconLocked() then
                local msg = "This panel is <b>locked</b> - the settings wrench is now hidden.<br/>"
                         .. "To bring it back, run: "
                         .. "<tt style='color:#8ab4ff;'>mux reveal " .. (target.id or "&lt;id&gt;") .. "</tt>"
                Mux._showPropsCloseConfirm(msg, function() d:close() end)
            else
                d:close()
            end
        end)
    end
end

-- Builds header/scroll/footer panel for a content target
local function buildPanel(target)
    local gid = target._gid
    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end
    if instances[gid] then populate(gid); return end

    local C = target.content
    local inst = { gid = gid, epoch = 0, rows = {}, target = target }
    instances[gid] = inst

    -- Header bar: title / search+clear / collapse-all rows. Built at "heading
    -- shown" position; relayoutTopbar (below) corrects it to the real state.
    inst.topbar = Geyser.Label:new({ name = gid .. "_gx_top", x = 0, y = 0, width = "100%", height = TOPBAR_FULL_H }, C)
    inst.topbar:setStyleSheet(CSS_HEADER)

    -- Row 1: title
    inst.title = Geyser.Label:new({
        name = gid .. "_gx_title", x = 8, y = 6, width = "100%-16px", height = 22,
    }, inst.topbar)
    inst.title:setStyleSheet("background-color:transparent; color:#c8c8d0; font-size:11px; font-weight:bold;")
    inst.title:echo("🔭 Galaxy Navigator")

    inst.showHeading = GX_PREFS.showHeading

    -- Row 2: search box (fills) + clear (✕) square on the far right
    inst.searchCmd = Geyser.CommandLine:new({
        name = gid .. "_gx_search", x = 8, y = 34, width = "100%-44px", height = 24,
    }, inst.topbar)
    inst.searchCmd:setStyleSheet([[
        background-color: rgb(10,10,16); color: rgba(200,200,210,255); font-size:11px; font-weight:bold;
        border:1px solid rgba(100,100,110,180); border-radius:3px; padding-left:4px; padding-right:4px;
    ]])
    inst.searchCmd:setAction(function() end)   -- never submit to the game on Enter

    inst.clearBtn = Geyser.Label:new({
        name = gid .. "_gx_clear", x = "-30", y = 34, width = 24, height = 24,
    }, inst.topbar)
    inst.clearBtn:setStyleSheet(CSS_ICONBTN)
    inst.clearBtn:echo("<center>✕</center>")
    inst.clearBtn:setToolTip("Clear search")
    inst.clearBtn:setClickCallback(function()
        if inst.searchCmd then
            if inst.searchCmd.clear then pcall(function() inst.searchCmd:clear() end)
            else pcall(function() inst.searchCmd:setText("") end) end
        end
        inst.lastSearch = ""
        populate(gid)
    end)

    -- Row 3: collapse-all square (minus), left-aligned with the cartel expand column
    inst.collapseBtn = Geyser.Label:new({
        name = gid .. "_gx_col", x = "1%", y = 60, width = 22, height = 22,
    }, inst.topbar)
    inst.collapseBtn:setStyleSheet(CSS_ICONBTN)
    inst.collapseBtn:echo("<center>−</center>")
    inst.collapseBtn:setToolTip("Collapse all")
    inst.collapseBtn:setClickCallback(function() F2T_GALAXY.expanded = {}; f2t_galaxy_refresh_open() end)

    -- Scroll area (styled chrome so no white strip appears beside the scrollbar)
    inst.scroll = Geyser.ScrollBox:new({ name = gid .. "_gx_scroll", x = 0, y = TOPBAR_FULL_H,
        width = "100%", height = "100%-" .. (TOPBAR_FULL_H + FOOTER_H) .. "px" }, C)
    pcall(function() inst.scroll:setStyleSheet(CSS_SCROLL) end)
    -- Content fills the FULL scrollbox width; the 8px scrollbar overlaps only
    -- the right edge (rows are left-anchored), so no white column is left uncovered.
    inst.contentW = math.max(50, inst.scroll:get_width() or 220)

    -- Permanent state label (loading / empty) and the row container.
    inst.stateLbl = Geyser.Label:new(
        { name = gid .. "_gx_state", x = 0, y = 0, width = inst.contentW, height = 2000 }, inst.scroll)
    inst.stateLbl:setStyleSheet(CSS_BG)
    inst.stateMsg = Geyser.Label:new(
        { name = gid .. "_gx_statemsg", x = 0, y = "35%", width = "100%", height = 60 }, inst.stateLbl)
    inst.stateMsg:setStyleSheet("background-color:transparent; color:rgba(190,190,200,210); font-size:11px;")

    inst.content = Geyser.Label:new(
        { name = gid .. "_gx_content", x = 0, y = 0, width = inst.contentW, height = 2000 }, inst.scroll)
    inst.content:setStyleSheet(CSS_BG)

    -- No footer legend: row-type and coverage-state meaning now live in each
    -- icon/dot's own tooltip instead (see icon:setToolTip/dot:setToolTip in
    -- createRow), so there's nothing left for a legend strip to explain.

    -- No-op until the scrape lands; f2t_galaxy_finish_capture re-runs this
    -- once data is ready, so an early-opened navigator still catches up.
    autoExpandCurrentLocation()

    relayoutTopbar(inst)

    -- Debounced search poll: rebuilds shortly after typing stops; idles
    -- entirely while the hosting pane/tab is condition-hidden.
    inst.pollActive = true
    inst.lastSearch = nil
    local function poll()
        local i = instances[gid]
        if not i or not i.pollActive then return end
        if i.target and targetHidden(i.target) then
            tempTimer(0.5, poll)
            return
        end
        local q = (i.searchCmd and i.searchCmd:getText() or ""):match("^%s*(.-)%s*$")
        if q ~= i.lastSearch then
            i.lastSearch = q
            if i.searchDebounce then killTimer(i.searchDebounce) end
            i.searchDebounce = tempTimer(0.3, function()
                i.searchDebounce = nil
                if instances[gid] then populate(gid) end
            end)
        end
        tempTimer(0.4, poll)
    end
    tempTimer(0.4, poll)
end

local function teardownPanel(gid)
    local inst = instances[gid]
    if not inst then return end
    inst.pollActive = false
    if inst.searchDebounce then killTimer(inst.searchDebounce); inst.searchDebounce = nil end
    instances[gid] = nil   -- widgets are children of target.content; the slot delete removes them
end

function f2t_galaxy_refresh_open()
    for gid in pairs(instances) do pcall(populate, gid) end
end

-- Content type definition
local function buildGalaxyDef()
    return {
        name        = "Galaxy Navigator",
        description = "Browse every syndicate, cartel, system, and planet from 'di systems'; click → to travel.",
        group       = "F2CE Tools",
        -- One navigator at a time: Muxlet tracks the active instance itself
        -- (def._activeTargetRef).
        singleton   = true,

        -- Refresh + Settings publish to the hosting pane/tab's titlebar and
        -- right-click menu; menuFallbackOnly keeps them off the ⋯ menu unless
        -- folded/compact or on a tab with no titlebar. The settings wrench
        -- itself uses the stronger Lock + `mux reveal` pattern since hiding
        -- it would otherwise be a dead end.
        titlebarElements = {
            {
                id = "galaxy.refresh", side = "left", group = "content", order = 0, priority = 100,
                icon = "🔄", tooltip = "Refresh (di systems)",
                visible = function() return GX_PREFS.showRefreshIcon end,
                onClick = function(_ctx, event)
                    if not event or event.button == "LeftButton" then f2t_galaxy_scrape() end
                end,
                menuText = function() return "🔄  Refresh - last: " .. ageStr(F2T_GALAXY.builtAt) end,
                menuGroup = "info", menuOrder = 90,
                menuFallbackOnly = true,
                run = function() f2t_galaxy_scrape() end,
            },
            {
                id = "galaxy.settings", side = "left", group = "content", order = 1, priority = 101,
                icon = "🔧", tooltip = "Galaxy Navigator settings",
                visible = function() return not settingsIconLocked() end,
                onClick = function(ctx, event)
                    if not event or event.button == "LeftButton" then
                        openGalaxySettings(galaxyTargetFor(ctx))
                    end
                end,
                menuText = "🔧  Galaxy settings…",
                menuGroup = "info", menuOrder = 95,
                menuFallbackOnly = true,
                run = function(ctx) openGalaxySettings(galaxyTargetFor(ctx)) end,
            },
        },

        apply = function(target)
            local ok, err = pcall(buildPanel, target)
            if not ok and f2t_debug_log then f2t_debug_log("[galaxy] apply error: %s", tostring(err)) end
        end,

        remove = function(target)
            teardownPanel(target._gid)
        end,

        resize = function(target)
            if instances[target._gid] then populate(target._gid) end
        end,

        -- GX_PREFS persists via this singleton target's serialize/restore.
        serialize = function(_target)
            return {
                showHeading     = GX_PREFS.showHeading,
                showRefreshIcon = GX_PREFS.showRefreshIcon,
                settingsLocked  = GX_PREFS.settingsLocked,
            }
        end,
        restore = function(target, data)
            if type(data) ~= "table" then return end
            if type(data.showHeading)     == "boolean" then GX_PREFS.showHeading     = data.showHeading end
            if type(data.showRefreshIcon) == "boolean" then GX_PREFS.showRefreshIcon = data.showRefreshIcon end
            if type(data.settingsLocked)  == "boolean" then GX_PREFS.settingsLocked  = data.settingsLocked end
            local inst = instances[target._gid]
            if inst then inst.showHeading = GX_PREFS.showHeading; relayoutTopbar(inst) end
        end,
        -- `mux reveal <pane id>` clears the settings-wrench lock.
        onReveal = function(target)
            if settingsIconLocked() then
                GX_PREFS.settingsLocked = false
                refreshOwningTitlebar(target)
            end
            populate(target._gid)
        end,
    }
end

-- Content is added to a pane via the Content Library, not created here;
-- Muxlet's pane persistence keeps the placement. These helpers find the
-- singleton's active target and toggle its condition-hidden state.
local function currentNavTarget()
    local def = Mux._content and Mux._content.fed2_galaxy
    return def and def._activeTargetRef or nil
end

-- A tab hosting sub-tabs is itself a .pane host, so a nested sub-tab needs
-- more than one hop up to the owning MuxPane.
local function rootPaneOf(t)
    while t and t.pane do t = t.pane end
    return t
end

function f2t_galaxy_hide_nav()
    local t = currentNavTarget()
    if t and t._conditionHide and not t._conditionHidden then t:_conditionHide() end
end

function f2t_galaxy_show_nav()
    local t = currentNavTarget()
    if not t then
        cecho("\n<red>[f2ce-tools]<reset> No Galaxy navigator pane yet — add the "
            .. "<cyan>Galaxy Navigator<reset> content to a pane from the Content Library first.\n")
        return
    end
    if t._conditionShow and t._conditionHidden then t:_conditionShow() end
    if Mux.raisePane then Mux.raisePane(rootPaneOf(t)) end
    f2t_galaxy_refresh_open()
end

-- Registration (init.lua's muxletReady calls this)
function f2tRegisterGalaxy()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("fed2_galaxy", buildGalaxyDef())
    -- Package (re)install re-enables all triggers; park the catch-all capture
    -- triggers unless a scrape is actually in flight.
    if not F2T_GALAXY.capture_active then setCaptureTriggers(false) end
    -- Only scrape here for a genuine hot-reload with no index yet; normal
    -- login schedules via f2tCharacterChanged. Guarding on `loaded` avoids a
    -- redundant re-scrape if this registrar re-runs after a mid-session install.
    if f2t_check_connection then f2t_check_connection() end
    if not F2T_GALAXY.loaded and F2T_CONNECTED ~= false and F2T_LOGGED_IN then
        f2t_galaxy_schedule_scrape(3)
    end
    f2t_debug_log("[galaxy] registered content")
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterGalaxy)

-- Don't scrape on connect; di systems would fire mid-login.
-- f2tCharacterChanged (below) schedules it once login is confirmed.
registerAnonymousEventHandler("sysConnectionEvent", function()
    if f2t_check_connection then f2t_check_connection() end
    f2t_galaxy_refresh_open()
end)

registerAnonymousEventHandler("f2tCharacterChanged", function()
    f2t_galaxy_schedule_scrape(3)
end)

-- Fires on every room move (including each hop of a speedwalk); keeps the
-- orange current-location highlight tracking the player live instead of
-- only refreshing on scrape/settings/search interactions. This also keeps
-- coverage/POI state live as you explore, since populate() recomputes both
-- fresh off the room DB every time - no separate cache to go stale.
registerAnonymousEventHandler("gmcp.room.info", function()
    f2t_galaxy_refresh_open()
end)

-- Bulk map changes (delete/clear, import) don't necessarily move the player,
-- so they can't rely on gmcp.room.info to trigger a repaint.
registerAnonymousEventHandler("f2tMapDataChanged", function()
    f2t_galaxy_refresh_open()
end)

f2t_debug_log("[galaxy] module loaded")
