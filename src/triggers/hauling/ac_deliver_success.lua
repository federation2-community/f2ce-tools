-- hauling_ac_deliver_success — patterns declared in triggers.json
-- Confirm cargo delivery - payment amount already captured by fee_start trigger
-- This trigger confirms the transaction completed successfully

-- Only process if hauling is active and in delivering phase
if not (F2T_HAULING_STATE and F2T_HAULING_STATE.active and
        F2T_HAULING_STATE.current_phase == "ac_delivering") then
    return
end

-- Check if we already captured a payment amount
local payment = F2T_HAULING_STATE.ac_payment_amount

if not payment then
    f2t_debug_log("[hauling/ac] Transfer confirmed but no payment amount captured")
    return
end

f2t_debug_log("[hauling/ac] Cargo delivered, payment confirmed: %dig", payment)

F2T_HAULING_STATE.ac_cargo_delivered = true

-- Schedule phase processing after brief delay to let trigger exit
-- This prevents race conditions with output capture
tempTimer(0.1, function()
    if F2T_HAULING_STATE and F2T_HAULING_STATE.active and
       F2T_HAULING_STATE.current_phase == "ac_delivering" then
        f2t_hauling_phase_ac_deliver()
    end
end)