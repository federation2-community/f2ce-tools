-- f2tCheckMapImport() runs from map content's apply() (Content Library add or
-- workspace restore) and decides whether to offer the bundled map-database
-- import overlay. Driven entirely by the persisted show_import_prompt
-- setting plus the hash re-arm below, never by live room count.
--
-- Resolves f2tGetMapSlotInfo() fresh at build time rather than snapshotting
-- from the calling apply(), since apply() can legitimately re-run mid-startup
-- (workspace restore) and invalidate an earlier snapshot's target slot.
--
-- Reason framing:
--   "firstrun" - profile has never acknowledged a bundled map database.
--   "upgrade"  - the bundled galaxy_brief.json's content changed since the
--                last acknowledged hash.
--
-- Gating is the user-facing map.show_import_prompt toggle; a changed bundled
-- database forces it back on via the hidden map_db_hash_seen setting. The
-- acknowledgement is written only after the overlay is shown, so a silent
-- miss can't permanently suppress the prompt.
--
-- The hash is content-based (not a hand-bumped counter) so a re-exported
-- galaxy_brief.json can never ship without re-arming the prompt -- mirrors
-- f2tFullStart's F2T_LAYOUT_HASH approach in ui/workspace.lua.

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

local function bundledMapPath()
    return getMudletHomeDir() .. "/f2ce-tools/galaxy_brief.json"
end

-- Hash of the bundled galaxy_brief.json as shipped this session, or nil if it
-- couldn't be read.
local function bundledMapHash()
    local f = io.open(bundledMapPath(), "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return contentHash(content)
end

local function seenHash()
    local d = Mux and Mux.settings and Mux.settings._data
    return d and d["f2t"] and d["f2t"]["map_db_hash_seen"]
end

local function markHashSeen(hash)
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["map_db_hash_seen"] = hash
    Mux.settings.save()
end

function f2tCheckMapImport()
    local hash = bundledMapHash()
    local seen = seenHash()

    -- A changed bundled database: force the user-facing toggle back on so
    -- the prompt reaches the user again, even if they'd turned it off after
    -- seeing an older one.
    local reason = seen and "upgrade" or "firstrun"
    if hash and hash ~= seen then
        f2t_settings_set("map", "show_import_prompt", true)
        f2t_debug_log("[map-import] bundled map db changed (seen=%s, current=%s) — show_import_prompt re-enabled",
            tostring(seen), tostring(hash))
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
        -- Defer off the synchronous apply() call (mirrors the overlay path's
        -- tempTimer stagger) so the UI paints before the potentially large
        -- galaxy_brief.json import runs — avoids a first-login freeze on web.
        tempTimer(0.2, function()
            local path = bundledMapPath()
            local ok, result = f2t_map_import_file(path)
            if ok then
                f2t_debug_log("[map-import] web first-run — silently imported %s (%d rooms)", path, result)
            else
                f2t_debug_log("[map-import] web first-run — silent import failed: %s", tostring(result))
            end
            f2t_settings_set("map", "show_import_prompt", false)
            markHashSeen(hash)
        end)
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
            markHashSeen(hash)
            f2t_debug_log("[map-import] overlay shown — show_import_prompt off, hash_seen=%s", tostring(hash))
        else
            f2t_debug_log("[map-import] overlay did not show — leaving prompt armed")
        end
    end)
end
