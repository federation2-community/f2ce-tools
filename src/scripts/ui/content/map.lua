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
            f2t_debug_log("[map content] apply() #%d called (epoch=%s)", applyCount, tostring(getEpoch and getEpoch() or os.time()))

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

                    -- Mudlet's own mapper widget shows a built-in "No map yet
                    -- for this profile" empty-state overlay whenever the room
                    -- database is empty, with its own raw Load/Create buttons
                    -- — entirely outside f2ce-tools' control, no Lua hook to
                    -- suppress it. This is UNRELATED to the show_import_prompt
                    -- decision below: it just seeds the player's current room
                    -- from already-cached GMCP data (no command sent to the
                    -- game) whenever the database happens to be empty, purely
                    -- so that native overlay never gets a chance to stick —
                    -- f2ce-tools decides what the user sees here, never raw
                    -- Mudlet. See map/import_check.lua for the prompt decision
                    -- itself, which never looks at room count.
                    if next(getRooms()) == nil and type(f2t_map_handle_gmcp_room) == "function" then
                        f2t_map_handle_gmcp_room()
                    end

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
            f2t_debug_log("[map content] remove() #%d called (epoch=%s)", removeCount, tostring(getEpoch and getEpoch() or os.time()))
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