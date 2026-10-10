-- Armstrong Cuthbert hauling job management
-- Provides data structures, room locations, and helper functions for AC jobs.
--
-- Job data is fully live via GMCP (gmcp.jobs.board / gmcp.char.job), same
-- feed the Hauling Jobs content module reads -- no "work" scraping needed.

-- AC room locations in Sol system (Fed2 hashes)
-- These rooms don't have special flags, so we maintain a static lookup
F2T_AC_ROOMS = {
    ["Earth"] = "Sol.Earth.519",
    ["Selena"] = "Sol.Selena.524",
    ["Magellan"] = "Sol.Magellan.1033",
    ["Mercury"] = "Sol.Mercury.520",
    ["Pearl"] = "Sol.Pearl.206",
    ["Paradise"] = "Sol.Paradise.522",
    ["Venus"] = "Sol.Venus.457",
    ["Sumatra"] = "Sol.Sumatra.1095",
    ["Rhea"] = "Sol.Rhea.654",
    ["Titan"] = "Sol.Titan.712",
    ["Castillo"] = "Sol.Castillo.200",
    ["Mars"] = "Sol.Mars.644",
    ["Phobos"] = "Sol.Phobos.342",
    ["Doris"] = "Sol.Doris.529",
    ["The Lattice"] = "Sol.The Lattice.2406",
    ["Brass"] = "Sol.Brass.263",
    ["Silk"] = "Sol.Silk.457"
}

--- Get the Fed2 hash for an AC room on a given planet
--- @param planet string Planet name (e.g., "Earth", "The Lattice")
--- @return string|nil Fed2 hash or nil if not found
function f2t_ac_get_room_hash(planet)
    -- For Sol planets, return the specific AC room hash
    if F2T_AC_ROOMS[planet] then
        return F2T_AC_ROOMS[planet]
    end

    -- For non-Sol planets, return the planet name (map will navigate to shuttlepad)
    return planet
end

--- Check if we're currently at an AC room
--- @return boolean True if at an AC room
function f2t_ac_at_room()
    -- Check Sol AC rooms (specific room hashes)
    local current_hash = f2t_get_current_room_hash()
    if current_hash then
        for planet, hash in pairs(F2T_AC_ROOMS) do
            if hash == current_hash then
                f2t_debug_log("[hauling/ac] At Sol AC room: %s", planet)
                return true
            end
        end
    end

    -- Outside Sol, AC room is the shuttlepad
    if f2t_has_room_flag("shuttlepad") then
        local current_planet = f2t_get_current_planet()
        f2t_debug_log("[hauling/ac] At shuttlepad AC room: %s", current_planet or "unknown")
        return true
    end

    return false
end

--- Get the planet name of the current AC room
--- @return string|nil Planet name or nil if not at AC room
function f2t_ac_get_current_planet()
    -- Check Sol AC rooms first
    local current_hash = f2t_get_current_room_hash()
    if current_hash then
        for planet, hash in pairs(F2T_AC_ROOMS) do
            if hash == current_hash then
                return planet
            end
        end
    end

    -- Outside Sol, if at shuttlepad, return the area (planet name)
    if f2t_has_room_flag("shuttlepad") then
        return f2t_get_current_planet()
    end

    return nil
end

--- Get the live AC job board from GMCP. The server keeps this updated in
--- real time (same feed the Hauling Jobs content module reads), so a
--- listing being present here means it's currently acceptable.
--- @return table Array of job entries (id, source, destination, commodity, quantity, gtu, payment, credits, totalValue)
function f2t_ac_get_board()
    local board = gmcp and gmcp.jobs and gmcp.jobs.board
    if type(board) ~= "table" then
        return {}
    end
    return board
end

--- Whether a given job id is still listed on the live board
--- @param job_id number
--- @return boolean
function f2t_ac_board_has_job(job_id)
    for _, entry in ipairs(f2t_ac_get_board()) do
        if entry.id == job_id then
            return true
        end
    end
    return false
end

--- gmcp.char.job carries a stray {offer=<userdata>} placeholder when there's
--- no real contract; only source/destination being real strings means an
--- actual job is active. An Adventurer's Akaturi contract arrives on the same
--- key with type "akaturi" and is not an AC job.
--- @param job table|nil
--- @return boolean
function f2t_ac_job_is_active(job)
    return type(job) == "table" and job.type ~= "akaturi"
        and type(job.source) == "string" and type(job.destination) == "string"
end

--- Get the player's current AC contract from GMCP, or nil if none accepted
--- @return table|nil
function f2t_ac_get_current_job()
    local job = gmcp and gmcp.char and gmcp.char.job
    if f2t_ac_job_is_active(job) then
        return job
    end
    return nil
end

--- Whether the live gmcp.char.job matches the job we selected/accepted
--- @param selected table Job entry we selected from the board
--- @return boolean
function f2t_ac_current_job_matches(selected)
    local current = f2t_ac_get_current_job()
    if not current or not selected then
        return false
    end
    return current.source == selected.source
        and current.destination == selected.destination
        and current.commodity == selected.commodity
end

--- Get hauling credits from GMCP data
--- @return number|nil Hauling credits or nil if not available
function f2t_ac_get_hauling_credits()
    if not gmcp or not gmcp.char or not gmcp.char.vitals or not gmcp.char.vitals.points then
        return nil
    end

    local points = gmcp.char.vitals.points
    if points.type == "hc" then
        return tonumber(points.amt) or 0
    end

    return nil
end

--- Check if player has enough hauling credits to advance
--- @return boolean True if has 500+ credits
function f2t_ac_has_enough_credits()
    local credits = f2t_ac_get_hauling_credits()
    if not credits then
        return false
    end
    return credits >= 500
end

--- Check if player has reached the 50 credit milestone
--- @return boolean True if has 50+ credits
function f2t_ac_reached_50_credits()
    local credits = f2t_ac_get_hauling_credits()
    if not credits then
        return false
    end
    return credits >= 50
end

--- Get current loan amount from GMCP
--- @return number|nil Loan amount or nil if not available
function f2t_ac_get_loan_amount()
    if not gmcp or not gmcp.char or not gmcp.char.vitals then
        return nil
    end
    return tonumber(gmcp.char.vitals.loan) or 0
end

--- Get current cash from GMCP
--- @return number|nil Cash amount or nil if not available
function f2t_ac_get_cash()
    if not gmcp or not gmcp.char or not gmcp.char.vitals then
        return nil
    end
    return tonumber(gmcp.char.vitals.cash) or 0
end

--- Check if player should repay their loan
--- Returns true if: has outstanding loan AND cash >= loan + 10000
--- @return boolean True if should repay loan
--- @return number|nil Loan amount to repay
function f2t_ac_should_repay_loan()
    local loan = f2t_ac_get_loan_amount()
    local cash = f2t_ac_get_cash()

    if not loan or not cash then
        return false, nil
    end

    -- No loan to repay
    if loan <= 0 then
        return false, nil
    end

    -- Check if we have enough cash (loan + 10k buffer)
    if cash >= (loan + 10000) then
        f2t_debug_log("[hauling/ac] Loan repayment eligible: cash=%d, loan=%d", cash, loan)
        return true, loan
    end

    return false, nil
end

--- Map room holding a planet's AC office: the fixed Sol room, else the shuttlepad
--- @param planet string
--- @return number|nil
local function acRoomId(planet)
    local hash = F2T_AC_ROOMS[planet]
    if hash then return f2t_map_get_room_by_hash(hash) end
    return f2t_map_find_shuttlepad_room(planet)
end

--- Moves on the mapped route between two rooms, and how many of them are in space
--- @return number|nil moves nil when the map has no route
--- @return number|nil spaceMoves
local function routeLength(fromId, toId)
    if not fromId or not toId then return nil end
    if fromId == toId then return 0, 0 end
    if not getPath(fromId, toId) then return nil end
    local spaceMoves = 0
    for _, roomId in ipairs(speedWalkPath) do
        local areaName = getRoomAreaName(getRoomArea(tonumber(roomId)))
        if type(areaName) == "string" and f2t_map_get_system_from_space_area(areaName) then
            spaceMoves = spaceMoves + 1
        end
    end
    return #speedWalkPath, spaceMoves
end

--- Travel and expected pay for a job. The contract clock (gtu) ticks once per
--- move in space after accepting, so only the source-to-destination leg counts
--- toward the late penalty (half pay) or the fast-delivery bonus (+20% within 2/3).
--- @return table { toSource = number, leg = number, fee = number } (moves are math.huge when unmapped)
local function assessJob(job, hereId)
    local sourceId = acRoomId(job.source)
    local toSource = hereId and routeLength(hereId, sourceId)
    local leg, legSpaceMoves = routeLength(sourceId, acRoomId(job.destination))

    local fee = job.quantity * job.payment
    local gtu = tonumber(job.gtu)
    if legSpaceMoves and gtu then
        if legSpaceMoves > gtu then
            fee = fee / 2
        elseif legSpaceMoves <= (gtu * 2) / 3 then
            fee = fee * 6 / 5
        end
    end

    return { toSource = toSource or math.huge, leg = leg or math.huge, fee = fee }
end

--- Select the best AC job from the live board: most hauling credits first, then
--- per the hauling/ac_priority setting:
--- shortest = fewest moves from here to the job's source, then shortest delivery;
--- return = highest expected fee
--- @param jobs table Array of gmcp.jobs.board entries
--- @param current_planet string|nil Current planet name
--- @param ship_capacity number Ship cargo capacity in tons
--- @return table|nil Best job or nil if none suitable
function f2t_ac_select_best_job(jobs, current_planet, ship_capacity)
    if not jobs or #jobs == 0 then
        f2t_debug_log("[hauling/ac] No jobs to select from")
        return nil
    end

    -- Filter jobs that fit in ship capacity
    local suitable_jobs = {}
    local unreachable = F2T_HAULING_STATE.ac_unreachable or {}
    for _, job in ipairs(jobs) do
        if unreachable[job.id] then
            f2t_debug_log("[hauling/ac] Job %d skipped, its source couldn't be reached", job.id)
        elseif job.quantity <= ship_capacity then
            table.insert(suitable_jobs, job)
        else
            f2t_debug_log("[hauling/ac] Job %d requires %d tons but ship capacity is %d",
                job.id, job.quantity, ship_capacity)
        end
    end

    if #suitable_jobs == 0 then
        f2t_debug_log("[hauling/ac] No suitable jobs for ship capacity %d", ship_capacity)
        return nil
    end

    local hereId = F2T_MAP_CURRENT_ROOM_ID
    local assessment = {}
    for _, job in ipairs(suitable_jobs) do
        assessment[job] = assessJob(job, hereId)
    end

    local shortest = f2t_settings_get("hauling", "ac_priority") ~= "return"
    table.sort(suitable_jobs, function(a, b)
        local aInfo, bInfo = assessment[a], assessment[b]
        if a.credits ~= b.credits then return a.credits > b.credits end
        if shortest then
            if aInfo.toSource ~= bInfo.toSource then return aInfo.toSource < bInfo.toSource end
            if aInfo.leg ~= bInfo.leg then return aInfo.leg < bInfo.leg end
            if aInfo.fee ~= bInfo.fee then return aInfo.fee > bInfo.fee end
        else
            if aInfo.fee ~= bInfo.fee then return aInfo.fee > bInfo.fee end
            if aInfo.toSource ~= bInfo.toSource then return aInfo.toSource < bInfo.toSource end
        end

        if current_planet then
            local a_at_source = (a.source == current_planet)
            local b_at_source = (b.source == current_planet)
            if a_at_source ~= b_at_source then
                return a_at_source
            end
        end

        return a.id < b.id
    end)

    local best_job = suitable_jobs[1]
    local best_info = assessment[best_job]
    local function movesText(moves) return moves == math.huge and "?" or tostring(moves) end
    f2t_debug_log("[hauling/ac] Selected job %d (%s): %s from %s to %s (%dig/tn, %dhcr, " ..
        "%s moves to source, %s to deliver, ~%dig)",
        best_job.id, shortest and "shortest" or "return",
        best_job.commodity, best_job.source, best_job.destination,
        best_job.payment, best_job.credits,
        movesText(best_info.toSource), movesText(best_info.leg), math.floor(best_info.fee))

    return best_job
end

f2t_debug_log("[hauling/ac] Armstrong Cuthbert module loaded")
