-- VeritasUI_Lib / Lib.lua
-- Shared utilities for all VeritasUI addons.
-- Access from any addon:  local VUI = _G.VeritasUI

if _G.VeritasUI then return end   -- guard against double-load

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G             = _G
local pairs, ipairs  = pairs, ipairs
local pcall, type    = pcall, type
local next           = next
local math_abs       = math.abs
local format         = string.format
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local InCombatLockdown = InCombatLockdown
local MouseIsOver    = MouseIsOver

local GetMouseFocus  = GetMouseFocus or function()
    local frames = GetMouseFoci()
    return frames and frames[1]
end

----------------------------------------------------------------
--  Namespace
----------------------------------------------------------------
local VUI = {}
_G.VeritasUI = VUI
VUI.VERSION = "1.6.23"

----------------------------------------------------------------
--  Print helpers
----------------------------------------------------------------
function VUI.Print(tag, msg)
    print(format("|cFF00CCFF[%s]|r %s", tag, msg))
end

function VUI.PrintOnOff(tag, label, state)
    local word = state and "|cFF00FF00turned on|r" or "|cFFFF4444turned off|r"
    VUI.Print(tag, label .. " " .. word .. " — |cFFFFFF00/reload|r to apply.")
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
        if not InCombatLockdown() then self:Hide() end
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
local HOVER_POLL_RATE = 0.1    -- ~10 Hz always
local HOVER_LEAVE_GRACE = 0.15 -- seconds after last "not over" before fading

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

    local function IsMouseOverAny()
        if target:IsMouseOver() then return true end
        for i = 1, #childCache do
            local child = childCache[i]
            if child:IsVisible() and child:IsMouseOver() then return true end
        end
        return false
    end

    local hovered    = false
    local graceSince = nil
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
        if self._t < HOVER_POLL_RATE then return end
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
local HOVER_POLL_RATE  = 0.20

function VUI.HookPlayerFrameFade(frame, inCombatRef)
    if not frame then return end
    frame:SetAlpha(0)

    local delayTimer, pollTicker, healthTimer
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

    local function StopPoll()
        if pollTicker then pollTicker:Cancel(); pollTicker = nil end
    end

    local function DoFadeOut()
        delayTimer = nil
        if not ShouldShow() then
            SmoothFade(frame, FADE_OUT_TIME, 0)
            wasShowing = false
            StopPoll()
        end
    end

    local function Evaluate()
        if ShouldShow() then
            if delayTimer then delayTimer:Cancel(); delayTimer = nil end
            if not wasShowing then
                SmoothFade(frame, FADE_IN_TIME, 1)
                wasShowing = true
            end
            if not pollTicker then
                pollTicker = C_Timer.NewTicker(HOVER_POLL_RATE, function()
                    if not ShouldShow() then Evaluate() end
                end)
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

    frame:HookScript("OnEnter", Evaluate)
    frame:HookScript("OnLeave", function() C_Timer.After(0.05, Evaluate) end)

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
    for _, fn in ipairs(pending) do pcall(fn) end
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
    if type(frameName) ~= "string" then return end
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
VUI._settingsLabels = {}
local reloadBtn

function VUI.RegisterSettingsLabel(label)
    VUI._settingsLabels[label] = true
    if not VUI._reloadBtnHooked then VUI._InitReloadButton() end
end

function VUI._InitReloadButton()
    if VUI._reloadBtnHooked then return end
    if not SettingsPanel then return end
    VUI._reloadBtnHooked = true

    SettingsPanel:HookScript("OnShow", function()
        if reloadBtn then return end

        -- Find the Defaults button to anchor beside.
        local defaultsBtn
        local function Search(f)
            for _, child in ipairs({ f:GetChildren() }) do
                if child:IsObjectType("Button") then
                    local t = child:GetText()
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
    end)

    SettingsPanel:HookScript("OnHide", function()
        if reloadBtn then reloadBtn:Hide() end
    end)
end
