-- hauling_work_start — patterns declared in triggers.json
--
-- Header of the `work` job listing.  Feeds the Hauling Jobs panel and gags the
-- raw listing — but only when the Work button sent this command, and never
-- while the hauling automation is running (its own capture owns the output
-- then). A manually typed `work` is never gagged.
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then return end
if f2tHaulingJobsAwaitingCommand and f2tHaulingJobsAwaitingCommand() then
    deleteLine()
    f2tHaulingJobsHeader()
end
