-- "You jump up and down, but nothing happens." The jump command only works
-- from the room holding the interstellar link (CmdParser::Jump gates on
-- IsALink()). Nothing is wrong with the destination - we are simply in the
-- wrong room - and a blind jump chain has no route to replan, so the only
-- honest outcome is to stop and say which of the two it was.
if F2T_SPEEDWALK_MOVE_TIMEOUT_ID then
    killTimer(F2T_SPEEDWALK_MOVE_TIMEOUT_ID)
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = nil
end
F2T_SPEEDWALK_WAITING_FOR_MOVE = false

if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active
    and F2T_MAP_EXPLORE_STATE.travel_target then
    F2T_SPEEDWALK_ACTIVE = false
    cecho(string.format(
        "\n<red>[map-explore]<reset> Cannot jump to %s: this room is not an interstellar link\n",
        tostring(F2T_MAP_EXPLORE_STATE.travel_target)))
    f2t_map_explore_travel_finish(false)
    return
end

if F2T_SPEEDWALK_ACTIVE then
    f2t_map_speedwalk_fail("Not at an interstellar link - 'jump' only works from the link room")
end
