-- VeritasUI_AdvancedOptions / Settings.lua
-- Main window (ButtonFrameTemplate + tabs).
--
-- Options -> AddOns -> VeritasUI -> Advanced Options (back in v1.58.0, owner's request). Until v1.12.2
-- this module registered an EMPTY category purely to be listed, which read as broken (owner, 2026-07-28),
-- so it was removed. It returns with real content: the page header's Open button (Lib,
-- VUI.RegisterSettingsLabel with an open function) and one row per tab of the window, each with an Open
-- button (Blizzard's own button row, CreateSettingsButtonInitializer, Blizzard_SettingControls.lua:910).
-- Every setting still lives in the window; the page is how a player finds it.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

local PNL_W     = 520
local PNL_H     = 660

----------------------------------------------------------------
--  Register with Blizzard's UIPanel manager at FILE LOAD time.
--  Same pattern as PriorityRotation — Tier A primary panel.
----------------------------------------------------------------
-- pushable 2 (owner, 2026-11-07): Blizzard sorts pushable windows left to right by this value, lowest first
-- (UIParentPanelManager.lua:54-58), so Professions (1) takes the far left, then ours, then Character Info (3);
-- with 0 ours stayed leftmost and pushed Professions into the middle.
VUI.RegisterManagedPanel("AdvancedOptionsMainWindow", {
    area     = "left",
    pushable = 2,
})

----------------------------------------------------------------
--  Portrait — gear icon for a settings-oriented panel.
----------------------------------------------------------------
-- Through Blizzard's own PortraitFrameMixin calls, the way SetPortraitToSpecIcon
-- does it (PortraitFrame.lua:78-79): the full icon, no border trim, so the zoom
-- matches Blizzard's portraits (e.g. Character Info).
local function ApplyPortrait(frame)
    if not frame.SetPortraitToAsset then return end
    frame:SetPortraitTexCoord(0, 1, 0, 1)
    frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Gear_01")
end

----------------------------------------------------------------
--  Main Window Builder
----------------------------------------------------------------
local function BuildMainWindow()
    -- ButtonFrameTemplate (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:660-693): the
    -- portrait frame plus its recessed Inset and the 26 px button bar along the bottom -- the frame
    -- the Auction House's bottom row and the Macro window are built on (owner's request, v1.35.10).
    -- The tab content sits in win.Inset; the bar holds a tab's main button (Featured: Collapse All).
    local win = CreateFrame("Frame", "AdvancedOptionsMainWindow", UIParent, "ButtonFrameTemplate")
    win:SetSize(PNL_W, PNL_H)
    win:EnableMouse(true)
    win:Hide()
    win:SetToplevel(true)

    -- Wire close button through UIPanel manager
    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function(self)
            VUI.CloseManagedPanel(self:GetParent())
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
    -- Inside Blizzard's recessed Inset. The fallback anchors match ButtonFrameTemplate's own Inset
    -- (TOPLEFT 4,-60 / BOTTOMRIGHT -6,26) should a client ever lack it.
    -- Flat Auction House background in the Inset instead of the old marble (Lib).
    VUI.UseFlatInsetBackground(win)

    local CONTENT = CreateFrame("Frame", nil, win)
    if win.Inset then
        CONTENT:SetPoint("TOPLEFT",     win.Inset, "TOPLEFT",      4, -4)
        CONTENT:SetPoint("BOTTOMRIGHT", win.Inset, "BOTTOMRIGHT", -4,  4)
    else
        CONTENT:SetPoint("TOPLEFT",     win, "TOPLEFT",      8, -64)
        CONTENT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 30)
    end

    -- Subtitle — centered in the band between the title bar and the Inset
    local subtitle = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    subtitle:SetPoint("TOP", win, "TOP", 0, -32)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    subtitle:SetText("Featured Settings")

    -- Featured tab content container
    local contFeatured = CreateFrame("Frame", nil, CONTENT)
    contFeatured:SetAllPoints(CONTENT)

    -- Browser tab content container
    local contBrowser = CreateFrame("Frame", nil, CONTENT)
    contBrowser:SetAllPoints(CONTENT)
    contBrowser:Hide()

    -- ── Tabs ──────────────────────────────────────────────────
    -- WoW Forever: icon tabs down the right edge (Lib VUI.CreateSideTabs, owner 2026-11-05); Retail: bottom tabs.
    local selectTab
    local function ActivateTab(which)
        local idx = (which == "browser") and 2 or 1
        selectTab(idx)
        contFeatured:SetShown(idx == 1)
        contBrowser:SetShown(idx == 2)
        subtitle:SetText(idx == 1 and "Featured Settings" or "All CVars")
        -- Persist last tab
        if AO.db then AO.db.lastTab = idx end
    end

    if VUI.IS_FOREVER and VUI.CreateSideTabs then
        selectTab = VUI.CreateSideTabs(win, {
            { icon = "Interface/ICONS/INV_Misc_Book_09", tooltip = "Featured" },
            { icon = "Interface/ICONS/INV_Scroll_03",    tooltip = "All CVars" },
        }, function(i) ActivateTab(i == 2 and "browser" or "featured") end)
        selectTab(1)
    else
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
        selectTab = function(idx) PanelTemplates_SetTab(win, idx) end

        tabFeatured:SetScript("OnClick", function() ActivateTab("featured") end)
        tabBrowser:SetScript("OnClick",  function() ActivateTab("browser")  end)
    end

    function win:ShowTab(which)
        VUI.OpenManagedPanel(self)
        ActivateTab(which)
    end

    -- ── Build tab contents ────────────────────────────────────
    AO:BuildFeaturedContent(contFeatured, win)
    AO:BuildBrowserContent(contBrowser, win)

    win:SetScript("OnShow", function()
        ApplyPortrait(win)
    end)
    -- Blizzard's standard window sound, as the Character Info and class trainer windows (after SetScript).
    if VUI.AddWindowSounds and SOUNDKIT then
        VUI.AddWindowSounds(win, SOUNDKIT.IG_CHARACTER_INFO_OPEN, SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end

    AO.MainWindow = win
    VUI.AnnounceFrame("AdvancedOptions.Window", win)
end

----------------------------------------------------------------
--  Startup
----------------------------------------------------------------
local SETTINGS_LABEL = "Advanced Options"

local function BuildNativeSettingsPanel()
    local category, layout = VUI.RegisterSettingsCategory(SETTINGS_LABEL)
    local function Opener(tab)
        return {
            open = function()
                if not AO.MainWindow then return end
                if tab then AO.MainWindow:ShowTab(tab) elseif not AO.MainWindow:IsShown() then AO:ShowWindow() end
            end,
        }
    end
    if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
        local rows = {
            { "Featured Settings", "featured",
              "Useful hidden settings as checkboxes, sliders and dropdowns, each with a reset button." },
            { "All CVars", "browser", "Search and change every setting your game has, and star your favourites." },
        }
        for _, row in ipairs(rows) do
            local opener = Opener(row[2])
            layout:AddInitializer(CreateSettingsButtonInitializer(row[1], "Open",
                function() VUI._OpenFromSettings(opener) end, row[3], false))
        end
    end
    Settings.RegisterAddOnCategory(category)
    AO.settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL, Opener(nil))
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok1, err1 = pcall(BuildMainWindow)
    if not ok1 then
        VUI.Print("Advanced Options",
            VUI.COL.RED .. "Window error:|r " .. tostring(err1))
    end
    local ok2, err2 = pcall(BuildNativeSettingsPanel)
    if not ok2 then
        VUI.Print("Advanced Options", VUI.COL.RED .. "Settings page error:|r " .. tostring(err2))
    end

    initFrame:UnregisterAllEvents()
end)
