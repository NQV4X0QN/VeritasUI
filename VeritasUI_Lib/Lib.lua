-- VeritasUI_Lib / Lib.lua
-- Shared utilities for all VeritasUI addons.
-- Access from any addon:  local VUI = _G.VeritasUI

if _G.VeritasUI then return end   -- guard against double-load

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G             = _G
local ipairs         = ipairs
local pcall, type    = pcall, type
local next           = next
local math_abs       = math.abs
local format         = string.format
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local InCombatLockdown = InCombatLockdown

-- Mouse-focus compatibility shim.  Probed live on this client: the legacy
-- GetMouseFocus global is GONE - type(GetMouseFocus) is "nil" and calling it
-- raises "attempt to call a nil value" - so the GetMouseFoci() branch is the
-- only live path and the `GetMouseFocus or` half is the dead one.  Kept in that
-- direction anyway: it costs one load-time truth test and keeps working if the
-- global ever returns.  DO NOT collapse this to a bare GetMouseFocus call.
-- VUI.HookPlayerFrameFade's hover test reads it from a 5 Hz ticker (see
-- PLAYER_FRAME_HOVER_POLL_RATE) plus both hover hooks, and CleanSolo hooks the
-- player frame in normal play, so a nil call would error five times a second
-- for as long as the frame is faded in.
local GetMouseFocus  = GetMouseFocus or function()
    local frames = GetMouseFoci()
    return frames and frames[1]
end

----------------------------------------------------------------
--  Namespace
----------------------------------------------------------------
local VUI = {}
_G.VeritasUI = VUI
VUI.VERSION = "1.13.2"
-- Diagnostic gate.  When true, opt-in error prints surface from
-- normally-silent paths (currently: the pcall failures caught in the
-- VUI.CombatQueue drain handler, below).  Off by default to avoid clutter;
-- toggle at runtime via /ah debug (suite-wide despite the prefix) or
-- /run VeritasUI.debug = true, then reproduce the issue.
VUI.debug = false

----------------------------------------------------------------
--  Print helpers
----------------------------------------------------------------
function VUI.Print(tag, msg)
    print(format("|cFF00CCFF[%s]|r %s", tag, msg))
end

-- On/off print for settings that require a /reload to apply (CleanSolo's
-- hooksecurefunc-based features — see the POLICY block in CleanSolo.lua).
function VUI.PrintOnOff(tag, label, state)
    local word = state and "|cFF00FF00turned on|r" or "|cFFFF4444turned off|r"
    VUI.Print(tag, label .. " " .. word .. " — |cFFFFFF00/reload|r to apply.")
end

-- On/off print for settings that apply IMMEDIATELY (QoL's v1.6.28
-- mid-session-apply pattern, AH tooltip toggles).  The "/reload to apply"
-- suffix dates to v1.2.0 when every setting genuinely needed one; telling
-- users to /reload for a live-apply toggle was wrong for nine settings
-- across two modules.
function VUI.PrintOnOffLive(tag, label, state)
    local word = state and "|cFF00FF00turned on|r" or "|cFFFF4444turned off|r"
    VUI.Print(tag, label .. " " .. word .. ".")
end

----------------------------------------------------------------
--  SmoothFade  (per-frame, self-cancelling)
--
--  Each frame gets a single entry in fadeFrames.  Starting a
--  new fade always replaces any in-progress fade, avoiding the
--  conflict bugs with Blizzard's global UIFrameFade table.
--
--  Exposed as VUI.SmoothFade for all modules.
----------------------------------------------------------------
local fadeFrames = {}
local fadeDriver = CreateFrame("Frame")

fadeDriver:SetScript("OnUpdate", function(_, elapsed)
    local f, info = next(fadeFrames)
    while f do
        local nxt = next(fadeFrames, f)
        info.timer = info.timer + elapsed
        if info.timer >= info.duration then
            f:SetAlpha(info.target)
            fadeFrames[f] = nil
        else
            local pct = info.timer / info.duration
            f:SetAlpha(info.start + (info.target - info.start) * pct)
        end
        f = nxt
        if f then info = fadeFrames[f] end
    end
    if not next(fadeFrames) then fadeDriver:Hide() end
end)
fadeDriver:Hide()

local function SmoothFade(frame, duration, targetAlpha)
    local cur = frame:GetAlpha()
    if math_abs(cur - targetAlpha) < 0.01 then
        frame:SetAlpha(targetAlpha)
        fadeFrames[frame] = nil
        return
    end
    fadeFrames[frame] = {
        start    = cur,
        target   = targetAlpha,
        duration = duration,
        timer    = 0,
    }
    fadeDriver:Show()
end

VUI.SmoothFade = SmoothFade

----------------------------------------------------------------
--  Safe frame hide / suppress
--
--  SuppressFrame is idempotent — safe to call multiple times
--  on the same frame without stacking hooks.
----------------------------------------------------------------
function VUI.SafeHide(f)
    if not f then return end
    f:SetAlpha(0)
    if not InCombatLockdown() then
        f:Hide()
    else
        VUI.CombatQueue.Add(function() f:SetAlpha(0); f:Hide() end)
    end
end

function VUI.SuppressFrame(f)
    if not f or f._vui_suppressed then return end
    f._vui_suppressed = true
    VUI.SafeHide(f)
    hooksecurefunc(f, "Show", function(self)
        self:SetAlpha(0)
        if not InCombatLockdown() then
            self:Hide()
        else
            -- Combat-locked Show: alpha 0 hides it visually, but the
            -- frame is still :IsShown() and re-asserts on layout passes.
            -- Defer the Hide until PLAYER_REGEN_ENABLED.  IsShown guard
            -- handles the case where Blizzard already hid the frame
            -- itself between Show and the queue drain.
            VUI.CombatQueue.Add(function()
                if self:IsShown() then self:Hide() end
            end)
        end
    end)
end

----------------------------------------------------------------
--  HookHoverFade  (MicroMenu, action bars, etc.)
--
--  Always-on 10 Hz poll that checks IsMouseOver on the target AND
--  all direct children via a cached array, handling Edit Mode layouts
--  where buttons extend beyond the parent bar frame's bounds.  Only
--  the parent's OnEnter is hooked for instant fade-in within its own
--  bounds — child frames (ActionButtons) are NOT hooked to avoid
--  tainting their execution context, which causes Midnight Secret
--  Value errors in Delves/M+/raids (WoWUIBugs #783-adjacent).
--  150ms grace period prevents flicker between adjacent children.
--
--  Uses SmoothFade to avoid Blizzard UIFrameFade table conflicts.
----------------------------------------------------------------
local HOVER_FADE_IN   = 0.2
local HOVER_FADE_OUT  = 0.5
local HOVER_FADE_POLL_RATE = 0.1    -- ~10 Hz always
local HOVER_LEAVE_GRACE = 0.15 -- seconds after last "not over" before fading

-- Widgets that belong to a bar but are NOT direct children of it.
--
-- Spell flyouts — Pet Utility, mage teleports, profession tools, warlock demons —
-- open ABOVE the button that spawned them. Neither the bar nor its direct children
-- report the mouse while the cursor is inside one, so the grace period expired and
-- the bar faded mid-interaction, taking the flyout's icons with it (they inherit
-- the bar's alpha). Reported 2026-07-28 against Pet Utility.
--
-- Handled TWO ways on purpose. Which one applies depends on whether Blizzard
-- parents the flyout onto the spawning button or onto UIParent, and that was not
-- verified before shipping, so neither is relied on alone:
--   1. IsMouseOverDescendant — walks the parent chain of whatever is under the
--      cursor. Catches a descendant at any depth with no frame name to get wrong,
--      and covers future nested widgets for free.
--   2. IsMouseOverFlyout — tests the flyout by global name, for the case where it
--      is parented outside the bar. Existence-guarded, so a wrong or renamed
--      global does nothing instead of erroring.
-- If BOTH miss, `/vui hover` dumps the real parent chain so the gap is one
-- measurement away rather than another guess.
local HOVER_FLYOUT_GLOBALS = { "SpellFlyout", "PetActionBarFlyout" }
local HOVER_WALK_MAX_DEPTH = 8   -- flyoutButton → flyout → actionButton → bar is 4

function VUI.HookHoverFade(target, shouldStayVisible)
    if not target then return end
    target:SetAlpha(0)

    local function IsLocked()
        return shouldStayVisible and shouldStayVisible()
    end

    -- Check target and all direct children — handles Edit Mode layouts
    -- where buttons extend beyond the parent bar frame's bounds.
    -- Short-circuits on target:IsMouseOver() (common case for MicroMenu).
    -- Children are cached to avoid table allocation on every poll tick;
    -- the cache is rebuilt when RefreshChildren is called (e.g. after
    -- Edit Mode exit changes the bar layout).
    local childCache = { target:GetChildren() }

    local function RefreshChildren()
        childCache = { target:GetChildren() }
    end

    -- Declared ABOVE IsMouseOverAny because that closure reads `hovered`. A local
    -- declared BELOW a closure that references it is captured as a nil GLOBAL at
    -- closure-creation time — the trap that silently broke /way. Do not move these
    -- back down.
    local hovered    = false
    local graceSince = nil

    local function IsMouseOverDescendant()
        local f = GetMouseFocus and GetMouseFocus()
        local depth = 0
        while f and depth < HOVER_WALK_MAX_DEPTH do
            if f == target then return true end
            if not f.GetParent then return false end
            local ok, parent = pcall(f.GetParent, f)
            if not ok then return false end
            f = parent
            depth = depth + 1
        end
        return false
    end

    local function IsMouseOverFlyout()
        for i = 1, #HOVER_FLYOUT_GLOBALS do
            local fo = _G[HOVER_FLYOUT_GLOBALS[i]]
            if fo and fo.IsShown and fo.IsMouseOver
               and fo:IsShown() and fo:IsMouseOver() then
                return true
            end
        end
        return false
    end

    local function IsMouseOverAny()
        if target:IsMouseOver() then return true end
        for i = 1, #childCache do
            local child = childCache[i]
            if child:IsVisible() and child:IsMouseOver() then return true end
        end
        -- Extended-widget checks run ONLY while the bar is already visible. A
        -- flyout cannot be opened without first hovering the bar, so on the faded
        -- path these could only burn work — and GetMouseFoci allocates a table per
        -- call, which is exactly the per-tick churn the child cache above exists to
        -- avoid. This keeps the idle cost identical to before.
        if not hovered then return false end
        return IsMouseOverDescendant() or IsMouseOverFlyout()
    end

    local poll       = CreateFrame("Frame")

    local function FadeOut()
        if not IsLocked() and not IsMouseOverAny() then
            hovered    = false
            graceSince = nil
            SmoothFade(target, HOVER_FADE_OUT, 0)
        end
    end

    local function FadeIn()
        if not hovered then
            hovered    = true
            graceSince = nil
            SmoothFade(target, HOVER_FADE_IN, 1)
        end
    end

    -- Poll: always active at 10 Hz.  Detects both hover-start (for
    -- child buttons that extend beyond the parent bar's bounds) and
    -- hover-end (with grace period to prevent flicker).  Only the
    -- parent bar's OnEnter is hooked for instant fade-in within its
    -- bounds — child ActionButtons are NOT hooked, avoiding taint
    -- propagation that causes Secret Value errors in Midnight Delves.
    poll:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < HOVER_FADE_POLL_RATE then return end
        self._t = 0
        if IsLocked() then graceSince = nil; return end
        if IsMouseOverAny() then
            graceSince = nil
            if not hovered then FadeIn() end
        elseif hovered then
            local now = GetTime()
            if not graceSince then
                graceSince = now
            elseif now - graceSince >= HOVER_LEAVE_GRACE then
                FadeOut()
            end
        end
    end)

    -- Instant fade-in on the parent bar frame only.  Child buttons
    -- are detected by the poll to avoid tainting ActionButton frames.
    target:HookScript("OnEnter", FadeIn)

    return FadeOut, RefreshChildren
end

----------------------------------------------------------------
--  HookPlayerFrameFade  (ElvUI oUF_Fader-inspired)
--
--  Single Evaluate() re-checks ALL conditions as a flat OR.
--  Health: UnitHealth returns a Secret Value in Midnight, so
--  we use event-timing — UNIT_HEALTH fires every regen tick
--  while below max; silence for HEALTH_IDLE_TIME → assume full.
--
--  Returns:  Evaluate, HealthPing
----------------------------------------------------------------
local FADE_IN_TIME     = 0.20
local FADE_OUT_TIME    = 0.50
local FADE_OUT_DELAY   = 0.50
local HEALTH_IDLE_TIME = 3.0
-- 10 Hz, matching HOVER_FADE_POLL_RATE. Was 0.20 and ran ONLY while the frame was
-- visible, with OnEnter waking it; now always-on, so it must be responsive enough to
-- replace that hook without the fade-in feeling laggy.
local PLAYER_FRAME_HOVER_POLL_RATE  = 0.10

function VUI.HookPlayerFrameFade(frame, inCombatRef)
    if not frame then return end
    frame:SetAlpha(0)

    local delayTimer, healthTimer
    local wasShowing   = false
    local healthActive = false

    local function IsHovered()
        local focus = GetMouseFocus()
        if focus == frame then return true end
        local p = focus and focus.GetParent and focus:GetParent()
        while p do
            if p == frame then return true end
            p = p.GetParent and p:GetParent()
        end
        return false
    end

    local function ShouldShow()
        return inCombatRef() or healthActive or IsHovered()
    end


    local function DoFadeOut()
        delayTimer = nil
        if not ShouldShow() then
            SmoothFade(frame, FADE_OUT_TIME, 0)
            wasShowing = false
        end
    end

    local function Evaluate()
        if ShouldShow() then
            if delayTimer then delayTimer:Cancel(); delayTimer = nil end
            if not wasShowing then
                SmoothFade(frame, FADE_IN_TIME, 1)
                wasShowing = true
            end
        elseif wasShowing and not delayTimer then
            delayTimer = C_Timer.NewTimer(FADE_OUT_DELAY, DoFadeOut)
        end
    end

    local function HealthPing()
        if healthTimer then healthTimer:Cancel(); healthTimer = nil end
        if not healthActive then
            healthActive = true
            Evaluate()
        end
        healthTimer = C_Timer.NewTimer(HEALTH_IDLE_TIME, function()
            healthTimer = nil
            healthActive = false
            Evaluate()
        end)
    end

    -- ⚠ DO NOT HookScript this frame. Until v1.12.3 hover was driven by
    -- HookScript("OnEnter"/"OnLeave") on the frame itself, with the poll running only
    -- while it was visible. That is the one place in this suite that hooked a secure
    -- Blizzard frame's mouse scripts, and it is the same shape as the documented
    -- ActionButton trap: hooking a secure frame's OnEnter taints its execution
    -- context, and Blizzard's own code on that frame then runs tainted. HookHoverFade
    -- polls instead of hooking child ActionButtons for exactly this reason —
    -- PlayerFrame was the inconsistency, and it is the single most
    -- targeting-sensitive frame in the game: its own code calls protected targeting
    -- functions.
    --
    -- Motivating evidence (NOT proof — recorded honestly): on 2026-07-28 a
    -- ADDON_ACTION_FORBIDDEN naming VeritasUI_Lib fired for ClearTarget() during
    -- ordinary mounted travel. Nothing in this suite calls ClearTarget, so it was
    -- taint propagation, and of every Blizzard frame Lib touches, PlayerFrame is the
    -- ONLY one whose own code does targeting.
    --
    -- The poll is now ALWAYS ON, because the OnEnter hook was load-bearing: the old
    -- ticker only ran while the frame was already visible, so with the hook removed
    -- and the old gating kept, a faded frame would never have come back on hover.
    -- No handle kept: this runs for the session, exactly like HookHoverFade's poll.
    C_Timer.NewTicker(PLAYER_FRAME_HOVER_POLL_RATE, Evaluate)

    return Evaluate, HealthPing
end

----------------------------------------------------------------
--  CombatQueue  — deferred actions executed on REGEN_ENABLED
----------------------------------------------------------------
VUI.CombatQueue = {}
local queue = {}

function VUI.CombatQueue.Add(fn)
    if not InCombatLockdown() then
        fn()
    else
        queue[#queue + 1] = fn
    end
end

local cqFrame = CreateFrame("Frame")
cqFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cqFrame:SetScript("OnEvent", function()
    local pending = queue
    queue = {}
    for _, fn in ipairs(pending) do
        -- Errors inside queued closures are caught (the queue must
        -- always finish draining; one bad action shouldn't strand the
        -- rest in combat-locked state).  Surface failures only when
        -- VUI.debug is on so users can reproduce silent CombatQueue
        -- bugs by flipping the flag and triggering the path again.
        local ok, err = pcall(fn)
        if not ok and VUI.debug then
            print("|cFFFF4444[VeritasUI]|r CombatQueue error: "
                .. tostring(err))
        end
    end
end)

-- NOTE: VUI.AttachSlimScrollbar was removed in v1.6.18.
-- Both AO tabs now use Blizzard's native ScrollBox + MinimalScrollBar.
-- If a future module needs a scrollbar, use ScrollBox + MinimalScrollBar
-- directly — see AdvancedOptions/Browser.lua and Featured.lua for examples.

----------------------------------------------------------------
--  Managed Panel Helpers — UIPanel system integration
--
--  Wraps Blizzard's ShowUIPanel / HideUIPanel so VUI panels
--  anchor to the standard left edge and stack with Character /
--  Journeys / Spellbook via UIParent_ManageFramePositions —
--  visually indistinguishable from Blizzard's own panels.
--
--  Usage:
--    1) Create the frame with a GLOBAL NAME (UIPanel system
--       requires a string-addressable frame):
--           CreateFrame("Frame", "MyAddon_Panel", UIParent,
--                       "PortraitFrameTemplate")
--    2) Do NOT call SetPoint, SetMovable, SetFrameStrata, or
--       SetToplevel on the frame — the manager owns positioning
--       and any manual anchor will fight it.
--    3) Register once at load:
--           VUI.RegisterManagedPanel("MyAddon_Panel", {
--               area = "left", pushable = 1, whileDead = 1 })
--    4) Open / close through the helpers (combat-safe + pcall):
--           VUI.OpenManagedPanel(frame)
--           VUI.CloseManagedPanel(frame)
--    5) Wire the X button to call HideUIPanel(self:GetParent())
--       so the manager is notified and frees the slot.
--
--  Defaults:
--    area      = "left"   ("left" | "doublewide" | "center")
--    pushable  = 1        Default is Tier B — coexists with Blizzard primary
--                         panels (CollectionsJournal, Character, etc.) without
--                         displacing them. Lower pushable wins slot 1.
--                         Documented Blizzard values (verified live in WoW
--                         Midnight 12.0.5):
--                           CollectionsJournal = 0  (Tier A, exclusive)
--                           CharacterFrame     = 3  (Tier B, coexists)
--                           ProfessionsFrame   = not in UIPanelWindows
--                                                (uses modern manager)
--                         Pass pushable=0 explicitly to behave like a Blizzard
--                         primary panel (always claims slot 1, mutually
--                         exclusive with other Tier A panels).
--                         Pass pushable=9+ to consistently yield to all
--                         Blizzard panels (lowest priority).
--    whileDead = 1        (allow opening while dead, like Char)
--    width     = N        Optional explicit width hint for the manager.
--    height    = N        Optional explicit height hint for the manager.
--
--  IMPORTANT: Call RegisterManagedPanel at FILE LOAD time, BEFORE the
--  frame is created. Blizzard registers all its UIPanelWindows entries
--  at top-level file scope, and the manager treats late-registered
--  frames as second-class — they hold their slot but won't displace
--  existing panels. The frame name is a string lookup; the frame
--  itself doesn't need to exist yet.
----------------------------------------------------------------

function VUI.RegisterManagedPanel(frameName, opts)
    -- Frame doesn't need to exist yet — UIPanelWindows is a string-keyed
    -- lookup the manager consults at ShowUIPanel time. Registering at file
    -- load (before CreateFrame) is the Blizzard-native pattern.
    if type(frameName) ~= "string" then
        -- Caller passed nil, a frame object, or some other non-string.
        -- Previously this returned silently, leaving the developer to
        -- debug "why isn't my panel registered?" with no signal.  Print
        -- a warning before the bail so the bug is immediately visible.
        VUI.Print("Lib", format(
            "RegisterManagedPanel: bad frameName (got %s, expected string)",
            type(frameName)))
        return
    end
    opts = opts or {}
    UIPanelWindows[frameName] = {
        area      = opts.area      or "left",
        pushable  = opts.pushable  or 1,
        whileDead = opts.whileDead or 1,
        width     = opts.width,
        height    = opts.height,
        xoffset   = opts.xoffset,
        yoffset   = opts.yoffset,
    }
    -- Escape-key support — mirror every Blizzard panel.
    for _, n in ipairs(UISpecialFrames) do
        if n == frameName then return end
    end
    table.insert(UISpecialFrames, frameName)
end

function VUI.OpenManagedPanel(frame)
    if not frame then return end
    if InCombatLockdown() then
        VUI.CombatQueue.Add(function() pcall(ShowUIPanel, frame) end)
    else
        pcall(ShowUIPanel, frame)
    end
end

function VUI.CloseManagedPanel(frame)
    if not frame then return end
    if InCombatLockdown() then
        VUI.CombatQueue.Add(function() pcall(HideUIPanel, frame) end)
    else
        pcall(HideUIPanel, frame)
    end
end

----------------------------------------------------------------
--  Settings Label Registry + Scoped Reload Button
--
--  Each VUI addon calls VUI.RegisterSettingsLabel(label) after
--  registering its Blizzard settings category.  This:
--    1) Tracks which labels belong to us
--    2) Creates a shared "Reload UI" button on SettingsPanel
--       that only appears when a VUI category is active
--
--  The Reload button is necessary because toggling VUI features
--  requires /reload to apply, and clicking a button is faster
--  than typing the command repeatedly.
----------------------------------------------------------------
----------------------------------------------------------------
--  Copy-settings UI (Settings panel control -> menu -> confirm)
--
--  Shape chosen to use only components already proven in this suite: a widget
--  anchored into SettingsPanel (the Reload UI button's mechanism), a MenuUtil
--  menu, and a StaticPopup confirmation.
--
--  ⚠ NEVER BACK THIS TRIGGER WITH A PERSISTED Settings VALUE. Blizzard's Settings
--  framework REPLAYS a persisted value on load — proven in this codebase: v1.6.10
--  added a guard against that replay, silently broke CleanSolo's bar selection and
--  was reverted in v1.6.11. A copy-on-select control whose choice is persisted
--  would re-copy the source character onto this one on every /reload, destroying
--  any divergence. The trigger IS a dropdown as of v1.12.1 — it anchors to itself,
--  where a cursor-anchored menu drifted with the click — and that is safe only
--  because it persists nothing: the entries are plain menu buttons and the copy is
--  confirmation-gated. This header read "never a dropdown" until v1.12.5, which
--  contradicted the code and mis-stated the actual rule.
--
--  ⚠ DO NOT ASSIGN THE GLOBAL StaticPopupDialogs — write only its KEYS.
--  The line `StaticPopupDialogs = StaticPopupDialogs or {}` stood here from v1.12.0
--  until v1.12.5 and was a live taint source. Assigning a Blizzard-owned global from
--  addon code taints that global's variable slot, and Blizzard reaches every dialog
--  through it (StaticPopup.lua indexes this table at sixteen sites), so each read
--  tainted the reading execution and any protected call made by the dispatched
--  handler was then refused. Observed in game 2026-07-29: ADDON_ACTION_FORBIDDEN
--  naming VeritasUI_Lib for EndBoundTradeable(), whose only caller is Blizzard's
--  END_BOUND_TRADEABLE dialog — raised by learning a still-trade-eligible caged pet.
--  The guard was worthless regardless: Blizzard_StaticPopup creates the table
--  unconditionally, long before any addon loads, so it can never be nil.
--
--  Adding KEYS is safe and is what every addon does: Blizzard only ever indexes this
--  table by key and never iterates it, so our keys cannot taint a sibling read.
--  StaticPopup_AddDefinition(which, def) is the sanctioned equivalent if some future
--  change wants it; direct key writes are kept because they are what is proven in
--  game today, and keeping the v1.12.5 diff to one line of behaviour makes the next
--  observation interpretable.
----------------------------------------------------------------

StaticPopupDialogs["VERITASUI_COPY_SETTINGS"] = {
    text = "Copy all VeritasUI settings from |cFFFFFF00%s|r onto |cFFFFFF00%s|r?"
        .. "\n\nThis character's current settings will be overwritten. You can undo it afterwards.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
    OnAccept = function(_, data)
        local ok, msg = VUI.CopyCharSettings(data)
        VUI.Print("VeritasUI", (ok and "" or "|cFFFF4444") .. msg .. (ok and "" or "|r"))
        if ok then StaticPopup_Show("VERITASUI_COPY_RELOAD") end
    end,
}

StaticPopupDialogs["VERITASUI_COPY_RELOAD"] = {
    text = "Settings copied. Some of them only take effect after a reload.",
    button1 = "Reload Now",
    button2 = "Later",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = ReloadUI,
}

StaticPopupDialogs["VERITASUI_UNDO_COPY"] = {
    text = "Undo the settings copy from |cFFFFFF00%s|r and restore this character's previous settings?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
    OnAccept = function()
        local ok, msg = VUI.UndoCharSettingsCopy()
        VUI.Print("VeritasUI", (ok and "" or "|cFFFF4444") .. msg .. (ok and "" or "|r"))
        if ok then StaticPopup_Show("VERITASUI_COPY_RELOAD") end
    end,
}

VUI.COPY_BUTTON_LABEL = "Copy From…"

-- Shared menu generator, used by the dropdown (primary) and the context-menu
-- fallback. Rebuilt on every open, so the character list and the undo entry are
-- always current.
local function BuildCopyMenu(_, root)
    -- WoWUIBugs #783 workaround: an addon menu opened first in a session otherwise
    -- assigns a tainted nil to the shared menu frame's minimumWidth, which then
    -- surfaces as Secret Value errors in unrelated Blizzard code. One line, defuses
    -- it. Remove when #783 is fixed.
    root:SetMinimumWidth(180)
    root:CreateTitle("Copy settings from")
    local sources = VUI.ListCopySources()
    if #sources == 0 then
        local none = root:CreateButton("No other characters yet", function() end)
        if none and none.SetEnabled then none:SetEnabled(false) end
    else
        for _, key in ipairs(sources) do
            root:CreateButton(key, function()
                StaticPopup_Show("VERITASUI_COPY_SETTINGS", key, VUI.CharKey() or "?", key)
            end)
        end
    end
    local last = VUI.GetUndoableCopy()
    if last then
        root:CreateDivider()
        root:CreateButton("Undo copy from " .. tostring(last.source), function()
            StaticPopup_Show("VERITASUI_UNDO_COPY", tostring(last.source))
        end)
    end
end
VUI._BuildCopyMenu = BuildCopyMenu

-- Cursor-anchored FALLBACK, used only if the dropdown template is unavailable.
-- The dropdown is preferred because its menu anchors to the widget itself, which is
-- the behaviour asked for; a context menu follows the cursor by design and so opens
-- in a different place depending on where in the button you clicked.
--
-- MenuUtil on this client (probed 2026-07-28) pairs each "...ContextMenu" with a
-- non-Context "...Menu" — CreateButtonContextMenu/CreateButtonMenu,
-- CreateCheckboxContextMenu/CreateCheckboxMenu — and the naming implies the plain
-- variants anchor to the owner. That is an INFERENCE from a naming pattern, not a
-- measured fact, so it is deliberately not what the shipped path relies on.
function VUI.ShowCopyMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        VUI.Print("VeritasUI", "|cFFFF4444Menu API unavailable|r — use |cFFFFFF00/vui copy|r instead.")
        return
    end
    MenuUtil.CreateContextMenu(owner, BuildCopyMenu)
end

VUI._settingsLabels = {}
local reloadBtn
local copyBtn

function VUI.RegisterSettingsLabel(label)
    VUI._settingsLabels[label] = true
    if not VUI._reloadBtnHooked then VUI._InitReloadButton() end
end

function VUI._InitReloadButton()
    if VUI._reloadBtnHooked then return end
    if not SettingsPanel then
        -- Deferred retry. RegisterSettingsLabel re-attempts on every call and
        -- all seven modules call it, but they all register in the same load
        -- phase — so seven retries at the same instant are one retry, and if
        -- SettingsPanel were ever absent then (LoD Blizzard_Settings) the
        -- Reload button would silently never exist for the whole session with
        -- nothing to trigger another attempt. PLAYER_LOGIN is strictly later
        -- than addon load, so it is the one retry point that adds a genuinely
        -- new opportunity. One-shot: the frame unregisters itself.
        if not VUI._reloadBtnRetry then
            VUI._reloadBtnRetry = CreateFrame("Frame")
            VUI._reloadBtnRetry:RegisterEvent("PLAYER_LOGIN")
            VUI._reloadBtnRetry:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                VUI._InitReloadButton()
            end)
        end
        return
    end
    VUI._reloadBtnHooked = true

    SettingsPanel:HookScript("OnShow", function()
        if reloadBtn then return end

        -- Find the Defaults button to anchor beside.
        local defaultsBtn
        local function Search(f)
            for _, child in ipairs({ f:GetChildren() }) do
                if child:IsObjectType("Button") then
                    local t = child:GetText()
                    -- The "Defaults" literal is a WON'T FIX decided in cycle 4, not an oversight:
                    -- DEFAULTS is the correct localized global and is tested first, so the literal can
                    -- only ever help on enUS, where the two are equal anyway. If DEFAULTS were nil the
                    -- search simply fails and the else branch below mis-anchors the button to a fixed
                    -- offset - cosmetic, never a fault. Paired with the AH tooltip's ": " separator as
                    -- one decision: single-user addon on an English client.
                    if t and (t == DEFAULTS or t == "Defaults") then
                        defaultsBtn = child; return
                    end
                end
                Search(child)
                if defaultsBtn then return end
            end
        end
        Search(SettingsPanel)

        reloadBtn = CreateFrame("Button", nil, SettingsPanel, "UIPanelButtonTemplate")
        reloadBtn:SetText("Reload UI")
        reloadBtn:SetWidth(100)
        reloadBtn:SetScript("OnClick", ReloadUI)
        if defaultsBtn then
            reloadBtn:SetPoint("RIGHT", defaultsBtn, "LEFT", -8, 0)
        else
            reloadBtn:SetPoint("TOPRIGHT", SettingsPanel, "TOPRIGHT", -200, -58)
        end
        reloadBtn:Hide()

        -- "Copy From…" sits to the left of Reload UI, same visibility rule.
        --
        -- A DROPDOWN widget rather than a plain button, so the menu opens directly
        -- beneath it every time. A cursor-anchored context menu drifted with the
        -- click position, which is what prompted this. WowStyle1DropdownTemplate
        -- anchors its menu to itself by construction and is already proven in this
        -- suite (PriorityRotation's spec switcher), so the placement is structural
        -- rather than dependent on an API default.
        --
        -- ⚠ This does NOT reopen the dropdown objection from the copy-settings UI
        -- header. That objection is specific to a dropdown backed by a PERSISTED
        -- Settings value, which Blizzard's framework replays on load. This widget
        -- persists nothing — the entries are plain menu buttons and the copy is still
        -- gated by a confirmation — so there is no value to replay.
        local okDD
        okDD, copyBtn = pcall(CreateFrame, "DropdownButton", nil, SettingsPanel,
                              "WowStyle1DropdownTemplate")
        if okDD and copyBtn and copyBtn.SetupMenu then
            copyBtn:SetWidth(150)
            copyBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -4, 0)
            if copyBtn.SetDefaultText then copyBtn:SetDefaultText(VUI.COPY_BUTTON_LABEL) end
            copyBtn:SetupMenu(VUI._BuildCopyMenu)
            -- Keep the label fixed. A DropdownButton normally shows the last thing
            -- clicked, and this widget is an action list, not a selection — a
            -- character name left in the label would read like a persisted choice.
            -- OverrideText is required rather than SetDefaultText: the default only
            -- applies until something has been clicked (see the dropdown landmine).
            if copyBtn.HookScript then
                copyBtn:HookScript("OnHide", function(self)
                    if self.OverrideText then self:OverrideText(VUI.COPY_BUTTON_LABEL) end
                end)
            end
        else
            -- Template unavailable: fall back to a plain button + cursor menu, which
            -- is the pre-1.12.1 behaviour. Positioning is worse, the feature works.
            copyBtn = CreateFrame("Button", nil, SettingsPanel, "UIPanelButtonTemplate")
            copyBtn:SetText(VUI.COPY_BUTTON_LABEL)
            copyBtn:SetWidth(110)
            copyBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -4, 0)
            copyBtn:SetScript("OnClick", function(self) VUI.ShowCopyMenu(self) end)
        end
        copyBtn:Hide()
    end)

    -- Poll every 0.25s to show the button only when a VUI category is active.
    -- Uses pcall so unknown API shapes degrade to "button stays hidden".
    local checker = CreateFrame("Frame", nil, SettingsPanel)
    local checkT = 0
    checker:SetScript("OnUpdate", function(_, dt)
        checkT = checkT + dt
        if checkT < 0.25 then return end
        checkT = 0
        if not reloadBtn then return end
        local show = false
        local ok, cat = pcall(SettingsPanel.GetCurrentCategory, SettingsPanel)
        if ok and cat then
            local ok2, name = pcall(cat.GetName, cat)
            if ok2 and name and VUI._settingsLabels[name] then
                show = true
            end
        end
        reloadBtn:SetShown(show)
        if copyBtn then copyBtn:SetShown(show) end
    end)

    SettingsPanel:HookScript("OnHide", function()
        if reloadBtn then reloadBtn:Hide() end
        if copyBtn then copyBtn:Hide() end
    end)
end

----------------------------------------------------------------
--  Blocked / forbidden action recorder
--
--  ADDON_ACTION_FORBIDDEN (insecure code called a function it may NEVER call)
--  and ADDON_ACTION_BLOCKED (a protected call reached from tainted execution)
--  both name the offending addon AND the offending function.  That function
--  name is the single datum that turns "some VeritasUI module tainted
--  something" into an actionable defect, and Blizzard hands it over exactly
--  once, in an event that is gone the instant the session ends.
--
--  ALWAYS ON, deliberately NOT gated on VUI.debug.  Same reasoning as the AH
--  scan trace: you cannot ask a taint popup to happen on cue, so a debug flag
--  would be off precisely when it mattered.  Recorded to SavedVariables so it
--  survives /reload and logout -- a popup dismissed with "Ignore" days ago is
--  still readable with /vui taint.
--
--  This records; it never prints on the event.  ADDON_ACTION_BLOCKED can fire
--  hundreds of times on one zone entry (see the ActionButton taint landmine),
--  so printing would bury the user in the symptom.  Entries are deduped on
--  event|addon|function, which turns that flood into a counter increment rather
--  than table growth, and timestamps are stored as time() integers and
--  formatted only at dump time so date() never runs on the flood path.
----------------------------------------------------------------
local TAINT_LOG_MAX = 25   -- cap on DISTINCT signatures, not on occurrences

-- pairs/time/date/sort are deliberately NOT localized at file top: the only
-- per-event work here is a table lookup and an increment, and every other path
-- (new signature, dump) is cold.  Per the suite's hot-global policy, cold
-- globals stay global.
local function TaintDB()
    local db = _G.VeritasUI_LibDB
    if type(db) ~= "table" then return nil end
    if type(db.taintLog) ~= "table" then db.taintLog = {} end
    return db
end

local function CountTaintEntries(db)
    local n = 0
    for _ in pairs(db.taintLog) do n = n + 1 end
    return n
end

local function RecordTaintEvent(event, addonName, funcName)
    local db = TaintDB()
    if not db then return end   -- fired before SavedVariables loaded; nothing to do
    local key = event .. "|" .. tostring(addonName) .. "|" .. tostring(funcName)
    local entry = db.taintLog[key]
    if entry then
        entry.count = (entry.count or 0) + 1
        entry.last  = time()
        return
    end
    if CountTaintEntries(db) >= TAINT_LOG_MAX then
        -- Only reachable via many DISTINCT signatures; a repeat of a recorded
        -- one is handled above and never consumes a slot.
        --
        -- FORBIDDEN outranks BLOCKED for a full log.  BLOCKED is the noisy
        -- event (a tainted action bar throws it in volume, and each distinct
        -- function name takes its own slot) while FORBIDDEN is rare and names a
        -- call insecure code may never make -- the datum this recorder exists to
        -- capture.  A plain first-come cap would let BLOCKED noise fill the log
        -- and drop the one entry that matters, so a FORBIDDEN arriving at a full
        -- log evicts the least-seen BLOCKED entry instead of being discarded.
        -- FORBIDDEN never evicts FORBIDDEN.
        local evictKey
        if event == "ADDON_ACTION_FORBIDDEN" then
            local fewest
            for k, v in pairs(db.taintLog) do
                if v.event == "ADDON_ACTION_BLOCKED"
                   and (not fewest or (v.count or 0) < fewest) then
                    fewest, evictKey = (v.count or 0), k
                end
            end
        end
        if not evictKey then
            db.taintLogDropped = (db.taintLogDropped or 0) + 1
            return
        end
        db.taintLog[evictKey] = nil
        db.taintLogDropped = (db.taintLogDropped or 0) + 1
    end
    -- Context is gathered ONCE per signature and every read is pcall'd.  This
    -- code runs when something is already broken, so the recorder must never
    -- become the thing that errors -- the audit's "harden diagnostics
    -- generously" rule, at its most literal.
    local ctx = {}
    pcall(function() ctx.zone   = GetZoneText() end)
    pcall(function() ctx.player = UnitName("player") end)
    pcall(function() ctx.combat = InCombatLockdown() and true or false end)
    pcall(function()
        -- Whether Blizzard_AuctionHouseUI is loaded discriminates the two
        -- candidate taint sources for the 2026-07-28 housing-vault report:
        -- AuctionHouse/Tooltip.lua arms at PLAYER_LOGIN and needs no AH visit,
        -- while SellStrip's AuctionHouseFrame hooks cannot exist without one.
        ctx.ahui = (C_AddOns and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI")) and true or false
    end)
    -- Frame under the cursor, and whether a target existed. Added after the
    -- 2026-07-28 ClearTarget() report, where the missing datum was WHICH frame's
    -- code was running: if a future occurrence names a unit frame here, that is
    -- close to conclusive. Best-effort — the cursor may have moved between the
    -- blocked call and this event.
    pcall(function()
        local f = GetMouseFocus and GetMouseFocus()
        if f and f.GetName then
            local ok, n = pcall(f.GetName, f)
            ctx.focus = (ok and n) or "<unnamed>"
        end
    end)
    pcall(function()
        ctx.hadTarget = (UnitExists and UnitExists("target")) and true or false
    end)
    db.taintLog[key] = {
        event   = event,
        addon   = tostring(addonName),
        func    = tostring(funcName),
        count   = 1,
        first   = time(),
        last    = time(),
        version = VUI.VERSION,
        ctx     = ctx,
    }
end

-- Programmatic read, for a future session that CAN reach the SavedVariables
-- file directly (or for another module that wants to react to the log).
function VUI.GetTaintLog()
    local db = TaintDB()
    return db and db.taintLog or nil
end

local function DumpTaintLog()
    local db = TaintDB()
    if not db then
        VUI.Print("VeritasUI", "Diagnostic log unavailable — saved variables not loaded yet.")
        return
    end
    local keys = {}
    for k in pairs(db.taintLog) do keys[#keys + 1] = k end
    if #keys == 0 then
        VUI.Print("VeritasUI", "No blocked-action events recorded.")
        return
    end
    table.sort(keys, function(a, b)
        return (db.taintLog[a].first or 0) < (db.taintLog[b].first or 0)
    end)
    VUI.Print("VeritasUI", format("Blocked-action log — %d distinct event%s:",
        #keys, #keys == 1 and "" or "s"))
    -- Body lines are raw print, NOT VUI.Print.  This is a diagnostic dump meant
    -- to be copy-pasted verbatim, and a per-line [VeritasUI] tag is noise in a
    -- paste -- the same split /zq debug and /ah diag already use.  Do not
    -- "unify" these onto VUI.Print.
    for i, k in ipairs(keys) do
        local e = db.taintLog[k]
        local c = e.ctx or {}
        print(format("%d) %s", i, e.event or "?"))
        print(format("   addon = %s", e.addon or "?"))
        print(format("   func  = %s", e.func or "?"))
        print(format("   seen %d time(s), first %s, last %s",
            e.count or 0,
            date("%Y-%m-%d %H:%M", e.first or 0),
            date("%Y-%m-%d %H:%M", e.last or 0)))
        print(format("   vui %s | char %s | zone %s | combat %s | ah-ui-loaded %s",
            e.version or "?", c.player or "?", c.zone or "?",
            tostring(c.combat), tostring(c.ahui)))
        print(format("   cursor-over %s | had-target %s",
            tostring(c.focus), tostring(c.hadTarget)))
    end
    if (db.taintLogDropped or 0) > 0 then
        print(format("   (%d further distinct signature(s) dropped — log caps at %d)",
            db.taintLogDropped, TAINT_LOG_MAX))
    end
    VUI.Print("VeritasUI", "|cFF888888/vui taint clear|r to reset the log.")
end

local taintFrame = CreateFrame("Frame")
taintFrame:RegisterEvent("ADDON_LOADED")
taintFrame:RegisterEvent("PLAYER_LOGIN")
taintFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
taintFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
taintFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        RecordTaintEvent(event, arg1, arg2)
    elseif event == "ADDON_LOADED" then
        if arg1 ~= "VeritasUI_Lib" then return end
        if type(_G.VeritasUI_LibDB) ~= "table" then _G.VeritasUI_LibDB = {} end
        TaintDB()   -- seeds .taintLog
    else
        -- PLAYER_LOGIN: one-line nudge so a popup dismissed with "Ignore" long
        -- ago does not sit unread in the log forever.
        local db = TaintDB()
        if not db then return end
        local n = CountTaintEntries(db)
        if n > 0 then
            VUI.Print("VeritasUI", format(
                "|cFFFF8800%d blocked-action event%s recorded|r — |cFFFFFF00/vui taint|r to view.",
                n, n == 1 and "" or "s"))
        end
    end
end)

----------------------------------------------------------------
--  Per-character settings storage
--
--  Settings live in the ACCOUNT-WIDE saved variable, keyed by "Realm-Character",
--  with each character reading and writing only its own slot:
--
--      VeritasUI_<Module>DB = {
--          chars = { ["Hyjal-Khalthazar"] = { ...settings... }, ... },
--          <legacy top-level keys>        -- pre-1.11 account-wide layout, RETAINED
--      }
--
--  ⚠ Deliberately NOT `SavedVariablesPerCharacter`. Those files are only loaded
--  for the character you are logged into, so no character could ever read
--  another's settings — which makes copying settings between characters
--  impossible by construction. Account-wide-keyed is the only shape that supports
--  it. Do not "simplify" this to SavedVariablesPerCharacter.
--
--  ⚠ TIMING: the key needs UnitName("player"), whose availability at
--  ADDON_LOADED is NOT established. PriorityRotation — the one module already
--  per-character — sidesteps this by never resolving its key at ADDON_LOADED
--  (PR:InitDB only creates the profiles table) and first resolving at
--  PLAYER_LOGIN. This follows that proven pattern: BindCharDB returns the LEGACY
--  ROOT when no key is available, so a caller may bind at ADDON_LOADED for
--  continuity and MUST re-bind at PLAYER_LOGIN to land on the real slot.
--
--  ⚠ Settings.RegisterAddOnSetting takes the TABLE as its 4th argument, so the
--  Settings framework holds a direct reference. A module registering settings
--  must do so AFTER its PLAYER_LOGIN re-bind and must pass the SLOT, not the
--  root — otherwise every change made in the options panel writes to the
--  account-wide root and per-character storage silently does nothing.
--  AuctionHouse already registered at PLAYER_LOGIN; that is the precedent.
----------------------------------------------------------------
function VUI.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do
        c[k] = (type(v) == "table") and VUI.DeepCopy(v) or v
    end
    return c
end

-- "Realm-Character", or nil if the player's identity is not available yet.
function VUI.CharKey()
    local name  = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return realm .. "-" .. name
end

-- Registry of per-character saved variables, populated BY BindCharDB itself so the
-- copy feature's module list cannot drift from the set of modules that actually use
-- per-character storage. Adding a module to the scheme automatically enrols it.
-- Value carries the module's defaults table, needed to re-seed keys the copy source
-- happens not to have.
VUI._charDBs = VUI._charDBs or {}

-- Bind (or re-bind) this character's settings slot inside `globalName`.
-- Returns the slot, or the legacy root if the key is not yet resolvable.
function VUI.BindCharDB(globalName, defaults)
    VUI._charDBs[globalName] = { defaults = defaults }
    local root = _G[globalName]
    if type(root) ~= "table" then root = {}; _G[globalName] = root end
    if type(root.chars) ~= "table" then root.chars = {} end

    local key = VUI.CharKey()
    if not key then return root end

    local slot = root.chars[key]
    if not slot then
        -- First bind for this character. Seed from the LEGACY top-level keys so it
        -- inherits whatever account-wide setup was in effect rather than bare
        -- defaults — without this, every character resets on upgrade.
        --
        -- The legacy block is deliberately NOT deleted: it remains the seed for
        -- characters that have not logged in since the change. Cost is a few
        -- hundred bytes; the alternative is those characters silently resetting.
        slot = {}
        for k, v in pairs(root) do
            if k ~= "chars" then slot[k] = VUI.DeepCopy(v) end
        end
        root.chars[key] = slot
    end

    if defaults then
        for k, v in pairs(defaults) do
            if slot[k] == nil then slot[k] = VUI.DeepCopy(v) end
        end
    end
    return slot
end

-- Characters that have a saved slot in `globalName`, sorted. Used by the
-- copy-settings feature; also handy for diagnostics.
function VUI.ListCharKeys(globalName)
    local root = _G[globalName]
    local out = {}
    if type(root) ~= "table" or type(root.chars) ~= "table" then return out end
    for k in pairs(root.chars) do out[#out + 1] = k end
    table.sort(out)
    return out
end

----------------------------------------------------------------
--  Copy settings between characters
--
--  Copies every registered per-character settings table from another character
--  onto this one, snapshotting this character's current values first so a single
--  undo can restore them.
--
--  ⚠ Slots are rewritten IN PLACE rather than replaced. Each module holds its slot
--  in a file-local `db`, and Blizzard's Settings framework holds the same table by
--  reference (see the BindCharDB header). Swapping in a new table would leave both
--  pointing at an orphan: the options panel would edit a table nobody reads, and
--  every module read would return pre-copy values until a reload. Keeping table
--  identity means the copy is live for anything that re-reads, and only CleanSolo's
--  hook-based features need the reload they already require by policy.
--
--  Deliberately excluded: PriorityRotation (its rotations are keyed per character
--  AND per specialization, so they cannot map onto a different class) and
--  AuctionHouse (account-wide market data, nothing character-specific). Neither
--  registers with BindCharDB, so both are excluded automatically rather than by a
--  list that could rot.
----------------------------------------------------------------

-- Characters that have a slot in ANY registered module, excluding this one.
function VUI.ListCopySources()
    local here, seen, out = VUI.CharKey(), {}, {}
    for globalName in pairs(VUI._charDBs) do
        for _, key in ipairs(VUI.ListCharKeys(globalName)) do
            if key ~= here and not seen[key] then
                seen[key] = true
                out[#out + 1] = key
            end
        end
    end
    table.sort(out)
    return out
end

local function LibDB()
    if type(_G.VeritasUI_LibDB) ~= "table" then _G.VeritasUI_LibDB = {} end
    return _G.VeritasUI_LibDB
end

-- Rewrite `slot` in place to hold exactly `values`, then re-seed anything missing
-- from `defaults`. Table identity is preserved; see the section header.
local function OverwriteSlot(slot, values, defaults)
    for k in pairs(slot) do slot[k] = nil end
    for k, v in pairs(values) do slot[k] = VUI.DeepCopy(v) end
    if defaults then
        for k, v in pairs(defaults) do
            if slot[k] == nil then slot[k] = VUI.DeepCopy(v) end
        end
    end
end

-- Returns ok, message.
function VUI.CopyCharSettings(sourceKey)
    local destKey = VUI.CharKey()
    if not destKey then return false, "This character is not identified yet." end
    if not sourceKey or sourceKey == "" then return false, "No source character given." end
    if sourceKey == destKey then return false, "That is this character." end

    local snapshot, copied = {}, 0
    for globalName, info in pairs(VUI._charDBs) do
        local root = _G[globalName]
        local src  = root and root.chars and root.chars[sourceKey]
        local dest = root and root.chars and root.chars[destKey]
        -- A module the SOURCE has never populated is skipped rather than reset to
        -- defaults: the user asked to copy a character's settings, not to wipe
        -- settings that character never expressed an opinion about.
        if src and dest then
            snapshot[globalName] = VUI.DeepCopy(dest)
            OverwriteSlot(dest, src, info and info.defaults)
            copied = copied + 1
        end
    end

    if copied == 0 then
        return false, "Nothing to copy from " .. sourceKey .. "."
    end

    LibDB().lastCopy = {
        source = sourceKey,
        dest   = destKey,
        when   = time(),
        snapshot = snapshot,
    }
    return true, ("Copied settings from |cFFFFFF00%s|r (%d module%s)."):format(
        sourceKey, copied, copied == 1 and "" or "s")
end

-- Is there an undoable copy for THIS character?
function VUI.GetUndoableCopy()
    local last = LibDB().lastCopy
    if type(last) ~= "table" then return nil end
    if last.dest ~= VUI.CharKey() then return nil end
    return last
end

-- Returns ok, message.
function VUI.UndoCharSettingsCopy()
    local last = VUI.GetUndoableCopy()
    if not last then return false, "Nothing to undo on this character." end
    local restored = 0
    for globalName, values in pairs(last.snapshot or {}) do
        local root = _G[globalName]
        local dest = root and root.chars and root.chars[last.dest]
        if dest then
            local info = VUI._charDBs[globalName]
            OverwriteSlot(dest, values, info and info.defaults)
            restored = restored + 1
        end
    end
    LibDB().lastCopy = nil
    if restored == 0 then return false, "Nothing could be restored." end
    return true, ("Restored this character's settings from before the copy (%d module%s)."):format(
        restored, restored == 1 and "" or "s")
end

----------------------------------------------------------------
--  /vui hover — mouse-focus parent-chain dump (diagnostic)
--
--  Answers "why did the bar fade while I was hovering that?" with the real
--  frame hierarchy instead of a guess. HookHoverFade keeps a bar visible when the
--  cursor is over the bar, a direct child, a DESCENDANT at any depth, or a known
--  flyout global; if a widget satisfies none of those, this names it and its whole
--  parent chain so the gap can be closed by measurement.
--
--  Sampling is DELAYED because a slash command necessarily leaves the cursor in
--  the chat box — there is no way to run it while hovering the thing in question.
----------------------------------------------------------------
local HOVER_PROBE_DELAY = 5

local function DumpHoverChain()
    local f = GetMouseFocus and GetMouseFocus()
    if not f then
        VUI.Print("VeritasUI", "Nothing under the cursor when sampled.")
        return
    end
    VUI.Print("VeritasUI", "Mouse-focus parent chain:")
    -- Raw print for copy-paste fidelity (suite print-split policy).
    local depth = 0
    while f and depth < 12 do
        local name = "<unnamed>"
        if f.GetName then
            local ok, n = pcall(f.GetName, f)
            if ok and n then name = n end
        end
        local kind = "?"
        if f.GetObjectType then
            local ok, t = pcall(f.GetObjectType, f)
            if ok and t then kind = t end
        end
        print(("   %d) %s  (%s)"):format(depth, name, kind))
        if not f.GetParent then break end
        local ok, parent = pcall(f.GetParent, f)
        if not ok then break end
        f = parent
        depth = depth + 1
    end
    for i = 1, #HOVER_FLYOUT_GLOBALS do
        local name = HOVER_FLYOUT_GLOBALS[i]
        local fo = _G[name]
        print(("   flyout global %s: %s"):format(name,
            fo and (fo.IsShown and fo:IsShown() and "SHOWN" or "hidden") or "absent"))
    end
end

function VUI.ProbeHoverChain()
    VUI.Print("VeritasUI", ("Move the cursor onto the element and hold still — sampling in %ds."):format(
        HOVER_PROBE_DELAY))
    C_Timer.After(HOVER_PROBE_DELAY, DumpHoverChain)
end

----------------------------------------------------------------
--  /veritasui slash command
----------------------------------------------------------------
SLASH_VERITASUI1 = "/veritasui"
SLASH_VERITASUI2 = "/vui"
SlashCmdList["VERITASUI"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "taint" then
        DumpTaintLog()
    elseif cmd == "taint clear" then
        local db = TaintDB()
        if db then
            db.taintLog = {}
            db.taintLogDropped = nil
        end
        VUI.Print("VeritasUI", "Blocked-action log cleared.")
    elseif cmd == "hover" then
        VUI.ProbeHoverChain()
    elseif cmd == "copy" or cmd:match("^copy%s") then
        -- Text fallback for the Settings-panel button. The button is anchored by
        -- searching for Blizzard's "Defaults" button, which has a fallback anchor but
        -- is not guaranteed to be found; without this there would be no way to reach
        -- the feature if that search ever failed.
        local target = (msg or ""):match("^%s*[Cc][Oo][Pp][Yy]%s+(.-)%s*$")
        if not target or target == "" then
            local sources = VUI.ListCopySources()
            if #sources == 0 then
                VUI.Print("VeritasUI", "No other characters have saved settings yet.")
            else
                VUI.Print("VeritasUI", "Copy settings from which character?")
                for _, key in ipairs(sources) do
                    print(("   /vui copy %s"):format(key))
                end
            end
        else
            StaticPopup_Show("VERITASUI_COPY_SETTINGS", target, VUI.CharKey() or "?", target)
        end
    elseif cmd == "undocopy" then
        local last = VUI.GetUndoableCopy()
        if not last then
            VUI.Print("VeritasUI", "Nothing to undo on this character.")
        else
            StaticPopup_Show("VERITASUI_UNDO_COPY", tostring(last.source))
        end
    else
        VUI.Print("VeritasUI", "Version " .. VUI.VERSION .. " loaded.")
        VUI.Print("VeritasUI", "|cFFFFFF00/vui taint|r — show recorded blocked-action events.")
        VUI.Print("VeritasUI", "|cFFFFFF00/vui taint clear|r — reset that log.")
        VUI.Print("VeritasUI", "|cFFFFFF00/vui hover|r — dump the parent chain under the cursor (5s delay).")
        VUI.Print("VeritasUI", "|cFFFFFF00/vui copy|r — copy another character's settings onto this one.")
        VUI.Print("VeritasUI", "|cFFFFFF00/vui undocopy|r — undo the last copy on this character.")
    end
end
