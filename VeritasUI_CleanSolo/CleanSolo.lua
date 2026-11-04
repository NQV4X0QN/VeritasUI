-- VeritasUI_CleanSolo / CleanSolo.lua
-- Fades or hides noisy default UI elements for solo play.
-- Settings: Options → AddOns → VeritasUI → Clean Solo  |  /cleansolo  |  /cs
--
-- ────────────────────────────────────────────────────────────────
--  POLICY: /reload required to apply setting changes (by design)
-- ────────────────────────────────────────────────────────────────
--
--  CleanSolo's features are implemented almost entirely via
--  hooksecurefunc — the chat window fade, the
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
--  Exceptions apply at once and say so: Fade Delay (read live
--  by VUI.SetFadeDelay), the faded-opacity sliders (read at each
--  fade, v1.40.0), Hide Profession Gear (plain events, switched by
--  its `apply`) and the v1.39.0 fades with an `apply`.  Every other CS tooltip and on-toggle
--  message mentions "/reload to apply" so the user is never
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
    print(RED_FONT_COLOR:WrapTextInColorCode("[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled."))
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
    -- Fade Chat Window (label since v1.41.0; the key keeps its old name so saved choices carry over)
    fadeChatTabs        = true,
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
    -- v1.48.0: Hide Top Banners is a dropdown. [groupId] = true for each kind hidden (TOP_BANNER_GROUPS).
    -- TABLE-typed. PAIRED: hideTopBannersMask (the dropdown's tick-box value) is derived from it, like
    -- hideErrorTypesMask. Replaces the hideTopBanners checkbox; a saved "on" becomes every row ticked.
    hideTopBannerTypes  = {},
    -- v1.49.0: Hide Transforms dropdown, [kindId] = true (TRANSFORM_KINDS). TABLE-typed. PAIRED with
    -- hideTransformsMask (derived), like hideTopBannersMask. Replaces hideProfessionGear (v1.27.0, ON
    -- since v1.37.0): Profession Gear stays ticked for new installs; the rest start off.
    hideTransformTypes  = { professions = true },
    -- v1.60.0: Fade Minimap Buttons dropdown, [buttonId] = true (MINIMAP_BUTTONS). TABLE-typed, PAIRED
    -- with fadeMinimapButtonsMask (derived). Default none. Replaces hideMinimapButtons (v1.50.0), whose
    -- choices it takes on upgrade at 0% opacity.
    fadeMinimapButtons  = {},
    -- v1.39.0 (owner's request): two more hover fades, applied at once. Universal: the damage meter
    -- and the reputation / experience / honor bars sit in the same place on every character.
    fadeDamageMeter     = true,    -- shown in combat or on hover
    fadeStatusBars      = true,    -- shown on hover
    -- v1.42.0 (owner's request): the All Objectives tracker, shown on hover. Universal, like the
    -- other interface fades.
    fadeObjectiveTracker = true,
    -- v1.43.0 (owner's request): your buffs and debuffs by the minimap, shown in combat or on hover.
    fadeAuras           = true,
    -- v1.44.0 (owner's request): the alert icons by the minimap (mail, crafting orders, and Quality
    -- of Life's Great Vault button), shown on hover.
    fadeMinimapAlerts   = true,
    -- v1.45.0 (owner's request): sub-option of Fade Main Action Bar, ON so the behaviour before it is
    -- kept: the bar is shown in flight. Off, flying is like any other time out of combat.
    fadeMainActionBarShowFlying = true,
    -- Sub-option, OFF by default (owner: some players want the bars only on hover, others want
    -- them shown on gains -- "an option that people can check if they want it").
    fadeStatusBarsOnGain = false,  -- also shown for 3 s after a reputation, experience or honor gain
    -- v1.40.0 (owner's request): how much of each faded element still shows, 0-1, from the slider
    -- beside its Fade option (Blizzard's checkbox + slider row, as in Options > Audio > Ping
    -- Sounds). 0 = hidden, the behaviour before the sliders. Universal: how a fade looks is an
    -- interface choice. One value covers every action bar: Action Bar 1 and the bars picked in
    -- Fade Action Bars (owner: the slider beside Fade Main Action Bar handles them all).
    fadeChatTabsOpacity    = 0,
    fadeMicroMenuOpacity   = 0,
    fadePlayerFrameOpacity = 0,
    fadeDamageMeterOpacity = 0,
    -- v1.51.0 (feature batch item 5): one faded opacity per tracker section (OT_SECTIONS), replacing
    -- fadeObjectiveTrackerOpacity (whose value the non-event sections take on upgrade). The three event
    -- sections default to 100%, which is how they behaved before. A section at 0% is also collapsed.
    -- One key per line: scope_map_test reads the defaults table line by line.
    otOpacity_scenario = 1,
    otOpacity_event = 1,
    otOpacity_bonus = 1,
    otOpacity_campaign = 0,
    otOpacity_quests = 0,
    otOpacity_collections = 0,
    otOpacity_achievements = 0,
    otOpacity_travelerslog = 0,
    otOpacity_endeavors = 0,
    otOpacity_professions = 0,
    otOpacity_worldquests = 0,
    -- "normal" | "raid" (every section hidden in a raid) | "boss" (hidden during a raid boss fight).
    fadeObjectiveTrackerRaid = "normal",
    fadeAurasOpacity = 0,
    fadeMinimapAlertsOpacity = 0,
    fadeMinimapButtonsOpacity = 0,
    fadeStatusBarsOpacity  = 0,
    fadeActionBarsOpacity  = 0,
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
    -- v1.39.0: Action Bar 1, shown in combat, while flying or on hover. Per-character with the other
    -- action bar fades, for the same reason (bars are used differently on each character).
    fadeMainActionBar = true,
}


local db
-- ⚠ Declared here, above every reader. `cdb` is the PER-CHARACTER table and is nil until
-- PLAYER_LOGIN: VUI.BindScopedDB deliberately does not fall back to the account root.
local cdb = nil
local settingsCategoryID
local frame = CreateFrame("Frame")

-- Getter for a faded-opacity slider's value, read live (VUI.FadedAlpha clamps it to 0-1).
local function Opacity(key)
    return function() return db and db[key] or 0 end
end
-- Set by SetupChatTabFading: puts already-faded tabs and type bars at a new opacity.
local chatTabsApplyOpacity

-- Transparent Chat Background (v1.6.4-v1.40.0) is RETIRED: Fade Chat Window now fades the window
-- itself to the slider's opacity, so 0% is what that option did. It forced the window's alpha to 0
-- through FCF_SetWindowAlpha and had to fight Blizzard's colour picker for it (landmine 70); the
-- window fade below leaves Blizzard's alpha alone. Its saved key is deleted at login.

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
--   HIDDEN     — hard clamp: held at the faded opacity
-- The faded opacity is the slider beside Fade Chat Window (v1.40.0), 0 by default.
local function SetupChatTabFading()
    local FADE_IN    = CHAT_FRAME_FADE_TIME     or 0.15
    local FADE_OUT   = CHAT_FRAME_FADE_OUT_TIME or 2.0
    local tabOpacity = Opacity("fadeChatTabsOpacity")
    local function TabAlpha() return VUI.FadedAlpha(tabOpacity) end

    local tabs = {}   -- chat window -> its tab

    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf  = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        -- Skip missing slots rather than aborting; frames may be non-contiguous.
        if cf and tab then
            tabs[cf] = tab

            tab:SetAlpha(TabAlpha())

            -- State: "VISIBLE", "FADING_OUT", or "HIDDEN"
            tab._vui_fadeState = "HIDDEN"
            tab._vui_prevAlpha = TabAlpha()
            tab._vui_inHook    = false

            hooksecurefunc(tab, "SetAlpha", function(self, a)
                if self._vui_inHook then return end
                self._vui_inHook = true

                local state = self._vui_fadeState
                local floor = TabAlpha()
                if state == "HIDDEN" and math.abs(a - floor) > 0.001 then
                    self:SetAlpha(floor)
                elseif state == "FADING_OUT" then
                    local prev = self._vui_prevAlpha or 0
                    if a > prev + 0.001 then
                        self:SetAlpha(prev)
                    elseif a < floor - 0.001 then
                        self:SetAlpha(floor)
                        self._vui_prevAlpha = floor
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
        VUI.SmoothFade(tab, FADE_OUT, TabAlpha())
        fadeDoneTimers[tab] = C_Timer.NewTimer(FADE_OUT + 0.05, function()
            fadeDoneTimers[tab] = nil
            if tab._vui_fadeState == "FADING_OUT" then
                tab._vui_fadeState = "HIDDEN"
                tab._vui_prevAlpha = TabAlpha()
            end
        end)
    end

    -- ── The IM-style type bar follows the window too (owner, 2026-10-31) ──
    -- With Chat Style "IM" Blizzard keeps the window's edit box shown while you are not typing,
    -- at a fixed 0.35 alpha (ChatFrameEditBoxMixin:Deactivate, ChatFrameEditBox.lua:543-553;
    -- shown by ChatFrameUtil.SetLastActiveWindow, ChatFrameUtil.lua:583-585), and never fades it,
    -- so it sat on screen with the window and tabs gone. Classic hides it instead, so nothing here
    -- changes Classic. The bar now goes to Blizzard's 0.35 when the window fades in and to 0 when
    -- it fades out, at the same speeds as the tab.
    -- ⚠ While you type, the bar is Blizzard's: ActivateChat sets it to 1 (ChatFrameUtil.lua:540) and
    --   every step of our fade checks ACTIVE_CHAT_EDIT_BOX first and drops out, so a fade already
    --   running can never dim the box you are typing in. Own driver, not VUI.SmoothFade, for
    --   exactly that check.
    local BAR_ALPHA = 0.35   -- Blizzard's inactive IM edit box alpha (ChatFrameEditBox.lua:551)
    -- Faded, the bar keeps the tabs' share of its own alpha: the slider at 50% leaves it at 0.175.
    local function BarFaded() return BAR_ALPHA * TabAlpha() end
    local barFades, barHooked = {}, {}
    local barDriver = CreateFrame("Frame")
    barDriver:Hide()
    barDriver:SetScript("OnUpdate", function(self, elapsed)
        for eb, f in pairs(barFades) do
            if _G.ACTIVE_CHAT_EDIT_BOX == eb then
                barFades[eb] = nil
            else
                f.t = f.t + (elapsed or 0)
                if f.t >= f.d then
                    eb:SetAlpha(f.to); barFades[eb] = nil
                else
                    eb:SetAlpha(f.from + (f.to - f.from) * f.t / f.d)
                end
            end
        end
        if not next(barFades) then self:Hide() end
    end)

    local FadeBar
    local function BarOf(cf)
        local eb = cf and rawget(cf, "editBox")
        if type(eb) ~= "table" or not eb.SetAlpha then return nil end
        -- After you send (or Escape), Blizzard puts the bar back at 0.35 at once; if the window
        -- has already faded out, take it away at the window's fade-out speed.
        if not barHooked[eb] and eb.Deactivate then
            barHooked[eb] = true
            hooksecurefunc(eb, "Deactivate", function()
                if not cf.hasBeenFaded then FadeBar(cf, BarFaded(), FADE_OUT) end
            end)
        end
        return eb
    end

    function FadeBar(cf, to, dur)
        local eb = BarOf(cf)
        if not eb or _G.ACTIVE_CHAT_EDIT_BOX == eb then return end
        barFades[eb] = { from = eb:GetAlpha(), to = to, d = dur, t = 0 }
        barDriver:Show()
    end

    -- Install the Deactivate hooks now, and take away the bar Blizzard has already shown at
    -- login, the way the tabs start hidden.
    for cf in pairs(tabs) do
        if not cf.hasBeenFaded then FadeBar(cf, BarFaded(), 0) else BarOf(cf) end
    end

    -- ── The window itself and the chat buttons (v1.41.0, owner's request) ──
    -- The window's background and border are the textures Blizzard lists in CHAT_FRAME_TEXTURES
    -- (FloatingChatFrame.lua:43-64). Blizzard fades their alpha itself: in to max(oldAlpha,
    -- DEFAULT_CHATFRAME_ALPHA), out to oldAlpha, your own Background opacity (FCF_FadeIn/OutChatFrame,
    -- :1052-1117, through UIFrameFade, which sets the alpha every frame).
    -- ⚠ We OWN that alpha, the way the tabs are owned: each texture's SetAlpha is hooked and put back
    -- to our value in the same call, so Blizzard's fade can never show for a frame. Test build 1 faded
    -- the VERTEX alpha instead, expecting it to multiply with Blizzard's: the window stayed after
    -- the mouse left and flickered on hover (owner, 2026-10-31), i.e. Blizzard's writes won.
    -- Our value goes between Blizzard's two ends: shown = max(oldAlpha, default), as Blizzard; faded =
    -- slider x oldAlpha, so 100% is Blizzard's own look and 0% is transparent. Both are read when
    -- applied, so a change to your Background opacity (FCF_SetWindowAlpha stores oldAlpha, :868-878)
    -- or to the slider applies at once. Blizzard's colour setter (:849-866) is hooked to put ours back.
    -- The messages are the frame's own text and are never touched (owner: they stay readable).
    -- The scroll bar keeps Blizzard's fade to 0 (FCF_FadeOutScrollbar, :1037-1050).
    --
    -- The chat buttons Clean Solo can hide (social, chat menu, voice) fade with ChatFrame1 when
    -- they are not hidden: none of them has its alpha set by Blizzard (source, 2026-10-31), and
    -- the menu and channel buttons sit in ChatFrame1's button frame, which Blizzard leaves at 1 while
    -- docked (FCF_DockFrame, :1971). Hovering them, or the social button, already brings the window
    -- in: Blizzard counts both in its hover test (FCF_OnUpdate, :1138-1143).
    -- Own driver, not VUI.SmoothFade: the window is many textures moved by one value.
    local DEFAULT_BG = _G.DEFAULT_CHATFRAME_ALPHA or 0.25
    local winTex, winShown, winAlpha, winInHook = {}, {}, {}, {}
    local function OldAlpha(cf)
        local a = tonumber(rawget(cf, "oldAlpha"))
        return a or DEFAULT_BG
    end
    -- p: 0 = faded, 1 = shown.
    local function ApplyWindow(cf)
        local p = winShown[cf] or 0
        local old = OldAlpha(cf)
        local faded, shown = TabAlpha() * old, math.max(old, DEFAULT_BG)
        local a = faded + (shown - faded) * p
        winAlpha[cf] = a
        winInHook[cf] = true
        for _, t in ipairs(winTex[cf] or {}) do t:SetAlpha(a) end
        winInHook[cf] = false
    end
    for cf in pairs(tabs) do
        local list, name = {}, cf.GetName and cf:GetName()
        for _, suffix in ipairs(_G.CHAT_FRAME_TEXTURES or {}) do
            local t = name and _G[name .. suffix]
            if type(t) == "table" and t.GetObjectType and t:GetObjectType() == "Texture" and t.SetAlpha then
                list[#list + 1] = t
                hooksecurefunc(t, "SetAlpha", function(self, a)
                    if winInHook[cf] or not winAlpha[cf] then return end
                    if not a or math.abs(a - winAlpha[cf]) > 0.001 then
                        winInHook[cf] = true
                        self:SetAlpha(winAlpha[cf])
                        winInHook[cf] = false
                    end
                end)
            end
        end
        winTex[cf] = list
    end

    local chatButtons = {}
    local function AddButton(f, hiddenKey)
        if type(f) == "table" and f.SetAlpha and not db[hiddenKey] then chatButtons[#chatButtons + 1] = f end
    end
    AddButton(_G.QuickJoinToastButton, "hideSocialButton")
    AddButton(_G.ChatFrameMenuButton, "hideChatButtons")
    AddButton(_G.ChatFrameChannelButton, "hideVoiceChatButton")
    AddButton(_G.ChatFrameToggleVoiceDeafenButton, "hideVoiceChatButton")
    AddButton(_G.ChatFrameToggleVoiceMuteButton, "hideVoiceChatButton")
    local buttonsOwner = _G.ChatFrame1
    -- Quality of Life's Copy Chat button (v1.57.0) sits in the same column and fades with them. It is
    -- built at QoL's PLAYER_LOGIN, which can come after this, so it is taken now if it exists and
    -- otherwise handed over by QoL through VUI.CS_AddChatButton, at the window's current look.
    -- Hovering it brings the window in: it is in ChatFrame1's button frame, which Blizzard's hover test
    -- counts (FCF_OnUpdate, FloatingChatFrame.lua:1139-1143).
    local addedButtons = {}
    local function AddLateButton(btn)
        if type(btn) ~= "table" or not btn.SetAlpha or addedButtons[btn] then return end
        addedButtons[btn] = true
        chatButtons[#chatButtons + 1] = btn
        btn:SetAlpha(((winShown and winShown[buttonsOwner]) or 0) >= 1 and 1 or TabAlpha())
    end

    local tweens = {}
    local tweenDriver = CreateFrame("Frame")
    tweenDriver:Hide()
    tweenDriver:SetScript("OnUpdate", function(self, elapsed)
        for key, tw in pairs(tweens) do
            tw.t = tw.t + (elapsed or 0)
            if tw.t >= tw.d then
                tweens[key] = nil
                tw.set(tw.to)
            else
                tw.set(tw.from + (tw.to - tw.from) * tw.t / tw.d)
            end
        end
        if not next(tweens) then self:Hide() end
    end)
    local function Tween(key, from, to, dur, set)
        if not dur or dur <= 0 or math.abs(to - from) < 0.001 then
            tweens[key] = nil
            set(to)
            return
        end
        tweens[key] = { from = from, to = to, d = dur, t = 0, set = set }
        tweenDriver:Show()
    end
    -- shown: true = Blizzard's shown look, false = faded to the slider.
    local function FadeWindow(cf, shown, dur)
        if not winTex[cf] then return end
        Tween(cf, winShown[cf] or 0, shown and 1 or 0, dur, function(v) winShown[cf] = v; ApplyWindow(cf) end)
        if cf == buttonsOwner then
            for _, btn in ipairs(chatButtons) do
                Tween(btn, btn:GetAlpha(), shown and 1 or TabAlpha(), dur, function(v) btn:SetAlpha(v) end)
            end
        end
    end

    for cf in pairs(tabs) do
        winShown[cf] = cf.hasBeenFaded and 1 or 0
        FadeWindow(cf, cf.hasBeenFaded and true or false, 0)
        ApplyWindow(cf)
    end
    AddLateButton(_G.VeritasUI_CopyChatButton)
    VUI.CS_AddChatButton = AddLateButton
    -- Colour and opacity changes from the Background picker write the textures directly.
    if _G.FCF_SetWindowColor then
        hooksecurefunc("FCF_SetWindowColor", function(cf) if winTex[cf] then ApplyWindow(cf) end end)
    end
    if _G.FCF_SetWindowAlpha then
        hooksecurefunc("FCF_SetWindowAlpha", function(cf) if winTex[cf] then ApplyWindow(cf) end end)
    end

    -- The opacity slider moved: tabs, type bars, windows and buttons that are faded now take the new
    -- value at once. Anything fading or shown picks it up when it next fades.
    function chatTabsApplyOpacity()
        local a = TabAlpha()
        for cf, tab in pairs(tabs) do
            if tab._vui_fadeState == "HIDDEN" then
                tab._vui_prevAlpha = a
                tab:SetAlpha(a)
            end
            if not cf.hasBeenFaded then
                FadeBar(cf, BAR_ALPHA * a, 0)
                FadeWindow(cf, false, 0)
            end
            if winTex[cf] then ApplyWindow(cf) end
        end
    end

    if FCF_FadeInChatFrame then
        hooksecurefunc("FCF_FadeInChatFrame", function(cf)
            ShowTab(cf)
            FadeBar(cf, BAR_ALPHA, FADE_IN)
            FadeWindow(cf, true, FADE_IN)
        end)
    end
    if FCF_FadeOutChatFrame then
        hooksecurefunc("FCF_FadeOutChatFrame", function(cf)
            HideTab(cf)
            FadeBar(cf, BarFaded(), FADE_OUT)
            FadeWindow(cf, false, FADE_OUT)
        end)
    end
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
    local fo, rc = VUI.HookHoverFade(MicroMenu, nil, nil, nil, Opacity("fadeMicroMenuOpacity"))
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
        InCombatLockdown,
        Opacity("fadePlayerFrameOpacity")
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
--
-- v1.48.0 (owner's request): a dropdown, one row per kind of banner, so a player can keep (say) the
-- Delve Nemesis message while hiding the rest. Owner's probe, 2026-11-01: every Delve message is an
-- event toast; "Nemesis Strongbox Upgraded" and "Dundun Hides Within..." are eventType SpellScript,
-- stage names ("The Darkway") eventType Scenario; no boss banner fired. The toast rows follow
-- Blizzard's own Enum.EventToastEventType (UIEventToastConstantsDocumentation.lua:32-67).
local TOP_BANNER_GROUPS = {
    { id = "zone",     label = "Zone Names", tip = "The zone name when you travel.",
      frame = "ZoneTextFrame", events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" } },
    { id = "boss",     label = "Boss Kills and Loot", tip = "The banner when a boss dies, and what it dropped.",
      frame = "BossBanner",    events = { "BOSS_KILL", "ENCOUNTER_LOOT_RECEIVED" } },
    { id = "levelup",  label = "Level Up and New Spells", tip = "Reaching a new level, and spells you learn.",
      types = { "LevelUp", "LevelUpSpell", "LevelUpDungeon", "LevelUpRaid", "LevelUpPvP", "LevelUpOther",
                "SpellLearned" } },
    { id = "scenario", label = "Scenario and Delve Stages", tip = "Stage names, such as The Darkway.",
      types = { "Scenario" } },
    { id = "messages", label = "Delve and Event Messages",
      tip = "Messages during a Delve or event, such as Nemesis Strongbox Upgraded.",
      types = { "SpellScript", "WorldStateChange", "QuestBossEmote", "CriteriaUpdated", "PlayerAuraAdded",
                "PlayerAuraRemoved" } },
    { id = "weekly",   label = "Weekly Rewards and Ratings",
      tip = "The Great Vault, Mythic+ records and PvP rating changes.",
      types = { "WeeklyRewardUnlock", "WeeklyRewardUpgrade", "MythicPlusWeeklyRecord", "PvPTierUpdate" } },
    { id = "renown",   label = "Renown", tip = "A new renown level.", types = { "RenownFactionLeveledUp" } },
    { id = "other",    label = "Everything Else", tip = "Flight points, pet battles, treasure, housing and the rest.",
      types = {} },   -- every toast type not named above
}

-- Group id of an event toast, from its eventType; a type not listed (or a new one) is "other".
local function ToastGroup(info)
    local et = type(info) == "table" and info.eventType
    if et == nil or (issecretvalue and issecretvalue(et)) then return "other" end
    local enum = Enum and Enum.EventToastEventType
    for _, g in ipairs(TOP_BANNER_GROUPS) do
        for _, name in ipairs(g.types or {}) do
            if enum and enum[name] == et then return g.id end
        end
    end
    return "other"
end

-- ⚠ Only SOME toast kinds hidden: Blizzard's toast chain stays Blizzard's (an EXPERIMENT until the
-- owner confirms it in game). Two ways a toast reaches the screen:
--  1. DISPLAY_EVENT_TOASTS while nothing is toasting: Blizzard's handler peeks the queue head and shows
--     it (EventToastManager.lua:154-160). Our handler runs FIRST (Blizzard's frame is re-registered
--     after ours) and pops hidden heads with RemoveCurrentToast, so Blizzard only ever sees a wanted
--     one. Nothing of Blizzard's is called or written: no taint.
--  2. The next toast in the queue when one finishes (ToastingEnded -> DisplayToast, :327-369), which
--     cannot be filtered first. Then the toast is made invisible (the manager frame's alpha, its black
--     band and gold lines hidden, its sounds cleared) and closed at once the way Blizzard closes toasts
--     itself (CloseActiveToasts, :235-244), but only once it is the PLAYING top banner: closing a
--     queued one would finish whichever banner is playing (OnAnimatedOut -> TopBannerManager_BannerFinished,
--     :1196). showAnim is stopped first so OnAnimatedIn cannot run AnimOut a second time.
local function SetupToastFilter(hidden)
    local etm = _G.EventToastManagerFrame
    local api = _G.C_EventToastManager
    if not (etm and api and api.GetNextToastToDisplay and api.RemoveCurrentToast) then return end
    local function Hidden(info) return info and hidden[ToastGroup(info)] or false end

    local pre = CreateFrame("Frame")
    pre:RegisterEvent("DISPLAY_EVENT_TOASTS")
    pre:SetScript("OnEvent", function()
        if etm.IsCurrentlyToasting and etm:IsCurrentlyToasting() then return end
        for _ = 1, 50 do
            local ok, info = pcall(api.GetNextToastToDisplay)
            if not (ok and Hidden(info)) then break end
            pcall(api.RemoveCurrentToast)
        end
    end)
    pcall(etm.UnregisterEvent, etm, "DISPLAY_EVENT_TOASTS")
    pcall(etm.RegisterEvent, etm, "DISPLAY_EVENT_TOASTS")

    local closing
    local function Check()
        local toast = etm.currentDisplayingToast
        if not (toast and Hidden(toast.toastInfo)) then
            closing = nil
            etm:SetAlpha(1)
            return
        end
        etm:SetAlpha(0)
        for _, k in ipairs({ "BlackBG", "GLine", "GLine2" }) do
            if etm[k] and etm[k].Hide then etm[k]:Hide() end
        end
        toast.toastInfo.showSoundKitID, toast.toastInfo.hideSoundKitID = nil, nil
        local cur = _G.TopBannerMgr and _G.TopBannerMgr.currentBanner
        if closing ~= toast and cur and cur.frame == toast and etm.CloseActiveToasts then
            closing = toast
            if toast.showAnim then toast.showAnim:Stop() end
            etm:CloseActiveToasts()
        end
    end
    if etm.DisplayToast then hooksecurefunc(etm, "DisplayToast", Check) end
    if _G.TopBannerManager_Show then hooksecurefunc("TopBannerManager_Show", Check) end
    if _G.TopBannerManager_BannerFinished then hooksecurefunc("TopBannerManager_BannerFinished", Check) end
end

local function HideTopBanners()
    local hidden, anyToast, allToasts = db.hideTopBannerTypes or {}, false, true
    for _, g in ipairs(TOP_BANNER_GROUPS) do
        if g.frame then
            local f = _G[g.frame]
            if hidden[g.id] and f and f.UnregisterEvent then
                for _, ev in ipairs(g.events) do pcall(f.UnregisterEvent, f, ev) end
            end
        elseif hidden[g.id] then anyToast = true
        else allToasts = false end
    end
    if anyToast and allToasts then
        -- Every kind of toast hidden: the original method, the event that starts them unregistered.
        local etm = _G.EventToastManagerFrame
        if etm and etm.UnregisterEvent then pcall(etm.UnregisterEvent, etm, "DISPLAY_EVENT_TOASTS") end
    elseif anyToast then
        SetupToastFilter(hidden)
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
--
-- v1.49.0 (feature batch item 3): Hide Transforms, a dropdown of four groups. The new groups' aura IDs
-- are server data too, from EllesmereUI v9.7.2's transform list
-- (EllesmereUIQoL.lua:4977-5015, read 2026-11-01), as the profession list was.
local TRANSFORM_KINDS = {
    { id = "professions", label = "Profession Gear", tip = "The outfit crafting, gathering and fishing put on you.",
      ids = {
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
    } },
    -- Owner, 2026-11-01: groups, not one row per item, so a new costume or toy is one more ID in
    -- its group rather than one more row.
    { id = "holiday", label = "Holiday Costumes",
      tip = "Hallowed Wand, Weighted Jack-o'-Lantern, Noblegarden Bunny and Pilgrim's Turkey.", ids = {
        44212,                               -- Weighted Jack-o'-Lantern
        172010, 218132, 191703, 24732, 191210, 172015, 24735, 24736, 191698, 191700,   -- Hallowed Wand
        172008, 24712, 24713, 191701, 191211, 24710, 24711, 191686, 191688, 24708,
        24709, 173958, 173959, 191682, 191683, 24723, 191702, 172003, 172020, 191208, 24740,
        61734, 61716,                        -- Noblegarden Bunny
        61781,                               -- Pilgrim's Turkey
    } },
    { id = "toys", label = "Toys", tip = "Aqir Egg Cluster, Atomic Recalibrator and Regoblinator, Detoxified "
      .. "Blight Grenade, Lucille's Sewing Needle and Spraybots.", ids = {
        318452,                              -- Aqir Egg Cluster
        399502,                              -- Atomic Recalibrator
        1215363,                             -- Atomic Regoblinator
        290224,                              -- Detoxified Blight Grenade
        279509,                              -- Lucille's Sewing Needle
        301892, 301893, 301894,              -- Spraybots
    } },
    { id = "consumables", label = "Consumables", tip = "Cursed Pickaxe, Noggenfogger Elixir and Reflecting Prism.",
      ids = {
        454405,                              -- Cursed Pickaxe
        16593, 1223630, 16595, 1223629, 1223631,   -- Noggenfogger Elixir
        163267,                              -- Reflecting Prism
    } },
}
-- The aura IDs of every ticked kind, rebuilt by SetHideTransforms.
local hiddenTransformAuras = {}
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
    for _, id in ipairs(hiddenTransformAuras) do
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

-- Applies db.hideTransformTypes at once (no /reload): the event registration follows it.
local function SetHideTransforms()
    local ids = {}
    for _, k in ipairs(TRANSFORM_KINDS) do
        if db.hideTransformTypes[k.id] then
            for _, id in ipairs(k.ids) do ids[#ids + 1] = id end
        end
    end
    hiddenTransformAuras = ids
    if #ids > 0 then
        gearFrame:RegisterUnitEvent("UNIT_AURA", "player")
        gearFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        gearFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        RemoveProfessionGear(false)
    else
        gearFrame:UnregisterAllEvents()
        gearPending = false
    end
end

-- ── Feature: Fade Minimap Buttons (v1.60.0, owner's request; was Hide Minimap Buttons, v1.50.0) ──
-- Blizzard has no option for these (Edit Mode's Minimap system offers only header position, size and
-- rotation). The pieces picked fade out, and hovering the minimap or any of them brings them ALL back
-- (owner: a button at 0% has to be findable). Each fades by ALPHA only, never Hide(): Blizzard Shows
-- several of them on its own (zoom buttons on hover, Minimap.lua:276-290; Tracking per game rule,
-- :390/:746/:797; the clock for an alarm, Blizzard_TimeManager.lua:465; the compartment and expansion
-- button from their own refresh, AddonCompartment.lua:141-147, Minimap.lua:866-891), and the expansion
-- button's OnHide drops its EventRegistry callbacks (:901-906). Blizzard never sets these frames' alpha
-- (no SetAlpha on them in Blizzard_Minimap or Blizzard_TimeManager), and the mouse is left on so a faded
-- piece can still be clicked. Mail and crafting orders stay with Fade Minimap Alerts. The fade itself
-- (SetupMinimapButtonsFade) sits below SetupLiveFade.
-- One frame per piece where a piece is a parent and its child (Tracking holds Tracking.Button,
-- Minimap.xml:51-81): fading both would multiply their alphas.
local MINIMAP_BUTTONS = {
    { id = "zone",       label = "Zone Name", tip = "The zone name above the minimap.",
      frames = function() local c = _G.MinimapCluster; return c and { c.BorderTop, c.ZoneTextButton } end },
    { id = "clock",      label = "Clock", tip = "The clock. A faded clock's alarm still plays its sound.",
      -- Blizzard_TimeManager is load-on-demand
      frames = function() return { _G.TimeManagerClockButton } end },
    { id = "calendar",   label = "Calendar", tip = "The calendar button.",
      frames = function() return { _G.GameTimeFrame } end },
    { id = "tracking",   label = "Tracking", tip = "The tracking button.",
      frames = function()
          local t = _G.MinimapCluster and _G.MinimapCluster.Tracking
          return t and { t }
      end },
    { id = "zoom",       label = "Zoom Buttons", tip = "The + and - buttons shown when you hover the minimap.",
      frames = function() local m = _G.Minimap; return m and { m.ZoomIn, m.ZoomOut } end },
    { id = "compartment", label = "Addon Compartment",
      tip = "The addon menu button, where VeritasUI's own shortcuts are listed.",
      frames = function() return { _G.AddonCompartmentFrame } end },
    { id = "expansion",  label = "Expansion Summary Button", tip = "The button that opens the expansion summary.",
      frames = function() return { _G.ExpansionLandingPageMinimapButton } end },
    { id = "difficulty", label = "Instance Difficulty", tip = "The difficulty shown in a dungeon, raid or Delve.",
      frames = function() local c = _G.MinimapCluster; return c and { c.InstanceDifficulty } end },
}

-- /cs gear: what is on you now, so a profession whose outfit still shows can be identified.
-- Lists the listed outfit auras found, then every buff's name and spell ID (scan pcall'd: aura
-- data is secret in restricted content).
local function PrintGearDiag()
    local on = {}
    for _, k in ipairs(TRANSFORM_KINDS) do
        if db and db.hideTransformTypes[k.id] then on[#on + 1] = k.label end
    end
    VUI.Print("Clean Solo", "Hide Transforms: " .. (#on > 0 and table.concat(on, ", ") or "none")
        .. "; last result: " .. gearLast)
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
      tip = "'You are too far away!', 'You are facing the wrong way!', no target, and similar.",
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
      tip = "Not ready yet, not enough mana, energy or rage, can't do that while moving, and similar.",
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
    { id = "items", label = "Items & Bags", tip = "Bags full, can't equip or use an item, and similar.",
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
      tip = "Mailbox, vendor and bank errors, such as 'Internal mail database error.'",
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
    { id = "loot", label = "Looting & Objects", tip = "Loot and object errors, such as being too far away to loot.",
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
    { id = "travel", label = "Mounts & Flight Paths", tip = "Mount and flight path errors.",
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
                local fo, rc = VUI.HookHoverFade(barFrame, IsEditModeActive, nil, nil,
                    Opacity("fadeActionBarsOpacity"))
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

-- ── Feature: Fade Damage Meter / Action Bar 1 / Status Bars (v1.39.0) ──
-- Same hover fade as the bars above, with a shouldShow condition (VUI.HookHoverFade): while it is
-- true the frame fades in and stays, as if hovered. Each applies at once: the hook is installed the
-- first time the option is on, and turning the option off makes shouldShow true, so it fades back
-- in and stays. Blizzard never sets the alpha of any of these frames itself (source, 2026-10-31):
-- DamageMeter sets only its session windows' alpha, which multiplies under ours
-- (DamageMeter.lua:298, :556); MainActionBar has no SetAlpha in Blizzard_ActionBar or
-- Blizzard_EditMode. The status-bar CONTAINERS do animate their own alpha -- see
-- SetupStatusBarFade. Landmine 71 (Bar 1 "overridden by Blizzard's alpha management") dated from
-- the MainMenuBar era; the v1.39.0 test build measured Action Bar 1 fading correctly (owner).
local liveFadeHooked = {}

local function SetupLiveFade(key, targets, shouldShow, noEnterHook, fadedAlpha)
    if liveFadeHooked[key] then return end
    local fadeOuts, refreshers = {}, {}
    for _, target in ipairs(targets) do
        if target then
            local fo, rc = VUI.HookHoverFade(target, IsEditModeActive, shouldShow, noEnterHook, fadedAlpha)
            if fo then fadeOuts[#fadeOuts + 1] = fo end
            if rc then refreshers[#refreshers + 1] = rc end
        end
    end
    if #fadeOuts == 0 then return end
    liveFadeHooked[key] = true
    if EditModeManagerFrame then
        pcall(hooksecurefunc, EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.2, function()
                for _, rc in ipairs(refreshers) do rc() end
                for _, fo in ipairs(fadeOuts) do fo() end
            end)
        end)
    end
end

-- No OnEnter hook (audit C1, 2026-11-01): DamageMeter is an Edit Mode system frame
-- (DamageMeter.xml:3 inherits EditModeDamageMeterSystemTemplate), the class of frame where a HookScript
-- tainted Edit Mode once already (landmine 114). The poll reveals it within 0.1 s, as for Action Bar 1.
local function SetupDamageMeterFade()
    local function Hook()
        SetupLiveFade("fadeDamageMeter", { _G.DamageMeter },
            function() return not db.fadeDamageMeter or InCombatLockdown() end,
            true, Opacity("fadeDamageMeterOpacity"))
    end
    if _G.DamageMeter then Hook()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_DamageMeter", Hook)
    end
end

-- The All Objectives tracker (v1.42.0, owner's request), faded SECTION BY SECTION since v1.44.1.
-- Owner, 2026-10-31: in a Delve, Mythic+, Void Incursion or similar event, that event's objective must
-- stay at full opacity while the rest of the tracker keeps the slider's opacity. The tracker's own alpha
-- multiplies into every section, so it is left at 1 and each child of ObjectiveTrackerFrame is faded
-- instead: the header and every module (Blizzard_ObjectiveTrackerManager.lua:190-216 puts all modules
-- in this container, Module.lua:65 parents them to it).
--   * Event modules are never faded: ScenarioObjectiveTracker (scenarios, Delves, Mythic+),
--     UIWidgetObjectiveTracker (event progress widgets) and BonusObjectiveTracker (objectives of the
--     area you are in). Blizzard shows a module only while it has contents and hides it otherwise
--     (Module.lua:201-214), so "never faded" is "full while the event is on".
--   * The background (NineSlice) is Blizzard's Edit Mode opacity (Container.lua:169-171): its SetAlpha is
--     owned as the chat window's is (landmine 140) -- Blizzard's value is kept and multiplied by ours, and
--     it stays full while an event module is shown, so the event keeps its background.
--   * Hovering the tracker shows every section. Blizzard never sets a module's or the header's own
--     alpha (source, 2026-10-31); blocks set their own, which multiply under ours.
-- Poll only, as before: no script hooks on a frame holding the quest item buttons, whose click is a
-- protected call (UseQuestLogSpecialItem, Blizzard_ObjectiveTrackerShared.lua:94-102).
-- ⚠ Since v1.51.0 the event modules are no longer "never faded": they have sliders like the rest, at
-- 100% by default, which is the same thing until a player lowers one.
-- v1.51.0 (feature batch item 5): each section has its own faded opacity, and a section at 0% is
-- COLLAPSED (owner, 2026-11-01): the sections below it move up, so a section kept at 100% does not sit
-- alone at the bottom under an invisible gap. Collapsing is done by re-anchoring the modules ourselves
-- with Blizzard's own formula (Container.lua:73-96: first module TOP at -topModulePadding, the rest TOP
-- to the previous module's BOTTOM at -moduleSpacing, LEFT at module.leftMargin; the background's BOTTOM
-- to the last module's at -bottomModulePadding). Only ClearAllPoints/SetPoint, never a write to the
-- tracker's Lua state and never module:SetCollapsed (which writes isCollapsed and re-runs the layout
-- that places the quest item buttons): nothing of Blizzard's runs from our code, so nothing is tainted.
-- Neither the modules nor the background are protected frames, so this works in combat too. Blizzard
-- re-anchors on its next update; the poll puts our chain back within a tenth of a second.
-- "In Raids" (fadeObjectiveTrackerRaid): hide every section in a raid, or only during a raid boss fight.
local OT_SECTIONS = {
    { id = "scenario",     frame = "ScenarioObjectiveTracker",          label = "Scenario",          full = true },
    { id = "event",        frame = "UIWidgetObjectiveTracker",          label = "Event Objectives",  full = true },
    { id = "campaign",     frame = "CampaignQuestObjectiveTracker",     label = "Campaign",          quests = true },
    { id = "quests",       frame = "QuestObjectiveTracker",             label = "Quests",            quests = true },
    { id = "collections",  frame = "AdventureObjectiveTracker",         label = "Collections" },
    { id = "achievements", frame = "AchievementObjectiveTracker",       label = "Achievements" },
    { id = "travelerslog", frame = "MonthlyActivitiesObjectiveTracker", label = "Traveler's Log" },
    { id = "endeavors",    frame = "InitiativeTasksObjectiveTracker",   label = "Endeavors" },
    { id = "professions",  frame = "ProfessionsRecipeTracker",          label = "Professions" },
    { id = "bonus",        frame = "BonusObjectiveTracker",             label = "Bonus Objectives",  full = true },
    { id = "worldquests",  frame = "WorldQuestObjectiveTracker",        label = "World Quests",      quests = true },
}
local OT_FADE_IN, OT_FADE_OUT, OT_POLL = 0.2, 0.5, 0.1   -- the hover fade's speeds (Lib HookHoverFade)
local otHooked = false

local function SectionOpacity(sec) return db and tonumber(db["otOpacity_" .. sec.id]) or (sec.full and 1 or 0) end

local otEncounter = false   -- a boss fight is on (ENCOUNTER_START .. ENCOUNTER_END)
local function OTRaidHidden()
    local mode = db and db.fadeObjectiveTrackerRaid or "normal"
    if mode == "normal" then return false end
    local ok, inInstance, kind = pcall(IsInInstance)
    if not (ok and inInstance and kind == "raid") then return false end
    return mode == "raid" or otEncounter
end

local function SetupObjectiveTrackerFade()
    if otHooked then return end
    local otf = _G.ObjectiveTrackerFrame
    if type(otf) ~= "table" or not otf.GetChildren then
        if EventUtil and EventUtil.ContinueOnAddOnLoaded then
            EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", SetupObjectiveTrackerFade)
        end
        return
    end
    otHooked = true
    local nine, header = otf.NineSlice, otf.Header
    local mods = {}         -- { frame, sec } in Blizzard's order (Manager.lua:194-206)
    for _, sec in ipairs(OT_SECTIONS) do
        local f = _G[sec.frame]
        if type(f) == "table" and f.SetAlpha then mods[#mods + 1] = { f = f, sec = sec } end
    end
    local known = { [nine or false] = true, [header or false] = true }
    for _, m in ipairs(mods) do known[m.f] = true end
    local extras = {}       -- any other child of the tracker: faded like the most-visible section
    local function Collect()
        extras = {}
        for _, child in ipairs({ otf:GetChildren() }) do
            if not known[child] and child.SetAlpha then extras[#extras + 1] = child end
        end
    end
    Collect()

    -- Background: Blizzard's own alpha x ours, put back whenever Blizzard writes it (landmine 140).
    local nineBlizz, nineOurs, nineInHook = 1, 1, false
    local function ApplyNine()
        if not nine then return end
        nineInHook = true
        nine:SetAlpha(nineBlizz * nineOurs)
        nineInHook = false
    end
    if type(nine) == "table" and nine.SetAlpha then
        nineBlizz = nine.GetAlpha and nine:GetAlpha() or 1
        hooksecurefunc(nine, "SetAlpha", function(_, a)
            if nineInHook then return end
            nineBlizz = tonumber(a) or 1
            ApplyNine()
        end)
    else
        nine = nil
    end

    -- Re-anchor the shown modules, leaving out the collapsed ones. A collapsed module is PARKED far below
    -- the tracker: left where Blizzard put it, the invisible section would lie over the ones that moved
    -- up and take their clicks.
    -- v1.51.0, owner's follow-ups: the FOCUSED quest (C_SuperTrack, the one with the arrow) comes FIRST in
    -- its section, and its section comes before any section that is hidden while faded, for as long as it
    -- is focused -- so hovering, which shows every section, never moves it from under the mouse. Its
    -- section's header stays shown with it. In a collapsed section its other quests are parked; otherwise
    -- they follow it in Blizzard's order. Blocks use Blizzard's own formula (Module.lua:341-347, 422-439: TOP
    -- to ContentsFrame TOP at fromHeaderOffsetY, then to the previous BOTTOM at fromBlockOffsetY, LEFT at
    -- offsetX or blockOffsetX, RIGHT unless fixedWidth); Blizzard's order (firstBlock -> nextBlock) and the
    -- same formula put every quest back once nothing is focused.
    local PARK_Y = -4000
    local touched = {}      -- [module] = true while its quests are anchored by us
    local function Park(f)
        local p1, rel, _, _, y = f:GetPoint(1)
        if p1 ~= "TOP" or rel ~= otf or y ~= PARK_Y then
            f:ClearAllPoints()
            f:SetPoint("TOP", otf, "BOTTOM", 0, PARK_Y)
        end
    end
    local function AnchorBlockAt(mod, b, anchor, relPoint, y)
        local p1, rel, _, _, cy = b:GetPoint(1)
        if p1 == "TOP" and rel == anchor and math.abs((cy or 0) - y) <= 0.5 then return end
        b:ClearAllPoints()
        b:SetPoint("TOP", anchor, relPoint, 0, y)
        b:SetPoint("LEFT", b.offsetX or mod.blockOffsetX or 0, 0)
        if not b.fixedWidth then b:SetPoint("RIGHT") end
    end
    -- Lays the module's quests out: `first` (if any) at the top, the rest in Blizzard's order after it, or
    -- parked when `parkOthers`.
    local function ChainBlocks(mod, first, parkOthers)
        local prevB
        if first and mod.ContentsFrame then
            AnchorBlockAt(mod, first, mod.ContentsFrame, "TOP", mod.fromHeaderOffsetY or -10)
            prevB = first
        end
        local b, n = mod.firstBlock, 0
        while b and n < 200 do
            if b ~= first then
                if parkOthers then Park(b)
                elseif prevB then AnchorBlockAt(mod, b, prevB, "BOTTOM", mod.fromBlockOffsetY or -10); prevB = b
                elseif mod.ContentsFrame then
                    AnchorBlockAt(mod, b, mod.ContentsFrame, "TOP", mod.fromHeaderOffsetY or -10); prevB = b
                end
            end
            b, n = b.nextBlock, n + 1
        end
    end
    local function Relayout(collapsed, focused, order)
        local prev
        for _, m in ipairs(order or mods) do
            local f = m.f
            local fb = focused[f]
            if fb then touched[f] = true; ChainBlocks(f, fb, collapsed[f])
            elseif touched[f] then ChainBlocks(f, nil, false); touched[f] = nil end
            if f:IsShown() and collapsed[f] and not fb then
                Park(f)
            elseif f:IsShown() then
                local p1, rel, _, _, y = f:GetPoint(1)
                local wantRel = prev or otf
                local wantY = prev and -(otf.moduleSpacing or 10) or -(otf.topModulePadding or 0)
                if p1 ~= "TOP" or rel ~= wantRel or math.abs((y or 0) - wantY) > 0.5 then
                    f:ClearAllPoints()
                    if prev then f:SetPoint("TOP", prev, "BOTTOM", 0, wantY)
                    else f:SetPoint("TOP", 0, wantY) end
                    f:SetPoint("LEFT", otf, "LEFT", f.leftMargin or 0, 0)
                end
                prev = (collapsed[f] and fb) or f
            end
        end
        if nine and prev and nine.GetPoint then
            for i = 1, (nine.GetNumPoints and nine:GetNumPoints() or 0) do
                local p, rel, _, _, y = nine:GetPoint(i)
                local wantY = -(otf.bottomModulePadding or 10)
                if p == "BOTTOM" and (rel ~= prev or math.abs((y or 0) - wantY) > 0.5) then
                    nine:SetPoint("BOTTOM", prev, "BOTTOM", 0, wantY)
                end
            end
        end
    end
    -- The section order while a quest is focused: sections above its section that still show while faded
    -- stay above it; the ones hidden while faded go after it, so hovering cannot push it down.
    local function FocusOrder(focusMod)
        local before, hiddenBefore, after, seen = {}, {}, {}, false
        for _, m in ipairs(mods) do
            if m.f == focusMod then seen = true
            elseif seen then after[#after + 1] = m
            elseif SectionOpacity(m.sec) > 0 then before[#before + 1] = m
            else hiddenBefore[#hiddenBefore + 1] = m end
        end
        local order = before
        for _, m in ipairs(mods) do if m.f == focusMod then order[#order + 1] = m end end
        for _, m in ipairs(hiddenBefore) do order[#order + 1] = m end
        for _, m in ipairs(after) do order[#order + 1] = m end
        return order
    end

    -- The focused quest's block, in a quest section, if it is laid out. Read-only walk of the module's
    -- block table (Module.lua:254-282: usedBlocks[template][id], id = questID for quest blocks).
    local function FocusedBlock(mod, questID)
        for _, blocks in pairs(type(mod.usedBlocks) == "table" and mod.usedBlocks or {}) do
            local b = type(blocks) == "table" and blocks[questID]
            if b and b.IsShown and b:IsShown() then return b end
        end
    end
    -- The focused quest's block, its right-edge frames (quest item and POI buttons, anchored RIGHT to the
    -- block or to each other: Block.lua:341-362) and its section's header show at full opacity through the
    -- section's fade.
    -- ⚠ SetIgnoreParentAlpha also escapes UIParent's alpha (landmine 142), which Quality of Life's AFK screen
    -- sets to 0, so it is dropped whenever UIParent is not fully shown.
    local ignoring = {}
    local function SetFullOpacity(mod, fb)
        local want = {}
        if fb and (not UIParent or (UIParent:GetAlpha() or 1) >= 0.99) then
            want[fb] = true
            if mod.Header then want[mod.Header] = true end   -- owner: keep the "Quests" header with it
            local grew = true
            while grew do
                grew = false
                for _, fr in pairs(type(mod.usedRightEdgeFrames) == "table" and mod.usedRightEdgeFrames or {}) do
                    if not want[fr] and fr.GetPoint then
                        local _, rel = fr:GetPoint(1)
                        if rel and want[rel] then want[fr] = true; grew = true end
                    end
                end
            end
        end
        for fr in pairs(ignoring) do
            if fr == mod.Header or fr.parentModule == mod or fr:GetParent() == mod.ContentsFrame then
                if not want[fr] then pcall(fr.SetIgnoreParentAlpha, fr, false); ignoring[fr] = nil end
            end
        end
        for fr in pairs(want) do
            if not ignoring[fr] and fr.SetIgnoreParentAlpha then
                pcall(fr.SetIgnoreParentAlpha, fr, true); ignoring[fr] = true
            end
        end
    end

    local last = {}
    local function FadeTo(f, target, instant)
        if last[f] == target then return end
        last[f] = target
        if instant then f:SetAlpha(target)
        else VUI.SmoothFade(f, target > (f:GetAlpha() or 0) and OT_FADE_IN or OT_FADE_OUT, target) end
    end

    -- Unfocusing a quest in a faded section (owner, 2026-11-01): the quest used to drop out at once and the
    -- section's own quests were put back while still on screen, so the top quest flashed. Now the quest
    -- that WAS focused keeps its place and fades to its section's opacity with the background; only then
    -- does it follow the section again, laid out as Blizzard has it (and collapsed at 0%). Its own alpha
    -- and its header's are put back to 1 afterwards (Blizzard's value for a shown block,
    -- AnimTemplates.lua:85), unseen, as they then follow the section's.
    local lastFocus, leaving, leavingFade = {}, {}, {}
    local lastCollapsed, lastFocused, lastOrder = {}, {}, nil
    local function EndLeaving(mod)
        local lb = leaving[mod]
        if not lb then return end
        lb:SetAlpha(1)
        if mod.Header then mod.Header:SetAlpha(1) end
        leaving[mod], leavingFade[lb] = nil, nil
    end
    local hoverUntil, sinceCollect = 0, 0
    local function Evaluate(instant)
        local now = GetTime()
        if otf:IsVisible() and otf:IsMouseOver() then
            hoverUntil = now + math.max(0.15, (VUI.GetFadeDelay and VUI.GetFadeDelay()) or 0)
        end
        local show = not db.fadeObjectiveTracker or now < hoverUntil or IsEditModeActive()
        local raidHidden = db.fadeObjectiveTracker and OTRaidHidden() and not show
        local collapsed, focused, top, focusMod = {}, {}, 0, nil
        local superID
        if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local okST, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
            if okST and type(id) == "number" and id > 0 then superID = id end
        end
        for _, m in ipairs(mods) do
            local target
            if show then target = 1
            elseif raidHidden then target = 0
            else target = VUI.FadedAlpha(function() return SectionOpacity(m.sec) end) end
            FadeTo(m.f, target, instant)
            -- The focused quest leads its section's order whenever the fade is on (even while hovered);
            -- it shows through the fade while the section is faded or still fading IN (else it would blink
            -- to the section's alpha the moment the mouse arrives).
            local fading = target < 1 or (m.f:GetAlpha() or 1) < 0.99
            local fb = m.sec.quests and superID and db.fadeObjectiveTracker and not raidHidden
                and FocusedBlock(m.f, superID) or nil
            if fb then focused[m.f] = fb; focusMod = m.f; if fading then top = 1 end end
            local lb = leaving[m.f]
            if lb and (fb or show or not lb:IsShown()) then EndLeaving(m.f); lb = nil end
            local was = lastFocus[m.f]
            if not fb and not lb and was and not show and m.sec.quests and was:IsShown() then
                lb = was; leaving[m.f] = lb
            end
            if lb then
                -- Down to the section's own opacity (0 for a collapsed section, e.g. 0.3 otherwise), where
                -- it can follow the section again without a jump; its header with it.
                if (lb:GetAlpha() or 0) > target + 0.01 then
                    if not leavingFade[lb] then
                        leavingFade[lb] = true
                        VUI.SmoothFade(lb, OT_FADE_OUT, target)
                        if m.f.Header then VUI.SmoothFade(m.f.Header, OT_FADE_OUT, target) end
                    end
                    focused[m.f] = lb; focusMod = focusMod or m.f
                else
                    EndLeaving(m.f); lb = nil
                end
            end
            lastFocus[m.f] = fb
            if m.sec.quests then SetFullOpacity(m.f, (fb and fading and fb) or lb) end
            -- Collapsed only once its fade-out has FINISHED (owner, 2026-11-01): parking it as soon as
            -- the target is 0 cut the fade short, so the tracker popped out instead of fading like the rest.
            if target <= 0 and not show and (m.f:GetAlpha() or 0) <= 0.01 then collapsed[m.f] = true end
            if m.f:IsShown() and target > top then top = target end
        end
        if show then top = 1 end
        if header then FadeTo(header, top, instant) end
        for _, f in ipairs(extras) do FadeTo(f, top, instant) end
        if nine and math.abs(nineOurs - top) > 0.001 then
            nineOurs = top
            ApplyNine()
        end
        lastCollapsed, lastFocused = raidHidden and {} or collapsed, focused
        lastOrder = focusMod and FocusOrder(focusMod) or nil
        if not IsEditModeActive() then Relayout(lastCollapsed, lastFocused, lastOrder) end
    end
    Evaluate(true)
    local poll = CreateFrame("Frame")
    poll:RegisterEvent("ENCOUNTER_START")
    poll:RegisterEvent("ENCOUNTER_END")
    poll:SetScript("OnEvent", function(_, event) otEncounter = (event == "ENCOUNTER_START") end)
    poll:SetScript("OnUpdate", function(self, elapsed)
        -- Every frame, the anchors only (cheap compares; a write only when Blizzard has re-laid out), so a
        -- Blizzard update is undone in the same or the next frame instead of showing for up to 0.1 s.
        if not IsEditModeActive() then Relayout(lastCollapsed, lastFocused, lastOrder) end
        self._t = (self._t or 0) + (elapsed or 0)
        if self._t < OT_POLL then return end
        sinceCollect = sinceCollect + self._t
        self._t = 0
        if sinceCollect >= 1 then sinceCollect = 0; Collect() end
        Evaluate(false)
    end)
end

-- Your buffs and debuffs by the minimap (v1.43.0, owner's request): BuffFrame and DebuffFrame
-- (Blizzard_BuffFrame/BuffFrame.xml:6, :87). Shown in combat like Action Bar 1 and the damage meter,
-- and on hover; hovering either shows both, as one group. Blizzard never sets either frame's own alpha,
-- only single aura buttons' (the expiry flash, BuffFrame.lua:956, :1045), which multiply under ours.
-- Poll only, no OnEnter hook: a right-click cancels a buff through a protected call (CancelUnitBuff,
-- BuffFrame.lua:868-877), so we stay off their scripts. External Defensives, at the top of the screen,
-- is not by the minimap and is left alone.
local function SetupAuraFade()
    local frames = { _G.BuffFrame, _G.DebuffFrame }
    local function Hovered()
        for _, f in ipairs(frames) do
            if f and f:IsVisible() and f:IsMouseOver() then return true end
        end
        return false
    end
    SetupLiveFade("fadeAuras", frames,
        function() return not db.fadeAuras or InCombatLockdown() or Hovered() end,
        true, Opacity("fadeAurasOpacity"))
end

-- The alert icons by the minimap (v1.44.0, owner's request): MinimapCluster.IndicatorFrame, the row
-- holding the mail icon and the crafting-order icon (Blizzard_Minimap Mainline/Minimap.xml:83-149).
-- Blizzard never sets that row's alpha (Minimap.lua). Quality of Life's Great Vault button follows the
-- row's effective alpha (QualityOfLife.lua, Great Vault), so it fades with it for free; hovering it
-- counts as hovering the row, read by its global name and simply absent when QoL is off. Poll only
-- and nothing written but alpha: MinimapCluster is an Edit Mode system frame (landmine 114).
local function SetupMinimapAlertsFade()
    local ind = _G.MinimapCluster and _G.MinimapCluster.IndicatorFrame
    if type(ind) ~= "table" or not ind.SetAlpha then return end
    local function VaultHovered()
        local v = _G.VUIQoLGreatVaultButton
        return v and v.IsVisible and v:IsVisible() and v:IsMouseOver() or false
    end
    SetupLiveFade("fadeMinimapAlerts", { ind },
        function() return not db.fadeMinimapAlerts or VaultHovered() end,
        true, Opacity("fadeMinimapAlertsOpacity"))
end

-- Fade Minimap Buttons (MINIMAP_BUTTONS above). Each picked piece gets its own live fade the first time
-- it is picked; unpicked later, its shouldShow holds it at full opacity. Shown while the mouse is on the
-- minimap or on any picked piece, so hovering one brings back all. Poll only (noEnterHook), as for the
-- alerts: every piece is a child of MinimapCluster, an Edit Mode system frame (landmine 114).
local function MinimapButtonsHovered()
    local m = _G.Minimap
    if m and m.IsMouseOver and m:IsMouseOver() then return true end
    for _, b in ipairs(MINIMAP_BUTTONS) do
        if db.fadeMinimapButtons[b.id] then
            for _, f in ipairs(b.frames() or {}) do
                if f and f.IsVisible and f:IsVisible() and f:IsMouseOver() then return true end
            end
        end
    end
    return false
end

local function SetupMinimapButtonsFade()
    for _, b in ipairs(MINIMAP_BUTTONS) do
        if db.fadeMinimapButtons[b.id] then
            local id = b.id
            SetupLiveFade("fadeMinimapButtons_" .. id, b.frames() or {},
                function() return not db.fadeMinimapButtons[id] or MinimapButtonsHovered() end,
                true, Opacity("fadeMinimapButtonsOpacity"))
        end
    end
end

-- The clock exists only once Blizzard_TimeManager loads. (Unavailable is declared further down, so
-- the check is spelled out here.)
local minimapLoader = CreateFrame("Frame")
minimapLoader:RegisterEvent("ADDON_LOADED")
minimapLoader:SetScript("OnEvent", function(_, _, name)
    if name ~= "Blizzard_TimeManager" or not (db and db.fadeMinimapButtons) then return end
    if VUI.OptionUnavailable and VUI.OptionUnavailable(ADDON_NAME, "fadeMinimapButtons") then return end
    SetupMinimapButtonsFade()
end)

-- Shown in full while the game puts vehicle or quest controls on it (v1.45.0, owner's request).
-- Blizzard swaps Action Bar 1's page to the vehicle, override or temporary-shapeshift bar when there
-- is one without its own art (ActionBarController_UpdateAll, Blizzard_ActionBarController
-- /ActionBarController.lua:153-165); with its own art it shows OverrideActionBar instead (:148-152),
-- which is never faded. The bonus bar (stances, cat form, stealth) is a class bar, not an event, and
-- is left out on purpose.
local function BarTakenOver()
    local ab = _G.C_ActionBar
    if not ab then return false end
    for _, fn in ipairs({ ab.HasVehicleActionBar, ab.HasOverrideActionBar, ab.HasTempShapeshiftActionBar }) do
        if fn then
            local ok, on = pcall(fn)
            if ok and on == true then return true end
        end
    end
    return false
end

local function SetupMainActionBarFade()
    -- No OnEnter hook on Action Bar 1 (see VUI.HookHoverFade): the poll alone reveals it.
    SetupLiveFade("fadeMainActionBar", { _G.MainActionBar },
        function()
            return not cdb.fadeMainActionBar or InCombatLockdown() or BarTakenOver()
                or (db.fadeMainActionBarShowFlying and _G.IsFlying and _G.IsFlying())
        end,
        true, Opacity("fadeActionBarsOpacity"))
end

-- ⚠ Fades the BARS inside the two containers, never the containers. Blizzard animates each
-- container's own alpha: FadeInAnimation (alpha 0 -> 1, setToFinalAlpha) is restarted by
-- StatusTrackingBarContainerMixin:FadeIn whenever a bar is shown and the container's alpha is below 1
-- (StatusTrackingManager.lua:238-259, StatusTrackingBar.xml:3-16). Faded at the container, the bar came
-- back after every /reload until first hovered (owner, test build 1), and would on any later FadeIn.
-- Blizzard never sets a bar's own alpha, so the bars are ours to fade. Hovering either container
-- shows every bar in both, as one strip.
-- The bar's outer frame art is NOT in the bar: it is the container's BarFrameTexture
-- (StatusTrackingBar.xml:5-7), so test build 2 faded the coloured bar and left the frame (owner). The
-- texture follows its container's SHOWN bar: every alpha we give that bar is copied to it (Blizzard
-- never sets that texture's alpha).
-- Shown for this long after a gain (sub-option fadeStatusBarsOnGain, owner's request 2026-10-31:
-- draw the eye to the bar, then fade it again). Gains, all read without their payloads:
--   reputation -- FACTION_STANDING_CHANGED, fires on every gain in the same frame as the chat line
--                 (measured 2026-10-24, QualityOfLife.lua Follow Reputation Gains);
--   watched faction changing -- UPDATE_FACTION with a new factionID (Track Latest Reputation
--                 switches after combat, outside the gain's window);
--   experience -- PLAYER_XP_UPDATE when UnitXP or UnitLevel went up (the event also fires on
--                 changes that are not gains, so the value is compared);
--   honor      -- HONOR_XP_UPDATE when UnitHonor went up (UnitDocumentation.lua).
local GAIN_SHOW_SECONDS = 3
local gainShownUntil = 0

local function SetupStatusBarFade()
    if liveFadeHooked.fadeStatusBars then return end   -- turned off and on again: already installed
    local containers = { _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer }
    local barOpacity = Opacity("fadeStatusBarsOpacity")
    local bars = {}
    local gainWatch = CreateFrame("Frame")
    gainWatch:RegisterEvent("FACTION_STANDING_CHANGED")
    -- A change of the WATCHED faction shows the bar too: Quality of Life's Track Latest Reputation
    -- defers its switch to the end of combat (QualityOfLife.lua RepFollowOnEvent), long after the
    -- gain's 3 s, and the owner switched factions and saw nothing (test build 9).
    gainWatch:RegisterEvent("UPDATE_FACTION")
    gainWatch:RegisterEvent("PLAYER_XP_UPDATE")
    gainWatch:RegisterEvent("HONOR_XP_UPDATE")
    local function Num(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if not ok or type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
        return v
    end
    local lastXP, lastLevel = Num(_G.UnitXP, "player"), Num(_G.UnitLevel, "player")
    local lastHonor = Num(_G.UnitHonor, "player")
    local function WatchedID()
        local ns = _G.C_Reputation
        if not (ns and ns.GetWatchedFactionData) then return nil end
        local ok, data = pcall(ns.GetWatchedFactionData)
        local id = ok and data and data.factionID
        if id == nil or (issecretvalue and issecretvalue(id)) then return nil end
        return id
    end
    local lastWatched = WatchedID()
    local Revealed
    gainWatch:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_FACTION" then
            local id = WatchedID()
            local changed = id and lastWatched and id ~= lastWatched
            if id then lastWatched = id end
            if not changed then return end
        elseif event == "PLAYER_XP_UPDATE" then
            local xp, level = Num(_G.UnitXP, "player"), Num(_G.UnitLevel, "player")
            local gained = (xp and lastXP and xp > lastXP) or (level and lastLevel and level > lastLevel)
            lastXP, lastLevel = xp or lastXP, level or lastLevel
            if not gained then return end
        elseif event == "HONOR_XP_UPDATE" then
            local honor = Num(_G.UnitHonor, "player")
            local gained = honor and lastHonor and honor > lastHonor
            lastHonor = honor or lastHonor
            if not gained then return end
        end
        -- The bar starts to fade 3 s after the gain: the hover fade's own leave delay (Fade Delay
        -- slider, at least 0.15 s) comes after this window, so it is taken off here (owner: it
        -- lingered ~5 s with the plain 3 s window).
        local delay = math.max(0.15, (VUI.GetFadeDelay and VUI.GetFadeDelay()) or 0)
        if db.fadeStatusBarsOnGain then
            gainShownUntil = GetTime() + math.max(0.5, GAIN_SHOW_SECONDS - delay)
        end
    end)
    function Revealed()
        if not db.fadeStatusBars then return true end
        if db.fadeStatusBarsOnGain and GetTime() < gainShownUntil then return true end
        for _, c in ipairs(containers) do
            if c and c:IsVisible() and c:IsMouseOver() then return true end
        end
        return false
    end
    for _, c in ipairs(containers) do
        local art = c and c.BarFrameTexture
        for _, bar in pairs(c and c.bars or {}) do
            bars[#bars + 1] = bar
            if art then
                hooksecurefunc(bar, "SetAlpha", function(self, a)
                    if self:IsShown() and art.SetAlpha then art:SetAlpha(a) end
                end)
            end
        end
    end

    -- ⚠ ROOT CAUSE (measured 2026-10-31, owner's test builds 4-7): Blizzard's holder starts at alpha 0
    -- (StatusTrackingBar.xml:3) and fades itself in with FadeInAnimation whenever it is below 1 and a
    -- bar is shown (StatusTrackingManager.lua:238-259). At login that animation is queued during the
    -- loading screen; on its first frame the bar and frame art inside went from 0 to 1 with no SetAlpha
    -- call (probe: "JUMP ... fadeIn true", first frame after LOADING_SCREEN_DISABLED). So while the bars
    -- are faded we never let that fade-in run: stop it and put the holder at the alpha it would end on
    -- (1), then the bars and art at the faded opacity -- all in the same call, so nothing is drawn in between.
    -- Blizzard's FadeIn returns early once the holder is at 1 (:249), so it is not started again until
    -- a bar change. Stop() writes no Lua state (the group has no OnStop script), so this taints nothing;
    -- Blizzard re-runs UpdateBarsShown on its next event, which is what its OnFinished would have led to.
    local function Settle(c)
        local fadeIn = c and c.FadeInAnimation
        if type(fadeIn) ~= "table" or not db.fadeStatusBars or Revealed() then return end
        if fadeIn:IsPlaying() then fadeIn:Stop() end
        if c.GetShownBar and c:GetShownBar() then
            c:SetAlpha(1)
            local a = VUI.FadedAlpha(barOpacity)
            for _, bar in pairs(c.bars or {}) do bar:SetAlpha(a) end
            if c.BarFrameTexture then c.BarFrameTexture:SetAlpha(a) end
        end
    end
    for _, c in ipairs(containers) do
        if c and c.FadeIn then hooksecurefunc(c, "FadeIn", Settle) end
    end

    -- No OnEnter hook (audit C1, 2026-11-01): the bars are inside Edit Mode's status-bar system, where
    -- a HookScript tainted Edit Mode once already (landmine 114). Revealed() already sees the hover.
    SetupLiveFade("fadeStatusBars", bars, Revealed, true, barOpacity)
    if db.fadeStatusBars then
        for _, c in ipairs(containers) do
            if c and c.BarFrameTexture then c.BarFrameTexture:SetAlpha(VUI.FadedAlpha(barOpacity)) end
            Settle(c)
        end
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

-- An option another addon has taken over (VUI.SetOptionUnavailable). Nothing takes a Clean Solo
-- option today: the caller was VeritasUI_ElvUI (retired), kept for a possible revival. Its feature
-- is skipped at login and its control is greyed out with the reason added to the tooltip; the
-- saved value is left alone.
local function Unavailable(key)
    return VUI.OptionUnavailable and VUI.OptionUnavailable(ADDON_NAME, key) or nil
end

local function TipWithReason(tip, key)
    local reason = Unavailable(key)
    if type(reason) ~= "string" then return tip end
    return tip .. "\n\n" .. VUI.COL.RED .. reason .. "|r"
end

local function GreyIfUnavailable(initializer, key)
    if Unavailable(key) and initializer and initializer.AddModifyPredicate then
        initializer:AddModifyPredicate(function() return false end)
    end
end

local function InitializeOptions()
    local category, layout = VUI.RegisterSettingsCategory(SETTINGS_LABEL)

    -- Every Clean Solo dropdown is drawn by Lib's cover dropdown (v1.59.0, VeritasUI_Lib/SettingsCoverDropdown.lua):
    -- no Blizzard dropdown row on the page, because a Blizzard dropdown row filled in with our data is reused by
    -- Blizzard's own pages and taints them (Options > Social's IsUserOAuthed blocked). Blizzard's own dropdown
    -- only if Lib is older than this module. `opts` = { unavailableKey, sub, isEnabled }.
    local function Dropdown(setting, name, getOptions, tip, opts)
        opts = opts or {}
        if VUI.AddCoverDropdown then
            local key, parentOn = opts.unavailableKey, opts.isEnabled
            return VUI.AddCoverDropdown(layout, { category = category, setting = setting, name = name,
                getOptions = getOptions, tooltip = TipWithReason(tip, key), sub = opts.sub,
                isEnabled = function()
                    if key and Unavailable(key) then return false end
                    return not parentOn or parentOn()
                end })
        end
        local init = Settings.CreateDropdown(category, setting, getOptions, TipWithReason(tip, opts.unavailableKey))
        GreyIfUnavailable(init, opts.unavailableKey)
        return init
    end

    -- Two groups under section headers, the way Blizzard's own Options pages are laid out
    -- (layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(...)),
    -- Blizzard_SettingsDefinitions_Frame/Interface.lua:18). Owner's request, 2026-10-29: fades
    -- and hides were interleaved. Order is presentation only; every key is unchanged.
    local function Header(name)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
        end
    end

    local BuildTrackerSectionOptions   -- defined below, called from AddCheckboxes
    local BuildMinimapButtonsDropdown  -- likewise
    local FADE_OPTIONS = {
        { key = "fadeChatTabs",        name = "Fade Chat Window",
          tip = "The chat window's background, its tabs and the chat buttons you haven't hidden "
             .. "fade out when you're not using chat, and come back when you mouse over it. The "
             .. "messages stay readable. With Chat Style set to IM, the box you type in fades too. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply.",
          opacity = "fadeChatTabsOpacity",
          opacityApply = function() if chatTabsApplyOpacity then chatTabsApplyOpacity() end end },
        { key = "fadeMicroMenu",       name = "Fade Micro Menu",
          tip = "The bottom-right menu bar fades out unless moused over. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply.",
          opacity = "fadeMicroMenuOpacity" },
        { key = "fadePlayerFrame",     name = "Fade Player Frame",
          tip = "Your player frame fades out when idle and reappears in combat, when damaged, or on mouseover. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply.",
          opacity = "fadePlayerFrameOpacity" },
        { key = "fadeAuras",           name = "Fade Buffs and Debuffs",
          tip = "Your buffs and debuffs by the minimap fade out unless you're in combat or mousing "
             .. "over them. Applies at once.",
          apply = function(value) if value then SetupAuraFade() end end,
          opacity = "fadeAurasOpacity" },
        { key = "fadeMinimapAlerts",   name = "Fade Minimap Alerts",
          tip = "The mail and crafting order icons by the minimap, and the Great Vault button, fade "
             .. "out unless you're mousing over them. Applies at once.",
          apply = function(value) if value then SetupMinimapAlertsFade() end end,
          opacity = "fadeMinimapAlertsOpacity" },
        -- v1.60.0: a tick-box dropdown + its own opacity slider (BuildMinimapButtonsDropdown below).
        -- Replaces Hide Minimap Buttons. Applies at once.
        { key = "fadeMinimapButtons", build = function() BuildMinimapButtonsDropdown() end },
        { key = "fadeDamageMeter",     name = "Fade Damage Meter",
          tip = "The damage meter fades out unless you're in combat or mousing over it. Applies at once.",
          apply = function(value) if value then SetupDamageMeterFade() end end,
          opacity = "fadeDamageMeterOpacity" },
        { key = "fadeObjectiveTracker", name = "Fade Objective Tracker",
          tip = "The All Objectives tracker fades out unless you're mousing over it; each section fades to "
             .. "its own opacity, set below. Applies at once.",
          apply = function(value) if value then SetupObjectiveTrackerFade() end end },
        -- v1.51.0: In Raids + one opacity slider per section, indented under it (built below).
        { key = "fadeObjectiveTrackerRaid", build = function() BuildTrackerSectionOptions() end },
        { key = "fadeStatusBars",      name = "Fade Reputation and Experience Bars",
          tip = "The reputation, experience and honor bars fade out unless you're mousing over them. "
             .. "Applies at once.",
          apply = function(value) if value then SetupStatusBarFade() end end,
          opacity = "fadeStatusBarsOpacity" },
        { key = "fadeStatusBarsOnGain", name = "Show on Gains", parent = "fadeStatusBars",
          tip = "The bars appear for 3 seconds when you gain reputation, experience or honor, or "
             .. "your tracked reputation changes, then fade again. Applies at once.",
          apply = function() end },
        { key = "fadeMainActionBar",   name = "Fade Main Action Bar",
          tip = "Action Bar 1 fades out unless you're in combat or mousing over it. It is shown in full "
             .. "while it holds vehicle or quest controls. Applies at once.",
          apply = function(value) if value then SetupMainActionBarFade() end end,
          opacity = "fadeActionBarsOpacity",
          opacityTip = " Also sets how faded the bars picked in Fade Action Bars get." },
        { key = "fadeMainActionBarShowFlying", name = "Show While Flying", parent = "fadeMainActionBar",
          tip = "Action Bar 1 is shown in full while you fly. Turn it off and it stays faded in flight, "
             .. "like any other time out of combat. Applies at once.",
          apply = function() end },
    }
    local BuildTopBannersDropdown   -- defined after the Fade section, called from AddCheckboxes
    local BuildTransformsDropdown   -- likewise
    local HIDE_OPTIONS = {
        { key = "hideSocialButton",    name = "Hide Social Button",
          tip = "Hides the Quick Join / Communities toast button. Left shown, it fades with the "
             .. "chat window while Fade Chat Window is on. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        { key = "hideChatButtons",     name = "Hide Chat Buttons",
          tip = "Hides the chat menu button (the speech bubble beside the chat window). Left "
             .. "shown, it fades with the chat window while Fade Chat Window is on. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        { key = "hideVoiceChatButton", name = "Hide Voice Chat Button",
          tip = "Hides the voice and channels button beside the chat window, and the mute and "
             .. "deafen buttons shown while you are in a voice channel. Left shown, they fade with "
             .. "the chat window while Fade Chat Window is on. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        { key = "hideBagButtons",      name = "Hide Bag Buttons",
          tip = "Hides the bag bar buttons. You can still open bags with B. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        { key = "hideMacroNames",      name = "Hide Macro Names",
          tip = "Hides the macro name text displayed on action bar buttons. "
             .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        { key = "hideTalkingHead",     name = "Hide Talking Head",
          tip = "Hides the NPC portrait that pops up with story dialogue in quests and dungeons. "
             .. "The voice still plays unless Mute Talking Head Voice is on. Still shown in Edit "
             .. "Mode so you can place it. Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        { key = "muteTalkingHead",     name = "Mute Talking Head Voice",
          tip = "Silences the voice line that plays with the talking head popup. The popup itself "
             .. "still shows unless Hide Talking Head is on. Requires " .. VUI.COL.YELLOW .. "/reload|r to apply." },
        -- v1.48.0: a tick-box dropdown, built where the checkbox was (BuildTopBannersDropdown below).
        { key = "hideTopBanners", build = function() BuildTopBannersDropdown() end },
        -- v1.49.0: Hide Transforms, a tick-box dropdown (BuildTransformsDropdown below).
        { key = "hideProfessionGear", build = function() BuildTransformsDropdown() end },
    }

    -- ⚠ THESE CHECKBOXES ARE MIXED-SCOPE. All the keys but one are account-wide and one
    -- (fadePlayerFrame) is per-character, so the table handed to Settings AND the table the
    -- default is read from must both be resolved PER KEY. Passing one table for all of them -- which
    -- is what this did before v1.14.4 -- would store fadePlayerFrame at account scope, and the
    -- panel would then read and write a value the runtime code never looks at. Blizzard captures
    -- the table by reference (Blizzard_Setting.lua:420), so getting this wrong stays invisible
    -- until a setting fails to persist or leaks across characters.
    local inits = {}

    -- ── Faded opacity: a slider beside a Fade checkbox (v1.40.0, owner's request) ──
    -- Blizzard's own checkbox + slider row, the one Options > Audio > Ping Sounds uses: the slider
    -- sits right of the checkbox and is greyed while it is off (CreateSettingsCheckboxSliderInitializer
    -- and SettingsCheckboxSliderControlMixin:EvaluateState, Blizzard_SettingControls.lua:1271-1320;
    -- 0-1 in 0.05 steps shown as a percentage, Mainline/AudioOverrides.lua:11-21). The faders read
    -- the value each time they fade, so it applies at once. Without that template the checkbox is
    -- plain and the value stays at its default.
    local OPACITY_TIP = "How much of it still shows while faded. At 0% it is hidden completely. "
        .. "Applies at once."
    local function OpacitySliderOptions()
        local o = Settings.CreateSliderOptions(0, 1, 0.05)
        local right = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
            and MinimalSliderWithSteppersMixin.Label.Right
        if right and o.SetLabelFormatter then
            o:SetLabelFormatter(right, function(value)
                if FormatPercentage then return FormatPercentage(value, true) end
                return string.format("%d%%", math.floor(value * 100 + 0.5))
            end)
        end
        return o
    end
    -- ⚠ Built with Settings.CreateSettingInitializer, NOT CreateSettingsCheckboxSliderInitializer (owner's repro,
    -- 2026-11-03: Options search "fade" -> Nameplates > Style -> Social popup, "VeritasUI_CleanSolo"). That helper
    -- is the same data + template, then initializer:AddSearchTags(cbLabel, sliderLabel) in the CALLER's execution
    -- (Blizzard_SettingControls.lua:1305-1323), so from addon code the tags are written tainted, and every search
    -- reads every initializer's tags (Blizzard_SettingsPanel.lua:575-610). Putting the checkbox setting in
    -- data.setting lets Blizzard's secure handler add its name as the tag instead (Blizzard_SettingsInbound.lua:
    -- 229-238). Cost: the row is found by its name, not by "Faded Opacity". data.setting also lets sub-options grey
    -- at once when it is ticked (SettingsListElementMixin:Init, Blizzard_SettingControls.lua:309-315).
    local function CreateCheckboxRow(opt, setting)
        local canPair = opt.opacity and Settings.CreateSettingInitializer
            and layout and layout.AddInitializer
        if not canPair then
            return Settings.CreateCheckbox(category, setting, TipWithReason(opt.tip, opt.key))
        end
        local slider = Settings.RegisterAddOnSetting(
            category,
            ADDON_NAME .. "_" .. opt.opacity,
            opt.opacity,
            db,                          -- UNIVERSAL: every opacity key
            "number",
            opt.name .. " Opacity",
            UNIVERSAL[opt.opacity]
        )
        if opt.opacityApply then
            slider:SetValueChangedCallback(function(_, value) opt.opacityApply(value) end)
        end
        local tip = TipWithReason(opt.tip, opt.key)
        local init = Settings.CreateSettingInitializer("SettingsCheckboxSliderControlTemplate", {
            name = opt.name, tooltip = tip, setting = setting,
            cbSetting = setting, cbLabel = opt.name, cbTooltip = tip,
            sliderSetting = slider, sliderOptions = OpacitySliderOptions(), sliderLabel = "Faded Opacity",
            sliderTooltip = OPACITY_TIP .. (opt.opacityTip or ""),
        })
        layout:AddInitializer(init)
        return init
    end
    local function AddCheckboxes(list)
        for _, opt in ipairs(list) do
          if opt.build then opt.build() else
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
                -- An option with `apply` takes effect at once instead of after a /reload, and
                -- says so: no "/reload to apply" for it (audit C2).
                local printer = opt.apply and VUI.PrintOnOffLive or VUI.PrintOnOff
                printer("Clean Solo", opt.name, value)
                if opt.apply and not Unavailable(opt.key) then opt.apply(value) end
            end)
            local init = CreateCheckboxRow(opt, setting)
            GreyIfUnavailable(init, opt.key)
            inits[opt.key] = init
            -- A refinement is a sub-option: indented under its parent and greyed while the parent is
            -- off. VUI.SettingsSubOption, NOT SetParentInitializer: Options search reads a matched row's
            -- parentInitializer, and written from our code that taints the search (SettingsCoverDropdown.lua).
            local parentInit = opt.parent and inits[opt.parent]
            if parentInit and VUI.SettingsSubOption then
                local parentOwner = PERCHAR[opt.parent] ~= nil and cdb or db
                VUI.SettingsSubOption(init, ADDON_NAME .. "_" .. opt.parent,
                    function() return parentOwner[opt.parent] end)
            end
          end
        end
    end

    -- ── Tick-box dropdowns: None, All, then the kinds (owner's standard, 2026-11-01: every dropdown
    -- of choices has None and All, as Hide Error Text does). Blizzard's Settings dropdown with check
    -- boxes (Settings.CreateControlTextContainer():AddCheckbox) over a number setting whose bits are
    -- the rows: 1 None, 2 All, 3.. the kinds. The truth is spec.truth ([kind id] = true); the mask is
    -- derived from it at every login and every change and only feeds the control. None and All are
    -- not stored: None is ticked when no kind is, All when every kind is. While All is ticked the kind
    -- rows drop their bar text, so the closed box reads "All", not every name (a nil `text` adds
    -- nothing to the bar, MenuTemplates.lua:775-791). Hide Error Text keeps its own code: its All is
    -- an override that also hides messages outside its groups.
    --   spec = { setting, maskKey, owner (table holding the mask), setMask(v), name,
    --            items = { {id, label} }, truth (table), defaultIds, tip, unavailableKey, onItem(item, on),
    --            onChanged() }
    -- setMask writes the mask through a literal `db.`/`cdb.` access so scope_map_test can see the key.
    local KD_NONE, KD_ALL, KD_FIRST = 1, 2, 3
    local function KindsDropdown(spec)
        local items, truth = spec.items, spec.truth
        local maxBit = KD_FIRST + #items - 1
        local function MaskOf(isOn)
            local mask, n = 0, 0
            for i, it in ipairs(items) do
                if isOn(it.id) then mask = mask + Bit(KD_FIRST + i - 1); n = n + 1 end
            end
            if n == 0 then return Bit(KD_NONE) end
            if n == #items then mask = mask + Bit(KD_ALL) end
            return mask
        end
        local function Mask() return MaskOf(function(id) return truth[id] end) end
        local defaults = {}
        for _, id in ipairs(spec.defaultIds or {}) do defaults[id] = true end

        local lastMask = Mask()
        spec.setMask(lastMask)
        local setting = Settings.RegisterAddOnSetting(category, spec.setting, spec.maskKey, spec.owner,
            "number", spec.name, MaskOf(function(id) return defaults[id] end))
        local ignore = false
        local function GetOptions()
            local all = true
            for _, it in ipairs(items) do if not truth[it.id] then all = false end end
            local container = Settings.CreateControlTextContainer()
            container:AddCheckbox(KD_NONE, "None")
            container:AddCheckbox(KD_ALL, "All", spec.allTip)
            -- Each row's own tooltip (third argument): Blizzard's dropdown tooltip lists every option as
            -- its name in white and its text in gold, a blank line apart (Settings.CreateOptionsInitTooltip,
            -- Blizzard_Settings.lua:415-460), as Options > Controls > Camera Following Style does.
            for i, it in ipairs(items) do
                local row = container:AddCheckbox(KD_FIRST + i - 1, it.label, it.tip)
                if all and type(row) == "table" then row.text = nil end
            end
            return container:GetData()
        end
        local function SetAll(on)
            for _, it in ipairs(items) do truth[it.id] = on or nil end
        end
        setting:SetValueChangedCallback(function(_, val)
            if ignore or type(val) ~= "number" then return end
            local changed = ChangedBits(lastMask, val, maxBit)
            if #changed == 1 then
                local v, on = changed[1], HasBit(val, changed[1])
                if v == KD_NONE then
                    if on then SetAll(false) end         -- unticking None alone changes nothing
                elseif v == KD_ALL then
                    SetAll(on)
                else
                    local it = items[v - KD_FIRST + 1]
                    truth[it.id] = on or nil
                    if spec.onItem then spec.onItem(it, on) end
                end
            elseif #changed > 1 then                     -- e.g. the Defaults button
                for i, it in ipairs(items) do truth[it.id] = HasBit(val, KD_FIRST + i - 1) or nil end
            end
            lastMask = Mask()
            spec.setMask(lastMask)
            ignore = true
            pcall(setting.SetValue, setting, lastMask)
            ignore = false
            if spec.onChanged then spec.onChanged() end
        end)
        return Dropdown(setting, spec.name, GetOptions, spec.tip, { unavailableKey = spec.unavailableKey })
    end

    -- ── Fade Objective Tracker's sub-options (v1.51.0): In Raids, then a faded-opacity slider for each
    -- section, all indented under Fade Objective Tracker and greyed while it is off (VUI.SettingsSubOption, not
    -- SetParentInitializer: see AddCheckboxes). Every value is read by the tracker's poll, so all apply at once.
    function BuildTrackerSectionOptions()
        local parentInit = inits.fadeObjectiveTracker
        local function Under(init)
            if parentInit and init and VUI.SettingsSubOption then
                VUI.SettingsSubOption(init, ADDON_NAME .. "_fadeObjectiveTracker",
                    function() return db.fadeObjectiveTracker end)
            end
        end
        local raidSetting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_fadeObjectiveTrackerRaid",
            "fadeObjectiveTrackerRaid", db, "string", "In Raids", UNIVERSAL.fadeObjectiveTrackerRaid)
        local function RaidOptions()
            local c = Settings.CreateControlTextContainer()
            c:Add("normal", "Normal", "The tracker fades as set above.")
            c:Add("raid", "Hide in Raids", "The whole tracker is hidden inside a raid.")
            c:Add("boss", "Hide During Boss Fights", "Hidden inside a raid only while a boss fight is on.")
            return c:GetData()
        end
        local raidTip = "What the tracker does in a raid. Hovering still shows it, and a hidden quest item button "
            .. "can still be clicked. Applies at once."
        if VUI.AddCoverDropdown then
            Dropdown(raidSetting, "In Raids", RaidOptions, raidTip,
                { sub = true, isEnabled = function() return db.fadeObjectiveTracker end })
        else
            Under(Settings.CreateDropdown(category, raidSetting, RaidOptions, raidTip))
        end
        for _, sec in ipairs(OT_SECTIONS) do
            local key = "otOpacity_" .. sec.id
            local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db,
                "number", sec.label, UNIVERSAL[key])
            Under(Settings.CreateSlider(category, setting, OpacitySliderOptions(),
                "How much of the " .. sec.label .. " section still shows while the tracker is faded. At 0% it "
                .. "is hidden and the sections below move up into its place. Applies at once."))
        end
    end

    -- ── Fade Minimap Buttons — tick-box dropdown, UNIVERSAL (mask paired with fadeMinimapButtons), then
    -- its faded-opacity slider, indented under it and greyed while nothing is picked. The dropdown goes
    -- through KindsDropdown -> Dropdown() -> Lib's cover dropdown (v1.59.0); the slider is linked with
    -- VUI.SettingsSubOption, re-checked whenever the dropdown's mask setting changes -- never
    -- SetParentInitializer (Options search reads it: the Social taint, landmine 149).
    function BuildMinimapButtonsDropdown()
        local init = KindsDropdown({
            setting = ADDON_NAME .. "_fadeMinimapButtons", maskKey = "fadeMinimapButtonsMask",
            owner = db,              -- UNIVERSAL: paired with fadeMinimapButtons
            setMask = function(v) db.fadeMinimapButtonsMask = v end,
            name = "Fade Minimap Buttons", items = MINIMAP_BUTTONS, truth = db.fadeMinimapButtons,
            unavailableKey = "fadeMinimapButtons",
            tip = "Pick the buttons and labels around the minimap to fade out. Mouse over the minimap and "
               .. "they all come back; a faded one can still be clicked. Applies at once.",
            onChanged = function()
                if not Unavailable("fadeMinimapButtons") then SetupMinimapButtonsFade() end
            end,
        })
        local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_fadeMinimapButtonsOpacity",
            "fadeMinimapButtonsOpacity", db, "number", "Faded Opacity", UNIVERSAL.fadeMinimapButtonsOpacity)
        local slider = Settings.CreateSlider(category, setting, OpacitySliderOptions(),
            "How much of the picked minimap buttons still shows while faded. At 0% they are hidden "
            .. "until you mouse over the minimap. Applies at once.")
        GreyIfUnavailable(slider, "fadeMinimapButtons")
        if init and slider and VUI.SettingsSubOption then
            VUI.SettingsSubOption(slider, ADDON_NAME .. "_fadeMinimapButtons",
                function() return next(db.fadeMinimapButtons) ~= nil end)
        end
    end

    Header("Fade")
    AddCheckboxes(FADE_OPTIONS)

    -- ── Fade Action Bars — tick-box dropdown, PER-CHARACTER (mask paired with fadeActionBars).
    cdb.fadeActionBars[1] = nil  -- Bar 1 is Blizzard-protected
    cdb.fadeActionBarsLabel = nil  -- RETIRED v1.21.0: the old display string, now the mask
    local barItems = {}
    for i = 2, 8 do barItems[#barItems + 1] = { id = i, label = ACTION_BAR_LABELS[i] } end
    KindsDropdown({
        setting = ADDON_NAME .. "_fadeActionBars", maskKey = "fadeActionBarsMask",
        owner = cdb,                 -- PER-CHARACTER: paired with fadeActionBars
        setMask = function(v) cdb.fadeActionBarsMask = v end,
        name = "Fade Action Bars", items = barItems, truth = cdb.fadeActionBars,
        unavailableKey = "fadeActionBars",
        tip = "Pick a bar to fade it out when idle; it reappears on mouseover. How faded it gets is set "
           .. "by the slider beside Fade Main Action Bar. Requires " .. VUI.COL.YELLOW .. "/reload|r to apply.",
        onItem = function(it, on)
            VUI.Print("Clean Solo", it.label .. " fade " .. (on and "enabled" or "disabled")
                .. " — " .. VUI.COL.YELLOW .. "/reload|r to apply.")
        end,
    })

    -- ── Fade Delay — slider, UNIVERSAL. Applies at once (as does Hide Profession Gear): it is a
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
        "How long a faded element stays visible after you move the mouse away, before it fades: "
        .. "every Fade option above. 0 keeps the usual short delay. The chat window and its tabs "
        .. "keep Blizzard's own timing. Applies at once.", "fadeDelay"))
    GreyIfUnavailable(delayInit, "fadeDelay")


    -- ── Hide Top Banners — tick-box dropdown, UNIVERSAL (mask paired with hideTopBannerTypes, both on
    -- db). The Fade Action Bars pattern: a None row, then one row per TOP_BANNER_GROUPS entry; the
    -- table is the truth and the mask is derived from it on every login and every change.
    function BuildTopBannersDropdown()
        KindsDropdown({
            setting = ADDON_NAME .. "_hideTopBanners", maskKey = "hideTopBannersMask",
            owner = db,              -- UNIVERSAL: paired with hideTopBannerTypes
            setMask = function(v) db.hideTopBannersMask = v end,
            name = "Hide Top Banners", items = TOP_BANNER_GROUPS, truth = db.hideTopBannerTypes,
            unavailableKey = "hideTopBanners",
            tip = "Pick the big messages at the top of the screen to stop. The rest still show. "
               .. "Requires " .. VUI.COL.YELLOW .. "/reload|r to apply.",
            onItem = function(g, on)
                VUI.Print("Clean Solo", "Hide Top Banners: " .. g.label .. " "
                    .. (on and "hidden" or "shown") .. " — " .. VUI.COL.YELLOW .. "/reload|r to apply.")
            end,
        })
    end


    -- ── Hide Transforms — tick-box dropdown, UNIVERSAL (mask paired with hideTransformTypes). Applies at
    -- once: SetHideTransforms only changes which aura IDs the UNIT_AURA handler removes.
    function BuildTransformsDropdown()
        KindsDropdown({
            setting = ADDON_NAME .. "_hideTransforms", maskKey = "hideTransformsMask",
            owner = db,              -- UNIVERSAL: paired with hideTransformTypes
            setMask = function(v) db.hideTransformsMask = v end,
            name = "Hide Transforms", items = TRANSFORM_KINDS, truth = db.hideTransformTypes,
            defaultIds = { "professions" },          -- as UNIVERSAL.hideTransformTypes
            unavailableKey = "hideProfessionGear",
            tip = "Pick the costumes and transformations to take off you as soon as they land, so your own "
               .. "look stays. Not during combat; anything that lands in combat comes off when it ends. "
               .. "Applies at once.",
            onItem = function(k, on)
                VUI.Print("Clean Solo", "Hide Transforms: " .. k.label .. " "
                    .. (on and "taken off" or "left on") .. ".")
            end,
            onChanged = function()
                if not Unavailable("hideProfessionGear") then SetHideTransforms() end
            end,
        })
    end

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
        container:AddCheckbox(ERR_ALL, "All", "Every error message.")
        for i, g in ipairs(ERROR_TYPE_GROUPS) do
            local row = container:AddCheckbox(ERR_FIRST_GROUP + i - 1, g.label, g.tip)
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
                .. " — " .. VUI.COL.YELLOW .. "/reload|r to apply.")
        end
        db.hideErrorTypesMask = ErrorTypesMask()
        lastErrMask = db.hideErrorTypesMask
        ignoreErrCallback = true
        pcall(errSetting.SetValue, errSetting, db.hideErrorTypesMask)
        ignoreErrCallback = false
    end)

    Dropdown(errSetting, "Hide Error Text", GetErrorTypeOptions,
        "Pick the kinds of red error message to hide, and the spoken lines that go with them; the rest "
        .. "still show. Requires " .. VUI.COL.YELLOW .. "/reload|r to apply.")

    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

-- ── Events ──────────────────────────────────────────────────
-- Player frame: no flash on login (owner, 2026-11-03). The frame shows for 3 s after any player UNIT_HEALTH /
-- UNIT_MAXHEALTH (Lib HookPlayerFrameFade, HEALTH_IDLE_TIME: health is a Secret Value, so a recent event is
-- the only sign of damage or regen). MEASURED (`/cs login`, a fresh login that flashed): UNIT_MAXHEALTH x2 at
-- +0.6 s and UNIT_HEALTH at +2.1 s after PLAYER_ENTERING_WORLD, the moment the loading screen lifted; the frame
-- rose at +2.5 s and faded from +6.1 s. Another login got none, so the flash was intermittent. So health events
-- are ignored from load until LOGIN_HEALTH_QUIET after the session's first loading screen lifts
-- (LOADING_SCREEN_DISABLED), with PEW + LOGIN_HEALTH_FALLBACK as a backstop. Combat and hover still show it,
-- and regen ticks after the window still count. Zone changes open no window.
-- ⛔ TEST BUILD PROBE: `loginProbe` + `/cs login` record what happened. Delete before release.
local LOGIN_HEALTH_QUIET, LOGIN_HEALTH_FALLBACK = 2, 8
local healthQuietUntil, loadingDone = math.huge, false
local pewAt
local loginProbe = { rows = {} }
local function ProbeRow(what)
    local rows = loginProbe.rows
    if #rows < 60 then rows[#rows + 1] = { pewAt and (GetTime() - pewAt) or nil, what } end
end
local probeDriver
local last = {}
local function ProbeSample()
    local pf = _G.PlayerFrame
    if type(pf) ~= "table" then return end
    local c = pf.PlayerFrameContainer
    local portrait = type(c) == "table" and c.PlayerPortrait or nil
    if type(portrait) ~= "table" then portrait = nil end
    local now = {
        frame = string.format("%.2f", pf:GetAlpha()),
        shown = tostring(pf:IsShown()),
        portrait = portrait and string.format("%.2f", portrait:GetAlpha()) or "-",
        ignoresParent = portrait and portrait.IsIgnoringParentAlpha
            and tostring(portrait:IsIgnoringParentAlpha()) or "-",
        combat = tostring(InCombatLockdown() and true or false),
        mouse = tostring(pf:IsMouseOver() and true or false),
    }
    for _, k in ipairs({ "frame", "shown", "portrait", "ignoresParent", "combat", "mouse" }) do
        if now[k] ~= last[k] then ProbeRow(k .. " = " .. now[k]); last[k] = now[k] end
    end
end
-- Started at the end of PLAYER_LOGIN (after every fade is set up), so it is the last OnUpdate frame made.
local function StartLoginProbe()
    if probeDriver then return end
    probeDriver = CreateFrame("Frame")
    probeDriver.vuiLoginProbe = true
    probeDriver:SetScript("OnUpdate", function(self)
        if pewAt and GetTime() - pewAt > 15 then self:SetScript("OnUpdate", nil); return end
        pcall(ProbeSample)
    end)
end
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LOADING_SCREEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, arg1, ...)
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

        -- v1.48.0: the old Hide Top Banners checkbox becomes every row of its dropdown. Before
        -- InitializeOptions, which derives the dropdown's value from the table.
        if db.hideTopBanners == true and next(db.hideTopBannerTypes) == nil then
            for _, g in ipairs(TOP_BANNER_GROUPS) do db.hideTopBannerTypes[g.id] = true end
        end
        db.hideTopBanners = nil
        -- v1.51.0: the single tracker opacity becomes every non-event section's own.
        if db.fadeObjectiveTrackerOpacity ~= nil then
            for _, sec in ipairs(OT_SECTIONS) do
                if not sec.full then db["otOpacity_" .. sec.id] = db.fadeObjectiveTrackerOpacity end
            end
            db.fadeObjectiveTrackerOpacity = nil
        end
        -- v1.49.0: Hide Profession Gear becomes the Profession Gear row of Hide Transforms.
        if db.hideProfessionGear ~= nil then
            db.hideTransformTypes.professions = (db.hideProfessionGear == true) or nil
            db.hideProfessionGear = nil
        end
        -- v1.60.0: Hide Minimap Buttons becomes Fade Minimap Buttons at 0%, so each piece looks as it did
        -- and now comes back on hover. Only into an empty choice, so it runs once.
        if type(db.hideMinimapButtons) == "table" then
            if next(db.fadeMinimapButtons) == nil and next(db.hideMinimapButtons) ~= nil then
                for id, on in pairs(db.hideMinimapButtons) do db.fadeMinimapButtons[id] = on or nil end
                db.fadeMinimapButtonsOpacity = 0
            end
        end
        db.hideMinimapButtons, db.hideMinimapButtonsMask = nil, nil
        InitializeOptions()
        -- Before any fader runs, so the first fade of the session already uses it.
        if VUI.SetFadeDelay then VUI.SetFadeDelay(db.fadeDelay) end
        if db.hideSocialButton and not Unavailable("hideSocialButton") then HideSocialButton() end
        if db.fadeChatTabs      and not Unavailable("fadeChatTabs")      then SetupChatTabFading()  end
        -- RETIRED v1.41.0: folded into Fade Chat Window (0% = transparent). Cleared from the
        -- character slot too, where per-character builds before v1.14.4 could have left it.
        db.transparentChatBG = nil
        if cdb then cdb.transparentChatBG = nil end
        if db.hideChatButtons and not Unavailable("hideChatButtons") then HideChatButtons() end
        if db.hideVoiceChatButton and not Unavailable("hideVoiceChatButton") then HideVoiceChatButton() end
        if db.fadeMicroMenu    and not Unavailable("fadeMicroMenu")    then SetupMicroMenuFade()  end
        if cdb.fadePlayerFrame and not Unavailable("fadePlayerFrame")  then SetupPlayerFrameFade() end
        if db.hideBagButtons and not Unavailable("hideBagButtons") then HideBagButtons() end
        if db.hideMacroNames and not Unavailable("hideMacroNames") then HideMacroNames() end
        if (db.hideTalkingHead and not Unavailable("hideTalkingHead"))
            or (db.muteTalkingHead and not Unavailable("muteTalkingHead")) then SetupTalkingHead() end
        if next(db.hideTopBannerTypes) ~= nil and not Unavailable("hideTopBanners") then HideTopBanners() end
        if not Unavailable("hideProfessionGear") then SetHideTransforms() end
        if db.hideErrorText       then HideErrorText()
        else                           HideErrorTypes()      end
        if not Unavailable("fadeActionBars") then SetupActionBarFading() end
        if cdb.fadeMainActionBar and not Unavailable("fadeMainActionBar") then SetupMainActionBarFade() end
        if db.fadeDamageMeter and not Unavailable("fadeDamageMeter") then SetupDamageMeterFade() end
        if db.fadeAuras and not Unavailable("fadeAuras") then SetupAuraFade() end
        if db.fadeMinimapAlerts and not Unavailable("fadeMinimapAlerts") then SetupMinimapAlertsFade() end
        if next(db.fadeMinimapButtons) ~= nil and not Unavailable("fadeMinimapButtons") then
            SetupMinimapButtonsFade()
        end
        if db.fadeObjectiveTracker and not Unavailable("fadeObjectiveTracker") then SetupObjectiveTrackerFade() end
        if db.fadeStatusBars and not Unavailable("fadeStatusBars") then SetupStatusBarFade() end
        StartLoginProbe()   -- ⛔ TEST BUILD PROBE

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

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin, then the reload flag.
        local isReload = ...
        if (arg1 or isReload) and not pewAt then
            pewAt = GetTime()
            healthQuietUntil = math.min(healthQuietUntil, pewAt + LOGIN_HEALTH_FALLBACK)
            loginProbe.kind = arg1 and "login" or "reload"
            ProbeRow("PLAYER_ENTERING_WORLD")
        end

    elseif event == "LOADING_SCREEN_DISABLED" then
        if not loadingDone then
            loadingDone = true
            healthQuietUntil = GetTime() + LOGIN_HEALTH_QUIET
            ProbeRow("LOADING_SCREEN_DISABLED")
        end

    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local ignored = GetTime() < healthQuietUntil
        ProbeRow(event .. (ignored and "  ignored" or "  used"))
        if ignored then return end
        if self._playerHealthPing then self._playerHealthPing() end
    end
end)

-- ── Slash commands ──────────────────────────────────────────
SLASH_VERITASUI_CLEANSOLO1 = "/cleansolo"
SLASH_VERITASUI_CLEANSOLO2 = "/cs"
SlashCmdList["VERITASUI_CLEANSOLO"] = function(msg)
    if strtrim(msg or ""):lower() == "gear" then PrintGearDiag(); return end
    if strtrim(msg or ""):lower() == "login" then
        -- TEST BUILD PROBE: what the player frame did from login until 15 s after entering the world.
        VUI.Print("Clean Solo", string.format("player frame after %s: %d changes", tostring(loginProbe.kind),
            #loginProbe.rows))
        for _, r in ipairs(loginProbe.rows) do
            print(string.format("  %s  %s", r[1] and string.format("%+.1f s", r[1]) or "before world", r[2]))
        end
        return
    end
    if strtrim(msg or ""):lower() == "tracker" then
        -- Which tracker sections are shown, and their alpha: if an event's objective still fades,
        -- this names the section it is in, so it can be added to OT_EVENT_MODULES.
        local otf = _G.ObjectiveTrackerFrame
        if not (otf and otf.GetChildren) then VUI.Print("Clean Solo", "no objective tracker"); return end
        for _, c in ipairs({ otf:GetChildren() }) do
            if c:IsShown() then
                local name = (c.GetName and c:GetName()) or (c == otf.Header and "Header")
                    or (c == otf.NineSlice and "Background") or "?"
                VUI.Print("Clean Solo", string.format("%s  alpha %.2f", tostring(name), c:GetAlpha()))
            end
        end
        return
    end
    if strtrim(msg or ""):lower() == "bars" then
        -- Reports every alpha between the screen and the reputation / experience bars, so a bar that
        -- shows when it should be faded points at the layer that is wrong.
        local function a(f) return f and f.GetAlpha and string.format("%.2f", f:GetAlpha()) or "-" end
        for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
            local c = _G[name]
            if c then
                local shown = {}
                for i, bar in pairs(c.bars or {}) do
                    if bar:IsShown() then
                        shown[#shown + 1] = string.format("bar %s alpha %s, fill %s",
                            tostring(i), a(bar), a(bar.StatusBar))
                    end
                end
                VUI.Print("Clean Solo", string.format("%s: shown %s, alpha %s, frame art %s; %s", name,
                    tostring(c:IsShown()), a(c), a(c.BarFrameTexture),
                    #shown > 0 and table.concat(shown, "; ") or "no bar shown"))
            end
        end
        return
    end
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
