-- VeritasUI_CleanSolo / CleanSolo.lua
-- Fades or hides noisy default UI elements for solo play.
-- Settings: Options → AddOns → Clean Solo  |  /cleansolo  |  /cs
--
-- ────────────────────────────────────────────────────────────────
--  POLICY: /reload required to apply setting changes (by design)
-- ────────────────────────────────────────────────────────────────
--
--  CleanSolo's features are implemented almost entirely via
--  hooksecurefunc — chat-tab fade, transparent chat background, the
--  social/voice/chat button hides, micro menu fade, player frame fade,
--  bag button hides, macro name hide, and error text suppression all
--  install Blizzard secure-function hooks at PLAYER_LOGIN.
--
--  hooksecurefunc has no inverse: once installed, a hook cannot be
--  removed at runtime.  This means CleanSolo settings cannot cleanly
--  toggle off mid-session — disabling a setting at runtime would
--  leave the hook installed, which would either: (a) keep the side
--  effect active despite the setting being "off", or (b) require
--  every hook to add a self-disabling guard against its own setting,
--  doubling the surface area of every feature for a minor UX win.
--
--  We chose (c): every CS setting is db-gated at hook-installation
--  time on PLAYER_LOGIN.  Toggling a setting writes to saved-vars
--  but does not unhook anything; the hook either fires (db is true,
--  feature on) or fires-but-no-ops (db is false, feature off, but
--  hook still installed harmlessly).  /reload re-runs PLAYER_LOGIN
--  init with the new db values, which is when the hooks actually
--  get re-evaluated against the current settings.
--
--  This is asymmetric with QualityOfLife's v1.6.28 mid-session-apply
--  pattern (QoL setting changes take effect immediately).  The
--  asymmetry is intentional: QoL features are mostly self-contained
--  event handlers that can be event-unregistered cleanly, whereas
--  CS features are hooks that cannot.
--
--  All CS setting tooltips and the on-toggle PrintOnOff message
--  consistently mention "/reload to apply" so the user is never
--  surprised by the policy.  See the tooltip strings in the
--  options{} table inside InitializeOptions for the wording.
-- ────────────────────────────────────────────────────────────────

local ADDON_NAME     = "VeritasUI_CleanSolo"
local SETTINGS_LABEL = "Clean Solo"

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G               = _G
local ipairs, pairs    = ipairs, pairs
local pcall            = pcall
local CreateFrame      = CreateFrame
local C_Timer          = C_Timer

local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Defaults & state
----------------------------------------------------------------
-- Saved settings, split by SCOPE. Authority: references/setting-scope-map.md in the skill
-- directory; enforced by scope_map_test and module_scope_test.
--
-- Shared by every character: chrome-hiding and chat cosmetics are choices about the interface
-- itself, not about how a particular character is played.
local UNIVERSAL = {
    fadeChatTabs        = true,
    transparentChatBG   = true,
    hideSocialButton    = true,
    hideChatButtons     = true,
    hideVoiceChatButton = true,
    fadeMicroMenu       = true,
    hideBagButtons      = true,
    hideMacroNames      = true,
    hideErrorText       = true,   -- the "All" row of the Hide Error Text dropdown (was its own checkbox)
    -- [groupId] = true. TABLE-typed. Overridden while hideErrorText ("All") is on.
    -- PAIRED: hideErrorTypesMask (the dropdown's tick-box value) is derived from this and
    -- hideErrorText, and must share their scope; like fadeActionBarsMask it has no default
    -- here because the Settings registration seeds it.
    hideErrorTypes      = {},
    -- Fade Delay slider, seconds (0-5). One value for every fade, an interface choice like the
    -- rest of this table. 0 = each fade's own built-in delay, i.e. the behaviour before v1.25.0.
    fadeDelay           = 0,
    -- v1.26.0 (EllesmereUI-inspired plan, phase 1). OFF by default: unlike the original options
    -- these remove game content (story popups, zone names, boss loot), so nobody gets them unasked.
    hideTalkingHead     = false,
    muteTalkingHead     = false,
    hideTopBanners      = false,
    hideProfessionGear  = false,   -- v1.27.0, owner's request; applies at once
}

-- ⚠ PER-CHARACTER. These two are the reason per-character storage was requested in the first
-- place: action bars are laid out and used differently from character to character, so an alt
-- inheriting a main's bar-fade choices was the original complaint.
--
-- PAIRED CONSTRAINT: fadeActionBarsMask is the dropdown's tick-box value and is recomputed from
-- fadeActionBars. It MUST share that key's scope, or the ticks shown in the panel would describe
-- a different character's bars. It has no default here on purpose -- Blizzard's Settings
-- framework seeds it via the default passed at registration. (Until v1.21.0 the same role was
-- played by the display string fadeActionBarsLabel, retired at login in InitializeOptions.)
local PERCHAR = {
    fadeActionBars  = {},     -- [barIndex] = true; TABLE-typed, so it needs a per-character copy
    fadePlayerFrame = true,
}


local db
-- ⚠ Declared here, above every reader. `cdb` is the PER-CHARACTER table and is nil until
-- PLAYER_LOGIN: VUI.BindScopedDB deliberately does not fall back to the account root.
local cdb = nil
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
-- Hides ALL chat tabs by default.  Each tab fades in when Blizzard
-- fades in its chat window and fades out when Blizzard fades it
-- out, so it never shows without its window (v1.34.1, v1.35.5).
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

    local tabs = {}   -- chat window -> its tab

    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf  = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        -- Skip missing slots rather than aborting; frames may be non-contiguous.
        if cf and tab then
            tabs[cf] = tab

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

    -- Each window's "fade-out finished -> go hard HIDDEN" timer, by tab. Cancelled when that
    -- window fades back in, or a stale one would flip state to HIDDEN mid-fade and the alpha hook
    -- above would snap the tab to 0.
    local fadeDoneTimers = {}

    -- ⚠ THE TABS FOLLOW THE WINDOW AND NOTHING ELSE (owner, 2026-10-30). Until v1.34.0 they also
    -- came in on their own the instant the mouse touched one (tab OnEnter), while Blizzard fades
    -- the window in only after the mouse rests over it for CHAT_TAB_SHOW_DELAY (FCF_OnUpdate,
    -- FloatingChatFrame.lua:1140-1151) -- so sweeping across the tabs left them floating over no
    -- window. Blizzard's hover area reaches 28 px above the window (topOffset, :1125), over the
    -- tab strip, so resting on a tab still brings both in, together. Do NOT re-add tab hover
    -- hooks, and do NOT call FCF_FadeInChatFrame ourselves: it runs Blizzard's shared
    -- UIFrameFade table from addon code (landmine 33).
    -- ⚠ EACH TAB FOLLOWS ITS OWN WINDOW (v1.35.5). Blizzard fades one window and its tab; when
    -- that window is the dock's selected one it repeats the call for every docked window
    -- (FCF_FadeInChatFrame / FCF_FadeOutChatFrame, FloatingChatFrame.lua:1052-1118), so docked
    -- tabs still come and go together. Moving all tabs on any window's fade popped the docked
    -- tabs up over a faded main chat whenever an undocked or whisper window was hovered.
    local function ShowTab(cf)
        local tab = cf and tabs[cf]
        if not tab then return end
        if fadeDoneTimers[tab] then fadeDoneTimers[tab]:Cancel(); fadeDoneTimers[tab] = nil end
        tab._vui_fadeState = "VISIBLE"
        VUI.SmoothFade(tab, CHAT_FRAME_FADE_TIME or FADE_IN, 1)
    end

    -- Starts in the same frame as Blizzard's own fade-out of the window, at its speed.
    local function HideTab(cf)
        local tab = cf and tabs[cf]
        if not tab or tab._vui_fadeState ~= "VISIBLE" then return end
        if fadeDoneTimers[tab] then fadeDoneTimers[tab]:Cancel(); fadeDoneTimers[tab] = nil end
        tab._vui_fadeState = "FADING_OUT"
        tab._vui_prevAlpha = tab:GetAlpha()
        VUI.SmoothFade(tab, FADE_OUT, 0)
        fadeDoneTimers[tab] = C_Timer.NewTimer(FADE_OUT + 0.05, function()
            fadeDoneTimers[tab] = nil
            if tab._vui_fadeState == "FADING_OUT" then
                tab._vui_fadeState = "HIDDEN"
                tab._vui_prevAlpha = 0
            end
        end)
    end

    if FCF_FadeInChatFrame then hooksecurefunc("FCF_FadeInChatFrame", ShowTab) end
    if FCF_FadeOutChatFrame then hooksecurefunc("FCF_FadeOutChatFrame", HideTab) end
end

-- ── Feature: Hide Chat Buttons ──────────────────────────────
-- The chat menu button (speech bubble). Frame names are SOURCED, live 12.1:
-- Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.xml:659. Until v1.17.11 this list also
-- held the voice/channels button (which belongs to the voice option below) and three
-- ChatFrame1ButtonFrame{Up,Down,Bottom}Button scroll buttons that no longer exist (audit C1).
local function HideChatButtons()
    VUI.SuppressFrame(_G.ChatFrameMenuButton)
end

-- ── Feature: Hide Voice Chat Button ─────────────────────────
-- The voice/channels button (headset) and the mute/deafen pair Blizzard shows while you are in
-- a voice channel: Blizzard_ChatFrame/Mainline/FloatingChatFrameVoiceChat.xml:4-27. Until
-- v1.17.11 this targeted VoiceChatTalkerContainer and ChatFrame1EditBox.voiceButton, neither
-- of which exists in 12.1, so the option did nothing (audit C1).
local function HideVoiceChatButton()
    for _, name in ipairs({
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
    }) do
        VUI.SuppressFrame(_G[name])
    end
end

-- ── Feature: Micro Menu Fade ────────────────────────────────
-- Both return values are captured and driven from ExitEditMode, mirroring the
-- action-bar path below. They were added to HookHoverFade AFTER this call site
-- was written (FadeOut in v1.6.13, RefreshChildren in v1.6.14, both for the
-- action-bar feature) and this site was never migrated — the omission was an
-- oversight, not a decision. Both of the conditions that motivated them apply
-- to the micro menu equally: it is Edit-Mode movable, so Blizzard forces it
-- visible during layout editing and no OnLeave fires afterwards to re-assert
-- alpha 0; and its child set changes (the Great Vault button appears and
-- disappears), which invalidates the child cache HookHoverFade builds at hook
-- time.
local function SetupMicroMenuFade()
    local fo, rc = VUI.HookHoverFade(MicroMenu)
    if fo and EditModeManagerFrame then
        pcall(hooksecurefunc, EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.2, function()
                if rc then rc() end
                fo()
            end)
        end)
    end
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

-- ── Feature: Hide Talking Head / Mute Talking Head Voice (v1.26.0) ──
-- Two independent options: the popup and its voice are separate in Blizzard's own code, so a
-- player can hide one and keep the other. Source: Blizzard_FrameXML/TalkingHeadUI.lua.
--   Hide: visibility is decided only by UpdateShownState (:241-243, SetShown(isInEditMode or
--   isPlaying)); a hook after it hides the frame unless Edit Mode is open, so the frame can still
--   be placed. The voice is a separate PlaySound (:211) and keeps playing.
--   Mute: PlayCurrent starts the line's sound and keeps its handle in self.voHandle (:211-214);
--   a hook after it stops that sound. The handle is only READ -- no Blizzard field is written.
-- Both hooks also check the saved value, so turning an option off stops it straight away.
local function SetupTalkingHead()
    local thf = _G.TalkingHeadFrame
    if not thf then return end
    if db.hideTalkingHead and thf.UpdateShownState then
        hooksecurefunc(thf, "UpdateShownState", function(self)
            if db.hideTalkingHead and not self.isInEditMode and self:IsShown() then self:Hide() end
        end)
        if thf:IsShown() and not thf.isInEditMode then thf:Hide() end
    end
    if db.muteTalkingHead and thf.PlayCurrent then
        hooksecurefunc(thf, "PlayCurrent", function(self)
            if db.muteTalkingHead and self.voHandle and StopSound then StopSound(self.voHandle) end
        end)
    end
end

-- ── Feature: Hide Top Banners (v1.26.0) ─────────────────────
-- The big zone name, event toasts (level up, scenario stages, weekly rewards, flight points...)
-- and the boss kill/loot banner. Each is STOPPED FROM STARTING by unregistering the event that
-- starts it, the same mechanism HideErrorText uses -- not hidden mid-animation. Hiding a playing
-- boss banner would leave it stuck as TopBannerMgr.currentBanner (its animation never finishes
-- on a hidden frame, so TopBannerManager_BannerFinished never runs; TopBannerManager.lua), which
-- would block every later top banner. Events, from source:
--   ZoneTextFrame          ZONE_CHANGED, _INDOORS, _NEW_AREA  (Mainline/ZoneText.lua:76-78; the
--                          sub-zone text is only ever shown from that same handler, :83-121)
--   BossBanner             BOSS_KILL, ENCOUNTER_LOOT_RECEIVED (BossBannerToast.lua:182-183)
--   EventToastManagerFrame DISPLAY_EVENT_TOASTS               (EventToastManager.lua:151)
-- Blizzard's OnLoad registers them again on the next load, so /reload with the option off undoes it.
local TOP_BANNER_EVENTS = {
    { "ZoneTextFrame",          { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" } },
    { "BossBanner",             { "BOSS_KILL", "ENCOUNTER_LOOT_RECEIVED" } },
    { "EventToastManagerFrame", { "DISPLAY_EVENT_TOASTS" } },
}

local function HideTopBanners()
    for _, entry in ipairs(TOP_BANNER_EVENTS) do
        local f = _G[entry[1]]
        if f and f.UnregisterEvent then
            for _, ev in ipairs(entry[2]) do pcall(f.UnregisterEvent, f, ev) end
        end
    end
end

-- ── Feature: Hide Profession Gear (v1.27.0) ─────────────────
-- Crafting or gathering puts a profession outfit on you as a cosmetic transform AURA; removing
-- that aura puts your own outfit back. Owner's request, 2026-10-29.
--
-- ⚠ The aura spell IDs are NOT from Blizzard's UI source (an aura's spell ID is server data, not
-- UI code). They come from EllesmereUI v9.6.9's transform list (EllesmereUIQoL.lua:4880-4893),
-- read 2026-10-29. If a profession's outfit still shows, `/cs gear` lists what is on you so the
-- missing ID can be added here.
--
-- Removal: C_UnitAuras.CancelAuraByInstanceID (UnitAuraDocumentation.lua:85, HasRestrictions),
-- found with GetPlayerAuraBySpellID (:395), so there is no buff-index scan. Never in combat, and
-- every read is pcall'd and secret-checked: aura data is secret in restricted content, where this
-- simply does nothing. A cancel refused in combat is retried when combat ends.
--
-- Fishing is the exception: its outfit (394009) is re-applied for as long as the fishing channel
-- (131476) runs, so it is removed when the channel stops.
local PROFESSION_GEAR_AURAS = {
    388658,   -- Blacksmithing
    394015,   -- Jewelcrafting
    391312,   -- Tailoring
    394007,   -- Engineering
    394008,   -- Enchanting
    394003,   -- Alchemy
    394016,   -- Inscription
    394001,   -- Leatherworking
    394005,   -- Herbalism
    394006,   -- Mining
    394011,   -- Skinning
    391775,   -- Cooking (Chef's Hat)
    394009,   -- Fishing (removed on channel stop, below)
}
local FISHING_AURA, FISHING_CHANNEL = 394009, 131476

local gearFrame = CreateFrame("Frame")
local gearPending = false
local gearLast = "none yet"   -- for /cs gear

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Remove every listed outfit aura on the player. Returns how many were removed.
local function RemoveProfessionGear(includeFishing)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.CancelAuraByInstanceID) then
        gearLast = "aura API missing"
        return 0
    end
    if InCombatLockdown() then gearPending = true; return 0 end
    local removed = 0
    for _, id in ipairs(PROFESSION_GEAR_AURAS) do
        if includeFishing or id ~= FISHING_AURA then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            local inst = ok and aura and not IsSecret(aura) and aura.auraInstanceID
            if inst and not IsSecret(inst) then
                local cok = pcall(C_UnitAuras.CancelAuraByInstanceID, "player", inst)
                if cok then
                    removed = removed + 1
                    gearLast = "removed " .. id
                else
                    gearLast = "cancel refused for " .. id
                end
            end
        end
    end
    return removed
end

gearFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "PLAYER_REGEN_ENABLED" then
        if gearPending then gearPending = false; RemoveProfessionGear(true) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if not IsSecret(spellID) and spellID == FISHING_CHANNEL then RemoveProfessionGear(true) end
    else -- UNIT_AURA, player only
        RemoveProfessionGear(false)
    end
end)

local function SetHideProfessionGear(on)
    if on then
        gearFrame:RegisterUnitEvent("UNIT_AURA", "player")
        gearFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        gearFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        RemoveProfessionGear(false)
    else
        gearFrame:UnregisterAllEvents()
        gearPending = false
    end
end

-- /cs gear: what is on you now, so a profession whose outfit still shows can be identified.
-- Lists the listed outfit auras found, then every buff's name and spell ID (scan pcall'd: aura
-- data is secret in restricted content).
local function PrintGearDiag()
    VUI.Print("Clean Solo", "Hide Profession Gear: " .. ((db and db.hideProfessionGear) and "on" or "off")
        .. ", last result: " .. gearLast)
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
    for i = 1, 40 do
        local ok, data = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
        if not ok then VUI.Print("Clean Solo", "  buffs can't be read here"); return end
        if not data then return end
        local name, id = data.name, data.spellId
        if IsSecret(name) or IsSecret(id) then VUI.Print("Clean Solo", "  (hidden)")
        else VUI.Print("Clean Solo", string.format("  %s  %d", tostring(name), id or 0)) end
    end
end

-- ── Feature: Hide Error Text ────────────────────────────────
local function HideErrorText()
    if UIErrorsFrame then
        UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    end
end

-- ── Feature: Hide Error Text, by type ──────────────────────
-- Used only when "All" (hideErrorText) is off. Each red error carries a numeric type
-- (LE_GAME_ERR_*), and Blizzard keeps a per-type hidden list with a setter for it:
-- UIErrorsMixin:SetMessageTypeEnabled, Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua.
-- The list is checked before the message is shown AND before its voice line plays.
--
-- ⚠ That list is shared with the yellow UI_INFO_MESSAGE path (same file, OnEvent), so
-- hiding a type hides it in yellow too. That is why these are hand-picked failure
-- messages and there is no "everything else" group: quest progress, "Mail sent.", friend
-- online and the like are message types too, and a catch-all would swallow them.
--
-- ⚠ We only ever write `true` into Blizzard's list. Un-hiding is done by /reload, which
-- rebuilds the list from Blizzard's own file, so no value of ours is left behind to be read
-- on a message we meant to show.
--
-- Names, not numbers: the numbers are assigned by the client and resolved through _G at
-- login, so a type Blizzard removes is skipped instead of hiding the wrong message.
local ERROR_TYPE_GROUPS = {
    { id = "combat", label = "Combat: Range, Facing & Targets",
      types = {
        "BADATTACKPOS", "BADATTACKFACING", "OUT_OF_RANGE", "SPELL_OUT_OF_RANGE",
        "PET_SPELL_OUT_OF_RANGE", "NO_ATTACK_TARGET", "GENERIC_NO_TARGET",
        "GENERIC_NO_VALID_TARGETS", "INVALID_ATTACK_TARGET", "COMMAND_NEEDS_TARGET",
        "UNIT_NOT_FOUND", "ATTACK_CHANNEL", "ATTACK_CHARMED", "ATTACK_CONFUSED",
        "ATTACK_DEAD", "ATTACK_FLEEING", "ATTACK_MOUNTED", "ATTACK_NO_ACTIONS",
        "ATTACK_PACIFIED", "ATTACK_PREVENTED_BY_MECHANIC_S",
        "ATTACK_PVP_TARGET_WHILE_UNFLAGGED", "ATTACK_STUNNED", "PET_SPELL_NOT_BEHIND",
        "PET_SPELL_TARGETS_DEAD", "PET_SPELL_DEAD", "PET_SPELL_ROOTED", "PET_SPELL_NOPATH",
        "PET_SPELL_AFFECTING_COMBAT", "TARGET_STUNNED", "CANT_TARGET_UNFRIENDLY_IN_OVERWORLD",
      } },
    { id = "spells", label = "Spells & Cooldowns",
      types = {
        "ABILITY_COOLDOWN", "SPELL_COOLDOWN", "ITEM_COOLDOWN", "POTION_COOLDOWN",
        "FOOD_COOLDOWN", "SPELL_FAILED_ALREADY_AT_FULL_HEALTH",
        "SPELL_FAILED_ALREADY_AT_FULL_MANA", "SPELL_FAILED_ALREADY_AT_FULL_POWER_S",
        "SPELL_FAILED_ANOTHER_IN_PROGRESS", "SPELL_FAILED_CANT_FLY_HERE",
        "SPELL_FAILED_EQUIPPED_ITEM", "SPELL_FAILED_EQUIPPED_ITEM_CLASS_S",
        "SPELL_FAILED_EQUIPPED_SPECIFIC_ITEM", "SPELL_FAILED_LEVEL_REQUIREMENT",
        "SPELL_FAILED_NOTUNSHEATHED", "SPELL_FAILED_OPTIONAL_REAGENTS",
        "SPELL_FAILED_REAGENTS", "SPELL_FAILED_REAGENTS_GENERIC", "SPELL_FAILED_S",
        "SPELL_FAILED_SHAPESHIFT_FORM_S", "SPELL_FAILED_TOTEMS",
        "OUT_OF_ALTERNATE_ENCOUNTER", "OUT_OF_ALTERNATE_MOUNT", "OUT_OF_ALTERNATE_QUEST",
        "OUT_OF_ARCANE_CHARGES", "OUT_OF_BALANCE", "OUT_OF_CHI", "OUT_OF_COMBO_POINTS",
        "OUT_OF_ENERGY", "OUT_OF_ESSENCE", "OUT_OF_FOCUS", "OUT_OF_FURY",
        "OUT_OF_HAPPINESS", "OUT_OF_HEALTH", "OUT_OF_HOLY_POWER", "OUT_OF_INSANITY",
        "OUT_OF_LUNAR_POWER", "OUT_OF_MAELSTROM", "OUT_OF_MANA", "OUT_OF_PAIN",
        "OUT_OF_POWER_DISPLAY", "OUT_OF_RAGE", "OUT_OF_RUNES", "OUT_OF_RUNE_BLOOD",
        "OUT_OF_RUNE_CHROMATIC", "OUT_OF_RUNE_FROST", "OUT_OF_RUNE_UNHOLY",
        "OUT_OF_RUNIC_POWER", "OUT_OF_SHADOW_ORBS", "OUT_OF_SOUL_SHARDS",
        "NOT_WHILE_DISARMED", "NOT_WHILE_FALLING", "NOT_WHILE_FATIGUED",
        "NOT_WHILE_MOUNTED", "NOT_WHILE_MOVING", "NOT_WHILE_SHAPESHIFTED",
        "NOT_IN_COMBAT", "AFFECTING_COMBAT", "GENERIC_STUNNED", "CANT_USE_DISARMED",
        "CANT_DO_THAT_RIGHT_NOW", "PASSIVE_ABILITY", "NOAMMO_S",
      } },
    { id = "items", label = "Items & Bags",
      types = {
        "INV_FULL", "BAG_FULL", "CANT_USE_ITEM", "CANT_USE_ITEM_IN_ARENA",
        "CANT_USE_ITEM_IN_RATED_BATTLEGROUND", "CANT_EQUIP_EVER", "CANT_EQUIP_LEVEL_I",
        "CANT_EQUIP_NEED_TALENT", "CANT_EQUIP_RANK", "CANT_EQUIP_RATING",
        "CANT_EQUIP_REPUTATION", "CANT_EQUIP_SKILL", "CANT_STACK", "CANT_SWAP",
        "WRONG_SLOT", "WRONG_BAG_TYPE", "WRONG_BAG_TYPE_SUBCLASS", "NOT_EQUIPPABLE",
        "ITEM_LOCKED", "ITEM_MAX_COUNT", "ITEM_MAX_COUNT_EQUIPPED_SOCKETED",
        "ITEM_MAX_COUNT_SOCKETED", "ITEM_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS",
        "ITEM_MAX_LIMIT_CATEGORY_EQUIPPED_EXCEEDED_IS",
        "ITEM_MAX_LIMIT_CATEGORY_SOCKETED_EXCEEDED_IS", "ITEM_UNIQUE_EQUIPPABLE",
        "ITEM_UNIQUE_EQUIPPABLE_SOCKETED", "ITEM_CANT_BE_DESTROYED", "2HANDED_EQUIPPED",
        "2HSKILLNOTFOUND", "SPLIT_FAILED", "TOO_FEW_TO_SPLIT", "DESTROY_NONEMPTY_BAG",
        "BAG_IN_BAG", "NOT_A_BAG", "SLOT_EMPTY", "MUST_EQUIP_ITEM",
        "EQUIPMENT_MANAGER_BAGS_FULL", "INTERNAL_BAG_ERROR", "NO_SLOT_AVAILABLE",
        "REAGENTBAG_ITEM_TYPE", "REAGENTBAG_WRONG_SLOT", "SLOT_ONLY_REAGENTBAG",
        "NO_ITEMS_WHILE_SHAPESHIFTED", "SHAPESHIFT_FORM_CANNOT_EQUIP",
        "TOO_MANY_SPECIAL_BAGS", "ONLY_ONE_AMMO", "ONLY_ONE_BOLT", "ONLY_ONE_QUIVER",
        "AMMO_ONLY",
      } },
    -- ITEM_NOT_FOUND sits here, not under Items: Open All at a mailbox raises it alongside
    -- MAIL_DATABASE_ERROR (reported in game 2026-10-26). Its exact in-game wording is not yet
    -- matched to this type -- if "Item is not found" still shows with this group on, it is a
    -- different type.
    { id = "mail", label = "Mail, Vendors & Bank",
      types = {
        "MAIL_DATABASE_ERROR", "ITEM_NOT_FOUND", "MAIL_ATTACHMENT_EXPIRED", "MAIL_BAG",
        "MAIL_BOUND_ITEM", "MAIL_CANT_SEND_REALM", "MAIL_CONJURED_ITEM",
        "MAIL_DELETE_ITEM_ERROR", "MAIL_INVALID_ATTACHMENT", "MAIL_INVALID_ATTACHMENT_SLOT",
        "MAIL_LIMITED_DURATION_ITEM", "MAIL_QUEST_ITEM", "MAIL_REACHED_CAP",
        "MAIL_RECEPIENT_CANT_RECEIVE_MAIL", "MAIL_RECEPIENT_IS_SELF_FOUND_CANNOT_RECEIVE_MAIL",
        "MAIL_TARGET_CANNOT_RECEIVE_MAIL", "MAIL_TARGET_IS_TRIAL", "MAIL_TARGET_NOT_FOUND",
        "MAIL_TEMP_RETURN_OUTAGE", "MAIL_TOO_MANY_ATTACHMENTS", "MAIL_TO_SELF",
        "MAIL_WRAPPED_COD", "VENDOR_DOESNT_BUY", "VENDOR_HATES_YOU", "VENDOR_MISSING_TURNINS",
        "VENDOR_NOT_INTERESTED", "VENDOR_REFUSE_SCRAPPABLE_AZERITE", "VENDOR_SOLD_OUT",
        "VENDOR_TOO_FAR", "NOT_ENOUGH_MONEY", "CANT_BUY_QUANTITY",
        "CANT_BULK_SELL_ITEM_WITH_REFUND", "NO_BANK_HERE", "NO_ACCOUNT_BANK_HERE",
        "BANK_FULL", "BANK_NOT_ACCESSIBLE", "REAGENT_BANK_FULL", "AUCTION_DATABASE_ERROR",
      } },
    { id = "loot", label = "Looting & Objects",
      types = {
        "LOOT_BAD_FACING", "LOOT_CANT_LOOT_THAT", "LOOT_CANT_LOOT_THAT_NOW",
        "LOOT_DIDNT_KILL", "LOOT_GONE", "LOOT_LOCKED", "LOOT_NOTSTANDING", "LOOT_NO_UI",
        "LOOT_STUNNED", "LOOT_TOO_FAR", "LOOT_WHILE_INVULNERABLE", "NO_LOOT",
        "ALREADY_PICKPOCKETED", "USE_BAD_ANGLE", "USE_CANT_IMMUNE", "USE_CANT_OPEN",
        "USE_DESTROYED", "USE_LOCKED", "USE_LOCKED_WITH_ITEM_S",
        "USE_LOCKED_WITH_SPELL_KNOWN_SI", "USE_LOCKED_WITH_SPELL_S", "USE_OBJECT_MOVING",
        "USE_PREVENTED_BY_MECHANIC_S", "USE_SPELL_FOCUS", "USE_TOO_FAR",
        "TOO_FAR_TO_INTERACT", "OBJECT_IS_BUSY", "CHEST_IN_USE", "DOOR_LOCKED",
        "CANT_INTERACT_SHAPESHIFTED", "FISH_ESCAPED", "FISH_NOT_HOOKED",
      } },
    { id = "travel", label = "Mounts & Flight Paths",
      types = {
        "MOUNT_ALREADYMOUNTED", "MOUNT_INVALIDMOUNTEE", "MOUNT_LOOTING",
        "MOUNT_NOTMOUNTABLE", "MOUNT_NOTYOURPET", "MOUNT_NO_FAVORITES", "MOUNT_NO_MOUNTS",
        "MOUNT_OTHER", "MOUNT_RACECANTMOUNT", "MOUNT_SHAPESHIFTED", "MOUNT_TOOFARAWAY",
        "DISMOUNT_NOPET", "DISMOUNT_NOTMOUNTED", "DISMOUNT_NOTYOURPET", "TAXIINCOMBAT",
        "TAXINOPATHS", "TAXINOSUCHPATH", "TAXINOTELIGIBLE", "TAXINOTENOUGHMONEY",
        "TAXINOTSTANDING", "TAXINOTVISITED", "TAXINOVENDORNEARBY",
        "TAXIPLAYERALREADYMOUNTED", "TAXIPLAYERBUSY", "TAXIPLAYERMOVING",
        "TAXIPLAYERSHAPESHIFTED", "TAXISAMENODE", "TAXITOOFARAWAY",
        "TAXIUNSPECIFIEDSERVERERROR",
      } },
}

local function HideErrorTypes()
    local f = UIErrorsFrame
    if not (f and f.SetMessageTypeEnabled) then return end
    for _, g in ipairs(ERROR_TYPE_GROUPS) do
        if db.hideErrorTypes[g.id] then
            for _, name in ipairs(g.types) do
                local t = _G["LE_GAME_ERR_" .. name]
                if type(t) == "number" then f:SetMessageTypeEnabled(t, false) end
            end
        end
    end
end

-- ── Feature: Fade Action Bars ──────────────────────────────
-- Hover-reveal for designated action bars: faded to alpha 0 when
-- idle, reappear on mouseover.  Uses VUI.HookHoverFade which
-- handles target + child OnEnter/OnLeave automatically.
local ACTION_BAR_FRAMES = {
    [2] = "MultiBarBottomLeft",
    [3] = "MultiBarBottomRight",
    [4] = "MultiBarRight",
    [5] = "MultiBarLeft",
    [6] = "MultiBar5",
    [7] = "MultiBar6",
    [8] = "MultiBar7",
}

local ACTION_BAR_LABELS = {
    [2] = "Action Bar 2", [3] = "Action Bar 3", [4] = "Action Bar 4",
    [5] = "Action Bar 5", [6] = "Action Bar 6", [7] = "Action Bar 7",
    [8] = "Action Bar 8",
}

local function IsEditModeActive()
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive,
                                 EditModeManagerFrame)
        return ok and active
    end
    return false
end

local function SetupActionBarFading()
    local fadeOuts = {}
    local refreshers = {}
    for i = 2, 8 do
        if cdb.fadeActionBars[i] then
            local barFrame = _G[ACTION_BAR_FRAMES[i]]
            if barFrame then
                local fo, rc = VUI.HookHoverFade(barFrame, IsEditModeActive)
                if fo then fadeOuts[#fadeOuts + 1] = fo end
                if rc then refreshers[#refreshers + 1] = rc end
            end
        end
    end
    -- Re-fade bars after Edit Mode exits — Blizzard forces them visible
    -- during layout editing, and no OnLeave fires to trigger FadeOut.
    -- Also refresh child caches in case Edit Mode changed button layout.
    if #fadeOuts > 0 and EditModeManagerFrame then
        pcall(hooksecurefunc, EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.2, function()
                for _, rc in ipairs(refreshers) do rc() end
                for _, fo in ipairs(fadeOuts) do fo() end
            end)
        end)
    end
end

-- ── Options Panel ───────────────────────────────────────────
-- The two multi-select dropdowns (Hide Error Text, Fade Action Bars) use Blizzard's own
-- tick-box rows, the control its Nameplates "Cast Bar Information" option uses:
-- container:AddCheckbox, with the setting's value a bitmask in which option value v is bit
-- v-1 (Blizzard_Settings.lua:254-258 and 519-533). Blizzard owns ticking, the bar text (the
-- ticked rows joined by commas, MenuTemplates.lua:775-794) and the absence of the arrow
-- buttons (shown only when a menu has radio rows, Blizzard_SettingControls.lua:780-785).
--
-- ⛔ NO getSelectionTextFunc. Nameplates sets one to show "None", but the Settings list
-- recycles control frames across every category and only ever SETS that function on the
-- recycled dropdown, never clears it (Blizzard_SettingControls.lua:787-790; MenuTemplates.lua
-- :747-748). Ours then ran inside Blizzard's Game > Social page, which next calls the
-- restricted C_Discord.IsUserOAuthed() (Social.lua:341): ADDON_ACTION_FORBIDDEN under Clean
-- Solo's name, 5 times in the owner's /vui taint (v1.21.0 test build). "None" is therefore
-- a real row instead: ticked exactly when nothing else is, so Blizzard's own text shows it.
--
-- Bits are plain arithmetic, not bit.*: the values are small powers of two.
local function Bit(v) return 2 ^ (v - 1) end
local function HasBit(mask, v) return math.floor((mask or 0) / Bit(v)) % 2 == 1 end
local function ChangedBits(old, new, maxV)
    local changed = {}
    for v = 1, maxV do
        if HasBit(old, v) ~= HasBit(new, v) then changed[#changed + 1] = v end
    end
    return changed
end

-- Hide Error Text rows: None, All, then the groups in ERROR_TYPE_GROUPS order.
local ERR_NONE, ERR_ALL, ERR_FIRST_GROUP = 1, 2, 3
local ERR_MAX = ERR_FIRST_GROUP + #ERROR_TYPE_GROUPS - 1

local function ErrorTypesMask()
    local mask = 0
    if db.hideErrorText then mask = Bit(ERR_ALL) end
    for i, g in ipairs(ERROR_TYPE_GROUPS) do
        if db.hideErrorText or db.hideErrorTypes[g.id] then mask = mask + Bit(ERR_FIRST_GROUP + i - 1) end
    end
    return mask > 0 and mask or Bit(ERR_NONE)
end

-- Fade Action Bars rows: None is value 1 (bar 1 is Blizzard-protected and never listed), and
-- bar N is value N, so the bar number IS the option value.
local BAR_NONE, BAR_MAX = 1, 8

local function ActionBarsMask()
    local mask = 0
    for i = 2, BAR_MAX do
        if cdb.fadeActionBars[i] then mask = mask + Bit(i) end
    end
    return mask > 0 and mask or Bit(BAR_NONE)
end

-- An option another addon has taken over (VUI.SetOptionUnavailable, today only VeritasUI_ElvUI,
-- which draws its own chat, bars and unit frames). Its feature is skipped at login and its control
-- is greyed out with the reason added to the tooltip; the saved value is left alone.
local function Unavailable(key)
    return VUI.OptionUnavailable and VUI.OptionUnavailable(ADDON_NAME, key) or nil
end

local function TipWithReason(tip, key)
    local reason = Unavailable(key)
    if type(reason) ~= "string" then return tip end
    return tip .. "\n\n|cFFFF4444" .. reason .. "|r"
end

local function GreyIfUnavailable(initializer, key)
    if Unavailable(key) and initializer and initializer.AddModifyPredicate then
        initializer:AddModifyPredicate(function() return false end)
    end
end

local function InitializeOptions()
    local category, layout = VUI.RegisterSettingsCategory(SETTINGS_LABEL)

    -- Two groups under section headers, the way Blizzard's own Options pages are laid out
    -- (layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(...)),
    -- Blizzard_SettingsDefinitions_Frame/Interface.lua:18). Owner's request, 2026-10-29: fades
    -- and hides were interleaved. Order is presentation only; every key is unchanged.
    local function Header(name)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
        end
    end

    local FADE_OPTIONS = {
        { key = "fadeChatTabs",        name = "Fade Chat Tabs",
          tip = "Chat tabs stay hidden until the chat window appears, then fade in and out with it. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "transparentChatBG",   name = "Transparent Chat Background",
          tip = "Makes the chat background transparent until you mouse over it. Turn it off and "
             .. "reload, and your own background comes back. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "fadeMicroMenu",       name = "Fade Micro Menu",
          tip = "The bottom-right menu bar fades out unless moused over. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "fadePlayerFrame",     name = "Fade Player Frame",
          tip = "Your player frame fades out when idle and reappears in combat, when damaged, or on mouseover. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
    }
    local HIDE_OPTIONS = {
        { key = "hideSocialButton",    name = "Hide Social Button",
          tip = "Hides the Quick Join / Communities toast button. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideChatButtons",     name = "Hide Chat Buttons",
          tip = "Hides the chat menu button (the speech bubble beside the chat window). "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideVoiceChatButton", name = "Hide Voice Chat Button",
          tip = "Hides the voice and channels button beside the chat window, and the mute and "
             .. "deafen buttons shown while you are in a voice channel. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideBagButtons",      name = "Hide Bag Buttons",
          tip = "Hides the bag bar buttons. You can still open bags with B. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideMacroNames",      name = "Hide Macro Names",
          tip = "Hides the macro name text displayed on action bar buttons. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideTalkingHead",     name = "Hide Talking Head",
          tip = "Hides the NPC portrait that pops up with story dialogue in quests and dungeons. "
             .. "The voice still plays unless Mute Talking Head Voice is on. Still shown in Edit "
             .. "Mode so you can place it. Requires |cFFFFFF00/reload|r to apply." },
        { key = "muteTalkingHead",     name = "Mute Talking Head Voice",
          tip = "Silences the voice line that plays with the talking head popup. The popup itself "
             .. "still shows unless Hide Talking Head is on. Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideTopBanners",      name = "Hide Top Banners",
          tip = "Stops the big messages at the top of the screen: the zone name when you travel, "
             .. "event banners (level up, new scenario stage, weekly rewards and similar) and the "
             .. "boss kill and loot banner. "
             .. "Requires |cFFFFFF00/reload|r to apply." },
        { key = "hideProfessionGear",  name = "Hide Profession Gear",
          tip = "Keeps your own outfit on while you craft, gather or fish, instead of the "
             .. "profession outfit the game puts on you. Not during combat. Applies at once.",
          apply = function(value) SetHideProfessionGear(value) end },
    }

    -- ⚠ THESE CHECKBOXES ARE MIXED-SCOPE. All the keys but one are account-wide and one
    -- (fadePlayerFrame) is per-character, so the table handed to Settings AND the table the
    -- default is read from must both be resolved PER KEY. Passing one table for all of them -- which
    -- is what this did before v1.14.4 -- would store fadePlayerFrame at account scope, and the
    -- panel would then read and write a value the runtime code never looks at. Blizzard captures
    -- the table by reference (Blizzard_Setting.lua:420), so getting this wrong stays invisible
    -- until a setting fails to persist or leaks across characters.
    local function AddCheckboxes(list)
        for _, opt in ipairs(list) do
            local perChar  = PERCHAR[opt.key] ~= nil
            local owner    = perChar and cdb or db
            local defTable = perChar and PERCHAR or UNIVERSAL
            local setting = Settings.RegisterAddOnSetting(
                category,
                ADDON_NAME .. "_" .. opt.key,
                opt.key,
                owner,
                type(defTable[opt.key]),
                opt.name,
                defTable[opt.key]
            )
            setting:SetValueChangedCallback(function(_, value)
                VUI.PrintOnOff("Clean Solo", opt.name, value)
                -- An option with `apply` takes effect at once instead of after a /reload.
                if opt.apply and not Unavailable(opt.key) then opt.apply(value) end
            end)
            local init = Settings.CreateCheckbox(category, setting, TipWithReason(opt.tip, opt.key))
            GreyIfUnavailable(init, opt.key)
        end
    end

    Header("Fade")
    AddCheckboxes(FADE_OPTIONS)

    -- ── Fade Action Bars — tick-box dropdown, PER-CHARACTER (mask paired with fadeActionBars).
    cdb.fadeActionBars[1] = nil  -- Bar 1 is Blizzard-protected
    cdb.fadeActionBarsLabel = nil  -- RETIRED v1.21.0: the old display string, now the mask
    cdb.fadeActionBarsMask = ActionBarsMask()
    local lastBarMask = cdb.fadeActionBarsMask

    local fadeSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_fadeActionBars",
        "fadeActionBarsMask",
        cdb,                         -- PER-CHARACTER: paired with fadeActionBars
        "number",
        "Fade Action Bars",
        Bit(BAR_NONE)
    )

    local ignoreFadeCallback = false

    local function GetBarOptions()
        local container = Settings.CreateControlTextContainer()
        container:AddCheckbox(BAR_NONE, "None")
        for i = 2, BAR_MAX do container:AddCheckbox(i, ACTION_BAR_LABELS[i]) end
        return container:GetData()
    end

    fadeSetting:SetValueChangedCallback(function(_, val)
        if ignoreFadeCallback or type(val) ~= "number" then return end
        local changed = ChangedBits(lastBarMask, val, BAR_MAX)
        if #changed == 1 then
            local v, on = changed[1], HasBit(val, changed[1])
            if v == BAR_NONE then
                if on then for i = 2, BAR_MAX do cdb.fadeActionBars[i] = nil end end
            else
                cdb.fadeActionBars[v] = on or nil
                VUI.Print("Clean Solo", ACTION_BAR_LABELS[v] .. " fade "
                    .. (on and "enabled" or "disabled") .. " — |cFFFFFF00/reload|r to apply.")
            end
        elseif #changed > 1 then
            for i = 2, BAR_MAX do cdb.fadeActionBars[i] = HasBit(val, i) or nil end
        end
        cdb.fadeActionBarsMask = ActionBarsMask()
        lastBarMask = cdb.fadeActionBarsMask
        ignoreFadeCallback = true
        pcall(fadeSetting.SetValue, fadeSetting, cdb.fadeActionBarsMask)
        ignoreFadeCallback = false
    end)

    local fadeInit = Settings.CreateDropdown(category, fadeSetting, GetBarOptions, TipWithReason(
        "Pick a bar to fade it out when idle; it reappears on mouseover. "
        .. "Requires |cFFFFFF00/reload|r to apply.", "fadeActionBars"))
    GreyIfUnavailable(fadeInit, "fadeActionBars")

    -- ── Fade Delay — slider, UNIVERSAL. The one Clean Solo setting that applies at once: it is a
    -- number the faders read each time they are about to fade (VUI.SetFadeDelay), not a hook, so
    -- the /reload policy at the top of this file does not apply to it. 0.5 s steps, the step
    -- Blizzard's own seconds-valued sliders use (Blizzard_SettingsDefinitions_Frame/Mounts.lua:114).
    local delaySetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_fadeDelay",
        "fadeDelay",
        db,                          -- UNIVERSAL
        "number",
        "Fade Delay",
        UNIVERSAL.fadeDelay
    )
    delaySetting:SetValueChangedCallback(function(_, value)
        VUI.SetFadeDelay(value)
    end)
    local delayOptions = Settings.CreateSliderOptions(0, 5, 0.5)
    local labelRight = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if labelRight and delayOptions.SetLabelFormatter then
        delayOptions:SetLabelFormatter(labelRight, function(value)
            return string.format("%.1f sec", value)
        end)
    end
    local delayInit = Settings.CreateSlider(category, delaySetting, delayOptions, TipWithReason(
        "How long the faded micro menu, player frame and action bars stay visible after you move "
        .. "the mouse away, before they fade. 0 keeps the usual short delay. The chat window and "
        .. "its tabs keep Blizzard's own timing. Applies at once.", "fadeDelay"))
    GreyIfUnavailable(delayInit, "fadeDelay")


    Header("Hide")
    AddCheckboxes(HIDE_OPTIONS)

    -- ── Hide Error Text — tick-box dropdown (see the Options Panel note above). UNIVERSAL:
    -- hideErrorText, hideErrorTypes and the mask all live on `db`.
    --
    -- "All" is stored in hideErrorText, the key the old Hide Error Text checkbox used, so a
    -- saved "on" from before this dropdown carries straight over as All. All is an override,
    -- not a seventh group: it hides EVERY red error (not just the six groups) the way the
    -- checkbox did. While it is on every group row is ticked too, and the individual picks
    -- underneath it are kept, so unticking All restores them. Unticking a group while All is
    -- on means "all but this one".
    --
    -- The mask is DERIVED from those two keys on every login and every change; they are the
    -- truth, the mask only feeds the control.
    db.hideErrorTypesLabel = nil   -- left by the unreleased v1.21.0 test builds
    db.hideErrorTypesMask = ErrorTypesMask()
    local lastErrMask = db.hideErrorTypesMask

    local errSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_hideErrorTypes",
        "hideErrorTypesMask",
        db,                          -- UNIVERSAL: paired with hideErrorTypes
        "number",
        "Hide Error Text",
        Bit(ERR_ALL) + (2 ^ ERR_MAX - 2 ^ (ERR_FIRST_GROUP - 1))   -- default: All, as before
    )

    local ignoreErrCallback = false

    local function GetErrorTypeOptions()
        local container = Settings.CreateControlTextContainer()
        container:AddCheckbox(ERR_NONE, "None")
        container:AddCheckbox(ERR_ALL, "All")
        for i, g in ipairs(ERROR_TYPE_GROUPS) do
            local row = container:AddCheckbox(ERR_FIRST_GROUP + i - 1, g.label)
            -- While All is on the group rows are ticked but must not be listed in the bar,
            -- which should read just "All". A row's `text` feeds only the bar text; the menu
            -- draws the row from `label` (CreateTextContainerData, Blizzard_Settings.lua:244-
            -- 246; the row initializer captures its label, MenuTemplates.lua:330-333). A nil
            -- text adds nothing to the bar's list (MenuTemplates.lua:775-791).
            if db.hideErrorText then row.text = nil end
        end
        return container:GetData()
    end

    local function ErrorSummary()
        if db.hideErrorText then return "All" end
        local names = {}
        for _, g in ipairs(ERROR_TYPE_GROUPS) do
            if db.hideErrorTypes[g.id] then names[#names + 1] = g.label end
        end
        return #names > 0 and table.concat(names, ", ") or "None"
    end

    errSetting:SetValueChangedCallback(function(_, val)
        if ignoreErrCallback or type(val) ~= "number" then return end
        local changed = ChangedBits(lastErrMask, val, ERR_MAX)
        if #changed == 1 then
            local v, on = changed[1], HasBit(val, changed[1])
            if v == ERR_NONE then
                if on then
                    db.hideErrorText = false
                    for k in pairs(db.hideErrorTypes) do db.hideErrorTypes[k] = nil end
                end                                   -- unticking None alone changes nothing
            elseif v == ERR_ALL then
                db.hideErrorText = on
            else
                local g = ERROR_TYPE_GROUPS[v - ERR_FIRST_GROUP + 1]
                if on then
                    db.hideErrorTypes[g.id] = true
                elseif db.hideErrorText then
                    db.hideErrorText = false
                    for _, other in ipairs(ERROR_TYPE_GROUPS) do
                        db.hideErrorTypes[other.id] = (other.id ~= g.id) or nil
                    end
                else
                    db.hideErrorTypes[g.id] = nil
                end
            end
        elseif #changed > 1 then                      -- e.g. the Defaults button
            db.hideErrorText = HasBit(val, ERR_ALL)
            if not db.hideErrorText then
                for i, g in ipairs(ERROR_TYPE_GROUPS) do
                    db.hideErrorTypes[g.id] = HasBit(val, ERR_FIRST_GROUP + i - 1) or nil
                end
            end
        end
        if #changed > 0 then
            VUI.Print("Clean Solo", "Hide Error Text: " .. ErrorSummary()
                .. " — |cFFFFFF00/reload|r to apply.")
        end
        db.hideErrorTypesMask = ErrorTypesMask()
        lastErrMask = db.hideErrorTypesMask
        ignoreErrCallback = true
        pcall(errSetting.SetValue, errSetting, db.hideErrorTypesMask)
        ignoreErrCallback = false
    end)

    Settings.CreateDropdown(category, errSetting, GetErrorTypeOptions,
        "Pick the kinds of red error message to hide, and the spoken lines that go with them; "
        .. "the rest still show. All hides every error message. Combat holds messages like "
        .. "'You are too far away!' and 'You are facing the wrong way!'; Mail, Vendors & Bank "
        .. "holds 'Internal mail database error.' Requires |cFFFFFF00/reload|r to apply.")

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
        -- Account table only: no identity yet, so cdb comes back nil. VUI.BindScopedDB replaces
        -- the hand-rolled seeding loop AND the local DeepCopy that used to live here -- that loop
        -- wrote EVERY default into the account root, which is the mechanism behind the pinning
        -- defect this refactor removes, so it had to go rather than sit alongside the binder. The
        -- binder deep-copies, which its own comment said the shallow version would eventually
        -- need for a nested default.
        db = VUI.BindScopedDB("VeritasUI_CleanSoloDB", UNIVERSAL, PERCHAR)
        -- InitializeOptions deliberately does NOT run here any more:
        -- Settings.RegisterAddOnSetting captures the TABLE it is given, so it must
        -- receive the per-character slot, which does not exist until PLAYER_LOGIN.
        -- Registering here would point every checkbox at the account-wide root and
        -- per-character settings would silently not work.
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Identity is available: bind BOTH tables, then register the options panel.
        -- ⚠ The old note here said "every read below and every Settings control must see the same
        -- table". That was true only while the whole module was per-character. The invariant now
        -- holds PER KEY: each read and each Settings registration must see the table that OWNS
        -- that key -- `db` for account-wide, `cdb` for the three per-character ones.
        db, cdb = VUI.BindScopedDB("VeritasUI_CleanSoloDB", UNIVERSAL, PERCHAR)

        -- ⚠ MUST run here: after the per-character table exists, and BEFORE anything reads a
        -- universal key below. Read first and every feature acts on the pre-migration value for
        -- the whole session.
        local promoted = VUI.MigrateScopedDB("VeritasUI_CleanSoloDB", UNIVERSAL, PERCHAR,
                                             "__vuiScopeMigrated")
        if promoted then
            local names = {}
            for k in pairs(promoted) do names[#names + 1] = k end
            table.sort(names)
            VUI.Print("Clean Solo", "settings now shared across characters: "
                .. table.concat(names, ", ") .. "  (taken from this character)")
        end

        InitializeOptions()
        -- Before any fader runs, so the first fade of the session already uses it.
        if VUI.SetFadeDelay then VUI.SetFadeDelay(db.fadeDelay) end
        if db.hideSocialButton and not Unavailable("hideSocialButton") then HideSocialButton() end
        if db.fadeChatTabs      and not Unavailable("fadeChatTabs")      then SetupChatTabFading()  end
        if db.transparentChatBG and not Unavailable("transparentChatBG") then SetupTransparentChatBG() end
        if db.hideChatButtons and not Unavailable("hideChatButtons") then HideChatButtons() end
        if db.hideVoiceChatButton and not Unavailable("hideVoiceChatButton") then HideVoiceChatButton() end
        if db.fadeMicroMenu    and not Unavailable("fadeMicroMenu")    then SetupMicroMenuFade()  end
        if cdb.fadePlayerFrame and not Unavailable("fadePlayerFrame")  then SetupPlayerFrameFade() end
        if db.hideBagButtons and not Unavailable("hideBagButtons") then HideBagButtons() end
        if db.hideMacroNames and not Unavailable("hideMacroNames") then HideMacroNames() end
        if (db.hideTalkingHead and not Unavailable("hideTalkingHead"))
            or (db.muteTalkingHead and not Unavailable("muteTalkingHead")) then SetupTalkingHead() end
        if db.hideTopBanners and not Unavailable("hideTopBanners") then HideTopBanners() end
        if db.hideProfessionGear and not Unavailable("hideProfessionGear") then SetHideProfessionGear(true) end
        if db.hideErrorText       then HideErrorText()
        else                           HideErrorTypes()      end
        if not Unavailable("fadeActionBars") then SetupActionBarFading() end

        self:UnregisterEvent("PLAYER_LOGIN")
        -- Login line removed (suite-wide audit S2): Lib prints the one "VeritasUI vX loaded" line.

    elseif event == "PLAYER_REGEN_DISABLED" then
        if self._playerEvaluate then
            self._playerEvaluate()
            -- Deferred retry: InCombatLockdown() may not return true
            -- on the same frame PLAYER_REGEN_DISABLED fires (known
            -- WoW timing quirk). A zero-delay timer re-evaluates on
            -- the next frame, catching the race that causes the player
            -- frame to stay hidden when joining someone else's combat.
            C_Timer.After(0, self._playerEvaluate)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if self._playerEvaluate then self._playerEvaluate() end

    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if self._playerHealthPing then self._playerHealthPing() end
    end
end)

-- ── Slash commands ──────────────────────────────────────────
SLASH_VERITASUI_CLEANSOLO1 = "/cleansolo"
SLASH_VERITASUI_CLEANSOLO2 = "/cs"
SlashCmdList["VERITASUI_CLEANSOLO"] = function(msg)
    if strtrim(msg or ""):lower() == "gear" then PrintGearDiag(); return end
    -- Guard against nil (options init not yet run, or failed) — same
    -- "still loading" pattern as PriorityRotation / ZoneQuests / AH.
    if settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    else
        VUI.Print("Clean Solo",
            "Settings are still loading — try again in a moment.")
    end
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_CleanSolo_OnAddonCompartmentClick()
    C_Timer.After(0, function()
        if settingsCategoryID then Settings.OpenToCategory(settingsCategoryID) end
    end)
end
