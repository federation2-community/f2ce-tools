-- fed2-tools — character identity tracking
--
-- Detects which character is logged in via GMCP, maintains F2T_CHAR_NAME,
-- and ensures a per-character persistent data directory exists.
--
-- In V2, settings are profile-global (owned by Mux.settings).  This module
-- does NOT redirect settings per-character.  Components that need character-
-- specific data (e.g. destinations) should store it under:
--   f2t_get_char_persistent_dir() / <component> / <file>
--
-- When the character changes, fires raiseEvent("f2tCharacterChanged", newName, oldName).

F2T_CHAR_NAME = nil

local loginDone = false

function f2t_get_char_persistent_dir()
    local base = getMudletHomeDir() .. "/fed2-tools-persistent"
    if F2T_CHAR_NAME and F2T_CHAR_NAME ~= "" then
        return base .. "/" .. F2T_CHAR_NAME:lower()
    end
    return base
end

registerAnonymousEventHandler("gmcp.char.vitals", function()
    local name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end
    if loginDone and F2T_CHAR_NAME == name then return end

    local prev    = F2T_CHAR_NAME
    F2T_CHAR_NAME = name
    loginDone     = true

    lfs.mkdir(getMudletHomeDir() .. "/fed2-tools-persistent")
    lfs.mkdir(f2t_get_char_persistent_dir())

    if prev ~= name then
        raiseEvent("f2tCharacterChanged", name, prev)
    end

    f2t_debug_log("[char] logged in as %s", name)
end)

-- Reset so the next login after a reconnect is detected fresh.
registerAnonymousEventHandler("sysConnectionEvent", function()
    loginDone = false
end)
