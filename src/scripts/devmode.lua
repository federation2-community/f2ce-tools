-- fed2-tools — Dev Mode: local build auto-reload and manual reload helpers
--
-- Auto-reload: muddlet --profile <name> writes a stamp file to the profile
-- directory after running muddler. A recursive 30-second timer watches for
-- stamp changes and performs uninstallPackage + installPackage for a clean reload.
--
-- Manual reload:
--   f2t reload        — upgrade path (preserves settings)
--   f2t reload fresh  — clears mux_autostart, simulating a fresh install

-- Stamp value seen at last check. nil = not yet observed this session.
local _devLastStamp = nil

local function f2tDevmodeDoReload(pkgPath)
    if table.contains(getPackages(), "fed2-tools") then
        uninstallPackage("fed2-tools")
    end
    installPackage(pkgPath)
end

-- Recursive 30-second timer. Does nothing when the stamp file is absent
-- (standard production installs have no stamp file).
local function f2tDevmodeCheck()
    local stampPath = getMudletHomeDir() .. "/fed2-tools-rebuild.stamp"
    local file = io.open(stampPath, "r")

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
        cecho("\n<yellow>[fed2-tools]<reset> Dev mode active — monitoring for new local builds\n")
        tempTimer(30, f2tDevmodeCheck)
        return
    end

    -- Stamp changed: a new build was deployed; reload.
    _devLastStamp = stamp
    cecho("\n<cyan>[fed2-tools]<reset> New local build detected — reloading...\n")
    local pkgPath = getMudletHomeDir() .. "/fed2-tools.mpackage"
    f2tDevmodeDoReload(pkgPath)
    -- No reschedule: the freshly installed package starts its own timer on load.
end

-- Called by "f2t reload [fresh]".
function f2t_devmode_reload(fresh)
    if fresh then
        if Mux and Mux.settings then
            Mux.settings.set("f2t", "mux_autostart", nil)
            cecho("\n<yellow>[fed2-tools]<reset> Cleared mux_autostart — mode-selection will run on next load.\n")
        else
            cecho("\n<yellow>[fed2-tools]<reset> Muxlet not ready; cannot clear mux_autostart.\n")
        end
    end

    local pkgPath = getMudletHomeDir() .. "/fed2-tools.mpackage"
    local f = io.open(pkgPath, "r")
    if not f then
        cecho(string.format("\n<red>[fed2-tools]<reset> No deployed build found at: %s\n", pkgPath))
        cecho("\n<yellow>[fed2-tools]<reset> Run: ./muddlet --profile <name>\n")
        return
    end
    f:close()

    cecho("\n<cyan>[fed2-tools]<reset> Reloading fed2-tools...\n")
    f2tDevmodeDoReload(pkgPath)
end

-- Only start the polling timer if a stamp file already exists in the profile
-- directory. Production installs never have this file, so the timer never
-- runs for end-users.
local function f2tDevmodeStart()
    local stampPath = getMudletHomeDir() .. "/fed2-tools-rebuild.stamp"
    local probe = io.open(stampPath, "r")
    if not probe then return end
    probe:close()
    tempTimer(30, f2tDevmodeCheck)
end

f2tDevmodeStart()
