# Premium Hauler navigation recovery (native-ew51)

This is a native hauling change, usable by existing FedHauler 1.17.43. No
separate API, Exchange Walker, or FedHauler update is needed. It applies to an
active exchange haul using `rotation="top_base_21"`, the Premium Hauler route.
Ordinary hauling, PO, factory construction and futures do not gain automatic
restart behavior. The public API version and start options are unchanged.

## Recovery sequence

1. Recover only when seller/buyer navigation reports failure: either the initial
   navigation/discovery request fails, or a started speedwalk later fails. A
   native terminal-state event covers timeout failures without a room GMCP push.
2. Let navigation settle, bounded to ten seconds. Active protection, bulk trades,
   purchase settlement or uncertain teleport results prevent recovery. Do not
   cancel another operation to take its command authority.
3. Send `status` once and allow eight seconds for a full `gmcp.char.ship` event.
   Cached ship data is not sufficient. Require the same character and location,
   a consistent free hold, cargo identity/origin/cost, and the active run's
   confirmed purchase/sale lot counts. Unknown or unrelated cargo is not adopted.
4. With confirmed cargo aboard, issue a fresh commodity price check and choose
   the best eligible positive off-world bid from that response. Revalidate the
   cargo, character, location and protection state when the response arrives.
   Exclude the failed destination, bonded origins and existing customs/system
   exclusions. Do not reintroduce a profit floor for clearing loaded cargo.
5. With a confirmed empty hold on a seller leg, use the existing next-supplier
   flow: retained alternatives first, then its bounded refresh if exhausted.
   An empty buyer leg is accepted only if the confirmed sale ledger also shows
   no remaining cargo; finish that commodity instead of buying it again.
6. Resume the normal route and existing trade confirmation logic. Repeated
   navigation failures repeat the fresh cargo/buyer checks, while remembering
   failed destinations for this commodity. No eligible buyer or invalid price
   response ends the run with cargo preserved, not a repeated visit or dump.

Each recovery requests only its cargo commodity's prices, not the entire
rotation. Buying and selling commands, receipt/GMCP reconciliation, retained
market selection, the 21-commodity rotation and persisted progress are unchanged.

## Cancellation and boundaries

- Manual Pause/Stop/Terminate invalidates pending recovery. Stop during recovery
  ends that operation rather than waiting for the failed route to finish.
- Disconnect pauses recovery; late ship or price responses cannot resume it.
  The existing consumer's reconnect policy still requires an explicit start.
- Missing fresh ship data, inconsistent cargo/ledger, changed identity/location
  or protection activity pauses without a new route or trade. Explicit Resume
  repeats the fresh cargo check, never the old failed speedwalk.
- Navigation callbacks and delayed arrival timers are scoped to their route
  attempt. An old callback cannot advance or interrupt its replacement. Pending
  map discovery does not inherit the previous speedwalk's terminal failure.
- This is recovery inside the active haul, not restart after an application
  crash, package replacement, uncertain transaction or previously stopped run.

## Verification

`tests/hauling/navigation_recovery_run.lua` exercises real exchange phases,
recovery/lifecycle code and a real speedwalk terminal event with synthetic
transport. Coverage includes loaded/empty holds, failed-target exclusion, fresh
prices below purchase cost, customs/origins, no buyer, inconsistent evidence,
timeouts, repeated failures, disconnect during a price request, protection,
explicit resume and stale timers/callbacks. The same tests run against the
packaged XML code through `scripts/test-native.ps1`.

No live accounts are started or packages installed by these tests. Install the
candidate with automation stopped. Live acceptance should confirm a naturally
occurring route failure produces one `status`, then a fresh price check for
loaded cargo and a different buyer, with no duplicate purchase/sale command.
