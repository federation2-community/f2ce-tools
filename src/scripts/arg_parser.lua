-- f2ce-tools — argument parsing utilities (ported from shared/scripts/f2t_arg_parser.lua)

function f2t_parse_words(str)
    if not str or str == "" then return {} end
    local words = {}
    for word in string.gmatch(str, "%S+") do
        table.insert(words, word)
    end
    return words
end

function f2t_parse_subcommand(args, subcommand)
    local pattern = "^" .. subcommand .. "%s*(.*)$"
    return args:match(pattern)
end

function f2t_parse_rest(words, start_index)
    start_index = start_index or 1
    local rest = {}
    for i = start_index, #words do
        table.insert(rest, words[i])
    end
    return table.concat(rest, " ")
end

function f2t_parse_required_arg(words, index, component, usage_msg)
    if not words[index] then
        cecho(string.format("\n<red>[%s]<reset> %s\n", component, usage_msg))
        return nil
    end
    return words[index]
end

function f2t_parse_optional_number(words, index, default)
    local value = tonumber(words[index])
    return value or default
end

function f2t_parse_required_number(words, index, component, usage_msg)
    local value = tonumber(words[index])
    if not value then
        if words[index] then
            cecho(string.format("\n<red>[%s]<reset> '%s' is not a valid number\n", component, words[index]))
        end
        cecho(string.format("\n<red>[%s]<reset> %s\n", component, usage_msg))
        return nil
    end
    return value
end

function f2t_parse_choice(words, index, choices, component, default)
    local value = words[index] or default
    if not value then
        cecho(string.format("\n<red>[%s]<reset> Missing required argument\n", component))
        cecho(string.format("\n<dim_grey>Allowed values: %s<reset>\n", table.concat(choices, ", ")))
        return nil
    end
    for _, choice in ipairs(choices) do
        if value == choice then return value end
    end
    cecho(string.format("\n<red>[%s]<reset> Invalid value '%s'\n", component, value))
    cecho(string.format("\n<dim_grey>Allowed values: %s<reset>\n", table.concat(choices, ", ")))
    return nil
end
