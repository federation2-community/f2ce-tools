-- String utility functions

-- Strip ANSI/MUD color codes from a string
-- Handles formats like: %%bold%%, %%green%%, %%reset%%, etc.
function f2t_strip_color_codes(str)
    if not str then
        return ""
    end

    -- Remove all %%code%% patterns
    local cleaned = string.gsub(str, "%%%%[^%%]+%%%%", "")

    return cleaned
end

-- Clean a room name for display/storage
-- Removes color codes and trims whitespace
function f2t_clean_room_name(name)
    if not name then
        return ""
    end

    -- Strip color codes
    local cleaned = f2t_strip_color_codes(name)

    -- Trim leading/trailing whitespace
    cleaned = string.match(cleaned, "^%s*(.-)%s*$")

    return cleaned
end

function f2t_padding(str, len, dir)
    str = tostring(str)

    -- If the string is longer than the length, truncate characters without doing anything
    if #str > len then
        return str:sub(1, len)
    end

    if dir == "left" then
        return str .. string.rep(" ", len - #str)
    elseif dir == "right" then
        return string.rep(" ", len - #str) .. str
    elseif dir == "center" then
        local total_padding = len - #str
        local left_padding  = math.floor(total_padding / 2)
        local right_padding = total_padding - left_padding

        return string.rep(" ", left_padding) .. str .. string.rep(" ", right_padding)
    end
end