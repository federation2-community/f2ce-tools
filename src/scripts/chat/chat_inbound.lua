-- fed2-tools chat — live inbound message continuation handling
--
-- Mirrors comhistory.lua's state-machine architecture (module-level state +
-- killPeek/armPeek), adapted for live com/say/tell traffic.  The permanent
-- trigger in src/triggers/chat/chat_inbound.lua (patterns in triggers.json)
-- calls into this module's f2tChatInboundBeginContinuation rather than
-- holding continuation logic inline, so state survives across trigger fires
-- — a bare trigger-script body's locals do NOT persist call-to-call, which is
-- what let the previous per-call-closure implementation splice/desync
-- messages when several arrived close together.

local MAX_CONTINUATION_LINES = 6   -- safety cap; see armPeek below

local state = {
    pending = nil,   -- { mtype, name, msg, lines } awaiting continuation, or nil
    peekId  = nil,   -- tempLineTrigger id armed to catch the next physical line
}

local killPeek, armPeek, matchLiveHeader, dispatchPending

killPeek = function()
    if state.peekId then killTrigger(state.peekId); state.peekId = nil end
end

-- True if `l` looks like the START of a new, unrelated message (one of the
-- three live chat header patterns from triggers.json) rather than a wrap
-- continuation of the pending one.  Does NOT consume/parse it — the
-- permanent chat_inbound trigger independently matches and dispatches it on
-- its own; this is purely a recognizer so the peek can bail out of the
-- continuation chain instead of swallowing an unrelated new message.
matchLiveHeader = function(l)
    if l:find('^Your comm unit signals a tight beam message from %w+, "') then return true end
    if l:find('^Your comm unit crackles with a message from %w+, "')     then return true end
    if l:find('^%w+ says, "') or l:find('^%w+ asks, "')                  then return true end
    return false
end

-- Dispatch whatever is pending as-is (normal completion / safe fallback).
dispatchPending = function()
    local p = state.pending
    state.pending = nil
    if not p then return end
    f2tChatAdd(p.mtype, p.name, p.msg)
end

armPeek = function()
    killPeek()
    state.peekId = tempLineTrigger(1, 1, function()
        local p = state.pending
        if not p then return end   -- nothing awaiting continuation; stray fire

        local l = getCurrentLine()

        if l:match('^%s*$') then
            -- Fed2 always delimits an output block with a blank line, even
            -- for a wrapped message. Hitting one here means the block ended
            -- without the closing quote we expected — dispatch what we have
            -- instead of folding in whatever unrelated block comes next.
            dispatchPending()
            return
        end

        if matchLiveHeader(l) then
            -- Not a continuation — a new message header. Dispatch what we
            -- have (no trailing continuation); do NOT consume `l`, the
            -- permanent trigger handles it on its own.
            dispatchPending()
            return
        end

        if l:match('"$') then
            p.msg = p.msg .. " " .. l:gsub('"$', '')
            state.pending = nil
            f2tChatAdd(p.mtype, p.name, p.msg)
            return
        end

        -- Still wrapping. Fold in and re-arm, up to the safety cap.
        p.lines = (p.lines or 1) + 1
        p.msg = p.msg .. " " .. l
        if p.lines > MAX_CONTINUATION_LINES then
            dispatchPending()
            return
        end
        armPeek()
    end)
end

-- Called by the chat_inbound trigger stub once it has parsed mtype/name/msg
-- from the matched line and found msg does NOT end in a closing quote.
function f2tChatInboundBeginContinuation(mtype, name, msg)
    -- A prior pending message (if any) never got its continuation —
    -- dispatch it as-is before starting the new one, rather than silently
    -- dropping it or splicing the two together.
    if state.pending then dispatchPending() end
    state.pending = { mtype = mtype, name = name, msg = msg, lines = 1 }
    armPeek()
end

registerAnonymousEventHandler("sysDisconnectionEvent", function()
    killPeek()
    state.pending = nil
end)

f2t_debug_log("[chat] chat_inbound module loaded")
