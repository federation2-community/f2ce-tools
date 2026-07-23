-- f2ce-tools map — saved destinations (ported from map_destinations.lua)

-- Safe accessor: ensures the destinations sub-table exists on whatever settings
-- store is currently active (may be _local_data before Mux is ready, or
-- Mux.settings._data afterwards).
local function ensureDestinations()
    local map_data = f2t_settings.map
    if not map_data.destinations then
        map_data.destinations = {}
    end
    return map_data.destinations
end

function f2t_map_destination_add(dest_name)
    if not dest_name or dest_name == "" then
        cecho("\n<red>[map]<reset> Destination name required\n"); return false
    end
    dest_name = string.lower(dest_name)
    if not f2t_map_ensure_current_location(f2t_map_destination_add, {dest_name}) then return false end
    local hash = getRoomHashByID(F2T_MAP_CURRENT_ROOM_ID)
    if not hash or hash == "" then
        cecho("\n<red>[map]<reset> Current room has no Fed2 hash - cannot save destination\n"); return false
    end
    local destinations = ensureDestinations()
    if destinations[dest_name] then
        cecho(string.format("\n<yellow>[map]<reset> Destination '%s' already exists (overwriting)\n", dest_name))
    end
    destinations[dest_name] = hash
    f2t_save_settings()
    local room_name = getRoomName(F2T_MAP_CURRENT_ROOM_ID)
    cecho(string.format("\n<green>[map]<reset> Destination '<yellow>%s<reset>' saved for <cyan>%s<reset>\n", dest_name, room_name))
    return true
end

function f2t_map_destination_remove(dest_name)
    if not dest_name or dest_name == "" then
        cecho("\n<red>[map]<reset> Destination name required\n"); return false
    end
    dest_name = string.lower(dest_name)
    local destinations = ensureDestinations()
    if not destinations[dest_name] then
        cecho(string.format("\n<red>[map]<reset> Destination '%s' not found\n", dest_name)); return false
    end
    destinations[dest_name] = nil
    f2t_save_settings()
    cecho(string.format("\n<green>[map]<reset> Destination '<yellow>%s<reset>' removed\n", dest_name))
    return true
end

function f2t_map_destination_list()
    local destinations = ensureDestinations()
    local count = 0
    for _ in pairs(destinations) do count = count + 1 end
    if count == 0 then
        cecho("\n<dim_grey>[map]<reset> No saved destinations\n")
        cecho("\n<dim_grey>Use 'map dest add <name>' to save a destination<reset>\n"); return
    end
    local sorted_names = {}
    for name in pairs(destinations) do table.insert(sorted_names, name) end
    table.sort(sorted_names)
    cecho(string.format("\n<green>[map]<reset> Saved Destinations (%d):\n", count))
    for _, name in ipairs(sorted_names) do
        local hash = destinations[name]
        local room_id = f2t_map_get_room_by_hash(hash)
        if room_id then
            cecho(string.format("  <yellow>%-20s<reset> → <cyan>%s<reset> <dim_grey>(%s)<reset>\n",
                name, getRoomName(room_id), hash))
        else
            cecho(string.format("  <yellow>%-20s<reset> → <red>Not mapped<reset> <dim_grey>(%s)<reset>\n", name, hash))
        end
    end
end

function f2t_map_destination_get(dest_name)
    if not dest_name or dest_name == "" then return nil end
    dest_name = string.lower(dest_name)
    return ensureDestinations()[dest_name]
end

function f2t_map_count_destinations()
    local count = 0
    for _ in pairs(ensureDestinations()) do count = count + 1 end
    return count
end
