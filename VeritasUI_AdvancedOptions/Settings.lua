-- VeritasUI_AdvancedOptions / Settings.lua
-- Main window (ButtonFrameTemplate + tabs).
--
-- This module deliberately has NO entry in Options -> AddOns. It used to register
-- an empty category purely so the module could be "discovered" there, but a blank
-- panel reads as broken rather than as discovery, which is worse than no panel at
-- all (owner-reported 2026-07-28). Every setting this module has lives in its own
-- window; there is nothing a Settings category could usefully show.
--
-- If an entry is ever wanted again, give it real content -- at minimum a button
-- that opens the window -- rather than reinstating an empty category.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

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
    subtitle:SetTextColor(1, 1, 1)
    subtitle:SetText("Advanced Options")

    -- Featured tab content container
    local contFeatured = CreateFrame("Frame", nil, CONTENT)
    contFeatured:SetAllPoints(CONTENT)

    -- Browser tab content container
    local contBrowser = CreateFrame("Frame", nil, CONTENT)
    contBrowser:SetAllPoints(CONTENT)
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
    AO:BuildFeaturedContent(contFeatured, win)
    AO:BuildBrowserContent(contBrowser)

    win:SetScript("OnShow", function()
        ApplyPortrait(win)
    end)

    AO.MainWindow = win
    VUI.AnnounceFrame("AdvancedOptions.Window", win)
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

    initFrame:UnregisterAllEvents()
end)
