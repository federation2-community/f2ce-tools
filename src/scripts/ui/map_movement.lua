-- f2tBuildMapMovement(parent, gid) creates a compass + navigation button
-- panel as a transparent overlay in the bottom-left of the Fed2 Map pane.
--
-- Shell: x=0%, y=80%, width=30%, height=21% (left 30% of pane, bottom 21%)
-- Inside shell:
--   Board button     - x=0%,  y=0%,  w=17%, h=17%
--   IN/OUT container - x=22%, y=2%,  w=60%, h=17%
--   Press button     - x=73%, y=4%,  w=12%, h=16%
--   Compass grid     - x=5%,  y=22%, w=85%, h=85%  (3x3, 25% buttons, 2% gaps)
--   UP/DN column     - x=75%, y=33%, w=17%, h=60%
--   Toggle tab       - x=0%,  y=78%, w=4%,  h=10%  (shows/hides all above)

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
local _CSS_TOGGLE = [[
    QLabel {
        background-color: rgba(22,26,42,200);
        color: rgba(140,160,200,220);
        border: 1px solid rgba(60,70,100,160);
        border-radius: 2px;
        font-size: 9px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(36,44,72,220);
        color: rgba(180,200,240,240);
        border-color: rgba(90,110,160,200);
    }
]]
local _CSS_BTN_DISABLED = [[
    QLabel {
        background-color: rgba(18,20,30,150);
        color: rgba(120,128,145,140);
        border: 1px solid rgba(50,56,75,120);
        border-radius: 3px;
        font-size: 11px;
        qproperty-alignment: AlignCenter;
    }
]]

-- Handler id for the last-built pane's exit-state updater, so a fresh
-- f2tBuildMapMovement() call (new pane instance) doesn't leave a stale
-- handler pointing at buttons that no longer exist.
local _exitHandlerId = nil

function f2tBuildMapMovement(parent, gid)
    local pfx = gid .. "_mv_"

    if _exitHandlerId then
        killAnonymousEventHandler(_exitHandlerId)
        _exitHandlerId = nil
    end

    -- Buttons that get enabled/disabled based on gmcp.room.info.exits (and the
    -- board flag below). Keyed by the direction/command sent on click.
    local dirButtons = {}

    -- ── Outer shell ───────────────────────────────────────────────────────────
    local shell = Geyser.Container:new({
        name   = pfx .. "shell",
        x      = "0%",
        y      = "81%",
        width  = "30%",
        height = "21%",
    }, parent)

    -- ── Board button ──────────────────────────────────────────────────────────
    local boardBtn = Geyser.Label:new({
        name   = pfx .. "board",
        x      = "3%",
        y      = "1%",
        width  = "17%",
        height = "17%",
    }, shell)
    boardBtn:setStyleSheet(_CSS_BTN)
    boardBtn:echo("<center>B</center>")
    boardBtn:setClickCallback(function() send("board", true) end)
    dirButtons["board"] = boardBtn

    -- ── IN / OUT container ────────────────────────────────────────────────────
    local inOutBox = Geyser.Container:new({
        name   = pfx .. "inout",
        x      = "22%",
        y      = "2%",
        width  = "60%",
        height = "17%",
    }, shell)

    local btnIn = Geyser.Label:new({
        name   = pfx .. "in",
        x      = 0,
        y      = 0,
        width  = "25%",
        height = "100%",
    }, inOutBox)
    btnIn:setStyleSheet(_CSS_BTN)
    btnIn:echo("<center>IN</center>")
    btnIn:setClickCallback(function() send("in", true) end)
    dirButtons["in"] = btnIn

    local btnOut = Geyser.Label:new({
        name   = pfx .. "out",
        x      = "27%",
        y      = 0,
        width  = "35%",
        height = "100%",
    }, inOutBox)
    btnOut:setStyleSheet(_CSS_BTN)
    btnOut:echo("<center>OUT</center>")
    btnOut:setClickCallback(function() send("out", true) end)
    dirButtons["out"] = btnOut

    -- ── Press button + flyout ─────────────────────────────────────────────────
    local pressPanel = nil
    local pressBtn = Geyser.Label:new({
        name   = pfx .. "press",
        x      = "73%",
        y      = "4%",
        width  = "12%",
        height = "16%",
    }, shell)
    pressBtn:setStyleSheet(_CSS_BTN)
    pressBtn:echo("<center>P</center>")
    pressBtn:setClickCallback(function()
        if pressPanel then
            pressPanel:hide()
            pressPanel = nil
            return
        end
        -- Start at x=86% so the flyout begins immediately right of P (which ends at 85%).
        -- Overflows the shell right edge into the mapper area — intentional.
        pressPanel = Geyser.Container:new({
            name   = pfx .. "pressPanel",
            x      = "86%",
            y      = "4%",
            width  = "70%",
            height = "16%",
        }, shell)
        local btnLbl = Geyser.Label:new({
            name   = pfx .. "pressButton",
            x      = "0%",
            y      = "0%",
            width  = "40%",
            height = "100%",
        }, pressPanel)
        btnLbl:setStyleSheet(_CSS_BTN)
        btnLbl:echo("<center>Button</center>")
        btnLbl:setClickCallback(function()
            send("press button", true)
            pressPanel:hide()
            pressPanel = nil
        end)
        -- "Touchpad" is longer than "Button" — give it the larger share so its
        -- label doesn't clip except at very small map pane sizes.
        local btnPad = Geyser.Label:new({
            name   = pfx .. "pressTouchpad",
            x      = "44%",
            y      = "0%",
            width  = "56%",
            height = "100%",
        }, pressPanel)
        btnPad:setStyleSheet(_CSS_BTN)
        btnPad:echo("<center>Touchpad</center>")
        btnPad:setClickCallback(function()
            send("press touchpad", true)
            pressPanel:hide()
            pressPanel = nil
        end)
        pressPanel:show()
        pressPanel:raise()
    end)

    -- ── Compass grid ──────────────────────────────────────────────────────────
    -- 3×3; buttons are 25%×25% with 2% gaps (offsets: 0%, 27%, 54%).
    local compass = Geyser.Container:new({
        name   = pfx .. "compass",
        x      = "5%",
        y      = "22%",
        width  = "85%",
        height = "85%",
    }, shell)

    local compassLayout = {
        { n="nw", x="0%",  y="0%",  w="25%", h="25%", lbl="NW",  cmd="nw"   },
        { n="n",  x="27%", y="0%",  w="25%", h="25%", lbl="N",   cmd="n"    },
        { n="ne", x="54%", y="0%",  w="25%", h="25%", lbl="NE",  cmd="ne"   },
        { n="w",  x="0%",  y="27%", w="25%", h="25%", lbl="W",   cmd="w"    },
        { n="lk", x="27%", y="27%", w="25%", h="25%", lbl="👁",   cmd="look" },
        { n="e",  x="54%", y="27%", w="25%", h="25%", lbl="E",   cmd="e"    },
        { n="sw", x="0%",  y="54%", w="25%", h="25%", lbl="SW",  cmd="sw"   },
        { n="s",  x="27%", y="54%", w="25%", h="25%", lbl="S",   cmd="s"    },
        { n="se", x="54%", y="54%", w="25%", h="25%", lbl="SE",  cmd="se"   },
    }

    for _, b in ipairs(compassLayout) do
        local btn = Geyser.Label:new({
            name   = pfx .. b.n,
            x      = b.x,
            y      = b.y,
            width  = b.w,
            height = b.h,
        }, compass)
        btn:setStyleSheet(_CSS_BTN)
        btn:echo("<center>" .. b.lbl .. "</center>")
        local cmd = b.cmd
        btn:setClickCallback(function() send(cmd, true) end)
        if cmd ~= "look" then
            dirButtons[cmd] = btn
        end
    end

    -- ── UP / DN column ────────────────────────────────────────────────────────
    local vertBox = Geyser.Container:new({
        name   = pfx .. "vert",
        x      = "75%",
        y      = "33%",
        width  = "17%",
        height = "60%",
    }, shell)

    local btnUp = Geyser.Label:new({
        name   = pfx .. "up",
        x      = 0,
        y      = 0,
        width  = "100%",
        height = "35%",
    }, vertBox)
    btnUp:setStyleSheet(_CSS_BTN)
    btnUp:echo("<center>UP</center>")
    btnUp:setClickCallback(function() send("up", true) end)
    dirButtons["up"] = btnUp

    local btnDn = Geyser.Label:new({
        name   = pfx .. "down",
        x      = 0,
        y      = "37%",
        width  = "100%",
        height = "35%",
    }, vertBox)
    btnDn:setStyleSheet(_CSS_BTN)
    btnDn:echo("<center>DN</center>")
    btnDn:setClickCallback(function() send("down", true) end)
    dirButtons["down"] = btnDn

    -- ── Exit-state updater ───────────────────────────────────────────────────
    -- Greys out (and disables the click callback of) any directional button
    -- whose direction isn't a valid exit from the current room, per GMCP room
    -- info. "board" is a synthetic exit added whenever docked/orbiting.
    local function updateExitState()
        if not gmcp or not gmcp.room or not gmcp.room.info then return end

        local exits = {}
        for exit in pairs(gmcp.room.info.exits or {}) do
            table.insert(exits, exit:lower())
        end
        if f2t_has_room_flag("shuttlepad") or f2t_has_room_flag("orbit") or gmcp.room.info.orbit then
            table.insert(exits, "board")
        end

        for dir, button in pairs(dirButtons) do
            if f2t_has_value(exits, dir) then
                button:setStyleSheet(_CSS_BTN)
                button:setClickCallback(function() send(dir, true) end)
            else
                button:setStyleSheet(_CSS_BTN_DISABLED)
                button:setClickCallback(function() end)
            end
        end
    end

    updateExitState()
    _exitHandlerId = registerAnonymousEventHandler("gmcp.room.info", updateExitState)

    -- ── Show / hide toggle ────────────────────────────────────────────────────
    -- Small tab on the left edge of the shell (x=0-4%), vertically within the
    -- lower compass row (y=78%), so it sits to the left of the SW button.
    local visible = true
    local toggleBtn = Geyser.Label:new({
        name   = pfx .. "toggle",
        x      = "0%",
        y      = "78%",
        width  = "4%",
        height = "10%",
    }, shell)
    toggleBtn:setStyleSheet(_CSS_TOGGLE)
    toggleBtn:echo("<center>▲</center>")
    toggleBtn:setClickCallback(function()
        if visible then
            boardBtn:hide()
            inOutBox:hide()
            compass:hide()
            vertBox:hide()
            pressBtn:hide()
            toggleBtn:echo("<center>▼</center>")
            visible = false
        else
            boardBtn:show()
            inOutBox:show()
            compass:show()
            vertBox:show()
            pressBtn:show()
            toggleBtn:echo("<center>▲</center>")
            visible = true
        end
    end)

    return shell
end
