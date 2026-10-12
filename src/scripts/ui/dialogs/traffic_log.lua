-- f2tShowTrafficLog() opens a scrollable window of every arrival and departure
-- seen this session (F2T_TRAFFIC.history, kept by traffic.lua), grouped by
-- room, with clickable names. Stays live while open. Opened by the "traffic"
-- command or the Full log button in Local Players.

local CONSOLE_FONT_SIZE = 10

local instances = {}   -- target._gid → { console, lastId }

local function writeEntry(console, entry)
    if entry.roomBreak then
        console:decho(string.format("\n<95,100,128>── %s ──<r>\n", entry.text ~= "" and entry.text or "Unknown room"))
        return
    end
    local lead, name, rest = f2tTrafficLineParts(entry)
    local who = entry.name
    console:decho("<95,100,128>" .. os.date("%H:%M:%S", math.floor(entry.at)) .. "  " .. lead)
    console:dechoLink(name .. "<r>", function()
        if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(who) end
    end, "Open " .. who .. "'s player card", true)
    console:decho(rest .. "\n")
end

local function replay(instance)
    instance.console:clear()
    instance.lastId = 0
    local history = F2T_TRAFFIC and F2T_TRAFFIC.history or {}
    if #history == 0 then
        instance.console:decho("<95,100,128>Nobody has come or gone yet this session.<r>\n")
        return
    end
    for _, entry in ipairs(history) do
        writeEntry(instance.console, entry)
        instance.lastId = entry.id
    end
end

-- Appends whatever arrived since this window last drew.
local function appendNew(instance)
    local history = F2T_TRAFFIC and F2T_TRAFFIC.history or {}
    if instance.lastId == 0 and #history > 0 then
        replay(instance)
        return
    end
    for _, entry in ipairs(history) do
        if entry.id > instance.lastId then
            writeEntry(instance.console, entry)
            instance.lastId = entry.id
        end
    end
end

local function applyTrafficLog(target)
    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end
    local console = Geyser.MiniConsole:new({
        name = target._gid .. "_trafficlog", x = 0, y = 0, width = "100%", height = "100%",
        fontSize = Mux.scaledFontSize(target, CONSOLE_FONT_SIZE),
    }, target.content)
    console:setColor(18, 18, 26)
    console:enableAutoWrap()
    local instance = { console = console, lastId = 0 }
    instances[target._gid] = instance
    replay(instance)
end

function f2tShowTrafficLog()
    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho("\n<yellow>[f2ce-tools]<reset> The traffic log requires Muxlet.\n")
        return
    end

    if not Mux._content or not Mux._content["f2t_traffic_log"] then
        Mux.registerContent("f2t_traffic_log", {
            internal = true,
            name     = "Room Traffic",
            apply    = applyTrafficLog,
            remove   = function(target) instances[target._gid] = nil end,
            onTextScale = function(target)
                local instance = instances[target._gid]
                if not instance then return end
                instance.console:setFontSize(Mux.scaledFontSize(target, CONSOLE_FONT_SIZE))
                replay(instance)
            end,
        })
    end

    local dialog = Mux.createDialog({
        title     = "Room Traffic",
        width     = 760,
        height    = 480,
        resizable = true,
        singleton = "f2t_traffic_log",
    })
    Mux._applyContent(dialog, "f2t_traffic_log")
    dialog:show()
    dialog:raise()
end

registerAnonymousEventHandler("f2tTrafficChanged", function()
    for gid, instance in pairs(instances) do
        if not pcall(appendNew, instance) then instances[gid] = nil end
    end
end)
