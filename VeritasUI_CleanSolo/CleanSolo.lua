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
    transparentChatBG   = true,
    hideSocialButton    = true,
    hideChatButtons     = true,
    hideVoiceChatButton = true,
    fadeMicroMenu       = true,
    fadePlayerFrame     = true,
    hideBagButtons      = true,
    hideMacroNames      = true,
    hideErrorText       = true,
}

local db
local settingsCategoryID
local frame = CreateFrame("Frame")

-- ── Feature: Transparent Chat Background ────────────────────
-- Writes alpha=0 to each chat frame's backdrop via Blizzard's
-- FCF_SetWindowAlpha API (the same setting the right slider in
-- /chatconfig → "Edit Window Appearance" controls). The color
-- component is left untouched — users who set a non-default tint
-- keep it. Blizzard's built-in hover-to-reveal behavior handles
-- the rest: background is invisible when idle, visible on
-- mouseover, exactly matching the Clean Solo aesthetic.
--
-- Runs once at PLAYER_LOGIN, then hooks FCF_SetWindowColor and
-- FCF_SetWindowAlpha so that any time the user opens the tab
-- right-click → "Background" color picker (or any other code path
-- changes the chat window color/alpha), alpha=0 is re-applied.
-- This is required because Blizzard's color picker fires its
-- opacityFunc on open with its cached value, which would otherwise
-- overwrite our setting.
--
-- The hooks gate on db.transparentChatBG so toggling the feature
-- off + /reload cleanly disables enforcement — hooksecurefunc
-- itself can't be unhooked, but db-gating has the same effect.
local function SetupTransparentChatBG()
    if not FCF_SetWindowAlpha then return end

    local function ApplyAlphaZero(cf)
        -- Third arg `true` is FCF_SetWindowAlpha's `doNotSave` flag —
        -- skips persistence to Blizzard's chat-config saved state so our
        -- hook-enforced alpha=0 stays session-volatile. This means
        -- toggling the feature off and /reloading restores Blizzard's
        -- saved alpha rather than leaving alpha=0 baked into the profile.
        if cf and cf._vui_inAlphaHook then return end
        if cf then cf._vui_inAlphaHook = true end
        pcall(FCF_SetWindowAlpha, cf, 0, true)
        if cf then cf._vui_inAlphaHook = false end
    end

    -- Initial pass: transparent every existing chat frame.
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        ApplyAlphaZero(_G["ChatFrame" .. i])
    end

    -- Enforce on user-driven color changes (tab right-click → Background).
    if FCF_SetWindowColor then
        hooksecurefunc("FCF_SetWindowColor", function(cf)
            if db and db.transparentChatBG then ApplyAlphaZero(cf) end
        end)
    end

    -- Enforce on any alpha-change attempt (e.g. opacity slider in the
    -- color picker, or Blizzard's opacityFunc firing on dialog open).
    -- The re-entry guard inside ApplyAlphaZero prevents our own 0-write
    -- from looping through the hook.
    hooksecurefunc("FCF_SetWindowAlpha", function(cf, alpha)
        if db and db.transparentChatBG and alpha and alpha > 0 then
            ApplyAlphaZero(cf)
        end
    end)
end

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

    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf  = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        -- Skip missing slots rather than aborting; frames may be non-contiguous.
        if cf and tab then
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

                local state = self._vui_fadeState
                if state == "HIDDEN" and a > 0 then
                    self:SetAlpha(0)
                elseif state == "FADING_OUT" then
                    local prev = self._vui_prevAlpha or 0
                    if a > prev + 0.001 then
                        self:SetAlpha(prev)
                    else
                        self._vui_prevAlpha = a
                    end
                end

                self._vui_inHook = false
            end)
        end
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
        InCombatLockdown
    )
    frame._playerEvaluate   = evaluate
    frame._playerHealthPing = healthPing
    frame:RegisterUnitEvent("UNIT_HEALTH", "player")
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    -- Combat events are only needed when this feature is active.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- ── Feature: Hide Bag Buttons ───────────────────────────────
-- SuppressFrame is idempotent, so repeated calls are safe.
-- KillAll runs immediately and again at 0.5 s and 2.0 s because
-- MainMenuBarBackpackButton and BagBarExpandToggle re-show themselves
-- asynchronously during the login sequence; SuppressFrame's Show-hook
-- keeps them permanently hidden after the login burst settles.
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

-- ── Options Panel ───────────────────────────────────────────
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local options = {
        { key = "fadeChatTabs",        name = "Fade Chat Tabs",
          tip = "Chat tabs fade out with the chat window and reappear on mouseover." },
        { key = "transparentChatBG",   name = "Transparent Chat Background",
          tip = "Sets the chat window background to fully transparent so only the text is visible when idle. "
             .. "Blizzard's built-in hover behavior reveals the background on mouseover. "
             .. "Disabling this does not restore your previous alpha — use /chatconfig to adjust manually." },
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
        if db.transparentChatBG   then SetupTransparentChatBG() end
        if db.hideChatButtons     then HideChatButtons()     end
        if db.hideVoiceChatButton then HideVoiceChatButton() end
        if db.fadeMicroMenu       then SetupMicroMenuFade()  end
        if db.fadePlayerFrame     then SetupPlayerFrameFade() end
        if db.hideBagButtons      then HideBagButtons()      end
        if db.hideMacroNames      then HideMacroNames()      end
        if db.hideErrorText       then HideErrorText()       end

        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("Clean Solo", "Loaded. Type |cFFFFFF00/cleansolo|r to open settings.")

    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
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
