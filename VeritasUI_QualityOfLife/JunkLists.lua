-- VeritasUI_QualityOfLife / JunkLists.lua
-- Junk Lists (v1.80.0; the idea from Leatrix Plus's sell-junk exclusions, none of its code). Two lists Auto Sell
-- Junk reads (QualityOfLife.lua VUI.QoL_IsJunk): Never Sell (greys kept) and Always Sell (anything with a sell price
-- sold as junk), universal db.junkNeverSell / db.junkAlwaysSell, [itemID] = true. An item is put on a list by
-- dragging it from your bags into the window -- the cursor's item (GetCursorInfo "item", itemID, CursorDocumentation
-- both games) read on our own frame's OnReceiveDrag / OnMouseUp, then ClearCursor -- so nothing of Blizzard's bags is
-- hooked (the v1.17.4 UseContainerItem lesson). Right-click a row to take it off. An item put on one list leaves the
-- other.
--
-- THE WINDOW: ButtonFrameTemplate with the flat inset (Lib VUI.UseFlatInsetBackground), as Advanced Options and
-- Priority Rotation; tabs at the bottom in Retail, LargeSideTabButtonTemplate side tabs in WoW Forever (Lib
-- VUI.CreateSideTabs), as Advanced Options. Rows are the mount list's (PetList-ButtonBackground block, the icon
-- outside it on the left in the bags' slot border), as Priority Rotation's (Editor.lua); the name in its quality
-- colour (C_Item.GetItemQualityColor). Hints in tooltips: "Right-click to remove" in LIGHTBLUE.
-- Also: the Keep Unbound Grey Gear sub-option and the Open button on the options page (VUI.QoL_JunkOptions), and
-- /qol junk.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, pairs = pcall, ipairs, pairs
local ADDON = "VeritasUI_QualityOfLife"
local WIN_NAME = "VeritasUI_JunkListsWindow"
local W, H = 338, 424                 -- the trainer window's size (Trainer.lua), a plain list window
local ROW_H, ICON_SZ, ICON_X = 40, 32, 8
local BLOCK_X = ICON_X + ICON_SZ + 4

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local LISTS = {
    { key = "junkNeverSell",  title = "Never Sell",  icon = "Interface\\Icons\\INV_Misc_Bag_10",
      empty = "Drag a grey item here to keep it.", tip = "Greys you keep: Auto Sell Junk leaves them in your bags." },
    { key = "junkAlwaysSell", title = "Always Sell", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      empty = "Drag an item here to sell it as junk.",
      tip = "Items Auto Sell Junk sells like greys, unless you could still get a refund or trade it to your group." },
}
local cur = 1

-- Lib's registration, at file load as the other windows do (Lib.lua RegisterManagedPanel notes).
VUI.RegisterManagedPanel(WIN_NAME, { area = "left", pushable = 2 })

local win

local function List(i)
    local db = DB()
    if type(db) ~= "table" then return {} end
    local key = LISTS[i].key
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

-- The bags' slot border, as Priority Rotation draws it (Editor.lua SlotBorder): UI-Quickslot2, 64 px on a 37 px
-- button, 1 px low (Blizzard_ItemButton/Shared/ItemButtonTemplate.xml:70-75).
local function SlotBorder(owner, size)
    local border = owner:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    local sz = math.floor(size * 64 / 37 + 0.5)
    border:SetSize(sz, sz)
    border:SetPoint("CENTER", owner, "CENTER", 0, -1)
    return border
end

local Refresh

-- Adds the item on the cursor to the list on show. Returns true when it took one.
local function TakeCursorItem()
    local ok, kind, itemID = pcall(GetCursorInfo)
    if not (ok and kind == "item" and type(itemID) == "number") then return false end
    ClearCursor()
    local okI, name, link, _, _, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, itemID)
    if cur == 2 and okI and name and not (type(price) == "number" and price > 0) then
        VUI.Print("Quality of Life", (link or name) .. " has no sell price.")
        return true
    end
    List(cur)[itemID] = true
    List(cur == 1 and 2 or 1)[itemID] = nil
    if okI and name then
        VUI.Print("Quality of Life", (link or name) .. " added to " .. LISTS[cur].title .. ".")
    end
    Refresh()
    return true
end

local function RowTooltip(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetItemByID, GameTooltip, row.itemID)
    GameTooltip:AddLine("Right-click to remove", LIGHTBLUE_FONT_COLOR:GetRGB())
    GameTooltip:Show()
end

local function BuildRow(row)
    row.built = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local block = row:CreateTexture(nil, "BACKGROUND")
    block:SetAtlas("PetList-ButtonBackground")
    block:SetPoint("TOPLEFT", row, "TOPLEFT", BLOCK_X, -2)
    block:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", ICON_X, 0)
    row.icon = icon
    local holder = CreateFrame("Frame", nil, row)
    holder:SetAllPoints(icon)
    SlotBorder(holder, ICON_SZ)
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", block, "LEFT", 8, 0)
    name:SetPoint("RIGHT", block, "RIGHT", -8, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, btn)
        if TakeCursorItem() then return end
        if btn == "RightButton" and self.itemID then
            List(cur)[self.itemID] = nil
            GameTooltip:Hide()
            Refresh()
        end
    end)
    row:SetScript("OnReceiveDrag", TakeCursorItem)
end

local function InitRow(row, itemID)
    if not row.built then BuildRow(row) end
    row.itemID = itemID
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    row.icon:SetTexture(icon or 134400)   -- 134400: the question-mark icon until the item's data loads
    local okI, name, _, quality = pcall(C_Item.GetItemInfo, itemID)
    if okI and name then
        local r, g, b = 1, 1, 1
        if C_Item.GetItemQualityColor and quality then
            local okQ, qr, qg, qb = pcall(C_Item.GetItemQualityColor, quality)
            if okQ and qr then r, g, b = qr, qg, qb end
        end
        row.name:SetText(name)
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetText(RETRIEVING_ITEM_INFO or "Retrieving item information")
        row.name:SetTextColor(GRAY_FONT_COLOR:GetRGB())
        if Item and Item.CreateFromItemID then
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() if win and win:IsShown() then Refresh() end end)
        end
    end
    if GameTooltip:IsOwned(row) then RowTooltip(row) end
end

function Refresh()
    if not (win and win:IsShown()) then return end
    if win.selectTab then win.selectTab(cur) end
    win.subtitle:SetText(LISTS[cur].title)
    local ids = {}
    for id, on in pairs(List(cur)) do if on then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b)
        local na = C_Item.GetItemInfo(a) or ""
        local nb = C_Item.GetItemInfo(b) or ""
        if na == nb then return a < b end
        return na < nb
    end)
    local provider = CreateDataProvider()
    for _, id in ipairs(ids) do provider:Insert(id) end
    win.ScrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    win.empty:SetText(LISTS[cur].empty)
    win.empty:SetShown(#ids == 0)
end

local function Select(i) cur = i; Refresh() end
VUI.QoL_JunkTakeCursor, VUI.QoL_JunkSelect = TakeCursorItem, Select   -- for qol_junklists_test

local function BuildWindow()
    win = CreateFrame("Frame", WIN_NAME, UIParent, "ButtonFrameTemplate")
    win:SetSize(W, H)
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:Hide()
    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function(self) VUI.CloseManagedPanel(self:GetParent()) end)
    end
    if win.SetTitle then win:SetTitle("Junk Lists") end
    if win.SetPortraitToAsset then
        win:SetPortraitTexCoord(0, 1, 0, 1)
        win:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_02")
    end
    VUI.UseFlatInsetBackground(win)

    local subtitle = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    subtitle:SetPoint("TOP", win, "TOP", 0, -32)
    subtitle:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    win.subtitle = subtitle

    -- The list fills the Inset; the whole Inset takes a dropped item, so it need not land on a row.
    local inset = win.Inset or win
    local drop = CreateFrame("Button", nil, win)
    drop:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    drop:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    drop:RegisterForClicks("LeftButtonUp")
    drop:SetScript("OnReceiveDrag", TakeCursorItem)
    drop:SetScript("OnClick", TakeCursorItem)
    drop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(LISTS[cur].title, HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:AddLine(LISTS[cur].tip, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        GameTooltip:AddLine("Drag an item from your bags here", LIGHTBLUE_FONT_COLOR:GetRGB())
        GameTooltip:Show()
    end)
    drop:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local box = CreateFrame("Frame", nil, drop, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", drop, "TOPLEFT", 0, -2)
    box:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", -18, 2)
    win.ScrollBox = box
    local bar = CreateFrame("EventFrame", nil, drop, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 5, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 5, 2)
    local view = CreateScrollBoxListLinearView(2, 2, 0, 0, 0)
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    local empty = drop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", box, "CENTER")
    empty:SetWidth(W - 60)
    win.empty = empty

    if VUI.IS_FOREVER and VUI.CreateSideTabs then
        local select = VUI.CreateSideTabs(win, {
            { icon = LISTS[1].icon, tooltip = LISTS[1].title },
            { icon = LISTS[2].icon, tooltip = LISTS[2].title },
        }, Select)
        win.selectTab = select
    else
        local t1 = CreateFrame("Button", "$parentTab1", win, "PanelTabButtonTemplate")
        t1:SetID(1)
        t1:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 11, -30)
        t1:SetText(LISTS[1].title)
        PanelTemplates_TabResize(t1, 0)
        local t2 = CreateFrame("Button", "$parentTab2", win, "PanelTabButtonTemplate")
        t2:SetID(2)
        t2:SetPoint("LEFT", t1, "RIGHT", -16, 0)
        t2:SetText(LISTS[2].title)
        PanelTemplates_TabResize(t2, 0)
        PanelTemplates_SetNumTabs(win, 2)
        t1:SetScript("OnClick", function() Select(1) end)
        t2:SetScript("OnClick", function() Select(2) end)
        win.selectTab = function(i) PanelTemplates_SetTab(win, i) end
    end

    win:SetScript("OnShow", Refresh)
    if VUI.AddWindowSounds and SOUNDKIT then
        VUI.AddWindowSounds(win, SOUNDKIT.IG_CHARACTER_INFO_OPEN, SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end
end

local function ToggleWindow()
    if not win then BuildWindow() end
    if win:IsShown() then VUI.CloseManagedPanel(win) else VUI.OpenManagedPanel(win) end
end
VUI.QoL_JunkListsToggle = ToggleWindow

-- The options page: Keep Unbound Grey Gear indented under Auto Sell Junk, then the Open button.
VUI.QoL_JunkOptions = function(layout, keepInit)
    if keepInit and VUI.SettingsSubOption then
        VUI.SettingsSubOption(keepInit, ADDON .. "_autoSellJunk",
            function() return VUI.QoL_Live and VUI.QoL_Live("autoSellJunk") end)
    end
    if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
        local opener = { open = function() if not (win and win:IsShown()) then ToggleWindow() end end }
        layout:AddInitializer(CreateSettingsButtonInitializer("Junk Lists", "Open",
            function() VUI._OpenFromSettings(opener) end,
            "Items Auto Sell Junk keeps although they are grey, and items it sells although they are not. "
            .. "Drag items from your bags into the window; right-click one to take it off.", false))
    end
end
