# Two-hop empty seller-leg teleport (native-ew49)

`API.hauling.start(context, {mode="exchange", teleport_to_seller=true})` is
opt-in and requires `hauling.teleport_seller`. The option must be a boolean;
other modes are rejected before command authority is acquired. Omitted/false
keeps ordinary hauling unchanged. The native hauling owner runs the worker
inside its existing command authority; consumers must not send a separate `tp`.

`f2t_map_teleport_exchange_target(location)` is a read-only map helper. It checks
the exchange flag, unlocked room, actual `getRoomHashByID`, and matching system,
area and server room metadata. It never constructs an address from a Mudlet ID.
The hash `Sol.The Lattice.1637` yields planetary address `Sol.The Lattice` and
local server room number `1637`. Spaces are retained. Missing or
mismatched mapping uses the normal seller navigation/discovery chain.

## Command and event sequence

1. On an eligible seller leg, capture `inv` from its anchored personal-kit
   header through the complete closing sentence. Accept an Mk1 teleporter
   control with a positive rental-day count. Wrapped lines and ANSI colors
   are supported; an incomplete or unrelated response never grants ownership.
2. Cache only for the current character/run/connection, for at most one hour
   and no longer than the conservative expiry bound. New runs and reconnects
   invalidate the cache. No rentals, renewals or currency spending are issued.
3. Before each hop, request `status` and wait for a full `gmcp.char.ship`. Require an explicitly
   empty cargo table and positive finite hold maximum equal to free capacity.
   Recheck location, target mapping, customs policy and protection priority.
4. Send `tp <system>.<planet>` once, such as `tp Essos.Valyria`. Wait for GMCP
   confirming that system/planet and its shuttle-pad flag. No local teleport or
   purchase is sent before that confirmation. If already on the seller planet,
   omit this interplanetary hop.
5. Refresh and verify the empty hold again, recheck the local origin and mapped
   target, then send `tp <server room number>` once, such as `tp 845`. This is
   never the Mudlet room ID or a full room hash. Confirm the exact seller's
   system, area, server room and exchange flag. Send one final `status` and
   require a full `gmcp.char.ship` confirming the empty hold at that exact
   exchange. Recheck the mapping, customs exclusion and protection priority,
   then enter the existing bulk-buy phase exactly once. No `look`, commodity
   snapshot, price poll or additional teleport is required for this handoff.
6. Confirmed ordinary refusals at either hop use normal navigation from the
   current location. A local refusal walks from the shuttle pad to the exchange.
   No guessed alternate teleport or automatic retry is issued. All loaded buyer legs remain ordinary
   navigation; partial sales cannot authorize another teleport.

Inventory and ship waits are bounded at eight seconds. Each teleport arrival waits
at most 15 seconds, then pauses without retrying. A confirmed exchange arrival with no
fresh ship update pauses after eight seconds. Known ordinary refusals permit
normal navigation, cargo/exile refusals pause, and closed systems skip the
supplier. Unknown output is not interpreted as a safe refusal. Stop/immediate
pause/disconnect/reload cancel pending callbacks. An unanswered or interrupted
teleport latches uncertainty, blocks Resume and automatic safe-room travel,
and requires location inspection followed by explicit stop/start.

## Compatibility and acceptance

The [game guide](https://federation2.com/guide/#sec-60.70) and the user's confirmed
syntax distinguish interplanetary landing-pad addresses from local numeric
addresses. ew48 replaced ew47's incorrect direct full-hash command. ew49 fixes
ew48's post-arrival commodity wait: in the inspected server source,
`Player::TeleportLocal` and `FedMap::Look` update room data without invoking
`SendGMCPExchangeSnapshot`. The old offline success fixture supplied a commodity
event that need not occur live; the regression now intentionally supplies none.
`status` supplies the full ship data used by the existing bulk buyer.
The public hauling option/capability are unchanged; existing FedHauler 1.17.40
can use ew49 without a consumer package update. This correction is offline-tested,
not live-installed or live-exercised by the agent.

Offline regressions cover inventory framing, rental expiry, mapping identity,
locks, full versus stale ship data before both hops and after final arrival,
landing-pad/local/wrong arrival, absent commodity events, duplicates, changed
cargo/location/mapping/protection, refusals, discovery fallback, cancellation
and loaded travel.
Before enabling unattended use, stop other automation on one test profile,
enable the option, start Premium Hauler, verify `inv` -> `status` ->
`tp System.Planet` -> confirmed shuttle pad -> `status` -> `tp number` ->
confirmed exchange -> `status` -> confirmed empty hold -> bulk buy.
Test an unmapped seller and
Stop while waiting. Never test exile or dangerous destinations deliberately.

This change does not alter bulk-buy/sell commands, sale policy, buyer retention,
commodity rotation, customs thresholds, factory purchase logic, or default-OFF
behavior. FedHauler exposes the option only for Premium Hauler.
