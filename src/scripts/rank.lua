-- f2ce-tools — rank comparison utilities

F2T_RANK_LEVELS = {
    groundhog    = 1,
    commander    = 2,
    captain      = 3,
    adventurer   = 4,
    adventuress  = 4,  -- gender variant, same level as adventurer
    merchant     = 5,
    trader       = 6,
    industrialist = 7,
    manufacturer = 8,
    financier    = 9,
    founder      = 10,
    engineer     = 11,
    mogul        = 12,
    technocrat   = 13,
    gengineer    = 14,
    magnate      = 15,
    plutocrat    = 16,
    syndicrat    = 17,
}

function f2t_get_rank()
    return gmcp.char and gmcp.char.vitals and gmcp.char.vitals.rank or nil
end

function f2t_get_rank_level(rankName)
    if not rankName then return nil end
    return F2T_RANK_LEVELS[string.lower(rankName)]
end

function f2t_is_rank_or_above(requiredRank)
    local currentRank = f2t_get_rank()
    if not currentRank then return false end
    local currentLevel  = f2t_get_rank_level(currentRank)
    local requiredLevel = f2t_get_rank_level(requiredRank)
    if not currentLevel or not requiredLevel then return false end
    return currentLevel >= requiredLevel
end

function f2t_is_rank_below(rankName)
    return not f2t_is_rank_or_above(rankName)
end

function f2t_is_rank_exactly(rankName)
    local currentRank = f2t_get_rank()
    if not currentRank then return false end
    local currentLevel = f2t_get_rank_level(currentRank)
    local targetLevel  = f2t_get_rank_level(rankName)
    if not currentLevel or not targetLevel then return false end
    return currentLevel == targetLevel
end

-- ── Rank → color (matches the game's own `ranks` command output exactly) ──────
-- Single source of truth: every UI surface (who list, local players, chat,
-- player card) derives its own format (hex / cecho triplet / rgba) from this
-- instead of keeping a private, drifting copy.
F2T_RANK_COLORS = {
    Groundhog     = "#800080",
    Commander     = "#800080",
    Captain       = "#000080",
    Adventurer    = "#000080",
    Adventuress   = "#000080",
    Merchant      = "#ffffff",
    Trader        = "#ffffff",
    Industrialist = "#008000",
    Manufacturer  = "#008000",
    Financier     = "#008000",
    Founder       = "#008080",
    Engineer      = "#008080",
    Mogul         = "#008080",
    Technocrat    = "#008080",
    Gengineer     = "#008080",
    Magnate       = "#008080",
    Plutocrat     = "#800000",
    Syndicrat     = "#808000",
}

function f2t_rank_color_hex(rankName)
    return rankName and F2T_RANK_COLORS[rankName] or nil
end

local function _hexToRgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- decho foreground tag ("<r,g,b>") for the same rank color. cecho only knows
-- named colors (and Mudlet's built-ins don't match the game's exact RGB
-- values), so exact-match rank coloring goes through decho instead.
function f2t_rank_color_decho(rankName)
    local hex = f2t_rank_color_hex(rankName)
    if not hex then return nil end
    return string.format("<%d,%d,%d>", _hexToRgb(hex))
end

-- CSS rgba() string for the same rank color, for stylesheet-driven widgets.
function f2t_rank_color_rgba(rankName, alpha)
    local hex = f2t_rank_color_hex(rankName)
    if not hex then return nil end
    local r, g, b = _hexToRgb(hex)
    return string.format("rgba(%d, %d, %d, %d)", r, g, b, alpha or 255)
end

function f2t_check_rank_requirement(requiredRank, featureName)
    if f2t_is_rank_or_above(requiredRank) then return true end
    local currentRank  = f2t_get_rank()
    local currentLevel = f2t_get_rank_level(currentRank)
    local requiredLevel = f2t_get_rank_level(requiredRank)
    cecho(string.format("\n<red>[f2ce-tools]<reset> %s requires rank <cyan>%s<reset> or higher\n",
        featureName, requiredRank))
    if currentRank then
        cecho(string.format("<dim_grey>Your rank: <white>%s<reset> (level %d / %d)<reset>\n",
            currentRank, currentLevel or 0, requiredLevel or 0))
    end
    return false
end
