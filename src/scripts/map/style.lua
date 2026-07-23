-- f2ce-tools map — room styling (ported from map_style.lua)

local ENV_MULTI_FLAG     = 257
local ENV_ORBIT          = 258
local ENV_LINK_SYSTEM    = 259
local ENV_LINK_CARTEL    = 260
local ENV_EXCHANGE       = 261
local ENV_SHUTTLEPAD     = 262
local ENV_HOSPITAL       = 263
local ENV_SPACE_DEFAULT  = 264
local ENV_DEATH          = 265
local ENV_LOCKED         = 268
local ENV_COURIER        = 259
local ENV_SHIPYARD       = 267
local ENV_BAR            = 269
local ENV_PLANET_DEFAULT = 272

local SYM_SHUTTLEPAD = "🚀"
local SYM_EXCHANGE   = "$"
local SYM_SHIPYARD   = "🔧"
local SYM_HOSPITAL   = "✚"
local SYM_BAR        = "🍸"
local SYM_COURIER    = "AC"
local SYM_LINK       = "⟡"
local SYM_UNKNOWN    = "?"
local SYM_DEATH      = "☠"
local SYM_LOCKED     = "🔒"

local SURFACE_STYLES = {
    {flag = "shuttlepad", symbol = SYM_SHUTTLEPAD, env = ENV_SHUTTLEPAD},
    {flag = "exchange",   symbol = SYM_EXCHANGE,   env = ENV_EXCHANGE},
    {flag = "shipyard",   symbol = SYM_SHIPYARD,   env = ENV_SHIPYARD},
    {flag = "hospital",   symbol = SYM_HOSPITAL,   env = ENV_HOSPITAL},
    {flag = "bar",        symbol = SYM_BAR,         env = ENV_BAR},
    {flag = "courier",    symbol = SYM_COURIER,     env = ENV_COURIER},
}

local SURFACE_FLAG_SET = {}
for _, entry in ipairs(SURFACE_STYLES) do SURFACE_FLAG_SET[entry.flag] = entry end

local SURFACE_PRIORITY = {"shuttlepad", "exchange", "shipyard", "hospital", "bar"}

local function get_orbit_symbol(room_id, default_symbol)
    if f2t_settings_get("map", "orbit_planet_initial") then
        local planet = getRoomUserData(room_id, "fed2_planet")
        if planet and planet ~= "" then
            return string.upper(string.sub(planet, 1, 1))
        end
    end
    return default_symbol
end

local function is_cartel_link(room_id)
    local system = getRoomUserData(room_id, "fed2_system")
    if not system or system == "" then return false end
    local area_id = getRoomArea(room_id)
    if not area_id then return false end
    local cartel = getAreaUserData(area_id, "fed2_cartel")
    if not cartel or cartel == "" then return false end
    return string.lower(system) == string.lower(cartel)
end

function f2t_map_apply_room_style(room_id, flags)
    if not room_id or not roomExists(room_id) then return false end
    if not flags then flags = {} end

    local has_link  = f2t_has_value(flags, "link")
    local has_orbit = f2t_has_value(flags, "orbit")

    if has_link then
        local env    = is_cartel_link(room_id) and ENV_LINK_CARTEL or ENV_LINK_SYSTEM
        local symbol = has_orbit and get_orbit_symbol(room_id, SYM_LINK) or SYM_LINK
        setRoomChar(room_id, symbol); setRoomEnv(room_id, env); unsetRoomCharColor(room_id)
        return true
    end

    if has_orbit then
        local symbol = get_orbit_symbol(room_id, "O")
        setRoomChar(room_id, symbol); setRoomEnv(room_id, ENV_ORBIT); unsetRoomCharColor(room_id)
        return true
    end

    local nav_set = {orbit = true, link = true, space = true}
    local surface_flags = {}
    for _, flag in ipairs(flags) do
        if not nav_set[flag] then table.insert(surface_flags, flag) end
    end

    local known_count = 0
    for _, flag in ipairs(surface_flags) do
        if SURFACE_FLAG_SET[flag] then known_count = known_count + 1 end
    end

    if known_count >= 2 then
        local top_style = nil
        for _, flag in ipairs(SURFACE_PRIORITY) do
            if f2t_has_value(surface_flags, flag) then top_style = SURFACE_FLAG_SET[flag]; break end
        end
        if top_style then
            setRoomChar(room_id, top_style.symbol); setRoomEnv(room_id, ENV_MULTI_FLAG); unsetRoomCharColor(room_id)
        else
            setRoomChar(room_id, SYM_UNKNOWN); setRoomEnv(room_id, ENV_PLANET_DEFAULT); unsetRoomCharColor(room_id)
        end
        return true
    end

    if known_count == 1 then
        for _, entry in ipairs(SURFACE_STYLES) do
            if f2t_has_value(surface_flags, entry.flag) then
                setRoomChar(room_id, entry.symbol); setRoomEnv(room_id, entry.env); unsetRoomCharColor(room_id)
                return true
            end
        end
    end

    if #surface_flags > 0 then
        setRoomChar(room_id, SYM_UNKNOWN); setRoomEnv(room_id, ENV_PLANET_DEFAULT); unsetRoomCharColor(room_id)
        return true
    end

    setRoomChar(room_id, ""); unsetRoomCharColor(room_id)
    if f2t_has_value(flags, "space") then
        setRoomEnv(room_id, ENV_SPACE_DEFAULT)
    else
        setRoomEnv(room_id, ENV_PLANET_DEFAULT)
    end
    return false
end

function f2t_map_apply_death_room_style(room_id)
    if not room_id or not roomExists(room_id) then return end
    setRoomChar(room_id, SYM_DEATH); setRoomEnv(room_id, ENV_DEATH); unsetRoomCharColor(room_id)
end

function f2t_map_apply_locked_room_style(room_id)
    if not room_id or not roomExists(room_id) then return end
    setRoomChar(room_id, SYM_LOCKED); setRoomEnv(room_id, ENV_LOCKED); unsetRoomCharColor(room_id)
end

function f2t_map_update_room_style(room_id)
    local death_date = getRoomUserData(room_id, "f2t_death_date")
    local is_danger  = getRoomUserData(room_id, "f2t_danger")
    if (death_date and death_date ~= "") or (is_danger == "true") then
        f2t_map_apply_death_room_style(room_id); return
    end
    if roomLocked(room_id) then
        f2t_map_apply_locked_room_style(room_id); return
    end
    local flags = {}
    local known_flags = {"shuttlepad","exchange","orbit","link","space","shipyard","hospital","bar","courier"}
    for _, flag_name in ipairs(known_flags) do
        if getRoomUserData(room_id, string.format("fed2_flag_%s", flag_name)) == "true" then
            table.insert(flags, flag_name)
        end
    end
    f2t_map_apply_room_style(room_id, flags)
end

function f2t_map_get_flag_symbol(flag)
    if flag == "link"  then return SYM_LINK end
    if flag == "orbit" then return "O" end
    local entry = SURFACE_FLAG_SET[flag]
    return entry and entry.symbol or nil
end

function f2t_map_get_flag_env(flag)
    if flag == "link"  then return ENV_LINK_SYSTEM end
    if flag == "orbit" then return ENV_ORBIT end
    local entry = SURFACE_FLAG_SET[flag]
    return entry and entry.env or nil
end

function f2t_map_get_flag_color(flag) return nil end

local ENV_COLOR_RGB = {
    [257]={200,50,50}, [258]={50,160,50}, [259]={185,165,30}, [260]={50,100,200},
    [261]={120,0,30},  [262]={30,170,170},[263]={40,130,40},  [265]={120,0,0},
    [267]={140,80,20}, [268]={50,50,65},  [269]={200,120,0},
}

function f2t_map_get_flag_badge_rgb(flag)
    local env = f2t_map_get_flag_env(flag)
    if not env then return nil end
    local color = ENV_COLOR_RGB[env]
    if not color then return nil end
    return color[1], color[2], color[3]
end

local function env_hex(env_id)
    local c = ENV_COLOR_RGB[env_id]
    if not c then return "#666666" end
    return string.format("#%02x%02x%02x", c[1], c[2], c[3])
end

function f2t_map_get_legend_data()
    return {
        {label="Death Room",              symbol=SYM_DEATH,      html_color=env_hex(ENV_DEATH),        note="Confirmed kill — navigation locked"},
        {label="Locked Room",             symbol=SYM_LOCKED,     html_color=env_hex(ENV_LOCKED),       note="Manually locked — navigation avoids"},
        {label="Cartel Link",             symbol=SYM_LINK,       html_color=env_hex(ENV_LINK_CARTEL),  note="Hub system jump gate"},
        {label="System Link",             symbol=SYM_LINK,       html_color=env_hex(ENV_LINK_SYSTEM),  text_color="#141400", note="Jump gate"},
        {label="Orbit",                   symbol="E / O",        html_color=env_hex(ENV_ORBIT),        text_color="#001a00", note="Above planet (first letter = planet name)"},
        {label="Multi-service",           symbol="🚀 / $ …",     html_color=env_hex(ENV_MULTI_FLAG),   note="2+ services — top priority shown"},
        {label="Shuttlepad",              symbol=SYM_SHUTTLEPAD, html_color=env_hex(ENV_SHUTTLEPAD),   text_color="#001a1a", note="Dock / launch pad"},
        {label="Exchange",                symbol=SYM_EXCHANGE,   html_color=env_hex(ENV_EXCHANGE),     note="Commodity market"},
        {label="Shipyard",                symbol=SYM_SHIPYARD,   html_color=env_hex(ENV_SHIPYARD),     text_color="#ffd090", note="Repairs & upgrades"},
        {label="Hospital",                symbol=SYM_HOSPITAL,   html_color=env_hex(ENV_HOSPITAL),     text_color="#88dd88", note="Medical"},
        {label="Bar",                     symbol=SYM_BAR,        html_color=env_hex(ENV_BAR),          text_color="#1a0800", note="Food & drink"},
        {label="Armstrong Cuthbert (AC)", symbol=SYM_COURIER,    html_color=env_hex(ENV_COURIER),      text_color="#141400", note="AC offices — courier jobs"},
    }
end

local function f2t_map_apply_env_colors()
    setCustomEnvColor(257, 200,  50,  50, 255)
    setCustomEnvColor(258,  50, 160,  50, 255)
    setCustomEnvColor(259, 185, 165,  30, 255)
    setCustomEnvColor(260,  50, 100, 200, 255)
    setCustomEnvColor(261, 120,   0,  30, 255)
    setCustomEnvColor(262,  30, 170, 170, 255)
    setCustomEnvColor(263,  40, 130,  40, 255)
    setCustomEnvColor(264,  40,  40,  40, 255)
    setCustomEnvColor(265, 120,   0,   0, 255)
    setCustomEnvColor(267, 140,  80,  20, 255)
    setCustomEnvColor(268,  50,  50,  65, 255)
    setCustomEnvColor(269, 200, 120,   0, 255)
    setCustomEnvColor(272,  80,  80,  90, 255)
end

f2t_map_apply_env_colors()

function f2t_map_restyle_all()
    local rooms = getRooms()
    if not rooms then
        cecho("\n<red>[map]<reset> No rooms found in map database\n")
        return 0
    end
    local count = 0
    for room_id, _ in pairs(rooms) do
        f2t_map_update_room_style(room_id)
        count = count + 1
    end
    updateMap()
    cecho(string.format("\n<green>[map]<reset> Restyled <white>%d<reset> rooms based on current metadata\n", count))
    return count
end
