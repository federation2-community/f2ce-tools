-- hauling_ac_already_has_contract — patterns declared in triggers.json
--
-- `ac <n>` fails because a contract is already outstanding:
--   "You already have an uncompleted contract!"
-- Never gags the line -- console output always prints as normal. Clears any
-- pending panel accept so a stray click doesn't stay "pending" forever; has
-- no effect on the panel if nothing was pending (e.g. typed manually).
if f2tHaulingJobsOnAcceptFailed then
    f2tHaulingJobsOnAcceptFailed()
end
