-- po_error_not_owner — patterns declared in triggers.json
if f2t_po.phase ~= "idle" then
    f2t_debug_log("[po] Not owner error detected during phase: %s", f2t_po.phase)
    deleteLine()
    f2t_po_capture_abort("You don't own the exchange on this planet!")
end