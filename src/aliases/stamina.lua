-- f2ce-tools — stamina command

local args = matches[2] or ""

if f2t_handle_help("stamina", args) then return end

local subcommand = string.lower(args):match("^(%S+)") or "status"

local function showStatus()
    local vitals = gmcp.char and gmcp.char.vitals and gmcp.char.vitals.stamina
    local current, maximum = vitals and tonumber(vitals.cur), vitals and tonumber(vitals.max)
    local limit = tonumber(f2t_settings_get("stamina", "threshold")) or 0
    local foodKey, food = f2tStaminaFoodType()

    cecho("\n<green>[stamina]<reset>")
    if current and maximum and maximum > 0 then
        cecho(string.format(" <white>%d/%d<reset> (%d%%)", current, maximum, math.floor(current / maximum * 100)))
    end
    cecho("\n")
    cecho(string.format("  Auto-eat:   %s\n", limit > 0
        and string.format("at or below <cyan>%d%%<reset>", limit) or "<yellow>off<reset> (threshold 0)"))
    local _, sourceName = f2tStaminaResolveFoodSource()
    cecho(string.format("  Eats at:    <cyan>%s<reset> <dim_grey>(food_source: %s)<reset>\n",
        sourceName, f2t_settings_get("stamina", "food_source") or "nearest"))
    cecho(string.format("  Sustenance: <cyan>%s<reset> <dim_grey>(%s)<reset>\n", foodKey, food.desc))
    if f2tStaminaTripActive() then
        cecho(string.format("  Food run:   <yellow>%s<reset> <dim_grey>(stamina cancel to stop)<reset>\n",
            f2tStaminaPhaseText()))
    end
end

if subcommand == "status" then
    showStatus()

elseif subcommand == "eat" then
    f2tStaminaEat()

elseif subcommand == "cancel" or subcommand == "stop" or subcommand == "reset" then
    if not f2tStaminaCancelTrip() then
        cecho("\n<dim_grey>[stamina]<reset> No food run under way\n")
    end

elseif subcommand == "settings" then
    f2t_handle_settings_command("stamina", args:match("^settings%s*(.*)") or "")

else
    cecho(string.format("\n<red>[stamina]<reset> Unknown command: %s\n", subcommand))
    f2t_show_help_hint("stamina")
end
