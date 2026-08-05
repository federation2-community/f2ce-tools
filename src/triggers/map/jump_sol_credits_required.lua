-- Sol is the only system in the game that gates its outbound links behind a
-- hauler credits threshold for new commanders, and it applies to every exit,
-- not just the one being tried. Unlike a stale-topology refusal, no route
-- recompute will ever get around this until the credits are earned, so fail
-- the movement immediately instead of burning through the retry budget.
if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
    local required = tonumber(matches[2]) or 50
    f2t_map_speedwalk_fail(string.format(
        "Sol requires at least %d hauler credits before you can leave", required))
end
