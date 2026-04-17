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

    -- Place Exchange/Commodities tabs In Top Left Navigation Frame (default location)
    UI.tab_top_left = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_left",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Spynet","Exchange", "Commodities"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_left
    )

    -- Place Spynet/Comms tab on the top of the Bottom Left Navigation Frame (default location)
    UI.tab_bottom_left = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_bottom_left",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Comm","Who"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
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
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_right
    )

    -- Place Hauling/Trading tabs on the bottom of the Right Navigation Frame (default location)
    UI.tab_bottom_right = Adjustable.TabWindow:new(
        {
            name             = "UI.tab_bottom_right",
            x                = "0%",
            y                = "0%",
            width            = "100%",
            height           = "100%",
            tabBarHeight     = "8%",
            tabs             = {"Hauling","Trading"},
            activeTabStyle   = UI.style.active_tab_css,
            inactiveTabStyle = UI.style.inactive_tab_css,
            footerStyle      = UI.style.footer_css,
            centerStyle      = UI.style.center_css,
        },
        UI.vbox_right
    )
end

-- populate our various tabs
function ui_build_tab_content()
    local text_size = 12

        --put spynet console in spynet tab
    UI.general_window = Geyser.MiniConsole:new(
        {
            name      = "UI.general_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = false,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_top_left.Spynetcenter
    )

    --put Exchange console in Exchange tab
    UI.exchange_window = Geyser.MiniConsole:new(
        {
            name      = "UI.exchange_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = false,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_top_left.Exchangecenter
    )
    UI.tab_top_left:removeTab("Exchange")

    --put commodities console in commodities tab
    UI.commodities_window = Geyser.MiniConsole:new(
        {
            name      = "UI.commodities_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = true,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_top_left.Commoditiescenter
    )

    --put chat console in chat tab
    UI.chat_window = Geyser.MiniConsole:new(
        {
            name      = "UI.chat_window",
            x         = "0%",
            y         = "0%",
            width     = "100%",
            height    = "100%",
            autoWrap  = true,
            scrollBar = false,
            fontSize  = text_size,
            color     = "black",
        },
        UI.tab_bottom_left.Commcenter
    )

    -- Timestamp toggle button — sits top-right of the Comm center pane.
    -- Dim by default; brightens when timestamps are active.
    UI.chat_ts_btn = Geyser.Label:new({
        name   = "UI.chat_ts_btn",
        x      = "-22", y = "2",
        width  = "20",  height = "16",
    }, UI.tab_bottom_left.Commcenter)
    UI.chat_ts_btn:echo("<center><font color='#3d3d3d'>⏱</font></center>")
    UI.chat_ts_btn:setStyleSheet(UI.style.button_css)
    UI.chat_ts_btn:setToolTip("Timestamps OFF — click to toggle")
    UI.chat_ts_btn:setClickCallback(function() ui_chat_toggle_timestamps() end)
 
    -- Who tab: header label + refresh button + scrollable table window
    UI.who_header = Geyser.Label:new({
        name   = "UI.who_header",
        x      = "0%", y = "0",
        width  = "-24", height = "20",
    }, UI.tab_bottom_left.Whocenter)
    UI.who_header:setStyleSheet(UI.style.header_label_css)
    UI.who_header:echo("  👥  Who's Online")
 
    UI.who_refresh_btn = Geyser.Label:new({
        name   = "UI.who_refresh_btn",
        x      = "-22", y = "2",
        width  = "20",  height = "16",
    }, UI.tab_bottom_left.Whocenter)
    UI.who_refresh_btn:echo("<center>⟳</center>")
    UI.who_refresh_btn:setStyleSheet(UI.style.button_css)
    UI.who_refresh_btn:setToolTip("Refresh who list")
    UI.who_refresh_btn:setClickCallback(function() ui_who_refresh() end)
 
    UI.who_window = Geyser.MiniConsole:new({
        name      = "UI.who_window",
        x         = "0%", y = "22",
        width     = "100%", height = "-22",
        autoWrap  = true,
        scrollBar = true,
        fontSize  = text_size,
        color     = "black",
    }, UI.tab_bottom_left.Whocenter)
    
    -- Trigger a who refresh whenever the Who tab is clicked into
    if UI.tab_bottom_left.Who and UI.tab_bottom_left.Who.adjLabel then
        UI.tab_bottom_left.Who.adjLabel:setClickCallback(function(event)
            UI.tab_bottom_left:onClick("Who", event)
            ui_who_refresh()
        end)
    end

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
end