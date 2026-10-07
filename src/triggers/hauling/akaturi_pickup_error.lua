-- hauling_akaturi_pickup_error — patterns declared in triggers.json
-- Wrong room for the pickup; a room search hides this and tries the next room

if f2t_akaturi_visit_refused("pickup") then
    deleteLine()
end
