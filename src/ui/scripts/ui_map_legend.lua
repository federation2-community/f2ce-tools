-- Map legend popup — Adjustable.Container reference card for room type colors/symbols

local _legend_shown = false

function ui_map_legend_close()
    if UI.map_legend_card then UI.map_legend_card:hide() end
    _legend_shown = false
end

function ui_map_legend_open()
    if UI.map_legend_card then
        UI.map_legend_card:show()
        UI.map_legend_card:raiseAll()
        _legend_shown = true
        return
    end

    if type(f2t_map_get_legend_data) ~= "function" then return end

    local sw, sh = getMainWindowSize()
    local W, H   = 420, 350
    local cx     = math.floor((sw - W) / 2)
    local cy     = math.floor((sh - H) / 2)

    UI.map_legend_card = Adjustable.Container:new({
        name          = "UI.map_legend_card",
        x             = cx, y = cy,
        width         = W,  height = H,
        adjLabelstyle = [[
            background-color: rgba(10, 12, 20, 252);
            border: 1px solid rgba(255, 255, 255, 0.28);
            border-radius: 4px;
        ]],
        autoSave = false,
        autoLoad = false,
    })
    UI.map_legend_card:lockContainer("border")
    UI.map_legend_card.locked = false

    local _in   = UI.map_legend_card.Inside
    local HDR_H = 34

    local hdr = Geyser.Label:new(
        { name = "ui_ml_hdr", x = 0, y = 0, width = "100%", height = HDR_H },
        _in
    )
    hdr:setStyleSheet([[
        background: qlineargradient(x1:0,y1:0,x2:0,y2:1,
            stop:0 rgba(25,30,48,255), stop:1 rgba(14,16,28,255));
        border: none; border-radius: 4px 4px 0 0;
    ]])

    local title = Geyser.Label:new(
        { name = "ui_ml_title", x = 12, y = 7, width = "-38", height = 22 },
        hdr
    )
    title:setStyleSheet([[
        background: transparent; border: none;
        color: rgba(195,210,225,0.95);
        font-size: 12px; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
    ]])
    title:echo("⊞  Map Legend")

    local close_btn = Geyser.Label:new(
        { name = "ui_ml_close", x = "-30", y = 6, width = 24, height = 22 },
        hdr
    )
    close_btn:setStyleSheet([[
        QLabel {
            background-color: rgba(180,50,50,220);
            border: 1px solid rgba(200,80,80,180);
            border-radius: 3px;
            color: white;
            font-size: 14px; font-weight: bold;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover { background-color: rgba(215,60,60,245); border-color: rgba(255,110,110,220); }
    ]])
    close_btn:echo("<center>✕</center>")
    close_btn:setClickCallback(function() ui_map_legend_close() end)

    local data = f2t_map_get_legend_data()
    local rows = {}
    for _, entry in ipairs(data) do
        local sym        = entry.symbol ~= "" and entry.symbol or "·"
        local text_color = entry.text_color or "#ddeeff"
        table.insert(rows, string.format(
            "<tr>"
            .. "<td style='width:48px;text-align:center;padding:3px 2px'>"
            ..   "<span style='background:%s;color:%s;padding:2px 6px;"
            ..   "border-radius:2px;font-size:11px'>%s</span>"
            .. "</td>"
            .. "<td style='padding:3px 8px;color:rgba(205,215,225,0.95);font-size:11px;"
            ..   "white-space:nowrap'>%s</td>"
            .. "<td style='padding:3px 6px;color:rgba(105,120,135,0.85);font-size:10px;'>%s</td>"
            .. "</tr>",
            entry.html_color, text_color, sym, entry.label, entry.note
        ))
    end

    local html = string.format(
        "<div style='font-family:Consolas,Monaco,monospace;'>"
        .. "<table style='width:100%%;border-collapse:collapse;padding:3px'>%s</table>"
        .. "</div>",
        table.concat(rows, "")
    )

    local content = Geyser.Label:new(
        { name = "ui_ml_content", x = 0, y = HDR_H, width = "100%", height = "100%-34px" },
        _in
    )
    content:setStyleSheet([[
        background: transparent; border: none;
        color: #b8c4d8;
        font-family: "Consolas","Monaco",monospace;
    ]])
    content:echo(html)

    _legend_shown = true
    UI.map_legend_card:hide()
    UI.map_legend_card:show()
    UI.map_legend_card:raiseAll()
end

function ui_map_legend_toggle()
    if _legend_shown then
        ui_map_legend_close()
    else
        ui_map_legend_open()
    end
end
