-- hauling_ac_deliver_capture_payment — patterns declared in triggers.json
-- Capture payment amount from any line during delivery
-- May be on same line as "your fee of" or wrapped to next line

-- Only process if hauling is active and in delivering phase
if not (F2T_HAULING_STATE and F2T_HAULING_STATE.active and
        F2T_HAULING_STATE.current_phase == "ac_delivering") then
    return
end

-- Don't capture multiple times
if F2T_HAULING_STATE.ac_payment_amount then
    return
end

-- Extract and store payment amount
local payment_str = matches[2]:gsub(",", "")
local payment = tonumber(payment_str)

if not payment then
    f2t_debug_log("[hauling/ac] Could not parse payment amount: %s", matches[2])
    return
end

-- Store amount temporarily (will be confirmed by "transferred" trigger)
F2T_HAULING_STATE.ac_payment_amount = payment

f2t_debug_log("[hauling/ac] Captured payment amount: %dig (waiting for confirmation)", payment)