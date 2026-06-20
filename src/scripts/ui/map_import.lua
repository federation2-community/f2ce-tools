-- fed2-tools — Map import dialog
--
-- f2tShowMapImportDialog() is called by map/import_check.lua when the Mudlet
-- map database is empty (first use) or a new map DB version shipped with an
-- upgrade.  Presents three pre-bundled map options and imports the selected one.
--
-- Uses Mux.registerContent + Mux._applyContent so the dialog integrates cleanly
-- with Muxlet's pane lifecycle (contentBg cleared, z-order, theme borders).

-- ── Option definitions ────────────────────────────────────────────────────────

local _MAP_OPTIONS = {
    { file = "galaxy_brief.json",              label = "Whole Galaxy  (Recommended)" },
    { file = "starter_map_with_exchanges.json", label = "Starter Map with Exchanges"  },
    { file = "starter_map.json",               label = "Starter Map  (Basic)"        },
}

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

-- ── Import logic ──────────────────────────────────────────────────────────────

local function _doImport(filePath, statusLbl, importBtn)
    local f = io.open(filePath, "r")
    if not f then
        statusLbl:setStyleSheet(_CSS_STATUS_ERR)
        statusLbl:echo("Map file not found — was the package installed via MPR?")
        return false
    end
    f:close()

    deleteMap()
    F2T_MAP_CURRENT_ROOM_ID = nil

    local ok, errMsg = loadJsonMap(filePath)
    if ok then
        updateMap()
        local roomCount = 0
        for _ in pairs(getRooms()) do roomCount = roomCount + 1 end
        tempTimer(0.5, function()
            if F2T_MAP_ENABLED and f2t_map_sync then f2t_map_sync() end
        end)
        statusLbl:setStyleSheet(_CSS_STATUS_OK)
        statusLbl:echo(string.format("Map imported — %d rooms loaded", roomCount))
        importBtn:setStyleSheet(_CSS_BTN_DONE)
        importBtn:echo("<center>Map Imported</center>")
        cecho(string.format("\n<green>[fed2-tools]<reset> Map imported — %d rooms\n", roomCount))
        return true
    else
        statusLbl:setStyleSheet(_CSS_STATUS_ERR)
        statusLbl:echo(string.format("Import failed: %s", errMsg or "unknown error"))
        return false
    end
end

-- ── Content apply function ────────────────────────────────────────────────────

local function applyMapImportToPane(target)
    target.contentBg:echo("")
    target.contentBg:setStyleSheet("background-color:rgba(0,0,0,0);border:none;")

    local c   = target.content
    local pfx = target._gid .. "_mi_"
    local IX  = "3%"
    local IW  = "94%"
    local y   = 10

    -- Intro text
    local intro = Geyser.Label:new({ name=pfx.."intro", x=IX, y=y, width=IW, height=46 }, c)
    intro:setStyleSheet("background:transparent; color:rgba(198,210,238,255); font-size:10px; padding:4px 14px;")
    intro:echo(
        "<font color='#c6d2ee'>Install a map database to jumpstart navigation.<br>" ..
        "You can skip this and build your map by exploring the galaxy.</font>")
    y = y + 52

    local div1 = Geyser.Label:new({ name=pfx.."div1", x=0, y=y, width="100%", height=1 }, c)
    div1:setStyleSheet(Mux.dialogCss.divider)
    y = y + 10

    -- Map option selector
    local optLbl = Geyser.Label:new({ name=pfx.."optLbl", x=IX, y=y, width=IW, height=16 }, c)
    optLbl:setStyleSheet("background:transparent; color:rgba(115,222,148,255); font-size:9px; font-weight:bold; padding:0 14px;")
    optLbl:echo("SELECT MAP DATABASE")
    y = y + 20

    local mapDir   = getMudletHomeDir() .. "/fed2-tools/shared/"
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

        local btn = Geyser.Label:new({ name=pfx.."opt"..i, x=IX, y=y, width=IW, height=32 }, c)
        btn:echo("<center>" .. label .. "</center>")
        table.insert(optBtns, btn)

        local capturedIdx = i
        btn:setClickCallback(function()
            if done then return end
            selected = capturedIdx
            refreshStyles()
        end)
        y = y + 36
    end
    refreshStyles()

    y = y + 6
    local div2 = Geyser.Label:new({ name=pfx.."div2", x=0, y=y, width="100%", height=1 }, c)
    div2:setStyleSheet(Mux.dialogCss.divider)
    y = y + 10

    -- Status label
    local statusLbl = Geyser.Label:new({ name=pfx.."status", x=IX, y=y, width=IW, height=20 }, c)
    statusLbl:setStyleSheet(_CSS_STATUS_INFO)
    statusLbl:echo("")
    y = y + 28

    -- Import button
    local importBtn = Geyser.Label:new({ name=pfx.."import", x="10%", y=y, width="80%", height=34 }, c)
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
                for _, btn in ipairs(optBtns) do
                    btn:setStyleSheet(_CSS_BTN_DONE)
                    btn:setClickCallback(function() end)
                end
            end
        end)
    end)
    y = y + 42

    local div3 = Geyser.Label:new({ name=pfx.."div3", x=0, y=y, width="100%", height=1 }, c)
    div3:setStyleSheet(Mux.dialogCss.divider)
    y = y + 10

    -- Skip / close button
    local skipBtn = Geyser.Label:new({ name=pfx.."skip", x="25%", y=y, width="50%", height=32 }, c)
    skipBtn:setStyleSheet(Mux.dialogCss.button)
    skipBtn:echo("<center>Skip</center>")
    skipBtn:setClickCallback(function() target:close() end)
end

-- ── Public entry point ────────────────────────────────────────────────────────

function f2tShowMapImportDialog()
    if not (Mux and Mux.createDialog and Mux.registerContent and Mux._applyContent) then
        cecho("\n<yellow>[fed2-tools]<reset> Map import: run  <cyan>map import<reset>  to load a map database.\n")
        return
    end

    if not Mux._content or not Mux._content["f2t_map_import"] then
        Mux.registerContent("f2t_map_import", {
            internal = true,
            name     = "Map Import",
            apply    = applyMapImportToPane,
        })
    end

    local DIALOG_W = 480
    local DIALOG_H = 360

    local dialog = Mux.createDialog({
        title  = "Import Map Database",
        width  = DIALOG_W,
        height = DIALOG_H,
    })
    Mux._applyContent(dialog, "f2t_map_import")
    dialog:show()
    dialog:raise()
end
