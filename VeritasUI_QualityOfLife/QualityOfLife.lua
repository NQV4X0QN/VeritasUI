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

local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Defaults & state
----------------------------------------------------------------
local defaults = {
    autoSellJunk   = true,
    autoRepair     = true,
    repairFunding  = "guild",   -- "guild" = Guild + Personal; "personal" = Personal Only
    showItemLevels = true,
    showMapCoords  = true,
    afkScreen      = true,
    -- Paints the Nemesis groups-remaining count on the Delve plaque icon that
    -- otherwise only reveals it on hover, and a checkmark once all groups are down.
    delveNemesisCount = true,
    -- Vertical offset of the Delve count from the icon's CENTRE, in pixels DOWN.
    -- Persisted and live-nudgeable via /qol delvenudge, because dialling a cosmetic
    -- pixel offset through screenshot round-trips is slow and imprecise -- the captures
    -- arrive at different crops and scales, so they cannot be measured against each
    -- other.
    --
    -- ⚠ Replaces delveCountOffsetY, which measured from the icon's BOTTOM EDGE. Same
    -- purpose, different origin; see DELVE_COUNT_CENTER_Y for why the old key is
    -- dropped rather than reinterpreted.
    delveCountCenterY = 1,
    -- Horizontal nudge from the icon's centre, in pixels RIGHT. Live via
    -- /qol delvenudge <y> <x>.
    delveCountCenterX = 1,
    -- Darkness of the circular scrim behind the count, percent 0-100. Live via
    -- /qol delvetint, for the same reason the offset is.
    delveTintAlpha = 60,
    -- Points added to Blizzard's number font for the count. Live via /qol delvesize.
    delveFontDelta = 0,
    -- Set while the AFK overlay has the UI hidden, cleared when it restores it.
    -- Persisted so a crash or disconnect during AFK can be recovered at the next
    -- PLAYER_LOGIN without force-restoring the UI on every ordinary login.
    afkUIDirty     = false,
}

local db
local settingsCategoryID
local frame = CreateFrame("Frame")

local itemLevelsSetup   = false  -- guards SetupItemLevels() re-entry
local coordsInitialized = false  -- guards InitCoords() re-entry
local mapCoordsSetup    = false  -- guards SetupMapCoordinates() re-entry
local mapCoordsAnchor   = nil    -- reference for mid-session show/hide

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
            GetCoinTextureString(soldValue)))
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

    local useGuild = db.repairFunding ~= "personal"
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
                GetCoinTextureString(cost), GetCoinTextureString(guildPays)))
            return
        end

        RepairAllItems(true)              -- guild funds first
        if remainder > 0 then
            RepairAllItems(false)         -- personal gold covers the remainder
        end
        VUI.Print("Quality of Life", format(
            "Repaired for %s (guild bank)", GetCoinTextureString(cost)))
    else
        -- RepairAllItems silently no-ops when personal gold can't cover the
        -- bill, so an unconditional print would claim a repair that never
        -- happened. Synchronous read-once pre-check — no delta math, no
        -- PLAYER_MONEY listener (the v1.6.36 constraints are preserved).
        if GetMoney() < cost then
            VUI.Print("Quality of Life", format(
                "Can't repair — costs %s and you don't have enough gold.",
                GetCoinTextureString(cost)))
            return
        end
        RepairAllItems(false)
        VUI.Print("Quality of Life", format(
            "Repaired for %s", GetCoinTextureString(cost)))
    end
end

-- ── Feature: Show Item Levels ───────────────────────────────
-- Displays item level overlays on equippable gear in:
--   • Bags, bank, warband bank  (SetItemButtonQuality hook)
--   • Character panel           (SetItemButtonQuality hook)
--   • Merchant windows          (dedicated merchant scanner)
-- Quest reward buttons are explicitly excluded.
-- ─────────────────────────────────────────────────────────────
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
        if not db or not db.showItemLevels then return end
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

-- ── Feature: Map Coordinates ────────────────────────────────
-- Shows player and cursor coordinates side-by-side on the World Map.
-- No backdrop or border — just two fontstrings with a drop shadow.
-- Hides the quest log side panel toggle button.
-- Right-click toggles lock/unlock; left-drag repositions when unlocked.
-- When locked, the frame is mouse-transparent (map clicks pass through).
-- Handles WorldMapFrame being load-on-demand (Blizzard_WorldMap).
-- Gracefully shows "—" in instances or areas without position data.
local function SetupMapCoordinates()
    -- Own re-entry guard, matching SetupItemLevels. Distinct from
    -- coordsInitialized, which means "the anchor exists" and is only set once
    -- InitCoords actually runs. When Blizzard_WorldMap is not loaded yet this
    -- function creates an ADDON_LOADED loader frame and returns with
    -- coordsInitialized still false, so the settings toggle re-entered on
    -- exactly the condition that was still unmet and stacked another loader
    -- frame on every off/on cycle.
    if mapCoordsSetup then return end
    mapCoordsSetup = true

    local THROTTLE = 0.033   -- ~30 fps

    -- Normal colours
    local PLAYER_R, PLAYER_G, PLAYER_B = 1, 0.82, 0        -- gold
    local CURSOR_R, CURSOR_G, CURSOR_B = 0.75, 0.75, 0.75  -- light gray
    -- Unlocked-mode tint (cyan)
    local UNLOCK_R, UNLOCK_G, UNLOCK_B = 0.2, 0.8, 1.0

    local function InitCoords()
        if coordsInitialized then return end
        if not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
        coordsInitialized = true
        local container = WorldMapFrame.ScrollContainer

        -- Hide the quest log show/hide toggle button in the bottom-right.
        local toggle = WorldMapFrame.SidePanelToggle
        if toggle then VUI.SuppressFrame(toggle) end

        -- Invisible container button — no backdrop, no border, no tint.
        -- Must be a Button (not Frame) so RegisterForClicks works.
        local anchor = CreateFrame("Button", nil, container)
        mapCoordsAnchor = anchor
        anchor:SetSize(1, 1)  -- auto-sized by content; initial 1×1 is a placeholder
        anchor:SetFrameStrata("DIALOG")
        anchor:SetFrameLevel(container:GetFrameLevel() + 10)

        -- Restore saved position or default to bottom-right.
        local saved = db.mapCoordsPos
        if saved then
            anchor:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", saved.x, saved.y)
        else
            anchor:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 4)
        end

        -- ── Lock / unlock state ──
        local locked = true

        -- Always accept mouse input so right-click (un)lock works in
        -- either state.  Left-clicks pass through to the map because we
        -- only RegisterForClicks("RightButtonUp"), never LeftButton.
        anchor:EnableMouse(true)
        anchor:SetMovable(false)
        anchor:SetClampedToScreen(true)

        local function SavePosition()
            anchor:StopMovingOrSizing()
            local aScale = anchor:GetEffectiveScale()
            local cScale = container:GetEffectiveScale()
            if cScale == 0 then return end
            local x = ((anchor:GetLeft()   or 0) * aScale
                       - (container:GetLeft()   or 0) * cScale) / cScale
            local y = ((anchor:GetBottom() or 0) * aScale
                       - (container:GetBottom() or 0) * cScale) / cScale
            db.mapCoordsPos = { x = x, y = y }
            -- Re-anchor to the container immediately: StartMoving() silently
            -- re-anchors the frame to screen coordinates, so without this the
            -- coords stop tracking the map frame (move/rescale the windowed
            -- map and they float) until the next login. This is the exact
            -- restore path already used at init, applied live.
            anchor:ClearAllPoints()
            anchor:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, y)
        end

        -- Player coords (gold) — left side.
        local playerText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerText:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        playerText:SetJustifyH("LEFT")
        playerText:SetTextColor(PLAYER_R, PLAYER_G, PLAYER_B)
        playerText:SetShadowColor(0, 0, 0, 1)
        playerText:SetShadowOffset(1, -1)
        playerText:SetText("Player: —")

        -- Cursor coords (light gray) — right of player, separated by a gap.
        local mouseText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mouseText:SetPoint("LEFT", playerText, "RIGHT", 12, 0)
        mouseText:SetJustifyH("LEFT")
        mouseText:SetTextColor(CURSOR_R, CURSOR_G, CURSOR_B)
        mouseText:SetShadowColor(0, 0, 0, 1)
        mouseText:SetShadowOffset(1, -1)
        mouseText:SetText("Cursor: —")

        -- Resize the invisible hit frame to wrap both fontstrings.
        local function ResizeAnchor()
            local pw = playerText:GetStringWidth() or 0
            local mw = mouseText:GetStringWidth()  or 0
            local h  = playerText:GetStringHeight() or 14
            anchor:SetSize(pw + 12 + mw, h)
        end
        ResizeAnchor()

        local function SetTextColors(unlocked)
            if unlocked then
                playerText:SetTextColor(UNLOCK_R, UNLOCK_G, UNLOCK_B)
                mouseText:SetTextColor(UNLOCK_R, UNLOCK_G, UNLOCK_B)
            else
                playerText:SetTextColor(PLAYER_R, PLAYER_G, PLAYER_B)
                mouseText:SetTextColor(CURSOR_R, CURSOR_G, CURSOR_B)
            end
        end

        local function SetLocked(lock)
            locked = lock
            anchor:SetMovable(not lock)
            if lock then
                anchor:RegisterForDrag()          -- clear drag registration
            else
                anchor:RegisterForDrag("LeftButton")
            end
            SetTextColors(not lock)
        end

        -- Right-click toggles lock/unlock.
        anchor:RegisterForClicks("RightButtonUp")
        anchor:SetScript("OnClick", function(_, button)
            if button ~= "RightButton" then return end
            if locked then
                SetLocked(false)
                VUI.Print("Quality of Life",
                    "Coordinates |cFF00CCFFunlocked|r — drag to reposition. "
                    .. "Right-click to lock.")
            else
                SavePosition()
                SetLocked(true)
                VUI.Print("Quality of Life", "Coordinates |cFF00FF00locked.|r")
            end
        end)

        -- Left-drag to reposition when unlocked.
        -- Drag registration is managed by SetLocked(); starts unregistered
        -- because locked=true at init.
        anchor:SetScript("OnDragStart", function(self)
            if not locked then self:StartMoving() end
        end)
        anchor:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SavePosition()
        end)

        -- Tooltip hint on hover — provides discoverability for the
        -- right-click lock/unlock interaction.
        anchor:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if locked then
                GameTooltip:AddLine("Right-click to unlock and reposition", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Drag to reposition", 0.2, 0.8, 1)
                GameTooltip:AddLine("Right-click to lock", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        anchor:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        anchor:SetScript("OnUpdate", function(self, elapsed)
            if not db or not db.showMapCoords then self:Hide(); return end
            self._t = (self._t or 0) + elapsed
            if self._t < THROTTLE then return end
            self._t = 0

            local mapID = C_Map.GetBestMapForUnit("player")
            local dirty = false

            -- Player position
            local pStr = "Player: —"
            if mapID then
                local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
                if ok and pos then
                    local x, y = pos:GetXY()
                    if x and y and (x > 0 or y > 0) then
                        pStr = format("Player: %.1f, %.1f", x * 100, y * 100)
                    end
                end
            end
            if pStr ~= self._lastPlayer then
                playerText:SetText(pStr)
                self._lastPlayer = pStr
                dirty = true
            end

            -- Cursor position (only while hovering the map canvas)
            local cStr = "Cursor: —"
            if container:IsMouseOver() then
                local ok, cx, cy = pcall(container.GetNormalizedCursorPosition, container)
                if ok and cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                    cStr = format("Cursor: %.1f, %.1f", cx * 100, cy * 100)
                end
            end
            if cStr ~= self._lastCursor then
                mouseText:SetText(cStr)
                self._lastCursor = cStr
                dirty = true
            end

            -- Only reflow the invisible hit rect when the text actually
            -- changed. GetStringWidth/Height + SetSize 30×/sec on unchanged
            -- text was wasteful.
            if dirty then ResizeAnchor() end
        end)
    end

    -- WorldMapFrame is load-on-demand; hook its load event if not yet available.
    if WorldMapFrame then
        InitCoords()
    else
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(self, _, addon)
            if addon == "Blizzard_WorldMap" then
                C_Timer.After(0, InitCoords)   -- defer one frame for full init
                self:UnregisterAllEvents()
            end
        end)
    end
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
    parts[#parts + 1] = "Level " .. tostring(level)
    parts[#parts + 1] = "Item Level " .. ilvlStr
    if zoneDisplay ~= "" then
        parts[#parts + 1] = zoneDisplay
    end
    afkOverlay._infoText:SetText(table.concat(parts, "  ·  "))

    -- Clock
    afkOverlay._clockText:SetText(date("%I:%M %p"))
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
    db.afkUIDirty = true

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
            afkOverlay._clockText:SetText(date("%I:%M %p"))
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
    if db then db.afkUIDirty = false end

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

-- Vertical nudge of the number from the icon's CENTRE, in pixels. Positive = lower.
--
-- ⚠ NEW KEY, NEW UNITS. The number used to sit BELOW the icon and delveCountOffsetY
-- meant "pixels below the icon's bottom edge" (settled at -1 by eye). It now sits ON
-- the icon, so that value is expressed in an origin that no longer exists. Silently
-- reinterpreting it would be the same class of quiet wrongness as the AH scanEngine
-- seeding bug, so this is a NEW key defaulting to a true centre and the old one is
-- dropped at login rather than carried across in obsolete units.
-- 1 is the value the owner settled on with /qol delvenudge against the live plaque, and the
-- configuration it belongs to is the one confirmed good in game.
--
-- ⚠ HORIZONTAL centring IS structural (see DelveAnchorCount); VERTICAL is not, because a
-- FontString with no height ignores justifyV, so this offset is doing real work rather than
-- expressing taste. An attempt to make it structural by anchoring all four sides broke
-- placement entirely -- see the warning in DelveAnchorCount. Until that is understood with
-- a measurement, this constant is load-bearing: do not zero it on the grounds that
-- "centring should not need a nudge".
local DELVE_COUNT_CENTER_Y = 1

-- Horizontal companion to the above. Not a symmetry nicety: the number read visibly
-- left of the circle's centre in game even though the fontstring is centre-anchored to
-- a centre-anchored icon (owner-observed 2026-08-05). Rather than invent a mechanism
-- for that -- a width-less fontstring's box IS its text, so justifyH is a no-op here --
-- this is a by-eye offset settled against the live client, exactly like the vertical
-- one. If the cause is ever actually measured, fix the cause and leave this at 0.
local DELVE_COUNT_CENTER_X = 1

-- Alpha of the black circular scrim behind the number, as a PERCENT (0-100) so the
-- stored value reads the same as the /qol delvetint argument.
--
-- By-eye value, therefore live-tunable rather than release-per-guess: v1.12.17 burned
-- five reloads settling a single cosmetic offset before /qol delvenudge existed.
local DELVE_TINT_ALPHA = 60

-- Atlases, both confirmed to RESOLVE on the live client via /qol delve (2026-08-05:
-- common-icon-checkmark 25x25, UI-Frame-IconMask 64x64) rather than trusted from
-- Blizzard's XML. The Midnight reagent-tier markers are why: those names still existed
-- but rendered the previous expansion's art.
local DELVE_CHECK_ATLAS = "common-icon-checkmark"
-- Fallback circular mask, used only if the widget carries neither of Blizzard's masks.
-- This is the FILE the template uses for its own circular case (CircleMask), not
-- UI-Frame-IconMask, which is the shape for the NON-circular case.
local DELVE_CIRCLE_MASK_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Pixels the checkmark extends past the icon on each side. The owner asked for it to
-- cover the whole icon, which is a DELIBERATE departure from Blizzard's own 16x16
-- corner EarnedCheck on this same template.
--
-- ⚠ Sized by ANCHORING to the icon's bounds, never by SetSize. The template declares a
-- 36x36 Icon but the live Delve plaque measured 24x24 -- the layout rescales it -- so
-- any hardcoded size would be wrong on the only surface this ships to.
local DELVE_CHECK_OUTSET = 2

-- Points added to Blizzard's own number font. A DELTA rather than an absolute size, so
-- the number still tracks the client's font if Blizzard restyles it.
--
-- ⚠ Now 0 (was -1). The -1 existed because the number used to sit BELOW the icon,
-- where StackCount's size read a shade large against the plaque's other text. It sits ON
-- the icon now -- which is precisely the placement StackCount is sized for -- so that
-- rationale is void by its own terms and Blizzard's native size is correct.
-- Fallback only; the live value is db.delveFontDelta (see /qol delvesize).
local DELVE_COUNT_FONT_DELTA = 0

-- Outline weight for the number. WoW has NO bold flag: SetFont's flags argument takes
-- OUTLINE / THICKOUTLINE / MONOCHROME and combinations, never a weight, so a heavier
-- outline is the native way to make a number read bolder. THICKOUTLINE is what Blizzard
-- itself uses on nameplate and floating-damage numbers.
-- Set back to "OUTLINE" if it ever reads too heavy at this size.
local DELVE_COUNT_OUTLINE = "THICKOUTLINE"

-- Colour by how many groups are LEFT, so the plaque reads at a glance without
-- reading the digit. Owner's mapping (revised 2026-08-05): 4 red, 3 orange, 2 yellow,
-- 1 green. The earlier mapping doubled orange on 3 and 2 and pushed green to 0; now that
-- 0 is drawn as a checkmark rather than a digit, green belongs on the last live number.
--
-- Blizzard's own font-colour globals rather than invented RGB, so it matches the
-- client and tracks any restyle -- all four are used by Blizzard's own
-- spellBorderColorFromTintValue table in Blizzard_UIWidgetTemplateBase.lua, which is
-- where they were confirmed to exist rather than assumed.
--
-- ⚠ Keys are ABSOLUTE remaining counts, per the owner's spec, NOT a proportion of
-- the total. Anything at or above DELVE_COUNT_MAX_KEY falls through to red, so a
-- delve with more than four groups still reads "plenty left" instead of losing its
-- colour. The observed total is 4; that is a single sample, hence the fallback.
--
-- 0 is retained and green even though the checkmark normally replaces the digit: it is
-- still reachable on the checkmark-atlas-missing fallback path.
local DELVE_COUNT_MAX_KEY = 4
local DELVE_COUNT_COLORS = {
    [0] = { g = "GREEN_FONT_COLOR",  r = 0.10, gr = 1.00, b = 0.10 },
    [1] = { g = "GREEN_FONT_COLOR",  r = 0.10, gr = 1.00, b = 0.10 },
    [2] = { g = "YELLOW_FONT_COLOR", r = 1.00, gr = 0.82, b = 0.00 },
    [3] = { g = "ORANGE_FONT_COLOR", r = 1.00, gr = 0.50, b = 0.25 },
    [4] = { g = "RED_FONT_COLOR",    r = 1.00, gr = 0.13, b = 0.13 },
}

-- Resolve to Blizzard's colour object when present, falling back to the literal RGB
-- above. The fallback is not decoration: a missing global would otherwise leave the
-- number its default colour with no hint why.
local function DelveCountColor(n)
    local key = n
    if type(key) ~= "number" then key = DELVE_COUNT_MAX_KEY end
    if key > DELVE_COUNT_MAX_KEY then key = DELVE_COUNT_MAX_KEY end
    local spec = DELVE_COUNT_COLORS[key] or DELVE_COUNT_COLORS[DELVE_COUNT_MAX_KEY]
    local obj = _G[spec.g]
    if type(obj) == "table" and obj.r and obj.g and obj.b then
        return obj.r, obj.g, obj.b
    end
    return spec.r, spec.gr, spec.b
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
-- Blizzard ever does populate the field.
-- Re-anchor only when the offset actually changed, so the 0.5s poll is not calling
-- SetPoint on every tick. ClearAllPoints first: SetPoint ADDS a point rather than
-- replacing one, so re-anchoring without clearing would leave the old point fighting
-- the new one.
DelveAnchorCount = function(fs, anchor)
    local y = (db and tonumber(db.delveCountCenterY)) or DELVE_COUNT_CENTER_Y
    local x = (db and tonumber(db.delveCountCenterX)) or DELVE_COUNT_CENTER_X
    if fs._vuiOffsetY == y and fs._vuiOffsetX == x then return end
    fs._vuiOffsetY, fs._vuiOffsetX = y, x
    fs:ClearAllPoints()
    -- ⚠ TWO horizontal anchors. This gives the fontstring the icon's WIDTH, which is what
    -- makes justifyH CENTER work: it centres the glyph regardless of its advance width, so
    -- the placement is not tuned against one digit. Centre-ANCHORING instead would centre
    -- the bounding BOX, i.e. the advance width, and an x offset settled against "4" could
    -- then be wrong for "1".
    --
    -- ⚠⚠ DO NOT "COMPLETE" THIS BY ALSO ANCHORING TOP+BOTTOM. Tried 2026-08-05 on the
    -- reasoning that giving the string a HEIGHT would make SetJustifyV("MIDDLE") meaningful
    -- and remove the need for a vertical nudge. It does the opposite: the number rendered in
    -- the icon's UPPER-LEFT corner, i.e. BOTH justifications stopped applying, not just the
    -- vertical one. Owner-observed in game. The mechanism is not understood -- opposing
    -- horizontal anchors demonstrably DO give a usable width here, so "FontStrings ignore
    -- opposing anchors" is not the explanation either. /qol delve now dumps the justify
    -- values and both rects so the next attempt starts from a measurement.
    fs:SetPoint("LEFT",  anchor, "LEFT",  x, -y)
    fs:SetPoint("RIGHT", anchor, "RIGHT", x, -y)
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

-- The circular scrim the number sits on. OURS, created on Blizzard's widget frame
-- alongside the count fontstring -- same precedent, in production since v1.12.15.
local function DelveTint(spellFrame)
    if spellFrame._vuiNemesisTint then return spellFrame._vuiNemesisTint end
    local icon = spellFrame.Icon
    if not icon then return nil end

    -- ARTWORK sublevel 1: above the icon art (sublevel 0) but BELOW the Border, which
    -- the template puts on OVERLAY. Dimming the gold ring would read as a broken icon
    -- rather than as a deliberate scrim.
    local tex = spellFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    if not tex then return nil end
    -- ⚠ WHITE8x8 + SetVertexColor rather than SetColorTexture. This is NOT what fixed
    -- the square scrim (that was the wrong mask, below) -- an earlier revision claimed it
    -- was, wrongly. It is kept because a colour texture has no real texture to sample and
    -- its participation in the vertex-colour/mask pipeline is unverified, while WHITE8x8
    -- is known-good there (it is the documented fix for the v1.6.17 SetGradient bug).
    tex:SetTexture("Interface/Buttons/WHITE8x8")
    tex:SetVertexColor(0, 0, 0)
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

    -- Circular, or not at all. A square scrim over a round icon looks like a bug, so
    -- the ladder ends in "no tint" rather than "wrong tint".
    --
    -- ⚠ ATTACH TO BOTH MASKS, exactly as Blizzard's own XML lists the Icon under both.
    -- Setup() picks one per widget update:
    --     IconMask:SetShown(iconDisplayType ~= Circular)
    --     CircleMask:SetShown(iconDisplayType == Circular)
    -- so precisely one is live at any moment, and a HIDDEN MaskTexture does not mask.
    -- Binding only to IconMask is why the scrim rendered SQUARE on the Delve plaque: its
    -- icons are Circular, so the mask we had attached to was the one Blizzard had just
    -- switched off. Attaching to both hands the arbitration back to Blizzard, and keeps
    -- working if a future widget flips iconDisplayType.
    local masked = false
    if tex.AddMaskTexture then
        for _, key in ipairs({ "CircleMask", "IconMask" }) do
            local m = spellFrame[key]
            if m and pcall(tex.AddMaskTexture, tex, m) then masked = true end
        end
    end
    if not masked then
        -- Neither Blizzard mask present: build a circular one. Deliberately the file the
        -- template itself uses for its CIRCULAR case, not UI-Frame-IconMask, which is the
        -- shape used when iconDisplayType is NOT circular.
        local okm, own = pcall(function()
            local m = spellFrame:CreateMaskTexture()
            m:SetTexture(DELVE_CIRCLE_MASK_FILE)
            m:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            m:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            return m
        end)
        if okm and own then masked = pcall(tex.AddMaskTexture, tex, own) end
    end
    tex._vuiNoMask = not masked
    tex:Hide()

    spellFrame._vuiNemesisTint = tex
    return tex
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
    local o = DELVE_CHECK_OUTSET
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", -o, o)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", o, -o)
    tex:Hide()

    spellFrame._vuiNemesisCheck = tex
    return tex
end

-- Last-resort typeface if no Blizzard object can be read. Friz Quadrata is the standard
-- Midnight UI face and what the rest of the Delve plaque uses.
local DELVE_FALLBACK_FONT_FILE = "Fonts\\FRIZQT__.TTF"

-- Resolve the TYPEFACE for the count.
--
-- ⚠ Deliberately NOT StackCount's. StackCount is NumberFontNormal (ARIALN, a narrow
-- stack-badge face), which made the count the only number on the plaque not in Friz
-- Quadrata -- owner-reported 2026-08-05 as looking "weird" next to everything else.
-- The widget's OWN Text fontstring is the authoritative source: the template declares it
-- inherits="GameFontNormal", so reading its file gives us exactly the plaque's face and
-- follows Blizzard if they ever restyle the standard UI font.
--
-- Only the FILE comes from here; the SIZE still comes from StackCount (see
-- DelveCountString), so switching typeface changed one variable and not two.
local function DelveNumberFontFile(spellFrame)
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

-- Apply the size delta and our outline weight, from the base font captured at creation.
--
-- ⚠ Reads fs._vuiBaseSize, NEVER GetFont. Once we have called SetFont, GetFont reports
-- the size WE wrote, so deriving the new size from it would compound the delta on every
-- change -- one tap of /qol delvesize would keep growing the number.
-- Re-applied only when the delta actually changed, so the 0.5s poll is not calling
-- SetFont on every tick.
local function DelveApplyFont(fs)
    local d = (db and tonumber(db.delveFontDelta)) or DELVE_COUNT_FONT_DELTA
    if fs._vuiFontDelta == d then return end
    fs._vuiFontDelta = d
    local file, base = fs._vuiBaseFile, fs._vuiBaseSize
    if not (file and type(base) == "number") then return end
    local sz = base + d
    if sz < 1 then sz = 1 end
    pcall(fs.SetFont, fs, file, sz, DELVE_COUNT_OUTLINE)
end

local function DelveCountString(spellFrame)
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
    DelveApplyFont(fs)

    -- Drop shadow, on the same reasoning as the map coordinates. It was briefly removed
    -- (2026-08-05) as redundant against the scrim and as a suspected source of a perceived
    -- off-centre bias -- the offset is (1, -1), down-right, which could make the glyph look
    -- pushed up-left. ⚠ THAT EXPERIMENT NEVER RAN: it was bundled with the four-anchor
    -- change above, which broke placement outright, so the shadow's effect on perceived
    -- centring is still UNMEASURED. Restored because the configuration it belongs to is the
    -- one confirmed good in game. Test it alone if it is ever worth testing.
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    -- Load-bearing, not cosmetic: DelveAnchorCount gives this fontstring the icon's full
    -- width via LEFT+RIGHT anchors, and justifyH is what centres the glyph inside it.
    -- ⚠ justifyV is a KNOWN no-op here -- the string has no height -- and is kept only so
    -- that it is already correct if the height problem is ever solved. Vertical placement is
    -- currently the anchor point plus the user offset, NOT justification.
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    spellFrame._vuiNemesisCount = fs
    DelveAnchorCount(fs, anchor)
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

        -- Three states, mutually exclusive: nothing / tinted number / checkmark.
        local showCount, showCheck = false, false
        if left and not nativeShows then
            if left == 0 then showCheck = true else showCount = true end
        end

        -- Cleared: the checkmark stands alone. A number and a scrim underneath it would
        -- muddy the art while adding no information.
        local chk = (showCheck and DelveCheck(f)) or (f and f._vuiNemesisCheck)
        if chk then chk:SetShown(showCheck) end

        -- Atlas unavailable (DelveCheck returned nil) -- fall back to drawing the number
        -- in green, which is what this looked like before the checkmark existed. Failing
        -- to a working older behaviour beats failing to a blank icon.
        if showCheck and not chk then showCount = true end

        local tint = (showCount and DelveTint(f)) or (f and f._vuiNemesisTint)
        if tint then
            local a = ((db and tonumber(db.delveTintAlpha)) or DELVE_TINT_ALPHA) / 100
            if tint._vuiAlpha ~= a then
                tint._vuiAlpha = a
                tint:SetAlpha(a)
            end
            -- Unmasked means the circular mask could not be established; showing a
            -- square black block would look worse than showing no scrim at all.
            tint:SetShown(showCount and not tint._vuiNoMask)
        end

        local fs = (showCount and DelveCountString(f)) or (f and f._vuiNemesisCount)
        if fs then
            if showCount then
                DelveAnchorCount(fs, f.Icon or f)   -- picks up a /qol delvenudge live
                DelveApplyFont(fs)                  -- and a /qol delvesize live
                fs:SetText(left)
                fs:SetTextColor(DelveCountColor(left))
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
            if f._vuiNemesisTint  then f._vuiNemesisTint:Hide()  end
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
            -- WHICH mask is live decides whether an overlay clips circular or square:
            -- Setup() shows exactly one, per iconDisplayType. Attaching to the hidden one
            -- is what made the scrim render square.
            local function shownOf(m)
                if not m then return "absent" end
                local oks, sh = pcall(function() return m:IsShown() end)
                return oks and tostring(sh) or "?"
            end
            print(("        mask shown: IconMask=%s CircleMask=%s  (exactly one should be true)")
                :format(shownOf(f.IconMask), shownOf(f.CircleMask)))
            -- Digit advance widths in the LIVE font. Equal widths mean the font is tabular
            -- and one x offset would suit every digit; unequal means it would not -- which
            -- is why the centring is structural rather than a tuned nudge.
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
                -- Why vertical centring still needs a user offset. Anchoring the string on
                -- all four sides to make justifyV meaningful instead pushed the number into
                -- the icon's upper-left corner, so BOTH justifications stopped applying and
                -- the reason is not understood. These are the numbers that would explain it:
                -- whether the justify values are actually set, whether the string has a real
                -- width and height, and where its rect sits relative to the icon's.
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
            end
        end
    end
end

-- ── Options Panel ───────────────────────────────────────────
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local function AddCheckbox(key, name, tip, onChange)
        local setting = Settings.RegisterAddOnSetting(
            category, ADDON_NAME .. "_" .. key, key,
            db, type(defaults[key]), name, defaults[key])   -- per-character SLOT
        setting:SetValueChangedCallback(function(_, value)
            -- Live variant: every QoL toggle applies mid-session (v1.6.28
            -- pattern) — the old PrintOnOff instructed a needless /reload.
            VUI.PrintOnOffLive("Quality of Life", name, value)
            if onChange then onChange(value) end
        end)
        Settings.CreateCheckbox(category, setting, tip)
    end

    AddCheckbox("showMapCoords", "Show Map Coordinates",
        "Displays player and cursor coordinates on the World Map. Right-click the coordinates to unlock and reposition. Hides the quest log toggle button.",
        function(value)
            if value then
                if not coordsInitialized then SetupMapCoordinates()
                elseif mapCoordsAnchor then mapCoordsAnchor:Show() end
            else
                if mapCoordsAnchor then mapCoordsAnchor:Hide() end
            end
        end)

    AddCheckbox("showItemLevels", "Show Item Levels",
        "Displays item level numbers on equipment in bags, bank, character panel, and merchants. Quest rewards are excluded.",
        function(value)
            if value then SetupItemLevels() end
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
        db,                                -- per-character SLOT (see VUI.BindCharDB)
        type(defaults.repairFunding),
        "Repair Funding",
        defaults.repairFunding
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
        .. "on a dark circular tint so it stays readable, and is replaced by a green "
        .. "checkmark once every group is defeated. Adjust the position with "
        .. "/qol delvenudge and the tint darkness with /qol delvetint.",
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
        VeritasUI_QualityOfLifeDB = VeritasUI_QualityOfLifeDB or {}
        for k, v in pairs(defaults) do
            if VeritasUI_QualityOfLifeDB[k] == nil then
                VeritasUI_QualityOfLifeDB[k] = v
            end
        end
        -- Legacy ROOT bound here so nothing in the ADDON_LOADED -> PLAYER_LOGIN
        -- window sees a nil db (unchanged behaviour). The per-character slot is
        -- bound at PLAYER_LOGIN -- see the TIMING note on VUI.BindCharDB.
        db = VeritasUI_QualityOfLifeDB
        -- InitializeOptions moved to PLAYER_LOGIN: Settings.RegisterAddOnSetting
        -- captures the table it is handed, so it must receive the per-character
        -- slot, which does not exist yet here.
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Re-bind to this character's slot, then register options against it.
        db = VUI.BindCharDB("VeritasUI_QualityOfLifeDB", defaults)
        -- Drop the superseded Delve offset. It measured from the icon's bottom edge;
        -- the count now measures from the icon's centre, so the stored number is in an
        -- origin that no longer exists and keeping it would be a silent 1px lie. Same
        -- self-clean the AH module does for its orphaned db.shopping.
        db.delveCountOffsetY = nil
        InitializeOptions()
        -- Belt-and-suspenders: if we crashed or disconnected while the AFK
        -- screen was up, UIParent alpha and MinimapCluster are left hidden.
        -- Gated on the persisted dirty flag rather than run unconditionally:
        -- UIParent:SetAlpha(1) genuinely is a no-op at the default, but
        -- MinimapCluster:Show() is not — running it on every login un-hid a
        -- minimap that another addon or an Edit Mode layout had deliberately
        -- hidden, which is precisely what AFK_Exit goes out of its way to avoid.
        if db.afkUIDirty then
            UIParent:SetAlpha(1)
            if MinimapCluster then MinimapCluster:Show() end
            db.afkUIDirty = false
        end

        if db.showItemLevels then SetupItemLevels()     end
        if db.showMapCoords  then SetupMapCoordinates() end

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
        local ny, nx = ntail:match("^(-?%d+)%s+(-?%d+)$")
        if not ny then ny = ntail:match("^(-?%d+)$") end
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif not ny then
            VUI.Print("Quality of Life", format(
                "Delve count offset is |cFFFFFF00%d|r down, |cFFFFFF00%d|r right of the "
                .. "icon's centre. |cFFFFFF00/qol delvenudge <down> [right]|r to change "
                .. "it (negatives go up / left).",
                tonumber(db.delveCountCenterY) or 0,
                tonumber(db.delveCountCenterX) or 0))
        else
            db.delveCountCenterY = tonumber(ny)
            if nx then db.delveCountCenterX = tonumber(nx) end
            -- Applies on the next poll tick (<=0.5s) with no reload: the anchor
            -- helper re-anchors as soon as it sees a different value.
            VUI.Print("Quality of Life", format(
                "Delve count offset set to |cFFFFFF00%d|r down, |cFFFFFF00%d|r right.",
                db.delveCountCenterY, tonumber(db.delveCountCenterX) or 0))
        end
        return
    end
    local tint = arg:lower():match("^delvetint%s*(%d*)")
    if tint then
        if not db then
            VUI.Print("Quality of Life", "Still loading — try again in a moment.")
        elseif tint == "" then
            VUI.Print("Quality of Life", format(
                "Delve icon tint is |cFFFFFF00%d%%|r. "
                .. "|cFFFFFF00/qol delvetint <0-100>|r to change it "
                .. "(0 = no tint, 100 = solid black).",
                tonumber(db.delveTintAlpha) or DELVE_TINT_ALPHA))
        else
            -- Clamped rather than rejected: an out-of-range number has an obvious
            -- intent, and silently doing nothing would read as the command being broken.
            local v = tonumber(tint) or DELVE_TINT_ALPHA
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            db.delveTintAlpha = v
            VUI.Print("Quality of Life", format(
                "Delve icon tint set to |cFFFFFF00%d%%|r.", v))
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

    -- Set the native Blizzard user waypoint.
    local mapPoint = UiMapPoint.CreateFromVector2D(mapID, CreateVector2D(nx, ny))
    C_Map.SetUserWaypoint(mapPoint)
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
