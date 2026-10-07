"""Build f2ce-tools' Sol map knowledge from the game's own map files.

Reads <maps>/<map>.loc (rooms, exits, flags), .xob (objects and their command
verbs) and .xev (event scripts) from fed2-community-maps' sol folder and writes:

  src/scripts/map/sol_mechanics.lua  what exploring can't learn by walking:
      special exits (commands that move you), rides that hold you in a room on
      the way, rooms that kill on entry, and how each Akaturi pickup room is
      reached. Loaded by the package, so it helps players who map Sol themselves.
  src/resources/galaxy_brief.json    (--map) every Sol room reachable from each
      shuttlepad merged into the bundled map, with those special exits, death
      rooms locked. Existing rooms keep their ids and anything already on them.

Only plain, repeatable moves become special exits: an event that just prints,
announces and moves the player, or a ride that waits (freeze/delayevent) and
then does the same. Anything behind a condition, a fare or a stat change is left
out, so a route never depends on luck or money.

Usage: python scripts/sol_map/build_sol_map.py --maps <path to maps/sol> [--map] [--write]
Without --write it only prints the audit.
"""
import argparse
import collections
import glob
import heapq
import json
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import qtjson  # noqa: E402

MAP_JSON = os.path.join(REPO, "src", "resources", "galaxy_brief.json")
MECHANICS_LUA = os.path.join(REPO, "src", "scripts", "map", "sol_mechanics.lua")

DIRECTIONS = {"n": "north", "ne": "northeast", "e": "east", "se": "southeast", "s": "south",
              "sw": "southwest", "w": "west", "nw": "northwest", "up": "up", "down": "down",
              "in": "in", "out": "out"}
STANDARD_EXIT_NAMES = set(DIRECTIONS.values())
SAFE_TAGS = {"comment", "message", "announce", "move"}
RIDE_TAGS = SAFE_TAGS | {"freeze", "delayevent", "release"}
# Verbs aimed at a character: any move they cause is a reaction, not a route
SOCIAL_VERBS = {"kiss", "hug", "slap", "tickle", "ask", "say", "tell"}
# .loc flag letter -> GMCP flag name, as Location::GMCPDescription reports them
FLAG_LETTERS = {"e": "exchange", "c": "courier", "w": "weapons", "r": "repair", "y": "shipyard",
                "b": "bar", "l": "link", "h": "hospital", "i": "insure", "s": "space"}

# Routes the game gates on something the map can't express
COMMAND_GATES = {
    ("Phobos", "press button 2"): "the buggy needs a keycard first: 'ask tracey for authorization' at the "
                                  "Help desk",
}
UNREACHABLE_NOTES = {
    ("Venus", 904): "it's only reached on the Hobbs End mine shuttle, which the tools can't ride yet",
}

# map style (style.lua): environment and badge per flag
ENV_MULTI_FLAG, ENV_PLANET_DEFAULT, ENV_DEATH, SYM_DEATH = 257, 272, 265, "☠"
SURFACE_STYLES = [("shuttlepad", "🚀", 262), ("exchange", "$", 261), ("shipyard", "🔧", 267),
                  ("hospital", "✚", 263), ("bar", "🍸", 269), ("courier", "AC", 259)]
SURFACE_PRIORITY = ["shuttlepad", "exchange", "shipyard", "hospital", "bar"]


def style_for(flags):
    surface = [f for f in flags if f not in ("orbit", "link", "space")]
    known = [s for s in SURFACE_STYLES if s[0] in surface]
    if len(known) >= 2:
        for name in SURFACE_PRIORITY:
            if name in surface:
                return ENV_MULTI_FLAG, next(s[1] for s in SURFACE_STYLES if s[0] == name)
        return ENV_PLANET_DEFAULT, "?"
    if len(known) == 1:
        return known[0][2], known[0][1]
    if surface:
        return ENV_PLANET_DEFAULT, "?"
    return ENV_PLANET_DEFAULT, None


def parse(path):
    try:
        return ET.parse(path).getroot()
    except (ET.ParseError, FileNotFoundError):
        return None


def read_events(maps, base):
    root = parse(os.path.join(maps, base + ".xev"))
    events = {}
    if root is None:
        return events
    for category in root.iter("category"):
        for section in category.iter("section"):
            for event in section.iter("event"):
                events[f"{category.get('name')}.{section.get('name')}.{event.get('num')}"] = list(event)
    return events


def player_moves(children):
    return [int(c.get("loc")) for c in children if c.tag == "move" and c.get("what") == "player"]


def safe_moves(events):
    """event ref -> (destination, holding room or None)"""
    moves = {}
    for ref, children in events.items():
        tags = {c.tag for c in children}
        if not tags <= RIDE_TAGS:
            continue
        here = player_moves(children)
        delayed = [c.get("event") for c in children if c.tag == "delayevent"]
        if not delayed:
            if len(here) == 1 and tags <= SAFE_TAGS | {"release"}:
                moves[ref] = (here[0], None)
            continue
        later = events.get(delayed[0], [])
        if len(delayed) == 1 and {c.tag for c in later} <= SAFE_TAGS | {"release"} \
                and len(player_moves(later)) == 1 and len(here) <= 1:
            moves[ref] = (player_moves(later)[0], here[0] if here else None)
    return moves


def lethal_events(events):
    lethal = set()
    for ref, children in events.items():
        for c in children:
            value = c.get("stamina") if c.tag == "changestat" else None
            if value is not None and value.lstrip("-").isdigit():
                if (c.get("change") == "set" and int(value) <= 0) or int(value) <= -50:
                    lethal.add(ref)
    return lethal


def read_planet(maps, loc_path):
    base = os.path.basename(loc_path)[:-4]
    root = parse(loc_path)
    if root is None or not root.get("from") or not root.get("to"):
        return None
    events = read_events(maps, base)
    moves = safe_moves(events)
    lethal = lethal_events(events)
    rooms, deadly = {}, set()
    for loc in root.findall("location"):
        num = int(loc.get("num"))
        exits = {}
        ex = loc.find("exits")
        if ex is not None:
            for short, value in ex.attrib.items():
                if short in DIRECTIONS and value.lstrip("-").isdigit() and int(value) >= 0:
                    exits[short] = int(value)
        room_events = loc.find("events")
        bounce = None
        if room_events is not None:
            enter = room_events.get("enter")
            if enter in moves and moves[enter][1] is None:
                bounce = moves[enter][0]
            if any(room_events.get(kind) in lethal for kind in ("enter", "in-room")):
                deadly.add(num)
        rooms[num] = {"name": loc.findtext("name"), "flags": loc.get("flags", ""), "exits": exits,
                      "special": {}, "bounce": bounce}

    transit = set()
    xob = parse(os.path.join(maps, base + ".xob"))
    if xob is not None:
        for obj in xob.iter("object"):
            start = obj.get("start")
            if obj.get("type") != "static" or not start or not start.isdigit() or int(start) not in rooms:
                continue
            for vocab in obj.iter("vocab"):
                move = moves.get(vocab.get("event"))
                if move is None or move[0] not in rooms or vocab.get("cmd") in SOCIAL_VERBS:
                    continue
                dest, holding = move
                command = f"{vocab.get('cmd')} {obj.findtext('name')}".strip()
                special = rooms[int(start)]["special"]
                if dest not in special.values():
                    special[command] = dest
                if holding is not None and holding in rooms and holding != dest:
                    transit.add(holding)
    return {"title": root.get("title"), "pad": int(root.get("from")), "rooms": rooms,
            "transit": transit, "deadly": deadly}


def landing(rooms, num, seen=None):
    """Where walking into room num really leaves you"""
    seen = seen or set()
    room = rooms.get(num)
    if room and room["bounce"] is not None and num not in seen:
        seen.add(num)
        return landing(rooms, room["bounce"], seen)
    return num


def routes(planet):
    """room -> list of (special command, room it's used in) on the route from
    the shuttlepad that needs the fewest special exits; unreachable rooms absent"""
    rooms = planet["rooms"]
    best = {planet["pad"]: (0, [])}
    queue = [(0, planet["pad"])]
    while queue:
        cost, num = heapq.heappop(queue)
        if cost > best[num][0] or num in planet["deadly"]:
            continue
        room = rooms[num]
        steps = [(landing(rooms, d), None) for d in room["exits"].values()]
        steps += [(landing(rooms, d), c) for c, d in room["special"].items()]
        for dest, command in steps:
            if dest not in rooms:
                continue
            via = best[num][1] + ([(command, num)] if command else [])
            new_cost = cost + (1000 if command else 1)
            if dest not in best or new_cost < best[dest][0]:
                best[dest] = (new_cost, via)
                heapq.heappush(queue, (new_cost, dest))
    return {num: via for num, (_, via) in best.items()}


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def mechanics_lua(planets):
    lines = [
        "-- Generated by scripts/sol_map/build_sol_map.py from the game's Sol map files; regenerate,",
        "-- don't edit. What exploring can't learn by walking: special exits {from, command, to}",
        "-- (room numbers), rooms a ride holds you in on the way, rooms that kill on entry, and for",
        "-- Akaturi pickup/dropoff rooms that need more than walking, the commands on the way there",
        "-- (via) or what stands in the way (gate). Applied by mechanics.lua.",
        "-- luacheck: no max line length",
        "F2T_SOL_MECHANICS = {",
    ]
    for planet in sorted(planets, key=lambda p: p["title"]):
        rooms = planet["rooms"]
        lines.append(f"    [{lua_string(planet['title'])}] = {{")
        lines.append("        special = {")
        for num in sorted(rooms):
            for command, dest in sorted(rooms[num]["special"].items()):
                lines.append(f"            {{{num}, {lua_string(command)}, {dest}}},")
        lines.append("        },")
        lines.append("        transit = {" + ", ".join(str(n) for n in sorted(planet["transit"])) + "},")
        lines.append("        deadly = {" + ", ".join(str(n) for n in sorted(planet["deadly"])) + "},")
        lines.append("        pickups = {")
        reach = routes(planet)
        notes = {}
        for num, room in sorted(rooms.items()):
            if "a" not in room["flags"]:
                continue
            if num not in reach:
                note = {"gate": UNREACHABLE_NOTES.get((planet["title"], num),
                                                      "the game files show no walking or command route to it")}
            else:
                via = reach[num]
                if not via:
                    continue
                gates = [COMMAND_GATES[(planet["title"], c)] for c, _ in via if (planet["title"], c) in COMMAND_GATES]
                note = {"via": [f"{c} ({rooms[r]['name']})" for c, r in via]}
                if gates:
                    note["gate"] = gates[0]
            # Several pickup rooms can share a name; keep the easiest
            old = notes.get(room["name"])
            if old is None or len(note.get("via", [])) < len(old.get("via", [])):
                notes[room["name"]] = note
        for name, note in sorted(notes.items()):
            parts = []
            if "via" in note:
                parts.append("via = {" + ", ".join(lua_string(v) for v in note["via"]) + "}")
            if "gate" in note:
                parts.append("gate = " + lua_string(note["gate"]))
            lines.append(f"            [{lua_string(name)}] = {{{', '.join(parts)}}},")
        lines.append("        },")
        lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def reachable(planet):
    rooms = planet["rooms"]
    todo, seen = [planet["pad"]], set()
    while todo:
        num = todo.pop()
        if num in seen or num not in rooms:
            continue
        seen.add(num)
        room = rooms[num]
        for dest in list(room["exits"].values()) + list(room["special"].values()):
            todo.append(landing(rooms, dest))
    return seen


def merge_into_map(planets, data):
    """Merge each planet's reachable rooms into the bundled map; returns audit lines"""
    areas = {a["name"]: a for a in data["areas"]}
    by_hash, next_id = {}, 1
    for area in data["areas"]:
        for room in area["rooms"]:
            by_hash[room["hash"]] = (area, room)
            next_id = max(next_id, room["id"] + 1)
    audit = []
    for planet in planets:
        title, rooms = planet["title"], planet["rooms"]
        area = areas.get(title)
        if area is None:
            audit.append(f"{title}: no area for it in the bundled map, skipped")
            continue
        keep = reachable(planet) | planet["transit"]
        sample_user = next((r["userData"] for r in area["rooms"] if r["userData"].get("fed2_cartel")), {})
        hash_of = {num: f"Sol.{title}.{num}" for num in rooms}
        ids, added = {}, 0
        for num in sorted(keep):
            existing = by_hash.get(hash_of[num])
            if existing:
                ids[num] = existing[1]["id"]
            else:
                ids[num], next_id, added = next_id, next_id + 1, added + 1

        for num in sorted(keep):
            src = rooms[num]
            flags = [FLAG_LETTERS[c] for c in src["flags"] if c in FLAG_LETTERS]
            if "s" in src["flags"] and "f" in src["flags"]:
                flags.append("fighting")
            if num == planet["pad"]:
                flags.append("shuttlepad")
            new_exits = []
            for short, dest in sorted(src["exits"].items(), key=lambda kv: list(DIRECTIONS).index(kv[0])):
                dest = landing(rooms, dest)
                if dest in ids:
                    new_exits.append({"exitId": ids[dest], "name": DIRECTIONS[short]})
            for command, dest in sorted(src["special"].items()):
                dest = landing(rooms, dest)
                if dest in ids:
                    new_exits.append({"exitId": ids[dest], "name": command})

            existing = by_hash.get(hash_of[num])
            if existing:
                room = existing[1]
                generated = {e["name"] for e in new_exits}
                old_by_name = {e["name"]: e for e in room.get("exits", [])}
                merged = []
                for exit_ in new_exits:
                    old = old_by_name.get(exit_["name"])
                    if old and old["exitId"] != exit_["exitId"]:
                        audit.append(f"  {title} {num} {exit_['name']}: map had {old['exitId']}, game files say "
                                     f"{exit_['exitId']}")
                    merged.append(old if old and old["exitId"] == exit_["exitId"] else exit_)
                merged += [e for e in room.get("exits", [])
                           if e["name"] not in generated and e["name"] not in STANDARD_EXIT_NAMES]
                room["exits"] = merged
                room.pop("stubExits", None)
            else:
                env, symbol = style_for(flags)
                room = {"coordinates": [num % 64, -(num // 64), 0], "environment": env, "exits": new_exits,
                        "hash": hash_of[num], "id": ids[num], "name": src["name"], "userData": {}}
                if symbol:
                    room["symbol"] = {"color24RGB": [255, 255, 255], "text": symbol}
                area["rooms"].append(room)
                by_hash[hash_of[num]] = (area, room)
            user = room.setdefault("userData", {})
            user.setdefault("fed2_area", title)
            user.setdefault("fed2_system", "Sol")
            user.setdefault("fed2_cartel", sample_user.get("fed2_cartel", "Sol"))
            if sample_user.get("fed2_syndicate"):
                user.setdefault("fed2_syndicate", sample_user["fed2_syndicate"])
            user.setdefault("fed2_planet", title)
            user["fed2_num"] = str(num)
            user["fed2_exits"] = ",".join(f"{s}:{d}" for s, d in src["exits"].items())
            for flag in flags:
                user[f"fed2_flag_{flag}"] = "true"
            if num in planet["transit"]:
                user["fed2_transit"] = "true"

        # Death rooms, marked as 'map room death' does
        for num in sorted(planet["deadly"] & keep):
            room = by_hash[hash_of[num]][1]
            room.update({"name": rooms[num]["name"], "locked": True, "environment": ENV_DEATH,
                         "symbol": {"color24RGB": [255, 255, 255], "text": SYM_DEATH}})
            room["userData"]["f2t_danger"] = "true"
        area["rooms"].sort(key=lambda r: r["id"])
        area["roomCount"] = len(area["rooms"])
        audit.append(f"{title}: {len(keep)}/{len(rooms)} rooms reachable, {added} added")

    # Exits into any Sol death room (Sol Space's sun too) are locked
    danger = {r["id"] for a in data["areas"] for r in a["rooms"]
              if r["hash"].startswith("Sol.") and r.get("userData", {}).get("f2t_danger") == "true"}
    for area in data["areas"]:
        for room in area["rooms"]:
            if room["hash"].startswith("Sol."):
                for exit_ in room.get("exits", []):
                    if exit_["exitId"] in danger:
                        exit_["locked"] = True
    data["roomCount"] = sum(len(a["rooms"]) for a in data["areas"])
    return audit


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--maps", required=True, help="fed2-community-maps sol folder (.loc/.xob/.xev)")
    parser.add_argument("--map", action="store_true", help="also merge Sol into the bundled galaxy_brief.json")
    parser.add_argument("--write", action="store_true", help="write the files (otherwise audit only)")
    args = parser.parse_args()

    planets = [p for p in (read_planet(args.maps, path) for path in sorted(glob.glob(os.path.join(args.maps, "*.loc"))))
               if p is not None]
    for planet in planets:
        reach = routes(planet)
        pickups = [n for n, r in planet["rooms"].items() if "a" in r["flags"]]
        missing = [n for n in pickups if n not in reach]
        special = sum(len(r["special"]) for r in planet["rooms"].values())
        print(f"{planet['title']:14} special exits {special:2}, deadly {sorted(planet['deadly'])}, "
              f"pickup rooms reachable {len(pickups) - len(missing)}/{len(pickups)}")

    lua = mechanics_lua(planets)
    if args.map:
        data = json.load(open(MAP_JSON, encoding="utf-8"))
        for line in merge_into_map(planets, data):
            print(line)
        print("bundled map rooms:", data["roomCount"])
    if args.write:
        with open(MECHANICS_LUA, "w", encoding="utf-8", newline="\n") as out:
            out.write(lua)
        print("written", MECHANICS_LUA)
        if args.map:
            with open(MAP_JSON, "w", encoding="utf-8", newline="\n") as out:
                out.write(qtjson.dumps(data))
            print("written", MAP_JSON)


if __name__ == "__main__":
    main()
