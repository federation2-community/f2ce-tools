# Module API verification

## 2026-09-24 Rank-specific factory automation caps (ew50)

Candidate `f2ce-tools-3.3.0-native-ew50.mpackage`, SHA256
`4bcf3a49185de77738a039ca62fa9b573df8a0522bb54655de225d5690459439`.
Companion `fed-hauler-live-1.17.41.mpackage`, SHA256
`05e617d4146f4de07801b5d42036f1887f2958777c2f83ae4bd66f7ef57d6031`.

All 21 native suites passed against source and reconstructed package code,
including 102 company checks and 59 unchanged teleport checks. Validation passed
279 Lua syntax checks, 32 metadata checks and 236 packaged script/trigger matches.
New tests confirm the last Industrialist/Manufacturer slot (8/15), one purchase,
matching wage acknowledgement/display, completed reconciliation, and refusal at
the full rank roster even with a requested limit of 15. Invalid automatic caps
are rejected before commands. The new optional `factoryRankLimitsVersion=1`
marker preserves compatibility with existing eight-factory consumers.

All 602 FedHauler source checks passed. The extracted consumer package passed
209 main tests and 131 integration tests against this reconstructed native
package. All 31 consumer package files match source. No live accounts, profiles,
servers or shared services were used or changed; nothing was installed or pushed.
Live acceptance remains pending user installation with automation stopped.

## 2026-09-24 Teleport seller handoff without a commodity snapshot (ew49)

Candidate `f2ce-tools-3.3.0-native-ew49.mpackage`, SHA256
`da3e80771b7efeec2b91256a9f903b372ec749246360cd850aec27a7a33324c1`.
Existing FedHauler 1.17.40 is unchanged; only the native F2CE package needs updating.

The reported seller-arrival pause was reproduced with the old worker: it sent
`look` and waited for `gmcp.exchange.commodities`, while the inspected server's
local teleport/look paths only guaranteed room data. The former success fixture
incorrectly supplied a commodity event. The corrected worker requests one
`status` after exact exchange arrival, then requires full empty-ship GMCP and
revalidates location, mapping, customs policy and protection before bulk buying.
No price polling, extra teleport or transaction-policy change was introduced.

All 21 native suites passed against source and reconstructed package code.
This includes 59 teleport checks, with no commodity snapshot, full versus partial
ship events, final cargo/location/mapping changes, protection recovery, late or
duplicate events, same-planet arrival, timeout, stop/pause/disconnect/reload and
unchanged loaded travel. A real bulk-buyer integration test sends exactly one
`buy woods 7` command and does not resend it after duplicate events/phase entry.
The 127-check FedHauler/native integration suite passed with the unchanged consumer.
All 279 Lua syntax checks, 32 metadata checks and 236 packaged script/trigger
comparisons passed. Documentation updated; no live profile modified, gameplay
command sent, package installed or remote push performed. Live acceptance remains
to be confirmed after installation with automation stopped.

## 2026-09-24 Planetary shuttle pad plus local exchange hop (ew48)

Candidate `f2ce-tools-3.3.0-native-ew48.mpackage`, SHA256
`9a110663f32bc34bc3711b3969da0c710fcc50881a68d08b9a078f25ad82d05c`.
Existing FedHauler 1.17.40 remains compatible without a runtime/package update.

All 21 native suites passed against source and reconstructed package code,
including 48 teleport checks. The build passed 279 Lua syntax checks, 32
metadata checks and 236 packaged script/trigger comparisons. The 127-check
FedHauler/native integration suite also passed with the unchanged consumer.

Commands now distinguish `tp System.Planet` from the subsequent local
`tp <server room number>`. Tests confirm the shuttle pad before the local hop,
require new empty-ship GMCP before each command, verify the final exchange and
fresh market before bulk buying, and reject direct interplanetary exchange
arrivals. Local refusal uses normal walking; unmapped exchanges retain ship
navigation/discovery. Tests also cover same-planet local-only teleport, stale
and duplicate events, second-hop timeout/cargo change, cancellation between
hops, unexpected destinations and unchanged loaded buyer travel. No live
profiles were modified or started; live two-hop acceptance remains to be done.

## 2026-09-24 Optional empty seller-leg teleport (ew47)

Candidate `f2ce-tools-3.3.0-native-ew47.mpackage`, SHA256
`d007814ca42bb6d33d14198971b9883a1ecd0237913f26e5169415b60b928fcb`.
Companion `fed-hauler-live-1.17.40.mpackage`, SHA256
`8eb0a0f4f68ed1f44f531746d4a88c1fc6e20ab9f3ded7dc1bf6cf233cfd59d2`.

All 21 native suites passed against source and reconstructed package code.
This includes 38 new teleport checks, 90 existing trade/refusal checks, 26
rotation checks and 97 company checks. All 279 Lua syntax checks, 32 metadata
checks and 236 packaged script/trigger comparisons passed.

All 591 FedHauler checks passed, including 127 actual-native API integration
checks. The extracted FedHauler package also passed the 209-check main suite
and the 127-check native integration suite. All 31 packaged files hash-match
the source. Settings migration defaults teleport OFF, booleans are validated,
older/missing API support fails before commands, and ordinary hauling never
receives the teleport option.

Tests cover the actual Mudlet `getRoomHashByID` and `roomLocked` interfaces,
missing/mismatched mappings, inventory framing and expiry, full fresh ship
updates, exact exchange/landing-pad/wrong-room arrival, market ordering,
known refusals, lost replies, cancellation, protection priority, asynchronous
map discovery and unchanged loaded buyer navigation. No live profile was
installed, controlled, rented a teleporter or started. Live full-hash behavior
remains an acceptance item; legacy full-hash refusals safely use ship navigation.

## 2026-09-24 Factory recovery and owned-commodity exception (ew46)

Candidate `f2ce-tools-3.3.0-native-ew46.mpackage`, SHA256
`dbf5179f4e60eb8d6989c682cfb32a479f2346f250c256be7d8005704f511181`.
Companion `fed-hauler-live-1.17.39.mpackage`, SHA256
`d4ff1d8f656c948659dcb72d9b128272393d9cd1134a7a90a03456441084f8eb`.

All 20 native suites passed against source and reconstructed package code:
97 company checks, 276 Lua syntax checks, 32 metadata checks and 234 packaged
script/trigger matches. Native tests at both Industrialist and Manufacturer
allow TQuarks after foreign NanoFabrics or one verified owned TQuarks factory.
They reject foreign matching production, a third owned factory, insufficient
workers/stock, missing output bids, mismatched slots, absent public ownership
and a competitor appearing between preview and confirmation. The ownership
exception is explicit; older callers retain strict all-company exclusion.

All 587 FedHauler checks passed, including 124 actual-native integrations,
38 comparison checks and 13 builder checks. The actual native parser failure
fixture confirms bounded independent read recovery, retained valid planets,
released command ownership and no construction during research. Source/package
hashes match for all 31 FedHauler package files. No live account, installation,
public-server purchase or automatic restart was performed by these tests.

## 2026-09-24 Batched factory planning reports (ew45)

Candidate `f2ce-tools-3.3.0-native-ew45.mpackage`, SHA256
`711ee5ef2f7dad0d346eee973d656bc3662a46a928b23d6ff319e3023fa50a11`.
Companion `fed-hauler-live-1.17.38.mpackage`, SHA256
`06d17e79ecf7d560f1644c9b5cffc810010d06353c70feb08bf0147567fcda82`.

All 20 native suites passed against source and reconstructed package bytes
using `scripts/test-native.ps1` with Lua/luac 5.1 and `-PackagePath`.
This includes 92 company API checks (seven new groups), 276 syntax checks,
32 metadata checks and 234 packaged script/trigger bodies matched to source.
Existing purchase, depot and wage confirmation tests remain passing.
The FedHauler companion passed all 574 checks, including 122 actual-native
integration tests; game transport/GMCP were mocked, not sent to live accounts.

At both Industrialist and Manufacturer, the new batch fixture inspects
100 planets with 101 commands: 100 `di planet` requests and one final
`di business` or `di company`. Each next request waits for the preceding
expected header. Completion requires all strict planet reports plus final
company text and fresh GMCP. Tests cover GMCP-before-text, earlier unrelated
GMCP, invalid/duplicate/oversized targets, malformed/truncated/out-of-order
reports, premature fences, timeout, cancellation, module disable and identity
changes. No partial report can imply that a planet has no competing factories.

FedHauler uses the batch only for planning and rechecks only the selected
planet before building. Transaction evidence/journals and fail-closed behavior
are unchanged. Older consumers and individual planet/system reads retain their
existing behavior. Nothing was installed, started, pushed or merged.

## 2026-09-21 Session hauling policy and resumable full-galaxy exploration

Candidate `f2ce-tools-3.3.0-native-ew44.mpackage`, SHA256
`a458ff998c826d186ccb616cb2c783e86d8b865b56894bded3e3b1fcae157161`.
Companion `fed-hauler-live-1.17.31.mpackage`, SHA256
`4a662edd4f8c1b1e582125d492ed3428bc64558c495d96195ee8f82dee1dca6d`.

The API now advertises `hauling.session_policy` and validates/copies a
session-scoped 0–100 customs ceiling plus at most 67 unique commodity
exclusions before native command authority is acquired. The customs policy is
re-ranked against that ceiling and caller exclusions are unioned with F2CE's
own settings. Factory automation accepts validated caller wage, total-factory
and per-planet limits within the established game bounds.

`map explore galaxy full` now propagates full mode through every exploration
layer. It captures the authoritative planet roster for every system, exhausts
system space, fully walks each reachable planet, recognizes non-compass orbit
arrivals, and records map-database completion markers for resumable reruns.
Unreachable targets continue to the deferred report without stalling the sweep.
Brief galaxy exploration is unchanged.

Source and reconstructed-package suites both passed: 276 syntax checks, 32
metadata checks, and 234 packaged Lua bodies matched. The suites included 85
company API, 28 API, seven adapter, 30 Walker, 16 counted-bulk, five catalogue,
three customs, 90 hauling, 26 rotation, six orbit-direction, five full-galaxy,
11 navigation-resilience, and all other map/stamina/Who checks. Tests use
mocked command/GMCP fixtures, not the live server. Nothing was installed,
started, pushed, or merged.

## 2026-09-21 Cartel customs policy and unrestricted cargo clearing

Candidate `f2ce-tools-3.3.0-native-ew43.mpackage`, SHA256
`d12ea8f56c25ed333812f76299b602225d12d2904bb7914b79c1f639687f850a`.
Companion `fed-hauler-live-1.17.30.mpackage`, SHA256
`505724835475ddcb26a1b420642d6402a03d8cc8577c4f1b74f6f85669b6464f`.

Before the first Premium Hauler run of a connection, the native hauling service
enumerates mapped cartels and sends exactly `di cartel <cartelname>` for each.
It parses the command's `Customs dues: N%` and `Member systems:` fields. Exactly
5% remains eligible; a duty above 5% excludes the cartel hub and every listed
member system from both supplier and buyer selection. The validated policy is
persisted in map userdata across reconnects and package replacement, then
refreshed once per live session. Malformed, incomplete or timed-out reports stop
before hauling begins.

Cargo already aboard no longer has a profit or purchase-cost sale floor. A
fresh positive bid at a planet other than the bonded origin is eligible, while
the receipt ledger, cargo identity, fresh local quote and one-bay receipt/GMCP
acknowledgements remain fail-closed. New purchases retain the configured entry
margin test, up to 50 cached buyers and the single exceptional refresh.

All native suites passed on source and reconstructed packaged Lua: 275 syntax
checks, 32 metadata checks, 234 packaged Lua bodies matched; 85 company API,
27 API, seven adapter, 30 Walker, 16 counted-bulk/receipt, five catalog, two
customs-policy, 90 hauling, 26 rotation and all remaining map/stamina/Who suites
passed. Whitespace checks passed. Tests use mocked command/GMCP fixtures, not
the live server. Nothing was installed, started or pushed.

## 2026-09-21 Premium lazy rotation and post-purchase buyer refresh

Candidate `f2ce-tools-3.3.0-native-ew42.mpackage`, SHA256
`ce13781aff2d6e41bd241e2c1471c14a13ca568dba337d867d909fbe07eb5f87`.
Companion `fed-hauler-live-1.17.29.mpackage`, SHA256
`d4cb425d146333c37e20b2006684a5608d0b2b75a1d121d48ede6f0fada03bb9`.

Premium `top_base_21` no longer sends 21 price requests at cycle start. The
persisted fixed catalog is queued without market traffic. Each commodity receives
one current snapshot to select its supplier and one post-purchase snapshot to
select a buyer using the confirmed counted-bulk receipt cost. A selected buyer's
refusal or price drop consumes the retained alternatives before a single
exceptional refresh; no remaining profitable buyer stops with cargo preserved.

Counted bulk buying, one-bay guarded selling, receipt/GMCP reconciliation and the
whole-load greater-than-1ig profit requirement were not relaxed. Ordinary
67-commodity hauling and manual price-all retain their existing behavior.

All native suites passed on source and reconstructed packaged Lua: 273 syntax
checks, 32 metadata checks, 233 packaged Lua bodies matched; 85 company API,
27 API, seven adapter, 30 Walker, 16 counted-bulk/receipt, five catalog,
86 hauling, 26 rotation and all remaining map/stamina/Who suites passed. All
538 private FedHauler tests passed, including 122 native integration tests.
Whitespace checks passed. Tests use mocked transport/GMCP fixtures, not the live
server. Nothing was installed, started or pushed.

## 2026-09-20 FedHauler premium top-21 base-price rotation

Candidate `f2ce-tools-3.3.0-native-ew41.mpackage`, SHA256
`1a27e159ab53a98da4515eb28691056f6e32b6d92866ed3fdd6a3747af57f7f4`.
Companion `fed-hauler-live-1.17.29.mpackage`, SHA256
`d4cb425d146333c37e20b2006684a5608d0b2b75a1d121d48ede6f0fada03bb9`.

FedHauler's existing Premium Hauler now requests a session-local rotation of
the 21 highest fixed base-price commodities. The bundled catalog establishes
the cutoff; Gold and Tracers are both included at 600ig. The premium scan sends
exactly those 21 requests and never substitutes lower-base commodities when a
selected item is unavailable, excluded or unprofitable. Ordinary exchange
hauling and manual price-all retain the complete 67-commodity catalog.

Existing dual-copy per-profile progress is reused. Previously attempted members
of the selected 21 remain attempted; markers for the other 46 do not prevent the
selected round from completing. Stops, reconnects and package replacement retain
progress, while loading remains inert. Older native packages reject Premium
Hauler Start before command authority is acquired instead of silently scanning
all 67.

Selling is unchanged from ew40. No sale, bulk-trade, buyer-selection, customs,
receipt or whole-load profit source was modified. The existing 82 hauling tests
continue to pass on source and the reconstructed package.

All native suites passed on source and reconstructed packaged Lua: 273 syntax
checks, 32 metadata checks, 233 packaged Lua bodies matched; 85 company API,
27 API, seven adapter, 30 Walker, 16 counted-bulk/receipt, five catalog,
82 hauling, 26 rotation and all remaining map/stamina/Who suites passed. All
538 private FedHauler tests passed, including 122 native integration tests.
Whitespace checks passed. Tests use mocked transport/GMCP fixtures, not the live
server. Nothing was installed, started or pushed.

## 2026-09-20 Whole-load sale profit instead of a highest-bay veto

Candidate `f2ce-tools-3.3.0-native-ew40.mpackage`, SHA256
`13fcec8d3c62ce7b3f52d572f7f491ea175fff93d9f39a40a1024a415a726135`.

Sale eligibility now requires projected whole-load profit greater than 1ig.
The minimum remaining net bid is `(purchase receipt total + 2 - net proceeds
already received) / remaining tons`, clamped at zero. Groats are integral, so
exactly 1ig or zero profit does not satisfy the requested greater-than-1ig rule.
Both alternative selection and the current-room guard use this budget. Neither
the most expensive remaining bay nor a percentage margin vetoes delivery of an
otherwise profitable owned load. New-purchase margin settings are unchanged.

The purchase/sales receipt ledger must reconcile with remaining cargo counts;
missing, invalid or mismatched accounting stops instead of guessing a cost.
Earlier receipts count only within this load. Previous loads and session profit
cannot subsidize a new losing load. A below-individual-cost sale is recorded,
settled against cargo GMCP, then the remaining budget is recalculated. The bulk
callback adds gross_revenue while preserving net revenue, allowing each buyer's
most recent observed per-bay customs deduction to inform later quote estimates.
That observation is commodity/buyer scoped and is not a fixed tariff guarantee.

The reported Crystals case is now a full regression: fourteen bays requested,
thirteen purchased, then not-selling refusal; 975 tons cost 726,900ig, including
an 830ig/ton bay. Thirteen guarded sales at 803ig/ton complete exactly once for
782,925ig revenue and 56,025ig load profit. No duplicate purchase or stalled
expensive last bay occurs. Further cases cover profitable early sales funding
later cheap bays, strict 0/1/2ig boundaries, already-recovered purchase cost,
missing ledgers, changing quotes, and buyer-specific customs deductions.

All native suites passed on source and reconstructed packaged Lua: 272 syntax
checks, 32 metadata checks, 233 packaged Lua bodies matched; 82 hauling tests,
16 counted-bulk/receipt tests, and 20 rotation tests passed. All other native
suites, sale/customs regex checks, and all 535 private FedHauler tests passed,
including 119 native integration tests. Whitespace checks passed.

FedHauler remains 1.17.28. Tests are offline with mocked GMCP and receipt
fixtures, not live-server verification. No profile installation, gameplay,
remote push or PR update occurred. Quotes/customs may change before execution;
projected profit is not guaranteed. Existing stopped cargo is not automatically
adopted into a new run without its original load ledger.

## 2026-09-20 Ship-sale wording and cartel customs net receipts

Candidate `f2ce-tools-3.3.0-native-ew39.mpackage`, SHA256
`df91d1dac79de893a3cf3d0f59e3dbc1d6755a5798902cf8215d585ded9f9b43`.

The reported `75 tons of Libraries sold for 49425ig from your ship` did not match
the old trigger, which required `sold to the exchange for`. Both forms now
match, with or without comma-separated amounts and the ship suffix. Native
verification checks real response strings against source regex metadata and
compares the compiled package's sale/customs regexes with the tested patterns.

The preceding Candy customs notice pairs with the next active sale receipt:
49,425ig gross minus 11,430ig customs records 37,995ig net, not gross income.
Wrapped continuations, blank lines, per-bay capture clearing, idle/buy isolation,
timeout/new-order cleanup, malformed/mismatched/duplicate notices, and zero net
are covered. A customs notice alone never acknowledges a sale or renews the
watchdog. Uncertain accounting stops without replay or advancing a bulk queue.

Full hauling tests exercise three taxed Libraries sales through the real trigger
bodies, recording 113,985ig and advancing once to the next commodity. A receipt
before cargo waits for ship GMCP; a preceding price update is retained. Customs
that makes net revenue below purchase cost records the real proceeds and stops
with remaining cargo preserved. This does not predict tariffs before a sale or
remove the current text-receipt dependency: cargo GMCP remains reconciliation,
not a transaction-specific net-proceeds receipt.

All native suites passed against source and reconstructed packaged Lua, with
272 syntax checks, 32 metadata checks, and 233 packaged Lua bodies matching
source. Counted bulk/receipt tests: 16 passed; hauling tests: 75 passed; rotation
tests: 20 passed. All other native suites and all 535 private FedHauler tests
passed, including 119 native integration tests. Diff whitespace checks passed.

FedHauler remains 1.17.28. The package retains ew38's purchase-ordering repair,
the 50-candidate shortlists, saved commodity rotation, and prior Who changes.
Testing was offline with mocked GMCP and literal live-response fixtures, not a
live Mudlet/server validation. No profile was installed, no gameplay command was
sent, and no remote branch or PR was updated.

## 2026-09-20 Counted purchase receipts independent of GMCP arrival order

Candidate `f2ce-tools-3.3.0-native-ew38.mpackage`, SHA256
`170f1a3e15f599ad9df13652fe4b85ea9ae2e78b0934d8971822fcfe08cb57e8`.

Reproduced the premature completion of a fourteen-bay purchase: a full-hold
GMCP snapshot arrived before the first text receipt, causing the old bulk buy
handler to finish after one receipt and the hauling accounting guard to stop.
Completion now requires the requested receipt count or an explicit terminal
response, not the GMCP free-space value. The command is still sent only once.

When complete receipts precede ship cargo, hauling waits up to five seconds for
the matching cargo count and valid commodity/cost records. Accounting uses the
sum of actual receipts, not a quoted price or an extrapolated first-bay cost.
Partial refusal delivers only confirmed cargo. Missing receipts or cargo stop
without replay. Immediate/deferred pause, repeated arrival/resume transitions,
handler cleanup, replaced state, and the safe-room stop delay cannot cause a
duplicate buy or revive a stopped purchase callback.

All native suites passed against source and reconstructed packaged Lua:
270 syntax checks, 32 metadata checks, and 231 packaged Lua bodies matching
source. Counted bulk tests: 5 passed; hauling refusal/accounting/ordering tests:
72 passed; rotation persistence tests: 20 passed. The three Who/table suites
and all other native suites passed. All 535 private FedHauler tests passed,
including 119 native integration tests. Diff whitespace checks passed.

This package retains ew37's Who improvements, ew36's 50-candidate shortlists,
durable 67-commodity rotation, and guarded sales. FedHauler remains 1.17.28.
Validation was offline: no live profile installation, gameplay command, remote
push, or PR update was performed. Existing cargo from an already stopped live
session is not automatically sold or resumed by installing this package.

## 2026-09-20 Incremental Who refresh integrated with native services

Candidate `f2ce-tools-3.3.0-native-ew37.mpackage`, SHA256
`00a6234290e32564d467abe73fb8d99a0fc2cfd9275b0d51d3314e2df445e214`.

Integrated the six-file Who/player-DB/table change from local commits `2bc5bf6`
and `a3c4508` on `fix/who-refresh-churn`, originally based on official upstream
`044b937`. The original branch was not modified or published. This candidate
retains all native ew36 services and hauling changes; it is not a replacement
with the upstream-only Who package. FedHauler remains 1.17.28 with no source or
package changes required for this integration.

Unchanged player feeds no longer notify UI consumers. Database row references
remain stable, Who caches unchanged cell writes and coalesces changed-player
payloads, and the shared table supports an in-place row refresh when membership
and sorting permit it. Legacy/full events, visibility/order changes and failed
row refreshes keep the full-refresh path. The event's extra version-1 payload
is optional for existing consumers.

Integration hardening validates the complete change payload before merging any
rows. Missing or wrong-type players/fields, mismatched keys, invalid flags and
unknown versions request a full refresh rather than throwing before a timer is
scheduled. A malformed delta coalesced with a valid one promotes the whole batch
to a full refresh. No additional optional performance optimizations were added.

All native suites passed against source and reconstructed packaged Lua, including
the three imported Who/player-DB/table suites and added malformed-event tests.
There were 270 Lua syntax checks, 32 metadata checks, and 231 packaged Lua bodies
matching source. Table tests additionally verify that Exchange Walker's custom
active/inactive header styles and growing/shrinking viewport heights survive.
All 535 private FedHauler tests passed against this native tree, including the
119 native integration tests. Diff whitespace checks passed.

Validation was offline. No live Mudlet profile was installed or exercised, no
gameplay commands were sent, and no remote branch or PR was updated. The prior
Who branch's web stress results were supplied as background evidence; that
browser performance benchmark was not rerun on this combined package.

## 2026-09-20 Durable commodity rotation and guarded normal sales

Candidate `f2ce-tools-3.3.0-native-ew36.mpackage`, SHA256
`42f671c525efbccbb6fc6e58b936fcfbace3145abb41e133dc7be6097db45c03`.

All native suites pass on source and reconstructed package: 267 Lua syntax
checks, 32 metadata checks, 231 packaged Lua bodies matching source, 60 hauling
refusal/accounting/guard tests, 20 rotation persistence tests, and seven native
adapter tests including a 50-result shortlist with the full 60-row market kept.
The private consumer passes all 535 tests, including its 119 native integration
tests. Its companion is FedHauler 1.17.28; legacy APIs without `prices.maxResults`
continue at 20 during staged upgrades, while this native API advertises 50.
No live profile installation or gameplay was performed.

The 67-commodity catalog is reviewed in full. Every eligible commodity gets at
most one load/attempt per round, not repeated loads of the five highest-ranked
goods. Unavailable, excluded and unprofitable goods are reviewed without trades.
An attempt is written and verified in both per-profile checkpoint copies before
its detail request/travel. The files live outside the package folder and contain
only revision/round/commodity markers, never executable or resumed authority.
The next explicit start reloads progress after stop/reconnect/package replacement;
interrupting an attempt therefore skips it until the next round. `haul rotation`
reports progress without activating anything. Saving/reading errors fail closed;
one valid copy can recover a damaged copy, but two invalid copies cannot reset
the round silently. Tests exercise every commodity across reloads, same-run
advancement, profile isolation, catalog changes, incomplete/duplicate reviews,
permission/write/close failures, corrupt copies, and stale run callbacks.

The existing protected recovery sale is now also the normal sale path. Each bay
requires a current-room quote covering the highest remaining cargo cost and both
receipt/cargo reconciliation before another bay. A post-order quote received
before its text receipt remains usable; the pre-order quote cannot be reused.
Counted bulk buys are unchanged, but purchase receipts now supply exact total
costs. Sale receipts supply exact revenue, so completed-cycle/session profit no
longer extrapolates first-bay costs or uses remote quote prices. Unexpected cargo
and legacy dump-phase entry points cannot bypass the guards or jettison cargo.
Tests also cover forced-pause refusal handoff and actual end-to-end profit sums.

The server still has no atomic minimum-bid sell command: a concurrent change
between the checked quote and execution can affect one bay. Its actual receipt
is recorded and remaining sales stop if that race takes the bid below cost.

## 2026-09-20 Full-market buyers and break-even cargo recovery

Candidate `f2ce-tools-3.3.0-native-ew35.mpackage`, SHA256
`1c41c7e4cb7c81b71c30d3b6408bfaa38e722a03ea20fb069bb277bd459fc6b8`.

All native suites pass on source and reconstructed package: 265 Lua syntax
checks, 32 metadata checks, 230 packaged script/trigger bodies matching source,
and 51 hauling refusal/recovery tests. The private consumer's 119 native
integration tests also pass. No live profile installation or trading was done.

The ew34 fallback incorrectly treated the display shortlist (20 rows for premium
prices) as the entire market. Routing now uses the complete parsed response,
which has already passed the provider's route-policy filter. Shortlist-only
callbacks remain compatible, but an explicitly empty full response cannot revive
stale shortlist entries. Price tables keep their existing display limits. The
full-market search is linear rather than rescanning all buyers per candidate.

As explicitly requested, recovery of already-held cargo may sell below the new
purchase margin down to break-even. Its floor is the highest purchase cost of
the remaining bays. Recovery sells one bay at a time using current-room GMCP
bid receipts, waits for the cargo count to reconcile, then requires a newer
matching commodity receipt before sending another bay. Handlers use full-market,
individual-commodity and parent `gmcp.char.ship` events and are removed on
cleanup. Normal profitable hauling retains counted bulk orders. Clearing the
recovery load completes its statistics once and advances to the next commodity.
New purchases retain their existing margin policy.

Tests cover the twenty-first buyer, suppliers hidden by display limits, full
market refreshes, partial/malformed responses, exact break-even and mixed bay
costs, below-cost arrival and falling next-bay bids, unrelated ticker updates,
room changes, missing quotes, delayed cargo updates, receipt revenue, forced and
deferred pause/resume, cleanup/reload, and a server-side price race. A quote wait
is bounded to three seconds before trying another buyer; an uncertain order or
unreconciled cargo stops without replay. Exhaustion reports quoted/untried
counts, the best remaining bid and the purchase-cost floor.

Federation's sale command has no atomic minimum-price condition. The guard uses
the latest local quote; another trade can still change the server price before
execution. If the actual receipt falls below the floor, its revenue is recorded
and remaining recovery cargo is stopped rather than continuing to sell.

## 2026-09-20 Prompt exchange-hauling refusal failover

Candidate `f2ce-tools-3.3.0-native-ew34.mpackage`, SHA256
`3c3ee1c032e2a224ebf8a0f4ccb1690e6148c11fc655a39fea581279fd636496`.

All native suites pass on source and reconstructed package: 264 Lua syntax
checks, 32 metadata checks, and 229 packaged script/trigger bodies matching
source. The new hauling refusal suite has 27 tests, alongside the three counted
bulk-command tests. The FedHauler native integration suite passes all 119 tests.
Full and line-wrapped Galactic Administration restriction messages are checked
against the trigger regex, as well as unrelated text that must not match.

Explicit unavailable-supplier and unavailable/restricted-buyer replies cancel
the bulk watchdog and carry a classified reason to exchange hauling. Its cached
alternatives are tried immediately, with per-commodity, direction, system and
planet exclusion instead of a changing sorted-list index. An exhausted cache
gets one fresh price request. Configured margin checks still apply. Partial
loads are delivered, partial sales keep the remainder, exhausted suppliers skip
the commodity and exhausted eligible buyers stop with cargo aboard. These are
temporary commodity-pass exclusions, not persistent navigation blacklists.

Regression coverage includes reordered prices, invalid/empty replies, stale
callbacks after stop or commodity changes, deferred pause and explicit resume,
graceful stop, partial timeout handling, mixed-cargo timeout cancellation and
reentrant bulk callbacks. Timed-out exchange trades, including cleanup/dump
paths, do not authorize another order or jettison. Existing native PO routing
policy is not redesigned here. No live accounts were driven, packages installed,
or gameplay purchases made for this verification.

## 2026-09-20 All-company factory commodity exclusion

Candidate `f2ce-tools-3.3.0-native-ew33.mpackage`, SHA256
`9ebcec5a8c9507b6025ecad68c1ae79af542a2f975d3ac32a85fc8cd580ea0e5`.

All native suites pass on source and reconstructed package: 262 Lua syntax
checks, 32 metadata checks, and 228 packaged script/trigger bodies matching
source. Company coverage is 85 tests, including public empty/foreign/wrapped
factory lists, invalid/partial/duplicate rows, both company ranks, late competitor
appearance before purchase and after depot purchase, cancellation/identity/
timeout cleanup, and unchanged wage-acknowledgement ordering. The private
consumer suite has 535 passing tests, including 119 native integration checks.

Public `di planet` commercial activity provides all-company factory evidence;
`di system` omits that section. Automatic builds and opt-in manual builds reread
the public list on their own lease before spending. Missing evidence is not an
empty list; an uncertain partial site is never replayed. This is not an atomic
reservation against another player building concurrently. No fresh live-server
purchases or graphical profile acceptance were performed for this change.

## 2026-09-20 Factory wage acknowledgement ordering

Candidate `f2ce-tools-3.3.0-native-ew32.mpackage`, SHA256
`c754307e03d89243444d1189ed3fb90f86b71cbd39ac620082e7d8b0eb6e2fd6`.

All native suites pass against source and reconstructed packaged XML: 262 Lua
files compile, 32 metadata files parse, and 228 packaged script/trigger bodies
match source with intended dependency injection. Company/factory coverage is
77 passing tests; the separate private consumer integration suite has 117 passes.

The regression reproduces purchase GMCP arriving before the automatic factory
display (initial wages 0ig). Neither that display nor an early 40ig display can
finish wage verification. Only the exact matching server acknowledgement unlocks
one new display request; its complete, identity-checked response must show 40ig.
Tests cover both company ranks, combined depot/factory builds, wrapped/colored
and invalid acknowledgements, timeout, cancellation/teardown, changed identity,
denied sends, and no duplicate writes. Cleanup and late cancellation preserve
confirmed status. Existing uncertain journals are not cleared by the update.

These are offline response-ordering and packaged-code tests, not a fresh live
server or graphical acceptance run. No public account commands were sent.

## 2026-09-16 Single-factory confirmation and workforce capture boundary

Candidate `f2ce-tools-3.3.0-native-ew27.mpackage`, SHA256
`60fae327f45cca2425c60ba4b5b2595146815216e3e95521d6829559d7cefb8e`.
Companion FedHauler 1.17.19, SHA256
`6c83d07f089ff2f54b14bb821c9e8144b3f4a5af50a0eab3959c65d36e235ee2`.

All native suites pass source and reconstructed package; company suite has 53
checks, 262 Lua files compile, 32 metadata files parse, and 228 packaged bodies
match. Tests cover both ranks, first slot/empty roster, fresh worker/market/cash
and stamina bounds, changed roster/authority, lease cleanup and no retry after
uncertain purchase. Header gating ignores trailing earlier-command text, without
weakening the strict system parser or the company text/GMCP completion fence.

Final-package code passed 11 real local-server checks per rank (Industrialist,
Manufacturer) in separate disposable, loopback-only namespaces. One cancelled
preview spent nothing; a separately confirmed purchase created Firewalls #2 on
Candy with exactly a 2m company debit and a real consumer journal. Repeated
confirmation sent nothing. The initial test exposed trailing `look` text arriving
after GMCP; the fixed system-header capture passed both ranks. Missing responses,
OFF/late replies and disconnect cleanup also passed. Original databases stayed
unchanged and disposable servers stopped. Public profiles were not touched.

Server was older F2CE 4.9 b856b6a3, SHA256
`396f17838e436f4881959e7c7a41f2be08bbd5e8c17a44d8da35825cf0a13412`.
This is not GUI acceptance, public-version certification, a labour reservation,
or profit guarantee. No automatic construction loop/promotion was added. The
consumer's 390 regressions passed; its purchase authority requires a durable
intent journal immediately before send. Full sanitized evidence is in the
FedHauler repository's `docs/FACTORY_BUILD_RESULTS_1.17.19.md`.

## 2026-09-16 Same-reservation built-in price delegation

Candidate: `f2ce-tools-3.3.0-native-ew25.mpackage`, SHA-256
`ea22fee5f60e46f146a41c862f51a805d0e89903107e2565dbe53bd2578a7430`.

Native suites pass against source and reconstructed packaged XML; 260 Lua
sources compile, 32 metadata files parse, and all 226 embedded bodies match
source with expected build substitutions. The core API suite now has 27 passing
groups, including four for `prices.provider_builtin`: one leased built-in
request without a nested queue, duplicate/mixed dispatch refusal, foreign native
contention rechecks, and rejection of late/duplicate callbacks after cancel or
timeout. Existing provider fallback and command ownership tests remain green.

FedHauler 1.17.17's 82 native integration checks also pass using both packaged
artifacts. The new test uses actual native cartel checking and price parsing
with Industrialist GMCP and no premium ticker; the consumer removes blacklisted
rows and recomputes results before continuing. No game subscription semantics,
Walker layout, factory transfers, rank gates, or default-OFF behavior changed.
No public-server profile or GUI session was used for this verification.

## 2026-09-16 Owned stamina cancellation and interplanetary factory journeys

Candidate: `f2ce-tools-3.3.0-native-ew24.mpackage`, SHA-256
`46b650cc3a0aecc7083f01442d2610986df77940e019eae86b27e94149830b96`.

- A disposable-server OFF-during-food test reproduced queued purchases after
  API client detachment. Unregister now cancels only the exact client's trip,
  invalidates old callbacks and releases only stamina-owned navigation.
  A command already transmitted cannot be recalled; foreign owners are untouched.
- Seven new native stamina groups cover owned/foreign cancellation, stale buy,
  navigation, room and pause callbacks, and cancellation within the pause callback.
  An adapter group checks exact callback ownership during unregister.
- Source and reconstructed-package suites: **146 groups each**, 260 Lua syntax,
  32 metadata checks, and 226 matching embedded script/trigger bodies.
- Final-package code with unchanged FedHauler 1.17.15 passed Industrialist and
  Manufacturer Candy/Earth input buy/store and output fetch/sell journeys. Both
  recovered from 25% to 100% stamina through real food travel and 15 purchases,
  returned and resumed without duplicate cargo mutations. Six checks per rank.
- A third disposable world passed three OFF checks, including cancellation
  during food buying with no subsequent food/haul commands or retained lease.
  FedHauler's 327 offline checks passed. Original databases remained unchanged;
  all test servers stopped. No installation, public account use or push occurred.
- Evidence: FedHauler `docs/FACTORY_JOURNEY_RESULTS_2026-09-16.md`. Tests use the
  local F2CE 4.9 b856b6a3 binary, isolated loopback namespaces and real native
  speedwalk/stamina with XML/BFS headless map storage. They do not certify
  graphical Mudlet, arbitrary routes, map exploration, random customs recovery
  or public-server revisions. No repeated schedule, construction or promotion.

## 2026-09-16 Single-bay market operations for reviewed factory logistics

Candidate: `f2ce-tools-3.3.0-native-ew23.mpackage`, SHA-256
`a2dff63727ab9cdae8c259b5c46c71d8a8d75a8a092d00c90f53736e4e352efa`.

- Add `company.cargo.transfer` / `company.prepareCargo` with one-bay preview,
  explicit scoped confirmation, quote bounds, 5,000t saleable input stock,
  personal/company reserves, fresh GMCP and exact settlement under one lease.
- Explicit `score`, `look` and rank-specific company reads support the older
  local binary; counted commodity commands avoid ambiguous bulk-sale syntax.
  Reject same-origin sales without evidence of an unbonded exception.
- Depot operations accept exact expected inventory for factory reservations.
  Exclude only four verified ambient ticker formats from strict depot capture.
- Source and reconstructed-package suites: 138 passing groups each (38 company
  groups), 259 Lua syntax, 32 metadata checks and 226 matching embedded scripts.
- Final FedHauler 1.17.15 passed 327 offline checks plus two disposable local
  rank runs, 10 checks each. Actual reviewed export fetch/sell and independent
  input buy/store primitives reconcile cargo and cash. Original database was
  unchanged and both servers stopped. No live profile installation or use.
- Evidence: FedHauler `docs/FACTORY_LIVE_RESULTS_1.17.15.md`. F2CE 4.9 b856b6a3,
  private loopback namespaces, headless client and a one-room map fixture only.
  Interplanetary/food navigation and graphical/public-server behavior remain
  unverified; no recurring trip schedule, construction or promotion is added.

## 2026-09-16 Explicit single-bay depot transfers

Candidate: `f2ce-tools-3.3.0-native-ew22.mpackage`, SHA-256
`bb4f77111d84718c10e8961642ebe61b029d7fae369e4ddc8c0b64ebc537b5d8`.

- Add `company.depot.transfer` preview/confirm, one shared lease, mandatory
  reserves and fresh room/ship/cash/stamina plus owner-fenced depot reads.
- Revalidate before sending once; require ship/depot and both cash deltas before
  confirmation. Expiry/cancel/disconnect revoke authority; no automatic retries
  after an uncertain result. No navigation, batch loop or construction.
- Source and exact-package verification: 130 groups pass per run, including
  30 company/depot groups; 259 Lua syntax and 32 metadata checks; 226 embedded
  scripts match source/substitutions.
- Final FedHauler 1.17.14 artifact passed Industrialist and Manufacturer real
  store/fetch round trips on separate disposable loopback worlds, each with 12
  acceptance checks. Both cash balances and cargo returned to their starting
  values. Original database unchanged; test servers stopped cleanly.
- Consumer evidence: `docs/FACTORY_LIVE_RESULTS_1.17.14.md` in FedHauler. Local
  binary is F2CE 4.9 b856b6a3; this is not graphical/public-server certification
  or a complete factory hauling executor. No live profiles were installed/run.

## 2026-09-15 Industrialist data and owner-bound depot reads

Candidate: `f2ce-tools-3.3.0-native-ew21.mpackage`, SHA-256
`4581aa1650f3cf7e1ac9dfa703eef52aed9413e4913f9361428f3458cc3c1359`.

- Add the real Industrialist `char.business` channel; no stale `char.company`
  fallback. Manufacturer/Financier retain `char.company`.
- Add `company.depot.read` / `company.depot(context,planet,callback)` with a
  strict depot parser, single read-response lease, ordered owner header fence,
  rank-specific fresh GMCP and Manufacturer occupancy reconciliation.
- Source and exact-package verification: 120 groups pass per run, including
  20 company/depot checks; 258 Lua files pass syntax, 32 metadata files parse,
  and all 225 embedded scripts match the tested source/substitutions.
- FedHauler 1.17.13 final package passed live Industrialist and Manufacturer
  stocked-depot acceptance against the isolated local 4.9 b856b6a3 binary.
  Separate disposable worlds, real legacy GMCP/text, strict read allowlists;
  original database unchanged and all servers stopped. No public profiles,
  cargo commands, depot writes, construction or promotion were used.

Detailed consumer evidence is recorded in its
`docs/FACTORY_LIVE_RESULTS_1.17.13.md`. These tests do not certify graphical UI,
current public-server revisions, arrival depot access or hauling execution.

## 2026-09-11 Rebuilt-orbit repair and counted hauling commands

Candidate: `f2ce-tools-3.3.0-native-ew19.mpackage`; Walker
3.4.0-native.12 and API 1.2.0-candidate.3 are unchanged.

SHA-256: `f62455cd9e5ab47a2a2fb5f3b5928fbed3634271c77650d9bbdcdc0314204f2b`.

The supplied map export exposed an exact rebuilt-system failure: live Lyra
userdata advertised `up:101,down:100`, but both saved exits still led to old
room 100. Because the stale `up` edge occupied the direction, exploration
could not create the missing stub and never visited the new orbit. Cached and
live exit reconciliation now remove a destination whose stored room hash
disagrees with authoritative exit userdata, create the correct stub, and
connect it when the new orbit is discovered. Correct non-compass edges remain
unchanged.

Native bulk hauling now transmits one counted `buy <commodity> <bays>` command.
A complete single-commodity hold uses `sell cargo`; bounded partial or mixed
sales use `sell <commodity> <count>`. Normal per-bay server replies are counted
without sending duplicate commands.

Source and exact-package verification pass all 100 native groups: API 23,
adapter 5, Walker 30, bulk hauling 3, startup 7, topology 8, map lifecycle 1,
Galaxy lifecycle 7, non-compass orbit discovery 5, and navigation resilience
11. All 253 Lua syntax checks, 32 metadata checks, and 221 packaged-script
comparisons pass. No profile was modified and no package was installed, pushed,
or released.

## 2026-09-11 Non-compass orbit discovery

Candidate: `f2ce-tools-3.3.0-native-ew18.mpackage`; Walker
3.4.0-native.12 and API 1.2.0-candidate.3 are unchanged.

SHA-256: `bfbe4e4a8bd66bb2f3452540cda1587d0b6716dd7fb3dbbe7a30e318af9b4658`.

System exploration now treats Mudlet's canonical `up` and `down` exit names
consistently with `in` and `out`, while retaining aliases for imported maps.
An already-mapped or duplicate arrival can no longer bypass expected-planet
recognition merely because the orbit room was visited earlier. Expected planet
names match case-insensitively, and an authoritative live GMCP orbit hash
repairs missing orbit userdata before the planet-landing phase begins.

Source and exact-package verification pass all 96 native groups: API 23,
adapter 5, Walker 30, startup 7, topology 8, map lifecycle 1, Galaxy lifecycle
7, non-compass orbit discovery 5, and navigation resilience 10. All 252 Lua
syntax checks, 32 metadata checks, and 221 packaged-script comparisons pass.
No profile was modified and no package was installed, pushed, or released.

## 2026-09-11 Native navigation resilience and map repair

Candidate: `f2ce-tools-3.3.0-native-ew17.mpackage`; Walker
3.4.0-native.12 and API 1.2.0-candidate.3 are unchanged.

SHA-256: `5d4204bd0dffd2c20864ca8dda90e56934dc583af0acb9af5cb9fc6b97c3b9af`.

Navigation ownership now spans the complete API/hauling/exploration operation
instead of being cleared after each individual speedwalk. Route cancellation
invalidates queued callbacks and stops speedwalking, circuit travel,
exploration, arrival handlers, and `whereis` capture. Unknown-location retries
are bounded, and a copied route edge is revalidated against the live map before
its command is sent.

Imported maps reconcile known regular-exit stubs and isolated legacy
`(via board)` rooms. A board endpoint proven by a live orbit/shuttlepad
transition is saved by room hash and cannot be overwritten by a later stale
GMCP board hint. Duplicate destination selection now prefers the current,
reachable, reciprocal, and most recently observed record deterministically.
Headless export also preserves command-keyed special exits; older code iterated
that Mudlet table backwards and silently omitted `board` and `jump` edges.

Source and exact-package verification pass all 91 native groups: API 23,
adapter 5, Walker 30, startup 7, topology 8, map lifecycle 1, Galaxy lifecycle
7, and navigation resilience 10. All 251 Lua syntax checks, 32 metadata checks,
and 221 packaged-script comparisons pass. No profile was modified and no
package was installed, pushed, or released.

## 2026-09-10 Exchange Walker column headings and policy bounds

Candidate: `f2ce-tools-3.3.0-native-ew16.mpackage`; Walker
3.4.0-native.12. API 1.2.0-candidate.3 is unchanged.

SHA-256: `d0f2d4aebe128f85e46ecfcd12769b3fbcd5a8dd15bcf5d62a8cafaaaf9fbc44`.

The data board now mounts its seven sortable headings directly in the Muxlet
content slot instead of nesting them inside a decorative Geyser Label. This
keeps Commodity, Spread, Current, Min, Max, Efficiency, and Net visible after
the saved tab's hidden/reveal paint cycle. Narrow panes retain explicit Spread
and Current labels and use only `Eff.%` as the compact heading.

Settings labels now state the game ranges. Deficit, breakeven, and surplus
spreads accept only 6-40%; every configured minimum accepts 0-10,000 tons; and
every configured maximum accepts 0-20,000 tons. Muxlet field metadata and the
whole-policy runtime validator enforce the same boundaries, including the
existing minimum-not-above-maximum rule. Boundary and rejection cases are
covered by the offline suite.

Source and exact-package verification pass all 81 native groups: API 23,
adapter 5, Walker 30, startup 7, topology 8, map lifecycle 1, and Galaxy
lifecycle 7. All 250 Lua checks, 32 metadata checks, and 221 packaged-script
comparisons pass. No profile was modified and no package was installed, pushed,
or released.

## 2026-09-10 Exchange Walker tab paint-order recovery

Candidate: `f2ce-tools-3.3.0-native-ew15.mpackage`; Walker
3.4.0-native.11. API 1.2.0-candidate.3 is unchanged.

SHA-256: `1c3eb07757e68b2a18333e7b5461e9e2198ecb93b60e80ef35b223e6fa26beb3`.

Ersella's saved workspace proves ew14 loaded and completed its reconstruction:
the selected `Exchange Walker` is a new locked tab with the registered Founder
rule and the expected content ID. A diagnostic copy of the same content in
floating pane_11 renders correctly, isolating the remaining failure to hidden
tab construction and reveal rather than the board renderer.

Mudlet 5.0.1 Geyser reveals a container's children through
`pairs(windowList)`, which does not preserve paint order. A board first built in
an inactive tab can therefore reveal its full-size black background after its
foreground and cover every otherwise healthy widget. Walker now activates a
selected replacement before applying content, routes Muxlet resize/reveal
callbacks through the complete visibility repair, and pins the background below
the table and controls after every immediate and settled reflow.

Source and exact-package verification pass all 81 native groups: API 23,
adapter 5, Walker 30, startup 7, topology 8, map lifecycle 1, and Galaxy
lifecycle 7. All 250 Lua checks, 32 metadata checks, and 221 packaged-script
comparisons pass. No profile was modified and pane_11 was not removed.

## 2026-09-10 Exchange Walker native-tab reconstruction

Candidate: `f2ce-tools-3.3.0-native-ew14.mpackage`; Walker
3.4.0-native.10. API 1.2.0-candidate.3 is unchanged.

SHA-256: `0a31c4f13764ac4c76f1086c8803e78945bc582916b3c219106deb8d9b9f555f`.

The remaining black-tab reports shared a malformed saved tab shell. Muxlet's
working Who, Events, and Exchange tabs are restored with native locked
capabilities, while older Walker placement created a normal user tab and then
appended its Founder rule without registering that tab with the reactive rule
engine. Replacing only the content slot left that broken lifecycle intact.

Walker now identifies only an exact `Exchange Walker` tab inside the native
Who/Events/Exchange host. If it has the legacy shell, Walker removes its active
content through Muxlet, deletes the old tab object, recreates it at the same
position with the same locked settings as the working tabs, registers the
Founder rule through Muxlet's native API, applies a new content slot, and
restores active selection. A valid native tab remains untouched. The exported
Full workspace now declares every matching setting explicitly.

Source and exact-package runs pass all 81 native groups: API 23, adapter 5,
Walker 30, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7. All
250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches pass.
No profile was modified and no package was installed, pushed, or released.

## 2026-09-10 Exchange Walker restored-tab inherited visibility recovery

Candidate: `f2ce-tools-3.3.0-native-ew13.mpackage`; Walker
3.4.0-native.9. API 1.2.0-candidate.3 is unchanged.

SHA-256: `675803813537a705f50ca33c086af7b01a66ed88b6e47f34adb227f882bd357f`.

Live inspection confirmed that Ersella had ew12 installed and the selected
`Exchange Walker` tab was correctly persisted with
`_activeContent: exchange_walker_live`. The black surface therefore was not a
stale binding or missing package. Inspection of Mudlet 5.0.1's
`Geyser.Container` showed the remaining defect: explicit `hidden` and inherited
`auto_hidden` flags are independent, while plain `show()` clears only the
former. The Muxlet-owned slot built while the restored tab was inactive could
remain `auto_hidden=true` after our earlier one-call reveal.

Active-tab repair now clears both visibility flags, in the required order, on
the tab content and Muxlet-owned content slot before reflow. The offline Geyser
mock now models Mudlet's two-flag behavior, and the saved-tab test starts with
both flags asserted on both layers and verifies all four are cleared.

Source and exact-package runs pass all 80 native groups: API 23, adapter 5,
Walker 29, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-10 Exchange Walker Mudlet 5.0.1 footer compatibility

Candidate: `f2ce-tools-3.3.0-native-ew12.mpackage`; Walker
3.4.0-native.8. API 1.2.0-candidate.3 is unchanged.

SHA-256: `aa103bb5e8c492934bab702020a9c8aff114494726fdf4db6e7c506336373a2b`.

Live Mudlet reported `[string "Script: board"]:327: attempt to call method
'setToolTip' (a nil value)` while constructing the integrated Exchange Walker
tab. Mudlet 5.0.1's `Geyser.CommandLine` does not implement the Label-only
tooltip method. Because the input was constructed before Refresh, Preview, and
the action rows, that uncaught enhancement call explained the visible input and
missing buttons exactly.

All board tooltip calls are now optional and protected. The test Geyser command
line intentionally omits `setToolTip`, matching the installed runtime, while
the visible Inspect label retains the field explanation and its supported
tooltip. Per-widget footer layout is also isolated so a future unsupported
primitive cannot prevent later controls from being positioned.

Source and exact-package runs pass all 80 native groups: API 23, adapter 5,
Walker 29, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-10 Exchange Walker stale-tab recovery and board polish

Candidate: `f2ce-tools-3.3.0-native-ew11.mpackage`; Walker
3.4.0-native.7. API 1.2.0-candidate.3 is unchanged.

SHA-256: `a0ab2635ba6d0a0f9bdce6ac4ca30d1deff6be320749c614bf4ec71d378f6e7b`.

Live inspection established that Ersella's selected tab was named `Exchange
Walker` but persisted `_activeContent: fed2_cargo`. The same tab stayed black
with other content while Walker rendered in a newly created pane. Muxlet 2.3.2
restores tab content while the tab is hidden, can leave both the tab container
and its framework-owned content slot explicitly hidden, and later activates the
saved tab without revealing that slot.

The native placement path now recognizes the intended named tab, replaces its
stale content binding with `exchange_walker_live`, verifies the complete board,
and reveals both Mux layers when that tab is active. It reuses the existing
Who/Events/Exchange host rather than creating another tab or pane. The named
tab remains the repair target even when a temporary direct-pane Walker mount
also exists, matching the live diagnostic workaround.

The board footer is also reorganized and styled for clearer action hierarchy.
The formerly ambiguous `Planet` field is now `Inspect`: Enter/Refresh performs
a one-off read-only remote exchange capture, while Preview calculates proposed
settings without applying them. Tooltips explain each action, state and schedule
remain separate from the operational message, and Unicode comparison text that
rendered incorrectly in Mudlet was replaced with ASCII-safe wording.

Source and exact-package runs pass all 80 native groups: API 23, adapter 5,
Walker 29, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-10 Exchange Walker saved-tab mount recovery

Candidate: `f2ce-tools-3.3.0-native-ew10.mpackage`; Walker
3.4.0-native.6. API 1.2.0-candidate.3 is unchanged.

SHA-256: `04601c29d2c0a4459c0d14faaeea789fb606c5a0bb858fa4ab34420ea33e2811`.

The remaining black-tab failure was reproduced from the Ersella workspace:
Muxlet restores every saved tab before activating the selected tab, so an
inactive Exchange Walker tab can initially report `0x0` content geometry.
Walker previously built and permanently accepted that effectively invisible
board. A construction interrupted during hot reload could likewise leave a
partial instance that later placement attempts mistook for a healthy mount.

Walker now uses the host tab viewport when an inactive tab has no usable
geometry, validates the complete widget/control tree before accepting any tab
or pane placement, rebuilds partial instances, reveals an active content slot,
and reflows after successful recovery. It preserves the saved tab, selected
workspace, Founder gate, bottom controls, and all map/Galaxy content.

Source and exact-package runs pass all 78 native groups: API 23, adapter 5,
Walker 27, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-09 Exchange Walker hot-update board recovery

Candidate: `f2ce-tools-3.3.0-native-ew9.mpackage`; Walker
3.4.0-native.5. API 1.2.0-candidate.3 is unchanged.

SHA-256: `263fdffba7df8da8b7e80a3e1e32a4d1bf811d4f8867dfccfe5cec8b32c32e56`.

The Exchange Walker board now explicitly renders CSS-colored labels in
Geyser `nocolor` mode, bypassing Mudlet 5.0.1's color parser. Content applied
to a hidden zero-sized Mux tab reflows when restored/revealed and again on the
next event-loop turn. The existing-tab placement path now also verifies that
the newly loaded Walker owns a live board instance. If a hot package update
removed the outgoing widgets while Muxlet retained the saved content ID, the
board is reapplied into that same tab instead of remaining black. The existing
Who/Events/Exchange host, Founder gate, bottom controls, and map/Galaxy content
remain unchanged.

The Walker suite passes 25 groups, including exact four-target Mux Settings
persistence, render-failure isolation, `0x0` hidden-tab recovery, and explicit
color-parser bypass, plus hot-reload reconstruction of an existing tab. Source
and exact-package runs pass all 76 native groups: API 23, adapter 5, Walker 25,
startup 7, topology 8, map lifecycle 1 and Galaxy
lifecycle 7. All 250 Lua checks, 32 metadata checks and 221 compiled-script/source
matches pass. No profile, gameplay command, push, release, or API policy change
is performed.

## 2026-09-09 topology capture and owned-response serialization

Candidate: `f2ce-tools-3.3.0-native-ew7.mpackage`; pair with FedHauler 1.16.6.
API 1.2.0-candidate.3 and Walker 3.4.0-native.3 remain unchanged.

SHA-256: `bf327afa910db69a284b3a68c2cfedaab990fabb93eca9e9f48646505a36c9b5`.

The reported `topology_capture` is F2CE's two-phase login sync. Automatic
topology now defers to active API/native command and navigation reservations;
a busy startup attempt reschedules without output. Capture timers are armed
before each phase's command. Timer/transport failure, disconnect and hot reload
clear topology's own state while preserving unrelated captures. Manual sync
remains explicitly available.

The paired consumer holds an existing public API command lease through owned
and automated local-market responses, preventing topology/Galaxy output from
starting inside either scan. If topology began first, it waits through both
native 15-second phase bounds, then dispatches one owned request. Persistent
contention remains fail-closed; no native guard was relaxed.

Source and compiled package pass 74 groups, 250 Lua checks, 32 metadata checks,
and 221 embedded-script/source matches. Paired FedHauler source/package checks
pass 243 tests and all 17 archive members match source. No install, gameplay,
push, release, trade-policy or Exchange Walker UI change was performed.

## 2026-09-09 Galaxy capture lifecycle and consumer handoff

Candidate: `f2ce-tools-3.3.0-native-ew6.mpackage`; pair with FedHauler 1.16.5.
API 1.2.0-candidate.3 and Walker 3.4.0-native.3 are unchanged. This patch is to
native Galaxy's capture lifecycle, not a relaxation of API contention guards.

SHA-256: `6864ae8985a06f72bf11cae9504fa9a750aa05f304e551992f06fbd6f7022e23`.

The live blocker is `galaxy_capture`; capture duration/staleness cannot be
deduced from the transcript. Native Galaxy previously sent its background
request without consulting existing reservations. It now defers to API/native
owners, arms bounded cleanup before sending, and clears its own state/gag
triggers on send/timer failure, disconnect, character change or reload. A
reload preserves the last complete index and retires its owned handlers.
No other capture is reset or navigation owner overridden.

Seven real-script lifecycle groups cover silence completion, continuous-output
maximum duration, missing/broken timers or transport, UI failure, reservation
deferral, disconnect, and reload. Consumer integration reproduces the real
Galaxy scrape overlapping a zero-owned text response: route 1 now waits at
the same target, then acquires normally after capture ends. A permanently
blocked capture stops after a bounded wait with review memory retained.

Source and compiled package pass 69 groups, 250 Lua checks, 32 metadata checks,
and 221 embedded-script/source matches. Paired FedHauler source/package checks
pass 237 tests and 17 archive/source matches. Live acceptance remains pending;
no install, gameplay, publication or Exchange Walker UI changes were performed.

## 2026-09-09 navigation completion handoff

Candidate: `f2ce-tools-3.3.0-native-ew5.mpackage`, API 1.2.0-candidate.3.
Pair with FedHauler 1.16.4. Exchange Walker remains 3.4.0-native.3; its
separately reported black-tab issue is unchanged.

SHA-256: `6203910217eb6b06d2dc8bc97a9972d3c2fa159a7088e2c23e7358475c5ec795`.

The previous API completed a navigation request as soon as the destination ID
matched, before checking native active/pending movement. Its `arrived` callback
path bypassed that check as well. Now retain the lease until speedwalking,
pending movement/arrival, exploration/circuit and customs continuation settle.
Only then release ownership and publish completion, so event subscribers see
the same released broker as the result callback. Foreign ownership remains
untouched. Native map code and map/pane contents are not changed.

New regressions cover each unsettled state, early native arrived callbacks,
and command acquisition from completion events. Consumer integration also
walks two simulated exchanges, waits before each local futures request, and
advances without contention. FedHauler separately waits at most five seconds
for temporary capture contention; persistent or foreign-owner contention stops
with explicit blocker details and preserves its checkpoint for explicit resume.
No capture reset, owner override, or trade retry is introduced.

Offline source and compiled-package checks cover 62 groups (API 23, adapter 5,
Walker 23, startup 6, topology 4, map lifecycle 1), 249 Lua syntax checks,
32 metadata checks and 221 compiled-script matches. Paired FedHauler checks
cover 182 legacy, 36 native and 13 Trader-goal tests. Live acceptance is pending;
the user's earlier message did not identify which native blocker persisted.
No live install, gameplay or publication was performed.

## 2026-09-09 premium hauling ownership correction

Candidate: `f2ce-tools-3.3.0-native-ew4.mpackage`, API 1.2.0-candidate.2.
Walker stays 3.4.0-native.3; its separately reported black-tab issue is not
claimed fixed by this package.

SHA-256: `e5e3032cf0ac8a46545d7792b7f5822831407b77c2d54771a26e5d093d89554b`.
249 syntax checks, 32 metadata checks, 221 compiled-script matches, and all
59 regression groups passed against source and compiled package (API 20,
adapter 5, Walker 23, startup 6, topology 4, map lifecycle 1). The paired
FedHauler 1.16.2 native integration suite also passes all 22 tests against
the Lua extracted from both built artifacts.

Native `f2t_hauling_start` reserves navigation owner `hauling` before invoking
price analysis. The API already borrowed the correct hauling command lease,
but its adapter still treated that stationary reservation as foreign contention.
Allow only the owned hauling-price request to share that exact reservation.
Active or pending movement, foreign owners, recovery and capture conflicts
remain denied. Ownership is neither cleared nor overwritten.

The native adapter test covers this boundary and FedHauler's real native-API
test invokes the price checker synchronously inside hauling start with the
reservation set. No live account, profile, or network gameplay is exercised.

## 2026-09-09 Exchange Walker color/settings/layout repair

Candidate: `f2ce-tools-3.3.0-native-ew3.mpackage`, Walker 3.4.0-native.3.
Native API and FedHauler are unchanged in this repair.

SHA-256: `59ffff8eb9bb71e15c8ceaba3f66b79a342db61f14b74d945dfdef960849a446`.

- 249 Lua syntax and 32 metadata checks passed.
- API 20, adapter 4, Walker 23, map startup 6, topology 4, map lifecycle 1
  groups passed: 58 total, against both source and the compiled package.
- 221 embedded scripts matched the tested source.
- Strengthening the Geyser echo mock to reject a numeric second argument
  reproduced the color crash before the patch (16 failing Walker groups).
- Exact `tempest, amsterdam, holland, denmark` Settings edits update the runtime
  four-target list, survive a mock profile reload, remain isolated from another
  profile, and send no commands until explicitly armed and started.
- An injected board repaint failure no longer interrupts settings application,
  preview invalidation, or cancellation. Target and interval defaults are visible.
- Empty and populated table geometry checked at 417x828, 643x450 and 1000x1000;
  compact/full headings, bottom controls, viewport height, sorting, header/body
  alignment, blank suppression and map/Galaxy isolation remain covered.

No live account or profile was modified; actual Qt appearance still needs a
test-profile check. This artifact does not claim to fix the separately reported
futures owned-refresh navigation issue.

## 2026-09-09 native consumer services / exchange board candidate

Candidate: `f2ce-tools-3.3.0-native-ew2.mpackage`, API 1.2.0-candidate.1,
Walker 3.4.0-native.2, pinned Muxlet v2.3.2.

SHA-256: `a64526c784fcb9c4e45253f52c34882300a113e66e7b83db6c5e85ee15cfbb13`.

- 249 Lua syntax checks and 32 JSON/manifest checks passed.
- API 20, native adapter 4, Walker 20, map startup 6, topology capture 4,
  and map content lifecycle 1 groups passed (55 total).
- 221 scripts reconstructed from compiled package XML matched source. All
  six suites passed again against those actual packaged scripts.
- FedHauler 1.16.0 companion: 182 legacy regressions and 17 actual native
  API/consumer integration tests passed against source and both built packages.
- New native coverage: load order, OFF authority, disconnect, genuine GMCP
  receipt generations and server-local/map room identity, broker release before
  arrival callback, top-20 premium provider hook, PO discovery/bulk ownership,
  low-stamina synchronous startup, in-flight movement settlement/timeout,
  foreign navigation isolation, bounded verified navigation, cancellation, and
  an already-here arrival synchronously starting the next route.
- New board coverage: Founder promotion/demotion/unknown rank; tab insertion
  without changing other tabs/maps; bottom controls; header/body pixel alignment
  after resize; signed Net colors and sorting; OFF read-only refresh; incomplete
  capture retention; cancellation; and bounded capture-only blank suppression.

No live account, installation, game command or GUI mutation was used. Geyser and
Mux behavior is exercised with mocks plus the real native table implementation;
actual Qt/Mudlet appearance and interactive lifecycle remain acceptance checks.
This candidate is not an upstream release. Native manual premium scans while a
haul is paused remain broker-blocked; use its registered premium provider flow
or stop hauling before a manual scan.

## 2026-09-09 native Exchange Walker / API 1.1 candidate

API development handoff was completed from the Build F2CE Module API task.
Work continues on `codex/native-exchange-walker`, based on `9d81fec`, in the
user's F2CE fork. No live profile, server, deployment, release, or push was used.

Candidate: `f2ce-tools-3.3.0-native-ew1.mpackage` (Walker 3.4.0-native.1;
API 1.1.0-candidate.1; pinned Muxlet v2.3.2).

SHA-256: `949CD3F4107FF21EB60605859BDC7BCE370B1B24D1ADA2EB7CE7CF6B795C9BEC`.

Build and verify with the checked-in scripts (Lua/luac 5.1.5, Muddler 1.1.0,
OpenJDK 21):

```powershell
./scripts/build-native.ps1 -MuddlerJar <muddle-1.1.0-all.jar> -JavaCommand <java.exe>
./scripts/test-native.ps1 -LuaExe <lua51.exe> -LuacExe <luac51.exe> -PackagePath <candidate.mpackage>
```

Results:

- Lua syntax: **244 files passed**.
- JSON/mfile validation: **32 files passed**.
- API suite: **20 passed, 0 failed**.
- Native adapter suite: **4 passed, 0 failed**.
- Native Walker integration: **17 groups passed, 0 failed**, including 165
  stock-policy cases verifying every intermediate min/max command is legal.
- Map startup safety: **6 passed, 0 failed**.
- Topology capture safety: **4 passed, 0 failed**.
- Map content lifecycle regression: **passed**.
- Exact compiled XML: **216 embedded scripts matched** checkout source after
  the documented Muddler metadata substitutions and dependency injection.
- All six suites were then repeated successfully against the reconstructed
  Lua from the actual package XML, not merely the staging directory.
- ZIP portable paths, required notices, native markers, pinned Muxlet URL,
  package XML parsing, and absence of the separate API loader: **passed**.
- `git diff --check`: **passed**.

New coverage includes disabled/contended API sessions; command input/range and
local ownership rejection; capture timeout, foreign callback ownership and
late callback isolation; callback-error cleanup; pruning released resources;
reconnect authority revocation; one-line/wrapped rows; wrong remote response
targets; incomplete counts; exact apply acknowledgements; no timeout retry;
Muxlet late load, visible defaults and custom validators; migration/schema
rejection and preserving native settings; explicit timer start and interval;
settings-change cancellation; duplicate-package blocking; pane 1/7/foreign
pane isolation; idempotent registration/reload/uninstall; and capture-scoped
blank suppression.

### Remaining live acceptance

The candidate has **not** been installed into Mudlet or run against the game.
Offline widget mocks do not prove Qt rendering. In a backed-up test profile,
check the real Settings form, old-to-native migration, standalone uninstall,
the default pane 15 and an existing custom layout, map/Galaxy rendering,
remote capture/preview, one explicit confirmed apply, timer start/stop, and
reconnect OFF behavior before adopting it for unattended use.

The interface hooks were inspected in Muxlet v2.2.9, but the package keeps the
existing v2.3.2 dependency; there was no live v2.2.9 installation test. No new
repository-wide lint claim is made; the older lint results below are historical.

## Historical candidate 1.0 validation

Environment: Windows, portable Lua/luac 5.1.5, LuaCheck 1.2.0, muddler 1.1.0, and Android OpenJDK 21. Validation was run on `feature/module-api-v1` after merging upstream `v3.3.0`. No game connection, profile automation, installed Mudlet package, or public server was used.

## Commands and results

Repository-wide Lua syntax (PowerShell supplied every `*.lua` path outside `build/` to luac):

```text
tools/lua51/luac51.exe -p <each Lua file>
LUAC checked=233 failed=0
```

JSON/package metadata parsing:

```text
Get-Content -Raw <each JSON file and mfile> | ConvertFrom-Json
JSON checked=31 failed=0
```

Offline API suite:

```text
tools/lua51/lua51.exe tests/api/run.lua src/scripts/api/v1.lua
RESULT 20 passed, 0 failed
API_TEST_EXIT=0
```

Native 3.3 adapter contract suite:

```text
tools/lua51/lua51.exe tests/api/native_adapter_run.lua src/scripts/api/v1.lua src/scripts/api/adapter.lua
RESULT 4 passed, 0 failed
ADAPTER_TEST_EXIT=0
```

Lint:

```text
luacheck.cmd src/scripts/api tests/api examples/module_api_v1
Total: 122 warnings / 0 errors in 6 files
LUACHECK_EXIT=1
```

The lint warnings are non-blocking style findings, predominantly long lines and unused callback arguments already present in the candidate API/test files. No undefined-variable or syntax errors were reported. The new native-adapter contract test is warning-free.

Native package build:

```text
java.exe -jar muddle-1.1.0-all.jar
MUDDLER: [INFO]: Version     : 3.3.0
MUDDLER: [INFO]: Found src\scripts\api\scripts.json
MUDDLER: [INFO]: Using script from src\scripts\api\v1.lua for script 'v1'
MUDDLER: [INFO]: Using script from src\scripts\api\adapter.lua for script 'adapter'
MUDDLER: [INFO]: XML created successfully, writing it to disk
MUDDLER: [INFO]: Build completed successfully!
MUDDLER_EXIT=0
```

The generated `build/f2ce-tools.mpackage` was opened as a ZIP and checked for `config.lua`, package XML, `1.0.0-candidate.3`, and the 3.3 adapter compatibility marker; every assertion passed. The local muddler-only artifact deliberately has no `MUXLET_URL` injection. GitHub's release workflow performs that injection before its build, so this local structural-validation artifact is not an installable release and is not committed.

## 2026-09-05 map command-safety follow-up

The 3.3-aligned branch was additionally checked after gating its automatic
login topology refresh on mapping enablement, the topology auto-sync setting,
login state, and a live connection. Minimal mode remains an intentional UI-only
choice: automatic topology refresh is permitted there when the map settings
remain enabled. Manual `map topology sync` remains available even when
automatic mapping is disabled.

```text
tools/lua51/luac51.exe -p <each Lua file outside build/>
LUAC checked=235 failed=0

tools/lua51/lua51.exe tests/map/startup_topology_sync_run.lua src/scripts/map/events.lua
RESULT 6 passed, 0 failed

tools/lua51/lua51.exe tests/map/topology_capture_safety_run.lua src/scripts/map/topology_capture.lua
RESULT 4 passed, 0 failed

tools/lua51/lua51.exe tests/api/run.lua src/scripts/api/v1.lua
RESULT 20 passed, 0 failed

tools/lua51/lua51.exe tests/api/native_adapter_run.lua src/scripts/api/v1.lua src/scripts/api/adapter.lua
RESULT 4 passed, 0 failed

Get-Content -Raw <each JSON file and mfile> | ConvertFrom-Json
JSON checked=33 failed=0

tools/muddler/expanded/muddle-shadow-1.1.0/bin/muddle.bat
MUDDLER_EXIT=0
```

The two map suites cover pre-login and disconnected startup, disabled mapping,
disabled topology auto-sync, duplicate vitals initialization, disabling while
the deferred timer is pending, cancellation before the second capture command,
fresh reconnect behavior, and preservation of an explicitly requested manual
sync. No network, game connection, profile, credentials, or installed package
was used.

## Covered behavior

The suites cover version/capability mismatch, duplicate module IDs, reload idempotence, scoped cleanup, 3.3 navigation start statuses, pending multi-leg navigation with an intermediate completion, native-owner contention and compare-and-release cleanup, interruption policy, both cancel modes, zero-command behavior after disable or native contention, built-in provider contention recheck, provider fallback/timeout/late-callback isolation, callback containment, nil/partial GMCP, reconnect reset, unload during active navigation, hauling mode validation, native hauling rejection, and service-lease release.
