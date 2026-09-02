-- f2ce-tools: explore-reset confirm dialog
--
-- Shown when a brief system sweep finishes but never found every expected
-- planet, even after the frontier walk exhausted every reachable exit. The
-- map's stub data can simply be stale - a server-side rebuild (a Dyson
-- Sphere build, etc.) can renumber a system's whole space area and leave old
-- rooms behind - and resetting the area lets the ordinary explorer rediscover
-- it as genuinely new territory. Destructive (deletes every room in the
-- system's space area), so this always asks before doing it. Standalone
-- system explores only - a nested sweep (cartel/galaxy/hauling) has no user
-- watching a dialog for, so it never offers this.

local _pendingExploreResetConfirm = nil

local function exploreResetConfirmBodyText(system_name, missing)
    local plural = #missing > 1
    return string.format(
        "Exploration couldn't find %s: <font color='#7ab4ff'>%s</font>.<br><br>" ..
        "Reset <font color='#7ab4ff'>%s</font>'s space and re-explore it from scratch, in case the " ..
        "map's current data is stale?",
        plural and "these expected planets" or "this expected planet",
        table.concat(missing, ", "), system_name)
end

-- Defined here, registered from the registrar below. A load-time call into
-- Mux raises while Muxlet is mid-reinstall, and everything after it in this
-- file, the show function included, would never be defined.
local exploreResetConfirmDef = {
    name = "Exploration Incomplete",
    internal = true,
    apply = function(target)
        if target.contentBg then target.contentBg:echo(""); target.contentBg:hide() end
        if not _pendingExploreResetConfirm then return end
        local pending = _pendingExploreResetConfirm
        _pendingExploreResetConfirm = nil

        local c = target.content

        local body = Geyser.Label:new({
            name = target._gid .. "_erc_body", x = "5%", y = 14, width = "90%", height = 160,
        }, c)
        -- QLabel clips instead of wrapping without an explicit word-wrap
        -- property; Mux.dialogCss.body doesn't set one (short-text dialogs
        -- elsewhere never needed it), so it's appended here.
        body:setStyleSheet(Mux.dialogCss.body .. "qproperty-wordWrap: true;")
        body:echo(exploreResetConfirmBodyText(pending.system_name, pending.missing))

        local cancelBtn = Geyser.Label:new({
            name = target._gid .. "_erc_cancel", x = "8%", y = 188, width = "38%", height = 34,
        }, c)
        cancelBtn:setStyleSheet(Mux.dialogCss.button)
        cancelBtn:echo("<center>Not now</center>")
        Mux.wireDialogButton(cancelBtn, Mux.dialogCss.button, Mux.dialogCss.buttonHover)

        local proceedBtn = Geyser.Label:new({
            name = target._gid .. "_erc_proceed", x = "54%", y = 188, width = "38%", height = 34,
        }, c)
        proceedBtn:setStyleSheet(Mux.dialogCss.buttonPrimary)
        proceedBtn:echo("<center>Reset &amp; Re-explore</center>")
        Mux.wireDialogButton(proceedBtn, Mux.dialogCss.buttonPrimary, Mux.dialogCss.buttonPrimaryHover)

        -- Close (X) behaves the same as "Not now"; a button that already
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
}

--- Shows a Reset & Re-explore / Not now confirm dialog after a system sweep
--- finishes with expected planets still missing.
function f2tShowExploreResetConfirm(system_name, missing, on_proceed, on_cancel)
    local dialog = Mux.createDialog({
        title  = "Exploration Incomplete",
        width  = 440,
        height = 270,
    })
    _pendingExploreResetConfirm = {
        system_name = system_name, missing = missing,
        on_proceed = on_proceed, on_cancel = on_cancel,
    }
    Mux._applyContent(dialog, "f2t_explore_reset_confirm")
    dialog:show()
    dialog:raise()
end

local function f2tRegisterExploreResetConfirm()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("f2t_explore_reset_confirm", exploreResetConfirmDef)
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterExploreResetConfirm)
