-- hauling_akaturi_pickup_success — patterns declared in triggers.json
-- Detect successful package pickup
-- Don't delete - user wants to see the confirmation

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_collecting" then
    F2T_HAULING_STATE.akaturi_package_collected = true
    f2t_debug_log("[hauling/akaturi] Package picked up successfully")

    -- Start capturing the delivery info that follows
    f2t_akaturi_start_pickup_capture()
    f2t_akaturi_add_pickup_line(line)

    -- Start timer - will fire 0.5s after last line
    f2t_akaturi_reset_pickup_timer()
end