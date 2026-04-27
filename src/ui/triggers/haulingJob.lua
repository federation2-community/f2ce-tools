-- @patterns:
--   - pattern: ^\s+(\d+)\.\s+From\s+(.+?)\s+to\s+(.+?)\s+-\s+\d+\s+tons\s+of\s+\S+\s+-\s+(\d+)gtu\s+(\d+)ig
--     type: regex

ui_on_hauling_job(matches[2], matches[3], matches[4], matches[5], matches[6])
deleteLine()