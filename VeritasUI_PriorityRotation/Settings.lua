-- VeritasUI_PriorityRotation / Settings.lua
-- Main editor window (custom tool UI) + native Blizzard Settings panel entry.
--
-- Uses PR:RefreshUI() pattern instead of monkey-patching PR methods.

local ADDON_NAME, PR = ...
local VUI = _G.VeritasUI
if not VUI then return end   -- Core.lua already printed the error

local SETTINGS_LABEL = "Priority Rotation"

local PNL_W     = 420
local PNL_H     = 660
local CONTENT_W = PNL_W - 18

-- Apply the current spec's icon to the frame's portrait slot, with the class
-- atlas as a fallback (e.g. pre-spec-selection or low-level characters).
-- Called on every RefreshBadge so it tracks spec changes automatically.
local function ApplySpecPortrait(frame)
    local portrait = (frame.PortraitContainer and frame.PortraitContainer.portrait)
                  or frame.portrait
    if not portrait then return end

    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local _, _, _, specIcon = GetSpecializationInfo(specIndex)
        if specIcon then
            portrait:SetTexture(specIcon)
            -- Trim the ~8% Blizzard icon border so the spec art fills the
            -- circular portrait mask cleanly.
            portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            return
        end
    end

    -- Fallback: circular class atlas (used only when no spec is selected)
    local _, class = UnitClass("player")
    if class then
        portrait:SetTexCoord(0, 1, 0, 1)
        portrait:SetAtlas("classicon-" .. class:lower())
    end
end

-- ── Main Editor Window ────────────────────────────────────────────

local function BuildMainWindow()
    local win = CreateFrame("Frame", "PriorityRotMainWindow", UIParent, "PortraitFrameTemplate")
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

    -- Title — PortraitFrameTemplate (via ButtonFrameTemplate) exposes SetTitle
    -- in modern clients; fall back to legacy fontstring paths defensively.
    if win.SetTitle then
        win:SetTitle("Priority Rotation")
    elseif win.TitleContainer and win.TitleContainer.TitleText then
        win.TitleContainer.TitleText:SetText("Priority Rotation")
    elseif win.TitleText then
        win.TitleText:SetText("Priority Rotation")
    end

    -- Force the title to center on the full frame width. By default the
    -- TitleContainer anchors between the portrait and close button, which
    -- visually drifts the title right-of-center. Re-anchoring to TOP overrides
    -- that layout.
    local titleText = (win.TitleContainer and win.TitleContainer.TitleText)
                   or win.TitleText
    if titleText then
        titleText:ClearAllPoints()
        titleText:SetPoint("TOP", win, "TOP", 0, -5)
    end

    ApplySpecPortrait(win)

    local CONTENT = CreateFrame("Frame", nil, win)
    CONTENT:SetPoint("TOPLEFT",     win, "TOPLEFT",     8,  -28)
    CONTENT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8,   6)

    -- Spec / profile badge — "Havoc Demon Hunter" in heroic 20pt Friz Quadrata
    -- (GameFontNormalHuge is Blizzard's standard section-title font).
    -- Anchored to CONTENT's TOP (horizontally centered) at y=-16 to visually
    -- balance against the portrait circle.
    local specBadge = CONTENT:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    specBadge:SetPoint("TOP", CONTENT, "TOP", 0, -16)
    specBadge:SetJustifyH("CENTER")
    specBadge:SetTextColor(1, 1, 1)

    -- Exposed on win so PR:RefreshUI() can call it without monkey-patching.
    -- Refreshes both the spec name and the portrait icon (spec changes trigger
    -- this via Core.lua's PLAYER_SPECIALIZATION_CHANGED handler).
    function win:RefreshBadge()
        specBadge:SetText(PR:GetCurrentSpecLabel())
        ApplySpecPortrait(self)
    end

    -- Content panels — anchored to CONTENT directly (not to specBadge) so
    -- horizontal position is independent of the badge's x offset. The -50 y
    -- offset reserves the top band for the heroic spec-name header and leaves
    -- room at the bottom for the Compiled Sequence preview to grow as users
    -- add more spells / higher freq values.
    local contRotation = CreateFrame("Frame", nil, CONTENT)
    contRotation:SetPoint("TOPLEFT",     CONTENT, "TOPLEFT",      4, -50)
    contRotation:SetPoint("BOTTOMRIGHT", CONTENT, "BOTTOMRIGHT", -4,   4)

    local contSettings = CreateFrame("Frame", nil, CONTENT)
    contSettings:SetPoint("TOPLEFT",     CONTENT, "TOPLEFT",      4, -50)
    contSettings:SetPoint("BOTTOMRIGHT", CONTENT, "BOTTOMRIGHT", -4,   4)
    contSettings:Hide()

    -- Bottom tabs — PanelTabButtonTemplate hangs below the frame edge in the
    -- modern Journeys / Collections style. Tabs overlap by -16 by design.
    local tabRotation = CreateFrame("Button", "$parentTab1", win, "PanelTabButtonTemplate")
    tabRotation:SetID(1)
    tabRotation:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 11, -30)
    tabRotation:SetText("Rotation")
    PanelTemplates_TabResize(tabRotation, 0)

    local tabSettings = CreateFrame("Button", "$parentTab2", win, "PanelTabButtonTemplate")
    tabSettings:SetID(2)
    tabSettings:SetPoint("LEFT", tabRotation, "RIGHT", -16, 0)
    tabSettings:SetText("Settings")
    PanelTemplates_TabResize(tabSettings, 0)

    PanelTemplates_SetNumTabs(win, 2)
    PanelTemplates_SetTab(win, 1)

    local function ActivateTab(which)
        local idx = (which == "editor") and 1 or 2
        PanelTemplates_SetTab(win, idx)
        contRotation:SetShown(idx == 1)
        contSettings:SetShown(idx == 2)
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
        local CW   = CONTENT_W - 8
        local HALF = math.floor((CW - 8) / 2)

        -- Section helper: gold header + 1px divider, returns divider frame.
        -- relPoint controls which edge of anchorFrame to hang from:
        --   "TOPLEFT"    — first section, hangs from the top of the container
        --   "BOTTOMLEFT" — subsequent sections, chains below previous body text
        local function Section(anchorFrame, relPoint, yOff, title)
            local hdr = cont:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            hdr:SetPoint("TOPLEFT", anchorFrame, relPoint, 0, yOff)
            hdr:SetTextColor(1, 0.82, 0)
            hdr:SetText(title)
            local div = cont:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetPoint("TOPLEFT",  hdr,  "BOTTOMLEFT",  0, -3)
            div:SetPoint("TOPRIGHT", cont, "TOPRIGHT",   -6,  0)
            div:SetColorTexture(0.35, 0.35, 0.35, 0.8)
            return div
        end

        local function Body(anchorFrame, yOff, text)
            local fs = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, yOff)
            fs:SetWidth(CW)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(0.75, 0.75, 0.75)
            fs:SetText(text)
            return fs
        end

        -- ── How It Works ──────────────────────────────────────────
        local divHow = Section(cont, "TOPLEFT", -4, "How It Works")
        local txtHow = Body(divHow, -6,
            "Spam the bound key to cycle through your rotation. "
            .."WoW's built-in cooldown and resource checks handle the rest.")

        -- ── Freq ──────────────────────────────────────────────────
        local divFreq = Section(txtHow, "BOTTOMLEFT", -10, "Freq")
        local txtFreq = Body(divFreq, -6,
            "Controls how often a spell appears in the cycle.\n"
            .."|cFFFFFF00Freq 3+|r  —  priority spells and cooldowns. "
            .."They fire as often as possible.\n"
            .."|cFFFFFF00Freq 1|r   —  filler spells. "
            .."They activate only when your higher-priority spells are on cooldown.")

        -- ── Setup ─────────────────────────────────────────────────
        local divSetup = Section(txtFreq, "BOTTOMLEFT", -10, "Setup")
        local txtSetup = Body(divSetup, -6,
            "1.  Click |cFFFFFF00Create / Update Macro|r below\n"
            .."2.  Drag |cFFFFFF00Attack|r from /macro onto any action bar\n"
            .."3.  Bind a key to that bar slot\n"
            .."4.  Click |cFFFFFF00Scan & Bind|r to activate")

        -- ── Action Buttons ────────────────────────────────────────
        -- All four buttons use MagicButtonTemplate for the gold-bordered
        -- premium look that matches Blizzard's modern frame chrome (e.g. the
        -- Specialization "Activate" button, Talent "Reset" button). The
        -- template's default text height is ~22px; we keep slightly taller
        -- sizes (28 primary / 24 secondary) so the button row reads as a
        -- distinct call-to-action band beneath the Setup body text.
        local macroBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        macroBtn:SetSize(CW, 28)
        macroBtn:SetPoint("TOPLEFT", txtSetup, "BOTTOMLEFT", 0, -14)
        macroBtn:SetText("Create / Update Macro")
        macroBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                VUI.Print("Priority Rotation", "|cFFFF4444Can't create macro in combat.|r")
                return
            end
            PR:UpdateMacroStub()
            VUI.Print("Priority Rotation",
                "Macro |cFFFFFF00" .. PR.MACRO_NAME
                .. "|r is ready — drag it from /macro to an action bar.")
        end)

        local scanBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        scanBtn:SetSize(CW, 28)
        scanBtn:SetPoint("TOPLEFT", macroBtn, "BOTTOMLEFT", 0, -6)
        scanBtn:SetText("Scan & Bind  (/pr scan)")
        scanBtn:SetScript("OnClick", function()
            SlashCmdList["VERITASUI_PR"]("scan")
        end)

        local resetBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        resetBtn:SetSize(HALF, 24)
        resetBtn:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 0, -14)
        resetBtn:SetText("Reset to Spec Defaults")
        resetBtn:SetScript("OnClick", function()
            PR:ResetCurrentProfileToDefault()
            PR:CompileSequence()
            PR:RefreshUI()
        end)

        local clearBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        clearBtn:SetSize(HALF, 24)
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
            C_CVar.SetCVar("ActionButtonUseKeyDown", "0")
            PR:CompileSequence()
            C_Timer.After(0.5, function()
                if not InCombatLockdown() then PR:ScanAndOverrideBarButton() end
            end)
            VUI.Print("Priority Rotation", "|cFF00FF00Enabled.|r")
        else
            if not InCombatLockdown() then
                PR:ClearOverride()
            else
                -- Defer override cleanup until combat ends.
                PR.needsClearOverride = true
            end
            PR:StopIconTicker()
            C_CVar.SetCVar("ActionButtonUseKeyDown", "1")
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