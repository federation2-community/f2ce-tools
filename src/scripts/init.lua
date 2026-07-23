-- Installs/upgrades (or downgrades) Muxlet via Mux.bootHost and drives our
-- own initialization from its onReady callback. Muxlet is pinned to an exact
-- version, not just a floor: if F2T_REQUIRED_MUXLET is set older than what's
-- installed, Mux.bootHost downgrades in place rather than treating the newer
-- install as satisfying.
--
-- On first run, init shows the mode-selection dialog (ui/popups.lua). The
-- user's choice persists as mux_autostart in Mux.settings and governs all
-- future sessions:
--   mux_autostart = true  -> Mux.fullStart() called automatically each session
--   mux_autostart = false -> Muxlet installed but never auto-started (Minimal)
--
-- F2T_REQUIRED_MUXLET and MUXLET_URL are injected by the build script (never
-- edit manually). Dev builds point at the prerelease tag; production builds
-- point at the production tag.

local MUXLET_PKG = "Muxlet"

-- build-injected: exact Muxlet version this f2ce-tools build is pinned to
local F2T_REQUIRED_MUXLET = nil
-- build-injected: GitHub release URL (bare tag = prerelease; v-tag = production)
local MUXLET_URL = nil

-- ── generic_mapper removal ────────────────────────────────────────────────────
-- generic_mapper conflicts with the f2ce-tools map system; remove it silently.
if table.contains(getPackages(), "generic_mapper") then
    f2t_debug_log("Removing incompatible package: generic_mapper")
    uninstallPackage("generic_mapper")
end

-- ── Install handler ───────────────────────────────────────────────────────────
-- sysInstall fires during installation only, not on normal session start.
registerAnonymousEventHandler("sysInstall", function(_, pkg)
    if pkg ~= "f2ce-tools" then return end

    -- Apply preferred mapper defaults only on the very first install so user
    -- customisations are never overwritten on upgrade.
    local firstInstall = not (Mux and Mux._workspaces and Mux._workspaces["current"])
    if firstInstall then
        tempTimer(3, function()
            local ok = setConfig({
                mapExitSize        = 10,
                mapRoomSize        = 5,
                mapRoundRooms      = false,
                mapShowGrid        = false,
                mapShowRoomBorders = false,
            })
            if ok then updateMap() end
        end)
    end
end)

-- ── Login gating ──────────────────────────────────────────────────────────────
-- Disruptive actions (installing/reinstalling a package, showing dialogs,
-- auto-starting Muxlet) are deferred until after gmcp.char.vitals fires, so
-- they never land mid-login-prompt.
local function afterLogin(fn)
    if gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name then
        fn()
        return
    end
    local waitId
    waitId = registerAnonymousEventHandler("gmcp.char.vitals", function()
        killAnonymousEventHandler(waitId)
        fn()
    end)
end

-- True when the currently loaded Muxlet already meets F2T_REQUIRED_MUXLET
-- (exact pin, not just a floor — see Mux._versionSatisfied). Reuses Muxlet's
-- own comparator rather than re-parsing versions here; only exists so the boot
-- sequence below can decide whether it needs to gate on login before calling
-- Mux.bootHost (which does the actual, possibly disruptive, upgrade/downgrade).
local function versionSatisfied()
    if not (Mux and Mux._version and Mux._versionSatisfied) then return false end
    return Mux._versionSatisfied(F2T_REQUIRED_MUXLET, true)
end

-- Recover if Muxlet ever disappears mid-session for any reason other than our
-- own devmode fresh-reload flow (muddlet --fresh, see devmode.lua) — that flow
-- reinstalls f2ce-tools itself and lets THIS package's own top-level bootstrap
-- below notice Muxlet is absent and reinstall it, so it sets
-- F2T_FRESH_UNINSTALL_PENDING first to keep this generic watchdog from also
-- firing and racing it. A handler Muxlet registers on itself can't reliably
-- outlive its own uninstall, so this has to live here, not in Muxlet.
registerAnonymousEventHandler("sysUninstallPackage", function(_, name)
    if name ~= MUXLET_PKG then return end
    if F2T_FRESH_UNINSTALL_PENDING then return end
    f2t_debug_log("Muxlet uninstalled unexpectedly; queuing reinstall")
    if MUXLET_URL then
        afterLogin(function() installPackage(MUXLET_URL) end)
    end
end)

-- ── Initialization ────────────────────────────────────────────────────────────
--
-- Content is registered every session regardless of mode so it is available
-- for manual use.
--
-- mux_autostart drives whether Muxlet actually starts:
--   nil   → first run; show mode-selection dialog (ui/popups.lua)
--   true  → auto-start (Full or BYOW choice from first run)
--   false → minimal; Muxlet stays idle until user runs mux start
--
-- f2ce-tools suppresses Muxlet's own welcome popup (mux.welcome_shown = true)
-- because it provides its own onboarding via f2tShowModeSelect().  It also
-- prevents Muxlet's auto_start timer from double-starting by owning fullStart().

-- Loops F2T_CONTENT_REGISTRARS. Also called by devmode.lua after a live
-- reload — Mux.registerContent() overwrites by name, safe to call repeatedly.
function f2tRegisterAllContent()
    for _, registrar in ipairs(F2T_CONTENT_REGISTRARS or {}) do
        local ok, err = pcall(registrar)
        if not ok then
            f2t_debug_log("[init] content registrar error: %s", tostring(err))
        end
    end
end

-- onReady callback passed to Mux.bootHost; runs once a satisfying (exactly
-- pinned) Muxlet is loaded and ready. Settings/content register immediately
-- (so Muxlet's own welcome/autostart timers are suppressed before they can
-- fire); only the mode-select/fullStart decision waits for login.
function f2tInit()
    if f2t_settings_flush_registrations then f2t_settings_flush_registrations() end

    f2tRegisterAllContent()

    -- Muxlet's own host default is false; opt in once, first time seen unset,
    -- so a later user choice is never overridden.
    local updateSettings = Mux.settings._data["f2t"]
    if not (updateSettings and updateSettings["update_check_enabled"] ~= nil) then
        Mux.settings.set("f2t", "update_check_enabled", true)
    end

    afterLogin(function()
        local d         = Mux.settings._data
        local autostart = d and d["f2t"] and d["f2t"]["mux_autostart"]

        if autostart == nil then
            if f2tShowModeSelect then f2tShowModeSelect() end
        elseif autostart == true then
            Mux.fullStart()
        end
        -- autostart == false: Minimal mode — Muxlet is available but not started.
    end)
end

-- Options passed to Mux.bootHost (see Muxlet's update.lua) — combines the old
-- separate Mux.configureHost call and Mux.ensureVersion boot gate into one.
-- defaultWorkspace is intentionally not set here: it depends on which mode the
-- user picks (full vs BYOW), so f2tShowModeSelect owns it, set once at choice
-- time — not re-asserted every session, which would silently fight a BYOW
-- user's choice of Muxlet's blank "default" workspace.
local function bootHostOpts()
    return {
        suppressWelcome = true,   -- f2ce-tools shows its own onboarding (f2tShowModeSelect)
        autoStart       = false,  -- f2ce-tools exclusively decides when Mux.fullStart() runs
        quietStart      = true,   -- f2ce-tools prints its own startup output
        checkForUpdates = false,  -- irrelevant once updateRepo is set below, kept for older Muxlets

        -- Let Muxlet's own update system check f2ce-tools' releases instead of
        -- (only) its own, and offer to bump Muxlet first if a newer release
        -- needs it — same two values already computed above for the boot gate.
        -- pinMuxletVersion = true makes that boot gate an exact pin instead of
        -- a floor: if F2T_REQUIRED_MUXLET is ever set OLDER than what's
        -- installed, Mux.bootHost downgrades rather than treating it as fine.
        updateRepo              = "federation2-community/f2ce-tools",
        requiredMuxletVersion   = F2T_REQUIRED_MUXLET,
        requiredMuxletUrl       = MUXLET_URL,
        pinMuxletVersion        = true,
        -- Keep the "f2t" namespace (so "f2t settings set update_check_enabled
        -- false" etc. keeps working), but give it its own dedicated "Update"
        -- sub-tab under the existing "F2CE-Tools" top-level tab — the same
        -- shape Muxlet's own "Muxlet/Update" tab has, just moved here instead
        -- of living lumped into General.
        updateSettingsNamespace = "f2t",
        updateSettingsTab       = "F2CE-Tools/Update",
        onReady                 = f2tInit,
    }
end

-- ── Boot ──────────────────────────────────────────────────────────────────────
-- Registered unconditionally so it's in place for every muxletReady this
-- session, whether that's Muxlet's first load or a reload triggered below.
local function onMuxletReady()
    if versionSatisfied() then
        Mux.bootHost(bootHostOpts())
        return
    end
    -- Wrong (or missing) version: gate the reinstall on login so it can never
    -- land mid-login-prompt. Mux.bootHost handles the actual upgrade/downgrade;
    -- its own fresh muxletReady re-invokes this handler once it's done.
    f2t_debug_log("Muxlet upgrade/downgrade queued: installed=%s required=%s",
        tostring(Mux and Mux._version), tostring(F2T_REQUIRED_MUXLET))
    afterLogin(function()
        Mux.bootHost(bootHostOpts())
    end)
end

registerAnonymousEventHandler("muxletReady", onMuxletReady)

if Mux and Mux._ready then
    onMuxletReady()
elseif not table.contains(getPackages(), MUXLET_PKG) then
    if not MUXLET_URL then
        cecho("\n<red>[f2ce-tools]<reset> Cannot install Muxlet: build is missing MUXLET_URL injection. "
            .. "Reinstall f2ce-tools from its latest GitHub release.\n")
    else
        f2t_debug_log("Muxlet install queued: not installed (required=%s)", tostring(F2T_REQUIRED_MUXLET))
        afterLogin(function() installPackage(MUXLET_URL) end)
    end
end
-- Otherwise Muxlet is installed but hasn't finished loading yet this
-- session — onMuxletReady above will fire naturally once it does.
