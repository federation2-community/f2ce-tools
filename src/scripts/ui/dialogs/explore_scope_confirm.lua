-- f2ce-tools: explore-scope confirm dialog
--
-- Shown before starting a cartel or syndicate exploration sweep - a long,
-- multi-system (cartel) or multi-cartel (syndicate) process that shouldn't
-- start from a single click (the Galaxy Navigator's state dot) or a single
-- typed command without a chance to back out. Standalone runs only: a
-- cartel sweep nested under a syndicate/galaxy sweep already got its one
-- confirmation at the top of that larger run and shouldn't ask again for
-- every cartel inside it.

local _pendingExploreScopeConfirm = nil

local KIND_SCOPE = {
    cartel    = "every system in the",
    syndicate = "every cartel (and every system in each) in the",
}

local function exploreScopeConfirmBodyText(kind, name)
    return string.format(
        "This explores %s <font color='#7ab4ff'>%s</font> %s.<br><br>" ..
        "This can take a long time and cover a lot of ground. Continue?",
        KIND_SCOPE[kind] or "everything in", name, kind)
end

Mux.registerContent("f2t_explore_scope_confirm", {
    name = "Confirm Exploration",
    internal = true,
    apply = function(target)
        if target.contentBg then target.contentBg:echo(""); target.contentBg:hide() end
        if not _pendingExploreScopeConfirm then return end
        local pending = _pendingExploreScopeConfirm
        _pendingExploreScopeConfirm = nil

        local c = target.content

        local body = Geyser.Label:new({
            name = target._gid .. "_esc_body", x = "5%", y = 14, width = "90%", height = 130,
        }, c)
        body:setStyleSheet(Mux.dialogCss.body .. "qproperty-wordWrap: true;")
        body:echo(exploreScopeConfirmBodyText(pending.kind, pending.name))

        local cancelBtn = Geyser.Label:new({
            name = target._gid .. "_esc_cancel", x = "8%", y = 158, width = "38%", height = 34,
        }, c)
        cancelBtn:setStyleSheet(Mux.dialogCss.button)
        cancelBtn:echo("<center>Cancel</center>")
        Mux.wireDialogButton(cancelBtn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)

        local proceedBtn = Geyser.Label:new({
            name = target._gid .. "_esc_proceed", x = "54%", y = 158, width = "38%", height = 34,
        }, c)
        proceedBtn:setStyleSheet(Mux.dialogCss.buttonPrimary)
        proceedBtn:echo("<center>Explore</center>")
        Mux.wireDialogButton(proceedBtn, Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover)

        -- Close (X) behaves the same as Cancel; a button that already
        -- handles its own close nulls onClose first so it doesn't also fire.
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

--- Shows an Explore/Cancel confirm dialog before a cartel or syndicate sweep.
-- @param kind "cartel" or "syndicate"
function f2tShowExploreScopeConfirm(kind, name, on_proceed, on_cancel)
    local dialog = Mux.createDialog({
        title  = "Confirm Exploration",
        width  = 440,
        height = 240,
    })
    _pendingExploreScopeConfirm = {kind = kind, name = name, on_proceed = on_proceed, on_cancel = on_cancel}
    Mux._applyContent(dialog, "f2t_explore_scope_confirm")
    dialog:show()
    dialog:raise()
end
