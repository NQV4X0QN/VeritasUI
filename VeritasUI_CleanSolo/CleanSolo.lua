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
-- in an active quest or the player is engaged with it.
--
-- Key implementation detail (TWW / Midnight):
--   SetAlpha() on plate.UnitFrame (a CompactUnitFrame) is a
--   protected action and triggers ADDON_ACTION_BLOCKED during
--   combat lockdown.  The fix is to operate on the plate frame
--   itself (not the UnitFrame).  NamePlateDriverFrame constantly
--   manages plate alpha for distance/occlusion — instead of
--   fighting that, we use an OnUpdate loop to keep suppressed
--   plates at alpha 0, and simply stop overriding when we want
--   the plate to show.  Blizzard's driver then restores it
--   naturally in the next frame.
-- ─────────────────────────────────────────────────────────────
local function SetupHideNeutralPlates()

    local engagedGUIDs = {}
    local hiddenPlates = {}   -- plate frame → true for plates we suppress

    local DAMAGE_SUB = {
        SWING_DAMAGE          = true, SWING_MISSED          = true,
        SPELL_DAMAGE          = true, SPELL_MISSED          = true,
        RANGE_DAMAGE          = true, RANGE_MISSED          = true,
        SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_MISSED = true,
    }

    -- ── OnUpdate: continuously hold suppressed plates at alpha 0 ──
    -- Idles (hidden) when no plates are suppressed so it has no
    -- per-frame cost outside of combat near neutral mobs.
    local overrideFrame = CreateFrame("Frame")
    overrideFrame:Hide()
    overrideFrame:SetScript("OnUpdate", function()
        local any = false
        for plate in pairs(hiddenPlates) do
            if plate:IsShown() then
                plate:SetAlpha(0)
                any = true
            else
                hiddenPlates[plate] = nil
            end
        end
        if not any then overrideFrame:Hide() end
    end)

    -- ── Hide / show helpers — operate on the plate, not UnitFrame ──
    local function HidePlate(plate)
        hiddenPlates[plate] = true
        plate:SetAlpha(0)
        overrideFrame:Show()
    end

    local function ShowPlate(plate)
        if hiddenPlates[plate] then
            hiddenPlates[plate] = nil
            -- Do NOT call plate:SetAlpha(1) — NamePlateDriverFrame
            -- restores it automatically on the next frame.
            if not next(hiddenPlates) then overrideFrame:Hide() end
        end
    end

    -- ── Quest detection ──────────────────────────────────────────
    local function IsQuestRelated(unit)
        if UnitIsQuestBoss then
            local ok, result = pcall(UnitIsQuestBoss, unit)
            if ok and result then return true end
        end
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

    -- ── Evaluate a single nameplate ──────────────────────────────
    local function EvaluateNameplate(unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate then return end

        local ok, reaction = pcall(UnitReaction, unit, "player")
        if not ok or (issecretvalue and issecretvalue(reaction)) then
            ShowPlate(plate); return
        end

        -- Non-neutral: never suppress.
        if reaction ~= 4 then
            ShowPlate(plate); return
        end

        -- Neutral: show if quest-related, in combat, or engaged.
        local questRelated = IsQuestRelated(unit)

        local cOk, unitInCombat = pcall(UnitAffectingCombat, unit)
        local isCombat = cOk and unitInCombat
            and not (issecretvalue and issecretvalue(unitInCombat))

        local tOk, threat = pcall(UnitThreatSituation, "player", unit)
        local hasThreat = tOk and threat ~= nil
            and not (issecretvalue and issecretvalue(threat))

        local guid = UnitGUID(unit)
        local playerEngaged = guid and engagedGUIDs[guid]

        if questRelated or isCombat or hasThreat or playerEngaged then
            ShowPlate(plate)
        else
            HidePlate(plate)
        end
    end

    local function ReevaluateAll()
        local plates = C_NamePlate.GetNamePlates()
        if not plates then return end
        for _, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken
                or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then EvaluateNameplate(unit) end
        end
    end

    -- ── Event handler ────────────────────────────────────────────
    local npFrame = CreateFrame("Frame")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    npFrame:RegisterEvent("QUEST_ACCEPTED")
    npFrame:RegisterEvent("QUEST_REMOVED")
    npFrame:RegisterEvent("QUEST_LOG_UPDATE")
    npFrame:RegisterEvent("UNIT_FACTION")
    npFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    npFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    npFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    npFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "NAME_PLATE_UNIT_ADDED" then
            EvaluateNameplate(arg1)
            local unit = arg1
            C_Timer.After(0.15, function() EvaluateNameplate(unit) end)

        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            local plate = C_NamePlate.GetNamePlateForUnit(arg1)
            if plate then ShowPlate(plate) end

        elseif event == "UNIT_FACTION"
            or event == "UNIT_THREAT_LIST_UPDATE" then
            if arg1 and arg1:find("nameplate") then
                EvaluateNameplate(arg1)
            end

        elseif event == "PLAYER_REGEN_DISABLED" then
            C_Timer.After(0.05, ReevaluateAll)

        elseif event == "PLAYER_REGEN_ENABLED" then
            wipe(engagedGUIDs)
            C_Timer.After(0.05, ReevaluateAll)

        else
            -- QUEST_ACCEPTED, QUEST_REMOVED, QUEST_LOG_UPDATE
            C_Timer.After(0.1, ReevaluateAll)
        end
    end)

    -- ── Combat log listener (isolated frame) ─────────────────────
    -- On its own frame to keep CombatLogGetCurrentEventInfo() away
    -- from any nameplate-adjacent execution path.
    local clFrame = CreateFrame("Frame")
    clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    clFrame:SetScript("OnEvent", function()
        local _, subEvent, _, srcGUID, _, _, _, dstGUID =
            CombatLogGetCurrentEventInfo()
        if not DAMAGE_SUB[subEvent] then return end
        local pGUID = UnitGUID("player")
        local mobGUID
        if srcGUID == pGUID then mobGUID = dstGUID
        elseif dstGUID == pGUID then mobGUID = srcGUID end
        if not mobGUID or engagedGUIDs[mobGUID] then return end
        engagedGUIDs[mobGUID] = true
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
                local u = plate.namePlateUnitToken
                    or (plate.UnitFrame and plate.UnitFrame.unit)
                if u and UnitGUID(u) == mobGUID then
                    ShowPlate(plate); break
                end
            end
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
