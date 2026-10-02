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
and `nav <destination>` (and the Hauling panel's Start button) are refused
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
| `f2tSpeedwalkFinished` | `result, roomId, settled` | A walk ended. `result` is `"completed"`, `"stopped"` or `"failed"`. `settled` is `false` when navigation is still working toward the destination (a recovery leg or a self-healing exploration started from this one), so wait for a settled event before acting on the result. |
| `f2tHaulingStatusChanged` | | Hauling was started, paused, resumed or stopped |
| `f2tStockpileChanged` | | A stockpile preview, update or setting changed |

## Useful entry points

These are the functions F2CE-Tools' own commands call. All of them report back
through a callback, so you don't need to watch game text yourself.

**Navigation**

```lua
local status = f2t_map_navigate("Earth exchange", {
    on_result = function(ok, status) end,  -- fires exactly once
})
-- status: "walking", "arrived", "pending" or "failed"
```

`on_result` reports whether the walk *started*. To know when it ends, use
`f2tSpeedwalkFinished`. Stop a walk with `f2t_map_speedwalk_stop()`.

**Trading** (at an exchange)

```lua
f2t_bulk_buy_start("alloys", 10, function(commodity, lotsBought, status, errorMessage) end)
f2t_bulk_sell_start("alloys", nil, function(commodity, lotsSold, status, errorMessage) end)
f2t_bulk_sell_start(nil, nil, function(_, lotsSold, status) end)  -- sell the whole hold
```

`status` is `"success"` when at least one lot traded. Short commodity names
(`petros`, `semis`) are accepted.

**Prices** (needs a remote-access certificate)

```lua
f2t_price_check_commodity("alloys", function(commodity, rows, analysis) end)
```

**Planet owners**

```lua
f2t_po_capture_exchange("Tempest", function(rows) end)       -- parsed "display exchange"
f2tStockpilePreview("Tempest", function(plan, err) end)
f2tStockpileApply(function(ok, err) end)
```

**Hauling**: `f2t_hauling_start(mode)`, `f2t_hauling_pause()`,
`f2t_hauling_resume()`, `f2t_hauling_stop()`.

## Stability

The control functions and events above are the supported surface and will
keep their names and arguments within the 3.x series. Other `f2t_*` functions
are what F2CE-Tools uses internally. They are fine to call, but they can
change between releases, so pin the F2CE-Tools versions you've tested against.
