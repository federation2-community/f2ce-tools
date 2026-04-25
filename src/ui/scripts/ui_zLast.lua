function ui_fuel_status()
    -- Update Buy Fuel button state
    if UI.button_buy_fuel then
        local fuel_full = false
        local is_space  = false

        if not gmcp then return end

        local gmcp_room_flags = gmcp.room and gmcp.room.info and gmcp.room.info.flags or {}
        local gmcp_fuel       = gmcp.char and gmcp.char.ship and gmcp.char.ship.fuel  or {}
        
        if f2t_is_rank_below("Commander") then
            UI.button_buy_fuel:hide()
        else
            UI.button_buy_fuel:show()
        end
        
        if type(gmcp_fuel.cur) == "number" and gmcp_fuel.cur == gmcp_fuel.max then fuel_full = true end
        
        if f2t_has_value(gmcp_room_flags, "space") then is_space = true end

        if fuel_full or is_space then
            UI.button_buy_fuel:setStyleSheet(UI.style.disabled_button_css)
            UI.button_buy_fuel:cecho("<center><gray>Buy Fuel<reset></center>")
            UI.button_buy_fuel:setClickCallback(function() end)
        else
            UI.button_buy_fuel:setStyleSheet(UI.style.button_css)
            UI.button_buy_fuel:cecho("<center><white>Buy Fuel<reset></center>")
            UI.button_buy_fuel:setClickCallback("ui_buy_fuel")
        end
    end
end

function ui_buy_fuel()
    send("buy fuel", false)
end

-- Run on every update to GMCP room info
function ui_on_gmcp_room_info()
    local exits = {}

    -- get all the gmcp room exits and add them to valid exits
    for exit, _ in pairs(gmcp.room.info.exits) do
        table.insert(exits, exit:lower())
    end

    if f2t_has_value(gmcp.room.info.flags, "exchange") then
        UI.tab_top_left:addTab("Exchange", 1)
    else
        UI.tab_top_left:removeTab("Exchange")
    end

    -- Detect shuttlepad or orbit and add board to valid exits
    if f2t_has_value(gmcp.room.info.flags, "shuttlepad") or f2t_has_value(gmcp.room.info.flags, "orbit") or gmcp.room.info.orbit then table.insert(exits, "board") end

    for dir, dirData in pairs(UI.movement.directions) do
        if f2t_has_value(exits, dir) then
            dirData.button:setStyleSheet(UI.style.button_css)
            dirData.button:setClickCallback(dirData.action)
        else
            dirData.button:setStyleSheet(UI.style.disabled_button_css)
            dirData.button:setClickCallback(function() end)
        end
    end

    ui_fuel_status()
    ui_update_local_players()
end

function ui_update_for_rank()
    if f2t_is_rank_or_above("Commander") then
        if not f2t_has_value(UI.tab_bottom_right.tabs, "Hauling") then
            UI.tab_bottom_right:addTab("Hauling", 1)
        end

        UI.button_status:show()
    else
        UI.tab_bottom_right:removeTab("Hauling")
        UI.button_status:hide()
    end

    -- Trading: only rank 4+
    if f2t_is_rank_or_above("Merchant") then
        if not f2t_has_value(UI.tab_bottom_right.tabs, "Trading") then
            UI.tab_bottom_right:addTab("Trading", 2)
        end
    else
        UI.tab_bottom_right:removeTab("Trading")
    end
end

function ui_remote_access_status()
    local remote_access = gmcp.char.vitals.tools and gmcp.char.vitals.tools["remote-access-cert"]

    if remote_access and remote_access.days > 0 then
      -- Show cartel-related buttons
      UI.cartel_toggle_button:show()
      UI.best_profit_button:show()
      
      -- Add tooltip with days remaining
      local tooltip = string.format("Remote Access Active (%d days remaining)", remote_access.days)

      UI.cartel_toggle_button:setToolTip(tooltip)
      UI.best_profit_button:setToolTip(tooltip)
    else
      -- Hide cartel-related buttons
      UI.cartel_toggle_button:hide()
      UI.best_profit_button:hide()
      
      -- Ensure cartel mode is off
      UI.trading.use_cartel = false
      
      -- Stop any active profit search
      if UI.trading.profit_search and UI.trading.profit_search.active then
        UI.trading.profit_search.active = false
        if UI.profit_progress_bar then
          UI.profit_progress_bar:hide()
        end
      end
    end
end

-- ── Floating gear icon ─────────────────────────────────────────────────────────
-- Sits just outside the corner where left_frame's right border meets
-- top_left_frame's bottom border:
--   • gear's LEFT  edge = left_frame's RIGHT edge   (outside, to the right)
--   • gear's TOP   edge = top_left_frame's BOTTOM edge (outside, below)
-- Free-floating on the main window (no parent container).

local _GEAR_SIZE = 26

function ui_build_gear_icon()
    UI.gear_icon = Geyser.Label:new({
        name   = "UI.gear_icon",
        x      = 0,
        y      = 0,
        width  = _GEAR_SIZE,
        height = _GEAR_SIZE,
    })
    UI.gear_icon:setStyleSheet(UI.style.button_css)
    UI.gear_icon:setFontSize(13)
    UI.gear_icon:echo("<center>⚙</center>")
    UI.gear_icon:setClickCallback("ui_toggle_settings")

    -- Position it correctly, then raise above other widgets
    ui_reposition_gear_icon()
    UI.gear_icon:raise()
end

-- Reposition gear icon based on current container geometry.
-- Called after window resize and container reposition events.
function ui_reposition_gear_icon()
    if not UI.gear_icon or not UI.left_frame or not UI.top_left_frame then return end

    -- Gear LEFT edge = left_frame's right edge (just outside the frame, to its right)
    local gx = UI.left_frame:get_x() + UI.left_frame:get_width()
    -- Gear TOP edge = top_left_frame's bottom edge (just below the frame)
    local gy = UI.top_left_frame:get_y() + UI.top_left_frame:get_height()

    UI.gear_icon:move(gx, gy)
    UI.gear_icon:raise()
end

function ui_build()
    ui_create_containers()
    ui_build_tabs()
    ui_build_tab_content()
    ui_build_header()
    ui_build_gear_icon()
    ui_build_quick_buttons()
    ui_build_movement()
    ui_hauling()
    ui_trading()
    ui_update_for_rank()
    ui_update_header()
    ui_who_init()
    ui_chat_init()
    ui_load_tab_layout()

    ui_built = true
    f2t_debug_log("[ui] ui_build finished")
end

function ui_register_trigger()
    f2t_ui_register_trigger("chatInbound")
    f2t_ui_register_trigger("exchange")
    f2t_ui_register_trigger("findBestProfitHide")
    f2t_ui_register_trigger("galaxySystemEnd")
    f2t_ui_register_trigger("galaxySystemLine")
    f2t_ui_register_trigger("haulingJob")
    f2t_ui_register_trigger("haulingStart")
    f2t_ui_register_trigger("movementPlayer")
    f2t_ui_register_trigger("promotions")
    f2t_ui_register_trigger("spynetReport")
    f2t_ui_register_trigger("tradingLine")
    f2t_ui_register_trigger("tradingProfitSearch")
    f2t_ui_register_trigger("whoListStart")
    f2t_ui_register_trigger("whoListLine")
    f2t_ui_register_trigger("whoListEnd")

    ui_triggered = true
    f2t_debug_log("[ui] registered triggers")
end

function ui_register_alias()
    f2t_ui_register_alias("chatOutbound")

    ui_aliased = true
    f2t_debug_log("[ui] registered aliases")
end

function ui_register_event()
    f2t_ui_register_event("AdjustableContainerRepositionFinish", "ui_on_container_reposition")
    f2t_ui_register_event("AdjustableContainerRepositionFinish", "ui_settings_on_reposition")
    f2t_ui_register_event("sysWindowResizeEvent"               , "ui_on_window_resize")
    f2t_ui_register_event("gmcp.char"                          , "ui_update_header")
    f2t_ui_register_event("gmcp.room.info"                     , "ui_on_gmcp_room_info")
    f2t_ui_register_event("gmcp.char.vitals.tools"             , "ui_remote_access_status")
    f2t_ui_register_event("sysConnectionEvent"                 , "ui_chat_on_connect")
    f2t_ui_register_event("sysDisconnectionEvent"              , "ui_chat_on_disconnect")
    f2t_ui_register_event("gmcp.char.vitals"                   , "ui_who_on_login_vitals")

    ui_evented = true
    f2t_debug_log("[ui] registered events")
end

-- If UI is enabled, kick everything off
if F2T_UI_STATE.enabled then
    if not ui_built     then ui_build()            end
    if not ui_triggered then ui_register_trigger() end
    if not ui_evented   then ui_register_event()   end
    if not ui_aliased   then ui_register_alias()   end
end
