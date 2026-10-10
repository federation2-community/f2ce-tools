-- Sol is the only system in the game that gates its outbound links behind a
-- hauler credits threshold for new commanders, and it applies to every exit,
-- not just the one being tried. Unlike a stale-topology refusal, no route
-- recompute will ever get around this until the credits are earned - so
-- record it against the system rather than the destination, and every later
-- attempt to leave can say so up front instead of walking back to the link
-- to be told again.
--
-- The pattern matches a substring on just the first line of the message
-- rather than the full sentence: the game wraps this message onto a second
-- line (after "at least 50"), so an anchored full-line pattern never matches.
-- The fail message is deferred slightly so the game's own second line prints
-- first, instead of interleaving in front of it.
local reason = "Sol requires at least 50 hauler credits before you can leave"

if f2t_map_mark_link_barred then
    f2t_map_mark_link_barred(f2t_get_current_system(), reason)
end

if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
    tempTimer(0.2, function() f2t_map_speedwalk_fail(reason) end)
end
