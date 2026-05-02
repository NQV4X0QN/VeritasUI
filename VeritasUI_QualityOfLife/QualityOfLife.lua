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
    showItemLevels = true,
    showMapCoords  = true,
}

local db
local settingsCategoryID
local frame = CreateFrame("Frame")

-- ── /way — proximity auto-clear state ───────────────────────
local wayTicker        = nil
local WAY_ARRIVAL_YARDS = 10

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
-- Event-driven selling: sells up to SELL_BATCH items per cycle,
-- then waits for BAG_UPDATE_DELAYED (fired after the client
-- processes bag changes) before selling the next batch.  This
-- lets the game's own event cadence throttle the sell rate,
-- handling any number of junk items reliably.
-- Gold reporting uses GetMoney() delta (before/after) rather than
-- item price lookups, which are unreliable with Midnight secret values.
local SELL_BATCH = 9
local sellState       -- nil when idle; table { count, startMoney } when selling

local function SellNextBatch()
    if not sellState then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then
        sellState = nil
        frame:UnregisterEvent("BAG_UPDATE_DELAYED")
        return
    end

    local sold = 0
    local remaining = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue then
                remaining = remaining + 1
                if not info.isLocked then
                    C_Container.UseContainerItem(bag, slot)
                    sellState.count = sellState.count + 1
                    sold = sold + 1
                    if sold >= SELL_BATCH then return end   -- pause; BAG_UPDATE_DELAYED will resume
                end
            end
        end
    end

    -- If any items are still locked (pending server confirmation), wait for the next event.
    if remaining > 0 then return end

    -- No remaining junk — finish up.
    frame:UnregisterEvent("BAG_UPDATE_DELAYED")

    local count      = sellState.count
    local startMoney = sellState.startMoney
    sellState = nil

    if count == 0 then return end

    -- Use GetMoney() delta for accurate reporting; wait one frame so the
    -- server-side money update is reflected in the client value.
    C_Timer.After(0, function()
        local earned = GetMoney() - startMoney
        if earned < 0 then earned = 0 end
        VUI.Print("Quality of Life", format(
            "Sold |cFFFFFF00%d|r junk item%s for %s",
            count, count > 1 and "s" or "",
            GetCoinTextureString(earned)))
    end)
end

local function AutoSellJunk()
    sellState = { count = 0, startMoney = GetMoney() }
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    SellNextBatch()
end

-- ── Feature: Auto Repair ────────────────────────────────────
-- Tries guild repair first, then personal gold covers any remainder.
-- GetRepairAllCost() after RepairAllItems(true) reflects a client-cached
-- value that updates asynchronously from the server, so we cannot reliably
-- split costs between guild and personal in the same frame.  Instead, we
-- always call RepairAllItems(false) after the guild attempt to cover any
-- shortfall, and report the original total cost.
local function AutoRepair()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost == 0 then return end

    if IsInGuild() and CanGuildBankRepair() then
        RepairAllItems(true)   -- guild funds first
        RepairAllItems(false)  -- personal gold covers any remainder
        VUI.Print("Quality of Life", format(
            "Repaired for %s (guild bank)", GetCoinTextureString(cost)))
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
    mf:RegisterEvent("MERCHANT_SHOW")
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
        if not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
        local container = WorldMapFrame.ScrollContainer

        -- Hide the quest log show/hide toggle button in the bottom-right.
        local toggle = WorldMapFrame.SidePanelToggle
        if toggle then VUI.SuppressFrame(toggle) end

        -- Invisible container button — no backdrop, no border, no tint.
        -- Must be a Button (not Frame) so RegisterForClicks works.
        local anchor = CreateFrame("Button", nil, container)
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
            self._t = (self._t or 0) + elapsed
            if self._t < THROTTLE then return end
            self._t = 0

            local mapID = C_Map.GetBestMapForUnit("player")

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
            end

            ResizeAnchor()
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
          tip = "Displays player and cursor coordinates on the World Map. Right-click the coordinates to unlock and reposition. Hides the quest log toggle button." },
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
frame:RegisterEvent("USER_WAYPOINT_UPDATED")

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
            self:RegisterEvent("MERCHANT_CLOSED")
        end

        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("Quality of Life", "Loaded. Type |cFFFFFF00/qol|r to open settings.")

    elseif event == "MERCHANT_SHOW" then
        if db.autoRepair   then AutoRepair()  end
        if db.autoSellJunk then C_Timer.After(0, AutoSellJunk) end

    elseif event == "MERCHANT_CLOSED" then
        if sellState then
            frame:UnregisterEvent("BAG_UPDATE_DELAYED")
            sellState = nil
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        SellNextBatch()

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
SLASH_VERITASUI_WAY1 = "/way"
SlashCmdList["VERITASUI_WAY"] = function(msg)
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
            .. "(e.g. |cFFFFFF00/way #2351 45.2 56.3|r)  —  "
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
