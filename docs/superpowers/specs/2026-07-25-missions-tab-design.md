# Missions Tab — Design

**Date:** 2026-07-25
**Repos:** `fed2-tools` (Mudlet client) + `fed2-community` (C++ game engine)
**Status:** Approved design, pre-implementation

## Goal

Add a **Missions** display to the Mudlet package's lower-right tabbed panel. It becomes the
**first** tab, so the order is **Missions · Hauling · Price Checker**. The tab shows the
player's active missions *and* the missions they can currently accept (with an Accept button),
and lets the player click any mission to expand an inline detail view.

## Background / current state

- The engine (`fed2-community`, `master`) exposes missions to players **only as plain text**
  via `display missions` (a fixed-width, ANSI-color-coded table rendered by
  `MissionManager::RenderMissionTable` / `displayMissions` / `displayPossibleMissions`).
  There is **no GMCP feed and no `<s-*>` XML tag** for missions.
- Every other GUI panel in `fed2-tools` (Hauling, Price Checker, Company, Exchange) is driven
  by **GMCP**, not text scraping. A prior audit (2026-07-17) found the package's worst
  breakages were all text-scraping drift.
- Player commands: `display mission[s] [id]` (view) and `choose <id>` (accept). There is no
  player-facing abandon/drop.

## Decision: GMCP, not text scraping

Mission data reaches the client through a **new `char.missions` GMCP feed** added to the
engine, consumed by the client exactly like `char.vitals` / `exchange.*`. This is robust,
matches the existing architecture, and is a small, well-precedented engine change. There is
**no text-scraping fallback** — the engine change must deploy for the tab to populate.

## Scope

This is a coordinated change across two repos that ship together:

1. `fed2-community` — add the `char.missions` GMCP feed.
2. `fed2-tools` — add the Missions content module and register it as the first tab.

---

## Part 1 — Engine: `char.missions` GMCP feed (`fed2-community`)

### Payload

GMCP key `char.missions`, value is a JSON **array**, one object per *visible* mission for the
player. Two variants, distinguished by the `global` boolean.

Normal (non-global) mission:
```json
{
  "id": 18,
  "name": "A Ship in Need",
  "desc": "Get your ship repaired.",
  "type": "ONE_TIME",
  "status": "active",
  "global": false,
  "progress": {"cur": 0, "total": 1},
  "goals": [{"desc": "Repair your ship", "cur": 0, "total": 1}],
  "rewards": {"points": 1, "money": 500, "slithy": 0},
  "cycles_left": -1
}
```

Global mission (replaces flat `progress` with `community` + `your_part`):
```json
{
  "id": 30,
  "name": "Community Effort",
  "desc": "...",
  "type": "DAILY_GLOBAL",
  "status": "active",
  "global": true,
  "community": {"cur": 4200, "total": 10000},
  "your_part": {"cur": 150, "cap": 500},
  "goals": [{"desc": "...", "cur": 150, "total": 500}],
  "rewards": {"points": 3, "money": 0, "slithy": 0},
  "cycles_left": 1
}
```

Field notes:
- `status` ∈ `active` (accepted, in progress), `available` (offered, not yet accepted),
  `completed` (finished this cycle, still shown).
- `type` = the `Mission::TYPE` enum name (`ONE_TIME`, `RANK`, `DAILY_TASK`, `DAILY_SOCIAL`,
  `DAILY_GLOBAL`, `ASSIGNABLE`, `CHAIN`; `SECRET` is excluded — see visibility).
- `cycles_left` = `-1` when the mission does not expire (`expire_after_cycles() == 0`),
  otherwise the remaining cycles (same value the text path shows).
- **No `hint` field.** Hints are only obtainable from a secret in-game location and must not
  be exposed to the client.
- Global vs normal: normal missions carry `progress` and omit `community`/`your_part`; global
  missions carry `community`/`your_part` and omit `progress`. Available globals still send
  `global:true` with the current community aggregate and `your_part.cur = 0`.

### Visibility (mirror the text display exactly)

Include the same missions the text renderer includes:
- accepted (`active`), offered (`available`), and just-`completed` missions.

Exclude:
- anything `hidden_until_started()` or `hidden_until_complete()`,
- `SECRET` type.

This guarantees the tab never leaks hidden or secret missions, and that the tab and
`display missions` always agree.

### Global-mission correctness

The builder reuses the **exact accessors the text renderer already uses** so the tab and
`display missions` cannot diverge:
- `updateGlobalTrackerCounts()` to refresh the aggregate,
- the aggregate `_global_trackers[mid]` total for `community.total`,
- the aggregate current for `community.cur`,
- the per-player tracker `getGoalTotal()` for `your_part.cur`,
- `personal_global_cap()` for `your_part.cap`.

### Mechanism (follows `FedMap::SendGMCPExchangeSnapshot` precedent)

1. Add `MISSIONS` to the GMCP type enum in `include/fed_telnet.h` (before `MAX_GMCP_TYPES`;
   index must stay < 256 for magic_enum safety elsewhere — verify).
2. Add `MissionManager::SendGMCPMissionsSnapshot(Player *player)` (or equivalently a
   `Player::GMCPMissions()` builder invoked from `FedTelnet::SendGMCP(MISSIONS)` — choose the
   form that best matches the surrounding code once implementing). It:
   - builds the JSON array (with a **string-escape helper** — mission names/descriptions
     contain apostrophes and `&`; JSON requires escaping `"` and `\` and control chars),
   - sends it via the player's telnet, gated on `WantsGMCP()`.
3. Emit points:
   - login — add `MISSIONS` to `SendAllGMCP()`,
   - after `acceptMission` success,
   - once at the end of `track()`, **only if the player's mission state actually changed**
     during that call (new auto-accept, progress advanced, completion, or a new offer became
     available). Use a dirty flag so we do not emit GMCP on every unrelated game event
     (`track()` runs per event).

### No version bump

Do **not** bump `Fed::version`. (Per user instruction for this change.)

---

## Part 2 — Client: the Missions tab (`fed2-tools`)

### Registration & tab placement

- New content module `src/scripts/ui/content/missions.lua`, registered as content id
  `fed2_missions` via a `F2T_CONTENT_REGISTRARS` entry (mirrors `hauling_jobs.lua`).
- Add `{"name": "missions"}` to `src/scripts/ui/content/scripts.json`.
- Insert a tab entry **first** in the `tabs` array of the `RightBottom` pane in
  `src/resources/full.lua` (`_activeContent = "fed2_missions"`, `name = "Missions"`,
  `nameAlign = "center"`, plus the standard disconnected/connecting overlay rules copied from
  the sibling tabs). Optionally set the pane's `activeTabName = "Missions"`.
- **Always visible** — no rank/cert gating condition (missions are core content). When the
  player has none, show empty-state text.
- `full.lua` is a generated Muxlet workspace export; the tab entry will be hand-edited to the
  documented shape (array order + entry fields). Note for maintainers: future layout changes
  are normally made in-game and re-exported.

### Data flow

- `registerAnonymousEventHandler("gmcp.char.missions", ...)` stashes the array in module state
  and debounce-redraws any open Missions panels (same pattern as `exchange.lua`).
- Accept is fire-and-forget: `send("choose " .. id)`. The panel refreshes when the engine
  re-emits `char.missions` after the accept.

### List view (two stacked sections in one scroll)

- **Active** section: each row shows name · status · progress.
  - Normal: `cur/total`, color-coded like the engine (`MakeColorNumericDisplay` semantics).
  - Global: `Community cur/total` + `Your part cur/cap`.
  - Row click → inline detail.
- **Available** section: each row shows name · type · an **Accept** button
  (`send("choose <id>")`). Row click → inline detail.
- Empty state when both sections are empty.

### Inline detail view

Clicking a mission replaces the list within the tab (a `‹ back` control returns to the list):
- full description,
- each goal with its `cur/total`,
- for globals, the `Community` and `Your part` lines,
- reward breakdown (points / money / slithy),
- an **Accept** button when `status == available`.

### Styling

Match the Hauling / Price Checker panels: shared `CELL_FONT`, header-bar gradient, panel
background, column-header CSS, and the action-button CSS. Use the existing color palette
(link/number `#7aa2ff`, good `#00cc44`, bad `#ff5555`, muted `#888888`, etc.).

---

## Testing

- **Engine (doctest, `tests/`):** unit-test the JSON builder:
  - required fields present for a normal mission,
  - string-escaping of a name containing an apostrophe (and `&`),
  - hidden/secret missions excluded,
  - global-mission shape (`community`/`your_part` present, flat `progress` absent) and normal
    shape (inverse),
  - `cycles_left == -1` for non-expiring missions.
  Follow the existing mission-test helpers (`ScopedPlayerIndex`, `makeMission`, `TestPlayer`).
- **Client:** no Mudlet unit harness. Verify end-to-end: build `fed2d`, connect via telnet,
  and drive the tab — accept an available mission, watch it move to Active and progress update,
  open the inline detail, confirm a global mission renders community + your-part. (The `run`
  skill covers launching the engine locally.)

## Deployment / ordering note

GMCP-only means the engine change must be live for the tab to show data. Deploy the engine
change; the client tab degrades to its empty state against an engine that hasn't shipped it
yet (no errors, just no rows).

## Open items (defaulted, revisit if needed)

- Missions tab always visible (not gated). 
- Accept available from both the available-list rows and the inline detail view.
