-- Detects which character is logged in via GMCP, maintains F2T_CHAR_NAME,
-- and ensures a per-character persistent data directory exists.
--
-- Settings are profile-global (Mux.settings), not redirected per-character.
-- Components needing character-specific data (destinations, player DB) store
-- it under f2t_get_char_persistent_dir()/<component>/<file>.
--
-- Persistence root is "<package>_persistent", matching Muxlet's own
-- "Muxlet_persistent" convention, defined once here as the single source of truth.
--
-- Fires raiseEvent("f2tCharacterChanged", newName, oldName) when the character changes.

F2T_CHAR_NAME  = nil
F2T_LOGGED_IN  = false

local loginDone = false
local PERSISTENT_BASE = getMudletHomeDir() .. "/f2ce-tools_persistent"

function f2t_get_char_persistent_dir()
    if F2T_CHAR_NAME and F2T_CHAR_NAME ~= "" then
        return PERSISTENT_BASE .. "/" .. F2T_CHAR_NAME:lower()
    end
    return PERSISTENT_BASE
end

local function onVitals()
    local name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end
    if loginDone and F2T_CHAR_NAME == name then return end

    local prev    = F2T_CHAR_NAME
    F2T_CHAR_NAME = name
    loginDone     = true
    F2T_LOGGED_IN = true

    lfs.mkdir(PERSISTENT_BASE)
    lfs.mkdir(f2t_get_char_persistent_dir())

    if prev ~= name then
        raiseEvent("f2tCharacterChanged", name, prev)
    end

    f2t_debug_log("[char] logged in as %s", name)
end

registerAnonymousEventHandler("gmcp.char.vitals", onVitals)

-- A script reload (e.g. dev-mode rebuild) re-executes this file, resetting
-- F2T_CHAR_NAME/loginDone to fresh-load defaults, but Mudlet doesn't replay
-- the GMCP event that originally set them. gmcp.char itself survives a
-- reload, so just re-check it immediately instead of waiting for reconnect.
onVitals()

-- Reset so the next login after a reconnect is detected fresh.
registerAnonymousEventHandler("sysConnectionEvent", function()
    loginDone     = false
    F2T_LOGGED_IN = false
end)