# VeritasUI

A personal World of Warcraft AddOn suite for **Midnight** (Patch 12.0.5, Interface 120005), focused on solo play quality-of-life, a Blizzard-native HUD, and a one-button spell rotation system.

VeritasUI uses Blizzard's native APIs and assets exclusively. Fonts, spacing, templates, and settings panels are designed to be visually indistinguishable from the default UI. Every feature is configurable through the standard **Options → AddOns** panel; slash commands exist for power users but are never required.

## Modules

The suite consists of six independently-loadable AddOns. Each one is a separate folder under the repo root, and all share a single shared library.

### VeritasUI_Lib

Shared foundation loaded by every other module. Provides:

- `VUI.Print()` / `VUI.PrintOnOff()` — standard print formatter
- `VUI.SmoothFade` — per-frame fade driver (replaces Blizzard's conflict-prone `UIFrameFadeIn`/`UIFrameFadeOut`)
- `VUI.SafeHide` / `VUI.SuppressFrame` — idempotent hide with `Show`-hook re-suppression; combat-safe via `CombatQueue`
- `VUI.HookPlayerFrameFade` — event-timing player-frame fade that works around Midnight's Secret Values on `UnitHealth`
- `VUI.CombatQueue.Add` — defer an action until `PLAYER_REGEN_ENABLED`
- `VUI.RegisterSettingsLabel` — registers a category so the shared **Reload UI** button appears on the Settings panel when that category is active

### VeritasUI_CleanSolo

UI decluttering for a cleaner solo experience.

- **Fade Chat Tabs** — tabs fade in sync with the chat window; reappear on mouseover
- **Hide Social Button** — removes the Quick Join / Communities toast
- **Hide Chat Buttons** — removes scroll buttons and the new-window button
- **Hide Voice Chat Button** — removes the voice chat icon
- **Fade Micro Menu** — bottom-right menu fades unless moused over
- **Fade Player Frame** — player frame fades when out of combat, at full health, and not moused over
- **Hide Bag Buttons** — hides the bag bar (press `B` to open bags)
- **Hide Macro Names** — removes macro name text from action bar buttons
- **Hide Error Text** — suppresses red center-screen error messages

Settings: **Options → AddOns → Clean Solo** · Slash: `/cs`, `/cleansolo`

### VeritasUI_HUDFrame

Blizzard-native chat anchor frames and interactive data text bars, styled to match Midnight's panel chrome.

- **Two chat anchor frames** (`ButtonFrameTemplate`) flanking the chat region; `ChatFrame1` and `ChatFrame2` are left under Blizzard's native position management
- **One center data bar** above the action bar cluster with a custom `_UI-Frame-Metal-EdgeTop` chrome strip
- **Interactive data points with hover tooltips** — `fps`, `latencyWorld`, `latencyHome`, `haste`, `mastery`, `crit`, `armor`, `ilvl`, `memory`, `durability`, `gold`, `guild`, `friends`, `zone`, `spec`, `empty`
- **Click actions** — `spec` opens a spec-switch menu; `gold` opens the currency tab; `durability`/`ilvl` open the character panel; `memory` forces a GC pass; `guild`/`friends` open their respective panels
- **Tiered color system** — `fps`, `latency`, `memory`, and `durability` use green/yellow/red thresholds
- **Drag-to-move** layout with `/hud move` / `/hud lock`; positions persist across sessions
- **Settings panel** with per-slot dropdowns and frame-size sliders

Settings: **Options → AddOns → HUD Frame** · Slash: `/hud`, `/hudframe` (subcommands: `move`, `lock`, `reset`, `config`, `list`, `layout`, `set <bar> <slot> <key>`)

### VeritasUI_QualityOfLife

Functional enhancements that do not fit the "hide/fade" category.

- **Map Coordinates** — player and cursor coordinates on the World Map using native tooltip backdrop textures; draggable with a lock/unlock icon button; position persists across sessions
- **Show Item Levels** — color-coded ilvl overlays on bags, bank, warband bank, character panel, and merchants; quest rewards and the Heart of Azeroth are explicitly excluded
- **Auto Sell Junk** — event-driven batched sell (9 per cycle, gated on `BAG_UPDATE_DELAYED`); reports earnings via `GetMoney()` delta for accuracy under Midnight's Secret Values
- **Auto Repair** — guild-funds-first repair, then personal-gold remainder; reports the split
- **`/way` TomTom-compatible waypoints** — `/way #mapID x y [label]`, `/way x y [label]`, or `/way clear`; places a native `C_Map.SetUserWaypoint` pin and activates the minimap directional arrow; auto-clears within 10 yards of the target

Settings: **Options → AddOns → Quality of Life** · Slash: `/qol`, `/qualityoflife`, `/way`

### VeritasUI_PriorityRotation

One-button spell cycling system for accessibility.

- Cycles through a configurable spell list on each key press via external key repeat (e.g. Logitech G-Hub at 50ms)
- Uses a `SecureHandlerWrapScript` restricted snippet for zero-taint combat execution — no addon code runs during rotation
- Three action-bar override strategies: direct slot lookup, Bartender4/ElvUI attribute scan, and `SetOverrideBindingClick` fallback
- Per-character/realm/spec profiles with 18 starter spell lists covering all modern specs
- Drag-and-drop editor with spellbook and macro integration
- Dynamic icon on the overridden bar button shows the next spell in the cycle (updates even in combat)
- Frequency tuning per spell: `freq == 1` entries are cooldowns, `freq > 1` entries are fillers repeated that many times; the compiler zippers them so cooldowns come up on a predictable cadence
- **Auto-manages `ActionButtonUseKeyDown` CVar** — sets to `0` when enabled (required for key-up cycling), restores to `1` when disabled. No manual Press and Hold Casting toggling required.

Settings: **Options → AddOns → Priority Rotation** · Slash: `/pr`, `/priorityrotation` (subcommands: `settings`, `clear`, `reset`, `scan`, `macro`, `test`, `help`)

### VeritasUI_ZoneQuests

Zone-specific quest filtering via the native Objective Tracker.

- Filters the Objective Tracker so only current-zone quests appear
- Zone matching via `C_Map` parent-hierarchy walk (capped at depth 20) plus directional prefix stripping and bidirectional substring match
- Always-show toggles for Campaign, Important, Legendary, Meta, and Repeatable (daily/weekly) quests
- Preserves the super-tracked quest (minimap arrow) regardless of zone
- Debounced `QUEST_LOG_UPDATE` handling with cache invalidation on zone changes

Settings: **Options → AddOns → Zone Quests** · Slash: `/zq`, `/zonequests` (subcommands: `on`, `off`, `refresh`, `debug`)

## Installation

1. Download the latest release zip from the [Releases page](https://github.com/NQV4X0QN/VeritasUI/releases).
2. Extract the archive. It contains six `VeritasUI_*` folders at the top level.
3. Copy all six folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
4. Reload (`/reload`) or restart the game.

Folder names must exactly match the TOC filenames — this is a WoW requirement.

## Requirements

- World of Warcraft: Midnight (Patch 12.0.5, Interface 120005)
- No external library dependencies — fully self-contained (no Ace3, LibStub, Masque, or similar)

## Design Philosophy

- **Native only** — Blizzard APIs and assets exclusively; no custom UI chrome, no third-party libraries
- **Invisible integration** — settings panels, fonts, textures, spacing, and button styling match the default UI exactly
- **Retail-only** — no backward-compatibility scaffolding; if an API was removed in Midnight, the module adapts rather than keeping legacy branches
- **Modules independent** — each `VeritasUI_*` folder is its own AddOn; the only shared surface is `VeritasUI_Lib`
- **Tradeoffs disclosed** — limitations are documented in the CHANGELOG and in settings tooltips rather than silently papered over

## Known Limitations

- **Midnight Secret Values** — `UnitHealth`, `GetHaste`, `GetMasteryEffect`, `GetCritChance`, `C_Item.GetDetailedItemLevelInfo`, and similar APIs can return opaque values in certain contexts. All such calls are `pcall`-wrapped and degrade gracefully to `"—"` when unreadable. Player Frame fade uses `UNIT_HEALTH` event timing as a workaround.
- **`IsQuestWatched` removed** — Midnight no longer exposes a way to query pre-existing quest watch state. ZoneQuests' "restore on disable" behavior is a best-effort snapshot of all non-hidden quests at enable time.
- **Quest reward item levels** — async data loading and base-vs-effective ilvl mismatch make reliable display impractical; quest reward ilvls are intentionally not shown.

## Distribution

VeritasUI is published on GitHub Releases only. It is not distributed through CurseForge, Wago, or WoWInterface.

## License

GNU General Public License v2.0 — see [LICENSE](LICENSE) for details.
