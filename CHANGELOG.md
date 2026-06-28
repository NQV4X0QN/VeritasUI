# Changelog

All notable changes to VeritasUI are documented here. Dates reflect the conversation sessions where changes were developed and tested.

## [1.7.15] - 2026-06-27

### Added
- `VeritasUI_AuctionHouse` — **a live progress indicator for the price scan, mounted in the empty band to the right of the Auction House money frame so it is visible on the Buy, Sell, and Auctions tabs alike.** Previously the auto-scan ran invisibly — you waited, with no feedback, until the "Scan complete" chat line. The scan already tracked a 0–1 `progress` value and broadcast its lifecycle on the event bus (`AH_SCAN_START` / `AH_SCAN_COMPLETE` / `AH_SCAN_FAILED`), but nothing consumed it on screen; the readout is a pure view subscribed to those existing events, so no scan logic changed. It is deliberately **two-phase** because only one phase has a knowable percentage: while waiting for the server snapshot (`REPLICATE_ITEM_LIST_UPDATE`, an unbounded wait with no progress signal by design) it shows an indeterminate animated sweep with a phase label and a live elapsed timer — "Connecting… (Ns)" before the throttle system is ready, then "Requesting auctions… (Ns)" after `ReplicateItems()` fires — and only once row-processing begins does it switch to a real determinate fill, "Scanning… N%", climbing 1→100%. A percentage is never invented for the wait. The bar uses the native player-health-bar fill atlas (`UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health`) and the `auctionhouse-itemheaderframe` frame art to match the native look, is centered against the atlas's visual cavity, and auto-hides shortly after a terminal message. Frame level is set by a relative bump off `AuctionHouseFrame`, not an absolute value (absolute `SetFrameLevel` does not stick on AH children). (`UI/ScanProgress.lua`, new)

### Fixed
- `VeritasUI_AuctionHouse` — **the sell strip no longer flickers and reshuffles when you open the Sell tab.** `Refresh()` was gated on the strip being *visible*, so item collection only began the instant you clicked Sell; the first scan then hit a cold item cache and, as `GET_ITEM_INFO_RECEIVED` events streamed in and the list re-sorted on each one, items visibly appeared, vanished, and shifted under the cursor — so a just-clicked item could disappear before it loaded. Collection is now gated on the Auction House *session* (`AH.isOpen`) instead of strip visibility, and a warm pass runs on `AH_OPEN`. Because `Render()` is safe on a hidden frame, the bag is collected and the cache-warm churn settles off-screen while you are still on the Buy tab; by the time you switch to Sell the list is already complete and stable, matching how established sellers (e.g. Auctionator) behave. Bag scanning still does not occur outside an open Auction House. (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" price line now matches Blizzard's 12.0.7 tooltip styling exactly (font, coin size, and column alignment).** In 12.0.7 Blizzard moved the native "Sell Price:" line off the `MoneyFrame` widget to an inline body-font text line and restyled it; our coins were still pinned to `NumberFontNormalRight` (ArialN / 14 / outline), which no longer matched. The native line was confirmed by live introspection to be the tooltip body font (`FRIZQT__` / 12 / no-outline); our coins now copy the live font from our own label line at render time, so they track the body font per-tooltip and across any future Blizzard restyle (what the old font-object pin only claimed to do). The coin column position (`COIN_COLUMN_X`) was set to the probe-measured rendered width of the native "Sell Price: " prefix (59 px) so our first digit sits directly under the native first digit, and the inline coin markup was matched byte-for-byte to native (`|A:coin-gold:14:14:2:0|a` — the inherited "13×13" code comment was wrong; native is 14×14 with a `2:0` baseline offset). (`Tooltip.lua`)

### Internal
- `VeritasUI_AuctionHouse` — **added an additive `AH_SCAN_REQUESTED` event**, fired in `Replicate.lua` immediately after `C_AuctionHouse.ReplicateItems()` goes out, marking the transition from the throttle/connect wait to the snapshot wait. It carries the auto/manual flag and changes no scan behavior; it exists so the new progress view can distinguish its two waiting phases. (`Replicate.lua`)

## [1.7.14] - 2026-06-21

### Fixed
- `VeritasUI_ZoneQuests` — **quests are now filtered by their actual objective location instead of the quest-log section header, fixing both missing in-zone quests and bleed-in from neighbouring zones.** The previous logic matched a quest's quest-log **header** string against the current zone name. Midnight's quest log groups many quests under non-geographic activity headers (Void Assaults, Dungeon, Meta, Abundance), so quests physically in the current zone but filed under such a header were wrongly hidden — e.g. standing in Silvermoon City, "Stalkers of the Stars" (in Murder Row, filed under "Void Assaults") never appeared. The module now derives the current-zone quest set from `C_QuestLog.GetQuestsOnMap` on the player's best map (walking up to the closest map level that has quests), and keeps a quest only when its **per-POI `mapID`** belongs to the current zone or a descendant sub-area. This correctly surfaces activity-headered quests that are genuinely local while rejecting sibling-zone bleed-in (e.g. Zul'Aman quests whose POIs draw inside the Eversong Woods map carry `mapID` 2536, a sibling, and are excluded; Silvermoon City quests carry `mapID` 2393, a child of Eversong, and are kept). Verified in-game across Eversong Woods, Zul'Aman, Voidstorm, and Harandar, including correct re-filtering on every zone transition. The "Always Show" pin toggles (Campaign / Important / Legendary / Meta / Daily & Weekly) and super-track preservation are unchanged and continue to override the zone filter, so a pinned quest type still shows everywhere regardless of zone. (`ZoneQuests.lua`)

### Internal
- `VeritasUI_ZoneQuests` — removed the legacy header-string matching machinery (`BuildZoneNameSet`, `HeaderMatches`, the directional-prefix stripper, and the zone-name cache) now that location is determined purely from map IDs. `/zq debug` rewritten to report the current best map, the resulting zone quest set, and a per-quest `zone` / `pin` / `dropped` verdict. Two map-based approaches were tried and rejected before landing on the per-POI `mapID` filter: walking map descendants/ancestors of the current zone (over- or under-showed depending on direction), and `C_QuestLog.GetQuestUiMapID` / global `GetQuestUiMapID` (returns a quest's anchor/hub map, not its objective zone — observed returning Silvermoon City for Voidstorm and Eversong quests alike, so it cannot distinguish a quest's real location). (`ZoneQuests.lua`)

## [1.7.13] - 2026-06-20

### Internal
- **Audit hardening pass (static + dynamic code audit; no gameplay behavior change).** A comprehensive seven-module read produced 0 critical/high logic findings; the codebase was confirmed solid. Applied changes are cleanup and hardening only:
  - **Dead code removed:** the unreferenced `AppendSpell` function in `Editor.lua` (orphaned since the v1.5.1 drop-zone removal), plus ~15 unused localized-global upvalues across `Lib.lua`, `AdvancedOptions/*`, `AuctionHouse/Core.lua`, `AuctionHouse/Database.lua`, `AuctionHouse/UI/SellStrip.lua`, `PriorityRotation/Core.lua`, and `QualityOfLife.lua`. Behavior-neutral; verified in-game with zero Lua errors.
  - **`VeritasUI_QualityOfLife`** — **`IsAddOnLoaded` now uses the modern `C_AddOns.IsAddOnLoaded` path** with a legacy-global fallback (mirrors `AuctionHouse/UI/SellStrip.lua`), future-proofing the `/way` TomTom-conflict check against removal of the bare global. Behavior identical on 12.0.7. (`QualityOfLife.lua`)
  - **`VeritasUI_PriorityRotation`** — **`/pr diag` now reports the live patch version** via `GetBuildInfo()` instead of a hardcoded "12.0.5" string, so the diagnostic header and `/pr help` line never go stale on a patch bump. The `table.freeze()` probe line dropped its stale "(12.0.5 confirmed)" parenthetical (it reports current availability, not a version claim). (`Core.lua`)
  - **`VeritasUI_PriorityRotation`** — **`/pr test` output unified onto `VUI.Print`**, so every line carries the `[Priority Rotation]` prefix (matching the earlier `/pr diag` and `/pr status` conversions). (`Core.lua`)
  - **Stale comments corrected:** `AuctionHouse/Tooltip.lua` comments that described the removed `SetTooltipMoney` approach now match the owned-fontstring render path (guards against reintroducing the v1.7.6 Secret-Value crash); `AdvancedOptions/Browser.lua` `KNOWN_CVARS` policy line-reference corrected; `AuctionHouse/Replicate.lua` "temp" diagnostic relabeled as a permanent debug aid (its first-scan-hang bug was fixed in v1.7.9).
  - **`SELL_BATCH` confirmed at 11** (`QualityOfLife.lua`) — verified working in-game on 12.0.7; the comment was corrected to record this as intentional, superseding the conservative 9 from the v1.3.14 era. No code change to the value.
  - **Added `.luacheckrc`** — a WoW-aware luacheck config (Blizzard global set, accidental-global / unused-variable / unreachable-code detection). luacheck run: 0 errors; warnings reduced from 80 to 24, the remaining 24 being intentional long display-string lines (no real issues suppressed).

## [1.7.12] - 2026-06-20

### Fixed
- `VeritasUI_AuctionHouse` — **the sell strip now shows reagent-bag items again (the module's primary purpose), reversing the v1.7.11 exclusion.** v1.7.11 stopped scanning bag 5 (the reagent bag) in response to a `CanPostItem` crash ("attempt to compare nil with number"). New evidence reframes that fix: the captured stack trace (`Blizzard_AuctionHouseSellFrame.lua:477` → `CanPostItem` → `CommoditiesSellFrame` `StartPost`/`PostItem`) shows the crash occurred **entirely inside Blizzard's own commodity-post code, with no VeritasUI frame on the stack**, and fired on the native "Create Auction" click — not on our `SetPostItem` load as the v1.7.11 commit message stated. The crash was reachable from Blizzard's native Sell flow too (loading a reagent natively and posting), so excluding bag 5 only removed our shortcut to a Blizzard-side bug, at the cost of the feature the module exists for. The crash **no longer reproduces on the current client by any path** (native sell from reagent bag, or sell-strip post) — most likely a 12.0.7 launch-week issue (the patch landed ~2026-06-15, the crash was hit 2026-06-17) since resolved server-side, though that attribution is probable, not confirmed. `CollectItems` now scans bags 0–5 again. (`UI/SellStrip.lua`)

### Added
- `VeritasUI_AuctionHouse` — **the sell strip now hides Warband-bound-until-equipped equipment, which cannot be auctioned.** Such items read `isBound = false` (they bind on equip) and carry a vendor sell price, so the existing "unbound + sellable" predicate wrongly admitted them — the strip could show a Warband weapon that can't be posted while hiding genuinely sellable items. Items are now rejected when `C_Item.IsBoundToAccountUntilEquip` returns true. This was verified by in-game probe (item 249677 Twinthorn Wildglaive) as the only clean discriminator: Warband-until-equip gear reports `bindType = 2`, identical to ordinary sellable BoE, so `bindType` cannot distinguish them. The check is conservative — it only rejects on a definitive `true`; on any error or unresolved result the item is shown, so a legitimate sellable is never hidden on doubt. Commodities (reagents, potions, dyes), ordinary BoE gear, and transmog "junk" armor all continue to appear. (`UI/SellStrip.lua`)

## [1.7.11] - 2026-06-17

### Fixed
- `VeritasUI_AuctionHouse` — **clicking a sell-strip item no longer throws a Lua error ("attempt to compare nil with number" in `CanPostItem`).** The bag scan in `CollectItems` looped over bags 0–5; bag 5 is the reagent bag, and Blizzard's AH `CanPostItem` → `StartPost` path crashes on reagent-bag items (nil deposit cost / missing category data). This bug was latent in prior versions because reagent-bag items were silently dropped as cache misses on first Sell-tab open and never appeared in the strip. The v1.7.10 cache-fill fix correctly populated them for the first time, making them clickable and surfacing the crash. Fix: `CollectItems` now iterates bags 0–4 only; the reagent bag (5) is excluded entirely. (`UI/SellStrip.lua`)

## [1.7.10] - 2026-06-16

### Fixed
- `VeritasUI_AuctionHouse` — **sell strip now populates all sellable items on first open of the Sell tab, not just the one or two already in the item cache.** `CollectItems` calls `C_Item.GetItemInfo` to read each item's vendor sell price; on the first Sell-tab open of a session most items aren't in the client cache yet, so `GetItemInfo` returns `nil` and those items were silently excluded — only previously-hovered or recently-used items (already cached) passed through. Clicking one item loaded it into the Sell form, which triggered cache population, and a subsequent `BAG_UPDATE_DELAYED` then revealed the rest — the visible symptom. Fix: when `GetItemInfo` returns `nil` (clean cache miss, distinct from a pcall error), the itemID is added to a `state.pending` set and `C_Item.RequestLoadItemDataByID` is called to actively request the data. The loader frame now also handles `GET_ITEM_INFO_RECEIVED`; when a pending itemID's data arrives, a 0.1s debounce timer (`ScheduleRefresh`) collapses any burst of incoming cache fills into a single `Refresh()` call. The strip populates fully within a fraction of a second of first open. (`UI/SellStrip.lua`)

## [1.7.9] - 2026-06-16

### Fixed
- `VeritasUI_AuctionHouse` — **first-Auction-House-visit-of-a-session scans no longer hang.** The v1.7.8 `FireWhenReady` fix correctly deferred until `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, but the server could still silently drop the `ReplicateItems()` call even after that event — confirmed in-game on day 2 of testing: the throttle system reported ready, `ReplicateItems()` fired, but `REPLICATE_ITEM_LIST_UPDATE` never arrived and the scan sat at `0%` indefinitely. Root cause: the server needs a moment beyond throttle-system readiness to accept replicate requests on the very first AH open of a session. Fix: after each `ReplicateItems()` call, a `REPLICATE_RETRY_DELAY = 10` second timer arms. If `REPLICATE_ITEM_LIST_UPDATE` arrives within that window (the normal path), the timer is cancelled immediately — no effect. If the event has not arrived after 10 seconds, the request is confirmed dropped (a genuine arrival would appear within 2–5 seconds) and `ReplicateItems()` is called again. The retry guard checks `AH.isOpen`, `scanning`, and `co == nil` before firing, so it can only trigger when the coroutine genuinely hasn't started. Timer is also cancelled on `AH_CLOSED`. (`Replicate.lua`)

## [1.7.8] - 2026-06-15

### Changed
- **Interface bumped to `120007` for the WoW 12.0.7 patch** (all seven module TOCs).

### Fixed
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" coins no longer leak onto player/NPC and other non-item tooltips.** Our coin display is a fontstring parented to the tooltip that persists between hovers; it was only hidden in the item-tooltip post-call, which never runs for unit/spell/etc. tooltips — so after hovering a priced item the stale coins appeared on the next player tooltip (e.g. a player showing the last item's price). It's now hidden whenever the tooltip is cleared (every rebuild, all content types); priced items re-show it in the same rebuild, so there's no flicker. (`Tooltip.lua`)

### Fixed (candidate — pending in-game verification)
- `VeritasUI_AuctionHouse` — **first-Auction-House-visit-of-a-session scans should no longer hang.** Confirmed cause: on the first AH open since login, the auto-scan fired its data request before Blizzard's throttle/message system was ready; the request was silently dropped, no data event arrived, and the scan sat at 0% until a `/reload` (re-opening the AH in the same session worked). The request is now deferred until the throttle system reports ready (`AUCTION_HOUSE_THROTTLED_SYSTEM_READY`) instead of firing too early. Defensive: if the readiness API is unavailable it falls back to firing immediately (prior behavior), and it uses an event wait, not a timeout. **This fix could only be tested on a fresh login, so it ships unverified for live confirmation;** the function and event were confirmed to exist in-client beforehand. (`Replicate.lua`)

## [1.7.7] - 2026-06-14

### Fixed
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" price line no longer reverts to the wrong font and old coin art (and no longer leaves a stray gap), including inside Delves, on login, and after picking up new bag items.** The v1.7.6 fix rendered the price through a private `TooltipMoneyFrameTemplate` driven by `MoneyFrame_Update`, on the belief that feeding it our own plain-integer price made it crash-safe. That was wrong: `MoneyFrame_Update` does arithmetic on an **internal** coin-column width (`silverWidth`) that becomes a **Secret Value** in instanced content (Delves/M+/raids), so it threw (`MoneyFrame.lua:340`) regardless of our price — and the pcall fallback quietly swapped in `GetCoinTextureString` text coins, which is the "old coins / wrong font" you saw. The price is now rendered **without ever calling Blizzard's money code**: a plain "Auction:" label line (matching the native "Sell Price:" label font) plus the coins drawn in a fontstring **we create and own**, parented to the tooltip, using the modern `Coin-Gold/Silver/Copper` atlases as inline `|A|` markup and the native money number font (`NumberFontNormalRight`). Because it's pure text and an owned region, there is no Blizzard money math to hit a Secret Value — verified rendering correctly in a Delve. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the "Auction:" coins now line up under the native "Sell Price:" coins.** Our owned coin fontstring is placed at a fixed column (`COIN_COLUMN_X`) from the label so the first digit sits under Sell Price's first digit, instead of being right-justified to the tooltip edge. The owned fontstring is hidden on every tooltip rebuild, so non-priced items never show stale coins from a previous hover. (`Tooltip.lua`)

### Internal
- `VeritasUI_AuctionHouse` — removed the temporary `/ah probe` diagnostic (its job — capturing the native coin atlases + money font specs — is done; those values are now baked into `Tooltip.lua`). A temporary `REPLICATE_ITEM_LIST_UPDATE` debug-trace line is intentionally **retained** in `Replicate.lua` to help diagnose a separate, still-open issue (first-Auction-House-visit-of-the-day scans can hang until a `/reload`); it only prints under `VeritasUI.debug`.

## [1.7.6] - 2026-06-13

### Fixed
- `VeritasUI_AuctionHouse` — **item tooltips no longer trigger a Lua error.** v1.7.2 switched the tooltip "Auction:" price line to the global `SetTooltipMoney` to pixel-match the native "Sell Price:" line. That function reuses Blizzard's *shared, pooled* money frame; calling it from our (insecure) addon context tainted that pool, and Blizzard's own Sell Price render then crashed doing arithmetic on a Secret Value (`MoneyFrame.lua:340`, "secret number value … tainted by VeritasUI_AuctionHouse") — item sell-price money is a Secret Value in Midnight. Once the pooled frame was tainted in a session, *every* item hover that drew a sell price threw. The price line now renders through a **private money frame we create and own** (`TooltipMoneyFrameTemplate`), driven by our plain-integer database price — so Blizzard's pool is never touched and its secure render is never disturbed. Same coins, same font as native, no crash. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the tooltip "Auction:" coins now align under the native "Sell Price:" coins** across every denomination combination. The price frame is shifted so each line's leftmost visible coin lines up: matching-denomination lines (gold↔gold, silver↔silver) align coin-for-coin; mismatched lines (e.g. a silver-only Sell Price vs. a gold Auction price) align at the block's left edge and stay inside the tooltip border. This is self-correcting across any font and value width — no hand-tuned spacing. (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — **the Sell-tab sellable-items strip now draws a border on *every* item, matching Blizzard's bags.** Previously only Uncommon (green) and above showed a colored edge; Poor (junk) and Common ("general") items had bare icons. Native item buttons border every item — gray on junk and common, colored above — so the strip now does too, using Blizzard's own bag quality palette (`BAG_ITEM_QUALITY_COLORS`). (`UI/SellStrip.lua`)

## [1.7.5] - 2026-06-13

### Fixed
- `VeritasUI_AuctionHouse` — **Auction House scans no longer fail intermittently.** The price scan was failing roughly half the time with "Scan failed." Root cause: a 45-second watchdog (added in v1.7.1 as a well-intentioned safety net) was declaring failure and **discarding the snapshot** when it arrived later than 45s — which a large, queued Auction House snapshot (200k+ rows) frequently does. The watchdog has been removed entirely; the scanner now waits for the data however long it takes, matching the proven model used by established scanners. The genuine "stuck flag" risk the watchdog was meant to address is now handled correctly by resetting scan state on Auction House open/close, with no failure timer. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **sell-strip tooltips now update while scrolling.** Previously, scrolling the sellable-items strip with the mouse held still kept showing the first item's tooltip; you had to move off and back. The tooltip now refreshes to whatever item is under the cursor on each scroll (and hides if you scroll onto an empty slot). (`UI/SellStrip.lua`)

### Removed
- `VeritasUI_AuctionHouse` — **the `/ah scan force` option.** Bypassing the 15-minute cooldown just fired a replicate request into the server's own cooldown — a silent no-op that looked like a failure. The cooldown is now always honored, matching how reliable scanners behave. `/ah scan` is unchanged.

### Added
- `VeritasUI_AuctionHouse` — **`/ah check`** diagnostic: shift-click an item after the command to see its stored price, age, and derived database key. Useful for confirming a scan recorded an item correctly.

### Internal
- `VeritasUI_AuctionHouse` — removed an unused `ADDON_NAME` local from five files (kept where actually used).

## [1.7.4] - 2026-06-12

### Fixed
- **Zone Quests login message** — its `/zq` slash command now renders in the same yellow as every other module's command. The other five modules wrap their command in the yellow color code; Zone Quests' was plain (white), an oversight from the v1.7.3 login-message standardization. Purely cosmetic — all six login lines are now visually consistent. (`VeritasUI_ZoneQuests/ZoneQuests.lua`)

## [1.7.3] - 2026-06-12

### Changed
- **Standardized every module's login message** to one consistent format: `[Module] vX.Y.Z loaded — /slash` (and `[Zone Quests] vX.Y.Z active for <zone> — /zq`). Previously some modules printed a version and a slash command while others just said "Loaded. Type /xxx to open settings." with no version. The version is pulled dynamically from `VUI.VERSION`, so these lines stay correct on every future bump. Clean Solo now advertises its short `/cs` alias. (`VeritasUI_AdvancedOptions/Core.lua`, `VeritasUI_AuctionHouse/Core.lua`, `VeritasUI_CleanSolo/CleanSolo.lua`, `VeritasUI_PriorityRotation/Core.lua`, `VeritasUI_QualityOfLife/QualityOfLife.lua`, `VeritasUI_ZoneQuests/ZoneQuests.lua`)

### Documentation / repo housekeeping
- **README brought current** — added the `VeritasUI_AuctionHouse` module (was entirely absent), corrected "six folders" → "seven" in the install steps, refreshed the Clean Solo (added Transparent Chat Background, Fade Action Bars) and Quality of Life (added AFK Screen, Repair Funding option) feature lists, corrected the Advanced Options CVar-enumeration description for Midnight (which removed `C_Console`), and removed a stale third-party-addon reference from the Priority Rotation description.
- **Removed two stale release-zip artifacts** (`VeritasUI-v1.6.32.zip`, `VeritasUI-v1.6.33.zip`) that were committed before `.gitignore` excluded `*.zip`; release zips live only on the GitHub Releases page.

## [1.7.2] - 2026-06-12

Two roadmap items for `VeritasUI_AuctionHouse`, both AH-only; no other module changed. Each verified in-game.

### Added
- `VeritasUI_AuctionHouse` — **auto-scan on Auction House open.** Opening the AH now automatically runs a price scan so tooltip prices stay fresh without typing `/ah scan`. It reuses the same 15-minute cooldown as a manual scan, so it silently does nothing if you scanned recently. A new **"Auto-scan on Auction House open"** checkbox (default on) in the AH settings panel controls it. You get a distinct "Auto-scanning prices…" start message, plus the usual success ("Scan complete — …") or failure message, so you always know whether to keep the window open and whether prices actually refreshed. (`Replicate.lua`, `Core.lua`, `Settings.lua`)

### Changed
- `VeritasUI_AuctionHouse` — **tooltip price line redesigned to match Blizzard's native "Sell Price:" line exactly.** The label is now `Auction:` (was "Auction (each)"), rendered in the same white, same font, and — crucially — using Blizzard's own embedded money frame (`SetTooltipMoney`) so the coin icons are the exact same model and size as the Sell Price coins, with the amount aligned directly beneath them. Previously the line used a right-justified text coin string, which used a different coin texture and font height. Battle-pet tooltips keep a text coin string (their custom frame has no money-frame support). (`Tooltip.lua`)
- `VeritasUI_AuctionHouse` — the scan-failure chat message is now cause-neutral: **"Scan failed — Prices were not updated; try again shortly."** (previously speculated a server cooldown, which the client cannot actually confirm). (`Replicate.lua`, `Core.lua`)

## [1.7.1] - 2026-06-12

Audit/robustness pass over the `VeritasUI_AuctionHouse` module (the v1.7.0 refocus shipped quickly; this is the follow-up quality review). All changes are AH-only; no other module touched. Each item below was verified in-game.

### Added
- `VeritasUI_AuctionHouse` — **battle-pet prices in tooltips.** Caged-pet auction prices were already recorded in the scan database (keyed by species) but never surfaced, because battle-pet tooltips do **not** flow through the item tooltip system. Added the correct hook (`BattlePetToolTip_Show`, which hands us the species id directly) so the "Auction (each)" line now appears on battle-pet tooltips in the AH, bags, and chat links. (`Tooltip.lua`)

### Fixed
- `VeritasUI_AuctionHouse` — **sell strip hardened against Midnight Secret Values.** The bag-scan that builds the sellable-items strip now wraps the bound-check, the `C_Item.GetItemInfo` call, and the vendor-price comparison in the suite's three-pcall pattern (mirroring QualityOfLife's AutoSell). A single problematic item is skipped instead of erroring the whole strip refresh. (`UI/SellStrip.lua`)
- `VeritasUI_AuctionHouse` — **price scan no longer strands on a dropped server response.** Added a watchdog: if `ReplicateItems()` is issued but `REPLICATE_ITEM_LIST_UPDATE` never arrives, the scan state resets cleanly and reports an honest message instead of leaving `/ah scan` permanently reporting "a scan is already running" until the AH is reopened. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — **a single malformed row no longer aborts an entire price scan.** The per-row read inside the scan coroutine is now pcall-isolated, so one bad row out of a 200k+ snapshot is skipped rather than discarding the whole scan. (`Replicate.lua`)
- `VeritasUI_AuctionHouse` — settings panel no longer depends on cross-frame event-dispatch order to seed its tooltip-toggle defaults (it now seeds them itself before reading them). (`Settings.lua`, `Tooltip.lua`)

### Changed
- `VeritasUI_AuctionHouse` — all `/ah` diagnostic and help output now routes through the standard `VUI.Print` formatter, so every line carries the `[Auction House]` prefix (matching the rest of the suite). (`Core.lua`, `UI/SellStrip.lua`)

### Removed
- `VeritasUI_AuctionHouse` — **dead-code sweep left over from the v1.7.0 Shopping-tab cut.** Removed the orphaned `AH.Money.SanitizePrice` helper (its only caller, the auction-posting path, was cut), a no-subscriber `AH_SCAN_PROGRESS` event broadcast, an unused local, and a global frame name on the strip buttons; scrubbed stale comments that still referenced removed files (`Throttle.lua`, `Search.lua`), a non-existent `/ah search` command, and obsolete development-phase tags. Comment-and-cleanup only — no behavioral change. (`Core.lua`, `Money.lua`, `Replicate.lua`, `Database.lua`, `Settings.lua`, `Tooltip.lua`, `UI/SellStrip.lua`)

## [1.7.0] - 2026-06-11

### Changed
- `VeritasUI_AuctionHouse` — **major refocus.** The module is no longer a "modernized Auctionator." Direct comparison against Midnight's native Auction House showed the planned Shopping/Buy/Cancelling clone duplicated functionality Blizzard now ships (category sidebar, sortable columns, Filter flyout with Required-Level/rarity/toggles, drill-down + Buy Now, Favorites-as-shopping-list). The module is refocused to do only what native does **not**: a price database feeding tooltip prices, plus the one genuinely-missing convenience — Auctionator's sellable-items bag panel, rebuilt natively on the default Sell tab.

### Added
- `VeritasUI_AuctionHouse` — **Sell strip (`UI/SellStrip.lua`)**: a horizontal strip of your sellable bag items mounted in the empty band under the native Sell tab's "Create Auction" button.
  - **Click an icon → the item loads into Blizzard's own Sell form** via `AuctionHouseFrame:SetPostItem(ItemLocation)` (the same path the native bag right-click uses). You verify, then click Blizzard's own Create Auction. **We never make a protected call — Blizzard owns the post entirely**, proven taint-clean in-game (populate-from-addon-code → native post produced no `ADDON_ACTION_BLOCKED`).
  - **Sellable predicate:** unbound items with a vendor sell price (verified to match native auctionability across the test bags). **Right-click an icon to hide it** from the strip (per-itemID blocklist; `/ah blocked` to list, `/ah blocked clear` to reset) — for dyes, saved reagents, etc.
  - **Mouse-wheel horizontal scroll** (no arrows). **Loaded-stack desaturation** mirrors Blizzard graying the bag item (hooks `SetPostItem`/`ClearPostItem`, matched by bag+slot, source-agnostic). **Native inset card** behind the icons using the `auctionhouse-itemheaderframe` atlas (the same art as the sell-slot card above). Quality-colored icon borders (`WhiteIconFrame`, no action-button glow) and correctly-sized **Midnight profession reagent-quality tier markers**.
  - The native **Buyout Mode checkbox is hidden** (it occupied the strip's space; the user always sells in buyout mode).
- `VeritasUI_AuctionHouse` — kept from earlier phases: the full-AH price scan (`/ah scan`), the native price database, and **auction prices in item tooltips** (the module's primary native-beating value).

### Removed
- `VeritasUI_AuctionHouse` — **the entire Shopping tab and its dependencies** (`Search.lua`, `Buy.lua`, `Shopping.lua`, `Throttle.lua`, `UI/TabInject.lua`, `UI/ShoppingTab.lua`, `UI/ShoppingCells.{lua,xml}`, `UI/FilterFlyout.lua` — ~4,200 lines). These cloned native Buy-tab functionality and were retired with the refocus above. The techniques (clean tab injection, taint-clean protected writes, live-client introspection) are preserved in git history and were reused where relevant. `Throttle.lua` was removed as dead code once no live AH queries remained (the price scan uses `ReplicateItems` directly). Orphaned `shopping` saved-variable data self-cleans on load.

## [1.6.52] - 2026-06-10

### Added
- `VeritasUI_AuctionHouse` — **Phase 4 Layer 4: the Shopping tab's Filter control** — a clean-room reproduction of Blizzard's native Buy-tab Filter button + filter flyout, extended with our own filters, all in one flyout (no tab-hopping). New file `UI/FilterFlyout.lua`.
  - **Reskinned Filter button** replacing the old "Search Options" stub. Built from the verified native dropdown-button atlas family (`common-dropdown-b-button` + `-hover`/`-pressed`/`-open`/`-disabled`), `GameFontNormal` label, with the native script-driven state swaps (OnEnter/OnLeave/OnMouseDown/OnMouseUp). Hover highlights in every state including while the flyout is open; the button swaps to the `-open` art while the flyout shows. Frame sits on the same grid as its Search / Add To List siblings (visible pill height is decoupled onto the background texture so alignment and height are independent).
  - **Native-faithful flyout** — `common-dropdown-bg` panel, `GameFontHighlight` section headers, texture-built checkboxes (`common-dropdown-ticksquare` + `common-dropdown-icon-checkmark-yellow`), and `common-search-border-*` numeric fields. Sections, top→bottom: **Level Range** · Uncollected/Usable/Current Expansion Only · **Equipment:** Upgrades Only · **Rarity** (7 quality checkboxes, quality-colored) · **More Filters:** Item Level, Max Buyout. Reproduced clean-room (our own frame/state); the native flyout frame is never reused.
  - **Filters split by mechanism (verified against `Enum.AuctionHouseFilter`, 14 members):** Level Range → `query.minLevel/maxLevel`; the four toggles (`UncollectedOnly=1`, `UsableOnly=2`, `CurrentExpansionOnly=3`, `UpgradesOnly=4`), `ExactMatch=5`, and the seven qualities (6–12) are all **server-side** `filters[]` members passed to `SendBrowseQuery`. Item Level + Max Buyout are **client-side** post-filters on the result rows (no native query field exists for them).
  - **Dynamic, like Blizzard's:** changing any server-side control re-runs the current search (single term or whole-list) with the new filters, debounced 0.3s so toggling several boxes collapses into one query; client-side controls re-filter the shown rows instantly with no re-query. Clicking outside the flyout closes it (via `GLOBAL_MOUSE_DOWN`, non-intercepting — your click still lands).
  - **Result-row tooltips** — hovering a results row now shows the item tooltip (prefers a true item hyperlink, falls back to `SetItemByID`), so items can be inspected without drilling in.

### Removed
- `VeritasUI_AuctionHouse` — **Import / Export / Export Results buttons** (were honest stubs). For a single-user, ~1-character account they serve no purpose: same-account characters already share shopping lists via the account-wide saved variable, the `WTF/.../SavedVariables/VeritasUI_AuctionHouse.lua` file already serves as the backup/transfer artifact, and a clean VeritasUI-native export blob would only round-trip into another VeritasUI install (a cross-account/sharing case that does not apply). The results panel reclaims the freed space; the New List button remains the sole bottom-left control.

## [1.6.51] - 2026-06-07

### Added
- `VeritasUI_AuctionHouse` — **Phase 4 Layer 3: Shopping Lists persistence, Recent Searches, and whole-list multi-term search.** The Shopping tab's left panel is now fully functional (previously stubbed).
  - **`Shopping.lua` — new persistence layer (UI-agnostic, mirrors `Search.lua`'s separation).** `AH.Lists` (create / delete / rename / add-item / remove-item) and `AH.Recent` (move-to-top, deduped, capped at 20), both over a new account-wide `AH.db.shopping = { lists, recent }` container. Terms are stored normalized (plain item name via `AH.Search.NormalizeSearchTerm`) so a shift-clicked link and a typed name dedupe identically. No `dbVersion` bump — this is UI state, not price-DB layout, so `InitDB`'s nil-seed upgrades any pre-Layer-3 saved var transparently with no migration.
  - **Shopping Lists left panel** — a `WowScrollBoxList` rendering saved lists as expandable headers (item count shown) with their search terms indented beneath. Any number of lists may be expanded at once. Expansion is signaled the native AH Buy-tab way — a gold selection band on the expanded header (`auctionhouse-ui-row-select`) plus the indented child rows — with no arrow glyph.
  - **Recent Searches left panel** — every search (button, Enter, shift-click, list-item click) is recorded newest-first and persists across `/reload` and relog.
  - **Whole-list multi-term search (`AH.Search.SearchList`).** Clicking a list header runs every term in the list sequentially through the existing throttle-queued browse engine (in a new `silent` mode that suppresses single-search events), accumulating results deduped by itemKey-string and keeping the lowest price seen per item. Progress is surfaced via a new `AH_LISTSEARCH_*` event family; results fill the same native results table.
  - **New List / Add To List wiring.** New List opens a native `StaticPopup` (Enter-to-create now works, routed through `StaticPopup_OnClick`). Add To List adds the current search term to the selected list. Left-row left-click searches; right-click removes (list deletion via a confirm popup).
  - **Right-click a results row → add that specific item to a list.** A native `MenuUtil.CreateContextMenu` lists each Shopping List (checkbox: checked = already present, click toggles add/remove) plus **New List…** (creates a list and adds the item in one step). Adds the exact item you clicked without retyping its name.

### Fixed
- `VeritasUI_AuctionHouse` — the Add To List button targeted a stale internal field after the multi-expand refactor and would always report "select a list first"; it now correctly targets the selected list.

## [1.6.50] - 2026-06-07

### Added
- `VeritasUI_AuctionHouse` — **Phase 4 Layer 2: the Shopping-tab drill-down + buying.** Clicking a results row now opens an individual-auction detail view modeled pixel-faithfully on Blizzard's native commodity/item buy display, wired to the proven `AH.Buy` engine.
  - **Two-pane drill-down (`UI/ShoppingTab.lua`).** A wide LEFT detail pane (item card + Quantity / Unit Price / Total Price / Buy) beside a narrower RIGHT auction list, each in its own themed inset. The item card uses the real circular icon mask + native item-border ring + quality-colored name on the `auctionhouse-background-buy-noncommodities-header` atlas, with a thin 1px tooltip-style border (not the heavy `InsetFrameTemplate` bevel).
  - **Native banded auction list (no fabricated textures).** Every row draws the verified native atlases — `auctionhouse-rowstripe-1` (full-width row band), `auctionhouse-ui-row-highlight` (hover), `auctionhouse-ui-row-select` (gold selection) — discovered by live-client introspection, not guessed. Price-left / quantity-right, headerless, matching native. Columns size so large gold values and large quantities both fit without clipping.
  - **Cumulative commodity selection.** Clicking row N selects rows 1..N (cheapest through N), highlights them gold, and fills the Quantity box with their summed quantity — the native commodity-buy behavior. "Select-all" (through the last row) uses the server's authoritative `GetCommoditySearchResultsQuantity` rather than the client row-sum; manual typing clears the selection (via the native `OnTextChanged` `userInput` flag). Total Price is a blended fill across price tiers.
  - **Buy Now, both paths, through the real UI.** Commodity: two-step `StartCommodity` → quote → `ConfirmCommodity`. Item: single `PlaceBid` buyout. Both fire from the Buy button's genuine hardware event (never throttle-queued), re-querying after purchase to refresh the list.
  - **Modern quantity input** — three-slice `auctionhouse-ui-inputfield-{left,middle,right}` atlas field (verified native), replacing the legacy beveled `InputBoxTemplate`.

### Changed
- `VeritasUI_AuctionHouse` — **native sort headers on the Shopping results table.** The Price / Name / Available column headers are now interactive, driving Blizzard's own header sort-state protocol (`RegisterHeader` / `SetSortOrder` / `GetSortOrderState` / `UpdateHeaders` against the global `AuctionHouseSortOrderState`), so the genuine native sort arrow and blue hover/active highlight light up exactly as on the Buy/Sell tabs. Click toggles ascending/descending; sort is client-side and stable.

### Removed
- `VeritasUI_AuctionHouse` — retired the Layer-2 development scaffolding now that the real Buy UI supersedes it: the `/ah buytest` validation harness (the OQ#5 taint test, its job done) and the `/ah rowdump` introspection probe. The live `AH.Buy` engine (`StartCommodity` / `ConfirmCommodity` / `CancelCommodity` / `IsActive` / `BuyItem`) is unchanged.

## [1.6.49] - 2026-06-06

### Added
- `VeritasUI_AuctionHouse` — **Phase 4: the Shopping tab (first in-AH UI) + verified protected-buy foundation.** The module's vision was refined this release to **a modernized, clean-room reimplementation of Auctionator** — its feature set (Shopping / Selling / Cancelling) rebuilt on *modern* Blizzard UI (where Auctionator still uses legacy assets), indistinguishable from today's default UI. The earlier "Browse" tab was repurposed into a **Shopping** tab to match Auctionator's model (Auctionator has no Browse tab; it doesn't re-skin Blizzard's native Buy).
  - **`UI/TabInject.lua` — native tab injection.** Injects our own tab into Blizzard's `AuctionHouseFrame`, matching the Buy/Sell/Auctions strip pixel-for-pixel. Our tab button lives under our *own* root frame (the inherited `parentArray="Tabs"` would otherwise silently pollute Blizzard's tab array), inherits `AuctionHouseFrameTabTemplate`, hooks `SetDisplayMode` (guarded on `#mode > 0` so our own teardown doesn't fight our clicks), re-injects idempotently on every AH open, and guards against the TSM sub-0.5 scale corruption.
  - **`Search.lua` — the query engine.** Keyword **browse** via `SendBrowseQuery` (throttle-queued, paginated to completion) plus a **drill-down** engine for per-item detail that handles the documented `SendSearchQuery` cold-cache trap by construction (gate on `GetItemKeyInfo`, validate-and-retry on false-empties, request-token matching, bounded timeout). Includes **shift-clicked-item / pasted-link normalization** (extracts the plain item name; a raw `|Hitem:…|h` string matches nothing on the AH server) — exposed for the search box so shift-clicking an item into Shopping Just Works.
  - **`UI/ShoppingTab.lua` + `UI/ShoppingCells.{lua,xml}` — the Shopping tab UI.** Search strip (`SearchBoxTemplate` with built-in clear button, Search / Search Options / Add To List), left **Shopping Lists / Recent Searches** sub-tabs (native `PanelTopTabButtonTemplate`), and a results table built on Blizzard's native **`TableBuilder`** — tab-bordered column headers, native `MoneyDisplayFrame` coin cells, `WowScrollBoxList` + `MinimalScrollBar`, columns **Price · Name · Available** matching Auctionator and native Buy exactly. Panels use the native **`auctionhouse-background-index`** atlas (not a fabricated fill — found in the game's own assets) for an authentically modern look.
  - **Protected-buy path PROVEN taint-clean (`Buy.lua`, resolves design OQ#5 — the project's highest-risk unknown).** Verified in-game that our own hardware-event button can drive the restricted commodity-purchase flow (`StartCommoditiesPurchase` → `COMMODITY_PRICE_UPDATED` quote → `ConfirmCommoditiesPurchase` → purchase succeeded) with **zero taint / blocked-action errors**. This unblocks the entire write side of the module — buying *and* Phase-5 selling (`PostItem`/`PostCommodity`) *and* Phase-6 cancelling (`CancelAuction`) all rely on this same capability. Hard rules recorded: protected calls must originate from a genuine hardware event and must NOT be throttle-queued (deferral strips the hardware context).
  - **Tooltip/DB note:** the scanned/DB market price intentionally appears only in item tooltips (its proper home), not as a results column — exact-match-only, blank on a miss, never an estimate (a wrong price is worse than no price).

### Notes
- The Shopping tab ships with search + results fully working and native-faithful. Selling/buying UI, drill-down, and the Shopping Lists / Recent Searches content are stubbed ("coming in a later layer") and land in subsequent passes — consistent with the suite's foundation-first, ship-each-phase cadence.

## [1.6.48] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **Phase 3: auction prices in item tooltips (first user-visible feature).**
  - **`Tooltip.lua`** — appends the stored market price to item tooltips via the modern hook `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` (verified 12.0.5). The callback reads the item link from `data.hyperlink` (falling back to `TooltipUtil.GetDisplayedItem`), looks it up with `AH.DB.GetMarketPriceForLink`, and adds an **"Auction (each)"** line in Blizzard coin-icon style plus an optional grey **"N seen · X days old"** annotation. Pure database read — no live AH query, works away from the Auction House, read-only (no taint). `pcall`-guarded so a malformed link can never error a tooltip; re-derives the link per tooltip rebuild so lines never stack. Items with no stored price show nothing (no empty line).
  - **`Settings.lua`** — three real, persisted checkboxes (all default on), bound to `AH.db.settings` via `Settings.RegisterAddOnSetting` → `Settings.CreateCheckbox`: *Show Auction Price in Tooltips*, *Show Quantity Seen*, *Show Price Age*.
  - **Phase 2 price accuracy confirmed:** spot-checked tooltip prices against the live Auction House in-game and they match — validating the full scan → per-unit keying → storage → readback pipeline produces correct values, not just plausible counts.

## [1.6.47] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **Phase 2: full-scan price database (first real data).**
  - **`Replicate.lua` — chunked full-scan driver.** `C_AuctionHouse.ReplicateItems()` → `REPLICATE_ITEM_LIST_UPDATE` → reads `GetNumReplicateItems()` rows via `GetReplicateItemInfo` + `GetReplicateItemLink`. **The row loop runs in a coroutine sliced to an ~8 ms/frame budget** so even a 50k–200k+ row snapshot never hitches the client (verified in-game on a ~278k-auction snapshot with no visible stutter). Per-row policy: skip bid-only auctions (`buyoutPrice == 0`), normalize to per-unit price (`floor(buyout / count)`), aggregate per key (min unit price + summed qty), commit once per item. Enforces a persisted **15-minute scan floor** (`/ah scan force` overrides). Fires `AH_SCAN_START` / `AH_SCAN_PROGRESS` / `AH_SCAN_COMPLETE` / `AH_SCAN_FAILED` on the module event bus; aborts cleanly if the AH closes mid-scan.
  - **`Database.lua` — native price store (no LibCBOR).** Key scheme (resolves design OQ#3): `p:<speciesID>` for battle pets, `i:<itemID>:<itemLevel>` for equippable gear (ilvl from `C_Item.GetDetailedItemLevelInfo` so variants don't collide — NOT `GetReplicateItemInfo`'s `level`, which is required *player* level), `i:<itemID>` for everything else (commodities/mats/consumables). The full 4-field `C_AuctionHouse` ItemKey is intentionally not used — `itemID[:ilvl]` is the right pricing granularity and Midnight dropped suffixes. Per-unit copper integers; per-day `{min,max,qty}` history; prune-on-write at a 14-day retention default. API: `MakeKey`, `Record`, `GetMarketPrice`, `GetMarketPriceForLink`, `GetPriceHistory`, `GetItemCount`, `GetPriceAge`, `Wipe`.
  - **`/ah scan`** (+ `scan force`) and **`/ah wipe`** commands; scan progress/complete chat reporting; `/ah diag` now shows live scan state (ready / cooldown / scanning %) and the real priced-item count.
  - Verified in-game: a scan priced **8,327 distinct items from 278,623 auctions**, persisted across `/reload`, with the scan floor enforced and no frame hitch. (Per-item price *accuracy* is spot-checkable in Phase 3 once tooltip prices render.)

## [1.6.46] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **Phase 1: session lifecycle + mandatory throttle queue + money helpers (foundation, no user-facing feature yet).**
  - **Session lifecycle (`Core.lua`)** — handles `AUCTION_HOUSE_SHOW` / `AUCTION_HOUSE_CLOSED` / `AUCTION_HOUSE_DISABLED`, tracks `AH.isOpen` / `AH.disabled`, and broadcasts `AH_OPEN` / `AH_CLOSED` / `AH_DISABLED` on a new in-module event bus.
  - **`AH.Events` pub/sub bus (`Core.lua`)** — a minimal `On(name, fn)` / `Fire(name, ...)` bus (pcall-isolated handlers). `VeritasUI_Lib` has no EventBus and the suite's module-independence rule forbids cross-module coupling, so the AH module owns its own. Defined before sibling files so they can subscribe at file-load time.
  - **`Throttle.lua` — mandatory AH send-queue.** Blizzard rate-limits AH traffic and gates its own SellFrame on `IsThrottledMessageSystemReady()`. This queue dispatches one send at a time only when the throttle system is ready, re-arms on `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, re-queues the in-flight send at the head on `AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED`, and clears on `AH_CLOSED`. Public API: `Enqueue(fn, label)`, `Clear()`, `PendingCount()`, `IsAwaiting()`. All later-phase AH queries (browse/search/replicate/owned) must route through this rather than calling `C_AuctionHouse` directly.
  - **`Money.lua` — copper formatting/rounding helpers.** `Format` (Blizzard coin-icon string via `C_CurrencyInfo.GetCoinTextureString`), `FormatText` ("12g 34s 56c"), `Breakdown`, and `SanitizePrice` (mirrors Blizzard's `AuctionHouseUtil.SanitizeAuctionHousePrice`: rounds up to copper, or to silver when `C_AuctionHouse.SupportsCopperValues()` is false). **Verified in-game: retail AH returns `SupportsCopperValues() == false`, so prices round up to the nearest silver** (e.g. `SanitizePrice(12345.6) == 12400`). This is a convenience/consistency layer, NOT a Secret-Value taint boundary (see design §2.1 — AH money is plain copper integers).
  - **`/ah diag` expanded** with session state (AH open / disabled), throttle state (ready / awaiting / pending), and a money-helper self-test line. New **`/ah throttletest`** enqueues a no-op send to verify the queue end-to-end (requires the AH open).

## [1.6.45] - 2026-06-05

### Added
- `VeritasUI_AuctionHouse` — **New 7th module (Phase 0 scaffolding).** Adds the foundation for an Auctionator-class Auction House module: full-scan price database, tooltip prices, search/browse, selling assistance, and owned-auction cancelling — built clean-room against the modern `C_AuctionHouse` API (Interface 120005), native-only (no LibStub/LibCBOR/Ace), and styled to be indistinguishable from Blizzard's own AH UI. **This release is scaffolding only — no AH features are active yet.** Phase 0 delivers: (a) `VeritasUI_AuctionHouse.toc` (`RequiredDeps: VeritasUI_Lib`, `SavedVariables: VeritasUI_AuctionHouseDB`); (b) `Core.lua` — seeds `VeritasUI_AuctionHouseDB = { dbVersion=1, prices={}, settings={} }` via recursive `DeepCopy` (the anti-aliasing pattern used by CleanSolo/ZoneQuests), registers `/ah` + `/auctionhouse` with `help`/`diag`/`settings` subcommands, and prints a load line on `PLAYER_LOGIN`; (c) `Settings.lua` — a discovery-only Blizzard Settings category + shared Reload-UI label. The module's main UI will be **injected tabs on Blizzard's `AuctionHouseFrame`** (matching the native Buy/Sell/Auctions tab strip) rather than a standalone window, so no `RegisterManagedPanel` is used — the one intentional divergence from the PriorityRotation/AdvancedOptions panel pattern. Full design, verified API facts, and the phased build plan live in `AUCTIONHOUSE_DESIGN.md` (skill directory). `/ah diag` reports module version, DB readiness, schema version, priced-item count, and AH-open state.

### Notes
- All 8 version strings (7 module TOCs + `Lib.lua` `VUI.VERSION`) bumped to 1.6.45 in lockstep. The suite's skill `sync-check.sh` was updated to count version-bearing files dynamically (no longer hardcoded to 6) so it stays accurate as modules are added.

## [1.6.44] - 2026-05-16

### Changed
- `VeritasUI_PriorityRotation` — **`/pr status` body now emits via `VUI.Print('Priority Rotation', ...)` matching F-38's `/pr diag` pattern.** F-38 (v1.6.42) unified the `/pr diag` output channel but was scoped to `/pr diag` only per the audit; `/pr status` retained the same header-uses-VUI.Print / body-uses-print mix that F-38 corrected. Per Observation #1 from `REMEDIATION_DELTA_AUDIT.md` (post-Phase 8 consistency cleanup, user-approved Phase 9 scope): bulk-converted 5 `print()` calls in `Core.lua:589-605` to `VUI.Print('Priority Rotation', ...)` using the same line-bounded perl regex as F-38. Multi-line prints (the `Macro:`/`On bar:`/`Keybind:` continuations) convert correctly because each trailing `)` still balances the opening `(` we replaced. All `/pr status` output now consistently prefixed.
- `VeritasUI_PriorityRotation` — **`UpdateMacroStub` now `pcall`-guards `CreateMacro` symmetrically with the F-7 `EditMacro` wrapping.** F-7 (v1.6.39) wrapped `EditMacro` at `Core.lua:318` to catch transient macro-frame state during `/reload` bursts; `CreateMacro` at `Core.lua:328` is called under the same conditions but was left unwrapped per F-7's audit-defined scope. Per Observation #4 from `REMEDIATION_DELTA_AUDIT.md` (user-approved Phase 9 scope): wrapped in `pcall`; on failure prints `|cFFFF4444Couldn't create the Attack macro|r — <err>` via `VUI.Print` and returns `false`, matching the failure-return contract used by both the EditMacro branch above and the macro-list-full branch below. Both macro-write APIs in `UpdateMacroStub` now have identical pcall-and-return-false handling.

### Documentation
- `VeritasUI_PriorityRotation` — **Stale legacy-`GetItemInfo` comment in `Editor.lua` Refresh block updated to match F-37's migrated code.** F-37 (v1.6.42) migrated the actual API call from legacy `GetItemInfo` to `C_Item.GetItemInfo` at `Editor.lua:631`, but the descriptive comment immediately above (`Editor.lua:616-618`, the "Refresh icon" doc block) still named the legacy global. Per Observation #2 from `REMEDIATION_DELTA_AUDIT.md` (user-approved Phase 9 scope): updated comment text from "refresh icon from `GetItemInfo`" to "refresh icon from `C_Item.GetItemInfo`" so the comment matches the migrated code.

### Skill maintenance (outside repo)
- `~/.agents/skills/veritasui/SKILL.md` — Added `**Policy:**` field to the CleanSolo Module Inventory entry cross-referencing the v1.6.43 file-top POLICY block at `CleanSolo.lua:4-41` (F-10 / OQ#3). Captures the `hooksecurefunc`-required-`/reload` rationale, the intentional asymmetry with QoL, and the tooltip wording policy. Per Observation #3 from `REMEDIATION_DELTA_AUDIT.md` (user-approved Phase 9 scope). Skill files are outside the repo's git history; no separate commit but logged here so the change is discoverable from changelog history.

### Deferred (per user direction in Phase 9)
- Observation #5 (CHANGELOG "Conventions" subsection as standing format) — left for the user to decide naturally as future entries accumulate.
- Observation #6 (`VUI.PrintRaw` body-text helper to suppress per-line prefixes in `/pr diag`) — left as YAGNI; `/pr diag` is a rarely-used diagnostic command and the current verbose output is acceptable.

## [1.6.43] - 2026-05-16

### Documentation
- `README.md` — **Two stale module descriptions corrected.** (1) Line 32 (AutoSell): replaced "reports earnings via gold delta" with "reports earnings by summing item sell prices, independent of any concurrent gold deductions (e.g. AutoRepair on the same merchant frame)" — v1.6.36 reverted from `GetMoney()` delta accounting to item-value summing as part of the AutoSell/AutoRepair decoupling that fixed the "Sold N for 0g" race; the README still described the pre-v1.6.36 mechanism. (2) Line 47 (PR): the bullet "Dynamic icon shows the current spell on the action bar" deleted entirely — the icon ticker was removed in v1.6.25 as part of PR architectural hardening (`Show()`/`SetTexture` on ActionButton children propagated taint causing Secret Value errors in Delves/M+/raids); the README still claimed the feature existed.
- `VeritasUI_CleanSolo` — **`/reload`-required policy formalized as file-top comment block + tooltip consistency pass.** Per audit OQ#3, CleanSolo's `hooksecurefunc`-heavy implementation cannot cleanly toggle off mid-session (hooks have no inverse), so settings cannot apply live the way `QualityOfLife`'s v1.6.28 mid-session-apply pattern does. This asymmetry is intentional but was previously undocumented in the file itself, leaving any reader (or future audit) wondering whether it was a bug or a feature. Added a 38-line POLICY block at the top of `CleanSolo.lua` (lines 4–41) documenting: (a) why the module uses `hooksecurefunc` extensively, (b) why hooks can't be removed at runtime, (c) the chosen design (db-gating at hook-installation time on `PLAYER_LOGIN`), (d) the explicit asymmetry with `QualityOfLife` and why both are correct, (e) the policy that all CS setting tooltips and on-toggle messages mention `/reload to apply`. Also updated all 11 setting tooltips (10 checkboxes in the `options` table + the Fade Action Bars dropdown) to consistently end with "Requires `/reload` to apply." — the Fade Action Bars dropdown previously said "`/reload` to apply" (slightly different wording) and the 10 checkboxes said nothing about `/reload`. All tooltips now use the same suffix wording. No Lua logic changes.

## [1.6.42] - 2026-05-16

### Added
- `VeritasUI_Lib` — **`VUI.debug` diagnostic flag (file-scope, default `false`).** Opt-in gate for prints from normally-silent paths. Currently used by `CombatQueue` (see below); future silent paths can adopt the same pattern. Flip at runtime via `/run VeritasUI.debug = true` and reproduce the issue. Off by default to keep normal play uncluttered.

### Changed
- `VeritasUI_Lib` — **`CombatQueue` now surfaces queued-closure errors when `VUI.debug` is on.** The `PLAYER_REGEN_ENABLED` drain at `Lib.lua:342-353` previously did `for _, fn in ipairs(pending) do pcall(fn) end` — errors caught (the queue must always finish draining; one bad action shouldn't strand the rest in combat-locked state) but completely silent, leaving developers and users unable to diagnose stuck-frame symptoms with no error trail. Wrapped the `pcall` to capture the error and print `|cFFFF4444[VeritasUI]|r CombatQueue error: <err>` only when `VUI.debug == true`. Behavior unchanged when the flag is off (still silent, queue still drains fully); when the flag is on, every queued-closure failure surfaces with its full Lua error message.
- `VeritasUI_PriorityRotation` — **Editor `GetItemInfo` migrated from legacy global to `C_Item.GetItemInfo` namespace.** Two sites in `Editor.lua` (`BuildEntryFromCursor` line 153; `Refresh` icon path line 631), both already pcall-wrapped by F-2 in v1.6.38. Return-value signature is identical between the legacy global and `C_Item.GetItemInfo` in 12.0.5 — both return `(name, link, quality, level, minLevel, type, subType, stack, equipLoc, texture, sellPrice, classID, ...)` so the positional captures remain correct without modification. Brings `Editor.lua` into namespace-consistency with `QualityOfLife.lua`'s `SetupItemLevels` paths, which use `C_Item.GetItemInfo` throughout. One of the last legacy-global call sites in the suite is now removed.
- `VeritasUI_PriorityRotation` — **`/pr diag` body now emits via `VUI.Print('Priority Rotation', ...)` instead of bare `print()`.** The diagnostic command had a header that already used `VUI.Print` but body lines used bare `print()`, creating a mixed-channel output where the header had the `[Priority Rotation]` prefix and 46 body lines didn't. Bulk-converted all 46 `print()` calls in `Core.lua:632-779` to `VUI.Print('Priority Rotation', ...)` via a line-bounded perl regex. Indentation and color-code formatting preserved verbatim. The single multi-line `print` (the slot-type diagnostic at line 710) converts correctly because the trailing `)` on the continuation line still balances the opening `(` we replaced. All `/pr diag` output now consistently prefixed. Tag chosen as `'Priority Rotation'` (matching the existing header) rather than the audit-suggested `'/pr diag'` to keep the prefix consistent across the entire PR module's output. The same `print()`/`VUI.Print` mix exists in `/pr status` (lines 589-604) but is out of F-38's scope and left untouched.

### Fixed
- `VeritasUI_Lib` — **`RegisterManagedPanel` now warns instead of silently returning on bad input.** `Lib.lua:418` rejected non-string `frameName` (nil, frame objects, numbers — all caller-side bugs) by returning silently. A developer registering a panel and forgetting to pass the frame's name as a string would see "panel not registered" with no error to debug. Added `VUI.Print("Lib", "RegisterManagedPanel: bad frameName (got <type>, expected string)")` before the `return` so the bug is immediately visible at file-load time. The string check itself is unchanged — non-strings still bail out and don't pollute `UIPanelWindows`.

## [1.6.41] - 2026-05-16

### Changed
- `VeritasUI_CleanSolo` — **Defaults init now uses recursive `DeepCopy` instead of inline shallow copy (preventive).** The `ADDON_LOADED` handler in `CleanSolo.lua` previously initialized table-typed defaults with a one-level inline shallow copy (`for k2, v2 in pairs(v) do db[k][k2] = v2 end`). This is correct for the only currently-existing table default (`fadeActionBars = {}`, an empty table with no nested keys), but any future nested default would silently alias the `defaults` constant under the shallow-copy idiom — mutating `db.<table>.<nested>` would mutate `defaults.<table>.<nested>` at runtime, an extremely subtle aliasing bug that only surfaces when the user's saved-vars and the constant both end up pointing at the same subtable. Replaced with the recursive `DeepCopy` pattern ported verbatim from `ZoneQuests.lua:357-362` (the audit-blessed implementation, also documented in SKILL.md Known Landmines under "Table defaults must be deep-copied on first init"). Behavior unchanged for the current single flat table default; future-proof against new nested defaults.

### Documentation
- `VeritasUI_AdvancedOptions` — **`KNOWN_CVARS` policy formalized as comment block (per audit OQ#2).** The master CVar list at `Browser.lua:49-67` includes some Midnight-removed CVar names. The audit raised this as F-12 (apparent drift); investigation confirmed it is policy: `C_CVar.GetCVarInfo` returns `nil` for removed names, and the Strategy 3 probe loop silently skips any name that returns nil. Removing entries from `KNOWN_CVARS` would risk accidentally pruning a CVar that does exist on this client (Blizzard restoring or renaming a CVar between patch cycles is not unprecedented), and the cost of keeping a dead entry is one wasted probe per `/reload` (negligible). Replaced the previous one-line "extend freely; invalid names are harmlessly skipped" comment with a full POLICY block at the same site (`Browser.lua:49-66`) explicitly: (1) calling out `C_CVar.GetCVarInfo`-nil as the silent-skip mechanism, (2) cross-referencing the Strategy 3 loop where the probe runs (line 225), (3) documenting the rationale for never pruning entries, (4) tagging the policy with its formalization version (v1.6.41) and origin (audit OQ#2). No code change. Future audit cycles should treat apparent stale entries in `KNOWN_CVARS` as policy, not drift.

### Conventions
- **`KNOWN_CVARS` is intentionally broad.** Dead names from previous patch cycles are silently skipped at runtime via `C_CVar.GetCVarInfo` returning nil. Entries are NOT pruned on Midnight removals — removing a name risks accidentally removing a CVar that does exist. See the policy comment at `VeritasUI_AdvancedOptions/Browser.lua:49-66`. This is policy, not drift.

## [1.6.40] - 2026-05-16

### Changed
- `VeritasUI_QualityOfLife` — **`[noautorepair]` guild-info parsing is now case-insensitive and tolerant of whitespace inside the brackets.** The auto-repair feature respects a longstanding guild-convention tag in `GetGuildInfoText()` — if the tag is present, the guild-bank repair branch is skipped and personal gold covers the cost. Previously the parser at `QualityOfLife.lua:264` (now line 300 after F-1's expansion) used `:find("[noautorepair]", 1, true)`, a plain literal match that only fired on the exact lowercase string `[noautorepair]`. A GM who typed `[NoAutoRepair]`, `[ noautorepair ]`, or `[NOAUTOREPAIR]` would have their suppression intent silently ignored and the user's repairs would still hit the guild bank. The user is at the mercy of whatever the GM typed; defensive parsing only ever makes the feature more reliable. Replaced with `:lower():find("%[%s*noautorepair%s*%]")` — case-insensitive (`:lower()` first), tolerant of optional whitespace immediately inside both brackets. Internal whitespace (`[no auto repair]`) is intentionally NOT matched so a GM who really did mean a different bracketed tag isn't accidentally swept up by the suppression convention. Resolves OQ#4.

### Fixed
- `VeritasUI_QualityOfLife` — **`/way` usage hint now states "coordinates must be positive 0–100"** so users who type `/way -5 50` (or any negative coordinate) understand why the command rejected their input. The current `(%d+%.?%d*)` parse pattern correctly refuses to match negative numbers (which don't exist in WoW maps — coordinates are always 0–100 within a map's UV space), but the rejected input falls through to the usage hint without explaining the constraint. The 0–100 range check at `QualityOfLife.lua:1278` does emit a friendly "Coordinates must be between 0 and 100." message, but only on a successful parse where the values exceed 100; negative coordinates fail to parse entirely and never reach that line. Updated the usage hint text inline to make the constraint discoverable on the first failed attempt. No pattern change, no behavior change for valid input — purely a clarity fix per the F-31 pre-resolved decision.

## [1.6.39] - 2026-05-16

### Added
- `VeritasUI_PriorityRotation` — **One-time per-session diagnostic warnings for missing macros and stale spellIDs in compiled rotations, with `UPDATE_MACROS` listener so the missing-macro warning surfaces immediately on external macro deletion.** Two parallel diagnostic gaps were closed in `Core.lua` `CompileSequence`. The macro branch (was lines 171–177) silently elided macro entries whose macros had been deleted or renamed since authoring — the rotation simply got shorter with no signal to the user. The spell branch (was lines 185–188) emitted `/cast <spellName>` text for stale `spellID`s without verifying the ID still resolved, so every key press surfaced an "Unknown spell: X" line in chat with no indication of which rotation slot was the culprit. Both branches now use the same warn-once-per-session pattern: file-scope `PR._missingMacroWarned = {}` and `PR._missingSpellWarned = {}` (declared with the `PR.*` constants block at line 65–66) track which names/IDs have already been reported. On a successful resolve the stored flag is cleared, so a future delete-and-recompile re-warns. On a missing macro or `C_Spell.GetSpellInfo`-nil spellID, a single `VUI.Print` "Missing macro X — entry skipped this session" or "Stale spell X (ID N) — entry skipped this session. Drag the current version of the spell back onto the slot." is emitted and the entry is elided from the compiled sequence as before. Subsequent compiles are silent until the entry resolves or `/reload` clears the table.
  - **`UPDATE_MACROS` listener (F-5 extension, Option C, approved post-Phase 3):** initial F-5 implementation matched the audit's recommendation verbatim but missed a real-world flow gap — `CompileSequence` is only called on profile change, editor edits, or specific slash commands, never on external macro deletion. A user who deleted a macro from `/macro` saw the rotation lose its compiled-cache contents only at the next manual recompile, with no warning surfacing in the meantime, and (separately, pre-existing per F-1 baseline) the rotation could appear "stuck" if the cached macro body became internally inconsistent. Registered `UPDATE_MACROS` on the existing event frame and routed it through `PR:ScheduleCompile()` (already-existing 0.3s debounce path; no new compile entry point introduced). Editor bursts — rapid save/rename/reorder during macro editing — collapse into a single recompile 0.3s after the last fire, so cadence concerns are bounded by the existing debounce. `CompileSequence`'s `if not self.db then return end` guard at line 150 makes any pre-`ADDON_LOADED` fire a no-op. Net effect: deleting a macro that's referenced by the active rotation now (a) immediately surfaces the F-5 warning, (b) recompiles the sequence excluding the missing entry so the rotation continues working with the remaining slots, and (c) restores the warning if the macro is later recreated and deleted again. The audit's optional Editor.lua red `[M]` visual indicator was deferred per minimal-change preference; rotation row icons remain unchanged.

### Changed
- `VeritasUI_PriorityRotation` — **`UpdateMacroStub` now `pcall`-guards `EditMacro` and returns false on failure.** `EditMacro(idx, name, icon, body)` at `Core.lua:273` was historically reliable but the macro frame can be in a transient state during `/reload` bursts or addon-driven `CreateMacro` pile-ups; a hard error here would surface as a vague Lua popup with no actionable recovery message. Wrapped in `pcall`; on failure prints `|cFFFF4444Couldn't update the Attack macro|r — <err>` via `VUI.Print` and returns `false`, matching the failure-return contract already used by the macro-list-full branch immediately below (line 280–283). `CreateMacro` at line 277 is intentionally not wrapped — F-7 scope is `EditMacro` only; a future audit cycle can address `CreateMacro` if its surface ever proves unreliable.

### Fixed
- `VeritasUI_PriorityRotation` — **`/pr settings` typed before Settings panel init now prints a friendly message instead of erroring on `Settings.OpenToCategory(nil)`.** `PR.settingsCategoryID` is set in `Settings.lua:512` after `category:GetID()` resolves; if the user types `/pr settings` during the brief PLAYER_LOGIN burst before that init line runs (timing-fragile, may need repeated tries to reproduce), `Core.lua:466` previously called `Settings.OpenToCategory(nil)` which depending on Blizzard's tolerance either silently no-op'd or surfaced a Lua error. Added a nil-check: if `PR.settingsCategoryID` is set, open the panel; otherwise emit `Priority Rotation is still loading — try again in a moment.` via `VUI.Print`. After PLAYER_LOGIN completes the panel opens normally as before.

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
