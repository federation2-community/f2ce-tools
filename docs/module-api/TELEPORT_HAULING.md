# Empty seller-leg teleport (native-ew47)

`API.hauling.start(context, {mode="exchange", teleport_to_seller=true})` is
opt-in and requires `hauling.teleport_seller`. The option must be a boolean;
other modes are rejected before command authority is acquired. Omitted/false
keeps ordinary hauling unchanged. The native hauling owner runs the worker
inside its existing command authority; consumers must not send a separate `tp`.

`f2t_map_teleport_exchange_target(location)` is a read-only map helper. It checks
the exchange flag, unlocked room, actual `getRoomHashByID`, and matching system,
area and server room metadata. It never constructs an address from a Mudlet ID.
Spaces in addresses such as `Sol.The Lattice.1637` are retained. Missing or
mismatched mapping uses the normal seller navigation/discovery chain.

## Command and event sequence

1. On an eligible seller leg, capture `inv` from its anchored personal-kit
   header through the complete closing sentence. Accept an Mk1 teleporter
   control with a positive rental-day count. Wrapped lines and ANSI colors
   are supported; an incomplete or unrelated response never grants ownership.
2. Cache only for the current character/run/connection, for at most one hour
   and no longer than the conservative expiry bound. New runs and reconnects
   invalidate the cache. No rentals, renewals or currency spending are issued.
3. Request `status` and wait for a full `gmcp.char.ship`. Require an explicitly
   empty cargo table and positive finite hold maximum equal to free capacity.
   Recheck location, target mapping, customs policy and protection priority.
4. Send `tp <hash>` once. Ignore legacy speedwalk completion while pending.
   Confirm system, area, server room and exchange flag. Then one `look` fences
   a fresh full local commodity update before the existing bulk-buy phase.
5. If teleport arrives at the destination planet's shuttlepad instead, finish
   with ordinary local navigation. All loaded buyer legs remain ordinary
   navigation; partial sales cannot authorize another teleport.

Inventory and ship waits are bounded at eight seconds. Teleport arrival waits
at most 15 seconds, then pauses without retrying. A confirmed arrival with no
fresh market update pauses after eight seconds. Known ordinary refusals permit
normal navigation, cargo/exile refusals pause, and closed systems skip the
supplier. Unknown output is not interpreted as a safe refusal. Stop/immediate
pause/disconnect/reload cancel pending callbacks. An unanswered or interrupted
teleport latches uncertainty, blocks Resume and automatic safe-room travel,
and requires location inspection followed by explicit stop/start.

## Compatibility and acceptance

The [game guide](https://federation2.com/guide/#sec-60.70) documents interplanetary
teleports to landing pads. The requested full room-hash command is supported by
this client only when the server accepts it and confirms the destination. The
older local server parser instead interprets the last two address components
as a planet name; its explicit unknown-planet refusal falls back to navigation.
No guessed alternate command or repeated teleport is issued. Live full-hash
behavior is not established by the offline tests.

Offline regressions cover inventory framing, rental expiry, mapping identity,
locks, full versus stale ship data, direct/landing-pad/incorrect arrival,
market ordering, refusals, discovery fallback, cancellation and loaded travel.
Before enabling unattended use, stop other automation on one test profile,
enable the option, start Premium Hauler, verify `inv` -> `status` -> one `tp`,
and confirm the correct exchange and bulk order. Test an unmapped seller and
Stop while waiting. Never test exile or dangerous destinations deliberately.

This change does not alter bulk-buy/sell commands, sale policy, buyer retention,
commodity rotation, customs thresholds, factory purchase logic, or default-OFF
behavior. FedHauler exposes the option only for Premium Hauler.
