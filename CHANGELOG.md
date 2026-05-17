# Changelog

All notable changes to VeritasUI are documented here. Dates reflect the conversation sessions where changes were developed and tested.

## [1.6.38] - 2026-05-16

### Fixed
- `VeritasUI_PriorityRotation` — **Editor `GetItemInfo` + `equipLoc` comparison now pcall-protected against Midnight Secret Values.** Two sites in `Editor.lua` called the legacy global `GetItemInfo` and compared `equipLoc ~= "INVTYPE_TRINKET"` without protection: `BuildEntryFromCursor` (lines 145-158, the trinket drag-handler) and the icon-refresh path inside `Refresh` (line 619). Both compare values that may be Secret Values in raid encounters or other restricted-execution contexts; either could surface as a Lua error popup mid-drag (BuildEntryFromCursor) or mid-row-render (Refresh). Fixed using the per-call pcall pattern that mirrors `QualityOfLife.lua:339-350` (the `IsEquippableGear` defensive pattern, also used by F-1 in v1.6.37): `pcall(GetItemInfo, itemID)` capturing all 10 returns positionally, then `pcall(function() return equipLoc == "INVTYPE_TRINKET" end)` for the comparison. On either pcall failure, `BuildEntryFromCursor` returns the existing user-facing "Item info not loaded yet — try again in a moment." message (the Secret Value path is indistinguishable from a not-yet-cached item from the user's perspective and the same retry advice applies). The Refresh icon path is purely cosmetic — on pcall failure it silently keeps the cached `e.icon` rather than overwriting with stale data. Legacy `GetItemInfo` namespace retained for now; the F-37 migration to `C_Item.GetItemInfo` is a separate Phase 6 commit per the audit's recommendation set.
- `VeritasUI_Lib` — **`SuppressFrame` Show-hook now combat-defers the `Hide` via `VUI.CombatQueue` instead of silently no-op'ing.** The Show-hook installed at `Lib.lua:114-117` set the frame's alpha to 0 and conditionally called `self:Hide()` only when `not InCombatLockdown()`. A combat-locked Show — common during the login burst, action bar layout passes, or any Blizzard subsystem that re-asserts a suppressed frame mid-encounter — left the frame at alpha 0 but still `:IsShown()`, and the deferred Hide it was promised never fired. Layout invalidation could subsequently re-assert the frame's geometry and the user would see the suppressed element flicker back at the next frame cycle. Fixed by routing the deferred Hide through `VUI.CombatQueue.Add(function() if self:IsShown() then self:Hide() end end)`, mirroring the established pattern in `SafeHide` (line 106). The `IsShown()` guard inside the queued closure handles the case where Blizzard hid the frame itself between the Show and the queue drain at `PLAYER_REGEN_ENABLED` — without it, the queued Hide would be a redundant but harmless call; with it, the queue drain is a clean no-op.
- `VeritasUI_Lib` — **Renamed two same-named file-locals `HOVER_POLL_RATE` to disambiguate `HookHoverFade` (10 Hz) from `HookPlayerFrameFade` (5 Hz).** Two unrelated subsystems in `Lib.lua` both declared `local HOVER_POLL_RATE` at file scope with different values — `0.1` (line 136, used by `HookHoverFade` for MicroMenu / faded action bars) and `0.20` (line 233, used by `HookPlayerFrameFade` for the player frame hover poll). The second declaration shadowed the first within its lexical scope; both resolved correctly because `HookHoverFade`'s closure captured the local from line 136 before line 233 was reached, and `HookPlayerFrameFade`'s closure captured line 233 after the shadow took effect. Behaviorally correct, but reading the file from top to bottom makes the second declaration look like a mistake or a refactor halfway done. Renamed to `HOVER_FADE_POLL_RATE` (line 136 → 147) and `PLAYER_FRAME_HOVER_POLL_RATE` (line 233 → 244) so the names match their function. No behavior change; both still poll at their original rates.

## [1.6.37] - 2026-05-16

### Fixed
- `VeritasUI_QualityOfLife` — **AutoSell `C_Item.GetItemInfo` calls now pcall-protected against Midnight Secret Values.** v1.6.36's rewrite to item-value summing reinstated `C_Item.GetItemInfo` at `ScanJunk` (lines 117-133) and `SellNextBatch` (lines 159-185) without preserving the pcall protection that v1.3.18 and v1.3.22 had established for this exact API. The Item Level overlay paths in the same file (lines 339-368) remained pcall'd, confirming the inconsistency was unintentional. Realistic exposure window: a player who starts selling near a hub vendor, then is pulled into combat (trash respawn in Stormwind / Dornogal) before the sell completes, would hit a Secret-Value comparison error on the next `SellNextBatch` cycle, producing a Lua error popup with `BAG_UPDATE_DELAYED` still registered. Fixed using the per-call pcall pattern that mirrors `QualityOfLife.lua:339-350` (the `IsEquippableGear` defensive pattern): the `info.quality == 0 and not info.hasNoValue` check is wrapped in `pcall(function() ... end)`, the `C_Item.GetItemInfo` call is wrapped in `pcall(C_Item.GetItemInfo, info.itemID)` capturing the 11th return positionally, and the `price > 0` arithmetic is wrapped in a third `pcall(function() ... end)` that returns the contribution (`price * stackCount`) on success. Items that fail any of the three guards are skipped (treated as not-junk / not-sellable). `SellNextBatch` applies the same three-pcall pattern with the additional `info.isLocked` clause in the first guard. The closure-helper alternative proposed in the audit was rejected in favor of inline per-call pcalls so the fix matches the file's established defensive idiom exactly. No other AutoSell behavior modified — locked-items-as-remaining accounting, no-progress timeout, decoupled AutoRepair, MERCHANT_SHOW one-frame defer, and BAG_UPDATE_DELAYED retry are all preserved verbatim.

## [1.6.36] - 2026-05-16

### Changed
- `VeritasUI_QualityOfLife` — **AutoSell and AutoRepair rewritten in the Scrap-style decoupled architecture; AutoRepair now works at Delver's Supplies and every other repair-only vendor.** The v1.6.30 "sell-first sequencing" architecture chained `AutoRepair` off the inside of `SellNextBatch` (and later `DoReport`), meaning `AutoRepair` could only fire after `AutoSellJunk` reached one of two narrow completion paths. At Delver's Supplies crates in Delves, Blizzard disables item sales entirely while still allowing repair — `UseContainerItem` no-ops, `BAG_UPDATE_DELAYED` never resolves the sell loop, and `AutoRepair` was therefore never called. The user experienced absolutely nothing happening at Delves crates. Five releases (v1.6.31, v1.6.32, v1.6.34, v1.6.35) chased symptoms of this coupling without removing its cause.
  - **Reread Scrap's actual source** (`jaliborc/Scrap` `addons/merchant/button.lua`). Scrap's `Button:OnMerchant` calls `Sell()` and `Repair()` independently — neither chains off the other. The earlier claim that Scrap coupled them was incorrect; the coupling in VeritasUI was based on a misread.
  - **MERCHANT_SHOW handler restored to independent dispatch** (matching v1.6.27 and Scrap): `if db.autoRepair then AutoRepair() end; if db.autoSellJunk then AutoSellJunk() end`. Either function can fail, no-op, or never start without affecting the other.
  - **Gold accounting replaced with item-value summing** (matching Scrap). At sell start, `ScanJunk` walks bags once and sums `select(11, C_Item.GetItemInfo(itemID)) * stackCount` for every grey item — this is `saleTotal`. On each cycle, `ScanJunk` recomputes the remaining junk value; when remaining hits 0, the print uses `saleTotal` directly. `GetMoney()` is never used for the sell amount, so there is no race with a concurrent repair deduction — this kills the original v1.6.12-v1.6.29 "Sold N items for 0g" bug at its root, not at a symptom.
  - **Locked items are counted as "remaining"** so the completion print only fires when the server has physically removed items from bags — not when they are merely locked mid-sale. The client locks each item the instant `UseContainerItem` runs, while the server is still processing (or rejecting) the request. If `ScanJunk` excluded locked items the way Scrap's `GetReport` does, we would print "Sold N for X" immediately after the sell loop and then the items would either confirm shortly after (print was just premature) or fail to sell and reappear unlocked (print was an outright lie). Counting locked items defers the print until the bag actually empties.
  - **No-progress timeout** (`MAX_NO_PROGRESS = 5s`) ends the retry loop only when items have stopped disappearing from the bag — not on absolute elapsed time. Each cycle compares the current remaining value to `lastRemainingValue`; if it dropped, sales are confirming and the timer resets. If it has been flat for 5 seconds, the vendor is rejecting our requests (or there is some other persistent failure) and `PrintSold` reports whatever partial value did sell (`saleTotal - remaining`, `saleCount - remainingCount`). This is correct for both small piles and very large drains — a 200-item sell that legitimately takes 8 seconds keeps resetting the timer with every confirmed batch, while a stuck vendor times out cleanly. The v1.6.16 0.5s `SELL_RETRY_SEC` BAG_UPDATE_DELAYED fallback is preserved, so the historical "stops after one batch if the bag event is dropped" stall stays fixed.
  - **Repair print uses `GetRepairAllCost()` directly** — known, exact, synchronous; no delta math, no listener, no fallback timer.
  - **Removed**: the `PLAYER_MONEY` event registration, the `pendingReportFn` / `pendingReportTimer` state, the `CancelPendingReport` helper, the `DoReport` closure with its `earned ≤ 0` rebase guard, the `count == 0` chained-repair branch in `SellNextBatch`, the `local AutoRepair` forward declaration, and the `sellState` struct with deferred `startMoney` snapshot. Roughly 90 lines of coupling machinery deleted.
  - **Preserved**: the `MERCHANT_SHOW` one-frame defer (v1.6.34's fix for Blizzard's handler-order race), the `BAG_UPDATE_DELAYED` event-driven sell loop, the 0.5s `SELL_RETRY_SEC` safety fallback for dropped bag updates (v1.6.16), the `[noautorepair]` guild-info convention (v1.6.30), and the Guild + Personal / Personal Only Repair Funding dropdown (v1.6.30).

## [1.6.35] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **Repair print appeared before sell print, breaking the visible sell-first ordering.** `RepairAllItems` triggers its `"Repaired for X"` print **synchronously** the instant `AutoRepair()` runs. The sell print is **asynchronous** — `DoReport` only fires after the server's sell `PLAYER_MONEY` packet arrives (~200ms RTT). Even though the logical sequencing was sell-first (UseContainerItem requests sent to the server before RepairAllItems), the client-side message order ended up repair-then-sell because the repair print didn't wait for any network round-trip. Fixed by chaining the `AutoRepair()` call off the *inside* of `DoReport` (after the sell `VUI.Print`), rather than firing it immediately after the listener is armed. The `earned ≤ 0` rebase guard is retained as a safety net for unrelated deductions during the gap, and `CanMerchantRepair()` inside `AutoRepair` handles the rare case where the merchant closes between the sell print and the chained repair call. The `count == 0` branch (no junk to sell) still calls `AutoRepair()` directly — no sell print means no ordering issue.

## [1.6.34] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **AutoSell Junk and AutoRepair completely non-functional on merchant visit.** `MERCHANT_SHOW` fires *before* Blizzard's `MerchantFrame_OnShow` handler runs, so `MerchantFrame:IsShown()` returns `false` at the moment our handler executes. `SellNextBatch`'s safety guard (`if not MerchantFrame:IsShown() then return end`) silently aborted the sell, and because `AutoRepair` is now chained off `SellNextBatch` (v1.6.30 sell-first sequencing), repair never fired either. Net effect: clicking a merchant did absolutely nothing — no error, no message, no sell, no repair. v1.6.29 masked this race condition with a 0.25s `C_Timer.After` delay before `AutoSellJunk`, which was removed in v1.6.30 when the sell-first refactor restructured the timing model. Fixed by deferring the `MERCHANT_SHOW` body by one frame (`C_Timer.After(0, ...)`), which runs after Blizzard's handler completes and `MerchantFrame` is fully shown. The `MerchantFrame:IsShown()` safety check is preserved inside the deferred closure to handle the edge case where the merchant is closed during the one-frame gap.

## [1.6.33] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **`/way` command was non-functional for non-TomTom users.** `local function WayCommand(msg)` was declared at the bottom of the file, after `frame:SetScript("OnEvent", ...)`. Lua compiles free variables in a closure at definition time; since `WayCommand` was not yet declared when the OnEvent closure was compiled, references inside it resolved to the global `_G.WayCommand` (nil). At PLAYER_LOGIN, `SlashCmdList["VERITASUI_WAY"] = WayCommand` assigned nil, and typing `/way` silently failed. Fixed by adding a `local WayCommand` forward declaration before `frame:SetScript` and changing the definition from `local function WayCommand` to `WayCommand = function` so it populates the upvalue. TomTom users were unaffected (the registration block is skipped when TomTom is present).
- `VeritasUI_PriorityRotation` — **Removed unused `usedCharSlot` variable from `BuildEntryFromCursor` in `Editor.lua`.** The variable was declared and assigned in two branches of the macro character-slot disambiguation logic but never read anywhere in the function. Dead code removed.

## [1.6.32] - 2026-05-15

### Fixed
- `VeritasUI_PriorityRotation` — **Settings.lua crash when opening the spec switcher dropdown.** Fix #3 from v1.6.31 incorrectly migrated `GetNumSpecializations()` to `C_SpecializationInfo.GetNumSpecializations()`. That method does not exist in the `C_SpecializationInfo` namespace in Midnight 12.0.5 — only the legacy global `GetNumSpecializations()` is available. Opening the spec switcher dropdown triggered `attempt to call a nil value` at `Settings.lua:382`. Reverted that one call to the global; all other `C_SpecializationInfo` migrations from v1.6.31 are correct and preserved.

## [1.6.31] - 2026-05-15

### Fixed
- `VeritasUI_QualityOfLife` — **AutoRepair scoping fix: `SellNextBatch` now correctly calls the VUI `AutoRepair` local.** `local function AutoRepair()` was declared at line 218, after `SellNextBatch` at line 104. In Lua, a local is only visible to code declared after it, so `AutoRepair()` inside `SellNextBatch` resolved to `_G.AutoRepair` (nil in WoW) rather than the VUI local — causing a Lua error on every merchant visit with both Auto Sell and Auto Repair enabled. Fixed with a forward declaration (`local AutoRepair`) placed before `SellNextBatch`; the definition is unchanged and the sell-first sequencing architecture from v1.6.30 is fully preserved.

### Changed
- `VeritasUI_PriorityRotation` — **Settings.lua spec API calls updated to `C_SpecializationInfo` namespace.** `ApplySpecPortrait`, `CurrentSpecName`, and the spec switcher dropdown's `SetupMenu` were using the legacy global `GetSpecialization` / `GetSpecializationInfo` / `GetNumSpecializations` with defensive nil guards. These are now replaced with direct `C_SpecializationInfo.*` calls, consistent with the pattern already used throughout `Profiles.lua`. Eliminates the inconsistency and removes reliance on globals that Blizzard may eventually drop.
- `VeritasUI_PriorityRotation` — **Deduplicated Spellbook/Macro toggle logic.** `ToggleSpellBookPanel` and `ToggleMacroPanel` are defined once in `Editor.lua` and exposed on the `PR` table. `Settings.lua`'s Spellbook and Macros button handlers now call `PR.ToggleSpellBookPanel()` / `PR.ToggleMacroPanel()` instead of inlining identical logic. Any future change to the toggle behavior only needs to be made in one place.

## [1.6.30] - 2026-05-14

### Changed
- `VeritasUI_QualityOfLife` — **AutoSell and AutoRepair: sell-first sequencing, guild tag respect, and repair funding setting.**
  - **Sell-first sequencing** — AutoSell now runs before AutoRepair instead of after. The merchant-open handler kicks off `AutoSellJunk()` immediately; `AutoRepair()` is triggered from inside `SellNextBatch` when all junk has been sold (or immediately if there was nothing to sell). This eliminates the 0.25s artificial delay that existed to prevent repair deductions from corrupting the sell gold delta. Sell credits arrive from the server before repair deductions in normal network order, and the existing `earned ≤ 0` rebase guard in `DoReport` handles the rare high-latency edge case. If Auto Sell is disabled and Auto Repair is on, repair fires immediately from `MERCHANT_SHOW` as before
  - **`[noautorepair]` guild tag** — `AutoRepair` now checks whether the guild's info text contains the literal string `[noautorepair]` before attempting guild bank repair. This is an informal convention used by guild masters to prevent auto-repair addons from drawing on guild funds (common in organized raiding guilds). If the tag is present, the guild repair step is skipped and personal gold is used instead
  - **Repair Funding setting** — new dropdown in the Quality of Life settings panel (directly below the Auto Repair checkbox): `Guild + Personal` (default, existing behavior) or `Personal Only`. `Guild + Personal` tries guild bank funds first when all guild conditions are met, then covers any remainder with personal gold. `Personal Only` skips guild entirely and always uses personal gold — useful for players not in a guild or who prefer not to use guild funds

## [1.6.29] - 2026-05-14

### Fixed
- `VeritasUI_QualityOfLife` — **AutoSell Junk gold reporting still showed 0g when Auto Repair also ran using personal gold.** Root cause: `C_Timer.After(0, AutoSellJunk)` started the sell one frame (~16ms) after the repair request was sent, but the server's repair `PLAYER_MONEY` event (money deduction) typically arrives 50–200ms later. `startMoney` was therefore captured pre-repair. Once the sell completed and `pendingReportFn = DoReport` was set, the repair's `PLAYER_MONEY` arrived first and fired `DoReport` with a negative delta (repair deduction − 0) → clamped to 0 → "for 0🪙". The sell's own `PLAYER_MONEY` arrived after `pendingReportFn` was already cleared and was silently ignored.
  - **Primary fix:** sell deferred by 0.25s (up from one frame) so repair credit settles in `GetMoney()` before `startMoney` is captured. Covers typical server round-trips of 50–200ms.
  - **Secondary fix (high-latency guard):** `DoReport` now checks whether `earned ≤ 0` before reporting. If a repair deduction still arrives after `pendingReportFn` is set (connection latency > 250ms), `DoReport` rebases `capturedStart` to the current post-deduction gold and returns without reporting — keeping `pendingReportFn` active so the sell's subsequent `PLAYER_MONEY` (earned > 0) fires a correct report. The 2-second fallback timer also reads the rebased `capturedStart`, so it reports sell proceeds rather than a net sell-minus-repair delta.

## [1.6.28] - 2026-05-14

### Changed
- `VeritasUI_QualityOfLife` — **Architectural hardening: ten robustness improvements.**
  - **AutoSell gold reporting — PLAYER_MONEY event replaces fixed-frame delay** — `C_Timer.After(0, ...)` raced against the server's money-credit packet, causing sub-1g sell totals to read `GetMoney() - startMoney == 0` and report "for 0g". `PLAYER_MONEY` fires exactly when the server confirms the credit; the report now triggers in that handler. A 2-second fallback timer fires if `PLAYER_MONEY` never arrives. A stale-closure guard (`pendingReportFn ~= DoReport`) and `CancelPendingReport()` prevent double-reporting if a new sell session starts before the previous report fires
  - **Item level hook respects mid-session disable** — `hooksecurefunc("SetItemButtonQuality", ...)` cannot be unregistered once set; overlays remained visible after disabling the setting mid-session. Added `if not db or not db.showItemLevels then return end` as the first guard in the hook closure so disabling takes effect immediately without a `/reload`
  - **Map coordinates OnUpdate respects mid-session disable** — the anchor frame's 30 fps `OnUpdate` ran regardless of `db.showMapCoords`. Added a db check that hides the anchor and returns when the setting is off
  - **Settings callbacks invoke feature setup on mid-session enable** — enabling `showItemLevels` or `showMapCoords` after login (when they were disabled at login) previously did nothing because setup only ran in `PLAYER_LOGIN`. Callbacks now call `SetupItemLevels()` / `SetupMapCoordinates()` when toggled on; `SetupItemLevels` is idempotent via the new `itemLevelsSetup` guard. Map coords anchor is shown/hidden directly if already initialised
  - **AFK poll starts when AFK Screen enabled mid-session** — `AFK_StartPoll()` was only called in `PLAYER_LOGIN` if `db.afkScreen`. Enabling the feature after login left the 5-second fallback poll un-started (event-driven path still worked). The `afkScreen` settings callback now calls `AFK_StartPoll()` on enable; the function is idempotent
  - **`MinimapCluster` visibility preserved across AFK** — `AFK_Exit()` unconditionally called `MinimapCluster:Show()`, revealing it even if another addon had hidden it before AFK started. `AFK_Enter()` now snapshots `MinimapCluster:IsShown()` into `afkOverlay._minimapWasShown`; `AFK_Exit()` restores that exact state
  - **`MoveViewRightStart` / `MoveViewRightStop` pcall-wrapped** — camera movement APIs can fail in cinematics, vehicle sequences, and certain phased content. Both calls are now guarded with `pcall`
  - **`InitCoords` idempotency guard** — added `coordsInitialized` flag; `InitCoords()` is now a no-op if called a second time (e.g. edge-case LoD event re-fire), preventing duplicate anchor frames on the map
  - **Merchant scanner no longer double-fires on open** — the item-level merchant scanner's `mf` frame registered both `MERCHANT_SHOW` and `MerchantFrame:HookScript("OnShow", ...)`, causing `UpdateMerchantItems` to be called twice at +0.1s on every merchant open. Removed `MERCHANT_SHOW` from `mf`; the `OnShow` hook covers the open case
  - **`/way` defers registration to `PLAYER_LOGIN` with TomTom detection** — if TomTom is loaded, both addons register `/way` and the last to load silently wins. Registration now happens in `PLAYER_LOGIN`; if `_G.TomTom` or `IsAddOnLoaded("TomTom")` is true, `/way` is skipped and a one-time note is printed. The slash handler extracted to `local function WayCommand(msg)` for testability

## [1.6.27] - 2026-05-14

### Changed
- `VeritasUI_ZoneQuests` — **Architectural hardening: five robustness improvements.**
  - **Remove `QUEST_ACCEPTED` stacked timers** — The `QUEST_ACCEPTED` handler created a non-cancellable `C_Timer.After(0.5, ...)` per event. Accepting multiple quests from one NPC fired multiple stacked timers that all called `SyncTracking` independently. Since `QUEST_LOG_UPDATE` fires on every acceptance and already routes through the cancellable debounce, `QUEST_ACCEPTED` was redundant. Handler and event registration removed
  - **Map walk uses `Enum.UIMapType` stop sentinel** — `BuildZoneNameSet`'s C_Map hierarchy walk previously stopped at hardcoded parent map IDs 946/947 (the World and Cosmic map IDs). If Blizzard renumbers these in a future patch, the walk would climb past the world level and pollute the name set with world-level names, causing every quest header to match every zone. Now stops when `info.mapType` is `Enum.UIMapType.World` or `Enum.UIMapType.Cosmic` (with numeric fallbacks), which is ID-independent
  - **`StripDir` uses ordered array and loops until stable** — `DIRECTIONAL` changed from a hash table (non-deterministic `pairs` iteration) to an ordered array (`ipairs`). `StripDir` now loops until no further prefix is stripped, so doubly-prefixed names like `"The Upper Blackrock Spire"` fully reduce to `"Blackrock Spire"` in two passes. Previously only one prefix was stripped per call, leaving the second prefix in place and relying on the substring fallback in `HeaderMatches` — which introduced false-positive risk
  - **`HeaderMatches` guards short stripped headers** — The bidirectional substring fallback now requires `#hs > 2` before checking whether the stripped quest header appears inside a zone name in the set. Previously a very short stripped header could sweep-match across unrelated zone names. The guard on `#name > 2` already protected the forward direction; this adds the symmetric guard to the reverse direction
  - **Remove redundant `registeredCategory` variable** — `registeredCategory` and `settingsCategoryID` both tracked whether `InitializeOptions` had run. All three guard sites now use `settingsCategoryID` directly, eliminating the drift risk if the two variables were ever set independently

## [1.6.26] - 2026-05-14

### Changed
- `VeritasUI_AdvancedOptions` — **Architectural hardening: six improvements to eliminate fragility and ensure long-term robustness.**
  - **Shared height constants** — `AO.CONTROL_HEIGHTS` table defined in `Controls.lua` using `ROW_HEIGHT` as the single source; `Featured.lua`'s extent calculator now references it instead of maintaining a duplicate copy. Adding a new control type no longer requires updating two files
  - **Shared scrollbar inset** — `AO.SB_INSET = 16` defined once in `Core.lua`; both `BuildFeaturedContent` and `BuildBrowserContent` reference it. The precisely-tuned scrollbar alignment between tabs can no longer silently drift if one is changed independently
  - **Featured → Browser CVar sync** — `EnumerateCVars` now auto-supplements the browser list with every CVar from `AO.FEATURED_CATEGORIES` after the three enumeration strategies run. Adding a CVar to the Featured tab will automatically appear in the All CVars tab without a separate `KNOWN_CVARS` entry; the lists can never silently diverge
  - **Slider write debounce** — `CreateSlider`'s `OnValueChanged` now uses the `userInput` parameter to skip programmatic `SetValue` calls (e.g. from `Refresh()`), and defers the actual `SetCVar` write via a 0.15s `C_Timer` debounce that commits only after the drag settles. Eliminates spurious writes on every `Refresh` and rapid-fire writes during drag
  - **CVar cache version stamp** — `InitDB` now clears `db.cvarCache` when `db.cacheVersion` doesn't match `AO.VERSION`, evicting stale entries from CVars renamed or removed in a prior patch. Cache repopulates naturally during the session
  - **Restart indicator comment corrected** — `CreateRestartIndicator` comment updated to reflect that `"!"` text is the intentional implementation; the atlas approach was tried and abandoned due to pool-frame reparenting conflicts

## [1.6.25] - 2026-05-14

### Changed
- `VeritasUI_PriorityRotation` — **Architectural hardening: seven improvements to eliminate fragility and Secret Value taint risk.**
  - **Removed icon ticker system** — `StartIconTicker()`, `StopIconTicker()`, `UpdateIcon()`, and `iconCache` are gone. The ticker called `icon:Show()`/`Hide()` and polled action button frames on every tick, producing taint that could corrupt secure execution contexts in Delves, M+, and raids. Action bar button now keeps its static macro icon; no dynamic updates
  - **CombatQueue delegation** — `PR.needsRecompile` and `PR.needsClearOverride` boolean flags replaced by direct calls to `VUI.CombatQueue.Add()` (already implemented in Lib.lua). Combat-blocked operations now queue correctly and execute atomically via the shared processor on `PLAYER_REGEN_ENABLED`; the `PLAYER_REGEN_ENABLED` handler in Core.lua is removed (Lib.lua owns it)
  - **Single cancellable scan timer** — `PR:ScheduleScan(delay)` method with one `PR._scanTimer` handle replaces three ad-hoc `C_Timer.After()` calls that stacked without cancelling each other
  - **Idempotent CVar management** — `PR:EnsureActionBarCVar(enabled)` value-checks before writing, so toggling enable/disable mid-session doesn't dirty the CVar when the value is already correct
  - **Compile dedup guard** — `_compileQueued` flag prevents multiple combat-blocked `CompileSequence()` calls from queueing more than one deferred execution
  - **Parameter-driven scan** — `ScanAndOverrideBarButton(macroName, verbose)` is now explicit-argument instead of hardcoded, ready for future multi-rotation support without structural change
  - **Per-macro override state** — `PR.overrides[macroName]` table replaces flat `overriddenButton`/`overriddenKeys` fields, matching the parameter-driven scan signature
  - **Explicit specID extraction** — `BuildDefaultProfile` in Profiles.lua uses explicit `if specIndex then ... end` instead of relying on Lua `and`/`or` multi-return discard, which was silently wrong when `GetSpecializationInfo` returned multiple values

## [1.6.24] - 2026-05-09

### Changed
- `VeritasUI_AdvancedOptions` — **All CVars tab: redesigned CVar editor from dropdown panel to inline edit.** Clicking a CVar row now turns the Value column into an editable field in-place — no overlay panel, no Set/Reset buttons, no DataProvider re-layout. Press Enter to apply, Escape to cancel, right-click to reset to default. This eliminates the `DataProvider:SignalUpdate()` dependency that was removed in Midnight (which caused the original crash) and all the layout issues that followed from trying to replace it. The extent calculator is now fixed-height (`ROW_H`) for all rows; the `EXPAND_H` constant and the shared editor frame are removed entirely

## [1.6.23] - 2026-05-09

### Fixed
- `VeritasUI_AdvancedOptions` — **All CVars tab: inline editor overlapped the row below and left a gap above.** The row frame stayed at `ROW_H` height even when the ScrollBox's extent calculator reserved `ROW_H + EXPAND_H`, and the editor anchored to `BOTTOMLEFT`/`BOTTOMRIGHT` (the row's bottom edge) which placed it outside the row's bounds. Fixed by dynamically setting the row height to `ROW_H + EXPAND_H` when expanded and anchoring the editor to `TOPLEFT` offset by `-ROW_H` — placing it directly below the CVar data line but inside the row's own allocated space

## [1.6.22] - 2026-05-09

### Fixed
- `VeritasUI_AdvancedOptions` — **All CVars tab: clicking a row to expand/edit crashed with "attempt to call a nil value" at Browser.lua:516.** `DataProvider:SignalUpdate()` was removed in Midnight. All three call sites (row expand/collapse, Set button, Reset button) called this nil method. Replaced with `FullRefresh()` which creates a fresh `DataProvider` and calls `scrollBox:SetDataProvider()` — the same proven path used by search, favourites, and initial populate. Required a forward declaration (`local FullRefresh` before the editor callbacks, assigned after ScrollBox setup) to avoid the Lua forward-reference-local-is-nil-in-closures trap

## [1.6.21] - 2026-05-04

### Fixed
- `VeritasUI_QualityOfLife` — **AFK Screen now reliably triggers on idle timeout.** Added a 5-second fallback poll (`UnitIsAFK("player")`) that detects AFK state independently of `PLAYER_FLAGS_CHANGED` event delivery. In Midnight, the event may not fire reliably for server-originated idle AFK in all contexts — the poll guarantees detection within 5 seconds regardless. The event handler remains for instant response when it does fire
  - **Secret Value hardening:** `UnitIsAFK` is tagged `SecretInChatMessagingLockdown` in Midnight and can return opaque secret values in restricted contexts. Both the event handler and the poll now guard with `pcall` + `issecretvalue` (matching ElvUI's defensive pattern via their `oUF:NotSecretValue` wrapper). If blocked, the poll silently retries on the next tick
  - **Dual-path architecture:** event handler (instant, when it fires) + poll (guaranteed, always running). Poll starts at `PLAYER_LOGIN` when AFK Screen is enabled; cost is one `pcall` every 5s with no allocations when state is unchanged

## [1.6.20] - 2026-05-04

### Fixed
- `VeritasUI_QualityOfLife` — **AFK Screen not triggering on idle timeout.** When WoW's server-side idle timer sets the AFK flag, `PLAYER_FLAGS_CHANGED` can fire with `arg1 = nil` (server-originated event without an explicit unit payload). The previous guard `if arg1 ~= "player"` treated `nil` as "not player" and bailed early, preventing `AFK_Enter()` from executing. Manual `/afk` was unaffected because the client-originated event always passes `arg1 = "player"`. Fixed by changing the guard to `if arg1 and arg1 ~= "player"` — nil is now treated as "self" and falls through to the `UnitIsAFK("player")` state check. Note: ElvUI's AFK module has the same unguarded pattern as of their current `main` branch

## [1.6.19] - 2026-05-03

### Added
- `VeritasUI_QualityOfLife` — **AFK Screen.** New toggle (default on) that activates a cinematic overlay when the player goes AFK. Hides all standard UI and displays character name (class-coloured), level, equipped item level, current zone/subzone, and a real-world clock over a slow camera orbit — designed to minimise OLED burn-in by eliminating static UI elements and keeping the screen moving
  - **Trigger:** `PLAYER_FLAGS_CHANGED` → `UnitIsAFK("player")`; dismissed when the server clears the AFK flag on character movement (keyboard input), matching Blizzard's default behavior
  - **UI hiding:** `UIParent:SetAlpha(0)` plus explicit `MinimapCluster:Hide()` (minimap has `SetIgnoreParentAlpha` in Blizzard code and bleeds through the alpha change)
  - **Camera:** `MoveViewRightStart(0.03)` slow orbit, stopped on exit
  - **Vignette:** four edge gradients (bottom/top 25%, left/right 20%) framing the 3D scene; single `OnSizeChanged` + `OnShow` handler for robust sizing
  - **Safety:** `PLAYER_LOGIN` unconditionally restores `UIParent` alpha and `MinimapCluster` visibility (crash/disconnect recovery); `PLAYER_LOGOUT` calls `AFK_Exit()` before the client saves frame state; `PLAYER_FLAGS_CHANGED` gated on `arg1 == "player"` to ignore group member flag changes
  - **Midnight hardening:** `GetAverageItemLevel` and the subsequent `format` call both wrapped in `pcall` for Secret Value safety; zone segment omitted from info line when `GetZoneText()` returns empty (loading screen/instance transition)

## [1.6.18] - 2026-05-03

### Changed
- `VeritasUI_AdvancedOptions` — **Both tabs now use Blizzard's native `WowScrollBoxList` + `MinimalScrollBar` for scrolling.** Replaces the custom `AttachSlimScrollbar` implementation with the same scroll system used by Blizzard's Talents, Professions, Housing, and Collections panels — pixel-identical scrollbar appearance and behavior
  - **Browser tab (All CVars):** Rewrote from manual 26-row virtual pool + bare `ScrollFrame` to native `WowScrollBoxList` + `CreateScrollBoxListLinearView` + `CreateDataProvider`. Blizzard's view handles row recycling natively; ~200 fewer lines of scroll plumbing. Inline editor and expand/collapse preserved
  - **Featured tab:** Converted from bare `ScrollFrame` to `WowScrollBoxList` with a flat data model — each category header, control, and inter-category gap is a separate list element. Controls are created once by the existing factory functions (`CreateCheckbox`/`CreateSlider`/`CreateDropdown`) and cached; the element initializer reparents them into whichever pool frame the ScrollBox assigns. Collapse/expand rebuilds the DataProvider

### Removed
- `VeritasUI_Lib` — **Removed `VUI.AttachSlimScrollbar` helper** (~240 lines). All consumers now use Blizzard's native `MinimalScrollBar` directly. Tombstone comment in Lib.lua points future modules to the AO implementations as reference

## [1.6.17] - 2026-05-03

### Improved
- `VeritasUI_QualityOfLife` — **Item level overlays now have a subtle bottom-vignette gradient for readability on busy or bright item art.** A vertical gradient fades from 70% black at the icon's bottom edge to fully transparent 24px above, ensuring ilvl numbers are legible regardless of the icon artwork behind them. Uses the Warcraft Wiki-documented `WHITE8x8` + `SetGradient` pattern with `colorRGBA` alpha interpolation (`SetColorTexture` does not support gradient alpha in Midnight — discovered during development). Single texture per button, zero extra frames

## [1.6.16] - 2026-05-03

### Fixed
- `VeritasUI_QualityOfLife` — **Auto Sell Junk no longer stalls mid-sell with large junk counts.** The sell chain relied entirely on `BAG_UPDATE_DELAYED` to drive each batch. If that event was lost — server throttle, event coalesced away, or bag reorganization swallowing the signal — the chain broke silently and remaining junk was never sold. Fix: a 0.5s safety timer (`SELL_RETRY_SEC`) now self-chains after every `SellNextBatch` call. If `BAG_UPDATE_DELAYED` fires normally (the common path), it cancels and replaces the timer. If the event is lost, the timer fires and resumes selling. The timer is cancelled on merchant close and on sell completion. Normal-path behavior and timing are unchanged

## [1.6.15] - 2026-05-03

### Fixed
- `VeritasUI_Lib` — **Fix Midnight Secret Value taint errors on faded action bars.** `HookHoverFade` previously hooked `OnEnter` on every child ActionButton via `HookScript`, which tainted their execution context. When `ACTIONBAR_UPDATE_COOLDOWN` fired in Secret Value zones (Delves, M+, raids), Blizzard's `ActionButton_UpdateCooldown` ran in the tainted context and `SetCooldown` rejected the Secret Values — producing `"bad argument #1 to 'SetCooldown'"` errors (175+ per Delve entry). Fix: child ActionButton `OnEnter` hooks removed entirely; the always-on 10 Hz poll now handles both hover-start and hover-end detection. Only the parent bar frame's `OnEnter` is hooked (not an ActionButton, so no taint). Poll was previously gated on `hovered` state; now runs unconditionally. Identical user-visible behavior, zero taint surface on ActionButton frames
- `VeritasUI_PriorityRotation` — **Remove `icon:Show()` from icon ticker to prevent latent taint.** `UpdateIcon` called `Show()` on the overridden ActionButton's icon texture from addon code every 0.25s. While `SetTexture` is unprotected, `Show()` on a child of a secure ActionButton propagates taint to the button's execution context, causing the same Secret Value errors when a rotation is active. Fix: `Show()` removed — `SetTexture(iconID)` alone is sufficient since the icon is already visible on any button with an assigned action

## [1.6.14] - 2026-05-02

### Fixed
- `VeritasUI_Lib` — **Rewrote `HookHoverFade` with hybrid poll-based hover detection.** The old event-driven `OnEnter`/`OnLeave` approach failed for action bars in Edit Mode layouts (e.g., 3×4 grids) where buttons extend beyond the parent bar frame's bounds — `MouseIsOver(target)` returned false while hovering a button, and `OnLeave`/`OnEnter` races between adjacent buttons left bars stuck visible. New approach: event-driven `OnEnter` for instant fade-in, `OnUpdate` poll (10 Hz, only active while hovered) for robust fade-out that checks target AND all direct children via `IsMouseOver()`. Cached child array with `RefreshChildren` handle avoids per-tick allocation. 150ms grace period prevents flicker between adjacent buttons. Zero per-frame cost while hidden
- `VeritasUI_CleanSolo` — `SetupActionBarFading` now captures the `RefreshChildren` handle and calls it on Edit Mode exit alongside `FadeOut`, so the child cache stays current after layout changes

## [1.6.13] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Fade Action Bars now re-hide after exiting Edit Mode.** Blizzard forces bars visible during Edit Mode layout editing, but no `OnLeave` fires on exit to trigger `FadeOut`. Fix: `SetupActionBarFading` now collects `FadeOut` handles returned by `HookHoverFade` and hooks `EditModeManagerFrame:ExitEditMode` to re-evaluate fade state 200ms after exit
- `VeritasUI_Lib` — `HookHoverFade` now returns its internal `FadeOut` closure so callers can force a re-evaluation after external state changes (e.g., Edit Mode exit). Existing callers that discard the return are unaffected

## [1.6.12] - 2026-05-02

### Fixed
- `VeritasUI_QualityOfLife` — **Auto Sell Junk now reports accurate earnings when Auto Repair is also active.** The `GetMoney()` snapshot was captured at sell-init time, but the preceding `AutoRepair` deduction could land asynchronously during the sell window, making the delta negative (clamped to 0 — "Sold 17 junk items for 0🥉"). Fix: the `startMoney` snapshot is now deferred to the moment the first `UseContainerItem` call fires inside `SellNextBatch`, giving the repair deduction time to settle in `GetMoney()` before the delta window opens

## [1.6.11] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Reverted v1.6.10 Fade Action Bars changes that broke persistence.** The v1.6.10 hardening commit added an early-return guard (`if val == db.fadeActionBarsLabel then return end`) in the dropdown callback that prevented the recompute + SetValue refresh from running when the Settings framework replayed a persisted value on load. This caused bar selections to silently reset to "None" across sessions. Restored the original working callback from v1.6.9 which handled all replay scenarios correctly

## [1.6.10] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Fade Action Bars selection now persists across sessions.** Blizzard's `Settings.RegisterAddOnSetting` framework persists the raw dropdown value (e.g. `"toggle:2"`) and replays it through the `SetValueChangedCallback` on the next login, re-toggling the bar OFF and resetting the label to "None". Fix: the display label is now computed fresh from the authoritative `fadeActionBars` table on every load, force-set on the setting after registration (overriding the stale persisted string), and the callback is suppressed during initialisation so the framework's restore replay is ignored. Bar selections in saved vars were always correct — only the display/callback replay was broken
- `VeritasUI_CleanSolo` — **Early-return on composite label re-selection in Fade Action Bars callback.** Prevents a no-op toggle cycle when the user clicks the already-displayed composite label in the dropdown

## [1.6.9] - 2026-05-02

### Added
- `VeritasUI_CleanSolo` — **Fade Action Bars: hover-reveal for action bars.** Designated bars fade to transparent when idle and reappear on mouseover. Uses `VUI.HookHoverFade` with an Edit Mode guard so bars stay visible during repositioning. Bars 2–8 are supported (Bar 1 is Blizzard-protected and excluded). Per-bar selection via a native `Settings.CreateDropdown` multi-select dropdown in the Options panel — modern gold-arrow style, part of the layout system, no floating frames or deferred anchoring. Toggling a bar in the dropdown marks it green; the dropdown label shows the current selection ("Bar 2" / "Bars 2, 5" / "None"). Saved vars: `fadeActionBars` table + `fadeActionBarsLabel` display string. Deep-copy table defaults on first init to avoid the shared-reference landmine

### Fixed
- `VeritasUI_CleanSolo` — **Player frame now reliably appears when joining combat initiated by another player.** `PLAYER_REGEN_DISABLED` can fire before `InCombatLockdown()` returns true on the same frame (known WoW timing quirk). Added a zero-delay deferred re-evaluation on `PLAYER_REGEN_DISABLED` that retries on the next frame when the lockdown flag has settled

## [1.6.8] - 2026-05-02

### Fixed
- `VeritasUI_CleanSolo` — **Player frame now reliably appears when joining combat initiated by another player.** `PLAYER_REGEN_DISABLED` can fire before `InCombatLockdown()` returns true on the same frame (known WoW timing quirk). When you initiate combat yourself, a near-simultaneous `UNIT_HEALTH` event masked the race, but when joining someone else's fight without immediately taking damage, the sole `Evaluate()` call saw `InCombatLockdown() == false` and the frame stayed hidden. Fix: a zero-delay deferred re-evaluation (`C_Timer.After(0, Evaluate)`) on `PLAYER_REGEN_DISABLED` retries on the next frame when the lockdown flag has settled

## [1.6.7] - 2026-05-02

### Changed
- `VeritasUI_AdvancedOptions` — **Browser tab rewritten as a virtual scroll list.** The old implementation created one full row frame (Button + 4 fontstrings + editor Frame + EditBox + 2 UIPanelButtons) per CVar — ~1,400 frames for 197 CVars. Every scroll interaction triggered `RefreshEntry` (pcall to `C_CVar.GetCVarInfo`) on all 197 entries and re-wired `SetScript` closures on every row. The new implementation uses a fixed pool of 26 row frames that are recycled as the user scrolls, with a single shared editor that repositions to the expanded row. Only the ~24 visible rows are bound and have their CVar values read on each scroll change. Click handlers, tooltips, and star toggles are wired once at pool creation and use a stable `row._entry` reference. Eliminates the game lock-up on first scroll and makes the tab feel instant
- `VeritasUI_AdvancedOptions` — Browser search now resets scroll position to top on every filter change. Previously, filtering down to a few results while scrolled deep into the full list left the viewport past the content, showing an empty list until the user scrolled up
- `VeritasUI_AdvancedOptions` — Browser tab scrollbar right-edge alignment normalized to match the Featured tab (both now at 16px inset from the parent's right edge)
- `VeritasUI_Lib` — `VUI.AttachSlimScrollbar` now includes hover-fade behaviour: the scrollbar starts invisible, fades in (0.15s) on mousewheel, hover, track click, or thumb drag, lingers for 1.5s after the last interaction, then fades out (0.4s). Stays visible during active thumb drag. Applies to both the Featured and Browser tabs automatically
- `VeritasUI_AdvancedOptions` — removed unused `math_abs` localization from `Browser.lua` (dead import from pre-virtual-scroll `Refresh`)

## [1.6.6] - 2026-05-02

### Removed
- `VeritasUI_AdvancedOptions` — removed 7 dead CVars from the Featured tab that were removed or replaced in WoW Midnight. **Nameplates:** `nameplateMotion` (dropdown), `nameplateOverlapH`, `nameplateOverlapV`, `nameplateOtherTopInset`, `nameplateOtherBottomInset` (sliders) — nameplate stacking is now per-unit-type (Enemy/Friendly) in Blizzard's Options → Nameplates panel. **Combat Text:** `WorldTextScale` (slider), `floatingCombatTextFloatMode` (dropdown) — no longer exposed as CVars. These controls appeared functional but were reading nil from `C_CVar.GetCVar`; sliders silently showed their min value, dropdowns showed "?"

### Changed
- `VeritasUI_AdvancedOptions` — `Controls.lua` dropdown factory (`CreateDropdown`) now uses `tostring()` coercion on both sides of value comparison and `ipairs()` for deterministic option iteration. Prevents potential mismatches between CVar string formatting and option table values
- `VeritasUI_AdvancedOptions` — `Core.lua` `GetCVar` now caches last-known-good values in saved vars (`cvarCache`). If a CVar returns nil (e.g. its Blizzard subsystem hasn't loaded yet), the cache provides a fallback. `SetCVar` also updates the cache on successful writes. Defensive measure for any future edge cases with late-loading LoD subsystems
- `VeritasUI_AdvancedOptions` — removed unused `PAD_Y` variable from `Featured.lua` and unused `CONTENT_W` constant from `Settings.lua`
- `VeritasUI_AdvancedOptions` — updated `GetCVar` docblock to reference the general late-loading subsystem case rather than specific removed CVars

## [1.6.5] - 2026-05-02

### Added
- `VeritasUI_AdvancedOptions` — the Featured tab now has the same slim scrollbar as the All CVars tab, for consistency across tabs. Mousewheel still works (as before), plus the new thumb can be dragged, and clicking the track above/below the thumb page-jumps. Scrollbar auto-hides when content fits in the visible area
- `VeritasUI_Lib` — new `VUI.AttachSlimScrollbar(scrollFrame, opts)` helper that attaches a modern Blizzard-style 8px slim scrollbar on the right edge of any ScrollFrame. Encapsulates the track / thumb / drag handling / mousewheel routing / page-jump behavior that was previously open-coded in `Browser.lua`. Options: `wheelStep`, `scrollbarWidth`, `gap`, `minThumbHeight`, `parent`. Returns an `update` function callers invoke after content-size changes so the thumb recomputes its height and position

### Changed
- `VeritasUI_AdvancedOptions` — `Browser.lua` refactored to call `VUI.AttachSlimScrollbar` instead of inline scrollbar code. ~105 lines of self-contained widget logic pulled out of the module; behavior preserved exactly (same wheel step of `ROW_H * 3`, same 8px scrollbar width, same 4px gap). Lowers drift risk between the two tabs' scrollbar implementations going forward
- `VeritasUI_AdvancedOptions` — Featured tab's scroll container is now inset 16px from the right edge (scrollbar width + gap + margin). `CW` (control row width) is reduced by the same 16px so right-anchored reset buttons fit cleanly within the scrollChild bounds instead of overflowing into the scrollbar gutter. Controls are ~3% narrower on a 520px window — imperceptible but arithmetically correct
- `VeritasUI_Lib` — added `math_max` and `math_min` localizations alongside the existing `math_abs` (required by the new scrollbar helper)

## [1.6.4] - 2026-05-02

### Added
- `VeritasUI_CleanSolo` — new "Transparent Chat Background" toggle (default on). Sets every chat frame's backdrop alpha to 0 via Blizzard's `FCF_SetWindowAlpha` API so only the text is visible when idle. Blizzard's built-in hover-to-reveal behavior still works — mousing over the chat frame reveals the background naturally. The color component is untouched, so any custom tint the user set in `/chatconfig` is preserved. Third arg to `FCF_SetWindowAlpha` (`doNotSave`) keeps the write session-volatile, so toggling the feature off and `/reload`ing restores Blizzard's saved alpha rather than leaving `alpha=0` baked into the profile
- `VeritasUI_CleanSolo` — Transparent Chat Background enforces itself against Blizzard's color picker. Hooks `FCF_SetWindowColor` (re-applies alpha=0 after any color change from the tab right-click → "Background" menu) and `FCF_SetWindowAlpha` (re-applies 0 if any code path — including Blizzard's opacityFunc firing on picker open — tries to set a non-zero alpha). Hooks are db-gated so toggling the feature off + `/reload` cleanly disables enforcement. Re-entry-guarded with a per-frame flag to prevent our own 0-write from looping through the alpha hook

## [1.6.3] - 2026-05-02

### Fixed
- `VeritasUI_PriorityRotation` — `C_CVar.SetCVar("ActionButtonUseKeyDown", ...)` is now `pcall`-wrapped at all three call sites (PLAYER_LOGIN handler, Enable setting callback on, Enable setting callback off). A raw error here would previously abort the rest of the login handler and leave PR half-initialized; now surfaces an amber warning and lets the rest of init proceed
- `VeritasUI_PriorityRotation` — `ScanAndOverrideBarButton` now counts slots that `pcall(GetActionInfo)` fails on (likely Midnight Secret Values in raid / M+ zones). When the user-initiated `/pr scan` or "Scan & Bind" button fails to find the Attack macro AND unreadable slots were present, prints an actionable diagnostic telling the user to re-scan after leaving the encounter or move the macro. Automatic scans (post-compile, post-login, post-spec-change) remain silent as before
- `VeritasUI_PriorityRotation` — `UpdateMacroStub` now returns a success boolean and warns the user with a red error when the account macro list is full (120/120). Previously the function silently no-op'd and callers printed a misleading "Macro is ready" message. Both user-facing callers (`/pr macro` slash command, "Create / Update Macro" button) now gate their success message on the return value

### Changed
- `VeritasUI_Lib` — corrected the `VUI.RegisterManagedPanel` docblock to accurately document the `pushable` default (`1`, Tier B coexist-with-everything) instead of the previously-claimed `0` (Tier A exclusive). Explains both tiers and clarifies when to pass `pushable=0` explicitly
- `VeritasUI_QualityOfLife` — map-coords `OnUpdate` now tracks a `dirty` flag and only calls `ResizeAnchor()` when player or cursor text actually changed. `GetStringWidth` / `GetStringHeight` / `SetSize` no longer fire 30×/sec on unchanged coordinates
- `VeritasUI_ZoneQuests` — first `BuildZoneNameSet()` call now assigns its result to `cachedNameSet` so subsequent `QUEST_LOG_UPDATE` events in the login-to-first-zone-change window reuse the cached set instead of rebuilding the map-hierarchy walk on every fire
- `VeritasUI_AdvancedOptions` — removed 4 duplicate entries from `Browser.lua` `KNOWN_CVARS` list (`movieSubtitle`, `showTimestamps`, `speechToText`, `textToSpeech` were each listed twice). List is now clean; 197 unique CVar names
- `VeritasUI_AdvancedOptions` — removed dead `thumb:RegisterForClicks` call on the Browser scrollbar thumb. Drag is implemented via `OnMouseDown` / `OnMouseUp` / `OnUpdate`; `RegisterForClicks` was a no-op
- `VeritasUI_AdvancedOptions` — Browser `expandedRow` (numeric list index) renamed to `expandedName` and keyed by CVar name. Toggling a favourite mid-session (which re-sorts the filtered list) no longer desyncs which row's inline editor is open

## [1.6.2] - 2026-05-02

### Changed
- `VeritasUI_QualityOfLife` — redesigned Map Coordinates display. Removed the metallic tooltip-style box (BackdropTemplate with border and tinted background) and lock icon button. Coordinates now render as two bare fontstrings side-by-side on one horizontal line: `Player: 42.0, 67.1  Cursor: —` with a black drop shadow for legibility against any map background. Player coords in gold, cursor coords in light gray. Frame strata set to DIALOG so the coordinates can be positioned anywhere on the map frame including the title bar chrome. Right-click the coordinates to toggle lock/unlock (cyan tint when unlocked); left-drag to reposition when unlocked. Hover tooltip provides contextual hint in both states. Settings tooltip updated to reflect the new interaction

## [1.6.1] - 2026-05-01

### Fixed
- `VeritasUI_PriorityRotation` — fixed Midnight taint error in `ActionButton_ApplyCooldown` caused by PR calling `SetAttribute` on Blizzard ActionButtons. Calling `SetAttribute("type", "click")` and `SetAttribute("clickbutton", ...)` from addon code taints the button's execution context; when Blizzard's own cooldown update code later passes Midnight Secret Values to `SetCooldown`, the tainted context throws `"Secret values are only allowed during untainted execution"`. Strategies 1 and 2 now only track which button frame holds the Attack macro (for the icon ticker) without modifying any attributes. Strategy 3 (`SetOverrideBindingClick`) is the sole click-routing mechanism — direct mouse clicks still work via the Attack macro's `/click PRAttackButton`

## [1.6.0] - 2026-04-28

### Added
- `VeritasUI_AdvancedOptions` — new module providing curated hidden settings and a full CVar browser. Features two tabs: a Featured tab with 9 collapsible categories (Camera, Nameplates, Combat Text, Action Bars, Targeting & Mouse, Tooltips & UI, Chat, Graphics, Accessibility) containing ~45 hand-picked settings with proper native controls (checkboxes, sliders, dropdowns), and an All CVars tab with a searchable browser listing every CVar on the client via `C_CVar.GetCVarInfo` probe fallback (Midnight removed `C_Console`). Browser features: star-favourite system (persisted, sorts to top), click-to-expand inline editor with Set/Reset buttons, modified-value highlighting, mousewheel + draggable slim scrollbar. Window uses `PortraitFrameTemplate` (520×660) registered as a Tier A UIPanel (`pushable=0`), matching the PriorityRotation panel pattern. Slash: `/ao`, `/advancedoptions`
- `VeritasUI_AdvancedOptions` control factory system in `Controls.lua` — three reusable factories (`CreateCheckbox`, `CreateSlider`, `CreateDropdown`) with per-control reset-to-default (`transmog-icon-revert` atlas), restart indicators for GX-restart CVars, and tooltips. Adding a new CVar to the Featured tab is a single table entry in `Featured.lua`
- `VeritasUI_AdvancedOptions` CVar browser uses a three-strategy enumeration: `C_Console.GetAllCommands()` (guarded), legacy `ConsoleGetAllCommands()`, then a ~170-entry known-CVar probe list as fallback. Midnight ships without `C_Console`, so the probe strategy fires and indexes all valid CVars via `C_CVar.GetCVarInfo`

## [1.5.1] - 2026-04-25

### Fixed
- `VeritasUI_PriorityRotation` combat-time Lua errors in Midnight — Blizzard `ActionButton.ApplyCooldown` and `SpellBookItem.UpdateCooldown` no longer throw "Secret values are only allowed during untainted execution" when PR is open during combat. Root cause: WoWUIBugs #783 — if a tainted (addon) dropdown is the first menu opened in a session, the menu compositor assigns a tainted `nil` to the shared menu frame's `minimumWidth` field, which then propagates through secure menu operations later. Applied Meorawr's workaround (Total-RP-3 PR #1242): call `root:SetMinimumWidth(CW)` at the top of every `SetupMenu` generator so the compositor sees a clean concrete integer instead of the tainted nil landmine
- `VeritasUI_PriorityRotation` spec dropdown label now updates live when the spec changes externally (via spec panel, macro, etc.). Switched from `SetDefaultText` (which only controls the label when no radio has been clicked) to `OverrideText`, which bypasses the click-label cache so `PLAYER_SPECIALIZATION_CHANGED` refreshes the display regardless of how the change originated
- `VeritasUI_PriorityRotation` window now sits flush against the instance-info side bar in M+ / raid zones. Added `win:SetToplevel(true)` to match Blizzard's `CharacterFrame` XML declaration — the frame now raises above same-strata frames (instance bar) when shown. Removed `width` / `height` from the `UIPanelWindows` registration so the manager reads live `GetWidth`/`GetHeight` from the frame instead of stale declared values, matching `CharacterFrame`'s entry exactly and eliminating a 1-2px horizontal drift

### Changed
- `VeritasUI_PriorityRotation` removed the green "Drop a spell, macro, or trinket here" bar at the bottom of the rotation editor — empty slots themselves accept drag-and-drop, and the `Spellbook` / `Macros` buttons in the Settings tab Tools section cover the "open spellbook" affordance. The Compiled Sequence card now grows into the reclaimed vertical space
- `VeritasUI_PriorityRotation` clicking an empty rotation slot toggles the Blizzard `PlayerSpellsFrame` (open if closed, close if open — same behaviour as the Spellbook button in Tools). Shift-clicking an empty slot toggles the Macro UI. Combat-guarded with a chat message. Empty-slot tooltip updated to document the new controls

## [1.5.0] - 2026-04-25

### Added
- `VeritasUI_Lib` — three new managed-panel helpers wrapping Blizzard's `UIPanelWindows` system: `VUI.RegisterManagedPanel(name, opts)`, `VUI.OpenManagedPanel(frame)`, `VUI.CloseManagedPanel(frame)`. Combat-safe via the existing `CombatQueue` and `pcall`-wrapped end-to-end. Documented Blizzard pushable values (`CharacterFrame=3`, `CollectionsJournal=0`, `ProfessionsFrame` outside `UIPanelWindows`) in the Lib comments for future module authors.
- `VeritasUI_PriorityRotation` Tools section in the Settings tab — spec switcher dropdown using the modern `WowStyle1DropdownTemplate`, plus `Spellbook` and `Macros` toggle buttons (click to open, click again to close) styled with `MagicButtonTemplate`
- `VeritasUI_PriorityRotation` trinket support — drag a trinket from your character pane or bag onto a rotation slot and PR will compile a `/use <ItemName>` macro for it. Item-name-based binding (not slot-based) so the rotation always fires THAT specific trinket. Restricted to `INVTYPE_TRINKET`; non-trinket items politely rejected. Editor displays trinkets with a yellow `[T]` tag, item icon, and standard Blizzard item tooltip on hover

### Changed
- `VeritasUI_PriorityRotation` settings panel now anchors to the standard Blizzard left edge via the `UIPanel` manager (`area="left"`, `pushable=0`) — visually and behaviourally indistinguishable from a Tier A primary panel like `CollectionsJournal`. Holds slot 1 against `CharacterFrame` / `SpellBookFrame` (which slide to slot 2), mutually exclusive with other Tier A panels (`Achievements`, `Housing`, `Maps`, `Appearances`). Escape closes it via `UISpecialFrames` registration. Replaces the previous floating `:SetPoint("CENTER")` + draggable behaviour
- `VeritasUI_PriorityRotation` editor help text and drop zone label updated to mention trinkets alongside spells and macros

### Fixed
- `VeritasUI_PriorityRotation` spec-switch handler now tries `C_SpecializationInfo.SetSpecialization` first and falls back to the global `SetSpecialization` — Midnight refactored the spec API into the `C_SpecializationInfo` namespace and the global may be absent or shimmed differently across builds

## [1.4.3] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` rotation editor "Compiled Sequence:" label + preview text now wrapped in a card matching the Phase 2 row card style (dark fill + 1px warm-amber border)
- Sequence preview card width now aligns with the row cards (was previously narrower)
- Card border tint refined across all editor cards (rows + sequence preview) from `(0.28, 0.23, 0.14, 0.75)` to `(0.32, 0.26, 0.15, 0.80)` for a "recessed in stone" look
- Sequence preview now scrollable via mousewheel for long rotations (e.g. 10 slots × freq 5 = 50 entries) — text no longer bleeds out of the card or frame

## [1.4.2] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` Settings tab action buttons (Create / Update Macro, Scan & Bind, Reset to Spec Defaults, Clear All Spells) swapped from `UIPanelButtonTemplate` to `MagicButtonTemplate` to match Blizzard's modern frame chrome (same template used by the Profession Specializations "Apply Knowledge" / "Overview" buttons)

## [1.4.1] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` rotation editor rows now render as bordered cards — dark fill with a 1px warm-amber border using `BACKGROUND`/`BORDER` draw layers
- Row gap increased from 2px to 4px for visible card separation
- Freq spinner `< >` text buttons replaced with arrow texture buttons using `SetRotation`
- Freq value label upgraded from `GameFontNormalSmall` to `GameFontNormal` white
- Drop zone replaced with a green-bordered card to distinguish it as a drop target

### Fixed
- Freq arrow vertical misalignment — both arrows now use identical rotation (`-π/2`) by pairing `Arrow-Down-Up` (dec) and `Arrow-Up-Up` (inc) so WoW's renderer produces pixel-perfect vertical alignment

## [1.4.0] - 2026-04-25

### Changed
- `VeritasUI_PriorityRotation` settings panel rebuilt on `PortraitFrameTemplate` with modern frame chrome
- Portrait slot now shows current spec icon (falls back to class atlas for unspecced characters)
- Spec/class name displayed in `GameFontNormalHuge` white, horizontally centered below the portrait
- Title bar "Priority Rotation" re-anchored to center on full frame width
- Tab navigation replaced with `PanelTabButtonTemplate` bottom tabs (Journeys-style)
- Column headers in the rotation editor now anchor to row components for pixel-accurate alignment
- Row slot numbers changed to center-justified under the `#` header
- Settings tab redesigned with gold section headers, dividers, full-width primary buttons, and side-by-side secondary buttons
- Freq guidance corrected — Freq 3+ for priority/cooldowns, Freq 1 for fillers
- Removed hardware-specific key-repeat wording from Setup instructions
- All 18 starter profiles updated: priority/cooldown spells default to Freq 3, filler spells to Freq 1

## [1.3.27] - 2026-04-24

### Fixed

- **[ZoneQuests] Deep-copy table defaults on init** — the shallow default-fill loop assigned `DEFAULTS.manualWatched` by reference into `VeritasUI_ZoneQuestsDB.manualWatched`, so subsequent `SnapshotWatched()` writes would mutate the `DEFAULTS` constant at runtime. Benign in current code paths (`DEFAULTS.manualWatched` is never re-read after init) but a latent footgun that would produce silent cross-mutation the moment any future code read `DEFAULTS.manualWatched` as an empty template. Added a local `DeepCopy` helper invoked only on table-typed defaults — matches the "table defaults must be deep-copied on first init" landmine documented in the development skill

## [1.3.26] - 2026-04-24

### Added

- **[PriorityRotation] `/pr diag` command for 12.0.5 API diagnostic** — tests `issecretvalue`, `table.freeze`, `C_ActionBar.RegisterActionUIButton`, `C_Secrets`, `C_RestrictedActions` availability; checks `SetCVar` lockdown, `newtable()` in restricted execution, `GetActionInfo` secret values across all 120 action slots, `GetAttribute` step readability, and icon resolution. Run in different contexts (open world, M+, raid, Delve) to identify platform-specific API restrictions

## [1.3.25] - 2026-04-21

### Changed

- **TOC bump to Interface 120005** — WoW patch 12.0.5 is now live; updated all module TOC files from 120001 to 120005 for full compatibility.

## [1.3.24] - 2026-04-16

### Fixed

- **TOC revert to Interface 120001** — v1.3.23 pre-bumped the interface version to 120005 for patch 12.0.5, but WoW rejects addons with a TOC version *higher* than the running client — there is no "load anyway" override for that direction. Reverted to 120001 so the addon loads correctly on live 12.0.1. The 120005 bump will be re-applied on patch day.

## [1.3.23] - 2026-04-16

### Changed

- **TOC bump to Interface 120005** — Updated all module TOC files from 120001 to 120005 for WoW patch 12.0.5 compatibility.

## [1.3.22] - 2026-04-11

### Fixed

- **[QualityOfLife] Auto Sell Junk gold reporting wildly inaccurate** — The tally used `C_Item.GetItemInfo` to look up each sold item's vendor price and multiply by stack count. In Midnight, `sellPrice` can return stale or secret values that pass the pcall arithmetic guard but contain bogus numbers, producing reported totals 20–30× the actual amount earned. Replaced with a `GetMoney()` delta approach: the player's gold is snapshotted before selling begins, and the reported amount is `GetMoney() - startMoney` after all items are gone, which is always accurate.

## [1.3.21] - 2026-04-09

### Fixed

- **[All] Comprehensive code review hardening pass** — 16 findings addressed across all five modules:
  - **[PriorityRotation/Core] SafeQuote injection** — `InjectSequence` now dynamically selects a long-string nesting level that cannot appear in the macro body, eliminating the theoretical edge case where a macro containing `]==]` would corrupt the secure Execute call.
  - **[PriorityRotation/Core] MAX_ACCOUNT_MACROS nil guard** — `UpdateMacroStub` now falls back to `120` if `MAX_ACCOUNT_MACROS` is nil, preventing a Lua error that would silently block macro creation in Midnight if the constant is renamed.
  - **[PriorityRotation/Core] Remove dead WrapScript guard** — `if not step or not macros[step] then step = 1 end` was unreachable dead code after `step % #macros + 1`; removed.
  - **[PriorityRotation/Core] Icon ticker only starts when a bar button is overridden** — Starting the ticker in Strategy 3 (keybind-only mode) caused a permanent 4 Hz idle ticker that immediately returned on every tick; ticker now only starts when `overriddenButton` is non-nil.
  - **[PriorityRotation/Editor] Guard PanelTemplates_GetSelectedTab** — Added existence check before calling this Blizzard global, which could be nil or renamed in Midnight.
  - **[CleanSolo] NUM_CHAT_WINDOWS nil guard** — Loop now uses `(NUM_CHAT_WINDOWS or 10)` to prevent a `compare number with nil` error if the constant is absent.
  - **[CleanSolo] Chat tab scan skips missing frames** — Changed `break` on a missing chat frame to a `skip`; non-contiguous frame slots no longer abort the entire scan.
  - **[CleanSolo] PLAYER_REGEN events moved into SetupPlayerFrameFade** — Combat enter/leave events are now only registered when the Player Frame Fade feature is active, eliminating unconditional event overhead for users with the feature disabled.
  - **[CleanSolo] Document HideBagButtons retry pattern** — Added comment explaining why KillAll runs at 0s, 0.5s, and 2.0s (login-sequence re-show bursts from Blizzard bag frames).
  - **[QualityOfLife] AutoRepair race condition eliminated** — `GetRepairAllCost()` called synchronously after `RepairAllItems(true)` returns the pre-repair client-cached value before the server updates it, making the guild-vs-personal cost split unreliable. Now always follows guild repair with a personal repair call to cover any remainder, and reports the original total cost with a guild-bank note.
  - **[QualityOfLife] Document bank slot magic number** — Added comment clarifying that the `28` slot-count limit in the SetItemButtonQuality hook refers to Midnight's bank container (-1) slot range.
  - **[ZoneQuests] Skip BuildZoneNameSet when disabled** — Zone change events now invalidate the name cache but skip the expensive map-hierarchy rebuild when ZoneQuests filtering is off; the next enabled sync rebuilds lazily via `cachedNameSet or BuildZoneNameSet()`.
  - **[ZoneQuests] HeaderMatches threshold lowered** — Substring fallback search now applies to zone names longer than 2 characters (was 4), catching short zone names like "Vale" that weren't matched by the exact-lookup path.
  - **[ZoneQuests] Correct SnapshotWatched comment** — Comment previously said disabling ZQ "re-tracks everything"; corrected to accurately describe that RestoreWatched restores the snapshot taken at enable/login time, not at disable time.
  - **[Lib] Remove unnecessary pcall on GetAlpha** — `GetAlpha()` never raises on a valid WoW Frame; replaced with a direct call. Alpha is a rendering property, not a game-state value subject to Midnight secret-value restrictions.
  - **[Lib] HookAllChildren no longer called on every OnEnter** — MicroMenu child-hook registration now runs only once at setup; removed the redundant per-hover-enter iteration that fired on every mouse-enter of MicroMenu despite the `hooked[child]` guard.

## [1.3.20] - 2026-04-07

### Fixed

- **[Lib] Restore Reload UI button in AddOn settings panel** — v1.3.12 replaced the working OnUpdate polling approach with an event-driven hook on `SettingsPanel.SelectCategory` which does not fire correctly in Midnight 12.0.1, causing the button to never appear. Reverted to the original 0.25s poll which works regardless of API shape.

## [1.3.19] - 2026-04-07

### Changed

- **[PriorityRotation] Automatically manage `ActionButtonUseKeyDown` CVar** — PR now sets the CVar to `0` (key-up firing) on login when enabled and on toggle-on, and restores it to `1` (key-down / Press and Hold Casting) on login when disabled and on toggle-off. Previously the conflict was only warned about; users had to manage the CVar manually, leading to a permanently desynced state where neither PR nor P&H casting worked correctly.

## [1.3.18] - 2026-04-07

### Fixed

- **[QualityOfLife] Guard item-level overlay against Midnight secret value errors in raid combat** — `C_Item.GetItemInfoInstant` and `C_Item.GetDetailedItemLevelInfo` can return secret values during raid encounters in 12.0.1; the comparisons `equipLoc ~= ""` and `ilvl <= 0` were outside any pcall, causing "attempt to compare secret value" Lua errors on every item button update (loot windows, gear inspection). Both comparisons are now wrapped in pcall so they degrade silently — overlays simply won't display for items with restricted data during encounters.
- **[QualityOfLife] Guard auto-sell junk price tally against secret vendor prices** — `C_Item.GetItemInfo` returns vendor price as a secret value in Midnight; arithmetic on it (`qty * vp`) threw an unguarded error on every sell-session tally. Both the GetItemInfo call and the multiplication are now pcall-protected; if the price can't be read, the item count is still announced without a gold amount.

## [1.3.17] - 2026-04-02

### Fixed

- **[ZoneQuests] Manually highlighted cross-zone quests now reliably preserved** — v1.3.16 attempted to use `QUEST_WATCH_LIST_CHANGED` to track player highlights but the event handler only captured one argument, so the `added` flag was always `nil` and the quest was never pinned; replaced the event-based approach entirely: `SyncTracking` now calls `C_SuperTrack.GetSuperTrackedQuestID()` directly at sync time and exempts the active super-tracked quest (the one with the minimap arrow) from zone-based removal; `SUPER_TRACKING_CHANGED` triggers a debounced re-sync so the quest is removed from the tracker promptly when the player clears the arrow

## [1.3.16] - 2026-04-02

### Fixed

- **[ZoneQuests] Manually highlighted cross-zone quests no longer auto-removed** — clicking a quest on the world map to set a minimap direction arrow triggered a zone-sync that immediately removed the quest from the Objective Tracker; the addon now tracks player-initiated highlight events via `QUEST_WATCH_LIST_CHANGED` and exempts those quests from zone-based removal until the player explicitly un-highlights them; quests un-highlighted while in a different zone are removed from the tracker normally

## [1.3.15] - 2026-04-01

### Fixed

- **[QualityOfLife] Fix Auto Sell Junk selling no items at all** — `MERCHANT_SHOW` fires before `MerchantFrame:IsShown()` returns `true`; the sell guard was immediately killing `sellState` and unregistering `BAG_UPDATE_DELAYED` before any items were sold. Fix: defer `AutoSellJunk()` by one frame with `C_Timer.After(0, AutoSellJunk)`.

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
- **VeritasUI\_Lib** — shared utilities: `VUI.Print()` formatter, `SmoothFade` per-frame fade manager, `HookPlayerFrameFade` with event-timing health detection, native settings panel helpers
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
