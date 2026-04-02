# Changelog

All notable changes to VeritasUI are documented here. Dates reflect the conversation sessions where changes were developed and tested.

## [1.3.14] — 2026-04-01

### Fixed

* **[QualityOfLife] Fix Auto Sell Junk stopping prematurely when server-throttled items remain locked mid-batch; reduce batch size from 12 to 9 to stay within WoW's server-side sell rate limit (matches Scrap addon's approach)**

---

## [1.3.13] — 2026-03-31

### Fixed

* **[CleanSolo] Fix syntax error from v1.3.12 audit** — the `inCombat` variable deletion merged two `local` declarations onto one line (`falselocal`), producing a Lua syntax error that prevented CleanSolo from loading; all fading features (chat tabs, micro menu, player frame) were non-functional

### Removed

* **[TOC] Revert Addon Compartment IconTexture** — removed the `## IconTexture` directive added in v1.3.12; the modules now use the default compartment icon as before

---

## [1.3.12] — 2026-03-31

### Changed

* **[Lib] SmoothFade zero-allocation iteration** — replaced `pairs()` iterator in the OnUpdate handler with `next()`-based traversal, eliminating a per-frame closure allocation during active fades
* **[Lib] Event-driven reload button visibility** — replaced the 0.25 s OnUpdate poll with `hooksecurefunc` on `SettingsPanel.SelectCategory`, so the Reload UI button now updates only on category changes instead of every frame while settings are open
* **[CleanSolo] Use `InCombatLockdown()` directly** — removed the redundant manual `inCombat` state variable; the player-frame fade system now queries `InCombatLockdown()` as the authoritative combat check, eliminating duplicate state tracking
* **[CleanSolo] Remove unnecessary pcall in chat tab hook** — the `SetAlpha` hook guard logic only accesses local variables and safe frame methods; the defensive `pcall(function() ... end)` wrapper was creating a closure on every `SetAlpha` call across all chat tabs
* **[QualityOfLife] Localize `C_Navigation` and `C_SuperTrack`** — added file-scope locals consistent with the rest of the hot-globals discipline
* **[QualityOfLife] `/way` comma normalization** — `gsub(",", ".")` on input so European-locale coordinate pastes (e.g. `45,2 56,3`) parse correctly
* **[QualityOfLife] Cache `IsQuestRewardButton` results** — the `SetItemButtonQuality` global hook now caches button-name lookups, avoiding repeated `string.find` + parent-chain walks on every bag open
* **[ZoneQuests] Cache zone name set** — `BuildZoneNameSet()` (which walks the `C_Map` hierarchy) is now called only on `ZONE_CHANGED*` events; `QUEST_LOG_UPDATE` syncs reuse the cached set
* **[ZoneQuests] Single-pass `SyncTracking`** — merged the previous two-pass remove-then-add design into one pass over the quest log, halving API calls and eliminating a theoretical stale-header race between passes

### Fixed

* **[CleanSolo] Stale section comment** — removed a duplicate `-- Feature: Hide Social Button` header left behind by the v1.3.11 neutral-nameplate removal

### Added

* **[TOC] Addon Compartment icon** — all five `.toc` files now specify `## IconTexture: Interface\Icons\INV_Misc_Gear_01` so the modules display a consistent gear icon in the minimap Addon Compartment menu instead of a generic placeholder

---

## [1.3.11] — 2026-03-31

### Removed

* **[CleanSolo] Remove Hide Neutral Nameplates feature** — the feature never worked reliably across all zone types (Blizzard housing neighborhoods, phased areas, etc.) and required 9 iterative fix attempts (v1.3.2–v1.3.10) without reaching a stable state; the entire feature has been removed: default setting, ~190-line `SetupHideNeutralPlates()` function, options panel checkbox, and activation call; `CleanSolo.lua` reduced from 570 to 380 lines

### Changed

* **[QualityOfLife] Rewrite Auto Sell Junk with event-driven batch selling** — the previous timer-based approach (`C_Timer.NewTicker(0)` with batches of 6) hit the WoW client's implicit action throttle at ~9 items, requiring multiple merchant window reopens to sell large inventories; the new implementation follows the pattern used by Scrap (the most popular junk-selling addon): sells up to 12 items per cycle, then waits for `BAG_UPDATE_DELAYED` (fired after the client processes bag changes) before selling the next batch; the game's own event cadence provides natural throttling, handling any number of junk items reliably; also adds `isLocked` checks to avoid selling items mid-transfer and `MERCHANT_CLOSED` registration to clean up if the vendor window closes mid-sell

---

## [1.3.10] — 2026-03-29

### Changed

* **[CleanSolo] Restore v1.3.1 neutral nameplate code as the definitive implementation** — confirmed working correctly in standard game zones (tested in Eversong Woods: neutral mobs hidden, nameplate appears as hostile immediately on aggro); the taint errors observed in v1.3.2–v1.3.9 were triggered by Blizzard housing neighborhood zones which use non-standard NPC behavior, not by the addon code itself; v1.3.1 logic is restored verbatim and this is now the stable baseline

---

## [1.3.9] — 2026-03-29

### Changed

* **[CleanSolo] Rewrite neutral nameplate hiding — no combat log, no taint** — removed all combat log / GUID tracking code; the new approach is: hide neutral plates (reaction == 4) out of combat via `plate:SetAlpha(0)` on the NamePlate parent frame (not `plate.UnitFrame`); on `PLAYER_REGEN_DISABLED` lift all suppression immediately so Blizzard's default combat display runs untouched; Blizzard fires `UNIT_FACTION` when a neutral mob is attacked and its reaction changes to hostile — the re-evaluation triggered by that event keeps the plate visible naturally; after combat ends (`PLAYER_REGEN_ENABLED`) neutral plates are re-hidden

---

## [1.3.8] — 2026-03-29

### Fixed

* **[CleanSolo] Fix persistent `ADDON_ACTION_BLOCKED` taint — root cause: `SetAlpha()` on `plate.UnitFrame`** — in TWW (11.0) and Midnight (12.0), `SetAlpha()` on `CompactUnitFrame` objects (nameplate UnitFrames) became a protected action that is blocked during combat lockdown; every previous fix attempt still called `uf:SetAlpha()` directly or indirectly; the correct fix is to operate exclusively on the `plate` frame (the NamePlate parent, which is not a CompactUnitFrame and whose `SetAlpha` is not protected); a `hiddenPlates` table tracks suppressed plates, and a lightweight `OnUpdate` loop continuously holds them at alpha 0 — idling when no plates are suppressed; `ShowPlate` removes the plate from `hiddenPlates` and does NOT call `SetAlpha(1)`, allowing `NamePlateDriverFrame` to restore the alpha naturally on the next frame; the entire `CompactUnitFrame_UpdateAll` hook was removed; no code anywhere in the feature now touches `plate.UnitFrame` for alpha/visibility

---

## [1.3.7] — 2026-03-29

### Fixed

* **[CleanSolo] Remove quest-name-visibility code that was causing taint** — the `ApplyQuestName` / `_vui_questName` system (added in v1.2.2) forced `uf.name:SetAlpha(1)` on nameplate sub-elements and re-applied it in the `CompactUnitFrame_UpdateAll` hook; accessing and writing to sub-elements of protected nameplate UnitFrames was the source of the persistent `ADDON_ACTION_BLOCKED` warning; removed the feature entirely — neutral plate hiding and quest-related plate showing both continue to work correctly

---

## [1.3.6] — 2026-03-29

### Fixed

* **[CleanSolo] Fix remaining "action blocked" taint error** — the combat log handler was calling `EvaluateNameplate`, which calls `IsQuestRelated` → `C_TooltipInfo.GetUnit`; calling tooltip APIs mid-combat is the taint source; the handler now only does the one thing it needs to — directly clears `_vui_hideNeutral` and restores alpha on the matching plate, with no tooltip scanning or other API calls

---

## [1.3.5] — 2026-03-29

### Fixed

* **[CleanSolo] Fix "action blocked" taint error** — `ClearQuestName` called Blizzard's `CompactUnitFrame_UpdateName(uf)` which internally calls `Show()` on protected nameplate sub-elements; the new combat log handler triggers `EvaluateNameplate` mid-combat far more frequently than before, making the taint reliably reproducible; removed the direct call entirely — clearing the `_vui_questName` flag is sufficient because Blizzard's own `CompactUnitFrame_UpdateAll` refresh cycle restores the name state naturally

---

## [1.3.4] — 2026-03-29

### Fixed

* **[CleanSolo] Fix taint error from combat log listener** — `COMBAT_LOG_EVENT_UNFILTERED` was registered on the same frame as nameplate events; `CombatLogGetCurrentEventInfo()` tainted the secure nameplate dispatch path, triggering "action blocked" warnings; the combat log listener now runs on its own isolated frame

---

## [1.3.3] — 2026-03-29

### Fixed

* **[CleanSolo] Neutral nameplates now reliably appear when the mob is attacked** — `UnitReaction` permanently returns 4 (neutral) even after aggro, and `UnitThreatSituation` returns nil for mobs without a standard threat table, so previous detection (events + API checks) silently failed; now uses `COMBAT_LOG_EVENT_UNFILTERED` to track GUIDs the player has exchanged damage with — the only fully reliable signal; engaged GUIDs are cleared on `PLAYER_REGEN_ENABLED` so plates re-hide after combat ends

---

## [1.3.2] — 2026-03-29

### Fixed

* **[CleanSolo] Neutral nameplates now appear when the mob is attacked** — attacking a neutral mob hid its nameplate because the `UNIT_FACTION` event does not fire on aggro and `UnitAffectingCombat` may not update in time; now listens for `UNIT_THREAT_LIST_UPDATE` (fires the instant a mob's threat table changes) and checks `UnitThreatSituation("player", unit)` as a secondary combat indicator, so the plate reappears immediately when you engage a neutral target

---

## [1.3.1] — 2026-03-29

### Added

* **[QualityOfLife] `/way` auto-clears on arrival** — after setting a waypoint, a background ticker polls `C_Navigation.GetDistance()` once per second; when the player comes within 10 yards the waypoint is automatically cleared and the minimap arrow dismissed, matching the feel of Blizzard's native destination pins; `/way clear` and any external clear (right-click map UI) also cancel the tracker via the `USER_WAYPOINT_UPDATED` event

---

## [1.3.0] — 2026-03-29

### Added

* **[QualityOfLife] TomTom-compatible `/way` waypoint command** — parses the standard TomTom waypoint syntax and places a native Blizzard user waypoint pin on the World Map; activates the minimap directional arrow automatically via `C_SuperTrack`, identical to right-clicking the map and choosing "Set Waypoint"; no TomTom addon required
  * `/way #mapID x y` — set a waypoint on a specific map by numeric ID (e.g. `/way #2351 45.2 56.3`)
  * `/way x y` — set a waypoint on the current zone at the given coordinates
  * Optional label appended after coordinates is echoed in the confirmation message (e.g. `/way #2351 45.2 56.3 Herb Node`)
  * `/way clear` — removes the active waypoint and deactivates the minimap arrow
  * Validates that the map ID exists via `C_Map.GetMapInfo()` and that coordinates are in the 0–100 range before setting; prints a usage hint on malformed input

---

## [1.2.2] — 2026-03-28

### Fixed

* **[CleanSolo] Quest enemy and neutral nameplate names now reliably visible** — `NAME_PLATE_UNIT_ADDED` was evaluating quest status synchronously on the first frame, before `C_TooltipInfo.GetUnit` had populated tooltip data for the new nameplate token; a deferred re-evaluation (`C_Timer.After(0.15)`) now corrects any false-hide applied on that first frame

### Added

* **[CleanSolo] Enemy quest NPCs now show their name in the nameplate** — previously the feature only controlled whether neutral nameplates were hidden; now any unit (neutral or hostile) that is quest-related has its nameplate name forced visible via `uf.name:SetAlpha(1)`, persisted through Blizzard's refresh cycle by the existing `CompactUnitFrame_UpdateAll` hook; non-quest enemy nameplates are unaffected and follow the player's Blizzard nameplate settings

---

## [1.2.1] — 2026-03-28

### Fixed

* **[PriorityRotation] Disable during combat now properly defers override cleanup** — unchecking "Enable Priority Rotation" in the Settings panel while in combat silently skipped `ClearOverride()`, leaving keybind overrides active until the next recompile or `/reload`; a new `needsClearOverride` flag now queues the cleanup for `PLAYER_REGEN_ENABLED`
* **[QualityOfLife] Auto-repair now correctly reports split guild/personal costs** — when guild bank funds only partially covered repair costs, the fallthrough to personal gold reported the total cost without qualifier; now reports the breakdown (e.g. "800g guild, 200g personal")
* **[CleanSolo] Nameplate evaluation now safe against Midnight Secret Values** — `UnitReaction()` and `UnitAffectingCombat()` on nameplate unit tokens may return Secret Values in Midnight 12.0; both calls are now pcall-wrapped with `issecretvalue()` checks, degrading gracefully (show the plate if uncertain)

### Changed

* **[QualityOfLife] `SetItemButtonQuality` hook deduplicated** — removed ~30 lines of duplicated equippability/skip/ilvl checks; the hook now resolves the item link and delegates to the existing `ProcessItem()` function
* **[CleanSolo] Nameplate evaluation logic collapsed** — three copy-pasted "restore and return" blocks replaced with a shared `RestoreNameplate()` helper and a combined condition
* **[ZoneQuests] `RestoreWatched` reduced from two passes to one** — uses idempotent `AddQuestWatch`/`RemoveQuestWatch` in a single loop
* **[PriorityRotation] `PR.VERSION` now references `VUI.VERSION`** — eliminates version string drift; only Lib.lua needs updating for future releases
* **[PriorityRotation] `SECURE_HANDLER` frame named `"PRSecureHandler"`** — visible in `/fstack` and `/dump` for easier debugging
* **[QualityOfLife] Added `## OptionalDeps: Blizzard_WorldMap`** to TOC — reduces deferred loader path for Map Coordinates
* **[QualityOfLife] Map coordinates `SavePosition` guarded against zero effective scale** — added `containerScale == 0` early return before division
* **[CleanSolo] Added documentation comments for Midnight API risks** — `CompactUnitFrame_UpdateAll` hook and tooltip color heuristic fragility noted inline

---

## [1.2.0] — 2026-03-28

### Added

* **QualityOfLife module** — map coordinates, item levels, auto-repair, and auto-sell extracted from CleanSolo into their own dedicated module (`VeritasUI_QualityOfLife`)
* **Macro support in Priority Rotation** — rotation slots now accept WoW macros in addition to spellbook spells; macro tooltips resolve the underlying spell via `#showtooltip` / `/cast` parsing
* **Neutral nameplate hiding** in CleanSolo — hides nameplates for neutral mobs unless they are quest-related or in combat; re-evaluates on combat state changes

### Fixed

* **Priority Rotation profile header** showing "Vengeance 0" — replaced broken seventh return value from `GetSpecializationInfo` with `UnitClass("player")`
* **Junk selling overcounting** — all `UseContainerItem` calls were firing in a single frame, hitting server throttle limits; rewritten to batch sells at 6 per frame with re-verification
* **Map coordinates position not persisting** — `StartMoving()` silently re-anchors to `UIParent`; fixed by saving `GetLeft()`/`GetBottom()` screen-space coordinates normalized through effective scales
* **Map coordinates box width** reduced from 146px to 126px to remove dead space
* **Chat tab fade persistence** — tabs remaining visible after mouse leaves; replaced `OnUpdate` enforcer with synchronous `hooksecurefunc(tab, "SetAlpha")` three-state guard
* **Item level display on legacy legendaries** (Heart of Azeroth showing 371 instead of 72) and junk items showing inflated values
* **Addon compartment handlers** not opening settings panels — was passing string display names to `Settings.OpenToCategory()` instead of numeric category ID from `category:GetID()`

### Changed

* **Comprehensive code audit** across all 8 Lua files — adopted recommendations from external review including: `pcall` wrapping on chat tab `SetAlpha` hook, guild-vs-personal funding source reporting in auto-repair, `PR.db` alias for PriorityRotation, `sv` renamed to `db` in ZoneQuests for suite-wide consistency
* **Reload UI button** moved from per-addon implementation to shared `VUI.RegisterSettingsLabel()` infrastructure in Lib.lua — only shows when a VeritasUI category is active
* Character-specific macros now correctly resolve tab-relative vs. absolute index using `MAX_ACCOUNT_MACROS` offset

---

## [1.1.0] — 2026-03-26

### Added

* **Map Coordinates** display on the World Map — player and cursor coordinates using native tooltip backdrop textures
* **Lock/unlock repositioning** for map coordinates — lock icon button (not right-click, which conflicts with map zoom); click to unlock (border turns cyan), drag freely, click to save and lock
* **"Create / Update Macro" button** added to Priority Rotation Settings UI
* **Static `SLOT_TO_FRAME` lookup table** for action bar detection in Priority Rotation — replaces unreliable `action` attribute polling

### Fixed

* **Action bar detection** in Priority Rotation — `SetOverrideBindingClick` requires a shown target; `PRAttackButton` made visible at 1×1px off-screen
* **Map coordinates positioned bottom-right** to avoid Blizzard's faction icons (was bottom-left)
* **`OnDragStop` firing on simple clicks** — removed auto-lock-on-drop; lock button is the sole toggle

### Changed

* Adopted external audit as new baseline — acknowledged missed bugs (SuppressFrame stacking, sparse array handling in HandleDrop, fade system inconsistency, AutoRepair fallback)
* Quest reward item level display **fully removed** — fundamental async loading and base vs. effective ilvl mismatch makes reliable display impractical

---

## [1.0.0] — 2026-03-23

### Added

* **VeritasUI suite created** — unified CleanSolo, PriorityRotation, and ZoneQuests under a single package with shared library, following ElvUI's multi-folder pattern
* **VeritasUI\_Lib** — shared utilities: `VUI.Print()` formatter, `SmoothFade` per-frame fade manager, `HookPlayerFrameFade` with event-timing health detection, native settings panel helpers
* **Hide Macro Names** on action bar buttons — hooks `SetText` and `Show` on button name fontstrings across all action bars
* **Hide Error Text** — unregisters `UI_ERROR_MESSAGE` from `UIErrorsFrame`
* **Auto Sell Junk** — sells gray items on `MERCHANT_SHOW` with `GetCoinTextureString` coin icon output
* **Auto Repair** — repairs gear at repair merchants, guild funds first with fallback to personal gold
* **Item Level Overlays** — universal `SetItemButtonQuality` hook covering bags, character panel, bank, and warband bank with full link resolution cascade
* **Merchant item level scanner** — dedicated scanner using `GetMerchantItemLink(idx)` since `SetItemButtonQuality` doesn't fire on merchant buttons
* **Native settings panels** for all modules using `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnSetting` + `Settings.CreateCheckbox`
* **Addon Compartment** integration for all modules

### Fixed

* **"Interface action failed" combat errors** — Priority Rotation icon ticker was modifying secure button textures from tainted code; added `InCombatLockdown()` guard
* **Player frame invisible at low health** — Midnight Secret Values block all health comparison from addon code; implemented event-timing via `UNIT_HEALTH` (~2s regen cadence) with 3-second idle timer
* **Player frame stuck visible** — hover detection gap when mouse moves from parent to child frame; added 200ms poll ticker
* **Overlapping fade conflicts** — replaced Blizzard's global `UIFrameFadeIn`/`UIFrameFadeOut` with custom per-frame `SmoothFade` manager
* **False spec-switch messages** in Priority Rotation on battleground entry — track `PR._lastProfileKey` to only react on actual spec changes
* **Bag button taint errors** — `Hide()` on SecureActionButton children guarded with `InCombatLockdown()`, `SetAlpha(0)` as visual fallback
* **Item level showing base ilvl instead of effective** — added link resolution cascade: `GetItemLink()` → `GetBagID/GetID` → `GetBankTabID/GetContainerSlotID` → main bank check → `GetInventoryItemLink`
* **Settings panel `SetValueChangedCallback`** — fixed 3-arg signature to correct 2-arg `(setting, value)` for Midnight

### Changed

* **Comprehensive code polish** — localized hot globals across all files, conditional event registration, extracted named functions from anonymous closures to reduce GC pressure

---

## Pre-VeritasUI History

The addons below were developed as standalone projects before being unified into VeritasUI.

### PriorityRotation (standalone)

#### v2.2.0 — 2026-03-22

* Final standalone version before VeritasUI consolidation
* Clean verification pass: removed dead auto-mode code, unused debug flags, stale references
* Macro renamed from "PriorityRot" to "Attack"

#### v2.1.0 — 2026-03-22

* Renamed macro and button from "PriorityRot" / "PriorityRotButton" to "Attack" / "PRAttackButton"
* Added dynamic icon showing current spell on the action bar via 150ms ticker

#### v2.0.0 — 2026-03-22

* **Major rewrite** — discovered GSE's action bar override mechanism via source code analysis
* Replaced broken `SecureActionButton` + `PreClick` approach with `SecureHandlerWrapScript` restricted snippet
* Zero-taint combat execution: restricted snippet cycles macros via attributes only, no addon code contact
* Discovered `GetCursorInfo()` returns 4 values for spells (spell ID is 4th, not 2nd)
* Discovered Press and Hold Casting (`ActionButtonUseKeyDown` CVar) conflicts with override mechanism
* Added weighted sequence compiler with zip-interleave distribution
* Per-spec profiles with auto-switch on `PLAYER_SPECIALIZATION_CHANGED`
* Drag-and-drop editor with spellbook integration
* DPS tested: 32.5K (addon) vs 31K (raw G-Hub) vs 44.6K (Blizzard SBA with Press and Hold)

#### v1.0.0 — 2026-03-21

* Initial version with custom floating editor window
* Broken: `/pr` command not working (frame GetWidth() returning 0 during construction)
* Broken: Options panel (OptionsSliderTemplate deprecated, RegisterCanvasLayoutCategory wrong args)

---

### CleanSolo (standalone)

#### v4.1 — 2026-03-22

* Removed health check from player frame fade (too much friction with Secret Values)
* Added `InCombatLockdown()` guards on all `Hide()` calls with `SetAlpha(0)` fallback

#### v4.0 — 2026-03-22

* Settings panel rewrite using `Settings.RegisterVerticalLayoutCategory`
* Added Reload UI button anchored to Defaults button
* Fixed `SetValueChangedCallback` 3-arg → 2-arg signature

#### v3.7 — 2026-03-22

* Stripped player frame fade to absolute minimum: `C_Timer.NewTicker(0.2)` with direct `SetAlpha`
* Removed all `hooksecurefunc` and `UIFrameFadeIn/Out` calls that caused infinite loops

#### v3.6 — 2026-03-22

* Added `hooksecurefunc(pf, "SetAlpha")` — caused infinite recursion (thousands of errors/sec)

#### v2.0 — 2026-03-22

* Added fade micro menu, fade player frame, hide bag buttons
* Settings panel with SavedVariables

#### v1.1 — 2026-03-21

* Changed chat tabs from hard-hide to fade-with-chat-window behavior
* Tabs now visible and interactable on mouseover

#### v1.0 — 2026-03-21

* Initial version: hide chat tabs, social button, chat buttons, voice chat button

---

### ZoneQuests (standalone)

#### v7.0 — 2026-03-21

* Final standalone version — stable, full-featured
* Always-show categories: Campaign, Important, Legendary, Meta, Repeatable
* Important quests identified via `GetQuestTagInfo` returning tagID 282
* Settings panel integrated into both floating panel and Options canvas

#### v5.0–v6.0 — 2026-03-21

* Added settings panel with always-show category checkboxes
* Fixed Options canvas content overlap (`TOP_OFFSET` -16 → -72)
* Fixed `UpdateState` not firing on panel open (added `OnShow` scripts)
* Fixed blank toggle button text

#### v3.0–v4.0 — 2026-03-21

* Robust zone matching: `C_Map` hierarchy walk, directional prefix stripping
* Infinite loop guard (visited set + hard cap of 20 iterations)
* Nil map ID handling for loading screens
* Event debouncing for `QUEST_LOG_UPDATE` bursts

#### v2.0 — 2026-03-21

* **Major rewrite** — switched from custom floating panel to managing the native Objective Tracker via quest watch state
* Fixed SavedVariables initialization timing (must use `ADDON_LOADED`, not file scope)
* Discovered `IsQuestWatched` removed in Midnight 12.0 — use `Add/RemoveQuestWatch` directly

#### v1.0 — 2026-03-21

* Initial version: custom floating panel showing zone-filtered quests
* Basic zone matching with bidirectional substring check
