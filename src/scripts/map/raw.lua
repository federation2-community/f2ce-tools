-- f2ce-tools map — raw diagnostic display (ported from map_raw.lua)

local function display_table(tbl, indent, max_depth)
    indent = indent or 0; max_depth = max_depth or 5
    if indent >= max_depth then
        cecho(string.rep("  ", indent) .. "<red>(max depth reached)<reset>\n"); return
    end
    if type(tbl) ~= "table" then
        cecho(string.rep("  ", indent) .. tostring(tbl) .. "\n"); return
    end
    for key, value in pairs(tbl) do
        local key_str    = tostring(key)
        local indent_str = string.rep("  ", indent)
        if type(value) == "table" then
            cecho(string.format("%s<yellow>%s<reset>: <dim_grey>(table)<reset>\n", indent_str, key_str))
            display_table(value, indent + 1, max_depth)
        elseif type(value) == "string" then
            cecho(string.format("%s<yellow>%s<reset>: <white>\"%s\"<reset>\n", indent_str, key_str, value))
        elseif type(value) == "number" then
            cecho(string.format("%s<yellow>%s<reset>: <cyan>%s<reset>\n", indent_str, key_str, tostring(value)))
        elseif type(value) == "boolean" then
            cecho(string.format("%s<yellow>%s<reset>: <magenta>%s<reset>\n", indent_str, key_str, tostring(value)))
        else
            cecho(string.format("%s<yellow>%s<reset>: <dim_grey>%s (%s)<reset>\n",
                indent_str, key_str, tostring(value), type(value)))
        end
    end
end

function f2t_map_raw_display_room(room_id, include_gmcp)
    room_id = room_id or F2T_MAP_CURRENT_ROOM_ID
    local is_current_room = (room_id == F2T_MAP_CURRENT_ROOM_ID)
    if not room_id or not roomExists(room_id) then
        cecho(string.format("\n<red>[map]<reset> Room %s does not exist\n", tostring(room_id))); return
    end
    cecho(string.format("\n<green>[map]<reset> Raw data for room <white>%d<reset>", room_id))
    if is_current_room then cecho(" <yellow>(current room)<reset>") end
    cecho(":\n\n")

    cecho("<cyan>═══ Basic Info ═══<reset>\n")
    cecho(string.format("<yellow>Name<reset>: <white>%s<reset>\n", getRoomName(room_id) or "(unnamed)"))
    cecho(string.format("<yellow>Area<reset>: <white>%s<reset> (ID: <cyan>%d<reset>)\n",
        getRoomAreaName(getRoomArea(room_id)) or "(unknown)", getRoomArea(room_id) or 0))
    local x, y, z = getRoomCoordinates(room_id)
    cecho(string.format("<yellow>Coordinates<reset>: <cyan>x=%d, y=%d, z=%d<reset>\n", x or 0, y or 0, z or 0))
    cecho(string.format("<yellow>Environment<reset>: <cyan>%d<reset>\n", getRoomEnv(room_id) or 0))
    cecho(string.format("<yellow>Weight<reset>: <cyan>%d<reset>\n", getRoomWeight(room_id) or 1))
    cecho(string.format("<yellow>Character<reset>: <white>%s<reset>\n", getRoomChar(room_id) or "(none)"))
    local hash = getRoomHashByID(room_id)
    if hash then cecho(string.format("<yellow>Hash<reset>: <white>%s<reset>\n", hash)) end
    cecho(string.format("<yellow>Room Locked<reset>: <magenta>%s<reset>\n", tostring(roomLocked(room_id))))

    cecho("\n<cyan>═══ Standard Exits ═══<reset>\n")
    local exits = getRoomExits(room_id)
    if exits and next(exits) ~= nil then
        for dir, dest in pairs(exits) do
            local locked = hasExitLock(room_id, dir)
            local lock_str = locked and " <red>[LOCKED]<reset>" or ""
            cecho(string.format("  <yellow>%-10s<reset> -> <cyan>%d<reset>%s <dim_grey>(%s)<reset>\n",
                dir, dest, lock_str, getRoomName(dest) or "unnamed"))
        end
    else
        cecho("  <dim_grey>(no standard exits)<reset>\n")
    end

    cecho("\n<cyan>═══ Special Exits ═══<reset>\n")
    local ok1, special_exits = pcall(getSpecialExitsSwap, room_id)
    if not ok1 then
        cecho(string.format("  <red>ERROR calling getSpecialExitsSwap: %s<reset>\n", tostring(special_exits)))
    elseif special_exits and next(special_exits) ~= nil then
        for dest, command in pairs(special_exits) do
            local dest_id = tonumber(dest)
            cecho(string.format("  <yellow>%-30s<reset> -> <cyan>%s<reset> <dim_grey>(%s)<reset>\n",
                tostring(command), tostring(dest), dest_id and getRoomName(dest_id) or "unnamed"))
        end
    else
        cecho("  <dim_grey>(no special exits)<reset>\n")
    end

    cecho("\n<cyan>═══ Stub Exits ═══<reset>\n")
    local ok2, stubs = pcall(getExitStubs1, room_id)
    if not ok2 then
        cecho(string.format("  <red>ERROR calling getExitStubs1: %s<reset>\n", tostring(stubs)))
    elseif stubs and #stubs > 0 then
        local dir_names = {
            [1]="north",[2]="northeast",[3]="northwest",[4]="east",[5]="west",[6]="south",
            [7]="southeast",[8]="southwest",[9]="up",[10]="down",[11]="in",[12]="out",
        }
        for _, stub_num in pairs(stubs) do
            local dir_name = dir_names[stub_num] or string.format("(unknown: %d)", stub_num)
            cecho(string.format("  <yellow>%-10s<reset> <dim_grey>(stub exit, not connected)<reset>\n", dir_name))
        end
    else
        cecho("  <dim_grey>(no stub exits)<reset>\n")
    end

    if is_current_room and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.exits then
        cecho("\n<cyan>═══ GMCP Exits ═══<reset>\n")
        local gmcp_exits = gmcp.room.info.exits
        if next(gmcp_exits) ~= nil then
            for dir, dest_num in pairs(gmcp_exits) do
                cecho(string.format("  <yellow>%-10s<reset> -> <cyan>%s<reset> <dim_grey>(Fed2 room num)<reset>\n",
                    dir, tostring(dest_num)))
            end
        else
            cecho("  <dim_grey>(no GMCP exits)<reset>\n")
        end
    end

    cecho("\n<cyan>═══ User Data ═══<reset>\n")
    local userdata_keys = {
        "fed2_system","fed2_area","fed2_num","fed2_owner","fed2_flags",
        "fed2_planet","fed2_arrival_cmd","fed2_arrival_type","fed2_arrival_executed","fed2_stub",
        "fed2_flag_link","fed2_jump_synced_at",
    }
    local has_userdata = false
    for _, key in ipairs(userdata_keys) do
        local ok3, value = pcall(getRoomUserData, room_id, key)
        if not ok3 then
            cecho(string.format("  <red>ERROR reading %s: %s<reset>\n", key, tostring(value)))
        elseif value and value ~= "" then
            has_userdata = true
            if key == "fed2_jump_synced_at" then
                local ts = tonumber(value)
                local age = ts and (os.time() - ts) or nil
                cecho(string.format("  <yellow>%-25s<reset>: <white>%s<reset> <dim_grey>(%s ago)<reset>\n",
                    key, value, age and string.format("%ds", age) or "unknown age"))
            else
                cecho(string.format("  <yellow>%-25s<reset>: <white>%s<reset>\n", key, value))
            end
        end
    end
    if not has_userdata then cecho("  <dim_grey>(no user data)<reset>\n") end

    if include_gmcp and is_current_room then
        cecho("\n")
        local ok4, err4 = pcall(f2t_map_raw_display_gmcp_inline)
        if not ok4 then
            cecho(string.format("  <red>ERROR displaying GMCP data: %s<reset>\n", tostring(err4)))
        end
    end
    cecho("\n")
end

function f2t_map_raw_display_gmcp_inline()
    if not gmcp then cecho("<red>GMCP not available<reset>\n\n"); return end
    cecho("<cyan>═══ gmcp.room.info ═══<reset>\n")
    if gmcp.room and gmcp.room.info then
        display_table(gmcp.room.info, 0, 3)
    else
        cecho("<dim_grey>(not available)<reset>\n")
    end
    cecho("\n")
    cecho("<cyan>═══ gmcp.char.vitals ═══<reset>\n")
    if gmcp.char and gmcp.char.vitals then
        display_table(gmcp.char.vitals, 0, 3)
    else
        cecho("<dim_grey>(not available)<reset>\n")
    end
    cecho("\n")
    cecho("<cyan>═══ gmcp.char.ship ═══<reset>\n")
    if gmcp.char and gmcp.char.ship then
        display_table(gmcp.char.ship, 0, 3)
    else
        cecho("<dim_grey>(not available)<reset>\n")
    end
    cecho("\n")
end
