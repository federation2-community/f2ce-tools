-- hauling_akaturi_pickup_line — patterns declared in triggers.json
-- Capture delivery information from pickup confirmation
-- Don't delete - user wants to see the delivery details

if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.current_phase == "akaturi_collecting" then
    if f2t_akaturi_is_capturing_pickup() then
        -- Capture for parsing (but don't hide from user)
        f2t_akaturi_add_pickup_line(line)

        -- Reset timer - extends deadline by 0.5s
        f2t_akaturi_reset_pickup_timer()
    end
end