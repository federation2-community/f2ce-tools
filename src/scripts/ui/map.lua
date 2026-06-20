-- fed2-tools — Map content registration
--
-- Registers the Fed2 Map content with Muxlet: apply/remove lifecycle hooks that
-- mount and unmount the Geyser.Mapper widget inside a Muxlet pane.
--
-- f2tRegisterMapContent() is called from init.lua's muxletReady handler.

local function buildContentDef()
    return {
        name        = "Fed2 Map",
        description = "Federation 2 mapper",
        singleton   = true,

        apply = function(target)
            closeMapWidget()
            target.contentBg:echo("")
            target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")

            -- Use _gid (never recycled) for the widget name so that closing a
            -- pane and creating a new one with the same user-facing id does not
            -- alias the old, now-hidden mapper widget and show blank content.
            local mapperName = target._gid .. "_fed2mapper"
            local capturedTarget = target
            tempTimer(0.1, function()
                local existing = Geyser.windowList[mapperName]
                if existing then
                    existing:show()
                    existing:raise()
                else
                    Geyser.Mapper:new({
                        name   = mapperName,
                        x      = "0%",
                        y      = "0%",
                        width  = "100%",
                        height = "100%",
                    }, capturedTarget.content)
                end

                -- Movement button overlay lives on top of the mapper.
                local mvName = capturedTarget._gid .. "_mv_shell"
                if not Geyser.windowList[mvName] then
                    if f2tBuildMapMovement then
                        local mvShell = f2tBuildMapMovement(capturedTarget.content, capturedTarget._gid)
                        if mvShell then mvShell:raise() end
                    end
                else
                    Geyser.windowList[mvName]:show()
                    Geyser.windowList[mvName]:raise()
                end

                -- Trigger map import dialog if the map DB is empty or an upgrade
                -- flagged a new database.  Deferred further so any onboarding
                -- dialog that just closed has a chance to finish animating out.
                tempTimer(0.5, function()
                    if f2tCheckMapImport then f2tCheckMapImport() end
                end)
            end)
        end,

    }
end

function f2tRegisterMapContent()
    Mux.registerContent("fed2_map", buildContentDef())
end
