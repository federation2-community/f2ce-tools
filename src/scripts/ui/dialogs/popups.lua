-- fed2-tools: first-run mode selection dialog
--
-- f2tShowModeSelect() is called by init.lua's muxletReady handler on first run.
-- Presents three startup modes with radio-style option selection.
-- On confirm, persists mux_autostart and starts Muxlet appropriately.
--
-- Uses Mux.registerContent + Mux._applyContent so Muxlet handles the pane
-- chrome (contentBg clearing, z-order, theme) correctly.

-- ── Settings helpers ──────────────────────────────────────────────────────────

-- Global (not local): f2t.lua's "f2t on"/"f2t off" reuse this to flip the same
-- flag the mode-select dialog writes, so there is only one source of truth for
-- whether Muxlet auto-starts.
function f2tSetAutostart(enabled)
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["mux_autostart"] = enabled
    Mux.settings.save()
end

-- ── Mode selection dialog ─────────────────────────────────────────────────────
--
-- Three modes presented as a radio list:
--   minimal: no Muxlet start; command-line tools only; layout unchanged
--   byow:    Muxlet starts with blank default workspace; user builds own layout
--   full:    Muxlet starts and fed2-tools workspace loads (recommended)

local _MODES = {
    { id = "full",    label = "Full  (Recommended)",
      desc = "Load the fed2-tools workspace: output pane and map side by side.<br>" ..
             "Muxlet starts automatically on every session." },
    { id = "byow",    label = "Build Your Own Workspace",
      desc = "Start Muxlet with a blank canvas. All fed2-tools content is<br>" ..
             "registered &mdash; add it to any pane with right-click &rsaquo; Add Content." },
    { id = "minimal", label = "Minimal",
      desc = "No changes to your Mudlet layout. All commands and aliases work.<br>" ..
             "Run <b>mux start</b> any time to open a workspace later." },
}

local _INTRO_HTML =
    "<font color='#c6d2ee'>fed2-tools is a Mudlet package for F2CE covering mapping, " ..
    "automated trading, factory management, and the other quality-of-life tools listed " ..
    "below. It also includes a full GUI workspace, which is the recommended way to use it.</font>"

local _COMPONENTS = {
    { name = "Map & Nav",         desc = "auto-mapping, galaxy topology, speedwalk travel" },
    { name = "Galaxy Navigator",  desc = "browse syndicates, cartels, systems, and planets; click to travel" },
    { name = "Hauling",           desc = "rank-aware automated commodity trading" },
    { name = "Factory",           desc = "status table, one-command flush-to-market" },
    { name = "Company",           desc = "factory, financial, and portfolio overview panes (rank-gated)" },
    { name = "Planet Owner",      desc = "exchange breakdowns for your planets" },
    { name = "Commodities",       desc = "bulk buy/sell, cross-cartel price checks" },
    { name = "Exchange & Futures", desc = "live price ticker and futures contracts/positions" },
    { name = "Cargo",             desc = "live ship manifest" },
    { name = "Stamina & Refuel",  desc = "automatic food runs and ship refueling" },
    { name = "Death Protection",  desc = "halts automation when you die" },
    { name = "Chat",              desc = "persistent com/tell/say history" },
    { name = "Player Info",       desc = "rank, fuel, stamina, groats, slithies, and hold at a glance" },
    { name = "Who / Local Players", desc = "online and in-room player lists" },
}

local function buildComponentsHtml()
    local parts = {}
    for _, comp in ipairs(_COMPONENTS) do
        parts[#parts + 1] = string.format(
            "<div style='margin-bottom:6px;'>" ..
            "<font color='#7ab4ff'><b>%s</b></font><font color='#c6d2ee'> &mdash; %s</font>" ..
            "</div>",
            comp.name, comp.desc
        )
    end
    return table.concat(parts, "")
end

-- ── Layout ─────────────────────────────────────────────────────────────────────
-- Every y-offset derives from the one above it plus a gap.
-- introH is hardcoded, not computed: Qt's getSizeHint() sizes word-wrapped
-- labels for an unconstrained width, not the actual render width, so it
-- overshoots. 56px matches 3 real-rendered lines at 10px font.
local function computeLayout()
    local gap = 6

    local introY, introH   = 8, 56
    local hdrY,   hdrH     = introY + introH + gap, 14
    -- Fixed viewport height. compBody's real content height is measured in
    -- applyModeSelectToPane instead of estimated here; a row-count formula
    -- undershot it twice.
    local compY, compH     = hdrY + hdrH + gap, 200
    local divY              = compY + compH + gap
    local promptY, promptH = divY + 1 + gap, 22
    local rowY0             = promptY + promptH + gap
    local rowH, rowGap     = 62, 4
    local btnY, btnH        = rowY0 + #_MODES * (rowH + rowGap) + 10, 36

    return {
        introY = introY, introH = introH,
        hdrY = hdrY, hdrH = hdrH,
        compY = compY, compH = compH,
        divY = divY,
        promptY = promptY, promptH = promptH,
        rowY0 = rowY0, rowH = rowH, rowGap = rowGap,
        btnY = btnY, btnH = btnH,
        contentBottom = btnY + btnH,
    }
end

-- ── Content apply function ────────────────────────────────────────────────────
-- Called by Mux._applyContent; target is the MuxPane (the dialog).

local function applyModeSelectToPane(target)
    target.contentBg:echo("")
    target.contentBg:setStyleSheet("background-color:rgba(0,0,0,0);border:none;")

    local INNER_W = "94%"
    local INNER_X = "3%"

    local c   = target.content
    local pfx = target._gid .. "_ms_"
    local L   = computeLayout()

    -- Intro line, word-wrapped: QLabel needs qproperty-wordWrap or it clips instead
    local intro = Geyser.Label:new({
        name = pfx .. "intro", x = INNER_X, y = L.introY, width = INNER_W, height = L.introH,
    }, c)
    intro:setStyleSheet([[
        background: transparent;
        color: rgba(198,210,238,255);
        font-size: 10px;
        padding: 4px 14px;
        qproperty-alignment: 'AlignLeft|AlignTop';
        qproperty-wordWrap: true;
    ]])
    intro:echo(_INTRO_HTML)

    -- "COMPONENTS" header
    local compHdr = Geyser.Label:new({
        name = pfx .. "comp_hdr", x = INNER_X, y = L.hdrY, width = INNER_W, height = L.hdrH,
    }, c)
    compHdr:setStyleSheet(
        "background: transparent; color: #73de94; font-size: 9px; font-weight: bold; padding: 0 14px;"
    )
    compHdr:echo("COMPONENTS")

    -- Geyser.ScrollBox has no setStyleSheet of its own; the underlying Qt
    -- scroll area defaults to white, so the content label must be opaque.
    local compScroll = Geyser.ScrollBox:new({
        name = pfx .. "comp_scroll", x = INNER_X, y = L.compY, width = INNER_W, height = L.compH,
    }, c)

    local SB_W = 16
    local compContentW = math.max(100, compScroll:get_width() - SB_W)
    local compBody = Geyser.Label:new({
        name = pfx .. "comp_body", x = 0, y = 0, width = compContentW, height = L.compH,
    }, compScroll)
    compBody:setStyleSheet([[
        background-color: rgba(18, 18, 26, 255);
        border: none;
        color: rgba(198,210,238,255);
        font-size: 10px;
        padding: 2px 14px;
    ]])
    compBody:echo(buildComponentsHtml())

    -- Rows don't wrap, so getSizeHint() reports the real stacked-div height
    -- reliably here (unlike the intro paragraph). Deferred a tick to run
    -- after the dialog is shown, not mid-construction.
    tempTimer(0, function()
        if not (compBody and compBody.adjustHeight) then return end
        compBody:adjustHeight()
        if compBody:get_height() < L.compH then
            compBody:resize(compContentW, L.compH)
        end
    end)

    -- Divider
    local div = Geyser.Label:new({
        name = pfx .. "div", x = 0, y = L.divY, width = "100%", height = 1,
    }, c)
    div:setStyleSheet(Mux.dialogCss.divider)

    -- "How would you like to start?" prompt
    local prompt = Geyser.Label:new({
        name = pfx .. "prompt", x = INNER_X, y = L.promptY, width = INNER_W, height = L.promptH,
    }, c)
    prompt:setStyleSheet("background: transparent; color: rgba(198,210,238,200); font-size: 10px; padding: 2px 14px;")
    prompt:echo("How would you like to start?")

    -- ── Radio options ─────────────────────────────────────────────────────────

    local selectedMode = "full"
    local indicators   = {}
    local rowBgs       = {}

    local FILLED   = "●"
    local EMPTY    = "○"
    local ROW_H    = L.rowH
    local ROW_Y0   = L.rowY0

    local function updateSelection(chosenId)
        selectedMode = chosenId
        for _, m in ipairs(_MODES) do
            local isFill = (m.id == chosenId)
            indicators[m.id]:echo(isFill and FILLED or EMPTY)
            indicators[m.id]:setStyleSheet(string.format(
                "background: transparent; font-size: 14px; color: %s;",
                isFill and "rgba(115,222,148,255)" or "rgba(120,140,180,180)"
            ))
            rowBgs[m.id]:setStyleSheet(
                isFill
                    and "background: rgba(60,80,50,80); border-radius: 4px;"
                    or  "background: transparent;"
            )
        end
    end

    for i, mode in ipairs(_MODES) do
        local rowY = ROW_Y0 + (i - 1) * (ROW_H + 4)

        -- Row background (highlights on selection)
        local bg = Geyser.Label:new({
            name = pfx .. "bg_" .. mode.id,
            x = INNER_X, y = rowY, width = INNER_W, height = ROW_H,
        }, c)
        bg:setStyleSheet("background: transparent;")
        rowBgs[mode.id] = bg

        -- Circle indicator
        local ind = Geyser.Label:new({
            name = pfx .. "ind_" .. mode.id,
            x = "5%", y = rowY + 8, width = 22, height = 22,
        }, c)
        ind:setStyleSheet("background: transparent; font-size: 14px; color: rgba(120,140,180,180);")
        ind:echo(EMPTY)
        indicators[mode.id] = ind

        -- Mode label
        local lbl = Geyser.Label:new({
            name = pfx .. "lbl_" .. mode.id,
            x = "12%", y = rowY + 6, width = "85%", height = 20,
        }, c)
        lbl:setStyleSheet("background: transparent; color: rgba(198,210,238,255); font-size: 10px; font-weight: bold;")
        lbl:echo(mode.label)

        -- Mode description
        local desc = Geyser.Label:new({
            name = pfx .. "desc_" .. mode.id,
            x = "12%", y = rowY + 28, width = "85%", height = 30,
        }, c)
        desc:setStyleSheet("background: transparent; color: rgba(150,170,200,200); font-size: 9px;")
        desc:echo(mode.desc)

        -- Click handlers on every element in the row
        local capturedId = mode.id
        local clickFn = function() updateSelection(capturedId) end
        bg:setClickCallback(clickFn)
        ind:setClickCallback(clickFn)
        lbl:setClickCallback(clickFn)
        desc:setClickCallback(clickFn)
    end

    -- Pre-select Full
    updateSelection("full")

    -- Confirm button: the only way to persist a choice
    local btn = Geyser.Label:new({
        name = pfx .. "confirm",
        x = "30%", y = L.btnY, width = "40%", height = L.btnH,
    }, c)
    btn:setStyleSheet(Mux.dialogCss.buttonPrimary)
    btn:echo("<center>Let's Go</center>")
    btn:setClickCallback(function()
        target:close()
        if selectedMode == "full" then
            f2tSetAutostart(true)
            -- Set before fullStart() so its no-'current'-yet fallback picks up
            -- "fed2-tools" directly: no separate apply call, no race with
            -- fullStart's own internal deferred setup.
            Mux.configureHost({ defaultWorkspace = "fed2-tools" })
            Mux.fullStart()
        elseif selectedMode == "byow" then
            f2tSetAutostart(true)
            Mux.configureHost({ defaultWorkspace = "default" })
            Mux.fullStart()
        else
            f2tSetAutostart(false)
        end
    end)

    -- Sizes the dialog to the content actually built above (introH included)
    -- instead of a hand-maintained constant in f2tShowModeSelect.
    target:fitContent(L.contentBottom)
end

-- ── Public entry point ────────────────────────────────────────────────────────

local _shown = false

-- force=true bypasses the one-shot guard, for "f2t mode" re-opening this
-- deliberately after first run. The dialog is also made closeable in that
-- case: the mandatory first-run appearance has no close button so a new
-- install can't skip the choice, but a user who summoned this themselves
-- shouldn't get stuck if they just want to look.
function f2tShowModeSelect(force)
    if _shown and not force then return end
    _shown = true

    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho(
            "\n<cyan>[fed2-tools]<reset> <white>Welcome!<reset>"
            .. " To start with the full workspace: <cyan>mux start<reset>"
            .. " then <cyan>mux workspace load fed2-tools<reset>\n"
        )
        f2tSetAutostart(false)
        return
    end

    if not Mux._content or not Mux._content["f2t_mode_select"] then
        Mux.registerContent("f2t_mode_select", {
            internal = true,
            name     = "Welcome",
            apply    = applyModeSelectToPane,
        })
    end

    -- height is a placeholder; applyModeSelectToPane's closing fitContent()
    -- call resizes the dialog to the content it actually built.
    local dialog = Mux.createDialog({
        title     = "Welcome to fed2-tools",
        width     = 540,
        height    = 300,
        closeable = force == true,
    })
    -- Only the "Let's Go" button (above) persists a choice via f2tSetAutostart.
    -- Closing via the X leaves mux_autostart untouched: nil on a first run, so
    -- the dialog resurfaces next load instead of silently defaulting to Minimal.
    Mux._applyContent(dialog, "f2t_mode_select")
    dialog:show()
    dialog:raise()
end
