-- Reconciles Mudlet 5.0's server-wrap undo with what f2ce-tools owns. Hiding
-- Mudlet's starter interface lives in Muxlet (mux.hideBaseUi).
--
-- A real setting rather than one-shot bookkeeping, so the escape hatch is
-- visible where a player would look for it and the reconciliation stays
-- idempotent. Turn it off and f2ce-tools stops touching that feature.

f2t_settings_register("mudlet", "keep_server_wrap_off", {
    tab         = "F2CE-Tools/Misc",
    label       = "Keep Mudlet's line-unwrapping off",
    description = "Mudlet 5.0 can rejoin the lines Fed2 wraps itself, and offers a one-click "
               .. "prompt to switch it on. This package's triggers read Fed2's wrapped output "
               .. "directly, so trading, hauling and map capture miss output when it is on.",
    default     = true,
})

-- Carries a player's "keep it" choice from the retired f2ce-tools hide_base_ui
-- setting over to Muxlet's, then drops the old value so it cannot override a
-- later change made in Muxlet.
local function migrateHideBaseUi()
    local stored = Mux.settings._data.mudlet
    if not (stored and stored.hide_base_ui ~= nil) then return end
    if stored.hide_base_ui == false and not Mux.settings.set("mux", "hideBaseUi", false) then
        return
    end
    stored.hide_base_ui = nil
    Mux.settings.save()
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

-- Triggers run in every mode, so the wrap check is not gated on Muxlet starting,
-- only on login, so the announcement cannot land on a password prompt.
registerAnonymousEventHandler("muxletReady", function()
    migrateHideBaseUi()
    if f2t_after_login then f2t_after_login(reconcileServerWrap) end
end)

if Mux and Mux._ready then migrateHideBaseUi() end
