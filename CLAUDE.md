# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**📖 Quick Navigation:** See [CLAUDE_INDEX.md](CLAUDE_INDEX.md) for documentation index and [CLAUDE_PATTERNS.md](CLAUDE_PATTERNS.md) for common code patterns.

## ⚠️ MANDATORY WORKFLOW - READ THIS FIRST ⚠️

**BEFORE making ANY code changes, you MUST:**

1. **Check current branch** - Run `git branch` to see what branch you're on
2. **NEVER work directly on `main` or `develop`** - These are protected branches
3. **Create a feature branch** - See GitFlow workflow section below
4. **Commit regularly** - Don't make all changes in one giant commit
5. **Update documentation** - Changes and docs must be in the same commits

**If you find yourself editing files without having created a feature branch first, STOP immediately and create one.**

## ⚠️ CRITICAL: Before Deleting or Recreating Functions ⚠️

**MANDATORY: Check git history before recreating functions that don't exist:**

1. **If a function is called but not defined**, search git history FIRST:
   ```bash
   git log --all -S "function_name" --source --all
   git show <commit>:path/to/file.lua
   ```

2. **NEVER recreate from scratch if it existed before** - Restore from git history
3. **NEVER delete functions without understanding their purpose** - Search for usages: `grep -r "function_name" src/`
4. **Make minimal, targeted changes** - Don't refactor unless requested
5. **When in doubt, ask** - Unsure? ASK before making changes

## Project Overview

Mudlet tools collection for Federation 2 Community Edition (https://federation2.com). Component-based structure where each component is a separate tool/feature. Each trigger, script, alias, timer, and keybinding is a separate .lua file. PowerShell build script compiles these into a Mudlet package (.mpackage).

**Key Concept**: Components are independent tools that get their own folder in Mudlet.

## Project Structure

```
fed2-tools/
├── project.json          # Package metadata
├── build.ps1            # Build script
├── CLAUDE.md            # Project-level documentation
├── README.md            # User-facing documentation
├── src/                 # Source files by component
│   ├── component1/
│   │   ├── CLAUDE.md    # Component-specific docs
│   │   ├── aliases/     # .lua files
│   │   ├── triggers/
│   │   ├── scripts/
│   │   └── resources/   # JSON, images, etc.
│   └── component2/
└── build/               # Generated (gitignored)
```

## Naming Conventions

### Component and Command Naming

**f2t Prefix Rule**: Only use `f2t` prefix for **shared/system components** (meta-commands that control fed2-tools itself).

**Individual tool components** should NOT use `f2t` prefix:
- ✅ `factory status`, `refuel 80`, `bb alloys 5`
- ❌ `f2t factory status`, `f2t refuel`, `f2t bb`

**System commands** (use f2t prefix):
- `f2t debug on/off` - Controls debug mode
- `f2t settings` - Manage shared/system settings (debug, stamina monitoring, etc.)
- `f2t status` - Show component states
- `f2t version` - Shows package version

### File Naming

**Design Principles**: File names should be clear even without folder context (important for Mudlet UI), searchable, predictable, and prioritize clarity over brevity.

#### Aliases
```
{command}.lua
```

File name MUST match the primary user-facing command.

**Examples**:
- ✅ `bb.lua` → `bb` command
- ✅ `factory.lua` → `factory`/`fac` command
- ✅ `nav.lua` → `nav`/`go`/`goto` commands

#### Scripts
```
{component}_{purpose}.lua        (for component scripts)
f2t_{purpose}.lua               (for shared utilities)
init.lua                        (for initialization)
{component}_help_init.lua       (for help registration)
```

**Rules**:
- Component scripts MUST have component prefix (except `init.lua`)
- Shared utilities MUST have `f2t_` prefix
- Standard init files use `init.lua` (no prefix needed)
- Help registration files use `{component}_help_init.lua`
- Purpose should be descriptive: `parser`, `formatter`, `state_machine`, etc.

**Exception**: Feature prefix allowed if component has ONE dominant feature AND feature name is clearer than component name (e.g., commodities component uses `price_` prefix intentionally).

**Examples**:
- ✅ `map_navigate.lua` (map component)
- ✅ `factory_parser.lua` (factory component)
- ✅ `hauling_phases.lua` (hauling component)
- ✅ `price_parser.lua` (commodities component - intentional exception)
- ✅ `f2t_debug.lua` (shared utility)
- ✅ `init.lua` (initialization script)
- ✅ `map_help_init.lua` (help registration)
- ❌ `parser.lua` (too generic, which component?)
- ❌ `connection_handler.lua` (should be `f2t_connection_handler.lua`)

#### Triggers
```
{descriptive_name}.lua
```

**Rules**:
- Name should clearly describe what the trigger responds to and/or what it does
- Add component/feature prefix when context isn't obvious from name alone
- Component folder provides context, so prefixes are optional if name is self-documenting

**Common patterns** (use what fits the trigger's purpose):
- `{action}_{result}.lua` - e.g., `buy_success.lua`
- `{action}_error_{reason}.lua` - e.g., `sell_error_no_cargo.lua`
- `{feature}_{stage}.lua` - e.g., `price_output_start.lua`
- `{component}_{feature}_{action}.lua` - e.g., `hauling_ac_collect_success.lua`
- `{condition}.lua` - e.g., `no_factory.lua`

**Examples**:
- ✅ `buy_success.lua` - clear even without prefix
- ✅ `price_output_start.lua` - "price" provides enough context
- ✅ `hauling_ac_collect_success.lua` - "hauling_ac" clarifies "ac" abbreviation
- ✅ `factory_capture_line.lua` - "factory" clarifies what's being captured
- ❌ `capture_line.lua` - unclear what's being captured

#### Keybinds
```
{descriptive_name}.lua
```

Describe what the keybind does, using underscores to separate words.

#### Resources
```
{descriptive_name}.{extension}
```

Use clear, descriptive names with appropriate file extension (e.g., `commodities.json`).

## Lua Coding Conventions

### Essential Project Patterns

**1. String Formatting - ALWAYS use `string.format()`:**
```lua
-- ✅ CORRECT
local msg = string.format("Player %s has %d gold", name, gold)
cecho(string.format("\n<green>[%s]<reset> Value: %d\n", component, value))

-- ❌ INCORRECT: concatenation
local msg = "Player " .. name .. " has " .. gold .. " gold"
```

**Common format specifiers:** `%s` (string), `%d` (integer), `%f` (float), `%.2f` (2 decimals)

**2. Variable Naming - Use snake_case, descriptive names:**
```lua
-- ✅ CORRECT
local factory_count = 0
local current_fuel_level = gmcp.char.ship.fuel.cur
F2T_DEBUG = false  -- Global with component prefix

-- ❌ INCORRECT
local fc = 0  -- unclear abbreviation
local fuelLvl = ...  -- camelCase
```

**3. Error Handling - Check nil before use:**
```lua
-- ✅ CORRECT
local fuel = gmcp.char.ship.fuel
if not fuel or not fuel.cur or not fuel.max then
    cecho("\n<red>[refuel]<reset> Error: Fuel data not available\n")
    return
end
```

**4. Mudlet Color Echo:**
```lua
-- ✅ CORRECT
cecho("\n<green>[refuel]<reset> Status: <yellow>ENABLED<reset>\n")

-- ❌ INCORRECT
echo("\n<green>Text</green>\n")  -- Wrong function
```

**5. Debug Logging - Use `f2t_debug_log()` with format string:**
```lua
-- ✅ CORRECT: Variadic arguments
f2t_debug_log("[component] Processing %d items", count)
f2t_debug_log("[component] User %s has %d gold", name, gold)

-- ❌ INCORRECT: Manual formatting
f2t_debug_log(string.format("[component] Processing %d items", count))
```

**When to log:**
- Component initialization
- State changes
- Key operations start/complete
- Error conditions

**Don't log:** Every loop iteration, trivial assignments, redundant info

**6. Comments - Explain "why", not "what":**
```lua
-- ✅ CORRECT
-- GMCP reports available space, not used space, so we invert
local used_space = max_hold - current_hold

-- ❌ INCORRECT
-- Set value to 0
local value = 0
```

**7. Early Returns - Reduce nesting:**
```lua
-- ✅ CORRECT
function process(factory)
    if not factory then return end
    if not factory.name then return end
    calculate_stats(factory)
end
```

**8. Performance - Cache repeated lookups:**
```lua
-- ✅ CORRECT
local fuel = gmcp.char.ship.fuel
local percent = math.floor((fuel.cur / fuel.max) * 100)
```

**9. Argument Parsing - Use Shared Helpers:**

**ALWAYS use shared argument parsing helpers** instead of manual parsing:

```lua
-- ✅ CORRECT
local words = f2t_parse_words(args)
local planet = f2t_parse_required_arg(words, 2, "hauling", "Usage: haul start <planet>")
if not planet then return end

-- ❌ INCORRECT
local words = {}
for word in string.gmatch(args, "%S+") do
    table.insert(words, word)
end
if not words[2] then
    cecho("\n<red>[hauling]<reset> Usage: haul start <planet>\n")
    return
end
local planet = words[2]
```

**Available in:** `src/shared/scripts/f2t_arg_parser.lua`

**Functions:**
- `f2t_parse_words(str)` - Split into word array
- `f2t_parse_rest(words, start_index)` - Join remaining words
- `f2t_parse_required_arg(words, index, component, usage)` - Required argument
- `f2t_parse_required_number(words, index, component, usage)` - Required number
- `f2t_parse_optional_number(words, index, default)` - Optional number
- `f2t_parse_choice(words, index, choices, component, default)` - Choice validation

**Component-specific helpers:**
- Map component has `map_arg_parser.lua` for optional room_id patterns
- Other components can create their own as needed

### Consolidated Alias Pattern

**MANDATORY: One alias file per command, not per subcommand.**

**Pattern Structure:**
1. Capture command with optional args: `^command(?:\s+(.+))?$`
2. No arguments → Show help OR default behavior
3. Check help: `f2t_handle_help(command, args)`
4. Parse/route subcommands with `if/elseif`
5. Execute logic or show error

**Example - Simple Command:**
```lua
-- @regex: ^bb(?:\s+(.+))?$
local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("bb")
    return
end

if f2t_handle_help("bb", args) then return end

local commodity, count_str = args:match("^(%S+)%s*(%d*)$")
local count = count_str ~= "" and tonumber(count_str) or nil
f2t_bulk_buy_start(commodity, count)
```

**Example - Command with Subcommands:**
```lua
-- @regex: ^(?:nav|go|goto)(?:\s+(.+))?$
local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("nav")
    return
end

if f2t_handle_help("nav", args) then return end

local subcommand = string.lower(args):match("^(%S+)")

if subcommand == "stop" then
    f2t_map_speedwalk_stop()
elseif subcommand == "pause" then
    f2t_map_speedwalk_pause()
else
    f2t_map_navigate(args)  -- Default: treat as destination
end
```

**Benefits:** One source of truth, easy to see all subcommands, consistent behavior, less clutter

### Help System

**CRITICAL: Every user-facing command MUST provide help via `help`.**

**Two Approaches:**

**1. Help Registry (PREFERRED)** - Register once in component init, use everywhere:
```lua
-- In init script:
f2t_register_help("nav", {
    description = "Navigate using speedwalk",
    usage = {
        {cmd = "nav <destination>", desc = "Navigate to destination"},
        {cmd = "nav stop", desc = "Stop speedwalk"}
    },
    examples = {"nav Earth", "nav stop"}
})

-- In alias:
if f2t_handle_help("nav", args) then return end
```

**2. Direct Display** - For dynamic/custom help:
```lua
if f2t_is_help_request(args) then
    f2t_show_help("command", "Description", usage_table, examples_table)
    return
end
```

**See `src/shared/CLAUDE.md` for full help system documentation.**

## Build Commands

```powershell
./build.ps1                              # Build package
Remove-Item -Recurse -Force build/       # Clean build
```

## Git Workflow (GitFlow)

**MANDATORY: All development MUST follow GitFlow with regular commits.**

### Pre-Flight Checklist - Run BEFORE Every Task

```bash
# 1. Check current branch
git branch

# 2. Update develop
git checkout develop
git pull origin develop

# 3. Create feature branch
git checkout -b feature/descriptive-name

# 4. Verify
git branch  # Should show: * feature/descriptive-name
```

**NEVER proceed without completing this checklist.**

### Branch Strategy

**Main Branches:**
- `main` - Production-ready, tagged with versions
- `develop` - Integration branch, always deployable

**Supporting Branches:**
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `hotfix/*` - Critical production fixes (from main)
- `release/*` - Release prep (from develop)

### Commit Messages

**Format:** `<type>: <subject>`

**Types:** `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`

**Examples:**
```
feat: add refuel disable functionality
fix: prevent refuel when disabled
docs: update refuel CLAUDE.md
refactor: rename f2t-factory-status to factory
```

**Rules:**
- Imperative mood ("add" not "added")
- Under 72 characters
- No period at end
- Commit logical units, not "everything I did today"

### Completing a Feature

```bash
# Update from develop
git checkout develop && git pull origin develop
git checkout feature/name && git merge develop

# Merge to develop
git checkout develop
git merge --no-ff feature/name
git push origin develop

# Delete branch
git branch -d feature/name
git push origin --delete feature/name
```

### No Exceptions Policy

**ALL changes require a branch:**
- ✅ Single trigger → Create branch
- ✅ Typo fix → Create branch
- ✅ Docs update → Create branch
- ❌ "Just a quick fix" → **NO.** Create a branch.

**Only exception:** Emergency hotfixes (use `hotfix/*` from `main`)

## Creating Components

### New Component

1. Create directory: `src/component-name/`
2. Add subdirectories: `aliases/`, `triggers/`, `scripts/`, `resources/`
3. Add `.lua` files to appropriate subdirectories

**Component becomes a folder in Mudlet's panels.**

### Component Initialization Pattern

**`scripts/init.lua` - Minimal initialization only:**
```lua
-- Initialize component
f2t_settings = f2t_settings or {}
f2t_settings.my_component = f2t_settings.my_component or {}

-- Load saved settings
MY_ENABLED = f2t_settings.my_component.enabled or false

-- Init message
if F2T_DEBUG then
    cecho("<green>[my-component]<reset> Initialized\n")
end
```

**Other script files - Functions and logic:**
```lua
-- Helper functions in separate files
function my_component_do_thing()
    -- Implementation
end
```

**Why:** Clear separation, organized by purpose, leverages Mudlet's alphabetical loading (init.lua first)

**Loading Order:** Scripts → Triggers → Aliases → Timers → Keybindings (alphabetically within each)

### Adding Resources

Place in `resources/` subdirectory:
```
src/shared/resources/commodities.json
```

**Access in Mudlet:**
```lua
local path = getMudletHomeDir() .. "/@PKGNAME@/component-name/filename"
local file = io.open(path, "r")
local json = file:read("*all")
file:close()
local data = yajl.to_value(json)  -- Parse JSON
```

## Build Script Details

**Process:**
1. Read `project.json`
2. Scan `src/` in priority order (`shared` first, then alphabetical)
3. Collect `.lua` files by type
4. Generate XML with component folders
5. Create `config.lua`
6. Bundle into `.mpackage` (ZIP archive)

### Component Load Order

**`shared` loads first** - provides:
- `F2T_DEBUG` flag
- `f2t_debug_log()` function
- `f2t_settings` table
- `f2t_has_value()` and utilities
- `f2t_render_table()` renderer

Then all other components load alphabetically.

### Metadata Headers

Add metadata as comments at top of `.lua` files using the `@patterns:` format:

**Aliases (single pattern):**
```lua
-- @patterns:
--   - pattern: ^command pattern (\w+)$
```

**Triggers (single pattern):**
```lua
-- @patterns:
--   - pattern: ^You see (.+)$
--     type: regex
```

**Triggers (multiple patterns):**
```lua
-- @patterns:
--   - pattern: Production Facility #
--     type: substring
--   - pattern: ^\s{2,}.+
--     type: regex
```

**Pattern types:** `substring`, `perl`/`regex`, `exact`, `lua`, `prompt`

**Format Notes:**
- Aliases don't need `type:` (always regex)
- Triggers require `type:` for each pattern
- Multiple patterns fire the same trigger code
- More efficient than broad patterns like `^.+$`

## Debug Logging System

**Global debug flag for all components.**

**Usage:**
```lua
f2t_debug_log("Your message here")  -- Helper function
if F2T_DEBUG then cecho("...") end  -- Manual check
```

**Commands:** `f2t debug on`, `f2t debug off`, `f2t debug`

**Persistence:** Stored in `f2t_settings` table, saved with `f2t_save_settings()`

## Persistent Settings Pattern

**IMPORTANT: Mudlet does NOT auto-persist global tables. MUST use `f2t_save_settings()`.**

### Pattern

```lua
-- Initialize (in init.lua)
f2t_settings = f2t_settings or {}
f2t_settings.my_component = f2t_settings.my_component or {}

-- Load settings
local enabled = f2t_settings.my_component.enabled or false

-- Save when changed
function set_setting(key, value)
    f2t_settings.my_component[key] = value
    f2t_save_settings()  -- REQUIRED
end
```

**Storage:** `<mudlet_home>/fed2-tools_settings.lua`

**Functions:**
- `f2t_save_settings()` - Save to disk
- `f2t_load_settings()` - Load from disk (auto-called on init)

## Shared Utility Functions

### Table Utilities

**`f2t_has_value(tab, val)`** - Check if table contains value:
```lua
if f2t_has_value(gmcp.room.info.flags, "shuttlepad") then
    -- At a shuttlepad
end
```

### Table Renderer

**`f2t_render_table(config)`** - Declarative table rendering with auto-width, formatting, styling, aggregations.

**See `src/shared/CLAUDE.md` for full API documentation.**

**Quick example:**
```lua
f2t_render_table({
    title = "Factory Status",
    columns = {
        {header = "#", field = "number", align = "right", width = 2},
        {header = "Location", field = "location", max_width = 15},
        {header = "P/L", field = "profit", format = "compact",
         color_fn = function(val) return val >= 0 and "green" or "red" end}
    },
    data = factories,
    footer = {aggregations = {{field = "profit", method = "sum"}}}
})
```

### Location Parsing

**`f2t_map_parse_location_prefix(input)`** - Parse multi-word location from user input.

**Use this when:** Your command accepts `<location> <other args>` format and needs to split them.

**How it works:** Progressive prefix matching - tries longest possible planet/system name first, then shorter prefixes.

**Example:**
```lua
-- User input: "the lattice exchange room"
local location, remaining = f2t_map_parse_location_prefix("the lattice exchange room")
-- location = "the lattice"
-- remaining = "exchange room"
```

**Returns:**
- `location_name` - Matched planet/system name (or `nil` if no location found)
- `remaining_text` - Everything after the location (or full input if no match)

**Common pattern in aliases:**
```lua
-- @regex: ^mycommand(?:\s+(.+))?$
local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("mycommand")
    return
end

if f2t_handle_help("mycommand", args) then return end

-- Parse location prefix
local location, remaining = f2t_map_parse_location_prefix(args)

if location then
    -- Has location: "mycommand <planet> <args>"
    do_something_with_location(location, remaining)
else
    -- No location: "mycommand <args>" (use current location or error)
    do_something_with_args(remaining)
end
```

**When NOT to use:**
- Command only accepts a location (use `f2t_map_navigate()` directly)
- Location is optional and comes LAST (different parsing strategy needed)
- Location format is fixed (e.g., always "planet exchange")

**Example commands using this:**
- `map search <location> <text>` - Search for text in a specific location
- Future: `price check <location> <commodity>` - Check price in specific location

## Common Mudlet Patterns

### Capturing Game Output

**MANDATORY: Always hide game output when capturing data for processing.**

**⚠️ CRITICAL FED2 LIMITATION: NEVER USE PROMPT TRIGGERS**

Federation 2 does NOT reliably send prompts that Mudlet can detect. Prompt triggers (`type: prompt`) are fundamentally unreliable in Fed2.

**Use these alternatives instead:**
- ✅ **BEST**: Explicit end marker (specific text pattern from game output)
- ✅ **ACCEPTABLE**: Timer-based completion (0.5s of silence = done)
- ❌ **NEVER**: Prompt triggers for completion detection

**See:** `src/hauling/CLAUDE.md` "Fed2 Prompt Trigger Unreliability" section for real-world example.

**CRITICAL `deleteLine()` RULES:**

1. ✅ **ONLY call `deleteLine()` when BOTH conditions are true:**
   - The trigger pattern explicitly matched (trigger fired)
   - We are actively capturing (capture flag is set)

2. ✅ **ALWAYS call `deleteLine()` INSIDE the capture-active check:**
   ```lua
   if capture_is_active then
       deleteLine()  -- Delete AFTER checking state
       process_data()
   end
   ```

3. ❌ **NEVER call `deleteLine()` before checking capture state:**
   ```lua
   -- WRONG - deletes even when user manually runs command
   deleteLine()
   if capture_is_active then
       process_data()
   end
   ```

**Why:** Only squelch output during automated capture, not when user manually runs commands.

**Pattern:**
1. Send command: `send("factory status")`
2. Capture with triggers
3. **Call `deleteLine()` INSIDE capture-active conditional**
4. Process in background
5. Display formatted results

**Example:**
```lua
-- Global state
F2T_CAPTURE_ACTIVE = false
F2T_CAPTURE_DATA = {}

-- Start trigger
-- @pattern: ^Output starts here
if not F2T_CAPTURE_ACTIVE then
    deleteLine()  -- Pattern matched AND we're starting capture
    F2T_CAPTURE_ACTIVE = true
    F2T_CAPTURE_DATA = {}
end

-- Capture trigger
-- @pattern: ^(.+data.+)$
if F2T_CAPTURE_ACTIVE then
    deleteLine()  -- Pattern matched AND capture is active
    table.insert(F2T_CAPTURE_DATA, line)
end

-- End trigger (explicit marker - NEVER use prompt triggers in Fed2!)
-- @pattern: ^Explicit end marker text here$
if F2T_CAPTURE_ACTIVE then
    local results = process_data(F2T_CAPTURE_DATA)
    display_formatted(results)
    F2T_CAPTURE_ACTIVE = false
    F2T_CAPTURE_DATA = {}
end
```

**Real-world examples:**
```lua
-- ✅ CORRECT: Factory capture
if f2t_factory.capturing then
    if not line:find("You don't have a factory") then
        deleteLine()  -- Inside conditional, pattern verified
        table.insert(f2t_factory.capture_buffer, line)
    end
end

-- ✅ CORRECT: Price capture
if not F2T_PRICE_CAPTURE_ACTIVE then
    return  -- Exit early if not capturing
end
deleteLine()  -- Only reached if capturing
table.insert(F2T_PRICE_CAPTURE_DATA, line)

-- ✅ CORRECT: AC work capture
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    deleteLine()  -- Only when actively hauling
    f2t_ac_start_capture()
end
```

**Why:** Clean UX, consistency, professional appearance, respects manual user commands

**When NOT to use deleteLine():**

```lua
-- ❌ WRONG: State-tracking triggers should NOT hide game output
-- @pattern: The clerk plugs your com unit into a terminal
-- This is just tracking that cargo was collected
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    F2T_HAULING_STATE.ac_cargo_collected = true  -- Just set flag, don't deleteLine()
end

-- ❌ WRONG: Payment capture should NOT hide the payment message
-- @pattern: ([\d,]+)ig has been transferred to your account
-- User wants to see they got paid!
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then
    F2T_HAULING_STATE.ac_payment_amount = tonumber(matches[2]:gsub(",", ""))
    -- NO deleteLine() - let user see the payment
end

-- ✅ CORRECT: State tracking without output suppression
-- @pattern: You have successfully landed
if F2T_SOME_STATE then
    F2T_SOME_STATE.has_landed = true
    -- Game output is useful, don't hide it
end
```

**Rule of thumb:**
- **Use `deleteLine()`**: When capturing multi-line command output that you'll reformat/redisplay
- **DON'T use `deleteLine()`**: When tracking state changes from natural game events the user should see

**Error handling:**
```lua
-- @pattern: ^Game error message
-- Only delete if we're in an automated flow
if F2T_SOME_ACTIVE_STATE then
    deleteLine()
    cecho("\n<red>[component]<reset> Friendly error message\n")
end
```

### Capture Pattern Selection

**CRITICAL: Choose the right pattern for your use case.**

#### Pattern Decision Matrix

| Use Case | Pattern | When to Use | Examples |
|----------|---------|-------------|----------|
| **Data Capture** | Permanent Triggers + Global State | • Capturing multi-line command output<br>• Known start/end patterns<br>• Runs frequently (user commands)<br>• Output format is consistent<br>• Need debugging visibility | • `factory status`<br>• `price alloys`<br>• `work` (AC jobs) |
| **Event-Driven** | Temporary Triggers + Lifecycle Mgmt | • Multi-phase workflows<br>• Unpredictable timing (may wait seconds)<br>• Dynamic patterns per invocation<br>• Runs infrequently<br>• Complex state transitions | • Circuit travel<br>• Train/tube navigation<br>• Complex automation |
| **State Tracking** | GMCP Event Handlers | • Single event (room change, cargo change)<br>• No pattern matching needed<br>• GMCP provides the data | • Special exit discovery<br>• Ship status monitoring |

#### Use Permanent Triggers When:

✅ Capturing multi-line command output
✅ Running frequently (user commands)
✅ Output format is known/consistent
✅ Need trigger visibility for debugging
✅ Simple start → capture → end lifecycle
✅ Examples: price, factory status, work listings

#### Use Temporary Triggers When:

✅ Event-driven state machine (multi-phase)
✅ Unpredictable timing (may wait seconds/minutes)
✅ Dynamic patterns (vary per invocation)
✅ Runs infrequently
✅ Complex lifecycle with cleanup needs
✅ Examples: circuit travel, train travel, complex navigation

**See `CLAUDE_PATTERNS.md` for code templates and `src/map/CLAUDE.md` for circuit pattern reference implementation.**

### Event-Driven State Machine Pattern

**Use for:** Multi-phase workflows with unpredictable timing (circuit travel, complex automation sequences)

**Core Principle:** Create triggers dynamically when needed, kill them when done, couple trigger lifecycle to workflow state.

#### Architecture

```lua
-- State object with trigger ID tracking
F2T_WORKFLOW_STATE = {
    active = false,
    phase = nil,  -- Track which phase we're in
    data = {},

    -- Trigger IDs for cleanup
    trigger_id_1 = nil,
    trigger_id_2 = nil,

    -- Timer IDs for cleanup
    timer_id = nil
}
```

#### Progressive Trigger Creation

**Don't create all triggers at start** - create them as needed:

```lua
function start_workflow()
    F2T_WORKFLOW_STATE.active = true
    F2T_WORKFLOW_STATE.phase = "waiting_event_1"

    -- Create first trigger only
    F2T_WORKFLOW_STATE.trigger_id_1 = tempRegexTrigger(
        "^Event 1 pattern",
        function()
            handle_event_1()
        end
    )
end

function handle_event_1()
    -- Guard: Check state
    if not F2T_WORKFLOW_STATE.active then return end
    if F2T_WORKFLOW_STATE.phase ~= "waiting_event_1" then return end

    -- Kill first trigger immediately
    if F2T_WORKFLOW_STATE.trigger_id_1 then
        killTrigger(F2T_WORKFLOW_STATE.trigger_id_1)
        F2T_WORKFLOW_STATE.trigger_id_1 = nil
    end

    -- Do work
    send("some command")

    -- Change phase
    F2T_WORKFLOW_STATE.phase = "waiting_event_2"

    -- Create next trigger after delay (avoid race conditions)
    tempTimer(0.5, function()
        if F2T_WORKFLOW_STATE.active and F2T_WORKFLOW_STATE.phase == "waiting_event_2" then
            F2T_WORKFLOW_STATE.trigger_id_2 = tempRegexTrigger(
                "^Event 2 pattern",
                function()
                    handle_event_2()
                end
            )
        end
    end)
end
```

#### Cleanup on All Exit Paths

```lua
function cleanup_workflow()
    -- Kill all triggers
    if F2T_WORKFLOW_STATE.trigger_id_1 then
        killTrigger(F2T_WORKFLOW_STATE.trigger_id_1)
    end
    if F2T_WORKFLOW_STATE.trigger_id_2 then
        killTrigger(F2T_WORKFLOW_STATE.trigger_id_2)
    end
    if F2T_WORKFLOW_STATE.timer_id then
        killTimer(F2T_WORKFLOW_STATE.timer_id)
    end

    -- Reset state
    F2T_WORKFLOW_STATE = {active = false}
end

function complete_workflow()
    cleanup_workflow()
    cecho("\n<green>[component]<reset> Workflow complete\n")
end

function stop_workflow()
    cleanup_workflow()
    cecho("\n<yellow>[component]<reset> Workflow stopped\n")
end

function error_workflow(message)
    cleanup_workflow()
    cecho(string.format("\n<red>[component]<reset> Error: %s\n", message))
end
```

#### State-Driven Guards

**Every handler must check state:**

```lua
function handle_event()
    -- Guard #1: Workflow active
    if not F2T_WORKFLOW_STATE.active then
        return
    end

    -- Guard #2: Correct phase
    if F2T_WORKFLOW_STATE.phase ~= "expected_phase" then
        return
    end

    -- Safe to proceed
    do_work()
end
```

#### Non-Blocking Delays

**Use tempTimer for delays, never block:**

```lua
-- ✅ CORRECT: Non-blocking
tempTimer(0.5, function()
    if F2T_WORKFLOW_STATE.active then
        do_next_action()
    end
end)

-- ❌ WRONG: Blocking (freezes Mudlet)
sleep(0.5)
do_next_action()
```

#### Why This Pattern?

**Benefits:**
- Zero interference when inactive (triggers don't exist)
- Lifecycle safety (trigger dies with workflow)
- Dynamic pattern matching (each invocation can use different patterns)
- State isolation (no global pollution)
- Memory efficiency (resources freed automatically)

**Trade-offs:**
- More complex code (must store/kill IDs)
- Harder to debug (triggers not visible in UI when inactive)
- Not suitable for frequent operations (creation overhead)

**Reference Implementation:** See `src/map/scripts/map_circuit.lua` for complete working example.

### Timer-Based Completion Rules

**CRITICAL: When using timer-based capture (Pattern 2), the timer MUST always complete when it expires.**

#### The Problem

```lua
-- ❌ WRONG: Timer might not complete
function reset_timer()
    if timer_id then killTimer(timer_id) end

    timer_id = tempTimer(0.5, function()
        -- BUG: If pattern matching fails, buffer is empty, capture stays active forever
        if CAPTURE_ACTIVE and #CAPTURE_DATA > 0 then
            process_capture()
        end
    end)
end
```

**If pattern matching fails (trigger doesn't match any lines), buffer stays empty, timer never processes, capture flag never resets → system broken forever.**

#### The Solution

```lua
-- ✅ CORRECT: Timer ALWAYS processes when it expires
function reset_timer()
    if timer_id then killTimer(timer_id) end

    timer_id = tempTimer(0.5, function()
        -- Always finish capture when timer expires, even if data is empty
        if CAPTURE_ACTIVE then
            process_capture()  -- Will process empty data gracefully
        end
    end)
end

function process_capture()
    -- Handle empty data gracefully
    if #CAPTURE_DATA == 0 then
        cecho("\n<yellow>[component]<reset> No data captured\n")
    else
        display_results(CAPTURE_DATA)
    end

    -- Always reset state
    CAPTURE_ACTIVE = false
    CAPTURE_DATA = {}
end
```

#### Why This Matters

**Timer is the ONLY completion mechanism** for Pattern 2 (timer-based capture):
- No explicit end trigger
- No prompt detection
- Just: "if no more lines arrive in 0.5s, we're done"

**If timer doesn't complete:**
- Capture flag stays `true`
- Next time user runs command → trigger still active → captures wrong output
- System permanently broken until package reload

#### Rule of Thumb

```lua
// Timer callback structure:
tempTimer(delay, function()
    if CAPTURE_FLAG then          // Check flag (allows manual stop)
        process_capture()          // ALWAYS call this
        // DON'T add: and #data > 0
        // DON'T add: and some_other_condition
    end
end)
```

**See:** Factory component (`src/factory/scripts/factory_capture_timer.lua`) for correct implementation.

### Message Formatting Convention

**All messages MUST start with `\n` to avoid line break issues:**

```lua
-- ✅ CORRECT
cecho("\n<green>[component]<reset> Message\n")
cecho(string.format("\n<green>[component]<reset> Value: %d\n", value))

-- ❌ INCORRECT
cecho("<green>[component]<reset> Message\n")  -- Missing \n
```

**Why:** Game output may not end with newline, causing messages to appear on same line.

## Federation 2 Tools

Multiple components provide various tools. Each has `CLAUDE.md` in source directory.

### Available Components

- **factory** - View all factory statuses (`src/factory/CLAUDE.md`)
- **refuel** - Automatic ship refueling (`src/refuel/CLAUDE.md`)
- **commodities** - Price analysis, bulk buy/sell (`src/commodities/CLAUDE.md`)
- **map** - Custom mapper with auto-mapping (`src/map/CLAUDE.md`)
- **hauling** - Automated commodity trading, rank-adaptive (`src/hauling/CLAUDE.md`)
- **po** - Planet owner tools: economy overview (`src/po/CLAUDE.md`)
- **shared** - Common utilities including stamina monitoring (`src/shared/CLAUDE.md`)

### Settings Management System

Unified settings with consistent interface and auto-persistence.

**Commands:**
```
<component> settings                    # List all
<component> settings get <name>         # Get specific
<component> settings set <name> <value> # Set value
<component> settings clear <name>       # Reset to default
```

**Available Settings:**

- **Commodities** (`price settings`): `results_count` (number, 1-20, default: 5)
- **Map** (`map settings`): `enabled` (boolean), `planet_nav_default` (shuttlepad|orbit)
- **Refuel** (`refuel settings`): `enabled` (boolean), `threshold` (0-100)
- **Shared** (`f2t settings`): `debug` (boolean), `stamina_enabled` (boolean), `stamina_threshold` (1-99), `food_source` (string), `safe_room` (string)
- **Hauling** (`haul settings`): `margin_threshold` (0-100), `cycle_pause` (0-300), `use_safe_room` (boolean), `po_deficit_threshold` (-525 to -75), `po_excess_threshold` (750-20000), `po_max_sell_attempts` (1-10), `po_mode` (both|deficit)

**Implementation** (in `f2t_settings_manager.lua`):
```lua
-- Register
f2t_settings_register("component", "name", {
    description = "...",
    default = value,
    validator = function(v) return true end
})

-- Get (returns value or default)
local value = f2t_settings_get("component", "name")

-- Set (validates and persists)
local success, err = f2t_settings_set("component", "name", value)

-- Clear (revert to default)
f2t_settings_clear("component", "name")
```

Settings auto-convert types, validate, persist via `f2t_save_settings()`, load on startup.

### Stamina Monitoring System

Automatic stamina monitoring service (in `shared` component) that pauses activities, navigates to food source, buys food until stamina is full, and resumes activities. Used by hauling and available for other components.

**User Commands:**
```bash
# Enable and configure stamina monitoring
f2t settings set stamina_enabled true
f2t settings set stamina_threshold 20        # Trigger at 20% stamina
f2t settings set food_source earth           # Destination name or room hash

# View current settings
f2t settings
```

**How It Works:**
1. Component (e.g., hauling) registers with stamina monitor on init
2. When component starts, stamina monitoring activates (if enabled)
3. System watches `gmcp.char.vitals.stamina` for changes
4. When stamina ≤ threshold AND component is active:
   - Pauses component (via registered callback)
   - Navigates to food source
   - Buys food repeatedly until stamina = 100%
   - Returns to original location
   - Resumes component (via registered callback)

**Integration Pattern:**

Components register callbacks in their init script:
```lua
-- In src/component/scripts/init.lua
f2t_stamina_register_client({
    pause_callback = component_pause_function,
    resume_callback = component_resume_function,
    check_active = function()
        return COMPONENT_STATE.active and not COMPONENT_STATE.paused
    end
})
```

Then start/stop monitoring in component start/stop functions:
```lua
function component_start()
    -- ... setup ...
    if f2t_settings_get("shared", "stamina_enabled") then
        f2t_stamina_start_monitoring()
    end
end

function component_stop()
    -- ... cleanup ...
    f2t_stamina_stop_monitoring()
end
```

**See `src/shared/CLAUDE.md` for full API documentation and `src/hauling` for integration example.**

### GMCP Reference

Federation 2 provides game data via GMCP (General Mud Communication Protocol).

**Room Information:**
- `gmcp.room.info.flags` - Array: "shuttlepad", "warehouse", "exchange", "orbit", "link"
- `gmcp.room.info.system` - System name (e.g., "Coffee")
- `gmcp.room.info.area` - Area name (e.g., "Latte")
- `gmcp.room.info.num` - Fed2 room number
- `gmcp.room.info.cartel` - Cartel name (e.g., "Coffee")
- `gmcp.room.info.owner` - Area owner name
- `gmcp.room.info.orbit` - Shuttlepad hash when in orbit: "system.planet.num" (use `board` to land)
- `gmcp.room.info.board` - Orbit hash when on shuttlepad: "system.space_area.num" (use `board` to launch)

**Ship Information:**
- `gmcp.char.ship.fuel.cur` - Current fuel
- `gmcp.char.ship.fuel.max` - Max fuel
- `gmcp.char.ship.hold.cur` - **AVAILABLE** space (NOT used!)
- `gmcp.char.ship.hold.max` - Max cargo capacity
- `gmcp.char.ship.cargo` - Array of cargo lots (each = 75 tons)
  - Each: `commodity`, `base`, `cost`, `origin`

**Character Information:**
- `gmcp.char.vitals.rank` - Character rank (e.g., "Merchant", "Adventurer")
- `gmcp.char.vitals.tools` - Table of game tools/upgrades (e.g., `{["remote-access-cert"] = {days = 20}}`)
- `gmcp.char.*` - Character stats/status

**Important:** `hold.cur` is AVAILABLE space. If max=675 and cur=675, hold is EMPTY. If cur=0, hold is FULL.

## Maintaining Documentation

### Keep Documentation Up-to-Date

**Structure:**
- **Main CLAUDE.md** - Project-level patterns, conventions, build
- **Component CLAUDE.md** - Component-specific details

**IMPORTANT: Docs MUST be in same feature branch/commits as code changes.**

**Update main CLAUDE.md when:**
- New architectural patterns apply project-wide
- Code organization decisions across components
- New Fed2 game mechanics/APIs discovered
- New conventions established
- Build script extended
- New shared utilities created

**Update component CLAUDE.md when:**
- New features added to component
- Internal changes
- New files added
- Usage/commands modified
- Component-specific patterns discovered

**New component checklist:**
1. Create directory structure
2. Create `CLAUDE.md` in component
3. Document: usage, how it works, patterns, key files
4. Add to "Available Components" list in main CLAUDE.md

### Keep README.md Current

**Update when:**
- New user-facing features
- Build process changes
- Project structure changes
- New configuration options
- New helpful examples

**README.md should:**
- Have accurate structure diagrams
- Include working examples
- Explain all user features
- Provide clear quick-start
- Stay synchronized with CLAUDE.md (but more user-friendly)

**Remember:** README.md for end users. CLAUDE.md for AI assistants and deep technical context.

## Mudlet Package Reference

`.mpackage` is a ZIP archive containing:
- `config.lua` - Package name
- `<package>.xml` - All triggers, aliases, scripts
- Resources (images, sounds, etc.)

**See:**
- [Manual:Mudlet Packages](https://wiki.mudlet.org/w/Manual:Mudlet_Packages)
- [Muddler Build Tool](https://github.com/demonnic/muddler)
