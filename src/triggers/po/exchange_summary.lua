-- po_exchange_summary — patterns declared in triggers.json
if f2t_po.phase == "capturing_exchange" then
    deleteLine()
    f2t_debug_log("[po] Exchange summary line detected")
    f2t_po_capture_exchange_complete()
end