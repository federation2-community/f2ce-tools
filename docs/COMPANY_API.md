# Company inspection API (native-ew20)

## Owned commodity exception (native-ew46)

Feature marker `API.company.factoryOwnedCommodityVersion=1` supports optional
`allow_owned_commodity=true` alongside `exclude_existing_commodity=true` in
factory proposals. Without that opt-in, the previous all-company duplicate
exclusion remains unchanged for older consumers.

With opt-in, a public matching factory is exempt only when its owner matches
the current company AND its numbered slot, planet and output match the fresh
owned roster. Missing public ownership or roster disagreement is rejected.
Another company's matching commodity still blocks construction. A different
commodity (for example foreign NanoFabrics when building TQuarks) does not.
At most two owned factories total are allowed per planet, including manual
opt-in builds. Automation may configure a stricter one-factory limit. Fresh
stock, output bid, reserved workers, cash, depot, wage and journal checks remain
separate and unchanged. This permits ONE factory per confirmed API operation,
not two purchases under one confirmation.

FedHauler 1.17.39 uses batches of ten with independent validated recovery on
report failure. The underlying batch API remains strict/all-or-nothing and
does not publish unfenced partial results; healthy earlier batches survive in
the consumer's pass-scoped cache. Authority/refusal errors are never retried.

## Batched planning inspection (native-ew45)

Optional feature marker `API.company.planetBatchVersion=1` exposes
`API.company.planets(context, targets, callback)`. Pass an ordered array of
1..100 unique `{planet="Example", system="Elsewhere"}` targets. The returned
cancellable handle uses the normal module-owned broker lease; it cannot borrow
a purchase lease. Each target and each send require `company.planet.inspect`
authorization. Completion returns `{reports={...}, captured_at=...}` with
ordered reports in the existing `planet` result format.

Send the first `di planet` only, then issue the next request when the current
expected header arrives. That next header fences the preceding planet report.
After the final planet header, send one `di business` (Industrialist) or
`di company` (Manufacturer). The last report requires the ordered company text
header AND an actual company GMCP receipt after that final command was sent.
GMCP alone is never proof of a complete public factory list. Parsing still
validates workforce and factories belonging to every company.

Bounds: 15 seconds per expected response/fence, 120 seconds overall, 1 MiB per
batch and the existing per-report parser/line limits. Incomplete, malformed,
out-of-order or identity-changing responses fail the entire batch without
partial eligible results or retries. Cancel/disable removes observers, timers,
subscription and command ownership; late replies cannot continue the chain.
This is for planning only: `planet`, `system` and borrowed purchase checks are
unchanged. Consumers must obtain fresh transaction evidence before spending.

## Single-factory preview/confirmation (native-ew27)

Capability `company.factory.build` exposes
`API.company.prepareFactory(context, options, callback)` and a cancellable
handle with `status()` / `confirm(callback)`. Required options:

```lua
{planet="Example", system="Elsewhere", commodity="Firewalls",
 company_reserve=1000000, labour=150, biological_required=false,
 output_price_floor=800,
 inputs={{commodity="Semiconductors", required=20, minimum_stock=5000,
          price_limit=300}}}
```

These are reviewed bounds, not API-calculated recipes/profit. At most six inputs;
minimum stock is at least 5,000t each. Require Industrialist/Manufacturer at the
selected non-Sol exchange, valid owned company/factory roster, an empty rank slot
(8/15), and the source-derived 2m cost without breaching the explicit reserve.
No public-server rule change or guarantee of future factory funding is implied.

Preview and confirmation both obtain fresh room/stamina/commodity GMCP via
`score`/`look`, then workforce and owned company via an ordered system read on
the SAME broker lease. Validate workers, economy/visitor access, stock, input
ask ceilings, output bid floor, healthy stamina and inactive recovery. Reject
changed owner/rank/location; confirmation also rejects roster changes. A ready
preview holds the lease and expires after 30s; read phases have 15s deadlines.

Authorize `company.factory.preview` for reads. Immediately before the purchase,
authorize `company.factory.buy` with copied options plus `proposal` (owner, CEO,
rank, planet/system, commodity, slot, cost, cash, reserve, workforce). **Consumer
must persist intent at this authorization boundary before returning true.**
The API sends one `buy factory <commodity>`, requests the rank-specific company
report and requires a fresh snapshot with exactly one matching added slot and
an exact 2m debit. Concurrent company spending can leave the result unresolved.
Success returns `confirmed=true` and post-purchase `company_cash`; the consumer
must persist completion. Post-send errors use `E_FACTORY_UNCONFIRMED`; status
exposes `sent`/`uncertain`. Never replay an uncertain purchase. No navigation,
batch building, promotion or module startup authority is provided.

## System workforce inspection (native-ew26)

Capability `company.system.read` exposes
`API.company.system(context, systemName, callback)`, authorized as
`company.system.inspect` with `{system=systemName}`. It holds one command lease
across `di system <systemName>` and the rank's `di business` / `di company`.
Both the matching report text and fresh owner-bound GMCP must arrive before
completion. Silence is never successful completion; timeout is 15 seconds.
Cancel/disconnect/unload remove observers, timers and the lease before callback.

The result is `{system, captured_at, planets}` keyed by lowercase planet name.
Each entry has `planet`, `system`, `economy`, `available`, `total`, and `closed`.
Economy None has no workforce values. Parse rejects missing/duplicate workers,
unknown economies, impossible counts, conflicting identities and partial
reports. Validates all planets in the response, with a 256-planet / 128KiB bound.
Additional infrastructure/approval fields are not interpreted. This read does
not use/enable navigation's capture flags, explore, gag output, or reserve labour.
Available workers are a snapshot, not a hiring guarantee or build permission.
ew27 starts capture only at the exact requested system header, ignoring trailing
text from earlier commands whose GMCP arrived first. Missing headers time out;
the owned text/GMCP completion fence and strict report validation still apply.

## Original inspection contract

`F2CE.API.v1` 1.2.0 candidate.4 adds `company.read` and the `company` GMCP
channel (`char.company`, `data.company`). This is read-only groundwork, not
an autonomous company manager or an upstream-approved release.

- `API.company.snapshot()` returns a copied company/business snapshot and
  receipt, or an error. It checks current GMCP character, CEO and rank.
- `API.company.refresh(context, callback)` requests `di business` at
  Industrialist, `di company` at Manufacturer/Financier. Only an actual new
  GMCP push completes the read; refreshing a cache does not.
- `API.company.inspect(context, number, callback)` requires that factory in
  the owned company snapshot. It sends `display factory <number>` and accepts
  only a complete, validated display for that company and slot. The pure
  native factory parser preserves input names, required/available tons,
  shortfall, output storage, disposal, workers, efficiency and progress.
  Reported accounting profit is separate from current income minus expenditure.

Requests require an enabled context with an explicit `authorize` callback for
`company.refresh`/`company.inspect`. They return a cancellable handle and hold
the command broker until response, cancellation or a 15-second timeout. A
callback receives `(value, error)` after cleanup/release. Disconnect/unload
cancels outstanding work. Inputs are never inferred from missing GMCP fields.
This reader does not gag unrelated output or alter Mux panes.

The original ew20 inspection contract exposes no spending. Later explicit
transfer/cargo/build operations are documented separately below/above. Existing
native panels remain unchanged; unattended growth toward 100m and automatic
promotion, repairs or dividends are not provided.

## PO stamina change

Protection clients may declare `isSettlingCommands()`. When pausing, a true
result permits only the already-existing command lease owned by that same
module to drain. The existing movement-settle gate waits for both movement and
that lease, bounded to ten seconds. New or foreign leases fail closed. Clients
must cancel their read captures and must not issue follow-on work during pause.
FedHauler 1.17.10 records cargo confirmations while suspended, then freshly
revalidates delivery after food recovery. No literal `yes` is sent by this API.

## Offline checks

Run `lua tests/api/company_run.lua`, `lua tests/api/run.lua` and
`lua tests/api/native_adapter_run.lua`. Consumer integration and food-handoff
regressions run in FedHauler's `tests/test_native_f2ce.lua` against this tree.
Synthetic factory fixtures follow `Factory::Display` in the game server source;
no account profiles or live transactions are part of these tests.
