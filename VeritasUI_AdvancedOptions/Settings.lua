-- VeritasUI_AdvancedOptions / Settings.lua
-- Main window (PortraitFrameTemplate + tabs) + native Blizzard Settings entry.

local ADDON_NAME, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

local SETTINGS_LABEL = "Advanced Options"

local PNL_W     = 520
local PNL_H     = 660

----------------------------------------------------------------
--  Register with Blizzard's UIPanel manager at FILE LOAD time.
--  Same pattern as PriorityRotation — Tier A primary panel.
----------------------------------------------------------------
VUI.RegisterManagedPanel("AdvancedOptionsMainWindow", {
    area     = "left",
    pushable = 0,
})

----------------------------------------------------------------
--  Portrait — gear icon for a settings-oriented panel.
----------------------------------------------------------------
local function ApplyPortrait(frame)
    local portrait = (frame.PortraitContainer and frame.PortraitContainer.portrait)
                  or frame.portrait
    if not portrait then return end
    portrait:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

----------------------------------------------------------------
--  Main Window Builder
----------------------------------------------------------------
local function BuildMainWindow()
    local win = CreateFrame("Frame", "AdvancedOptionsMainWindow", UIParent, "PortraitFrameTemplate")
    win:SetSize(PNL_W, PNL_H)
    win:EnableMouse(true)
    win:Hide()
    win:SetToplevel(true)

    -- Wire close button through UIPanel manager
    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function(self)
            HideUIPanel(self:GetParent())
        end)
    end

    -- Title
    if win.SetTitle then
        win:SetTitle("Advanced Options")
    elseif win.TitleContainer and win.TitleContainer.TitleText then
        win.TitleContainer.TitleText:SetText("Advanced Options")
    elseif win.TitleText then
        win.TitleText:SetText("Advanced Options")
    end

    -- Center the title
    local titleText = (win.TitleContainer and win.TitleContainer.TitleText)
                   or win.TitleText
    if titleText then
        titleText:ClearAllPoints()
        titleText:SetPoint("TOP", win, "TOP", 0, -5)
    end

    ApplyPortrait(win)

    -- ── Content panels ────────────────────────────────────────
    local CONTENT = CreateFrame("Frame", nil, win)
    CONTENT:SetPoint("TOPLEFT",     win, "TOPLEFT",     8,  -28)
    CONTENT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8,   6)

    -- Subtitle — centered below the portrait area
    local subtitle = CONTENT:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    subtitle:SetPoint("TOP", CONTENT, "TOP", 0, -12)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(1, 1, 1)
    subtitle:SetText("Advanced Options")

    -- Featured tab content container
    local contFeatured = CreateFrame("Frame", nil, CONTENT)
    contFeatured:SetPoint("TOPLEFT",     CONTENT, "TOPLEFT",      4, -40)
    contFeatured:SetPoint("BOTTOMRIGHT", CONTENT, "BOTTOMRIGHT", -4,   4)

    -- Browser tab content container
    local contBrowser = CreateFrame("Frame", nil, CONTENT)
    contBrowser:SetPoint("TOPLEFT",     CONTENT, "TOPLEFT",      4, -40)
    contBrowser:SetPoint("BOTTOMRIGHT", CONTENT, "BOTTOMRIGHT", -4,   4)
    contBrowser:Hide()

    -- ── Bottom Tabs ───────────────────────────────────────────
    local tabFeatured = CreateFrame("Button", "$parentTab1", win, "PanelTabButtonTemplate")
    tabFeatured:SetID(1)
    tabFeatured:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 11, -30)
    tabFeatured:SetText("Featured")
    PanelTemplates_TabResize(tabFeatured, 0)

    local tabBrowser = CreateFrame("Button", "$parentTab2", win, "PanelTabButtonTemplate")
    tabBrowser:SetID(2)
    tabBrowser:SetPoint("LEFT", tabFeatured, "RIGHT", -16, 0)
    tabBrowser:SetText("All CVars")
    PanelTemplates_TabResize(tabBrowser, 0)

    PanelTemplates_SetNumTabs(win, 2)
    PanelTemplates_SetTab(win, 1)

    local function ActivateTab(which)
        local idx = (which == "browser") and 2 or 1
        PanelTemplates_SetTab(win, idx)
        contFeatured:SetShown(idx == 1)
        contBrowser:SetShown(idx == 2)
        subtitle:SetText(idx == 1 and "Advanced Options" or "All CVars")
        -- Persist last tab
        if AO.db then AO.db.lastTab = idx end
    end

    tabFeatured:SetScript("OnClick", function() ActivateTab("featured") end)
    tabBrowser:SetScript("OnClick",  function() ActivateTab("browser")  end)

    function win:ShowTab(which)
        VUI.OpenManagedPanel(self)
        ActivateTab(which)
    end

    -- ── Build tab contents ────────────────────────────────────
    AO:BuildFeaturedContent(contFeatured)
    AO:BuildBrowserContent(contBrowser)

    win:SetScript("OnShow", function()
        ApplyPortrait(win)
    end)

    AO.MainWindow = win
end

----------------------------------------------------------------
--  Native Blizzard Settings Panel
--
--  Registers a simple category in Options → AddOns so users
--  can discover the module exists. The actual UI is the custom
--  PortraitFrame window opened via /ao.
----------------------------------------------------------------
local function BuildNativeSettingsPanel()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    -- No toggleable settings yet — the panel just exists as a
    -- discovery mechanism. We can add global on/off toggles later.

    Settings.RegisterAddOnCategory(category)
    AO.settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

----------------------------------------------------------------
--  Startup
----------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok1, err1 = pcall(BuildMainWindow)
    if not ok1 then
        VUI.Print("Advanced Options",
            "|cFFFF4444Window error:|r " .. tostring(err1))
    end

    local ok2, err2 = pcall(BuildNativeSettingsPanel)
    if not ok2 then
        VUI.Print("Advanced Options",
            "|cFFFF4444Settings error:|r " .. tostring(err2))
    end

    initFrame:UnregisterAllEvents()
end)
