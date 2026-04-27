UI.movement         = UI.movement or {}
UI.movement.visible = true

-- Build Movement Buttons
function ui_build_movement()
    ------------- Main Container -------------------------------
    UI.map_commands_container = Adjustable.Container:new(
        {
            name          = "UI.map_commands_container",
            x             = "0%",
            y             = "77%",
            width         = "30%",
            height        = "22%",
            lockStyle     = "none",
            adjLabelstyle = UI.style.frame_css,
            attached      = "left",
            autoSave      = false,
            autoLoad      = false
        },
        UI.tab_top_right.fedmapcenter
    )
    UI.map_commands_container:connectToBorder("left")
    UI.map_commands_container:lockContainer("none")

    ------------- Show/Hide Button -----------------------------
    UI.button_show_hide = Geyser.Label:new(
        {
            name    = "UI.button_show_hide",
            x       = "0%",
            y       = "78%",
            width   = "4%",
            height  = "10%"
        },
        UI.map_commands_container
    )
    UI.button_show_hide:setStyleSheet(UI.style.toggle_button_css)
    UI.button_show_hide:setClickCallback("ui_toggle_movement_buttons")
    UI.button_show_hide:setToolTip("Show/Hide Movement Buttons")

    -------------- Board Button --------------------------------
    UI.button_board = Geyser.Label:new(
        {
            name    = "UI.button_board",
            x       = "0%",
            y       = "0%",
            width   = "17%",
            height  = "17%",
            message = "<center>B</center>"
        },
        UI.map_commands_container
    )
    UI.button_board:setStyleSheet(UI.style.button_css)
    UI.button_board:setClickCallback("ui_board")
    UI.button_board:setToolTip("board")

    ------------- IN/OUT Container -----------------------------
    UI.in_out_box = Geyser.Container:new(
        {
            name   = "UI.in_out_box",
            x      = "22%",
            y      = "2%",
            width  = "60%",
            height = "17%"
        },
        UI.map_commands_container
    )

    ------------- IN Button ------------------------------------
    UI.button_in = Geyser.Label:new(
        {
            name    = "UI.button_in",
            x       = 0,
            y       = 0,
            width   = "25%",
            height  = "100%",
            message = "<center>IN</center>"
        },
        UI.in_out_box
    )
    UI.button_in:setStyleSheet(UI.style.button_css)
    UI.button_in:setClickCallback("ui_move_in")

    ------------- OUT Button -----------------------------------
    UI.button_out = Geyser.Label:new(
        {
            name    = "UI.button_out",
            x       = "27%",
            y       = 0,
            width   = "35%",
            height  = "100%",
            message = "<center>OUT</center>"
        },
        UI.in_out_box
    )
    UI.button_out:setStyleSheet(UI.style.button_css)
    UI.button_out:setClickCallback("ui_move_out")

    ------------- Compass Container ----------------------------
    UI.cardinal_box = Geyser.Container:new(
        {
            name   = "UI.cardinal_box",
            x      = "5%",
            y      = "22%",
            width  = "85%",
            height = "85%"
        },
        UI.map_commands_container
    )

    -- Create all 9 compass buttons with percentages
    local compass_layout = {
        {var = "button_nw" , x = "0%" , y = "0%" , w = "25%", h = "25%", cb = "ui_move_nw",              msg = "NW"},
        {var = "button_n"  , x = "27%", y = "0%" , w = "25%", h = "25%", cb = "ui_move_n" ,              msg = "N" },
        {var = "button_ne" , x = "54%", y = "0%" , w = "25%", h = "25%", cb = "ui_move_ne",              msg = "NE"},
        {var = "button_w"  , x = "0%" , y = "27%", w = "25%", h = "25%", cb = "ui_move_w" ,              msg = "W" },
        {var = "button_e"  , x = "54%", y = "27%", w = "25%", h = "25%", cb = "ui_move_e" ,              msg = "E" },
        {var = "button_sw" , x = "0%" , y = "54%", w = "25%", h = "25%", cb = "ui_move_sw",              msg = "SW"},
        {var = "button_s"  , x = "27%", y = "54%", w = "25%", h = "25%", cb = "ui_move_s" ,              msg = "S" },
        {var = "button_se" , x = "54%", y = "54%", w = "25%", h = "25%", cb = "ui_move_se",              msg = "SE"},
        {var = "buttonLook", x = "27%", y = "27%", w = "25%", h = "25%", cb = "ui_look"   , tt = "Look", msg = "👁"}
    }
    
    for _, btn in ipairs(compass_layout) do
        UI[btn.var] = Geyser.Label:new(
            {
                name    = "UI." .. btn.var,
                x       = btn.x,
                y       = btn.y,
                width   = btn.w,
                height  = btn.h,
                message = "<center>" .. btn.msg .. "</center>"
            },
            UI.cardinal_box
        )
        UI[btn.var]:setStyleSheet(UI.style.button_css)
        UI[btn.var]:setClickCallback(btn.cb)

        if btn.tt then UI[btn.var]:setToolTip(btn.tt) end
    end

    ------------- UP/DOWN Container ----------------------------
    UI.vertical_box = Geyser.Container:new(
        {
            name   = "UI.vertical_box",
            x      = "75%",
            y      = "33%",
            width  = "17%",
            height = "60%",
        },
        UI.map_commands_container
    )

    ------------- UP Button ------------------------------------
    UI.button_up = Geyser.Label:new(
        {
            name    = "UI.button_up",
            x       = 0,
            y       = 0,
            width   = "100%",
            height  = "35%",
            message = "<center>UP</center>"
        },
        UI.vertical_box
    )
    UI.button_up:setStyleSheet(UI.style.button_css)
    UI.button_up:setClickCallback("ui_move_up")

    ------------- DOWN Button ----------------------------------
    UI.button_down = Geyser.Label:new(
        {
            name    = "UI.button_down",
            x       = 0,
            y       = "37%",
            width   = "100%",
            height  = "35%",
            message = "<center>DN</center>"
        },
        UI.vertical_box
    )
    UI.button_down:setStyleSheet(UI.style.button_css)
    UI.button_down:setClickCallback("ui_move_down")

    ------------- Press Button ----------------------------------
    UI.button_press = Geyser.Label:new(
        {
            name    = "UI.button_press",
            x      = "73%",
            y      = "4%",
            width  = "12%",
            height = "16%",
            message = "<center>P</center>"
        },
        UI.map_commands_container
    )
    UI.button_press:setStyleSheet(UI.style.button_css)
    UI.button_press:setClickCallback("ui_press")

    -- Store button and action references
    UI.movement.directions = {
        n      = { button = UI.button_n,     action = "ui_move_n"    },
        ne     = { button = UI.button_ne,    action = "ui_move_ne"   },
        e      = { button = UI.button_e,     action = "ui_move_e"    },
        se     = { button = UI.button_se,    action = "ui_move_se"   },
        s      = { button = UI.button_s,     action = "ui_move_s"    },
        sw     = { button = UI.button_sw,    action = "ui_move_sw"   },
        w      = { button = UI.button_w,     action = "ui_move_w"    },
        nw     = { button = UI.button_nw,    action = "ui_move_nw"   },
        up     = { button = UI.button_up,    action = "ui_move_up"   },
        down   = { button = UI.button_down,  action = "ui_move_down" },
        ["in"] = { button = UI.button_in,    action = "ui_move_in"   },
        out    = { button = UI.button_out,   action = "ui_move_out"  },
        board  = { button = UI.button_board, action = "ui_board"     }
    }
end

function ui_press()
    if UI.press then
        UI.press:hide()
        UI.press = nil

        return
    end

    UI.press = Geyser.Container:new(
        {
            name   = "UI.press",
            x      = "87%",
            y      = "4%",
            width  = "40%",
            height = "16%"
        },
        UI.map_commands_container
    )

    UI.press_button = Geyser.Label:new(
        {
            name    = "UI.press_button",
            x       = "0%",
            y       = "0%",
            width   = "75%",
            height  = "100%",
            message = "<center>Button</center>",
        },
        UI.press
    )
    UI.press_button:setStyleSheet(UI.style.button_css)
    UI.press_button:setClickCallback(function()
        send("press button")
        UI.press:hide()
        UI.press = nil
    end)

    UI.press_touchpad = Geyser.Label:new(
        {
            name    = "UI.press_touchpad",
            x       = "77%",
            y       = "0%",
            width   = "100%",
            height  = "100%",
            message = "<center>Touchpad</center>",
        },
        UI.press
    )
    UI.press_touchpad:setStyleSheet(UI.style.button_css)
    UI.press_touchpad:setClickCallback(function()
        send("press touchpad")
        UI.press:hide()
        UI.press = nil
    end)

    UI.press:show()
    UI.press:raise()
end

-- Toggle Movement Buttons Visibility
function ui_toggle_movement_buttons()
    if UI.movement.visible then
        UI.cardinal_box:hide()
        UI.vertical_box:hide()
        UI.in_out_box:hide()
        UI.button_show_hide:echo("<center>Show Buttons</center>")
        UI.button_board:hide()
        UI.button_press:hide()
        UI.movement.visible = false
    else
        UI.cardinal_box:show()
        UI.vertical_box:show()
        UI.in_out_box:show()
        UI.button_show_hide:echo("<center>Hide Buttons</center>")
        UI.button_board:show()
        UI.button_press:show()
        UI.movement.visible = true
    end
end

function ui_move_n()
    send("n", false)
end

function ui_move_ne()
    send("ne", false)
end

function ui_move_e()
    send("e", false)
end

function ui_move_se()
    send("se", false)
end

function ui_move_s()
    send("s", false)
end

function ui_move_sw()
    send("sw", false)
end

function ui_move_w()
    send("w", false)
end

function ui_move_nw()
    send("nw", false)
end

function ui_move_up()
    send("up", false)
end

function ui_move_down()
    send("down", false)
end

function ui_move_in()
    send("in", false)
end

function ui_move_out()
    send("out", false)
end

function ui_look()
    send("look", false)
end

function ui_board()
    send("board", false)
end
