-- The player's Akaturi contract as the game reports it, whether they work it
-- by hand or hauling automates it. GMCP char.job (type "akaturi") carries the
-- planets, package, payment and collected flag; the pickup and dropoff room
-- titles only appear in the contract text (ak, pickup, di ak), captured here
-- and kept per character so a contract carried over a relog still knows them.
-- Raises "f2tAkaturiContractChanged" whenever anything here changes.

F2T_AKATURI_CONTRACT = nil

-- Rank needed for ak; credits needed, with cash in the bank, to promote.
F2T_AKATURI_RANK          = "Adventurer"
F2T_AKATURI_PROMOTE_AT    = 25
F2T_AKATURI_PROMOTE_CASH  = 55000
-- An Adventurer's cash above this is taxed at their next login.
F2T_AKATURI_CASH_CAP      = 600000

-- { signature, pickupRoom, deliveryRoom }; signature ties the rooms to the
-- contract they were read from, nil while text arrived ahead of GMCP.
local rooms = { signature = nil }
local roomsLoaded = false
local detailsAsked = nil
-- Deaths while holding the current contract
local contractDeaths = 0

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

--- The leg the contract is on and where it is
--- @param contract table
--- @return string kind "pickup" or "delivery"
--- @return string planet
--- @return string|nil room
function f2t_akaturi_leg(contract)
    if contract.collected then
        return "delivery", contract.deliveryPlanet, contract.deliveryRoom
    end
    return "pickup", contract.pickupPlanet, contract.pickupRoom
end

-- A contract seen without its room (taken before this was installed, or the
-- text scrolled past unread) asks the game once; the delay lets the text that
-- follows ak/pickup arrive first.
local function askForMissingRoom()
    tempTimer(2, function()
        local contract = F2T_AKATURI_CONTRACT
        if not contract then return end
        local kind, _, room = f2t_akaturi_leg(contract)
        local key = rooms.signature .. "|" .. kind
        if room or detailsAsked == key then return end
        if F2T_HAULING_STATE and F2T_HAULING_STATE.active and F2T_HAULING_STATE.mode == "akaturi" then return end
        detailsAsked = key
        send("di ak", false)
    end)
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
        contractDeaths = 0
        rooms.signature = signature
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
    askForMissingRoom()
end

registerAnonymousEventHandler("gmcp.char.job", onCharJob)
registerAnonymousEventHandler("f2tCharacterChanged", function()
    loadRooms()
    F2T_AKATURI_CONTRACT = nil
    detailsAsked = nil
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
    room = room:gsub("%s*%(Not patrolled%)$", "")
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
    -- From 0 so the first line offered is checked: Mudlet versions differ on
    -- whether a trigger made mid-line also sees that line, and starting at 1
    -- would then skip the opening "-----".
    captureTrigger = tempLineTrigger(0, 40, function()
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

-- ── Queries ──────────────────────────────────────────────────────────────────

--- The current contract, or nil when the player doesn't hold one
--- @return table|nil contract
function f2t_akaturi_contract()
    return F2T_AKATURI_CONTRACT
end

--- Whether the player's rank takes Akaturi contracts
--- @return boolean
function f2t_akaturi_rank_ok()
    local level = f2t_get_rank_level(f2t_get_rank())
    return level ~= nil and level == f2t_get_rank_level(F2T_AKATURI_RANK)
end

--- Whether ak works here: a Sol room the game flags as a courier office.
--- Akaturi work is Sol-only, so contracts are only ever taken in Sol.
--- @return boolean
function f2t_akaturi_at_office()
    if f2t_get_current_system() ~= "Sol" then return false end
    if f2t_has_room_flag("courier") then return true end
    local hash = f2t_get_current_room_hash()
    if not hash then return false end
    for _, officeHash in pairs(F2T_AC_ROOMS) do
        if officeHash == hash then return true end
    end
    return false
end

--- Where to take a contract: this Sol planet's AC office, else Earth's
--- (which is also where a walk from outside Sol goes)
--- @return string destination
--- @return string label
function f2t_akaturi_office_target()
    local here = f2t_get_current_planet()
    if f2t_get_current_system() == "Sol" and here and F2T_AC_ROOMS[here] then
        return F2T_AC_ROOMS[here], here
    end
    return F2T_AC_ROOMS.Earth, "Earth"
end

-- ── Deaths ───────────────────────────────────────────────────────────────────
-- An insured death keeps the contract, collected package included (the server
-- only drops AC cargo jobs), and wakes the player in a hospital. Death recovery
-- locks the room that killed them; a second death on one contract means the
-- danger is somewhere the lock didn't cover, so nothing resumes by itself then.

registerAnonymousEventHandler("f2tDeathDetected", function()
    if F2T_AKATURI_CONTRACT then contractDeaths = contractDeaths + 1 end
end)

--- Why Akaturi work must not carry on by itself after a death, or nil if it may
--- @param insured boolean|nil whether death recovery reports the player insured again
--- @return string|nil reason
function f2t_akaturi_death_hold_reason(insured)
    if not F2T_AKATURI_CONTRACT then return "the contract is gone" end
    if insured ~= true then return "not insured again, so another death would be permanent" end
    if contractDeaths >= 2 then return "died twice on this contract" end
    return nil
end

-- ── Actions ──────────────────────────────────────────────────────────────────

--- Walk to the AC office; onArrive(ok) runs once the walk settles
--- @param onArrive function|nil
function f2t_akaturi_go_to_office(onArrive)
    if f2t_akaturi_at_office() then
        if onArrive then onArrive(true) end
        return
    end
    local destination, label = f2t_akaturi_office_target()
    cecho(string.format("\n<cyan>[akaturi]<reset> Heading to take a contract at %s\n", label))
    f2tNav.go(destination, { owner = "akaturi", onDone = function(result)
        if onArrive then onArrive(result.status == "arrived" and f2t_akaturi_at_office()) end
    end })
end

--- Go to an AC office if needed and ask for a contract
function f2t_akaturi_take_contract()
    if F2T_AKATURI_CONTRACT then
        cecho("\n<yellow>[akaturi]<reset> You already hold a contract; finish it first.\n")
        return
    end
    if not f2t_akaturi_rank_ok() then
        cecho("\n<yellow>[akaturi]<reset> Akaturi contracts are for Adventurers.\n")
        return
    end
    if not f2t_insurance_allows() then
        f2t_insurance_check("doing Akaturi work", f2t_akaturi_take_contract)
        return
    end
    f2t_akaturi_go_to_office(function(ok)
        if ok then
            send("ak")
        else
            cecho("\n<yellow>[akaturi]<reset> Didn't reach an Armstrong Cuthbert office; ak only works in one.\n")
        end
    end)
end

--- Pick up or drop off in the room the player is standing in, nothing more
function f2t_akaturi_act_here()
    local contract = F2T_AKATURI_CONTRACT
    if not contract then return end
    send(contract.collected and "dropoff" or "pickup")
end

--- Carry the held contract's current leg out automatically: find the pickup or
--- dropoff room and pick up or drop off there
function f2t_akaturi_work_leg()
    local contract = F2T_AKATURI_CONTRACT
    if not contract then
        f2t_akaturi_take_contract()
        return
    end
    if not f2t_insurance_allows() then
        f2t_insurance_check("doing Akaturi work", f2t_akaturi_work_leg)
        return
    end
    local kind, planet, room = f2t_akaturi_leg(contract)
    if not room then
        cecho("\n<yellow>[akaturi]<reset> Reading the room from the contract first.\n")
        local handlerId
        handlerId = registerAnonymousEventHandler("f2tAkaturiContractChanged", function()
            local held = F2T_AKATURI_CONTRACT
            if not held then killAnonymousEventHandler(handlerId) return end
            local _, _, known = f2t_akaturi_leg(held)
            if known then
                killAnonymousEventHandler(handlerId)
                f2t_akaturi_work_leg()
            end
        end)
        tempTimer(5, function() killAnonymousEventHandler(handlerId) end)
        send("di ak", false)
        return
    end
    f2t_akaturi_visit(kind, { planet = planet, room = room, owner = "manual" })
end

f2t_debug_log("[akaturi] contract tracker loaded")
