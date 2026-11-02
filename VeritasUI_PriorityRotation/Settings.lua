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

-- Apply the current spec's icon to the frame's portrait slot through Blizzard's
-- own PortraitFrameMixin:SetPortraitToSpecIcon (PortraitFrame.lua:73), the call
-- the Character Info pane uses (CharacterFrame.lua:110): full-texture texcoords,
-- class-circle fallback when no spec is chosen. Called on every RefreshBadge so
-- it tracks spec changes automatically.
local function ApplySpecPortrait(frame)
    if frame.SetPortraitToSpecIcon then
        frame:SetPortraitToSpecIcon()
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
    -- ButtonFrameTemplate (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:660-693): the
    -- portrait frame plus its recessed Inset and the 26 px button bar along the bottom -- the same
    -- frame as Advanced Options (owner's request, v1.35.11). Both tabs sit in win.Inset; the bar
    -- holds the Settings tab's Scan & Bind.
    local win = CreateFrame("Frame", "PriorityRotMainWindow", UIParent, "ButtonFrameTemplate")
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
    -- manager so the slot is released. VUI.CloseManagedPanel uses HideUIPanel
    -- out of combat and a plain Hide in combat, where Blizzard refuses
    -- HideUIPanel from addon code (see the note on CloseManagedPanel in Lib.lua).
    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function(self)
            VUI.CloseManagedPanel(self:GetParent())
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

    -- Flat Auction House background in the Inset instead of the old marble (Lib).
    VUI.UseFlatInsetBackground(win)

    -- The tabs' content, inside Blizzard's recessed Inset. The fallback anchors match
    -- ButtonFrameTemplate's own Inset (TOPLEFT 4,-60 / BOTTOMRIGHT -6,26).
    local CONTENT = CreateFrame("Frame", nil, win)
    if win.Inset then
        CONTENT:SetPoint("TOPLEFT",     win.Inset, "TOPLEFT",      4, -4)
        CONTENT:SetPoint("BOTTOMRIGHT", win.Inset, "BOTTOMRIGHT", -4,  4)
    else
        CONTENT:SetPoint("TOPLEFT",     win, "TOPLEFT",      8, -64)
        CONTENT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 30)
    end

    -- Spec / profile badge — "Havoc Demon Hunter" in heroic 20pt Friz Quadrata
    -- (GameFontNormalHuge is Blizzard's standard section-title font), centred in the band
    -- between the title bar and the Inset.
    local specBadge = win:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    specBadge:SetPoint("TOP", win, "TOP", 0, -30)
    specBadge:SetJustifyH("CENTER")
    specBadge:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())

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
        -- Re-sync the reacquire checkbox to the now-current spec's profile
        -- (reacquire is per-spec, so a spec change flips which value shows).
        if self.reacqCheck then
            self.reacqCheck:SetChecked(PR:CurrentProfile().reacquire and true or false)
        end
    end

    -- Content panels fill CONTENT (the Inset); the spec badge sits above it.
    local contRotation = CreateFrame("Frame", nil, CONTENT)
    contRotation:SetAllPoints(CONTENT)

    local contSettings = CreateFrame("Frame", nil, CONTENT)
    contSettings:SetAllPoints(CONTENT)
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
        -- Equal margins left and right (owner, 2026-10-30: everything sat on the left border with
        -- 8 px spare on the right). The column is CW wide inside a CONTENT_W-wide tab, so it starts
        -- MARGIN in; every later row hangs off the first section, so this one offset moves them all.
        local MARGIN = (CONTENT_W - CW) / 2

        -- Section helper: gold header + 1px divider, returns divider frame.
        -- relPoint controls which edge of anchorFrame to hang from:
        --   "TOPLEFT"    — first section, hangs from the top of the container
        --   "BOTTOMLEFT" — subsequent sections, chains below previous body text
        local function Section(anchorFrame, relPoint, yOff, title, xOff)
            local hdr = cont:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            hdr:SetPoint("TOPLEFT", anchorFrame, relPoint, xOff or 0, yOff)
            hdr:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
            hdr:SetText(title)
            local div = cont:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetPoint("TOPLEFT",  hdr,  "BOTTOMLEFT",  0, -3)
            div:SetPoint("TOPRIGHT", cont, "TOPRIGHT", -MARGIN, 0)
            div:SetColorTexture(0.35, 0.35, 0.35, 0.8)
            return div
        end

        local function Body(anchorFrame, yOff, text)
            local fs = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, yOff)
            fs:SetWidth(CW)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())   -- panel body: white (owner, 2026-11-01)
            fs:SetText(text)
            return fs
        end

        -- ── How It Works ──────────────────────────────────────────
        local divHow = Section(cont, "TOPLEFT", -4, "How It Works", MARGIN)
        local txtHow = Body(divHow, -6,
            "Spam the bound key to cycle through your rotation. "
            .."WoW's built-in cooldown and resource checks handle the rest.")

        -- ── Targeting ─────────────────────────────────────────────
        -- Per-spec toggle. Writes CurrentProfile().reacquire and forces a
        -- recompile so the reacquire prefix is (un)baked into the spell
        -- steps immediately. The checkbox state is re-synced to the live
        -- profile in win:RefreshBadge (fires on spec change and on show),
        -- so switching spec always shows THAT spec's setting.
        local divTarget = Section(txtHow, "BOTTOMLEFT", -10, "Targeting")

        -- Own label fontstring rather than the template's built-in text
        -- region — avoids the .Text/.text naming drift across CheckButton
        -- template revisions.
        local reacqCheck = CreateFrame("CheckButton", nil, cont, "UICheckButtonTemplate")
        reacqCheck:SetPoint("TOPLEFT", divTarget, "BOTTOMLEFT", 0, -6)
        reacqCheck:SetSize(24, 24)
        local reacqLbl = cont:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        reacqLbl:SetPoint("LEFT", reacqCheck, "RIGHT", 2, 0)
        reacqLbl:SetText("Auto-target next enemy on death")
        reacqLbl:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
        reacqCheck:SetChecked(PR:CurrentProfile().reacquire and true or false)
        reacqCheck:SetScript("OnClick", function(self)
            local checked = self:GetChecked() and true or false
            PR:CurrentProfile().reacquire = checked
            PR:CompileSequence()
            VUI.Print("Priority Rotation", checked
                and "Auto-target on death " .. VUI.COL.GREEN .. "enabled|r for this spec."
                or  "Auto-target on death " .. VUI.COL.RED .. "disabled|r for this spec.")
        end)
        -- Clicking the label toggles the box too — larger hit target.
        local reacqLabelBtn = CreateFrame("Button", nil, cont)
        reacqLabelBtn:SetPoint("TOPLEFT",     reacqLbl, "TOPLEFT",     0, 0)
        reacqLabelBtn:SetPoint("BOTTOMRIGHT", reacqLbl, "BOTTOMRIGHT", 0, 0)
        reacqLabelBtn:SetScript("OnClick", function()
            reacqCheck:Click()
        end)
        win.reacqCheck = reacqCheck

        local txtTarget = Body(reacqCheck, -4,
            "When your target dies, holding the rotation key switches to "
            .."the nearest enemy. Only a target's death or your own "
            .."tab/click ever changes targets — a live target you picked is "
            .."never overridden. " .. VUI.COL.YELLOW .. "Set per spec.|r")

        -- (A "Rotation Columns" section here repeated the Rotation tab's explanation of Frequency /
        -- After / Combat; removed v1.35.11 at the owner's request. Those columns explain themselves
        -- in their header tooltips, Editor.lua.)

        -- ── Setup ─────────────────────────────────────────────────
        local divSetup = Section(txtTarget, "BOTTOMLEFT", -10, "Setup")
        local txtSetup = Body(divSetup, -6,
            "1.  Click " .. VUI.COL.YELLOW .. "Create / Update Macro|r below\n"
            .."2.  Drag " .. VUI.COL.YELLOW .. "Attack|r from /macro onto any action bar\n"
            .."3.  Bind a key to that bar slot\n"
            .."4.  Click " .. VUI.COL.YELLOW .. "Scan & Bind|r to activate")

        -- ── Action Buttons ────────────────────────────────────────
        -- Every button on this tab uses MagicButtonTemplate for the gold-bordered
        -- premium look that matches Blizzard's modern frame chrome (e.g. the
        -- Specialization "Activate" button, Talent "Reset" button). The
        -- template's default text height is ~22px; we keep slightly taller
        -- sizes (28 primary / 24 secondary) so the button row reads as a
        -- distinct call-to-action band beneath the Setup body text.
        local macroBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        macroBtn:SetSize(CW, 28)
        macroBtn:SetPoint("TOPLEFT", txtSetup, "BOTTOMLEFT", 0, -14)
        macroBtn:SetText("Create / Update Macro")
        -- Delegate like scanBtn below: the combat guard, the success wording and
        -- UpdateMacroStub's failure messages all live in one place, /pr macro.
        macroBtn:SetScript("OnClick", function()
            SlashCmdList["VERITASUI_PR"]("macro")
        end)

        -- Scan & Bind sits in the window's bottom bar, bottom right, at ButtonFrameTemplate's own
        -- corner offset (MagicButton_OnLoad, SharedUIPanelTemplates.lua:36-39) -- the same spot as
        -- Advanced Options' buttons (owner's request, v1.35.11). Parented to this tab, so it shows
        -- with it only.
        local scanBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        scanBtn:SetSize(150, 22)
        scanBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 4)
        scanBtn:SetText("Scan & Bind")
        scanBtn:SetScript("OnClick", function()
            SlashCmdList["VERITASUI_PR"]("scan")
        end)

        local resetBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        resetBtn:SetSize(HALF, 24)
        resetBtn:SetPoint("TOPLEFT", macroBtn, "BOTTOMLEFT", 0, -14)
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
                local idx = C_SpecializationInfo.GetSpecialization()
                if idx then
                    local _, name = C_SpecializationInfo.GetSpecializationInfo(idx)
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

                local n = GetNumSpecializations() or 0
                for i = 1, n do
                    local id, name = C_SpecializationInfo.GetSpecializationInfo(i)
                    if id and name then
                        root:CreateRadio(
                            name,
                            function() return C_SpecializationInfo.GetSpecialization() == i end,
                            function()
                                -- Shared with the AddOns-menu flyout (Core.lua PR.SwitchSpec):
                                -- combat refusal keeps the menu open, anything else closes it.
                                if PR.SwitchSpec(i) == "combat" then
                                    return MenuResponse.Refresh
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

        -- Spellbook button. ⛔ Priority Rotation does NOT open the spellbook itself: doing so from
        -- this code tainted it, and a spell clicked in it was refused (CastSpellBookItem,
        -- ADDON_ACTION_FORBIDDEN, fixed v1.22.1). The click is taken by SpellbookOpener.lua's
        -- secure overlay (AddTarget below) and forwarded to Blizzard's PlayerSpellsMicroButton,
        -- which opens or closes it like the menu bar. PR.ToggleSpellBookPanel only explains, for
        -- when the overlay is absent (in combat, or no micro button). Never call PlayerSpellsUtil here.
        local spellBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        spellBtn:SetSize(HALF, 24)
        spellBtn:SetPoint("TOPLEFT", (specDD or divTools), "BOTTOMLEFT", 0, -10)
        spellBtn:SetText("Spellbook")
        spellBtn:SetScript("OnClick", function()
            PR.ToggleSpellBookPanel()
        end)
        if PR.SpellbookOpener then PR.SpellbookOpener.AddTarget(spellBtn) end

        -- Macros toggle. ShowMacroFrame opens (and load-on-demands the
        -- Blizzard_MacroUI addon). Once loaded, MacroFrame is the global
        -- handle we check IsShown() against to implement the close half
        -- of the toggle.
        local macroOpenBtn = CreateFrame("Button", nil, cont, "MagicButtonTemplate")
        macroOpenBtn:SetSize(HALF, 24)
        macroOpenBtn:SetPoint("LEFT", spellBtn, "RIGHT", 8, 0)
        macroOpenBtn:SetText("Macros")
        macroOpenBtn:SetScript("OnClick", function()
            PR.ToggleMacroPanel()
        end)
    end

    BuildInWindowSettingsTab(contSettings)

    win:SetScript("OnShow", function()
        win:RefreshBadge()
        if PR.Editor then PR.Editor:Refresh() end
    end)

    PR.MainWindow = win
    VUI.AnnounceFrame("PriorityRotation.Window", win)
end

-- ── Native Settings Panel ────────────────────────────────────────

local function BuildNativeSettingsPanel()
    local category = VUI.RegisterSettingsCategory(SETTINGS_LABEL)

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
            PR:ScheduleScan(0.5)
            VUI.Print("Priority Rotation", VUI.COL.GREEN .. "Enabled.|r")
        else
            PR:ClearOverride()
            VUI.Print("Priority Rotation", VUI.COL.RED .. "Disabled.|r")
        end
    end)
    Settings.CreateCheckbox(category, enableSetting,
        "Cycles through your configured spell list on each key press. "
        .."Use " .. VUI.COL.YELLOW .. "/pr|r to open the rotation editor.")

    Settings.RegisterAddOnCategory(category)
    PR.settingsCategoryID = category:GetID()
    -- An Open button in the page header instead of Reload UI / Copy From... (owner, v1.58.0).
    VUI.RegisterSettingsLabel(SETTINGS_LABEL, {
        open = function()
            if PR.MainWindow and not PR.MainWindow:IsShown() then PR.MainWindow:ShowTab("editor") end
        end,
        window = function() return PR.MainWindow end,
    })
end

-- ── Startup ───────────────────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local ok1, err1 = pcall(BuildMainWindow)
    if not ok1 then
        VUI.Print("Priority Rotation", VUI.COL.RED .. "Editor error:|r " .. tostring(err1))
    end

    local ok2, err2 = pcall(BuildNativeSettingsPanel)
    if not ok2 then
        VUI.Print("Priority Rotation", VUI.COL.RED .. "Settings error:|r " .. tostring(err2))
    end

    initFrame:UnregisterAllEvents()
end)