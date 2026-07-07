-- fed2-tools — Galaxy Navigator
--
-- Data comes from the in-game "di systems" command — a full listing of every
-- cartel, system, and planet — NOT the Mudlet map DB. This matters because a
-- player's map may be incomplete, whereas "di systems" is always authoritative.
-- The capture/parse mirrors the v1 archive's ui_galaxy module.
--
-- Two pieces, registered with Muxlet from init.lua's muxletReady handler via
-- f2tRegisterGalaxy():
--
--   1. A background "di systems" scrape, run at load (once connected) and on
--      (re)connect / character change. Output lines are captured and deleted by
--      two triggers, so nothing spams the main console. Because the index is
--      pre-built in the background, opening the navigator is instant.
--
--   2. A "fed2_galaxy" Muxlet content type (singleton) rendering the cartel →
--      system → planet tree in a scrollable console (expand/collapse, click a
--      name for "di" info, click → to navigate). Add it to a pane from the
--      Content Library, position/anchor that pane, and save the workspace —
--      Muxlet's own pane persistence carries the placement from there. To
--      show/hide it from a Button Grid button, bind the button to Muxlet's
--      generic "Toggle Pane/Tab Visibility" action and pick that pane as the
--      target (see Muxlet's conditional.lua / contentLibrary/buttons.lua).

-- ── Data store ───────────────────────────────────────────────────────────────
-- cartels[cartel] = { name, systems = { [sys] = { name, cartel, planets = { {name,system,cartel}, ... } } } }
F2T_GALAXY = F2T_GALAXY or {
    cartels        = {},
    loaded         = false,
    loading        = false,
    builtAt        = 0,        -- unix time of last successful scrape
    capture_active = false,
    capture_lines  = {},
    expanded       = {},       -- [key]=true; session-only expand state
}

-- ── "di systems" capture (mirrors the v1 archive methodology) ──────────────────

-- Completion is silence-based (0.5s of no further di-systems-shaped output),
-- reset on every line seen while capturing — NOT "the first blank line ends
-- it". Fed2's login sequence can interleave unrelated blank lines (and other
-- chatter) mid-response while this scrape runs in the background; treating any
-- blank line as authoritative "end of di systems" cut capture short after just
-- the first few entries, leaking the (much longer) remainder of the listing
-- straight to the console. See CLAUDE.md's "Timer-Based Completion Rules".
-- The capture triggers include catch-all line patterns (galaxy_nav_line ^(.+)$,
-- galaxy_nav_end ^$) that otherwise run on every line of output forever. They
-- are armed only for the duration of a scrape.
local function setCaptureTriggers(on)
    local fn = on and enableTrigger or disableTrigger
    pcall(fn, "galaxy_nav_line")
    pcall(fn, "galaxy_nav_end")
end

local finishTimer = nil
local function resetFinishTimer()
    if finishTimer then killTimer(finishTimer) end
    finishTimer = tempTimer(0.5, function()
        finishTimer = nil
        if F2T_GALAXY.capture_active then f2t_galaxy_finish_capture() end
    end)
end

-- Send "di systems" and begin capturing. Safe to call repeatedly; the loading
-- guard prevents overlap. Bails when offline (the command needs the game).
function f2t_galaxy_scrape()
    if not F2T_LOGGED_IN then
        f2t_debug_log("[galaxy] scrape skipped (not logged in)")
        return
    end
    if F2T_GALAXY.loading then return end
    if F2T_CONNECTED == false then
        f2t_debug_log("[galaxy] scrape skipped (offline)")
        return
    end
    F2T_GALAXY.loading        = true
    F2T_GALAXY.capture_active = true
    F2T_GALAXY.capture_lines  = {}
    setCaptureTriggers(true)
    f2t_galaxy_refresh_open()              -- show the loading state in any open navigator
    sendAll("di systems", false)           -- false = don't echo the command; triggers delete the output
    resetFinishTimer()
end

-- Called by the galaxy_nav_line trigger for every line while capture is active.
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
    -- Lines matching neither (command echo, stray text) are ignored.
end

-- Called by the galaxy_nav_end trigger for a blank line while capture is
-- active — hidden (it's still part of an automated background command) but
-- no longer treated as "the" terminator; see resetFinishTimer above.
function f2t_galaxy_capture_blank()
    if not F2T_GALAXY.capture_active then return end
    resetFinishTimer()
end

-- Parse one combined system line into its components.
-- Format: "SystemName - CartelName cartel - Rank Owner[tag]: Planet(T) Planet(T) ..."
local function parseSystemLine(line)
    local system_name, cartel_name, planet_str =
        line:match("^(.+) %- (.+) cartel %- [^:]+: (.*)$")
    if not system_name then return nil end
    system_name = system_name:match("^%s*(.-)%s*$")
    cartel_name = cartel_name:match("^%s*(.-)%s*$")

    local planets = {}
    -- "Planet Name(T)" where T is the planet type tag in parentheses.
    for planet_name in (planet_str or ""):gmatch("(.-)%([^%)]+%)%s*") do
        planet_name = planet_name:match("^%s*(.-)%s*$")
        if planet_name ~= "" then
            planets[#planets + 1] = { name = planet_name, system = system_name, cartel = cartel_name }
        end
    end
    return system_name, cartel_name, planets
end

-- Called when the 0.5s silence timer (resetFinishTimer) expires.
function f2t_galaxy_finish_capture()
    if not F2T_GALAXY.capture_active then return end
    F2T_GALAXY.capture_active = false
    setCaptureTriggers(false)
    if finishTimer then killTimer(finishTimer); finishTimer = nil end

    if #F2T_GALAXY.capture_lines == 0 then
        F2T_GALAXY.loading = false
        f2t_galaxy_refresh_open()
        return
    end

    local cartels = {}
    for _, line in ipairs(F2T_GALAXY.capture_lines) do
        local sys, cart, planets = parseSystemLine(line)
        if sys and cart then
            cartels[cart] = cartels[cart] or { name = cart, systems = {} }
            cartels[cart].systems[sys] = { name = sys, cartel = cart, planets = planets }
        end
    end

    F2T_GALAXY.cartels = cartels
    F2T_GALAXY.loading = false
    F2T_GALAXY.loaded  = true
    F2T_GALAXY.builtAt = os.time()

    local nc = 0; for _ in pairs(cartels) do nc = nc + 1 end
    f2t_debug_log("[galaxy] di systems → %d cartels", nc)
    raiseEvent("f2tGalaxyIndexed", nc)
    f2t_galaxy_refresh_open()
end

-- Debounced scheduler so neither load nor reconnect fires multiple scrapes.
local scrapeTimer = nil
function f2t_galaxy_schedule_scrape(delay)
    if scrapeTimer then killTimer(scrapeTimer); scrapeTimer = nil end
    scrapeTimer = tempTimer(delay or 3, function()
        scrapeTimer = nil
        local ok, err = pcall(f2t_galaxy_scrape)
        if not ok then f2t_debug_log("[galaxy] scrape error: %s", tostring(err)) end
    end)
end

-- ── Navigation / info ────────────────────────────────────────────────────────

function f2t_galaxy_nav_to(kind, name)
    expandAlias("nav " .. name)          -- routes via the fed2-tools nav alias
    f2t_galaxy_hide_nav()                -- tidy away the dedicated navigator after picking
end

local function galaxyInfo(kind, name)
    send("di " .. kind .. " " .. name)   -- cartel / system / planet detail to the main console
end

-- ── Search match helpers (ported from v1 archive ui_galaxy) ───────────────────
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

-- ── Styles (self-contained; no dependency on the v1 UI.style table) ───────────
local ROW_H      = 24    -- px per row (tied to font size, not pane size)
local INDENT_PCT = 4
local EXPAND_PCT = 5
local ICON_PCT   = 5
local NAV_X      = "93%"
local NAV_W      = "5%"

local CSS_BG     = "background-color: rgb(18,18,26); border: none;"
local CSS_ROW    = "background-color: rgb(22,22,30); border: none; border-bottom: 1px solid rgba(255,255,255,35);"
local CSS_HEADER = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1, stop:0 #2a2a3a, stop:0.4 #1e1e2a, stop:1 #16161e); border:none;"
local CSS_BTN    = [[
    QLabel{ background-color: rgba(40,40,45,200); border:1px solid rgba(100,100,110,180);
        border-radius:3px; color: rgba(200,200,210,255); font-size:11px; font-weight:bold;
        qproperty-alignment: AlignCenter; }
    QLabel::hover{ background-color: rgba(60,60,70,220); border-color: rgba(120,180,255,200); color:white; }
]]
local CSS_BTN_CUR = [[
    QLabel{ background-color: rgba(40,40,45,200); border:1px solid rgba(255,140,0,200);
        border-radius:3px; color: rgba(200,200,210,255); font-size:11px; font-weight:bold;
        qproperty-alignment: AlignCenter; }
    QLabel::hover{ background-color: rgba(60,60,70,220); border-color: rgba(255,165,0,255); color:white; }
]]
local CSS_NAV = [[
    QLabel{ background-color: rgba(40,120,80,210); border:1px solid rgba(60,140,100,180);
        border-radius:3px; color:white; font-size:10px; font-weight:bold; qproperty-alignment:AlignCenter; }
    QLabel::hover{ background-color: rgba(55,150,95,230); }
]]
local ICONS = { cartel = { "🌌", "#ff6b9d" }, system = { "⭐", "#ffd700" }, planet = { "🌍", "#4ecdc4" } }

-- Small square icon button (refresh / collapse / clear): bordered square, bigger glyph.
local CSS_ICONBTN = [[
    QLabel{ background-color: rgba(40,40,45,210); border:1px solid rgba(100,100,110,180);
        border-radius:3px; color: rgba(210,210,220,255); font-size:14px; font-weight:bold;
        qproperty-alignment: AlignCenter; }
    QLabel::hover{ background-color: rgba(60,60,70,230); border-color: rgba(120,180,255,210); color:white; }
]]

-- ScrollBox chrome (copied from the gmcp viewer fix): dark viewport, no horizontal
-- bar, a fixed 8px dark vertical bar, and a dark corner.  Combined with content
-- that fills the FULL scrollbox width, this removes the white strip that used to
-- appear left of the scrollbar when shrinking the pane.
local CSS_SCROLL = [[
    background: rgb(18,18,26); border: none;
    QScrollBar:horizontal { height: 0px; max-height: 0px; }
    QScrollBar:vertical { background: rgba(20,22,32,0.95); width: 8px; border: none; }
    QScrollBar::handle:vertical { background: rgba(70,90,135,0.85); border-radius: 4px; min-height: 16px; }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0px; border: none; }
    QAbstractScrollArea::corner { background: rgb(18,18,26); }
]]

-- One instance per content target, keyed by the pane/tab's stable _gid.
-- Each holds its own header/scroll/footer widgets and search state.
local instances = {}

local function ageStr(ts)
    if not ts or ts == 0 then return "never" end
    local age = os.time() - ts
    if age < 60        then return "just now"
    elseif age < 3600  then return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then return string.format("%dh ago", math.floor(age / 3600))
    else                    return string.format("%dd ago", math.floor(age / 86400)) end
end

-- ── Styled row (cartel / system / planet) ────────────────────────────────────
local function createRow(inst, parent, name, row_type, indent_level, y_px, data, is_current)
    local cartel_ctx = (data and data.cartel) or ""
    -- "_r" suffix keeps the uid from ending in a Class$ pattern Geyser would skip.
    local uid = (string.format("gx_%s_%d_%s_%s_%s", inst.gid, inst.epoch, row_type, cartel_ctx, name)
        :gsub("[^%w_]", "_")) .. "_r"

    local row = Geyser.Label:new({ name = uid, x = 0, y = y_px, width = "100%", height = ROW_H }, parent)
    row:setStyleSheet(CSS_ROW)

    local indent_pct = 1 + indent_level * INDENT_PCT

    local exp_key
    if row_type == "cartel" then exp_key = name
    elseif row_type == "system" then exp_key = cartel_ctx .. ":" .. name end

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

    local icon_x_pct = indent_pct + EXPAND_PCT
    local ic = ICONS[row_type]
    local icon = Geyser.Label:new({ name = uid .. "_ico", x = icon_x_pct .. "%", y = 1,
        width = ICON_PCT .. "%", height = ROW_H - 2 }, row)
    icon:setStyleSheet(string.format("background-color:transparent; color:%s; font-size:11px;", ic[2]))
    icon:echo("<center>" .. ic[1] .. "</center>")

    local name_x_pct = icon_x_pct + ICON_PCT
    local has_nav    = (row_type == "system" or row_type == "planet")
    local name_end   = has_nav and 91 or 97
    local name_w_pct = math.max(5, name_end - name_x_pct)

    local nlbl = Geyser.Label:new({ name = uid .. "_name", x = name_x_pct .. "%", y = 1,
        width = name_w_pct .. "%", height = ROW_H - 2 }, row)
    nlbl:setStyleSheet(is_current and CSS_BTN_CUR or CSS_BTN)
    nlbl:echo(name)
    nlbl:setClickCallback(function() galaxyInfo(row_type, name) end)
    nlbl:setToolTip("Click for info (di " .. row_type .. ")")

    if has_nav then
        local nbtn = Geyser.Label:new({ name = uid .. "_nav", x = NAV_X, y = 1,
            width = NAV_W, height = ROW_H - 2 }, row)
        nbtn:setStyleSheet(CSS_NAV)
        nbtn:echo("<center>→</center>")
        nbtn:setClickCallback(function() f2t_galaxy_nav_to(row_type, name) end)
        nbtn:setToolTip("Navigate here")
    end

    inst.rows[#inst.rows + 1] = row
    return row
end

-- ── Populate one instance's scroll tree (with search filtering) ───────────────
local function populate(gid)
    local inst = instances[gid]
    if not inst or not inst.scroll then return end
    inst.epoch = (inst.epoch or 0) + 1

    -- Track the live viewport so content fills the full width (no white strip by
    -- the scrollbar) and is never shorter than the viewport (no white gap below
    -- the rows when collapsed).
    if inst.scroll.get_width then
        local w = inst.scroll:get_width()
        if w and w > 0 then inst.contentW = math.max(50, w) end
    end
    local viewportH = (inst.scroll.get_height and inst.scroll:get_height()) or 0
    if viewportH <= 0 then viewportH = 200 end
    pcall(function() inst.stateLbl:resize(inst.contentW, viewportH) end)
    pcall(function() inst.content:resize(inst.contentW, viewportH) end)

    if inst.refreshIcon then
        inst.refreshIcon:setToolTip("Refresh — last: " .. ageStr(F2T_GALAXY.builtAt))
    end

    for _, r in ipairs(inst.rows) do pcall(function() r:delete() end) end
    inst.rows = {}

    local g = F2T_GALAXY

    -- State (loading / empty) shown on the permanent state label.
    local function showState(msg)
        inst.content:hide()
        inst.stateMsg:echo("<center>" .. msg .. "</center>")
        inst.stateLbl:show()
    end

    if g.loading then showState("Loading galaxy data…"); return end
    if not g.loaded or not g.cartels or next(g.cartels) == nil then
        showState("Galaxy data is not loaded.<br/>Click ⟳ in the header to load it."); return
    end

    inst.stateLbl:hide()
    inst.content:show()

    local q = ""
    if inst.searchCmd then q = (inst.searchCmd:getText() or ""):match("^%s*(.-)%s*$") end
    local searching = q ~= ""

    local sorted = {}
    for cn in pairs(g.cartels) do sorted[#sorted + 1] = cn end
    table.sort(sorted)

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

    local y = 2
    for _, cn in ipairs(sorted) do
        local cd = g.cartels[cn]
        if not searching or cartelHasMatch(cd, q) then
            createRow(inst, inst.content, cn, "cartel", 0, y, cd); y = y + ROW_H
            local auto_c = searching and cartelHasChildrenMatch(cd, q)
            if g.expanded[cn] or auto_c then
                local ss = {}
                for sn in pairs(cd.systems or {}) do ss[#ss + 1] = sn end
                table.sort(ss)
                for _, sn in ipairs(ss) do
                    if sn ~= (cn .. " Space") then
                        local sd = cd.systems[sn]
                        local show_s = not searching or g.expanded[cn] or systemHasMatch(sd, q)
                        if show_s then
                            local sys_cur = (sn == cur_system) and (cn == cur_cartel) and (cur_planet == "")
                            createRow(inst, inst.content, sn, "system", 1, y, sd, sys_cur); y = y + ROW_H
                            local skey = cn .. ":" .. sn
                            local s_named = searching and qMatches(sd.name, q)
                            local auto_s  = searching and not s_named and systemHasPlanetMatch(sd, q)
                            if g.expanded[skey] or auto_s then
                                for _, pd in ipairs(sd.planets or {}) do
                                    if pd.name ~= (sn .. " Space") then
                                        local show_p = not searching or g.expanded[skey] or planetMatches(pd, q)
                                        if show_p then
                                            local pcur = (pd.name == cur_planet) and (sn == cur_system)
                                            createRow(inst, inst.content, pd.name, "planet", 2, y, pd, pcur)
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

    -- Resize AFTER all rows exist (resizing mid-loop corrupts container refs).
    -- Height is max(rows, viewport): fills the viewport when short (no white gap,
    -- no phantom scroll) and grows to scroll when long.
    pcall(function() inst.content:resize(inst.contentW or 200, math.max(y + 4, viewportH)) end)
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

-- ── Build the header / scroll / footer panel into a content target ────────────
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

    local topbar_h, footer_h = 86, 24

    -- Header bar (three rows: title+refresh / search+clear / collapse-all)
    local topbar = Geyser.Label:new({ name = gid .. "_gx_top", x = 0, y = 0, width = "100%", height = topbar_h }, C)
    topbar:setStyleSheet(CSS_HEADER)

    -- Row 1: title (left) + refresh (small square, top-right of the content)
    local title = Geyser.Label:new({ name = gid .. "_gx_title", x = 8, y = 6, width = "100%-44px", height = 22 }, topbar)
    title:setStyleSheet("background-color:transparent; color:#c8c8d0; font-size:11px; font-weight:bold;")
    title:echo("🔭 Galaxy Navigator")

    inst.refreshIcon = Geyser.Label:new({ name = gid .. "_gx_ref", x = "-30", y = 6, width = 24, height = 24 }, topbar)
    inst.refreshIcon:setStyleSheet(CSS_ICONBTN)
    inst.refreshIcon:echo("<center>🔄</center>")
    inst.refreshIcon:setToolTip("Refresh (di systems)")
    inst.refreshIcon:setClickCallback(function() f2t_galaxy_scrape() end)

    -- Row 2: search box (fills) + clear (✕) square on the far right
    inst.searchCmd = Geyser.CommandLine:new({ name = gid .. "_gx_search", x = 8, y = 34, width = "100%-44px", height = 24 }, topbar)
    inst.searchCmd:setStyleSheet([[
        background-color: rgb(10,10,16); color: rgba(200,200,210,255); font-size:11px; font-weight:bold;
        border:1px solid rgba(100,100,110,180); border-radius:3px; padding-left:4px; padding-right:4px;
    ]])
    inst.searchCmd:setAction(function() end)   -- never submit to the game on Enter

    local clearBtn = Geyser.Label:new({ name = gid .. "_gx_clear", x = "-30", y = 34, width = 24, height = 24 }, topbar)
    clearBtn:setStyleSheet(CSS_ICONBTN)
    clearBtn:echo("<center>✕</center>")
    clearBtn:setToolTip("Clear search")
    clearBtn:setClickCallback(function()
        if inst.searchCmd then
            if inst.searchCmd.clear then pcall(function() inst.searchCmd:clear() end)
            else pcall(function() inst.searchCmd:setText("") end) end
        end
        inst.lastSearch = ""
        populate(gid)
    end)

    -- Row 3: collapse-all square (minus), left-aligned with the cartel expand column
    local collapse = Geyser.Label:new({ name = gid .. "_gx_col", x = "1%", y = 60, width = 22, height = 22 }, topbar)
    collapse:setStyleSheet(CSS_ICONBTN)
    collapse:echo("<center>−</center>")
    collapse:setToolTip("Collapse all")
    collapse:setClickCallback(function() F2T_GALAXY.expanded = {}; f2t_galaxy_refresh_open() end)

    -- Scroll area (styled chrome so no white strip appears beside the scrollbar)
    inst.scroll = Geyser.ScrollBox:new({ name = gid .. "_gx_scroll", x = 0, y = topbar_h,
        width = "100%", height = "100%-" .. (topbar_h + footer_h) .. "px" }, C)
    pcall(function() inst.scroll:setStyleSheet(CSS_SCROLL) end)
    -- Content fills the FULL scrollbox width; the 8px scrollbar overlaps only the
    -- right edge (rows are left-anchored), so there is no uncovered white column.
    inst.contentW = math.max(50, inst.scroll:get_width() or 220)

    -- Permanent state label (loading / empty) and the row container.
    inst.stateLbl = Geyser.Label:new({ name = gid .. "_gx_state", x = 0, y = 0, width = inst.contentW, height = 2000 }, inst.scroll)
    inst.stateLbl:setStyleSheet(CSS_BG)
    inst.stateMsg = Geyser.Label:new({ name = gid .. "_gx_statemsg", x = 0, y = "35%", width = "100%", height = 60 }, inst.stateLbl)
    inst.stateMsg:setStyleSheet("background-color:transparent; color:rgba(190,190,200,210); font-size:11px;")

    inst.content = Geyser.Label:new({ name = gid .. "_gx_content", x = 0, y = 0, width = inst.contentW, height = 2000 }, inst.scroll)
    inst.content:setStyleSheet(CSS_BG)

    -- Footer legend (a little taller so the text isn't cramped)
    local footer = Geyser.Label:new({ name = gid .. "_gx_foot", x = 0, y = "-" .. footer_h, width = "100%", height = footer_h }, C)
    footer:setStyleSheet(CSS_HEADER)
    local legend = Geyser.Label:new({ name = gid .. "_gx_legend", x = "1%", y = 0, width = "98%", height = "100%" }, footer)
    legend:setStyleSheet("background-color:transparent; color:rgba(160,160,170,190); font-size:9px;")
    legend:echo("<center>🌌 Cartel&nbsp;&nbsp;&nbsp;⭐ System&nbsp;&nbsp;&nbsp;🌍 Planet</center>")

    -- Auto-expand current cartel/system on open.
    local ri = gmcp and gmcp.room and gmcp.room.info
    if ri and ri.cartel and ri.cartel ~= "" then
        F2T_GALAXY.expanded[ri.cartel] = true
        if ri.system and ri.system ~= "" then F2T_GALAXY.expanded[ri.cartel .. ":" .. ri.system] = true end
    end

    populate(gid)

    -- Debounced search poll: rebuild the tree shortly after typing stops.
    -- Runs at 0.4s (fast enough to feel live for typed search) and idles
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

-- Re-render every open navigator (after a scrape, expand toggle, or reconnect).
function f2t_galaxy_refresh_open()
    for gid in pairs(instances) do pcall(populate, gid) end
end

-- ── Content type ────────────────────────────────────────────────────────────────
local function buildGalaxyDef()
    return {
        name        = "Galaxy Navigator",
        description = "Browse every cartel, system, and planet from 'di systems'; click → to travel.",
        group       = "Fed2 Tools",
        -- One navigator at a time: Muxlet tracks the active instance itself
        -- (def._activeTargetRef), which f2t_galaxy_show_nav/hide_nav below use to
        -- find "the" navigator without fed2-tools keeping its own pane reference.
        singleton   = true,

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

        serialize = function(_target) return {} end,     -- data is global; nothing per-instance
        restore   = function(_target, _data) end,
        onReveal  = function(target) populate(target._gid) end,
    }
end

-- ── Show/hide convenience ─────────────────────────────────────────────────────
-- The navigator pane itself is no longer created or placed by fed2-tools: add
-- the "Galaxy Navigator" content to a pane from the Content Library once,
-- position/anchor it, and save the workspace — Muxlet's own pane persistence
-- (floating geometry, anchors) carries it from there. Since the content is
-- singleton (above), Muxlet tracks that one active instance itself
-- (def._activeTargetRef); these two helpers just find it and drive its real
-- condition-hidden state (MuxPane/MuxTab :_conditionShow/_conditionHide,
-- shared with the generic "Toggle Pane/Tab Visibility" action a Button Grid
-- button can bind to — see Muxlet's conditional.lua).
local function currentNavTarget()
    local def = Mux._content and Mux._content.fed2_galaxy
    return def and def._activeTargetRef or nil
end

-- Walks a tab's .pane back-references up to the owning MuxPane (a tab hosting
-- sub-tabs is itself a .pane host, so a nested sub-tab needs more than one hop).
local function rootPaneOf(t)
    while t and t.pane do t = t.pane end
    return t
end

-- Hide the dedicated navigator pane if it's showing (used after navigating).
function f2t_galaxy_hide_nav()
    local t = currentNavTarget()
    if t and t._conditionHide and not t._conditionHidden then t:_conditionHide() end
end

-- Reveal the navigator (used when a player card jumps to a system).
function f2t_galaxy_show_nav()
    local t = currentNavTarget()
    if not t then
        cecho("\n<red>[fed2-tools]<reset> No Galaxy navigator pane yet — add the "
            .. "<cyan>Galaxy Navigator<reset> content to a pane from the Content Library first.\n")
        return
    end
    if t._conditionShow and t._conditionHidden then t:_conditionShow() end
    if Mux.raisePane then Mux.raisePane(rootPaneOf(t)) end
    f2t_galaxy_refresh_open()
end

-- ── Registration (called from init.lua muxletReady) ──────────────────────────────
function f2tRegisterGalaxy()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("fed2_galaxy", buildGalaxyDef())
    -- Package (re)install re-enables all triggers; park the catch-all capture
    -- triggers unless a scrape is actually in flight.
    if not F2T_GALAXY.capture_active then setCaptureTriggers(false) end
    -- Background scrape only for a genuine hot-reload (script re-executed
    -- with no index built yet). Normal login path: f2tCharacterChanged fires
    -- after vitals and schedules the scrape. Guarding on `loaded` also stops
    -- a redundant, visible "di systems" re-scrape when Muxlet finishes an
    -- in-session install well after login and this registrar re-runs.
    if not F2T_GALAXY.loaded and F2T_CONNECTED ~= false and F2T_LOGGED_IN then
        f2t_galaxy_schedule_scrape(3)
    end
    f2t_debug_log("[galaxy] registered content")
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterGalaxy)

-- ── Connection awareness ─────────────────────────────────────────────────────────
-- Refresh open navigator on (re)connect. Do NOT schedule a scrape here:
-- di systems would fire during the login sequence. The f2tCharacterChanged
-- handler below schedules the scrape after login is confirmed.
registerAnonymousEventHandler("sysConnectionEvent", function()
    if f2t_check_connection then f2t_check_connection() end
    f2t_galaxy_refresh_open()
end)

registerAnonymousEventHandler("f2tCharacterChanged", function()
    f2t_galaxy_schedule_scrape(3)
end)

f2t_debug_log("[galaxy] module loaded")