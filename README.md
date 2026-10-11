# VeritasUI

A personal World of Warcraft addon suite for **Midnight** (12.1.0 "Curse of Ula'tek", Interface 120100), focused on solo play quality-of-life improvements.

VeritasUI uses Blizzard's native APIs exclusively and matches Blizzard's UI aesthetics — fonts, spacing, layout, and settings panels are designed to be indistinguishable from the default UI. Most features are configurable through the standard **Options → AddOns** panel, with slash commands available for quick access.

## Modules

### VeritasUI_Lib
Shared utility library loaded by all other modules. Provides the common print formatter, smooth per-frame fade manager (replacing Blizzard's conflicting `UIFrameFadeIn`/`UIFrameFadeOut`), player frame fade with event-timing health detection, frame suppression helpers (`SafeHide`/`SuppressFrame`), hover-fade hooks, a combat-deferral queue (`CombatQueue`), managed-panel helpers wrapping Blizzard's `UIPanelWindows` system, and the shared settings panel infrastructure including the Reload UI button.

### VeritasUI_CleanSolo
UI decluttering for a cleaner solo experience.

- **Fade Chat Tabs** — tabs fade in sync with the chat window, reappear on mouseover
- **Transparent Chat Background** — removes the chat window's background and edge so only the text shows
- **Hide Social Button** — removes the Quick Join / Communities toast
- **Hide Chat Buttons** — removes scroll buttons and the new-window button
- **Hide Voice Chat Button** — removes the voice chat icon
- **Fade Micro Menu** — bottom-right menu fades unless moused over
- **Fade Player Frame** — player frame fades when out of combat, at full health, and not moused over (uses event-timing via `UNIT_HEALTH` to work around Midnight's Secret Values)
- **Fade Action Bars** — per-bar multi-select fading (bars 2–8) that reappear on mouseover; survives Edit Mode changes
- **Hide Bag Buttons** — hides the bag bar (use `B` to open bags)
- **Hide Macro Names** — removes macro name text from action bar buttons
- **Hide Error Text** — suppresses red center-screen error messages

Settings: **Options → AddOns → Clean Solo** | `/cs`

### VeritasUI_QualityOfLife
Functional enhancements that don't fit the "hide/fade" category.

- **Minimap Coordinates** — shows your coordinates directly below the minimap; hidden where the game gives no position. For World Map coordinates use WoW's own option (Options > Interface); VeritasUI's former map readout was retired in v1.17.9 and turns that option on for anyone who had it enabled
- **Item Level Overlays** — shows color-coded item levels on gear in bags, character panel, bank, warband bank, and merchant windows; uses a universal `SetItemButtonQuality` hook with a dedicated merchant scanner
- **Auto Sell Junk** — automatically sells gray items when visiting a merchant using event-driven batch selling; reports earnings by summing item sell prices, independent of any concurrent gold deductions (e.g. AutoRepair on the same merchant frame)
- **Auto Repair** — automatically repairs gear at repair merchants, with a **Repair Funding** option (Guild + Personal, or Personal Only) and source reporting; honors the `[noautorepair]` guild-info tag
- **AFK Screen** — a cinematic full-screen overlay when you go AFK (character name, level, item level, zone, and clock over a slow camera orbit), useful for reducing OLED burn-in; dismissed on movement
- **Show Delve Nemesis Count** — adds the remaining enemy-group count to the Delve objective plaque, reading it from the widget's spell description where Blizzard only exposes it in prose
- **Journeys experience-bar toggle** — adds the "Show as Experience Bar" checkbox that Blizzard ships on Renown cards but omits from the Journeys "Encounters" cards, so Delves and Prey progress can be watched on the status bar like any other reputation
- **Click a status bar to open its window** — left-click the reputation bar to jump straight to that faction's Journeys page (or Character → Reputation for factions without one), or the Honor bar to open the PvP UI; clicking again closes it
- **TomTom-compatible Waypoints** — `/way #mapID x y [label]` or `/way x y [label]` places a native Blizzard waypoint pin and activates the minimap directional arrow; `/way clear` removes it; reads the same format used by most online guides (e.g. `/way #2351 45.2 56.3`)

Settings: **Options → AddOns → Quality of Life** | `/qol` | `/way`

### VeritasUI_PriorityRotation
One-button spell cycling system for accessibility.

- Cycles through a configurable list of spells, macros, and trinkets on each key press via external key repeat
- Uses a `SecureHandlerWrapScript` restricted snippet for zero-taint combat execution
- A keybind-override mechanism routes a real keybind to the hidden secure button so the rotation fires from a normal action-bar press
- Per-spec profiles with drag-and-drop editor — supports spellbook spells, `/macro` macros, and equipped trinkets
- `PortraitFrameTemplate` settings window registered as a Tier A UIPanel (behaves like Blizzard's Journeys/Collections panels)
- Built-in Tools section: spec switcher dropdown, Spellbook and Macros toggle buttons
- Frequency tuning per entry for weighted distribution (interleave compiler)

Settings: `/pr` or `/pr settings`

### VeritasUI_ZoneQuests
Zone-specific quest tracking via the native Objective Tracker.

- Automatically manages quest watch state so only current-zone quests appear
- Location-based filtering: quests are matched by their objectives' actual map (`C_QuestLog.GetQuestsOnMap` + per-POI `mapID` against the current zone and its sub-areas), so quests filed under activity headers still show when they're genuinely local, and neighbouring-zone bleed-in is rejected
- Always-show categories configurable: Campaign, Important, Legendary, Meta, Repeatable
- Event-debounced updates to handle `QUEST_LOG_UPDATE` bursts

Settings: **Options → AddOns → Zone Quests** | `/zq`

### VeritasUI_AdvancedOptions
Curated hidden settings and full CVar browser.

- **Featured tab** — 9 collapsible categories (Camera, Nameplates, Combat Text, Action Bars, Targeting & Mouse, Tooltips & UI, Chat, Graphics, Accessibility) with ~38 hand-picked hidden settings using native checkboxes, sliders, and dropdowns. Per-control reset-to-default and restart indicators for GX-restart CVars
- **All CVars tab** — searchable browser listing every CVar on the client. Star-favourite system (persists across sessions, sorts to top), click-to-expand inline editor, modified-value highlighting, native scrollbar
- CVar enumeration uses a multi-strategy fallback (`C_Console.GetAllCommands()` → legacy `ConsoleGetAllCommands()` → a known-CVar probe list via `C_CVar.GetCVarInfo`); on Midnight, which removed `C_Console`, the probe-list strategy is what resolves

Settings: **Options → AddOns → Advanced Options** | `/ao`

### VeritasUI_AuctionHouse
Auction House price tracking and selling convenience, built entirely on the native Auction House frame.

- **Price database** — a **Scan** button on the Auction House frame sweeps the whole auction house and records the current lowest price and quantity seen for every item listed, stored account-wide; you can also run one with `/ah scan`
- **Scan button states** — the button tells you where a scan stands at a glance: ready to scan, counting down the cooldown between scans, or working through results
- **Scan progress bar** — a progress readout next to the money frame at the bottom of the Auction House, visible on the Buy, Sell and Auctions tabs alike
- **Tooltip prices** — shows the latest market price on item and battle-pet tooltips, styled to match Blizzard's own "Sell Price:" line. Prices stay available everywhere, including away from the Auction House
- **Sell strip** — a strip of your sellable bag items on the Sell tab. Right-click one to load it into Blizzard's sell form, then left-click it again (or press Create Auction) to post; Shift-Left-click hides it from the strip. Loading works through Blizzard's own bag window, so your bags need to be open — with a bag addon that replaces Blizzard's bags, load items from that addon instead
- **Steady Create Auction button** — the Sell tab's Quantity row stays visible even when you only have one of an item, so the form never changes height and "Create Auction" does not move between listings
- **Reagents value on crafting orders** — adds a "Reagents Value:" line to Blizzard's Place Crafting Order form showing what the recipe's reagents are worth at the last scanned price, so a commission can be judged against material cost; works away from an auctioneer
- Settings hold the three tooltip-display toggles and the crafting-order reagents line

Settings: **Options → AddOns → Auction House** | `/ah`

## Installation

1. Download the latest `VeritasUI-vX.Y.Z.zip` from the [Releases page](https://github.com/NQV4X0QN/VeritasUI/releases/latest) — the zip contains only the seven addon folders, nothing to sort through
2. Extract it and copy all seven `VeritasUI_*` folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Keep the folder names exactly as they are — WoW requires each folder name to match its `.toc` filename
4. Reload or restart the game

All seven modules move in lockstep on a single version number, so install them together; `VeritasUI_Lib` is required by every other module.

## Requirements

- World of Warcraft: Midnight (Patch 12.1.0, Interface 120100)
- No external library dependencies — fully self-contained

## Design Philosophy

- **Native only** — Blizzard APIs exclusively, no custom UI chrome
- **Invisible integration** — settings panels, fonts, and spacing match the default UI exactly
- **Solo-focused** — every feature targets the single-player experience
- **Tradeoffs disclosed** — if a feature has a cost or limitation, it's documented and configurable

## Known Limitations

- **Press and Hold Casting** must be disabled for Priority Rotation to function (the addon handles this automatically with a one-time notification)
- **Quest reward item levels** are not displayed — async data loading and base vs. effective ilvl mismatch make reliable display impractical; this is an open problem for future work
- **Secret Values** in Midnight prevent direct health reading from addon code — the player frame fade uses event-timing as a workaround

## License

This project is licensed under the GNU General Public License v2.0 — see [LICENSE](LICENSE) for details.
