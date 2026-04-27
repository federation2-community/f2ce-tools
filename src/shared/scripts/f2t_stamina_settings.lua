-- Stamina monitoring settings registration
-- Registers stamina-related settings with the settings manager
-- threshold = 0 means disabled, threshold > 0 means enabled at that percentage

f2t_settings_register("shared", "stamina_threshold", {
    description = "Stamina threshold to trigger food buying (0=disabled, 1-99=trigger at this %)",
    default = 25,
    min = 0, max = 99,
    validator = function(value)
        local num = tonumber(value)
        if not num or num < 0 or num > 99 then
            return false, "Must be a number between 0 and 99"
        end
        return true
    end
})

f2t_settings_register("shared", "food_source", {
    description = "Food source location: Fed2 room hash (system.planet.num) or saved destination name",
    default = "Sol.Earth.454",
    validator = function(value)
        if type(value) ~= "string" then
            return false, "Food source must be a string"
        end
        if value == "" then
            return false, "Food source cannot be empty"
        end
        -- Accept either Fed2 hash format OR any destination name
        -- Hash format: system.planet.num (e.g., Sol.Earth.454)
        -- Destination: any non-empty string (e.g., "earth", "Sol Exchange")
        return true
    end
})

f2t_settings_register("shared", "safe_room", {
    description = "Safe room location for automation to return to on failure, completion, or pause",
    default = "Sol.Earth.454",
    validator = function(value)
        if type(value) ~= "string" then
            return false, "Safe room must be a string"
        end
        if value == "" then
            return false, "Safe room cannot be empty"
        end
        -- Accept either Fed2 hash format OR any destination name
        -- Hash format: system.planet.num (e.g., Sol.Earth.454)
        -- Destination: any non-empty string (e.g., "earth", "Sol Exchange")
        return true
    end
})

f2t_debug_log("[stamina] Settings registered")
