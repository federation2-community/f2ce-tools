-- @patterns:
--   - pattern: ^([\w\s]+): ([\w\s]+) is (buying|selling) (\d+) tons at (\d+)ig/ton$
--     type: regex

ui_on_trading_line(matches[2], matches[3], matches[4], matches[5], matches[6])
deleteLine()