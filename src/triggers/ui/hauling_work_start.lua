-- hauling_work_start — patterns declared in triggers.json
--
-- Header of the `work` job listing. Always feeds the Hauling Jobs panel, so
-- a manually typed `work` keeps the panel in sync too -- but only gags the
-- raw listing when the Work button itself sent this command, and never
-- while the hauling automation is running (its own capture owns the output
-- then).
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then return end
if f2tHaulingJobsAwaitingCommand and f2tHaulingJobsAwaitingCommand() then
    deleteLine()
end
if f2tHaulingJobsHeader then f2tHaulingJobsHeader() end
