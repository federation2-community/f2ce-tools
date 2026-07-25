# Missions Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Missions" tab (first, before Hauling and Price Checker) to the fed2-tools Mudlet GUI that shows a player's active and available missions with an Accept button and a click-through inline detail view, fed by a new `char.missions` GMCP feed added to the fed2-community engine.

**Architecture:** The engine (`fed2-community`) gains a `char.missions` GMCP feed built in a new pure-serialization unit (`MissionGMCP`), wired through `MissionManager` and pushed on login / accept / mission-state change — mirroring the existing `SendGMCPExchangeSnapshot` precedent. The client (`fed2-tools`) gains a Muxlet content module (`missions.lua`) that consumes `gmcp.char.missions`, renders a unified list via the existing `table_system`, and toggles an inline detail panel.

**Tech Stack:** C++17 (doctest unit tests, CMake, clang-format/clang-tidy) on the engine; Lua + Geyser + Muxlet on the client (built with muddler).

## Global Constraints

- **Do NOT bump `Fed::version`.** (Explicit user instruction for this change.)
- **Do NOT send a `hint` field** in the GMCP payload or show it in the client — hints are only obtainable from a secret in-game location.
- Engine: after changing any `.cc`/`.h`, run `clang-format -i` and `./run-clang-tidy.sh` on the touched files and resolve new warnings. Never run clang-format on `CMakeLists.txt`.
- Engine code style: `.clang-format` is authoritative (LLVM-derived, 4-space, 110-col, `SpacesInAngles: true` → `std::list< T >`, right pointer alignment, sorted includes).
- Engine: every new `.cc`/`.h` must be listed in `CMakeLists.txt` (`SOURCE_FILES`); new test files in `FED2D_TEST_SOURCES`.
- The tab and `display missions` must never disagree: mirror the text display's visibility filters (accepted && !hidden_until_complete; offered && !hidden_until_started && !hidden_until_complete), plus exclude `SECRET` type as defense-in-depth.
- Both repos ship together; GMCP-only (no text-scraping fallback). Client work is on branch `missions-tab` (fed2-tools); do engine work on a matching branch in `fed2-community`.

---

## File Structure

**fed2-community (engine):**
- Create `include/mission_gmcp.h` — declares `MissionGMCP` namespace (pure serialization: `JsonEscape`, `TrackerToJson`, `FilterVisible`, `BuildArray`).
- Create `src/mission_gmcp.cc` — implements the above.
- Create `tests/test_mission_gmcp.cc` — doctest unit tests for the serialization unit.
- Modify `include/mission_manager.h` — add `buildMissionsGMCP`, `SendGMCPMissionsSnapshot`, private `missionStateSignature`.
- Modify `src/mission_manager.cc` — implement those; emit on accept and on state-change in `track()`.
- Modify `src/fed_telnet.cc` — push the snapshot from `SendAllGMCP()` (login).
- Modify `CMakeLists.txt` — register the new source + test.

**fed2-tools (client):**
- Create `src/scripts/ui/content/missions.lua` — the Missions content module.
- Modify `src/scripts/ui/content/scripts.json` — add `{"name": "missions"}`.
- Modify `src/resources/full.lua` — insert the Missions tab first in the RightBottom pane.

---

## Task 1: Engine — `MissionGMCP` pure serialization unit (TDD)

**Files:**
- Create: `fed2-community/include/mission_gmcp.h`
- Create: `fed2-community/src/mission_gmcp.cc`
- Test: `fed2-community/tests/test_mission_gmcp.cc`
- Modify: `fed2-community/CMakeLists.txt`

**Interfaces:**
- Produces:
  - `std::string MissionGMCP::JsonEscape(const std::string &s)`
  - `std::string MissionGMCP::TrackerToJson(MissionTracker *tracker, MissionTracker *global_tracker)`
  - `std::vector< MissionTracker * > MissionGMCP::FilterVisible(const std::unordered_map< int, MissionTracker * > &trackers)`
  - `std::string MissionGMCP::BuildArray(const std::vector< MissionTracker * > &visible, std::unordered_map< int, MissionTracker * > &global_trackers)`
- Consumes: `Mission` / `MissionTracker` getters (`id()`, `applyTemplate()`, `type()`, `accepted()`, `completed()`, `offered()`, `inactive()`, `is_global()`, `hidden_until_complete()`, `hidden_until_started()`, `getGoalTotal()`, `effectiveTotalQuantity()`, `personal_global_cap()`, `total_quantity()`, `goals()`, `goal_count(i)`, `resolvedQnt(i)`, `rewards()`, `expire_after_cycles()`, `expiresInCycles()`, `updateGlobalTrackerCounts()`).

- [ ] **Step 1: Create the header**

Create `include/mission_gmcp.h`:

```cpp
#ifndef MISSION_GMCP_H
#define MISSION_GMCP_H

#include <string>
#include <unordered_map>
#include <vector>

class MissionTracker;

namespace MissionGMCP {
    // Escape a string for embedding in a JSON double-quoted string. Handles
    // ", \, and control chars < 0x20. Apostrophes are legal JSON and pass
    // through unchanged.
    std::string JsonEscape(const std::string &s);

    // Serialize one tracker to a JSON object. global_tracker is the resolved
    // aggregate tracker for a global mission (already updated), or nullptr for
    // non-global missions / when no aggregate exists.
    std::string TrackerToJson(MissionTracker *tracker, MissionTracker *global_tracker);

    // Filter a player's trackers to the client-visible set (mirrors the text
    // display: accepted && !hidden_until_complete, or offered &&
    // !hidden_until_started && !hidden_until_complete; SECRET type and inactive
    // excluded), sorted by mission id ascending.
    std::vector< MissionTracker * >
    FilterVisible(const std::unordered_map< int, MissionTracker * > &trackers);

    // Build the JSON array body ("[{...},{...}]") for the given visible
    // trackers, resolving each global mission's aggregate from global_trackers.
    std::string BuildArray(const std::vector< MissionTracker * >       &visible,
                           std::unordered_map< int, MissionTracker * > &global_trackers);
} // namespace MissionGMCP

#endif // MISSION_GMCP_H
```

- [ ] **Step 2: Create the implementation**

Create `src/mission_gmcp.cc`:

```cpp
#include "mission_gmcp.h"

#include "mission.h"
#include "mission_tracker.h"

#include <algorithm>
#include <cstdio>
#include <magic_enum/magic_enum.hpp>
#include <sstream>

namespace MissionGMCP {

    std::string JsonEscape(const std::string &s) {
        std::string out;
        out.reserve(s.size() + 8);
        for (char c : s) {
            switch (c) {
                case '"':
                    out += "\\\"";
                    break;
                case '\\':
                    out += "\\\\";
                    break;
                case '\n':
                    out += "\\n";
                    break;
                case '\r':
                    out += "\\r";
                    break;
                case '\t':
                    out += "\\t";
                    break;
                default:
                    if (static_cast< unsigned char >(c) < 0x20) {
                        char buf[7];
                        std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast< unsigned char >(c));
                        out += buf;
                    } else {
                        out += c;
                    }
            }
        }
        return out;
    }

    namespace {
        void AppendCounts(std::ostringstream &o, const char *key, int cur, int total) {
            o << "\"" << key << "\":{\"cur\":" << cur << ",\"total\":" << total << "}";
        }

        bool Complete(MissionTracker *t, MissionTracker *g) {
            return t->completed() || (g != nullptr && g->completed());
        }
    } // namespace

    std::string TrackerToJson(MissionTracker *tracker, MissionTracker *global_tracker) {
        Mission           *m = tracker->mission();
        std::ostringstream o;
        o << "{";
        o << "\"id\":" << m->id() << ",";
        o << "\"name\":\"" << JsonEscape(tracker->applyTemplate(m->name(), 0)) << "\",";
        o << "\"desc\":\"" << JsonEscape(tracker->applyTemplate(m->description(), 0)) << "\",";
        o << "\"type\":\"" << std::string(magic_enum::enum_name(m->type())) << "\",";

        std::string status = "active";
        if (!tracker->accepted()) {
            status = "available";
        } else if (Complete(tracker, global_tracker)) {
            status = "completed";
        }
        o << "\"status\":\"" << status << "\",";
        o << "\"global\":" << (m->is_global() ? "true" : "false") << ",";

        if (m->is_global()) {
            int community = global_tracker != nullptr ? global_tracker->getGoalTotal() : 0;
            AppendCounts(o, "community", community, m->total_quantity());
            o << ",";
            AppendCounts(o, "your_part", tracker->getGoalTotal(), m->personal_global_cap());
            o << ",";
        } else {
            AppendCounts(o, "progress", tracker->getGoalTotal(), tracker->effectiveTotalQuantity());
            o << ",";
        }

        o << "\"goals\":[";
        const auto &goals     = m->goals();
        bool        firstGoal = true;
        for (size_t i = 0; i < goals.size(); ++i) {
            if (!goals[i].showLine) {
                continue;
            }
            if (!firstGoal) {
                o << ",";
            }
            firstGoal = false;
            o << "{\"desc\":\"" << JsonEscape(tracker->applyTemplate(goals[i].desc, static_cast< int >(i)))
              << "\",\"cur\":" << tracker->goal_count(static_cast< int >(i))
              << ",\"total\":" << tracker->resolvedQnt(static_cast< int >(i)) << "}";
        }
        o << "],";

        Mission::Rewards &r = m->rewards();
        o << "\"rewards\":{\"points\":" << r.points << ",\"money\":" << r.money << ",\"slithy\":" << r.slithy
          << "},";

        int cycles_left = m->expire_after_cycles() > 0 ? tracker->expiresInCycles() : -1;
        o << "\"cycles_left\":" << cycles_left;

        o << "}";
        return o.str();
    }

    std::vector< MissionTracker * >
    FilterVisible(const std::unordered_map< int, MissionTracker * > &trackers) {
        std::vector< MissionTracker * > visible;
        for (const auto &[id, tracker] : trackers) {
            Mission *m = tracker->mission();
            if (tracker->inactive() || m->hidden_until_complete() || m->type() == Mission::SECRET) {
                continue;
            }
            if (tracker->accepted()) {
                visible.push_back(tracker);
            } else if (tracker->offered() && !m->hidden_until_started()) {
                visible.push_back(tracker);
            }
        }
        std::sort(visible.begin(), visible.end(), [](MissionTracker *a, MissionTracker *b) {
            return a->mission()->id() < b->mission()->id();
        });
        return visible;
    }

    std::string BuildArray(const std::vector< MissionTracker * >       &visible,
                           std::unordered_map< int, MissionTracker * > &global_trackers) {
        std::ostringstream o;
        o << "[";
        bool first = true;
        for (MissionTracker *tracker : visible) {
            MissionTracker *global_tracker = nullptr;
            if (tracker->mission()->is_global()) {
                auto it = global_trackers.find(tracker->mission()->id());
                if (it != global_trackers.end()) {
                    it->second->updateGlobalTrackerCounts();
                    global_tracker = it->second;
                }
            }
            if (!first) {
                o << ",";
            }
            first = false;
            o << TrackerToJson(tracker, global_tracker);
        }
        o << "]";
        return o.str();
    }

} // namespace MissionGMCP
```

- [ ] **Step 3: Register in CMakeLists.txt**

In `CMakeLists.txt`, in the `SOURCE_FILES` block after the line `src/mission.cc` (currently line 460), add:

```
		include/mission_gmcp.h
		src/mission_gmcp.cc
```

In the `FED2D_TEST_SOURCES` block after `tests/test_mission_tracker.cc` (currently line 669), add:

```
    tests/test_mission_gmcp.cc
```

- [ ] **Step 4: Write the failing test**

Create `tests/test_mission_gmcp.cc`:

```cpp
#include <doctest.h>

#include "game_event.h"
#include "mission.h"
#include "mission_gmcp.h"
#include "mission_tracker.h"
#include "misc.h"
#include "support/scoped_player_index.h"
#include "support/test_player.h"

#include <string>
#include <unordered_map>

namespace {
    class ScopedCycle {
        int previous;

      public:
        explicit ScopedCycle(int cycle) : previous(Game::cycle_count) { Game::cycle_count = cycle; }
        ~ScopedCycle() { Game::cycle_count = previous; }
        ScopedCycle(const ScopedCycle &)            = delete;
        ScopedCycle &operator=(const ScopedCycle &) = delete;
    };

    // A single-goal mission whose one goal counts up to `total`. No expiry by
    // default so trackers built at any cycle stay active.
    Mission makeMission(int id, Mission::TYPE type, int total) {
        Mission mission;
        mission.id(id);
        mission.name("Tracker Mission");
        mission.type(type);
        mission.active(true);
        mission.total_quantity(total);
        mission.expire_after_cycles(0);

        Mission::Goal goal;
        goal.event    = GameEventType::EXCHANGE_PLAYERBUY;
        goal.target   = "woods";
        goal.desc     = "Buy woods";
        goal.maxTimes = total;
        goal.showLine = true;
        mission.addGoal(goal);
        return mission;
    }

    std::unordered_map< std::string, std::string >
    trackerRow(int offered, int started, int completed = 0, const std::string &goal_cnts = "0") {
        return {
            {           "rowid",                       "1" },
            {   "offered_cycle",   std::to_string(offered) },
            {   "started_cycle",   std::to_string(started) },
            { "completed_cycle", std::to_string(completed) },
            {        "inactive",                       "0" },
            {       "goal_cnts",                 goal_cnts },
            {    "goal_targets",                        "" },
        };
    }
} // namespace

TEST_CASE("MissionGMCP::JsonEscape escapes quotes, backslashes, control chars") {
    CHECK(MissionGMCP::JsonEscape("a\"b\\c") == "a\\\"b\\\\c");
    CHECK(MissionGMCP::JsonEscape(std::string("x\ny")) == "x\\ny");
    // Apostrophes are legal in JSON and must pass through unchanged.
    CHECK(MissionGMCP::JsonEscape("A Merchant's Mettle") == "A Merchant's Mettle");
}

TEST_CASE("MissionGMCP::TrackerToJson: normal active mission has progress, no community") {
    ScopedPlayerIndex players;
    ScopedCycle       cycle(50);
    TestPlayer        player("gmcp-normal", true);
    player->setStorageID(300);
    players->AddPlayerForTesting(player.Get());

    Mission m = makeMission(200, Mission::ONE_TIME, 1);
    m.name("A Ship in Need");
    auto           row = trackerRow(/*offered=*/1, /*started=*/2);
    MissionTracker t(&m, player.Get(), &row);

    std::string j = MissionGMCP::TrackerToJson(&t, nullptr);
    CHECK(j.find("\"id\":200") != std::string::npos);
    CHECK(j.find("\"name\":\"A Ship in Need\"") != std::string::npos);
    CHECK(j.find("\"type\":\"ONE_TIME\"") != std::string::npos);
    CHECK(j.find("\"status\":\"active\"") != std::string::npos);
    CHECK(j.find("\"global\":false") != std::string::npos);
    CHECK(j.find("\"progress\":{\"cur\":0,\"total\":1}") != std::string::npos);
    CHECK(j.find("\"community\":") == std::string::npos);
    CHECK(j.find("\"cycles_left\":-1") != std::string::npos);
}

TEST_CASE("MissionGMCP::TrackerToJson: escapes double quotes in the name") {
    ScopedPlayerIndex players;
    ScopedCycle       cycle(50);
    TestPlayer        player("gmcp-escape", true);
    player->setStorageID(301);
    players->AddPlayerForTesting(player.Get());

    Mission m = makeMission(201, Mission::ONE_TIME, 1);
    m.name("Fix \"the\" ship");
    auto           row = trackerRow(1, 2);
    MissionTracker t(&m, player.Get(), &row);

    std::string j = MissionGMCP::TrackerToJson(&t, nullptr);
    CHECK(j.find("Fix \\\"the\\\" ship") != std::string::npos);
}

TEST_CASE("MissionGMCP::TrackerToJson: global mission has community + your_part, no progress") {
    ScopedPlayerIndex players;
    ScopedCycle       cycle(50);
    TestPlayer        player("gmcp-global", true);
    player->setStorageID(302);
    players->AddPlayerForTesting(player.Get());

    Mission m = makeMission(202, Mission::DAILY_GLOBAL, 100);
    m.is_global(true);
    auto           row = trackerRow(1, 2, 0, /*goal_cnts=*/"5");
    MissionTracker t(&m, player.Get(), &row);

    Mission        gm   = makeMission(202, Mission::DAILY_GLOBAL, 100);
    gm.is_global(true);
    auto           grow = trackerRow(1, 2, 0, /*goal_cnts=*/"40");
    MissionTracker g(&gm, player.Get(), &grow);

    std::string j = MissionGMCP::TrackerToJson(&t, &g);
    CHECK(j.find("\"global\":true") != std::string::npos);
    CHECK(j.find("\"community\":{\"cur\":40,\"total\":100}") != std::string::npos);
    CHECK(j.find("\"your_part\":{\"cur\":5,\"total\":10}") != std::string::npos);
    CHECK(j.find("\"progress\":") == std::string::npos);
}

TEST_CASE("MissionGMCP::FilterVisible excludes hidden and secret, keeps active + available") {
    ScopedPlayerIndex players;
    ScopedCycle       cycle(50);
    TestPlayer        player("gmcp-filter", true);
    player->setStorageID(303);
    players->AddPlayerForTesting(player.Get());

    Mission m1 = makeMission(1, Mission::ONE_TIME, 1);       // accepted -> in
    Mission m2 = makeMission(2, Mission::ONE_TIME, 1);       // offered  -> in
    Mission m3 = makeMission(3, Mission::ONE_TIME, 1);       // hidden   -> out
    m3.hidden_until_complete(true);
    Mission m4 = makeMission(4, Mission::SECRET, 1);         // secret   -> out

    auto r1 = trackerRow(1, 2);
    auto r2 = trackerRow(1, 0);
    auto r3 = trackerRow(1, 2);
    auto r4 = trackerRow(1, 2);
    MissionTracker t1(&m1, player.Get(), &r1);
    MissionTracker t2(&m2, player.Get(), &r2);
    MissionTracker t3(&m3, player.Get(), &r3);
    MissionTracker t4(&m4, player.Get(), &r4);

    std::unordered_map< int, MissionTracker * > trackers = {
        { 1, &t1 },
        { 2, &t2 },
        { 3, &t3 },
        { 4, &t4 },
    };

    auto vis = MissionGMCP::FilterVisible(trackers);
    REQUIRE(vis.size() == 2);
    CHECK(vis[0]->mission()->id() == 1);
    CHECK(vis[1]->mission()->id() == 2);
}
```

- [ ] **Step 5: Build the tests and verify they compile+pass**

Run:
```sh
cd fed2-community && cmake . >/dev/null && cmake --build . --target fed2d_tests -- -j6
./fed2d_tests -tc="MissionGMCP*"
```
Expected: all `MissionGMCP*` test cases PASS. (If the DB constructor marks a tracker inactive because of cycle math, confirm `expire_after_cycles` is 0 in `makeMission` — non-expiring — and `started_cycle`/`cycle` are consistent.)

- [ ] **Step 6: Format, lint, commit**

Run:
```sh
clang-format -i include/mission_gmcp.h src/mission_gmcp.cc tests/test_mission_gmcp.cc
./run-clang-tidy.sh src/mission_gmcp.cc
git add include/mission_gmcp.h src/mission_gmcp.cc tests/test_mission_gmcp.cc CMakeLists.txt
git commit -m "Add MissionGMCP serialization unit for char.missions feed"
```
Expected: clang-tidy reports no new warnings on `src/mission_gmcp.cc`; commit succeeds.

---

## Task 2: Engine — wire `char.missions` into the live GMCP feed

**Files:**
- Modify: `fed2-community/include/mission_manager.h`
- Modify: `fed2-community/src/mission_manager.cc`
- Modify: `fed2-community/src/fed_telnet.cc`

**Interfaces:**
- Consumes: `MissionGMCP::FilterVisible`, `MissionGMCP::BuildArray` (Task 1); `Player::WantsGMCP()`, `Player::SendGMCPMessage(const std::string &)`, `Player::getStorageID()`; `MissionTracker::started_cycle()/getGoalTotal()/completed()/offered()`.
- Produces:
  - `std::string MissionManager::buildMissionsGMCP(Player *player)` → returns `"char.missions [...]"`.
  - `void MissionManager::SendGMCPMissionsSnapshot(Player *player)` → pushes it to a GMCP-capable client (no-op otherwise).
  - `size_t MissionManager::missionStateSignature(int pid)` (private).

- [ ] **Step 1: Declare the new methods**

In `include/mission_manager.h`, in the `public:` section after the `refillPossibleMissions` declaration (currently line 74), add:

```cpp
    // Build the "char.missions [...]" GMCP payload for this player's visible
    // missions (active + available), mirroring the text `display missions`
    // filters. SendGMCPMissionsSnapshot wraps this and pushes it to the socket.
    std::string buildMissionsGMCP(Player *player);
    // Push the char.missions GMCP snapshot to a GMCP-capable client. No-op for
    // non-GMCP clients. Called on login, on accept, and after any tracked event
    // that changed this player's mission state.
    void SendGMCPMissionsSnapshot(Player *player);
```

In the `private:` section near the bottom (before `autoAcceptRankMissionsForPromotion`, currently line 108), add:

```cpp
    // Order-independent fingerprint of a player's mission state (tracker count +
    // per-tracker accept/progress/complete/offer flags). track() compares it
    // before and after processing to decide whether to re-emit char.missions.
    size_t missionStateSignature(int pid);
```

- [ ] **Step 2: Implement the methods**

In `src/mission_manager.cc`, add `#include "mission_gmcp.h"` to the include block (keep it sorted — place it before `#include "mission_parser.h"`, currently line 12).

Add the implementations (place them right after `acceptMission`, i.e. after the closing brace of `MissionManager::acceptMission` at line 1023):

```cpp
std::string MissionManager::buildMissionsGMCP(Player *player) {
    std::vector< MissionTracker * > visible;
    auto                            it = _player_trackers.find(player->getStorageID());
    if (it != _player_trackers.end()) {
        visible = MissionGMCP::FilterVisible(it->second);
    }
    return "char.missions " + MissionGMCP::BuildArray(visible, _global_trackers);
}

void MissionManager::SendGMCPMissionsSnapshot(Player *player) {
    if (player == nullptr || !player->WantsGMCP()) {
        return;
    }
    player->SendGMCPMessage(buildMissionsGMCP(player));
}

size_t MissionManager::missionStateSignature(int pid) {
    auto it = _player_trackers.find(pid);
    if (it == _player_trackers.end()) {
        return 0;
    }
    size_t sig = it->second.size();
    for (const auto &[mid, t] : it->second) {
        size_t p = static_cast< size_t >(mid) * 2654435761u;
        p        = p * 31 + static_cast< size_t >(t->started_cycle());
        p        = p * 31 + static_cast< size_t >(t->getGoalTotal());
        p        = p * 31 + (t->completed() ? 1u : 0u);
        p        = p * 31 + (t->offered() ? 1u : 0u);
        sig += p; // commutative combine: independent of unordered_map order
    }
    return sig;
}
```

- [ ] **Step 3: Emit after accept**

In `src/mission_manager.cc`, at the end of `MissionManager::acceptMission`, after the success `player->Send(...)` line (currently line 1022), add:

```cpp
    SendGMCPMissionsSnapshot(player);
```

- [ ] **Step 4: Emit on state change in track()**

In `src/mission_manager.cc`, in `MissionManager::track`, capture the signature immediately after `const int pid = ge->player()->getStorageID();` (currently line 586):

```cpp
    const size_t sig_before = missionStateSignature(pid);
```

Then, at the end of `track()` immediately before `delete ge;` (currently line 658), add:

```cpp
    if (missionStateSignature(pid) != sig_before) {
        SendGMCPMissionsSnapshot(ge->player());
    }
```

Note: this refreshes the acting player's own view (including the updated community aggregate for a global mission they just pushed). Other online players' `community` numbers refresh on their own next event or relog — a deliberate v1 choice to avoid broadcasting GMCP to every player on every global-mission event; the 25/50/75% galaxy-wide milestone broadcasts already give coarse live feedback.

- [ ] **Step 5: Emit on login (SendAllGMCP)**

In `src/fed_telnet.cc`, add these includes to the include block (after `#include "player_index.h"`, currently line 19):

```cpp
#include "misc.h"
#include "mission_manager.h"
```

In `FedTelnet::SendAllGMCP()` (currently line 697), after the existing exchange-snapshot block that ends at line 703 (`}` closing the `if (owner != nullptr && owner->CurrentMap() != nullptr)`), add:

```cpp
    if (owner != nullptr) {
        Game::missionManager->SendGMCPMissionsSnapshot(owner);
    }
```

- [ ] **Step 6: Build the server and tests**

Run:
```sh
cd fed2-community && cmake . >/dev/null && cmake --build . -- -j6 && cmake --build . --target fed2d_tests -- -j6
./fed2d_tests >/dev/null && echo TESTS_OK
```
Expected: both binaries build clean; `TESTS_OK` prints (full suite still green).

- [ ] **Step 7: Manual smoke test over telnet**

Launch the engine and connect (use the `run` skill). In a GMCP-capable session, confirm the engine sends `char.missions` on login and after `choose <id>`. A quick way without a full GMCP client: temporarily connect with the fed2-tools client (Task 3) or inspect with a GMCP-aware telnet. Minimum bar here: server runs, `display missions` still works, and no crash on login/accept. Full GMCP payload verification happens in Task 3.

- [ ] **Step 8: Format, lint, commit**

Run:
```sh
clang-format -i include/mission_manager.h src/mission_manager.cc src/fed_telnet.cc
./run-clang-tidy.sh src/mission_manager.cc src/fed_telnet.cc
git add include/mission_manager.h src/mission_manager.cc src/fed_telnet.cc
git commit -m "Push char.missions GMCP on login, accept, and mission-state change"
```
Expected: no new clang-tidy warnings on the touched files; commit succeeds.

---

## Task 3: Client — Missions content module + tab registration

**Files:**
- Create: `fed2-tools/src/scripts/ui/content/missions.lua`
- Modify: `fed2-tools/src/scripts/ui/content/scripts.json`
- Modify: `fed2-tools/src/resources/full.lua`

**Interfaces:**
- Consumes: global `gmcp.char.missions` (array of mission objects with fields `id, name, desc, type, status, global, progress{cur,total} | community{cur,total}+your_part{cur,cap}, goals[]{desc,cur,total}, rewards{points,money,slithy}, cycles_left`); the reusable table API `f2tTableCreate/f2tTableSetScrollbox/f2tTableSetColHdrs/f2tTableSetData/f2tTableToggleSort/f2tTableOnResize/f2tTableDestroy`; `Mux.registerContent`; global `F2T_CONTENT_REGISTRARS`; `send`.
- Produces: content module registered as `fed2_missions`.

- [ ] **Step 1: Create the content module**

Create `src/scripts/ui/content/missions.lua`:

```lua
-- Missions tab: lists the player's active and available missions from the
-- char.missions GMCP feed. Available missions carry an Accept button
-- (choose <id>); clicking any mission name opens an inline detail panel.
-- Data is push-only from GMCP; Accept just sends the command and the panel
-- refreshes when the engine re-emits char.missions.

local H_COL = 20   -- column header bar height (px)
local ROW_H = 22   -- row height (px)
local SB_W  = 17   -- scrollbar pixel allowance

local CELL_FONT = "font-size:10pt;font-family:Consolas,Monaco,monospace;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

local _BTN_ACCEPT_CSS = [[
    QLabel {
        background-color: rgba(26,30,46,220);
        color: rgba(210,220,240,255);
        border: 1px solid rgba(72,85,128,180);
        border-left: 3px solid #3ecf5e;
        border-radius: 4px;
        font-size: 10px; font-weight: bold; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(38,44,66,235); border-left: 3px solid #5ce87c; color: white; }
]]

local _BTN_BACK_CSS = [[
    QLabel {
        background-color: rgba(26,30,46,220);
        color: rgba(210,220,240,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 4px;
        font-size: 11px; font-weight: bold; font-family: "Consolas","Monaco",monospace;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover { background-color: rgba(38,44,66,235); color: white; }
]]

local function emptyStateHtml(text)
    return string.format("<div style='padding:10px 6px;color:#888888;%s'>%s</div>", CELL_FONT, text)
end

-- Per-pane state, keyed by target._gid.
local instances = {}
-- Latest mission list from GMCP (shared across panes).
local missions = {}

local STATUS_ORDER = { active = 0, available = 1, completed = 2 }
local STATUS_COLOR = { active = "#7aa2ff", available = "#00cc44", completed = "#888888" }

local function capitalize(s)
    if not s or s == "" then return "" end
    return s:sub(1, 1):upper() .. s:sub(2)
end

local function findMission(id)
    for _, m in ipairs(missions) do
        if m.id == id then return m end
    end
    return nil
end

local function progressText(m)
    if m.global and m.community and m.your_part then
        return string.format("Com %s/%s  You %s/%s",
            m.community.cur, m.community.total, m.your_part.cur, m.your_part.cap)
    elseif m.progress then
        return string.format("%s/%s", m.progress.cur, m.progress.total)
    end
    return ""
end

local function buildRows()
    local rows = {}
    for _, m in ipairs(missions) do
        rows[#rows + 1] = {
            id           = m.id,
            name         = m.name or "",
            status       = m.status,
            statusText   = capitalize(m.status),
            statusOrder  = STATUS_ORDER[m.status] or 9,
            statusColor  = STATUS_COLOR[m.status] or "#c8c8c8",
            progressText = progressText(m),
        }
    end
    -- Group active first, then available, then completed; stable by id within.
    table.sort(rows, function(a, b)
        if a.statusOrder ~= b.statusOrder then return a.statusOrder < b.statusOrder end
        return (a.id or 0) < (b.id or 0)
    end)
    return rows
end

-- ── Inline detail panel ────────────────────────────────────────────────────

local function detailHtml(m)
    local p = {}
    p[#p + 1] = string.format(
        "<div style='%scolor:#e6d28c;font-size:12pt;font-weight:bold;padding:4px 6px;'>#%s  %s</div>",
        CELL_FONT, tostring(m.id), m.name or "")
    if m.desc and m.desc ~= "" then
        p[#p + 1] = string.format("<div style='%scolor:#c8c8c8;padding:2px 6px;'>%s</div>", CELL_FONT, m.desc)
    end
    if m.global and m.community and m.your_part then
        p[#p + 1] = string.format(
            "<div style='%scolor:#7aa2ff;padding:4px 6px;'>Community: %s/%s &nbsp;&nbsp; Your part: %s/%s</div>",
            CELL_FONT, m.community.cur, m.community.total, m.your_part.cur, m.your_part.cap)
    elseif m.progress then
        p[#p + 1] = string.format("<div style='%scolor:#7aa2ff;padding:4px 6px;'>Progress: %s/%s</div>",
            CELL_FONT, m.progress.cur, m.progress.total)
    end
    if m.goals and #m.goals > 0 then
        p[#p + 1] = string.format(
            "<div style='%scolor:#a0a0b9;padding:6px 6px 0;font-weight:bold;'>Goals</div>", CELL_FONT)
        for _, g in ipairs(m.goals) do
            p[#p + 1] = string.format("<div style='%scolor:#c8c8c8;padding:1px 12px;'>&bull; %s &mdash; %s/%s</div>",
                CELL_FONT, g.desc or "", g.cur, g.total)
        end
    end
    local r = m.rewards or {}
    local bits = {}
    if (r.points or 0) > 0 then bits[#bits + 1] = tostring(r.points) .. " Mission Points" end
    if (r.money or 0) > 0 then bits[#bits + 1] = tostring(r.money) .. "ig" end
    if (r.slithy or 0) > 0 then bits[#bits + 1] = tostring(r.slithy) .. " Slithy" end
    p[#p + 1] = string.format("<div style='%scolor:#3ecf5e;padding:6px;'>Reward: %s</div>",
        CELL_FONT, #bits > 0 and table.concat(bits, ", ") or "&mdash;")
    if (m.cycles_left or -1) > 0 then
        p[#p + 1] = string.format("<div style='%scolor:#888888;padding:0 6px 6px;'>Cycles left: %s</div>",
            CELL_FONT, m.cycles_left)
    end
    return table.concat(p)
end

local function hideDetail(inst)
    if inst.detail then inst.detail.box:hide() end
    inst.detailId = nil
    if inst.listBox then inst.listBox:show() end
end

local function showDetail(gid, id)
    local inst = instances[gid]
    if not inst then return end
    local m = findMission(id)
    if not m then return end
    inst.detailId = id

    if not inst.detail then
        local box = Geyser.Container:new({
            name = gid .. "_mdetail", x = 0, y = 0, width = "100%", height = "100%",
        }, inst.content)

        local back = Geyser.Label:new({
            name = gid .. "_mback", x = 6, y = 6, width = 70, height = 22,
        }, box)
        back:setStyleSheet(_BTN_BACK_CSS)
        back:echo("<center>&lsaquo; Back</center>")
        back:setClickCallback(function() hideDetail(instances[gid]) end)

        local accept = Geyser.Label:new({
            name = gid .. "_maccept", x = 84, y = 6, width = 80, height = 22,
        }, box)
        accept:setStyleSheet(_BTN_ACCEPT_CSS)
        accept:echo("<center>Accept</center>")

        local scroll = Geyser.ScrollBox:new({
            name = gid .. "_mdscroll", x = 0, y = 34, width = "100%", height = "100%-34px",
        }, box)
        local body = Geyser.Label:new({
            name = gid .. "_mdbody", x = 0, y = 0, width = "100%-" .. SB_W .. "px", height = 1200,
        }, scroll)
        body:setStyleSheet("background-color: rgba(18,18,26,255); border: none;")

        inst.detail = { box = box, accept = accept, body = body }
    end

    inst.detail.body:echo(detailHtml(m))
    if m.status == "available" then
        inst.detail.accept:show()
        inst.detail.accept:setClickCallback(function() send("choose " .. id, false) end)
    else
        inst.detail.accept:hide()
    end

    if inst.listBox then inst.listBox:hide() end
    inst.detail.box:show()
    inst.detail.box:raise()
end

-- ── List columns ───────────────────────────────────────────────────────────

local function buildCols(gid)
    return {
        {
            key = "name", label = "Mission", sortable = true,
            sort_value = function(r) return (r.name or ""):lower() end,
            scrollbox_pct = 42,
            render_label = function(v, row, cell)
                cell:echo(string.format(
                    "<span style='%scolor:#7aa2ff;text-decoration:underline;'>%s</span>", CELL_FONT, v or ""))
                cell:setToolTip("Click for mission details")
                local id = row.id
                cell:setClickCallback(function() showDetail(gid, id) end)
            end,
        },
        {
            key = "statusText", label = "Status", sortable = true,
            sort_value = function(r) return r.statusOrder end,
            scrollbox_pct = 20,
            render_label = function(v, row, cell)
                cell:echo(string.format("<span style='%scolor:%s;'>%s</span>", CELL_FONT, row.statusColor, v or ""))
            end,
        },
        {
            key = "progressText", label = "Progress", sortable = false,
            scrollbox_pct = 24,
            render_label = function(v, _row, cell)
                cell:echo(string.format("<span style='%scolor:#c8c8c8;'>%s</span>", CELL_FONT, v or ""))
            end,
        },
        {
            key = "action", label = "", sortable = false,
            scrollbox_pct = 14,
            render_label = function(_v, row, cell)
                if row.status == "available" then
                    cell:setStyleSheet(_BTN_ACCEPT_CSS)
                    cell:echo("<center>Accept</center>")
                    local id = row.id
                    cell:setToolTip("Accept mission " .. tostring(id))
                    cell:setClickCallback(function() send("choose " .. id, false) end)
                else
                    cell:echo("")
                end
            end,
        },
    }
end

-- ── Refresh ────────────────────────────────────────────────────────────────

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    local rows = buildRows()
    f2tTableSetData(inst.tableId, rows)
    if inst.emptyLbl then
        if #rows == 0 then inst.emptyLbl:show() else inst.emptyLbl:hide() end
    end
    -- Keep an open detail panel live as progress updates arrive.
    if inst.detailId then
        local m = findMission(inst.detailId)
        if m then showDetail(gid, inst.detailId) else hideDetail(inst) end
    end
end

local _renderTimer = nil
local function refreshAllDebounced()
    if _renderTimer then killTimer(_renderTimer) end
    _renderTimer = tempTimer(0.1, function()
        _renderTimer = nil
        for gid in pairs(instances) do pcall(refreshInstance, gid) end
    end)
end

local function onGmcpMissions()
    local data = gmcp and gmcp.char and gmcp.char.missions
    if type(data) ~= "table" then return end
    missions = data
    refreshAllDebounced()
end

registerAnonymousEventHandler("gmcp.char.missions", onGmcpMissions)

-- ── Content build ──────────────────────────────────────────────────────────

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        refreshInstance(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_mi_%d", gid, wc)
    end

    -- Everything below the (host-provided) tab lives inside listBox; the detail
    -- panel is a sibling container that overlays it.
    local listBox = Geyser.Container:new({
        name = wid(), x = 0, y = 0, width = "100%", height = "100%",
    }, target.content)

    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_COL,
    }, listBox)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    local scroll = Geyser.ScrollBox:new({
        name = wid(), x = 0, y = H_COL, width = "100%", height = "100%-" .. H_COL .. "px",
    }, listBox)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1200,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    local emptyLbl = Geyser.Label:new({
        name = wid(), x = 0, y = H_COL, width = "100%", height = "100%-" .. H_COL .. "px",
    }, listBox)
    emptyLbl:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")
    emptyLbl:echo(emptyStateHtml("No missions yet — check back after you rank up, or type 'display missions'."))
    emptyLbl:hide()

    local tableId = "missions_" .. gid
    local cols    = buildCols(gid)
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, ROW_H, scroll)

    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name = wid(), x = xPct .. "%", y = 0, width = col.scrollbox_pct .. "%", height = "100%",
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local tid, key = tableId, col.key
            lbl:setClickCallback(function() f2tTableToggleSort(tid, key) end)
            lbl:setToolTip("Sort by " .. col.label)
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    instances[gid] = {
        content      = target.content,
        listBox      = listBox,
        tableId      = tableId,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
        emptyLbl     = emptyLbl,
    }

    refreshInstance(gid)
end

local function buildMissionsDef()
    return {
        name        = "Missions",
        description = "Your active and available missions, with accept and detail views.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok and f2t_debug_log then
                f2t_debug_log("[missions] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableDestroy(inst.tableId)
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            if newCw ~= inst.contentW then
                inst.contentW = newCw
                inst.contentLabel:resize(newCw, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) refreshInstance(target._gid) end,
    }
end

function f2tRegisterMissions()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[missions] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_missions", buildMissionsDef())
    if f2t_debug_log then f2t_debug_log("[missions] registered fed2_missions content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterMissions)

if f2t_debug_log then f2t_debug_log("[missions] module loaded") end
```

- [ ] **Step 2: Register the module in the manifest**

In `src/scripts/ui/content/scripts.json`, add `{"name": "missions"}` as the first entry so it loads before the others (order in this file is load order, not tab order). The array becomes:

```json
[
  {"name": "missions"},
  {"name": "map"},
  {"name": "who"},
  {"name": "galaxy"},
  {"name": "player_info"},
  {"name": "cargo"},
  {"name": "chat"},
  {"name": "local_players"},
  {"name": "commodities"},
  {"name": "hauling_jobs"},
  {"name": "price_checker"},
  {"name": "company"},
  {"name": "futures"},
  {"name": "exchange"}
]
```

- [ ] **Step 3: Add the tab (first) in the workspace layout**

First confirm the rule ids `r16`/`r17` are unused:
```sh
cd fed2-tools && grep -o 'id = "r[0-9]*"' src/resources/full.lua | sort -u
```
If `r16`/`r17` are taken, pick the next two unused `rN` ids and use them below.

In `src/resources/full.lua`, in the `RightBottom` pane's `tabs = {` array (currently line 536), insert this table as the **first** element, immediately before the existing Hauling entry (`{ _activeContent = "fed2_hauling_jobs", ...` at line 537):

```lua
                        {
                            _activeContent = "fed2_missions",
                            closeable = false,
                            contentState = {},
                            contentable = false,
                            movable = true,
                            name = "Missions",
                            nameAlign = "center",
                            propertiesButton = false,
                            renamable = false,
                            rules = {
                                {
                                    act = "mux.overlay.disconnected.show",
                                    actElse = "mux.overlay.disconnected.hide",
                                    cond = {
                                        ref = "disconnected"
                                    },
                                    enabled = true,
                                    id = "r16"
                                },
                                {
                                    act = "mux.overlay.connecting.show",
                                    actElse = "mux.overlay.connecting.hide",
                                    cond = {
                                        ref = "connecting"
                                    },
                                    enabled = true,
                                    id = "r17"
                                }
                            }
                        },
```

This tab has **no** `mux.showSelf`/`mux.hideSelf` rule, so it is always visible (unlike Hauling/Price Checker which gate on rank/cert). Leave the pane's `activeTabName = "Company"` unchanged (Missions is first in order; the default-selected tab is a separate setting). `full.lua` is a generated Muxlet export — note for maintainers that future layout edits are normally made in-game and re-exported.

- [ ] **Step 4: Build the package**

Run:
```sh
cd fed2-tools && ./muddlet --fresh --profile <your-mudlet-profile>
```
(Or `docker run demonnic/muddler` per CI, then install the `.mpackage`.) Expected: build succeeds, no Lua syntax errors reported by muddler.

- [ ] **Step 5: Manual verification over telnet**

With the Task 2 engine running locally (use the `run` skill) and a fed2-tools GMCP session connected:
1. **Tab order + visibility:** the lower-right pane shows tabs **Missions · Hauling · Price Checker** (Missions first). Missions is visible even at low rank.
2. **List populates:** on login (and after `display missions`), active + available missions appear. Status column colors: active blue, available green, completed grey. Progress shows `cur/total`.
3. **Accept:** an available mission shows an Accept button; clicking it runs `choose <id>`, and after the engine re-emits the mission flips to active (its Accept button disappears) without a manual refresh.
4. **Detail:** clicking a mission name opens the inline detail (description, goals with `cur/total`, reward line "N Mission Points, Nig, N Slithy"); `‹ Back` returns to the list. Available missions also show an Accept button in the detail header.
5. **Global mission:** a global mission renders `Com cur/total  You cur/cap` in the list and `Community:` + `Your part:` in the detail; no `progress` line.
6. **Empty state:** a brand-new/low-rank character with no missions shows the empty-state text, not a blank pane.

Fix any layout/behavior issues surfaced here (Mudlet has no unit harness; this run is the test), rebuilding with `./muddlet --fresh` as needed.

- [ ] **Step 6: Commit**

Run:
```sh
cd fed2-tools
git add src/scripts/ui/content/missions.lua src/scripts/ui/content/scripts.json src/resources/full.lua
git commit -m "Add Missions tab (first) consuming char.missions GMCP feed"
```

---

## Self-Review

**Spec coverage:**
- GMCP feed (transport decision) → Task 1 + Task 2. ✓
- Payload schema (normal vs global, no hint, cycles_left -1) → Task 1 `TrackerToJson`. ✓
- Visibility (mirror text, exclude hidden/secret) → Task 1 `FilterVisible`. ✓
- Global correctness (reuse text accessors) → Task 1 uses `getGoalTotal`/`personal_global_cap`/`total_quantity`/`updateGlobalTrackerCounts`; Task 2 note on cross-player refresh. ✓
- Emit points (login, accept, state change) → Task 2 Steps 3–5. ✓
- No `Fed::version` bump → Global Constraints; no task touches it. ✓
- Missions tab first, always visible → Task 3 Step 3. ✓
- List: active + available, status, progress, Accept on available → Task 3 columns. ✓
- Inline detail (back, desc, goals, rewards, Accept when available, community/your-part for globals) → Task 3 detail panel. ✓
- Styling matches existing panels → Task 3 reuses CSS conventions. ✓
- Tests: engine doctest (fields, escaping, hidden/secret exclusion, global shape, cycles_left -1); client manual → Task 1 Step 4, Task 3 Step 5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the only "pick a value" is the rule-id check in Task 3 Step 3, which is a concrete grep + fallback instruction.

**Type consistency:** `SendGMCPMissionsSnapshot`, `buildMissionsGMCP`, `missionStateSignature`, `MissionGMCP::{JsonEscape,TrackerToJson,FilterVisible,BuildArray}`, and the JSON field names (`community`/`your_part`/`progress`/`cycles_left`) are used identically across engine tasks and the client's `progressText`/`detailHtml` readers. Client content id `fed2_missions` matches between `missions.lua` registration and `full.lua`'s `_activeContent`.
