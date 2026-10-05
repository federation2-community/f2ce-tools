-- f2ce-tools map — right-click menu entries for the mapper widget
--
-- Mudlet shows every addMapEvent/addMapMenu entry on every right-click (room
-- or empty space) and hands the action the current selection, which is not
-- always the room under the cursor: right-clicking empty space keeps whatever
-- was last selected. Room actions therefore read the selection from the event
-- and say so when there is none. Mudlet sorts entries by unique name, menus
-- before plain items, which is what the numeric prefixes control.
--
-- sysMapWindowMousePressEvent fires on press, before the release that builds
-- the menu, so the walking/exploring entries are refreshed there to show only
-- what applies right now.

local MENU_EVENT = "f2tMapMenuAction"

local ROOM_MENU    = "f2tMap_1_room"
local EXPLORE_MENU = "f2tMap_2_explore"

-- Entries present on every menu.
local STATIC_ACTIONS = {
    { id = "f2tMap_10_walk",          parent = "",           label = "Walk here" },
    { id = "f2tMap_60_center",        parent = "",           label = "Center map on me" },
    { id = "f2tMap_70_legend",        parent = "",           label = "Map legend" },
    { id = "f2tMap_r1_avoid",         parent = ROOM_MENU,    label = "Avoid / allow in routes" },
    { id = "f2tMap_r2_saveDest",      parent = ROOM_MENU,    label = "Save as destination..." },
    { id = "f2tMap_r3_copyLocation",  parent = ROOM_MENU,    label = "Copy location" },
    { id = "f2tMap_r4_routeInfo",     parent = ROOM_MENU,    label = "Route info" },
    { id = "f2tMap_r5_details",       parent = ROOM_MENU,    label = "Details" },
    { id = "f2tMap_e1_planetBrief",   parent = EXPLORE_MENU, label = "This planet (brief)" },
    { id = "f2tMap_e2_planetFull",    parent = EXPLORE_MENU, label = "This planet (full)" },
    { id = "f2tMap_e3_systemBrief",   parent = EXPLORE_MENU, label = "This system (brief)" },
    { id = "f2tMap_e4_systemFull",    parent = EXPLORE_MENU, label = "This system (full)" },
}

local WALK_PAUSE_ID    = "f2tMap_20_walkPause"
local WALK_STOP_ID     = "f2tMap_21_walkStop"
local EXPLORE_PAUSE_ID = "f2tMap_30_explorePause"
local EXPLORE_STOP_ID  = "f2tMap_31_exploreStop"

local DYNAMIC_IDS = { WALK_PAUSE_ID, WALK_STOP_ID, EXPLORE_PAUSE_ID, EXPLORE_STOP_ID }

local function menuEcho(message)
    cecho(string.format("\n<cyan>[map]<reset> %s\n", message))
end

local function setDynamicEntry(id, label)
    if label then
        addMapEvent(id, MENU_EVENT, "", label)
    else
        removeMapEvent(id)
    end
end

function f2tMapMenuRefresh()
    local walking   = F2T_SPEEDWALK_ACTIVE
    local exploring = F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active
    setDynamicEntry(WALK_PAUSE_ID, walking and (F2T_SPEEDWALK_PAUSED and "Resume walking" or "Pause walking"))
    setDynamicEntry(WALK_STOP_ID, walking and "Stop walking")
    setDynamicEntry(EXPLORE_PAUSE_ID,
        exploring and (F2T_MAP_EXPLORE_STATE.paused and "Resume exploring" or "Pause exploring"))
    setDynamicEntry(EXPLORE_STOP_ID, exploring and "Stop exploring")
end

function f2tMapMenuRegister()
    addMapMenu(ROOM_MENU, "", "Room")
    addMapMenu(EXPLORE_MENU, "", "Explore")
    for _, action in ipairs(STATIC_ACTIONS) do
        addMapEvent(action.id, MENU_EVENT, action.parent, action.label)
    end
    f2tMapMenuRefresh()
end

function f2tMapMenuUnregister()
    for _, action in ipairs(STATIC_ACTIONS) do removeMapEvent(action.id) end
    for _, id in ipairs(DYNAMIC_IDS) do removeMapEvent(id) end
    removeMapMenu(ROOM_MENU)
    removeMapMenu(EXPLORE_MENU)
end

-- With a selection Mudlet passes its room IDs; without one it passes the
-- entry's own strings, none of which are numbers.
local function selectedRooms(...)
    local rooms = {}
    for _, value in ipairs({...}) do
        local roomId = tonumber(value)
        if roomId and roomExists(roomId) then rooms[#rooms + 1] = roomId end
    end
    return rooms
end

local viewedAreaId = nil

local function currentViewedArea()
    if viewedAreaId and getRoomAreaName(viewedAreaId) then return viewedAreaId end
    local roomId = F2T_MAP_CURRENT_ROOM_ID
    return roomId and roomExists(roomId) and getRoomArea(roomId) or nil
end

-- Planet areas are named after their planet; space areas hold orbit rooms
-- tagged with other planets' names, so only a non-space room counts.
local function planetOfArea(areaId)
    for _, roomId in ipairs(f2t_map_area_room_list(areaId)) do
        if getRoomUserData(roomId, "fed2_flag_space") ~= "true" then
            local planet = getRoomUserData(roomId, "fed2_planet") or ""
            if planet ~= "" then return planet end
        end
    end
    return nil
end

-- A selected room (planet room or orbit) wins over the area being viewed.
local function resolvePlanet(rooms)
    local planet = rooms[1] and getRoomUserData(rooms[1], "fed2_planet") or ""
    if planet ~= "" then return planet end
    local areaId = currentViewedArea()
    return areaId and planetOfArea(areaId)
end

local function resolveSystem(rooms)
    local system = rooms[1] and getRoomUserData(rooms[1], "fed2_system") or ""
    if system ~= "" then return system end
    local areaId = currentViewedArea()
    system = areaId and getAreaUserData(areaId, "fed2_system") or ""
    return system ~= "" and system or nil
end

local function explorePlanet(rooms, mode)
    local planet = resolvePlanet(rooms)
    if not planet then
        menuEcho("No planet here: view a planet's map or right-click its orbit")
        return
    end
    if f2tControlBlocks("Exploration") then return end
    f2t_map_explore_planet_start(mode, planet)
end

local function exploreSystem(rooms, mode)
    local system = resolveSystem(rooms)
    if not system then
        menuEcho("No known system for this part of the map")
        return
    end
    if f2tControlBlocks("Exploration") then return end
    f2t_map_explore_system_start(mode, system)
end

local function toggleAvoid(rooms)
    for _, roomId in ipairs(rooms) do
        if roomLocked(roomId) then
            f2t_map_manual_unlock_room(roomId)
        else
            f2t_map_manual_lock_room(roomId)
        end
    end
end

local function copyLocation(roomId)
    local hash = getRoomHashByID(roomId)
    if not hash or hash == "" then
        menuEcho("That room has no Fed2 location to copy")
        return
    end
    setClipboardText(hash)
    menuEcho(string.format("Copied <yellow>%s<reset> (use with <white>nav %s<reset>)", hash, hash))
end

local ROOM_ACTIONS = {
    f2tMap_10_walk = function(rooms)
        if f2tControlBlocks("Navigation") then return end
        f2t_map_navigate(tostring(rooms[1]), {interactive = true, compensate_incomplete_map = true})
    end,
    f2tMap_r1_avoid        = toggleAvoid,
    f2tMap_r2_saveDest     = function(rooms)
        printCmdLine(string.format("map dest room %d ", rooms[1]))
        menuEcho("Type a name for the destination and press Enter")
    end,
    f2tMap_r3_copyLocation = function(rooms) copyLocation(rooms[1]) end,
    f2tMap_r4_routeInfo    = function(rooms) f2t_map_show_route_info(nil, tostring(rooms[1])) end,
    f2tMap_r5_details      = function(rooms) f2t_map_manual_room_info(rooms[1]) end,
}

-- Actions that work without a selection; rooms may be empty.
local GENERAL_ACTIONS = {
    f2tMap_e1_planetBrief = function(rooms) explorePlanet(rooms, "brief") end,
    f2tMap_e2_planetFull  = function(rooms) explorePlanet(rooms, "full") end,
    f2tMap_e3_systemBrief = function(rooms) exploreSystem(rooms, "brief") end,
    f2tMap_e4_systemFull  = function(rooms) exploreSystem(rooms, "full") end,
    f2tMap_60_center = function()
        local roomId = F2T_MAP_CURRENT_ROOM_ID
        if not roomId or not roomExists(roomId) then
            menuEcho("Your current room is not on the map yet")
            return
        end
        centerview(roomId)
        f2t_map_info_snap_to_current()
    end,
    f2tMap_70_legend = function() f2tShowMapLegend() end,
    [WALK_PAUSE_ID] = function()
        if F2T_SPEEDWALK_PAUSED then f2t_map_speedwalk_resume() else f2t_map_speedwalk_pause() end
    end,
    [WALK_STOP_ID] = function() f2t_map_speedwalk_stop() end,
    [EXPLORE_PAUSE_ID] = function()
        if F2T_MAP_EXPLORE_STATE.paused then f2t_map_explore_resume() else f2t_map_explore_pause() end
    end,
    [EXPLORE_STOP_ID] = function() f2t_map_explore_stop() end,
}

function f2tMapMenuHandle(_, uniqueName, ...)
    local rooms = selectedRooms(...)
    local general = GENERAL_ACTIONS[uniqueName]
    if general then
        general(rooms)
        return
    end
    local roomAction = ROOM_ACTIONS[uniqueName]
    if not roomAction then return end
    if #rooms == 0 then
        menuEcho("Right-click a room first (or left-click it, then right-click anywhere)")
        return
    end
    roomAction(rooms)
end

-- GMCP is authoritative for where the player is, so Mudlet's built-in "Set
-- player location" only desyncs the drawn position from the routing origin.
function f2tMapMenuUndoManualLocation(_, roomId)
    local actualRoomId = F2T_MAP_CURRENT_ROOM_ID
    if not actualRoomId or tonumber(roomId) == actualRoomId or not roomExists(actualRoomId) then return end
    tempTimer(0, function() centerview(actualRoomId) end)
    menuEcho("Your location comes from the game, so the map stays on your actual room")
end

F2T_MAP_MENU_HANDLER_IDS = F2T_MAP_MENU_HANDLER_IDS or {}
for _, handlerId in ipairs(F2T_MAP_MENU_HANDLER_IDS) do killAnonymousEventHandler(handlerId) end
F2T_MAP_MENU_HANDLER_IDS = {
    registerAnonymousEventHandler(MENU_EVENT, f2tMapMenuHandle),
    registerAnonymousEventHandler("sysMapWindowMousePressEvent", f2tMapMenuRefresh),
    registerAnonymousEventHandler("sysManualLocationSetEvent", f2tMapMenuUndoManualLocation),
    registerAnonymousEventHandler("sysMapAreaChanged", function(_, areaId) viewedAreaId = tonumber(areaId) end),
    registerAnonymousEventHandler("sysUninstallPackage", function(_, packageName)
        if packageName == "f2ce-tools" then f2tMapMenuUnregister() end
    end),
}

f2tMapMenuRegister()
