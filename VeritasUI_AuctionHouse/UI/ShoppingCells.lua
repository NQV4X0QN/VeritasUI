-- VeritasUI_AuctionHouse / UI/ShoppingCells.lua
-- Cell mixins for the Shopping results table (driven by Blizzard's TableBuilder).
-- Templates are defined in UI/ShoppingCells.xml; these mixins implement the
-- TableBuilder cell contract: :Init(...) (one-time, gets the column's cellParameters)
-- and :Populate(rowData, index) (per row).
--
-- XML mixins MUST be globals (the XML loader resolves them by name), so these are
-- intentionally global. They reach module state through the addon's shared AH table,
-- captured from the file vararg here. (Load order: TOC lists this file under UI/, so
-- it shares the same ADDON_NAME, AH = ... vararg as every other module file; the AH
-- table already has .Money/.DB/.Search defined by the time a cell is ever Populated,
-- which only happens after a search — long after load.)

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  VUIAHTextCellMixin — plain left text from a named field
----------------------------------------------------------------
VUIAHTextCellMixin = {}

function VUIAHTextCellMixin:Init(fieldName)
    self.fieldName = fieldName
end

function VUIAHTextCellMixin:Populate(rowData, index)
    local v = rowData and self.fieldName and rowData[self.fieldName]
    if type(v) == "number" then v = (v > 0 and tostring(v) or "") end
    self.Text:SetText(v or "")
end

----------------------------------------------------------------
--  VUIAHMoneyCellMixin — native coin display from a named copper field
--    fieldName "minPrice" → live lowest; "scannedPrice" → our DB price (resolved here)
----------------------------------------------------------------
VUIAHMoneyCellMixin = {}

function VUIAHMoneyCellMixin:Init(fieldName)
    self.fieldName = fieldName
end

function VUIAHMoneyCellMixin:Populate(rowData, index)
    local copper
    if self.fieldName == "scannedPrice" then
        -- EXACT-MATCH-ONLY DB price (OQ#6): blank on a miss, never an estimate.
        if AH.DB and rowData then
            if rowData.appearanceLink then
                copper = AH.DB.GetMarketPriceForLink(rowData.appearanceLink)
            end
            if not copper and rowData.itemID then
                copper = AH.DB.GetMarketPrice("i:" .. rowData.itemID)
            end
        end
    else
        copper = rowData and self.fieldName and rowData[self.fieldName]
    end

    if copper and copper > 0 then
        self.MoneyDisplay:SetAmount(copper)
        self.MoneyDisplay:Show()
    else
        self.MoneyDisplay:SetAmount(0)
        self.MoneyDisplay:Hide()   -- show nothing for unpriced (esp. Scanned misses)
    end
end

----------------------------------------------------------------
--  VUIAHItemCellMixin — icon + quality-colored name from the row's itemKey
----------------------------------------------------------------
VUIAHItemCellMixin = {}

function VUIAHItemCellMixin:Init()
    -- no params; reads rowData.itemKey
end

function VUIAHItemCellMixin:Populate(rowData, index)
    local info = AH.Search and rowData and AH.Search.GetKeyInfo(rowData.itemKey)
    if info and info.itemName and info.itemName ~= "" then
        local r, g, b = 1, 1, 1
        if info.quality and C_Item and C_Item.GetItemQualityColor then
            local cr, cg, cb = C_Item.GetItemQualityColor(info.quality)
            if cr then r, g, b = cr, cg, cb end
        end
        self.Text:SetText(info.itemName)
        self.Text:SetTextColor(r, g, b)
        if info.iconFileID then
            self.Icon:SetTexture(info.iconFileID)
            self.Icon:Show()
        else
            self.Icon:Hide()
        end
    else
        self.Text:SetText("...")
        self.Text:SetTextColor(0.6, 0.6, 0.6)
        self.Icon:Hide()
    end
end

