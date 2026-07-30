-- hauling_work_line — patterns declared in triggers.json
--
-- One job line from the `work` listing:
--   "  12. From The Lattice to Earth - 75 tons of alloys - 4gtu 13ig"
-- Always feeds the Hauling Jobs panel (manual `work` keeps it in sync too),
-- under the same gagging rule as the header.
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then return end
if f2tHaulingJobsAwaitingCommand and f2tHaulingJobsAwaitingCommand() then
    deleteLine()
end
if f2tHaulingJobsLine then
    f2tHaulingJobsLine(matches[2], matches[3], matches[4], matches[5], matches[6])
end
