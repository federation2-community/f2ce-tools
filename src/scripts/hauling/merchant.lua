-- Merchant rank tracking for exchange hauling
-- Provides helper functions for tracking merchant points progress

--- Get current merchant points from GMCP data
--- @return number|nil Merchant points or nil if not available
function f2t_merchant_get_points()
    if not gmcp or not gmcp.char or not gmcp.char.vitals or not gmcp.char.vitals.points then
        return nil
    end

    local points = gmcp.char.vitals.points
    if points.type == "merchant" then
        return tonumber(points.amt) or 0
    end

    return nil
end

--- Check if player has enough merchant points to advance (800+)
--- @return boolean True if has 800+ points
function f2t_merchant_has_enough_points()
    local points = f2t_merchant_get_points()
    if not points then
        return false
    end
    return points >= 800
end

f2t_debug_log("[hauling/merchant] Merchant tracking module loaded")