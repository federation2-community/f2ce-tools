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

-- Hidden bookkeeping, not a user preference -- mirrors map/import_check.lua's
-- seenHash()/markHashSeen() for the exact same reason: f2t_settings_get/set
-- silently no-op on an unregistered key (Mux.settings.set returns
-- false/"Unknown setting" without f2t_settings_register having run for it
-- first), and registering it would only add a meaningless Settings-UI row
-- for a value no user should ever touch. Reads/writes Mux.settings._data
-- directly instead, with an explicit save.
local function layoutHashSeen()
    local d = Mux and Mux.settings and Mux.settings._data
    return d and d["f2t"] and d["f2t"]["layout_hash_seen"]
end

local function markLayoutHashSeen(hash)
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["layout_hash_seen"] = hash
    Mux.settings.save()
end

-- Genuinely user-facing, unlike layout_hash_seen above -- registered so it
-- gets a real Settings-UI row and actually persists via f2t_settings_set.
-- Flipped off by the "Never Prompt" button in layout_update_confirm.lua.
f2t_settings_register("workspace", "notify_layout_updates", {
    tab         = "F2CE-Tools/Misc",
    label       = "Notify on layout updates",
    description = "Prompt to reload the Full workspace layout when full.lua ships a change. "
                .. "Turned off automatically by the prompt's own \"Never Prompt\" button.",
    default     = true,
})

-- Hash a deferred layout-update prompt is waiting on (see f2tFullStart's
-- "wasRunning" branch below), or nil when nothing is pending. Read by
-- f2tOnRestartDeclined, wired as Muxlet's onRestartDeclined callback in
-- init.lua's bootHostOpts.
local _pendingLayoutUpdateHash = nil

-- Shows the Reload/Not This Time/Never Prompt dialog. Shared by
-- f2tFullStart's immediate path and f2tOnRestartDeclined's deferred one.
-- "seen" is recorded from inside Reload/Not This Time/Never Prompt's own
-- callbacks -- only once the user has actually responded to one of those
-- three, not merely because the dialog was shown -- so closing the dialog
-- (a deliberate no-op, wired in layout_update_confirm.lua) or a profile
-- that closes before any button is clicked both correctly re-prompt next
-- time instead of silently marking it handled.
local function f2tShowLayoutUpdate(hash)
    if not f2tShowLayoutUpdateConfirm then return end
    f2tShowLayoutUpdateConfirm(
        function() -- on_reload
            Mux.applyWorkspace("f2ce-tools")
            markLayoutHashSeen(hash)
        end,
        function() -- on_not_this_time: ask again once full.lua changes further
            markLayoutHashSeen(hash)
        end,
        function() -- on_never: also silence the notify_layout_updates toggle
            markLayoutHashSeen(hash)
            f2t_settings_set("workspace", "notify_layout_updates", false)
        end
    )
end

-- Called back by Muxlet's restart-recommended dialog (see init.lua's
-- bootHostOpts) when the user picks "Close Later" over "Close Profile" --
-- the one moment a prompt deferred below actually needs to appear.
function f2tOnRestartDeclined()
    if not _pendingLayoutUpdateHash then return end
    local hash = _pendingLayoutUpdateHash
    _pendingLayoutUpdateHash = nil
    f2t_debug_log("[workspace] f2tOnRestartDeclined: showing deferred Reload/Not This Time/Never Prompt")
    f2tShowLayoutUpdate(hash)
end

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
    -- Read before Mux.fullStart(), which sets Mux._running = true itself on
    -- a fresh start -- checking after the call would always read true.
    local wasRunning = Mux._running
    Mux.fullStart()

    f2t_debug_log("[workspace] f2tFullStart: hash=%s hadCurrent=%s reset_workspace=%s seen=%s",
        tostring(F2T_LAYOUT_HASH), tostring(hadCurrent),
        tostring(Mux.settings.get("mux", "reset_workspace")),
        tostring(layoutHashSeen()))

    if not F2T_LAYOUT_HASH then
        f2t_debug_log("[workspace] f2tFullStart: bailing, full.lua never loaded (F2T_LAYOUT_HASH is nil)")
        return
    end

    if not hadCurrent then
        -- Just built fresh from this session's "f2ce-tools" (or BYOW's
        -- "default"); that already IS this content.
        f2t_debug_log("[workspace] f2tFullStart: no prior 'current' workspace; seeding baseline, no prompt")
        markLayoutHashSeen(F2T_LAYOUT_HASH)
        return
    end

    if Mux.settings.get("mux", "reset_workspace") ~= "f2ce-tools" then
        f2t_debug_log("[workspace] f2tFullStart: bailing, reset_workspace is not \"f2ce-tools\"")
        return -- BYOW, or no mode chosen
    end

    if not f2t_settings_get("workspace", "notify_layout_updates") then
        f2t_debug_log("[workspace] f2tFullStart: bailing, notify_layout_updates is off")
        return
    end

    if layoutHashSeen() == F2T_LAYOUT_HASH then
        f2t_debug_log("[workspace] f2tFullStart: bailing, hash matches what was already seen")
        return
    end

    if wasRunning then
        -- Mux was already running, meaning this is an in-place reinstall
        -- (not a fresh boot) -- exactly the situation that always pairs
        -- with Muxlet's own restart-recommended dialog too, whether this
        -- reinstall came from a dev-mode local build or a real end-user
        -- update. Showing both dialogs at once stacks one on top of the
        -- other, so wait for the actual restart decision instead: if the
        -- user restarts, the next boot's own non-deferred call through this
        -- same function shows this fresh, with nothing lost; if they pick
        -- "Close Later" (see f2tOnRestartDeclined above), it shows then.
        f2t_debug_log("[workspace] f2tFullStart: deferring Reload/Not This Time/Never Prompt to restart decision")
        _pendingLayoutUpdateHash = F2T_LAYOUT_HASH
        return
    end

    f2t_debug_log("[workspace] f2tFullStart: showing Reload/Not This Time/Never Prompt")
    f2tShowLayoutUpdate(F2T_LAYOUT_HASH)
end
