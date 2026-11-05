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
-- VUI.HookPlayerFrameFade's hover test reads it from a 10 Hz ticker
-- (PLAYER_FRAME_HOVER_POLL_RATE = 0.10; the note above that constant says 10 Hz
-- too), and Interface hooks the player frame in normal play, so a nil call would
-- error TEN times a second for as long as the frame is faded in — and that ticker
-- keeps no handle, so it cannot be cancelled short of /reload.
--
-- ⚠ CORRECTED v1.13.8: this said "5 Hz" and "five times a second". It understated the
-- blast radius of the exact hazard this block exists to reason about, by half.
local GetMouseFocus  = GetMouseFocus or function()
    local frames = GetMouseFoci()
    return frames and frames[1]
end

----------------------------------------------------------------
--  Namespace
----------------------------------------------------------------
local VUI = {}
_G.VeritasUI = VUI
VUI.VERSION = "1.65.0"
-- WoW Forever (game type camelot): one codebase serves both games, and a module drops what Forever lacks.
-- MEASURED in Forever 1.60.1.70790 (owner's /vui forever probe, 2026-11-04): WOW_PROJECT_ID = 18 =
-- WOW_PROJECT_CAMELOT (Blizzard_ProjectConstants/Camelot/ProjectConstants.lua:1-2). Retail defines only
-- MAINLINE and CLASSIC (Gethe live 12.1.5.70783, Blizzard_ProjectConstants/ProjectConstants.lua:1-2), so
-- this is false there.
VUI.IS_FOREVER = _G.WOW_PROJECT_CAMELOT ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CAMELOT
-- Diagnostic gate.  When true, opt-in error prints surface from
-- normally-silent paths (currently: the pcall failures caught in the
-- VUI.CombatQueue drain handler, below).  Off by default to avoid clutter;
-- toggle at runtime via /vui debug (or /ah debug, kept as an alias) or
-- /run VeritasUI.debug = true, then reproduce the issue.
VUI.debug = false

----------------------------------------------------------------
--  Print helpers
----------------------------------------------------------------
-- Timestamps on VeritasUI's own lines (v1.31.0). Quality of Life's "Timestamp Every Message"
-- turns this on; Blizzard's message filters never see these lines, because print() writes to the
-- chat window directly instead of sending a chat event. Same format as Blizzard's Chat Timestamps
-- option (ChatFrameUtil.GetTimestampFormat + TimeUtil.BetterDate); nothing when that is None.
local printStamps = false

function VUI.SetPrintTimestamps(on)
    printStamps = on and true or false
end

local function PrintStamp()
    if not printStamps then return "" end
    local get = _G.ChatFrameUtil and _G.ChatFrameUtil.GetTimestampFormat
    local fmt = get and get()
    if not (fmt and _G.TimeUtil and _G.TimeUtil.BetterDate) then return "" end
    local ok, stamp = pcall(_G.TimeUtil.BetterDate, fmt, time())
    return (ok and type(stamp) == "string") and stamp or ""
end

-- Blizzard's named colours as |c codes (owner's standard, 2026-11-01: never hand-picked colours). Read from
-- Blizzard's own ColorMixin constants (SharedColorConstants; WrapTextInColorCode as Blizzard uses it, e.g.
-- ChatFrameOverrides.lua:256). The fallbacks are those constants' values, used only if one is missing.
local function ColorCode(c, fallback)
    if type(c) == "table" and c.WrapTextInColorCode then
        local ok, s = pcall(c.WrapTextInColorCode, c, "")
        if ok and type(s) == "string" and #s >= 10 then return s:sub(1, 10) end
    end
    return fallback
end
VUI.COL = {
    NORMAL    = ColorCode(_G.NORMAL_FONT_COLOR,    "|cffffd100"),   -- gold
    HIGHLIGHT = ColorCode(_G.HIGHLIGHT_FONT_COLOR, "|cffffffff"),   -- white
    YELLOW    = ColorCode(_G.YELLOW_FONT_COLOR,    "|cffffff00"),
    RED       = ColorCode(_G.RED_FONT_COLOR,       "|cffff2020"),
    GREEN     = ColorCode(_G.GREEN_FONT_COLOR,     "|cff20ff20"),
    GRAY      = ColorCode(_G.GRAY_FONT_COLOR,      "|cff808080"),
    DISABLED  = ColorCode(_G.DISABLED_FONT_COLOR,  "|cff7f7f7f"),
    ORANGE    = ColorCode(_G.ORANGE_FONT_COLOR,    "|cffff7f3f"),
    LIGHTBLUE = ColorCode(_G.LIGHTBLUE_FONT_COLOR, "|cff8080ff"),
    BRIGHTBLUE = ColorCode(_G.BRIGHTBLUE_FONT_COLOR, "|cff3399ff"),
}

function VUI.Print(tag, msg)
    print(PrintStamp() .. format(VUI.COL.BRIGHTBLUE .. "[%s]|r %s", tag, msg))
end

-- On/off print for settings that require a /reload to apply (Interface's
-- hooksecurefunc-based features — see the POLICY block in Interface.lua).
function VUI.PrintOnOff(tag, label, state)
    local word = state and VUI.COL.GREEN .. "turned on|r" or VUI.COL.RED .. "turned off|r"
    VUI.Print(tag, label .. " " .. word .. " — " .. VUI.COL.YELLOW .. "/reload|r to apply.")
end

-- On/off print for settings that apply IMMEDIATELY (QoL's v1.6.28
-- mid-session-apply pattern, AH tooltip toggles).  The "/reload to apply"
-- suffix dates to v1.2.0 when every setting genuinely needed one; telling
-- users to /reload for a live-apply toggle was wrong for nine settings
-- across two modules.
function VUI.PrintOnOffLive(tag, label, state)
    local word = state and VUI.COL.GREEN .. "turned on|r" or VUI.COL.RED .. "turned off|r"
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
    local function Rehide(self)
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
    end
    hooksecurefunc(f, "Show", Rehide)
    -- ⚠ SetShown is a SEPARATE route: it does not call the frame's Show, so the hook above never
    -- sees it. Blizzard's property buttons (voice/channels, mute, deafen) re-show themselves this
    -- way (PropertyBindingMixin.lua:120-123), and until v1.17.14 they came back at alpha 0 --
    -- invisible but still clickable (suite-wide audit S1).
    if f.SetShown then
        hooksecurefunc(f, "SetShown", function(self, shown)
            if shown then Rehide(self) end
        end)
    end
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

-- Fade Delay (Interface's slider, v1.25.0): how long a faded element stays up after it no longer
-- needs to show, before it starts fading. ONE value for the hover and player-frame faders so they
-- behave alike. Each keeps its own built-in delay as a floor (hover 0.15 s, player frame 0.5 s),
-- so 0 means exactly the behaviour before the slider existed. Interface's chat tabs are left off
-- it on purpose: Blizzard fades the chat window on its own timing (Interface.lua, HideAllTabs).
-- Read at the moment a fade is about to start, so a change applies at once, without /reload.
local FADE_DELAY_MAX = 5
local fadeDelay = 0

function VUI.SetFadeDelay(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 elseif seconds > FADE_DELAY_MAX then seconds = FADE_DELAY_MAX end
    fadeDelay = seconds
end

function VUI.GetFadeDelay()
    return fadeDelay
end

-- Faded opacity (Interface's per-fade sliders, v1.40.0): how much of a faded element still shows,
-- 0-1. The hover and player-frame faders take an optional getter and read it every time they fade
-- out, and while faded they follow a change at once, so a slider applies without /reload.
-- No getter, or a bad value, is 0: fully hidden, the behaviour before the sliders.
local function FadedAlpha(getter)
    if not getter then return 0 end
    local ok, a = pcall(getter)
    a = ok and tonumber(a) or 0
    if a < 0 then return 0 elseif a > 1 then return 1 end
    return a
end
VUI.FadedAlpha = FadedAlpha

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

-- shouldStayVisible: while it returns true the fade is FROZEN where it is (Edit Mode).
-- shouldShow (v1.39.0): while it returns true the target fades IN and stays, exactly as if hovered
--   (combat, flying, or the option being turned off live). nil = hover only, as before.
-- noEnterHook (v1.39.0): skip the OnEnter hook and rely on the 10 Hz poll alone. Used for Action
--   Bar 1, whose frame is the most taint-sensitive bar in the game (landmine: never HookScript a
--   secure Blizzard frame); fade-in then starts within 0.1 s instead of at once.
-- fadedAlpha (v1.40.0): getter for the faded opacity (see FadedAlpha). nil = 0, as before.
function VUI.HookHoverFade(target, shouldStayVisible, shouldShow, noEnterHook, fadedAlpha)
    if not target then return end
    local faded = FadedAlpha(fadedAlpha)

    local function IsLocked()
        return shouldStayVisible and shouldStayVisible()
    end

    local function IsForced()
        return shouldShow and shouldShow()
    end

    -- Hooked while it must be shown (turned on mid-fight, or while flying): no drop to 0 and back.
    if not IsForced() then target:SetAlpha(faded) end

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
        if not IsLocked() and not IsForced() and not IsMouseOverAny() then
            hovered    = false
            graceSince = nil
            faded      = FadedAlpha(fadedAlpha)
            SmoothFade(target, HOVER_FADE_OUT, faded)
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
        if IsForced() or IsMouseOverAny() then
            graceSince = nil
            if not hovered then FadeIn() end
        elseif hovered then
            local now = GetTime()
            if not graceSince then
                graceSince = now
            elseif now - graceSince >= math.max(HOVER_LEAVE_GRACE, fadeDelay) then
                FadeOut()
            end
        elseif fadedAlpha then
            -- Faded, and the opacity slider moved: follow it.
            local a = FadedAlpha(fadedAlpha)
            if math_abs(a - faded) > 0.001 then
                faded = a
                SmoothFade(target, HOVER_FADE_OUT, a)
            end
        end
    end)

    -- Instant fade-in on the parent bar frame only.  Child buttons
    -- are detected by the poll to avoid tainting ActionButton frames.
    if not noEnterHook then target:HookScript("OnEnter", FadeIn) end

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

-- fadedAlpha (v1.40.0): optional getter for the faded opacity, as in HookHoverFade.
-- holdRef (v1.63.0): optional; while it returns true the frame stays shown (Interface: a resource still filling
-- or draining after combat, read from its value when the game lets us).
function VUI.HookPlayerFrameFade(frame, inCombatRef, fadedAlpha, holdRef)
    if not frame then return end
    local faded = FadedAlpha(fadedAlpha)
    frame:SetAlpha(faded)

    local delayTimer, healthTimer
    local wasShowing   = false
    local healthActive = false

    -- ⚠ EVERY widget call on the mouse-focus object must be pcall'd, and the walk
    -- must be depth-capped.  Both were missing until v1.14.10 and both bit.
    --
    -- Measured 2026-08-15 (owner, House Editor): with the cursor on a room plaque the
    -- focus was `Button <Blizzard_HouseEditorLayoutMode.lua:193>` — a HousingLayoutPin,
    -- which is a FORBIDDEN object.  `focus.GetParent` is a plain table read and
    -- succeeds; `focus:GetParent()` is a widget C call and raises "Attempt to access
    -- forbidden object from code tainted by an AddOn".  Our code is tainted by
    -- definition (this runs from an addon-created ticker), so there is no taint leak to
    -- chase here — a forbidden object simply cannot be touched by addon code at all,
    -- and the only correct move is to stop walking.
    --
    -- Blast radius was the 10 Hz ticker at the end of this function: the error's Count climbed by ten
    -- a second for as long as the cursor rested on the pin, and each throw aborted
    -- Evaluate() mid-flight, so the fade stopped being re-evaluated while it happened.
    --
    -- This is now the same shape as HookHoverFade's IsMouseOverDescendant (above),
    -- which has had the pcall and the cap since it was written.  IsHovered was the
    -- inconsistency, not the pattern.  Returning false on an inaccessible chain is
    -- deliberate: if we cannot see the chain we cannot claim a hover, and a cursor
    -- parked on House Editor furniture is not a cursor on the player frame.
    local function IsHovered()
        local p = GetMouseFocus()
        local depth = 0
        while p and depth < HOVER_WALK_MAX_DEPTH do
            if p == frame then return true end
            if not p.GetParent then return false end
            local ok, parent = pcall(p.GetParent, p)
            if not ok then return false end
            p = parent
            depth = depth + 1
        end
        return false
    end

    local function ShouldShow()
        return inCombatRef() or healthActive or IsHovered() or (holdRef ~= nil and holdRef() == true)
    end


    local function DoFadeOut()
        delayTimer = nil
        if not ShouldShow() then
            faded = FadedAlpha(fadedAlpha)
            SmoothFade(frame, FADE_OUT_TIME, faded)
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
            delayTimer = C_Timer.NewTimer(math.max(FADE_OUT_DELAY, fadeDelay), DoFadeOut)
        elseif not wasShowing and fadedAlpha then
            -- Faded, and the opacity slider moved: follow it.
            local a = FadedAlpha(fadedAlpha)
            if math_abs(a - faded) > 0.001 then
                faded = a
                SmoothFade(frame, FADE_OUT_TIME, a)
            end
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
    -- while it was visible.
    --
    -- ⚠ CORRECTED v1.13.8: this used to call that "the one place in this suite that
    -- hooked a secure Blizzard frame's mouse scripts". It is not. HookHoverFade still
    -- does exactly that (its target:HookScript("OnEnter")) — on MicroMenu and on up to
    -- seven MultiBar* containers (Interface's two VUI.HookHoverFade calls). That hooking
    -- is DELIBERATE and documented (parent containers yes, child ActionButtons never — see
    -- HookHoverFade's header, its poll, and the note on its OnEnter hook); only the "one
    -- place" claim was false. It matters because a reader trusting it would believe no
    -- secure mouse-script hooks remain and would not think to look at HookHoverFade's
    -- OnEnter hook when the next ADDON_ACTION_FORBIDDEN names VeritasUI_Lib.
    --
    -- What IS unique about PlayerFrame: it is the one place where hooking was ABANDONED
    -- in favour of polling. It is the same shape as the documented
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
            print(VUI.COL.RED .. "[VeritasUI]|r CombatQueue error: "
                .. tostring(err))
        end
    end
end)

----------------------------------------------------------------
--  Built frames — lets an optional module restyle frames the suite creates
----------------------------------------------------------------
-- A module calls VUI.AnnounceFrame(key, frame) once it has finished building a frame that
-- another addon might want to restyle. VUI.OnFrameBuilt(key, fn) runs fn(frame) for every
-- frame announced under `key`, including any announced before it was called, so neither side
-- depends on load or login order. Nothing listens unless an optional module registers; none
-- ships since VeritasUI_ElvUI was retired in v1.35.0 (kept so a revival needs no other changes),
-- so an announcement is a table insert.
--
-- A listener error is reported through WoW's error handler and does not interrupt the module
-- that announced the frame.
local builtFrames, builtListeners = {}, {}

local function RunListener(fn, frame)
    local handler = geterrorhandler and geterrorhandler()
    if handler then xpcall(fn, handler, frame) else pcall(fn, frame) end
end

function VUI.AnnounceFrame(key, frame)
    if not (key and frame) then return end
    local list = builtFrames[key]
    if not list then list = {}; builtFrames[key] = list end
    list[#list + 1] = frame
    for _, fn in ipairs(builtListeners[key] or {}) do RunListener(fn, frame) end
end

function VUI.OnFrameBuilt(key, fn)
    if not (key and type(fn) == "function") then return end
    local list = builtListeners[key]
    if not list then list = {}; builtListeners[key] = list end
    list[#list + 1] = fn
    for _, frame in ipairs(builtFrames[key] or {}) do RunListener(fn, frame) end
end

----------------------------------------------------------------
--  Unavailable options — another addon owns the part of the screen an option changes
----------------------------------------------------------------
-- VUI.SetOptionUnavailable says an option of `addonName` cannot work alongside another addon,
-- and must be called before the owning module builds its options page. The owning module then
-- skips that feature and shows the option greyed out with `reason` in its tooltip. The saved
-- value is never touched, so the option comes back as it was without that addon. ⚠ IN USE:
-- Quality of Life calls it for its own /way option when TomTom is installed (at PLAYER_LOGIN,
-- before InitializeOptions). VeritasUI_ElvUI (retired v1.35.0) was the other caller.
local unavailableOptions = {}

function VUI.SetOptionUnavailable(addonName, key, reason)
    if not (addonName and key) then return end
    unavailableOptions[addonName] = unavailableOptions[addonName] or {}
    unavailableOptions[addonName][key] = reason or true
end

-- Returns the reason (or true) when the option is unavailable, nil when it is available.
function VUI.OptionUnavailable(addonName, key)
    local list = unavailableOptions[addonName]
    return list and list[key] or nil
end

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
--    5) Wire the X button to call VUI.CloseManagedPanel(self:GetParent())
--       so the manager is notified and frees the slot (and it still closes in combat).
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

-- Flat, modern background for a ButtonFrameTemplate window's recessed Inset (AO v1.35.10, PR
-- v1.35.11). The Inset's own Bg is the old marble tile; the Auction House's lists use
-- auctionhouse-background-index (Blizzard_AuctionHouseBrowseResultsFrame.xml:10), laid 3 px inside
-- the same InsetFrameTemplate border (AuctionHouseBackgroundMixin:OnLoad,
-- Blizzard_AuctionHouseSharedTemplates.lua:25-34). Atlases come from the client, not the Auction
-- House addon, so it shows without that UI loaded. Stretched to the Inset's size. Owner-chosen look.
function VUI.UseFlatInsetBackground(win)
    local inset = win and win.Inset
    if type(inset) ~= "table" or type(inset.Bg) ~= "table" then return false end
    local bg = inset.Bg
    bg:SetHorizTile(false)
    bg:SetVertTile(false)
    bg:SetAtlas("auctionhouse-background-index")
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT",     inset, "TOPLEFT",      3, -3)
    bg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -3,  3)
    return true
end

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

-- ⚠ In combat Blizzard refuses HideUIPanel from addon code: CheckProtectedFunctionsAllowed shows
-- "Interface action failed because of an AddOn" and returns (UIParentPanelManager.lua:844-848,
-- :895-897) -- owner hit it closing Priority Rotation mid-fight, 2026-10-29. Our panels are plain
-- insecure frames, so in combat they are simply hidden. The manager tidies the freed slot itself:
-- every ShowUIPanel starts with RepairUIPanelState, which releases slots whose frame is no longer
-- shown (:156-183, called at :195). A protected frame is never hidden this way.
function VUI.CloseManagedPanel(frame)
    if not frame then return end
    if InCombatLockdown() then
        if not (frame.IsProtected and frame:IsProtected()) then frame:Hide() end
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
--  added a guard against that replay, silently broke Interface's bar selection and
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
    text = "Copy all VeritasUI settings from " .. VUI.COL.YELLOW .. "%s|r onto " .. VUI.COL.YELLOW .. "%s|r?"
        .. "\n\nThis character's current settings will be overwritten. You can undo it afterwards.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
    OnAccept = function(_, data)
        local ok, msg = VUI.CopyCharSettings(data)
        VUI.Print("VeritasUI", (ok and "" or VUI.COL.RED) .. msg .. (ok and "" or "|r"))
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
    text = "Undo the settings copy from " .. VUI.COL.YELLOW .. "%s|r and restore this character's previous settings?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
    OnAccept = function()
        local ok, msg = VUI.UndoCharSettingsCopy()
        VUI.Print("VeritasUI", (ok and "" or VUI.COL.RED) .. msg .. (ok and "" or "|r"))
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
        VUI.Print("VeritasUI", VUI.COL.RED .. "Menu API unavailable|r — use "
            .. VUI.COL.YELLOW .. "/vui copy|r instead.")
        return
    end
    MenuUtil.CreateContextMenu(owner, BuildCopyMenu)
end

----------------------------------------------------------------
--  One "VeritasUI" entry on the AddOns tab, with every module's page nested under it
--  (owner, 2026-10-30). Blizzard draws group headers only on the Game tab
--  (Blizzard_CategoryList.lua:411-417) and files every addon under one unheaded "AddOns"
--  group (Blizzard_Settings.lua:133-137), so a parent category with subcategories is the
--  AddOns-tab way to group a suite (Blizzard_ImplementationReadme.lua:9-19).
--   * The parent is a canvas page: a title styled like Blizzard's page header
--     (Blizzard_SettingsList.xml:9-23) and the installed modules with their TOC notes.
--     Canvas, not a vertical list, so it carries no Defaults button that would reset nothing.
--   * Subcategories inherit the AddOns tab from the parent (Blizzard_Category.lua:65-73).
--     Each module still calls Settings.RegisterAddOnCategory(subcategory): for a category with a
--     parent that only rebuilds the list (Blizzard_CategoryList.lua:299-305), which is what makes
--     a page registered after the parent appear.
--   * Expanded by default and sorted by name (SetExpanded / SetShouldSortAlphabetically,
--     Blizzard_Category.lua:114-136, read by CreateSection, Blizzard_CategoryList.lua:392-407).
----------------------------------------------------------------
local settingsParent
local SUITE_MODULES = {   -- folder, shown name; every installed module except Lib itself
    { "VeritasUI_AdvancedOptions",  "Advanced Options" },
    { "VeritasUI_AuctionHouse",     "Auction House" },
    { "VeritasUI_Interface",        "Interface" },
    { "VeritasUI_PriorityRotation", "Priority Rotation" },
    { "VeritasUI_QualityOfLife",    "Quality of Life" },
    { "VeritasUI_ZoneQuests",       "Zone Quests" },
}

local function BuildSuitePage()
    local page = CreateFrame("Frame")
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetJustifyH("LEFT")
    title:SetText("VeritasUI")
    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -50)
    local version = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    version:SetPoint("TOPLEFT", 20, -70)
    version:SetText("Version " .. tostring(VUI.VERSION))

    local rows = {}
    page.OnRefresh = function()
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        local meta = C_AddOns and C_AddOns.GetAddOnMetadata
        local y, n = -100, 0
        for _, m in ipairs(SUITE_MODULES) do
            local okL, loaded = pcall(isLoaded, m[1])
            if okL and loaded then
                n = n + 1
                local row = rows[n]
                if not row then
                    row = {
                        name  = page:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
                        notes = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
                    }
                    row.notes:SetJustifyH("LEFT")
                    rows[n] = row
                end
                row.name:SetPoint("TOPLEFT", 20, y)
                row.name:SetText(m[2])   -- no slash commands: owner, none or all, and none reads cleaner
                local okN, notes = pcall(meta, m[1], "Notes")
                notes = (okN and type(notes) == "string") and notes:gsub("%s*|c%x%x%x%x%x%x%x%x.-|r", "") or ""
                row.notes:SetPoint("TOPLEFT", 20, y - 18)
                row.notes:SetPoint("RIGHT", page, "RIGHT", -20, 0)
                row.notes:SetText(notes)
                row.name:Show(); row.notes:Show()
                y = y - 44
            end
        end
        for i = n + 1, #rows do rows[i].name:Hide(); rows[i].notes:Hide() end
    end
    page:SetScript("OnShow", page.OnRefresh)
    return page
end

-- Every module registers its options page through this instead of
-- Settings.RegisterVerticalLayoutCategory; returns the same (category, layout) pair.
function VUI.RegisterSettingsCategory(name)
    local sub = Settings.RegisterVerticalLayoutSubcategory
    if not sub or not Settings.RegisterCanvasLayoutCategory then
        return Settings.RegisterVerticalLayoutCategory(name)
    end
    if not settingsParent then
        settingsParent = Settings.RegisterCanvasLayoutCategory(BuildSuitePage(), "VeritasUI")
        if settingsParent.SetExpanded then settingsParent:SetExpanded(true) end
        if settingsParent.SetShouldSortAlphabetically then settingsParent:SetShouldSortAlphabetically(true) end
        Settings.RegisterAddOnCategory(settingsParent)
    end
    return sub(settingsParent, name)
end

VUI._settingsLabels = {}
local reloadBtn
local copyBtn
local openBtn

-- opts (v1.58.0, owner's request): { open = function } for a module whose
-- settings live in its own window (Priority Rotation, Advanced Options). Its page then shows an Open
-- button where Reload UI and Copy From... sit on the other pages; Copy From... copies every module, so it
-- stays reachable from those.
function VUI.RegisterSettingsLabel(label, opts)
    VUI._settingsLabels[label] = (type(opts) == "table" and type(opts.open) == "function") and opts or true
    if not VUI._reloadBtnHooked then VUI._InitReloadButton() end
end

-- Open a module's window from its Settings page. While Blizzard's Settings window is up no other panel may
-- open (the owner measured it: the first test build's Open did nothing), so Settings is closed first the way
-- Blizzard's own Settings buttons do it: SettingsPanel:Close(true), as the Assisted Combat "view spellbook"
-- button does before opening the spellbook (Blizzard_SettingsDefinitions_Frame/AdvancedOptions.lua:39-43).
-- true = skipTransitionBackToOpeningPanel: Settings closes without bringing the Game Menu back
-- (ExitWithCommit, Blizzard_SettingsPanel.lua:259-267) -- the two Escape presses in one. If you have
-- unapplied changes, Blizzard asks first (Close, :231-237) and Settings stays: nothing opens, and Open
-- can be clicked again after answering. Otherwise the window opens on the next frame, once Settings is gone.
local pendingOpen, settingsHooked
local function OpenNow(opts) pcall(opts.open) end
function VUI._OpenFromSettings(opts)
    local panel = _G.SettingsPanel
    if not (panel and panel.IsShown and panel:IsShown() and panel.Close) then OpenNow(opts); return end
    pendingOpen = opts
    if not settingsHooked then
        settingsHooked = true
        panel:HookScript("OnHide", function()
            local o = pendingOpen
            pendingOpen = nil
            if o then C_Timer.After(0, function() OpenNow(o) end) end
        end)
    end
    pcall(panel.Close, panel, true)
    if panel:IsShown() then pendingOpen = nil end   -- Blizzard asked about unapplied changes
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

    -- Blizzard's own Defaults button, reached by its parentKey path: SettingsPanel:GetSettingsList()
    -- (Blizzard_SettingsPanel.lua:823) -> .Header.DefaultsButton (Blizzard_SettingsList.xml:28).
    -- Until v1.17.7 this searched every child for a button labelled DEFAULTS, but Blizzard labels it
    -- SETTINGS_DEFAULTS (Blizzard_SettingsPanel.lua:78), so on a client where the two differ the
    -- search missed and the buttons fell back to a fixed offset. The label search survives only as a
    -- fallback for the day the path changes, and now matches the string Blizzard actually sets.
    local function FindDefaultsButton()
        local ok, list = pcall(SettingsPanel.GetSettingsList, SettingsPanel)
        local direct = ok and type(list) == "table" and type(list.Header) == "table"
                       and list.Header.DefaultsButton
        if direct then return direct end
        local label = SETTINGS_DEFAULTS or DEFAULTS
        if not label then return nil end
        local found
        local function Search(f)
            for _, child in ipairs({ f:GetChildren() }) do
                if child:IsObjectType("Button") and child:GetText() == label then
                    found = child; return
                end
                Search(child)
                if found then return end
            end
        end
        Search(SettingsPanel)
        return found
    end

    local function CreateButtons()
        local defaultsBtn = FindDefaultsButton()

        reloadBtn = CreateFrame("Button", nil, SettingsPanel, "UIPanelButtonTemplate")
        -- RELOADUI is Blizzard's localized "Reload UI" (Blizzard_AddOnList/AddonList.lua:527).
        reloadBtn:SetText(RELOADUI or "Reload UI")
        local okW, textW = pcall(reloadBtn.GetTextWidth, reloadBtn)
        reloadBtn:SetWidth(math.max(100, ((okW and tonumber(textW)) or 0) + 24))
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

        -- "Open" for a module whose settings are its own window, in Reload UI's place.
        openBtn = CreateFrame("Button", nil, SettingsPanel, "UIPanelButtonTemplate")
        openBtn:SetText("Open")
        openBtn:SetWidth(100)
        openBtn:SetPoint("RIGHT", reloadBtn, "RIGHT", 0, 0)
        openBtn:SetScript("OnClick", function(self)
            if type(self.opts) == "table" then VUI._OpenFromSettings(self.opts) end
        end)
        openBtn:Hide()
        VUI.AnnounceFrame("Lib.SettingsButton", reloadBtn)
        VUI.AnnounceFrame("Lib.SettingsButton", copyBtn)
        VUI.AnnounceFrame("Lib.SettingsButton", openBtn)
    end

    -- Shown only while a VeritasUI category is the current one. Driven by Blizzard's own
    -- notification rather than the 4 Hz poll used until v1.17.7: SelectCategory fires
    -- "Settings.CategoryChanged" with the category on every change (Blizzard_SettingsPanel.lua:
    -- 799-809), and SettingsPanelMixin:OnShow re-selects with force=true (:153-157), so it fires
    -- on every open as well. The OnShow evaluation below covers the very first open, where
    -- Blizzard's event fires before our hook has created the buttons.
    local function UpdateButtons(category)
        if not reloadBtn then return end
        if category == nil then
            local ok, cur = pcall(SettingsPanel.GetCurrentCategory, SettingsPanel)
            category = ok and cur or nil
        end
        local info
        if category and category.GetName then
            local ok, name = pcall(category.GetName, category)
            info = ok and name and VUI._settingsLabels[name] or nil
        end
        local opens = type(info) == "table"
        reloadBtn:SetShown(info ~= nil and not opens)
        if copyBtn then copyBtn:SetShown(info ~= nil and not opens) end
        if openBtn then
            openBtn.opts = opens and info or nil
            openBtn:SetShown(opens)
        end
    end

    SettingsPanel:HookScript("OnShow", function()
        if not reloadBtn then CreateButtons() end
        UpdateButtons()
    end)

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, category)
            UpdateButtons(category)
        end, {})
    end

    SettingsPanel:HookScript("OnHide", function()
        if reloadBtn then reloadBtn:Hide() end
        if copyBtn then copyBtn:Hide() end
        if openBtn then openBtn:Hide() end
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
    VUI.Print("VeritasUI", VUI.COL.GRAY .. "/vui taint clear|r to reset the log.")
end

----------------------------------------------------------------
--  WoW's own `taintLog` CVar is NOT touched here any more.
--
--  v1.17.3-v1.17.6 forced it to 1 at every login (ArmTaintLog) while the UseContainerItem
--  FORBIDDEN was being chased, because the CVar does not survive a logout (measured by the
--  owner 2026-08-30). That code was marked TEMPORARY and was removed in v1.17.7 once the
--  investigation closed (v1.17.4, 2026-09-13): forcing a Blizzard debug setting on for every
--  player diverges from the default client. Nothing needs undoing — the CVar resets itself on
--  the next logout. To capture a WoW-side log again, set `/console taintLog 1` by hand AFTER
--  logging in.
----------------------------------------------------------------

local taintFrame = CreateFrame("Frame")
taintFrame:RegisterEvent("ADDON_LOADED")
taintFrame:RegisterEvent("PLAYER_LOGIN")
taintFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
taintFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
taintFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        -- arg1 is the name of the addon Blizzard blames (RestrictedActionsDocumentation.lua;
        -- Blizzard passes it to AddonTooltip_ActionBlocked). Record ONLY our own modules:
        -- another addon's blocked actions are not ours to report, and recording them made the
        -- login nudge announce other addons' problems and let their noise fill the 25-entry cap.
        if type(arg1) ~= "string" or not arg1:find("^VeritasUI") then return end
        RecordTaintEvent(event, arg1, arg2)
    elseif event == "ADDON_LOADED" then
        if arg1 ~= "VeritasUI_Lib" then return end
        if type(_G.VeritasUI_LibDB) ~= "table" then _G.VeritasUI_LibDB = {} end
        TaintDB()   -- seeds .taintLog
        -- Opt-out flag for the removed taintLog arming (see above). Dead data now.
        _G.VeritasUI_LibDB.taintLogArm = nil
    else
        -- PLAYER_LOGIN: a one-line nudge so a popup dismissed with "Ignore" long ago does
        -- not sit unread in the log forever.
        local db = TaintDB()
        if not db then return end
        local n = CountTaintEntries(db)
        if n > 0 then
            VUI.Print("VeritasUI", format(
                VUI.COL.ORANGE .. "%d blocked-action event%s recorded|r — "
                    .. VUI.COL.YELLOW .. "/vui taint|r to view.",
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
--  PLAYER_LOGIN. Both binders follow that pattern, but they differ in what the early
--  call hands back, and the difference is the whole point:
--    VUI.BindScopedDB (current) returns the account table and NIL for the character
--      table, so per-character work cannot run before an identity exists.
--    VUI.BindCharDB (legacy; no shipped callers) returns the LEGACY ROOT as a
--      stand-in -- which is exactly how AdvancedOptions used to seed its
--      per-character CVar cache into account-wide storage at load time.
--  Either way a caller MUST re-bind at PLAYER_LOGIN to land on the real slot.
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

-- Registry of per-character saved variables, populated BY THE BINDERS THEMSELVES
-- (VUI.BindScopedDB today; VUI.BindCharDB historically) so the copy feature's module list cannot
-- drift from the set of modules that actually use per-character storage. Adding a module to the
-- scheme enrols it automatically.
--
-- ⚠ BindScopedDB registers ONLY its per-character defaults. VUI.CopyCharSettings re-seeds from
-- this table, so registering the universal set would make /vui copy write account-wide values into
-- one character's slot. copy_scope_test asserts per module that no universal key appears here.
-- Value carries the module's defaults table, needed to re-seed keys the copy source
-- happens not to have.
VUI._charDBs = VUI._charDBs or {}

-- Bind a module's saved variables with PER-KEY scope: an account-wide set and a
-- per-character set. Returns `accountTable, charTable`.
--
--   local adb, cdb = VUI.BindScopedDB("VeritasUI_QualityOfLifeDB", UNIVERSAL, PERCHAR)
--
-- Call it at BOTH ADDON_LOADED and PLAYER_LOGIN. The first call seeds and returns the
-- account table with `cdb == nil` (no identity yet); the second returns both. That is
-- exactly the shape AdvancedOptions already uses by calling InitDB twice.
--
-- WHY THIS EXISTS instead of VUI.BindCharDB: BindCharDB scopes an ENTIRE module
-- per-character. That is how four modules became per-character to solve a two-setting
-- problem, and how the Delve count's placement ended up per-character when it should be
-- shared. The authority on which keys go where is
-- ~/.agents/skills/veritasui/references/setting-scope-map.md; only a handful of keys are
-- per-character (the map has the list). Do not reach for BindCharDB for new work.
--
-- ⚠ TWO CONTRACTS THAT ARE THE OPPOSITE OF BindCharDB'S. Both are deliberate, both are
-- enforced by scoped_db_test, and reverting either reintroduces a shipped defect:
--
--   1. NO ROOT FALLBACK. When VUI.CharKey() is unresolvable this returns nil for the
--      char table, where BindCharDB returns the root. If it fell back, the ADDON_LOADED
--      call would write per-character keys (cvarCache, cacheVersion) INTO the account
--      root -- pinning them there for every character, on the very keys the scope map
--      flags as paired. Callers must therefore defer per-character work to PLAYER_LOGIN
--      and tolerate a nil second return.
--
--   2. NO ROOT->SLOT COPY. BindCharDB seeds a fresh slot from every non-`chars` root key
--      (see below) so characters inherit account-wide setup. Once universal values live
--      on the root, that copy pulls them into per-character slots and pins them -- audit
--      finding D8, in a new place. A new character's slot here is seeded ONLY from
--      perCharDefaults, which is what "per-character" means: a new character starts from
--      the shipped default, not from whatever another character happened to set.
--
-- Table identity is stable across re-binds: Settings.RegisterAddOnSetting captures the
-- table it is handed, so handing back a fresh table would silently detach the panel.
function VUI.BindScopedDB(globalName, universalDefaults, perCharDefaults)
    universalDefaults = universalDefaults or {}
    perCharDefaults   = perCharDefaults   or {}

    -- A key with two homes has no defined value. Silently preferring one would hide a
    -- scope-map violation for as long as both happened to agree.
    for k in pairs(perCharDefaults) do
        if universalDefaults[k] ~= nil then
            error(("VUI.BindScopedDB: key '%s' is in BOTH the universal and per-character "
                .. "defaults for %s. See references/setting-scope-map.md."):format(
                tostring(k), tostring(globalName)), 2)
        end
    end

    -- Registered with the PER-CHARACTER defaults only. VUI.CopyCharSettings re-seeds from
    -- this table, so registering the universal set would make /vui copy write
    -- account-wide values into a character's slot.
    VUI._charDBs[globalName] = { defaults = perCharDefaults }

    local root = _G[globalName]
    if type(root) ~= "table" then root = {}; _G[globalName] = root end
    if type(root.chars) ~= "table" then root.chars = {} end

    for k, v in pairs(universalDefaults) do
        if root[k] == nil then root[k] = VUI.DeepCopy(v) end
    end

    local key = VUI.CharKey()
    if not key then return root, nil end          -- contract 1: nil, never the root

    local slot = root.chars[key]
    if not slot then
        slot = {}                                  -- contract 2: no root->slot copy
        root.chars[key] = slot
    end
    for k, v in pairs(perCharDefaults) do
        if slot[k] == nil then slot[k] = VUI.DeepCopy(v) end
    end

    return root, slot
end

-- ONE-WAY scope migration, for a module moving from VUI.BindCharDB to VUI.BindScopedDB.
-- Returns a { [key] = value } table of what it promoted, or nil if it had already run.
--
-- ⚠ The key lists are the SAME two defaults tables handed to VUI.BindScopedDB. That is
-- deliberate: it makes the migration list and the scope decision one thing, so they cannot
-- drift. Do NOT pass a hand-written list -- an earlier plan derived it from a module's
-- `defaults` table and would have silently skipped `mapCoordsPos`, which is a live saved
-- key that is not in `defaults`, losing the map readout's dragged position.
--
-- Three jobs, in order:
--   1. PROMOTE newly-universal keys. The CURRENT character's stored value wins and is written
--      to the account root, overwriting whatever auto-seeded default sits there. Owner-chosen
--      rule; see references/setting-scope-map.md. A character with no stored value promotes
--      NOTHING -- promoting a nil would silently reset the setting.
--   2. CLEAN those keys from EVERY character slot, not just the current one. Nothing reads
--      them there any more, but a stale per-character copy would resurrect the moment a key
--      were ever re-scoped back.
--   3. DELETE the per-character keys' VESTIGIAL ROOT copies. The old auto-seeding loop wrote
--      every default to the root, so a per-character key has an account-wide copy that is
--      dead data yet reads as authoritative.
--
-- ⚠ TIMING: call this AFTER VUI.BindScopedDB has returned a non-nil char table (i.e. at
-- PLAYER_LOGIN, not ADDON_LOADED) and BEFORE the module reads any universal key. Read
-- before, and the feature acts on the pre-migration value for that session.
function VUI.MigrateScopedDB(globalName, universalDefaults, perCharDefaults, flagKey)
    local root = _G[globalName]
    if type(root) ~= "table" then return nil end
    if root[flagKey] then return nil end            -- one-way: never re-run

    local key      = VUI.CharKey()
    local chars    = type(root.chars) == "table" and root.chars or nil
    local slot     = (chars and key) and chars[key] or nil
    local promoted = {}

    for k in pairs(universalDefaults or {}) do
        if slot ~= nil and slot[k] ~= nil then
            root[k] = slot[k]
            promoted[k] = slot[k]
        end
        if chars then
            for _, s in pairs(chars) do s[k] = nil end
        end
    end

    for k in pairs(perCharDefaults or {}) do
        root[k] = nil
    end

    root[flagKey] = true
    return next(promoted) ~= nil and promoted or nil
end

-- ⛔ LEGACY. ZERO SHIPPED CALLERS as of v1.14.6 -- all four modules moved to VUI.BindScopedDB
-- across v1.14.1-v1.14.5. Retained, not deleted, and the reasoning is on the record:
--
--   * Deleting it is TIDINESS WITH NO DEFECT ATTACHED, which this project's audit discipline
--     default-rejects (references/audit-cycle-discipline.md Part 1). Nothing calls it, so it cannot
--     misbehave.
--   * The cost of deleting lands entirely in TEST code: charDB_test exists to test this function,
--     and copy_test/copy_ui_test use it to build their fixtures. Rewriting three working suites is
--     churn in the layer that has produced the most defects during this refactor.
--   * Its remaining value is real: those copy suites exercise VUI.CopyCharSettings through it.
--
-- ⚠ BUT DO NOT USE IT FOR NEW WORK, and do not "restore" a module to it. Its two behaviours are
-- precisely the ones that caused the defects this refactor removed:
--   1. It returns the ACCOUNT ROOT when the character key is unresolvable, so anything called at
--      ADDON_LOADED writes per-character keys into account-wide storage. That is how
--      AdvancedOptions seeded its per-character CVar cache account-wide at load time.
--   2. It seeds a new character's slot from every non-`chars` root key, which pins whatever the
--      shipped default was at that moment -- audit finding D8, the reason a Delve position
--      confirmed on one character never reached any other.
-- VUI.BindScopedDB inverts both deliberately; see its header and scoped_db_test.
--
-- Binds (or re-binds) this character's settings slot inside `globalName`.
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
--  reference (see the "Per-character settings storage" header). Swapping in a new table would leave both
--  pointing at an orphan: the options panel would edit a table nobody reads, and
--  every module read would return pre-copy values until a reload. Keeping table
--  identity means the copy is live for anything that re-reads, and only Interface's
--  hook-based features need the reload they already require by policy.
--
--  Deliberately excluded: PriorityRotation (its rotations are keyed per character
--  AND per specialization, so they cannot map onto a different class) and
--  AuctionHouse (account-wide market data, nothing character-specific). Neither
--  calls VUI.BindScopedDB, which is what enrols a module here (VUI._charDBs), so both
--  are excluded automatically rather than by a list that could rot.
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
    return true, ("Copied settings from " .. VUI.COL.YELLOW .. "%s|r (%d module%s)."):format(
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
-- Each module's command, for the /vui listing. Only modules that are actually loaded are shown.
local MODULE_COMMANDS = {
    { "VeritasUI_AuctionHouse",     "/ah",  "Auction House" },
    { "VeritasUI_AdvancedOptions",  "/ao",  "Advanced Options" },
    { "VeritasUI_Interface",        "/interface", "Interface" },
    { "VeritasUI_PriorityRotation", "/pr",  "Priority Rotation" },
    { "VeritasUI_QualityOfLife",    "/qol", "Quality of Life" },
    { "VeritasUI_ZoneQuests",       "/zq",  "Zone Quests" },
}

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
    elseif cmd == "probe search" and VUI.ProbeSearchTaint then
        VUI.ProbeSearchTaint()
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
    elseif cmd == "debug" then
        -- Suite-wide debug switch (audit S3): lived only as /ah debug, so it vanished with the
        -- Auction House module. /ah debug still works.
        VUI.debug = not VUI.debug
        VUI.Print("VeritasUI", "Debug prints " .. (VUI.debug and VUI.COL.GREEN .. "ON|r (suite-wide)"
            or VUI.COL.RED .. "OFF|r"))
    elseif cmd == "undocopy" then
        local last = VUI.GetUndoableCopy()
        if not last then
            VUI.Print("VeritasUI", "Nothing to undo on this character.")
        else
            StaticPopup_Show("VERITASUI_UNDO_COPY", tostring(last.source))
        end
    else
        VUI.Print("VeritasUI", "Version " .. VUI.VERSION .. " loaded.")
        VUI.Print("VeritasUI", VUI.COL.YELLOW .. "/vui taint|r — show recorded blocked-action events.")
        VUI.Print("VeritasUI", VUI.COL.YELLOW .. "/vui taint clear|r — reset that log.")
        VUI.Print("VeritasUI", VUI.COL.YELLOW .. "/vui hover|r — dump the parent chain under the cursor (5s delay).")
        VUI.Print("VeritasUI", VUI.COL.YELLOW .. "/vui copy|r — copy another character's settings onto this one.")
        VUI.Print("VeritasUI", VUI.COL.YELLOW .. "/vui undocopy|r — undo the last copy on this character.")
        VUI.Print("VeritasUI", VUI.COL.YELLOW .. "/vui debug|r — toggle debug output for every module.")
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        local lines = {}
        for _, m in ipairs(MODULE_COMMANDS) do
            if isLoaded and isLoaded(m[1]) then
                lines[#lines + 1] = VUI.COL.YELLOW .. m[2] .. "|r " .. m[3]
            end
        end
        if #lines > 0 then
            VUI.Print("VeritasUI", "Modules: " .. table.concat(lines, "  ·  "))
        end
    end
end

-- The one login line for the whole suite (audit S2, owner-chosen 2026-10-11). Each module used
-- to print its own "vX loaded" line -- six lines at every login, where WoW's own UI prints none.
-- Warnings and one-time notices still come from the modules themselves.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    VUI.Print("VeritasUI", format("VeritasUI v%s loaded — " .. VUI.COL.YELLOW .. "/vui|r for commands", VUI.VERSION))
end)
