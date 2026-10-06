-- The player's Akaturi contract as the game reports it, whether they work it
-- by hand or hauling automates it. GMCP char.job (type "akaturi") carries the
-- planets, package, payment and collected flag; the pickup and dropoff room
-- titles only appear in the contract text (ak, pickup, di ak), captured here
-- and kept per character so a contract carried over a relog still knows them.
-- Raises "f2tAkaturiContractChanged" whenever anything here changes.

F2T_AKATURI_CONTRACT = nil

-- { signature, pickupRoom, deliveryRoom }; signature ties the rooms to the
-- contract they were read from, nil while text arrived ahead of GMCP.
local rooms = { signature = nil }
local roomsLoaded = false

-- Per-kind index into a room title's map matches, so repeated clicks walk
-- through every room sharing the title.
local matchCursor = { pickup = 0, delivery = 0 }

local function roomsPath() return f2t_get_char_persistent_dir() .. "/akaturi_rooms" end

local function loadRooms()
    local buffer = {}
    local ok = pcall(table.load, roomsPath(), buffer)
    rooms = (ok and type(buffer) == "table") and buffer or { signature = nil }
    roomsLoaded = true
end

local function saveRooms()
    lfs.mkdir(f2t_get_char_persistent_dir())
    local ok, err = pcall(table.save, roomsPath(), rooms)
    if not ok then f2t_debug_log("[akaturi] room save error: %s", tostring(err)) end
end

local function changed()
    raiseEvent("f2tAkaturiContractChanged")
end

local function signatureOf(job)
    return string.format("%s|%s|%s", job.source, job.destination, tostring(job.payment))
end

local function applyRooms()
    local contract = F2T_AKATURI_CONTRACT
    if not contract then return end
    contract.pickupRoom   = rooms.pickupRoom
    contract.deliveryRoom = rooms.deliveryRoom
end

local function onCharJob()
    if not roomsLoaded then loadRooms() end
    local job = gmcp and gmcp.char and gmcp.char.job
    local isAkaturi = type(job) == "table" and job.type == "akaturi"
        and type(job.source) == "string" and type(job.destination) == "string"

    if not isAkaturi then
        if F2T_AKATURI_CONTRACT or rooms.signature then
            F2T_AKATURI_CONTRACT = nil
            rooms = { signature = nil }
            saveRooms()
            changed()
        end
        return
    end

    local signature = signatureOf(job)
    if rooms.signature ~= signature then
        if rooms.signature ~= nil then rooms = {} end
        rooms.signature = signature
        matchCursor = { pickup = 0, delivery = 0 }
        saveRooms()
    end

    F2T_AKATURI_CONTRACT = {
        pickupPlanet   = job.source,
        deliveryPlanet = job.destination,
        package        = type(job.commodity) == "string" and job.commodity or nil,
        payment        = tonumber(job.payment) or 0,
        collected      = job.collected == true,
    }
    applyRooms()
    changed()
end

registerAnonymousEventHandler("gmcp.char.job", onCharJob)
registerAnonymousEventHandler("f2tCharacterChanged", function()
    loadRooms()
    F2T_AKATURI_CONTRACT = nil
    onCharJob()
end)

-- ── Contract text capture ────────────────────────────────────────────────────
-- The room shown between the two "-----" lines starts with its title.

local captureTrigger = nil

local function stopCapture()
    if captureTrigger then killTrigger(captureTrigger) end
    captureTrigger = nil
end

local function recordRoom(kind, room)
    rooms[kind .. "Room"] = room
    applyRooms()
    saveRooms()
    f2t_debug_log("[akaturi] %s room: %s", kind, room)
    changed()
end

--- Begin reading the room that follows a contract header line
--- @param kind string "pickup" or "delivery"
function f2t_akaturi_tracker_capture(kind)
    stopCapture()
    local inSection = false
    captureTrigger = tempLineTrigger(1, 40, function()
        local text = line or ""
        if text:match("^%s*%-%-%-%-%-%s*$") then
            if inSection then stopCapture() end
            inSection = true
            return
        end
        if inSection then
            local title = text:match("^%s*(.-)%s*$")
            if title ~= "" then
                stopCapture()
                recordRoom(kind, title)
            end
        end
    end)
end

-- ── Queries and actions ──────────────────────────────────────────────────────

--- The current contract, or nil when the player doesn't hold one
--- @return table|nil contract
function f2t_akaturi_contract()
    return F2T_AKATURI_CONTRACT
end

--- Whether the player is standing in one of Sol's Armstrong Cuthbert offices
--- @return boolean
function f2t_akaturi_at_office()
    local hash = f2t_get_current_room_hash()
    if not hash then return false end
    for _, officeHash in pairs(F2T_AC_ROOMS) do
        if officeHash == hash then return true end
    end
    return false
end

--- The planet whose AC office to use: this one when it has an office, else Earth
--- @return string planet
function f2t_akaturi_office_planet()
    local here = f2t_get_current_planet()
    if here and F2T_AC_ROOMS[here] then return here end
    return "Earth"
end

--- Walk to the AC office; onArrive(ok) runs once the walk settles
--- @param onArrive function|nil
function f2t_akaturi_go_to_office(onArrive)
    if f2t_akaturi_at_office() then
        if onArrive then onArrive(true) end
        return
    end
    local planet = f2t_akaturi_office_planet()
    cecho(string.format("\n<cyan>[akaturi]<reset> Heading to Armstrong Cuthbert on %s\n", planet))
    f2t_map_navigate(F2T_AC_ROOMS[planet], {
        on_result = function(ok) if onArrive then onArrive(ok and f2t_akaturi_at_office()) end end,
    })
end

--- Go to an AC office if needed and ask for a contract
function f2t_akaturi_take_contract()
    if F2T_AKATURI_CONTRACT then
        cecho("\n<yellow>[akaturi]<reset> You already hold a contract; finish it first.\n")
        return
    end
    f2t_akaturi_go_to_office(function(ok)
        if ok then send("ak") end
    end)
end

--- Walk to the contract's pickup or dropoff room, exploring the planet for it
--- when the map doesn't have it yet
--- @param kind string "pickup" or "delivery"
function f2t_akaturi_go_to_room(kind)
    local contract = F2T_AKATURI_CONTRACT
    if not contract then return end
    if kind == "delivery" and not contract.collected then
        cecho("\n<yellow>[akaturi]<reset> The dropoff is revealed when you collect the package.\n")
        return
    end
    local planet = kind == "pickup" and contract.pickupPlanet or contract.deliveryPlanet
    local room   = kind == "pickup" and contract.pickupRoom or contract.deliveryRoom

    if not room then
        cecho(string.format("\n<yellow>[akaturi]<reset> Room not known yet; asking the game and heading to %s.\n",
            planet))
        send("di ak", false)
        f2t_map_navigate(planet)
        return
    end

    local matches = f2t_akaturi_search_room(planet, room)
    if matches and #matches > 0 then
        local index = matchCursor[kind]
        if index < 1 or index > #matches then index = 1 end
        if matches[index].room_id == F2T_MAP_CURRENT_ROOM_ID then
            index = index % #matches + 1
        end
        matchCursor[kind] = index
        if #matches > 1 then
            cecho(string.format("\n<cyan>[akaturi]<reset> %d rooms are called '%s'; going to number %d. " ..
                "Click again for the next.\n", #matches, room, index))
        end
        f2t_map_navigate(matches[index].room_id)
        return
    end

    cecho(string.format("\n<yellow>[akaturi]<reset> '%s' isn't mapped on %s yet; exploring for it.\n", room, planet))
    f2t_map_explore_planet_start("brief", planet, function(foundRoomId)
        if foundRoomId then
            f2t_map_navigate(foundRoomId)
        else
            cecho(string.format("\n<yellow>[akaturi]<reset> Couldn't find '%s' on %s; look around for it.\n",
                room, planet))
        end
    end, nil, room, true)
end

f2t_debug_log("[akaturi] contract tracker loaded")
