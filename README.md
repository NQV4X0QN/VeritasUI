# VeritasUI

A personal World of Warcraft addon suite for **Midnight** (12.0, Interface 120001), focused on solo play quality-of-life improvements.

VeritasUI uses Blizzard's native APIs exclusively and matches Blizzard's UI aesthetics — fonts, spacing, layout, and settings panels are designed to be indistinguishable from the default UI. Every feature is configurable through the standard **Options → AddOns** panel with no slash commands required.

## Modules

### VeritasUI_Lib
Shared utility library loaded by all other modules. Provides the common print formatter, smooth per-frame fade manager (replacing Blizzard's conflicting `UIFrameFadeIn`/`UIFrameFadeOut`), player frame fade with event-timing health detection, and the shared settings panel infrastructure including the Reload UI button.

### VeritasUI_CleanSolo
UI decluttering for a cleaner solo experience.

- **Fade Chat Tabs** — tabs fade in sync with the chat window, reappear on mouseover
- **Hide Social Button** — removes the Quick Join / Communities toast
- **Hide Chat Buttons** — removes scroll buttons and the new-window button
- **Hide Voice Chat Button** — removes the voice chat icon
- **Fade Micro Menu** — bottom-right menu fades unless moused over
- **Fade Player Frame** — player frame fades when out of combat, at full health, and not moused over (uses event-timing via `UNIT_HEALTH` to work around Midnight's Secret Values)
- **Hide Bag Buttons** — hides the bag bar (use `B` to open bags)
- **Hide Macro Names** — removes macro name text from action bar buttons
- **Hide Error Text** — suppresses red center-screen error messages

Settings: **Options → AddOns → Clean Solo** | `/cs`

### VeritasUI_QualityOfLife
Functional enhancements that don't fit the "hide/fade" category.

- **Map Coordinates** — displays player and cursor coordinates on the World Map using native tooltip backdrop textures; draggable with a lock/unlock icon button; position persists across sessions
- **Item Level Overlays** — shows color-coded item levels on gear in bags, character panel, bank, warband bank, and merchant windows; uses a universal `SetItemButtonQuality` hook with a dedicated merchant scanner
- **Auto Sell Junk** — automatically sells gray items when visiting a merchant, with batched selling (6 per frame) and coin icon output
- **Auto Repair** — automatically repairs gear at repair merchants, attempting guild funds first with source reporting
- **TomTom-compatible Waypoints** — `/way #mapID x y [label]` or `/way x y [label]` places a native Blizzard waypoint pin on the World Map and activates the minimap directional arrow; `/way clear` removes it; reads the same format used by most online guides (e.g. `/way #2351 45.2 56.3`)

Settings: **Options → AddOns → Quality of Life** | `/qol` | `/way`

### VeritasUI_PriorityRotation
One-button spell cycling system for accessibility.

- Cycles through a configurable spell list on each key press via external key repeat (G-Hub at 50ms)
- Uses a `SecureHandlerWrapScript` restricted snippet for zero-taint combat execution
- Action bar override mechanism (reverse-engineered from GSE) redirects a real bar button to the hidden secure button
- Per-spec profiles with drag-and-drop editor and spellbook/macro integration
- Dynamic icon shows the current spell on the action bar
- Frequency tuning per spell for weighted distribution

Settings: **Options → AddOns → Priority Rotation** | `/pr`

### VeritasUI_ZoneQuests
Zone-specific quest tracking via the native Objective Tracker.

- Automatically manages quest watch state so only current-zone quests appear
- Uses a robust zone matching system: `C_Map` hierarchy walk, directional prefix stripping, bidirectional substring matching
- Always-show categories configurable: Campaign, Important, Legendary, Meta, Repeatable
- Event-debounced updates to handle `QUEST_LOG_UPDATE` bursts

Settings: **Options → AddOns → Zone Quests** | `/zq`

## Installation

1. Download or clone this repository
2. Copy all five `VeritasUI_*` folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Ensure the folder names exactly match the TOC filenames (WoW requires this)
4. Reload or restart the game

## Requirements

- World of Warcraft: Midnight (Patch 12.0.1, Interface 120001)
- No external library dependencies — fully self-contained

## Design Philosophy

- **Native only** — Blizzard APIs exclusively, no custom UI chrome
- **Invisible integration** — settings panels, fonts, and spacing match the default UI exactly
- **Solo-focused** — every feature targets the single-player experience
- **Tradeoffs disclosed** — if a feature has a cost or limitation, it's documented and configurable

## Known Limitations

- **Press and Hold Casting** must be disabled for Priority Rotation to function (the addon handles this automatically with a one-time notification)
- **Quest reward item levels** are not displayed — async data loading and base vs. effective ilvl mismatch make reliable display impractical; this is an open problem for future work
- **Secret Values** (Midnight 12.0) prevent direct health reading from addon code — the player frame fade uses event-timing as a workaround

## License

This project is licensed under the GNU General Public License v2.0 — see [LICENSE](LICENSE) for details.
