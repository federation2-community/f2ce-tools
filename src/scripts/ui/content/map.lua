-- Registers the F2CE Map content with Muxlet: apply/remove lifecycle hooks
-- mount and unmount a Geyser.Mapper widget inside a Muxlet pane.
--
-- The embedded map widget is a per-profile singleton (TMainConsole::mpMapper
-- in Mudlet), not a Qt child of its Geyser container, so deleting the slot
-- doesn't remove it and reparenting an existing wrapper leaves it blank. On
-- release we hide the native mapper and drop our wrapper reference (see
-- releaseLive() for why we don't call m:delete()); on acquire we create a
-- fresh wrapper, which re-points the singleton at the new slot. None of this
-- touches the map database, which lives in Host::mpMap.
--
-- f2tRegisterMapContent() is called from init.lua's muxletReady handler.
--
-- F2T_DEBUG logging times and counts apply/remove/resize and every
-- createMapper()/updateMap() pass, to track teardown/rebuild cost per login.

-- Mapper management
local liveMapper = nil    -- the wrapper currently shown in a pane (or nil)
local mapperSeq  = 0      -- wrapper names are never reused (Qt caches by name)
local applyCount  = 0     -- diagnostic: how many times apply() has fired this session
local removeCount = 0     -- diagnostic: how many times remove() has fired this session
local resizeCount = 0     -- diagnostic: how many times resize() has fired this session

-- Slot container + gid of the currently live map pane, so code outside this
-- apply() closure (settings gear menu, "map import db" alias) can build the
-- import overlay into the right place. See f2tGetMapSlotInfo() below.
local liveSlotContent = nil
local liveGid         = nil

-- Deliberately doesn't call m:delete(): Mudlet's GeyserMapper.lua routes
-- type_delete() through closeMapWidget(), which wedges the singleton native
-- mapper (TMainConsole::mpMapper) when called on an embedded mapper - the
-- next createMapper() sizes correctly, but its room-graphics layer never
-- paints again this session. m:hide() alone already zeros the embedded
-- mapper via Geyser's own embedded-aware path, and mapperSeq below
-- guarantees each new wrapper gets a unique window name.
local function releaseLive()
    if not liveMapper then return end
    local m = liveMapper
    liveMapper = nil
    pcall(function() m:hide() end)      -- sizes the singleton native mapper to 0×0
end

-- Acquire a mapper into `slotContent`.  Always a FRESH wrapper (reparenting an
-- existing one renders blank), with the prior one released first.
local function mapperAcquire(slotContent)
    local tAcquireStart = os.clock()
    releaseLive()

    mapperSeq = mapperSeq + 1
    local tCreateStart = os.clock()
    liveMapper = Geyser.Mapper:new({
        name   = "f2t_mapper_" .. mapperSeq,
        x      = "0%", y = "0%",
        width  = "100%", height = "100%",
    }, slotContent)
    f2t_debug_log("[map content] mapperAcquire #%d: Geyser.Mapper:new (createMapper) took %.0fms",
        mapperSeq, (os.clock() - tCreateStart) * 1000)

    pcall(function()
        liveMapper:show()
        liveMapper:reposition()
    end)

    if updateMap then
        local tUpdateStart = os.clock()
        pcall(updateMap)
        f2t_debug_log("[map content] mapperAcquire #%d: updateMap() took %.0fms",
            mapperSeq, (os.clock() - tUpdateStart) * 1000)
    end

    f2t_debug_log("[map content] mapperAcquire #%d total: %.0fms",
        mapperSeq, (os.clock() - tAcquireStart) * 1000)
    return liveMapper
end

-- Release the live mapper on content removal, BEFORE the slot is destroyed, so
-- it is never orphaned in a deleted container nor left drawing over the
-- replacement.
local function mapperRelease()
    releaseLive()
end

-- Refit the live mapper to the current slot (called from resize()).
local function mapperFit()
    if not liveMapper then return end
    local tFitStart = os.clock()
    pcall(function()
        liveMapper:move("0%", "0%")
        liveMapper:resize("100%", "100%")
        liveMapper:reposition()
    end)
    if updateMap then
        local tUpdateStart = os.clock()
        pcall(updateMap)
        f2t_debug_log("[map content] mapperFit: updateMap() took %.0fms",
            (os.clock() - tUpdateStart) * 1000)
    end
    f2t_debug_log("[map content] mapperFit total: %.0fms", (os.clock() - tFitStart) * 1000)
end

-- ── Post-mount view sync ─────────────────────────────────────────────────────
-- Mudlet's 2D mapper draws a room cell at min(widgetW, widgetH) / areaZoom
-- pixels, and it takes both its zoom AND its displayed area from whatever
-- f2t_map_handle_gmcp_room() last applied via setMapZoom()/centerview().  Until
-- that has run *with a live native mapper*, the widget keeps some other area at
-- some other zoom — which renders as a couple of rooms blown up to the size of
-- the whole pane.
--
-- A single attempt at mount is not enough.  Two independent ways it misses:
--   * gmcp.room.info has not landed yet (the handler early-returns), which is
--     common on the new-character path where the room burst trails the UI build;
--   * the native mapper is not up yet, and setMapZoom() fails soft with
--     "no active mapper" — it returns nil + message rather than raising.
-- Either miss used to persist until the player moved.  It only looked rare
-- because a *first-run* profile also runs the silent map import, whose
-- tempTimer(0.5, f2t_map_sync) happened to re-apply the view as a side effect;
-- profiles that skip the import (and unlucky first-run ones) had nothing.
--
-- There is a third miss, and measurement showed it is the one that actually
-- bites: the widget's GEOMETRY, not its zoom (see settleView below).  A fix
-- that only re-applied zoom/centre was built and A/B tested against the
-- released package and did NOT repair the view — zoom was already correct.
-- Hence the settle loop refits the widget every tick rather than gating on
-- viewIsApplied(), which is kept only as a debug-log signal.
local VIEW_SYNC_RETRY_DELAYS = {0.25, 0.75, 1.5, 3.0}

-- Diagnostic only: has the widget been pointed at the player's area at our
-- zoom?  NOT used to skip work — a "yes" here was true throughout the bug.
local function viewIsApplied()
    local room = F2T_MAP_CURRENT_ROOM_ID
    if not room then return false end
    local ok_exists, exists = pcall(roomExists, room)
    if not ok_exists or not exists then return false end
    local ok_area, area = pcall(getRoomArea, room)
    if not ok_area or not area then return false end
    local want = tonumber(f2t_settings_get("map", "area_zoom"))
    if not want then return true end          -- nothing to verify against
    local ok_zoom, got = pcall(getMapZoom, area)
    return ok_zoom and tonumber(got) == want
end

-- Deliberately NOT a plain re-run of f2t_map_handle_gmcp_room(): that handler
-- also processes exits and can fire on-arrival commands, so calling it on every
-- retry risks duplicate side effects.  Once the room is known, re-apply just the
-- two view calls, which are idempotent.  Only fall back to the full handler
-- while the room is still unknown, i.e. the handler never got to run at all.
local function applyMapView()
    local room = F2T_MAP_CURRENT_ROOM_ID
    if not room then
        if type(f2t_map_handle_gmcp_room) == "function" then
            pcall(f2t_map_handle_gmcp_room)
        end
        return
    end
    local ok_area, area = pcall(getRoomArea, room)
    if not ok_area or not area then return end
    local want = tonumber(f2t_settings_get("map", "area_zoom"))
    if want then pcall(setMapZoom, want, area) end
    pcall(centerview, room)
end

local function buildContentDef()
    -- Token-based guard: each apply mints a new token table.  The deferred timer
    -- checks this token before building; remove() clears it so a timer that fires
    -- after removal is a no-op (prevents an orphaned mapper on rapid apply→remove).
    local activeToken = nil

    return {
        name        = "F2CE Map",
        description = "F2CE mapper",
        group       = "F2CE Tools",
        singleton   = true,

        apply = function(target)
            applyCount = applyCount + 1
            local tApplyStart = os.clock()
            f2t_debug_log("[map content] apply() #%d called (epoch=%s)",
                applyCount, tostring(getEpoch and getEpoch() or os.time()))

            target.contentBg:echo("")
            target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
            target.contentBg:hide()

            local gid = target._gid

            -- target.content points to the framework's slot container right now
            -- (during apply).  After this function returns, the framework restores
            -- target.content to the real pane container, so the deferred callback
            -- must capture the slot reference here before returning.
            local slotContent = target.content

            local myToken = {}
            activeToken = myToken

            tempTimer(0.1, function()
                if activeToken ~= myToken then return end

                -- Build the mapper + overlays under pcall so a failure here can
                -- never swallow the import-check scheduling below.
                local ok, err = pcall(function()
                    local mapper = mapperAcquire(slotContent)
                    target._f2tHasMapper = true
                    liveSlotContent, liveGid = slotContent, gid
                    if mapper then mapper:raise() end

                    -- Re-syncs to the current room (cached GMCP, no command sent) so
                    -- the fresh widget doesn't open on a stale prior-session room,
                    -- and suppresses Mudlet's native empty-map overlay when unpopulated.
                    if type(f2t_map_handle_gmcp_room) == "function" then
                        f2t_map_handle_gmcp_room()
                    end

                    -- ...and then settle the view over the next few seconds.
                    -- See VIEW_SYNC_RETRY_DELAYS above for why one shot isn't
                    -- enough. Each tick refits the widget to its slot as well as
                    -- re-applying zoom/centre: the native mapper is a singleton
                    -- that does NOT track its Geyser container's geometry (Mudlet's
                    -- T2DMap has no resizeEvent), so when the pane is still being
                    -- laid out at mount it can end up sized to something far larger
                    -- than the slot. Room cells are min(widgetW,widgetH)/zoom, so an
                    -- oversized widget draws rooms many times too big and the pane
                    -- shows a clipped corner of them — the reported symptom. Both
                    -- calls are idempotent, so ticking a few times is harmless.
                    local function settleView(attempt)
                        if activeToken ~= myToken then return end   -- pane went away
                        mapperFit()
                        applyMapView()
                        local delay = VIEW_SYNC_RETRY_DELAYS[attempt]
                        if not delay then
                            f2t_debug_log("[map content] view settle finished after %d ticks (applied=%s)",
                                attempt, tostring(viewIsApplied()))
                            return
                        end
                        tempTimer(delay, function() settleView(attempt + 1) end)
                    end
                    settleView(1)

                    -- Movement button overlay lives on top of the mapper.  It is
                    -- a true child of the slot, so the framework's slot delete
                    -- removes it cleanly on content change/removal.
                    if f2tBuildMapMovement then
                        local mvShell = f2tBuildMapMovement(slotContent, gid)
                        if mvShell then mvShell:raise() end
                    end

                    -- Settings gear (manual import/export) — top of the stack.
                    if f2tBuildMapSettings then
                        local setShell = f2tBuildMapSettings(slotContent, gid)
                        if setShell then setShell:raise() end
                    end
                end)
                if not ok then
                    f2t_debug_log("[map content] overlay build error: %s", tostring(err))
                end

                -- Offer the bundled map-database import overlay on first load /
                -- after an upgrade (decision lives entirely in f2tCheckMapImport's
                -- persisted show_import_prompt setting — see map/import_check.lua;
                -- it never looks at room count). Built directly into this slot
                -- (not a separate floating dialog) so it stacks above the native
                -- mapper widget exactly like the overlays above.
                if f2tCheckMapImport then
                    f2tCheckMapImport()
                else
                    f2t_debug_log("[map content] f2tCheckMapImport missing — cannot offer import")
                end

                f2t_debug_log("[map content] apply() #%d deferred build total: %.0fms",
                    applyCount, (os.clock() - tApplyStart) * 1000)
            end)
        end,

        -- Detach the shared mapper into the hidden garage BEFORE the framework
        -- deletes the slot, so it is never orphaned inside a deleted container and
        -- never keeps drawing over whatever content replaces it.  The movement /
        -- settings overlays are real slot children and are removed by the slot
        -- delete automatically.
        remove = function(target)
            removeCount = removeCount + 1
            f2t_debug_log("[map content] remove() #%d called (epoch=%s)",
                removeCount, tostring(getEpoch and getEpoch() or os.time()))
            activeToken = nil
            mapperRelease()
            target._f2tHasMapper = nil
            liveSlotContent, liveGid = nil, nil
        end,

        -- Keep the mapper filling the slot as the pane/tab is resized.
        resize = function(target)
            resizeCount = resizeCount + 1
            f2t_debug_log("[map content] resize() #%d called, hasMapper=%s",
                resizeCount, tostring(target._f2tHasMapper))
            if target._f2tHasMapper then mapperFit() end
        end,
    }
end

-- Lets code outside this apply() closure (settings gear menu, "map import db"
-- alias) build the import overlay into the live map pane's slot. Returns
-- nil, nil if no F2CE Map content is currently applied anywhere.
function f2tGetMapSlotInfo()
    return liveSlotContent, liveGid
end

-- Reports whether a native mapper widget is currently live in a pane.
--
-- Mudlet gates loadJsonMap/saveJsonMap/deleteMap behind an open mapper widget
-- (they fail with "no map present or loaded" otherwise). The widget only exists
-- once a F2CE Map pane has mounted it via mapperAcquire() above — i.e. in Full
-- or BYOW mode, or after "mux start" + opening the map. In Minimal mode no pane
-- ever mounts, so no widget exists, and callers must take a widget-free path
-- rather than touching those functions. import_export.lua uses this to decide
-- between Mudlet's native loader/saver (widget present) and a headless rebuild
-- straight through the room-database API (widget absent). Deliberately does NOT
-- create a widget: Minimal mode promises the user's Mudlet layout is untouched.
function f2tMapHasLiveMapper()
    return liveMapper ~= nil
end

function f2tRegisterMapContent()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("fed2_map", buildContentDef())
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterMapContent)