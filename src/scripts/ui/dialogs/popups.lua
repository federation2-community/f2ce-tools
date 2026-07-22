-- fed2-tools — First-run mode selection dialog
--
-- f2tShowModeSelect() is called by init.lua's muxletReady handler on first run.
-- Presents three startup modes with radio-style option selection.
-- On confirm, persists mux_autostart and starts Muxlet appropriately.
--
-- Uses Mux.registerContent + Mux._applyContent so Muxlet handles the pane
-- chrome (contentBg clearing, z-order, theme) correctly.

-- ── Settings helpers ──────────────────────────────────────────────────────────

local function isFirstRun()
    local d = Mux.settings and Mux.settings._data
    if not d or not d["f2t"] then return true end
    return d["f2t"]["mux_autostart"] == nil
end

local function setAutostart(enabled)
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["mux_autostart"] = enabled
    Mux.settings.save()
end

-- ── Mode selection dialog ─────────────────────────────────────────────────────
--
-- Three modes presented as a radio list:
--   minimal — no Muxlet start; command-line tools only; layout unchanged
--   byow    — Muxlet starts with blank default workspace; user builds own layout
--   full    — Muxlet starts and fed2-tools workspace loads (recommended)

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
    "<font color='#c6d2ee'>Mapping, automated trading, factory management, and quality-of-life " ..
    "tools for Federation 2 &mdash; grab what fits your playstyle.</font>"

local _COMPONENTS = {
    { name = "Map & Nav",        desc = "auto-mapping, galaxy topology, speedwalk travel" },
    { name = "Hauling",          desc = "rank-aware automated commodity trading" },
    { name = "Factory",          desc = "status table, one-command flush-to-market" },
    { name = "Planet Owner",     desc = "exchange breakdowns for your planets" },
    { name = "Commodities",      desc = "bulk buy/sell, cross-cartel price checks" },
    { name = "Stamina & Refuel", desc = "automatic food runs and ship refueling" },
    { name = "Death Protection", desc = "halts automation when you die" },
    { name = "Chat",             desc = "persistent com/tell/say history" },
}

local function buildComponentsHtml()
    local parts = {}
    for _, comp in ipairs(_COMPONENTS) do
        parts[#parts + 1] = string.format(
            "<font color='#7ab4ff'><b>%s</b></font><font color='#c6d2ee'> &mdash; %s</font>",
            comp.name, comp.desc
        )
    end
    return table.concat(parts, "<br>")
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
    local SB_W = 16

    -- Intro line
    local intro = Geyser.Label:new({
        name = pfx .. "intro", x = INNER_X, y = 8, width = INNER_W, height = 32,
    }, c)
    intro:setStyleSheet([[
        background: transparent;
        color: rgba(198,210,238,255);
        font-size: 10px;
        padding: 4px 14px;
    ]])
    intro:echo(_INTRO_HTML)

    -- "COMPONENTS" header
    local compHdr = Geyser.Label:new({
        name = pfx .. "comp_hdr", x = INNER_X, y = 42, width = INNER_W, height = 14,
    }, c)
    compHdr:setStyleSheet(
        "background: transparent; color: #73de94; font-size: 9px; font-weight: bold; padding: 0 14px;"
    )
    compHdr:echo("COMPONENTS")

    -- Scrollable component list (keeps the dialog compact as the list grows)
    local compScroll = Geyser.ScrollBox:new({
        name = pfx .. "comp_scroll", x = INNER_X, y = 58, width = INNER_W, height = 112,
    }, c)

    local compContentW = math.max(100, compScroll:get_width() - SB_W)
    local compBody = Geyser.Label:new({
        name = pfx .. "comp_body", x = 0, y = 0, width = compContentW, height = 200,
    }, compScroll)
    compBody:setStyleSheet([[
        background: transparent;
        color: rgba(198,210,238,255);
        font-size: 10px;
        padding: 2px 14px;
    ]])
    compBody:echo(buildComponentsHtml())

    -- Divider
    local div = Geyser.Label:new({
        name = pfx .. "div", x = 0, y = 174, width = "100%", height = 1,
    }, c)
    div:setStyleSheet(Mux.dialogCss.divider)

    -- "How would you like to start?" prompt
    local prompt = Geyser.Label:new({
        name = pfx .. "prompt", x = INNER_X, y = 181, width = INNER_W, height = 22,
    }, c)
    prompt:setStyleSheet("background: transparent; color: rgba(198,210,238,200); font-size: 10px; padding: 2px 14px;")
    prompt:echo("How would you like to start?")

    -- ── Radio options ─────────────────────────────────────────────────────────

    local selectedMode = "full"
    local indicators   = {}
    local rowBgs       = {}

    local FILLED   = "●"
    local EMPTY    = "○"
    local ROW_H    = 62
    local ROW_Y0   = 208

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

    -- Confirm button — the only way to advance; no close button on this dialog
    local btnY = ROW_Y0 + #_MODES * (ROW_H + 4) + 10
    local btn = Geyser.Label:new({
        name = pfx .. "confirm",
        x = "30%", y = btnY, width = "40%", height = 36,
    }, c)
    btn:setStyleSheet(Mux.dialogCss.buttonPrimary)
    btn:echo("<center>Let's Go</center>")
    btn:setClickCallback(function()
        target:close()
        if selectedMode == "full" then
            setAutostart(true)
            -- Set before fullStart() so its own no-'current'-yet fallback
            -- picks up "fed2-tools" directly — no separate apply call needed,
            -- and no race with fullStart's own internal deferred setup.
            Mux.configureHost({ defaultWorkspace = "fed2-tools" })
            Mux.fullStart()
        elseif selectedMode == "byow" then
            setAutostart(true)
            Mux.configureHost({ defaultWorkspace = "default" })
            Mux.fullStart()
        else
            setAutostart(false)
        end
    end)
end

-- ── Public entry point ────────────────────────────────────────────────────────

local _shown = false

function f2tShowModeSelect()
    if _shown then return end
    _shown = true

    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho(
            "\n<cyan>[fed2-tools]<reset> <white>Welcome!<reset>"
            .. " To start with the full workspace: <cyan>mux start<reset>"
            .. " then <cyan>mux workspace load fed2-tools<reset>\n"
        )
        setAutostart(false)
        return
    end

    if not Mux._content or not Mux._content["f2t_mode_select"] then
        Mux.registerContent("f2t_mode_select", {
            internal = true,
            name     = "Welcome",
            apply    = applyModeSelectToPane,
        })
    end

    local DIALOG_W = 540
    local DIALOG_H = 530

    local dialog = Mux.createDialog({
        title     = "Welcome to fed2-tools",
        width     = DIALOG_W,
        height    = DIALOG_H,
        closeable = false,
    })
    Mux._applyContent(dialog, "f2t_mode_select")
    dialog:show()
    dialog:raise()
end
