-- f2tCheckMapImport() runs from map content's apply() (Content Library add or
-- workspace restore) and decides whether to offer the bundled map-database
-- import overlay. Driven entirely by the persisted show_import_prompt
-- setting plus the version re-arm below, never by live room count.
--
-- Resolves f2tGetMapSlotInfo() fresh at build time rather than snapshotting
-- from the calling apply(), since apply() can legitimately re-run mid-startup
-- (workspace restore) and invalidate an earlier snapshot's target slot.
--
-- Reason framing:
--   "firstrun" - profile has never acknowledged a map database version.
--   "upgrade"  - a newer MAP_DB_VERSION shipped than last acknowledged.
--
-- Gating is the user-facing map.show_import_prompt toggle; a newer database
-- version forces it back on via the hidden map_db_version_applied counter.
-- The acknowledgement is written only after the overlay is shown, so a
-- silent miss can't permanently suppress the prompt.
--
-- Bump MAP_DB_VERSION in this file when new maps ship.

local MAP_DB_VERSION = 1

local function appliedVersion()
    local d = Mux and Mux.settings and Mux.settings._data
    return tonumber(d and d["f2t"] and d["f2t"]["map_db_version_applied"]) or 0
end

local function markVersionApplied()
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["map_db_version_applied"] = MAP_DB_VERSION
    Mux.settings.save()
end

function f2tCheckMapImport()
    local seen = appliedVersion()

    -- A newer map database shipped than this profile last acknowledged: force
    -- the user-facing toggle back on so the prompt reaches the user again,
    -- even if they'd turned it off after seeing an older version.
    local reason = (seen > 0) and "upgrade" or "firstrun"
    if seen < MAP_DB_VERSION then
        f2t_settings_set("map", "show_import_prompt", true)
        f2t_debug_log("[map-import] new map db (seen=%d, current=%d) — show_import_prompt re-enabled",
            seen, MAP_DB_VERSION)
    end

    if not f2t_settings_get("map", "show_import_prompt") then
        f2t_debug_log("[map-import] show_import_prompt is off — no prompt")
        return
    end

    -- Web client, first run: skip the overlay entirely and import the
    -- recommended bundled database directly, so a browser first-time user
    -- lands in the full UI with no dialogs. A returning web user on an
    -- "upgrade" reason still gets the overlay below — they can choose.
    if f2t_is_web() and reason == "firstrun" then
        local path = getMudletHomeDir() .. "/f2ce-tools/galaxy_brief.json"
        local ok, result = f2t_map_import_file(path)
        if ok then
            f2t_debug_log("[map-import] web first-run — silently imported %s (%d rooms)", path, result)
        else
            f2t_debug_log("[map-import] web first-run — silent import failed: %s", tostring(result))
        end
        f2t_settings_set("map", "show_import_prompt", false)
        markVersionApplied()
        return
    end

    if not f2tShowMapImportOverlay then
        f2t_debug_log("[map-import] f2tShowMapImportOverlay missing — cannot prompt")
        return
    end

    f2t_debug_log("[map-import] offering import overlay (reason=%s)", reason)

    -- Defer slightly so the mapper/movement/settings overlays built just above
    -- this call finish laying out before the import overlay stacks on top.
    tempTimer(0.2, function()
        local slotContent, gid
        if f2tGetMapSlotInfo then
            slotContent, gid = f2tGetMapSlotInfo()
        end
        if not slotContent then
            f2t_debug_log("[map-import] no live map pane — skipping overlay")
            return
        end
        local shown = f2tShowMapImportOverlay(slotContent, gid, reason)
        -- Only burn the acknowledgement once the overlay genuinely displayed, so a
        -- failed show leaves the prompt armed for the next map load.
        if shown then
            f2t_settings_set("map", "show_import_prompt", false)
            markVersionApplied()
            f2t_debug_log("[map-import] overlay shown — show_import_prompt off, version_applied=%d", MAP_DB_VERSION)
        else
            f2t_debug_log("[map-import] overlay did not show — leaving prompt armed")
        end
    end)
end
