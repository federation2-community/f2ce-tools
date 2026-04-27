# Hauling Component

Automated hauling that adapts based on player rank:
- **Groundhog (level 1)**: No hauling available (must reach Commander)
- **Commander, Captain (levels 2-3)**: Armstrong Cuthbert jobs (hauling contracts)
- **Adventurer/Adventuress (level 4)**: Akaturi contracts (courier missions)
- **Merchant to Financier (levels 5-9)**: Exchange trading (buy low, sell high)
- **Founder+ (level 10+)**: Planet Owner trading (default), Exchange trading (optional override)

## Features

### Planet Owner Trading (Founder+)
- Scans current system for planets and verifies ownership via GMCP (once at startup)
- Captures exchange data remotely for all planets (no navigation needed)
- Identifies production deficits and excesses using configurable thresholds:
  - Deficits: stock at or below `po_deficit_threshold` (default -525)
  - Excesses: stock at or above `po_excess_threshold` (default 20000)
- Deficit lot count adapts to actual shortage (up to 7 lots)
- Resolves sources/destinations: owned planets first, then cartel price check
- Prevents buying from and selling to the same planet
- Ships >= 14 lots can bundle 2 jobs with same sell destination per trip
- After each sell, re-scans exchanges remotely for new deficits (priority insertion)
- Partial sell retry: tries up to `po_max_sell_attempts` exchanges (default 3)
- Tracks deficit and excess cycle counts separately
- Continuous loop: scan → queue → execute → re-check → cycle pause → re-scan
- Immediately stops on game shutdown warning
- Use `haul start exchange` to force exchange mode instead

### Exchange Trading (Merchant to Financier)
- Automatically identifies most profitable commodity
- Navigates to best buy/sell locations
- Uses bulk buy/sell to maximize efficiency
- Tracks cycle count and profitability
- Monitors merchant points progress (at Merchant rank)
- Notifies when 800 points reached (ready for Trader rank)
- Continues hauling - doesn't auto-stop at milestone

### Armstrong Cuthbert Jobs (Commander, Captain)
- Fetches available hauling jobs automatically
- Selects jobs based on hauling credits, payment, and location
- Navigates to pickup and delivery locations
- Tracks hauling credits and progress milestones (50, 500 credits)
- Automatically stops at 500 credits (ready for rank advancement)

### Akaturi Contracts (Adventurer)
- Accepts courier missions from Armstrong Cuthbert
- Automatically searches map for pickup and delivery rooms
- Tries multiple room matches if exact name isn't unique
- Pauses for manual room finding when automated search fails
- Tracks Akaturi points progress (25 contracts to complete)
- Automatically stops at 25 points (ready for rank advancement)

### Common
- Supports pause/resume/stop controls with **deferred pause** (completes current operation before pausing)
- Rank-aware: automatically detects and uses appropriate mode for your rank

## Commands

### Start/Stop
```
haul start            # Begin automated trading (auto-detects mode by rank)
haul start exchange   # Force exchange mode (Founder+ only)
haul stop             # Stop and reset state
```

### Pause/Resume
```
haul pause     # Deferred pause: completes current operation, pauses at next phase boundary
haul resume    # Continue from pause (or cancel pending pause request)
haul terminate # Immediate stop (does not wait for current operation)
```

**Deferred Pause:** When you run `haul pause` (or stamina monitor triggers), the system sets a `pause_requested` flag instead of immediately pausing. Async callbacks continue running (their guards check `paused`, which is still false). At the next phase boundary (`f2t_hauling_transition()` or mode-specific boundary functions), the request converts to actual `paused = true`. This prevents broken async chains and wasted re-scanning on resume.

**Stamina Monitor Pause:** The stamina monitor also uses deferred pause. After requesting pause, it waits (polls `check_active()`) until the current operation completes and hauling actually pauses. Only then does it take over navigation to the food source.

**Immediate Pause:** The `immediate` parameter on `f2t_hauling_pause(true)` is reserved for system-initiated pauses that need to stop immediately (e.g., Akaturi mode's "manual room finding" when no room match is found).

**Status shows:** `RUNNING`, `PAUSING...` (deferred pending), or `PAUSED`.

### Status
```
haul status    # Show current state
```

### Settings
```
haul settings                           # List all settings
haul settings get <name>                # Get specific setting
haul settings set <name> <value>        # Set setting value
haul settings clear <name>              # Reset to default

# Available settings:
# - margin_threshold (0-100): Minimum profit margin % to continue trading
# - cycle_pause (0-300): Seconds to pause after completing all 5 commodities
# - use_safe_room (boolean): Return to safe room on completion, failure, or cycle pause
# - excluded_commodities (string): Comma-separated list of commodities to exclude from trading
# - po_mode (both|deficit): PO hauling mode
# - po_deficit_threshold (-525 to -75): Stock level to trigger deficit hauling
# - po_excess_threshold (750-20000): Stock level to trigger excess selling
# - po_max_sell_attempts (1-10): Max sell locations before jettisoning
```

**Examples:**
```
haul settings set margin_threshold 25   # Require 25% profit margin
haul settings get margin_threshold      # View current threshold
haul settings clear margin_threshold    # Reset to default (40%)

haul settings set cycle_pause 120       # Pause 120s after trading 5 commodities
haul settings clear cycle_pause         # Reset to default (60s)

haul settings set use_safe_room true    # Enable safe room navigation
f2t settings set safe_room "earth"      # Set safe room destination

haul settings set excluded_commodities "alloys,cereals"  # Exclude specific commodities
haul settings clear excluded_commodities                 # Clear exclusion list

haul settings set po_deficit_threshold -375   # Trigger deficit at 5 lots short (instead of 7)
haul settings set po_excess_threshold 3000    # Trigger excess at 3000+ tons
haul settings set po_max_sell_attempts 5      # Try up to 5 sell locations before jettison
```

## How It Works

The hauling system automatically detects your rank on startup and uses the appropriate workflow. Founder+ defaults to PO mode but can override with `haul start exchange`.

### Planet Owner Trading Cycle (Founder+)

1. **Scan System**: Use `f2t_map_di_system_capture_start()` to get planet names, verify ownership via GMCP
2. **Scan Exchanges**: Remotely capture exchange data for all planets using `f2t_po_capture_exchange(planet)`
4. **Build Queue**: Find deficits (stock == -525) and excesses (stock == max)
5. **Resolve Sources**: Check owned planets first, fall back to `f2t_price_check_commodity()` for cartel
6. **Bundle**: For 14-lot ships, pair jobs with same sell destination
7. **Execute Jobs**: Navigate → buy 7 lots → navigate → sell all (deficits first)
8. **Re-check Deficits**: After each sell, re-scan exchanges remotely. New deficits inserted at front of queue
9. **Cycle**: When queue exhausted, cycle_pause then restart from step 1

### Exchange Trading Cycle (Merchant to Financier)

1. **Analyze**: Use `f2t_price_get_all_data()` to find most profitable commodity
2. **Navigate to Buy**: Use `f2t_map_navigate()` to go to best selling exchange
3. **Buy**: Use `f2t_bulk_buy_start()` to fill hold with commodity
4. **Navigate to Sell**: Use `f2t_map_navigate()` to go to best buying exchange
5. **Sell**: Use `f2t_bulk_sell_start()` to sell all cargo
6. **Repeat**: Start next cycle

### Armstrong Cuthbert Job Cycle (Commander, Captain)

1. **Fetch Jobs**: Send `work` command and parse available jobs
2. **Select Job**: Choose best job based on hauling credits, payment, location, and ship capacity
3. **Navigate to Source**: Travel to AC room at source planet
4. **Accept Job**: Use `ac <job_number>` to accept the job
5. **Collect Cargo**: Use `collect` command to load cargo
6. **Navigate to Destination**: Travel to AC room at destination planet
7. **Deliver Cargo**: Use `deliver` command to complete job
8. **Repeat**: Fetch new jobs and continue
9. **Stop at 500 credits**: Automatically stops when reaching rank advancement threshold

### Akaturi Contract Cycle (Adventurer)

1. **Get Job**: Navigate to AC room if needed, send `ak` command to get contract
2. **Parse Pickup**: Extract pickup planet and room name from job assignment
3. **Search Pickup**: Use `f2t_map_search()` to find exact room matches
4. **Navigate Pickup**: Travel to pickup room (try multiple matches if needed)
5. **Collect Package**: Use `pickup` command, parse delivery location
6. **Search Delivery**: Use `f2t_map_search()` to find delivery room
7. **Navigate Delivery**: Travel to delivery room (try multiple matches if needed)
8. **Deliver Package**: Use `dropoff` command to complete contract
9. **Repeat**: Get new contract and continue
10. **Stop at 25 points**: Automatically stops when reaching rank advancement threshold

**Room Matching Strategy**:
- If no exact match found → Navigate to planet, pause for manual room finding
- If one exact match → Navigate directly to that room
- If multiple exact matches → Try each sequentially until success
- On wrong room error → Try next match or pause if no more matches

### State Machine

The hauling automation uses a state machine with rank-specific phases:

**Planet Owner Phases**:
- **po_scanning_system**: Getting planet list via `di system`
- **po_scanning_exchanges**: Remotely capturing exchange data for all planets (no navigation)
- **po_building_queue**: Finding deficits/excesses, resolving sources, bundling
- **po_navigating_to_buy**: Traveling to buy location
- **po_buying**: Buying 7 lots (or bundled buy)
- **po_navigating_to_bundled_buy**: Traveling to second source for bundled jobs
- **po_navigating_to_sell**: Traveling to sell location
- **po_selling**: Selling all cargo
- **po_checking_deficits**: Remote re-scan for new deficits after sell

**Exchange Trading Phases**:
- **analyzing**: Finding most profitable commodity and locations
- **navigating_to_buy**: Traveling to purchase location
- **buying**: Purchasing commodity to fill hold
- **navigating_to_sell**: Traveling to sell location
- **selling**: Selling cargo

**Armstrong Cuthbert Phases**:
- **ac_fetching_jobs**: Getting list of available jobs
- **ac_selecting_job**: Choosing best job for ship
- **ac_navigating_to_source**: Traveling to pickup location
- **ac_accepting_job**: Accepting the job contract
- **ac_collecting**: Collecting cargo from AC room
- **ac_navigating_to_dest**: Traveling to delivery location
- **ac_delivering**: Delivering cargo to complete job

**Akaturi Contract Phases**:
- **akaturi_getting_job**: Navigate to AC room and request contract
- **akaturi_parsing_pickup**: Parse pickup planet and room from assignment
- **akaturi_searching_pickup**: Search map for pickup room matches
- **akaturi_navigating_pickup**: Travel to pickup location
- **akaturi_collecting**: Pick up package and parse delivery info
- **akaturi_searching_delivery**: Search map for delivery room matches
- **akaturi_navigating_delivery**: Travel to delivery location
- **akaturi_delivering**: Deliver package and complete contract

State transitions happen automatically, or can be paused/resumed manually.

### Integration Points

**Commodities Component**:
- `f2t_price_get_all_data(callback)` - Get profitability analysis
- `f2t_price_check_commodity(commodity, callback)` - Get specific buy/sell locations

**Map Component**:
- `f2t_map_navigate(destination)` - Navigate to planet

**Bulk Commands** (Exchange Trading):
- `f2t_bulk_buy_start(commodity, lots)` - Buy commodity (nil = fill hold)
- `f2t_bulk_sell_start(commodity, lots)` - Sell commodity (nil = sell all)

**Shared Utilities**:
- `f2t_get_rank()` - Get current player rank
- `f2t_get_rank_level(rank)` - Get numeric level for rank comparison
- `f2t_is_rank_below(rank)` - Check if below specific rank

**Mode Detection** ([mode_detection.lua](scripts/hauling_mode_detection.lua)):
- `f2t_hauling_detect_mode(requested_mode)` - Determine hauling mode based on rank (returns "ac", "akaturi", "exchange", "po", or nil)
- `f2t_hauling_get_mode_name(mode)` - Get display name for mode
- `f2t_hauling_get_starting_phase(mode)` - Get initial phase for mode

**Armstrong Cuthbert Module** ([armstrong_cuthbert.lua](scripts/armstrong_cuthbert.lua)):
- `f2t_ac_get_hauling_credits()` - Get current hauling credits from GMCP
- `f2t_ac_parse_job_line(line)` - Parse work command output line
- `f2t_ac_select_best_job(jobs, current_planet, capacity)` - Select optimal job
- `f2t_ac_get_room_hash(planet)` - Get Fed2 hash for AC room
- `f2t_ac_at_room()` - Check if currently at AC room

**Akaturi Module** ([hauling_akaturi.lua](scripts/hauling_akaturi.lua)):
- `f2t_akaturi_get_points()` - Get current Akaturi points from GMCP
- `f2t_akaturi_is_complete()` - Check if 25 contracts complete
- `f2t_akaturi_parse_job(lines)` - Parse job assignment for pickup location
- `f2t_akaturi_parse_pickup(lines)` - Parse pickup confirmation for delivery location
- `f2t_akaturi_search_room(planet, room_title, callback)` - Search map for exact room match
- `f2t_akaturi_get_next_match(matches)` - Get next room match to try
- `f2t_akaturi_reset_contract()` - Reset contract state for new job

## Key Files

**Scripts**:
- `init.lua` - Initialization, settings, state structure
- `hauling_mode_detection.lua` - Centralized mode selection based on rank
- `hauling_state_machine.lua` - State management, start/stop/pause/resume, phase dispatcher
- `hauling_exchange_phases.lua` - Exchange trading phases + event handlers
- `hauling_ac_phases.lua` - Armstrong Cuthbert job phases + event handlers
- `hauling_armstrong_cuthbert.lua` - AC job data structures and helper functions
- `hauling_ac_capture_timer.lua` - AC work command capture timer
- `hauling_akaturi_phases.lua` - Akaturi contract phases + event handlers
- `hauling_akaturi.lua` - Akaturi contract data structures and helper functions
- `hauling_po_discovery.lua` - PO system scanning and ownership verification
- `hauling_po_queue.lua` - PO deficit/excess detection, resolution, and bundling
- `hauling_po_phases.lua` - PO phase implementations and event handlers

**Aliases**:
- `haul.lua` - Consolidated alias for all subcommands

**Triggers**:
- `ac_work_start.lua` - Capture start of work command output
- `ac_work_line.lua` - Capture individual job listings
- `ac_job_taken.lua` - Handle job unavailability errors
- `ac_collect_success.lua` - Detect successful cargo collection
- `ac_collect_errors.lua` - Handle collection errors
- `ac_deliver_success.lua` - Detect successful delivery
- `ac_deliver_error.lua` - Handle delivery errors
- `hauling_akaturi_job_start.lua` - Detect job assignment header
- `hauling_akaturi_job_line.lua` - Capture job assignment lines
- `hauling_akaturi_job_complete.lua` - Detect job output completion
- `hauling_akaturi_job_error.lua` - Handle ak command errors
- `hauling_akaturi_pickup_success.lua` - Detect successful package pickup
- `hauling_akaturi_pickup_line.lua` - Capture delivery information
- `hauling_akaturi_pickup_error.lua` - Handle pickup errors
- `hauling_akaturi_dropoff_success.lua` - Detect successful delivery
- `hauling_akaturi_payment.lua` - Capture payment amount
- `hauling_akaturi_dropoff_error.lua` - Handle delivery errors

## State Structure

```lua
F2T_HAULING_STATE = {
    -- Common
    active = false,                 -- Whether hauling is running
    paused = false,                 -- Whether hauling is paused
    pause_requested = false,        -- Deferred pause: set by user, converted to paused at next phase boundary
    mode = nil,                     -- Current mode: "ac", "akaturi", "exchange"
    current_phase = nil,            -- Current phase name
    handler_id = nil,               -- GMCP event handler ID for current mode
    total_cycles = 0,               -- Total cycles completed
    session_profit = 0,             -- Total profit this session
    commodity_history = {},         -- History of traded commodities

    -- Exchange Trading (Merchant+)
    current_commodity = nil,        -- Selected commodity
    buy_location = {                -- Where to buy
        system = "...",
        planet = "...",
        price = 0
    },
    sell_location = {               -- Where to sell
        system = "...",
        planet = "...",
        price = 0
    },
    expected_profit = 0,            -- Expected profit per ton
    actual_cost = 0,                -- What we actually paid per ton
    margin_threshold_pct = 40,      -- Minimum acceptable profit margin
    commodity_total_profit = 0,     -- Accumulated profit across all cycles of current commodity
    sell_attempts = 0,              -- Number of sell locations tried
    dump_attempts = 0,              -- Number of dump locations tried

    -- Armstrong Cuthbert Jobs (Commander, Captain)
    ac_job = {                      -- Currently selected job
        number = 0,
        source = "...",
        destination = "...",
        tons = 75,
        commodity = "...",
        time_allowed_gtu = 0,
        payment_per_ton = 0,
        hauling_credits = 0
    },
    ac_job_taken = false,           -- Job was taken by someone else
    ac_cargo_collected = false,     -- Cargo collection complete
    ac_cargo_delivered = false,     -- Cargo delivery complete
    ac_collect_error = nil,         -- Collection error message
    ac_deliver_error = nil,         -- Delivery error message
    ac_50_milestone_shown = false,  -- Whether 50 credit message shown

    -- Akaturi Contracts (Adventurer)
    akaturi_contract = {            -- Currently selected contract
        pickup_planet = "...",
        pickup_room = "...",
        delivery_planet = "...",
        delivery_room = "...",
        item = "..."
    },
    akaturi_package_collected = false,  -- Package pickup complete
    akaturi_package_delivered = false,  -- Package delivery complete
    akaturi_pickup_error = false,       -- Pickup error occurred
    akaturi_delivery_error = false,     -- Delivery error occurred
    akaturi_pickup_sent = false,        -- Pickup command sent (prevent duplicates)
    akaturi_delivery_sent = false,      -- Dropoff command sent (prevent duplicates)
    akaturi_payment_amount = nil,       -- Payment received for contract

    -- Planet Owner Trading (Founder+)
    po_owned_planets = {},              -- Array of owned planet names
    po_current_system = nil,            -- System being operated in
    po_planet_exchange_data = {},       -- {[planet_name] = exchange_data_array}
    po_job_queue = {},                  -- Array of resolved job objects
    po_job_index = 1,                   -- Current position in queue
    po_current_job = nil,               -- Currently executing job
    po_ship_lots = 0,                   -- Ship capacity in lots (hold.max / 75)
    po_scan_count = 0,                  -- Full scan iterations completed
    po_deficit_count = 0,               -- Deficits found in last scan
    po_excess_count = 0,                -- Excesses found in last scan
    po_scan_planets = {},               -- Planets to scan during exchange scan
    po_deficit_cycles = 0,              -- Deficit cycles completed this session
    po_excess_cycles = 0,               -- Excess cycles completed this session

    -- Shutdown timer
}
```

**Armstrong Cuthbert Room Locations**:
```lua
F2T_AC_ROOMS = {
    ["Earth"] = "Sol.Earth.519",
    ["Selena"] = "Sol.Selena.524",
    -- ... (17 total Sol planets)
}
```

## Future Enhancements

### Event-Driven Completion Detection

The hauling system uses event handlers instead of fixed timers:

**GMCP Room Handler**: Monitors `gmcp.room.info` events to detect navigation completion
- Fires when speedwalk completes and room changes
- Automatically transitions to buy or sell phase

**Completion Timer**: Polls every 0.3 seconds to check operation status
- Monitors `F2T_SPEEDWALK_ACTIVE` for navigation
- Monitors `F2T_BULK_STATE.active` for buy/sell operations
- Monitors `gmcp.char.ship.cargo` for cargo verification

**Partial Sell Handling**: Automatically finds next sell location
- Checks cargo after sell completes
- If cargo remains, increments `sell_attempts` counter
- Fetches fresh prices and navigates to next best exchange
- Stops after 3 failed sell attempts to prevent loops

**Cargo Validation**: Verifies operations succeeded
- After buy: Checks that cargo was loaded
- After sell: Checks if cargo remains (partial sell scenario)
- Stops hauling if buy fails completely

### Current Limitations

1. **Price Re-validation**: Doesn't re-check prices between cycles
   - Should verify profit margin hasn't eroded
   - Should detect when commodity is no longer profitable

2. **Exchange Errors**: Minimal handling
   - Should detect exchange unavailability
   - Should handle insufficient funds
   - Should skip exchanges that error out

3. **Hold Optimization**: Doesn't check if buy filled hold
   - Should verify hold is actually full after buy
   - Should adjust strategy if buy was partial

### Armstrong Cuthbert Implementation

**Rank Detection**: Uses `f2t_is_rank_below("Merchant")` to determine if player should use AC jobs

**Job Selection Priority**:
1. Highest hauling credits reward
2. Highest payment per ton
3. Current location match (already at source)
4. Ship capacity fit

**Milestones**:
- **50 credits**: Message shown about player-operated planet opportunities (but continues in Sol)
- **500 credits**: Automation stops with congratulations message (ready for rank advancement)

**Error Handling**:
- Job taken by another player: Retry by fetching new jobs
- Collection errors: Abort and fetch new jobs
- Delivery errors: Abort and fetch new jobs
- No suitable jobs: Wait 10 seconds and retry
- Duplicate command prevention: Guard flags prevent re-sending collect/deliver commands

**Navigation Handling**:
- Uses static Fed2 hash table for 17 AC room locations in Sol system
- Double-verification: When map component returns "already at destination", verifies actual planet matches before proceeding
- Prevents premature phase transitions when map data is stale or incorrect
- **Navigation ownership**: Sets owner to "hauling" with interrupt callback for customs/out-of-fuel handling
- **Defers to speedwalk for retry logic**: Checks `F2T_SPEEDWALK_LAST_RESULT` to determine outcome:
  - `"completed"` → Verify location and continue to next phase
  - `"stopped"` → User manually stopped navigation, stop hauling
  - `"failed"` → Path blocked after speedwalk retries, skip job and fetch new ones
- **No redundant retries**: If speedwalk can't reach destination after 3 attempts with path recomputation, hauling trusts that decision and moves on
- **Single source of truth**: Speedwalk is the navigation expert, hauling doesn't second-guess it

**See also**: `src/map/CLAUDE.md` "Navigation Ownership Model" for interrupt handling pattern

### Planned Features

1. ~~**Planet Owner Hauling** (Founder+ rank)~~ ✓ Implemented
   - ~~Transfer commodities between owned planets~~
   - ~~Optimize factory supply chains~~

3. **Multi-Commodity Strategy**
   - Trade multiple commodities per cycle
   - Fill hold with best combination of goods

4. **Route Optimization**
   - Calculate optimal buy/sell routes
   - Minimize jumps and travel time

5. **Profit Tracking**
   - Log revenue per cycle
   - Calculate total earnings
   - Display profit statistics

## Settings

**Registered Settings:**

- `margin_threshold` (number, 0-100, default: `40`) - Minimum profit margin % to continue trading a commodity
- `cycle_pause` (number, 0-300, default: `60`) - Seconds to pause after completing all 5 commodities (0 = no pause)
- `use_safe_room` (boolean, default: `false`) - Return to safe room on completion, failure, or cycle pause
- `excluded_commodities` (string, default: `""`) - Comma-separated list of commodities to exclude from trading
- `po_mode` (string, default: `"both"`) - PO hauling mode: 'both' (deficit + excess) or 'deficit' (deficit only)
- `po_deficit_threshold` (number, -525 to -75, default: `-525`) - Stock level at or below which deficit hauling triggers
- `po_excess_threshold` (number, 750-20000, default: `20000`) - Stock level at or above which excess selling triggers
- `po_max_sell_attempts` (number, 1-10, default: `3`) - Maximum sell locations to try before jettisoning cargo

**Safe Room Integration:**

When `use_safe_room` is enabled, hauling will navigate to the configured safe room (set via `f2t settings set safe_room <destination>`) in the following scenarios:

1. **On Completion**: When hauling stops normally, it will return to safe room before showing final statistics
2. **On Failure**: When hauling encounters an error and must stop, it will return to safe room
3. **On Cycle Pause**: When all 5 commodities have been traded and `cycle_pause` is set, hauling will:
   - Navigate to safe room
   - Wait for the configured pause duration
   - Return to the previous location
   - Resume by re-analyzing market prices

**Commodity Exclusion:**

Use `excluded_commodities` to prevent trading specific commodities:

- **Format**: Comma-separated list (case-insensitive)
- **Example**: `haul settings set excluded_commodities "alloys,cereals,nanofabrics"`
- **Applies**: During analysis phase (affects next cycle, not mid-cycle)
- **Works alongside**: Profitability and margin threshold checks
- **Empty entries**: Trimmed and ignored (e.g., `"alloys,,cereals"` → `["alloys", "cereals"]`)
- **Invalid names**: Silently ignored (no effect if commodity doesn't exist)

**Use cases:**
- Avoid commodities with volatile pricing
- Skip commodities you're saving for other purposes
- Exclude commodities that tend to have blocked trade routes

**Access via:**

```lua
-- Get setting values
local threshold = f2t_settings_get("hauling", "margin_threshold")
local pause = f2t_settings_get("hauling", "cycle_pause")
local use_safe_room = f2t_settings_get("hauling", "use_safe_room")
local excluded = f2t_settings_get("hauling", "excluded_commodities")

-- Set setting values (with validation)
local success, err = f2t_settings_set("hauling", "margin_threshold", 25)
local success, err = f2t_settings_set("hauling", "cycle_pause", 60)
local success, err = f2t_settings_set("hauling", "use_safe_room", true)
local success, err = f2t_settings_set("hauling", "excluded_commodities", "alloys,cereals")

-- Clear settings (revert to defaults)
f2t_settings_clear("hauling", "margin_threshold")
f2t_settings_clear("hauling", "cycle_pause")
f2t_settings_clear("hauling", "use_safe_room")
f2t_settings_clear("hauling", "excluded_commodities")
```

**User commands:**
```
haul settings                           # List all settings
haul settings get margin_threshold      # Get specific setting
haul settings set margin_threshold 25   # Set setting value
haul settings set cycle_pause 60        # Pause 60s after 5 commodities
haul settings set use_safe_room true    # Enable safe room navigation
haul settings set excluded_commodities "alloys,cereals"  # Exclude commodities
haul settings clear margin_threshold    # Reset to default
haul settings clear excluded_commodities  # Clear exclusion list

# Configure safe room destination (shared setting)
f2t settings set safe_room "earth"      # Set safe room to Earth
f2t settings set safe_room "Sol.Earth.454"  # Or use Fed2 room hash
```

**Note:** Hauling doesn't have an `enabled` setting - it's enabled when you run `haul start` and disabled when you run `haul stop` or `haul terminate`.

Settings are persisted via `f2t_save_settings()`, auto-loaded on startup.

## Debug Logging

```
f2t debug on
```

Output includes:
- Phase transitions
- Commodity selection
- Navigation destinations
- Buy/sell operations
- Cycle completion

## Safety Notes

- **Monitor your ship**: Automation uses navigation and can take you anywhere
- **Check your funds**: Buying commodities requires capital
- **Start small**: Test with pause/resume before long runs
- **Use stop liberally**: Stop immediately if something goes wrong

## Lessons Learned

### AC Work Capture Timer Race Condition

**Problem:** Work output occasionally not captured, leading to "No AC jobs available" message despite jobs being visible in game output. Issue became more frequent after first occurrence.

**Root Cause:** Timer-based capture starting too early, racing against network latency:

1. `f2t_hauling_phase_ac_fetch_jobs()` starts timer immediately after sending `work` command
2. Network latency: command → server → response takes variable time (typically 100-500ms)
3. If latency + header arrival > 500ms, timer fires before first job line captured
4. Capture stops with empty jobs array
5. User sees "No AC jobs available, retrying in 10 seconds..."
6. Actual work output arrives but capture is already stopped

**Why It Got Worse:** After first timeout, system retries every 10 seconds. Each retry with high latency has same race condition.

**Solution:** Make the work start trigger reset the timer when header arrives:

```lua
-- In hauling_ac_work_start.lua
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    deleteLine()
    f2t_debug_log("[hauling/ac] Work output header detected")

    -- Reset timer to prevent premature timeout
    f2t_ac_reset_capture_timer()
end
```

**Key Insight:** For timer-based capture with multi-part output (header + data lines), ALL triggers that fire during capture should reset the timer, not just data line triggers. This prevents race conditions when network latency varies.

**Pattern:** When using Pattern 2 (Timer-Based Capture) with a known start marker:
1. ✅ Start timer immediately (responsive if output never arrives)
2. ✅ Reset timer when start marker arrives (prevents premature firing)
3. ✅ Reset timer on each data line (extends deadline)
4. ✅ Timer fires 0.5s after last line (correct completion)

### Fed2 Prompt Trigger Unreliability

**Problem:** Akaturi job assignment capture occasionally failed to complete, leading to "Failed to parse pickup location from job output" despite the output being received.

**Root Cause:** Fed2 doesn't reliably send prompts that Mudlet can detect with prompt triggers.

**Evidence:**
- `hauling_akaturi_job_complete.lua` originally used prompt trigger (`type: prompt`) to detect capture completion
- This worked *sometimes* but not consistently
- When prompt trigger didn't fire, capture never completed
- Parsing phase never triggered, leading to retry loop

**Solution:** Use explicit end marker instead:

```lua
-- File: hauling_akaturi_job_end_marker.lua
-- @pattern: ^Delivery details will be provided when you collect the package\.$

if f2t_akaturi_is_capturing_job() then
    f2t_akaturi_add_job_line(line)
    f2t_debug_log("[hauling/akaturi] Job output end marker detected")

    -- Trigger parsing immediately
    tempTimer(0.1, function()
        f2t_hauling_phase_akaturi_parse_pickup()
    end)
end
```

**CRITICAL RULE: NEVER USE PROMPT TRIGGERS IN FED2**

Fed2 doesn't reliably send prompts that Mudlet can detect. Prompt triggers are fundamentally unreliable.

**Use these alternatives instead:**

- ✅ **BEST**: Explicit end marker (specific text pattern from game output)
- ✅ **ACCEPTABLE**: Timer-based completion (0.5s of silence = done)
- ❌ **NEVER**: Prompt triggers (`type: prompt`)

**Pattern for Fed2 Capture:**
1. ✅ Use specific text pattern from game output as end marker
2. ✅ If no specific end marker exists, use timer-based completion
3. ❌ Never use prompt triggers, not even as a backup
4. ❌ Don't assume prompts work in Fed2 - they don't
