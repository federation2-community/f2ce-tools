-- Auto-fetches the game's `comhistory` output once per session after login
-- and merges missed com messages into F2T_CHAT.history, deduplicating against
-- existing records (ages are reported in whole-unit buckets, so the dedup
-- window spans one bucket on each side).
--
-- Two permanent triggers drive capture (src/triggers/chat/):
--   comhistory_capture -> f2tChatComhistoryBegin()   (header line)
--   comhistory_line    -> f2tChatComhistoryLine()    (every line, catch-all)
-- Permanent triggers avoid missing lines already batched in the server's
-- response when the request was sent from a timer; f2tChatComhistoryLine()
-- branches on whether each line looks like a new entry header or a
-- continuation. chat_inbound.lua uses the same catch-all pattern for live
-- message continuations.
--
-- A live com/say/tell message can arrive interleaved with this capture (e.g.
-- another player messages you right after login): f2tChatComhistoryLine()
-- defers while chat_inbound.lua has a message pending, and treats a live
-- message header as an entry boundary, so the two catch-alls never collide.
--
-- comhistory's header always names the server's current cycle, even when it
-- has no messages to report ("No COM messages have been sent yet in cycle
-- N."). Every entry in one response belongs to that same cycle (the game
-- itself scopes comhistory to the current cycle only), so each capture also
-- ensures a "cycle" divider record (chat/history.lua) exists in F2T_CHAT for
-- that cycle number, positioned at the server's ~10am Eastern reset —
-- computed DST-aware below since that's the actual start of the cycle,
-- whether or not any messages happened to survive comhistory's own window.

local MAX_CONTINUATION_LINES = 6   -- per-entry safety cap, same as chat_inbound.lua
-- Wider than other captures since a long comhistory dump can span socket reads.
local FINISH_TIMEOUT = 1.5

-- ── Cycle reset boundary (~10:00 America/New_York, DST-aware) ────────────────
-- US DST rules since 2007: starts 2nd Sunday of March, ends 1st Sunday of
-- November, both at 2am local. Only the calendar date (not the 2am cutover
-- itself) is used below, so the one or two days a year spanning an actual
-- transition can be off by an hour — acceptable for "roughly where the cycle
-- break should occur."
local DOW_TABLE = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }

local function dayOfWeek(y, m, d)   -- 0 = Sunday
    if m < 3 then y = y - 1 end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + DOW_TABLE[m] + d) % 7
end

local function nthSundayOfMonth(year, month, n)
    local firstSunday = ((7 - dayOfWeek(year, month, 1)) % 7) + 1
    return firstSunday + (n - 1) * 7
end

local function isEasternDST(year, month, day)
    if month < 3 or month > 11 then return false end
    if month > 3 and month < 11 then return true end
    if month == 3 then return day >= nthSundayOfMonth(year, 3, 2) end
    return day < nthSundayOfMonth(year, 11, 1)
end

-- Most recent 10:00 America/New_York at-or-before refTime, as a unix time.
local function cycleResetBoundary(refTime)
    local estGuess = os.date("!*t", refTime - 5 * 3600)
    local offset = isEasternDST(estGuess.year, estGuess.month, estGuess.day) and -4 * 3600 or -5 * 3600
    local eastern = os.date("!*t", refTime + offset)
    local dayStart = refTime + offset - (eastern.hour * 3600 + eastern.min * 60 + eastern.sec) + 10 * 3600
    if eastern.hour < 10 then dayStart = dayStart - 86400 end
    return dayStart - offset
end

local state = {
    -- sent: false = not requested yet; "pending" = requested, header not seen;
    --       true  = capture consumed this session (prevents re-capture)
    sent      = false,
    active    = false,   -- true while collecting message lines
    inEntry   = false,   -- true if the most recent line could still take a wrapped continuation
    current   = nil,     -- buffer entry the next continuation line (if any) folds into
    contLines = 0,       -- continuation lines folded into the current entry
    refTime   = nil,
    cycle     = nil,      -- comhistory's reported cycle number for this capture
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

-- ── Cycle divider records ─────────────────────────────────────────────────────
-- r.type == "cycle" is rendered by ui/content/chat.lua as a day-style divider;
-- r.cycle is the game's own cycle number, used only to dedup against re-runs.

local function hasCycleMarker(cycleNum)
    for _, r in ipairs(F2T_CHAT.history) do
        if r.type == "cycle" and r.cycle == cycleNum then return true end
    end
    return false
end

local function cycleMarkerRecord(cycleNum, t)
    return {
        t = t, type = "cycle", from = "", cycle = cycleNum,
        msg  = "Cycle " .. cycleNum,
        line = string.format("#1a3040── Cycle %d ──────────────────────────\n", cycleNum),
    }
end

-- Used when comhistory reports no messages for the cycle at all — nothing to
-- anchor the marker to, so it goes straight in at the computed reset time.
local function ensureCycleMarker(cycleNum, t)
    if not cycleNum or hasCycleMarker(cycleNum) then return end
    merge({ cycleMarkerRecord(cycleNum, t) })
    f2tChatSave()
    raiseEvent("f2tChatUpdated", "replay")
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
    state.timerId = tempTimer(FINISH_TIMEOUT, finish)
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

    -- All of these entries belong to state.cycle (comhistory itself only ever
    -- shows the current cycle) — anchor the marker just before the earliest
    -- one so it reads as "start of cycle" regardless of how the ~10am
    -- estimate lines up, rather than trusting the estimate outright.
    local addedMarker = false
    if state.cycle and not hasCycleMarker(state.cycle) then
        local minT = nil
        for _, r in ipairs(newRecords) do
            if not minT or r.t < minT then minT = r.t end
        end
        local markerT = math.min(minT or math.huge, cycleResetBoundary(state.refTime))
        if minT then markerT = markerT - 1 end
        table.insert(newRecords, cycleMarkerRecord(state.cycle, markerT))
        addedMarker = true
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
    local msgCount = #newRecords - (addedMarker and 1 or 0)
    f2t_debug_log("[comhistory] %d missed message%s added to chat%s",
        msgCount, msgCount == 1 and "" or "s", addedMarker and " (+cycle marker)" or "")
end

-- ── Trigger entry points ──────────────────────────────────────────────────────

-- Header line ("COM message history…" or "No COM messages have been sent
-- yet…").  Only consumes output we requested — a manual comhistory shows
-- normally.
function f2tChatComhistoryBegin()
    if state.sent ~= "pending" then return end
    if state.active then return end

    deleteLine()   -- hide the header/no-history line of our automated request

    local cycleNum = tonumber(line:match("cycle (%d+)"))

    if line:match("^No COM messages") then
        state.sent = true
        setBackfillTriggers(false)
        if cycleNum then ensureCycleMarker(cycleNum, cycleResetBoundary(os.time())) end
        f2t_debug_log("[comhistory] no history to fetch")
        return
    end

    state.sent    = true
    state.active  = true
    state.inEntry = false
    state.current = nil
    state.refTime = os.time()
    state.buffer  = {}
    state.cycle   = cycleNum

    state.timerId = tempTimer(FINISH_TIMEOUT, finish)
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

    -- A live message can also interleave; once chat_inbound.lua has one
    -- pending, every line belongs to it until dispatched — don't touch any
    -- of it here (including a bare continuation line that wouldn't otherwise
    -- be recognized as anything, and would otherwise get folded into
    -- whatever comhistory entry happens to be in progress).
    if F2T_CHAT_INBOUND_PENDING and F2T_CHAT_INBOUND_PENDING() then return end

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

    -- A live message header just started (chat_inbound.lua's own anchored
    -- trigger fires on it independently) — close this entry out rather than
    -- swallowing the header line as a bogus continuation. Don't consume it;
    -- it isn't ours.
    if F2T_CHAT_INBOUND_IS_HEADER and F2T_CHAT_INBOUND_IS_HEADER(line) then
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

-- True from the moment the backfill request is sent until its capture
-- finishes. f2t_galaxy_schedule_scrape (ui/content/galaxy.lua) defers its own
-- login-time "di systems" scrape while this is true — both modules can be
-- triggered around the same login window, and galaxy's catch-all capture
-- trigger would otherwise steal comhistory's own lines out from under it
-- (see F2T_GALAXY.capture_active check in f2tChatComhistoryLine above).
function F2T_CHAT_COMHISTORY_PENDING()
    return state.sent == "pending" or state.active
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
    state.inEntry, state.current, state.cycle = false, nil, nil
    state.buffer, state.timerId = {}, nil
    setBackfillTriggers(true)
end)

f2t_debug_log("[chat] comhistory module loaded")
