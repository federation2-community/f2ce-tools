-- fed2-tools — player database (player_db)  ·  shared infrastructure
--
-- Stores every player ever seen online; survives across sessions, separated per
-- character.  This is foundational data consumed by multiple surfaces — the who
-- list, contact cards, chat name-colouring, local-players — so it lives as an
-- always-on module, NOT inside any window.
--
-- Ported from the archive's ui_player_db.lua with the framework coupling removed
-- and three things rewired for the new project:
--   * Storage is keyed off f2t_get_char_persistent_dir() → fed2-tools_persistent/
--     <char>/players/db (Mudlet table.save/load).
--   * Per-character reload is driven by the "f2tCharacterChanged" event raised by
--     char.lua (replaces the archive's f2t_on_char_detected hook).
--   * The GMCP feed (mark-offline → upsert online → save) is a GLOBAL
--     gmcp.players handler owned here, so the DB stays current regardless of
--     which (if any) windows are open.  In the archive this feed lived inside
--     the who window; that was the wrong home.
--
-- Rank ordering comes from the shared rank.lua (F2T_RANK_LEVELS via
-- f2t_get_rank_level) rather than a private copy.  Display colour is derived by
-- consumers from .rank, so it is not stored here.

F2T_PLAYER_DB = F2T_PLAYER_DB or {}   -- lowercase name → entry

local _dirty = false   -- only write to disk when data actually changed

-- ── Persistence ───────────────────────────────────────────────────────────────

local function _dir()  return f2t_get_char_persistent_dir() .. "/players" end
local function _path() return _dir() .. "/db" end

local function _ensure_dir()
    lfs.mkdir(f2t_get_char_persistent_dir())
    lfs.mkdir(_dir())
end

function f2t_player_db_count()
    local n = 0
    for _ in pairs(F2T_PLAYER_DB) do n = n + 1 end
    return n
end

function f2t_player_db_load()
    local buf = {}
    local ok  = pcall(table.load, _path(), buf)
    if ok and type(buf) == "table" then
        F2T_PLAYER_DB = buf
    else
        F2T_PLAYER_DB = {}
    end
    _dirty = false
    f2t_debug_log("[player_db] loaded %d entries", f2t_player_db_count())
end

function f2t_player_db_save()
    if not _dirty then return end
    _ensure_dir()
    local ok, err = pcall(table.save, _path(), F2T_PLAYER_DB)
    if ok then _dirty = false
    else f2t_debug_log("[player_db] save error: %s", tostring(err)) end
end

-- Debounced save: gmcp.players deltas arrive every few seconds while players
-- move, and writing the whole DB per delta was constant synchronous disk churn.
-- The in-memory DB (and every UI reading it) stays realtime; disk catches up
-- within SAVE_INTERVAL, with forced saves on disconnect and Mudlet exit.
local SAVE_INTERVAL = 30
local _saveTimer = nil

function f2t_player_db_save_debounced()
    if not _dirty or _saveTimer then return end
    _saveTimer = tempTimer(SAVE_INTERVAL, function()
        _saveTimer = nil
        f2t_player_db_save()
    end)
end

-- Unconditional save — for disconnect/logout where we must persist immediately.
function f2t_player_db_save_forced()
    if _saveTimer then killTimer(_saveTimer); _saveTimer = nil end
    _ensure_dir()
    local ok, err = pcall(table.save, _path(), F2T_PLAYER_DB)
    if ok then _dirty = false
    else f2t_debug_log("[player_db] forced save error: %s", tostring(err)) end
end

-- ── Entry schema ──────────────────────────────────────────────────────────────
-- { name, rank, rank_order, location, company, system, cartel, syndicate,
--   ship_class, staff, titles, is_online (bool), last_seen (os.time()|nil),
--   first_seen }
-- cartel and syndicate are distinct GMCP fields (Plutocrats own a cartel;
-- Syndicrats own a syndicate directly) -- never derive one from the other.

local function _key(name) return name:lower() end

-- Upsert a player entry. `entry` must have at least .name; .is_online optional.
function f2t_player_db_upsert(entry)
    if not entry or not entry.name then return end
    local k        = _key(entry.name)
    local now      = os.time()
    local existing = F2T_PLAYER_DB[k]
    local online   = (entry.is_online ~= nil) and entry.is_online or (existing and existing.is_online) or false

    local new_entry = {
        name       = entry.name,
        rank       = entry.rank       or (existing and existing.rank)       or "",
        rank_order = entry.rank_order or (existing and existing.rank_order) or 0,
        location   = entry.location   or (existing and existing.location)   or "",
        company    = entry.company    or (existing and existing.company)    or "",
        system     = entry.system     or (existing and existing.system)     or "",
        cartel     = entry.cartel     or (existing and existing.cartel)     or "",
        syndicate  = entry.syndicate  or (existing and existing.syndicate)  or "",
        ship_class = entry.ship_class or (existing and existing.ship_class) or "",
        staff      = entry.staff      or (existing and existing.staff)      or "",
        titles     = entry.titles     or (existing and existing.titles)     or {},
        is_online  = online,
        last_seen  = online and now or (existing and existing.last_seen),
        first_seen = existing and existing.first_seen or now,
    }

    local changed = not existing
        or existing.rank       ~= new_entry.rank
        or existing.location   ~= new_entry.location
        or existing.company    ~= new_entry.company
        or existing.system     ~= new_entry.system
        or existing.cartel     ~= new_entry.cartel
        or existing.syndicate  ~= new_entry.syndicate
        or existing.ship_class ~= new_entry.ship_class
        or existing.is_online  ~= new_entry.is_online

    F2T_PLAYER_DB[k] = new_entry
    if changed then _dirty = true end
end

-- Mark every entry offline (called before processing a fresh online list).
-- Does not set dirty; the upsert loop sets it if a status actually changed.
function f2t_player_db_mark_all_offline()
    for _, e in pairs(F2T_PLAYER_DB) do e.is_online = false end
end

-- ── Reads ───────────────────────────────────────────────────────────────────

function f2t_player_db_get(name)
    if not name then return nil end
    return F2T_PLAYER_DB[_key(name)]
end

-- All offline entries, sorted by last_seen descending.
function f2t_player_db_get_offline()
    local result = {}
    for _, e in pairs(F2T_PLAYER_DB) do
        if not e.is_online then result[#result + 1] = e end
    end
    table.sort(result, function(a, b) return (a.last_seen or 0) > (b.last_seen or 0) end)
    return result
end

-- Human-readable "last seen" from a timestamp.
function f2t_player_db_last_seen_str(ts)
    if not ts then return "never" end
    local delta = os.time() - ts
    if delta < 60      then return "just now"
    elseif delta < 3600   then return string.format("%dm ago", math.floor(delta / 60))
    elseif delta < 86400  then return string.format("%dh ago", math.floor(delta / 3600))
    else                       return string.format("%dd ago", math.floor(delta / 86400)) end
end

function f2t_player_db_reload()
    f2t_player_db_load()
    f2t_debug_log("[player_db] reloaded for char %s", F2T_CHAR_NAME or "?")
    raiseEvent("f2tPlayerDbReloaded")
end

-- ── Global GMCP feed ──────────────────────────────────────────────────────────
-- Always-on: keeps the DB current independent of any open window.  Consumers
-- that want to react to fresh data listen for "f2tPlayerDbUpdated".

-- The server always publishes under gmcp.players.online, keyed by name. A
-- "count" key alongside it means this is the full authoritative roster (sent
-- on login/logout/new character/deletion): every entry is complete for its
-- rank, so a field the JSON omits genuinely doesn't apply right now and
-- should replace whatever we had. No "count" means this is a targeted delta
-- for exactly one player (a location move, rank/company/ship change, etc.)
-- carrying only the fields that changed -- those get merged onto the
-- existing record instead of blanking everything else.
function f2t_player_db_feed_from_gmcp()
    if not (gmcp and gmcp.players and type(gmcp.players.online) == "table") then return end

    if gmcp.players.count then
        f2t_player_db_mark_all_offline()
        for _, p in pairs(gmcp.players.online) do
            if type(p) == "table" and p.name then
                f2t_player_db_upsert({
                    name       = p.name,
                    rank       = p.rank or "",
                    rank_order = f2t_get_rank_level(p.rank) or 0,
                    location   = p.location or "",
                    company    = p.company or "",
                    system     = p.system or "",
                    cartel     = p.cartel or "",
                    syndicate  = p.syndicate or "",
                    ship_class = p.ship_class or "",
                    staff      = p.staff_role or "",
                    titles     = p.titles or {},
                    is_online  = true,
                })
            end
        end
    else
        for name, p in pairs(gmcp.players.online) do
            if type(p) == "table" then
                f2t_player_db_upsert({
                    name       = p.name or name,
                    rank       = p.rank,
                    rank_order = p.rank and f2t_get_rank_level(p.rank) or nil,
                    location   = p.location,
                    company    = p.company,
                    system     = p.system,
                    cartel     = p.cartel,
                    syndicate  = p.syndicate,
                    ship_class = p.ship_class,
                    staff      = p.staff_role,
                    titles     = p.titles,
                    is_online  = true,
                })
            end
        end
    end

    f2t_player_db_save_debounced()
    raiseEvent("f2tPlayerDbUpdated")
end

registerAnonymousEventHandler("gmcp.players", "f2t_player_db_feed_from_gmcp")

-- Reload the DB whenever the logged-in character changes.
registerAnonymousEventHandler("f2tCharacterChanged", function()
    f2t_player_db_reload()
end)

-- On disconnect, mark everyone offline and persist so last_seen stays accurate.
registerAnonymousEventHandler("sysDisconnectionEvent", function()
    f2t_player_db_mark_all_offline()
    f2t_player_db_save_forced()
end)

-- Mudlet exit is the other session-ending path the debounced save must survive.
registerAnonymousEventHandler("sysExitEvent", function()
    f2t_player_db_save_forced()
end)

-- Load now in case a character is already known (e.g. package reload mid-session).
if F2T_CHAR_NAME and F2T_CHAR_NAME ~= "" then
    f2t_player_db_load()
end

f2t_debug_log("[player_db] Module initialized")