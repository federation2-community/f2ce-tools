-- Dev Mode: local build auto-reload.
--
-- muddlet --profile <name> writes f2ce-tools-rebuild.stamp (unix timestamp)
-- to the profile directory after every build. A 30-second timer here watches
-- it; on change, f2ce-tools reinstalls itself from the deployed package. New
-- code is active immediately; Mux._promptRestartRequired then offers a
-- profile close/reopen for a fully clean UI, but doesn't force one.
--
-- muddlet --fresh also writes a fresh flag file. The watcher then wipes
-- Muxlet_persistent and f2ce-tools_persistent, uninstalls Muxlet, and
-- reinstalls f2ce-tools, whose bootstrap re-downloads a clean Muxlet,
-- simulating a first-time install without closing Mudlet.

-- Stamp value seen at last check. nil = not yet observed this session.
local _devLastStamp = nil

-- Recursively deletes every file under a directory tree, leaving the
-- directory skeleton in place (mirrors Muxlet's own Mux._wipePersistentDir).
local function wipeFiles(path)
    local attr = lfs.attributes(path)
    if not attr then return end
    if attr.mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                wipeFiles(path .. "/" .. entry)
            end
        end
    else
        os.remove(path)
    end
end

-- Deferred to a runtime tempTimer(0): uninstalling the script that's
-- currently executing (from inside the watcher's own callback) frees it
-- mid-run and crashes Mudlet, so this must run after the call stack unwinds.
--
-- Reinstalling only reloads f2ce-tools' Lua; Muxlet doesn't re-fire
-- "muxletReady", so the registrar list is cleared and re-run explicitly here.
local function f2tDevmodeDoReload(pkgPath)
    tempTimer(0, function()
        if table.contains(getPackages(), "f2ce-tools") then
            uninstallPackage("f2ce-tools")
        end
        local ok, err = installPackage(pkgPath)
        if ok then
            F2T_CONTENT_REGISTRARS = {}
            if f2tRegisterAllContent then f2tRegisterAllContent() end
            cecho("\n<green>[f2ce-tools]<reset> Reinstalled.\n")
            if Mux and Mux._promptRestartRequired then Mux._promptRestartRequired() end
        else
            cecho(string.format(
                "\n<red>[f2ce-tools]<reset> Reinstall failed (%s). Install manually from: %s\n",
                tostring(err or "unknown error"), pkgPath))
        end
    end)
end

-- Wipes persisted state and removes Muxlet from the profile before handing off
-- to f2tDevmodeDoReload, simulating a brand-new install without closing Mudlet.
local function f2tDevmodeFreshReload(pkgPath)
    local home = getMudletHomeDir()

    cecho("\n<yellow>[f2ce-tools]<reset> --fresh: deleting Muxlet_persistent...\n")
    wipeFiles(home .. "/Muxlet_persistent")

    cecho("\n<yellow>[f2ce-tools]<reset> --fresh: deleting f2ce-tools_persistent...\n")
    wipeFiles(home .. "/f2ce-tools_persistent")

    if table.contains(getPackages(), "Muxlet") then
        cecho("\n<yellow>[f2ce-tools]<reset> --fresh: removing Muxlet from profile...\n")
        -- init.lua's sysUninstallPackage watchdog stands down for this
        -- uninstall (it's ours); f2tDevmodeDoReload below re-triggers
        -- Muxlet's reinstall. Global so it survives into that handler,
        -- which clears it immediately.
        F2T_FRESH_UNINSTALL_PENDING = true
        local waitId
        waitId = registerAnonymousEventHandler("sysUninstallPackage", function(_, name)
            if name ~= "Muxlet" then return end
            killAnonymousEventHandler(waitId)
            F2T_FRESH_UNINSTALL_PENDING = false
            cecho("\n<cyan>[f2ce-tools]<reset> Reloading f2ce-tools...\n")
            f2tDevmodeDoReload(pkgPath)
        end)
        uninstallPackage("Muxlet")
    else
        cecho("\n<cyan>[f2ce-tools]<reset> Reloading f2ce-tools...\n")
        f2tDevmodeDoReload(pkgPath)
    end
end

-- Recursive 30-second timer. Does nothing when the stamp file is absent
-- (standard production installs have no stamp file).
local function f2tDevmodeCheck()
    -- Defer all file I/O and reloads until after login. The synchronous
    -- io.open call blocks Mudlet's main thread; if it fires during the
    -- password prompt the brief freeze can corrupt the login sequence.
    if not F2T_LOGGED_IN then
        tempTimer(5, f2tDevmodeCheck)
        return
    end

    local home      = getMudletHomeDir()
    local stampPath = home .. "/f2ce-tools-rebuild.stamp"
    local file      = io.open(stampPath, "r")

    if not file then
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    local stamp = file:read("*a"):match("^%s*(.-)%s*$")
    file:close()

    if stamp == _devLastStamp then
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    if _devLastStamp == nil then
        -- First observation: record stamp but don't reload. Prevents a spurious
        -- reload on every package restart when the stamp file already exists.
        _devLastStamp = stamp
        cecho("\n<yellow>[f2ce-tools]<reset> Dev mode active — monitoring for new local builds\n")
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    -- Stamp changed: a new build was deployed; check for the fresh flag.
    _devLastStamp = stamp
    local pkgPath   = home .. "/f2ce-tools.mpackage"
    local freshPath = home .. "/f2ce-tools-fresh.stamp"
    local freshFile = io.open(freshPath, "r")

    if freshFile then
        freshFile:close()
        os.remove(freshPath)
        cecho("\n<yellow>[f2ce-tools]<reset> New local build detected (fresh) — wiping and reloading...\n")
        f2tDevmodeFreshReload(pkgPath)
    else
        cecho("\n<cyan>[f2ce-tools]<reset> New local build detected — reloading...\n")
        f2tDevmodeDoReload(pkgPath)
    end
    -- No reschedule: the freshly installed package starts its own timer on load.
end

-- Only start the polling timer if a stamp file already exists in the profile
-- directory. Production installs never have this file, so the timer never
-- runs for end-users.
local function f2tDevmodeStart()
    local stampPath = getMudletHomeDir() .. "/f2ce-tools-rebuild.stamp"
    local probe = io.open(stampPath, "r")
    if not probe then return end
    probe:close()
    tempTimer(30, f2tDevmodeCheck)
end

f2tDevmodeStart()
