-- @patterns:
--   - pattern:  has promoted to
--     type: substring
--   - pattern:  has gained promotion to 
--     type: substring
--   - pattern:  has reached Trader rank!
--     type: substring
--   - pattern:  has been acclaimed as Founder of 
--     type: substring
--   - pattern:  and has promoted to Industrialist!
--     type: substring
--   - pattern:  has been elevated to the ranks of the plutocracy!
--     type: substring
--   - pattern:  has joined the Galactic Trading Guild and become a Merchant!
--     type: substring
--   - pattern:  has earned membership in the Adventurer's Guild and become an 
--     type: substring

UI.general_window:cecho(matches[1])
tempLineTrigger(0, 2, [[deleteLine()]]) --delete the current line and the next line, to catch the newline after every SPYNET REPORT