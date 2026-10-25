-- VeritasUI_AuctionHouse / Settings.lua
-- Native Blizzard Settings entry (Options → AddOns → Auction House).
--
-- Real toggles for the tooltip price display, bound to AH.db.settings.
-- NOTE: this module has no managed UIPanel window — its in-AH UI is the sell
-- strip mounted on Blizzard's native Sell tab (see UI/SellStrip.lua). This
-- Settings category holds the global tooltip toggles.

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
                -- Live variant: tooltip toggles take effect on the next
                -- hover — no /reload involved.
                VUI.PrintOnOffLive(AH.TAG, name, value)
            end)
            Settings.CreateCheckbox(category, setting, tip)
        end

        AddCheckbox("ttShowPrice", true, "Show Auction Price in Tooltips",
            "Adds the item's auction price to its tooltip, anywhere in the game. "
            .. "Scan at the Auction House to update prices.")

        AddCheckbox("ttShowQty", true, "Show Quantity Seen",
            "Adds how many were listed at the last scan.")

        AddCheckbox("ttShowAge", true, "Show Price Age",
            "Shows how many days old the price is, when it isn't from today.")

        AddCheckbox("craftShowReagentValue", true, "Show Reagents Value on Crafting Orders",
            "Adds a |cFFFFFF00Reagents Value:|r line to the Place Crafting Order form: what "
            .. "the recipe's reagents would sell for at the Auction House.")

        AddCheckbox("liveSearchPrices", true, "Correct Prices from Live Searches",
            "When you look at an item on the Buy or Sell tab, its saved price is updated from "
            .. "the current listings. It doesn't affect the scan cooldown.")

        -- Auto-scan on AH open: REMOVED (2026-07-02). Scans are user-initiated via
        -- the Scan button (UI/ScanButton.lua) or /ah scan. The auto-fire-on-open
        -- path was the locus of the first-open-of-session replicate hang; Core's
        -- InitDB drops the orphaned db.settings.autoScan key.
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
