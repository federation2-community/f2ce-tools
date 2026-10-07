-- f2ce-tools: uninsured warning dialog
--
-- Shown by f2t_insurance_check before something risky (exploring, resuming
-- work after a death) while the player isn't insured. Get Insured walks to the
-- nearest broker and buys a policy, then carries on; Go Anyway carries on
-- uninsured until the next policy or death; Cancel (or closing) doesn't.

local _pendingInsuranceConfirm = nil

-- Defined here, registered from the registrar below. A load-time call into
-- Mux raises while Muxlet is mid-reinstall, and everything after it in this
-- file, the show function included, would never be defined.
local insuranceConfirmDef = {
    name = "Not Insured",
    internal = true,
    apply = function(target)
        if target.contentBg then target.contentBg:echo(""); target.contentBg:hide() end
        if not _pendingInsuranceConfirm then return end
        local pending = _pendingInsuranceConfirm
        _pendingInsuranceConfirm = nil

        local c = target.content

        local body = Geyser.Label:new({
            name = target._gid .. "_ic_body", x = "5%", y = 14, width = "90%", height = 120,
        }, c)
        body:setStyleSheet(Mux.dialogCss.body .. "qproperty-wordWrap: true;")
        body:echo(string.format(
            "<font color='#ff6b6b'><b>You aren't insured.</b></font> Dying while %s would be permanent: "
            .. "your character would be gone.<br><br>"
            .. "<i>Get Insured</i> walks to the nearest insurance broker, buys a policy and carries on. "
            .. "<i>Go Anyway</i> carries on uninsured until you next insure.", pending.what))

        local function button(key, label, x, css, cssHover, choice)
            local btn = Geyser.Label:new({
                name = target._gid .. "_ic_" .. key, x = x, y = 142, width = "31%", height = 34,
            }, c)
            btn:setStyleSheet(css)
            btn:echo("<center>" .. label .. "</center>")
            Mux.wireDialogButton(btn, css, cssHover)
            btn:setClickCallback(function()
                target.onClose = nil
                target:close()
                pending.onChoice(choice)
            end)
        end
        button("cancel", "Cancel", "2%", Mux.dialogCss.button, Mux.dialogCss.buttonHover, "cancel")
        button("anyway", "Go Anyway", "35%", Mux.dialogCss.button, Mux.dialogCss.buttonHover, "anyway")
        button("insure", "Get Insured", "68%", Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover,
            "insure")

        -- Closing (X) is Cancel; buttons clear this before closing.
        target.onClose = function() pending.onChoice("cancel") end
        target._autoFitHeight = 196
    end,
    remove = function(_) end,
}

--- Shows the uninsured warning
--- @param what string what is about to happen, e.g. "exploring"
--- @param onChoice function onChoice("insure"|"anyway"|"cancel")
function f2tShowInsuranceConfirm(what, onChoice)
    local dialog = Mux.createDialog({
        title  = "Not Insured",
        width  = 460,
        height = 225,
    })
    _pendingInsuranceConfirm = { what = what, onChoice = onChoice }
    Mux._applyContent(dialog, "f2t_insurance_confirm")
    dialog:show()
    dialog:raise()
end

local function f2tRegisterInsuranceConfirm()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("f2t_insurance_confirm", insuranceConfirmDef)
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterInsuranceConfirm)
