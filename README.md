# F2CE-Tools

> **Native integration candidate in the ralphcma fork:** this branch includes
> Exchange Walker and `F2CE.API.v1` 1.2.0. It is not an upstream-approved release.
> All Walker preferences are in **Muxlet Settings → F2CE-Tools → Exchange Walker**.
> Read the [migration, defaults, build and licensing notes](docs/module-api/NATIVE_EXCHANGE_WALKER.md)
> before installing. In-game/MPR installation described below still delivers the
> community package, not this candidate. No separate Walker/API package is needed
> for native Walker or FedHauler 1.16.0. Walker adds a Founder+ tab beside
> Who/Events/Exchange, with a sortable remote exchange table and bottom controls.

Native candidate **ew45**, with **FedHauler 1.17.38**, reduces factory planning
report traffic: up to 100 public planet inspections share one final company
report instead of issuing a company report per planet. Requests are pipelined
one header at a time, with bounded timeouts, strict report validation and
rank-correct `di business` / `di company` completion. Purchase, depot and wage
verification retain their existing fresh checks. See the
[company API](docs/COMPANY_API.md) for the optional planning-only batch method.

Included from **ew44**, with **FedHauler 1.17.31**: validated
per-session Premium Hauler settings without changing F2CE's saved global
preferences. A caller may set the maximum accepted cartel customs rate and a
bounded commodity exclusion list; native validation occurs before command
authority is acquired. The default remains 5%, and ordinary hauling is
unchanged. Factory automation also accepts the caller's validated wage,
factory-total and per-planet limits within the game's existing safety bounds.

The mapper adds `map explore galaxy full`. Unlike the existing brief galaxy
sweep, full mode exhausts the frontier of every system-space area and every
reachable planet surface. It uses each authoritative `di system` roster,
recognizes orbit routes reached through `in`, `out`, `up`, or `down`, reports
unreachable planets instead of stalling, and stores full-area completion in the
Mudlet map database. Re-running the command therefore skips completed areas and
resumes unfinished ones across reconnects and package replacement. `map explore
galaxy` and `map explore galaxy brief` retain the original brief behavior.

Included from **ew43**, with **FedHauler 1.17.30**: a persistent cartel
customs policy to Premium Hauler. On the first premium run of a connection it
reads every mapped cartel with `di cartel`, suppresses the captured reports, and
excludes the cartel hub and all member systems when customs are **above 5%**.
Exactly 5% remains eligible. The last complete policy is saved in Mudlet map
userdata, so reconnects and package replacement do not temporarily restore
excluded routes; an incomplete scan fails closed.

New purchases still require the configured margin. Once cargo is aboard, however,
delivery no longer has a profit floor: the best positive off-world bid is used,
then retained buyers and one exceptional refresh are exhausted if necessary.
Bonded cargo is never routed back to its origin planet. Each actual sale remains
one bay at a time and requires a fresh local quote, an exact receipt and cargo
GMCP reconciliation. A zero/non-buying bid, uncertain receipt or exhausted buyer
list still stops with the cargo preserved.

Included from **ew42**: Premium Hauler is limited to the **21 highest fixed
base-price commodities** without a 21-request scan burst at cycle start. Gold
and Tracers are both included at the 600ig cutoff. Each commodity is scanned when
its saved turn begins to select a supplier, then once more after the counted bulk
purchase to choose a buyer. Existing saved attempts carry over, and each selected
commodity gets one attempt before another round. Ordinary hauling and manual
price-all retain all 67. Update both packages while stopped; loading starts no
automation.

Included from **ew39**: both ship-sale receipt wordings ("sold for"
and "sold to the exchange for"). A preceding cartel-customs notice, including
wrapped continuations, supplies net proceeds for accounting and the cost guard;
the customs notice alone cannot confirm a sale. Mismatched/incomplete notices
stop without retry or a gross-as-net fallback. Hauling still reconciles the
text receipt with ship cargo GMCP before another sale. Source and packaged
trigger patterns are checked against the reported live wording and legacy forms.

Included from **ew38**: counted purchases when GMCP runs ahead of text
receipts. A full hold no longer completes a multi-bay buy after its first receipt:
all requested receipts (or an explicit terminal refusal/error) are required.
If receipts arrive before cargo GMCP, exchange hauling waits up to five seconds
for the matching cargo instead of immediately failing. Pause/resume cannot resend
the in-flight buy. Missing receipts/cargo still stop safely without retrying.
Counted bulk commands, exact receipt accounting, and saved rotation are retained.

Included from **ew37**: the incremental Who-tab updates from local
commits `2bc5bf6` and `a3c4508`: unchanged player feeds do not refresh consumers,
changed player rows are updated in place where safe, and repeated updates are
coalesced. Membership/sort changes and legacy or malformed events fall back to
a full refresh. Exchange Walker's custom table headers and viewport resizing
remain intact. This combined native package retains the API, Walker, company,
navigation and hauling work; it is not the standalone upstream-based Who build.

Included from **ew36**: a saved, per-profile rotation (67 commodities for ordinary
hauling; the selected 21 for FedHauler premium mode starting in ew41):
one load/attempt per commodity before starting another round. An ordinary full
market review considers all 67, while ew42's premium rotation queues its fixed
catalog without polling it in advance. Unavailable/unprofitable or excluded goods
are skipped and do not substitute lower-base commodities.
Progress is saved before travel in two verified `f2ce-hauling-rotation-v1-*.json`
files in the profile root, outside the package folder. Stops, reconnects and
package replacement preserve progress; load/reconnect never starts automation.
An interrupted attempt counts as attempted, so restarting does not hammer it.
Use `haul rotation` to inspect progress. A failed save blocks further travel;
one corrupt copy can recover from the other, but two invalid copies require
repair rather than silently restarting the rotation. This is per profile, not
a cross-account hauling coordinator.

The price API/table setting accepts up to **50 buyers and suppliers**;
FedHauler 1.17.28 requests that limit. Routing still searches the full filtered
market beyond those shortlists. Counted bulk purchases are retained, with costs
summed from actual server receipts. **All exchange hauling sales**, including
the original buyer, require a fresh positive local bid and sell one bay at a
time; no profit floor applies after purchase. Completed-load/session results use actual
receipts, not cached quotes or an extrapolated first-bay cost. Existing unexpected
cargo is preserved, never dumped or jettisoned to start a new purchase.

Exchange/premium hauling refusal handling:
Galactic Administration sale restrictions and not-buying/not-selling replies
advance immediately to an eligible cached alternative, without waiting for the
15-second bulk watchdog. Refused locations are excluded for that commodity and
trade direction until the next commodity pass; they are not map blacklists.
Routing uses the full, policy-filtered price response, not the UI's bounded
shortlist. An exhausted cache gets one price refresh. No remaining supplier skips
the commodity. New purchases retain their margin checks; already-owned recovery
cargo clears at any positive off-origin bid. Recovery checks a fresh,
current-room bid and sells one bay at a time, waiting
for both its cargo reconciliation and a new quote before another sale. A cleared
load advances to the next commodity. No eligible buyer leaves cargo aboard with an explanatory stop
message. Uncertain timed-out trades stop without retries. The server does not
offer an atomic minimum-price order: if a concurrent change beats the last local
quote, its actual net receipt is recorded and the remaining load is re-evaluated.

A Mudlet package for [Federation 2 Community Edition](https://federation2.com) — mapping, navigation, automated trading, factory management, planet-owner tools, and quality-of-life automation, with an optional [Muxlet](https://github.com/tmtocloud/Muxlet)-based GUI.

Independent packages should use Muxlet's `Mux.registerContent` for visual content and workspace integration. For behind-the-scenes F2CE features—such as navigation, hauling, prices, copied game state, and map queries—they should use the versioned `F2CE.API.v1` boundary instead of reading or replacing `F2T_*`/`f2t_*` implementation globals. See the [module API architecture](docs/module-api/ARCHITECTURE.md), [reference](docs/module-api/API_REFERENCE.md), and [example module](examples/module_api_v1/example_module.lua).

![F2CE-Tools Muxlet GUI](screenshot.png)

## Installation

**Recommended: install from in-game.** Log in to F2CE with Mudlet and, the first time the game doesn't see F2CE-Tools installed, it'll prompt you to type `f2t on` — that delivers the package straight from this repo's latest GitHub release to your client automatically, no manual download needed. If you'd rather not be asked, `f2t off` dismisses the prompt (you can still trigger delivery any time by typing `f2t on` yourself).

Alternate install methods, if you'd prefer:

- **Mudlet Package Repository:** run `mpkg install f2ce-tools` in your F2CE profile — Mudlet fetches the latest release directly from the [Mudlet Package Repository](https://github.com/Mudlet/mudlet-package-repository).
- **Manual:** download the latest `f2ce-tools.mpackage` from [Releases](../../releases), then in Mudlet open **Package Manager** and install it into your F2CE profile.

Once installed, `f2t on`/`f2t off` stop talking to the server and instead control whether F2CE-Tools' own Muxlet UI is running (see [Choosing a startup mode](#choosing-a-startup-mode) below) — the in-game delivery prompt only ever appears pre-install.

F2CE-Tools installs [Muxlet](https://github.com/tmtocloud/Muxlet) automatically the first time it loads — Muxlet powers the optional GUI panels below, no separate step needed. Everything else (mapping, hauling, factory tools, etc.) works without it.

### Choosing a startup mode

On first load F2CE-Tools asks how you'd like Muxlet to start. Pick whichever fits how you play — you're not locked in, and every command/alias works the same regardless of mode:

- **Full (recommended)** — loads the ready-made f2ce-tools workspace (output pane and map side by side, plus the panels below) automatically every session. Some panels appear only when they're relevant to you: the Company tab only shows at Industrialist rank and above, its Investment sub-tab only at Financier, and the Exchange pane swaps itself to Futures Market depending on your rank and room — all driven by Muxlet's condition/rule engine, no manual toggling needed.
- **Build Your Own Workspace (BYOW)** — Muxlet starts on a blank canvas with every F2CE-Tools panel registered and ready to drop into any pane or tab from its **Content Library**. Same building blocks as Full, but you lay them out yourself — and if you want the same rank- or room-based show/hide behavior Full gets for free, you can wire it up with your own Muxlet condition rules.
- **Minimal** — no changes to your Mudlet layout at all. Run `mux start` any time later (then `mux workspace load f2ce-tools` for the full layout) if you change your mind.

### Staying up to date

F2CE-Tools checks for new production releases on startup by default and offers to install them — this applies regardless of which startup mode you picked above. Pre-release/dev builds are never offered unless you opt in. Both are configurable under **F2CE-Tools › Update** in Settings, along with a "Check for updates now" button.

## Getting Started

Run `f2t` for a full command overview, or `f2t status` to see which components are enabled. Every component also takes its own `help`, e.g. `map help`, `haul help`, `factory help`.

## Features

**Mapping & Navigation** (`map`, `nav`)
Automatic room-by-room mapping as you move, syndicate/cartel/system galaxy topology tracking, saved destinations, speedwalk navigation by name/hash/room ID, planet and system exploration (single room, planet, system, cartel, syndicate, or full galaxy), manual room/exit editing, special exits (arrival commands, circuit travel like trains and shuttles), and map import/export.

Use `map explore galaxy full` to walk every reachable system-space and planet
surface. The command is resumable; `map explore galaxy` remains the faster
flag-oriented brief sweep.

**Automated Trading** (`haul`)
Rank-aware automated commodity trading: analyzes exchange prices, buys low, sells high, and repeats across a queue of profitable commodities. Supports Exchange mode and rank-gated modes (Armstrong Cuthbert, Akaturi merchant runs), with configurable profit margins and pause behavior.

**Factory Management** (`factory`, `fac`)
Status table for all your factories, one-command flush-to-market, and settings for automatic pre-reset flushing.

**Planet Owner Tools** (`po`)
Exchange economy breakdowns for your planets, filterable by commodity group.

**Commodities** (`bb`, `bs`, `price`)
Bulk buy/sell at the exchange and cross-cartel price analysis to find the best deals.

**Stamina & Refueling**
Automatic stamina monitoring with food-run automation (or a yes/no prompt in standalone use), and GMCP-driven automatic ship refueling with an emergency out-of-fuel trigger.

**Death Protection**
Tracks your last safe room and halts other automation (hauling, exploration) on death so you don't wake up mid-cycle.

**Chat History** (`f2t chat`)
Persistent, searchable com/tell/say history that survives reconnects.

## Muxlet GUI Panels

With Muxlet installed, F2CE-Tools adds these panels to the Content Library:

- **Galaxy Navigator** — browse every syndicate, cartel, system, and planet; click to travel
- **F2CE Map** — the live Mudlet mapper
- **Company** — overview, factories, financials, and portfolio (Financier+) as separate panes
- **Exchange** — live prices (or futures for Traders/Financiers) with a ticker
- **Futures Market** — contracts on offer and your open positions, with profit scoring
- **Price Checker** — cartel price scanning for the best profit
- **Commodities** — reference table of names, codes, and base prices
- **Cargo** — live ship manifest
- **Hauling Jobs** — Armstrong Cuthbert job board with route distance and effective pay
- **Player Info** — rank, fuel, stamina, groats, slithies, and hold at a glance
- **Chat** — com/say/tell history with filters and timestamps
- **Who** / **Local Players** — online and in-room player lists

## Acknowledgments

- **Colborn (ping65510)** — original creator of F2CE-Tools.
- **Swift ([Ohmi02/Fed2](https://github.com/Ohmi02/Fed2/))** — original idea for the multi-window UI layout (exchange/stats/mapper/chat split panes), later merged into F2CE-Tools.
- **tmtocloud (jackrungh)** — took over maintenance from Colborn, merged in Swift's UI layout, and has since rewritten most of the codebase.
