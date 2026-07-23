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

local function f2tRegisterWorkspace()
    if not (Mux and Mux.registerWorkspace) then
        if f2t_debug_log then f2t_debug_log("[workspace] Muxlet workspace API unavailable; skipping") end
        return
    end

    local path = getMudletHomeDir() .. "/f2ce-tools/full.lua"
    local chunk, loadErr = loadfile(path)
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
