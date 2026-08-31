-- Shared silence-window mechanics for the "send a command, swallow its output
-- until the game goes quiet" captures: display cartels/syndicates, display
-- cartel, di system, di systems.
--
-- Each capture owns its own state table and its own parser, which is the only
-- part that genuinely differs between them. What they all had - and all had
-- slightly differently - is the timer, so that lives here.
--
-- The window is bounded twice over: `quietFor` seconds with no new line closes
-- it, and `maxWindow` seconds from the first armed tick closes it regardless.
-- The second bound is the point. Every one of these captures re-arms on lines
-- it did not itself produce (a blank-line trigger firing on unrelated output,
-- say), and with only a silence bound a steady trickle of traffic could hold a
-- capture open indefinitely, swallowing the screen with it.
--
-- Headless by design: no UI or Geyser dependency, so Minimal mode and the
-- Galaxy Navigator content can share it.

F2T_CAPTURE_WINDOWS = F2T_CAPTURE_WINDOWS or {}

local DEFAULT_QUIET_FOR  = 0.5
local DEFAULT_MAX_WINDOW = 15
-- How long to wait for the command to produce anything at all. The quiet
-- window can only measure silence, and silence is also what a server that
-- hasn't answered yet looks like - so arming straight into a half-second
-- window makes a busy moment read as "no data captured", which then dumps the
-- listing to the screen unfiltered when it does arrive.
local FIRST_LINE_WAIT    = 4

-- (Re)arm `name`'s window. onDone fires once, when the window closes - either
-- way it closes. Callers still check their own active flag inside onDone; the
-- window knows nothing about what is being captured.
function f2t_capture_arm(name, onDone, quietFor, maxWindow)
    local window = F2T_CAPTURE_WINDOWS[name]
    local opening = not window
    if opening then
        window = {startedAt = os.time(), maxWindow = maxWindow or DEFAULT_MAX_WINDOW}
        F2T_CAPTURE_WINDOWS[name] = window
    end
    if window.timerId then killTimer(window.timerId) end
    window.timerId = nil

    local remaining = window.maxWindow - (os.time() - window.startedAt)
    if remaining <= 0 then
        f2t_capture_close(name)
        f2t_debug_log("[map/capture] Window '%s' hit its %ds cap", name, window.maxWindow)
        onDone()
        return
    end

    local wait = quietFor or DEFAULT_QUIET_FOR
    if opening then wait = math.max(wait, FIRST_LINE_WAIT) end

    window.timerId = tempTimer(math.min(wait, remaining), function()
        -- A window closed and re-opened while this timer was pending belongs
        -- to a different capture run; let it be.
        if F2T_CAPTURE_WINDOWS[name] ~= window then return end
        f2t_capture_close(name)
        onDone()
    end)
end

-- End the window without firing onDone. The next arm starts a fresh one, so
-- this is also how a multi-phase capture gives each phase its own cap.
function f2t_capture_close(name)
    local window = F2T_CAPTURE_WINDOWS[name]
    if not window then return end
    if window.timerId then killTimer(window.timerId) end
    F2T_CAPTURE_WINDOWS[name] = nil
end

f2t_debug_log("[map] Loaded capture.lua")
