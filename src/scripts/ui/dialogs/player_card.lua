-- Player card content: renders as a normal Muxlet pane (registered content
-- "f2t_player_card") with a real pane titlebar (player name centered, colored
-- to match rank), a rank-colored border, and the detail rows/quick-send
-- command line. Not splittable or resizable (fixed-size info card, not a
-- layout host) but embeddable/swappable like any other content; its
-- Properties icon is hidden since there's nothing there worth exposing.
--
-- Public API:
--   f2tPlayerCardShowOrRaise(player)      - show or bring existing card to front
--   f2tPlayerCardShowOrRaiseByName(name)  - look up by name, then show or raise
--   f2tPlayerCardsRefreshAll()            - re-render any open card whose data changed

local _cardsByName = {}   -- player name → MuxPane

-- ── Rank → accent color (pane border + titlebar name) ─────────────────────────

local CARD_COLOR_DEFAULT = "rgba(120, 125, 155, 255)"

-- Rank color persists whether the player is online or not — only the who
-- list's own row grays out for offline; the card keeps identifying the rank.
local function accentFor(player)
    return f2t_rank_color_rgba(player.rank) or CARD_COLOR_DEFAULT
end

-- ── Button styles ─────────────────────────────────────────────────────────────

local _CSS_NAV = [[
    QLabel {
        background-color: rgba(40, 120, 80, 210);
        border: 1px solid rgba(60, 140, 100, 180);
        border-radius: 3px;
        color: white;
        font-size: 10px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(55, 150, 95, 230); }
]]
local _CSS_GAL = [[
    QLabel {
        background-color: rgba(18, 22, 52, 210);
        color: rgba(120, 155, 255, 255);
        border: 1px solid rgba(75, 95, 200, 200);
        border-radius: 3px;
        font-size: 12px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(30, 40, 90, 235);
        border-color: rgba(110, 140, 255, 255);
        color: rgba(180, 205, 255, 255);
    }
]]
local _CSS_ICON = [[
    QLabel {
        background-color: rgba(32, 36, 58, 220);
        color: rgba(165, 180, 220, 255);
        border: 1px solid rgba(80, 92, 140, 210);
        border-radius: 4px;
        font-size: 14px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(50, 58, 95, 240);
        border-color: rgba(110, 125, 195, 255);
        color: rgba(210, 225, 255, 255);
    }
]]
local _TEXT_CSS_BASE = [[
    background: transparent; border: none;
    font-size: 12px; font-family: "Consolas","Monaco",monospace;
    padding: 0 8px;
]]
local _LABEL_HTML = "<span style='color: rgb(120,130,170);'>%s:</span> "

local ROW_H   = 26
local BADGE_H = 32
local LOC_GAP = 16
local BTN_W   = 26
local ICON_W  = 30
local GAP     = 3
local R_M     = 4
local CMD_H   = 30
local SEND_W  = 26
local CMD_L_M = 4
local CMD_R_M = 8

local NAV_X_2  = tostring(-(BTN_W + GAP + BTN_W + R_M))
local GAL_X    = tostring(-(BTN_W + R_M))
local TEXT_W_2 = tostring(-(BTN_W + GAP + BTN_W + GAP + R_M))
local TEXT_W_1 = tostring(-(BTN_W + GAP + R_M))
local ACCT_X   = tostring(-(ICON_W + R_M))
local TEXT_W_A = tostring(-(ICON_W + GAP + R_M))
local SEND_X   = tostring(-(SEND_W + CMD_R_M))
local CMD_W    = tostring(-(SEND_W + GAP + CMD_R_M + CMD_L_M))
local FRAME_W  = tostring(-(SEND_W + GAP + CMD_R_M + CMD_L_M - 2))

-- ── Galaxy integration ────────────────────────────────────────────────────────

local function openInGalaxy(cartelName, entityName, syndicateName)
    if not F2T_GALAXY then return end

    -- Key format must match what populate()/createRow actually check
    -- ("syn:Name", "cartel:Syndicate:Name", "system:Cartel:Name" -- see
    -- galaxy.lua's autoExpandCurrentLocation for the canonical pattern this
    -- was silently drifted from). Without the prefixes these previously set
    -- keys that populate() never looks at, so nothing ever actually expanded.
    local function expandCartel(cn, cd)
        if cd.syndicate then F2T_GALAXY.expanded["syn:" .. cd.syndicate] = true end
        F2T_GALAXY.expanded["cartel:" .. (cd.syndicate or "") .. ":" .. cn] = true
    end

    -- galaxy.lua's ScrollBox has no scrollTo/ensureVisible hook (confirmed:
    -- Muxlet's own globals.lua notes the same gap for pane content groups),
    -- so there's no way to scroll the viewport to an arbitrary row. The
    -- nearest available approximation -- also the one Muxlet already uses
    -- for that other case -- is to sort the expanded branch to the front of
    -- each level's list, since the view always starts scrolled to the top.
    -- populate() reads this to hoist syn/cartel/system into place.
    local function expand()
        F2T_GALAXY.scrollTarget = nil
        if cartelName and cartelName ~= "" then
            local cd = F2T_GALAXY.cartels[cartelName]
            if cd then
                expandCartel(cartelName, cd)
                F2T_GALAXY.scrollTarget = { syn = cd.syndicate, cartel = cartelName }
            end
        elseif entityName and entityName ~= "" then
            for cn, cd in pairs(F2T_GALAXY.cartels or {}) do
                if cd.systems then
                    if cd.systems[entityName] then
                        expandCartel(cn, cd)
                        F2T_GALAXY.expanded["system:" .. cn .. ":" .. entityName] = true
                        F2T_GALAXY.scrollTarget = { syn = cd.syndicate, cartel = cn, system = entityName }
                        break
                    end
                    local foundPlanet = false
                    for sn, sd in pairs(cd.systems) do
                        for _, pd in ipairs(sd.planets or {}) do
                            if pd.name == entityName then
                                expandCartel(cn, cd)
                                F2T_GALAXY.expanded["system:" .. cn .. ":" .. sn] = true
                                F2T_GALAXY.scrollTarget = { syn = cd.syndicate, cartel = cn, system = sn }
                                foundPlanet = true
                                break
                            end
                        end
                        if foundPlanet then break end
                    end
                    if foundPlanet then break end
                end
            end
        elseif syndicateName and syndicateName ~= "" then
            F2T_GALAXY.expanded["syn:" .. syndicateName] = true
            F2T_GALAXY.scrollTarget = { syn = syndicateName }
        end
        if f2t_galaxy_refresh_open then f2t_galaxy_refresh_open() end
    end

    if F2T_GALAXY.loaded then
        expand()
    elseif F2T_GALAXY.loading then
        local function wait()
            if F2T_GALAXY.loaded then expand()
            elseif F2T_GALAXY.loading then tempTimer(0.25, wait) end
        end
        tempTimer(0.25, wait)
    else
        if f2t_galaxy_schedule_scrape then f2t_galaxy_schedule_scrape(0) end
        local function wait()
            if F2T_GALAXY.loaded then expand()
            elseif F2T_GALAXY.loading then tempTimer(0.25, wait) end
        end
        tempTimer(0.5, wait)
    end

    if f2t_galaxy_show_nav then f2t_galaxy_show_nav() end
end

-- ── Fingerprint (detects data changes for f2tPlayerCardsRefreshAll) ───────────

local function fingerprint(p)
    return table.concat({
        p.rank or "", p.location or "", p.company or "",
        p.system or "", p.cartel or "", p.syndicate or "", p.ship_class or "",
        p.staff or "", tostring(p.is_online == false),
        -- Titles affect rendered height (each one adds a row), so a title
        -- change has to count as a data change here too -- previously it
        -- didn't, meaning a player earning a new title while their card was
        -- open wouldn't have triggered f2tPlayerCardsRefreshAll at all.
        table.concat(p.titles or {}, "|"),
    }, "\0")
end

-- ── Initial pane size (the only size — the pane is not resizable) ─────────────

local function initialContentSize(player)
    local rank      = player.rank       or "Unknown"
    local staff     = player.staff      or ""
    local loc       = player.location   or ""
    local company   = player.company    or ""
    local system    = player.system     or ""
    local cartel    = player.cartel     or ""
    local syndField = player.syndicate  or ""
    local ship      = player.ship_class or ""
    local isOffline = (player.is_online == false)

    local isFounder    = rank == "Founder"
    local isPlutocrat  = rank == "Plutocrat"
    local isSyndicrat  = rank == "Syndicrat"
    local hasCompany   = company ~= ""
    local isIndustrial = rank == "Industrialist"
    local isMfrFin     = rank == "Manufacturer" or rank == "Financier"
    local hasSystem    = system ~= "" and not isFounder and (
        rank == "Engineer"   or rank == "Technocrat" or rank == "Gengineer" or
        rank == "Magnate"    or rank == "Mogul")
    local hasPlanet    = isFounder and system ~= ""
    local hasCartel    = cartel ~= "" and isPlutocrat
    -- A card shows a player's own fief, not everything it's nested inside —
    -- a Plutocrat's cartel belongs to a syndicate same as a Mogul's system
    -- belongs to a cartel, but neither of those parents gets its own row.
    local syndicate    = isSyndicrat and syndField ~= "" and syndField or nil
    local hasSyndicate = syndicate ~= nil
    local hasShip      = ship ~= ""
    local hasOwnership = (hasCompany and (isIndustrial or isMfrFin))
        or hasSystem or hasPlanet or hasCartel or hasSyndicate

    local function badgePx(s) return math.ceil(#s * 6.5) + 16 end
    local rankBadgeW  = badgePx(rank)
    local staffBadgeW = staff ~= "" and badgePx("[" .. staff .. "]") or 0
    -- Trailing term reserves room for the spynet-report button on the right
    -- of this same row (see render()'s spynetBtn, anchored at GAL_X) so long
    -- rank/staff badges never grow into it.
    local headerNeed  = 10 + rankBadgeW + (staff ~= "" and (4 + staffBadgeW) or 0) + 8 + BTN_W + R_M

    -- Titles render as "  \xc2\xb7 <text>" at the same font/width as the body
    -- rows below, but were never factored into width at all -- a long title
    -- (e.g. "Member of the Order of True Caffeination") routinely exceeds
    -- every other field's length, wraps or overflows its fixed 22px-tall
    -- label when the pane clamps to the 360px floor, and visually spills
    -- into whatever's positioned next. That overflow is pure text rendering,
    -- invisible to every get_height()-based measurement, which is why it
    -- kept surviving several rounds of height/position fixes.
    local longestTitle = 0
    for _, t in ipairs(player.titles or {}) do
        if #t > longestTitle then longestTitle = #t end
    end

    local longest = math.max(
        #(loc ~= "" and loc or "Unknown"),
        hasCompany   and (#company   + 10) or 0,
        hasSystem    and (#system    + 8)  or 0,
        hasPlanet    and (#system    + 8)  or 0,
        hasCartel    and (#cartel    + 8)  or 0,
        hasSyndicate and (#syndicate + 12) or 0,
        longestTitle + 4)
    local bodyNeed = math.ceil(longest * 7.0) + 30 + 62

    local W = math.max(360, math.min(580, math.max(headerNeed, bodyNeed)))

    local offlineH = isOffline and ROW_H or 0
    -- +2 matches the divider line render() draws right under the badge row
    -- (rowY += 2 there, alongside the += BADGE_H) -- omitting it here left
    -- the pane 2px shorter than its actual content, every card, always.
    local H = BADGE_H + 2 + offlineH + ROW_H
    if hasOwnership                then H = H + LOC_GAP end
    if hasCompany and isIndustrial then H = H + ROW_H end
    if hasCompany and isMfrFin     then H = H + ROW_H end
    if hasSystem                   then H = H + ROW_H end
    if hasPlanet                   then H = H + ROW_H end
    if hasSyndicate                then H = H + ROW_H end
    if hasCartel                   then H = H + ROW_H end
    if hasShip                     then H = H + ROW_H end
    -- Tail term's trailing constant sets the bottom margin below the
    -- quick-send button: gap = (tail - 10)px, so 26 -> 16px, matching
    -- LOC_GAP -- the same visual rhythm the card already uses elsewhere,
    -- instead of a uniquely large gap that reads as inconsistent design
    -- regardless of it being pixel-identical on every card.
    H = H + (isOffline and 14 or (10 + CMD_H + 26))
    -- Reserve room for the full title list up front so a fresh card doesn't
    -- open pre-truncated; render() re-measures the real content height
    -- afterward in case the pane ends up smaller than this estimate.
    local titleCount = player.titles and #player.titles or 0
    if titleCount > 0 then H = H + 10 + ROW_H + titleCount * 22 end

    return W, H
end

-- ── Quick-send slot (persistent — survives every render) ───────────────────────
-- Built once per card and left alone afterward. render() deletes/recreates its
-- own "_in" slot on every data refresh (see below), which would destroy and
-- recreate this command line too if it lived there -- silently dropping
-- keyboard focus and any unsent draft out from under whatever the user was
-- mid-keystroke on. Living in its own container that's never deleted, only
-- repositioned (via :move) and re-styled, sidesteps that entirely. Parented to
-- target.content the one time this runs -- the apply() callback defers its
-- first renderCard() call by a tick specifically so target.content is always
-- the pane's real, permanent container by then (see registerContent's apply
-- below), never the disposable slot Mux._applyContent aliases it to for the
-- duration of apply() itself. Every later "_in" also lands in that same real
-- container, so this and the main content rows are guaranteed to share one
-- coordinate frame for the card's whole life, instead of two independently
-- tracked containers that only coincidentally cover the same rectangle.
local function ensureQuickSlot(target)
    if target._f2tQuickSlot then return target._f2tQuickSlot end

    local quickCmdName = target._gid .. "_qcmd"
    local actionKey     = "_f2t_qsend_" .. target._gid
    _G[actionKey] = function(text)
        if text and text ~= "" then
            expandAlias(string.format("tb %s %s", target._f2tCardPlayerName, text), false)
            clearCmdLine(quickCmdName)
        end
    end
    target._f2tCardActionKey = actionKey

    -- height="-0px": Geyser's negative-size convention for "stretch to the far
    -- edge of the parent" -- resolved live against target.content's real Qt
    -- geometry on every reposition, not a fixed pixel guess. Exactly matching
    -- the pane's true bottom edge by construction, whatever it turns out to be,
    -- sidesteps needing to reverse-engineer Muxlet's chrome/inset math by hand.
    local q = Geyser.Container:new({
        name = target._gid .. "_quickslot", x = 0, y = 0, width = "100%", height = "-0px",
    }, target.content)

    -- Fills the margins around the frame/button (the divider gap, the side
    -- edges, and now whatever's left below the button down to the pane's real
    -- bottom) that render()'s own bg fill used to cover back when this row
    -- was still a child of its disposable _in slot.
    local qbg = Geyser.Label:new({ name = target._gid .. "_qbg", x="0%", y="0%", width="100%", height="100%" }, q)
    qbg:setStyleSheet(Mux.css and Mux.css("content", target) or "background-color: rgba(15,17,30,255); border: none;")

    local qdiv = Geyser.Label:new({ name = target._gid .. "_qdiv", x=4, y=8, width=tostring(-8), height=1 }, q)
    qdiv:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")

    -- Positioned down from q's top via an explicit pixel offset, not derived
    -- from q's current height at all -- confirmed correct by direct
    -- measurement (contentH matched the requested height exactly, and the
    -- gap from the button's bottom edge to that boundary was identical --
    -- 40px -- on both a short, no-titles card and a long, many-titles card).
    -- A bottom-anchored (negative y) version briefly lived here instead, but
    -- that depends on q's height already reflecting the post-auto-fit size
    -- at the moment these widgets are first positioned, which isn't
    -- guaranteed -- ensureQuickSlot only runs once, before auto-fit's
    -- resize has necessarily taken effect, and nothing was forcing a
    -- reposition afterward once render() started skipping unchanged
    -- re-renders. Top-anchored has no such dependency.
    local cmdFrame = Geyser.Label:new({
        name = target._gid .. "_qframe", x = CMD_L_M - 2, y = 16, width = FRAME_W, height = CMD_H + 4,
    }, q)
    cmdFrame:setStyleSheet([[
        background: rgba(18, 20, 38, 235);
        border: 1px solid rgba(75, 90, 135, 190);
        border-radius: 4px;
    ]])

    local quickCmd = Geyser.CommandLine:new({
        name = quickCmdName, x = CMD_L_M, y = 18, width = CMD_W, height = CMD_H,
    }, q)
    quickCmd:setStyleSheet([[
        QPlainTextEdit {
            background: transparent;
            color: rgba(198, 210, 238, 255);
            border: none;
            font-size: 12px;
            font-family: "Consolas","Monaco",monospace;
            padding: 2px 6px;
        }
        QPlainTextEdit::placeholder {
            color: rgba(110, 120, 160, 200);
            font-style: italic;
        }
    ]])
    quickCmd:setAction(actionKey)
    if setCommandLineAction then setCommandLineAction(quickCmdName, actionKey) end

    local sendBtn = Geyser.Label:new({
        name = target._gid .. "_qsend", x = SEND_X, y = 16, width = SEND_W, height = CMD_H + 4,
    }, q)
    sendBtn:echo("<center>▶</center>")
    sendBtn:setClickCallback(function()
        local text = getCmdLine(quickCmdName)
        if text and text ~= "" then
            expandAlias(string.format("tb %s %s", target._f2tCardPlayerName, text), false)
            clearCmdLine(quickCmdName)
        end
    end)

    target._f2tQuickSlot = { container = q, send = sendBtn, bg = qbg }
    return target._f2tQuickSlot
end

-- ── Render ────────────────────────────────────────────────────────────────────
-- Called on apply, resize, restore, and refresh — i.e. more than once over a
-- card's life, none of which go through Muxlet's own content-slot teardown (that
-- only fires when the content is removed/reapplied wholesale). So render() owns
-- a child container it fully deletes and recreates each call, the same
-- "disposable slot" pattern _applyContent itself uses, rather than hand-tracking
-- every widget it creates. The quick-send row is the one exception -- see
-- ensureQuickSlot above.
local function render(target, player)
    -- render() gets invoked far more often than the player's data actually
    -- changes: Muxlet's own reflow machinery re-fires this content's resize
    -- hook (Mux._relayoutContent) every time target.content's measured size
    -- changes, which the auto-fit call at the end of this function itself
    -- triggers at least once, asynchronously, after it resizes the pane --
    -- confirmed by logging, one card fired this 4 times in a row for a
    -- single open, all producing identical output. Skip the whole rebuild
    -- when nothing this function's output depends on has actually changed
    -- since the last time it fully ran for this target.
    local fp = fingerprint(player)
    if target._f2tCardSlot and target._f2tLastRenderFingerprint == fp then return end
    target._f2tLastRenderFingerprint = fp

    -- delete() only schedules the old widgets' underlying Qt objects for teardown
    -- (deleteLater) -- they stay fully visible for at least one event-loop tick
    -- after this call returns. hide() first is synchronous, so the old slot never
    -- has a moment on screen next to the new one. The epoch suffix additionally
    -- guarantees the new widgets never share a name with the still-tearing-down
    -- old ones (a fresh render() with an identical row layout would otherwise
    -- create same-named replacements while the old ones are still pending delete).
    -- The quick-send command line lives outside this slot entirely (see
    -- ensureQuickSlot below) specifically so a data refresh never touches it --
    -- destroying/recreating it would silently drop keyboard focus and any
    -- unsent draft mid-keystroke.
    if target._f2tCardSlot then
        pcall(function() target._f2tCardSlot:hide() end)
        pcall(function() target._f2tCardSlot:delete() end)
    end
    target._f2tCardEpoch = (target._f2tCardEpoch or 0) + 1
    local epoch = target._f2tCardEpoch
    local _in = Geyser.Container:new({
        name = target._gid .. "_cardslot_" .. epoch, x="0%", y="0%", width="100%", height="100%",
    }, target.content)
    target._f2tCardSlot = _in

    local name      = player.name or target._f2tCardPlayerName or "Unknown"
    local rank      = player.rank       or "Unknown"
    local loc       = player.location   or ""
    local company   = player.company    or ""
    local system    = player.system     or ""
    local cartel    = player.cartel     or ""
    local syndField = player.syndicate  or ""
    local staff     = player.staff      or ""
    local ship      = player.ship_class or ""
    local titles    = player.titles     or {}
    local isOffline = (player.is_online == false)
    local lastSeen  = player.last_seen

    local accent = accentFor(player)

    local isFounder    = rank == "Founder"
    local isPlutocrat  = rank == "Plutocrat"
    local isSyndicrat  = rank == "Syndicrat"
    local hasCompany   = company ~= ""
    local isIndustrial = rank == "Industrialist"
    local isMfrFin     = rank == "Manufacturer" or rank == "Financier"
    local hasSystem    = system ~= "" and not isFounder and (
        rank == "Engineer"   or rank == "Technocrat" or rank == "Gengineer" or
        rank == "Magnate"    or rank == "Mogul")
    local hasPlanet    = isFounder and system ~= ""
    local hasCartel    = cartel ~= "" and isPlutocrat
    -- A card shows a player's own fief, not everything it's nested inside —
    -- a Plutocrat's cartel belongs to a syndicate same as a Mogul's system
    -- belongs to a cartel, but neither of those parents gets its own row.
    local syndicate    = isSyndicrat and syndField ~= "" and syndField or nil
    local hasSyndicate = syndicate ~= nil
    local hasShip      = ship   ~= ""
    local hasOwnership = (hasCompany and (isIndustrial or isMfrFin))
        or hasSystem or hasPlanet or hasCartel or hasSyndicate

    local wc = 0
    local function wid() wc = wc + 1; return string.format("%s_%d_%d", target._gid, epoch, wc) end

    -- Opaque fill for the slot: target.contentBg is hidden (per the Muxlet content
    -- convention), so without this, gaps between rows are fully transparent and
    -- whatever sits behind the pane (another window, chat) shows through.
    local bg = Geyser.Label:new({ name = wid(), x="0%", y="0%", width="100%", height="100%" }, _in)
    bg:setStyleSheet(Mux.css and Mux.css("content", target) or "background-color: rgba(15,17,30,255); border: none;")

    local rowY = 0

    -- ── Rank / staff badges ───────────────────────────────────────────────────
    local function badgePx(s) return math.ceil(#s * 6.5) + 16 end
    local rankBadgeW  = badgePx(rank)
    local rankLbl = Geyser.Label:new({ name=wid(), x=10, y=4, width=rankBadgeW, height=22 }, _in)
    rankLbl:setStyleSheet(string.format([[
        background: rgba(20,22,38,200);
        color: %s;
        font-size: 10px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        border: 1px solid %s;
        border-radius: 3px;
        qproperty-alignment: AlignCenter;
    ]], accent, accent))
    rankLbl:echo(rank)

    local spynetBtn = Geyser.Label:new({ name=wid(), x=GAL_X, y=4, width=BTN_W, height=22 }, _in)
    spynetBtn:setStyleSheet(_CSS_ICON)
    spynetBtn:echo("<center>🕵️</center>")
    spynetBtn:setClickCallback(function() send(string.format("spynet report %s", name)) end)
    spynetBtn:setToolTip("Spynet report on " .. name .. "  (spynet report " .. name .. ")")

    if staff ~= "" then
        local staffBadgeW = badgePx("[" .. staff .. "]")
        local staffLbl = Geyser.Label:new({ name=wid(), x=10+rankBadgeW+4, y=4, width=staffBadgeW, height=22 }, _in)
        staffLbl:setStyleSheet([[
            background: rgba(100, 80, 0, 180);
            color: rgba(255, 215, 70, 255);
            font-size: 9px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            border: 1px solid rgba(200, 165, 0, 160);
            border-radius: 3px;
            qproperty-alignment: AlignCenter;
        ]])
        staffLbl:echo(string.format("[%s]", staff))
    end
    rowY = rowY + BADGE_H

    local div = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=2 }, _in)
    div:setStyleSheet("background-color: rgba(255,255,255,0.09); border: none;")
    rowY = rowY + 2

    -- ── Row helpers ───────────────────────────────────────────────────────────
    local function addLinkRow(opts)
        local hasNav = opts.nav_cmd ~= nil
        local hasGal = opts.galaxy_fn ~= nil
        local textW, navX, galX
        if hasNav and hasGal then
            textW = TEXT_W_2; navX = NAV_X_2; galX = GAL_X
        elseif hasGal then
            textW = TEXT_W_1; galX = GAL_X
        else
            textW = tostring(-R_M)
        end
        local labelHtml = opts.label and string.format(_LABEL_HTML, opts.label) or ""
        local txt = Geyser.Label:new({ name=wid(), x=0, y=rowY, width=textW, height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. string.format("color: %s;", opts.text_color))
        if opts.di_cmd then
            txt:echo(string.format("  %s  %s<u>%s</u>", opts.icon, labelHtml, opts.text))
            txt:setClickCallback(function() send(opts.di_cmd) end)
            txt:setToolTip(opts.di_tooltip or opts.di_cmd)
        else
            txt:echo(string.format("  %s  %s%s", opts.icon, labelHtml, opts.text))
        end
        if hasNav then
            local nb = Geyser.Label:new({ name=wid(), x=navX, y=rowY+2, width=BTN_W, height=ROW_H-4 }, _in)
            nb:setStyleSheet(_CSS_NAV)
            nb:echo("<center>→</center>")
            nb:setClickCallback(function() expandAlias(opts.nav_cmd) end)
            nb:setToolTip("Navigate to " .. opts.text)
        end
        if hasGal then
            local gb = Geyser.Label:new({ name=wid(), x=galX, y=rowY+2, width=BTN_W, height=ROW_H-4 }, _in)
            gb:setStyleSheet(_CSS_GAL)
            gb:echo("<center>🔭</center>")
            gb:setClickCallback(opts.galaxy_fn)
            gb:setToolTip("View in Galaxy Navigator")
        end
        rowY = rowY + ROW_H
    end

    local function addCompanyRow(opts)
        local hasAcct = opts.acct_cmd ~= nil
        local textW   = hasAcct and TEXT_W_A or tostring(-R_M)
        local labelHtml = opts.label and string.format(_LABEL_HTML, opts.label) or ""
        local txt = Geyser.Label:new({ name=wid(), x=0, y=rowY, width=textW, height=ROW_H }, _in)
        txt:setStyleSheet(_TEXT_CSS_BASE .. string.format("color: %s;", opts.text_color))
        if opts.di_cmd then
            txt:echo(string.format("  %s  %s<u>%s</u>", opts.icon, labelHtml, opts.text))
            txt:setClickCallback(function() send(opts.di_cmd) end)
            txt:setToolTip(opts.di_tooltip or opts.di_cmd)
        else
            txt:echo(string.format("  %s  %s%s", opts.icon, labelHtml, opts.text))
        end
        if hasAcct then
            local ab = Geyser.Label:new({ name=wid(), x=ACCT_X, y=rowY+2, width=ICON_W, height=ROW_H-4 }, _in)
            ab:setStyleSheet(_CSS_ICON)
            ab:echo("<center>📊</center>")
            ab:setClickCallback(function() send(opts.acct_cmd) end)
            ab:setToolTip("View accounts  (di accounts " .. opts.text .. ")")
        end
        rowY = rowY + ROW_H
    end

    -- ── Offline banner ────────────────────────────────────────────────────────
    if isOffline then
        local agoStr = (lastSeen and f2t_player_db_last_seen_str)
            and ("Last seen " .. f2t_player_db_last_seen_str(lastSeen))
            or  "Offline"
        local offLbl = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=ROW_H }, _in)
        offLbl:setStyleSheet([[
            background: rgba(60, 30, 30, 180);
            border: none;
            color: rgba(200, 140, 140, 255);
            font-size: 11px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        ]])
        offLbl:echo("⊘ OFFLINE  —  " .. agoStr)
        rowY = rowY + ROW_H
    end

    -- ── Location row ──────────────────────────────────────────────────────────
    local locText = loc ~= "" and loc or "Unknown"
    local locSys  = locText:match("^(.+) Space$")
    local diLoc   = locSys and ("di system " .. locSys) or ("di planet " .. locText)
    local navLoc  = locSys and ("nav " .. locSys .. " link") or ("nav " .. locText)

    addLinkRow({
        icon       = "📍",
        text       = locText,
        text_color = "rgba(130, 200, 255, 255)",
        di_cmd     = diLoc,
        di_tooltip = "Get info  (" .. diLoc .. ")",
        nav_cmd    = navLoc,
        galaxy_fn  = function()
            openInGalaxy(nil, locSys or locText)
        end,
    })

    if hasOwnership then
        local sep = Geyser.Label:new({ name=wid(), x=4, y=rowY+7, width=tostring(-8), height=1 }, _in)
        sep:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")
        rowY = rowY + LOC_GAP
    end

    -- ── Company ───────────────────────────────────────────────────────────────
    if hasCompany then
        if isIndustrial then
            addCompanyRow({
                icon       = "🏢",
                label      = "Business",
                text       = company,
                text_color = "rgba(160, 255, 160, 255)",
                di_cmd     = "di business " .. company,
                di_tooltip = "Get business info  (di business " .. company .. ")",
            })
        elseif isMfrFin then
            addCompanyRow({
                icon       = "🏭",
                label      = "Company",
                text       = company,
                text_color = "rgba(160, 255, 160, 255)",
                di_cmd     = "di company " .. company,
                di_tooltip = "Get company info  (di company " .. company .. ")",
                acct_cmd   = "di accounts " .. company,
            })
        end
    end

    -- ── System ────────────────────────────────────────────────────────────────
    if hasSystem then
        addLinkRow({
            icon       = "⭐",
            label      = "System",
            text       = system,
            text_color = "rgba(255, 228, 100, 255)",
            di_cmd     = "di system " .. system,
            di_tooltip = "Get system info  (di system " .. system .. ")",
            nav_cmd    = "nav " .. system .. " link",
            galaxy_fn  = function() openInGalaxy(nil, system) end,
        })
    end

    -- ── Planet (Founders own a planet, not a system) ───────────────────────────
    if hasPlanet then
        addLinkRow({
            icon       = "🌍",
            label      = "Planet",
            text       = system,
            text_color = "rgba(120, 220, 190, 255)",
            di_cmd     = "di planet " .. system,
            di_tooltip = "Get planet info  (di planet " .. system .. ")",
            nav_cmd    = "nav " .. system,
            galaxy_fn  = function() openInGalaxy(nil, system) end,
        })
    end

    -- ── Syndicate (Syndicrats only — their own) ─────────────────────────────────
    if hasSyndicate then
        addLinkRow({
            icon       = "🏛️",
            label      = "Syndicate",
            text       = syndicate,
            text_color = "rgba(200, 160, 255, 255)",
            di_cmd     = "di syndicate " .. syndicate,
            di_tooltip = "Get syndicate info  (di syndicate " .. syndicate .. ")",
            galaxy_fn  = function() openInGalaxy(nil, nil, syndicate) end,
        })
    end

    -- ── Cartel ────────────────────────────────────────────────────────────────
    if hasCartel then
        addLinkRow({
            icon       = "🌌",
            label      = "Cartel",
            text       = cartel,
            text_color = "rgba(255, 150, 200, 255)",
            di_cmd     = "di cartel " .. cartel,
            di_tooltip = "Get cartel info  (di cartel " .. cartel .. ")",
            galaxy_fn  = function() openInGalaxy(cartel, nil) end,
        })
    end

    -- ── Ship class ────────────────────────────────────────────────────────────
    if hasShip then
        local shipTxt = Geyser.Label:new({ name=wid(), x=0, y=rowY, width=tostring(-R_M), height=ROW_H }, _in)
        shipTxt:setStyleSheet(_TEXT_CSS_BASE .. "color: rgba(160, 165, 215, 255);")
        shipTxt:echo("  🚀  " .. ship)
        rowY = rowY + ROW_H
    end

    local quickH = isOffline and 14 or (10 + CMD_H + 26)

    -- ── Titles ──────────────────────────────────────────────────────────────
    -- Shows every title unconditionally. This used to truncate the list
    -- against a computed estimate of the pane's real content height --
    -- target.content:get_height() looked like the more honest source but
    -- proved unreliable (confirmed reading back a different value across
    -- renders of the *same* unchanged player data), and even a deterministic
    -- formula-based estimate never quite matched the pane's actual rendered
    -- chrome closely enough to avoid the quick-send row sometimes clipping
    -- the row above it, sometimes overlapping the border. Mux.requestAutoFit
    -- (below, once rowY is final) sidesteps the whole problem: it resizes the
    -- pane to whatever this function actually rendered, using Muxlet's own
    -- already-correct chrome math, so there's no fixed budget left to
    -- truncate titles against -- the card just grows to fit them.
    if #titles > 0 then
        local tdiv = Geyser.Label:new({ name=wid(), x=4, y=rowY+4, width=tostring(-8), height=1 }, _in)
        tdiv:setStyleSheet("background-color: rgba(255,255,255,0.15); border: none;")
        rowY = rowY + 10

        local thdr = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=ROW_H }, _in)
        thdr:setStyleSheet([[
            background: transparent; border: none;
            color: rgba(130, 140, 185, 255);
            font-size: 10px; font-weight: bold;
            font-family: "Consolas","Monaco",monospace;
            padding: 0 10px;
        ]])
        thdr:echo("  Titles")
        rowY = rowY + ROW_H

        for i = 1, #titles do
            local tl = Geyser.Label:new({ name=wid(), x=0, y=rowY, width="100%", height=22 }, _in)
            tl:setStyleSheet([[
                background: transparent; border: none;
                color: rgba(175, 185, 225, 200);
                font-size: 11px;
                font-family: "Consolas","Monaco",monospace;
                padding: 0 10px;
            ]])
            -- Qt's QLabel stylesheet engine doesn't reliably support CSS
            -- text-overflow, so truncate the string itself as a hard safety
            -- net -- 74 chars is safe even at the pane's max possible width
            -- (580px), regardless of whether the width formula above ever
            -- under-estimates for some future title text.
            local titleText = titles[i]
            if #titleText > 74 then titleText = titleText:sub(1, 73) .. "…" end
            tl:echo("  · " .. titleText)
            rowY = rowY + 22
        end
    end

    -- ── Quick-send (online only) — persistent slot, positioned/re-styled only ──
    if not isOffline then
        -- Shrink _in's bg to stop exactly where the quick slot begins, instead
        -- of overlapping it and depending on z-order to stay out of its way.
        -- Nothing else in _in extends past this rowY (it's the final value,
        -- computed after every row above), and the quick slot's own qbg covers
        -- everything from here down -- so the two never occupy the same pixels
        -- and which one Qt happens to paint first stops mattering. That
        -- z-order dependency turned out to be real: Mux.raiseFloatingPanes()
        -- (called after every location-driven refresh) does outer:raiseAll()
        -- on the whole pane, which re-raises _in -- freshly deleted and
        -- re-inserted by this same render, landing after the long-lived quick
        -- slot in insertion order -- right back on top of it.
        --
        -- qY is always exactly rowY -- never earlier. A clamp against a
        -- separately-estimated pane height lived here briefly to add bottom
        -- padding, but that estimate never quite matched the pane's actual
        -- rendered chrome, and a min()-based clamp can pick a value *smaller*
        -- than rowY -- pushing this section's top edge above where the last
        -- content row actually ends, clipping straight into it (its buttons,
        -- in one reported case). There's no valid reason to ever start this
        -- section before the content above it has finished. The pane's real
        -- size is now driven by Mux.requestAutoFit below instead, so any
        -- bottom padding just comes from quickH's own trailing margin.
        local qY = rowY
        bg:resize(nil, qY)
        local q = ensureQuickSlot(target)
        q.container:show()
        q.container:move(0, qY)
        q.bg:setStyleSheet(Mux.css and Mux.css("content", target)
            or "background-color: rgba(15,17,30,255); border: none;")
        q.send:setStyleSheet(string.format([[
            QLabel {
                background-color: rgba(18, 20, 38, 235);
                color: %s;
                border: 1px solid rgba(75, 90, 135, 190);
                border-radius: 4px;
                font-size: 13px; font-weight: bold;
                qproperty-alignment: AlignCenter;
            }
            QLabel::hover {
                background-color: rgba(30, 34, 58, 245);
                border-color: %s;
                color: rgba(220, 235, 255, 255);
            }
        ]], accent, accent))
    elseif target._f2tQuickSlot then
        target._f2tQuickSlot.container:hide()
    end

    -- Resizes the pane's real outer window to fit whatever was just rendered,
    -- using Muxlet's own chrome math (titlebar height, border inset) instead
    -- of this file re-deriving it -- see galaxy.lua/local_players.lua for the
    -- same pattern. This is what actually ends the border/clipping saga: the
    -- pane now always matches rowY+quickH exactly, by construction, so there
    -- is no fixed budget left to guess at or fall out of sync with.
    --
    -- Only call it when the target height actually changed. requestAutoFit
    -- always resizes target.outer and schedules a deferred reposition even
    -- when asked for the size it's already at, and that reposition changes
    -- target.content's measured dimensions enough to trip Muxlet's own
    -- Mux._relayoutContent, which calls this content's resize hook (=
    -- renderCard) again -- a confirmed 4x render() cascade for one card open.
    -- It always converged on the right numbers, just wastefully, so this
    -- skips the redundant resize instead of ever actually reaching Mux for
    -- a no-op change, cutting the cascade off at its source.
    local wantH = rowY + quickH
    if Mux and Mux.requestAutoFit and target._f2tLastAutoFitH ~= wantH then
        target._f2tLastAutoFitH = wantH
        Mux.requestAutoFit(target, wantH)
    end
end

-- Applies accent (border + centered titlebar name color) and re-renders. Safe
-- to call any time the pane already carries _f2tCardPlayerName/PlayerData.
local function renderCard(target)
    local name = target._f2tCardPlayerName
    if not name then return end   -- content applied before restore() set it; restore() re-renders
    local player = target._f2tCardPlayerData
        or (f2t_player_db_get and f2t_player_db_get(name))
        or { name = name }
    local accent = accentFor(player)
    -- applyTheme() triggers a relayout that calls back into this content's
    -- resize hook (renderCard again), so only call it when accent changed.
    if accent ~= target._f2tCardAccent then
        target._f2tCardAccent = accent
        target._tokens = target._tokens or {}
        target._tokens["pane.border.color"]  = accent
        target._tokens["titlebar.text.color"] = accent
        if target.applyTheme then target:applyTheme() end
    end
    render(target, player)
    target._f2tCardFingerprint = fingerprint(player)
end

-- Deferred to F2T_CONTENT_REGISTRARS like every other f2ce-tools content module.
function f2tRegisterPlayerCard()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[player_card] Muxlet content API unavailable; skipping") end
        return
    end

    Mux.registerContent("f2t_player_card", {
        name        = "Player Card",
        description = "Rank-colored info card for a player, with quick-send.",
        group       = "F2CE Tools",
        internal    = true,
        singleton   = false,

        apply = function(target)
            target.contentBg:echo(""); target.contentBg:hide()
            -- Mux._applyContent temporarily aliases target.content to a disposable
            -- one-shot slot for the duration of this call, then restores it to the
            -- pane's real, permanent .content right after apply() returns. Calling
            -- renderCard synchronously here would build the quick-send slot (which
            -- ensureQuickSlot only ever creates once, then reuses forever) inside
            -- that disposable slot -- while every later render (any data refresh)
            -- builds its own rows fresh under the real .content instead, since by
            -- then the alias has already been restored. That split every card that
            -- ever refreshes into two independently-tracked containers which merely
            -- happen to cover the same rectangle instead of guaranteed to, and
            -- explains the border misaligning after some refreshes but not others.
            -- Deferring one tick guarantees this first render also runs against
            -- the real, permanent container, so every widget the card ever creates
            -- shares the exact same parent for its whole life.
            tempTimer(0, function() renderCard(target) end)
        end,

        remove = function(target)
            if target._f2tCardActionKey then
                _G[target._f2tCardActionKey] = nil
                target._f2tCardActionKey = nil
            end
            if target._f2tQuickSlot then
                pcall(function() target._f2tQuickSlot.container:delete() end)
                target._f2tQuickSlot = nil
            end
            -- _f2tCardSlot is destroyed with the rest of the content slot
            target._f2tCardSlot = nil
        end,

        resize = function(target) renderCard(target) end,

        serialize = function(target) return { name = target._f2tCardPlayerName } end,
        restore   = function(target, data)
            if data and data.name then
                target._f2tCardPlayerName = data.name
                target._f2tCardPlayerData = nil   -- force a fresh DB lookup
                renderCard(target)
            end
        end,
    })
    if f2t_debug_log then f2t_debug_log("[player_card] registered f2t_player_card content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterPlayerCard)

-- ── Public: show or raise ─────────────────────────────────────────────────────

local function showCard(player)
    local name = player.name or "Unknown"
    local accent = accentFor(player)
    local w, h = initialContentSize(player)
    local theme = Mux.activeTheme and Mux.activeTheme() or {}
    local chromeH = (theme.titlebarHeight or 22) + 6
    local sw, sh = getMainWindowSize()
    local n = 0
    for _ in pairs(_cardsByName) do n = n + 1 end
    local offset = n % 10 * 22
    local floatW, floatH = w + 6, h + chromeH

    local pane = Mux.newFloatingPane({
        name             = name,
        nameAlign        = "center",
        floatX           = math.floor(((sw or 1200) - floatW) / 2) + offset,
        floatY           = math.floor(((sh or 800)  - floatH) / 2) + offset,
        floatW           = floatW,
        floatH           = floatH,
        propertiesButton = false,
        contentable      = false,
        zoomable         = false,
        confirmClose     = false,
        convertible      = true,
        splittable       = false,
        swappable        = true,
        resizable        = false,
        borderColor      = accent,
        tokens           = { ["titlebar.text.color"] = accent },
        onClose          = function() _cardsByName[name] = nil end,
    })
    if not pane then return end

    pane._f2tCardPlayerName = name
    pane._f2tCardPlayerData = player
    _cardsByName[name] = pane

    Mux._applyContent(pane, "f2t_player_card")
end

function f2tPlayerCardShowOrRaise(player)
    local name = player and player.name
    if not name then return end
    local existing = _cardsByName[name]
    if existing then Mux.raisePane(existing); return end
    showCard(player)
end

function f2tPlayerCardShowOrRaiseByName(name)
    if not name or name == "" then return end
    local existing = _cardsByName[name]
    if existing then Mux.raisePane(existing); return end
    local dbEntry = f2t_player_db_get and f2t_player_db_get(name)
    showCard(dbEntry or { name = name })
end

-- Re-render open cards whose data changed since they were last shown.
function f2tPlayerCardsRefreshAll()
    local anyRendered = false
    for name, pane in pairs(_cardsByName) do
        local fresh = (f2t_player_db_get and f2t_player_db_get(name))
        if fresh and fingerprint(fresh) ~= pane._f2tCardFingerprint then
            pane._f2tCardPlayerData = fresh
            renderCard(pane)
            anyRendered = true
        end
    end
    -- Freshly recreated widgets land on top of the Qt stacking order regardless
    -- of Muxlet's own logical z-order (see local_players.lua's identical fix), so
    -- a live data update on a card sitting *behind* others would otherwise pop it
    -- to the front. Re-assert the real order once, after all cards are updated.
    if anyRendered and Mux and Mux.raiseFloatingPanes then Mux.raiseFloatingPanes() end
end

if f2t_debug_log then f2t_debug_log("[player_card] module loaded") end
