-- Map info overlay: renders Fed2 breadcrumb directly on the mapper canvas.
-- Uses room_id parameter so clicking any room shows that room's stored data.
-- Requires Mudlet 4.11+ (registerMapInfo API).

pcall(function() disableMapInfo("Short") end)
pcall(function() disableMapInfo("Full") end)

local ICON_FOR_FLAG = {
    link       = "⟡",
    orbit      = "○",
    shuttlepad = "🚀",
    exchange   = "$",
    shipyard   = "🔧",
    hospital   = "✚",
    bar        = "🍸",
    courier    = "ℭ",
}

local ICON_PRIORITY = {
    "link", "orbit", "shuttlepad", "exchange", "shipyard", "hospital", "bar", "courier"
}

-- After the player moves, snap the info display back to the current room.
-- Mudlet persists the user's clicked-room selection even after centerview();
-- this override holds for 1.5s so movement snaps cleanly without permanently
-- disabling click-to-inspect on other rooms.
local _snap_to_current = false

function f2t_map_info_snap_to_current()
    _snap_to_current = true
    tempTimer(1.5, function()
        _snap_to_current = false
    end)
end

registerMapInfo("fed2_info", function(room_id, sel_size, area_id, displayed_area_id)
    -- Snap to current room immediately after player movement
    if _snap_to_current and F2T_MAP_CURRENT_ROOM_ID and
       roomExists(F2T_MAP_CURRENT_ROOM_ID) then
        room_id = F2T_MAP_CURRENT_ROOM_ID
        area_id = getRoomArea(room_id)
    end

    if not room_id or not roomExists(room_id) then return "" end

    local system = getRoomUserData(room_id, "fed2_system") or ""
    local planet = getRoomUserData(room_id, "fed2_planet") or ""
    local name   = getRoomName(room_id) or ""
    local cartel = getRoomUserData(room_id, "fed2_cartel") or ""

    -- Pick highest-priority room type icon from stored flags
    local room_icon = ""
    for _, f in ipairs(ICON_PRIORITY) do
        if getRoomUserData(room_id, "fed2_flag_" .. f) == "true" then
            room_icon = ICON_FOR_FLAG[f] .. " "
            break
        end
    end

    -- Line 1: galaxy path breadcrumb
    local parts = {}
    if cartel ~= "" then table.insert(parts, "🌌 " .. cartel) end
    if system ~= "" then table.insert(parts, "⭐ " .. system) end
    if planet ~= "" then table.insert(parts, "🌍 " .. planet) end
    local line1 = table.concat(parts, " › ")

    -- Line 2: room type icon + room name
    local line2 = name ~= "" and (room_icon .. name) or ""

    local text = line1
    if line2 ~= "" then text = text .. "\n" .. line2 end

    return text, false, false, 190, 210, 230
end)

enableMapInfo("fed2_info")
