-- po_error_invalid_planet — patterns declared in triggers.json
if f2t_po.phase ~= "idle" then
    f2t_debug_log("[po] Invalid planet error during phase: %s", f2t_po.phase)
    deleteLine()
    f2t_po_capture_abort("Planet name not recognized")
end