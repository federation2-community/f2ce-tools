UI.style = UI.style or {}

setProfileStyleSheet([[
QScrollBar:vertical {
    background: rgba(255,255,255,0.03);
    width: 10px;
    margin: 2px;
    border-radius: 3px;
}

QScrollBar::handle:vertical {
    background: rgba(255,255,255,0.38);
    border: 1px solid rgba(255,255,255,0.45);
    border-radius: 3px;
    min-height: 24px;

    box-shadow:
        inset 0 1px 0 rgba(255,255,255,0.15),
        0 0 6px rgba(255,255,255,0.05);
}

QScrollBar::handle:vertical:hover {
    background: rgba(255,255,255,0.52);
    border-color: rgba(255,255,255,0.65);
}

QScrollBar::handle:vertical:pressed {
    background: rgba(255,255,255,0.70);
}

QScrollBar::add-line:vertical,
QScrollBar::sub-line:vertical {
    height: 0px;
    background: none;
}

QScrollBar::add-page:vertical,
QScrollBar::sub-page:vertical {
    background: none;
}
]])

UI.style.frame_css = [[
    /* Slightly translucent light panel so frames read on black backgrounds */
    background: rgba(255,255,255,0.035); /* a touch of light so panels aren't 'black on black' */

    /* Thin, visible light border that contrasts on black */
    border: 2px solid rgba(255,255,255,0.46);

    /* Faster, crisp interactions */
    transition: transform 120ms ease, box-shadow 160ms ease, border-color 120ms ease, background 120ms ease;
    color: rgba(255,255,255,0.95);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

-- Active tab - modern translucent style
UI.style.active_tab_css = UI.style.active_tab_css or [[
    background-color: rgba(40, 40, 50, 230);
    color: rgba(255, 255, 255, 0.95);
    border-top-left-radius: 0px;
    border-top-right-radius: 0px;
    border-width: 2px;
    border-style: solid;
    border-color: rgba(255, 255, 255, 0.46);
    margin-right: 1px;
    margin-left: 1px;
    qproperty-alignment: 'AlignVCenter';
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.10), 0 2px 8px rgba(0, 0, 0, 0.4);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

-- Inactive tab - modern translucent style with hover effects
UI.style.inactive_tab_css = UI.style.inactive_tab_css or [[
    QLabel::hover{
        background-color: rgba(50, 50, 60, 200);
        color: rgba(255, 255, 255, 0.95);
        border-top-left-radius: 0px;
        border-top-right-radius: 0px;
        border-width: 2px;
        border-style: solid;
        border-color: rgba(120, 180, 255, 0.6);
        margin-right: 1px;
        margin-left: 1px;
        qproperty-alignment: 'AlignVCenter';
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 2px 6px rgba(0, 0, 0, 0.3);
        transition: all 120ms ease;
    }
    QLabel::!hover{
        background-color: rgba(30, 30, 35, 180);
        color: rgba(200, 200, 210, 0.85);
        border-top-left-radius: 10px;
        border-top-right-radius: 10px;
        border-width: 1px;
        border-style: solid;
        border-color: rgba(100, 100, 110, 0.3);
        margin-right: 1px;
        margin-left: 1px;
        qproperty-alignment: 'AlignVCenter';
    }
]]

-- Footer - modern translucent style
UI.style.footer_css = [[
    background-color: rgba(35, 35, 45, 220);
    border-bottom-left-radius: 3px;
    border-bottom-right-radius: 3px;
    border-width: 2px;
    border-style: solid;
    border-color: rgba(255, 255, 255, 0.46);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 4px 12px rgba(0, 0, 0, 0.5);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

-- Center container - modern translucent style
UI.style.center_css = [[
    background-color: rgba(25, 25, 30, 200);
    border-radius: 5px;
    border-width: 1px;
    border-style: solid;
    border-color: rgba(80, 80, 90, 0.4);
    margin: 5px;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.05), 0 6px 20px rgba(0, 0, 0, 0.6);
    -webkit-backdrop-filter: blur(3px) saturate(105%);
    backdrop-filter: blur(3px) saturate(105%);
]]

-- style the labels: background color and a little border between each label
UI.style.label_css = [[
    background-color: rgba(77,77,77,100); /*because DimGrey is not dark enough*/
    border-right-style: solid;
    border-left-style: solid;
    border-width: 1px;
    border-radius: 1;
    border-color: white;
]]

UI.style.header_label_css = [[
    background-color: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 #2a2a3a,
        stop:0.4 #1e1e2a,
        stop:1 #16161e);
    color: #c8c8d0;
    border: none;
    border-right: 1px solid #3a3a4a;
    padding: 4px 8px;
    font-family: "Consolas", "Monaco", monospace;
]]

-- Modern button styling
UI.style.button_css = [[
    QLabel{
        background-color: rgba(40, 40, 45, 200);
        border-style: solid;
        border-width: 1px;
        border-radius: 3px;
        border-color: rgba(100, 100, 110, 180);
        color: rgba(200, 200, 210, 255);
        font-size: 11px;
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover{
        background-color: rgba(60, 60, 70, 220);
        border-color: rgba(120, 180, 255, 200);
        color: white;
        qproperty-alignment: AlignCenter;
    }
]]

UI.style.disabled_button_css = [[
    QLabel{
        background-color: rgba(25, 25, 28, 150);
        border-style: solid;
        border-width: 1px;
        border-radius: 3px;
        border-color: rgba(60, 60, 65, 120);
        color: rgba(255,255,255,0.65);
        font-size: 11px;
        font-weight: bold;
    }
]]

UI.style.toggle_button_css = [[
    QLabel{
        background-color: rgba(50, 50, 55, 220);
        border-style: solid;
        border-width: 1px;
        border-radius: 3px;
        border-color: rgba(120, 120, 130, 200);
        color: rgba(220, 220, 230, 255);
        font-size: 10px;
        font-weight: bold;
    }
    QLabel::hover{
        background-color: rgba(70, 130, 180, 240);
        border-color: rgba(150, 200, 255, 230);
        color: white;
    }
]]

-- Gap filler (standalone mode only) — left border only, same as cargo gap filler
UI.style.local_players_gap_filler_css = [[
    background-color: rgba(0,0,0,255);
    border-left: 2px solid rgba(255,255,255,0.46);
    border-right: none;
    border-top: none;
    border-bottom: none;
    padding: 1px;
    margin: 0px;
    box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.10),
    0 10px 30px rgba(0,0,0,0.6),
    0 0 18px rgba(255,255,255,0.02);
    transition: transform 120ms ease, box-shadow 160ms ease, border-color 120ms ease, background 120ms ease;
    color: rgba(255,255,255,0.95);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

-- Standalone (no cargo visible): gap filler sits above, so no top border; needs right border
UI.style.local_players_dropdown_standalone_css = [[
    background-color: rgba(0,0,0,255);
    border-left: 2px solid rgba(255,255,255,0.46);
    border-right: 2px solid rgba(255,255,255,0.46);
    border-bottom: 2px solid rgba(255,255,255,0.46);
    border-top: none;
    padding: 1px;
    margin: 0px;
    box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.10),
    0 10px 30px rgba(0,0,0,0.6),
    0 0 18px rgba(255,255,255,0.02);
    transition: transform 120ms ease, box-shadow 160ms ease, border-color 120ms ease, background 120ms ease;
    color: rgba(255,255,255,0.95);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

-- With-cargo (cargo visible): starts at top_left_height so needs top border; no right border (cargo is adjacent)
UI.style.local_players_dropdown_with_cargo_css = [[
    background-color: rgba(0,0,0,255);
    border-left: 2px solid rgba(255,255,255,0.46);
    border-right: none;
    border-bottom: 2px solid rgba(255,255,255,0.46);
    border-top: 2px solid rgba(255,255,255,0.46);
    padding: 1px;
    margin: 0px;
    box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.10),
    0 10px 30px rgba(0,0,0,0.6),
    0 0 18px rgba(255,255,255,0.02);
    transition: transform 120ms ease, box-shadow 160ms ease, border-color 120ms ease, background 120ms ease;
    color: rgba(255,255,255,0.95);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

UI.style.cargo_gap_filler_css = [[
    background-color: rgba(0,0,0,255);
    border-left: 2px solid rgba(255,255,255,0.46);
    border-right: none;
    border-top: none;
    border-bottom: none;
    padding: 1px;
    margin: 0px;
    box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.10),
    0 10px 30px rgba(0,0,0,0.6),
    0 0 18px rgba(255,255,255,0.02);
    transition: transform 120ms ease, box-shadow 160ms ease, border-color 120ms ease, background 120ms ease;
    color: rgba(255,255,255,0.95);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]

-- Notification inactive tab - warm red border + tinted background signals unread content
UI.style.notify_inactive_tab_css = UI.style.notify_inactive_tab_css or [[
    QLabel::hover{
        background-color: rgba(60, 35, 35, 210);
        color: rgba(255, 255, 255, 0.95);
        border-top-left-radius: 0px;
        border-top-right-radius: 0px;
        border-width: 2px;
        border-style: solid;
        border-color: rgba(230, 80, 60, 0.95);
        margin-right: 1px;
        margin-left: 1px;
        qproperty-alignment: 'AlignVCenter';
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 2px 6px rgba(0, 0, 0, 0.3);
        transition: all 120ms ease;
    }
    QLabel::!hover{
        background-color: rgba(50, 25, 25, 190);
        color: rgba(255, 210, 200, 0.9);
        border-top-left-radius: 10px;
        border-top-right-radius: 10px;
        border-width: 2px;
        border-style: solid;
        border-color: rgba(210, 65, 50, 0.8);
        margin-right: 1px;
        margin-left: 1px;
        qproperty-alignment: 'AlignVCenter';
    }
]]

UI.style.cargo_dropdown_css = [[
    background-color: rgba(0,0,0,255);
    border-left: 2px solid rgba(255,255,255,0.46);
    border-right: 2px solid rgba(255,255,255,0.46);
    border-bottom: 2px solid rgba(255,255,255,0.46);
    border-top: none;
    padding: 1px;
    margin: 0px;
    box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.10),
    0 10px 30px rgba(0,0,0,0.6),
    0 0 18px rgba(255,255,255,0.02);
    transition: transform 120ms ease, box-shadow 160ms ease, border-color 120ms ease, background 120ms ease;
    color: rgba(255,255,255,0.95);
    -webkit-backdrop-filter: blur(4px) saturate(110%);
    backdrop-filter: blur(4px) saturate(110%);
]]