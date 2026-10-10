-- f2ce-tools — external control lock
--
-- Lets another Mudlet package (a bot) claim the character so the player's own
-- f2ce-tools commands don't start a competing automation underneath it, and
-- lets the player take control back with `f2t control release`.
--
-- The lock is advisory and only guards player-facing entry points (haul start,
-- map explore, nav). A package holding it calls f2ce-tools functions directly
-- (f2tNav.go, f2t_bulk_buy_start, f2t_hauling_start, ...) as usual.
--
-- Events:
--   f2tControlChanged(owner)            owner is nil once released
--   f2tControlRevoked(owner, reason)    the player took control back; stop work
--   f2tNavFinished(owner, status, roomId, reason)  raised from nav_api.lua

F2T_CONTROL = F2T_CONTROL or { owner = nil, reason = nil, since = nil }

-- Name of the first native automation currently running, or nil when idle
function f2tControlNativeActivity()
    if F2T_HAULING_STATE and F2T_HAULING_STATE.active then return "hauling" end
    if F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then return "exploration" end
    if f2tNav and f2tNav.busy() then return "navigation" end
    if F2T_BULK_STATE and F2T_BULK_STATE.active then return "bulk trading" end
    if f2t_po and f2t_po.phase ~= "idle" then return "planet economy capture" end
    if f2tPriceServiceBusy and f2tPriceServiceBusy() then return "price check" end
    if F2T_STOCKPILE and F2T_STOCKPILE.applying then return "stockpile update" end
    return nil
end

--- Claim control for a package
--- @param owner string Stable package name shown to the player
--- @param reason string|nil Short description of what it is doing
--- @return boolean ok, string|nil why it was refused
function f2tControlAcquire(owner, reason)
    if type(owner) ~= "string" or owner == "" then
        return false, "owner name required"
    end
    if F2T_CONTROL.owner == owner then
        F2T_CONTROL.reason = reason or F2T_CONTROL.reason
        return true
    end
    if F2T_CONTROL.owner then
        return false, "control held by " .. F2T_CONTROL.owner
    end
    local activity = f2tControlNativeActivity()
    if activity then
        return false, activity .. " is running"
    end
    F2T_CONTROL.owner, F2T_CONTROL.reason, F2T_CONTROL.since = owner, reason, os.time()
    f2t_debug_log("[control] acquired by %s (%s)", owner, tostring(reason))
    raiseEvent("f2tControlChanged", owner)
    return true
end

--- Release control; only the current owner can release
--- @return boolean true if owner held control and it is now free
function f2tControlRelease(owner)
    if not F2T_CONTROL.owner or F2T_CONTROL.owner ~= owner then return false end
    F2T_CONTROL.owner, F2T_CONTROL.reason, F2T_CONTROL.since = nil, nil, nil
    f2t_debug_log("[control] released by %s", owner)
    raiseEvent("f2tControlChanged", nil)
    return true
end

--- Player override: free the lock and stop any walk in progress
function f2tControlRevoke(reason)
    local owner = F2T_CONTROL.owner
    if not owner then return false end
    F2T_CONTROL.owner, F2T_CONTROL.reason, F2T_CONTROL.since = nil, nil, nil
    f2t_debug_log("[control] revoked from %s (%s)", owner, tostring(reason))
    raiseEvent("f2tControlRevoked", owner, reason or "player")
    raiseEvent("f2tControlChanged", nil)
    if f2tNav then f2tNav.stopAll() end
    return true
end

--- @return string|nil owner, string|nil reason, number|nil since (os.time)
function f2tControlOwner()
    return F2T_CONTROL.owner, F2T_CONTROL.reason, F2T_CONTROL.since
end

--- Guard for player-facing entry points; prints why and returns true when blocked
--- @param feature string What the player tried to start, for the message
function f2tControlBlocks(feature)
    local owner = F2T_CONTROL.owner
    if not owner then return false end
    cecho(string.format(
        "\n<yellow>[f2t]<reset> %s unavailable: <cyan>%s<reset> has control%s. "
            .. "Type <green>f2t control release<reset> to take it back.\n",
        feature, owner, F2T_CONTROL.reason and (" (" .. F2T_CONTROL.reason .. ")") or ""))
    return true
end

function f2tControlShowStatus()
    local owner, reason, since = f2tControlOwner()
    if owner then
        local minutes = math.floor((os.time() - since) / 60)
        cecho(string.format("\n<green>[f2t]<reset> Control: <cyan>%s<reset>%s, for %d min\n",
            owner, reason and (" - " .. reason) or "", minutes))
    else
        cecho("\n<green>[f2t]<reset> Control: <white>player<reset> (no package holds it)\n")
    end
    local activity = f2tControlNativeActivity()
    cecho(string.format("<dim_grey>  Native activity: %s<reset>\n", activity or "idle"))
end
