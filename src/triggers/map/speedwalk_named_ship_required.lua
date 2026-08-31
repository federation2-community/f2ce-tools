-- A planet can be set to accept named ships only (FedMap::AllowsPlayerToLand),
-- which refuses the shuttle at the landing controller. It is a per-player
-- restriction the topology model cannot see and no route recompute can get
-- around, so fail the movement immediately rather than burning the retry
-- budget, and say what actually fixes it.
-- An exploration refuel detour just gives up on this planet and carries on;
-- there is nothing wrong with the sweep, only with landing here.
if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.refuel_state then
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
        killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
        F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
    end
    F2T_SPEEDWALK_ACTIVE = false
    f2t_map_explore_refuel_abandon("this planet accepts named ships only")
    return
end

if F2T_SPEEDWALK_ACTIVE and F2T_SPEEDWALK_WAITING_FOR_MOVE then
    tempTimer(0.2, function()
        f2t_map_speedwalk_fail("This planet only accepts named ships - use 'dub' to name yours")
    end)
end
