# Changelog

All notable changes to VeritasUI are documented here. Dates reflect the conversation sessions where changes were developed and tested.

## [1.5.0] - 2026-04-23

### Added

- **[HUDFrame] Three independent panel bars** — the single panel bar is replaced with a three-bar system (`HUF.panelBars[1..3]`). Each bar has its own position, width (300–1200px slider), slot layout, and visibility. Default slot layouts: bar 1 = stats (`haste`/`mastery`/`crit`/`armor`/`ilvl`), bar 2 = performance + currency (`fps`/`latencyWorld`/`memory`/`durability`/`gold`), bar 3 = social + zone (`spec`/`zone`/`friends`/`guild`/`empty`). Bars 2 and 3 default to hidden

- **[HUDFrame] Per-frame visibility checkboxes** — Blizzard AddOn settings panel now has a master "Enable HUD Frame" toggle plus five sub-checkboxes: Show Left Chat Frame, Show Right Chat Frame, Show Panel Bar 1, Show Panel Bar 2, Show Panel Bar 3. Master toggle gates the sub-toggles

- **[HUDFrame] Per-bar full-width mode** — each panel bar can be toggled between `normal` (anchored width from slider) and `fullwidth` (edge-to-edge `LEFT`/`RIGHT` anchors across the screen). Controlled via a new Mode dropdown in `/hud config` or the new `/hud mode <idx> <normal|fullwidth>` slash subcommand. In fullwidth mode the bar is draggable vertically but X position is locked to screen edges; the width slider for that bar is automatically disabled while preserving its stored value

- **[HUDFrame] Zones for full-width bars** — fullwidth bars support three named zones (left, center, right), each holding up to 4 slots. Left-zone slots anchor to the left screen edge; right-zone slots anchor to the right screen edge; center-zone slots center on the bar midline. Normal-mode bars continue to use the existing single slot list unchanged. Mode toggle preserves both layouts — switching back to normal restores the pre-fullwidth slot list; switching back to fullwidth restores the pre-normal zones. No data loss in either direction

- **[HUDFrame] `/hud mode <1|2|3> <normal|fullwidth>`** — new slash subcommand to toggle a panel bar's display mode from the command line

- **[HUDFrame] `/hud set panelzone <idx> <left|center|right> <slot#> <key>`** — new slash subcommand to set zone slots on fullwidth bars

- **[Repo] `PANELBAR_DESIGN_CONSTRAINTS.md`** — companion document (stored alongside the VeritasUI AI development skill) captures the load-bearing rationale for `CreatePanelBar`'s `ButtonFrameTemplate`-plus-hidden-chrome approach and the `PortraitContainer` repurposing. Protects the rendering internals from future "simplification" passes

### Changed

- **[HUDFrame] Internal rename `centerBar` → `panelBar`** — function names (`CreateCenterBar` → `CreatePanelBar`), DB keys (`centerBarPos` → `panelBarPos`, `centerBarWidth` → `panelBarWidth`, `layout.centerBar` → `layout.panelBar`), Config constants (`CENTER_BAR_W`/`Y` → `PANEL_BAR_W`/`Y`), settings labels, and slash commands are all updated. One-time DB migration handles the rename automatically on first load after upgrade. `/hud set center` retained as a back-compat alias that resolves to panel bar 1

- **[HUDFrame] `/hud set panel`** — accepts both 2-arg (`panel <slot> <key>`, back-compat targeting bar 1) and 3-arg (`panel <barIdx> <slot> <key>`, target specific bar) forms

- **[HUDFrame] `/hud layout`** — output now shows each panel bar's mode alongside its slot list; fullwidth bars print a three-line zone breakdown (left/center/right, em-dash for empty zones)

- **[HUDFrame] `/hud reset`** — now also resets per-bar mode back to `normal` and re-seeds empty zone subtables, producing an immediately-consistent runtime state without requiring `/reload`

- **[HUDFrame] Settings panel** — window resized to 520×1000 to accommodate three stacked Panel Bar sections with Mode dropdown and mode-aware slot editor (5 slots in normal mode, 3×4 zone grid in fullwidth mode). Frame Sizes section now has three independent width sliders, one per bar (300–1200px range)

- **[HUDFrame] Rendering pipeline refactor** — `BuildBar` extended with an optional `zones` parameter; fullwidth bars render via a new `BuildZone` helper that distributes FontStrings at edge-aligned positions. Interactive slot wiring (clickFrame, highlight texture, tooltip handlers) extracted into a shared `CreateInteractiveSlot` helper used by both rendering paths

- **[HUDFrame] Zone slot spacing** — `ZONE_SLOT_GAP` tuned to 180px after in-game verification. 100px caused overlap on wider data text (`Mastery: 69.3%`, `Zone: Silvermoon City`); 180px gives comfortable margin for the widest data points

- **[Repo] CHANGELOG normalization** — historical entries (v1.0.0–v1.4.2) retroactively conformed to the skill's formatting rules: hyphen date separators, `-` bullet markers, trailing periods removed, redundant `---` dividers collapsed. The `## Pre-VeritasUI History` appendix is preserved at `####` subheader level

- **[Repo] README rewrite** — updated for Interface 120005, added the `VeritasUI_HUDFrame` module documentation (previously missing), refreshed all module feature lists, removed the stale "Press and Hold Casting must be disabled" note (v1.3.19 made `PriorityRotation` auto-manage the CVar), clarified GitHub-only distribution

- **[Repo] GitHub Releases normalization** — all 46 prior releases (v1.0.0–v1.4.2) had their bodies and titles normalized to the current format (`**Added**` bold section headers, `-` bullet markers). Releases that previously had bare `vX.Y.Z` titles gained descriptive suffixes

### Fixed

- **[HUDFrame] Shared-reference bug in defaults table** — first-time DB init now deep-copies subtable defaults (`visibility`, `panelBarWidth`, `panelBars`) rather than sharing references with the `defaults` constant. Prevents silent state leaks across reloads if a user mutated a subtable value

### Requires

- World of Warcraft: Midnight (Patch 12.0.5, Interface 120005) — unchanged from v1.4.2

## [1.4.2] - 2026-04-22

### Changed

- **[HUDFrame] Chat frame decoupled from anchor frames** — `MirrorAnchorToChatFrame` is now a no-op; `SyncOneAnchor` only restores the anchor's own saved position. Chat frames are left entirely to Blizzard's native position management

- **[HUDFrame] Interactive data points with hover tooltips** — `BuildBar` now creates a `Button` click surface for any data point declaring `onClick` or `onEnter`. Hovering shows a `GameTooltip` with the data point label, optional detail lines, and a click hint. A subtle `ADD`-blend highlight texture appears on hover

- **[HUDFrame] Tiered color system expanded** — `FormatSlot` checks `tierColor` before `warnThreshold`/`warnColor`. `fps`, `latencyWorld`, `latencyHome`, `memory`, and `durability` now use green/yellow/red tier coloring based on thresholds

- **[HUDFrame] New data points: `fps`, `latencyWorld`, `latencyHome`** — Display framerate and world/home latency with tiered colors

- **[HUDFrame] `spec` — click to switch specialization** — Opens a `MenuUtil` context menu listing all available specs; blocked in combat with an error frame message. Hover shows role and primary stat

- **[HUDFrame] `durability` — click opens character panel; hover shows per-slot breakdown** — Replaced `warnThreshold`/`warnColor` with `tierColor` (≥50% green, ≥20% yellow, below red)

- **[HUDFrame] `gold` — click opens currency tab; hover shows gold/silver/copper** — `math_floor` usage normalized to `math.floor`

- **[HUDFrame] `guild` — click opens guild panel; hover shows name and online count**

- **[HUDFrame] `friends` — click opens friends list; hover shows online/total count**

- **[HUDFrame] `zone` — hover shows zone, subzone, and player map coordinates**

- **[HUDFrame] `memory` — click forces garbage collection; hover shows top-10 addon memory usage**

- **[HUDFrame] `ilvl` — click opens character panel; hover shows overall, equipped, and PvP item levels**

## [1.4.1] - 2026-04-22

### Changed

- **[HUDFrame] Chat anchor Inset repositioned** — `ButtonFrameTemplate`'s `Inset` region on left/right chat anchor frames is now explicitly repositioned to `TOPLEFT 10, -25` / `BOTTOMRIGHT -5, 26`, aligning the dark interior fill with the visible chrome border edges

## [1.4.0] - 2026-04-22

### Changed

- **[HUDFrame] Center bar chrome strip reworked** — `_UI-Frame-Metal-EdgeTop` atlas strip is anchored via explicit two-point `TOPLEFT`/`TOPRIGHT` rather than `SetAllPoints`; `true` flag passed to `SetAtlas` for correct atlas sizing. All NineSlice pieces plus the parent `NineSlice` frame are now fully hidden via `ns:Hide()`

- **[HUDFrame] ButtonFrameTemplate residual regions cleaned up** — A `cleanupKeys` loop hides `Inset`, `Bg`, `bgTex`, `TopTileStreaks`, `TitleBg`, `PortraitFrame`, `PortraitFrameBg`, `Portrait`, `Shadow`, and `shadowTex` on the center bar, removing any leftover template chrome

- **[HUDFrame] `bar.blizzBar` alias added** — `bar.blizzBar = bar.PortraitContainer` stored for potential use as a data-text host frame

- **[HUDFrame] `textFrame` child removed from center bar** — FontStrings are now created directly on the bar frame at OVERLAY sublevel 7, which clears all NineSlice draw layers without requiring a separate high-level child frame

- **[HUDFrame] Center bar FontStrings anchored `BOTTOM, -7`** — Places data text on the chrome strip rather than at the geometric center of the bar frame

- **[HUDFrame] `BAR_HEIGHT` increased to 26px** — Provides enough height for the chrome strip plus readable data text

- **[HUDFrame] Move-mode tint checks `stripTex` first** — `ApplyMoveTint`/`ApplyNormalTint` now tint `bar.stripTex` when present before falling back to `NineSlice`

- **[Repo] `.gitattributes` added** — Enforces LF line endings for all `.lua`, `.toc`, `.md`, and `.xml` files, eliminating CRLF conversion warnings on Windows

## [1.3.39] - 2026-04-21

### Changed

- **[HUDFrame] Center bar simplified to single BottomEdge chrome strip** — `TopEdge` added to the NineSlice hide list; only `BottomEdge` (the gray UIFrameMetal strip) now renders. `bgTex` background texture removed entirely — the bar is transparent except for the chrome strip. `ApplyMoveTint`/`ApplyNormalTint` `bgTex` branches removed accordingly

- **[HUDFrame] Center bar textFrame overlay for reliable FontString rendering** — A child `Frame` (`bar.textFrame`) set to `bar:GetFrameLevel() + 600` is created on the center bar. `DataText.lua` parents FontStrings to `barFrame.textFrame` when present so they render above all NineSlice layers

- **[HUDFrame] BAR_HEIGHT reduced to 20px** — Matches the BottomEdge chrome strip height on UIFrameMetal so the center bar frame is exactly the strip with no extra space

## [1.3.38] - 2026-04-21

### Fixed

- **[HUDFrame] Center bar NineSlice Center hidden; background texture restored** — `ns.Center` (the NineSlice's internal fill, which rendered above FontStrings at high frame level) is now included in the hide list alongside corners and side edges. A plain `BACKGROUND`-layer texture using `UI-DialogBox-Background-Dark` is created directly on the bar frame and stored as `bar.bgTex`, restoring the dark fill at a draw layer that FontStrings render above

- **[HUDFrame] Move-mode tinting covers bgTex** — `ApplyMoveTint`/`ApplyNormalTint` now also tint `entry.frame.bgTex` when present (warm yellow on unlock, white on lock), guarded by a nil check so the chat anchor frames are unaffected

## [1.3.37] - 2026-04-21

### Changed

- **[HUDFrame] Center bar corners and side edges hidden for clean thin rendering** — `CreateCenterBar` remains `ButtonFrameTemplate` but the four NineSlice corner pieces and left/right edge bars are explicitly hidden after frame creation. Only the top and bottom UIFrameMetal chrome strips render, running the full bar width with no geometry at the ends. This avoids corner distortion at 22px height without texture coordinate hacks

- **[HUDFrame] Move-mode tinting unified across all three frames** — `ApplyMoveTint`/`ApplyNormalTint` now dispatch on `NineSlice` presence for all hudFrames entries. Since all three frames (left anchor, right anchor, center bar) are `ButtonFrameTemplate`, the `isAnchor`/`SetBackdropColor` branch is removed entirely

## [1.3.36] - 2026-04-21

### Fixed

- **[HUDFrame] Center bar NineSlice corner overlap at thin heights** — Added `ResizeCorner` logic inside `CreateCenterBar`. All four NineSlice corner pieces are resized to `math.floor(BAR_HEIGHT / 2)` pixels (11px at the default 22px height), preventing corners from overlapping each other at the center of the bar. Texture coordinates are adjusted to preserve the correct corner slice of the atlas

## [1.3.35] - 2026-04-21

### Changed

- **[HUDFrame] Left/right data text embedded into chat anchor bottom chrome** — Eliminated the separate left and right `BackdropTemplate` data bar frames entirely. Data text `FontStrings` for the left and right bars are now created directly on the `ButtonFrameTemplate` chat anchor frames, positioned at `BOTTOM+8` so they render inside the bottom chrome strip. This makes the data text an integral part of each chat panel, matching Blizzard's own design language

- **[HUDFrame] Center bar data text unchanged** — Center bar remains a standalone `ButtonFrameTemplate` frame with data text centered vertically, unchanged from v1.3.34

- **[HUDFrame] DataText.lua BuildBar takes mount-point parameters** — `BuildBar()` now accepts optional `mountPoint` and `yOffset` arguments. Left/right bars pass `"BOTTOM", 8`; center bar uses the default `"CENTER", 0`. The `_vuiSlots` table and ticker now reference `leftAnchor`/`rightAnchor` directly rather than the removed bar frames

- **[HUDFrame] Frame Sizes slider section in config panel** — `/hud config` now includes a "Frame Sizes" section with `OptionsSliderTemplate` sliders for left chat width (200–700), left chat height (80–500), right chat width (200–700), right chat height (80–500), and center bar width (300–800). Each slider updates live, saves to `VeritasUI_HUDFrameDB`, and immediately resizes the frame. Chat frames track anchor size changes via `MirrorAnchorToChatFrame`. Center bar width triggers a full `RebuildAllBars()` so FontStrings redistribute. Panel height extended to 580px

- **[HUDFrame] Saved size defaults** — New DB keys (`leftAnchorWidth`, `leftAnchorHeight`, `rightAnchorWidth`, `rightAnchorHeight`, `centerBarWidth`) initialized from `defaults` table on ADDON_LOADED. Matching constants added to `Config.lua`. `SetupHUDFrame` reads these values from DB so saved sizes persist across sessions

## [1.3.34] - 2026-04-21

### Changed

- **[HUDFrame] Center data bar switched to ButtonFrameTemplate** — `CreateCenterBar()` replaces the `BackdropTemplate` approach used previously. Portrait, `TitleContainer`, and `CloseButton` hidden so only the NineSlice metallic border renders, matching the two chat anchor frames exactly. All three elements now share the same border treatment

- **[HUDFrame] Move-mode tinting uses NineSlice presence check** — `ApplyMoveTint`/`ApplyNormalTint` now detect frame type by checking `entry.frame.NineSlice` rather than the `isAnchor` flag. Any `ButtonFrameTemplate` frame (both chat anchors and center bar) tints via `NineSlice:SetVertexColor`; `BackdropTemplate` frames (left/right bars) continue to use `SetBackdropColor`

## [1.3.33] - 2026-04-21

### Changed

- **[HUDFrame] Chat anchors switched to ButtonFrameTemplate** — Replaced `BackdropTemplate` on the two chat anchor frames with `ButtonFrameTemplate` (the same template used by Journeys, Appearances, bags, and other Blizzard panels). Portrait hidden via `ButtonFrameTemplate_HidePortrait`; `TitleContainer` and `CloseButton` hidden so only the NineSlice metallic border renders. `SetFrameStrata("BACKGROUND")` and `SetFrameLevel(1)` preserved

- **[HUDFrame] Chat frame 12px inset from ButtonFrameTemplate border** — `MirrorAnchorToChatFrame` (drag-stop) and both paths of `SyncOneAnchor` (PLAYER_ENTERING_WORLD) updated to position chat frames 12px inset inside their anchor using two-point anchor-relative positioning. On first load with no saved position, the anchor wraps 12px outside the Blizzard-placed chat frame

- **[HUDFrame] Move-mode tinting split for anchors vs bars** — `ApplyMoveTint`/`ApplyNormalTint` re-diverged by `isAnchor`: anchors tint via `NineSlice:SetVertexColor(1, 0.85, 0.3)` / restore `(1, 1, 1)`; bars keep `SetBackdropColor` as before

## [1.3.32] - 2026-04-21

### Changed

- **[HUDFrame] Backdrop colors use Blizzard globals** — `SetBackdropColor` and `SetBackdropBorderColor` on all five HUD frames (two chat anchors, three data bars) now reference `TOOLTIP_DEFAULT_BACKGROUND_COLOR` and `TOOLTIP_DEFAULT_COLOR` instead of hardcoded warm-dark values. Frames automatically match every other native Blizzard UI element and inherit any future Blizzard color changes. Move-mode warm highlight (`0.15, 0.12, 0.05, 0.95`) remains intentional and unchanged. `ApplyNormalTint` restores using `TOOLTIP_DEFAULT_BACKGROUND_COLOR`

## [1.3.31] - 2026-04-21

### Fixed

- **[HUDFrame] SettingsPanel TitleText nil error** — Guarded the title text assignment against both `ButtonFrameTemplate` structures: tries `win.TitleContainer.TitleText` first (current retail), falls back to `win.TitleText` (older structure)

- **[HUDFrame] Data bars switched to BackdropTemplate** — Replaced manual texture approach on all three data bars with `BackdropTemplate` + `ApplyBackdrop()`, matching the chat anchor style. Uses `edgeSize 10` (vs 16 on anchors) for appropriate weight at 22px bar height. Move-mode tinting simplified: all five HUD frames now call `SetBackdropColor` uniformly — the `isAnchor`/`bgTex` branch distinction is removed

## [1.3.30] - 2026-04-21

### Changed

- **[HUDFrame] Chat anchors: BackdropTemplate** — Replaced manual texture layering on chat anchor frames with Blizzard's `BackdropTemplate` + `ApplyBackdrop()`. Uses `UI-DialogBox-Background-Dark` fill and `UI-Tooltip-Border` edge, tinted dark warm (`SetBackdropBorderColor(0.3, 0.25, 0.2, 0.85)`). Move-mode tinting now calls `SetBackdropColor` on anchors (`0.15, 0.12, 0.05, 0.95`) and restores on lock (`0.06, 0.05, 0.04, 0.92`); `ApplyMoveTint`/`ApplyNormalTint` now diverge by `isAnchor`

- **[HUDFrame] Data bars: simplified to single top edge** — Removed bottom edge texture from data bars. Top edge layer changed to `BORDER` sublevel 1 with a warm-tinted color `(0.35, 0.28, 0.15, 0.9)` matching Blizzard's thin bar strip treatment. Base fill alpha bumped to 0.82

- **[HUDFrame] Settings panel: ButtonFrameTemplate** — Replaced `BasicFrameTemplate` with `ButtonFrameTemplate` for the layout config panel. Frame renamed to `VeritasUI_HUDFrameSettingsPanel`. Portrait hidden via `ButtonFrameTemplate_HidePortrait`. Title set via `win.TitleText`. Template's built-in `CloseButton` wired to hide the panel; manually created close button removed. Content area top inset adjusted from 26px to 32px to clear the taller title bar

- **[HUDFrame] DataPoints: updated API calls** — All `getValue` functions updated to current Midnight APIs: `GetHaste()`, `GetCritChance()`, `GetMasteryEffect()` (first return), `UnitArmor` second return (effective armor), `GetAverageItemLevel` second return (equipped ilvl), simplified gold format without color codes. Durability loops slots 1–18 directly. Spec uses `GetSpecialization`/`GetSpecializationInfo`. Guild drops `IsInGuild` guard, calls `GetNumGuildMembers` directly. All `getValue` bodies wrapped in `pcall`

- **[HUDFrame] Guild roster primed on load** — Added `pcall(C_GuildInfo.GuildRoster)` in the `ADDON_LOADED` handler so guild online count is available immediately without waiting for a manual query

## [1.3.29] - 2026-04-21

### Changed

- **[HUDFrame] Midnight-era visual restyle — chat anchors and data bars** — Removed all `SetBackdrop`/`BackdropTemplate`/DialogBox border and background textures from chat anchor frames and data bars. Replaced with pure `SetColorTexture` layering matching the Midnight UI aesthetic (Map & Quest Log, Journeys, Appearances panels):
  - **Chat anchors**: near-black warm fill `(0.05, 0.04, 0.03, 0.85)`; 1px white top highlight at 12% opacity; 1px warm gold accent at -1px offset at 25% opacity; 1px left/right edges at 6% white; 1px dark bottom edge. No border texture files. No gold filigree
  - **Data bars**: near-black fill `(0.04, 0.03, 0.02, 0.80)` for a lighter-weight read; 1px white top edge at 15% opacity; 1px black bottom edge at 50% opacity. No side edges. Move-mode highlight uses `SetVertexColor(0.9, 0.7, 0.15)` on the base fill only
  - **Center bar end-caps removed** — previously had gold side edges; bars now bleed to natural width
  - Move-mode tinting unified: both anchors and bars now use `bgTex:SetVertexColor` (anchors no longer called `SetBackdropColor`)

## [1.3.28] - 2026-04-21

### Changed

- **[HUDFrame] Data bar visual restyle (Fix 1)** — Removed all `SetBackdrop`/`BackdropTemplate` from data bar frames. Visuals now built from raw textures: `BACKGROUND` sublevel 0 uses `UI-DialogBox-Background-Dark` in REPEAT wrap mode (alpha 0.85); `BORDER` sublevel 1 adds a 2px gold top edge and 1px dark bottom edge via `SetColorTexture`. Move-mode tinting uses `bar.bgTex:SetVertexColor` instead of `SetBackdropColor`

- **[HUDFrame] Chat anchor rearchitecture (Fix 2)** — Stopped repositioning ChatFrame1/ChatFrame2 directly (which caused ChatFrameEditBox misalignment on zone transitions). Anchor frames now mirror chat frame position/size on `PLAYER_ENTERING_WORLD`. On DragStop, the anchor's new position is mirrored back to the corresponding chat frame. Chat frames are never re-parented or force-repositioned

- **[HUDFrame] Data point registry + slot system (Part 3)** — New `DataPoints.lua` file with `HUF.DataPoints` registry of 13 configurable data points: haste, mastery, crit, armor, ilvl, memory, durability, gold, guild, friends, zone, spec, empty. Each of the three bars has independently configurable numbered slots. Layout is persisted in `VeritasUI_HUDFrameDB`. `BuildBar` distributes FontStrings evenly; `RebuildAllBars` rebuilds from the current layout

- **[HUDFrame] Settings panel (Part 4)** — New `SettingsPanel.lua` with a standalone drag-to-move config panel (matches PriorityRotation's `BasicFrameTemplate` pattern). Opens via `/hud config`. UIDropDownMenu dropdowns for each slot across three sections (Left Bar, Right Bar, Center Bar). Escape closes via `UISpecialFrames` registration. Reset to Defaults + Close buttons

- **[HUDFrame] New file structure** — TOC now loads: `Core.lua`, `Config.lua`, `DataPoints.lua`, `SettingsPanel.lua`, `DataText.lua`. `HUDFrame.lua` is superseded by `Core.lua` and removed from the TOC load list (left on disk)

- **[HUDFrame] New slash commands** — `/hud config` opens the settings panel; `/hud set <bar> <slot> <key>` sets a slot from the command line; `/hud list` lists registered data point keys; `/hud layout` prints the current layout

## [1.3.27] - 2026-04-21

### Changed

- **[HUDFrame] Drag-to-move scaffolding** — All five HUD frames are now repositionable at runtime
  - `/hud move` enters move mode: frames receive a gold tint (anchors via `SetBackdropColor`, bars via `SetVertexColor` on the base texture) to signal they are draggable. Dragging snaps to screen edge via `SetClampedToScreen`
  - `/hud lock` exits move mode and restores normal tint. Dragging is a no-op while locked (default on login)
  - `/hud reset` clears all saved positions, moves frames back to their default layout, and locks
  - Positions (point, relPoint, x, y relative to UIParent) are persisted in `VeritasUI_HUDFrameDB` and restored on login. The left and right data bars follow their anchor frames automatically — only the two chat anchors and the center bar have independent drag handles
- **[HUDFrame] Bar texture restyle** — Replaced the flat `UI-Tooltip-Background` backdrop on data bars with a layered raw-texture approach:
  - `BACKGROUND` layer: `UI-DialogBox-Background-Dark` in `REPEAT`/`REPEAT` wrap mode — matches the warm charcoal-brown of the chat anchor interiors
  - `BORDER` layer: 2px gold top edge (`SetColorTexture(1, 0.82, 0, 0.6)`) and 1px gold bottom edge at reduced opacity (0.3) for depth
  - Center bar only: thin 1px vertical gold end-caps on the left and right edges
  - `BAR_HEIGHT` raised from 20 → 22 px in `Config.lua`

## [1.3.26] - 2026-04-21

### Added

- **[HUDFrame] New module: VeritasUI_HUDFrame** — Blizzard Midnight-style HUD with chat anchor frames and data text bars
  - Two chat anchor frames (left and right) using `UI-DialogBox-Background-Dark` and the gold filigree `UI-DialogBox-Border`, matching the Journeys/Appearances panel aesthetic. ChatFrame1 docks into the left anchor; ChatFrame2 into the right. Native chat functionality (tabs, scrolling, right-click menus) is fully preserved
  - Three DataText bars in Friz Quadrata TT at 11pt with a warm dark background and a single 1px gold hairline top edge:
    - **Left bar** (below left chat): Memory (MB), Durability (lowest slot %), Gold (g/s/c)
    - **Right bar** (below right chat): Guild online, Friends online, Current zone
    - **Center bar** (above action bar area): Haste %, Mastery %, Crit %, Armor (base), Avg item level
  - Labels in Blizzard gold `|cffffd100`, values in white `|cffffffff`, warnings (durability < 20%, memory > 80 MB) in red `|cffff4444`. Data points separated by an ornamental `•` glyph
  - All values update on a 2-second `C_Timer.NewTicker`. All stats using `GetCombatRatingBonus`, `GetMasteryBonus`, `UnitArmor`, and `GetInventoryItemDurability` are pcall-wrapped against Midnight secret value errors
  - Positions and thresholds are all named constants in `Config.lua`; `CENTER_BAR_Y` controls the center bar height above the action bar cluster
  - Settings panel at Options → AddOns → HUD Frame with enable/disable toggle. `/hud` slash command. Addon Compartment integration

## [1.3.25] - 2026-04-21

### Changed

- **TOC bump to Interface 120005** — WoW patch 12.0.5 is now live; updated all module TOC files from 120001 to 120005 for full compatibility

## [1.3.24] - 2026-04-16

### Fixed

- **TOC revert to Interface 120001** — v1.3.23 pre-bumped the interface version to 120005 for patch 12.0.5, but WoW rejects addons with a TOC version *higher* than the running client — there is no "load anyway" override for that direction. Reverted to 120001 so the addon loads correctly on live 12.0.1. The 120005 bump will be re-applied on patch day

## [1.3.23] - 2026-04-16

### Changed

- **TOC bump to Interface 120005** — Updated all module TOC files from 120001 to 120005 for WoW patch 12.0.5 compatibility

## [1.3.22] - 2026-04-11

### Fixed

- **[QualityOfLife] Auto Sell Junk gold reporting wildly inaccurate** — The tally used `C_Item.GetItemInfo` to look up each sold item's vendor price and multiply by stack count. In Midnight, `sellPrice` can return stale or secret values that pass the pcall arithmetic guard but contain bogus numbers, producing reported totals 20–30× the actual amount earned. Replaced with a `GetMoney()` delta approach: the player's gold is snapshotted before selling begins, and the reported amount is `GetMoney() - startMoney` after all items are gone, which is always accurate

## [1.3.21] - 2026-04-09

### Fixed

- **[All] Comprehensive code review hardening pass** — 16 findings addressed across all five modules:
  - **[PriorityRotation/Core] SafeQuote injection** — `InjectSequence` now dynamically selects a long-string nesting level that cannot appear in the macro body, eliminating the theoretical edge case where a macro containing `]==]` would corrupt the secure Execute call
  - **[PriorityRotation/Core] MAX_ACCOUNT_MACROS nil guard** — `UpdateMacroStub` now falls back to `120` if `MAX_ACCOUNT_MACROS` is nil, preventing a Lua error that would silently block macro creation in Midnight if the constant is renamed
  - **[PriorityRotation/Core] Remove dead WrapScript guard** — `if not step or not macros[step] then step = 1 end` was unreachable dead code after `step % #macros + 1`; removed
  - **[PriorityRotation/Core] Icon ticker only starts when a bar button is overridden** — Starting the ticker in Strategy 3 (keybind-only mode) caused a permanent 4 Hz idle ticker that immediately returned on every tick; ticker now only starts when `overriddenButton` is non-nil
  - **[PriorityRotation/Editor] Guard PanelTemplates_GetSelectedTab** — Added existence check before calling this Blizzard global, which could be nil or renamed in Midnight
  - **[CleanSolo] NUM_CHAT_WINDOWS nil guard** — Loop now uses `(NUM_CHAT_WINDOWS or 10)` to prevent a `compare number with nil` error if the constant is absent
  - **[CleanSolo] Chat tab scan skips missing frames** — Changed `break` on a missing chat frame to a `skip`; non-contiguous frame slots no longer abort the entire scan
  - **[CleanSolo] PLAYER_REGEN events moved into SetupPlayerFrameFade** — Combat enter/leave events are now only registered when the Player Frame Fade feature is active, eliminating unconditional event overhead for users with the feature disabled
  - **[CleanSolo] Document HideBagButtons retry pattern** — Added comment explaining why KillAll runs at 0s, 0.5s, and 2.0s (login-sequence re-show bursts from Blizzard bag frames)
  - **[QualityOfLife] AutoRepair race condition eliminated** — `GetRepairAllCost()` called synchronously after `RepairAllItems(true)` returns the pre-repair client-cached value before the server updates it, making the guild-vs-personal cost split unreliable. Now always follows guild repair with a personal repair call to cover any remainder, and reports the original total cost with a guild-bank note
  - **[QualityOfLife] Document bank slot magic number** — Added comment clarifying that the `28` slot-count limit in the SetItemButtonQuality hook refers to Midnight's bank container (-1) slot range
  - **[ZoneQuests] Skip BuildZoneNameSet when disabled** — Zone change events now invalidate the name cache but skip the expensive map-hierarchy rebuild when ZoneQuests filtering is off; the next enabled sync rebuilds lazily via `cachedNameSet or BuildZoneNameSet()`
  - **[ZoneQuests] HeaderMatches threshold lowered** — Substring fallback search now applies to zone names longer than 2 characters (was 4), catching short zone names like "Vale" that weren't matched by the exact-lookup path
  - **[ZoneQuests] Correct SnapshotWatched comment** — Comment previously said disabling ZQ "re-tracks everything"; corrected to accurately describe that RestoreWatched restores the snapshot taken at enable/login time, not at disable time
  - **[Lib] Remove unnecessary pcall on GetAlpha** — `GetAlpha()` never raises on a valid WoW Frame; replaced with a direct call. Alpha is a rendering property, not a game-state value subject to Midnight secret-value restrictions
  - **[Lib] HookAllChildren no longer called on every OnEnter** — MicroMenu child-hook registration now runs only once at setup; removed the redundant per-hover-enter iteration that fired on every mouse-enter of MicroMenu despite the `hooked[child]` guard

## [1.3.20] - 2026-04-07

### Fixed

- **[Lib] Restore Reload UI button in AddOn settings panel** — v1.3.12 replaced the working OnUpdate polling approach with an event-driven hook on `SettingsPanel.SelectCategory` which does not fire correctly in Midnight 12.0.1, causing the button to never appear. Reverted to the original 0.25s poll which works regardless of API shape

## [1.3.19] - 2026-04-07

### Changed

- **[PriorityRotation] Automatically manage `ActionButtonUseKeyDown` CVar** — PR now sets the CVar to `0` (key-up firing) on login when enabled and on toggle-on, and restores it to `1` (key-down / Press and Hold Casting) on login when disabled and on toggle-off. Previously the conflict was only warned about; users had to manage the CVar manually, leading to a permanently desynced state where neither PR nor P&H casting worked correctly

## [1.3.18] - 2026-04-07

### Fixed

- **[QualityOfLife] Guard item-level overlay against Midnight secret value errors in raid combat** — `C_Item.GetItemInfoInstant` and `C_Item.GetDetailedItemLevelInfo` can return secret values during raid encounters in 12.0.1; the comparisons `equipLoc ~= ""` and `ilvl <= 0` were outside any pcall, causing "attempt to compare secret value" Lua errors on every item button update (loot windows, gear inspection). Both comparisons are now wrapped in pcall so they degrade silently — overlays simply won't display for items with restricted data during encounters
- **[QualityOfLife] Guard auto-sell junk price tally against secret vendor prices** — `C_Item.GetItemInfo` returns vendor price as a secret value in Midnight; arithmetic on it (`qty * vp`) threw an unguarded error on every sell-session tally. Both the GetItemInfo call and the multiplication are now pcall-protected; if the price can't be read, the item count is still announced without a gold amount

## [1.3.17] - 2026-04-02

### Fixed

- **[ZoneQuests] Manually highlighted cross-zone quests now reliably preserved** — v1.3.16 attempted to use `QUEST_WATCH_LIST_CHANGED` to track player highlights but the event handler only captured one argument, so the `added` flag was always `nil` and the quest was never pinned; replaced the event-based approach entirely: `SyncTracking` now calls `C_SuperTrack.GetSuperTrackedQuestID()` directly at sync time and exempts the active super-tracked quest (the one with the minimap arrow) from zone-based removal; `SUPER_TRACKING_CHANGED` triggers a debounced re-sync so the quest is removed from the tracker promptly when the player clears the arrow

## [1.3.16] - 2026-04-02

### Fixed

- **[ZoneQuests] Manually highlighted cross-zone quests no longer auto-removed** — clicking a quest on the world map to set a minimap direction arrow triggered a zone-sync that immediately removed the quest from the Objective Tracker; the addon now tracks player-initiated highlight events via `QUEST_WATCH_LIST_CHANGED` and exempts those quests from zone-based removal until the player explicitly un-highlights them; quests un-highlighted while in a different zone are removed from the tracker normally

## [1.3.15] - 2026-04-01

### Fixed

- **[QualityOfLife] Fix Auto Sell Junk selling no items at all** — `MERCHANT_SHOW` fires before `MerchantFrame:IsShown()` returns `true`; the sell guard was immediately killing `sellState` and unregistering `BAG_UPDATE_DELAYED` before any items were sold. Fix: defer `AutoSellJunk()` by one frame with `C_Timer.After(0, AutoSellJunk)`

## [1.3.14] - 2026-04-01

### Fixed

- **[QualityOfLife] Fix Auto Sell Junk stopping prematurely when server-throttled items remain locked mid-batch; reduce batch size from 12 to 9 to stay within WoW's server-side sell rate limit (matches Scrap addon's approach)**

## [1.3.13] - 2026-03-31

### Fixed

- **[CleanSolo] Fix syntax error from v1.3.12 audit** — the `inCombat` variable deletion merged two `local` declarations onto one line (`falselocal`), producing a Lua syntax error that prevented CleanSolo from loading; all fading features (chat tabs, micro menu, player frame) were non-functional

### Removed

- **[TOC] Revert Addon Compartment IconTexture** — removed the `## IconTexture` directive added in v1.3.12; the modules now use the default compartment icon as before

## [1.3.12] - 2026-03-31

### Changed

- **[Lib] SmoothFade zero-allocation iteration** — replaced `pairs()` iterator in the OnUpdate handler with `next()`-based traversal, eliminating a per-frame closure allocation during active fades
- **[Lib] Event-driven reload button visibility** — replaced the 0.25 s OnUpdate poll with `hooksecurefunc` on `SettingsPanel.SelectCategory`, so the Reload UI button now updates only on category changes instead of every frame while settings are open
- **[CleanSolo] Use `InCombatLockdown()` directly** — removed the redundant manual `inCombat` state variable; the player-frame fade system now queries `InCombatLockdown()` as the authoritative combat check, eliminating duplicate state tracking
- **[CleanSolo] Remove unnecessary pcall in chat tab hook** — the `SetAlpha` hook guard logic only accesses local variables and safe frame methods; the defensive `pcall(function() ... end)` wrapper was creating a closure on every `SetAlpha` call across all chat tabs
- **[QualityOfLife] Localize `C_Navigation` and `C_SuperTrack`** — added file-scope locals consistent with the rest of the hot-globals discipline
- **[QualityOfLife] `/way` comma normalization** — `gsub(",", ".")` on input so European-locale coordinate pastes (e.g. `45,2 56,3`) parse correctly
- **[QualityOfLife] Cache `IsQuestRewardButton` results** — the `SetItemButtonQuality` global hook now caches button-name lookups, avoiding repeated `string.find` + parent-chain walks on every bag open
- **[ZoneQuests] Cache zone name set** — `BuildZoneNameSet()` (which walks the `C_Map` hierarchy) is now called only on `ZONE_CHANGED*` events; `QUEST_LOG_UPDATE` syncs reuse the cached set
- **[ZoneQuests] Single-pass `SyncTracking`** — merged the previous two-pass remove-then-add design into one pass over the quest log, halving API calls and eliminating a theoretical stale-header race between passes

### Fixed

- **[CleanSolo] Stale section comment** — removed a duplicate `-- Feature: Hide Social Button` header left behind by the v1.3.11 neutral-nameplate removal

### Added

- **[TOC] Addon Compartment icon** — all five `.toc` files now specify `## IconTexture: Interface\Icons\INV_Misc_Gear_01` so the modules display a consistent gear icon in the minimap Addon Compartment menu instead of a generic placeholder

## [1.3.11] - 2026-03-31

### Removed

- **[CleanSolo] Remove Hide Neutral Nameplates feature** — the feature never worked reliably across all zone types (Blizzard housing neighborhoods, phased areas, etc.) and required 9 iterative fix attempts (v1.3.2–v1.3.10) without reaching a stable state; the entire feature has been removed: default setting, ~190-line `SetupHideNeutralPlates()` function, options panel checkbox, and activation call; `CleanSolo.lua` reduced from 570 to 380 lines

### Changed

- **[QualityOfLife] Rewrite Auto Sell Junk with event-driven batch selling** — the previous timer-based approach (`C_Timer.NewTicker(0)` with batches of 6) hit the WoW client's implicit action throttle at ~9 items, requiring multiple merchant window reopens to sell large inventories; the new implementation follows the pattern used by Scrap (the most popular junk-selling addon): sells up to 12 items per cycle, then waits for `BAG_UPDATE_DELAYED` (fired after the client processes bag changes) before selling the next batch; the game's own event cadence provides natural throttling, handling any number of junk items reliably; also adds `isLocked` checks to avoid selling items mid-transfer and `MERCHANT_CLOSED` registration to clean up if the vendor window closes mid-sell

## [1.3.10] - 2026-03-29

### Changed

- **[CleanSolo] Restore v1.3.1 neutral nameplate code as the definitive implementation** — confirmed working correctly in standard game zones (tested in Eversong Woods: neutral mobs hidden, nameplate appears as hostile immediately on aggro); the taint errors observed in v1.3.2–v1.3.9 were triggered by Blizzard housing neighborhood zones which use non-standard NPC behavior, not by the addon code itself; v1.3.1 logic is restored verbatim and this is now the stable baseline

## [1.3.9] - 2026-03-29

### Changed

- **[CleanSolo] Rewrite neutral nameplate hiding — no combat log, no taint** — removed all combat log / GUID tracking code; the new approach is: hide neutral plates (reaction == 4) out of combat via `plate:SetAlpha(0)` on the NamePlate parent frame (not `plate.UnitFrame`); on `PLAYER_REGEN_DISABLED` lift all suppression immediately so Blizzard's default combat display runs untouched; Blizzard fires `UNIT_FACTION` when a neutral mob is attacked and its reaction changes to hostile — the re-evaluation triggered by that event keeps the plate visible naturally; after combat ends (`PLAYER_REGEN_ENABLED`) neutral plates are re-hidden

## [1.3.8] - 2026-03-29

### Fixed

- **[CleanSolo] Fix persistent `ADDON_ACTION_BLOCKED` taint — root cause: `SetAlpha()` on `plate.UnitFrame`** — in TWW (11.0) and Midnight (12.0), `SetAlpha()` on `CompactUnitFrame` objects (nameplate UnitFrames) became a protected action that is blocked during combat lockdown; every previous fix attempt still called `uf:SetAlpha()` directly or indirectly; the correct fix is to operate exclusively on the `plate` frame (the NamePlate parent, which is not a CompactUnitFrame and whose `SetAlpha` is not protected); a `hiddenPlates` table tracks suppressed plates, and a lightweight `OnUpdate` loop continuously holds them at alpha 0 — idling when no plates are suppressed; `ShowPlate` removes the plate from `hiddenPlates` and does NOT call `SetAlpha(1)`, allowing `NamePlateDriverFrame` to restore the alpha naturally on the next frame; the entire `CompactUnitFrame_UpdateAll` hook was removed; no code anywhere in the feature now touches `plate.UnitFrame` for alpha/visibility

## [1.3.7] - 2026-03-29

### Fixed

- **[CleanSolo] Remove quest-name-visibility code that was causing taint** — the `ApplyQuestName` / `_vui_questName` system (added in v1.2.2) forced `uf.name:SetAlpha(1)` on nameplate sub-elements and re-applied it in the `CompactUnitFrame_UpdateAll` hook; accessing and writing to sub-elements of protected nameplate UnitFrames was the source of the persistent `ADDON_ACTION_BLOCKED` warning; removed the feature entirely — neutral plate hiding and quest-related plate showing both continue to work correctly

## [1.3.6] - 2026-03-29

### Fixed

- **[CleanSolo] Fix remaining "action blocked" taint error** — the combat log handler was calling `EvaluateNameplate`, which calls `IsQuestRelated` → `C_TooltipInfo.GetUnit`; calling tooltip APIs mid-combat is the taint source; the handler now only does the one thing it needs to — directly clears `_vui_hideNeutral` and restores alpha on the matching plate, with no tooltip scanning or other API calls

## [1.3.5] - 2026-03-29

### Fixed

- **[CleanSolo] Fix "action blocked" taint error** — `ClearQuestName` called Blizzard's `CompactUnitFrame_UpdateName(uf)` which internally calls `Show()` on protected nameplate sub-elements; the new combat log handler triggers `EvaluateNameplate` mid-combat far more frequently than before, making the taint reliably reproducible; removed the direct call entirely — clearing the `_vui_questName` flag is sufficient because Blizzard's own `CompactUnitFrame_UpdateAll` refresh cycle restores the name state naturally

## [1.3.4] - 2026-03-29

### Fixed

- **[CleanSolo] Fix taint error from combat log listener** — `COMBAT_LOG_EVENT_UNFILTERED` was registered on the same frame as nameplate events; `CombatLogGetCurrentEventInfo()` tainted the secure nameplate dispatch path, triggering "action blocked" warnings; the combat log listener now runs on its own isolated frame

## [1.3.3] - 2026-03-29

### Fixed

- **[CleanSolo] Neutral nameplates now reliably appear when the mob is attacked** — `UnitReaction` permanently returns 4 (neutral) even after aggro, and `UnitThreatSituation` returns nil for mobs without a standard threat table, so previous detection (events + API checks) silently failed; now uses `COMBAT_LOG_EVENT_UNFILTERED` to track GUIDs the player has exchanged damage with — the only fully reliable signal; engaged GUIDs are cleared on `PLAYER_REGEN_ENABLED` so plates re-hide after combat ends

## [1.3.2] - 2026-03-29

### Fixed

- **[CleanSolo] Neutral nameplates now appear when the mob is attacked** — attacking a neutral mob hid its nameplate because the `UNIT_FACTION` event does not fire on aggro and `UnitAffectingCombat` may not update in time; now listens for `UNIT_THREAT_LIST_UPDATE` (fires the instant a mob's threat table changes) and checks `UnitThreatSituation("player", unit)` as a secondary combat indicator, so the plate reappears immediately when you engage a neutral target

## [1.3.1] - 2026-03-29

### Added

- **[QualityOfLife] `/way` auto-clears on arrival** — after setting a waypoint, a background ticker polls `C_Navigation.GetDistance()` once per second; when the player comes within 10 yards the waypoint is automatically cleared and the minimap arrow dismissed, matching the feel of Blizzard's native destination pins; `/way clear` and any external clear (right-click map UI) also cancel the tracker via the `USER_WAYPOINT_UPDATED` event

## [1.3.0] - 2026-03-29

### Added

- **[QualityOfLife] TomTom-compatible `/way` waypoint command** — parses the standard TomTom waypoint syntax and places a native Blizzard user waypoint pin on the World Map; activates the minimap directional arrow automatically via `C_SuperTrack`, identical to right-clicking the map and choosing "Set Waypoint"; no TomTom addon required
  - `/way #mapID x y` — set a waypoint on a specific map by numeric ID (e.g. `/way #2351 45.2 56.3`)
  - `/way x y` — set a waypoint on the current zone at the given coordinates
  - Optional label appended after coordinates is echoed in the confirmation message (e.g. `/way #2351 45.2 56.3 Herb Node`)
  - `/way clear` — removes the active waypoint and deactivates the minimap arrow
  - Validates that the map ID exists via `C_Map.GetMapInfo()` and that coordinates are in the 0–100 range before setting; prints a usage hint on malformed input

## [1.2.2] - 2026-03-28

### Fixed

- **[CleanSolo] Quest enemy and neutral nameplate names now reliably visible** — `NAME_PLATE_UNIT_ADDED` was evaluating quest status synchronously on the first frame, before `C_TooltipInfo.GetUnit` had populated tooltip data for the new nameplate token; a deferred re-evaluation (`C_Timer.After(0.15)`) now corrects any false-hide applied on that first frame

### Added

- **[CleanSolo] Enemy quest NPCs now show their name in the nameplate** — previously the feature only controlled whether neutral nameplates were hidden; now any unit (neutral or hostile) that is quest-related has its nameplate name forced visible via `uf.name:SetAlpha(1)`, persisted through Blizzard's refresh cycle by the existing `CompactUnitFrame_UpdateAll` hook; non-quest enemy nameplates are unaffected and follow the player's Blizzard nameplate settings

## [1.2.1] - 2026-03-28

### Fixed

- **[PriorityRotation] Disable during combat now properly defers override cleanup** — unchecking "Enable Priority Rotation" in the Settings panel while in combat silently skipped `ClearOverride()`, leaving keybind overrides active until the next recompile or `/reload`; a new `needsClearOverride` flag now queues the cleanup for `PLAYER_REGEN_ENABLED`
- **[QualityOfLife] Auto-repair now correctly reports split guild/personal costs** — when guild bank funds only partially covered repair costs, the fallthrough to personal gold reported the total cost without qualifier; now reports the breakdown (e.g. "800g guild, 200g personal")
- **[CleanSolo] Nameplate evaluation now safe against Midnight Secret Values** — `UnitReaction()` and `UnitAffectingCombat()` on nameplate unit tokens may return Secret Values in Midnight 12.0; both calls are now pcall-wrapped with `issecretvalue()` checks, degrading gracefully (show the plate if uncertain)

### Changed

- **[QualityOfLife] `SetItemButtonQuality` hook deduplicated** — removed ~30 lines of duplicated equippability/skip/ilvl checks; the hook now resolves the item link and delegates to the existing `ProcessItem()` function
- **[CleanSolo] Nameplate evaluation logic collapsed** — three copy-pasted "restore and return" blocks replaced with a shared `RestoreNameplate()` helper and a combined condition
- **[ZoneQuests] `RestoreWatched` reduced from two passes to one** — uses idempotent `AddQuestWatch`/`RemoveQuestWatch` in a single loop
- **[PriorityRotation] `PR.VERSION` now references `VUI.VERSION`** — eliminates version string drift; only Lib.lua needs updating for future releases
- **[PriorityRotation] `SECURE_HANDLER` frame named `"PRSecureHandler"`** — visible in `/fstack` and `/dump` for easier debugging
- **[QualityOfLife] Added `## OptionalDeps: Blizzard_WorldMap`** to TOC — reduces deferred loader path for Map Coordinates
- **[QualityOfLife] Map coordinates `SavePosition` guarded against zero effective scale** — added `containerScale == 0` early return before division
- **[CleanSolo] Added documentation comments for Midnight API risks** — `CompactUnitFrame_UpdateAll` hook and tooltip color heuristic fragility noted inline

## [1.2.0] - 2026-03-28

### Added

- **QualityOfLife module** — map coordinates, item levels, auto-repair, and auto-sell extracted from CleanSolo into their own dedicated module (`VeritasUI_QualityOfLife`)
- **Macro support in Priority Rotation** — rotation slots now accept WoW macros in addition to spellbook spells; macro tooltips resolve the underlying spell via `#showtooltip` / `/cast` parsing
- **Neutral nameplate hiding** in CleanSolo — hides nameplates for neutral mobs unless they are quest-related or in combat; re-evaluates on combat state changes

### Fixed

- **Priority Rotation profile header** showing "Vengeance 0" — replaced broken seventh return value from `GetSpecializationInfo` with `UnitClass("player")`
- **Junk selling overcounting** — all `UseContainerItem` calls were firing in a single frame, hitting server throttle limits; rewritten to batch sells at 6 per frame with re-verification
- **Map coordinates position not persisting** — `StartMoving()` silently re-anchors to `UIParent`; fixed by saving `GetLeft()`/`GetBottom()` screen-space coordinates normalized through effective scales
- **Map coordinates box width** reduced from 146px to 126px to remove dead space
- **Chat tab fade persistence** — tabs remaining visible after mouse leaves; replaced `OnUpdate` enforcer with synchronous `hooksecurefunc(tab, "SetAlpha")` three-state guard
- **Item level display on legacy legendaries** (Heart of Azeroth showing 371 instead of 72) and junk items showing inflated values
- **Addon compartment handlers** not opening settings panels — was passing string display names to `Settings.OpenToCategory()` instead of numeric category ID from `category:GetID()`

### Changed

- **Comprehensive code audit** across all 8 Lua files — adopted recommendations from external review including: `pcall` wrapping on chat tab `SetAlpha` hook, guild-vs-personal funding source reporting in auto-repair, `PR.db` alias for PriorityRotation, `sv` renamed to `db` in ZoneQuests for suite-wide consistency
- **Reload UI button** moved from per-addon implementation to shared `VUI.RegisterSettingsLabel()` infrastructure in Lib.lua — only shows when a VeritasUI category is active
- Character-specific macros now correctly resolve tab-relative vs. absolute index using `MAX_ACCOUNT_MACROS` offset

## [1.1.0] - 2026-03-26

### Added

- **Map Coordinates** display on the World Map — player and cursor coordinates using native tooltip backdrop textures
- **Lock/unlock repositioning** for map coordinates — lock icon button (not right-click, which conflicts with map zoom); click to unlock (border turns cyan), drag freely, click to save and lock
- **"Create / Update Macro" button** added to Priority Rotation Settings UI
- **Static `SLOT_TO_FRAME` lookup table** for action bar detection in Priority Rotation — replaces unreliable `action` attribute polling

### Fixed

- **Action bar detection** in Priority Rotation — `SetOverrideBindingClick` requires a shown target; `PRAttackButton` made visible at 1×1px off-screen
- **Map coordinates positioned bottom-right** to avoid Blizzard's faction icons (was bottom-left)
- **`OnDragStop` firing on simple clicks** — removed auto-lock-on-drop; lock button is the sole toggle

### Changed

- Adopted external audit as new baseline — acknowledged missed bugs (SuppressFrame stacking, sparse array handling in HandleDrop, fade system inconsistency, AutoRepair fallback)
- Quest reward item level display **fully removed** — fundamental async loading and base vs. effective ilvl mismatch makes reliable display impractical

## [1.0.0] - 2026-03-23

### Added

- **VeritasUI suite created** — unified CleanSolo, PriorityRotation, and ZoneQuests under a single package with shared library, following ElvUI's multi-folder pattern
- **VeritasUI_Lib** — shared utilities: `VUI.Print()` formatter, `SmoothFade` per-frame fade manager, `HookPlayerFrameFade` with event-timing health detection, native settings panel helpers
- **Hide Macro Names** on action bar buttons — hooks `SetText` and `Show` on button name fontstrings across all action bars
- **Hide Error Text** — unregisters `UI_ERROR_MESSAGE` from `UIErrorsFrame`
- **Auto Sell Junk** — sells gray items on `MERCHANT_SHOW` with `GetCoinTextureString` coin icon output
- **Auto Repair** — repairs gear at repair merchants, guild funds first with fallback to personal gold
- **Item Level Overlays** — universal `SetItemButtonQuality` hook covering bags, character panel, bank, and warband bank with full link resolution cascade
- **Merchant item level scanner** — dedicated scanner using `GetMerchantItemLink(idx)` since `SetItemButtonQuality` doesn't fire on merchant buttons
- **Native settings panels** for all modules using `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnSetting` + `Settings.CreateCheckbox`
- **Addon Compartment** integration for all modules

### Fixed

- **"Interface action failed" combat errors** — Priority Rotation icon ticker was modifying secure button textures from tainted code; added `InCombatLockdown()` guard
- **Player frame invisible at low health** — Midnight Secret Values block all health comparison from addon code; implemented event-timing via `UNIT_HEALTH` (~2s regen cadence) with 3-second idle timer
- **Player frame stuck visible** — hover detection gap when mouse moves from parent to child frame; added 200ms poll ticker
- **Overlapping fade conflicts** — replaced Blizzard's global `UIFrameFadeIn`/`UIFrameFadeOut` with custom per-frame `SmoothFade` manager
- **False spec-switch messages** in Priority Rotation on battleground entry — track `PR._lastProfileKey` to only react on actual spec changes
- **Bag button taint errors** — `Hide()` on SecureActionButton children guarded with `InCombatLockdown()`, `SetAlpha(0)` as visual fallback
- **Item level showing base ilvl instead of effective** — added link resolution cascade: `GetItemLink()` → `GetBagID/GetID` → `GetBankTabID/GetContainerSlotID` → main bank check → `GetInventoryItemLink`
- **Settings panel `SetValueChangedCallback`** — fixed 3-arg signature to correct 2-arg `(setting, value)` for Midnight

### Changed

- **Comprehensive code polish** — localized hot globals across all files, conditional event registration, extracted named functions from anonymous closures to reduce GC pressure

---

## Pre-VeritasUI History

The addons below were developed as standalone projects before being unified into VeritasUI.

### PriorityRotation (standalone)

#### v2.2.0 — 2026-03-22

- Final standalone version before VeritasUI consolidation
- Clean verification pass: removed dead auto-mode code, unused debug flags, stale references
- Macro renamed from "PriorityRot" to "Attack"

#### v2.1.0 — 2026-03-22

- Renamed macro and button from "PriorityRot" / "PriorityRotButton" to "Attack" / "PRAttackButton"
- Added dynamic icon showing current spell on the action bar via 150ms ticker

#### v2.0.0 — 2026-03-22

- **Major rewrite** — discovered GSE's action bar override mechanism via source code analysis
- Replaced broken `SecureActionButton` + `PreClick` approach with `SecureHandlerWrapScript` restricted snippet
- Zero-taint combat execution: restricted snippet cycles macros via attributes only, no addon code contact
- Discovered `GetCursorInfo()` returns 4 values for spells (spell ID is 4th, not 2nd)
- Discovered Press and Hold Casting (`ActionButtonUseKeyDown` CVar) conflicts with override mechanism
- Added weighted sequence compiler with zip-interleave distribution
- Per-spec profiles with auto-switch on `PLAYER_SPECIALIZATION_CHANGED`
- Drag-and-drop editor with spellbook integration
- DPS tested: 32.5K (addon) vs 31K (raw G-Hub) vs 44.6K (Blizzard SBA with Press and Hold)

#### v1.0.0 — 2026-03-21

- Initial version with custom floating editor window
- Broken: `/pr` command not working (frame GetWidth() returning 0 during construction)
- Broken: Options panel (OptionsSliderTemplate deprecated, RegisterCanvasLayoutCategory wrong args)

### CleanSolo (standalone)

#### v4.1 — 2026-03-22

- Removed health check from player frame fade (too much friction with Secret Values)
- Added `InCombatLockdown()` guards on all `Hide()` calls with `SetAlpha(0)` fallback

#### v4.0 — 2026-03-22

- Settings panel rewrite using `Settings.RegisterVerticalLayoutCategory`
- Added Reload UI button anchored to Defaults button
- Fixed `SetValueChangedCallback` 3-arg → 2-arg signature

#### v3.7 — 2026-03-22

- Stripped player frame fade to absolute minimum: `C_Timer.NewTicker(0.2)` with direct `SetAlpha`
- Removed all `hooksecurefunc` and `UIFrameFadeIn/Out` calls that caused infinite loops

#### v3.6 — 2026-03-22

- Added `hooksecurefunc(pf, "SetAlpha")` — caused infinite recursion (thousands of errors/sec)

#### v2.0 — 2026-03-22

- Added fade micro menu, fade player frame, hide bag buttons
- Settings panel with SavedVariables

#### v1.1 — 2026-03-21

- Changed chat tabs from hard-hide to fade-with-chat-window behavior
- Tabs now visible and interactable on mouseover

#### v1.0 — 2026-03-21

- Initial version: hide chat tabs, social button, chat buttons, voice chat button

### ZoneQuests (standalone)

#### v7.0 — 2026-03-21

- Final standalone version — stable, full-featured
- Always-show categories: Campaign, Important, Legendary, Meta, Repeatable
- Important quests identified via `GetQuestTagInfo` returning tagID 282
- Settings panel integrated into both floating panel and Options canvas

#### v5.0–v6.0 — 2026-03-21

- Added settings panel with always-show category checkboxes
- Fixed Options canvas content overlap (`TOP_OFFSET` -16 → -72)
- Fixed `UpdateState` not firing on panel open (added `OnShow` scripts)
- Fixed blank toggle button text

#### v3.0–v4.0 — 2026-03-21

- Robust zone matching: `C_Map` hierarchy walk, directional prefix stripping
- Infinite loop guard (visited set + hard cap of 20 iterations)
- Nil map ID handling for loading screens
- Event debouncing for `QUEST_LOG_UPDATE` bursts

#### v2.0 — 2026-03-21

- **Major rewrite** — switched from custom floating panel to managing the native Objective Tracker via quest watch state
- Fixed SavedVariables initialization timing (must use `ADDON_LOADED`, not file scope)
- Discovered `IsQuestWatched` removed in Midnight 12.0 — use `Add/RemoveQuestWatch` directly

#### v1.0 — 2026-03-21

- Initial version: custom floating panel showing zone-filtered quests
- Basic zone matching with bidirectional substring check
