-- VeritasUI_AuctionHouse / Settings.lua
-- Native Blizzard Settings entry (discovery point in Options → AddOns).
--
-- PHASE 0: a bare category so the module is discoverable and the shared
-- Reload-UI button appears. No toggles yet. NOTE: unlike PR/AO, the AH
-- module's main UI is INJECTED TABS on Blizzard's AuctionHouseFrame
-- (see AUCTIONHOUSE_DESIGN.md §2.9) — so we deliberately do NOT register
-- a managed UIPanel window here.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local SETTINGS_LABEL = "Auction House"

local function BuildNativeSettingsPanel()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    -- No toggleable settings yet — the panel exists as a discovery
    -- mechanism. Feature toggles (tooltip price display, etc.) arrive
    -- with the phases that introduce them.

    Settings.RegisterAddOnCategory(category)
    AH.settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok, err = pcall(BuildNativeSettingsPanel)
    if not ok then
        VUI.Print(AH.TAG or "Auction House",
            "|cFFFF4444Settings error:|r " .. tostring(err))
    end
    initFrame:UnregisterAllEvents()
end)
