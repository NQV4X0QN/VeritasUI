-- VeritasUI_QualityOfLife / QualityOfLife.lua
-- Functional enhancements: map coordinates, item levels, auto-repair, auto-sell, AFK screen.
-- Settings: Options → AddOns → Quality of Life  |  /qol

local ADDON_NAME     = "VeritasUI_QualityOfLife"
local SETTINGS_LABEL = "Quality of Life"

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G               = _G
local ipairs, pairs    = ipairs, pairs
local pcall, type      = pcall, type
local format           = string.format
local math_min         = math.min
local CreateFrame      = CreateFrame
local C_Timer          = C_Timer
local C_Container      = C_Container
local C_Item           = C_Item
local C_Map            = C_Map
local GetCoinTextureString = GetCoinTextureString
local C_Navigation  = C_Navigation
local C_SuperTrack  = C_SuperTrack
-- Midnight moved IsAddOnLoaded under C_AddOns; shim to the modern path with a
-- legacy-global fallback (mirrors VeritasUI_AuctionHouse/UI/SellStrip.lua). Used
-- by the /way TomTom-conflict check at PLAYER_LOGIN. Without the shim, a future
-- build that drops the global would make the check silently conclude "TomTom
-- absent" and re-register /way, re-creating the slash-command clash the v1.6.28
-- TomTom detection exists to prevent.
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

----------------------------------------------------------------
--  Chat money output
----------------------------------------------------------------
-- Coins() is the single funnel for every money string this file prints (Auto Sell Junk
-- and Auto Repair), so the coin-rendering decision lives in exactly one place.
--
-- Renders through Blizzard's own GetMoneyString. It emits each denomination as
-- GOLD/SILVER/COPPER_AMOUNT_TEXTURE:format(n, 0, 0) -> "|T...:0:0|t" (sourced:
-- Blizzard_SharedXML/FormattingUtil.lua), and in a texture escape sequence height 0
-- AND width 0 means "size = the font's text height" (sourced: warcraft.wiki.gg, UI
-- escape sequences). So the coin is sized by the same mechanism Blizzard's own
-- "You gained:" money line uses -- we are not imitating it, we call it.
--
-- ⚠ WHY THIS AND NOT A HARDCODED SIZE -- both work TODAY; this one keeps working.
--   The alternative is GetCoinTextureString(copper, 12), whose second argument is an
--   absolute icon height in pixels (default 14, sourced: CurrencyInfoDocumentation.lua,
--   fontHeight Default = 14). At the default 14 our coins render one notch LARGER than
--   Blizzard's; an explicit 12 matches. And a fixed 12 does NOT break when the chat
--   font changes, because WoW's chat font-size setting scales the whole chat frame as
--   a unit rather than just the glyphs (owner-measured at chat font 14/16/18).
--
--   So the fixed size is not broken -- it is just OURS. It re-derives a number that
--   Blizzard already computes, which means any future change Blizzard makes to coin
--   sizing or coin art silently desyncs us until someone notices and re-tunes 12 by
--   eye. Calling GetMoneyString inherits that change for free. That is the whole
--   argument, and it is the project's "use Blizzard's own mechanism" rule applied
--   literally. Secondary benefit, sourced: GetMoneyString handles colorblind mode
--   explicitly (swaps coins for GOLD/SILVER/COPPER_AMOUNT_SYMBOL when colorblindMode
--   is set); GetCoinTextureString's behaviour in that mode is unmeasured.
--
-- Owner-confirmed in game, all three separately:
--   * GetMoneyString(n) printed beside GetCoinTextureString(n, 12) was pixel-identical
--     in BOTH coin art and size, and both matched Blizzard's "You gained:" line.
--   * That identity held across chat font 14, 16 and 18.
--   * This GetMoneyString build was run in game and renders correctly.
--
-- Keeps the OLD/legacy coin art either way, which is the correct match for CHAT --
-- Blizzard still uses it there. The modern |A:coin-*|a atlas art belongs to UI panels
-- only; see the AuctionHouse CraftingOrder note and the AutoSell landmine.
local COIN_SIZE_FALLBACK = 12

local function Coins(copper)
    -- Resolved per call rather than localized at file top: load order is not guaranteed
    -- to have Blizzard_SharedXML's globals in place when this file runs, and a nil
    -- captured at load time would silently pin us to the fallback for the whole session.
    -- This fires a handful of times per session, so the lookup costs nothing.
    local MoneyString = _G.GetMoneyString
    if MoneyString then return MoneyString(copper) end
    -- Fallback only. 12 (not the API default 14) is the owner-confirmed match.
    return GetCoinTextureString(copper, COIN_SIZE_FALLBACK)
end

local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Defaults & state
----------------------------------------------------------------
-- Saved settings, split by SCOPE. Authority: references/setting-scope-map.md in the skill
-- directory; enforced by scope_map_test and module_scope_test.
--
-- ⚠ ALL of these are shared across characters. That is the point of the refactor: the
-- Delve count's placement in particular was per-character purely as a side effect of the whole
-- module being per-character, so a value tuned and confirmed on one character never reached any
-- other -- and a later change to the shipped default could never reach a character that already
-- held the key. Making them universal removes that class of defect instead of patching it.
local UNIVERSAL = {
    autoSellJunk   = true,
    autoRepair     = true,
    showItemLevels = true,
    showMinimapCoords = true,
    afkScreen      = true,
    -- Paints the Nemesis groups-remaining count on the Delve plaque icon that
    -- otherwise only reveals it on hover, and a checkmark once all groups are down.
    delveNemesisCount = true,
    -- Where the Delve count sits, as insets from the icon's BOTTOM-RIGHT CORNER: pixels
    -- IN from the right edge and UP from the bottom edge. Persisted and live-nudgeable via
    -- /qol delvenudge, because dialling a cosmetic pixel offset through screenshot
    -- round-trips is slow and imprecise -- the captures arrive at different crops and
    -- scales, so they cannot be measured against each other.
    --
    -- ⚠ THIRD ORIGIN THIS SETTING HAS USED. Replaces delveCountCenterY/X (from the icon's
    -- CENTRE), which replaced delveCountOffsetY (from its BOTTOM EDGE). All superseded keys
    -- are dropped at login rather than reinterpreted -- see DELVE_COUNT_INSET_X.
    -- 0/0 is owner-settled in game (2026-08-15, see DELVE_COUNT_INSET_X); NEGATIVE values
    -- push the digit outside the icon's corner.
    delveCountInsetX = 0,
    delveCountInsetY = 0,
    -- Horizontal inset used ONLY when the count reads 1, overriding delveCountInsetX. Live
    -- via /qol delveone. See DELVE_COUNT_INSET_X_BY_COUNT for why one glyph needs its own
    -- value even though the count is corner-anchored.
    delveCountInsetX1 = 0,
    -- Pixels the completion checkmark extends past the icon's bounds on each side.
    -- Negative insets it. Live via /qol delvecheck. 0 is owner-confirmed in game.
    delveCheckOutset = 0,
    -- Points added to Blizzard's number font for the count. Live via /qol delvesize.
    delveFontDelta = -3,
    -- TYPEFACE for the count. Live via /qol delveface. Two values, both SOURCED:
    --   "plaque"   — the widget's own Text face (Friz Quadrata). Formerly the default, chosen
    --                when the owner reported ARIALN looked "weird" next to the plaque
    --                (2026-08-05); the shipped default is now "blizzard".
    --   "blizzard" — StackCount's own face, i.e. what Blizzard draws its count in:
    --                NumberFontNormal -> NumberFont_Outline_Med -> Fonts\ARIALN.TTF.
    -- This key exists so the two can be compared in game without a release round trip.
    delveCountFace = "blizzard",
    -- OUTLINE weight for the count. Live via /qol delveoutline. WoW has no bold flag, so the
    -- outline IS the weight knob. "OUTLINE" is the shipped default and
    -- is what Blizzard's NumberFont_Outline_Med declares (outline="NORMAL"); "THICKOUTLINE" is
    -- the heavier option.
    -- Stored as the literal SetFont flag string so nothing has to map it.
    delveCountOutline = "OUTLINE",
}
-- RETIRED keys (audit Q1, v1.17.9): the world-map coordinate readout was removed in favour of
-- Blizzard's own. They are no longer defaults -- nothing seeds them -- but they stay in the
-- MIGRATION list so a value still sitting in a pre-scope per-character slot is promoted to the
-- account root first, where RetireWorldMapCoords reads it and hands the player Blizzard's
-- option. Remove them from here only together with RetireWorldMapCoords.
local RETIRED_UNIVERSAL = { showMapCoords = true, mapCoordsPos = true }

-- The migration list is UNIVERSAL plus the retired keys, BUILT from them rather than restated, so
-- it cannot drift from either. VUI.MigrateScopedDB only reads the KEYS of this table.
local MIGRATE_UNIVERSAL = {}
for k, v in pairs(UNIVERSAL)         do MIGRATE_UNIVERSAL[k] = v    end
for k    in pairs(RETIRED_UNIVERSAL) do MIGRATE_UNIVERSAL[k] = true end

-- ⚠ PER-CHARACTER -- exactly two keys, for two different reasons.
local PERCHAR = {
    -- A genuine per-character CHOICE: guild membership differs, and whether guild funds should be
    -- spent on repairs is a decision you may want to make differently on an alt.
    repairFunding  = "guild",   -- "guild" = Guild + Personal; "personal" = Personal Only

    -- A technical CONSTRAINT, not a preference. Never offer this as a user-facing choice.
    -- Set while the AFK overlay has the UI hidden, cleared when it restores it.
    -- Persisted so a crash or disconnect during AFK can be recovered at the next
    -- PLAYER_LOGIN without force-restoring the UI on every ordinary login.
    afkUIDirty     = false,
}


local db   -- ACCOUNT-wide table
-- ⚠ Declared here, above every reader. `cdb` is the PER-CHARACTER table (repairFunding and
-- afkUIDirty only) and is nil until PLAYER_LOGIN: VUI.BindScopedDB deliberately does not fall
-- back to the account root.
local cdb  -- PER-CHARACTER table; nil before PLAYER_LOGIN
local settingsCategoryID
local frame = CreateFrame("Frame")

local itemLevelsSetup   = false  -- guards SetupItemLevels() re-entry
local miniCoordsSetup   = false  -- guards SetupMinimapCoordinates() re-entry
local miniCoordsFrame   = nil    -- reference for mid-session show/hide

-- ── /way — proximity auto-clear state ───────────────────────
local wayTicker        = nil
local WAY_ARRIVAL_YARDS = 10
local WayCommand                       -- forward declaration; defined below frame:SetScript

local function StopWaypointTracking()
    if wayTicker then wayTicker:Cancel(); wayTicker = nil end
end

local function StartWaypointTracking()
    StopWaypointTracking()
    wayTicker = C_Timer.NewTicker(1, function()
        if not C_Map.HasUserWaypoint() then
            StopWaypointTracking(); return
        end
        local dist = C_Navigation.GetDistance()
        if dist and dist <= WAY_ARRIVAL_YARDS then
            C_Map.ClearUserWaypoint()
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
            StopWaypointTracking()
            VUI.Print("Quality of Life", "Waypoint reached — cleared.")
        end
    end)
end

-- ── Feature: Auto Sell Junk ─────────────────────────────────
-- Event-driven selling: each SellNextBatch call sells up to
-- SELL_BATCH grey items, then waits for BAG_UPDATE_DELAYED (or
-- the SELL_RETRY_SEC fallback) to re-enter and continue.
--
-- Gold accounting uses summed item sell prices (the same pattern
-- as Scrap, jaliborc/Scrap addons/merchant/button.lua).  At sell
-- start we snapshot saleTotal = sum of every grey item's
-- sellPrice * stackCount.  On each call we recompute the remaining
-- junk value (excluding locked items mid-sale); the delta
-- saleTotal - remaining is the amount actually sold.  GetMoney()
-- is never used for the sell amount, so there is no race with a
-- concurrent repair deduction.
--
-- AutoRepair is independent — it is NOT chained off this code path.
-- That decoupling is intentional: at Delver's Supplies crates in
-- Delves, Blizzard disables item sales entirely while still
-- allowing repair.  If AutoRepair were chained off AutoSellJunk,
-- the inability to sell would also kill repair.
local SELL_BATCH         = 11    -- items per cycle. Verified working in-game on
                                 -- 12.0.7 (junk sells reliably, nothing stranded).
                                 -- Supersedes the conservative 9 from changelog
                                 -- v1.3.14 (12→9 era); the BAG_UPDATE_DELAYED +
                                 -- SELL_RETRY_SEC loop below paces successive batches,
                                 -- so the exact per-cycle count is not a hard ceiling.
local SELL_RETRY_SEC     = 0.5
local MAX_NO_PROGRESS    = 5     -- bail if no item is removed for this many seconds
local saleTotal              -- nil when idle; total value of junk at sell start
local saleCount              -- count of grey stacks at sell start (for print)
local lastRemainingValue     -- previous cycle's remaining value (progress detection)
local noProgressSince        -- GetTime() of last cycle that made progress (or sell start)
local sellRetryTimer         -- safety timer; fires if BAG_UPDATE_DELAYED is lost
local sellPending  = {}      -- [itemID] = true: grey whose GetItemInfo was a clean
                             -- cache miss during ScanJunk (all-cold first visit);
                             -- GET_ITEM_INFO_RECEIVED re-runs the scan when one lands
local coldSellTimer          -- debounce for GET_ITEM_INFO_RECEIVED bursts
local ScheduleColdSellRetry  -- forward declaration; defined after AutoSellJunk

local function CancelSellRetry()
    if sellRetryTimer then sellRetryTimer:Cancel(); sellRetryTimer = nil end
end

local function CancelColdSellRetry()
    if coldSellTimer then coldSellTimer:Cancel(); coldSellTimer = nil end
end

-- Walk bags once, return (totalValue, count) for every grey item that has
-- a cached sell price.  Locked items ARE counted — when UseContainerItem
-- runs, the client locks the item immediately while the server processes
-- the sale.  If we excluded locked items here, ScanJunk would report
-- "0 remaining" the instant the sell loop finishes, before the server
-- has actually removed (or rejected) anything.  Counting locked items
-- means we only declare the sale complete when items are physically gone
-- from the bag, which is the only signal that proves the server accepted
-- the request.  Scrap's GetReport excludes locked items and would have
-- the same premature-print risk at any merchant that rejects a sell.
local function ScanJunk()
    local total, count = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                -- info.quality / info.hasNoValue may be secret values in
                -- raid encounters; guard the comparison.  Items that fail
                -- the check are skipped (treated as not-junk).  Mirrors the
                -- defensive pattern in IsEquippableGear, below.
                local okJ, isJunk = pcall(function()
                    return info.quality == 0 and not info.hasNoValue
                end)
                if okJ and isJunk then
                    local okP, _, _, _, _, _, _, _, _, _, _, price =
                        pcall(C_Item.GetItemInfo, info.itemID)
                    if okP then
                        if price == nil then
                            -- Clean cache miss (distinct from a secret value,
                            -- which is non-nil and caught by the pcall below).
                            -- Request the record and flag the itemID so
                            -- GET_ITEM_INFO_RECEIVED can re-run the junk scan
                            -- once it lands — otherwise a fully cold cache
                            -- (fresh client start straight to a vendor) sells
                            -- nothing for the visit. Mirrors the proven
                            -- SellStrip pending/RequestLoadItemDataByID pattern.
                            sellPending[info.itemID] = true
                            if C_Item.RequestLoadItemDataByID then
                                pcall(C_Item.RequestLoadItemDataByID, info.itemID)
                            end
                        end
                        -- price may be a secret value; guard arithmetic.
                        local okC, contrib = pcall(function()
                            if price and price > 0 then
                                return price * (info.stackCount or 1)
                            end
                        end)
                        if okC and contrib then
                            total = total + contrib
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return total, count
end

local function ResetSellState()
    saleTotal          = nil
    saleCount          = nil
    lastRemainingValue = nil
    noProgressSince    = nil
    CancelSellRetry()
    frame:UnregisterEvent("BAG_UPDATE_DELAYED")
end

-- Emit a "sold N for X" print using the currently-observed remaining
-- value/count vs the captured saleTotal/saleCount.  Only prints when
-- the delta is positive (something actually sold).  Used by both the
-- normal-completion path and the hard-timeout bailout.
local function PrintSold(remainingValue, remainingCount)
    local soldCount = (saleCount or 0) - (remainingCount or 0)
    local soldValue = (saleTotal or 0) - (remainingValue or 0)
    if soldCount > 0 and soldValue > 0 then
        VUI.Print("Quality of Life", format(
            "Sold |cFFFFFF00%d|r junk item%s for %s",
            soldCount, soldCount > 1 and "s" or "",
            Coins(soldValue)))
    end
end

local function SellNextBatch()
    if not saleTotal then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then
        ResetSellState()
        return
    end

    -- Try to sell up to SELL_BATCH items.  Skip locked items (we can't
    -- sell them while they're mid-something) but include them in the
    -- remaining-value check below — they still occupy bag space and
    -- haven't been confirmed sold yet.
    local sold = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                -- info.quality / info.hasNoValue / info.isLocked may be
                -- secret values in raid encounters; guard the comparison.
                -- Items that fail the check are skipped (treated as not-
                -- sellable).  Mirrors IsEquippableGear, below.
                local okJ, isSellable = pcall(function()
                    return info.quality == 0
                        and not info.hasNoValue
                        and not info.isLocked
                end)
                if okJ and isSellable then
                    local okP, _, _, _, _, _, _, _, _, _, _, price =
                        pcall(C_Item.GetItemInfo, info.itemID)
                    if okP then
                        -- price may be a secret value; guard the comparison.
                        local okC, hasPrice = pcall(function()
                            return price and price > 0
                        end)
                        if okC and hasPrice then
                            C_Container.UseContainerItem(bag, slot)
                            sold = sold + 1
                            if sold >= SELL_BATCH then break end
                        end
                    end
                end
            end
        end
        if sold >= SELL_BATCH then break end
    end

    -- Full ScanJunk (locked items included) — we only declare completion
    -- when the server has actually removed items from the bag, not when
    -- they're transiently locked while the request is in flight.
    local remainingValue, remainingCount = ScanJunk()

    if remainingValue == 0 then
        PrintSold(0, 0)
        ResetSellState()
        return
    end

    -- Progress detection.  If remaining value dropped since the previous
    -- cycle, items are being removed from the bag — sales are working,
    -- reset the no-progress timer.  If it hasn't dropped for
    -- MAX_NO_PROGRESS seconds, the vendor is rejecting our requests
    -- (or some other persistent failure); bail out and report whatever
    -- partial value did sell.  This is correct for both small and very
    -- large junk piles — a 200-item drain that takes 8 seconds will
    -- keep resetting the timer with every confirmed batch, while a
    -- stuck vendor will time out cleanly after 5 idle seconds.
    if lastRemainingValue == nil or remainingValue < lastRemainingValue then
        lastRemainingValue = remainingValue
        noProgressSince    = GetTime()
    elseif noProgressSince and (GetTime() - noProgressSince) > MAX_NO_PROGRESS then
        PrintSold(remainingValue, remainingCount)
        ResetSellState()
    end
end

-- Safety retry: BAG_UPDATE_DELAYED can be coalesced or dropped under
-- server throttling; a 0.5s fallback re-drives the loop until selling
-- finishes.  Cancelled whenever BAG_UPDATE_DELAYED fires normally or
-- ResetSellState runs.
local function ScheduleSellRetry()
    CancelSellRetry()
    if saleTotal then
        sellRetryTimer = C_Timer.NewTimer(SELL_RETRY_SEC, function()
            sellRetryTimer = nil
            SellNextBatch()
            ScheduleSellRetry()
        end)
    end
end

local function AutoSellJunk()
    local total, count = ScanJunk()
    if total == 0 then return end   -- nothing to sell; print nothing
    saleTotal          = total
    saleCount          = count
    lastRemainingValue = nil
    noProgressSince    = GetTime()
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    SellNextBatch()
    ScheduleSellRetry()
end

-- Cold-cache retry: re-run AutoSellJunk once a pending grey's item record
-- streams in. Fires ONLY while idle (saleTotal nil) — AutoSellJunk resets the
-- sale accounting, so re-entering mid-sale would corrupt the report; a sale
-- already in progress re-scans the bags every cycle and needs no retry.
-- Debounced 0.1s: GET_ITEM_INFO_RECEIVED cache fills arrive in bursts.
ScheduleColdSellRetry = function()
    CancelColdSellRetry()
    coldSellTimer = C_Timer.NewTimer(0.1, function()
        coldSellTimer = nil
        if saleTotal then return end
        if not (MerchantFrame and MerchantFrame:IsShown()) then return end
        if db and db.autoSellJunk then AutoSellJunk() end
    end)
end

-- ── Feature: Auto Repair ────────────────────────────────────
-- Fires independently from MERCHANT_SHOW; never chained off
-- AutoSellJunk.  Print uses GetRepairAllCost() directly — no
-- GetMoney() delta, no race condition, no PLAYER_MONEY listener.
--
-- Funding source is controlled by db.repairFunding:
--   "guild"    — try guild bank first, then personal covers any remainder.
--                Skipped if the guild's info text contains [noautorepair]
--                (a convention used by GMs to block auto-repairs against
--                the guild bank). The remainder left by the daily withdrawal
--                limit is checked against personal gold BEFORE repairing, so
--                we never claim a repair we couldn't pay for. The residual
--                case we deliberately do NOT predict is a guild bank whose
--                balance is below the withdrawal limit: GetGuildBankMoney()
--                is unreliable until the bank frame has been opened, and
--                trusting a stale zero there would refuse repairs that would
--                actually succeed.
--   "personal" — always use personal gold, skip guild entirely.
local function AutoRepair()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost == 0 then return end

    -- ⚠ DO NOT append `or false` to make this a strict boolean. `and` binds tighter than `or`, so
    -- `cdb and X or false and IsInGuild() and ...` parses as `(cdb and X) or (false and ...)` --
    -- the entire guild-membership chain is short-circuited away and guild repair fires with no
    -- guild at all. That is exactly what happened during the v1.14.5 scope conversion, caught by
    -- qol_vendor_test case 7. `cdb ~= nil` keeps this one flat and-chain intact.
    local useGuild = cdb ~= nil
        and cdb.repairFunding ~= "personal"
        and IsInGuild()
        and CanGuildBankRepair()
        -- Case-insensitive, whitespace-tolerant `[noautorepair]` match.
        -- The user is at the mercy of whatever the GM typed in guild
        -- info — `[NoAutoRepair]`, `[ noautorepair ]`, `[NOAUTOREPAIR]`
        -- all mean the same thing and all suppress the guild-bank repair.
        -- Internal whitespace (`[no auto repair]`) is intentionally NOT
        -- matched so a GM who really did mean a different bracketed tag
        -- isn't accidentally interpreted as the suppression convention.
        and not (GetGuildInfoText() or ""):lower():find("%[%s*noautorepair%s*%]")

    if useGuild then
        -- Work out the split BEFORE repairing anything. GetRepairAllCost() must
        -- NOT be re-read after RepairAllItems(true) — that stale-cache race was
        -- removed in v1.3.21 — so the guild's share is derived from the daily
        -- withdrawal limit instead. A limit of -1 means unlimited.
        local limit     = GetGuildBankWithdrawMoney() or 0
        local guildPays = (limit < 0) and cost or math_min(limit, cost)
        local remainder = cost - guildPays

        if remainder > 0 and GetMoney() < remainder then
            VUI.Print("Quality of Life", format(
                "Can't repair — costs %s, the guild bank can cover %s and you "
                .. "don't have enough gold for the rest.",
                Coins(cost), Coins(guildPays)))
            return
        end

        RepairAllItems(true)              -- guild funds first
        if remainder > 0 then
            RepairAllItems(false)         -- personal gold covers the remainder
        end
        VUI.Print("Quality of Life", format(
            "Repaired for %s (guild bank)", Coins(cost)))
    else
        -- RepairAllItems silently no-ops when personal gold can't cover the
        -- bill, so an unconditional print would claim a repair that never
        -- happened. Synchronous read-once pre-check — no delta math, no
        -- PLAYER_MONEY listener (the v1.6.36 constraints are preserved).
        if GetMoney() < cost then
            VUI.Print("Quality of Life", format(
                "Can't repair — costs %s and you don't have enough gold.",
                Coins(cost)))
            return
        end
        RepairAllItems(false)
        VUI.Print("Quality of Life", format(
            "Repaired for %s", Coins(cost)))
    end
end

-- ── Feature: Show Item Levels ───────────────────────────────
-- Displays item level overlays on equippable gear in:
--   • Bags, bank, warband bank  (SetItemButtonQuality hook)
--   • Character panel           (SetItemButtonQuality hook)
--   • Merchant windows          (dedicated merchant scanner)
-- Quest reward buttons are explicitly excluded.
-- ─────────────────────────────────────────────────────────────
-- Sweeps every overlay we have painted, so "Show Item Levels" can be switched OFF without a
-- reload. Forward-declared here on purpose: it is ASSIGNED inside SetupItemLevels (which owns
-- the registry) but CALLED from InitializeOptions, and InitializeOptions runs FIRST at login.
-- ⚠ A local declared below the referencing closure would bind as a nil global -- the /way
-- v1.6.33 trap. Declare above both; assign later.
local HideAllItemLevelOverlays

local function SetupItemLevels()
    if itemLevelsSetup then return end
    itemLevelsSetup = true
    local QUALITY_COLORS = ITEM_QUALITY_COLORS
    local GEAR_CLASSES   = { [2] = true, [4] = true }  -- Weapon, Armor
    -- Items whose GetDetailedItemLevelInfo returns a stale/wrong ilvl.
    -- Heart of Azeroth: BfA Azerite scaling is defunct; API returns old ilvl.
    local SKIP_ITEMS     = { [158075] = true }

    local function FindIcon(btn)
        return btn.icon or btn.Icon or btn.IconTexture
    end

    -- Every button we have ever painted. Weak-keyed so it never keeps a button alive on our
    -- account; WoW frames outlive the session anyway, but the registry has no business being
    -- the thing that holds them.
    local overlaid = setmetatable({}, { __mode = "k" })

    local function ApplyOverlay(btn, ilvl, quality)
        local anchor = FindIcon(btn) or btn
        local fs = btn._vui_ilvl
        if not fs then
            fs = btn:CreateFontString(nil, "OVERLAY")
            fs:SetFontObject(NumberFontNormal)
            fs:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 2)
            fs:SetJustifyH("CENTER")
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
            btn._vui_ilvl = fs

            -- Bottom-vignette gradient for readability on busy/bright
            -- item art.  Uses the Warcraft Wiki-documented pattern:
            -- WHITE8x8 base texture + SetGradient with colorRGBA.
            -- SetGradient acts as a vertex-color filter (multiplied
            -- with the texture), so WHITE8x8 × gradient = the gradient
            -- itself.  ARTWORK sublevel 7 sits behind the OVERLAY
            -- fontstring but above the icon texture.
            local bg = btn:CreateTexture(nil, "ARTWORK", nil, 7)
            bg:SetTexture("Interface/Buttons/WHITE8x8")
            bg:SetGradient("VERTICAL",
                CreateColor(0, 0, 0, 0.7),    -- bottom: opaque (behind text)
                CreateColor(0, 0, 0, 0))       -- top: transparent (fades out)
            bg:SetPoint("BOTTOMLEFT",  anchor, "BOTTOMLEFT",  0, 0)
            bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
            bg:SetHeight(24)
            btn._vui_ilvlBG = bg
        end
        local c = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
        fs:SetText(ilvl)
        fs:SetTextColor(c.r, c.g, c.b)
        fs:Show()
        if btn._vui_ilvlBG then btn._vui_ilvlBG:Show() end
        overlaid[btn] = true
    end

    local function HideOverlay(btn)
        -- Also CANCEL any pending cold-cache retry for this button.
        --
        -- This is the single choke point that every early return and every
        -- ProcessItem bail already calls, which is why the cancel lives here
        -- rather than at each caller. The v1.8.0 retry guarded button reuse with
        -- the _vui_pendingIlvl token, but the token was only ever cleared inside
        -- ProcessItem — and the hook's three early returns (nil item, Poor
        -- quality, quest-reward button) all return BEFORE reaching it. So a bank
        -- button that was emptied or reassigned kept its token armed, the pending
        -- ContinueOnItemLoad callback's guard still matched, and it stamped an
        -- item level onto a now-empty slot once the record streamed in. Clearing
        -- here makes that stale callback unreachable from every path at once
        -- instead of patching three of them.
        --
        -- Ordering note: ProcessItem calls HideOverlay and THEN QueueRetry, so a
        -- deliberate arm still lands. Do not reorder those two.
        btn._vui_pendingIlvl = nil
        if btn._vui_ilvl   then btn._vui_ilvl:Hide()   end
        if btn._vui_ilvlBG then btn._vui_ilvlBG:Hide() end
    end

    -- Registry entries are deliberately NOT cleared after a sweep: the same button must still
    -- be swept if the feature is toggled off a second time without being repainted in between.
    HideAllItemLevelOverlays = function()
        for btn in pairs(overlaid) do HideOverlay(btn) end
    end

    local function IsEquippableGear(itemIDOrLink)
        if not itemIDOrLink then return false end
        local ok, itemID, _, _, equipLoc, _, classID =
            pcall(C_Item.GetItemInfoInstant, itemIDOrLink)
        if not ok then return false end
        -- equipLoc/classID may be secret values in raid encounters; guard the comparison.
        local ok2, gear = pcall(function()
            return GEAR_CLASSES[classID] and equipLoc and equipLoc ~= ""
        end)
        if not ok2 or not gear then return false end
        return true, itemID
    end

    -- Resolve an item's quality from the item itself. Returns 0 for Poor, which
    -- matters: `(ok and q) or 1` looks like it would turn 0 into 1, but 0 is
    -- TRUTHY in Lua, so `0 or 1` is 0 and junk is reported correctly.
    --
    -- MUST be defined above ProcessItem. ProcessItem is a forward-assigned
    -- closure, so a local declared BELOW it would be captured as a global
    -- lookup and be nil at call time — the documented forward-reference trap
    -- that silently broke /way (see the Lua-scoping landmine).
    local function GetItemQuality(link)
        if not link then return 1 end
        local ok, _, _, q = pcall(C_Item.GetItemInfo, link)
        return (ok and q) or 1
    end

    -- Cosmetic gear carries a real item level of 1, so the `ilvl <= 0` filter
    -- lets it through and renders a meaningless "1" (reported at vendors).
    -- Deliberately NOT fixed by raising that threshold: a genuine low-level
    -- alt's gear legitimately sits in single digits, so a cutoff would hide
    -- numbers that are real. Conservative, mirroring SellStrip's Warband
    -- predicate: reject only on a definitive true, so a missing API or a cold
    -- record shows the item rather than hiding a legitimate one.
    local function IsCosmetic(itemIDOrLink)
        if not (C_Item and C_Item.IsCosmeticItem) then return false end
        local ok, cosmetic = pcall(C_Item.IsCosmeticItem, itemIDOrLink)
        return (ok and cosmetic) and true or false
    end

    -- Resolve the link the button is CURRENTLY displaying, from the button's own
    -- accessors. Extracted from the SetItemButtonQuality hook so the cold-cache
    -- retry can re-check what a button holds before painting it; the branch order
    -- and semantics are unchanged from the inline version.
    --
    -- Returns: link (or nil), knowable
    --   knowable = we successfully queried this button's slot, so a nil link
    --   means the slot is EMPTY rather than merely unresolved. That distinction
    --   is what lets the retry tell "this button was emptied" (bail) apart from
    --   "this button has no accessor I understand" (proceed) — merchant buttons
    --   are the latter, since their link is passed in rather than derived.
    local function ResolveButtonLink(btn)
        local link, knowable = nil, false
        -- Fall-through order preserved EXACTLY from the inline version: each
        -- accessor is tried only while no link has been found, so a button whose
        -- GetItemLink returns nil still gets its container queried. Returning on
        -- the first merely-callable accessor would silently downgrade such
        -- buttons to the bare itemID, and with it the effective item level.
        if btn.GetItemLink then
            local ok, r = pcall(btn.GetItemLink, btn)
            if ok then knowable = true; if r then link = r end end
        end
        if not link and btn.GetBagID and btn.GetID then
            local ok, r = pcall(C_Container.GetContainerItemLink,
                btn:GetBagID(), btn:GetID())
            if ok then knowable = true; if r then link = r end end
        end
        if not link and btn.GetBankTabID and btn.GetContainerSlotID then
            local ok, r = pcall(C_Container.GetContainerItemLink,
                btn:GetBankTabID(), btn:GetContainerSlotID())
            if ok then knowable = true; if r then link = r end end
        end
        if not link and btn.GetID
            and not btn.GetBagID and not btn.GetBankTabID then
            local slotID = btn:GetID()
            local pName = btn:GetParent()
                and btn:GetParent().GetName
                and btn:GetParent():GetName() or ""
            -- Blizzard bank container (-1) has slots 1–28 in Midnight.
            if slotID >= 1 and slotID <= 28 and pName:find("Bank") then
                local ok, r = pcall(C_Container.GetContainerItemLink, -1, slotID)
                if ok then knowable = true; if r then link = r end end
            end
        end
        if not link and btn.GetID then
            local bName = btn.GetName and btn:GetName() or ""
            if bName:find("Character") then
                local ok, r = pcall(GetInventoryItemLink, "player", btn:GetID())
                if ok then knowable = true; if r then link = r end end
            end
        end
        return link, knowable
    end

    -- Compare two item references by itemID. Full links are not compared
    -- directly: two links for the same item can differ in bonus/context strings
    -- while still being the same item, and the retry only needs to know the
    -- button has not been handed a DIFFERENT item.
    local function SameItemID(a, b)
        if not (a and b) then return false end
        local okA, idA = pcall(C_Item.GetItemInfoInstant, a)
        local okB, idB = pcall(C_Item.GetItemInfoInstant, b)
        return okA and okB and idA ~= nil and idA == idB
    end

    -- Forward-declared: QueueRetry's callback re-enters ProcessItem after the
    -- item record loads (same closure-sees-later-assignment pattern as WayCommand).
    local ProcessItem

    -- Cold item-data-cache retry. On the FIRST bank/warband-bank open of a session
    -- most item records aren't client-cached yet, so GetDetailedItemLevelInfo()
    -- returns nil and the overlay silently never appeared (it "fixed itself" on a
    -- tab flip only because the flip re-fired SetItemButtonQuality after the server
    -- had streamed the records in). Instead of dropping the button, re-process it
    -- the moment ITS record arrives, via the Blizzard-provided ItemMixin:
    -- ContinueOnItemLoad (fires immediately if already loaded, else on data arrival).
    -- The _vui_pendingIlvl token guards button reuse: any fresh ProcessItem call for
    -- this button supersedes the pending retry, making the stale callback a no-op,
    -- and HideOverlay now cancels it too (see the comment there).
    --
    -- Quality is deliberately NOT captured. v1.8.0 captured the quality argument
    -- alongside the item and replayed it, but on a cold cache Blizzard passes
    -- quality = nil, and that nil then (a) skipped the Poor filter entirely, so
    -- junk got an overlay, and (b) fell through ApplyOverlay's `quality or 1`
    -- to Common = WHITE, which is why retried items rendered white instead of
    -- their rarity colour. By the time this callback runs the record is loaded by
    -- definition, so ProcessItem re-resolves quality from the item instead.
    local function QueueRetry(btn, itemIDOrLink)
        local ok, item = pcall(function()
            if type(itemIDOrLink) == "string" then
                return Item:CreateFromItemLink(itemIDOrLink)
            end
            return Item:CreateFromItemID(itemIDOrLink)
        end)
        if not ok or not item or item:IsItemEmpty() then return end
        btn._vui_pendingIlvl = itemIDOrLink
        item:ContinueOnItemLoad(function()
            if btn._vui_pendingIlvl ~= itemIDOrLink then return end
            btn._vui_pendingIlvl = nil
            -- Re-check what the button holds NOW. The token alone cannot cover a
            -- button that Blizzard empties without calling SetItemButtonQuality
            -- for it — whether it always does is unverified, and this makes the
            -- question moot rather than betting on it.
            local curLink, knowable = ResolveButtonLink(btn)
            if knowable then
                if not curLink then HideOverlay(btn); return end
                if not SameItemID(curLink, itemIDOrLink) then return end
            end
            -- Prefer the freshly resolved LINK over the captured reference: if
            -- the hook was handed a bare itemID, the link yields the effective
            -- (upgraded) item level where the ID yields only the base. This
            -- aligns the retry path with the hook path, which has always
            -- resolved a link first.
            ProcessItem(btn, curLink or itemIDOrLink, nil, true)   -- one shot only
        end)
    end

    ProcessItem = function(btn, itemIDOrLink, quality, noRetry)
        -- Any fresh call supersedes a pending cold-cache retry for this button.
        btn._vui_pendingIlvl = nil
        if not itemIDOrLink then HideOverlay(btn); return end
        -- Resolve a nil quality from the item rather than trusting the argument.
        -- Blizzard passes nil while the record is cold, and every consumer below
        -- treats nil as "not Poor, colour it white" — see QueueRetry's note.
        if quality == nil then quality = GetItemQuality(itemIDOrLink) end
        if quality == 0 then HideOverlay(btn); return end
        local equippable, rawID = IsEquippableGear(itemIDOrLink)
        if not equippable then HideOverlay(btn); return end
        if rawID and SKIP_ITEMS[rawID] then HideOverlay(btn); return end
        if IsCosmetic(itemIDOrLink) then HideOverlay(btn); return end
        -- ITEM LEVEL SOURCE — GetItemInfo's index 4, NOT
        -- C_Item.GetDetailedItemLevelInfo. Changed in v1.9.17 on measurement, not
        -- reasoning; the numbers are recorded in PROBE_LIBRARY_AND_REFERENCE.md §2
        -- under /qol ilvl, dated 2026-07-28.
        --
        -- GetDetailedItemLevelInfo is WRONG on LEVEL-SCALING items: it returns the
        -- scaling CEILING. A Timewalking crossbow (226167) whose tooltip read 78
        -- returned 522. That was the reported "icon disagrees with the tooltip"
        -- bug, and it also appears to be the same class of problem that got quest
        -- reward item levels removed in v1.1.0 ("base vs. effective ilvl
        -- mismatch", CHANGELOG entry for 1.1.0).
        --
        -- Index 4 matched the tooltip on BOTH measured cases, including the hard
        -- one: an upgrade-track epic (250032) with a base of 44 and an effective
        -- 276 read 276, so index 4 is upgrade-aware rather than a naive base read.
        -- That was the specific risk of this change and it is disproven —
        -- GetDetailedItemLevelInfo's whole purpose is reporting upgraded levels,
        -- so it agrees there too; it is only the scaling case that diverges.
        --
        -- ⚠ Do NOT "restore" GetDetailedItemLevelInfo here, and do NOT add it as a
        -- fallback when index 4 is nil: nil means the record is not cached, which
        -- the retry below already handles correctly, whereas a fallback would
        -- reintroduce the 522 on exactly the items this fixes.
        --
        -- The C_TooltipInfo route (reading the tooltip's own data) was measured and
        -- REJECTED: it returns the same answer but costs 0.055–0.110 ms/call,
        -- i.e. ~11–22 ms per 200 bank slots, over a full frame at 60 fps, and it
        -- would need localized string parsing. No reason to pay that for a value a
        -- plain numeric call already gets right.
        local ok, _, _, _, ilvl = pcall(C_Item.GetItemInfo, itemIDOrLink)
        if not ok or not ilvl then
            -- nil ilvl on equippable gear = cold item-data cache, not "no ilvl".
            -- Hide for now; re-run this button once when the record loads. noRetry
            -- stops a second queue if the loaded record STILL yields no ilvl
            -- (ContinueOnItemLoad on a loaded item fires synchronously — requeueing
            -- there would recurse).
            HideOverlay(btn)
            if not noRetry then QueueRetry(btn, itemIDOrLink) end
            return
        end
        -- ilvl may be a secret value in raid encounters; guard the comparison.
        local cmpOk, tooLow = pcall(function() return ilvl <= 0 end)
        if not cmpOk or tooLow then HideOverlay(btn); return end
        ApplyOverlay(btn, ilvl, quality)
    end

    ----------------------------------------------------------------
    --  SetItemButtonQuality hook
    ----------------------------------------------------------------
    -- Name-based quest-reward exclusion. As of 2026-07-29 this is BELT AND BRACES,
    -- not the real defence: the supported-button gate in the hook below excludes
    -- every non-container button structurally, which subsumes these two patterns.
    -- Kept because it is cached and nearly free, and because it documents the v1.1.0
    -- policy explicitly. ⚠ Do NOT treat it as the exclusion that matters, and do NOT
    -- extend it with more frame names when a new bad surface appears -- fix the gate.
    local questBtnCache = {}
    local function IsQuestRewardButton(btn)
        local name = btn.GetName and btn:GetName()
        if not name then return false end
        local cached = questBtnCache[name]
        if cached ~= nil then return cached end
        if name:find("QuestInfoItem") then
            questBtnCache[name] = true
            return true
        end
        local p = btn:GetParent()
        for _ = 1, 3 do
            if not p then break end
            local pn = p.GetName and p:GetName()
            if pn and pn:find("QuestInfoRewardsFrame") then
                questBtnCache[name] = true
                return true
            end
            p = p:GetParent()
        end
        questBtnCache[name] = false
        return false
    end

    hooksecurefunc("SetItemButtonQuality", function(btn, quality, itemIDOrLink)
        if not db or not db.showItemLevels then
            -- ⚠ Do NOT bare-return here. Bag and bank buttons are RECYCLED across items, so an
            -- overlay painted while the feature was on stayed visible over whatever item later
            -- occupied that slot -- a wrong item level against an unrelated item, indefinitely,
            -- until /reload. The options sweep clears what is on screen at the moment of
            -- switching off; this clears anything Blizzard repaints afterwards.
            -- Gated on _vui_ilvl so the common disabled case stays a single field read: this
            -- hook fires on every quality set, on every button, everywhere.
            if btn and btn._vui_ilvl then HideOverlay(btn) end
            return
        end
        if not btn or not btn.CreateFontString then return end
        if not itemIDOrLink then HideOverlay(btn); return end
        if quality ~= nil and quality == 0 then HideOverlay(btn); return end
        if IsQuestRewardButton(btn) then HideOverlay(btn); return end

        -- ⚠ SUPPORTED-BUTTON GATE. Resolve the button FIRST and bail if we cannot
        -- identify which container slot it represents.
        --
        -- This is now the PRIMARY exclusion, replacing name matching. `knowable` is
        -- true only when one of ResolveButtonLink's container accessors was actually
        -- callable -- bag, bank, warband bank or character slot. A button satisfying
        -- none of them is not an inventory button at all, and an item level on it is
        -- always wrong.
        --
        -- Motivating defect (2026-07-29, owner-confirmed by disabling all addons): a
        -- World Quest reward in a map tooltip showed 26 against a tooltip reading
        -- 151. World Quest rewards are scaled BY THE QUEST, so asking the item for
        -- its level yields a meaningless template value -- there is no better API to
        -- reach for, which is exactly why quest reward item levels were removed
        -- wholesale in v1.1.0 ("base vs. effective ilvl mismatch makes reliable
        -- display impractical"). That removal named two frame patterns
        -- (QuestInfoItem, QuestInfoRewardsFrame); the World Quest tooltip uses
        -- EmbeddedItemTooltip under GameTooltip and matched neither, and
        -- IsQuestRewardButton additionally returned false for any UNNAMED button.
        --
        -- ⚠ Do NOT replace this with another frame-name list. A name list is what
        -- rotted: it can only exclude surfaces someone already thought of, whereas
        -- this excludes everything that is not a container slot, including surfaces
        -- that do not exist yet.
        --
        -- Cost: up to five pcall'd accessor calls per fire, where a passed-in link
        -- previously short-circuited them -- roughly 2 ms across a ~200-slot bank
        -- open, once. Accepted deliberately over caching the answer on the button,
        -- which would be faster but adds state for a saving that does not matter.
        --
        -- Merchants are unaffected: that path calls ProcessItem directly from
        -- UpdateMerchantItems, because SetItemButtonQuality does not fire for
        -- merchant buttons at all.
        local resolved, knowable = ResolveButtonLink(btn)
        if not knowable then HideOverlay(btn); return end

        -- Prefer a passed-in full link over the resolved one: both give the effective
        -- item level, and the caller's is authoritative for this fire.
        local link = (type(itemIDOrLink) == "string" and itemIDOrLink) or resolved

        -- Delegate to ProcessItem for equippability, skip, ilvl, and overlay.
        ProcessItem(btn, link or itemIDOrLink, quality)
    end)

    ----------------------------------------------------------------
    --  Merchant scanner
    ----------------------------------------------------------------
    local function FindMerchantButton(slot)
        local btn = _G["MerchantItem" .. slot .. "ItemButton"]
        if btn then return btn end
        local parent = _G["MerchantItem" .. slot]
        if not parent then return nil end
        btn = parent.ItemButton or parent.itemButton
        if btn then return btn end
        for _, child in ipairs({ parent:GetChildren() }) do
            if child:IsObjectType("Button")
                and (child.icon or child.Icon or child.IconTexture) then
                return child
            end
        end
    end

    local function UpdateMerchantItems()
        -- Every other consumer of this feature gates on the setting; this scanner did not, so
        -- vendor overlays kept being repainted after the feature was switched off.
        if not db or not db.showItemLevels then return end
        if not MerchantFrame or not MerchantFrame:IsShown() then return end
        if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
            return
        end
        local numItems = GetMerchantNumItems and GetMerchantNumItems() or 0
        local perPage  = MERCHANT_ITEMS_PER_PAGE or 10
        local offset   = ((MerchantFrame.page or 1) - 1) * perPage

        for i = 1, perPage do
            local btn = FindMerchantButton(i)
            if not btn then break end
            local idx = offset + i
            if idx > numItems then
                HideOverlay(btn)
            else
                local ok, link = pcall(GetMerchantItemLink, idx)
                if ok and link then
                    ProcessItem(btn, link, GetItemQuality(link))
                else
                    HideOverlay(btn)
                end
            end
        end
    end

    for _, fn in ipairs({
        "MerchantFrame_Update",
        "MerchantFrame_UpdateMerchantInfo",
    }) do
        if _G[fn] then
            pcall(hooksecurefunc, fn, function()
                C_Timer.After(0.05, UpdateMerchantItems)
            end)
        end
    end

    if MerchantFrame then
        MerchantFrame:HookScript("OnShow", function()
            C_Timer.After(0.1, UpdateMerchantItems)
        end)
        for _, name in ipairs({
            "MerchantNextPageButton", "MerchantPrevPageButton",
            "MerchantFrameTab1", "MerchantFrameTab2",
        }) do
            local btn = _G[name]
            if btn then
                btn:HookScript("OnClick", function()
                    C_Timer.After(0.05, UpdateMerchantItems)
                end)
            end
        end
    end

    local mf = CreateFrame("Frame")
    mf:RegisterEvent("MERCHANT_UPDATE")
    mf:RegisterEvent("MERCHANT_FILTER_ITEM_UPDATE")
    mf:SetScript("OnEvent", function()
        C_Timer.After(0.1, UpdateMerchantItems)
    end)
end

-- ── Retired: World Map Coordinates (audit Q1, v1.17.9) ───────
-- WoW 12.1 ships its own readout (Options > Interface, map coordinates section; CVars
-- worldMapShowPlayerCoords / worldMapShowCursorCoords,
-- WorldMapCoordsPanelMixin in Blizzard_WorldMapTemplates.lua). Ours duplicated it and was
-- less correct: its player numbers came from the zone you stand in even while the map showed
-- another one, and it hid the map's quest-log toggle until /reload. So it is gone, and a
-- player who had ours on is handed Blizzard's, once.
--
-- ⚠ The keys are cleared only AFTER the CVars are written. At a /reload in combat the write
-- waits on the combat queue; clearing first would lose the intent if the player logged out
-- before combat ended. Running again is harmless: with the keys gone there is nothing to do.
local function RetireWorldMapCoords()
    if not db or db.showMapCoords == nil and db.mapCoordsPos == nil then return end
    if db.showMapCoords ~= true then
        db.showMapCoords, db.mapCoordsPos = nil, nil
        return
    end
    VUI.CombatQueue.Add(function()
        local cv  = _G.C_CVar
        local set = cv and cv.SetCVar
        if set then
            pcall(set, "worldMapShowPlayerCoords", "1")
            pcall(set, "worldMapShowCursorCoords", "1")
        end
        db.showMapCoords, db.mapCoordsPos = nil, nil
        VUI.Print("Quality of Life", "Map coordinates now use WoW's own option "
            .. "(Options > Interface) and have been turned on for you.")
    end)
end

-- ── Feature: Minimap Coordinates ────────────────────────────
-- Player coordinates shown directly under the minimap. Display-only:
-- a plain FontString on an insecure frame, no protected actions, so it
-- adds no taint surface. Parented to Minimap, so it inherits the map's
-- show/hide (e.g. it vanishes with the minimap during the AFK screen).
-- Hidden automatically wherever the API returns no position (dungeons,
-- raids, arenas), so it never displays a stale value.
--
-- Reads position through C_Map:
-- C_Map.GetBestMapForUnit -> GetPlayerMapPosition, x/y in 0-1 scaled to
-- 0-100, nil-guarded (pcall, x>0 or y>0).
local function SetupMinimapCoordinates()
    if miniCoordsSetup then return end
    if not Minimap then return end
    miniCoordsSetup = true

    local THROTTLE = 0.1   -- 10 Hz; coordinates change slowly, 30 fps is wasteful here

    local holder = CreateFrame("Frame", nil, Minimap)
    miniCoordsFrame = holder
    holder:SetSize(80, 12)
    holder:SetPoint("TOP", Minimap, "BOTTOM", 0, -6)
    holder:SetFrameStrata(Minimap:GetFrameStrata())
    holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    -- GameFontHighlightSmall (white): the font Blizzard's own World Map coordinates use
    -- (Blizzard_WorldMapTemplates.xml:206, 217), so the two readouts match. Was gold
    -- GameFontNormalSmall to match VeritasUI's retired map readout (owner request 2026-10-11).
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", holder, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    holder.text = text

    holder:SetScript("OnUpdate", function(self, elapsed)
        if not db or not db.showMinimapCoords then self:Hide(); return end
        self._t = (self._t or 0) + elapsed
        if self._t < THROTTLE then return end
        self._t = 0

        local str = ""
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
            if ok and pos then
                local x, y = pos:GetXY()
                if x and y and (x > 0 or y > 0) then
                    str = format("%.1f, %.1f", x * 100, y * 100)
                end
            end
        end
        if str ~= self._last then
            self.text:SetText(str)
            self._last = str
        end
    end)
end

-- ── Feature: AFK Screen ─────────────────────────────────────
-- Cinematic AFK overlay: hides all UI, shows character info
-- (name, level, item level, zone) with a slow camera orbit
-- to minimise OLED burn-in.
-- Triggered by PLAYER_FLAGS_CHANGED → UnitIsAFK("player").
-- Dismissed when AFK flag clears (any input), OR instantly on
-- PLAYER_STARTED_MOVING — see the fast-path note at that handler.
-- ─────────────────────────────────────────────────────────────
local afkOverlay          -- the fullscreen frame (created once, reused)
local afkClockTicker      -- 30s timer for real-world clock refresh
local afkActive = false   -- guard against re-entry

local AFK_REVEAL_POLL_RATE = 0.2   -- 5 Hz, AFK-only
-- Strata the overlay drops to while something is revealed. Panels are MEDIUM and
-- up, and the overlay sits at FULLSCREEN_DIALOG, so a revealed panel would render
-- BEHIND it. We lower the overlay rather than raise the panel: setting strata on a
-- UIPanel-managed frame fights the panel manager, which owns strata and produces
-- drift and flicker (documented landmine). BACKGROUND is chosen as the safest
-- floor — it is above WorldFrame (strata WORLD), so the overlay still covers the
-- 3D scene, and below every panel regardless of that panel's own strata. Nothing
-- is lost by being under the rest of the UI because the rest of the UI is at
-- alpha 0 and does not render at all.
local AFK_OVERLAY_STRATA     = "FULLSCREEN_DIALOG"
local AFK_OVERLAY_LOW_STRATA = "BACKGROUND"

-- Frames not registered in UIPanelWindows, so not covered by that enumeration.
local AFK_EXTRA_FRAMES = {
    "ContainerFrameCombinedBags",
    "GameMenuFrame",
    "ChatFrame1EditBox",
}
for i = 1, 13 do
    AFK_EXTRA_FRAMES[#AFK_EXTRA_FRAMES + 1] = "ContainerFrame" .. i
end

local function AFK_CreateOverlay()
    if afkOverlay then return afkOverlay end

    local f = CreateFrame("Frame", "VeritasUI_AFKScreen", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata(AFK_OVERLAY_STRATA)
    f:SetFrameLevel(500)
    f:SetIgnoreParentAlpha(true)
    -- Keyboard is deliberately NOT captured (no EnableKeyboard). Dismissal is
    -- driven by PLAYER_FLAGS_CHANGED + the fallback poll, never by keystrokes,
    -- so capturing input added nothing — and the old OnKeyDown handler's
    -- SetPropagateKeyboardInput(true) is combat-protected (10.1.5+): a mob
    -- attacking the AFK player put us in combat, and the wake-up keypress
    -- then triggered a blocked-action error — and, if it was the session's
    -- first overlay keypress, the key was swallowed (propagation still at its
    -- default false), so the player couldn't move to clear AFK. With no
    -- keyboard capture, every key reaches the game directly.
    f:Hide()

    -- ── Vignette overlay ──
    -- Four edge gradients converging inward for a soft cinematic frame.
    -- Each strip is a percentage of the screen dimension and fades from
    -- dark edge to transparent interior.
    local VIG_ALPHA = 0.85

    -- Bottom
    local vigB = f:CreateTexture(nil, "BACKGROUND")
    vigB:SetTexture("Interface/Buttons/WHITE8x8")
    vigB:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, VIG_ALPHA),
        CreateColor(0, 0, 0, 0))
    vigB:SetPoint("BOTTOMLEFT")
    vigB:SetPoint("BOTTOMRIGHT")

    -- Top
    local vigT = f:CreateTexture(nil, "BACKGROUND")
    vigT:SetTexture("Interface/Buttons/WHITE8x8")
    vigT:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, 0),
        CreateColor(0, 0, 0, VIG_ALPHA))
    vigT:SetPoint("TOPLEFT")
    vigT:SetPoint("TOPRIGHT")

    -- Left
    local vigL = f:CreateTexture(nil, "BACKGROUND")
    vigL:SetTexture("Interface/Buttons/WHITE8x8")
    vigL:SetGradient("HORIZONTAL",
        CreateColor(0, 0, 0, VIG_ALPHA * 0.6),
        CreateColor(0, 0, 0, 0))
    vigL:SetPoint("TOPLEFT")
    vigL:SetPoint("BOTTOMLEFT")

    -- Right
    local vigR = f:CreateTexture(nil, "BACKGROUND")
    vigR:SetTexture("Interface/Buttons/WHITE8x8")
    vigR:SetGradient("HORIZONTAL",
        CreateColor(0, 0, 0, 0),
        CreateColor(0, 0, 0, VIG_ALPHA * 0.6))
    vigR:SetPoint("TOPRIGHT")
    vigR:SetPoint("BOTTOMRIGHT")

    -- Single OnSizeChanged handler sizes all four vignette strips.
    -- Also called explicitly on Show to handle the case where the frame
    -- is already at its final size (SetAllPoints resolves immediately)
    -- and OnSizeChanged never fires.
    local function SizeVignettes(w, h)
        if not w or w == 0 then return end
        vigB:SetHeight(h * 0.25)
        vigT:SetHeight(h * 0.25)
        vigL:SetWidth(w * 0.20)
        vigR:SetWidth(w * 0.20)
    end
    f:HookScript("OnSizeChanged", function(_, w, h) SizeVignettes(w, h) end)
    f:HookScript("OnShow", function(self) SizeVignettes(self:GetSize()) end)

    -- ── Info cluster (bottom-center) ──
    local cluster = CreateFrame("Frame", nil, f)
    cluster:SetPoint("BOTTOM", f, "BOTTOM", 0, 60)
    cluster:SetSize(400, 80)

    -- Character name — class-coloured, large
    local nameText = cluster:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    nameText:SetPoint("BOTTOM", cluster, "BOTTOM", 0, 24)
    nameText:SetJustifyH("CENTER")
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(2, -2)
    f._nameText = nameText

    -- Level · Item Level · Zone — subdued white
    local infoText = cluster:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", nameText, "BOTTOM", 0, -4)
    infoText:SetJustifyH("CENTER")
    infoText:SetTextColor(0.78, 0.78, 0.78)
    infoText:SetShadowColor(0, 0, 0, 1)
    infoText:SetShadowOffset(1, -1)
    f._infoText = infoText

    -- Real-world clock — dim gray, below info line
    local clockText = cluster:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clockText:SetPoint("TOP", infoText, "BOTTOM", 0, -6)
    clockText:SetJustifyH("CENTER")
    clockText:SetTextColor(0.50, 0.50, 0.50)
    clockText:SetShadowColor(0, 0, 0, 1)
    clockText:SetShadowOffset(1, -1)
    f._clockText = clockText

    -- No input scripts: mouse is not captured (EnableMouse stays false) and
    -- keyboard is not captured (see the note at frame creation), so movement
    -- keys and clicks all fall through to the game untouched.

    afkOverlay = f
    return f
end

-- Blizzard's own clock text (GameTimeUtil.lua:77-80): follows the player's 24-hour setting and
-- writes "7:30 PM", not "07:30 PM". os.date was hard-wired to 12-hour with a leading zero (audit Q3).
local function AFK_ClockText()
    if GameTime_GetLocalTime then
        local ok, s = pcall(GameTime_GetLocalTime, true)
        if ok and type(s) == "string" then return s end
    end
    return date("%I:%M %p")
end

local function AFK_RefreshInfo()
    if not afkOverlay then return end

    -- Character name in class colour
    local name = UnitName("player") or "Unknown"
    local _, classFile = UnitClass("player")
    local cc = C_ClassColor and C_ClassColor.GetClassColor(classFile)
    if cc then
        afkOverlay._nameText:SetText(cc:WrapTextInColorCode(name))
    else
        afkOverlay._nameText:SetText(name)
    end

    -- Level · ilvl · zone
    local level = UnitLevel("player") or "?"
    local ilvlStr = "—"
    local ok, _, equipped = pcall(GetAverageItemLevel)
    if ok and equipped then
        -- equipped may be a secret value; guard the format call
        local fmtOk, s = pcall(format, "%.0f", equipped)
        if fmtOk then ilvlStr = s end
    end

    local zone = GetZoneText() or ""
    local subZone = GetSubZoneText() or ""
    local zoneDisplay = zone
    if subZone ~= "" and subZone ~= zone then
        zoneDisplay = subZone .. ", " .. zone
    end

    -- Build info line; omit zone segment if zone data is unavailable
    -- (loading screen, instance transition) to avoid a trailing separator.
    local parts = {}
    -- Blizzard's translated labels, so a non-English client does not get English here.
    parts[#parts + 1] = (LEVEL or "Level") .. " " .. tostring(level)
    parts[#parts + 1] = (STAT_AVERAGE_ITEM_LEVEL or "Item Level") .. " " .. ilvlStr
    if zoneDisplay ~= "" then
        parts[#parts + 1] = zoneDisplay
    end
    afkOverlay._infoText:SetText(table.concat(parts, "  ·  "))

    -- Clock
    afkOverlay._clockText:SetText(AFK_ClockText())
end

-- ── AFK panel reveal ─────────────────────────────────────────
-- Let the player actually USE the UI while the AFK screen is up, without
-- dropping the screen and without capturing a single keystroke.
--
-- The whole feature is a visibility problem, not an input problem. AFK_Enter
-- hides the UI with UIParent:SetAlpha(0), and alpha 0 leaves children fully
-- FUNCTIONAL — so pressing C already opens the character sheet, B already opens
-- the bags and Enter already focuses chat. They are simply transparent. Making
-- one visible is the same lever the overlay uses on itself: SetIgnoreParentAlpha.
--
-- ⚠ Deliberately NO keyboard capture. EnableKeyboard / SetPropagateKeyboardInput
-- on a fullscreen insecure overlay is combat-protected and was removed in v1.9.2
-- for breaking the player's ability to move (see the AFK_CreateOverlay comment
-- and the matching landmine). Nothing here reintroduces it: we only observe
-- frames, never input.
--
-- Detection is a poll rather than per-frame hooks. Hooks would need separate
-- coverage for UIPanel frames, the container frames, the chat edit box and the
-- Escape menu, and would still miss anything new; the poll needs no maintenance
-- and self-corrects. Same reasoning as VUI.HookHoverFade. It runs ONLY while the
-- AFK screen is up, and SetIgnoreParentAlpha is called only on a transition.
--
-- NOTE on interaction with CleanSolo: SetIgnoreParentAlpha bypasses the PARENT's
-- alpha, not the frame's own. A chat tab CleanSolo has faded to alpha 0 stays
-- invisible, which is correct — we are undoing our own UIParent blanket, not
-- overriding another feature's deliberate choice.
local afkRevealed = {}     -- [frame] = true while we are overriding its alpha
local afkRevealTicker

local function AFK_Reveal(f)
    if not (f and f.SetIgnoreParentAlpha) or afkRevealed[f] then return end
    afkRevealed[f] = true
    pcall(f.SetIgnoreParentAlpha, f, true)
end

local function AFK_Unreveal(f)
    if not (f and afkRevealed[f]) then return end
    afkRevealed[f] = nil
    pcall(f.SetIgnoreParentAlpha, f, false)
end

-- Revert every override. MUST run on AFK exit: leaving SetIgnoreParentAlpha(true)
-- on a Blizzard frame would make it ignore future alpha changes entirely, which
-- would silently break the next AFK session and CleanSolo's fades.
local function AFK_UnrevealAll()
    for f in pairs(afkRevealed) do
        pcall(f.SetIgnoreParentAlpha, f, false)
        afkRevealed[f] = nil   -- clearing an existing key mid-pairs is legal
    end
end

local function AFK_SyncOverlayStrata()
    if not afkOverlay then return end
    if next(afkRevealed) ~= nil then
        if afkOverlay._afkLowered then return end
        afkOverlay._afkLowered = true
        afkOverlay:SetFrameStrata(AFK_OVERLAY_LOW_STRATA)
    elseif afkOverlay._afkLowered then
        afkOverlay._afkLowered = nil
        afkOverlay:SetFrameStrata(AFK_OVERLAY_STRATA)
    end
end

local function AFK_ScanPanels()
    if not afkActive then return end

    -- Every UIPanel-managed frame. Enumerated from Blizzard's own registry so
    -- Character, Spellbook, Collections, Map, Bank, Merchant — and VeritasUI's own
    -- Priority Rotation / Advanced Options windows — are all covered with no list
    -- to maintain here.
    if UIPanelWindows then
        for name in pairs(UIPanelWindows) do
            local f = _G[name]
            if f and f.IsShown then
                if f:IsShown() then AFK_Reveal(f) else AFK_Unreveal(f) end
            end
        end
    end

    for _, name in ipairs(AFK_EXTRA_FRAMES) do
        local f = _G[name]
        if f and f.IsShown then
            if f:IsShown() then AFK_Reveal(f) else AFK_Unreveal(f) end
        end
    end

    -- Chat is driven by the EDIT BOX, not by the chat windows' own state: the
    -- windows are always shown, so keying off IsShown would reveal them for the
    -- entire AFK session. Pressing Enter opens the edit box and brings the
    -- conversation with it; sending (or Escape) closes the edit box and both go
    -- away again on the next tick.
    local eb = _G.ChatFrame1EditBox
    local typing = eb and eb.IsShown and eb:IsShown() and true or false
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.IsShown then
            if typing and cf:IsShown() then AFK_Reveal(cf) else AFK_Unreveal(cf) end
        end
    end

    AFK_SyncOverlayStrata()
end

local function AFK_StartReveal()
    if afkRevealTicker then return end
    AFK_ScanPanels()   -- immediate first pass, so an already-open panel appears at once
    afkRevealTicker = C_Timer.NewTicker(AFK_REVEAL_POLL_RATE, AFK_ScanPanels)
end

local function AFK_StopReveal()
    if afkRevealTicker then afkRevealTicker:Cancel(); afkRevealTicker = nil end
    AFK_UnrevealAll()
    if afkOverlay and afkOverlay._afkLowered then
        afkOverlay._afkLowered = nil
        afkOverlay:SetFrameStrata(AFK_OVERLAY_STRATA)
    end
end

local function AFK_Enter()
    if afkActive then return end
    if not db or not db.afkScreen then return end
    afkActive = true

    local overlay = AFK_CreateOverlay()

    -- Hide all standard UI
    UIParent:SetAlpha(0)

    -- MinimapCluster has SetIgnoreParentAlpha(true) in Blizzard code,
    -- so UIParent:SetAlpha(0) doesn't reach it.  Hide it explicitly.
    -- Save pre-AFK visibility so AFK_Exit restores the exact prior state
    -- rather than force-showing something another addon may have hidden.
    if MinimapCluster then
        afkOverlay._minimapWasShown = MinimapCluster:IsShown()
        MinimapCluster:Hide()
    end

    -- Mark the UI as ours-and-hidden so a crash while AFK can be recovered at
    -- the next login. AFK_Exit clears it, so a clean exit leaves nothing to undo.
    if cdb then cdb.afkUIDirty = true end

    -- Refresh info and show
    AFK_RefreshInfo()
    overlay:Show()

    -- Start slow camera orbit (pcall-guarded: may fail in cinematics or vehicle sequences).
    pcall(MoveViewRightStart, 0.03)

    -- Watch for panels the player opens while the screen is up, so they become
    -- visible instead of being invisible-but-functional. See AFK_ScanPanels.
    AFK_StartReveal()

    -- Clock refresh every 30s
    if afkClockTicker then afkClockTicker:Cancel() end
    afkClockTicker = C_Timer.NewTicker(30, function()
        if afkOverlay and afkOverlay:IsShown() then
            afkOverlay._clockText:SetText(AFK_ClockText())
        end
    end)
end

local function AFK_Exit()
    if not afkActive then return end
    afkActive = false

    -- Stop camera orbit
    pcall(MoveViewRightStop)

    -- Drop every SetIgnoreParentAlpha override first. Ordered before the alpha
    -- restore deliberately: an override left in place would make that frame ignore
    -- alpha changes for the rest of the session, breaking the next AFK screen and
    -- CleanSolo's fades.
    AFK_StopReveal()

    -- Restore UI; only show MinimapCluster if it was visible before AFK started.
    UIParent:SetAlpha(1)
    if MinimapCluster then
        if afkOverlay and afkOverlay._minimapWasShown then
            MinimapCluster:Show()
        end
    end
    if cdb then cdb.afkUIDirty = false end

    -- Hide overlay
    if afkOverlay then afkOverlay:Hide() end

    -- Stop clock ticker
    if afkClockTicker then afkClockTicker:Cancel(); afkClockTicker = nil end
end

-- ── AFK Fallback Poll ──────────────────────────────────────────
-- Belt-and-suspenders: PLAYER_FLAGS_CHANGED may not fire reliably
-- for server-originated idle AFK in all Midnight builds.  A 5s poll
-- guarantees we catch the transition regardless of event delivery.
-- Cost: one pcall(UnitIsAFK,"player") every 5 seconds — negligible.
local afkPollTicker
local function AFK_StartPoll()
    if afkPollTicker then return end
    afkPollTicker = C_Timer.NewTicker(5, function()
        if not db or not db.afkScreen then return end
        local ok, afk = pcall(UnitIsAFK, "player")
        if not ok or (issecretvalue and issecretvalue(afk)) then return end
        if afk and not afkActive then
            AFK_Enter()
        elseif not afk and afkActive then
            AFK_Exit()
        end
    end)
end

----------------------------------------------------------------
--  Delve — show the Nemesis Strongbox groups-remaining count
--
--  Blizzard puts the remaining Nemesis enemy-group count in the TOOLTIP of the
--  middle circular icon on the Delve plaque, so it is only readable by hovering
--  mid-run. This paints the number permanently under that icon.
--
--  ── VERIFIED FROM BLIZZARD SOURCE (wow-ui-source live, 2026-08-04) ──
--  The plaque is ONE widget, not three. It is the ScenarioHeaderDelves widget
--  (Blizzard_UIWidgetTemplateScenarioHeaderDelves.lua) living in
--  ScenarioObjectiveTracker.StageBlock.WidgetContainer -- the StageBlock whose
--  texture kit is "delves-scenario" (Blizzard_ScenarioObjectiveTracker.lua). Its
--  `spells` table drives a pool of UIWidgetBaseSpellTemplate frames parented to
--  `SpellContainer`, one per icon, each carrying its own `spellInfo` table with
--  `spellID`, `tooltip`, `text` and `stackDisplay`.
--
--  ⚠ WHY THE NUMBER IS PARSED FROM A STRING RATHER THAN READ FROM A FIELD.
--  `spellInfo.stackDisplay` is a number and would be the obvious source -- but
--  UIWidgetBaseSpellTemplateMixin:Setup shows its StackCount fontstring
--  UNCONDITIONALLY whenever `stackDisplay > 0`. The owner's screenshot shows no
--  number on any of the three icons, so every one of them has stackDisplay == 0.
--  That is a deduction from Blizzard's own code plus the observed UI, not a
--  guess: if the count were in stackDisplay, Blizzard would already be drawing
--  it and this feature would not be needed. The count exists only in the
--  tooltip text. `/qol delve` dumps the live fields so this can be re-checked if
--  Blizzard ever populates the numeric field -- at which point PREFER it.
--
--  ⚠ IDENTIFIED BY PATTERN, NOT BY INDEX. The nemesis icon is the middle one
--  today, but "index 2" rests on a single screenshot and Blizzard owns the
--  ordering. Matching the icon whose tooltip contains an "N / M" pair is
--  self-validating: the thing that identifies the icon IS the number we want,
--  so we can never label the wrong icon with a real count.
----------------------------------------------------------------

-- 0.5s: kill credit is not frame-critical and the poll only runs while a Delve
-- plaque with a matching icon is on screen. Deliberately slower than the hover
-- and AFK pollers.
local DELVE_POLL_RATE = 0.5

-- ⚠ The seeding note that used to live here still applies to the replacement key
-- below: unlike AuctionHouse's scanEngine, a user-tunable POSITION should be seeded,
-- because a stored value ought to win over a later default change. Do not "fix" either
-- offset key by adding it to a seed exemption.

-- ── Where the number sits: BLIZZARD'S OWN CORNER, not a centred glyph ──
--
-- ⚠⚠ NEW KEYS, NEW UNITS AGAIN, AND THE THIRD ORIGIN THIS FEATURE HAS USED. These are
-- insets from the icon's BOTTOM-RIGHT CORNER. The predecessors (delveCountCenterY/X)
-- measured from the icon's CENTRE, and delveCountOffsetY before them from its BOTTOM
-- EDGE. A stored 6/6 that meant "6 down and 6 right of centre" is a completely different
-- position read as a corner inset, so the old keys are DROPPED at login rather than
-- carried across -- same call as last time, same reason: silently reinterpreting a stored
-- number in new units is the AH scanEngine class of quiet wrongness.
--
-- ⚠ WHY CENTRING WAS ABANDONED, so nobody "restores" it. Centring a digit on this icon
-- could not be made exact. Three rounds of by-eye offsets each fixed one digit and left
-- another reading off-centre (the last was a per-glyph override for 1 alone), because the
-- API centres a string's METRICS BOX and no accessor exposes glyph INK bounds --
-- GetStringWidth and GetUnboundedStringWidth both report metrics. Any residual difference
-- between a glyph's ink and its advance box is therefore uncorrectable in general, and
-- dividing the icon's width by two to centre also lands on fractional pixels that round
-- per-digit. Owner-observed across v1.12.20 and the 2026-08-07 test build.
--
-- VERIFIED FROM BLIZZARD SOURCE (wow-ui-source live, 2026-08-07) -- this is Blizzard's own
-- placement for the count on THIS EXACT TEMPLATE, in both the XML and the Setup:
--     Blizzard_UIWidgetTemplateBase.xml:177-181
--         <FontString parentKey="StackCount" inherits="NumberFontNormal">
--             <Anchor point="BOTTOMRIGHT" relativeKey="$parent.Icon" x="-2" y="2"/>
--     Blizzard_UIWidgetTemplateBase.lua:511
--         self.StackCount:SetPoint("BOTTOMRIGHT", self.Icon, -2, 2);
-- A SINGLE corner anchor. No width, no justifyH, no centring, and therefore no width
-- division and no per-digit variation: the string's right edge is pinned to a fixed point,
-- so every digit lands identically by construction. Blizzard does not solve the centring
-- problem on this template -- they avoid it, and matching them is both exact and more
-- native than a centred digit ever was.
--
-- ⚠⚠ SETTLED AT 0/0 IN GAME (owner, 2026-08-15) -- the digit sits exactly ON the icon's
-- bottom-right corner, neither inset nor outset. Note what this does NOT mean: Blizzard's own
-- -2/+2 was chosen for a 36px icon, and its proportional equivalent on this 24px icon is 1.33,
-- so 0/0 is a deliberate choice near-but-not-equal to the scaled value, arrived at by eye at
-- the settled 11px font size. Do not restore -1/-1 (the pre-v1.14.13 default) and do not
-- "correct" it to Blizzard's 2/2.
--
-- ⚠ WHAT IS SOURCED HERE AND WHAT IS NOT -- the distinction cost a test round trip.
-- SOURCED: the anchoring METHOD (one BOTTOMRIGHT point, no span), which is what removed the
-- per-digit drift. OWNER-TUNED: the offsets below. Blizzard's literal -2/+2 shipped as the
-- default first on an unstated assumption that the owner's hand-dialled position was
-- equivalent to theirs; it was not -- he reported it "too close to the center". Evidence for
-- the construction is not evidence for the constants, and adopting both from one reading was
-- the error. (-1/-1 was confirmed in game 2026-08-07, then superseded by 0/0 on 2026-08-15.)
--
-- Insets are stored POSITIVE-inward (in from the right edge, up from the bottom edge) so the
-- numbers read the same as the /qol delvenudge arguments; NEGATIVE pushes the digit outside
-- the icon's bottom-right corner. 0/0 is a deliberate departure from Blizzard's inset
-- placement, in the same spirit as the checkmark departing from their 16x16 corner EarnedCheck. Do not "correct" them back to 2/2 on the grounds that Blizzard
-- uses 2/2: that exact move is what this comment exists to prevent.
local DELVE_COUNT_INSET_X = 0
local DELVE_COUNT_INSET_Y = 0

-- Per-glyph X override, keyed by the displayed count. The digit 1 alone reads further RIGHT
-- than the others and needs pulling left. The value below is the owner's, confirmed in
-- game; it is deliberately NOT restated in prose here, because the previous wording
-- named "1" and went stale the moment v1.13.4 tuned it to 3.
--
-- ⚠⚠ THIS SURVIVED THE MOVE TO CORNER ANCHORING, WHICH I PREDICTED IT WOULD NOT.
-- v1.13.0 deleted the centred design's equivalent override as "made meaningless by corner
-- anchoring", on the claim that one edge anchor makes "every digit land identically by
-- construction". That claim was wrong, and the owner falsified it immediately: the 1 still
-- hovered right. What corner anchoring actually fixed was the WIDTH DIVISION and its
-- per-digit pixel rounding. It pins the advance BOX's right edge -- it cannot touch where the
-- INK sits inside that box, and that is the one cause no accessor can measure.
--
-- ⚠ MECHANISM STILL UNMEASURED -- do not write it as fact anywhere. The consistent reading
-- is that 1's ink sits right of centre within its advance box (a smaller right side bearing
-- than the other digits), which would explain the SAME glyph needing the SAME direction of
-- correction under two completely different anchoring schemes -- centred (v1.12.20, needed
-- pulling left) and right-edge-anchored (v1.13.0, needs pulling left again). That
-- cross-scheme consistency is real evidence that the cause is the GLYPH and not the
-- construction, which is more than was known before. It is still not a measurement: nobody
-- has read Friz Quadrata's metrics, and GetStringWidth/GetUnboundedStringWidth report the
-- advance, not the ink. Treated as a per-glyph OPTICAL correction, which is standard
-- typographic practice and stays correct whether or not the reading above is right.
--
-- ⚠ X ONLY, and that is deliberate rather than an omission: all digits share a baseline and
-- none has a descender, so the vertical position is not glyph-dependent. If a vertical
-- difference is ever REPORTED, that reasoning is what to re-examine first.
--
-- ⚠ A TABLE keyed by count, so a second exception needs no new key and no new command. An
-- absent key means "use the global inset"; do not collapse this into a plain number.
local DELVE_COUNT_INSET_X_BY_COUNT = { [1] = 0 }

-- Atlases, both confirmed to RESOLVE on the live client via /qol delve (2026-08-05:
-- common-icon-checkmark 25x25, UI-Frame-IconMask 64x64) rather than trusted from
-- Blizzard's XML. The Midnight reagent-tier markers are why: those names still existed
-- but rendered the previous expansion's art.
local DELVE_CHECK_ATLAS = "common-icon-checkmark"

-- Pixels the checkmark extends past the icon on each side; NEGATIVE insets it. The owner
-- asked for it to cover the whole icon, which is a DELIBERATE departure from Blizzard's
-- own 16x16 corner EarnedCheck on this same template -- that intent still stands, this
-- knob only trims how far past the ring it spills.
--
-- ⚠ 0 (was 2, i.e. 28x28 over a 24px icon) is CONFIRMED GOOD IN GAME by the owner
-- (2026-08-07): "the checkmark looks great". Do not re-tune it as part of unrelated work.
--
-- ⚠ Sized by ANCHORING to the icon's bounds, never by SetSize. The template declares a
-- 36x36 Icon but the live Delve plaque measured 24x24 -- the layout rescales it -- so
-- any hardcoded size would be wrong on the only surface this ships to.
-- Fallback only; the live value is db.delveCheckOutset.
local DELVE_CHECK_OUTSET = 0

-- Points added to Blizzard's own number font. A DELTA rather than an absolute size, so
-- the number still tracks the client's font if Blizzard restyles it.
--
-- ⚠ Now 0 (was -1). The -1 existed because the number used to sit BELOW the icon,
-- where StackCount's size read a shade large against the plaque's other text. It sits ON
-- the icon now -- which is precisely the placement StackCount is sized for -- so that
-- rationale is void by its own terms and Blizzard's native size is correct.
-- Fallback only; the live value is db.delveFontDelta (see /qol delvesize).
--
-- ⚠⚠ THE SENTENCE ABOVE -- "it sits ON the icon now, which is precisely the placement
-- StackCount is sized for" -- IS NOW KNOWN TO BE ONLY HALF TRUE, AND THE MISSING HALF IS
-- THE ICON SIZE. MEASURED on the entrance placard 2026-08-15 via /qol delveplacard:
--
--     Blizzard's own count:  ARIALN.TTF  size 14  flags "OUTLINE"  white (1,1,1,1)
--                            anchors BOTTOMRIGHT -> BOTTOMRIGHT  -2,+2
--                            on an Icon measuring 36x36     -> ratio 14/36 = 0.389
--
-- Blizzard chose 14 FOR A 36px ICON. We inherit that absolute 14 from StackCount's font
-- object and apply it to the in-Delve plaque, whose Icon the layout RESCALES SMALLER (the
-- checkmark comment below records 24x24 measured 2026-08-05, unconfirmed since). At 24px
-- our number is 14/24 = 0.583 of the icon -- about 1.5x Blizzard's proportion; the ratio-
-- matched size would be ~9px.
--
-- ⚠ The irony is that the checkmark comment ~15 lines below already states this exact
-- principle -- "any hardcoded size would be wrong on the only surface this ships to" --
-- and solves it by ANCHORING rather than SetSize. That reasoning was never carried across
-- to the FONT size, which is the same hardcoded-absolute mistake in a different property.
--
-- ⚠⚠ BOTH HALVES NOW MEASURED (/qol delve in-Delve, 2026-08-15). The 24x24 above is
-- CONFIRMED, not stale:
--     in-Delve:  Icon 24x24, our count FRIZQT__.TTF at 13.99, stringHeight 13.9
--                -> 13.9/24 = 0.579  vs  Blizzard's 14/36 = 0.389   = 1.50x their proportion
--     ratio-matched size on a 24px icon = 9.33px, i.e. delveFontDelta about -5
--
-- ⚠ THE INSET IS A 36px CONSTANT TOO. Blizzard's -2,+2 was chosen for a 36px icon; the
-- proportional equivalent on 24px is 1.33, which is close to the owner's hand-dialled x=1.
-- So "correct the inset to Blizzard's 2" would move it AWAY from proportional truth.
--
-- ⚠⚠ SETTLED IN GAME AT -3, NOT THE RATIO-MATCHED -5 (owner, 2026-08-15): "in keeping with
-- the spirit without sacrificing visibility". That is 11px on a 24px icon = ratio 0.458
-- against Blizzard's 0.389 -- deliberately larger than proportional, because a proportionally
-- exact 9px digit was not legible enough on a 24px icon at normal viewing distance.
--
-- ⚠ DO NOT "CORRECT" THIS TO 0.389 OR TO -5. The ratio arithmetic was the tool for finding the
-- right neighbourhood, not the answer -- matching Blizzard's proportion and reading well at
-- 24px turned out to be different goals, and legibility won on the surface that ships. This is
-- the same trap as the inset: evidence for a construction is not evidence for its constants.
--
-- ⚠ Still stored as a DELTA off StackCount's live base, so a Blizzard restyle still carries
-- through. A ratio-of-icon-height implementation was considered and NOT built: the in-Delve
-- Icon has now measured 24x24 twice (2026-08-05 and 2026-08-15), so it would add a division
-- and per-icon rounding to solve a rescaling nobody has ever observed.
local DELVE_COUNT_FONT_DELTA = -3

-- Outline weight for the number. WoW has NO bold flag: SetFont's flags argument takes
-- OUTLINE / THICKOUTLINE / MONOCHROME and combinations, never a weight, so a heavier
-- outline is the native way to make a number read bolder. THICKOUTLINE is what Blizzard
-- itself uses on nameplate and floating-damage numbers.
-- Set back to "OUTLINE" if it ever reads too heavy at this size.
local DELVE_COUNT_OUTLINE = "OUTLINE"

-- The number's colour. WHITE, unconditionally, and NOT a count-based ramp.
--
-- ⚠ THIS REPLACES A FOUR-STEP COLOUR RAMP (4 red / 3 orange / 2 yellow / 1 green) that
-- shipped from 2026-08-05. Removed at the owner's request 2026-08-07 along with the scrim:
-- once the digit moved to Blizzard's own corner it reads as a stack badge, and a stack
-- badge that changes colour is not something the default UI does anywhere. Do not
-- reintroduce the ramp as a "nice to have" -- it was deliberately dropped, not lost.
--
-- VERIFIED FROM BLIZZARD SOURCE (wow-ui-source live, 2026-08-07): this is what Blizzard's
-- own count on this template is coloured. Their Setup NEVER calls SetTextColor on
-- StackCount (Blizzard_UIWidgetTemplateBase.lua around 507-548 sets only the point, the
-- text and the shown state), so it renders in the colour its font object declares --
-- NumberFontNormal, which is HIGHLIGHT_FONT_COLOR (Blizzard_Fonts_Shared FontStyles.xml
-- :389-391). So the global below is not "white by taste", it is the exact colour Blizzard
-- draws this number in.
--
-- Literal fallback because we set the colour explicitly rather than inheriting the font
-- object: the face and size come from the plaque's own Text, so nothing would supply the
-- colour if the global were missing.
local DELVE_COUNT_COLOR_GLOBAL = "HIGHLIGHT_FONT_COLOR"

local function DelveCountColor()
    local obj = _G[DELVE_COUNT_COLOR_GLOBAL]
    if type(obj) == "table" and obj.r and obj.g and obj.b then
        return obj.r, obj.g, obj.b
    end
    return 1, 1, 1
end

local delveTicker
local delveWarnedNoFont = false
-- Forward-declared: DelveCountString references it, and a local declared BELOW a
-- referencing function binds as a nil global (the /way trap).
local DelveAnchorCount

-- Locate the live Delve plaque's icon frames. Every level is guarded: this is a
-- Blizzard layout we do not own, and a restructure must cost us the feature
-- rather than throw inside their tracker's update.
--
-- ⚠ SEARCHED BY SHAPE, NOT BY PATH -- and that is a CORRECTION, not a flourish.
-- v1.12.15 looked only in ScenarioObjectiveTracker.StageBlock.WidgetContainer and
-- found nothing, because Blizzard's XML declares THREE sibling widget containers
-- (StageBlock.WidgetContainer, TopWidgetContainerBlock.WidgetContainer and
-- BottomWidgetContainerBlock.WidgetContainer) and the Delve header lives in one of
-- the others. I picked one of three by inference and shipped it.
--
-- Rather than swap in a different hardcoded path -- a one-in-three guess again --
-- this walks the tracker's descendants for the SHAPE the plaque actually has: a
-- frame with a `SpellContainer` whose children carry `spellInfo`. That is
-- self-validating (the thing we search for is the thing we need) and it survives
-- Blizzard moving the widget between containers, which is exactly what caught us.
local DELVE_SEARCH_DEPTH = 6
local delveCachedWidget

local function DelveSpellsFromWidget(w)
    if type(w) ~= "table" then return nil end
    -- A widget Blizzard has hidden or released back to its pool is not a plaque.
    -- Without this the cache can outlive the Delve: the frames still answer
    -- GetChildren after release, so a stale widget would keep validating.
    if w.IsShown and not w:IsShown() then return nil end
    local sc = w.SpellContainer
    if not (sc and sc.GetChildren) then return nil end
    local spells = { sc:GetChildren() }
    if #spells == 0 then return nil end
    -- Require the spellInfo shape: a SpellContainer alone could belong to another
    -- scenario header, and labelling someone else's icons would be worse than
    -- showing nothing.
    for i = 1, #spells do
        if spells[i] and spells[i].spellInfo then return spells end
    end
    return nil
end

-- Parameter is `node`, not `frame`: `frame` is this file's module-wide event frame
-- and shadowing it inside a recursive walk is exactly the kind of confusion that
-- reads fine and then bites during a later edit.
local function DelveFindWidget(node, depth)
    if not node or depth > DELVE_SEARCH_DEPTH or not node.GetChildren then return nil end
    if DelveSpellsFromWidget(node) then return node end
    local kids = { node:GetChildren() }
    for i = 1, #kids do
        local found = DelveFindWidget(kids[i], depth + 1)
        if found then return found end
    end
    return nil
end

local function DelveSpellFrames()
    -- The tracker itself going away (leaving the Delve, a UI reload of the module)
    -- invalidates any cached widget outright -- checked BEFORE the fast path, so a
    -- released frame that still answers GetChildren cannot keep the cache alive.
    local root = _G.ScenarioObjectiveTracker or _G.ObjectiveTrackerFrame
    if not root then delveCachedWidget = nil; return nil end

    -- Fast path: re-validate the cached widget instead of re-walking every tick.
    local spells = delveCachedWidget and DelveSpellsFromWidget(delveCachedWidget)
    if spells then return spells end

    delveCachedWidget = nil
    -- Roots tried in order. The scenario module is where the plaque lives today;
    -- the manager frame is a cheap hedge against Blizzard reparenting it, and
    -- costs one nil check when absent.
    local roots = { _G.ScenarioObjectiveTracker, _G.ObjectiveTrackerFrame }
    for i = 1, #roots do
        local w = DelveFindWidget(roots[i], 1)
        if w then
            delveCachedWidget = w
            return DelveSpellsFromWidget(w)
        end
    end
    return nil
end

-- Pull the REMAINING count out a tooltip carrying an "N / M" pair.
-- Returns nil when the tooltip has no such pair, which is how non-nemesis icons
-- are rejected. Only the first number is used -- the owner asked for a bare
-- countdown (4, 3, 2, 1, 0), not a fraction.
--
-- ⚠ Takes the LAST pair, not the first. The observed tooltip contains exactly
-- one ("Enemy groups remaining: 4 / 4"), but that is a SINGLE sample of a
-- localized, server-authored string: the prose paragraphs above it could
-- legitimately contain another fraction, and a counter is conventionally the
-- trailing line. Anchoring to the first match would silently report a number
-- lifted out of a sentence. Neither choice is provably right, so this takes the
-- one that fails more gracefully -- and says so rather than looking deliberate.
-- Where the count text actually lives.
--
-- ⚠ MEASURED, NOT ASSUMED (/qol delve on a live Delve, 2026-08-04):
-- spellInfo.tooltip is EMPTY ("") on all three icons, and so is spellInfo.text.
-- v1.12.15 read spellInfo.tooltip and therefore had nothing to parse. Blizzard's
-- own UIWidgetBaseSpellTemplateMixin:OnEnter explains why:
--     local shouldUseSpellOrLootObjectTooltip = not self.tooltip or self.tooltip == "";
--     ... EmbeddedItemTooltip:SetSpellByID(self.spellID, false, true);
-- i.e. when the widget string is empty the tooltip is rendered FROM THE SPELL, so
-- the "Enemy groups remaining: N / M" line is the spell's DESCRIPTION, which the
-- server fills with the live value.
--
-- The widget string is still preferred when present: Blizzard prefers it too, and a
-- future patch could start supplying it.
local function DelveCountText(info)
    if type(info) ~= "table" then return nil end
    if type(info.tooltip) == "string" and info.tooltip ~= "" then
        return info.tooltip
    end
    local id = info.spellID
    if type(id) ~= "number" or not C_Spell then return nil end

    -- A description can be empty until the spell's data is cached. Ask once and let
    -- the next poll tick pick it up -- no event plumbing needed, because we are
    -- already polling.
    if C_Spell.GetSpellDescription then
        local ok, desc = pcall(C_Spell.GetSpellDescription, id)
        if ok and type(desc) == "string" and desc ~= "" then return desc end
    end
    if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
    return nil
end

local function DelveParseRemaining(tooltip)
    if type(tooltip) ~= "string" then return nil end
    local last
    for n in tooltip:gmatch("(%d+)%s*/%s*%d+") do last = n end
    return last and tonumber(last) or nil
end

-- Our own fontstring, never Blizzard's StackCount. StackCount is hidden on every
-- Setup pass while stackDisplay is 0, so writing to it would be a fight we lose
-- on the next widget update -- and would also destroy the native path if
-- Blizzard ever does populate the field. We do, however, put it exactly where
-- Blizzard puts theirs; see DELVE_COUNT_INSET_X for the sourced anchor.
--
-- Re-anchor only when the inset actually changed, so the 0.5s poll is not calling
-- SetPoint on every tick. ClearAllPoints first: SetPoint ADDS a point rather than
-- replacing one, so re-anchoring without clearing would leave the old point fighting
-- the new one.
DelveAnchorCount = function(fs, anchor, count)
    local y = (db and tonumber(db.delveCountInsetY)) or DELVE_COUNT_INSET_Y
    local x = (db and tonumber(db.delveCountInsetX)) or DELVE_COUNT_INSET_X
    -- Per-glyph optical correction; see DELVE_COUNT_INSET_X_BY_COUNT. Only the digit 1 has
    -- one, and only on the X axis.
    --
    -- ⚠⚠ A DELTA ADDED TO THE GLOBAL INSET, NOT A REPLACEMENT FOR IT (changed v1.14.14).
    -- It used to assign `x = <the override>` outright, which made the correction ABSOLUTE --
    -- and an optical correction is inherently RELATIVE ("this glyph needs N px more inset than
    -- the others"), so absolute was simply the wrong shape. Two concrete costs:
    --   1. Moving the global silently changed the correction's magnitude. When the owner set
    --      /qol delvenudge 0 0 in v1.14.13, the digit 1's correction went from +2 to +3 with
    --      nothing touching it.
    --   2. It made a 0 default UNSAFE. With absolute semantics, inset1=0 matches the global
    --      only while the global is also 0; the first /qol delvenudge would tear the digit 1
    --      away from every other digit. As a delta, 0 means "no correction" permanently.
    -- ⚠ Behaviour-preserving at the shipped 0/0: a stored 3 read as an absolute gave x=3, and
    -- read as a delta off 0 also gives x=3. So no migration is needed for existing accounts.
    local d1 = (db and tonumber(db.delveCountInsetX1))
               or DELVE_COUNT_INSET_X_BY_COUNT[1] or 0
    if count == 1 then
        x = x + d1
    elseif DELVE_COUNT_INSET_X_BY_COUNT[count] ~= nil then
        x = x + DELVE_COUNT_INSET_X_BY_COUNT[count]
    end
    -- ⚠ The cache key must include the RESOLVED x, not just the stored settings, or a count
    -- ticking 2 -> 1 would keep the previous digit's offset: the early-out would see the same
    -- db numbers and skip the re-anchor the new glyph needs.
    if fs._vuiInsetY == y and fs._vuiInsetX == x then return end
    fs._vuiInsetY, fs._vuiInsetX = y, x
    fs:ClearAllPoints()
    -- ⚠ ONE point, BOTTOMRIGHT to BOTTOMRIGHT -- Blizzard's own anchor for the count on
    -- this template (Blizzard_UIWidgetTemplateBase.lua:511). Insets are stored positive
    -- and negated here, so the stored numbers read as "in from the right, up from the
    -- bottom" and match the /qol delvenudge arguments.
    --
    -- ⚠⚠ DO NOT REINTRODUCE CENTRING. This deliberately replaced a LEFT+RIGHT span with
    -- SetJustifyH("CENTER"). Centring acts on the METRICS box, no API exposes glyph ink
    -- bounds, and halving the icon width lands on fractional pixels that round per digit --
    -- so it could not be made exact and cost three rounds of by-eye offsets. Corner
    -- anchoring pins the box's RIGHT EDGE instead, with no width division and no justify.
    --
    -- ⚠⚠ WHAT THAT DOES AND DOES NOT BUY -- AN EARLIER VERSION OF THIS COMMENT OVERCLAIMED.
    -- It said "every digit lands identically by construction". That is true of the ADVANCE
    -- BOX and false of the visible INK: corner anchoring removes the width division and the
    -- per-digit rounding, but a glyph whose ink sits off-centre INSIDE its own box is still
    -- off. The owner falsified the claim on 2026-08-07 -- the digit 1 still read further
    -- right than the others -- which is why the per-glyph override above exists in the
    -- corner-anchored design too. Corner anchoring removed two of the three causes, not all
    -- three, and the remaining one is exactly the one no accessor can measure.
    --
    -- ⚠ Historical, still true and still a trap: anchoring all four sides (tried 2026-08-05
    -- to give the string a height so justifyV would apply) put the number in the icon's
    -- UPPER-LEFT corner -- BOTH justifications stopped applying, not just the vertical one.
    -- Owner-observed. The mechanism was never understood. Single-point anchoring sidesteps
    -- it entirely, and there is now no reason to go back and find out.
    fs:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
end

-- Does an atlas actually RESOLVE on this client? SetAtlas does not report a bad name --
-- it silently leaves the texture blank -- so a pcall around it proves nothing. This is
-- the only way to fail loudly instead of drawing nothing.
--
-- ⚠ Namespace-guarded, not merely pcall'd: indexing a nil C_Texture raises before pcall
-- can catch it (the C_Console trap).
local function DelveAtlasExists(name)
    local ns = _G.C_Texture
    if not (ns and ns.GetAtlasInfo) then return false end
    local ok, info = pcall(ns.GetAtlasInfo, name)
    return (ok and info) and true or false
end

-- ⚠ THE CIRCULAR SCRIM IS GONE ON PURPOSE (removed 2026-08-07, owner's request).
-- A black masked texture used to sit under the number at 60% so a centred digit stayed
-- readable over the icon art. It went with the centring: the number now sits in Blizzard's
-- own corner, where their StackCount has no backing texture either, and the digit's
-- THICKOUTLINE plus its drop shadow are what carry contrast -- which is exactly how
-- Blizzard's own numbers read against artwork.
--
-- ⚠ DO NOT REINTRODUCE IT without re-reading this: the deleted code carried a hard-won
-- mask fix (attach to BOTH IconMask and CircleMask, because Setup shows exactly one and a
-- hidden MaskTexture does not mask -- binding only to IconMask is why the scrim once
-- rendered SQUARE on a circular icon). That detail is preserved in git history at
-- the v1.12.20 tag, which is permanent -- read DelveTint there first. Recreating a scrim from
-- scratch would very likely reintroduce the square-scrim bug.

-- Size the checkmark against the icon's live bounds. Split out of DelveCheck so the
-- outset is tunable without a reload: DelveCheck early-outs on its cached texture, so
-- anchors set only at creation could never change. Same shape as DelveAnchorCount --
-- cache the applied value, ClearAllPoints first (SetPoint ADDS a point rather than
-- replacing one), and no-op when nothing moved so the 0.5s poll stays cheap.
local function DelveAnchorCheck(tex, icon)
    local o = (db and tonumber(db.delveCheckOutset)) or DELVE_CHECK_OUTSET
    if tex._vuiOutset == o then return end
    tex._vuiOutset = o
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -o, o)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", o, -o)
end

-- The completion checkmark.
--
-- ⚠ Deliberately NOT Blizzard's own EarnedCheck, even though it exists on this frame
-- and uses this very atlas: their Setup runs SetShown(spellInfo.showAsEarned) on every
-- widget update, so driving it ourselves is the same fight-we-lose that already rules
-- out writing to StackCount. Owning the texture also leaves their native path intact
-- if the server ever does set showAsEarned.
local function DelveCheck(spellFrame)
    if spellFrame._vuiNemesisCheck then return spellFrame._vuiNemesisCheck end
    local icon = spellFrame.Icon
    if not icon or not DelveAtlasExists(DELVE_CHECK_ATLAS) then return nil end

    -- OVERLAY sublevel 2: above the Border ring AND above Blizzard's EarnedCheck
    -- (sublevel 1), because this one covers the whole icon by design.
    local tex = spellFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    if not tex then return nil end
    if not pcall(tex.SetAtlas, tex, DELVE_CHECK_ATLAS) then return nil end
    DelveAnchorCheck(tex, icon)
    tex:Hide()

    spellFrame._vuiNemesisCheck = tex
    return tex
end

-- Last-resort typeface if no Blizzard object can be read. Friz Quadrata is the standard
-- Midnight UI face and what the rest of the Delve plaque uses.
local DELVE_FALLBACK_FONT_FILE = "Fonts\\FRIZQT__.TTF"

-- Resolve the TYPEFACE for the count.
--
-- ⚠ Deliberately NOT StackCount's, BY DEFAULT. StackCount is NumberFontNormal (ARIALN, a
-- narrow stack-badge face), which made the count the only number on the plaque not in Friz
-- Quadrata -- owner-reported 2026-08-05 as looking "weird" next to everything else.
-- The widget's OWN Text fontstring is the authoritative source for that: reading its file
-- gives us the plaque's live face and follows Blizzard if they restyle the standard UI font.
--
-- ⚠ As of v1.14.11 this is SWITCHABLE via db.delveCountFace ("plaque" | "blizzard"), so the
-- owner can A/B it in game against the number Blizzard itself draws on the pre-entry
-- placard. The shipped default is "blizzard". See the key's comment in the defaults table.
--
-- ⚠ CORRECTION (sourced 2026-08-15, Blizzard_UIWidgetTemplateBase.lua:531): the old comment
-- here said the template "declares it inherits=GameFontNormal, so reading its file gives us
-- exactly the plaque's face". Reading the file IS right, but the reasoning was not: Setup
-- calls `self.Text:Setup(text, self.spellInfo.textFontType, self.spellInfo.textSizeType, ...)`,
-- so the live face is chosen by SERVER-SUPPLIED font-type fields, not fixed by the template's
-- inherit. Reading the live fontstring is therefore the ONLY correct way to get it -- do not
-- "simplify" this to a hardcoded GameFontNormal lookup on the strength of the inherit.
--
-- Only the FILE comes from here; the SIZE still comes from StackCount (see
-- DelveCountString), so switching typeface changes one variable and not two.
local function DelveNumberFontFile(spellFrame)
    -- Blizzard's own count face, when asked for it. StackCount's live font first (that is
    -- literally the object Blizzard draws the number with), NumberFontNormal as the fallback.
    if db and db.delveCountFace == "blizzard" then
        local sc = spellFrame and spellFrame.StackCount
        if sc and sc.GetFont then
            local ok, file = pcall(sc.GetFont, sc)
            if ok and type(file) == "string" and file ~= "" then return file end
        end
        local nfn = _G.NumberFontNormal
        if nfn and nfn.GetFont then
            local ok, file = pcall(nfn.GetFont, nfn)
            if ok and type(file) == "string" and file ~= "" then return file end
        end
        -- Fall through to the plaque face rather than returning nothing: a missing number
        -- font would leave an invisible digit, which reads as the feature being broken.
    end
    local candidates = { spellFrame.Text, _G.GameFontNormal }
    for i = 1, #candidates do
        local src = candidates[i]
        if src and src.GetFont then
            local ok, file = pcall(src.GetFont, src)
            if ok and type(file) == "string" and file ~= "" then return file end
        end
    end
    return DELVE_FALLBACK_FONT_FILE
end

-- Apply the size delta, typeface and outline weight, from the base size captured at creation.
--
-- ⚠ Reads fs._vuiBaseSize, NEVER GetFont. Once we have called SetFont, GetFont reports
-- the size WE wrote, so deriving the new size from it would compound the delta on every
-- change -- one tap of /qol delvesize would keep growing the number.
--
-- ⚠⚠ THE EARLY-OUT CACHE KEY MUST COVER EVERY INPUT SetFont CONSUMES -- delta, FACE and
-- OUTLINE. It covered the delta alone until v1.14.11, which was correct only while the other
-- two were compile-time constants. Now that /qol delveface and /qol delveoutline can change
-- them live, a delta-only key would make both commands silently no-op until the delta
-- happened to move -- the same class of bug the anchor helper's key documents (a count
-- ticking 2 -> 1 keeping the old glyph's offset). If another SetFont input is ever added,
-- add it here in the same breath.
--
-- ⚠ The FACE is re-resolved on every call rather than read from a value captured at
-- creation, because the face knob changes what DelveNumberFontFile returns. The SIZE is
-- still the captured base -- that one genuinely must not be re-read (see above).
local function DelveApplyFont(fs, spellFrame)
    local d = (db and tonumber(db.delveFontDelta)) or DELVE_COUNT_FONT_DELTA
    local outline = (db and db.delveCountOutline) or DELVE_COUNT_OUTLINE
    local file = spellFrame and DelveNumberFontFile(spellFrame) or fs._vuiBaseFile
    if fs._vuiFontDelta == d and fs._vuiOutline == outline and fs._vuiFaceFile == file then
        return
    end
    fs._vuiFontDelta, fs._vuiOutline, fs._vuiFaceFile = d, outline, file
    local base = fs._vuiBaseSize
    if not (file and type(base) == "number") then return end
    local sz = base + d
    if sz < 1 then sz = 1 end
    -- ⚠ SetFont takes file, size and flags TOGETHER: a resize that forgets the flags
    -- silently drops the outline. "NONE" is passed as nil, which is how you ask for no
    -- outline at all -- the empty string is not a documented flag value.
    pcall(fs.SetFont, fs, file, sz, (outline ~= "NONE") and outline or nil)
end

-- `count` is forwarded to DelveAnchorCount only so the per-glyph override is right on the
-- very first frame; nothing else here depends on the value.
local function DelveCountString(spellFrame, count)
    if spellFrame._vuiNemesisCount then return spellFrame._vuiNemesisCount end
    local anchor = spellFrame.Icon or spellFrame
    local fs = spellFrame:CreateFontString(nil, "OVERLAY")

    -- Adopt Blizzard's StackCount font object first, purely to inherit its SIZE -- the
    -- scale Blizzard chose for a number sitting inside this icon. Its TYPEFACE is then
    -- replaced below, because StackCount is ARIALN and every other number on this plaque
    -- is Friz Quadrata. NumberFontNormal is the fallback, and a missing font object is
    -- reported once rather than leaving an invisible fontstring to look like a bug.
    local src = spellFrame.StackCount and spellFrame.StackCount.GetFontObject
                and spellFrame.StackCount:GetFontObject()
    if src then
        fs:SetFontObject(src)
    elseif _G.NumberFontNormal then
        fs:SetFontObject(_G.NumberFontNormal)
    elseif not delveWarnedNoFont then
        delveWarnedNoFont = true
        VUI.Print("Quality of Life",
            "Delve count: no usable number font found; the count may be invisible.")
    end
    -- ⚠ Capture the base size ONCE, here, BEFORE any delta is applied.
    -- DelveApplyFont re-reads these rather than GetFont, because after we have written to
    -- the fontstring GetFont reports OUR size -- so re-deriving the delta from it would
    -- compound the adjustment every time the knob moved.
    local okf, _, size = pcall(fs.GetFont, fs)
    if okf and type(size) == "number" then
        -- SIZE from Blizzard's stack badge, FILE from the plaque's own typeface. The two
        -- deliberately come from different objects: the badge is the right SCALE for a
        -- number sitting inside a 24px icon, but the wrong FACE for this panel.
        fs._vuiBaseSize = size
    end
    fs._vuiBaseFile = DelveNumberFontFile(spellFrame)
    DelveApplyFont(fs, spellFrame)

    -- Drop shadow, on the same reasoning as the map coordinates -- and now load-bearing
    -- rather than decorative: the black scrim that used to guarantee contrast is gone, so
    -- the shadow and the THICKOUTLINE are the only things separating a white digit from
    -- bright icon art. This is how Blizzard's own numbers read against artwork.
    --
    -- ⚠ Its (1, -1) offset was once suspected of biasing PERCEIVED centring, an experiment
    -- that never ran. That question died with centring itself -- the digit is corner-anchored
    -- now, so there is no centre to be biased away from. Do not remove the shadow on the
    -- strength of that old note: its job here is contrast.
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    -- ⚠ NO SetJustifyH / SetJustifyV, deliberately. Both were here to serve centring, and
    -- both are no-ops on a single-point-anchored string with no width or height -- the box
    -- IS the text. Blizzard sets neither on their own StackCount. Setting them anyway would
    -- read as though justification were doing work, which is how the last round of wrong
    -- assumptions started.
    spellFrame._vuiNemesisCount = fs
    DelveAnchorCount(fs, anchor, count)
    return fs
end

local function DelveUpdate()
    local spells = DelveSpellFrames()
    if not spells then return end
    for i = 1, #spells do
        local f    = spells[i]
        local info = f and f.spellInfo
        local left = info and DelveParseRemaining(DelveCountText(info))

        -- Prefer the numeric field the moment Blizzard ever populates it, and
        -- stand down entirely in that case: their StackCount is then already
        -- drawing the number and a second copy would be clutter.
        local nativeShows = info and type(info.stackDisplay) == "number"
                            and info.stackDisplay > 0

        -- Three states, mutually exclusive: nothing / number / checkmark.
        local showCount, showCheck = false, false
        if left and not nativeShows then
            if left == 0 then showCheck = true else showCount = true end
        end

        -- Cleared: the checkmark stands alone, replacing the digit rather than joining it.
        local chk = (showCheck and DelveCheck(f)) or (f and f._vuiNemesisCheck)
        if chk then
            -- Re-anchor even while hidden: picks up a /qol delvecheck live, and keeps the
            -- size correct if the layout rescales the icon between runs.
            if f.Icon then DelveAnchorCheck(chk, f.Icon) end
            chk:SetShown(showCheck)
        end

        -- Atlas unavailable (DelveCheck returned nil) -- fall back to drawing the digit 0,
        -- which is what this looked like before the checkmark existed. Failing to a working
        -- older behaviour beats failing to a blank icon.
        if showCheck and not chk then showCount = true end

        local fs = (showCount and DelveCountString(f, left)) or (f and f._vuiNemesisCount)
        if fs then
            if showCount then
                -- `left` is passed rather than read back off the fontstring: this runs BEFORE
                -- SetText, so the string still holds the PREVIOUS count at this point.
                DelveAnchorCount(fs, f.Icon or f, left)  -- picks up /qol delvenudge+delveone
                DelveApplyFont(fs, f)   -- picks up /qol delvesize+delveface+delveoutline live
                fs:SetText(left)
                -- Set every tick rather than once at creation: DelveApplyFont can re-read
                -- the font object, and a colour is cheap. Unconditional white -- there is
                -- no longer a per-count ramp; see DELVE_COUNT_COLOR_GLOBAL.
                fs:SetTextColor(DelveCountColor())
                fs:Show()
            else
                fs:Hide()
            end
        end
    end
end

local function DelveStopCount()
    if delveTicker then delveTicker:Cancel(); delveTicker = nil end
    local spells = DelveSpellFrames()
    if not spells then return end
    for i = 1, #spells do
        local f = spells[i]
        if f then
            if f._vuiNemesisCount then f._vuiNemesisCount:Hide() end
            if f._vuiNemesisCheck then f._vuiNemesisCheck:Hide() end
        end
    end
end

local function DelveStartCount()
    if delveTicker then return end
    delveTicker = C_Timer.NewTicker(DELVE_POLL_RATE, function()
        if not (db and db.delveNemesisCount) then return end
        DelveUpdate()
    end)
end

-- PERMANENT diagnostic. The whole feature rests on where Blizzard keeps this
-- number, and that is only knowable by reading the live widget -- so the tool
-- that reads it stays shipped, exactly like /ah check and /qol ilvl.
----------------------------------------------------------------
--  /qol delveplacard  — measure the number Blizzard draws itself
--
--  WHY A SECOND PROBE. `/qol delve` (below) starts from ScenarioObjectiveTracker and gives
--  up with "run this while inside a Delve" if it finds nothing. The surface this one exists
--  for is the placard that pops up when you WALK UP TO a Delve entrance, i.e. BEFORE the
--  scenario tracker holds anything -- so the existing probe is structurally blind to it.
--  That is the recorded landmine "a probe only covers the question it was built for", and
--  extending the old one was the wrong shape: its whole discovery path is the thing that
--  cannot reach here.
--
--  WHAT IT ANSWERS. On the pre-entry placard Blizzard populates the count itself, which
--  means `spellInfo.stackDisplay > 0` and its own StackCount fontstring is doing the work
--  (Blizzard_UIWidgetTemplateBase.lua:543-545). Inside a Delve stackDisplay is 0 -- measured
--  2026-08-04 -- which is why we draw our own digit there at all. So this dumps, for every
--  spell widget it can find anywhere in the UI, the three things needed to make ours match
--  theirs: the FONT (file/size/flags), the ANCHOR (point + offsets), and the COLOUR.
--
--  ⚠ DISCOVERY IS BY SHAPE, FROM UIParent -- deliberately not from a named container. I do
--  not know what frame hosts the pre-entry placard, and guessing a path is exactly how
--  v1.12.16 shipped a fix for a non-bug. A frame carrying a `SpellContainer` whose children
--  have `spellInfo` is the signature; the walk reports what it found so a miss is diagnosable
--  rather than silent.
--
--  ⚠⚠ EVERY WIDGET CALL IS pcall'd AND THE WALK IS DEPTH-CAPPED. A sweep from UIParent WILL
--  meet FORBIDDEN objects -- that is not hypothetical, it is the v1.14.10 bug: a House Editor
--  pin raised "Attempt to access forbidden object from code tainted by an AddOn" on a bare
--  GetParent(). Note the asymmetry that makes it easy to get wrong: `node.SpellContainer` is a
--  table read and is safe, while `node:GetChildren()` is a widget call and is not.
----------------------------------------------------------------
local DELVE_PLACARD_MAX_DEPTH = 12

-- Font facts for one FontString, or nil. Returned as a table so the caller decides layout.
local function DelveFontFacts(fs)
    if not (fs and fs.GetFont) then return nil end
    local ok, file, size, flags = pcall(fs.GetFont, fs)
    if not ok then return nil end
    local t = { file = file or "?", size = size or 0, flags = flags or "" }
    -- Strip the directory so the FACE is readable in a screenshot; the full path is noise
    -- at photo resolution and the filename is the part that identifies the typeface.
    t.face = tostring(t.file):match("([^\\/]+)$") or tostring(t.file)
    local okc, r, g, b, a = pcall(fs.GetTextColor, fs)
    if okc and r then t.color = ("%.2f,%.2f,%.2f,%.2f"):format(r, g, b, a or 1) end
    local oks, shown = pcall(fs.IsShown, fs)
    if oks then t.shown = shown end
    local okt, txt = pcall(fs.GetText, fs)
    if okt then t.text = txt end
    local okn, n = pcall(fs.GetNumPoints, fs)
    if okn and type(n) == "number" and n > 0 then
        local parts = {}
        for i = 1, n do
            local okp, pt, _, relPt, x, y = pcall(fs.GetPoint, fs, i)
            if okp then
                parts[#parts + 1] = ("%s->%s %+.0f,%+.0f")
                    :format(tostring(pt), tostring(relPt), x or 0, y or 0)
            end
        end
        t.anchors = table.concat(parts, "  ")
    end
    return t
end

-- ⚠⚠ THE SIGNATURE IS `StackCount`, NOT `SpellContainer` -- CORRECTED v1.14.12 AFTER THE
-- v1.14.11 PROBE FOUND NOTHING. `SpellContainer` is a parentKey on the ScenarioHeaderDelves
-- template alone (Blizzard_UIWidgetTemplateScenarioHeaderDelves.xml:40), i.e. the IN-DELVE
-- plaque. The entrance placard's icons live in a generic `UIWidgetContainerTemplate`
-- (Blizzard_DelvesDifficultyPicker.xml:136) whose widget frames are
-- `UIWidgetTemplateSpellDisplay`, and THAT template holds the spell frame one level down
-- under parentKey `Spell` (Blizzard_UIWidgetTemplateSpellDisplay.xml:8). So the old sweep
-- missed the placard twice over: wrong wrapper, and one level too shallow.
--
-- ⚠ The lesson is the recorded one, hit while writing a probe specifically to avoid it: a
-- probe only covers the question it was built for. The signature was generalised from the
-- ONE surface already known, so it could only ever re-find that surface. Matching on
-- StackCount -- the thing actually being measured -- is signature-by-GOAL rather than
-- signature-by-example, and it matches all three nestings.
local function DelvePlacardSweep(node, depth, out, seen, stats)
    if not node or depth > DELVE_PLACARD_MAX_DEPTH then return end
    if seen[node] then return end
    seen[node] = true
    stats.visited = stats.visited + 1
    if depth > stats.deepest then stats.deepest = depth end
    -- Table reads: safe even on a forbidden object. Any of the three shapes counts.
    local why
    if node.StackCount ~= nil then why = "StackCount"
    elseif node.SpellContainer ~= nil then why = "SpellContainer"
    elseif node.widgetFrames ~= nil then why = "widgetFrames" end
    if why then out[#out + 1] = { frame = node, why = why, depth = depth } end
    -- Widget CALL: must be pcall'd. A forbidden object raises here.
    if not node.GetChildren then return end
    local ok, kids = pcall(function() return { node:GetChildren() } end)
    if not ok then stats.forbidden = stats.forbidden + 1; return end
    for i = 1, #kids do
        DelvePlacardSweep(kids[i], depth + 1, out, seen, stats)
    end
end

-- Dump the count-bearing fontstrings for ONE spell frame. Shared by the named-lookup path
-- and the sweep, so both report identically and a discrepancy between them is meaningful.
local function DelveDumpSpellFrame(indent, sf)
    local rows = { { "StackCount", sf.StackCount }, { "Text", sf.Text },
                   { "ours", sf._vuiNemesisCount } }
    for r = 1, #rows do
        local lbl, tgt = rows[r][1], rows[r][2]
        local ft = DelveFontFacts(tgt)
        if not tgt then
            print(("%s%-11s ABSENT"):format(indent, lbl))
        elseif not ft then
            print(("%s%-11s unreadable"):format(indent, lbl))
        else
            print(("%s%-11s face=%s size=%.0f flags=%q shown=%s text=%q")
                :format(indent, lbl, ft.face, ft.size, ft.flags,
                        tostring(ft.shown), tostring(ft.text)))
            print(("%s%-11s color=%s  anchors: %s")
                :format(indent, "", tostring(ft.color), tostring(ft.anchors)))
        end
    end
end

local function DumpDelvePlacardProbe()
    print("|cFF00CCFF[VeritasUI Delve placard probe]|r")
    print("  Stand at a Delve ENTRANCE with the placard showing, then run this.")

    -- The two reference font objects, printed unconditionally so the comparison table is
    -- complete even if no placard is found. These are what Blizzard's own count and the
    -- plaque's own text resolve to, and they are the two candidates /qol delveface switches
    -- between.
    for _, name in ipairs({ "NumberFontNormal", "GameFontNormal" }) do
        local f = DelveFontFacts(_G[name])
        print(("  %-17s %s"):format(name,
            f and ("face=%s size=%.0f flags=%q color=%s")
                :format(f.face, f.size, f.flags, tostring(f.color)) or "ABSENT"))
    end
    local face = (db and db.delveCountFace) or "blizzard"
    local outl = (db and db.delveCountOutline) or "?"
    print(("  our settings:    face=%s outline=%s sizeDelta=%s inset=%s,%s inset1=%s")
        :format(face, outl, tostring(db and db.delveFontDelta),
                tostring(db and db.delveCountInsetX), tostring(db and db.delveCountInsetY),
                tostring(db and db.delveCountInsetX1)))

    ----------------------------------------------------------------
    --  PATH 1 — NAMED LOOKUP (sourced, primary)
    --
    --  Blizzard_DelvesDifficultyPicker.lua:651 registers the placard's "Map Properties"
    --  icons via  self.DelveModifiersWidgetContainer:RegisterForWidgetSet(
    --      self.selectedTierInfo.modifierUIWidgetSetID)
    --  and UIWidgetContainerMixin keeps them in `self.widgetFrames`
    --  (Blizzard_UIWidgetManager.lua:262), keyed by widgetID. Each frame is a
    --  UIWidgetTemplateSpellDisplay, which holds the actual spell frame one level down
    --  under parentKey `Spell` (Blizzard_UIWidgetTemplateSpellDisplay.xml:8).
    --
    --  A named lookup is used IN PREFERENCE to the sweep now that source supplies the name:
    --  it cannot be missed by a wrong signature or a depth cap, which is exactly how the
    --  v1.14.11 sweep reported "found 0" on a placard that was plainly on screen.
    ----------------------------------------------------------------
    local picker = _G.DelvesDifficultyPickerFrame
    print(("  DelvesDifficultyPickerFrame: %s"):format(tostring(picker ~= nil)))
    if picker then
        local shown = "?"
        local oks, s = pcall(picker.IsShown, picker)
        if oks then shown = tostring(s) end
        local mc = picker.DelveModifiersWidgetContainer
        print(("    shown=%s  DelveModifiersWidgetContainer=%s")
            :format(shown, tostring(mc ~= nil)))
        if mc then
            -- widgetFrames is a plain table: pairs() is a table read, no widget call.
            local wf = mc.widgetFrames
            local n = 0
            if type(wf) == "table" then for _ in pairs(wf) do n = n + 1 end end
            print(("    widgetFrames=%s count=%d"):format(type(wf), n))
            if type(wf) == "table" then
                for id, wframe in pairs(wf) do
                    -- The spell frame is under .Spell on a SpellDisplay widget; fall back to
                    -- the frame itself in case a different widget type is in use here.
                    -- ⚠ named wframe, not frame: `frame` is an upvalue in this file.
                    local sf = wframe and (wframe.Spell or wframe)
                    local info = sf and sf.spellInfo
                    print(("    widget id=%s  hasSpell=%s stackDisplay=%s spellID=%s")
                        :format(tostring(id), tostring(wframe and wframe.Spell ~= nil),
                                tostring(info and info.stackDisplay),
                                tostring(info and info.spellID)))
                    if sf then
                        local iw, ih = 0, 0
                        if sf.Icon then
                            local okg, a, b = pcall(function()
                                return sf.Icon:GetWidth(), sf.Icon:GetHeight()
                            end)
                            if okg then iw, ih = a or 0, b or 0 end
                        end
                        local ab = "n/a"
                        if sf.AmountBorder then
                            local okab, v = pcall(sf.AmountBorder.IsShown, sf.AmountBorder)
                            if okab then ab = tostring(v) end
                        end
                        print(("        Icon %.0fx%.0f  amountBorderShown=%s")
                            :format(iw, ih, ab))
                        DelveDumpSpellFrame("        ", sf)
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    --  PATH 2 — SHAPE SWEEP (backstop)
    --
    --  Retained even though PATH 1 is authoritative, because it is the only thing that
    --  would notice Blizzard MOVING the count somewhere else. Signature widened in
    --  v1.14.12 from SpellContainer to StackCount/SpellContainer/widgetFrames, and the
    --  deepest depth reached is now reported so a cap miss is visible rather than silent.
    ----------------------------------------------------------------
    local out, stats = {}, { visited = 0, forbidden = 0, deepest = 0 }
    DelvePlacardSweep(_G.UIParent, 0, out, {}, stats)
    print(("  sweep: %d frames, deepest=%d (cap %d), %d forbidden, %d candidate(s)")
        :format(stats.visited, stats.deepest, DELVE_PLACARD_MAX_DEPTH,
                stats.forbidden, #out))
    if stats.deepest >= DELVE_PLACARD_MAX_DEPTH then
        print("    ⚠ hit the depth cap — something may lie deeper and be unreported.")
    end
    for i = 1, #out do
        local rec = out[i]
        local w = rec.frame
        local nm = "<unnamed>"
        if w.GetName then
            local okn, nn = pcall(w.GetName, w)
            if okn and nn then nm = nn end
        end
        local vis = "?"
        local okv, v = pcall(w.IsVisible, w)
        if okv then vis = tostring(v) end
        print(("   [%d] %s  matched=%s depth=%d visible=%s")
            :format(i, nm, rec.why, rec.depth, vis))
        -- Only a StackCount match is directly measurable here; the other two shapes are
        -- reported so their existence is known, and PATH 1 covers the placard properly.
        if rec.why == "StackCount" then
            DelveDumpSpellFrame("        ", w)
        end
    end
end

local function DumpDelveProbe()
    local tracker = _G.ScenarioObjectiveTracker
    print("|cFF00CCFF[VeritasUI Delve probe]|r")
    print(("  ScenarioObjectiveTracker: %s   StageBlock: %s   WidgetContainer: %s")
        :format(tostring(tracker ~= nil),
                tostring(tracker and tracker.StageBlock ~= nil),
                tostring(tracker and tracker.StageBlock
                         and tracker.StageBlock.WidgetContainer ~= nil)))
    local hasDelve = C_DelvesUI and C_DelvesUI.HasActiveDelve
    if hasDelve then
        local ok, active = pcall(C_DelvesUI.HasActiveDelve)
        print("  C_DelvesUI.HasActiveDelve: " .. (ok and tostring(active) or "error"))
    else
        print("  C_DelvesUI.HasActiveDelve: absent")
    end

    -- Report ALL THREE widget containers by name. v1.12.15 searched only the
    -- StageBlock's and silently found nothing; had the probe printed this, the
    -- wrong-container bug would have been one photo instead of a release.
    if tracker then
        for _, path in ipairs({ "StageBlock", "TopWidgetContainerBlock", "BottomWidgetContainerBlock" }) do
            local blk = tracker[path]
            local wc  = blk and blk.WidgetContainer
            local n   = 0
            local hit = "no"
            if wc and wc.GetChildren then
                local kids = { wc:GetChildren() }
                n = #kids
                for i = 1, #kids do
                    if kids[i] and kids[i].SpellContainer then hit = "YES" end
                end
            end
            print(("  %-26s block=%s container=%s children=%d hasSpellContainer=%s")
                :format(path, tostring(blk ~= nil), tostring(wc ~= nil), n, hit))
        end
    end
    print("  cached widget: " .. tostring(delveCachedWidget ~= nil))

    local spells = DelveSpellFrames()
    if not spells then
        print("  No Delve plaque icons found — run this while inside a Delve.")
        print("  If you ARE in a Delve, the three lines above say which container holds it.")
        return
    end
    print(("  icons found: %d"):format(#spells))
    -- Atlases any icon-overlay treatment would need. Read from the live client
    -- rather than trusted from Blizzard's XML: the template says these exist, but
    -- an atlas that renders old art or has been renamed is exactly the trap the
    -- Midnight reagent-tier markers hit.
    for _, a in ipairs({ "common-icon-checkmark", "UI-Frame-IconMask" }) do
        -- ⚠ Namespace-guarded, NOT merely pcall'd: indexing a nil C_Texture raises
        -- before pcall can catch it, exactly like the C_Console trap. Reached via
        -- _G because this file does not localize C_Texture.
        local ai
        local ns = _G.C_Texture
        if ns and ns.GetAtlasInfo then
            local oka, r = pcall(ns.GetAtlasInfo, a)
            if oka then ai = r end
        end
        print(("  atlas %s: %s"):format(a,
            ai and ("%dx%d"):format(ai.width or 0, ai.height or 0) or "ABSENT"))
    end
    for i = 1, #spells do
        local info = spells[i] and spells[i].spellInfo
        if not info then
            print(("   [%d] no spellInfo on the frame"):format(i))
        else
            local desc = ""
            if C_Spell and C_Spell.GetSpellDescription and type(info.spellID) == "number" then
                local okd, d = pcall(C_Spell.GetSpellDescription, info.spellID)
                if okd and type(d) == "string" then desc = d end
            end
            print(("   [%d] spellID=%s stackDisplay=%s text=%q parsed=%s")
                :format(i, tostring(info.spellID), tostring(info.stackDisplay),
                        tostring(info.text or ""),
                        tostring(DelveParseRemaining(DelveCountText(info)))))
            print(("        tooltip=%q"):format(tostring(info.tooltip or ""):sub(1, 120)))
            -- The field the count actually comes from; see DelveCountText.
            print(("        spellDesc=%q"):format(desc:gsub("\n", " | "):sub(1, 200)))
        end

        -- Frame STRUCTURE, not widget data -- what an icon overlay could anchor to
        -- and mask against. Printed for every icon including the ones we reject: a
        -- missing parentKey means the live frames are not the template we read, and
        -- that is the single fact worth knowing before designing against it.
        local f = spells[i]
        if f then
            local iw, ih = 0, 0
            if f.Icon then
                local okg, w, h = pcall(function()
                    return f.Icon:GetWidth(), f.Icon:GetHeight()
                end)
                if okg then iw, ih = w or 0, h or 0 end
            end
            print(("        Icon=%s %.0fx%.0f  IconMask=%s CircleMask=%s EarnedCheck=%s Border=%s")
                :format(tostring(f.Icon ~= nil), iw, ih,
                        tostring(f.IconMask ~= nil), tostring(f.CircleMask ~= nil),
                        tostring(f.EarnedCheck ~= nil), tostring(f.Border ~= nil)))
            -- WHICH mask is live decides whether any overlay we add clips circular or
            -- square: Setup() shows exactly one, per iconDisplayType, and a hidden
            -- MaskTexture does not mask. Nothing we draw is masked any more (the scrim that
            -- was is gone), so this is retained purely as the measurement that would be
            -- needed AGAIN before adding any masked overlay -- attaching to the hidden one
            -- is what once made the scrim render square over a circular icon.
            local function shownOf(m)
                if not m then return "absent" end
                local oks, sh = pcall(function() return m:IsShown() end)
                return oks and tostring(sh) or "?"
            end
            print(("        mask shown: IconMask=%s CircleMask=%s  (exactly one should be true)")
                :format(shownOf(f.IconMask), shownOf(f.CircleMask)))
            -- Digit widths in the LIVE font. Informational now, not load-bearing: the count
            -- is corner-anchored, so its placement does not depend on any digit's width.
            --
            -- ⚠ RETAINED AS THE EPITAPH FOR CENTRING, because the reasoning that once lived
            -- here was wrong twice and could be re-derived by anyone tempted to centre the
            -- digit again. The original claim was that equal widths mean "one x offset suits
            -- every digit". Equal widths establish no such thing: a glyph's ink can sit off
            -- centre inside its own width when its side bearings differ, so a tabular font
            -- can report identical widths for 1 and 4 while 1 still reads right of centre --
            -- exactly what the owner observed (2026-08-07). And this dump cannot settle it
            -- either way: GetStringWidth and GetUnboundedStringWidth both report METRICS, and
            -- no accessor in the API exposes ink bounds, so equal numbers here are consistent
            -- with a centred glyph AND an off-centre one. That is why centring was abandoned
            -- rather than tuned further -- see DELVE_COUNT_INSET_X.
            local cfs = f._vuiNemesisCount
            if cfs and cfs.GetStringWidth then
                local saved, widths = cfs:GetText(), {}
                for d = 0, 4 do
                    cfs:SetText(tostring(d))
                    local okw, w = pcall(cfs.GetStringWidth, cfs)
                    widths[#widths + 1] =
                        ("%d=%s"):format(d, okw and ("%.1f"):format(w or 0) or "?")
                end
                cfs:SetText(saved)
                print("        digit widths: " .. table.concat(widths, " "))
                -- The actual rendered font, so "what size is the number" is answerable
                -- from the client instead of inferred from the font object we copied.
                local okg2, gfile, gsize, gflags = pcall(cfs.GetFont, cfs)
                if okg2 then
                    print(("        font: %s %s %s  (Blizzard base %s %+d)")
                        :format(tostring(gfile), tostring(gsize), tostring(gflags),
                                tostring(cfs._vuiBaseSize),
                                (db and tonumber(db.delveFontDelta)) or 0))
                end
                -- The count's rect against the icon's, which is what makes a placement
                -- complaint diagnosable instead of a matter of opinion. justify is dumped
                -- too and BOTH SHOULD READ AS BLIZZARD'S DEFAULTS: we deliberately set
                -- neither any more, because a single corner anchor gives the string no width
                -- or height for justification to act on. If either ever reads as something
                -- we set, someone has reintroduced the centring apparatus -- see
                -- DelveAnchorCount.
                local function num(v)
                    return (type(v) == "number") and ("%.1f"):format(v) or tostring(v)
                end
                local function rect(o, label)
                    if not o then print(("        %s: absent"):format(label)); return end
                    local okr, w, h, l, t = pcall(function()
                        return o:GetWidth(), o:GetHeight(), o:GetLeft(), o:GetTop()
                    end)
                    if okr then
                        print(("        %s: w=%s h=%s left=%s top=%s")
                            :format(label, num(w), num(h), num(l), num(t)))
                    else
                        print(("        %s: unreadable"):format(label))
                    end
                end
                local okj, jh = pcall(cfs.GetJustifyH, cfs)
                local okv, jv = pcall(cfs.GetJustifyV, cfs)
                print(("        justify: H=%s V=%s")
                    :format(okj and tostring(jh) or "?", okv and tostring(jv) or "?"))
                rect(cfs, "count rect")
                rect(f.Icon, "icon  rect")
                local oksh, sh = pcall(cfs.GetStringHeight, cfs)
                print(("        stringHeight=%s  (line box; digits do not use the descent)")
                    :format(oksh and num(sh) or "?"))
                -- Every live cosmetic knob in one place, so "what is it set to" is answered
                -- from the client rather than from the saved-variables file.
                -- ⚠ The shipped defaults are FORMATTED FROM THE CONSTANTS, never written as
                -- literals. This line read "[default -1/-1, digit 1 at 1]" while the shipped
                -- digit-1 default was 3: v1.13.4 changed the value in the two places that
                -- affect rendering and missed this third copy, so the one tool whose whole
                -- job is answering "what is this set to" reported a wrong default. A literal
                -- here cannot be kept in sync by hand -- do not reintroduce one.
                print(("        insets from icon BOTTOMRIGHT: y=%s x=%s  x(digit 1)=%s"
                       .. "  applied=(%s,%s)   [default %s/%s, digit 1 at %s]")
                    :format(num(db and db.delveCountInsetY),
                            num(db and db.delveCountInsetX),
                            num(db and db.delveCountInsetX1),
                            num(cfs._vuiInsetX), num(cfs._vuiInsetY),
                            num(DELVE_COUNT_INSET_Y), num(DELVE_COUNT_INSET_X),
                            num(DELVE_COUNT_INSET_X_BY_COUNT[1])))
            end
            local cchk = f._vuiNemesisCheck
            print(("        check outset: %s  applied=%s  (texture %s)")
                :format(tostring((db and db.delveCheckOutset) or DELVE_CHECK_OUTSET),
                        tostring(cchk and cchk._vuiOutset),
                        cchk and "created" or "not yet created"))
        end
    end
end

-- ── Options Panel ───────────────────────────────────────────
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local function AddCheckbox(key, name, tip, onChange)
        local setting = Settings.RegisterAddOnSetting(
            category, ADDON_NAME .. "_" .. key, key,
            db, type(UNIVERSAL[key]), name, UNIVERSAL[key])   -- ACCOUNT table: every
        setting:SetValueChangedCallback(function(_, value)
            -- Live variant: every QoL toggle applies mid-session (v1.6.28
            -- pattern) — the old PrintOnOff instructed a needless /reload.
            VUI.PrintOnOffLive("Quality of Life", name, value)
            if onChange then onChange(value) end
        end)
        Settings.CreateCheckbox(category, setting, tip)
    end

    AddCheckbox("showMinimapCoords", "Show Minimap Coordinates",
        "Displays your current coordinates directly below the minimap. Hidden automatically in dungeons, raids, and other areas without a position.",
        function(value)
            if value then
                if not miniCoordsSetup then SetupMinimapCoordinates()
                elseif miniCoordsFrame then miniCoordsFrame:Show() end
            else
                if miniCoordsFrame then miniCoordsFrame:Hide() end
            end
        end)

    AddCheckbox("showItemLevels", "Show Item Levels",
        "Displays item level numbers on equipment in bags, bank, character panel, and merchants. Quest rewards are excluded.",
        function(value)
            -- Live-apply BOTH ways. Enable-only was the bug: the module's stated contract is
            -- that every QoL toggle applies mid-session, and this one needed a /reload to take
            -- effect in the off direction. Mirrors showMinimapCoords directly above.
            if value then
                SetupItemLevels()
            elseif HideAllItemLevelOverlays then
                HideAllItemLevelOverlays()
            end
        end)

    -- Mid-session enable: MERCHANT_SHOW/CLOSED are registered at PLAYER_LOGIN
    -- only if a merchant feature was already on.  If BOTH were off at login,
    -- enabling one later did nothing until /reload — the only QoL toggle that
    -- violated the module's live-apply pattern.  RegisterEvent is idempotent,
    -- so registering again from the callback is safe; disable needs no
    -- unregister (the MERCHANT_SHOW handler gates on the db flags).
    local function EnsureMerchantEvents(value)
        if value then
            frame:RegisterEvent("MERCHANT_SHOW")
            frame:RegisterEvent("MERCHANT_CLOSED")
        end
    end

    AddCheckbox("autoSellJunk", "Auto Sell Junk",
        "Automatically sells all grey items when you visit a merchant.",
        EnsureMerchantEvents)

    AddCheckbox("autoRepair", "Auto Repair",
        "Automatically repairs all equipment at repair vendors. Funding source is selected below.",
        EnsureMerchantEvents)

    -- Repair Funding dropdown — appears directly below the Auto Repair checkbox.
    local repairSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_repairFunding",
        "repairFunding",
        -- ⚠ The ONLY per-character Settings control in this module. Every other setting here
        -- goes through AddCheckbox, which correctly targets the ACCOUNT table -- so unlike
        -- CleanSolo there is no mixed loop, just this one registration that must not use `db`.
        cdb,
        type(PERCHAR.repairFunding),
        "Repair Funding",
        PERCHAR.repairFunding
    )
    repairSetting:SetValueChangedCallback(function(_, value)
        local label = value == "guild" and "Guild + Personal" or "Personal Only"
        VUI.Print("Quality of Life", "Repair Funding: " .. label)
    end)
    local function GetRepairFundingOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("guild",    "Guild + Personal")
        container:Add("personal", "Personal Only")
        return container:GetData()
    end
    Settings.CreateDropdown(category, repairSetting, GetRepairFundingOptions,
        "How repair costs are funded. 'Guild + Personal' uses guild bank funds first (requires guild membership, guild repair permission, and guild info must not contain [noautorepair]), then covers any remainder with personal gold. 'Personal Only' always uses personal gold.")

    AddCheckbox("afkScreen", "AFK Screen",
        "Shows a cinematic overlay when you go AFK — your character name, level, item level, and zone over a slow camera orbit. Helps minimize OLED burn-in by hiding static UI elements and keeping the screen moving.",
        function(value)
            if value then AFK_StartPoll() end
        end)

    AddCheckbox("delveNemesisCount", "Show Delve Nemesis Count",
        "Shows how many Nemesis enemy groups are left directly on the icon on the Delve "
        .. "plaque, instead of only revealing it when you hover the icon. The count sits "
        .. "in the icon's lower-right corner, where the default UI puts a stack count, and "
        .. "is replaced by a checkmark once every group is defeated. Adjust the position with "
        .. "/qol delvenudge, the digit 1 relative to the others with /qol delveone, and the "
        .. "checkmark "
        .. "size with /qol delvecheck. Typeface and outline weight are /qol delveface and "
        .. "/qol delveoutline; /qol delveplacard measures the number Blizzard draws itself "
        .. "on the placard at a Delve entrance, for comparison.",
        function(value)
            if value then DelveStartCount() else DelveStopCount() end
        end)

    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

-- ── Events ──────────────────────────────────────────────────
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("USER_WAYPOINT_UPDATED")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
frame:RegisterEvent("PLAYER_STARTED_MOVING")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        -- Account table only: no identity yet, so cdb comes back nil. VUI.BindScopedDB replaces
        -- the hand-rolled seeding loop that used to live here -- that loop wrote EVERY default
        -- into the account root, which is the mechanism behind the pinning defect (audit D8), so
        -- it had to go rather than sit alongside the binder. It also deep-copies, where this loop
        -- assigned table defaults by reference.
        db = VUI.BindScopedDB("VeritasUI_QualityOfLifeDB", UNIVERSAL, PERCHAR)
        -- InitializeOptions moved to PLAYER_LOGIN: Settings.RegisterAddOnSetting
        -- captures the table it is handed, so it must receive the per-character
        -- slot, which does not exist yet here.
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Identity is available: bind BOTH tables. `db` is account-wide, so every universal
        -- read site below is unchanged; `cdb` holds repairFunding and afkUIDirty.
        db, cdb = VUI.BindScopedDB("VeritasUI_QualityOfLifeDB", UNIVERSAL, PERCHAR)

        -- ⚠ MUST run before any universal read below, or every feature acts on the pre-migration
        -- value for the whole session. Note MIGRATE_UNIVERSAL, not UNIVERSAL: the retired map-coordinate
        -- keys are absent from UNIVERSAL but must still be promoted, so RetireWorldMapCoords sees a
        -- pre-scope player's real choice.
        --
        -- THIS IS WHERE AUDIT FINDING D8 DISSOLVES. The Delve placement keys stop being
        -- per-character at all, so nothing can pin a stale copy of a shipped default ever again --
        -- and the digit-1 value confirmed in game at v1.13.4 finally reaches every character
        -- instead of only the one it was tuned on.
        local promoted = VUI.MigrateScopedDB("VeritasUI_QualityOfLifeDB", MIGRATE_UNIVERSAL,
                                             PERCHAR, "__vuiScopeMigrated")
        if promoted then
            local names = {}
            for k in pairs(promoted) do names[#names + 1] = k end
            table.sort(names)
            VUI.Print("Quality of Life", "settings now shared across characters: "
                .. table.concat(names, ", ") .. "  (taken from this character)")
        end
        -- Drop every superseded Delve key. Each measured the count's position from an
        -- origin that no longer exists -- delveCountOffsetY from the icon's bottom edge,
        -- then delveCountCenterY/X from its centre. delveCountCenterX1 was the centred design's
        -- per-glyph correction; its replacement is delveCountInsetX1, in corner-inset units,
        -- so the old key must go for the same reason as the others. Keeping any of
        -- them would be a silent lie about where the number is: a stored "6 right of centre"
        -- is a completely different place read as "6 in from the right edge". delveTintAlpha
        -- goes too -- the scrim it controlled no longer exists. Same self-clean the AH
        -- module does for its orphaned db.shopping.
        db.delveCountOffsetY  = nil
        db.delveCountCenterY  = nil
        db.delveCountCenterX  = nil
        db.delveCountCenterX1 = nil
        db.delveTintAlpha     = nil
        InitializeOptions()
        -- Belt-and-suspenders: if we crashed or disconnected while the AFK
        -- screen was up, UIParent alpha and MinimapCluster are left hidden.
        -- Gated on the persisted dirty flag rather than run unconditionally:
        -- UIParent:SetAlpha(1) genuinely is a no-op at the default, but
        -- MinimapCluster:Show() is not — running it on every login un-hid a
        -- minimap that another addon or an Edit Mode layout had deliberately
        -- hidden, which is precisely what AFK_Exit goes out of its way to avoid.
        if cdb and cdb.afkUIDirty then
            UIParent:SetAlpha(1)
            if MinimapCluster then MinimapCluster:Show() end
            cdb.afkUIDirty = false
        end

        if db.showItemLevels then SetupItemLevels()     end
        RetireWorldMapCoords()
        if db.showMinimapCoords then SetupMinimapCoordinates() end

        if db.autoSellJunk or db.autoRepair then
            self:RegisterEvent("MERCHANT_SHOW")
            self:RegisterEvent("MERCHANT_CLOSED")
        end

        if db.afkScreen then AFK_StartPoll() end

        -- Starts unconditionally when enabled: the ticker's own body is cheap and
        -- early-outs unless a Delve plaque is on screen, so there is nothing to
        -- register or unregister on zone changes.
        if db.delveNemesisCount then DelveStartCount() end

        -- Register /way only if TomTom is absent; both addons claim this command.
        if not (_G.TomTom or (IsAddOnLoaded and IsAddOnLoaded("TomTom"))) then
            SLASH_VERITASUI_WAY1 = "/way"
            SlashCmdList["VERITASUI_WAY"] = WayCommand
        else
            VUI.Print("Quality of Life",
                "TomTom detected — |cFFFFFF00/way|r is handled by TomTom.")
        end

        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("Quality of Life", format("v%s loaded — |cFFFFFF00/qol|r", VUI.VERSION))

    elseif event == "PLAYER_LOGOUT" then
        -- Ensure UI is fully restored before the client saves frame state.
        AFK_Exit()

    elseif event == "MERCHANT_SHOW" then
        -- Defer one frame so MerchantFrame is fully shown before we
        -- check repair capability or scan bags.  MERCHANT_SHOW fires
        -- before Blizzard's MerchantFrame_OnShow handler runs.
        --
        -- AutoRepair and AutoSellJunk are fully independent — neither
        -- depends on the other.  This matters at repair-only vendors
        -- such as Delver's Supplies crates in Delves, where Blizzard
        -- disables item sales entirely; AutoRepair must still fire.
        -- Same pattern as Scrap (Button:OnMerchant in
        -- jaliborc/Scrap addons/merchant/button.lua).
        --
        -- GET_ITEM_INFO_RECEIVED is registered only for the merchant visit:
        -- it fires far too often to listen to globally, and it's only needed
        -- to catch greys whose item data was cold when ScanJunk ran.
        if db.autoSellJunk then
            self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        end
        C_Timer.After(0, function()
            if db.autoRepair   then AutoRepair()  end
            if db.autoSellJunk then AutoSellJunk() end
        end)

    elseif event == "MERCHANT_CLOSED" then
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        CancelColdSellRetry()
        wipe(sellPending)
        if saleTotal then ResetSellState() end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- arg1 = itemID whose record just arrived. Only react to itemIDs
        -- flagged as cold-cache misses by ScanJunk, and only while idle —
        -- see ScheduleColdSellRetry for the mid-sale guard rationale.
        if arg1 and sellPending[arg1] then
            sellPending[arg1] = nil
            if not saleTotal then ScheduleColdSellRetry() end
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        CancelSellRetry()
        SellNextBatch()
        ScheduleSellRetry()

    elseif event == "PLAYER_FLAGS_CHANGED" then
        -- arg1 is the unit whose flags changed; ignore non-player units.
        -- Note: idle-timeout AFK can fire with arg1=nil (server-originated),
        -- so treat nil as "self" and only bail on an explicit other-unit token.
        if arg1 and arg1 ~= "player" then return end
        -- UnitIsAFK can return a Secret Value under Midnight's
        -- ChatMessagingLockdown restriction.  Guard with pcall +
        -- issecretvalue (added in 12.0.0) to guarantee we get a real bool.
        local ok, afk = pcall(UnitIsAFK, "player")
        if not ok or (issecretvalue and issecretvalue(afk)) then
            afk = nil -- treat as unknown; fallback poll will catch it
        end
        if afk then
            AFK_Enter()
        elseif afk == false then
            AFK_Exit()
        end

    elseif event == "PLAYER_STARTED_MOVING" then
        -- Fast path: PLAYER_FLAGS_CHANGED depends on a server round-trip
        -- confirming the AFK flag cleared, which is why dismissal felt
        -- sometimes instant and sometimes several-seconds-late (up to the
        -- 5s fallback poll interval) — the round-trip time varies with
        -- latency/server load. Movement is detected client-side the moment
        -- it happens, so drop the overlay immediately without waiting for
        -- the server to confirm. Not keyboard capture (no EnableKeyboard
        -- on the frame), so this doesn't touch the combat-protection issue
        -- that got the old OnKeyDown handler removed in v1.9.2.
        if afkActive then AFK_Exit() end

    elseif event == "USER_WAYPOINT_UPDATED" then
        -- Fired when the waypoint is cleared externally (e.g. map right-click UI).
        if not C_Map.HasUserWaypoint() then
            StopWaypointTracking()
        end
    end
end)

-- ── Slash commands ──────────────────────────────────────────
----------------------------------------------------------------
--  /qol ilvl — item-level source comparison (diagnostic)
--
--  Answers one question with measurement instead of argument: when the tooltip
--  and the icon disagree (reported 2026-07-28: a Timewalking item whose tooltip
--  read 120 while the overlay read 78), WHICH source is right, and can we afford
--  to use the tooltip one?
--
--  GetDetailedItemLevelInfo answers "what is this item's level", from the item
--  record plus the link's upgrade/bonus data. The tooltip answers "what is this
--  item's level FOR ME, RIGHT NOW". For ordinary current-content gear the two
--  agree, which is why those numbers have always looked correct. They diverge
--  wherever the displayed level depends on context the link does not carry —
--  Timewalking scaling, heirlooms, level-scaled loot.
--
--  So this dumps both, side by side, plus C_TooltipInfo's answer (the modern
--  structured tooltip-data API — reading the tooltip without showing one) and
--  the cost of that call, since it would have to run across ~200 bank slots.
--  RETAINED as a permanent diagnostic (v1.9.17), not removed after answering its
--  original question. Two reasons: "this number looks wrong" recurs in this
--  feature by nature, since the correct source is only knowable by comparison
--  against the tooltip; and the suite already keeps equivalent permanent probes
--  (/ah check, /ah find, /ah diag). It reads nothing and changes nothing.
----------------------------------------------------------------
local function DumpIlvlDiag(link)
    local TAG = "Quality of Life"
    if not link or link == "" then
        VUI.Print(TAG, "Usage: |cFFFFFF00/qol ilvl|r then SHIFT-CLICK an item into the chat box.")
        VUI.Print(TAG, "  Compares the overlay's item-level source against the tooltip's.")
        return
    end
    VUI.Print(TAG, "Item-level sources for " .. link .. ":")
    -- Body lines raw-print for clean copy-paste (suite print-split policy).
    local okI, itemID, _, _, equipLoc, _, classID, subClassID =
        pcall(C_Item.GetItemInfoInstant, link)
    print(("   itemID = %s   class/subclass = %s/%s   equipLoc = %s"):format(
        tostring(okI and itemID), tostring(okI and classID),
        tostring(okI and subClassID), tostring(okI and equipLoc)))

    local okQ, _, _, quality = pcall(C_Item.GetItemInfo, link)
    print(("   quality = %s"):format(tostring(okQ and quality)))

    -- The comparison that matters: link (effective) vs bare itemID (base).
    local okL, byLink = pcall(C_Item.GetDetailedItemLevelInfo, link)
    print(("   GetDetailedItemLevelInfo(link)   = %s   <- WRONG on scaling items (ceiling)"):format(
        tostring(okL and byLink)))
    if okI and itemID then
        local okD, byID = pcall(C_Item.GetDetailedItemLevelInfo, itemID)
        print(("   GetDetailedItemLevelInfo(itemID) = %s   <- base only"):format(
            tostring(okD and byID)))
    end
    local okG, _, _, _, giLvl = pcall(C_Item.GetItemInfo, link)
    print(("   GetItemInfo ilvl (index 4)       = %s   <- what the overlay uses"):format(
        tostring(okG and giLvl)))

    print(("   IsCosmeticItem = %s   (API present: %s)"):format(
        tostring(C_Item and C_Item.IsCosmeticItem
            and select(2, pcall(C_Item.IsCosmeticItem, link))),
        tostring(C_Item and C_Item.IsCosmeticItem ~= nil)))

    -- Tooltip route.
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
        print("   C_TooltipInfo.GetHyperlink = ABSENT on this client")
        return
    end
    local okT, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not okT or not data then
        print("   C_TooltipInfo.GetHyperlink returned nothing")
        return
    end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, data)
    end
    local lines = data.lines or {}
    -- Build the match pattern from the LOCALIZED global rather than a literal.
    local pat = type(ITEM_LEVEL) == "string"
        and ITEM_LEVEL:gsub("%%d", "(%%d+)") or "Item Level (%d+)"
    local found
    for _, line in ipairs(lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            pcall(TooltipUtil.SurfaceArgs, line)
        end
        local t = line.leftText
        if type(t) == "string" then
            local n = t:match(pat) or t:match("[Ii]tem [Ll]evel%s*(%d+)")
            if n and not found then found = n end
        end
    end
    print(("   C_TooltipInfo item level = %s   <- what the TOOLTIP shows (%d lines)"):format(
        tostring(found), #lines))

    -- Cost: is this affordable across a full bank + warband bank?
    if debugprofilestop then
        local t0 = debugprofilestop()
        for _ = 1, 50 do pcall(C_TooltipInfo.GetHyperlink, link) end
        local per = (debugprofilestop() - t0) / 50
        print(("   cost = %.3f ms/call  ->  ~%.1f ms for 200 slots"):format(per, per * 200))
    end
end

----------------------------------------------------------------
--  Slash commands
----------------------------------------------------------------
SLASH_VERITASUI_QOL1 = "/qol"
SLASH_VERITASUI_QOL2 = "/qualityoflife"
SlashCmdList["VERITASUI_QOL"] = function(msg)
    local arg = (msg and strtrim(msg)) or ""
    local ntail = arg:lower():match("^delvenudge%s*(.*)$")
    if ntail then
        -- Guarded: these branches return before the handler's own db nil-check below,
        -- and a /qol delvenudge typed during the login burst would otherwise index nil.
        --
        -- ⚠ UNITS CHANGED 2026-08-07. These are insets from the icon's BOTTOM-RIGHT
        -- CORNER now (in from the right, up from the bottom), not offsets from its centre.
        -- Argument ORDER is unchanged (vertical first) so the muscle memory still works.
        local ny, nx = ntail:match("^(-?%d+)%s+(-?%d+)$")
        if not ny then ny = ntail:match("^(-?%d+)$") end
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif not ny then
            VUI.Print("Quality of Life", format(
                "Delve count sits |cFFFFFF00%d|r px up from the icon's bottom edge and "
                .. "|cFFFFFF00%d|r px in from its right edge. "
                .. "|cFFFFFF00/qol delvenudge <up> [left]|r to change it "
                .. "(negatives push it outside the icon).",
                tonumber(db.delveCountInsetY) or DELVE_COUNT_INSET_Y,
                tonumber(db.delveCountInsetX) or DELVE_COUNT_INSET_X))
        else
            db.delveCountInsetY = tonumber(ny)
            if nx then db.delveCountInsetX = tonumber(nx) end
            -- Applies on the next poll tick (<=0.5s) with no reload: the anchor
            -- helper re-anchors as soon as it sees a different value.
            VUI.Print("Quality of Life", format(
                "Delve count set to |cFFFFFF00%d|r px up, |cFFFFFF00%d|r px in from the "
                .. "icon's bottom-right corner.",
                db.delveCountInsetY,
                tonumber(db.delveCountInsetX) or DELVE_COUNT_INSET_X))
        end
        return
    end
    local fsize = arg:lower():match("^delvesize%s*(-?%d*)")
    if fsize then
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif fsize == "" then
            VUI.Print("Quality of Life", format(
                "Delve count font is Blizzard's size |cFFFFFF00%+d|r. "
                .. "|cFFFFFF00/qol delvesize <n>|r to change it (0 = Blizzard's own size). "
                .. "Run |cFFFFFF00/qol delve|r to see the resulting pixel size.",
                tonumber(db.delveFontDelta) or 0))
        else
            -- Clamped to a sane band: the number has to stay inside a 24px circle, and a
            -- huge value would render as a blob rather than look like a mistake.
            local v = tonumber(fsize) or 0
            if v < -6 then v = -6 elseif v > 6 then v = 6 end
            db.delveFontDelta = v
            VUI.Print("Quality of Life", format(
                "Delve count font set to Blizzard's size |cFFFFFF00%+d|r.", v))
        end
        return
    end
    -- ⚠ MUST be matched before the bare "^delve" probe fallback below, which would
    -- otherwise swallow it and dump the probe instead.
    local chk = arg:lower():match("^delvecheck%s*(-?%d*)")
    if chk then
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif chk == "" then
            VUI.Print("Quality of Life", format(
                "Delve checkmark extends |cFFFFFF00%+d|r px past the icon. "
                .. "|cFFFFFF00/qol delvecheck <n>|r to change it "
                .. "(0 = flush with the icon, negatives shrink it further).",
                tonumber(db.delveCheckOutset) or DELVE_CHECK_OUTSET))
        else
            -- Clamped, not rejected, for the same reason delvesize is: the intent of an
            -- out-of-range number is obvious, and doing nothing would read as a bug. The
            -- band keeps it recognisable as a checkmark on a 24px icon.
            local v = tonumber(chk) or DELVE_CHECK_OUTSET
            if v < -8 then v = -8 elseif v > 8 then v = 8 end
            db.delveCheckOutset = v
            VUI.Print("Quality of Life", format(
                "Delve checkmark outset set to |cFFFFFF00%+d|r px.", v))
        end
        return
    end
    local one = arg:lower():match("^delveone%s*(-?%d*)")
    if one then
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif one == "" then
            -- ⚠ Reports a DELTA and the resulting absolute, since v1.14.14. The old wording
            -- said "sits N px in from the right edge", which described the absolute semantics
            -- and is now wrong -- and a stale help string is how a user learns the wrong model.
            local g  = tonumber(db.delveCountInsetX) or DELVE_COUNT_INSET_X
            local d1 = tonumber(db.delveCountInsetX1) or DELVE_COUNT_INSET_X_BY_COUNT[1] or 0
            VUI.Print("Quality of Life", format(
                "The digit |cFFFFFF001|r is nudged |cFFFFFF00%+d|r px relative to the other "
                .. "digits, so it sits at |cFFFFFF00%d|r px in while they sit at "
                .. "|cFFFFFF00%d|r. |cFFFFFF000|r means no correction. "
                .. "|cFFFFFF00/qol delveone <n>|r to change it. Only the horizontal axis: "
                .. "digits share a baseline, so the vertical never differs.",
                d1, g + d1, g))
        else
            db.delveCountInsetX1 = tonumber(one) or 0
            -- Worded as the status line above words it: a DELTA relative to the other digits.
            -- The old "N px in from the right edge" described the pre-v1.14.14 absolute model.
            local g = tonumber(db.delveCountInsetX) or DELVE_COUNT_INSET_X
            VUI.Print("Quality of Life", format(
                "The digit |cFFFFFF001|r is now nudged |cFFFFFF00%+d|r px relative to the other "
                .. "digits (|cFFFFFF00%d|r px in).", db.delveCountInsetX1, g + db.delveCountInsetX1))
        end
        return
    end
    -- ⚠⚠ ORDERING: every `delve*` subcommand MUST be matched BEFORE the `^delve` catch-all
    -- below, which is a PREFIX match and would otherwise swallow it into the old probe.
    -- Adding one after that line makes it silently run the wrong command.
    local dface = arg:lower():match("^delveface%s*(%a*)$")
    if dface then
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif dface == "" then
            VUI.Print("Quality of Life", format(
                "Delve count typeface is |cFFFFFF00%s|r. |cFFFFFF00/qol delveface "
                .. "blizzard|r uses the face Blizzard draws its own count in (ARIALN, from "
                .. "NumberFontNormal); |cFFFFFF00/qol delveface plaque|r uses the plaque's "
                .. "own face (Friz Quadrata). Applies within half a second, no reload.",
                tostring(db.delveCountFace)))
        elseif dface ~= "blizzard" and dface ~= "plaque" then
            VUI.Print("Quality of Life",
                "Use |cFFFFFF00/qol delveface blizzard|r or |cFFFFFF00/qol delveface plaque|r.")
        else
            db.delveCountFace = dface
            VUI.Print("Quality of Life", format(
                "Delve count typeface set to |cFFFFFF00%s|r.", dface))
        end
        return
    end
    local doutline = arg:lower():match("^delveoutline%s*(%a*)$")
    if doutline then
        -- Typed as friendly words, stored as the literal SetFont flag so nothing has to map
        -- it at draw time. WoW has NO bold flag -- the outline IS the weight control.
        local OUTLINE_MAP = { thick = "THICKOUTLINE", normal = "OUTLINE", none = "NONE" }
        local OUTLINE_REV = { THICKOUTLINE = "thick", OUTLINE = "normal", NONE = "none" }
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif doutline == "" then
            VUI.Print("Quality of Life", format(
                "Delve count outline is |cFFFFFF00%s|r. |cFFFFFF00/qol delveoutline "
                .. "thick|normal|none|r — |cFFFFFF00normal|r is what Blizzard's own count "
                .. "uses (NumberFont_Outline_Med declares outline=\"NORMAL\").",
                tostring(OUTLINE_REV[db.delveCountOutline] or db.delveCountOutline)))
        elseif not OUTLINE_MAP[doutline] then
            VUI.Print("Quality of Life",
                "Use |cFFFFFF00thick|r, |cFFFFFF00normal|r or |cFFFFFF00none|r.")
        else
            db.delveCountOutline = OUTLINE_MAP[doutline]
            VUI.Print("Quality of Life", format(
                "Delve count outline set to |cFFFFFF00%s|r.", doutline))
        end
        return
    end
    if arg:lower():match("^delveplacard") then
        DumpDelvePlacardProbe()
        return
    end
    if arg:lower():match("^delve") then
        DumpDelveProbe()
        return
    end
    if arg:lower():match("^ilvl") then
        -- Accept a shift-clicked item link, matching /ah check's pattern.
        DumpIlvlDiag(arg:match("(|c%x+|H.-|h.-|h|r)") or arg:match("(|H.-|h)"))
        return
    end
    -- Guard against nil (options init not yet run, or failed) — same
    -- "still loading" pattern as PriorityRotation / ZoneQuests / AH.
    if settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    else
        VUI.Print("Quality of Life",
            "Settings are still loading — try again in a moment.")
    end
end

-- ── /way — TomTom-compatible waypoint command ────────────────
-- Registered at PLAYER_LOGIN to detect TomTom conflicts; see PLAYER_LOGIN handler.
-- Supported formats (mirrors TomTom syntax):
--   /way #2351 45.2 56.3              -- explicit map ID
--   /way #2351 45.2 56.3 Some Label   -- with optional label
--   /way 45.2 56.3                    -- current zone
--   /way 45.2 56.3 Some Label         -- current zone with label
--   /way clear                        -- remove waypoint
--
-- Uses Blizzard's native user-waypoint APIs so the pin appears on
-- the World Map and the minimap arrow activates automatically
-- (same behaviour as right-clicking the map and choosing "Set Waypoint").
WayCommand = function(msg)
    msg = strtrim(msg or ""):gsub(",", ".")

    -- ── Clear ──────────────────────────────────────────────
    if msg:lower() == "clear" or msg == "" then
        if C_Map.HasUserWaypoint() then
            C_Map.ClearUserWaypoint()
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
            StopWaypointTracking()
            VUI.Print("Quality of Life", "Waypoint cleared.")
        else
            VUI.Print("Quality of Life", "No waypoint is set.")
        end
        return
    end

    -- ── Parse: /way #mapID x y [label] ────────────────────
    local mapID, x, y, label
    local mID, mX, mY, mLabel = msg:match("^#(%d+)%s+(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.*)")
    if mID then
        mapID = tonumber(mID)
        x     = tonumber(mX)
        y     = tonumber(mY)
        label = strtrim(mLabel or "")
    else
        -- ── Parse: /way x y [label] ───────────────────────
        local cX, cY, cLabel = msg:match("^(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.*)")
        if cX then
            mapID = C_Map.GetBestMapForUnit("player")
            x     = tonumber(cX)
            y     = tonumber(cY)
            label = strtrim(cLabel or "")
        end
    end

    if not (mapID and x and y) then
        VUI.Print("Quality of Life",
            "Usage: |cFFFFFF00/way #mapID x y|r or |cFFFFFF00/way x y|r  "
            .. "(coordinates must be positive 0–100, e.g. |cFFFFFF00/way #2351 45.2 56.3|r)  —  "
            .. "|cFFFFFF00/way clear|r to remove.")
        return
    end

    -- Validate map ID exists.
    local mapInfo = C_Map.GetMapInfo(mapID)
    if not mapInfo then
        VUI.Print("Quality of Life",
            format("Unknown map ID |cFFFFFF00%d|r.", mapID))
        return
    end

    -- Coordinates are in 0-100 scale; WoW API expects 0-1.
    local nx, ny = x / 100, y / 100
    if nx < 0 or nx > 1 or ny < 0 or ny > 1 then
        VUI.Print("Quality of Life", "Coordinates must be between 0 and 100.")
        return
    end

    -- Set the native Blizzard user waypoint. Both checks are the ones Blizzard's own /mappin
    -- makes (WaypointLocationDataProvider.lua:214-220): some maps refuse pins, and the set
    -- itself reports whether it happened. Without them /way announced a waypoint that did
    -- not exist and started the arrival ticker for it (audit Q2).
    local invalid = MAP_PIN_INVALID_MAP or "Map pins cannot be placed on this map."
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        VUI.Print("Quality of Life", invalid)
        return
    end
    local mapPoint = UiMapPoint.CreateFromVector2D(mapID, CreateVector2D(nx, ny))
    if not C_Map.SetUserWaypoint(mapPoint) then
        VUI.Print("Quality of Life", invalid)
        return
    end
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    StartWaypointTracking()

    -- Build confirmation message.
    local zoneName = mapInfo.name or ("Map " .. mapID)
    local desc = (label ~= "") and format(" |cFFCCCCCC(%s)|r", label) or ""
    VUI.Print("Quality of Life",
        format("Waypoint set: |cFFFFD200%s|r — |cFF00FF00%.1f, %.1f|r%s",
            zoneName, x, y, desc))
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_QualityOfLife_OnAddonCompartmentClick()
    C_Timer.After(0, function()
        if settingsCategoryID then Settings.OpenToCategory(settingsCategoryID) end
    end)
end
