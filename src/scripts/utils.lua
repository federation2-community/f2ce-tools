-- f2ce-tools — shared utilities
--
-- Consolidates: debug logging, game tool checks, string helpers, table helpers.

-- ── Version ───────────────────────────────────────────────────────────────────
-- Read from the installed package itself (mirrors Muxlet's own Mux._version),
-- not a build-time constant, so it always reflects what's actually installed.
local _f2tPkgInfo = getPackageInfo("f2ce-tools")
F2T_VERSION = (_f2tPkgInfo and _f2tPkgInfo.version) or "unknown"

-- ── Content registrar list ────────────────────────────────────────────────────
-- Owned here, and cleared outright rather than kept with `or {}`, because this
-- script loads first (scripts.json, and it must stay first for that reason) and
-- every content module appends to the list as it loads. Uninstalling a package
-- does not clear Lua globals, so on an in-place upgrade the previous version's
-- list is still here and its closures still callable: keeping it would run both
-- generations of every registrar, the outgoing one against globals the incoming
-- version has since changed.
F2T_CONTENT_REGISTRARS = {}

-- ── Web client detection ──────────────────────────────────────────────────────

-- True only in the dedicated Mudlet Web client (the "mudix" browser runtime).
-- It registers a private global namespace (__mudix_* / __mws_*) that desktop
-- Mudlet never has, so their presence identifies the web client. We check
-- several so a future upstream rename of any one degrades gracefully (worst
-- case: web falls back to the desktop prompts, no crash). Referencing an
-- undefined global is nil in Lua, so this is safe on desktop.
--
-- NOTE: do NOT use getMudletInfo() here — in Mudlet Web it only ECHOES a
-- diagnostic block and returns nil (it does not return a string).
function f2t_is_web()
    local markers = { "__mudix_is_connected", "__mudix_pump", "__mudix_now", "__mws_w" }
    for _, name in ipairs(markers) do
        if _G[name] ~= nil then return true end
    end
    return false
end

-- GUI font scaling: Mudlet Web renders panel text larger than desktop, so shrink
-- it ~15% on web only. Desktop is unchanged. Helpers return a CSS size token.
F2T_UI_FONT_SCALE = f2t_is_web() and 0.85 or 1.0
function f2t_ui_pt(pt) return string.format("%gpt", pt * F2T_UI_FONT_SCALE) end

-- The same scale as a bare number, for Geyser.Label:setFontSize().
--
-- Use this — NOT a font-size in the widget's stylesheet — to size a Geyser
-- label. Geyser.Label:echo() re-wraps the message in `<div style="font-size:
-- <self.fontSize>pt">` on every single update, and that inline style beats
-- anything the stylesheet says. A font-size in setStyleSheet() on a label you
-- ever :echo() to is silently dead code.
function f2t_ui_fs(pt) return math.max(6, math.floor(pt * F2T_UI_FONT_SCALE + 0.5)) end

-- ── Per-surface text size ─────────────────────────────────────────────────────
-- Muxlet's Text Size % for a pane or tab (1.0 = 100%). Content that opts in
-- sizes fonts, and the row/strip heights that hold text, through these.

function f2tTextScale(target)
    if target and Mux and Mux.textScale then return Mux.textScale(target) end
    return 1
end

-- Pixel length (row height, strip height, px font size) at the surface's size.
function f2tScaled(target, px) return math.floor(px * f2tTextScale(target) + 0.5) end

local function roundPoints(pt) return math.max(5, math.floor(pt * 10 + 0.5) / 10) end

-- Label fontSize in points at the surface's size. f2tUiPt also applies the web
-- shrink, matching f2t_ui_pt; f2tTextPt doesn't, matching Geyser's 8pt default
-- and px sizes (px * 0.75) that were never web-scaled.
function f2tUiPt(target, pt)   return roundPoints(pt * F2T_UI_FONT_SCALE * f2tTextScale(target)) end
function f2tTextPt(target, pt) return roundPoints(pt * f2tTextScale(target)) end

-- Click-outside dismissal for dropdowns: a transparent full-window label shown
-- under the menu, so a click anywhere off the menu lands on it and runs
-- onDismiss. The menu must be top-level (parented to Geyser) and raiseAll()ed
-- after this call, or the backdrop covers it; a bare Container:raise() moves
-- no widgets.
local dropdownBackdrop
function f2tShowDropdownBackdrop(onDismiss)
    local screenW, screenH = getMainWindowSize()
    if not dropdownBackdrop then
        dropdownBackdrop = Geyser.Label:new({
            name = "f2t_dropdown_backdrop", x = 0, y = 0, width = screenW, height = screenH,
        }, Geyser)
        dropdownBackdrop:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
    end
    dropdownBackdrop:setClickCallback(function()
        f2tHideDropdownBackdrop()
        if onDismiss then onDismiss() end
    end)
    dropdownBackdrop:move(0, 0)
    dropdownBackdrop:resize(screenW, screenH)
    dropdownBackdrop:show()
    dropdownBackdrop:raise()
end

function f2tHideDropdownBackdrop()
    if dropdownBackdrop then dropdownBackdrop:hide() end
end

-- onTextScale handler for content that lays itself out once in apply(): re-applies
-- it at the new size and carries serialize() state across. afterRebuild(target)
-- restores what serialize() doesn't keep. Coalesced, so stepping the size several
-- times rebuilds once.
local pendingTextScaleRebuilds = {}
function f2tRebuildForTextScale(target, afterRebuild)
    if pendingTextScaleRebuilds[target] then return end
    local contentId = target._activeContent
    pendingTextScaleRebuilds[target] = true
    tempTimer(0.15, function()
        pendingTextScaleRebuilds[target] = nil
        if not contentId or target._activeContent ~= contentId then return end
        local def = Mux._content and Mux._content[contentId]
        if not def then return end
        local state
        if def.serialize then
            local ok, result = pcall(def.serialize, target)
            if ok and type(result) == "table" then state = result end
        end
        Mux._applyContent(target, contentId, true)
        if state and def.restore then pcall(def.restore, target, state) end
        if afterRebuild then pcall(afterRebuild, target) end
    end)
end

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

-- ── Table helpers ─────────────────────────────────────────────────────────────

function f2t_has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then return true end
    end
    return false
end

function f2t_table_count_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end
