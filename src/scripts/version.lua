-- fed2-tools — version checking and update notification (MPR-based)
-- Settings for this module are registered in settings.lua under the "f2t" namespace.

-- Semver comparison: returns true if v1 is newer than v2.
function f2t_version_is_newer(v1, v2)
    if not v1 or not v2 then return false end
    local function parse(v)
        local a, b, c = v:match("^(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    local a1, b1, c1 = parse(v1)
    local a2, b2, c2 = parse(v2)
    if a1 ~= a2 then return a1 > a2 end
    if b1 ~= b2 then return b1 > b2 end
    return c1 > c2
end

-- Check for a newer version via the Mudlet Package Repository.
-- silent = true suppresses "up to date" and error messages (used for startup checks).
function f2t_check_latest_version(silent)
    if not silent then
        cecho("\n<green>[fed2-tools]<reset> Checking for updates...\n")
    end

    if not mpkg or not mpkg.ready(true) then
        if not silent then
            cecho("<yellow>[fed2-tools]<reset> mpkg not available — install via Package Manager to enable update checks.\n")
        end
        return
    end

    mpkg.updatePackageList(true)

    tempTimer(5, function()
        local current = mpkg.getInstalledVersion("fed2-tools") or "0.0.0"
        local latest  = mpkg.getRepositoryVersion("fed2-tools")
        if not latest then
            if not silent then
                cecho("<yellow>[fed2-tools]<reset> Could not retrieve repository version.\n")
            end
            return
        end

        if f2t_version_is_newer(latest, current) then
            cecho(string.format(
                "\n<yellow>[fed2-tools]<reset> Update available: <white>v%s<reset> → <green>v%s<reset>\n",
                current, latest))
            cecho("<dim_grey> Update via the Package Manager or run: mpkg install fed2-tools<reset>\n")
        elseif not silent then
            cecho(string.format("<green>[fed2-tools]<reset> Up to date (v%s).\n", current))
        end
    end)
end

-- Startup update check — fires on connection, skips silently per settings.
local function startupCheck()
    local updateCheck = f2t_settings_get("f2t", "update_check_enabled")
    if updateCheck == false or updateCheck == "false" then return end

    local skip = tonumber(f2t_settings_get("f2t", "update_check_remind_skip")) or 0
    if skip > 0 then
        f2t_settings_set("f2t", "update_check_remind_skip", skip - 1)
        return
    end

    tempTimer(10, function()
        f2t_check_latest_version(true)
    end)
end

registerAnonymousEventHandler("sysConnectionEvent", startupCheck)
