-- Map info overlay: replaces the built-in "Short" canvas text with a
-- Fed2-aware breadcrumb drawn directly on the mapper tiles.
-- Requires Mudlet 4.11+ (registerMapInfo API).

-- Disable built-in overlays so our handler is the only one shown.
pcall(function() disableMapInfo("Short") end)
pcall(function() disableMapInfo("Full") end)

local FLAG_LABELS = {
    link       = "⟡ Link",
    orbit      = "○ Orbit",
    shuttlepad = "🚀 Pad",
    exchange   = "$ Exchange",
    shipyard   = "🔧 Shipyard",
    hospital   = "✚ Hospital",
    bar        = "🍸 Bar",
    courier    = "AC",
    space      = "Space",
}

local FLAG_ORDER = {
    "link", "orbit", "shuttlepad", "exchange", "shipyard", "hospital", "bar", "courier", "space"
}

registerMapInfo("fed2_info", function(room_id, sel_size, area_id, displayed_area_id)
    if not room_id or not roomExists(room_id) then return "" end

    local system = getRoomUserData(room_id, "fed2_system") or ""
    local planet = getRoomUserData(room_id, "fed2_planet") or ""
    local name   = getRoomName(room_id) or ""

    local active_flags = {}
    for _, f in ipairs(FLAG_ORDER) do
        if getRoomUserData(room_id, "fed2_flag_" .. f) == "true" then
            table.insert(active_flags, FLAG_LABELS[f])
        end
    end

    local parts = {}
    if system ~= "" then table.insert(parts, system) end
    if planet ~= "" and planet ~= system then table.insert(parts, planet) end
    if name   ~= "" then table.insert(parts, name) end

    local line1 = table.concat(parts, " › ")
    local line2 = table.concat(active_flags, "  ")

    local text = line1
    if line2 ~= "" then text = text .. "\n" .. line2 end

    return text, false, false, 190, 210, 230
end)

enableMapInfo("fed2_info")
