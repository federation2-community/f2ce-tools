local explore_source = assert(arg[1], "explore.lua is required")
local system_source = assert(arg[2], "explore_system.lua is required")
local cartel_source = assert(arg[3], "explore_cartel.lua is required")
local galaxy_source = assert(arg[4], "explore_galaxy.lua is required")

local passed, failed = 0, 0
local function check(value, message) if not value then error(message or "check failed", 2) end end
local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ",
            tostring(expected), tostring(actual)), 2)
    end
end

local area_data = {}
function f2t_debug_log() end
function cecho() end
function tempTimer(_, callback) callback(); return 1 end
function getAreaUserData(area_id, key)
    return area_data[area_id] and area_data[area_id][key] or ""
end
function setAreaUserData(area_id, key, value)
    area_data[area_id] = area_data[area_id] or {}
    area_data[area_id][key] = value
end
function f2t_map_area_room_list() return {} end
function deleteRoom() end
function getRoomArea() return 42 end
function getRoomName() return "Landing Pad" end
function getRoomAreaName() return "Atlas" end
function getRoomUserData() return "" end
function getPath() return true end

dofile(explore_source)
dofile(system_source)
dofile(cartel_source)
dofile(galaxy_source)

local tests = {}

function tests.full_area_markers_persist_and_reset()
    area_data = {}
    check(not f2t_map_explore_area_is_fully_explored(42), "new area started complete")
    check(f2t_map_explore_mark_area_fully_explored(42), "mark failed")
    check(f2t_map_explore_area_is_fully_explored(42), "mark was not readable")
    f2t_map_explore_delete_area_rooms(42)
    check(not f2t_map_explore_area_is_fully_explored(42), "reset retained full marker")
end

function tests.galaxy_full_reaches_cartel_with_full_mode()
    local cartel_mode
    F2T_MAP_CURRENT_ROOM_ID = 1
    F2T_MAP_TOPOLOGY = {cartels={Alpha="Prime"}}
    F2T_MAP_EXPLORE_STATE = {active=false}
    function f2t_map_explore_register_safety_hooks() end
    function f2t_map_explore_brief_mode_start() end
    function f2t_map_topology_sync(callback) callback(true); return true end
    function f2t_map_get_current_cartel() return nil end
    function f2t_map_explore_cartel_start(_, _, mode) cartel_mode = mode; return true end

    check(f2t_map_explore_galaxy_start("full"), "galaxy full did not start")
    equal(F2T_MAP_EXPLORE_STATE.galaxy_explore_mode, "full", "stored galaxy mode")
    equal(cartel_mode, "full", "galaxy-to-cartel mode")
end

function tests.cartel_full_reaches_system_with_full_mode()
    local system_mode
    F2T_MAP_EXPLORE_STATE = {
        active=true, mode="galaxy", cartel_system_mode="full",
        cartel_stats={systems_explored=0},
    }
    function f2t_map_explore_system_start(mode) system_mode = mode; return true end
    f2t_map_explore_cartel_start_system_mode("Alpha")
    equal(system_mode, "full", "cartel-to-system mode")
end

function tests.nested_full_system_keeps_mode_and_roster()
    local received
    function f2t_map_di_system_capture_start(_, callback)
        callback({"Atlas", "Borealis"}, {Borealis=true}, false)
    end
    function f2t_map_explore_system_start_with_planets(mode, system, planets, no_exchange, callback)
        received = {mode=mode, system=system, planets=planets, no_exchange=no_exchange, callback=callback}
    end
    local callback = function() end
    check(f2t_map_explore_system_start("full", "alpha", callback), "nested full system did not start")
    equal(received.mode, "full", "nested mode was downgraded")
    equal(received.system, "Alpha", "system normalization")
    equal(#received.planets, 2, "authoritative planet roster")
    check(received.no_exchange.Borealis, "no-exchange roster was lost")
    equal(received.callback, callback, "parent callback was lost")
end

function tests.full_planet_walk_marks_surface_and_updates_stats()
    local started_mode, advanced = nil, 0
    area_data = {}
    F2T_MAP_CURRENT_ROOM_ID = 77
    F2T_SPEEDWALK_ACTIVE = false
    F2T_SPEEDWALK_LAST_RESULT = nil
    F2T_MAP_EXPLORE_STATE = {
        active=true, paused=false, mode="galaxy", phase="boarding_planet",
        system_phase="running_full", system_mode="full", brief_target_planet="Atlas",
        planet_list={{name="Atlas"}}, current_planet_index=1,
        system_stats={planets_explored=0, exchanges_found=0, planets_skipped=0},
        cartel_stats={total_planets=0, total_exchanges=0},
        visited_rooms={[77]=true}, stats={rooms_discovered=0, blocked_exits=0},
        frontier_stack={}, temp_locked_exits={},
    }
    function f2t_map_find_room_with_flag(area_id, flag)
        if area_id == 42 and flag == "exchange" then return 88 end
    end
    function f2t_map_explore_planet_start(mode, _, callback)
        started_mode = mode
        callback()
        return true
    end
    function f2t_map_explore_system_brief_next_planet() advanced = advanced + 1 end

    f2t_map_explore_on_room_change()
    equal(started_mode, "full", "surface exploration mode")
    check(f2t_map_explore_area_is_fully_explored(42), "surface was not marked complete")
    equal(F2T_MAP_EXPLORE_STATE.system_stats.planets_explored, 1, "system planet count")
    equal(F2T_MAP_EXPLORE_STATE.system_stats.exchanges_found, 1, "system exchange count")
    equal(F2T_MAP_EXPLORE_STATE.cartel_stats.total_planets, 1, "cartel planet count")
    equal(advanced, 1, "next planet was not scheduled")
end

for name, test in pairs(tests) do
    local ok, err = pcall(test)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

print(string.format("RESULT %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
