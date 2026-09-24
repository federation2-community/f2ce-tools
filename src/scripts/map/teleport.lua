-- Interplanetary teleport addresses are System.Planet, never room numbers.
-- The mapped exchange hash is used only to validate the final seller identity.
-- It has no movement side effects: unmapped/ambiguous destinations use normal nav.
function f2t_map_teleport_exchange_target(location)
    if type(location) ~= "table" or type(location.planet) ~= "string"
        or type(location.system) ~= "string" then return nil end
    local id = f2t_map_resolve_location(location.planet .. " exchange")
    if not id or not f2t_map_room_has_flag(id, "exchange") then return nil end
    if type(getRoomHashByID) ~= "function" then return nil end
    local hash = getRoomHashByID(id)
    if type(hash) ~= "string" or #hash > 180 or hash:find("[%c;|<>]") then return nil end
    local system, planet, num = hash:match("^([^%.]+)%.([^%.]+)%.(%d+)$")
    if not system or system:lower() ~= location.system:lower()
        or planet:lower() ~= location.planet:lower() then return nil end
    if type(getRoomUserData) ~= "function"
        or tostring(getRoomUserData(id, "fed2_num")) ~= num
        or getRoomUserData(id, "fed2_system") ~= system
        or getRoomUserData(id, "fed2_area") ~= planet then return nil end
    if type(roomLocked) ~= "function" or roomLocked(id) then return nil end
    local number = tonumber(num)
    if not number or number < 0 or number > 2147483647 then return nil end
    return {id=id, hash=hash, address=system .. "." .. planet,
        system=system, planet=planet, num=number}
end
