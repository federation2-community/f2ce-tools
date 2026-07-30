-- hauling_ac_no_service — patterns declared in triggers.json
--
-- `ac <n>` rejected because the player's rank is too low to use Armstrong
-- Cuthbert's services at all:
--   "Armstrong Cuthbert Inc has no haulage work for you at the moment."
-- Never gags the line -- console output always prints as normal. Clears any
-- pending panel accept so a click doesn't stay "pending" forever; has no
-- effect on the panel if nothing was pending (e.g. typed manually).
if f2tHaulingJobsOnAcceptFailed then
    f2tHaulingJobsOnAcceptFailed()
end
