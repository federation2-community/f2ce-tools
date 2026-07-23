-- f2ce-tools — shared utilities
--
-- Consolidates: debug logging, game tool checks, string helpers, table helpers.

-- ── Version ───────────────────────────────────────────────────────────────────
-- Read from the installed package itself (mirrors Muxlet's own Mux._version),
-- not a build-time constant, so it always reflects what's actually installed.
local _f2tPkgInfo = getPackageInfo("f2ce-tools")
F2T_VERSION = (_f2tPkgInfo and _f2tPkgInfo.version) or "unknown"

-- ── Debug ─────────────────────────────────────────────────────────────────────

F2T_DEBUG = false

function f2t_debug_log(formatStr, ...)
    local debugOn = (Mux and Mux.debug) or F2T_DEBUG
    if not debugOn then return end
    local message
    if select("#", ...) > 0 then
        message = string.format(formatStr, ...)
    else
        message = formatStr
    end
    cecho(string.format("\n<cyan>[F2T DEBUG]<reset> %s\n", message))
end

function f2t_set_debug(enabled)
    F2T_DEBUG = enabled
    if Mux and Mux.settings and Mux.settings.set then
        Mux.settings.set("mux", "debug", enabled)
    end
end

-- ── Game tools ────────────────────────────────────────────────────────────────

COLS = getColumnCount and (getColumnCount() > 100 and 100 or getColumnCount()) or 100

function f2t_get_tool(toolName)
    if not toolName then return nil end
    local tools = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.tools
    if not tools then return nil end
    return tools[toolName]
end

function f2t_has_tool(toolName)
    return f2t_get_tool(toolName) ~= nil
end

function f2t_check_tool_requirement(toolName, featureName, displayName)
    if f2t_has_tool(toolName) then return true end
    local name = displayName or toolName
    cecho(string.format("\n<red>[f2ce-tools]<reset> %s requires the <cyan>%s<reset> tool\n",
        featureName, name))
    cecho("<dim_grey>See: https://federation2.com/guide/#sec-230.20<reset>\n")
    return false
end

-- ── String helpers ────────────────────────────────────────────────────────────

function f2t_strip_color_codes(str)
    if not str then return "" end
    return string.gsub(str, "%%%%[^%%]+%%%%", "")
end

function f2t_clean_room_name(name)
    if not name then return "" end
    local cleaned = f2t_strip_color_codes(name)
    cleaned = string.match(cleaned, "^%s*(.-)%s*$")
    return cleaned
end

local function _dlen(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

function f2t_padding(str, len, dir)
    str = tostring(str)
    local dlen = _dlen(str)
    if dlen > len then
        local n, i = 0, 1
        while i <= #str and n < len do
            local b = str:byte(i)
            if b < 0x80 or b >= 0xC0 then n = n + 1 end
            i = i + 1
        end
        return str:sub(1, i - 1)
    end
    local pad = len - dlen
    if dir == "left" then
        return str .. string.rep(" ", pad)
    elseif dir == "right" then
        return string.rep(" ", pad) .. str
    elseif dir == "center" then
        local left  = math.floor(pad / 2)
        local right = pad - left
        return string.rep(" ", left) .. str .. string.rep(" ", right)
    end
end

-- ── Table helpers ─────────────────────────────────────────────────────────────

function f2t_has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then return true end
    end
    return false
end

function f2t_table_get_sorted_keys(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

function f2t_table_count_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end
