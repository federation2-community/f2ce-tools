-- =============================================================================
-- ui_player_db  —  persistent player database
-- Stores every player seen online; survives across sessions.
-- Loaded into UI.player_db[name] = entry table.
-- =============================================================================

UI            = UI or {}
UI.player_db  = UI.player_db or {}   -- name (lowercase key) → entry
UI.who        = UI.who or {}

local _db_dirty = false   -- only write to disk when data actually changed

-- ── Persistence paths ─────────────────────────────────────────────────────────

local function _db_dir()  return getMudletHomeDir() .. "/fed2-tools" end
local function _db_path() return _db_dir() .. "/player_db" end

local function _ensure_dir()
    lfs.mkdir(_db_dir())
end

function ui_player_db_load()
    local buf = {}
    local ok  = pcall(table.load, _db_path(), buf)
    if ok and type(buf) == "table" then
        UI.player_db = buf
    end
    f2t_debug_log("[player_db] loaded %d entries", (function()
        local n = 0; for _ in pairs(UI.player_db) do n = n + 1 end; return n
    end)())
end

function ui_player_db_save()
    if not _db_dirty then return end
    _ensure_dir()
    local ok, err = pcall(table.save, _db_path(), UI.player_db)
    if ok then
        _db_dirty = false
    else
        f2t_debug_log("[player_db] save error: %s", tostring(err))
    end
end

-- Unconditional save — use for disconnect/logout where we must persist immediately.
function ui_player_db_save_forced()
    _ensure_dir()
    local ok, err = pcall(table.save, _db_path(), UI.player_db)
    if ok then
        _db_dirty = false
    else
        f2t_debug_log("[player_db] forced save error: %s", tostring(err))
    end
end

-- ── Entry schema ──────────────────────────────────────────────────────────────
-- {
--   name, rank, rank_order, cecho_color,
--   location, company, system, cartel, ship_class, staff, titles,
--   is_online  (bool),
--   last_seen  (os.time() or nil),
--   first_seen (os.time()),
-- }

local function _key(name) return name:lower() end

-- ── Write helpers ─────────────────────────────────────────────────────────────

-- Upsert a player entry.  entry must have at least .name set.
function ui_player_db_upsert(entry)
    if not entry or not entry.name then return end
    local k        = _key(entry.name)
    local now      = os.time()
    local existing = UI.player_db[k]
    local online   = (entry.is_online ~= nil) and entry.is_online or false

    local new_entry = {
        name        = entry.name,
        rank        = entry.rank        or (existing and existing.rank)        or "",
        rank_order  = entry.rank_order  or (existing and existing.rank_order)  or 0,
        cecho_color = entry.cecho_color or (existing and existing.cecho_color) or "ansi_white",
        location    = entry.location    or (existing and existing.location)    or "",
        company     = entry.company     or (existing and existing.company)     or "",
        system      = entry.system      or (existing and existing.system)      or "",
        cartel      = entry.cartel      or (existing and existing.cartel)      or "",
        ship_class  = entry.ship_class  or (existing and existing.ship_class)  or "",
        staff       = entry.staff       or (existing and existing.staff)       or "",
        titles      = entry.titles      or (existing and existing.titles)      or {},
        is_online   = online,
        last_seen   = online and now or (existing and existing.last_seen),
        first_seen  = existing and existing.first_seen or now,
    }

    -- Only mark dirty if something meaningful changed
    local changed = not existing
        or existing.rank      ~= new_entry.rank
        or existing.location  ~= new_entry.location
        or existing.company   ~= new_entry.company
        or existing.system    ~= new_entry.system
        or existing.cartel    ~= new_entry.cartel
        or existing.ship_class ~= new_entry.ship_class
        or existing.is_online ~= new_entry.is_online

    UI.player_db[k] = new_entry
    if changed then _db_dirty = true end
end

-- Mark all DB entries as offline (called before processing a fresh online list).
-- Does NOT set dirty — the subsequent upsert loop will set it if anyone's
-- online status actually changed.
function ui_player_db_mark_all_offline()
    for _, e in pairs(UI.player_db) do
        e.is_online = false
    end
end

-- ── Read helpers ──────────────────────────────────────────────────────────────

-- Returns the entry for name (case-insensitive), or nil.
function ui_player_db_get(name)
    if not name then return nil end
    return UI.player_db[_key(name)]
end

-- Returns all offline entries sorted by last_seen descending.
function ui_player_db_get_offline()
    local result = {}
    for _, e in pairs(UI.player_db) do
        if not e.is_online then table.insert(result, e) end
    end
    table.sort(result, function(a, b)
        return (a.last_seen or 0) > (b.last_seen or 0)
    end)
    return result
end

-- Human-readable "last seen" string from a timestamp.
function ui_player_db_last_seen_str(ts)
    if not ts then return "never" end
    local delta = os.time() - ts
    if delta < 60     then return "just now"
    elseif delta < 3600   then return string.format("%dm ago", math.floor(delta / 60))
    elseif delta < 86400  then return string.format("%dh ago", math.floor(delta / 3600))
    else                       return string.format("%dd ago", math.floor(delta / 86400))
    end
end
