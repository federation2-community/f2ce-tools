-- A `board` special exit is generated from GMCP room data whenever a planet
-- room links to orbit (see exit.lua), but that link only works for
-- commanders who own a ship. No route recompute will ever get around that,
-- so fail the movement immediately instead of burning through the retry
-- budget on a doomed path.
--
-- The game wraps this message onto a second line (after "commercial"), so
-- the fail message is deferred slightly to print after it instead of
-- interleaving in front of it (mirrors jump_sol_credits_required.lua).
if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
    tempTimer(0.2, function()
        f2t_map_speedwalk_fail("You don't have a ship, can't leave the planet this way")
    end)
end
