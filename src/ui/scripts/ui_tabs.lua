function ui_build_tabs()
    -- Build the box to split the right frame in half
    UI.vbox_left = Geyser.VBox:new(
        {
            name   = "UI.vbox_left",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%"
        },
        UI.left_frame
    )

    -- Build the box to split the right frame in half
    UI.vbox_right = Geyser.VBox:new(
        {
            name   = "UI.vbox_right",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%"
        },
        UI.right_frame
    )

    -- Place Who/General/Exchange tabs In Top Left Navigation Frame (Who is default active)
    UI.tab_top_left = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_left",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Who","General","Exchange"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_left
    )

    -- Place Comm tab on the top of the Bottom Left Navigation Frame (default location)
    UI.tab_bottom_left = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_bottom_left",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Comm"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_left
    )

    -- Place Map/Comms tabs on the top of the Right Navigation Frame (default location)
    UI.tab_top_right = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_top_right",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"fedmap"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_right
    )

    -- Place Hauling/Trading/Company tabs on the bottom of the Right Navigation Frame (default location)
    -- Visibility of each tab is managed by ui_update_for_rank() in ui_zLast.lua.
    UI.tab_bottom_right = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_bottom_right",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Hauling","Trading","Company","Futures"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            notifyTabStyle   = UI.style.notify_inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_right
    )

end

-- Restore tab layout from the previous session.
-- save() and load() are class-level operations: they iterate Adjustable.TabWindow.all
-- and save/restore every window's tab assignments, active tab, and floating state
-- (including the position and size of any independently-floated windows).
-- On first run the save file won't exist and load() silently returns, leaving
-- tabs in their default positions.
function ui_load_tab_layout()
    Adjustable.TabWindow:load()
end

-- Call ui_tab_notify("TabName") whenever content is added to a tab to show the
-- red-border indicator on that tab if it is not currently active.
-- The indicator is automatically cleared when the user switches to the tab.
-- Uses Adjustable.TabWindow.allTabs (the live tracker) so this works correctly
-- even after the user drags a tab to a different frame or floats it.

function ui_tab_notify(tab_name)
    local tab_window = Adjustable.TabWindow.allTabs and Adjustable.TabWindow.allTabs[tab_name]
    if not tab_window then return end
    tab_window:notify(tab_name)
end

function ui_tab_clear_notify(tab_name)
    local tab_window = Adjustable.TabWindow.allTabs and Adjustable.TabWindow.allTabs[tab_name]
    if not tab_window then return end
    tab_window:clearNotification(tab_name)
end

-- populate our various tabs
function ui_build_tab_content()
    local text_size = 12

        --put general console in general tab
    UI.general_window = Geyser.MiniConsole:new(
        {
            name      = "UI.general_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_top_left.Generalcenter
    )

    -- ── General tab filter button ─────────────────────────────────────────
    UI.general_filter_btn = Geyser.Label:new({
        name   = "UI.general_filter_btn",
        x      = "-22", y = "2",
        width  = "20",  height = "16",
    }, UI.tab_top_left.Generalcenter)
    UI.general_filter_btn:setStyleSheet([[
        QLabel{ background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
                border-radius:3px; border-color:rgba(100,100,110,180);
                color:rgba(160,160,170,255); font-size:10px; font-weight:bold; }
        QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }
    ]])
    UI.general_filter_btn:echo("<center>A</center>")
    UI.general_filter_btn:setToolTip("Show all")
    UI.general_filter_btn:setClickCallback(function() ui_general_cycle_filter() end)

    --put Exchange console in Exchange tab
    UI.exchange_window = Geyser.MiniConsole:new(
        {
            name      = "UI.exchange_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.tab_top_left:removeTab("Exchange")

    --put chat console in chat tab
    UI.chat_window = Geyser.MiniConsole:new(
        {
            name      = "UI.chat_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_bottom_left.Commcenter
    )

    -- ── Comm tab buttons ──────────────────────────────────────────────────
    -- Filter button (cycles A/C/T/S); sits left of the timestamp button.
    UI.chat_filter_btn = Geyser.Label:new({
        name   = "UI.chat_filter_btn",
        x      = "-44", y = "2",
        width  = "20",  height = "16",
    }, UI.tab_bottom_left.Commcenter)
    UI.chat_filter_btn:setStyleSheet([[
        QLabel{ background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
                border-radius:3px; border-color:rgba(100,100,110,180);
                color:rgba(160,160,170,255); font-size:10px; font-weight:bold; }
        QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }
    ]])
    UI.chat_filter_btn:echo("<center>A</center>")
    UI.chat_filter_btn:setToolTip("Show all messages")
    UI.chat_filter_btn:setClickCallback(function() ui_chat_cycle_filter() end)

    -- Timestamp toggle button.
    UI.chat_ts_btn = Geyser.Label:new({
        name   = "UI.chat_ts_btn",
        x      = "-22", y = "2",
        width  = "20",  height = "16",
    }, UI.tab_bottom_left.Commcenter)
    UI.chat_ts_btn:echo("<center><font color='#3a3a3a'>⏱</font></center>")
    UI.chat_ts_btn:setStyleSheet(UI.style.button_css)
    UI.chat_ts_btn:setToolTip("Timestamps OFF — click to toggle")
    UI.chat_ts_btn:setClickCallback(function() ui_chat_toggle_timestamps() end)

    -- ── Who tab ───────────────────────────────────────────────────────────
    -- Header leaves 44px on the right for the Online/All toggle button.
    UI.who_header = Geyser.Label:new({
        name = "UI.who_header",
        x = "0%", y = "0",
        width = "-46", height = "20",
    }, UI.tab_top_left.Whocenter)
    UI.who_header:setStyleSheet(UI.style.header_label_css)
    UI.who_header:echo("  👥  Who's Online")

    -- Online / All toggle button
    UI.who_toggle_btn = Geyser.Label:new({
        name = "UI.who_toggle_btn",
        x = "-44", y = "2",
        width = "42", height = "16",
    }, UI.tab_top_left.Whocenter)
    UI.who_toggle_btn:setStyleSheet([[
        QLabel{ background-color:rgba(28,28,32,200); border-style:solid; border-width:1px;
                border-radius:3px; border-color:rgba(100,100,110,180);
                color:rgba(160,160,170,255); font-size:9px; font-weight:bold; }
        QLabel::hover{ background-color:rgba(60,60,70,220); color:white; }
    ]])
    UI.who_toggle_btn:echo("<center>Online</center>")
    UI.who_toggle_btn:setToolTip("Toggle Online / All known players")
    UI.who_toggle_btn:setClickCallback(function() ui_who_toggle_view() end)

    -- MiniConsole for the table renderer — sits below the 21px header.
    UI.who_window = Geyser.MiniConsole:new({
        name      = "UI.who_window",
        x         = "0%", y = "21px",
        width     = "100%", height = "100%-21px",
        autoWrap  = true,
        scrollBar = true,
        fontSize  = 12,
        color     = "black",
    }, UI.tab_top_left.Whocenter)

    --put map into map window
    UI.mapper = Geyser.Mapper:new(
        {
            name   = "fedmap",
            x      = "0%",
            y      = "0%", 
            width  = "100%",
            height = "100%",
        },
        UI.tab_top_right.fedmapcenter
    )

    --put hauling container in hauling tab
    UI.hauling_container = Geyser.Container:new(
        {
            name   = "UI.hauling_container",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%",
        },
        UI.tab_bottom_right.Haulingcenter
    )

    -- Button bar at top
    UI.hauling_button_bar = Geyser.HBox:new(
        {
            name   = "UI.hauling_button_bar",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "25px",
        },
        UI.hauling_container
    )

    UI.hauling_window = Geyser.MiniConsole:new(
        {
            name      = "UI.hauling_window",
            x         = "0%",
            y         = "25px",
            width     = "100%",
            height    = "100%-25px",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = 12,
            color     = "black",
        },
        UI.hauling_container
    )

    --put trading container in trading tab
    UI.trading_container = Geyser.Container:new(
        {
            name   = "UI.trading_container",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%",
        },
        UI.tab_bottom_right.Tradingcenter
    )

    -- Button bar at top
    UI.trading_button_bar = Geyser.HBox:new(
        {
            name   = "UI.trading_button_bar",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "25px",
        },
        UI.trading_container
    )

    UI.trading_window = Geyser.MiniConsole:new(
        {
            name      = "UI.trading_window",
            x         = "0%",
            y         = "25px",
            width     = "100%",
            height    = "100%-25px",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = 12,
            color     = "black",
        },
        UI.trading_container
    )

    -- put futures container in futures tab
    UI.futures_container = Geyser.Container:new(
        {
            name   = "UI.futures_container",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "100%",
        },
        UI.tab_bottom_right.Futurescenter
    )

    -- Button bar at top
    UI.futures_button_bar = Geyser.HBox:new(
        {
            name   = "UI.futures_button_bar",
            x      = "0%",
            y      = "0%",
            width  = "100%",
            height = "25px",
        },
        UI.futures_container
    )

    UI.futures_window = Geyser.MiniConsole:new(
        {
            name      = "UI.futures_window",
            x         = "0%",
            y         = "25px",
            width     = "100%",
            height    = "100%-25px",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = 12,
            color     = "black",
        },
        UI.futures_container
    )
end