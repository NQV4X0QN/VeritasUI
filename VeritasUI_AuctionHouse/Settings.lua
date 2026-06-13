-- VeritasUI_AuctionHouse / Settings.lua
-- Native Blizzard Settings entry (Options → AddOns → Auction House).
--
-- Real toggles for the tooltip price display, bound to AH.db.settings.
-- NOTE: this module has no managed UIPanel window — its in-AH UI is the sell
-- strip mounted on Blizzard's native Sell tab (see UI/SellStrip.lua). This
-- Settings category holds the global tooltip toggles only.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local SETTINGS_LABEL = "Auction House"

local function BuildNativeSettingsPanel()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    -- Seed the tooltip defaults here too, so this panel never depends on
    -- Tooltip.lua's PLAYER_LOGIN frame having fired first (cross-frame event
    -- dispatch order is not guaranteed). SeedDefaults is the single seeding
    -- authority and is idempotent — calling it from both paths only fills nils.
    if AH.Tooltip and AH.Tooltip.SeedDefaults then
        AH.Tooltip.SeedDefaults()
    end

    -- Tooltip toggles bind directly to AH.db.settings (InitDB on ADDON_LOADED
    -- guarantees AH.db exists; SeedDefaults above guarantees the keys exist).
    local store = AH.db and AH.db.settings
    if store then
        local function AddCheckbox(key, default, name, tip)
            local setting = Settings.RegisterAddOnSetting(
                category, ADDON_NAME .. "_" .. key, key,
                store, "boolean", name, default)
            setting:SetValueChangedCallback(function(_, value)
                VUI.PrintOnOff(AH.TAG, name, value)
            end)
            Settings.CreateCheckbox(category, setting, tip)
        end

        AddCheckbox("ttShowPrice", true, "Show Auction Price in Tooltips",
            "Appends the last-scanned market price (per unit) to item tooltips. "
            .. "Pure database read — works away from the Auction House. "
            .. "Run |cFFFFFF00/ah scan|r at the AH to refresh prices.")

        AddCheckbox("ttShowQty", true, "Show Quantity Seen",
            "Adds the quantity seen at the last scan beneath the price line.")

        AddCheckbox("ttShowAge", true, "Show Price Age",
            "Annotates how many days old the stored price is when it isn't from today's scan.")
    end

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
