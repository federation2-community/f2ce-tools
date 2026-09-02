-- Muxlet capture Transform for "SPYNET REPORT: <Rank> <Name> has entered/left <place>."
-- lines (see full.lua's default "SypnetReport" capture). Colors the line by
-- the rank shown in the report and turns the name into a player-card link,
-- the same rank-color + click-to-card convention as chat.lua/local_players.lua.
--
-- Registered as an ordinary Muxlet action (Settings → Muxlet → Actions still
-- lists it, read-only) so any capture's Transform dropdown can pick it by name;
-- no Muxlet-side change is needed to add more of these later.

local function spynetTransform(ctx)
    local mc   = ctx and ctx.console
    local text = ctx and ctx.value
    if not (mc and text) then return end

    local rank, name, verb, place = text:match("^SPYNET REPORT: (%a+) (%S+) has (%a+) (.-)%.?$")
    if not name then return end   -- unrecognized shape: let the caller fall back to a verbatim copy

    local rc        = (f2t_rank_color_decho and f2t_rank_color_decho(rank)) or "<200,200,200>"
    local verbColor = (verb == "entered") and "<green>" or "<red>"

    mc:decho(rc .. rank .. " <r>")
    mc:dechoLink(rc .. "<b>" .. name .. "</b><r>", function()
        if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(name) end
    end, "Open player card for " .. name, true)
    mc:cecho(string.format(" has %s%s<reset> %s.\n", verbColor, verb, place))

    return true
end

function f2tRegisterSpynetCaptureTransform()
    if not (Mux and Mux.registerAction) then
        if f2t_debug_log then f2t_debug_log("[spynet_capture] Muxlet action API unavailable; skipping") end
        return
    end
    Mux.registerAction("f2t.captureTransform.spynetReport", {
        name = "Spynet Report (color + card link)", group = "Capture Transform", icon = "🕵️", readOnly = true,
        desc = "For the Capture content: colors a SPYNET REPORT line by the mentioned player's rank and "
            .. "makes their name open the player card. Pick it from a capture's Transform dropdown.",
        run = spynetTransform,
    })
    if f2t_debug_log then f2t_debug_log("[spynet_capture] registered f2t.captureTransform.spynetReport action") end
end
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterSpynetCaptureTransform)
