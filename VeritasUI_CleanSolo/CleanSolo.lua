-- VeritasUI_CleanSolo / CleanSolo.lua
-- Fades or hides noisy default UI elements for solo play.
-- Settings: Options → AddOns → Clean Solo  |  /cleansolo  |  /cs

local ADDON_NAME     = "VeritasUI_CleanSolo"
local SETTINGS_LABEL = "Clean Solo"

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G               = _G
local ipairs, pairs    = ipairs, pairs
local pcall            = pcall
local format           = string.format
local CreateFrame      = CreateFrame
local C_Timer          = C_Timer
local MouseIsOver      = MouseIsOver

local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Defaults & state
----------------------------------------------------------------
local defaults = {
    fadeChatTabs        = true,
    hideSocialButton    = true,
    hideChatButtons     = true,
    hideVoiceChatButton = true,
    fadeMicroMenu       = true,
    fadePlayerFrame     = true,
    hideBagButtons      = true,
    hideMacroNames      = true,
    hideErrorText       = true,
    hideNeutralPlates   = true,
}

local db
local inCombat = false
local settingsCategoryID
local frame = CreateFrame("Frame")

-- ── Feature: Hide Social Button ─────────────────────────────
local function HideSocialButton()
    VUI.SuppressFrame(QuickJoinToastButton)
end

-- ── Feature: Chat Tab Fading ────────────────────────────────
-- Hides ALL chat tabs by default.  Tabs fade in when Blizzard
-- fades in the chat frame (synchronized) and fade back out as
-- a group when the mouse leaves.
--
-- Each tab has a three-state guard driven by hooksecurefunc on
-- SetAlpha (fires synchronously after every call, so Blizzard
-- can never "win" a frame):
--   VISIBLE    — no guard, alpha flows freely
--   FADING_OUT — monotonic: alpha may only decrease (our fade),
--                any increase (Blizzard) is slammed back down
--   HIDDEN     — hard clamp: any alpha > 0 is forced to 0
local function SetupChatTabFading()
    local FADE_IN    = CHAT_FRAME_FADE_TIME     or 0.15
    local FADE_OUT   = CHAT_FRAME_FADE_OUT_TIME or 2.0
    local FADE_DELAY = CHAT_TAB_HIDE_DELAY      or 1.0

    local chatFrames = {}
    local tabs       = {}

    for i = 1, NUM_CHAT_WINDOWS do
        local cf  = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if not cf or not tab then break end
        chatFrames[#chatFrames + 1] = cf
        tabs[#tabs + 1] = tab

        tab:SetAlpha(0)

        -- State: "VISIBLE", "FADING_OUT", or "HIDDEN"
        tab._vui_fadeState = "HIDDEN"
        tab._vui_prevAlpha = 0
        tab._vui_inHook    = false

        hooksecurefunc(tab, "SetAlpha", function(self, a)
            if self._vui_inHook then return end
            self._vui_inHook = true

            pcall(function()
                local state = self._vui_fadeState
                if state == "HIDDEN" and a > 0 then
                    self:SetAlpha(0)
                elseif state == "FADING_OUT" then
                    local prev = self._vui_prevAlpha or 0
                    if a > prev + 0.001 then
                        -- Blizzard trying to raise alpha — block it.
                        self:SetAlpha(prev)
                    else
                        -- Our SmoothFade decreasing alpha — allow it.
                        self._vui_prevAlpha = a
                    end
                end
            end)

            self._vui_inHook = false
        end)
    end

    local hideTimer

    local function IsOverAnyChatElement()
        for _, cf in ipairs(chatFrames) do
            if MouseIsOver(cf) then return true end
        end
        for _, tab in ipairs(tabs) do
            if MouseIsOver(tab) then return true end
        end
        return false
    end

    local function ShowAllTabs()
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
        for _, tab in ipairs(tabs) do
            tab._vui_fadeState = "VISIBLE"
            VUI.SmoothFade(tab, FADE_IN, 1)
        end
    end

    local function HideAllTabs()
        if hideTimer then hideTimer:Cancel() end
        hideTimer = C_Timer.NewTimer(FADE_DELAY, function()
            hideTimer = nil
            if not IsOverAnyChatElement() then
                for _, tab in ipairs(tabs) do
                    tab._vui_fadeState = "FADING_OUT"
                    tab._vui_prevAlpha = tab:GetAlpha()
                    VUI.SmoothFade(tab, FADE_OUT, 0)
                end
                -- After the fade-out duration, switch to hard HIDDEN.
                C_Timer.After(FADE_OUT + 0.05, function()
                    if not IsOverAnyChatElement() then
                        for _, tab in ipairs(tabs) do
                            if tab._vui_fadeState == "FADING_OUT" then
                                tab._vui_fadeState = "HIDDEN"
                                tab._vui_prevAlpha = 0
                            end
                        end
                    end
                end)
            end
        end)
    end

    -- Tab hover: show/hide on direct interaction.
    for _, tab in ipairs(tabs) do
        tab:HookScript("OnEnter", ShowAllTabs)
        tab:HookScript("OnLeave", HideAllTabs)
    end

    -- Chat frame leave: trigger the hide countdown.
    for _, cf in ipairs(chatFrames) do
        cf:HookScript("OnLeave", HideAllTabs)
    end

    -- Synchronize tab fade-in with Blizzard's own chat frame
    -- fade-in, so tabs appear at exactly the same moment.
    if FCF_FadeInChatFrame then
        hooksecurefunc("FCF_FadeInChatFrame", function()
            ShowAllTabs()
        end)
    end
end

-- ── Feature: Hide Chat Buttons ──────────────────────────────
local function HideChatButtons()
    for _, name in ipairs({
        "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrame1ButtonFrameUpButton",
        "ChatFrame1ButtonFrameDownButton",
        "ChatFrame1ButtonFrameBottomButton",
    }) do
        VUI.SuppressFrame(_G[name])
    end
end

-- ── Feature: Hide Voice Chat Button ─────────────────────────
local function HideVoiceChatButton()
    VUI.SuppressFrame(VoiceChatTalkerContainer)
    if ChatFrame1EditBox then
        VUI.SuppressFrame(
            ChatFrame1EditBox.voiceButton
            or _G["ChatFrame1EditBoxVoiceButton"]
        )
    end
end

-- ── Feature: Micro Menu Fade ────────────────────────────────
local function SetupMicroMenuFade()
    VUI.HookHoverFade(MicroMenu)
end

-- ── Feature: Player Frame Fade ──────────────────────────────
local function SetupPlayerFrameFade()
    local evaluate, healthPing = VUI.HookPlayerFrameFade(
        PlayerFrame,
        function() return inCombat end
    )
    frame._playerEvaluate   = evaluate
    frame._playerHealthPing = healthPing
    frame:RegisterUnitEvent("UNIT_HEALTH", "player")
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
end

-- ── Feature: Hide Bag Buttons ───────────────────────────────
-- SuppressFrame is idempotent, so repeated calls are safe.
local function HideBagButtons()
    local function KillAll()
        VUI.SuppressFrame(BagsBar)
        VUI.SuppressFrame(BagBar)
        for _, name in ipairs({
            "MainMenuBarBackpackButton", "BagBarExpandToggle",
            "CharacterBag0Slot", "CharacterBag1Slot",
            "CharacterBag2Slot", "CharacterBag3Slot",
            "CharacterReagentBag0Slot",
        }) do
            VUI.SuppressFrame(_G[name])
        end
    end
    KillAll()
    C_Timer.After(0.5, KillAll)
    C_Timer.After(2.0, KillAll)
end

-- ── Feature: Hide Macro Names ───────────────────────────────
local BAR_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton",      "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button",
    "MultiBar7Button", "MultiBar8Button",
}

local function HideMacroNames()
    local hooked = {}

    local function HideOnButton(btn)
        if not btn then return end
        local fs = btn.Name or (btn:GetName() and _G[btn:GetName() .. "Name"])
        if not fs or hooked[fs] then
            if fs then fs:SetAlpha(0) end
            return
        end
        fs:SetAlpha(0)
        hooked[fs] = true
        hooksecurefunc(fs, "SetText", function(self) self:SetAlpha(0) end)
        hooksecurefunc(fs, "Show",    function(self) self:SetAlpha(0) end)
    end

    local function ScanAll()
        for _, prefix in ipairs(BAR_PREFIXES) do
            for i = 1, 12 do HideOnButton(_G[prefix .. i]) end
        end
        for i = 1, 10 do HideOnButton(_G["PetActionButton" .. i]) end
    end

    ScanAll()
    C_Timer.After(1, ScanAll)
    C_Timer.After(3, ScanAll)
end

-- ── Feature: Hide Error Text ────────────────────────────────
local function HideErrorText()
    if UIErrorsFrame then
        UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    end
end

-- ── Feature: Hide Neutral Nameplates ────────────────────────
-- Hides yellow (neutral) nameplates unless the unit is involved
-- in an active quest.  Quest detection uses C_TooltipInfo to
-- scan for quest-related lines in the unit's tooltip data,
-- plus UnitIsQuestBoss when available.
--
-- Key implementation detail: Blizzard's NamePlateDriverFrame
-- continuously manages plate alpha (distance, occlusion) and
-- will override any SetAlpha on the plate frame itself.  In
-- Midnight, UnitFrames are also protected (Hide() causes
-- taint).  The working approach is:
--   1. SetAlpha(0) on plate.UnitFrame (not the plate)
--   2. Hook CompactUnitFrame_UpdateAll to re-apply after
--      Blizzard refreshes the frame
--   3. Mark hidden UnitFrames with _vui_hideNeutral so the
--      hook knows which ones to suppress
-- ─────────────────────────────────────────────────────────────
local function SetupHideNeutralPlates()

    -- Determine whether a nameplate unit is related to an active quest.
    -- NOTE (3b): Quest detection relies on tooltip line color heuristic
    -- (yellow: r≈1.0, g≈0.82, b≈0.0).  If Blizzard changes the quest
    -- header color in tooltips, this will silently stop matching.
    -- UnitIsQuestBoss provides a partial safety net.
    local function IsQuestRelated(unit)
        -- UnitIsQuestBoss covers kill-objective mobs.
        if UnitIsQuestBoss then
            local ok, result = pcall(UnitIsQuestBoss, unit)
            if ok and result then return true end
        end

        -- Tooltip data scan: quest titles appear with a distinctive
        -- yellow color (r ≈ 1.0, g ≈ 0.82, b ≈ 0.0) in the unit's
        -- tooltip lines.
        if C_TooltipInfo and C_TooltipInfo.GetUnit then
            local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
            if ok and data and data.lines then
                for i = 2, #data.lines do
                    local line = data.lines[i]
                    if line and line.leftColor then
                        local c = line.leftColor
                        if c.r and c.r > 0.9
                            and c.g and c.g > 0.7 and c.g < 0.9
                            and c.b and c.b < 0.15 then
                            return true
                        end
                    end
                end
            end
        end

        return false
    end

    -- Restore visibility on a previously hidden nameplate UnitFrame.
    local function RestoreNameplate(uf)
        if uf._vui_hideNeutral then
            uf._vui_hideNeutral = nil
            uf:SetAlpha(1)
        end
    end

    -- Force the nameplate name text visible (quest-related units).
    -- _vui_questName persists so the CompactUnitFrame_UpdateAll hook
    -- can re-apply the override after each Blizzard refresh cycle.
    local function ApplyQuestName(uf)
        uf._vui_questName = true
        if uf.name then uf.name:SetAlpha(1) end
    end

    -- Remove the forced-name-visible override and let Blizzard's own
    -- CompactUnitFrame_UpdateName restore the unit's normal name state.
    local function ClearQuestName(uf)
        if uf._vui_questName then
            uf._vui_questName = nil
            if CompactUnitFrame_UpdateName then
                pcall(CompactUnitFrame_UpdateName, uf)
            end
        end
    end

    -- Apply or remove the hide/name overrides on a single nameplate.
    -- Behaviour summary:
    --   Neutral  + quest-related  → show plate, force name visible
    --   Neutral  + not quest      → hide plate (alpha 0)
    --   Neutral  + in combat      → show plate, normal name state
    --   Enemy    + quest-related  → plate unchanged, force name visible
    --   Enemy    + not quest      → plate unchanged, normal name state
    -- UnitReaction and UnitAffectingCombat may return Secret Values
    -- in Midnight — pcall-wrapped to degrade gracefully.
    local function EvaluateNameplate(unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate or not plate.UnitFrame then return end
        local uf = plate.UnitFrame

        -- Wrap UnitReaction: may return Secret in Midnight.
        local ok, reaction = pcall(UnitReaction, unit, "player")
        if not ok or issecretvalue and issecretvalue(reaction) then
            RestoreNameplate(uf)
            ClearQuestName(uf)
            return
        end

        -- Evaluate quest status once; used for both name and hide logic.
        local questRelated = IsQuestRelated(unit)

        -- Force name visible for any quest-related unit (neutral or enemy).
        -- Clear the override for units that are no longer quest-related.
        if questRelated then
            ApplyQuestName(uf)
        else
            ClearQuestName(uf)
        end

        -- Non-neutral units: only the name override above applies.
        if reaction ~= 4 then
            RestoreNameplate(uf)
            return
        end

        -- Neutral mob: also check combat state before hiding.
        local cOk, inCombat = pcall(UnitAffectingCombat, unit)
        local isCombat = cOk and inCombat
            and not (issecretvalue and issecretvalue(inCombat))

        if isCombat or questRelated then
            RestoreNameplate(uf)
            return
        end

        -- Neutral, not in combat, not quest-related — hide the UnitFrame.
        uf._vui_hideNeutral = true
        uf:SetAlpha(0)
    end

    -- Re-evaluate every visible nameplate (called on quest changes).
    local function ReevaluateAll()
        local plates = C_NamePlate.GetNamePlates()
        if not plates then return end
        for _, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken
                or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then EvaluateNameplate(unit) end
        end
    end

    -- Hook CompactUnitFrame_UpdateAll so we re-apply the hide after
    -- every Blizzard refresh cycle (health updates, aura updates, etc.).
    -- NOTE (3a): If Midnight restructures nameplate code and removes or
    -- renames this global, the hook silently stops working.  The initial
    -- SetAlpha(0) still applies, but Blizzard's periodic refresh would
    -- override it until NAME_PLATE_UNIT_ADDED re-fires.
    if CompactUnitFrame_UpdateAll then
        hooksecurefunc("CompactUnitFrame_UpdateAll", function(uf)
            if uf and uf._vui_hideNeutral then
                uf:SetAlpha(0)
            end
            -- Re-apply forced name visibility after Blizzard's refresh.
            if uf and uf._vui_questName and uf.name then
                uf.name:SetAlpha(1)
            end
        end)
    end

    local npFrame = CreateFrame("Frame")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    npFrame:RegisterEvent("QUEST_ACCEPTED")
    npFrame:RegisterEvent("QUEST_REMOVED")
    npFrame:RegisterEvent("QUEST_LOG_UPDATE")
    npFrame:RegisterEvent("UNIT_FACTION")
    npFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    npFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    npFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "NAME_PLATE_UNIT_ADDED" then
            EvaluateNameplate(arg1)
            -- Re-evaluate after a short delay: C_TooltipInfo data
            -- (including quest objective lines used by IsQuestRelated)
            -- is often incomplete on the very first frame a nameplate
            -- token is assigned.  The deferred call corrects any false
            -- "hide" that the immediate evaluation applied.
            local unit = arg1
            C_Timer.After(0.15, function() EvaluateNameplate(unit) end)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            local plate = C_NamePlate.GetNamePlateForUnit(arg1)
            if plate and plate.UnitFrame then
                local uf = plate.UnitFrame
                if uf._vui_hideNeutral then
                    uf._vui_hideNeutral = nil
                    uf:SetAlpha(1)
                end
                -- Clear the quest-name flag; the UnitFrame may be
                -- recycled for a different unit next time.
                uf._vui_questName = nil
            end
        elseif event == "UNIT_FACTION" then
            -- A unit's reaction changed (e.g. neutral mob aggro'd).
            if arg1 and arg1:find("nameplate") then
                EvaluateNameplate(arg1)
            end
        elseif event == "PLAYER_REGEN_DISABLED"
            or event == "PLAYER_REGEN_ENABLED" then
            -- Combat state changed — neutral mobs may now be in
            -- combat (or just left it).  Re-evaluate all plates.
            C_Timer.After(0.05, ReevaluateAll)
        else
            -- QUEST_ACCEPTED, QUEST_REMOVED, QUEST_LOG_UPDATE
            C_Timer.After(0.1, ReevaluateAll)
        end
    end)
end

-- ── Options Panel ───────────────────────────────────────────
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local options = {
        { key = "fadeChatTabs",        name = "Fade Chat Tabs",
          tip = "Chat tabs fade out with the chat window and reappear on mouseover." },
        { key = "hideSocialButton",    name = "Hide Social Button",
          tip = "Hides the Quick Join / Communities toast button." },
        { key = "hideChatButtons",     name = "Hide Chat Buttons",
          tip = "Hides the chat scroll buttons and the new-window button." },
        { key = "hideVoiceChatButton", name = "Hide Voice Chat Button",
          tip = "Hides the voice chat icon near the chat frame." },
        { key = "fadeMicroMenu",       name = "Fade Micro Menu",
          tip = "The bottom-right menu bar fades out unless moused over." },
        { key = "fadePlayerFrame",     name = "Fade Player Frame",
          tip = "Your player frame fades out when idle and reappears in combat, when damaged, or on mouseover." },
        { key = "hideBagButtons",      name = "Hide Bag Buttons",
          tip = "Hides the bag bar buttons. You can still open bags with B." },
        { key = "hideMacroNames",      name = "Hide Macro Names",
          tip = "Hides the macro name text displayed on action bar buttons." },
        { key = "hideErrorText",       name = "Hide Error Text",
          tip = "Hides the red error messages like 'Not enough energy' and 'You're facing the wrong way'." },
        { key = "hideNeutralPlates",   name = "Hide Neutral Nameplates",
          tip = "Hides yellow (neutral) nameplates unless the unit is involved in one of your active quests." },
    }

    for _, opt in ipairs(options) do
        local setting = Settings.RegisterAddOnSetting(
            category,
            ADDON_NAME .. "_" .. opt.key,
            opt.key,
            VeritasUI_CleanSoloDB,
            type(defaults[opt.key]),
            opt.name,
            defaults[opt.key]
        )
        setting:SetValueChangedCallback(function(_, value)
            VUI.PrintOnOff("Clean Solo", opt.name, value)
        end)
        Settings.CreateCheckbox(category, setting, opt.tip)
    end

    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

-- ── Events ──────────────────────────────────────────────────
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        VeritasUI_CleanSoloDB = VeritasUI_CleanSoloDB or {}
        for k, v in pairs(defaults) do
            if VeritasUI_CleanSoloDB[k] == nil then
                VeritasUI_CleanSoloDB[k] = v
            end
        end
        db = VeritasUI_CleanSoloDB
        InitializeOptions()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if db.hideSocialButton    then HideSocialButton()    end
        if db.fadeChatTabs        then SetupChatTabFading()  end
        if db.hideChatButtons     then HideChatButtons()     end
        if db.hideVoiceChatButton then HideVoiceChatButton() end
        if db.fadeMicroMenu       then SetupMicroMenuFade()  end
        if db.fadePlayerFrame     then SetupPlayerFrameFade() end
        if db.hideBagButtons      then HideBagButtons()      end
        if db.hideMacroNames      then HideMacroNames()      end
        if db.hideErrorText       then HideErrorText()       end
        if db.hideNeutralPlates   then SetupHideNeutralPlates() end

        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("Clean Solo", "Loaded. Type |cFFFFFF00/cleansolo|r to open settings.")

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if self._playerEvaluate then self._playerEvaluate() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if self._playerEvaluate then self._playerEvaluate() end

    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if self._playerHealthPing then self._playerHealthPing() end
    end
end)

-- ── Slash commands ──────────────────────────────────────────
SLASH_VERITASUI_CLEANSOLO1 = "/cleansolo"
SLASH_VERITASUI_CLEANSOLO2 = "/cs"
SlashCmdList["VERITASUI_CLEANSOLO"] = function()
    Settings.OpenToCategory(settingsCategoryID)
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_CleanSolo_OnAddonCompartmentClick()
    C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
end
