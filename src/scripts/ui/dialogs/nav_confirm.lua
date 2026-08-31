-- f2ce-tools: navigate-hint confirm dialog
--
-- Shown by f2t_map_navigate when a typed destination isn't in the local map
-- but resolve_location found something worth acting on (a known-but-
-- incomplete planet/system, or a whereis-confirmed real place). Interactive
-- callers (the `nav` alias) only - automated callers skip this and explore
-- immediately instead.

local _pendingNavConfirm = nil

local function navConfirmBodyText(destination, hint)
    -- Two different problems wear the same dialog: a place the map has never
    -- heard of, and a place it knows but has no route to.
    local problem = hint.mapped_but_unreachable
        and string.format("Your map has no route to '%s' yet.", destination)
        or string.format("'%s' isn't in your map yet.", destination)

    if hint.kind == "planet" then
        return string.format(
            "%s<br><br>Explore <font color='#7ab4ff'>%s</font> to look for its %s?",
            problem, hint.name, hint.flag)
    end
    return string.format(
        "%s<br><br>Travel to the <font color='#7ab4ff'>%s</font> system and explore for it?",
        problem, hint.name)
end

Mux.registerContent("f2t_nav_confirm", {
    name = "Destination Not Found",
    internal = true,
    apply = function(target)
        if target.contentBg then target.contentBg:echo(""); target.contentBg:hide() end
        if not _pendingNavConfirm then return end
        local pending = _pendingNavConfirm
        _pendingNavConfirm = nil

        local c = target.content

        local body = Geyser.Label:new({
            name = target._gid .. "_nc_body", x = "5%", y = 14, width = "90%", height = 100,
        }, c)
        body:setStyleSheet(Mux.dialogCss.body)
        body:echo(navConfirmBodyText(pending.destination, pending.hint))

        local cancelBtn = Geyser.Label:new({
            name = target._gid .. "_nc_cancel", x = "8%", y = 128, width = "38%", height = 34,
        }, c)
        cancelBtn:setStyleSheet(Mux.dialogCss.button)
        cancelBtn:echo("<center>Cancel</center>")
        Mux.wireDialogButton(cancelBtn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)

        local proceedBtn = Geyser.Label:new({
            name = target._gid .. "_nc_proceed", x = "54%", y = 128, width = "38%", height = 34,
        }, c)
        proceedBtn:setStyleSheet(Mux.dialogCss.buttonPrimary)
        proceedBtn:echo("<center>Proceed</center>")
        Mux.wireDialogButton(proceedBtn, Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover)

        -- Close (X) behaves the same as Cancel; a button that already handles
        -- its own close nulls onClose first so it doesn't also fire it.
        target.onClose = function() pending.on_cancel() end
        cancelBtn:setClickCallback(function()
            target.onClose = nil
            target:close()
            pending.on_cancel()
        end)
        proceedBtn:setClickCallback(function()
            target.onClose = nil
            target:close()
            pending.on_proceed()
        end)
    end,
    remove = function(_) end,
})

--- Shows a Proceed/Cancel confirm dialog for an unresolved nav destination.
-- Not resizable/convertible/anchorable/minimizable/zoomable; movable is fine
-- (all defaults on Mux.createDialog already match this).
function f2tShowNavHintConfirm(destination, hint, error_msg, on_proceed, on_cancel)
    local dialog = Mux.createDialog({
        title  = "Destination Not Found",
        width  = 420,
        height = 210,
    })
    _pendingNavConfirm = {
        destination = destination, hint = hint, error_msg = error_msg,
        on_proceed = on_proceed, on_cancel = on_cancel,
    }
    Mux._applyContent(dialog, "f2t_nav_confirm")
    dialog:show()
    dialog:raise()
end
