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
local CreateFrame      = CreateFrame
local C_Timer          = C_Timer
local C_Container      = C_Container
local C_Item           = C_Item
local C_Map            = C_Map
local GetCoinTextureString = GetCoinTextureString
local C_Navigation  = C_Navigation
local C_SuperTrack  = C_SuperTrack

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
}

local db
local settingsCategoryID
local frame = CreateFrame("Frame")

local itemLevelsSetup   = false  -- guards SetupItemLevels() re-entry
local coordsInitialized = false  -- guards InitCoords() re-entry
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
local SELL_BATCH         = 11
local SELL_RETRY_SEC     = 0.5
local MAX_NO_PROGRESS    = 5     -- bail if no item is removed for this many seconds
local saleTotal              -- nil when idle; total value of junk at sell start
local saleCount              -- count of grey stacks at sell start (for print)
local lastRemainingValue     -- previous cycle's remaining value (progress detection)
local noProgressSince        -- GetTime() of last cycle that made progress (or sell start)
local sellRetryTimer         -- safety timer; fires if BAG_UPDATE_DELAYED is lost

local function CancelSellRetry()
    if sellRetryTimer then sellRetryTimer:Cancel(); sellRetryTimer = nil end
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
                -- defensive pattern at IsEquippableGear (lines 339-350).
                local okJ, isJunk = pcall(function()
                    return info.quality == 0 and not info.hasNoValue
                end)
                if okJ and isJunk then
                    local okP, _, _, _, _, _, _, _, _, _, _, price =
                        pcall(C_Item.GetItemInfo, info.itemID)
                    if okP then
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
                -- sellable).  Mirrors IsEquippableGear (lines 339-350).
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

-- ── Feature: Auto Repair ────────────────────────────────────
-- Fires independently from MERCHANT_SHOW; never chained off
-- AutoSellJunk.  Print uses GetRepairAllCost() directly — no
-- GetMoney() delta, no race condition, no PLAYER_MONEY listener.
--
-- Funding source is controlled by db.repairFunding:
--   "guild"    — try guild bank first, then personal covers any remainder.
--                Skipped if the guild's info text contains [noautorepair]
--                (a convention used by GMs to block auto-repairs against
--                the guild bank). Our dual-call approach always covers
--                the remainder with personal gold regardless of withdrawal
--                limit — we never silently under-repair.
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
        RepairAllItems(true)   -- guild funds first
        RepairAllItems(false)  -- personal gold covers any remainder
        VUI.Print("Quality of Life", format(
            "Repaired for %s (guild bank)", GetCoinTextureString(cost)))
    else
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

    local function ProcessItem(btn, itemIDOrLink, quality)
        if not itemIDOrLink then HideOverlay(btn); return end
        if quality ~= nil and quality == 0 then HideOverlay(btn); return end
        local equippable, rawID = IsEquippableGear(itemIDOrLink)
        if not equippable then HideOverlay(btn); return end
        if rawID and SKIP_ITEMS[rawID] then HideOverlay(btn); return end
        local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, itemIDOrLink)
        if not ok or not ilvl then HideOverlay(btn); return end
        -- ilvl may be a secret value in raid encounters; guard the comparison.
        local cmpOk, tooLow = pcall(function() return ilvl <= 0 end)
        if not cmpOk or tooLow then HideOverlay(btn); return end
        ApplyOverlay(btn, ilvl, quality)
    end

    local function GetItemQuality(link)
        if not link then return 1 end
        local ok, _, _, q = pcall(C_Item.GetItemInfo, link)
        return (ok and q) or 1
    end

    ----------------------------------------------------------------
    --  SetItemButtonQuality hook
    ----------------------------------------------------------------
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

        -- Resolve a full item link for accurate ilvl (effective vs base).
        -- The passed itemIDOrLink may be a numeric ID; a full link gives
        -- GetDetailedItemLevelInfo the effective (upgraded) ilvl.
        local link = type(itemIDOrLink) == "string" and itemIDOrLink or nil
        if not link then
            if btn.GetItemLink then
                local ok, r = pcall(btn.GetItemLink, btn)
                if ok and r then link = r end
            end
            if not link and btn.GetBagID and btn.GetID then
                local ok, r = pcall(C_Container.GetContainerItemLink,
                    btn:GetBagID(), btn:GetID())
                if ok and r then link = r end
            end
            if not link and btn.GetBankTabID and btn.GetContainerSlotID then
                local ok, r = pcall(C_Container.GetContainerItemLink,
                    btn:GetBankTabID(), btn:GetContainerSlotID())
                if ok and r then link = r end
            end
            if not link and btn.GetID
                and not btn.GetBagID and not btn.GetBankTabID then
                local slotID = btn:GetID()
                local pName = btn:GetParent()
                    and btn:GetParent().GetName
                    and btn:GetParent():GetName() or ""
                -- Blizzard bank container (-1) has slots 1–28 in Midnight.
                if slotID >= 1 and slotID <= 28 and pName:find("Bank") then
                    local ok, r = pcall(C_Container.GetContainerItemLink,
                        -1, slotID)
                    if ok and r then link = r end
                end
            end
            if not link and btn.GetID then
                local bName = btn.GetName and btn:GetName() or ""
                if bName:find("Character") then
                    local ok, r = pcall(GetInventoryItemLink,
                        "player", btn:GetID())
                    if ok and r then link = r end
                end
            end
        end

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
    local fmt = string.format
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
                        pStr = fmt("Player: %.1f, %.1f", x * 100, y * 100)
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
                    cStr = fmt("Cursor: %.1f, %.1f", cx * 100, cy * 100)
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
-- Dismissed when AFK flag clears (any input).
-- ─────────────────────────────────────────────────────────────
local afkOverlay          -- the fullscreen frame (created once, reused)
local afkClockTicker      -- 30s timer for real-world clock refresh
local afkActive = false   -- guard against re-entry

local function AFK_CreateOverlay()
    if afkOverlay then return afkOverlay end

    local f = CreateFrame("Frame", "VeritasUI_AFKScreen", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(500)
    f:SetIgnoreParentAlpha(true)
    f:EnableKeyboard(true)
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

    -- ── Input dismiss ──
    -- Only character movement (keyboard) clears AFK in Blizzard's default
    -- behavior — mouse clicks do not.  Propagate every key so the movement
    -- key that wakes the player also reaches the game.  Mouse is not
    -- captured (EnableMouse stays false) so clicks fall through harmlessly.
    f:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(true)
    end)

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
    local ok, overall, equipped = pcall(GetAverageItemLevel)
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

    -- Refresh info and show
    AFK_RefreshInfo()
    overlay:Show()

    -- Start slow camera orbit (pcall-guarded: may fail in cinematics or vehicle sequences).
    pcall(MoveViewRightStart, 0.03)

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

    -- Restore UI; only show MinimapCluster if it was visible before AFK started.
    UIParent:SetAlpha(1)
    if MinimapCluster then
        if afkOverlay and afkOverlay._minimapWasShown then
            MinimapCluster:Show()
        end
    end

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

-- ── Options Panel ───────────────────────────────────────────
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local function AddCheckbox(key, name, tip, onChange)
        local setting = Settings.RegisterAddOnSetting(
            category, ADDON_NAME .. "_" .. key, key,
            VeritasUI_QualityOfLifeDB, type(defaults[key]), name, defaults[key])
        setting:SetValueChangedCallback(function(_, value)
            VUI.PrintOnOff("Quality of Life", name, value)
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

    AddCheckbox("autoSellJunk", "Auto Sell Junk",
        "Automatically sells all grey items when you visit a merchant.")

    AddCheckbox("autoRepair", "Auto Repair",
        "Automatically repairs all equipment at repair vendors. Funding source is selected below.")

    -- Repair Funding dropdown — appears directly below the Auto Repair checkbox.
    local repairSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_repairFunding",
        "repairFunding",
        VeritasUI_QualityOfLifeDB,
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

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        VeritasUI_QualityOfLifeDB = VeritasUI_QualityOfLifeDB or {}
        for k, v in pairs(defaults) do
            if VeritasUI_QualityOfLifeDB[k] == nil then
                VeritasUI_QualityOfLifeDB[k] = v
            end
        end
        db = VeritasUI_QualityOfLifeDB
        InitializeOptions()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Belt-and-suspenders: if we crashed/disconnected while AFK was
        -- active, UIParent alpha and MinimapCluster may be in a bad state.
        -- Restore unconditionally on every login — these are no-ops when
        -- already at their default values.
        UIParent:SetAlpha(1)
        if MinimapCluster then MinimapCluster:Show() end

        if db.showItemLevels then SetupItemLevels()     end
        if db.showMapCoords  then SetupMapCoordinates() end

        if db.autoSellJunk or db.autoRepair then
            self:RegisterEvent("MERCHANT_SHOW")
            self:RegisterEvent("MERCHANT_CLOSED")
        end

        if db.afkScreen then AFK_StartPoll() end

        -- Register /way only if TomTom is absent; both addons claim this command.
        if not (_G.TomTom or (IsAddOnLoaded and IsAddOnLoaded("TomTom"))) then
            SLASH_VERITASUI_WAY1 = "/way"
            SlashCmdList["VERITASUI_WAY"] = WayCommand
        else
            VUI.Print("Quality of Life",
                "TomTom detected — |cFFFFFF00/way|r is handled by TomTom.")
        end

        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("Quality of Life", "Loaded. Type |cFFFFFF00/qol|r to open settings.")

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
        C_Timer.After(0, function()
            if db.autoRepair   then AutoRepair()  end
            if db.autoSellJunk then AutoSellJunk() end
        end)

    elseif event == "MERCHANT_CLOSED" then
        if saleTotal then ResetSellState() end

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

    elseif event == "USER_WAYPOINT_UPDATED" then
        -- Fired when the waypoint is cleared externally (e.g. map right-click UI).
        if not C_Map.HasUserWaypoint() then
            StopWaypointTracking()
        end
    end
end)

-- ── Slash commands ──────────────────────────────────────────
SLASH_VERITASUI_QOL1 = "/qol"
SLASH_VERITASUI_QOL2 = "/qualityoflife"
SlashCmdList["VERITASUI_QOL"] = function()
    Settings.OpenToCategory(settingsCategoryID)
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
            string.format("Unknown map ID |cFFFFFF00%d|r.", mapID))
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
    local desc = (label ~= "") and string.format(" |cFFCCCCCC(%s)|r", label) or ""
    VUI.Print("Quality of Life",
        string.format("Waypoint set: |cFFFFD200%s|r — |cFF00FF00%.1f, %.1f|r%s",
            zoneName, x, y, desc))
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_QualityOfLife_OnAddonCompartmentClick()
    C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
end
