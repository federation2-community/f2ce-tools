if not F2T_MAP_WHEREIS_CAPTURE or not F2T_MAP_WHEREIS_CAPTURE.active then
    return
end

deleteLine()

local system_name = matches[2]

f2t_map_whereis_capture_complete(system_name)
