-- f2tShowMapImportOverlay(slotContent, gid, reason) is called by
-- map/import_check.lua (auto first-run/upgrade), map_settings.lua's gear
-- menu, and the "map import db" alias. Presents three pre-bundled map
-- options and imports the selected one.
--
-- Built as a Geyser overlay inside the map content's own slot (slotContent),
-- not a separate floating Mux dialog: Mudlet's native mapper widget owns its
-- own "No map yet" empty-state overlay with no Lua hook to suppress it, and a
-- top-level dialog would race it for z-order. A same-parent overlay inside
-- the same slotContent uses the same raise() stacking the mapper/movement/
-- settings widgets already rely on.

-- ── Option definitions ────────────────────────────────────────────────────────

local _MAP_OPTIONS = {
    { file = "galaxy_brief.json",              label = "Whole Galaxy  (Recommended)" },
    { file = "starter_map_with_exchanges.json", label = "Starter Map with Exchanges"  },
    { file = "starter_map.json",               label = "Starter Map  (Basic)"        },
}

local _CSS_BG = "background-color: rgba(10,12,20,235); border: none;"
local _CSS_PANEL = [[
    background-color: rgba(16,20,34,235);
    border: 1px solid rgba(80,95,140,200);
    border-radius: 6px;
]]
local _CSS_BTN_OFF = [[
    QLabel {
        background-color: rgba(28,32,50,210);
        color: rgba(150,165,205,255);
        border: 1px solid rgba(72,85,128,180);
        border-radius: 4px;
        font-size: 10px;
        qproperty-alignment: AlignCenter;
    }
    QLabel::hover {
        background-color: rgba(42,48,78,230);
        border-color: rgba(105,138,220,200);
        color: rgba(200,215,255,255);
    }
]]
local _CSS_BTN_ON = [[
    QLabel {
        background-color: rgba(20,50,36,240);
        color: rgba(115,222,148,255);
        border: 2px solid rgba(52,160,86,220);
        border-radius: 4px;
        font-size: 10px; font-weight: bold;
        qproperty-alignment: AlignCenter;
    }
]]
local _CSS_BTN_DONE = [[
    QLabel {
        background-color: rgba(20,46,32,200);
        color: rgba(100,175,120,195);
        border: 2px solid rgba(50,140,75,155);
        border-radius: 4px;
        font-size: 10px;
        qproperty-alignment: AlignCenter;
    }
]]
local _CSS_STATUS_INFO = "background:transparent; color:rgba(105,125,180,255); font-size:9px; padding:0 14px;"
local _CSS_STATUS_OK   = "background:transparent; color:rgba(115,222,148,255); font-size:9px; padding:0 14px;"
local _CSS_STATUS_ERR  = "background:transparent; color:rgba(210,120,115,255); font-size:9px; padding:0 14px;"
local _CSS_TITLE = "background:transparent; color:rgba(230,236,250,255); font-size:12px; font-weight:bold; padding:0 14px;"

local _INTRO_BY_REASON = {
    firstrun =
        "<font color='#c6d2ee'>Install a map database to jumpstart navigation.<br>" ..
        "You can skip this and build your map by exploring the galaxy.</font>",
    upgrade =
        "<font color='#c6d2ee'>This version ships an updated map database.<br>" ..
        "Re-importing is recommended — it replaces your current map.</font>",
    manual =
        "<font color='#c6d2ee'>Choose a bundled map database to import.<br>" ..
        "Importing replaces your current map.</font>",
}

local _TITLE_BY_REASON = {
    firstrun = "Import Map Database",
    upgrade  = "Map Database Update Recommended",
    manual   = "Import Map Database",
}

-- Singleton: only one map pane exists at a time (fed2_map is singleton
-- content), so a single module-level reference is enough to avoid stacking
-- duplicate overlays if something calls this twice in a row.
local _live = nil   -- { shell = Geyser.Container, slotContent = ... }

-- ── Import logic ──────────────────────────────────────────────────────────────

local function _doImport(filePath, statusLbl, importBtn)
    -- f2t_map_import_file (map/import_export.lua) is the single source of truth
    -- for loading a map file into the profile: wipe, load, refresh, sync.
    local ok, result = f2t_map_import_file(filePath)
    if ok then
        statusLbl:setStyleSheet(_CSS_STATUS_OK)
        statusLbl:echo(string.format("Map imported — %d rooms loaded", result))
        importBtn:setStyleSheet(_CSS_BTN_DONE)
        importBtn:echo("<center>Map Imported</center>")
        cecho(string.format("\n<green>[fed2-tools]<reset> Map imported — %d rooms\n", result))
        return true
    else
        statusLbl:setStyleSheet(_CSS_STATUS_ERR)
        statusLbl:echo(string.format("Import failed: %s", result or "unknown error"))
        return false
    end
end

local function _dismiss()
    if not _live then return end
    local shell = _live.shell
    _live = nil
    if shell then
        pcall(function()
            if shell.delete then shell:delete() else shell:hide() end
        end)
    end
end

-- ── Public entry point ────────────────────────────────────────────────────────

-- reason: "firstrun" (default) | "upgrade" | "manual" — controls framing.
-- Returns true if the overlay was actually created/shown, false otherwise, so
-- callers (import_check.lua) can avoid burning the "seen" flag on a failed show.
function f2tShowMapImportOverlay(slotContent, gid, reason)
    if not slotContent then
        cecho("\n<yellow>[fed2-tools]<reset> Map import: no map pane is open to show the picker in.\n")
        return false
    end

    reason = reason or "firstrun"

    -- Already showing (e.g. re-triggered while up) — just raise it.
    if _live and _live.slotContent == slotContent then
        pcall(function() _live.shell:raise() end)
        return true
    end
    _dismiss()

    local pfx = (gid or "f2t_map") .. "_mi_"

    local shell = Geyser.Container:new({ name = pfx.."shell", x=0, y=0, width="100%", height="100%" }, slotContent)
    local bg = Geyser.Label:new({ name = pfx.."bg", x=0, y=0, width="100%", height="100%" }, shell)
    bg:setStyleSheet(_CSS_BG)

    -- Centered panel so the overlay reads as a modal card over the map,
    -- not a full-bleed wall of controls. Height must fit: 12 top pad + title
    -- (24) + intro (48) + div1 (10) + optLbl (18) + 3 options (32 each = 96)
    -- + gap (4) + div2 (8) + status (22) + import btn (38) + div3 (8) + skip
    -- btn (28) = 316, plus bottom padding. Scales modestly with the host pane
    -- (clamped to that minimum) so it doesn't read as a tiny card adrift in a
    -- huge dark void on a large map pane.
    local slotW = (slotContent.get_width  and slotContent:get_width())  or 380
    local slotH = (slotContent.get_height and slotContent:get_height()) or 340
    local PANEL_W = math.max(380, math.min(520, math.floor(slotW * 0.42)))
    local PANEL_H = math.max(340, math.min(460, math.floor(slotH * 0.42)))
    local panel = Geyser.Container:new({
        name = pfx.."panel",
        x = "50%-" .. math.floor(PANEL_W / 2), y = "50%-" .. math.floor(PANEL_H / 2),
        width = PANEL_W, height = PANEL_H,
    }, shell)
    local panelBg = Geyser.Label:new({ name = pfx.."panelBg", x=0, y=0, width="100%", height="100%" }, panel)
    panelBg:setStyleSheet(_CSS_PANEL)

    local IX = "3%"
    local IW = "94%"
    local y  = 12

    local titleLbl = Geyser.Label:new({ name=pfx.."title", x=IX, y=y, width=IW, height=18 }, panel)
    titleLbl:setStyleSheet(_CSS_TITLE)
    titleLbl:echo(_TITLE_BY_REASON[reason] or _TITLE_BY_REASON.firstrun)
    y = y + 24

    local intro = Geyser.Label:new({ name=pfx.."intro", x=IX, y=y, width=IW, height=42 }, panel)
    intro:setStyleSheet("background:transparent; color:rgba(198,210,238,255); font-size:10px; padding:4px 14px;")
    intro:echo(_INTRO_BY_REASON[reason] or _INTRO_BY_REASON.firstrun)
    y = y + 48

    local div1 = Geyser.Label:new({ name=pfx.."div1", x=0, y=y, width="100%", height=1 }, panel)
    div1:setStyleSheet(Mux and Mux.dialogCss and Mux.dialogCss.divider or "background-color: rgba(255,255,255,0.10); border: none;")
    y = y + 10

    -- Map option selector
    local optLbl = Geyser.Label:new({ name=pfx.."optLbl", x=IX, y=y, width=IW, height=14 }, panel)
    optLbl:setStyleSheet("background:transparent; color:rgba(115,222,148,255); font-size:9px; font-weight:bold; padding:0 14px;")
    optLbl:echo("SELECT MAP DATABASE")
    y = y + 18

    local mapDir   = getMudletHomeDir() .. "/fed2-tools/"
    local selected = 1
    local done     = false
    local optBtns  = {}

    local function refreshStyles()
        for i, btn in ipairs(optBtns) do
            btn:setStyleSheet(i == selected and _CSS_BTN_ON or _CSS_BTN_OFF)
        end
    end

    for i, opt in ipairs(_MAP_OPTIONS) do
        local roomCount
        local mf = io.open(mapDir .. opt.file, "r")
        if mf then
            local raw = mf:read("*all")
            mf:close()
            local ok2, data = pcall(yajl.to_value, raw)
            if ok2 and data and data.roomCount then roomCount = data.roomCount end
        end
        local label = roomCount
            and string.format("%s  (%d rooms)", opt.label, roomCount)
            or  opt.label

        local btn = Geyser.Label:new({ name=pfx.."opt"..i, x=IX, y=y, width=IW, height=28 }, panel)
        btn:echo("<center>" .. label .. "</center>")
        table.insert(optBtns, btn)

        local capturedIdx = i
        btn:setClickCallback(function()
            if done then return end
            selected = capturedIdx
            refreshStyles()
        end)
        y = y + 32
    end
    refreshStyles()

    y = y + 4
    local div2 = Geyser.Label:new({ name=pfx.."div2", x=0, y=y, width="100%", height=1 }, panel)
    div2:setStyleSheet(Mux and Mux.dialogCss and Mux.dialogCss.divider or "background-color: rgba(255,255,255,0.10); border: none;")
    y = y + 8

    -- Status label
    local statusLbl = Geyser.Label:new({ name=pfx.."status", x=IX, y=y, width=IW, height=16 }, panel)
    statusLbl:setStyleSheet(_CSS_STATUS_INFO)
    statusLbl:echo("")
    y = y + 22

    -- Import button
    local importBtn = Geyser.Label:new({ name=pfx.."import", x="10%", y=y, width="80%", height=30 }, panel)
    importBtn:setStyleSheet([[
        QLabel {
            background-color: rgba(28,48,78,230);
            color: rgba(120,180,255,255);
            border: 1px solid rgba(68,118,200,210);
            border-radius: 5px;
            font-size: 11px; font-weight: bold;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(38,68,108,245);
            border-color: rgba(100,158,255,240);
            color: white;
        }
    ]])
    importBtn:echo("<center>Import Selected Map</center>")

    local skipBtn -- forward-declared so importBtn's callback can relabel it

    importBtn:setClickCallback(function()
        if done then return end
        local opt  = _MAP_OPTIONS[selected]
        local path = mapDir .. opt.file
        statusLbl:setStyleSheet(_CSS_STATUS_INFO)
        statusLbl:echo("Importing, please wait…")
        tempTimer(0.1, function()
            local ok2 = _doImport(path, statusLbl, importBtn)
            if ok2 then
                done = true
                tempTimer(0.6, function() _dismiss() end)
            end
        end)
    end)
    y = y + 38

    local div3 = Geyser.Label:new({ name=pfx.."div3", x=0, y=y, width="100%", height=1 }, panel)
    div3:setStyleSheet(Mux and Mux.dialogCss and Mux.dialogCss.divider or "background-color: rgba(255,255,255,0.10); border: none;")
    y = y + 8

    -- Skip / close button — always available, per design: the user must deal
    -- with this overlay, but skipping out of it is always on the table.
    skipBtn = Geyser.Label:new({ name=pfx.."skip", x="25%", y=y, width="50%", height=28 }, panel)
    skipBtn:setStyleSheet(Mux and Mux.dialogCss and Mux.dialogCss.button or _CSS_BTN_OFF)
    skipBtn:echo("<center>Skip</center>")
    skipBtn:setClickCallback(function() _dismiss() end)

    shell:raise()
    _live = { shell = shell, slotContent = slotContent }
    return true
end
