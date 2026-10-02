-- Delete +++ exchange ticker announcements from the main console when the
-- exchange/console_spam setting is off.  The Exchange content still gets the
-- data via gmcp.exchange.commodity.

-- "+++ The display shows the prices for" only answers the player's own remote
-- price check (c price <commodity> <planet>); always keep it and the up to 3
-- +++ lines of that result that follow it.
if line:match("^%+%+%+ The display shows the prices for ") then
    F2T_EXCHANGE_REQUESTED_LINES_LEFT = 3
    tempLineTrigger(1, 3, function()
        if not line:match("^%+%+%+ ") then F2T_EXCHANGE_REQUESTED_LINES_LEFT = nil end
    end)
    return
end
if (F2T_EXCHANGE_REQUESTED_LINES_LEFT or 0) > 0 then
    F2T_EXCHANGE_REQUESTED_LINES_LEFT = F2T_EXCHANGE_REQUESTED_LINES_LEFT - 1
    return
end

if f2t_settings_get("exchange", "console_spam") then return end

deleteLine()
-- The announcement block is followed by a blank line; eat that too.
tempLineTrigger(1, 1, function()
    if line == "" or line:match("^%s*$") then deleteLine() end
end)
