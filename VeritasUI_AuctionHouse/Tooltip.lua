-- VeritasUI_AuctionHouse / Tooltip.lua
-- Phase 3: append the stored market price to item tooltips.
--
-- Pure DB READ — no live AH query, works offline (away from the AH), and is
-- read-only so it carries no taint risk. Uses the modern tooltip hook
-- (verified 12.0.5): TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn).
-- The callback receives (tooltip, data); data.hyperlink is the item link, which
-- AH.DB keys/prices directly. (TooltipUtil.GetDisplayedItem is the fallback path
-- for the rare case data.hyperlink is absent but a GUID is present.)

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local TooltipDataProcessor = TooltipDataProcessor
local TooltipUtil          = TooltipUtil
local Enum                 = Enum
local pairs                = pairs

AH.Tooltip = {}

-- Defaults for the Phase 3 toggles. Seeded into db.settings on first run; all on.
local TT_DEFAULTS = {
    ttShowPrice = true,   -- show "AH:" market price line
    ttShowAge   = true,   -- annotate stale prices with their age in days
    ttShowQty   = true,   -- show last-seen quantity
}

local function S(key)
    local s = AH.db and AH.db.settings
    if not s then return TT_DEFAULTS[key] end
    if s[key] == nil then return TT_DEFAULTS[key] end
    return s[key]
end
AH.Tooltip.Setting = S

-- Seed missing toggle defaults (called once, after AH.db exists).
function AH.Tooltip.SeedDefaults()
    if not AH.db then return end
    AH.db.settings = AH.db.settings or {}
    for k, v in pairs(TT_DEFAULTS) do
        if AH.db.settings[k] == nil then
            AH.db.settings[k] = v
        end
    end
end

----------------------------------------------------------------
--  The price line builder
----------------------------------------------------------------
local LABEL_COLOR = "|cFF00CCFF"   -- VUI cyan, matches VUI.Print prefix tint
local VALUE_COLOR = "|cFFFFFFFF"

-- Append our line(s) to a tooltip for the given item link, if we have a price.
local function AppendPrice(tooltip, link)
    if not S("ttShowPrice") then return end
    if not (AH.DB and link) then return end

    local price, key = AH.DB.GetMarketPriceForLink(link)
    if not price or price <= 0 then return end

    -- Main price line: "Auction (each): 12g 34s 56c"
    local money = AH.Money and AH.Money.Format(price) or tostring(price)
    tooltip:AddDoubleLine(
        LABEL_COLOR .. "Auction (each)|r",
        VALUE_COLOR .. money .. "|r")

    -- Optional quantity-seen + age annotations on a secondary line.
    local extras = {}
    if S("ttShowQty") then
        local hist = AH.DB.GetPriceHistory(key)
        local today = hist[1]
        if today and today.qty and today.qty > 0 then
            extras[#extras + 1] = today.qty .. " seen"
        end
    end
    if S("ttShowAge") then
        local age = AH.DB.GetPriceAge(key)
        if age and age > 0 then
            extras[#extras + 1] = (age == 1 and "1 day old" or (age .. " days old"))
        end
    end
    if #extras > 0 then
        tooltip:AddLine("|cFF808080" .. table.concat(extras, "  ·  ") .. "|r")
    end
end

----------------------------------------------------------------
--  Hook registration
--
--  AddTooltipPostCall fires on every tooltip (re)build. We re-derive the link
--  fresh each call (cheap) and let Blizzard's own rebuild clear prior lines, so
--  there is no line-stacking on repeated refreshes — each rebuild starts clean
--  and we append exactly once.
----------------------------------------------------------------
local function OnItemTooltip(tooltip, data)
    -- Only handle the shared GameTooltip + ItemRefTooltip family. Some internal
    -- tooltips (compare shopping, etc.) are children we don't want to touch.
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

    local link = data and data.hyperlink
    if not link and TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, l = TooltipUtil.GetDisplayedItem(tooltip)
        link = l
    end
    if not link then return end

    -- Read-only DB lookup; pcall-guarded so a malformed link never errors a tooltip.
    pcall(AppendPrice, tooltip, link)
end

local function Register()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
            and Enum and Enum.TooltipDataType) then
        if VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444Tooltip hook unavailable|r (API missing).")
        end
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

----------------------------------------------------------------
--  Startup — seed defaults then register the hook on login.
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function()
    AH.Tooltip.SeedDefaults()
    Register()
    ef:UnregisterAllEvents()
end)
