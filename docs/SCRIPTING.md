# Scripting F2CE-Tools from another package

F2CE-Tools has no separate API layer. A package that wants to automate play
calls F2CE-Tools' own functions, the same ones its commands and panels use,
and claims **control** so the player's commands don't start a competing
automation in the middle of its run.

Everything here is available from F2CE-Tools 3.4.0. Check the installed
version with `getPackageInfo("f2ce-tools", "version")`.

## Control

```lua
local ok, why = f2tControlAcquire("mybot", "hauling Sol loop")
if not ok then
    cecho("mybot can't start: " .. why .. "\n")  -- e.g. "hauling is running"
    return
end
-- ... drive f2ce-tools ...
f2tControlRelease("mybot")
```

| Function | Returns | Notes |
|---|---|---|
| `f2tControlAcquire(owner, reason)` | `true` or `false, why` | Refused if another package holds control, or if one of F2CE-Tools' own automations is running (hauling, exploration, navigation, bulk trading, a planet or price capture, a stockpile update). Calling it again as the current owner is fine and updates `reason`. |
| `f2tControlRelease(owner)` | `boolean` | Only the current owner can release. |
| `f2tControlOwner()` | `owner, reason, since` | `nil` when the player has control. |
| `f2tControlNativeActivity()` | `string` or `nil` | Name of the F2CE-Tools automation currently running. |

While a package holds control, the player's `haul start`, `map explore ...`
and `nav <destination>` (and the Commerce panels' Haul menu) are refused
with a message naming the package. Stop, pause, resume and status commands
still work. Your package's own calls are never blocked.

The player can take control back at any time with `f2t control release`.
That stops any walk in progress and raises `f2tControlRevoked`. **Your
package must stop when it sees that event.**

Control is not cleared on disconnect or reload; release it yourself when your
run ends.

## Events

Register with `registerAnonymousEventHandler(name, fn)`.

| Event | Arguments | When |
|---|---|---|
| `f2tControlChanged` | `owner` (`nil` once released) | Control was acquired, released or revoked |
| `f2tControlRevoked` | `owner, reason` | The player took control back |
| `f2tNavStarted` | `owner, destination` | A trip began |
| `f2tNavFinished` | `owner, status, roomId, reason` | A trip ended. `status` is as for `f2tNav.go`'s `onDone` below |
| `f2tHaulingStatusChanged` | | Hauling was started, paused, resumed or stopped, moved to a new phase, or its mode setting changed |
| `f2tStockpileChanged` | | A stockpile preview, update or setting changed |

## Useful entry points

These are the functions F2CE-Tools' own commands call. All of them report back
through a callback, so you don't need to watch game text yourself.

**Navigation**

Everything that moves the player goes through `f2tNav`, F2CE-Tools' own
hauling and commands included. It gets from where the player stands to any
real place, exploring and jumping through unmapped space on the way when it
has to.

```lua
f2tNav.go("Earth exchange", {
    owner  = "mybot",
    onDone = function(result) end,  -- fires exactly once, when the trip is over
})
```

The destination is anything `nav` accepts: `<planet> exchange` (or any other
room flag), a planet, `<system> link`, a room id or hash, a saved destination.
`result.status` is one of:

| Status | Meaning |
|---|---|
| `"arrived"` | The player is there |
| `"stopped"` | The trip was stopped (`f2tNav.stop`, `nav stop`, the player stopping its exploration) |
| `"unreachable"` | Navigation couldn't get there; `result.reason` says why |
| `"superseded"` | Another trip started; `result.by` names its owner |

`result.roomId` is where the player ended up. One trip runs at a time: a new
`go` ends the current one as `"superseded"`.

| Function | Notes |
|---|---|
| `f2tNav.stop(owner)` | Ends the trip as `"stopped"`; with `owner`, only a trip that owner started |
| `f2tNav.pause()`, `f2tNav.resume()` | |
| `f2tNav.status()` | `nil`, or `{owner, destination, paused}` for the trip under way |
| `f2tNav.busy()` | `true` while anything is moving the player |

**Trading** (at an exchange)

```lua
f2t_bulk_buy_start("alloys", 10, function(commodity, lotsBought, status, errorMessage) end)
f2t_bulk_sell_start("alloys", nil, function(commodity, lotsSold, status, errorMessage) end)
f2t_bulk_sell_start(nil, nil, function(_, lotsSold, status) end)  -- sell the whole hold
```

`status` is `"success"` when at least one lot traded. Short commodity names
(`petros`, `semis`) are accepted.

**Prices** (needs the Remote Price Check Service)

```lua
f2t_price_check_for("mybot", "alloys", function(commodity, parsed, analysis, err) end)
f2t_price_check_for("mybot", "alloys", callback, "galaxy")   -- Premium Ticker, every open planet
f2t_price_get_all_data(function(results, err) end, { owner = "mybot", maxAge = 600, scope = "cartel" })
f2t_price_cancel_all("mybot")   -- withdraw your own pending checks and scan
```

Checks queue and run one at a time, shared with F2CE-Tools' own hauling and
panels, so they never read each other's output. `parsed` and `analysis` are
always tables (empty on failure); `err` names why a check failed (no
subscription, Sol, no reply). `maxAge` lets a scan finished within that many
seconds answer instead of a new one.

The `cartel` scope (the default) uses the cartel check, or in Sol the
Upgrade's system check from outside an exchange, else the Premium Ticker
filtered to the cartel; `galaxy` needs the Premium Ticker.
`f2tPriceServices()` reports which services the player owns and
`f2tPriceRemoteForm(scope)` whether a check can run from where they stand.
`f2tPriceCached(commodity, scope)` returns the last result anyone got, and
`f2tPriceUpdated` (commodity, scope) fires on each one.

**Planet owners**

```lua
f2t_po_capture_exchange("Tempest", function(rows) end)       -- parsed "display exchange"
f2tStockpilePreview("Tempest", function(plan, err) end)
f2tStockpileApply(function(ok, err) end)
```

**Hauling**: `f2t_hauling_start(mode)` (`mode` is `ac`, `akaturi`, `exchange`,
`planet` or `deficit`; `nil` uses the player's `haul mode`), `f2t_hauling_pause()`,
`f2t_hauling_resume()`, `f2t_hauling_stop()`. `f2tHaulingSnapshot()` returns the
current run state, mode, phase and session totals.

## Stability

The control functions, `f2tNav` and the events above are the supported surface and will
keep their names and arguments within the 3.x series. Other `f2t_*` functions
are what F2CE-Tools uses internally. They are fine to call, but they can
change between releases, so pin the F2CE-Tools versions you've tested against.
