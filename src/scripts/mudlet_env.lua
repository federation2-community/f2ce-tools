-- Reconciles two Mudlet 5.0 features that overlap with what f2ce-tools owns:
-- its starter interface, and its server-wrap undo.
--
-- Both are real settings rather than one-shot bookkeeping, so the escape hatch
-- is visible where a player would look for it and the reconciliation stays
-- idempotent. Turn either off and f2ce-tools stops touching that feature.

f2t_settings_register("mudlet", "hide_base_ui", {
    tab         = "F2CE-Tools/Misc",
    label       = "Hide Mudlet's starter interface",
    description = "Mudlet 5.0 preinstalls its own map/chat/gauges dock for newer installs. "
               .. "It draws over the f2ce-tools layout and competes for the single map widget, "
               .. "so it is hidden when the f2ce-tools GUI starts. Turn this off to keep it.",
    default     = true,
})

f2t_settings_register("mudlet", "keep_server_wrap_off", {
    label       = "Keep Mudlet's line-unwrapping off",
    description = "Mudlet 5.0 can rejoin the lines Fed2 wraps itself, and offers a one-click "
               .. "prompt to switch it on. This package's triggers read Fed2's wrapped output "
               .. "directly, so trading, hauling and map capture miss output when it is on.",
    default     = true,
})

-- Mudlet 5.0 preinstalls "Mudlet base UI" on new-ish installs for any game not
-- flagged providesOwnUi, which Federation 2 CE is not. It does not know Muxlet
-- exists: the two write the same window borders absolutely, and both build a
-- Geyser.Mapper over the single per-profile map widget, so whichever loses that
-- race draws blank. Only reachable on an install new enough to have been given
-- the dock at all.
local function hideBaseUi()
    if not f2t_settings_get("mudlet", "hide_base_ui") then return end
    if not (type(BaseUI) == "table" and type(BaseUI.hide) == "function") then return end
    -- dormant() is a predicate, not a flag: true once the starter UI has already
    -- stood aside for a game-supplied interface, in which case there is nothing
    -- on screen to hide and the announcement would only confuse.
    if type(BaseUI.dormant) == "function" then
        local known, isDormant = pcall(BaseUI.dormant)
        if known and isDormant then return end
    end

    local ok, err = pcall(BaseUI.hide)
    if not ok then
        f2t_debug_log("[env] BaseUI.hide failed: %s", tostring(err))
        return
    end
    cecho("\n<yellow>[f2ce-tools]<reset> Hid Mudlet's starter interface, which draws over this "
        .. "package's layout and competes for the map widget.\n"
        .. "  To keep it instead, turn off <cyan>Hide Mudlet's starter interface<reset> under "
        .. "Settings > F2CE-Tools > Misc.\n")
end

-- Fed2 hard-wraps, so Mudlet raises a one-time hint on this profile with a
-- click-to-enable link: a single misclick away, and 74 of this package's 92
-- trigger patterns are anchored regexes written against the wrapped shape.
local function reconcileServerWrap()
    if not f2t_settings_get("mudlet", "keep_server_wrap_off") then return end
    if not (getConfig and setConfig) then return end

    local ok, enabled = pcall(getConfig, "undoServerWrap")
    if not ok or not enabled then return end
    if not pcall(setConfig, "undoServerWrap", false) then return end

    cecho("\n<yellow>[f2ce-tools]<reset> Turned off Mudlet's <cyan>undo the game's own line "
        .. "wrapping<reset> for this profile.\n"
        .. "  This package's triggers read Fed2's wrapped output directly. To use it anyway, "
        .. "turn off <cyan>Keep Mudlet's line-unwrapping off<reset> under Settings > F2CE-Tools "
        .. "> Misc, then set it again in Mudlet.\n")
end

-- muxletStarted, not muxletReady: the dock only collides once Muxlet actually
-- owns the screen. In Minimal mode Mudlet's interface is the only one the player
-- has, so it stays.
registerAnonymousEventHandler("muxletStarted", hideBaseUi)

-- Triggers run in every mode, so this one is not gated on Muxlet starting, only
-- on login, so the announcement cannot land on a password prompt.
registerAnonymousEventHandler("muxletReady", function()
    if f2t_after_login then f2t_after_login(reconcileServerWrap) end
end)
