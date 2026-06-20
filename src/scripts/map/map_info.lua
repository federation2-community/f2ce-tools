-- fed2-tools map — mapper info overlay and toolbar style
--
-- Registers two map info lines (breadcrumb + room badge) via Mudlet's
-- registerMapInfo API (Mudlet 4.11+).
--
-- Also hides the mapper's built-in display-options toolbar via CSS, since
-- that panel is unnecessary when the map lives inside a Muxlet pane.

-- ── Toolbar CSS ───────────────────────────────────────────────────────────────
-- QWidget#widget_panel     = the collapsible controls panel in dlgMapper
-- QToolButton#togglePanel  = the expand/collapse arrow
-- Forcing dimensions to 0 collapses both out of sight.

local _MAPPER_TOOLBAR_CSS = [[
QWidget#widget_panel {
    max-height: 0px;
    min-height: 0px;
    padding:    0px;
    border:     none;
}
QToolButton#toolButton_togglePanel {
    max-height: 0px;
    min-height: 0px;
    max-width:  0px;
    min-width:  0px;
    padding:    0px;
    border:     none;
}
]]

-- Apply immediately at load time as a baseline so the panel is hidden even
-- before Muxlet is initialised.  init.lua's muxletReady handler re-registers
-- this via Mux.addProfileCss so the rule survives subsequent theme changes.
setProfileStyleSheet(_MAPPER_TOOLBAR_CSS)

function f2tRegisterMapperCss()
    if Mux and Mux.addProfileCss then
        Mux.addProfileCss(_MAPPER_TOOLBAR_CSS)
    end
end

-- ── Map info overlay ──────────────────────────────────────────────────────────

pcall(function() disableMapInfo("Short") end)
pcall(function() disableMapInfo("Full") end)
pcall(function() disableMapInfo("fed2_info") end)
pcall(function() disableMapInfo("fed2_bc") end)
pcall(function() disableMapInfo("fed2_rm") end)

local ICON_PRIORITY = {
    "link", "orbit", "shuttlepad", "exchange", "shipyard", "hospital", "bar", "courier"
}

-- After the player moves, snap the info display back to the current room.
-- Mudlet persists the clicked-room selection even after centerview(); this
-- override holds for 1.5s so movement snaps cleanly without permanently
-- disabling click-to-inspect on other rooms.
local _snapToCurrent = false
local _snapTimerId = nil

function f2t_map_info_snap_to_current()
    _snapToCurrent = true
    updateMap()
    if _snapTimerId then killTimer(_snapTimerId) end
    _snapTimerId = tempTimer(1.5, function()
        _snapToCurrent = false
        _snapTimerId = nil
    end)
end

local function resolveRoom(room_id)
    if _snapToCurrent and F2T_MAP_CURRENT_ROOM_ID and
       roomExists(F2T_MAP_CURRENT_ROOM_ID) then
        return F2T_MAP_CURRENT_ROOM_ID
    end
    return room_id
end

-- Line 1: galaxy path breadcrumb  (cartel › system › planet)
registerMapInfo("fed2_bc", function(room_id)
    room_id = resolveRoom(room_id)
    if not room_id or not roomExists(room_id) then return "" end

    local system = getRoomUserData(room_id, "fed2_system") or ""
    local planet = getRoomUserData(room_id, "fed2_planet") or ""
    local cartel = getRoomUserData(room_id, "fed2_cartel") or ""

    local parts = {}
    if cartel ~= "" then table.insert(parts, "🌌 " .. cartel) end
    if system ~= "" then table.insert(parts, "⭐ " .. system) end
    if planet ~= "" then table.insert(parts, "🌍 " .. planet) end

    if #parts == 0 then return "" end
    return table.concat(parts, " › "), false, false, 190, 210, 230
end)

-- Line 2: room name with colored badge when the room has a typed flag.
registerMapInfo("fed2_rm", function(room_id)
    room_id = resolveRoom(room_id)
    if not room_id or not roomExists(room_id) then return "" end

    local name = getRoomName(room_id) or ""
    if name == "" then return "" end

    local matched_flag = nil
    for _, f in ipairs(ICON_PRIORITY) do
        if getRoomUserData(room_id, "fed2_flag_" .. f) == "true" then
            matched_flag = f
            break
        end
    end

    if matched_flag and type(f2t_map_get_flag_symbol) == "function" then
        local r, g, b
        if type(f2t_map_get_flag_badge_rgb) == "function" then
            r, g, b = f2t_map_get_flag_badge_rgb(matched_flag)
        end
        if matched_flag == "orbit" then
            return name, false, false, r or 190, g or 210, b or 230
        end
        local sym = f2t_map_get_flag_symbol(matched_flag) or matched_flag
        if r then
            return sym .. "  " .. name, false, false, r, g, b
        end
        return sym .. "  " .. name, false, false, 190, 210, 230
    end

    return name, false, false, 190, 210, 230
end)

enableMapInfo("fed2_bc")
enableMapInfo("fed2_rm")
registerAnonymousEventHandler("muxletStarted", function() updateMap() end)
