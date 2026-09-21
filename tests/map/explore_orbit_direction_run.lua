local frontier_source = assert(arg[1], "explore_frontier.lua is required")
local helper_source = assert(arg[2], "explore_system_helpers.lua is required")
local explore_source = assert(arg[3], "explore.lua is required")

local passed, failed = 0, 0
local function check(value, message) if not value then error(message or "check failed", 2) end end
local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ",
            tostring(expected), tostring(actual)), 2)
    end
end

local rooms = {}
local completed = 0
local resolved = {}

function f2t_debug_log() end
function cecho() end
function getRoomExits(room_id) return (rooms[room_id] and rooms[room_id].exits) or {} end
function getExitStubs(room_id) return (rooms[room_id] and rooms[room_id].stubs) or {} end
function getRoomUserData(room_id, key)
    return rooms[room_id] and rooms[room_id].data and rooms[room_id].data[key] or ""
end
function setRoomUserData(room_id, key, value) rooms[room_id].data[key] = tostring(value) end
function hasExitLock() return false end
function roomLocked() return false end
function f2t_map_area_room_list() return {} end
function getPath() return false end

dofile(explore_source)
dofile(frontier_source)
dofile(helper_source)

-- Keep the arrival handler focused on the orbit-discovery branch.
function f2t_map_explore_system_space_complete() completed = completed + 1 end
function f2t_map_resolve_stub_exit(from_room, to_room, direction)
    resolved[#resolved + 1] = {from_room=from_room, to_room=to_room, direction=direction}
end
function f2t_map_explore_recompute_frontier() end
function f2t_map_explore_next_step() end

local function exploration_state(room_id, expected, observed, direction)
    rooms[room_id] = {data={fed2_planet=observed}, exits={}}
    F2T_MAP_CURRENT_ROOM_ID = room_id
    F2T_SPEEDWALK_ACTIVE = false
    F2T_SPEEDWALK_LAST_RESULT = nil
    F2T_MAP_EXPLORE_STATE = {
        active=true, paused=false, phase="navigating",
        system_mode="brief", system_phase="exploring_space",
        expected_planets={[expected]=true}, expected_planets_found={},
        expected_planets_remaining=1, frontier_stack={},
        visited_rooms={[room_id]=true},
        stats={rooms_discovered=0, blocked_exits=0},
        last_room_before_move=1, last_direction_attempted=direction,
    }
end

local tests = {}

function tests.vertical_stub_numbers_use_mudlet_exit_names()
    equal(f2t_map_explore_direction_number_to_name(9), "up", "up command")
    equal(f2t_map_explore_direction_number_to_name(10), "down", "down command")
    equal(f2t_map_explore_direction_number_to_name(11), "in", "in command")
    equal(f2t_map_explore_direction_number_to_name(12), "out", "out command")
end

function tests.mapped_direction_aliases_do_not_reenter_visited_orbits()
    local cases = {
        {command="up", stored="up"}, {command="u", stored="up"},
        {command="down", stored="down"}, {command="d", stored="down"},
        {command="in", stored="in"}, {command="out", stored="out"},
    }
    for index, case in ipairs(cases) do
        local source, destination = 100 + index, 200 + index
        rooms[source] = {exits={[case.stored]=destination}}
        F2T_MAP_EXPLORE_STATE = {visited_rooms={[destination]=true}}
        check(not f2t_map_explore_is_exit_valid(source, case.command),
            case.command .. " revisited a mapped orbit")
    end
end

function tests.every_noncompass_orbit_arrival_is_recognized_even_when_previsited()
    completed, resolved = 0, {}
    for index, direction in ipairs({"in", "out", "up", "down"}) do
        local room_id = 300 + index
        local planet = "Planet " .. direction
        exploration_state(room_id, planet, planet, direction)
        f2t_map_explore_on_room_change()
        check(F2T_MAP_EXPLORE_STATE.expected_planets_found[planet],
            direction .. " orbit was not recognized")
        equal(F2T_MAP_EXPLORE_STATE.expected_planets_remaining, 0,
            direction .. " expected count")
        equal(resolved[#resolved].direction, direction, direction .. " resolved direction")
    end
    equal(completed, 4, "space completion count")
end

function tests.expected_planet_matching_is_case_insensitive()
    completed = 0
    exploration_state(401, "HogRock", "Hogrock", "up")
    f2t_map_explore_on_room_change()
    check(F2T_MAP_EXPLORE_STATE.expected_planets_found.HogRock,
        "canonical expected name was not retained")
    check(not F2T_MAP_EXPLORE_STATE.expected_planets_found.Hogrock,
        "observed spelling leaked into the expected set")
    equal(completed, 1, "case-insensitive completion count")
end

function tests.full_system_records_orbits_without_finishing_space_early()
    completed = 0
    exploration_state(601, "Atlas", "Atlas", "up")
    F2T_MAP_EXPLORE_STATE.system_mode = "full"
    f2t_map_explore_on_room_change()
    check(F2T_MAP_EXPLORE_STATE.expected_planets_found.Atlas,
        "full system did not retain the discovered orbit")
    equal(F2T_MAP_EXPLORE_STATE.expected_planets_remaining, 0,
        "full system expected count")
    equal(completed, 0, "full system stopped before exhausting the space frontier")
end

function tests.live_orbit_hash_recovers_missing_room_userdata()
    completed = 0
    exploration_state(402, "Outer Castle", "", "out")
    gmcp = {room={info={orbit="Zork.Outer Castle.396"}}}
    f2t_map_explore_on_room_change()
    gmcp = nil
    check(F2T_MAP_EXPLORE_STATE.expected_planets_found["Outer Castle"],
        "live orbit hash fallback was not recognized")
    equal(getRoomUserData(402, "fed2_planet"), "Outer Castle", "repaired planet userdata")
    equal(getRoomUserData(402, "fed2_flag_orbit"), "true", "repaired orbit flag")
    equal(completed, 1, "live orbit completion count")
end

for name, test in pairs(tests) do
    local ok, err = pcall(test)
    if ok then
        passed = passed + 1
        io.write("PASS ", name, "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    end
end

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
