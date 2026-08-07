-- Sol is the only system in the game that gates its outbound links behind a
-- hauler credits threshold for new commanders, and it applies to every exit,
-- not just the one being tried. Unlike a stale-topology refusal, no route
-- recompute will ever get around this until the credits are earned, so fail
-- the movement immediately instead of burning through the retry budget.
--
-- The pattern matches a substring on just the first line of the message
-- rather than the full sentence: the game wraps this message onto a second
-- line (after "at least 50"), so an anchored full-line pattern never matches.
if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
    f2t_map_speedwalk_fail("Sol requires at least 50 hauler credits before you can leave")
end
