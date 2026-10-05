-- Delete +++ exchange ticker announcements from the main console when the
-- exchange/console_spam setting is off.  The Exchange content still gets the
-- data via gmcp.exchange.commodity.

-- The reply to a check the price service sent for a panel: it shows there.
if f2tPriceLocalReplyActive and f2tPriceLocalReplyActive() then
    deleteLine()
    tempLineTrigger(1, 1, function()
        if line == "" or line:match("^%s*$") then deleteLine() end
    end)
    return
end

-- The reply to the player's own price check uses the same +++ lines; keep
-- them, and end the request window at the first line after the block.
if f2tExchangePriceRequestActive and f2tExchangePriceRequestActive() then
    tempLineTrigger(1, 1, function()
        if not line:match("^%+%+%+ ") then f2tExchangePriceRequestEnd() end
    end)
    return
end

if f2t_settings_get("exchange", "console_spam") then return end

deleteLine()
-- The announcement block is followed by a blank line; eat that too.
tempLineTrigger(1, 1, function()
    if line == "" or line:match("^%s*$") then deleteLine() end
end)
