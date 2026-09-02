-- f2ce-tools: Full-layout update confirm dialog
--
-- Shown to a returning Full-mode user when full.lua's workspace layout has
-- moved to a newer F2T_LAYOUT_VERSION (see workspace.lua) than what they last
-- saw. Offers the reload instead of forcing it, since the user may have
-- rearranged panes themselves. BYOW users never see this dialog -- they
-- never load the "f2ce-tools" workspace in the first place.

local _pendingLayoutUpdateConfirm = nil

-- Defined here, registered from the registrar below. A load-time call into
-- Mux raises while Muxlet is mid-reinstall, and everything after it in this
-- file, the show function included, would never be defined.
local layoutUpdateConfirmDef = {
    name = "Layout Updated",
    internal = true,
    apply = function(target)
        if target.contentBg then target.contentBg:echo(""); target.contentBg:hide() end
        if not _pendingLayoutUpdateConfirm then return end
        local pending = _pendingLayoutUpdateConfirm
        _pendingLayoutUpdateConfirm = nil

        local c = target.content

        local body = Geyser.Label:new({
            name = target._gid .. "_luc_body", x = "5%", y = 14, width = "90%", height = 100,
        }, c)
        body:setStyleSheet(Mux.dialogCss.body .. "qproperty-wordWrap: true;")
        body:echo(
            "F2CE-Tools' Full workspace layout has been updated.<br><br>"
            .. "Reload it now? Panes you've rearranged yourself will be reset to the new default."
        )

        local cancelBtn = Geyser.Label:new({
            name = target._gid .. "_luc_cancel", x = "8%", y = 128, width = "38%", height = 34,
        }, c)
        cancelBtn:setStyleSheet(Mux.dialogCss.button)
        cancelBtn:echo("<center>Keep Mine</center>")
        Mux.wireDialogButton(cancelBtn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)

        local proceedBtn = Geyser.Label:new({
            name = target._gid .. "_luc_proceed", x = "54%", y = 128, width = "38%", height = 34,
        }, c)
        proceedBtn:setStyleSheet(Mux.dialogCss.buttonPrimary)
        proceedBtn:echo("<center>Reload</center>")
        Mux.wireDialogButton(proceedBtn, Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover)

        -- Close (X) behaves the same as "Keep Mine"; a button that already
        -- handles its own close nulls onClose first so it doesn't also fire.
        target.onClose = function() pending.on_keep() end
        cancelBtn:setClickCallback(function()
            target.onClose = nil
            target:close()
            pending.on_keep()
        end)
        proceedBtn:setClickCallback(function()
            target.onClose = nil
            target:close()
            pending.on_reload()
        end)
    end,
    remove = function(_) end,
}

--- Shows a Reload/Keep Mine confirm dialog for a Full-layout update.
-- on_keep defaults to a no-op since the caller only needs to react to reload.
function f2tShowLayoutUpdateConfirm(on_reload, on_keep)
    local dialog = Mux.createDialog({
        title  = "Layout Updated",
        width  = 420,
        height = 210,
    })
    _pendingLayoutUpdateConfirm = { on_reload = on_reload, on_keep = on_keep or function() end }
    Mux._applyContent(dialog, "f2t_layout_update_confirm")
    dialog:show()
    dialog:raise()
end

local function f2tRegisterLayoutUpdateConfirm()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("f2t_layout_update_confirm", layoutUpdateConfirmDef)
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterLayoutUpdateConfirm)
