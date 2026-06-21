-- hauling_akaturi_payment — patterns declared in triggers.json
-- Capture payment amount from delivery confirmation

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_delivering" then
    deleteLine()

    local payment_str = matches[2]:gsub(",", "")
    local payment = tonumber(payment_str)

    if payment then
        F2T_HAULING_STATE.akaturi_payment_amount = payment
        f2t_debug_log("[hauling/akaturi] Payment captured: %dig", payment)
    end
end