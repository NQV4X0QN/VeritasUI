-- VeritasUI_PriorityRotation / Settings.lua
-- Main editor window (custom tool UI) + native Blizzard Settings panel entry.
--
-- Uses PR:RefreshUI() pattern instead of monkey-patching PR methods.

local ADDON_NAME, PR = ...
local VUI = _G.VeritasUI
if not VUI then return end   -- Core.lua already printed the error

local SETTINGS_LABEL = "Priority Rotation"

local PNL_W     = 380
local PNL_H     = 620
local TAB_H     = 24
local CONTENT_W = PNL_W - 18

-- ── Main Editor Window ────────────────────────────────────────────

local function BuildMainWindow()
    local win = CreateFrame("Frame", "PriorityRotMainWindow", UIParent, "BasicFrameTemplate")
    win:SetSize(PNL_W, PNL_H)
    win:SetPoint("CENTER")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop",  win.StopMovingOrSizing)
    win:Hide()
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)

    if win.TitleText then
        win.TitleText:SetText("Priority Rotation")
    elseif win.TitleBar and win.TitleBar.TitleText then
        win.TitleBar.TitleText:SetText("Priority Rotation")
    end

    local CONTENT = CreateFrame("Frame", nil, win)
    CONTENT:SetPoint("TOPLEFT",     win, "TOPLEFT",     8,  -26)
    CONTENT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6,   6)

    -- Spec / profile badge
    local specBadge = CONTENT:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specBadge:SetPoint("TOPLEFT", CONTENT, "TOPLEFT", 8, -4)
    specBadge:SetJustifyH("LEFT")

    -- Exposed on win so PR:RefreshUI() can call it without monkey-patching.
    function win:RefreshBadge()
        specBadge:SetText(PR:GetCurrentSpecLabel())
    end

    -- Tabs
    local tabBar = CreateFrame("Frame", nil, CONTENT)
    tabBar:SetSize(CONTENT_W, TAB_H + 2)
    tabBar:SetPoint("TOPLEFT", specBadge, "BOTTOMLEFT", -4, -4)

    local function MakeTab(label, xOff)
        local btn = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
        btn:SetSize(110, TAB_H)
        btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", xOff, 0)
        btn:SetText(label)
        return btn
    end

    local tabRotation = MakeTab("Rotation", 0)
    local tabSettings = MakeTab("Settings", 116)

    local divider = CONTENT:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  tabBar,   "BOTTOMLEFT",  0, -1)
    divider:SetPoint("TOPRIGHT", CONTENT,  "TOPRIGHT",   -6,  0)
    divider:SetColorTexture(0.35, 0.35, 0.35, 1)

    local contRotation = CreateFrame("Frame", nil, CONTENT)
    contRotation:SetPoint("TOPLEFT",     divider, "BOTTOMLEFT",  4, -4)
    contRotation:SetPoint("BOTTOMRIGHT", CONTENT, "BOTTOMRIGHT", -4,  6)

    local contSettings = CreateFrame("Frame", nil, CONTENT)
    contSettings:SetPoint("TOPLEFT",     divider, "BOTTOMLEFT",  4, -4)
    contSettings:SetPoint("BOTTOMRIGHT", CONTENT, "BOTTOMRIGHT", -4,  6)
    contSettings:Hide()

    local function ActivateTab(which)
        contRotation:SetShown(which == "editor")
        contSettings:SetShown(which ~= "editor")
        tabRotation:SetText(which == "editor"  and "|cFF00CCFFRotation|r" or "Rotation")
        tabSettings:SetText(which ~= "editor"  and "|cFF00CCFFSettings|r" or "Settings")
    end

    tabRotation:SetScript("OnClick", function() ActivateTab("editor") end)
    tabSettings:SetScript("OnClick", function() ActivateTab("settings") end)

    function win:ShowTab(which)
        self:Show()
        ActivateTab(which)
        self:RefreshBadge()
        if PR.Editor then PR.Editor:Refresh() end
    end

    PR:BuildEditor(contRotation, CONTENT_W)

    -- ── In-window Settings Tab ────────────────────────────────────
    local function BuildInWindowSettingsTab(cont)
        local CW = CONTENT_W - 8

        local howLbl = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        howLbl:SetPoint("TOPLEFT", cont, "TOPLEFT", 0, -4)
        howLbl:SetWidth(CW)
        howLbl:SetJustifyH("LEFT")
        howLbl:SetText(
            "|cFFAAAAAAThis addon cycles through your spell list on each "
            .."key press. WoW handles cooldown/resource checks naturally.\n\n"
            .."|cFFFFFF00Freq|cFFAAAAAA controls how often a spell appears per cycle. "
            .."Use Freq 1 for cooldowns, Freq 3+ for filler spells.\n\n"
            .."|cFFFFFF00Setup:|cFFAAAAAA\n"
            .."  1) Click 'Create / Update Macro' below\n"
            .."  2) Drag Attack from /macro to any action bar\n"
            .."     (hidden bars like Bar 5 work too)\n"
            .."  3) Bind a key to that bar slot\n"
            .."  4) Click 'Scan & Bind' to activate\n"
            .."  5) Spam the key (or use G-Hub repeat)|r")

        local macroBtn = CreateFrame("Button", nil, cont, "UIPanelButtonTemplate")
        macroBtn:SetSize(200, 24)
        macroBtn:SetPoint("TOPLEFT", howLbl, "BOTTOMLEFT", 0, -10)
        macroBtn:SetText("Create / Update Macro")
        macroBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                VUI.Print("Priority Rotation", "|cFFFF4444Can't create macro in combat.|r")
                return
            end
            PR:UpdateMacroStub()
            VUI.Print("Priority Rotation",
                "Macro |cFFFFFF00" .. PR.MACRO_NAME
                .. "|r is ready — open /macro to drag it to a bar.")
        end)

        local scanBtn = CreateFrame("Button", nil, cont, "UIPanelButtonTemplate")
        scanBtn:SetSize(200, 24)
        scanBtn:SetPoint("TOPLEFT", macroBtn, "BOTTOMLEFT", 0, -6)
        scanBtn:SetText("Scan & Bind (/pr scan)")
        scanBtn:SetScript("OnClick", function()
            SlashCmdList["VERITASUI_PR"]("scan")
        end)

        local resetBtn = CreateFrame("Button", nil, cont, "UIPanelButtonTemplate")
        resetBtn:SetSize(170, 24)
        resetBtn:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 0, -10)
        resetBtn:SetText("Reset to Spec Defaults")
        resetBtn:SetScript("OnClick", function()
            PR:ResetCurrentProfileToDefault()
            PR:CompileSequence()
            PR:RefreshUI()
        end)

        local clearBtn = CreateFrame("Button", nil, cont, "UIPanelButtonTemplate")
        clearBtn:SetSize(120, 24)
        clearBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
        clearBtn:SetText("Clear All Spells")
        clearBtn:SetScript("OnClick", function()
            PR:CurrentProfile().spells = {}
            PR:CompileSequence()
            PR:RefreshUI()
        end)

    end

    BuildInWindowSettingsTab(contSettings)

    win:SetScript("OnShow", function()
        win:RefreshBadge()
        if PR.Editor then PR.Editor:Refresh() end
    end)

    PR.MainWindow = win
end

-- ── Native Settings Panel ────────────────────────────────────────

local function BuildNativeSettingsPanel()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local enableSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_enabled",
        "enabled",
        PR.db,
        "boolean",
        "Enable Priority Rotation",
        true
    )
    enableSetting:SetValueChangedCallback(function(_, value)
        if value then
            PR:CompileSequence()
            C_Timer.After(0.5, function()
                if not InCombatLockdown() then PR:ScanAndOverrideBarButton() end
            end)
            VUI.Print("Priority Rotation", "|cFF00FF00Enabled.|r")
        else
            if not InCombatLockdown() then
                PR:ClearOverride()
            end
            PR:StopIconTicker()
            VUI.Print("Priority Rotation", "|cFFFF4444Disabled.|r")
        end
    end)
    Settings.CreateCheckbox(category, enableSetting,
        "Cycles through your configured spell list on each key press. "
        .."Use |cFFFFFF00/pr|r to open the rotation editor.")

    Settings.RegisterAddOnCategory(category)
    PR.settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

-- ── Startup ───────────────────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok1, err1 = pcall(BuildMainWindow)
    if not ok1 then
        VUI.Print("Priority Rotation", "|cFFFF4444Editor error:|r " .. tostring(err1))
    end

    local ok2, err2 = pcall(BuildNativeSettingsPanel)
    if not ok2 then
        VUI.Print("Priority Rotation", "|cFFFF4444Settings error:|r " .. tostring(err2))
    end

    initFrame:UnregisterAllEvents()
end)