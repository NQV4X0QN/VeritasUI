-- VeritasUI_QualityOfLife / QualityOfLife.lua
-- Functional enhancements: map coordinates, item levels, auto-repair, auto-sell.
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
    showItemLevels = true,
    showMapCoords  = true,
}

local db
local settingsCategoryID
local frame = CreateFrame("Frame")

-- ── Feature: Auto Sell Junk ─────────────────────────────────
-- Phase 1: Scan all bags and collect junk items.
-- Phase 2: Sell in small batches (≤ 6 per frame) to stay within
--          the server's per-frame processing limit.  Each item is
--          re-verified before the sell call to handle any bag
--          shuffling from combined-bag cleanup.
-- Phase 3: Tally and announce after the last batch.
local function AutoSellJunk()
    -- Phase 1 — collect
    local junk = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue then
                junk[#junk + 1] = {
                    bag  = bag,
                    slot = slot,
                    id   = info.itemID,
                    qty  = info.stackCount or 1,
                }
            end
        end
    end

    if #junk == 0 then return end

    -- Phase 2 — sell in batches
    local BATCH = 6
    local idx   = 1
    local soldItems = {}   -- only items we verified were sold

    local ticker
    ticker = C_Timer.NewTicker(0, function()   -- 0 = next frame
        local batchEnd = math.min(idx + BATCH - 1, #junk)
        for i = idx, batchEnd do
            local j = junk[i]
            -- Re-verify: the item must still be at this bag/slot with the
            -- same itemID and still be grey-quality.
            local info = C_Container.GetContainerItemInfo(j.bag, j.slot)
            if info and info.itemID == j.id and info.quality == 0 then
                C_Container.UseContainerItem(j.bag, j.slot)
                soldItems[#soldItems + 1] = { id = j.id, qty = j.qty }
            end
        end
        idx = batchEnd + 1

        if idx > #junk then
            ticker:Cancel()

            -- Phase 3 — tally & announce
            local count = #soldItems
            if count == 0 then return end

            local function Tally()
                local copper, pending = 0, 0
                for _, s in ipairs(soldItems) do
                    local _, _, _, _, _, _, _, _, _, _, vp = C_Item.GetItemInfo(s.id)
                    if vp then copper = copper + s.qty * vp
                    else pending = pending + 1 end
                end
                return copper, pending
            end

            local function Announce(copper)
                VUI.Print("Quality of Life", format(
                    "Sold |cFFFFFF00%d|r junk item%s for %s",
                    count, count > 1 and "s" or "",
                    GetCoinTextureString(copper)))
            end

            local copper, pending = Tally()
            if pending == 0 then Announce(copper); return end

            -- Uncached prices — retry until all resolve (max 3 s).
            local retries = 0
            local priceTicker
            priceTicker = C_Timer.NewTicker(0.5, function()
                retries = retries + 1
                copper, pending = Tally()
                if pending == 0 or retries >= 6 then
                    priceTicker:Cancel()
                    Announce(copper)
                end
            end)
        end
    end)
end

-- ── Feature: Auto Repair ────────────────────────────────────
-- Tries guild repair first, then falls back to personal gold.
-- Reports funding source so the player knows who paid.
-- NOTE (2a): GetRepairAllCost() after RepairAllItems(true) assumes
-- the server updates cost within the same frame.  This is reliable
-- in practice but not contractually guaranteed by the API.
local function AutoRepair()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost == 0 then return end

    if IsInGuild() and CanGuildBankRepair() then
        RepairAllItems(true)
        local remaining = GetRepairAllCost()
        if remaining == 0 then
            VUI.Print("Quality of Life", format(
                "Repaired for %s (guild bank)", GetCoinTextureString(cost)))
            return
        end
        -- Guild only covered part — pay the rest from personal gold.
        RepairAllItems(false)
        local guildPaid = cost - remaining
        if guildPaid > 0 then
            VUI.Print("Quality of Life", format(
                "Repaired for %s (%s guild, %s personal)",
                GetCoinTextureString(cost),
                GetCoinTextureString(guildPaid),
                GetCoinTextureString(remaining)))
        else
            VUI.Print("Quality of Life", format(
                "Repaired for %s (personal gold)", GetCoinTextureString(cost)))
        end
        return
    end
    RepairAllItems(false)

    VUI.Print("Quality of Life", format(
        "Repaired for %s", GetCoinTextureString(cost)))
end

-- ── Feature: Show Item Levels ───────────────────────────────
-- Displays item level overlays on equippable gear in:
--   • Bags, bank, warband bank  (SetItemButtonQuality hook)
--   • Character panel           (SetItemButtonQuality hook)
--   • Merchant windows          (dedicated merchant scanner)
-- Quest reward buttons are explicitly excluded.
-- ─────────────────────────────────────────────────────────────
local function SetupItemLevels()
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
        end
        local c = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
        fs:SetText(ilvl)
        fs:SetTextColor(c.r, c.g, c.b)
        fs:Show()
    end

    local function HideOverlay(btn)
        if btn._vui_ilvl then btn._vui_ilvl:Hide() end
    end

    local function IsEquippableGear(itemIDOrLink)
        if not itemIDOrLink then return false end
        local ok, itemID, _, _, equipLoc, _, classID =
            pcall(C_Item.GetItemInfoInstant, itemIDOrLink)
        if not ok then return false end
        if not (GEAR_CLASSES[classID] and equipLoc and equipLoc ~= "") then
            return false
        end
        return true, itemID
    end

    local function ProcessItem(btn, itemIDOrLink, quality)
        if not itemIDOrLink then HideOverlay(btn); return end
        if quality ~= nil and quality == 0 then HideOverlay(btn); return end
        local equippable, rawID = IsEquippableGear(itemIDOrLink)
        if not equippable then HideOverlay(btn); return end
        if rawID and SKIP_ITEMS[rawID] then HideOverlay(btn); return end
        local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, itemIDOrLink)
        if not ok or not ilvl or ilvl <= 0 then HideOverlay(btn); return end
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
    local function IsQuestRewardButton(btn)
        local name = btn.GetName and btn:GetName()
        if name and name:find("QuestInfoItem") then return true end
        local p = btn:GetParent()
        for _ = 1, 3 do
            if not p then break end
            local pn = p.GetName and p:GetName()
            if pn and pn:find("QuestInfoRewardsFrame") then return true end
            p = p:GetParent()
        end
        return false
    end

    hooksecurefunc("SetItemButtonQuality", function(btn, quality, itemIDOrLink)
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
    mf:RegisterEvent("MERCHANT_SHOW")
    mf:RegisterEvent("MERCHANT_UPDATE")
    mf:RegisterEvent("MERCHANT_FILTER_ITEM_UPDATE")
    mf:SetScript("OnEvent", function()
        C_Timer.After(0.1, UpdateMerchantItems)
    end)
end

-- ── Feature: Map Coordinates ────────────────────────────────
-- Shows player and cursor coordinates on the World Map.
-- Uses WoW's native tooltip backdrop textures for a metallic frame.
-- Hides the quest log side panel toggle button.
-- Small lock button toggles positioning mode; position saved across sessions.
-- When locked, the box is mouse-transparent (map clicks pass through).
-- Handles WorldMapFrame being load-on-demand (Blizzard_WorldMap).
-- Gracefully shows "—" in instances or areas without position data.
local function SetupMapCoordinates()
    local fmt = string.format
    local THROTTLE = 0.033   -- ~30 fps

    local function InitCoords()
        if not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
        local container = WorldMapFrame.ScrollContainer

        -- Hide the quest log show/hide toggle button in the bottom-right.
        local toggle = WorldMapFrame.SidePanelToggle
        if toggle then VUI.SuppressFrame(toggle) end

        local bg = CreateFrame("Frame", nil, container, "BackdropTemplate")
        bg:SetSize(126, 38)
        bg:SetFrameStrata("HIGH")
        bg:SetFrameLevel(container:GetFrameLevel() + 10)
        bg:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true,
            tileSize = 16,
            edgeSize = 16,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        bg:SetBackdropColor(0.08, 0.08, 0.10, 0.65)
        bg:SetBackdropBorderColor(0.65, 0.65, 0.65, 1)

        -- Restore saved position or default to bottom-right.
        -- Saved positions are always stored as BOTTOMLEFT offsets from the
        -- container's BOTTOMLEFT corner (see SavePosition below).
        local saved = db.mapCoordsPos
        if saved then
            bg:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", saved.x, saved.y)
        else
            bg:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 3, 0)
        end

        -- ── Lock / unlock via a small toggle button ──
        local locked = true

        -- Mouse-transparent when locked so map clicks pass through.
        bg:EnableMouse(false)
        bg:SetMovable(false)
        bg:SetClampedToScreen(true)

        local function SavePosition()
            bg:StopMovingOrSizing()
            -- After StartMoving(), WoW silently re-anchors the frame to
            -- UIParent for drag tracking, so GetPoint(1) returns offsets
            -- relative to UIParent — NOT our container.  Using those
            -- offsets with container as the relative frame on restore
            -- places the box in the wrong spot every login.
            --
            -- GetLeft()/GetBottom() always return true screen-space
            -- positions regardless of WoW's internal anchor state, so we
            -- compute the BOTTOMLEFT offset from the container explicitly.
            -- Both frames may have different effective scales, so we
            -- normalise through screen-pixel space first.
            local bgScale        = bg:GetEffectiveScale()
            local containerScale = container:GetEffectiveScale()
            if containerScale == 0 then return end
            local x = ((bg:GetLeft()   or 0) * bgScale
                       - (container:GetLeft()   or 0) * containerScale)
                      / containerScale
            local y = ((bg:GetBottom() or 0) * bgScale
                       - (container:GetBottom() or 0) * containerScale)
                      / containerScale
            db.mapCoordsPos = { x = x, y = y }
        end

        local function SetLocked(lock)
            locked = lock
            bg:SetMovable(not lock)
            bg:EnableMouse(not lock)
            if lock then
                bg:SetBackdropBorderColor(0.65, 0.65, 0.65, 1)
            else
                bg:SetBackdropBorderColor(0.2, 0.8, 1.0, 1)
            end
        end

        -- Small lock/unlock toggle button on the bottom-right corner.
        -- This is the ONLY way to lock/unlock — no auto-lock on drop.
        local lockBtn = CreateFrame("Button", nil, bg)
        lockBtn:SetSize(14, 14)
        lockBtn:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -5, 4)
        lockBtn:SetFrameLevel(bg:GetFrameLevel() + 2)

        local lockIcon = lockBtn:CreateTexture(nil, "ARTWORK")
        lockIcon:SetAllPoints()
        lockIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
        lockIcon:SetVertexColor(0.7, 0.7, 0.7)
        lockBtn.icon = lockIcon

        -- Drag handling: only starts/stops movement, never changes lock state.
        bg:RegisterForDrag("LeftButton")
        bg:SetScript("OnDragStart", function(self)
            if not locked then
                self:StartMoving()
            end
        end)
        bg:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SavePosition()
        end)

        lockBtn:SetScript("OnClick", function()
            if locked then
                SetLocked(false)
                lockIcon:SetVertexColor(0.2, 0.8, 1.0)
                VUI.Print("Quality of Life",
                    "Coordinates |cFF00CCFFunlocked|r — drag to reposition. "
                    .. "Click the lock icon to lock.")
            else
                SavePosition()
                SetLocked(true)
                lockIcon:SetVertexColor(0.7, 0.7, 0.7)
                VUI.Print("Quality of Life", "Coordinates |cFF00FF00locked.|r")
            end
        end)

        lockBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if locked then
                GameTooltip:AddLine("Click to unlock and reposition", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Click to lock position", 0.2, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        lockBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Player line (gold).
        local playerText = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerText:SetPoint("TOPLEFT", bg, "TOPLEFT", 10, -7)
        playerText:SetJustifyH("LEFT")
        playerText:SetTextColor(1, 0.82, 0)
        playerText:SetText("Player:  —")

        -- Cursor line (light gray).
        local mouseText = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mouseText:SetPoint("TOPLEFT", playerText, "BOTTOMLEFT", 0, -3)
        mouseText:SetJustifyH("LEFT")
        mouseText:SetTextColor(0.75, 0.75, 0.75)
        mouseText:SetText("Cursor:  —")

        bg:SetScript("OnUpdate", function(self, elapsed)
            self._t = (self._t or 0) + elapsed
            if self._t < THROTTLE then return end
            self._t = 0

            local mapID = C_Map.GetBestMapForUnit("player")

            -- Player position
            local pStr = "Player:  —"
            if mapID then
                local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
                if ok and pos then
                    local x, y = pos:GetXY()
                    if x and y and (x > 0 or y > 0) then
                        pStr = fmt("Player:  %.1f, %.1f", x * 100, y * 100)
                    end
                end
            end
            if pStr ~= self._lastPlayer then
                playerText:SetText(pStr)
                self._lastPlayer = pStr
            end

            -- Cursor position (only while hovering the map canvas)
            local cStr = "Cursor:  —"
            if container:IsMouseOver() then
                local ok, cx, cy = pcall(container.GetNormalizedCursorPosition, container)
                if ok and cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                    cStr = fmt("Cursor:  %.1f, %.1f", cx * 100, cy * 100)
                end
            end
            if cStr ~= self._lastCursor then
                mouseText:SetText(cStr)
                self._lastCursor = cStr
            end
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

-- ── Options Panel ───────────────────────────────────────────
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local options = {
        { key = "showMapCoords",   name = "Show Map Coordinates",
          tip = "Displays player and cursor coordinates on the World Map. Use the lock icon to unlock and reposition. Hides the quest log toggle button." },
        { key = "showItemLevels",  name = "Show Item Levels",
          tip = "Displays item level numbers on equipment in bags, bank, character panel, and merchants. Quest rewards are excluded." },
        { key = "autoSellJunk",    name = "Auto Sell Junk",
          tip = "Automatically sells all grey items when you visit a merchant." },
        { key = "autoRepair",      name = "Auto Repair",
          tip = "Automatically repairs all equipment at repair vendors. Uses guild funds first if available." },
    }

    for _, opt in ipairs(options) do
        local setting = Settings.RegisterAddOnSetting(
            category,
            ADDON_NAME .. "_" .. opt.key,
            opt.key,
            VeritasUI_QualityOfLifeDB,
            type(defaults[opt.key]),
            opt.name,
            defaults[opt.key]
        )
        setting:SetValueChangedCallback(function(_, value)
            VUI.PrintOnOff("Quality of Life", opt.name, value)
        end)
        Settings.CreateCheckbox(category, setting, opt.tip)
    end

    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

-- ── Events ──────────────────────────────────────────────────
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

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
        if db.showItemLevels then SetupItemLevels()     end
        if db.showMapCoords  then SetupMapCoordinates() end

        if db.autoSellJunk or db.autoRepair then
            self:RegisterEvent("MERCHANT_SHOW")
        end

        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("Quality of Life", "Loaded. Type |cFFFFFF00/qol|r to open settings.")

    elseif event == "MERCHANT_SHOW" then
        if db.autoRepair   then AutoRepair()  end
        if db.autoSellJunk then AutoSellJunk() end
    end
end)

-- ── Slash commands ──────────────────────────────────────────
SLASH_VERITASUI_QOL1 = "/qol"
SLASH_VERITASUI_QOL2 = "/qualityoflife"
SlashCmdList["VERITASUI_QOL"] = function()
    Settings.OpenToCategory(settingsCategoryID)
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_QualityOfLife_OnAddonCompartmentClick()
    C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
end
