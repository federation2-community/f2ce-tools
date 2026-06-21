-- po_capture_line — patterns declared in triggers.json
-- Exchange commodity data lines:
--   Line 1: "  Alloys: value 137ig/ton  Spread: ..."  (anchored to start, requires ig/ton)
--   Line 2: "105%  Net: 44"  (starts with efficiency percentage)
-- Production data lines:
--   "  Alloys: production 45, consumption ..."  (anchored to start, requires trailing comma)

if f2t_po.phase == "capturing_exchange" then
    deleteLine()
    table.insert(f2t_po.capture_buffer, line)
    f2t_po_capture_reset_timer()
elseif f2t_po.phase == "capturing_production" then
    deleteLine()
    table.insert(f2t_po.capture_buffer, line)
    f2t_po_capture_reset_timer()
end