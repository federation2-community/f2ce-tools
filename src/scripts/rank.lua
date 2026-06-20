-- fed2-tools — rank comparison utilities

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

function f2t_check_rank_requirement(requiredRank, featureName)
    if f2t_is_rank_or_above(requiredRank) then return true end
    local currentRank  = f2t_get_rank()
    local currentLevel = f2t_get_rank_level(currentRank)
    local requiredLevel = f2t_get_rank_level(requiredRank)
    cecho(string.format("\n<red>[fed2-tools]<reset> %s requires rank <cyan>%s<reset> or higher\n",
        featureName, requiredRank))
    if currentRank then
        cecho(string.format("<dim_grey>Your rank: <white>%s<reset> (level %d / %d)<reset>\n",
            currentRank, currentLevel or 0, requiredLevel or 0))
    end
    return false
end
