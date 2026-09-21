# `F2CE.API.v1` reference

All data returned across the API boundary is copied. Errors are tables with `code`, `message`, optional copied `details`, and a useful `tostring(error)` value. Functions return `nil, error` when they fail closed.

## Metadata and dependency validation

- `API.version`: semantic API version (`1.2.0`; candidate build).
- `API.f2ce_version`: installed F2CE package version.
- `API.info()`: copied API/F2CE/adapter/capability/integration record.
- `API.hasCapability(name)`, `API.getCapabilities()`, `API.requireCapabilities(names)`.
- `API.validateDependency({api=">=1.0.0", f2ce=">=3.3.0", capabilities={...}})`.
- `API.versions.compare(a,b)` and `API.versions.satisfies(actual, requirement)`; operators are `=`, `>`, `>=`, `<`, `<=`, and `~` (same major/minor, at least the requested patch).

Capabilities include `modules`, `events`, `navigation`, `navigation.status.v33`, `commands`, `commands.native_contention`, `gmcp.snapshots`, `prices.providers`, `hauling`, `hauling.exchange_override`, `hauling.rotation_top_base21`, `hauling.customs_max5`, `map.queries`, and `muxlet.content` when `Mux.registerContent` is available. `hauling.customs_max5` identifies the persistent premium-hauling cartel scan, its greater-than-5% system exclusion, bonded-origin protection and positive-bid cargo disposal policy. The dotted 3.3 capabilities let modules distinguish these native contracts from legacy fallback behavior.

`API.integration` identifies this API's scope as F2CE gameplay services and identifies Muxlet as the UI/content provider. Visual integrations should call `Mux.registerContent` directly; this API does not wrap Muxlet.

## Modules and scoped context

### Native consumer services added in 1.2

- `data.receipt(channel)` returns a copied generation, global sequence, receipt
  time, data, frozen room and mapped `room_id`. Only genuine GMCP events advance
  this journal. `data.refresh(channel)` updates cache without creating freshness.
  Normalized data events include `received` and an optional `receipt`.
- `data.mapRoomId(room)` resolves the server's `system.area.num` hash. Server
  local numbers are not mapper IDs; unresolved hashes return nil.
- `navigation.environment()` is copied native state. `navigation.verify(ctx,
  destination, options)` provides bounded semantic re-resolution/retries and
  authoritative arrival checks. Options include `on_arrival`, `on_failure`,
  `on_retry`, `require_exchange`, timeout (15–600 seconds), max_attempts (1–4),
  max_room_visits (2–5). The returned session has `status()`/`cancel(reason)`;
  deliberate cancellation does not call the failure callback. No map edits or
  guessed exits are performed, and foreign navigation is never stopped.
- `actions.command(ctx, operation, payload)` validates authorization and builds
  futures.refresh/buy/liquidate or prices.premium/local commands. `actions.send`
  also acquires/releases the broker. These require the module's explicit
  `authorize(operation,payload)` callback. A send receipt is not game acceptance.
- `discovery.system(ctx,name,callback)` returns a cancellable leased operation.
  Callback receives planets, excluded, missing, failure. `trading.bulk(ctx,
  {side,commodity,lots},callback)` accepts buy/sell and 1–100 lots; callback carries
  the native confirmed count/status. Neither assumes transport means success.
- `settings.get(component,key)` and `character.hasRank(rank)` are read-only.
- `prices.analyze(commodity,lines,count)` returns parsed/analysis copies with a
  validated 1–50 result count (native ew36+); `prices.maxResults` advertises 50.
  Older APIs without the hint retain their 20-result limit. Full parsed arrays
  remain untruncated; `prices.display` invokes native presentation.
  The stock checker has an explicit native provider hook for API-owned hauling;
  only that owner's provider may borrow its hauling broker lease. It does not
  replace the global checker. Foreign activity and captures remain blockers.
- `protection.attach(ctx,{pause,resume,isActive,onHandoffFailure})` registers an
  owner-scoped stamina client with `isOwned`, `status`, `ensure`, and `detach`.
  Call `ensure()` after saving the returned handle: it can synchronously invoke
  pause at low stamina. Pause must release unsent navigation. Already-sent steps
  require fresh matching room receipts within 10 seconds before food travel.
  Incomplete command operations, unknown movement, foreign owners, death and
  timeout fail closed. `deathState`, `isRecovering`, `staminaState` and `status`
  expose copied protection data; events include death.started/completed and
  stamina.handoff_ready/failed. No literal `yes` or alternate navigator is used.
  `detach()` cancels that exact client's active food trip as well as unregistering
  it. Queued food purchases, return callbacks and pause polls are invalidated;
  only stamina-owned navigation is stopped, never another owner's route. A
  command already sent cannot be recalled. A new trip requires fresh activation.

Capabilities added: `gmcp.receipts`, `commands.typed`, `po.discovery`,
`trading.bulk`, `prices.analysis`, `prices.hauling_provider`, `settings.read`,
`protection.stamina`, `protection.death`. Read `api.ready` through the API or
Mudlet's `f2ceApiReady` notification when the package finishes installing its
adapter. Readiness grants no gameplay authority.

### Registry

- `API.modules.register(spec)` where `spec.id` is a lowercase dotted ID and `spec` may define `version`, `requires`, `initialize(context)`, `enable(context)`, `disable(context,reason)`, and `unload(context,reason)`.
- `initialize(id)`, `enable(id)`, `disable(id,reason)`, `unload(id,reason)`, `unregister(id,reason)`, `reload(spec)`, and `status(id)`.
- `context:on(api_event,callback)` subscribes to F2CE API service events.
- `context:own(kind,resource,cleanup)` attaches an explicit cleanup token for a resource created through Mudlet, Muxlet, or another library.

Callbacks registered through a context are gated on the current enabled generation. Cleanup is reverse-order and idempotent.

The context does not create aliases, triggers, timers, HTTP requests, widgets, or general Mudlet event handlers. Those remain with their native owner. For example, a package can create an alias with `tempAlias` and attach its ID using `context:own("mudlet_alias", id, killAlias)`.

## Navigation

`lease, err = API.navigation.acquire(context, metadata)` acquires the sole API lease only if no native navigation owner or known native automation is active. `lease:request(destination, options)` returns a handle. Options: `suppress_hint`, `interactive`, `compensate_incomplete_map`, `on_complete(result)`, `on_failure(result)`, and `on_interrupt(result)`. The first three map directly to F2CE-Tools 3.3.0 navigation options. Returning `{auto_resume=true}` from the interruption callback requests F2CE's supported customs recovery behavior.

Request state is normalized from the 3.3.0 native start status: `walking` becomes `running`, `pending` remains `pending`, `arrived` completes immediately, and `failed` is rejected. A pending self-healing route is not completed by an intermediate speedwalk's `LAST_RESULT`; it remains pending until native resolution advances it or the requested destination resolves to the current room. Releasing a lease clears the native owner only when the API's owner token still matches.

Handle functions: `status()`, `pause()`, `resume()`, `cancel(reason)` (graceful, finalized on the next service tick), and `cancelImmediate(reason)`. `lease:release(reason)` is allowed only when no request is active. `API.navigation.status()` returns `{state="idle"}` or a copied request record.

Events: `navigation.lease_acquired`, `.lease_released`, `.started`, `.paused`, `.resumed`, `.cancelling`, `.interrupted`, `.completed`, and `.failed`. Request fields include `request_id`, `lease_id`, `module_id`, `destination`, `state`, timestamps, `reason`, `interruption_reason`, `detail`, and copied progress.

## Commands

`lease = API.commands.acquire(context, metadata)` obtains the sole command lease. `lease:send(command,{reason="...", echo=false, ...})` transmits only while the owning module remains enabled. `lease:release(reason)` revokes it. Navigation and arbitrary command leases are mutually exclusive. Acquisition fails while known native speedwalk, exploration, circuit, hauling, death-recovery, bulk-trade, or command/response capture state is active; every API send rechecks that state and fails closed with zero transmission if it changed. `API.commands.audit()` returns copied bounded history.

`command.sent` / `command.failed` fields: `id`, `module_id`, `lease_id`, `command`, copied `metadata`, `timestamp`, `status`, and optional `reason`. These report transport only, not game acceptance. `command.acknowledged` remains a deprecated transport alias for backward compatibility.

## Exchange capture and stock settings (1.1)

Capabilities: `exchange.capture`, `exchange.settings`.
`session = API.exchange.acquire(context,{reason="explicit reviewed operation"})`
holds the existing command lease across related operations. A disabled module,
foreign API lease, or known native automation prevents acquisition.

- `session:capture(kind,planet,callback,{timeout=15})`: kind is `exchange` or
  `production`; planet may be nil for local capture. Callback `(rows,error)`
  receives copied native PO results. Remote response headers must identify the
  requested planet. Exchange results include `_expected_count` from the summary.
  The consumer must validate completeness before acting on the data.
- `session:set({kind,commodity,value,planet})`: typed setting command. Accepted
  ranges are integer min 0–10000, max 0–20000, spread 6–40. Local operations
  require current owner/player GMCP equality; remote ownership is enforced by
  the server. A sent result is not a server acknowledgement.
- `session:status()`, `session:release(reason)`: release cancels only the capture
  callback owned by that session. The client must release after a capture pair
  or confirmed apply sequence. Disable/unload/reconnect also clean the session.

`exchange.captured` / `exchange.capture_failed` carry copied `kind`, `planet`,
`module_id`, `rows`, and optional `error`. Invalid kinds, names, numbers,
contention, missing capabilities, disabled contexts and timeouts fail closed.

The native [Exchange Walker integration](NATIVE_EXCHANGE_WALKER.md) demonstrates
complete capture validation and one-at-a-time acknowledged setting changes.
Reconnect now disables every enabled module; consumers must explicitly enable
again, rather than obtaining new leases with old connection authority.

## Copied GMCP data

`API.data.get(channel)`, `refresh(channel)`, and `channels()`. Channels and events:

| Channel | Normalized event | Established source |
|---|---|---|
| `room` | `data.room` | `gmcp.room.info` |
| `vitals` | `data.vitals` | `gmcp.char.vitals` |
| `ship` | `data.ship` | `gmcp.char.ship` |
| `cargo` | `data.cargo` | `gmcp.char.ship.cargo` |
| `jobs_board` | `data.jobs_board` | `gmcp.jobs.board` |
| `job` | `data.job` | `gmcp.char.job` |
| `commodities` | `data.commodities` | `gmcp.exchange.commodities` |
| `futures_market` | `data.futures_market` | `gmcp.exchange.futures` |
| `futures_owned` | `data.futures_owned` | `gmcp.char.futures` |
| `business` | `data.business` | `gmcp.char.business` (Industrialist) |
| `company` | `data.company` | `gmcp.char.company` (Manufacturer/Financier) |

Each event is `{channel, available, value, timestamp}`. `value` is a deep copy and may be `nil` for absent/partial GMCP.

## Owner-bound company and depot reads

Native ew33 adds `API.company.planet(context, planet, system, callback)` with
authorization operation `company.planet.inspect`. It reads `di planet <planet>`
and a rank-appropriate company report on one command lease. The complete text
and fresh company GMCP are both required; it never infers absence from silence.
The copied result has `system`, `planet`, `captured_at` and a `planets` map keyed
by lowercase planet. Each planet includes workforce/economy plus
`factories_verified=true` and `factories={ {owner,number,output,planet}, ... }`
covering all companies, not only the caller. Missing/truncated, mismatched or
duplicated records fail closed. Cancellation, teardown and identity changes
discard late results. `company.factoryCompetitionVersion == 1` advertises the
corresponding fresh pre-purchase exclusion; see `FACTORY_AUTOMATION.md`.

Native ew27 adds `company.factory.build` / `API.company.prepareFactory` for
separately confirmed single-factory construction. See `docs/COMPANY_API.md` for
bounded options, fresh checks and the mandatory consumer pre-send journal
boundary. This is not a read-only operation or a scheduled company manager.

`API.company.snapshot()` returns the copied business/company and its receipt,
selected by current rank and checked against the current character's CEO name.
No cross-rank cache fallback is used. `refresh(context, callback)` sends
`di business` or `di company` and waits for a real rank-specific GMCP event.
`inspect(context, factoryNumber, callback)` reads a complete owned factory display.

Native ew21 adds capability `company.depot.read` and
`API.company.depot(context, planet, callback)`. The planet must appear in this
owner's snapshot. One broker lease sends `display depot <planet>` followed by
the rank-appropriate company/business read. Its exact owner-bound header closes
the depot display; fresh GMCP is also mandatory. Manufacturer capacity, occupancy
and efficiency must agree with the following report. Industrialist reports have
no occupancy count, so their completeness boundary is the ordered read fence.
Quiet intervals and partial rows are never accepted as complete inventory.

Result fields: `owner`, `ceo`, `planet`, `capacity`, `used_bays`, `free_bays`,
`workforce`, `efficiency`, `bays`, `inventory`, `captured_at`, `completeness`.
Each bay has `number`, `commodity`, `tons=75`, `cost_per_ton`, `origin`, `system`;
inventory maps lower-case commodities to total tons. All three asynchronous
methods return cancel/status handles, require explicit module authorization,
hold ownership through response processing, time out in 15 seconds, and clean
up on disable/reconnect. Callback `(value,error)` runs after lease release.
The read operation is `company.depot.inspect`. Remote inspection proves neither
ship access nor future inventory.

### Explicit single-bay transfers (native ew22)

Capability `company.depot.transfer` exposes
`API.company.prepareTransfer(context, options, callback)`. Options require
`side="store"|"fetch"`, `planet`, `commodity` for store or `bay` for fetch,
and nonnegative `personal_reserve` and `company_reserve`. Returns a handle with
`status()`, `cancel(reason)` and **`confirm(callback)`**. The preparation callback
receives a copied proposal, not an authority token; no write occurs until confirm.

The module must explicitly authorize `company.depot.preview`, its depot inspect,
and `company.depot.store` or `.fetch` at confirmation and immediately before send.
One broker lease spans preview, revalidation and settlement. `score` refreshes
room/ship/cash/stamina with actual GMCP events, then owner-fenced depot inspection
refreshes rank-specific company data. Preview expiry is 30 seconds, state and
depot reads each have a 15-second deadline. Ground location, owner, rank, ship,
unchanged manifests, capacity, stamina and both reserve floors are checked.

Store chooses the first matching ordinary 75-ton ship cargo; fetch chooses the
numbered depot bay. No jobs, batch loop, navigation, food recovery or retries.
Settlement requires matching cargo multiset/space deltas and opposite cash
movements at original cargo cost. On success, completion runs after release;
the proposal callback runs **while the lease remains held**. A failure after
send is `E_DEPOT_UNCONFIRMED`: inspect manually, never automatically resend.
Cancellation cannot reverse a sent command. Server production is not locked;
an unrelated inventory/cash change can prevent reconciliation. No persistent
restart journal or atomic server transaction is claimed.

`cash` and `stamina` data channels mirror `char.vitals.cash` and
`char.vitals.stamina`, with `data.cash` / `data.stamina` events and normal receipts.

### Single-bay cargo market operation (native ew23)

`company.cargo.transfer` exposes `company.prepareCargo(context,options,callback)`
using the same preview/confirm/cancel handle. Options: `side="buy"|"sell"`,
`planet`, `commodity`, both reserve floors and mandatory `price_limit` (maximum
ask for buy, minimum bid for sell). Sends explicit `score`, `look` and rank-specific
`di business` / `di company` reads under the same lease. Requires a fresh exchange-room
response including commodities, ship, cash, stamina and rank-specific company.
Buy requires an empty ordinary ship, at least one free bay, 5,000t saleable local
stock and funds both for personal purchase and the company's later reimbursement.
Sell requires **exactly one matching ordinary bay** before `sell <commodity> 1`. One
counted `buy <commodity> 1` is sent for purchase. Revalidation and exact ship,
hold and personal cash deltas plus unchanged company cash are mandatory.
Authorization operations are `company.cargo.preview`, `.buy`, `.sell`.
Same-origin sales fail with `E_CARGO_ORIGIN`; legacy data cannot prove an
unbonded factory-produced exception. Choose a different buyer planet.

Depot options additionally accept `single_cargo=true` and `expected_depot`
(the exact copied bay list used for factory reservations). A changed bay list
invalidates the operation before sending. Four exact ambient exchange ticker
formats are excluded from depot capture; unknown text still fails strict parsing.
The API does not lock factory production, enforce consumer trip budgets or
replace the consumer's need to protect inputs reserved by other factories.

## Price provider operations

Native ew25 adds capability `prices.provider_builtin`. Within a provider attempt,
`provider_request:useBuiltin(callback)` delegates **one** regular built-in price
query on the existing command reservation. Callback receives copied
`(result,error)`; the provider must finish with `done(transformedResult)` or
`done(nil,error)`. This is for filtering/reanalysis, not a queued second request.
The built-in query retains native rank/tool checks, capture and command audit.
Foreign native activity is rechecked before dispatch. Duplicate delegation,
mixing `send` with delegation, and stale attempts are refused; late/duplicate
callbacks after completion/cancellation/timeout are ignored. A provider callback
exception fails its attempt. It does not grant trading authority or premium
access, change the commodity, or authorize a silent provider fallback.

`API.prices.registerProvider(context,{id,priority,scopes,capabilities,request})` returns a scoped registration token. `request(provider_request,done)` returns `false` to decline or calls `done(result)` / `done(nil,error)`. `provider_request:send(command,metadata)` uses the serialized service command lease and audit trail. It also exposes copied `options`, `commodity`, `id`, and `isCancelled()`.

`API.prices.request(context,commodity,{scope,timeout,...},callback)` returns a cancel/status handle. Providers run by descending priority, then the built-in `f2t_price_check_commodity` provider. Events: `provider.registered`, `.queued`, `.started`, `.timed_out`, `.completed`, `.failed`.

## Hauling

`API.hauling.start(context,{mode="auto"|"exchange"})` delegates to F2CE's rank-aware state machine. `auto` passes no override; `exchange` is the supported Founder+ exchange override. No hauling algorithm is duplicated. The API verifies that native state actually became active; cargo, rank, or other synchronous native rejection releases the service command lease and returns `E_HAUL_START`. The returned handle exposes `status`, `pause`, `resume`, `cancel` (graceful), and `cancelImmediate`. Top-level equivalents and `API.hauling.status()` are also available.

Events: `hauling.started`, `hauling.state`, and `hauling.stopped`. Status copies the established F2CE state fields, including `active`, `paused`, `mode`, `current_phase`, `stopping`, and counters when present.

Native ew41 adds capability `hauling.rotation_top_base21` and the optional
`rotation="top_base_21"` argument to `hauling.start` in exchange mode only.
FedHauler 1.17.30 uses it for its existing Premium Hauler. This session-local
selection rotates the 21 highest `commodities.json` base prices, with
canonical-name tie ordering, and preserves existing per-profile attempt
checkpoints. Native ew42 queues that fixed catalog without a cycle-start price
sweep. It requests one market snapshot when each commodity becomes current, then
a second snapshot after purchase settlement to select a buyer against confirmed
receipt cost. Native ew43 also advertises `hauling.customs_max5`: before the
first premium route of a connection it issues `di cartel <cartelname>` for each
mapped cartel and excludes every hub/member system whose report shows customs
above 5%. The complete policy persists in map userdata. Once cargo is aboard,
the best positive off-origin bid is accepted without a profit floor; guarded
one-bay sale, receipt and cargo reconciliation remain mandatory. Buyer refusal
consumes retained alternatives before one exceptional refresh. Nil keeps the full catalog;
ordinary starts clear the selection. An unsupported/invalid selection is rejected
before acquiring command authority. Manual price-all and other price consumers
are unchanged.

## Map queries

- `API.map.roomHasFlag(room_id,flag)`.
- `findRoomsWithFlag(area_id_or_name,flag)`.
- `findExchange(area_id_or_name)` returns copied `{room_id,name,area_id}` records.
- `resolve(location)` returns `{room_id,error,hint}`.
- `areas()` and `systems()` return copied sorted records.
- `reachability(from_room,to_room)` returns `{reachable,from_room,to_room,directions,rooms}` copies.

## Reconnect and schema discovery

`reconnect.reset` is emitted after leases/active work are revoked and caches cleared. `API.schemas` documents required fields for `module.state`, `navigation.*`, `hauling.*`, `provider.*`, `command.acknowledged`, `data.*`, and `reconnect.reset`.
