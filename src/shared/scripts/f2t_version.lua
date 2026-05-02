-- =============================================================================
-- Unified Version Checker: Supports MPR (Mudlet Package Repository)
-- =============================================================================

f2t_settings_register("shared", "update_check_enabled", {
    description = "Check for fed2-tools updates automatically on session start",
    default = true,
    validator = function(value)
        if value ~= true and value ~= false and value ~= "true" and value ~= "false" then
            return false, "Must be true or false"
        end
        return true
    end
})

f2t_settings_register("shared", "update_check_remind_skip", {
    description = "Sessions remaining before update reminder re-appears (managed by 'Remind Later')",
    default = 0,
    min = 0, max = 99,
    validator = function(value)
        local num = tonumber(value)
        if not num or num < 0 or num > 99 then
            return false, "Must be a number between 0 and 99"
        end
        return true
    end
})

function f2t_check_latest_version(silent)
    if not silent then cecho("\n<green>[fed2-tools]<reset> Checking for updates...\n") end

    if not mpkg or not mpkg.ready(true) then
        if not silent then cecho("<red> Error: mpkg repository data not loaded.\n") end
        return
    end
    
    -- Ensure latest mpkg repository, silently, wait five seconds to have it take effect
    mpkg.updatePackageList(true)

    tempTimer(5, function ()
        local current = mpkg.getInstalledVersion("fed2-tools") or "0.0.0"
        local pkg     = getPackageInfo("fed2-tools")

        if not pkg then
            if not silent then cecho("<red> Error: fed2-tools not found in mpkg repository.\n") end
            return
        end

        if f2t_version_is_newer(mpkg.getRepositoryVersion("fed2-tools"), current) then
            f2t_trigger_update_dialog(current, mpkg.getRepositoryVersion("fed2-tools"))
        elseif not silent then
            cecho("<green> You are up to date.\n")
        end
    end)
end

-- Trigger Update Dialog, and get Changelog for versions that are new
function f2t_trigger_update_dialog(currentVersion, latestVersion)
    local tmp = getMudletHomeDir() .. "/f2t_releases.json"

    -- RESET: Clear previous notes before starting a new download
    F2T_CHANGELOG = {}

    -- Clean up previous handler if it exists
    if F2T_DL_HANDLER then killAnonymousEventHandler(F2T_DL_HANDLER) end

    -- Register a event handler for download complete that gets changelog info, fires the update UI popup, and deletes itself
    F2T_DL_HANDLER = registerAnonymousEventHandler("sysDownloadDone", function(_, filename)
        if filename ~= tmp then return end

        local file = io.open(tmp, "r")
        if not file then return end

        local content = file:read("*a")
        file:close()

        local releases = yajl.to_value(content)
        if not releases then return end

        -- Populate F2T_CHANGELOG with release data
        for _, release in ipairs(releases) do
            local tag = release.tag_name:gsub("^v","")

            if f2t_version_is_newer(tag, currentVersion) then
                table.insert(F2T_CHANGELOG, {
                    version = tag,
                    body = release.body
                })
            end
        end

        -- SORTING: Ensures newest version is at the top (index 1)
        table.sort(F2T_CHANGELOG, function(a, b)
            return f2t_version_is_newer(a.version, b.version)
        end)
    
        -- Call the dialog in ui/scripts/ui_update_dialog
        if ui_update_show_dialog then ui_update_show_dialog(currentVersion, latestVersion) end

        killAnonymousEventHandler(F2T_DL_HANDLER)
        F2T_DL_HANDLER = nil
    end)

    downloadFile(tmp, "https://api.github.com/repos/tmtocloud/fed2-tools/releases")
end

-- Helper: Semver logic (Reusing your existing function)
function f2t_version_is_newer(v1, v2)
    if not v1 or not v2 then return false end
    local function parse(v)
        local major, minor, patch = v:match("^(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end
    local maj1, min1, pat1 = parse(v1)
    local maj2, min2, pat2 = parse(v2)
    if maj1 ~= maj2 then return maj1 > maj2 end
    if min1 ~= min2 then return min1 > min2 end
    return pat1 > pat2
end

-- Runs on game connection
function f2t_startup_check()
    -- Check if update check is enabled in your settings system
    local update_check = f2t_settings_get("shared", "update_check_enabled")
    
    -- If update check is nil, default to true
    if update_check == false or update_check == "false" then return end

    local skip = tonumber(f2t_settings_get("shared", "update_check_remind_skip")) or 0

    if skip > 0 then
        f2t_settings_set("shared", "update_check_remind_skip", skip - 1)
        return
    end
        
    -- Run the version check silently
    tempTimer(10, function()
        f2t_check_latest_version(true) -- true = silent
    end)
end

-- Register the startup event
F2T_CONNECTION_HANDLER = registerAnonymousEventHandler("sysConnectionEvent", "f2t_startup_check")

-- add a cleanup handler
registerAnonymousEventHandler("sysUninstall", function(_, pkg)
    if pkg == "fed2-tools" and F2T_CONNECTION_HANDLER then
        killAnonymousEventHandler(F2T_CONNECTION_HANDLER)
        F2T_CONNECTION_HANDLER = nil
    end
end)
