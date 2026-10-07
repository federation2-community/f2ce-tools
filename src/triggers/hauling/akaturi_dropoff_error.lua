-- hauling_akaturi_dropoff_error — patterns declared in triggers.json
-- Wrong room for the dropoff; a room search hides this and tries the next room

if f2t_akaturi_visit_refused("delivery") then
    deleteLine()
end
