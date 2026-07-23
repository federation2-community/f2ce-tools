-- f2tShowMapLegend() opens a reference card for mapper room colors/symbols,
-- rendered from f2t_map_get_legend_data() (map/style.lua, the single source
-- of truth for symbols and environment colors). Launched from the F2CE Map
-- gear menu (ui/map_settings.lua).
--
-- Uses Mux.registerContent + Mux._applyContent so the dialog integrates
-- cleanly with Muxlet's pane lifecycle (contentBg cleared, z-order, theme borders).

local function legendHtml()
    if type(f2t_map_get_legend_data) ~= "function" then
        return "<div style='color:#8899aa;padding:8px;'>Legend data unavailable.</div>"
    end

    local rows = {}
    for _, entry in ipairs(f2t_map_get_legend_data()) do
        local sym       = entry.symbol ~= "" and entry.symbol or "·"
        local textColor = entry.text_color or "#ddeeff"
        table.insert(rows, string.format(
            "<tr>"
            .. "<td style='width:52px;text-align:center;padding:4px 2px'>"
            ..   "<span style='background:%s;color:%s;padding:3px 7px;"
            ..   "border-radius:2px;font-size:13px'>%s</span>"
            .. "</td>"
            .. "<td style='padding:4px 8px;color:rgba(205,215,225,0.95);font-size:13px;"
            ..   "white-space:nowrap'>%s</td>"
            .. "<td style='padding:4px 6px;color:rgba(105,120,135,0.85);font-size:12px;'>%s</td>"
            .. "</tr>",
            entry.html_color, textColor, sym, entry.label, entry.note
        ))
    end

    return string.format(
        "<div style='font-family:Consolas,Monaco,monospace;'>"
        .. "<table style='width:100%%;border-collapse:collapse;padding:3px'>%s</table>"
        .. "</div>",
        table.concat(rows, ""))
end

local function applyMapLegendToPane(target)
    target.contentBg:echo("")
    target.contentBg:setStyleSheet("background-color:rgba(0,0,0,0);border:none;")

    local lbl = Geyser.Label:new({
        name = target._gid .. "_mlgd", x = 0, y = 0, width = "100%", height = "100%",
    }, target.content)
    lbl:setStyleSheet([[
        background: transparent; border: none;
        color: #b8c4d8;
        font-family: "Consolas","Monaco",monospace;
    ]])
    lbl:echo(legendHtml())
end

function f2tShowMapLegend()
    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho("\n<yellow>[f2ce-tools]<reset> Map legend requires Muxlet.\n")
        return
    end

    if not Mux._content or not Mux._content["f2t_map_legend"] then
        Mux.registerContent("f2t_map_legend", {
            internal = true,
            name     = "Map Legend",
            apply    = applyMapLegendToPane,
        })
    end

    local dialog = Mux.createDialog({
        title     = "Map Legend",
        width     = 460,
        height    = 440,
        resizable = true,
        singleton = "f2t_map_legend",
    })
    Mux._applyContent(dialog, "f2t_map_legend")
    dialog:show()
    dialog:raise()
end
