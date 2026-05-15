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

-- Register with the UIPanel manager at FILE LOAD time, BEFORE BuildMainWindow
-- runs at PLAYER_LOGIN. Blizzard's primary panels register at top-level file
-- scope; doing the same makes PR a first-class citizen of the manager.
--
-- pushable=0 mirrors CollectionsJournal/Journeys exactly — the highest-
-- priority value in the legacy UIPanelWindows system. Lower pushable wins
-- slot 1, and PR with pushable=0 will:
--   • Always hold slot 1 against CharacterFrame (pushable=3) and other
--     legacy panels with pushable >= 1, regardless of opening order
--   • Coexist visibly: Character slides to slot 2 if opened after PR, or
--     opens directly into slot 2 if opened after PR — end state identical
--   • Yield to modern primary panels (ProfessionsFrame, PlayerSpellsFrame)
--     that use the newer panel manager outside UIPanelWindows — same as
--     how Journeys yields to Professions in Blizzard's own UI
--
-- This is the authentic "Blizzard primary panel" registration. The
-- consistent leftmost slot regardless of opening order is the deterministic
-- layout that makes Blizzard's UI feel cohesive.
--
-- Width / height are intentionally NOT declared here. Blizzard's own
-- CharacterFrame registration omits them, letting the manager read
-- GetWidth() / GetHeight() from the live frame instead of using stale
-- declared values. Declaring width=PNL_W caused a 1-2px horizontal
-- drift vs Blizzard's own panels (instance bar not flush against our
-- left edge) because PortraitFrameTemplate's portrait overhang makes
-- the rendered geometry differ from the logical SetSize value the
-- manager would otherwise use for positioning math.
VUI.RegisterManagedPanel("PriorityRotMainWindow", {
    area     = "left",
    pushable = 0,
})

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
    -- Registered with Blizzard's UIPanel manager at file load time (see
    -- VUI.RegisterManagedPanel call near the top of this file). Because
    -- the manager owns positioning and strata, we must NOT call SetPoint,
    -- SetMovable, or SetFrameStrata here — any manual anchor fights the
    -- manager and produces drift / strata-flicker. SetToplevel IS safe
    -- (the manager doesn't touch it) and is required for PR to render
    -- above the instance-info side bar, matching CharacterFrame.
    local win = CreateFrame("Frame", "PriorityRotMainWindow", UIParent, "PortraitFrameTemplate")
    win:SetSize(PNL_W, PNL_H)
    win:EnableMouse(true)
    win:Hide()

    -- Match Blizzard's primary-panel declaration. CharacterFrame's XML
    -- sets `toplevel="true"`, which causes the frame to raise above other
    -- same-strata frames (like the instance-info side bar) whenever it's
    -- shown or clicked. Without this, PR renders *below* the instance bar,
    -- which visually breaks the "flush against the instance bar" alignment
    -- that Blizzard's panels have. The UIPanel manager does NOT manage
    -- toplevel state — only strata/position/level — so setting it here
    -- does not fight the manager.
    win:SetToplevel(true)

    -- Wire the PortraitFrameTemplate close button through the UIPanel
    -- manager so the slot is released; a bare :Hide() leaves the manager
    -- thinking the panel is still occupying the slot and corrupts stacking
    -- on the next open.
    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function(self)
            HideUIPanel(self:GetParent())
        end)
    end

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
        -- Keep the spec switcher dropdown's label in sync with the live
        -- spec. Set up by BuildInWindowSettingsTab (Tools section).
        if self.specDD and self.specDD.RefreshLabel then
            self.specDD:RefreshLabel()
        end
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
        VUI.OpenManagedPanel(self)
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
            if PR:UpdateMacroStub() then
                VUI.Print("Priority Rotation",
                    "Macro |cFFFFFF00" .. PR.MACRO_NAME
                    .. "|r is ready — drag it from /macro to an action bar.")
            end
            -- On failure, UpdateMacroStub already printed the specific reason.
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

        -- ── Tools ─────────────────────────────────────────────────
        -- Convenience shortcuts: spec switcher dropdown, plus quick-open
        -- buttons for the Spellbook and Macro UI (the two interfaces a
        -- user juggles most while authoring a rotation).
        --
        -- IMPORTANT anchor note: Section() chains the header from the
        -- given anchorFrame's relPoint at x=0. We anchor off resetBtn
        -- (the LEFT half of the previous row) so the header lands at the
        -- left edge of `cont`. Anchoring off clearBtn (the right half)
        -- would place the header in the middle of the panel, pushing
        -- every chained child off the right edge.
        local divTools = Section(resetBtn, "BOTTOMLEFT", -14, "Tools")

        -- Spec switcher — uses the modern WowStyle1DropdownTemplate
        -- (`DropdownButton` widget that replaced legacy UIDropDownMenu in
        -- Dragonflight). SetupMenu re-runs each time the dropdown opens so
        -- the radio state always reflects the live spec, even mid-cast.
        --
        -- Defensive: wrap creation in pcall — if the template isn't
        -- available on this client (e.g. some private-server build),
        -- fall back gracefully without breaking the rest of the panel.
        local specDD
        local okDD = pcall(function()
            specDD = CreateFrame("DropdownButton", nil, cont, "WowStyle1DropdownTemplate")
        end)
        if okDD and specDD then
            specDD:SetPoint("TOPLEFT", divTools, "BOTTOMLEFT", 0, -10)
            specDD:SetWidth(CW)

            local function CurrentSpecName()
                local idx = GetSpecialization and GetSpecialization()
                if idx then
                    local _, name = GetSpecializationInfo(idx)
                    if name and name ~= "" then return name end
                end
                return "Switch Specialization"
            end

            specDD:SetupMenu(function(_, root)
                -- ──────────────────────────────────────────────────────────
                -- TAINT WORKAROUND for WoWUIBugs #783
                -- ──────────────────────────────────────────────────────────
                -- Midnight 12.0 bug: if a tainted (addon) dropdown is the
                -- FIRST menu opened in a session, the menu compositor
                -- assigns a tainted `nil` to the shared menu frame's
                -- `minimumWidth` field. That tainted nil then propagates
                -- through secure menu operations opened later, producing
                -- Secret Value errors in Blizzard code (SpellBookItem
                -- UpdateCooldown, ActionButton ApplyCooldown, etc.) during
                -- combat in zones with Secret Values active.
                --
                -- Fix: assign a clean concrete integer at the top of EVERY
                -- menu generator so the compositor never sees the tainted
                -- nil landmine. One line, zero behavior cost.
                --
                -- Value is set to CW (the dropdown button's own width) so
                -- the menu popup matches the button width visually rather
                -- than auto-shrinking to the longest radio label. Any
                -- positive integer defuses the taint; CW just looks right.
                --
                -- Credit: Meorawr (Total-RP-3 PR #1242). Remove this call
                -- when WoWUIBugs #783 is resolved by Blizzard.
                -- ──────────────────────────────────────────────────────────
                root:SetMinimumWidth(CW)

                local n = (GetNumSpecializations and GetNumSpecializations()) or 0
                for i = 1, n do
                    local id, name = GetSpecializationInfo(i)
                    if id and name then
                        root:CreateRadio(
                            name,
                            function() return GetSpecialization() == i end,
                            function()
                                if InCombatLockdown() then
                                    VUI.Print("Priority Rotation",
                                        "|cFFFF4444Can't switch spec in combat.|r")
                                    return MenuResponse.Refresh
                                end
                                if i ~= GetSpecialization() then
                                    -- Midnight refactored the spec API into
                                    -- C_SpecializationInfo; the global
                                    -- SetSpecialization may be absent or shimmed.
                                    -- Try the modern namespace first, fall back
                                    -- to the global, surface the actual error
                                    -- if both fail so we can diagnose.
                                    local ok, err
                                    if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
                                        ok, err = pcall(C_SpecializationInfo.SetSpecialization, i)
                                    end
                                    if not ok and SetSpecialization then
                                        ok, err = pcall(SetSpecialization, i)
                                    end
                                    if not ok then
                                        VUI.Print("Priority Rotation",
                                            "|cFFFF4444Spec switch failed:|r " .. tostring(err))
                                    end
                                end
                                return MenuResponse.Close
                            end
                        )
                    end
                end
            end)

            -- Refresh helper — updates the dropdown's button label to
            -- show the live spec name. Called from win:RefreshBadge so
            -- the dropdown stays in sync with PLAYER_SPECIALIZATION_CHANGED.
            --
            -- OverrideText is the correct API here. SetDefaultText only
            -- controls the label when no radio has been clicked — once the
            -- user clicks a radio, the dropdown caches THAT radio's label
            -- and won't re-poll isSelectedFn until the menu reopens. A
            -- spec change fired by the game (not the dropdown) leaves the
            -- cached click-label stale. OverrideText bypasses the cache
            -- and force-sets the displayed text directly.
            function specDD:RefreshLabel()
                local name = CurrentSpecName()
                if self.OverrideText then
                    self:OverrideText(name)
                elseif self.SetDefaultText then
                    self:SetDefaultText(name)
                end
            end
            specDD:RefreshLabel()
            -- Expose to the outer window so RefreshBadge can find it.
            win.specDD = specDD
        end

        -- Spellbook toggle button. In Midnight, SpellBookFrame was retired
        -- and absorbed into PlayerSpellsFrame. We implement explicit
        -- toggle: if PlayerSpellsFrame is shown, hide via HideUIPanel
        -- (manager-aware); otherwise open via the modern PlayerSpellsUtil
        -- with a ToggleSpellBook fallback for earlier-build clients.
        local spellBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        spellBtn:SetSize(HALF, 24)
        spellBtn:SetPoint("TOPLEFT", (specDD or divTools), "BOTTOMLEFT", 0, -10)
        spellBtn:SetText("Spellbook")
        spellBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                VUI.Print("Priority Rotation", "|cFFFF4444Can't toggle Spellbook in combat.|r")
                return
            end
            if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
                pcall(HideUIPanel, PlayerSpellsFrame)
                return
            end
            local opened = false
            if PlayerSpellsUtil and PlayerSpellsUtil.OpenToSpellBookTab then
                opened = pcall(PlayerSpellsUtil.OpenToSpellBookTab)
            end
            if not opened and ToggleSpellBook then
                pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
            end
        end)

        -- Macros toggle. ShowMacroFrame opens (and load-on-demands the
        -- Blizzard_MacroUI addon). Once loaded, MacroFrame is the global
        -- handle we check IsShown() against to implement the close half
        -- of the toggle.
        local macroOpenBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        macroOpenBtn:SetSize(HALF, 24)
        macroOpenBtn:SetPoint("LEFT", spellBtn, "RIGHT", 8, 0)
        macroOpenBtn:SetText("Macros")
        macroOpenBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                VUI.Print("Priority Rotation", "|cFFFF4444Can't toggle Macros in combat.|r")
                return
            end
            if MacroFrame and MacroFrame:IsShown() then
                pcall(HideUIPanel, MacroFrame)
                return
            end
            if ShowMacroFrame then pcall(ShowMacroFrame) end
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
            PR:EnsureActionBarCVar(true)
            PR:CompileSequence()
            PR:ScheduleScan(0.5)
            VUI.Print("Priority Rotation", "|cFF00FF00Enabled.|r")
        else
            PR:ClearOverride()
            PR:EnsureActionBarCVar(false)
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