-- Mirrors comhistory.lua's design: a permanent catch-all trigger
-- (chat_inbound_line.lua, pattern ^.*$) feeds every line to
-- f2tChatInboundLine() while a message is pending completion, rather than a
-- tempLineTrigger armed to "peek" at just the next line, which could drop a
-- wrapped message when several lines flush in one batch.
--
-- comhistory.lua defers to this module (via F2T_CHAT_INBOUND_PENDING)
-- whenever a message is pending here, so its backfill never treats a live
-- message's lines as part of a comhistory entry.

local MAX_CONTINUATION_LINES = 6   -- safety cap; see f2tChatInboundLine below

local state = {
    pending = nil,   -- { mtype, name, msg, lines } awaiting continuation, or nil
}

local matchLiveHeader, dispatchPending

-- True if `l` looks like the START of a new, unrelated message (one of the
-- three live chat header patterns from triggers.json) rather than a wrap
-- continuation of the pending one. Does NOT consume/parse it — the permanent
-- chat_inbound trigger independently matches and dispatches it on its own;
-- this is purely a recognizer so continuation handling can bail out of the
-- chain instead of swallowing an unrelated new message. Also exposed as
-- F2T_CHAT_INBOUND_IS_HEADER so comhistory.lua's backfill capture can
-- recognize the same boundary.
matchLiveHeader = function(l)
    if l:find('^Your comm unit signals a tight beam message from %w+, "') then return true end
    if l:find('^Your comm unit crackles with a message from %w+, "')     then return true end
    if l:find('^%w+ says, "') or l:find('^%w+ asks, "')                  then return true end
    return false
end
F2T_CHAT_INBOUND_IS_HEADER = matchLiveHeader

-- Dispatch whatever is pending as-is (normal completion / safe fallback).
dispatchPending = function()
    local p = state.pending
    state.pending = nil
    if not p then return end
    f2tChatAdd(p.mtype, p.name, p.msg)
end

-- True while a message is mid-continuation. comhistory.lua checks this to
-- avoid stealing lines that belong to a live message.
function F2T_CHAT_INBOUND_PENDING()
    return state.pending ~= nil
end

-- Fires on every line (catch-all pattern in triggers.json); no-ops unless a
-- message is currently pending, so this costs one cheap check per line the
-- rest of the time.
function f2tChatInboundLine()
    local p = state.pending
    if not p then return end

    -- The once-per-login topology sync (map/events.lua) and galaxy navigator
    -- scrape (ui/content/galaxy.lua) both auto-request plain game output
    -- (`display cartels`/`display syndicates`, `di systems`) around the same
    -- login window a wrapped chat message can be mid-continuation. Their own
    -- triggers own those lines and gag them once they've matched, but this
    -- catch-all fires first/independently and has no gag of its own, so
    -- without this check it folds their output straight into the pending
    -- message (mirrors comhistory.lua's identical F2T_GALAXY.capture_active
    -- guard).
    if F2T_MAP_TOPOLOGY_CAPTURE and F2T_MAP_TOPOLOGY_CAPTURE.active then return end
    if F2T_GALAXY and F2T_GALAXY.capture_active then return end

    local l = line

    if l:match('^%s*$') then
        -- Fed2 always delimits an output block with a blank line, even for
        -- a wrapped message. Hitting one here means the block ended without
        -- the closing quote we expected — dispatch what we have instead of
        -- folding in whatever unrelated block comes next.
        dispatchPending()
        return
    end

    if matchLiveHeader(l) then
        -- Not a continuation — a new message header. Dispatch what we have
        -- (no trailing continuation); do NOT consume `l`, the permanent
        -- trigger handles it on its own.
        dispatchPending()
        return
    end

    if l:match('"$') then
        p.msg = p.msg .. " " .. l:gsub('"$', '')
        state.pending = nil
        f2tChatAdd(p.mtype, p.name, p.msg)
        return
    end

    -- Still wrapping. Fold in and keep waiting, up to the safety cap.
    p.lines = (p.lines or 1) + 1
    p.msg = p.msg .. " " .. l
    if p.lines > MAX_CONTINUATION_LINES then
        dispatchPending()
    end
end

-- Called by the chat_inbound trigger stub once it has parsed mtype/name/msg
-- from the matched line and found msg does NOT end in a closing quote.
function f2tChatInboundBeginContinuation(mtype, name, msg)
    -- A prior pending message (if any) never got its continuation —
    -- dispatch it as-is before starting the new one, rather than silently
    -- dropping it or splicing the two together.
    if state.pending then dispatchPending() end
    state.pending = { mtype = mtype, name = name, msg = msg, lines = 1 }
end

registerAnonymousEventHandler("sysDisconnectionEvent", function()
    state.pending = nil
end)

f2t_debug_log("[chat] chat_inbound module loaded")
