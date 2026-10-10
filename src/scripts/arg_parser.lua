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
