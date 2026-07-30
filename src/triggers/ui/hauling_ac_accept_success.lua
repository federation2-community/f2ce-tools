-- hauling_ac_accept_success — patterns declared in triggers.json
--
-- Confirms `ac <n>` actually succeeded:
--   "Your bid is accepted for 75 tons of Katydidics from Earth with delivery to The Lattice."
-- Never gags the line -- console output always prints as normal, whether
-- typed manually or sent by the panel's Job-number click. The Hauling Jobs
-- panel is kept in sync either way; see f2tHaulingJobsOnAcceptSuccess().
if f2tHaulingJobsOnAcceptSuccess then
    f2tHaulingJobsOnAcceptSuccess(matches[4], matches[5])
end
