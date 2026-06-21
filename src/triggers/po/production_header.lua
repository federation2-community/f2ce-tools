-- po_production_header — patterns declared in triggers.json
if f2t_po.phase == "capturing_production" then
    deleteLine()
    f2t_po_capture_reset_timer()
    f2t_debug_log("[po] Production header detected")
end