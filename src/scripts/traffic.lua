-- Room traffic: parses other players' arrival/departure lines, keeps a per-room
-- record of who came and went (read by the Local Players pane), and decides how
-- each line shows in the main console (kept, condensed, or removed).

F2T_TRAFFIC = F2T_TRAFFIC or {
    roomKey   = nil,
    movements = {},   -- lowercased name → latest movement in this room
    departed  = {},   -- lowercased name → time they last left this room
    log       = {},   -- newest first: movements and room-change dividers
    version   = 0,
    unseen    = 0,    -- log entries added since the drawer was last opened
}

local LOG_LIMIT   = 50
local BACK_WINDOW = 600   -- seconds after leaving that a return reads as "back"

f2t_settings_register("traffic", "show_in", {
    tab         = "F2CE-Tools/Movement",
    label       = "Show comings and goings in",
    description = "Where other players arriving and leaving appear: the main console, the Local Players "
               .. "pane (with a flash on arrival, a fade on departure and a recent-traffic list), or both",
    default     = "both",
    choices     = {"console", "players", "both"},
})

f2t_settings_register("traffic", "console_style", {
    label       = "Main console style",
    description = "full keeps the game's own wording. condensed shows one short line with an icon, "
               .. "e.g. \"+ 🚀 Ralph arrived from S\". Only used when comings and goings show in the console",
    default     = "condensed",
    choices     = {"full", "condensed"},
})

function f2tTrafficInPlayers()
    local showIn = f2t_settings_get("traffic", "show_in")
    return showIn == "players" or showIn == "both"
end

-- ── Parsing ──────────────────────────────────────────────────────────────────

local COMPASS = {
    north = "N", south = "S", east = "E", west = "W",
    northeast = "NE", northwest = "NW", southeast = "SE", southwest = "SW",
}
local FROM_WORDS = { above = true, below = true, inside = true, outside = true }
local TO_WORDS   = { upwards = "up", downwards = "down", inwards = "in", outwards = "out" }

-- " from the south" → "S", " from above" → "above", "" → "" (no direction).
-- Anything else is not a movement line.
local function fromDirection(part)
    if part == "" then return "" end
    local word = part:match("^ from the (%a+)$")
    if word then return COMPASS[word] end
    word = part:match("^ from (%a+)$")
    if word and FROM_WORDS[word] then return word end
    return nil
end

local function toDirection(part)
    if part == "" then return "" end
    local word = part:match("^ to the (%a+)$")
    if word then return COMPASS[word] end
    word = part:match("^ (%a+)$")
    return word and TO_WORDS[word] or nil
end

-- The name is the last word of what precedes "has": walking players can carry
-- a free-text mood before it ("Happy Ralph has left.").
local function nameFrom(prefix)
    return prefix and prefix:match("^.-(%u%w*)$")
end

local function plainName(prefix)
    return prefix and prefix:match("^%u%w*$") and prefix or nil
end

-- ", The Ebony Jewels," or ", The Ebony Jewels" → "The Ebony Jewels".
local function shipName(clause)
    if not clause or clause == "" then return nil end
    return clause:match("^, (.-),?$")
end

local function event(name, kind, extra)
    if not name then return nil end
    local result = { name = name, kind = kind }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local parsers = {
    function(text)
        local prefix, clause, rest = text:match("^(.-)'s ship(.-) has just entered the sector(.-)%.$")
        local direction = rest and fromDirection(rest)
        if direction then
            return event(plainName(prefix), "shipIn", { direction = direction, ship = shipName(clause) })
        end
    end,
    function(text)
        local prefix, clause, rest = text:match("^(.-)'s ship(.-) has left the sector(.-)%.$")
        local direction = rest and toDirection(rest)
        if direction then
            return event(plainName(prefix), "shipOut", { direction = direction, ship = shipName(clause) })
        end
    end,
    function(text)
        return event(plainName(text:match("^(.-)'s ship has just limped into the sector%.$")), "limpIn")
    end,
    function(text)
        return event(plainName(text:match("^(.-)'s ship has fled the sector!$")), "fleeOut")
    end,
    function(text)
        local prefix, clause = text:match(
            "^(.-)'s spaceship(.-) appears from the hyperspace link in a shower of high energy tachyons%.$")
        return event(plainName(prefix), "linkIn", { ship = shipName(clause) })
    end,
    function(text)
        local prefix, clause = text:match(
            "^(.-)'s spaceship(.-) disappears into the hyperspace link in a shower of high energy tachyons%.$")
        return event(plainName(prefix), "linkOut", { ship = shipName(clause) })
    end,
    function(text)
        local prefix, from = text:match("^(.-) has departed (.-) in a shuttle to the planet below%.$")
        if from == "orbit" then return event(plainName(prefix), "shuttleDown") end
        local ship = from and from:match("^%a+ ship, (.-),?$")
        if ship then return event(plainName(prefix), "shuttleDown", { ship = ship }) end
    end,
    function(text)
        local prefix = text:match("^(.-) has arrived in orbit from the planet below%.$")
        if prefix then return event(nameFrom(prefix), "shuttleUp") end
        local ship
        prefix, ship = text:match("^(.-) has arrived in orbit and boarded %a+ ship, (.+)%.$")
        return event(nameFrom(prefix), "shuttleUp", { ship = ship })
    end,
    function(text)
        local prefix = text:match("^(.-) has arrived in a shuttle from orbit%.$")
        if prefix then return event(plainName(prefix), "landed") end
        local ship
        prefix, ship = text:match("^(.-) has arrived in a shuttle from %a+ ship, (.+)%.$")
        return event(plainName(prefix), "landed", { ship = ship })
    end,
    function(text)
        local prefix = text:match("^(.-) has departed for orbit%.$")
        if prefix then return event(nameFrom(prefix), "launched") end
        local ship
        prefix, ship = text:match("^(.-) has boarded a shuttle and departed for %a+ ship, (.+), in orbit%.$")
        return event(nameFrom(prefix), "launched", { ship = ship })
    end,
    function(text)
        return event(nameFrom(text:match("^(.-) has arrived with a shimmer of teleportation effect")), "teleportIn")
    end,
    function(text)
        return event(nameFrom(text:match("^(.-) has left in a shimmer of teleportation effect%.$")), "teleportOut")
    end,
    function(text)
        local prefix, rest = text:match("^(.-) has just arrived(.-)%.$")
        if not rest then return nil end
        local direction = fromDirection((rest:gsub(" wearing a wedding ring$", "")))
        if direction then return event(nameFrom(prefix), "walkIn", { direction = direction }) end
    end,
    function(text)
        local prefix, rest = text:match("^(.-) has left(.-)%.$")
        local direction = rest and toDirection(rest)
        if direction then return event(nameFrom(prefix), "walkOut", { direction = direction }) end
    end,
}

-- Returns { name, kind, direction?, ship? } for a movement line, else nil.
function f2tTrafficParse(text)
    text = text and text:gsub("%s+$", "") or ""
    for _, parse in ipairs(parsers) do
        local result = parse(text)
        if result then return result end
    end
    return nil
end

-- ── Wording ──────────────────────────────────────────────────────────────────

-- icon, arrival (+) or departure (-), and wording fresh / on a return
local KINDS = {
    walkIn      = { icon = "🚶", sign = "+" },
    walkOut     = { icon = "🚶", sign = "-" },
    shipIn      = { icon = "🚀", sign = "+" },
    shipOut     = { icon = "🚀", sign = "-" },
    shuttleDown = { icon = "🛬", sign = "-", text = "shuttled down to planet" },
    shuttleUp   = { icon = "🛫", sign = "+", text = "shuttled up from planet", back = "back up from planet" },
    landed      = { icon = "🛬", sign = "+", text = "landed from orbit", back = "landed back from orbit" },
    launched    = { icon = "🛫", sign = "-", text = "launched to orbit" },
    teleportIn  = { icon = "✨", sign = "+", text = "teleported in", back = "teleported back in" },
    teleportOut = { icon = "✨", sign = "-", text = "teleported out" },
    linkIn      = { icon = "🌀", sign = "+", text = "came through the link", back = "back through the link" },
    linkOut     = { icon = "🌀", sign = "-", text = "left through the link" },
    limpIn      = { icon = "💨", sign = "+", text = "limped in", back = "limped back in" },
    fleeOut     = { icon = "💨", sign = "-", text = "fled the sector" },
}

local function describe(movement, returning)
    local kind = KINDS[movement.kind]
    if kind.text then return returning and kind.back or kind.text end
    local direction = movement.direction or ""
    if kind.sign == "+" then
        local verb = returning and "back" or "arrived"
        return direction == "" and verb or (verb .. " from " .. direction)
    end
    return direction == "" and "left" or (TO_WORDS[direction .. "wards"] and ("left " .. direction)
        or ("left to " .. direction))
end

function f2tTrafficRankOf(name)
    local players = gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.players
    for _, player in ipairs(players or {}) do
        if player.name == name and player.rank then return player.rank end
    end
    local known = f2t_player_db_get and f2t_player_db_get(name)
    return known and known.rank or nil
end

-- ── Record ───────────────────────────────────────────────────────────────────

local function pushLog(entry)
    table.insert(F2T_TRAFFIC.log, 1, entry)
    while #F2T_TRAFFIC.log > LOG_LIMIT do table.remove(F2T_TRAFFIC.log) end
    F2T_TRAFFIC.unseen = F2T_TRAFFIC.unseen + 1
end

local function changed()
    F2T_TRAFFIC.version = F2T_TRAFFIC.version + 1
    raiseEvent("f2tTrafficChanged")
end

-- Keys the record to the room you're in: a real move starts a fresh record and
-- puts a divider in the recent-traffic list. Resends of the same room do nothing.
function f2tTrafficSyncRoom()
    local info = gmcp and gmcp.room and gmcp.room.info
    if not (info and info.num) then return end
    local key = tostring(info.system) .. "|" .. tostring(info.area) .. "|" .. tostring(info.num)
    if key == F2T_TRAFFIC.roomKey then return end
    local hadRoom = F2T_TRAFFIC.roomKey ~= nil
    F2T_TRAFFIC.roomKey   = key
    F2T_TRAFFIC.movements = {}
    F2T_TRAFFIC.departed  = {}
    if hadRoom and #F2T_TRAFFIC.log > 0 and not F2T_TRAFFIC.log[1].roomBreak then
        table.insert(F2T_TRAFFIC.log, 1, { roomBreak = true, at = getEpoch(), text = info.name or info.area or "" })
    end
    changed()
end

function f2tTrafficRecord(movement)
    local kind = KINDS[movement.kind]
    local key  = movement.name:lower()
    local now  = getEpoch()
    local previous = F2T_TRAFFIC.movements[key]

    movement.sign = kind.sign
    movement.icon = kind.icon
    movement.at   = now
    movement.rank = f2tTrafficRankOf(movement.name)
    if kind.sign == "+" then
        local leftAt = F2T_TRAFFIC.departed[key]
        local returning = (previous and previous.sign == "-") or (leftAt and now - leftAt <= BACK_WINDOW)
        movement.text = describe(movement, returning)
        movement.order = now
        F2T_TRAFFIC.departed[key] = nil
    else
        movement.text = describe(movement, false)
        -- a departing row keeps its place in the list while it fades
        movement.order = previous and previous.order or 0
        F2T_TRAFFIC.departed[key] = now
    end
    movement.ship = movement.ship or (previous and previous.ship)

    F2T_TRAFFIC.movements[key] = movement
    pushLog({ at = now, sign = movement.sign, icon = movement.icon, name = movement.name,
              rank = movement.rank, text = movement.text })
    changed()
end

-- ── Main console ─────────────────────────────────────────────────────────────

local SIGN_DECHO = { ["+"] = "<79,210,122>+", ["-"] = "<229,163,61>−" }
local NAME_DEFAULT_DECHO = "<200,200,200>"

function f2tTrafficConsoleLine(movement)
    local nameColor = movement.rank and f2t_rank_color_decho(movement.rank) or NAME_DEFAULT_DECHO
    local tail = movement.ship and ("<95,100,128> · " .. movement.ship) or ""
    return string.format("%s %s %s%s<150,156,178> %s%s<r>",
        SIGN_DECHO[movement.sign], movement.icon, nameColor, movement.name, movement.text, tail)
end

-- Body of the movement trigger: record the line, then keep, condense or remove it.
function f2tTrafficHandleLine()
    local movement = f2tTrafficParse(line)
    if not movement then return end
    f2tTrafficSyncRoom()
    f2tTrafficRecord(movement)

    if f2t_settings_get("traffic", "show_in") == "players" then
        deleteLine()
    elseif f2t_settings_get("traffic", "console_style") == "condensed" then
        dreplaceLine("main", f2tTrafficConsoleLine(movement))
    end
end

registerAnonymousEventHandler("gmcp.room.info", function() f2tTrafficSyncRoom() end)

f2t_debug_log("[traffic] module loaded")
