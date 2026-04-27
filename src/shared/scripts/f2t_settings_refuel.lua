-- Refuel settings registration
-- Registers refuel settings with the shared settings manager
-- threshold = 0 means disabled, threshold > 0 means enabled at that percentage

f2t_settings_register("shared", "refuel_threshold", {
    description = "Auto-refuel threshold (0=disabled, 1-99=refuel when at/below this %)",
    default = 50,
    min = 0, max = 99,
    validator = function(value)
        local num = tonumber(value)
        if not num or num < 0 or num > 99 then
            return false, "Must be a number between 0 and 99"
        end
        return true
    end
})

f2t_debug_log("[refuel] Settings registered")
