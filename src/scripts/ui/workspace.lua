-- Loads the "f2ce-tools" Muxlet workspace.
--
-- The workspace definition itself is not here: it lives at
-- resources/full.lua as the literal, unwrapped output of
-- `mux workspace export f2ce-tools`. Re-run that export after changing the
-- layout/rules in-game and overwrite full.lua wholesale with the result --
-- nothing in this file needs to change.
--
-- Loading is deferred via F2T_CONTENT_REGISTRARS (like content modules)
-- rather than run at file-load time, because Mux may not exist yet on a
-- fresh profile: Muxlet installation is deferred until after login, while
-- this file loads synchronously during the initial package install.

-- Cheap djb2-ish content hash, arithmetic-only (no bit library assumed) --
-- used purely for change detection, not security, so collisions costing an
-- occasional missed/extra prompt are an acceptable tradeoff for portability.
local function contentHash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return h
end

-- Hash of full.lua's source as loaded this session; nil until
-- f2tRegisterWorkspace runs, or if it failed to read the file. Read by
-- f2tFullStart() below to auto-detect a layout change with no manual
-- version bump required.
F2T_LAYOUT_HASH = nil

local function f2tRegisterWorkspace()
    if not (Mux and Mux.registerWorkspace) then
        if f2t_debug_log then f2t_debug_log("[workspace] Muxlet workspace API unavailable; skipping") end
        return
    end

    local path = getMudletHomeDir() .. "/f2ce-tools/full.lua"
    local f, openErr = io.open(path, "r")
    if not f then
        if f2t_debug_log then f2t_debug_log("[workspace] failed to open %s: %s", path, tostring(openErr)) end
        return
    end
    local source = f:read("*a")
    f:close()

    F2T_LAYOUT_HASH = contentHash(source)

    local chunk, loadErr = loadstring(source, "@" .. path)
    if not chunk then
        if f2t_debug_log then f2t_debug_log("[workspace] failed to load %s: %s", path, tostring(loadErr)) end
        return
    end

    local ok, runErr = pcall(chunk)
    if not ok then
        if f2t_debug_log then f2t_debug_log("[workspace] error running %s: %s", path, tostring(runErr)) end
    end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterWorkspace)

-- Runs Mux.fullStart(), then reconciles the "f2ce-tools" Full-mode layout
-- against F2T_LAYOUT_HASH.
--
-- Mux.fullStart() always restores the auto-saved "current" session snapshot
-- over the freshly-registered "f2ce-tools" workspace (Muxlet's manager.lua)
-- -- and "current" gets written within seconds of a Full-mode user's very
-- first session, since nearly any structural event schedules an autosave.
-- Left alone, that means a full.lua layout change never reaches a returning
-- user on its own. This offers a reload instead of forcing one, since the
-- user may have rearranged panes themselves; BYOW users are untouched
-- either way, since they never load "f2ce-tools". The hash is content-based
-- (not a hand-bumped counter) so this can never be forgotten -- the tradeoff
-- is that a re-export with zero visible difference still counts as "changed"
-- and prompts once.
function f2tFullStart()
    local hadCurrent = Mux._workspaces["current"] ~= nil
    Mux.fullStart()

    if not F2T_LAYOUT_HASH then return end -- full.lua failed to load; nothing to compare

    if not hadCurrent then
        -- Just built fresh from this session's "f2ce-tools" (or BYOW's
        -- "default"); that already IS this content.
        f2t_settings_set("f2t", "layout_hash_seen", F2T_LAYOUT_HASH)
        return
    end

    if Mux.settings.get("mux", "reset_workspace") ~= "f2ce-tools" then return end -- BYOW, or no mode chosen

    if f2t_settings_get("f2t", "layout_hash_seen") == F2T_LAYOUT_HASH then return end

    if f2tShowLayoutUpdateConfirm then
        f2tShowLayoutUpdateConfirm(function() -- on_reload
            Mux.applyWorkspace("f2ce-tools")
        end)
    end
    -- Either choice means the user has now been asked about this content;
    -- never ask again for it.
    f2t_settings_set("f2t", "layout_hash_seen", F2T_LAYOUT_HASH)
end
