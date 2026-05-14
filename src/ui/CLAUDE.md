# UI Component — Coding Conventions

The canonical style reference for this component is `ui_tabs.lua`. When modifying
UI code, follow these patterns.

## Style / CSS rules

**All shared or structural styles belong in `ui_styles.lua` as `UI.style.*` properties.**
Component files should reference them, not repeat them:

```lua
-- ✅ CORRECT
tabWindow:new({ activeTabStyle = UI.style.active_tab_css, ... })
btn:setStyleSheet(UI.style.button_css)

-- ❌ WRONG
tabWindow:new({ activeTabStyle = [[ background-color: rgba(40,40,50,230); ... ]], ... })
```

Inline CSS is acceptable only for small, truly local one-off elements (e.g. a single
button in one file). It must not be duplicated — if two widgets share a style, the
style goes in `ui_styles.lua`.

**CSS font convention:**
- Labels and buttons: `font-size` in `px`, no `font-family` (let Qt use the profile font).
- MiniConsoles: `fontSize = text_size` where `text_size` is a local constant.
- Do not tie runtime font detection to widget construction (no `getFont()` in
  style-building code). If the profile font matters, document the expected value as a
  comment and hardcode a reasonable default.

## Widget naming

The `name` field in every Geyser widget must match the Lua variable exactly:

```lua
UI.chat_window = Geyser.MiniConsole:new({ name = "UI.chat_window", ... })
```

This lets Mudlet's debug tools and `setProfileStyleSheet` selectors work predictably.

## Constructor formatting

Align `=` signs vertically within constructor tables. Each property on its own line:

```lua
-- ✅ CORRECT
UI.foo = Geyser.Label:new(
    {
        name   = "UI.foo",
        x      = "0%",
        y      = "0%",
        width  = "100%",
        height = "20px",
    },
    parent
)

-- ❌ WRONG
UI.foo = Geyser.Label:new({name="UI.foo",x="0%",y="0%",width="100%",height="20px"},parent)
```

## Magic numbers

Extract shared literal values to named locals at the top of the function.
Never repeat the same number across multiple widget definitions:

```lua
-- ✅ CORRECT
local text_size = 12
UI.hauling_window = Geyser.MiniConsole:new({ fontSize = text_size, ... })
UI.trading_window = Geyser.MiniConsole:new({ fontSize = text_size, ... })

-- ❌ WRONG
UI.hauling_window = Geyser.MiniConsole:new({ fontSize = 12, ... })
UI.trading_window = Geyser.MiniConsole:new({ fontSize = 12, ... })
```

## Sizing strategy

| Element | Use |
|---------|-----|
| Containers that fill parent | `"100%"` |
| Right/bottom anchored elements | `"-22"` (Geyser negative = parent_size − N) |
| Fixed chrome (headers, button bars) | pixels (`"25px"`, `"20"`) |
| Scrollbox content label width | `scrollbox:get_width() - 17` (scrollbar allowance) |

## Function separation

Structural layout (containers, VBox, TabWindows) belongs in `ui_build_tabs()`.
Content creation (MiniConsoles, buttons, who-list, etc.) belongs in `ui_build_tab_content()`.
Initialisation logic (table setup, GMCP wiring) belongs in per-component `ui_*_init()`.

## Comments

Comment only when the "why" or a layout constraint is non-obvious. Do not comment
the "what":

```lua
-- ✅ good — explains layout math
-- 39px = 21px title strip + 18px column-header bar
UI.who_scroll = Geyser.ScrollBox:new({ y = "39px", height = "100%-39px" }, ...)

-- ✅ good — explains a cross-file dependency
-- Visibility of each tab is managed by ui_update_for_rank() in ui_zLast.lua.

-- ❌ bad — restates the code
-- Create the hauling container
UI.hauling_container = Geyser.Container:new(...)
```

## Known style debt

The following files contain inline CSS that should eventually migrate to `ui_styles.lua`:

- `ui_players.lua` — `_COL_HDR_CSS`, `_COL_HDR_ACTIVE_CSS`, `_CSS_CLOSE`, `_CSS_NAV`,
  `_CSS_GAL`, `_CSS_ICON`, contact-card `string.format` style blocks
- `ui_table_system.lua` — `_SB_HDR_CSS`, `_SB_HDR_ACTIVE_CSS`, `_SB_CELL_CSS`
- `ui_tabs.lua` — filter-button inline CSS (duplicated across General/Comm/Who buttons)

Do not add more inline CSS to these files. Migrate to `UI.style.*` when touching.
