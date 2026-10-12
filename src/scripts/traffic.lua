-- Room traffic: parses other players' arrival/departure lines, keeps a per-room
-- record of who came and went (read by the Local Players pane), and decides how
-- each line shows in the main console (kept, condensed, or removed).

-- Kept across package reloads; fields are filled in individually so a reload
-- that adds a field still finds it on the surviving table.
F2T_TRAFFIC = F2T_TRAFFIC or {}
local defaults = {
    movements  = {},   -- lowercased name → latest movement in this room
    departed   = {},   -- lowercased name → time they last left this room
    arrivals   = {},   -- lowercased name → their last arrival in this room
    departures = {},   -- lowercased name → their last departure from this room
    log        = {},   -- newest first: movements and room-change dividers
    version    = 0,
    unseen     = 0,    -- log entries added since the drawer was last opened
    history    = {},   -- oldest first: every movement this session, for the full log window
    nextId     = 1,
}
for field, value in pairs(defaults) do
    if F2T_TRAFFIC[field] == nil then F2T_TRAFFIC[field] = value end
end

local LOG_LIMIT     = 50
local HISTORY_LIMIT = 2000
local BACK_WINDOW = 600   -- seconds after leaving that a return reads as "back"

f2t_settings_register("traffic", "show_in", {
    tab         = "F2CE-Tools/Movement",
    label       = "Show comings and goings in",
    description = "Where other players arriving and leaving appear: the main console, the Local Players "
               .. "pane (with a flash on arrival, a fade on departure and a recent-traffic list), or both",
    default     = "players",
    choices     = {"console", "players", "both"},
})

f2t_settings_register("traffic", "console_style", {
    label       = "Main console style",
    description = "full keeps the game's own wording. condensed shows one short line with an icon, "
               .. "e.g. \"+ 🚀 Ralph arrived from S\". Only used when comings and goings show in the console",
    default     = "condensed",
    choices     = {"full", "condensed"},
})

f2t_settings_register("traffic", "arrival_seconds", {
    label       = "Arrivals stay (seconds)",
    description = "How long a new arrival stays highlighted at the top of Local Players before joining "
               .. "everyone else",
    default     = 15,
    min = 5, max = 60,
})

f2t_settings_register("traffic", "departure_seconds", {
    label       = "Departures stay (seconds)",
    description = "How long someone who left stays under Just left in Local Players, along with their "
               .. "crossed-out arrival if they were only passing through",
    default     = 15,
    min = 5, max = 60,
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

-- icon, arrival (+) or departure (-), and how they travelled (route) when the
-- direction alone doesn't say
local KINDS = {
    walkIn      = { icon = "🚶", sign = "+" },
    walkOut     = { icon = "🚶", sign = "-" },
    shipIn      = { icon = "🚀", sign = "+" },
    shipOut     = { icon = "🚀", sign = "-" },
    shuttleDown = { icon = "🛬", sign = "-", route = "by shuttle to planet" },
    shuttleUp   = { icon = "🛫", sign = "+", route = "by shuttle from planet" },
    landed      = { icon = "🛬", sign = "+", route = "by shuttle from orbit" },
    launched    = { icon = "🛫", sign = "-", route = "by shuttle to orbit" },
    teleportIn  = { icon = "✨", sign = "+", route = "by teleport" },
    teleportOut = { icon = "✨", sign = "-", route = "by teleport" },
    linkIn      = { icon = "🌀", sign = "+", route = "via hyperspace link" },
    linkOut     = { icon = "🌀", sign = "-", route = "via hyperspace link" },
    limpIn      = { icon = "💨", sign = "+", route = "limping in" },
    fleeOut     = { icon = "💨", sign = "-", route = "fleeing" },
}

-- Splits a movement into a verb ("arrived", "back" or "left") and where or how
-- ("from S", "up", "via hyperspace link"; "" when the game doesn't say).
local function describe(movement, returning)
    local kind = KINDS[movement.kind]
    local verb = kind.sign == "-" and "left" or (returning and "back" or "arrived")
    if kind.route then return verb, kind.route end
    local direction = movement.direction or ""
    if direction == "" then return verb, "" end
    if kind.sign == "+" then return verb, "from " .. direction end
    return verb, TO_WORDS[direction .. "wards"] and direction or ("to " .. direction)
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

-- Each player has one entry per room: a new movement replaces their last one
-- (a return retires the departure).
local function pushLog(entry)
    local log = F2T_TRAFFIC.log
    for i = 1, #log do
        if log[i].roomBreak then break end
        if log[i].name == entry.name then
            table.remove(log, i)
            break
        end
    end
    table.insert(log, 1, entry)
    while #F2T_TRAFFIC.log > LOG_LIMIT do table.remove(F2T_TRAFFIC.log) end
    F2T_TRAFFIC.unseen = F2T_TRAFFIC.unseen + 1
end

-- Appends to the full session history, starting a new room section when the
-- movement happened somewhere other than the previous one.
local function pushHistory(movement)
    local history = F2T_TRAFFIC.history
    local last = history[#history]
    local info = gmcp and gmcp.room and gmcp.room.info or {}
    if not last or last.roomKey ~= F2T_TRAFFIC.roomKey then
        history[#history + 1] = { id = F2T_TRAFFIC.nextId, roomBreak = true, roomKey = F2T_TRAFFIC.roomKey,
            at = movement.at, text = info.name or info.area or "" }
        F2T_TRAFFIC.nextId = F2T_TRAFFIC.nextId + 1
    end
    history[#history + 1] = { id = F2T_TRAFFIC.nextId, roomKey = F2T_TRAFFIC.roomKey, at = movement.at,
        sign = movement.sign, icon = movement.icon, name = movement.name, rank = movement.rank,
        verb = movement.verb, route = movement.route, ship = movement.ship }
    F2T_TRAFFIC.nextId = F2T_TRAFFIC.nextId + 1
    while #history > HISTORY_LIMIT do table.remove(history, 1) end
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
    F2T_TRAFFIC.movements  = {}
    F2T_TRAFFIC.departed   = {}
    F2T_TRAFFIC.arrivals   = {}
    F2T_TRAFFIC.departures = {}
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
        movement.verb, movement.route = describe(movement, returning)
        movement.order = now
        F2T_TRAFFIC.departed[key] = nil
    else
        movement.verb, movement.route = describe(movement, false)
        -- a departing row keeps its place in the list while it fades
        movement.order = previous and previous.order or 0
        F2T_TRAFFIC.departed[key] = now
    end
    movement.text = movement.route == "" and movement.verb or (movement.verb .. " " .. movement.route)
    movement.ship = movement.ship or (previous and previous.ship)

    F2T_TRAFFIC.movements[key] = movement
    if movement.sign == "+" then
        F2T_TRAFFIC.arrivals[key] = movement
    else
        F2T_TRAFFIC.departures[key] = movement
    end
    pushLog({ at = now, sign = movement.sign, icon = movement.icon, name = movement.name,
              rank = movement.rank, text = movement.text })
    pushHistory(movement)
    changed()
end

-- ── Main console ─────────────────────────────────────────────────────────────

-- ASCII signs: a wider glyph (e.g. U+2212 minus) knocks the columns after it out of line.
local SIGN_DECHO = { ["+"] = "<79,210,122>+", ["-"] = "<229,163,61>-" }
local NAME_DEFAULT_DECHO = "<200,200,200>"
local NAME_COLUMN  = 15   -- longest character name the game allows
local VERB_COLUMN  = 7    -- "arrived"
local ROUTE_COLUMN = 22   -- "by shuttle from planet"

-- A movement as decho pieces in fixed-width columns (sign and icon, name,
-- then verb, route and ship), so every line's columns line up. The name is
-- separate so a caller can make it a link.
function f2tTrafficLineParts(movement)
    local nameColor = movement.rank and f2t_rank_color_decho(movement.rank) or NAME_DEFAULT_DECHO
    local route = movement.route
    local tail = ""
    if movement.ship then
        route = string.format("%-" .. ROUTE_COLUMN .. "s", route)
        tail = "<95,100,128>  " .. movement.ship
    end
    local verb = route == "" and movement.verb or string.format("%-" .. VERB_COLUMN .. "s", movement.verb)
    return SIGN_DECHO[movement.sign] .. " " .. movement.icon .. " ",
        nameColor .. string.format("%-" .. NAME_COLUMN .. "s", movement.name),
        string.format("<150,156,178> %s %s%s<r>", verb, route, tail)
end

function f2tTrafficConsoleLine(movement)
    local lead, name, rest = f2tTrafficLineParts(movement)
    return lead .. name .. rest
end

-- Turns the first occurrence of the name in the current line into a link to
-- their player card.
local function linkName(name)
    if selectString(name, 1) == -1 then return end
    setLink(string.format("f2tPlayerCardShowOrRaiseByName(%q)", name), "Open " .. name .. "'s player card")
    deselect()
end

-- The game hard-wraps long lines at your console width, so a movement can
-- arrive split over two or three lines. These are how one can begin.
local SHIP_PHRASES = {
    "has just entered the sector", "has left the sector", "has just limped into the sector",
    "has fled the sector", "appears from the hyperspace link", "disappears into the hyperspace link",
}
local PERSON_PHRASES = {
    "has just arrived", "has left", "has departed", "has arrived in", "has arrived with",
    "has boarded a shuttle",
}
local MAX_SEGMENTS = 3

local function startsPhrase(tail, phrases)
    for _, phrase in ipairs(phrases) do
        if phrase:sub(1, #tail) == tail or tail:sub(1, #phrase) == phrase then return true end
    end
    return false
end

-- True for the first part of a movement line the game wrapped.
local function wrappedStart(text)
    if text:match("[%.!]$") then return false end
    if text:match("^%u%w*'s ship, [^,]*$") or text:match("^%u%w*'s spaceship, [^,]*$") then return true end
    local tail = text:match("^%u%w*'s ship, .-, (.*)$") or text:match("^%u%w*'s spaceship, .-, (.*)$")
        or text:match("^%u%w*'s ship (.*)$") or text:match("^%u%w*'s spaceship (.*)$")
    if tail then return startsPhrase(tail, SHIP_PHRASES) end
    tail = text:match("^.-%u%w* (has .*)$")
    return tail ~= nil and startsPhrase(tail, PERSON_PHRASES)
end

local held = nil   -- { text, segments } while a wrapped movement line is being joined

-- The game sometimes follows a movement line with an empty one; drop it.
local function dropBlankAfter()
    tempLineTrigger(1, 1, function()
        if line:match("^%s*$") then deleteLine() end
    end)
end

-- Records a complete movement, then keeps, condenses or removes the current
-- line. A joined wrapped line is shown whole on this, its last, line.
local function finish(movement, joinedText)
    f2tTrafficSyncRoom()
    f2tTrafficRecord(movement)
    if f2t_settings_get("traffic", "show_in") == "players" then
        deleteLine()
        dropBlankAfter()
        return
    elseif f2t_settings_get("traffic", "console_style") == "condensed" then
        dreplaceLine("main", f2tTrafficConsoleLine(movement))
    elseif joinedText then
        dreplaceLine("main", "<0,179,0>" .. joinedText .. "<r>")
    end
    linkName(movement.name)
    dropBlankAfter()
end

local function continueWrapped()
    tempLineTrigger(1, 1, function()
        local joined = held.text .. " " .. line:gsub("%s+$", "")
        F2T_TRAFFIC.consumedLine = line
        local movement = f2tTrafficParse(joined)
        if movement then
            held = nil
            finish(movement, joined)
        elseif held.segments < MAX_SEGMENTS and not joined:match("[%.!]$") then
            held.text, held.segments = joined, held.segments + 1
            deleteLine()
            continueWrapped()
        else
            -- not a movement after all: give back the text held from earlier lines
            held = nil
            dreplaceLine("main", joined)
        end
    end)
end

-- Body of the movement trigger.
function f2tTrafficHandleLine()
    if held or F2T_TRAFFIC.consumedLine == line then
        F2T_TRAFFIC.consumedLine = nil
        return
    end
    local text = line:gsub("%s+$", "")
    local movement = f2tTrafficParse(text)
    if movement then
        finish(movement, nil)
    elseif wrappedStart(text) then
        held = { text = text, segments = 1 }
        deleteLine()
        continueWrapped()
    end
end

registerAnonymousEventHandler("gmcp.room.info", function() f2tTrafficSyncRoom() end)

f2t_debug_log("[traffic] module loaded")
