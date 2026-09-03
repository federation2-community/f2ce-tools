-- f2ce-tools: Full-layout update confirm dialog
--
-- Shown to a returning Full-mode user when full.lua's workspace layout has
-- changed (by content hash, F2T_LAYOUT_HASH -- see workspace.lua) since what
-- they last saw, regardless of how the installed package was built. Offers
-- the reload instead of forcing it, since the user may have rearranged
-- panes themselves. BYOW users never see this dialog -- they never load the
-- "f2ce-tools" workspace in the first place.
--
-- Note this dialog's choice never affects whether the SAVED "f2ce-tools"
-- workspace definition matches full.lua -- f2tRegisterWorkspace (see
-- workspace.lua) rebuilds and re-registers it fresh from full.lua's current
-- content on every load, unconditionally, regardless of what happens here.
-- This dialog only decides whether the user's currently ACTIVE session also
-- gets switched to match it.

local _pendingLayoutUpdateConfirm = nil

-- Defined here, registered from the registrar below. A load-time call into
-- Mux raises while Muxlet is mid-reinstall, and everything after it in this
-- file, the show function included, would never be defined.
local layoutUpdateConfirmDef = {
    name = "F2CE-Tools Full Workspace Updated",
    internal = true,
    apply = function(target)
        if target.contentBg then target.contentBg:echo(""); target.contentBg:hide() end
        if not _pendingLayoutUpdateConfirm then return end
        local pending = _pendingLayoutUpdateConfirm
        _pendingLayoutUpdateConfirm = nil

        local c = target.content

        local body = Geyser.Label:new({
            name = target._gid .. "_luc_body", x = "5%", y = 14, width = "90%", height = 120,
        }, c)
        body:setStyleSheet(Mux.dialogCss.body .. "qproperty-wordWrap: true;")
        body:echo(
            "F2CE-Tools' Full workspace layout has been updated.<br><br>"
            .. "Reload it now? Panes you've rearranged yourself will be reset to the new default."
            .. "<br><br>"
            .. "<i>Not This Time</i> asks again once it changes further; <i>Never Prompt</i> turns "
            .. "this off for good (F2CE-Tools/Misc settings). Closing this dialog asks again next "
            .. "time the profile starts."
        )

        -- One row of three -- the earlier overflow wasn't from cramming
        -- three across (percentage widths below sum well under 100%), it
        -- was _autoFitHeight (see below) being set shorter than this row's
        -- own bottom edge, and Mux._applyContent forcibly resizes the
        -- dialog to _autoFitHeight + chrome on open regardless of what
        -- height was requested from Mux.createDialog.
        local notThisTimeBtn = Geyser.Label:new({
            name = target._gid .. "_luc_not_this_time", x = "2%", y = 142, width = "31%", height = 34,
        }, c)
        notThisTimeBtn:setStyleSheet(Mux.dialogCss.button)
        notThisTimeBtn:echo("<center>Not This Time</center>")
        Mux.wireDialogButton(notThisTimeBtn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)

        local neverBtn = Geyser.Label:new({
            name = target._gid .. "_luc_never", x = "35%", y = 142, width = "31%", height = 34,
        }, c)
        neverBtn:setStyleSheet(Mux.dialogCss.button)
        neverBtn:echo("<center>Never Prompt</center>")
        Mux.wireDialogButton(neverBtn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)

        local reloadBtn = Geyser.Label:new({
            name = target._gid .. "_luc_reload", x = "68%", y = 142, width = "31%", height = 34,
        }, c)
        reloadBtn:setStyleSheet(Mux.dialogCss.buttonPrimary)
        reloadBtn:echo("<center>Reload</center>")
        Mux.wireDialogButton(reloadBtn, Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover)

        -- Closing (the titlebar X) is deliberately a true no-op -- no
        -- onClose handler at all -- so nothing gets recorded and the prompt
        -- reappears next time the profile starts, distinct from both
        -- "Not This Time" (persists past this session, until full.lua
        -- changes again) and "Never Prompt" (persists until re-enabled in
        -- settings).
        notThisTimeBtn:setClickCallback(function()
            target:close()
            pending.on_not_this_time()
        end)
        neverBtn:setClickCallback(function()
            target:close()
            pending.on_never()
        end)
        reloadBtn:setClickCallback(function()
            target:close()
            pending.on_reload()
        end)
        -- Button row bottom edge (142+34=176) plus bottom padding: the real
        -- dialog height ends up _autoFitHeight + chrome (~26px), not
        -- whatever's passed to Mux.createDialog below.
        target._autoFitHeight = 196
    end,
    remove = function(_) end,
}

--- Shows a Reload/Not This Time/Never Prompt confirm dialog for a Full-layout
--- update. on_not_this_time and on_never default to no-ops since some
--- callers only need to react to reload.
function f2tShowLayoutUpdateConfirm(on_reload, on_not_this_time, on_never)
    local dialog = Mux.createDialog({
        title  = "F2CE-Tools Full Workspace Updated",
        width  = 460,
        height = 225,
    })
    _pendingLayoutUpdateConfirm = {
        on_reload        = on_reload,
        on_not_this_time = on_not_this_time or function() end,
        on_never         = on_never or function() end,
    }
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
