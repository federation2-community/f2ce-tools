-- Renders F2T_CHAT.history (scripts/chat/history.lua) into a MiniConsole with
-- grouped speakers, per-type colors, an A/C/T/S filter cycle, and a timestamp
-- toggle. Live messages append via the f2tChatUpdated event; filter or
-- timestamp changes replay the whole log.
--
-- Only registers content; place "fed2_chat" in any pane or tab for an
-- always-visible chat view. Filter and timestamp state serialize with the
-- workspace.
--
-- The console fills the whole content area (no in-content header): filter
-- and timestamp controls publish to the hosting pane/tab's own titlebar and
-- right-click menu via titlebarElements (see buildChatDef below), the same
-- mechanism Muxlet's own Button Grid content uses for its wrench icon.

-- ── Style per message type ────────────────────────────────────────────────────
-- gutterHex: hecho #RRGGBB for the continuation pipe / direction arrows
-- textHex:   hecho #RRGGBB for the message body

local STYLE = {
    com       = { gutterHex = "#2a7070", textHex = "#008080" },
    say       = { gutterHex = "#008000", textHex = "#008000" },
    tell_in   = { gutterHex = "#882222", textHex = "#882222" },
    self_com  = { gutterHex = "#226622", textHex = "#00ffff" },
    self_say  = { gutterHex = "#4caf70", textHex = "#4caf70" },
    self_tell = { gutterHex = "#ff8888", textHex = "#ff8888" },
}

local FILTERS = {
    { id = "all",  label = "A", matches = nil,                                tip = "Show all messages" },
    { id = "com",  label = "C", matches = { com = true, self_com = true },    tip = "Com channel only" },
    { id = "tell", label = "T", matches = { tell_in = true, self_tell = true }, tip = "Tells only" },
    { id = "say",  label = "S", matches = { say = true, self_say = true },    tip = "Say only" },
}

-- Per-pane state, keyed by target._gid
local instances = {}

-- ── Name coloring ─────────────────────────────────────────────────────────────

-- decho tag for a name with unknown/unrecorded rank (mirrors who.lua's RC_DEFAULT).
local UNKNOWN_RANK_DECHO = "<200,200,200>"

-- Colors by the sender's last known rank regardless of online status —
-- player_db keeps a player's rank after they log out, so this only falls
-- back to gray for names we have never seen a rank for at all.
local function rankDecho(name)
    if f2t_player_db_get then
        local entry = f2t_player_db_get(name)
        if entry and entry.rank then
            local tag = f2t_rank_color_decho(entry.rank)
            if tag then return tag, entry.rank end
        end
    end
    return UNKNOWN_RANK_DECHO, nil
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

-- Render one record into an instance's console.
--   isCont = true: same speaker+type as previous message — colored pipe only.
-- hecho carries #hex prefixes, cecho carries <colorname> tags, decho carries
-- <r,g,b> tags (used for exact rank-color matches). Never mixed in one call.
local function renderRecord(inst, r, isCont)
    local mc = inst.console
    if not mc then return end

    -- Cycle markers always render (structural game-day dividers from old saves)
    if r.type == "cycle" then
        mc:hecho(r.line or "")
        return
    end

    -- Status lines only render when timestamps are on
    if r.type == "status" then
        if inst.showTs then mc:hecho(r.line or "") end
        return
    end

    local filter = FILTERS[inst.filterIdx]
    if filter.matches and not filter.matches[r.type] then return end

    local st = STYLE[r.type] or STYLE.com

    if inst.showTs and r.t then
        mc:hecho("#404040[" .. os.date("%H:%M", r.t) .. "] ")
    end

    if isCont then
        mc:hecho(st.gutterHex .. "▎  ")
        mc:hecho(st.textHex .. r.msg .. "\n")
        return
    end

    local nc, rank = rankDecho(r.from)
    local hint     = rank and (rank .. " " .. r.from) or r.from
    local from     = r.from

    if r.type == "self_tell" then
        mc:hecho(st.gutterHex .. "❯❯ ")
    elseif r.type == "tell_in" then
        mc:hecho(st.gutterHex .. "❮❮ ")
    end

    mc:dechoLink(
        nc .. "<b>" .. from .. "</b><r>",
        function()
            if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(from) end
        end,
        hint, true)
    mc:cecho(" <dim_gray>»<reset> ")
    mc:hecho(st.textHex .. r.msg .. "\n")
end

local function replay(inst)
    local mc = inst.console
    if not mc then return end
    mc:clear()
    inst.lastKey = nil
    if #F2T_CHAT.history == 0 then return end

    local filtered = (FILTERS[inst.filterIdx].matches ~= nil)

    if inst.showTs then
        mc:hecho("#303030─── Chat History ──────────────────────────\n")
    end

    local lastDay = ""
    local prev    = nil

    for _, r in ipairs(F2T_CHAT.history) do
        if inst.showTs and r.t and r.type ~= "status" then
            local day = os.date("%Y-%m-%d", r.t)
            if day ~= lastDay then
                mc:hecho("#1a3040── " .. os.date("%A, %b %d", r.t) .. " ──\n")
                lastDay = day
            end
        end

        local isCont = (not filtered)
            and prev
            and r.type ~= "status" and prev.type ~= "status"
            and r.type ~= "cycle"  and prev.type ~= "cycle"
            and prev.from == r.from and prev.type == r.type

        renderRecord(inst, r, isCont)
        if r.type ~= "status" and r.type ~= "cycle" then prev = r end
    end

    if inst.showTs then
        mc:hecho("#303030─── Live ─────────────────────────────────\n")
    end

    inst.lastKey = prev and (prev.from .. prev.type) or nil
end

-- Append the newest history record to one instance, tracking speaker grouping.
local function appendLatest(inst)
    local r = F2T_CHAT.history[#F2T_CHAT.history]
    if not r then return end

    local isCont = false
    if r.type == "status" or r.type == "cycle" then
        inst.lastKey = nil
    else
        local key = r.from .. r.type
        if not FILTERS[inst.filterIdx].matches then
            isCont = (inst.lastKey == key)
        end
        inst.lastKey = key
    end
    renderRecord(inst, r, isCont)
end

-- ── Titlebar element helpers ──────────────────────────────────────────────────

-- Resolve the instance state for a titlebarElements callback's ctx (a tab's
-- content publishes to its owning pane's titlebar, but keys off the tab's own
-- _gid — see Muxlet's README "Publishing to the titlebar and menu").
local function chatInstFor(ctx)
    local surf = ctx and (ctx.tab or ctx.pane)
    return surf and instances[surf._gid]
end

-- ── Content build ─────────────────────────────────────────────────────────────

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    if instances[gid] then
        replay(instances[gid])
        return
    end

    local mc = Geyser.MiniConsole:new({
        name = gid .. "_chatmc", x = 0, y = 0, width = "100%", height = "100%",
        fontSize = 9,
    }, target.content)
    mc:setColor(18, 18, 26)
    mc:enableAutoWrap()

    local inst = {
        console   = mc,
        showTs    = f2t_settings_get("chat", "show_timestamps") or false,
        filterIdx = 1,
        lastKey   = nil,
    }
    instances[gid] = inst

    replay(inst)
end

-- ── Content registration ──────────────────────────────────────────────────────

local function buildChatDef()
    return {
        name        = "Chat",
        description = "Com/say/tell history with speaker grouping, filters, and timestamps.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,

        -- Filter/timestamp controls publish to the hosting pane/tab's own
        -- titlebar + right-click menu instead of drawing an in-content header
        -- strip (mirrors Muxlet's own Button Grid wrench icon). Muxlet's
        -- per-element "hide from titlebar" (right-click > Properties) already
        -- covers hiding either of these individually — nothing extra needed here.
        titlebarElements = {
            {
                id = "chat.timestamps", side = "left", group = "content", order = 0, priority = 100,
                icon = "⏱", tooltip = "Toggle timestamps",
                hideable = true, hideLabel = "Timestamps Icon",
                onClick = function(ctx, event)
                    if event and event.button ~= "LeftButton" then return end
                    local inst = chatInstFor(ctx)
                    if not inst then return end
                    inst.showTs = not inst.showTs
                    f2t_settings_set("chat", "show_timestamps", inst.showTs)
                    replay(inst)
                end,
                menuText = function(ctx)
                    local inst = chatInstFor(ctx)
                    return (inst and inst.showTs) and "⏱  Timestamps ON" or "⏱  Timestamps OFF"
                end,
                menuGroup = "info", menuOrder = 90,
                run = function(ctx)
                    local inst = chatInstFor(ctx)
                    if not inst then return end
                    inst.showTs = not inst.showTs
                    f2t_settings_set("chat", "show_timestamps", inst.showTs)
                    replay(inst)
                end,
            },
            {
                id = "chat.filter", side = "left", group = "content", order = 1, priority = 101,
                icon = "🔎", tooltip = "Cycle message filter (all / com / tell / say)",
                hideable = true, hideLabel = "Filter Icon",
                onClick = function(ctx, event)
                    if event and event.button ~= "LeftButton" then return end
                    local inst = chatInstFor(ctx)
                    if not inst then return end
                    inst.filterIdx = (inst.filterIdx % #FILTERS) + 1
                    replay(inst)
                end,
                menuText = function(ctx)
                    local inst = chatInstFor(ctx)
                    local f = inst and FILTERS[inst.filterIdx]
                    return "🔎  Filter: " .. (f and f.tip or "Show all messages")
                end,
                menuGroup = "info", menuOrder = 91,
                run = function(ctx)
                    local inst = chatInstFor(ctx)
                    if not inst then return end
                    inst.filterIdx = (inst.filterIdx % #FILTERS) + 1
                    replay(inst)
                end,
            },
        },

        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[chat] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            instances[target._gid] = nil
        end,
        serialize = function(target)
            local inst = instances[target._gid]
            if not inst then return {} end
            return { showTs = inst.showTs, filterIdx = inst.filterIdx }
        end,
        restore = function(target, data)
            local inst = instances[target._gid]
            if not inst then return end
            if type(data.showTs) == "boolean" then inst.showTs = data.showTs end
            if type(data.filterIdx) == "number" and FILTERS[data.filterIdx] then
                inst.filterIdx = data.filterIdx
            end
            replay(inst)
        end,
        onReveal = function(target)
            local inst = instances[target._gid]
            if inst then replay(inst) end
        end,
    }
end

function f2tRegisterChat()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[chat] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_chat", buildChatDef())
    if f2t_debug_log then f2t_debug_log("[chat] registered fed2_chat content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterChat)

registerAnonymousEventHandler("f2tChatUpdated", function(_, mode)
    for gid, inst in pairs(instances) do
        if mode == "append" then
            local ok = pcall(appendLatest, inst)
            if not ok then instances[gid] = nil end
        else
            local ok = pcall(replay, inst)
            if not ok then instances[gid] = nil end
        end
    end
end)

if f2t_debug_log then f2t_debug_log("[chat] content module loaded") end
