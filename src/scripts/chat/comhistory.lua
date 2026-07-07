-- fed2-tools chat — comhistory backfill
--
-- Auto-fetches the game's `comhistory` output once per session shortly after
-- login and merges any missed com messages into F2T_CHAT.history, deduplicating
-- against records already present (the game reports ages in whole-unit buckets,
-- so the dedup window spans one bucket on each side).
--
-- Two permanent triggers drive capture (src/triggers/chat/):
--   comhistory_capture → f2tChatComhistoryBegin()   (header line)
--   comhistory_line    → f2tChatComhistoryLine()    (every line, catch-all)
--
-- Permanent triggers (rather than tempLineTrigger) avoid missing lines already
-- batched in the server's response when the request was sent from a timer —
-- this applies just as much to wrapped continuation lines mid-capture as it
-- does to the first entry, so comhistory_line's pattern is a catch-all and
-- f2tChatComhistoryLine() itself branches on whether the line looks like a
-- new entry header or a continuation of the one in progress. (An earlier
-- version used a tempLineTrigger armed after each line to peek at the next
-- one; armed mid-batch it registered one line too late, causing it to skip
-- every other line for the rest of the capture.)
--
-- Ported from archive's ui_chat_comhistory.lua.

local MAX_CONTINUATION_LINES = 6   -- per-entry safety cap, same as chat_inbound.lua

local state = {
    -- sent: false = not requested yet; "pending" = requested, header not seen;
    --       true  = capture consumed this session (prevents re-capture)
    sent      = false,
    active    = false,   -- true while collecting message lines
    inEntry   = false,   -- true if the most recent line could still take a wrapped continuation
    current   = nil,     -- buffer entry the next continuation line (if any) folds into
    contLines = 0,       -- continuation lines folded into the current entry
    refTime   = nil,
    buffer    = {},      -- list of {name, ago, text}
    timerId   = nil,
}

-- Returns (estimatedUnixTime, toleranceSeconds).  "N hours ago" means the
-- message is in the range [N, N+1) hours old, so tolerance = one bucket.
local function parseTime(agoStr, refTime)
    if agoStr == "just now" then return refTime, 60 end
    local n, unit = agoStr:match("^(%d+) (%a+) ago$")
    if not n then return refTime, 60 end
    n = tonumber(n)
    if unit:match("^minute") then return refTime - n * 60,   60   end
    if unit:match("^hour")   then return refTime - n * 3600, 3600 end
    return refTime, 60
end

local function isDuplicate(from, msg, t, tolerance)
    for _, r in ipairs(F2T_CHAT.history) do
        if r.type == "com" and r.from == from and r.msg == msg
           and math.abs(r.t - t) <= tolerance then
            return true
        end
    end
    return false
end

-- Merge new records into history preserving chronological order. Same-bucket
-- entries sort by original emission index (table.sort isn't stable) then get
-- a +1s nudge so comhistory's own ordering survives.
local function merge(newRecords)
    for i, r in ipairs(newRecords) do r._idx = i end
    table.sort(newRecords, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a._idx < b._idx
    end)
    for i = 2, #newRecords do
        if newRecords[i].t <= newRecords[i-1].t then
            newRecords[i].t = newRecords[i-1].t + 1
        end
    end
    for _, r in ipairs(newRecords) do r._idx = nil end
    local merged, hi, ni = {}, 1, 1
    local hist = F2T_CHAT.history
    while hi <= #hist or ni <= #newRecords do
        local ht = hist[hi]       and hist[hi].t       or math.huge
        local nt = newRecords[ni] and newRecords[ni].t or math.huge
        if ht <= nt then
            table.insert(merged, hist[hi]);       hi = hi + 1
        else
            table.insert(merged, newRecords[ni]); ni = ni + 1
        end
    end
    F2T_CHAT.history = merged
end

-- The backfill triggers include a catch-all line pattern (comhistory_line,
-- ^.*$) that otherwise runs on every line of game output forever. They are
-- only needed between the login request and capture completion, so they are
-- disabled once the backfill has run and re-armed on disconnect — before the
-- next connection can need them.
local function setBackfillTriggers(on)
    local fn = on and enableTrigger or disableTrigger
    pcall(fn, "comhistory_capture")
    pcall(fn, "comhistory_line")
end

local finish, resetFinishTimer, matchHeader

resetFinishTimer = function()
    if state.timerId then killTimer(state.timerId) end
    state.timerId = tempTimer(0.5, finish)
end

-- Matches a comhistory entry header line ("Name, X ago: text" / "Name, just
-- now: text"). Returns name, ago, text, or nil if the line isn't one.
matchHeader = function(l)
    local name, ago, text = l:match("^(%a+), (%d+ %a+ ago): (.+)$")
    if name then return name, ago, text end
    name, text = l:match("^(%a+), just now: (.+)$")
    if name then return name, "just now", text end
    return nil
end

finish = function()
    state.active  = false
    state.inEntry = false
    state.current = nil
    state.timerId = nil
    setBackfillTriggers(false)   -- backfill done for this session

    local buffer = state.buffer
    state.buffer = {}
    f2t_debug_log("[comhistory] processing %d raw entries", #buffer)

    local newRecords = {}
    for _, entry in ipairs(buffer) do
        local t, tolerance = parseTime(entry.ago, state.refTime)
        if not isDuplicate(entry.name, entry.text, t, tolerance) then
            table.insert(newRecords, { t = t, type = "com", from = entry.name, msg = entry.text })
        end
    end

    if #newRecords == 0 then
        f2t_debug_log("[comhistory] no new messages")
        return
    end

    merge(newRecords)
    f2tChatSave()
    raiseEvent("f2tChatUpdated", "replay")

    -- The chat panel isn't necessarily open/enabled, so this stays out of the
    -- main console — the merged records show up in the chat log whenever the
    -- user next looks at it.
    f2t_debug_log("[comhistory] %d missed message%s added to chat",
        #newRecords, #newRecords == 1 and "" or "s")
end

-- ── Trigger entry points ──────────────────────────────────────────────────────

-- Header line ("COM message history…" or "No COM messages have been sent
-- yet…").  Only consumes output we requested — a manual comhistory shows
-- normally.
function f2tChatComhistoryBegin()
    if state.sent ~= "pending" then return end
    if state.active then return end

    deleteLine()   -- hide the header/no-history line of our automated request

    if line:match("^No COM messages") then
        state.sent = true
        setBackfillTriggers(false)
        f2t_debug_log("[comhistory] no history to fetch")
        return
    end

    state.sent    = true
    state.active  = true
    state.inEntry = false
    state.current = nil
    state.refTime = os.time()
    state.buffer  = {}

    state.timerId = tempTimer(0.5, finish)
    f2t_debug_log("[comhistory] capture started")
end

-- Fires on every line (catch-all pattern in triggers.json) while a backfill
-- capture is active. Fed2 wraps long comhistory lines the same way it wraps
-- quoted chat messages (chat_inbound.lua) — a continuation line repeats
-- neither the sender name nor the "X ago:" prefix, so it never matches
-- matchHeader(). Any such line is treated as a continuation of whatever entry
-- is in progress (state.current, or none if the entry belonged to our own
-- message — already in the live log) as long as state.inEntry is still true.
function f2tChatComhistoryLine()
    if not state.active then return end

    -- The galaxy navigator's background "di systems" scrape can interleave
    -- with this capture at login; its lines belong to that capture, not here.
    if F2T_GALAXY and F2T_GALAXY.capture_active then return end

    local name, ago, text = matchHeader(line)   -- `line` is Mudlet's global for the trigger's current line

    if name then
        deleteLine()

        -- Timer-based completion: any recognized line resets the window, and
        -- the timer ALWAYS finishes the capture when it expires (even on
        -- empty data).
        resetFinishTimer()

        state.inEntry   = true
        state.contLines = 0
        if F2T_CHAR_NAME and name:lower() == F2T_CHAR_NAME:lower() then
            state.current = nil
        else
            state.current = { name = name, ago = ago, text = text }
            table.insert(state.buffer, state.current)
        end
        return
    end

    if not state.inEntry then return end

    -- Fed2 delimits an output block with a blank line, even mid-wrap (same
    -- rule as chat_inbound.lua) — the entry is complete; anything after the
    -- blank is unrelated output and must not be folded in.
    if line:match("^%s*$") then
        deleteLine()
        resetFinishTimer()
        state.inEntry = false
        state.current = nil
        return
    end

    deleteLine()
    resetFinishTimer()
    if state.current then
        state.current.text = state.current.text .. " " .. line
    end
    state.contLines = state.contLines + 1
    if state.contLines >= MAX_CONTINUATION_LINES then
        state.inEntry = false
        state.current = nil
    end
end

-- Re-arm the once-per-session gate and fetch again (used by `f2t chat wipe`).
-- Offline it just resets the gate so the next login auto-fetches.
function f2tChatComhistoryRefetch()
    if state.timerId then killTimer(state.timerId) end
    state.active, state.inEntry, state.current = false, false, nil
    state.buffer, state.timerId = {}, nil
    local name = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then
        state.sent = false
        cecho("\n<yellow>[chat]<reset> Not logged in — com history will be fetched at next login.\n")
        return
    end
    state.sent = "pending"
    setBackfillTriggers(true)
    send("comhistory", false)
    cecho("\n<yellow>[chat]<reset> Re-fetching com history...\n")
end

-- ── Session wiring ────────────────────────────────────────────────────────────

local function requestOnLogin()
    if state.sent then return end
    if f2t_settings_get("chat", "fetch_history") == false then
        setBackfillTriggers(false)   -- no backfill this session; stop the per-line tax
        return
    end
    state.sent = "pending"
    setBackfillTriggers(true)
    tempTimer(2, function()
        send("comhistory", false)
        f2t_debug_log("[comhistory] auto-requested")
    end)
end

-- gmcp.char.vitals fires repeatedly; the sent-flag makes this once per session.
-- The 2s delay keeps the request clear of the login sequence output.
local function onVitals()
    local name = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return end
    requestOnLogin()
end

registerAnonymousEventHandler("gmcp.char.vitals", onVitals)

-- A script reload (e.g. dev-mode rebuild while still connected) re-executes
-- this file, giving `state` a fresh sent=false with no gmcp.char.vitals event
-- coming to re-trigger onVitals (Mudlet doesn't replay it; see char.lua for
-- the same gap). Check for already-present vitals data immediately so the
-- backfill still runs once after a reload instead of silently never firing.
onVitals()

-- Reset on disconnect so the next login fetches again. Re-arming the triggers
-- here guarantees they are live before the next connection needs them.
registerAnonymousEventHandler("sysDisconnectionEvent", function()
    if state.timerId then killTimer(state.timerId) end
    state.sent, state.active, state.refTime = false, false, nil
    state.inEntry, state.current = false, nil
    state.buffer, state.timerId = {}, nil
    setBackfillTriggers(true)
end)

f2t_debug_log("[chat] comhistory module loaded")
