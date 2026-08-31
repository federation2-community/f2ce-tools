-- Galaxy topology model.
--
-- Jump legality is a pure function of: which cartel each system belongs to,
-- which syndicate each cartel belongs to, each hub system (cartel hub ==
-- cartel name, syndicate hub cartel == syndicate name, except Prime whose hub
-- is Sol), and each syndicate's beacon builds. This module owns those facts
-- and derives every link room's "jump <system>" special exits from them, so
-- Mudlet's native getPath() plans over exactly the legal jump graph.
-- Sources of truth: gmcp.room.info.jumps corrects the model as you travel
-- (f2t_map_topology_apply_gmcp); "display cartels"/"display syndicates"
-- captures sync it wholesale (topology_capture.lua).
--
-- Rule set (verified against game server code):
--   1. Always: any member system -> every accepted member of its own cartel.
--   2. From a cartel hub: -> every other cartel hub in the same syndicate.
--   3. Hub Beacon (never Prime): from anywhere in the syndicate -> every
--      accepted member system of every sibling cartel.
--   4. From the syndicate hub system: -> every other syndicate's hub system.
--   5. Distant Beacon (never Prime): from anywhere in the syndicate -> every
--      other syndicate's hub system.
-- Jump edges are directed; destination-side builds never affect legality, so
-- never create a reverse exit by symmetry.

-- systems[name]    = cartel name (accepted members only)
-- cartels[name]    = syndicate name, or false when the cartel is known but
--                    its syndicate is not yet
-- syndicates[name] = {hub_beacon=bool, distant_beacon=bool}
-- closed[name]     = os.time() of a refusal that proved the system shut to
--                    *this* player. Membership and openness are separate
--                    facts: membership makes an edge legal, openness makes it
--                    usable. Absence means open, never unknown-so-closed -
--                    the server's own lists are per-player, so a system it
--                    stops offering may simply be out of rules range.
-- exiled[name]     = os.time() you were turned back at that system's border.
--                    Kept apart from closed: the server deliberately still
--                    offers jumps to systems you are exiled from, so GMCP
--                    presence retires a closure but never an exile.
-- refused[from][to] = os.time() the server denied a specific edge outright
--                    ("no direct link"). Directed, and dropped on the next
--                    successful sync, which re-derives from authority.
F2T_MAP_TOPOLOGY = F2T_MAP_TOPOLOGY or {systems = {}, cartels = {}, syndicates = {},
    closed = {}, exiled = {}, refused = {}, synced_at = nil}
F2T_MAP_TOPOLOGY_LOADED = F2T_MAP_TOPOLOGY_LOADED or false
F2T_MAP_TOPOLOGY_REBUILD_TIMER = F2T_MAP_TOPOLOGY_REBUILD_TIMER or nil
F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC = F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC or 0

local MAP_USERDATA_KEY = "f2t_topology"
local AUTO_SYNC_COOLDOWN = 300

function f2t_map_topology_hub_system(syndicate_name)
    if syndicate_name == "Prime" then return "Sol" end
    return syndicate_name
end

function f2t_map_topology_save()
    local ok, encoded = pcall(yajl.to_string, F2T_MAP_TOPOLOGY)
    if ok and encoded then setMapUserData(MAP_USERDATA_KEY, encoded) end
end

function f2t_map_topology_load()
    local raw = getMapUserData(MAP_USERDATA_KEY)
    if raw and raw ~= "" then
        local ok, decoded = pcall(yajl.to_value, raw)
        if ok and type(decoded) == "table" and type(decoded.systems) == "table" then
            F2T_MAP_TOPOLOGY = {
                systems    = decoded.systems or {},
                cartels    = decoded.cartels or {},
                syndicates = decoded.syndicates or {},
                closed     = decoded.closed or {},
                exiled     = decoded.exiled or {},
                refused    = decoded.refused or {},
                synced_at  = decoded.synced_at,
            }
        end
    end
    f2t_map_topology_bootstrap()
    F2T_MAP_TOPOLOGY_LOADED = true

    -- Re-derive the jump graph before anything gets a chance to plan over it.
    -- A map can hold two link rooms for one system - a system whose space map
    -- the game has since rebuilt (a Dyson Sphere going up renumbers it) leaves
    -- the imported one stranded, with its own orbits and planets hanging off
    -- it. Nothing connects that half to the live one except stale "jump X"
    -- exits still pointing into it, and getPath will happily route out of the
    -- system and back in to use one. The rebuild repoints every jump exit at
    -- the canonical link room, which strands the dead half where it belongs;
    -- doing it on arrival, as we used to, is a walk too late.
    f2t_map_topology_request_rebuild()
end

function f2t_map_topology_ensure_loaded()
    if not F2T_MAP_TOPOLOGY_LOADED then f2t_map_topology_load() end
end

-- Seed system->cartel, and cartel->syndicate where already known, from the
-- mapped areas' userdata so a map that predates the model (bundled starter
-- maps included) starts with as much knowledge as it can without a sync.
function f2t_map_topology_bootstrap()
    local t = F2T_MAP_TOPOLOGY
    for area_name, area_id in pairs(getAreaTable()) do
        local system = f2t_map_get_system_from_space_area(area_name)
        if system and not t.systems[system] then
            local cartel = getAreaUserData(area_id, "fed2_cartel")
            if cartel and cartel ~= "" then
                t.systems[system] = cartel
                if t.cartels[cartel] == nil then
                    local syndicate = getAreaUserData(area_id, "fed2_syndicate")
                    t.cartels[cartel] = (syndicate and syndicate ~= "") and syndicate or false
                end
            end
        end
    end
end

-- The game does not care about case and neither should this. Names reach the
-- model from typed commands, captured text and GMCP, and the spelling varies;
-- matching on the exact string means one system can end up in the model twice
-- under two spellings, and a lookup can miss a place it already knows. Every
-- key goes in and comes out through these.
local function canonicalKey(tbl, name)
    if not name or name == "" then return nil end
    if tbl[name] ~= nil then return name end
    local lowered = string.lower(name)
    for key in pairs(tbl) do
        if string.lower(key) == lowered then return key end
    end
    return nil
end

-- The single sink for "system X is in cartel Y, of syndicate Z" facts,
-- whichever source produced them: GMCP, whereis, a cartel roster, a system
-- listing. Purely additive - none of those sources can prove a membership is
-- gone, only that one exists. Returns true when a fact changed.
function f2t_map_topology_learn(system, cartel, syndicate)
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY
    local changed = false

    -- Keep the spelling the model already has. Without this the same place
    -- arrives as "Apocalypse" from whereis and "apocalypse" from a typed
    -- command and the model grows both, after which half the lookups miss.
    system    = canonicalKey(t.systems, system) or system
    cartel    = canonicalKey(t.cartels, cartel) or cartel
    syndicate = canonicalKey(t.syndicates, syndicate) or syndicate

    if system and system ~= "" and cartel and cartel ~= "" and t.systems[system] ~= cartel then
        t.systems[system] = cartel
        changed = true
    end

    if cartel and cartel ~= "" then
        if syndicate and syndicate ~= "" then
            if t.cartels[cartel] ~= syndicate then
                t.cartels[cartel] = syndicate
                changed = true
            end
        elseif t.cartels[cartel] == nil then
            t.cartels[cartel] = false
            changed = true
        end
    end

    -- A syndicate's bare existence is itself a fact rules 4 and 5 need: its
    -- hub is a legal destination from every other syndicate hub regardless of
    -- what else we know about it.
    if syndicate and syndicate ~= "" and t.syndicates[syndicate] == nil then
        t.syndicates[syndicate] = {}
        changed = true
    end

    return changed
end

-- Record that the server refused travel into a system because it is closed.
-- Per-player: a system owner is exempt, so this is only ever what *you* were
-- told, and it is cleared the moment the server offers the jump again.
function f2t_map_topology_mark_closed(system)
    if not system or system == "" then return false end
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY
    t.closed = t.closed or {}
    if t.closed[system] then return false end
    t.closed[system] = os.time()
    return true
end

-- The server offering a jump into a system is positive proof it is open to
-- you, which retires any earlier closure.
function f2t_map_topology_mark_open(system)
    if not system or system == "" then return false end
    local t = F2T_MAP_TOPOLOGY
    if not t.closed or not t.closed[system] then return false end
    t.closed[system] = nil
    return true
end

function f2t_map_topology_is_closed(system)
    return canonicalKey(F2T_MAP_TOPOLOGY.closed or {}, system) ~= nil
end

-- Exile is per-player and, unlike closure, is left visible in the server's
-- jump lists on purpose, so only actually standing in the system retires it.
function f2t_map_topology_mark_exiled(system)
    if not system or system == "" then return false end
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY
    t.exiled = t.exiled or {}
    if t.exiled[system] then return false end
    t.exiled[system] = os.time()
    return true
end

function f2t_map_topology_clear_exile(system)
    local t = F2T_MAP_TOPOLOGY
    if not system or not t.exiled or not t.exiled[system] then return false end
    t.exiled[system] = nil
    return true
end

-- Closed and exiled are different reasons with the same consequence: the
-- rules say the edge is legal and the server will still turn you away.
function f2t_map_topology_is_barred(system)
    local t = F2T_MAP_TOPOLOGY
    return canonicalKey(t.closed or {}, system) ~= nil
        or canonicalKey(t.exiled or {}, system) ~= nil
end

-- A refused edge, recorded against the model rather than only against the
-- room, so a rebuild cannot re-derive what the server just denied.
function f2t_map_topology_mark_refused(from_system, to_system)
    if not from_system or not to_system or from_system == "" or to_system == "" then return false end
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY
    t.refused = t.refused or {}
    local from = t.refused[from_system]
    if not from then
        from = {}
        t.refused[from_system] = from
    end
    if from[to_system] then return false end
    from[to_system] = os.time()
    return true
end

function f2t_map_topology_clear_refusal(from_system, to_system)
    local t = F2T_MAP_TOPOLOGY
    local from = t.refused and t.refused[from_system]
    if not from or not from[to_system] then return false end
    from[to_system] = nil
    if next(from) == nil then t.refused[from_system] = nil end
    return true
end

-- Persist and re-derive after a batch of learn() calls. Takes the accumulated
-- changed flag so callers read as "learn, learn, commit".
function f2t_map_topology_commit(changed)
    if not changed then return false end
    f2t_map_topology_save()
    f2t_map_topology_request_rebuild()
    return true
end

-- The name of a place as the model already spells it, or nil when it is new.
-- Systems and cartels share a namespace here on purpose: a cartel hub is a
-- system of the same name, and callers routinely have only one of the two.
function f2t_map_topology_canonical_system(name)
    local t = F2T_MAP_TOPOLOGY
    return canonicalKey(t.systems, name) or canonicalKey(t.cartels, name)
end

function f2t_map_topology_canonical_cartel(name)
    return canonicalKey(F2T_MAP_TOPOLOGY.cartels, name)
end

function f2t_map_topology_canonical_syndicate(name)
    return canonicalKey(F2T_MAP_TOPOLOGY.syndicates, name)
end

function f2t_map_topology_grouping_known(cartel)
    cartel = canonicalKey(F2T_MAP_TOPOLOGY.cartels, cartel) or cartel
    return type(F2T_MAP_TOPOLOGY.cartels[cartel]) == "string"
end

-- True when the model can positively place a system in the jump graph: it
-- knows the system's cartel and that cartel's syndicate. Only then does "the
-- rules don't derive an edge to it" mean the edge is illegal rather than
-- merely underived - absence of knowledge is not evidence of illegality.
function f2t_map_topology_placed(system)
    system = f2t_map_topology_canonical_system(system) or system
    local cartel = F2T_MAP_TOPOLOGY.systems[system]
    return cartel ~= nil and f2t_map_topology_grouping_known(cartel)
end

-- Legal jump destinations (set of system names) for a system, from the five
-- rules. Returns nil when the system's cartel is unknown; when the cartel's
-- syndicate is unknown only rule 1 can be derived and `complete` is false.
function f2t_map_topology_jump_destinations(system)
    local t = F2T_MAP_TOPOLOGY
    system = f2t_map_topology_canonical_system(system) or system
    local cartel = t.systems[system]
    if not cartel then return nil, false end

    local refused = (t.refused or {})[system] or {}
    local function usable(name)
        return not refused[name] and not f2t_map_topology_is_barred(name)
    end

    local dests = {}
    for name, c in pairs(t.systems) do
        if c == cartel and name ~= system then dests[name] = true end
    end
    if cartel ~= system then dests[cartel] = true end

    local syndicate = t.cartels[cartel]
    if type(syndicate) ~= "string" then
        for name in pairs(dests) do
            if not usable(name) then dests[name] = nil end
        end
        return dests, false
    end

    local syn = t.syndicates[syndicate] or {}
    local is_prime = (syndicate == "Prime")

    if system == cartel then
        for cname, y in pairs(t.cartels) do
            if y == syndicate and cname ~= cartel then dests[cname] = true end
        end
    end

    if syn.hub_beacon and not is_prime then
        for name, c in pairs(t.systems) do
            if c ~= cartel and t.cartels[c] == syndicate and name ~= system then
                dests[name] = true
            end
        end
        for cname, y in pairs(t.cartels) do
            if y == syndicate and cname ~= cartel then dests[cname] = true end
        end
    end

    local hub_system = f2t_map_topology_hub_system(syndicate)
    if system == hub_system or (syn.distant_beacon and not is_prime) then
        for yname, _ in pairs(t.syndicates) do
            if yname ~= syndicate then
                dests[f2t_map_topology_hub_system(yname)] = true
            end
        end
    end

    dests[system] = nil
    for name in pairs(dests) do
        if not usable(name) then dests[name] = nil end
    end
    return dests, true
end

-- Index of system name -> link room id for every mapped system space area.
function f2t_map_topology_link_room_index()
    local index = {}
    for area_name, area_id in pairs(getAreaTable()) do
        local system = f2t_map_get_system_from_space_area(area_name)
        if system then
            local link_room = f2t_map_find_link_room(area_id)
            if link_room then index[system] = link_room end
        end
    end
    return index
end

-- Reconcile every mapped link room's "jump ___" special exits with the model.
-- Rooms whose syndicate grouping is still unknown are left untouched (their
-- exits keep whatever GMCP last applied directly) rather than stripped down
-- to a rule-1-only set. Removal is likewise gated on positive knowledge of
-- the destination, so an incomplete model never deletes an edge GMCP just
-- proved legal.
function f2t_map_topology_rebuild_exits()
    f2t_map_topology_ensure_loaded()
    local index = f2t_map_topology_link_room_index()
    local rebuilt, skipped, changed_exits = 0, 0, 0

    for system, room_id in pairs(index) do
        local cartel = F2T_MAP_TOPOLOGY.systems[system]
        if cartel and f2t_map_topology_grouping_known(cartel) then
            local dests = f2t_map_topology_jump_destinations(system)
            local wanted = {}
            for dest in pairs(dests or {}) do
                local dest_room = index[dest]
                if dest_room and dest_room ~= room_id then
                    wanted[string.format("jump %s", dest)] = dest_room
                end
            end

            local existing = getSpecialExitsSwap(room_id) or {}
            local to_remove = {}
            for command, dest_room in pairs(existing) do
                local dest = type(command) == "string" and string.match(command, "^jump (.+)$")
                if dest then
                    if wanted[command] == dest_room then
                        wanted[command] = nil
                    elseif wanted[command] or f2t_map_topology_placed(dest)
                        or f2t_map_topology_is_barred(dest)
                        or (((F2T_MAP_TOPOLOGY.refused or {})[system] or {})[dest] ~= nil) then
                        table.insert(to_remove, command)
                    end
                end
            end
            for _, command in ipairs(to_remove) do
                removeSpecialExit(room_id, command)
                changed_exits = changed_exits + 1
            end
            for command, dest_room in pairs(wanted) do
                addSpecialExit(room_id, dest_room, command)
                changed_exits = changed_exits + 1
            end
            rebuilt = rebuilt + 1
        else
            skipped = skipped + 1
        end
    end

    f2t_debug_log("[map/topology] Rebuilt jump exits: %d system(s), %d exit change(s), %d skipped (grouping unknown)",
        rebuilt, changed_exits, skipped)
    return rebuilt, skipped, changed_exits
end

-- Debounced rebuild so bursts of model changes (captures, GMCP) coalesce.
function f2t_map_topology_request_rebuild()
    if F2T_MAP_TOPOLOGY_REBUILD_TIMER then killTimer(F2T_MAP_TOPOLOGY_REBUILD_TIMER) end
    F2T_MAP_TOPOLOGY_REBUILD_TIMER = tempTimer(0.3, function()
        F2T_MAP_TOPOLOGY_REBUILD_TIMER = nil
        f2t_map_topology_rebuild_exits()
    end)
end

-- Correct the model from gmcp.room.info at a link room. The payload is exact
-- ground truth for this source system at this moment; a single observation
-- can therefore fix every room in the affected cartel/syndicate. `syndicate`
-- and `jumps.hub_beacon`/`jumps.distant_beacon` come straight from the server
-- (fed2-community PR #382, live), so beacon state is read rather than
-- inferred. Returns true when any fact changed (a rebuild is then requested
-- by the caller).
function f2t_map_topology_apply_gmcp(system, cartel, syndicate, jumps)
    if not system or not cartel or not jumps then return false end
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY
    local changed = f2t_map_topology_learn(system, cartel, syndicate)

    -- jumps.local is this cartel's accepted roster as offered to you right
    -- now - a rank/standing/permit-gated snapshot, so a name missing from it
    -- proves nothing. Add members; never prune. Pruning belongs to a full
    -- sync, which sees the authoritative listing.
    for _, dest in ipairs(jumps["local"] or {}) do
        if f2t_map_topology_learn(dest, cartel, syndicate) then changed = true end
    end

    -- The server filters its jump lists per player, so anything still offered
    -- is open to us - including our own system, which we are standing in, and
    -- which we have plainly not been turned back from.
    if f2t_map_topology_mark_open(system) then changed = true end
    if f2t_map_topology_clear_exile(system) then changed = true end
    for _, list in ipairs({"local", "intra_syndicate", "inter_syndicate"}) do
        for _, dest in ipairs(jumps[list] or {}) do
            if f2t_map_topology_mark_open(dest) then changed = true end
        end
    end

    local syn_name = t.cartels[cartel]
    if type(syn_name) == "string" then
        if syn_name ~= "Prime" then
            local syn = t.syndicates[syn_name]
            if not syn then
                syn = {}
                t.syndicates[syn_name] = syn
                changed = true
            end

            local hub_beacon = jumps.hub_beacon or false
            local distant_beacon = jumps.distant_beacon or false
            if syn.hub_beacon ~= hub_beacon then
                syn.hub_beacon = hub_beacon
                changed = true
            end
            if syn.distant_beacon ~= distant_beacon then
                syn.distant_beacon = distant_beacon
                changed = true
            end
        end

        -- Every inter_syndicate entry is another syndicate's hub system, and a
        -- hub system is the namesake member of the namesake hub cartel (Sol
        -- for Prime). One arrival therefore names every syndicate in the
        -- galaxy along with its hub.
        for _, dest in ipairs(jumps.inter_syndicate or {}) do
            local other = (dest == "Sol") and "Prime" or dest
            if f2t_map_topology_learn(dest, dest, other) then changed = true end
        end

        -- intra_syndicate is only unambiguous from a cartel hub with no Hub
        -- Beacon: rule 2 alone, so every entry is a sibling cartel hub, which
        -- is its own cartel's namesake member. With the beacon built the list
        -- mixes in ordinary members that cannot be told apart, so skip it.
        local syn = t.syndicates[syn_name] or {}
        if system == cartel and not syn.hub_beacon then
            for _, dest in ipairs(jumps.intra_syndicate or {}) do
                if f2t_map_topology_learn(dest, dest, syn_name) then changed = true end
            end
        end
    elseif not (syndicate and syndicate ~= "") then
        -- The server names the syndicate on every link room, so reaching here
        -- means the payload was malformed or the room is not what we think it
        -- is. Rules 2-5 can't be derived anywhere in this syndicate until it
        -- is known; one sync heals it.
        f2t_map_topology_auto_sync("unknown syndicate for cartel " .. cartel)
    end

    if changed then f2t_map_topology_save() end
    return changed
end

-- Rate-limited background sync used when the model proves itself wrong
-- (unknown grouping, refused jump). Manual "map topology sync" bypasses this.
function f2t_map_topology_auto_sync(reason)
    if not f2t_settings_get("map", "topology_auto_sync") then return end
    if F2T_MAP_TOPOLOGY_CAPTURE and F2T_MAP_TOPOLOGY_CAPTURE.active then return end
    local now = os.time()
    if now - F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC < AUTO_SYNC_COOLDOWN then return end
    F2T_MAP_TOPOLOGY_LAST_AUTO_SYNC = now
    f2t_debug_log("[map/topology] Auto-sync triggered: %s", reason or "unknown")
    f2t_map_topology_sync()
end

-- Shortest legal blind-jump command chain between two systems, mirroring the
-- server's own route builder. Used by the explorers to reach unmapped
-- territory where getPath() has no rooms to work with. Returns an array of
-- "jump <system>" commands, or nil when the model lacks the grouping to build
-- a legal chain.
function f2t_map_topology_jump_chain(from_system, to_system)
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY

    from_system = f2t_map_topology_canonical_system(from_system) or from_system
    to_system   = f2t_map_topology_canonical_system(to_system) or to_system

    local from_cartel = t.systems[from_system]
    local to_cartel = t.systems[to_system]
    if not to_cartel and t.cartels[to_system] ~= nil then to_cartel = to_system end
    if not from_cartel or not to_cartel then return nil end
    if from_system == to_system then return {} end

    local chain = {}
    local last = from_system
    local blocked = false
    local function emit(dest)
        if dest ~= last then
            if f2t_map_topology_is_barred(dest) then blocked = true end
            table.insert(chain, string.format("jump %s", dest))
            last = dest
        end
    end

    if from_cartel == to_cartel then
        emit(to_system)
        return (not blocked) and chain or nil
    end

    local from_syn = t.cartels[from_cartel]
    local to_syn = t.cartels[to_cartel]
    if type(from_syn) ~= "string" or type(to_syn) ~= "string" then return nil end
    local fsyn = t.syndicates[from_syn] or {}
    local tsyn = t.syndicates[to_syn] or {}

    if from_syn == to_syn then
        if fsyn.hub_beacon and from_syn ~= "Prime" then
            emit(to_system)
        else
            emit(from_cartel)
            emit(to_cartel)
            emit(to_system)
        end
        return (not blocked) and chain or nil
    end

    local from_hub = f2t_map_topology_hub_system(from_syn)
    local to_hub = f2t_map_topology_hub_system(to_syn)

    if fsyn.distant_beacon and from_syn ~= "Prime" then
        emit(to_hub)
    elseif fsyn.hub_beacon and from_syn ~= "Prime" then
        emit(from_hub)
        emit(to_hub)
    else
        emit(from_cartel)
        emit(from_hub)
        emit(to_hub)
    end

    if tsyn.hub_beacon and to_syn ~= "Prime" then
        emit(to_system)
    else
        emit(to_cartel)
        emit(to_system)
    end

    return (not blocked) and chain or nil
end

-- Every mapped system's link room, flagging the ones with more than one room
-- flagged "link". A system has exactly one server-side, so a second is stale
-- map data - and it is what makes a "jump <system>" exit point somewhere the
-- game never puts you, which a speedwalk then loops on.
function f2t_map_topology_show_links()
    local names = {}
    local areas = {}
    for area_name, area_id in pairs(getAreaTable()) do
        local system = f2t_map_get_system_from_space_area(area_name)
        if system then
            table.insert(names, system)
            areas[system] = area_id
        end
    end
    table.sort(names)

    cecho("\n<cyan>Interstellar link rooms<reset>\n")
    local suspect = 0
    for _, system in ipairs(names) do
        local candidates = f2t_map_find_all_rooms_with_flag(areas[system], "link")
        local chosen = f2t_map_find_link_room(areas[system])
        if #candidates > 1 then
            suspect = suspect + 1
            cecho(string.format("  <red>%-20s %d rooms flagged link<reset>\n", system, #candidates))
            for _, room_id in ipairs(candidates) do
                local stamp = tonumber(getRoomUserData(room_id, "fed2_jump_synced_at"))
                -- No path from the room the game actually uses means this one
                -- and everything hanging off it is a stranded island.
                local stranded = room_id ~= chosen and chosen and not getPath(chosen, room_id)
                cecho(string.format("      %s room %d  <dim_grey>%s  last seen %s<reset>%s\n",
                    room_id == chosen and "->" or "  ", room_id,
                    getRoomName(room_id) or "unnamed",
                    stamp and os.date("%Y-%m-%d %H:%M", stamp) or "never",
                    stranded and "  <red>stranded<reset>" or ""))
            end
        elseif not chosen then
            cecho(string.format("  <yellow>%-20s no link room mapped<reset>\n", system))
        end
    end
    if suspect == 0 then
        cecho("  <green>No system has more than one room flagged link<reset>\n")
    else
        cecho(string.format(
            "\n<dim_grey>%d system(s) with duplicates. The arrow marks the one the client uses"
            .. " (most recently confirmed by GMCP).<reset>\n", suspect))
    end
end

function f2t_map_topology_show()
    f2t_map_topology_ensure_loaded()
    local t = F2T_MAP_TOPOLOGY

    local system_count = 0
    for _ in pairs(t.systems) do system_count = system_count + 1 end

    cecho("\n<cyan>═══════════════════════════════════════════════════════════<reset>\n")
    cecho("<cyan>                    Galaxy Topology Model<reset>\n")
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n\n")

    local syndicate_names = {}
    for name in pairs(t.syndicates) do table.insert(syndicate_names, name) end
    table.sort(syndicate_names)

    if #syndicate_names == 0 then
        cecho("<yellow>No syndicates known yet.<reset> Run <white>map topology sync<reset>\n")
    end

    for _, syndicate in ipairs(syndicate_names) do
        local syn = t.syndicates[syndicate]
        local beacons = {}
        if syn.hub_beacon then table.insert(beacons, "Hub Beacon") end
        if syn.distant_beacon then table.insert(beacons, "Distant Beacon") end
        local beacon_str = #beacons > 0
            and string.format(" <green>(%s)<reset>", table.concat(beacons, ", "))
            or ""
        cecho(string.format("<white>%s<reset> syndicate%s <dim_grey>(hub: %s)<reset>\n",
            syndicate, beacon_str, f2t_map_topology_hub_system(syndicate)))

        local cartel_names = {}
        for cname, y in pairs(t.cartels) do
            if y == syndicate then table.insert(cartel_names, cname) end
        end
        table.sort(cartel_names)
        for _, cname in ipairs(cartel_names) do
            local members = 0
            for _, c in pairs(t.systems) do
                if c == cname then members = members + 1 end
            end
            cecho(string.format("  <cyan>%s<reset> <dim_grey>(%d known system%s)<reset>\n",
                cname, members, members == 1 and "" or "s"))
        end
    end

    local orphans = {}
    for cname, y in pairs(t.cartels) do
        if type(y) ~= "string" then table.insert(orphans, cname) end
    end
    if #orphans > 0 then
        table.sort(orphans)
        cecho(string.format("\n<yellow>Cartels with unknown syndicate:<reset> %s\n", table.concat(orphans, ", ")))
    end

    local closed_names = {}
    for name in pairs(t.closed or {}) do table.insert(closed_names, name) end
    if #closed_names > 0 then
        table.sort(closed_names)
        cecho(string.format("\n<yellow>Closed to you:<reset> %s\n", table.concat(closed_names, ", ")))
    end

    local exiled_names = {}
    for name in pairs(t.exiled or {}) do table.insert(exiled_names, name) end
    if #exiled_names > 0 then
        table.sort(exiled_names)
        cecho(string.format("\n<red>Exiled from:<reset> %s\n", table.concat(exiled_names, ", ")))
    end

    cecho(string.format("\n<dim_grey>Known systems: %d   Last sync: %s<reset>\n",
        system_count,
        t.synced_at and os.date("%Y-%m-%d %H:%M:%S", t.synced_at) or "never"))
    cecho("<cyan>═══════════════════════════════════════════════════════════<reset>\n")
end

f2t_debug_log("[map] Loaded topology.lua")
