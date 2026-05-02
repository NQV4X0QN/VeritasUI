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
local math_max       = math.max
local math_min       = math.min
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
VUI.VERSION = "1.6.12"

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
--  HookHoverFade  (MicroMenu, etc.)
--
--  Uses SmoothFade to avoid Blizzard UIFrameFade table conflicts.
----------------------------------------------------------------
local HOVER_FADE_IN  = 0.2
local HOVER_FADE_OUT = 0.5

function VUI.HookHoverFade(target, shouldStayVisible)
    if not target then return end
    target:SetAlpha(0)

    local function IsLocked()
        return shouldStayVisible and shouldStayVisible()
    end

    local function FadeIn()
        SmoothFade(target, HOVER_FADE_IN, 1)
    end
    local function FadeOut()
        if not IsLocked() and not MouseIsOver(target) then
            SmoothFade(target, HOVER_FADE_OUT, 0)
        end
    end

    local hooked = {}
    local function HookChild(child)
        if not child or hooked[child] or not child.HookScript then return end
        hooked[child] = true
        child:HookScript("OnEnter", FadeIn)
        child:HookScript("OnLeave", function() C_Timer.After(0.1, FadeOut) end)
    end
    local function HookAllChildren()
        for _, child in ipairs({ target:GetChildren() }) do HookChild(child) end
    end

    target:HookScript("OnEnter", FadeIn)
    target:HookScript("OnLeave", function() C_Timer.After(0.1, FadeOut) end)
    HookAllChildren()
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

----------------------------------------------------------------
--  Slim Scrollbar — modern Blizzard-style slim thumb track
--
--  Attaches an 8px vertical scrollbar on the right edge of the
--  given ScrollFrame. Visual style matches modern Blizzard panels
--  (Talents, Collections, Professions) — dark translucent track,
--  lighter thumb, subtle highlight on hover.
--
--  Behavior:
--    • Mousewheel routes to scrollFrame (and also works over the
--      track itself).
--    • Thumb drag via OnMouseDown/Up/OnUpdate — the thumb height
--      is proportional to visible/content ratio.
--    • Clicking the track above/below the thumb page-jumps to
--      that position.
--    • Auto-hides when content fits in the visible area.
--
--  Usage:
--      local update = VUI.AttachSlimScrollbar(myScrollFrame, {
--          wheelStep = 60,        -- pixels per wheel notch (default 30)
--      })
--      -- Call update() after the scrollChild's height changes so
--      -- the thumb resizes/repositions correctly.
--
--  Args:
--    scrollFrame: the ScrollFrame that needs scrolling. Must already
--                 have a scroll child set.
--    opts (table, optional):
--      wheelStep       (number, default 30)  pixels per wheel notch
--      scrollbarWidth  (number, default 8)   thumb/track width
--      gap             (number, default 4)   gap between scrollFrame's
--                                            right edge and the track
--      minThumbHeight  (number, default 24)  minimum thumb height so
--                                            it's always grabbable
--      parent          (Frame, optional)     where to anchor the track
--                                            (default: scrollFrame:GetParent())
--                                            NOTE: the track MUST live
--                                            outside the ScrollFrame so
--                                            it isn't clipped.
--
--  Returns:
--    update, track
--      update: function; call after content-size changes so the thumb
--              recomputes its height and position.
--      track:  the track Frame, for callers that want to tweak visuals.
----------------------------------------------------------------
function VUI.AttachSlimScrollbar(scrollFrame, opts)
    opts = opts or {}
    local wheelStep      = opts.wheelStep      or 30
    local scrollbarWidth = opts.scrollbarWidth or 8
    local gap            = opts.gap            or 4
    local minThumbHeight = opts.minThumbHeight or 24
    local trackParent    = opts.parent or scrollFrame:GetParent()

    -- Track — sits on the right edge of scrollFrame, parented outside
    -- the scroll region so it never clips.
    local track = CreateFrame("Frame", nil, trackParent)
    track:SetWidth(scrollbarWidth)
    track:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    gap, 0)
    track:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", gap, 0)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)

    local trackBorder = track:CreateTexture(nil, "BORDER")
    trackBorder:SetAllPoints()
    trackBorder:SetColorTexture(0.25, 0.25, 0.25, 0.4)

    -- Thumb — drag handle + visual indicator of scroll position.
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(scrollbarWidth)
    thumb:EnableMouse(true)
    thumb:SetMovable(true)
    -- Drag via OnMouseDown/Up/OnUpdate; no RegisterForClicks needed.

    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.45, 0.45, 0.45, 0.8)

    local thumbHover = thumb:CreateTexture(nil, "HIGHLIGHT")
    thumbHover:SetAllPoints()
    thumbHover:SetColorTexture(0.6, 0.6, 0.6, 0.5)

    local function Update()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local trackH    = track:GetHeight()

        if maxScroll <= 0 or trackH <= 0 then
            thumb:Hide()
            return
        end
        thumb:Show()

        -- Thumb height proportional to visible/total ratio, clamped
        -- to minThumbHeight so it remains a comfortable grab target.
        local visibleH = scrollFrame:GetHeight()
        local contentH = visibleH + maxScroll
        local thumbH   = math_max(minThumbHeight, (visibleH / contentH) * trackH)
        thumb:SetHeight(thumbH)

        -- Thumb position proportional to current scroll.
        local curScroll = scrollFrame:GetVerticalScroll()
        local scrollPct = curScroll / maxScroll
        local travel    = trackH - thumbH
        local yOff      = -(scrollPct * travel)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, yOff)
    end

    -- Mousewheel on the scrollFrame.
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = cur - (delta * wheelStep)
        newScroll = math_max(0, math_min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
        Update()
    end)

    -- Mousewheel on the track itself (so wheeling near the edge works).
    track:EnableMouseWheel(true)
    track:SetScript("OnMouseWheel", function(_, delta)
        local cur = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = cur - (delta * wheelStep)
        newScroll = math_max(0, math_min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
        Update()
    end)

    -- Thumb drag — tracks the cursor vertically, maps to scroll range.
    local isDragging = false
    local dragStartY, dragStartScroll
    thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
            dragStartY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
            dragStartScroll = scrollFrame:GetVerticalScroll()
            self:SetScript("OnUpdate", function()
                if not isDragging then return end
                local curY = select(2, GetCursorPosition()) / thumb:GetEffectiveScale()
                local deltaY = dragStartY - curY
                local trackH = track:GetHeight()
                local thumbH = thumb:GetHeight()
                local travel = trackH - thumbH
                if travel <= 0 then return end
                local maxScroll = scrollFrame:GetVerticalScrollRange()
                local scrollDelta = (deltaY / travel) * maxScroll
                local newScroll = math_max(0, math_min(maxScroll, dragStartScroll + scrollDelta))
                scrollFrame:SetVerticalScroll(newScroll)
                Update()
            end)
        end
    end)
    thumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            isDragging = false
            self:SetScript("OnUpdate", nil)
        end
    end)

    -- Click on the track (above or below the thumb) to page-jump.
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local trackTop = self:GetTop()
        if not trackTop then return end
        local clickPct = (trackTop - cursorY) / self:GetHeight()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = math_max(0, math_min(maxScroll, clickPct * maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
        Update()
    end)

    -- ── Hover-fade behaviour ─────────────────────────────────
    -- Track starts hidden, fades in on hover/scroll, lingers for
    -- 1.5s after the last interaction, then fades out.
    local FADE_IN_DUR  = 0.15
    local FADE_OUT_DUR = 0.4
    local LINGER_SEC   = 1.5
    local lingerHandle = nil

    track:SetAlpha(0)

    local function ShowTrack()
        if lingerHandle then lingerHandle:Cancel(); lingerHandle = nil end
        VUI.SmoothFade(track, FADE_IN_DUR, 1)
    end

    local function ScheduleHideTrack()
        if lingerHandle then lingerHandle:Cancel() end
        lingerHandle = C_Timer.NewTimer(LINGER_SEC, function()
            lingerHandle = nil
            -- Don't fade out while dragging
            if isDragging then return end
            VUI.SmoothFade(track, FADE_OUT_DUR, 0)
        end)
    end

    -- Show on mousewheel (already wired above; hook the Update call).
    local origOnMouseWheel = scrollFrame:GetScript("OnMouseWheel")
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        origOnMouseWheel(self, delta)
        ShowTrack()
        ScheduleHideTrack()
    end)

    local origTrackWheel = track:GetScript("OnMouseWheel")
    track:SetScript("OnMouseWheel", function(self, delta)
        origTrackWheel(self, delta)
        ShowTrack()
        ScheduleHideTrack()
    end)

    -- Show on hover over the scrollbar area (track or thumb).
    track:HookScript("OnEnter", function() ShowTrack() end)
    track:HookScript("OnLeave", function() ScheduleHideTrack() end)
    thumb:HookScript("OnEnter", function() ShowTrack() end)
    thumb:HookScript("OnLeave", function()
        if not isDragging then ScheduleHideTrack() end
    end)

    -- Keep visible during drag; schedule hide when drag ends.
    -- HookScript fires after the original OnMouseUp (which clears
    -- isDragging), so ScheduleHideTrack sees the correct state.
    thumb:HookScript("OnMouseUp", function()
        ScheduleHideTrack()
    end)

    -- Show on track click too.
    track:HookScript("OnMouseDown", function() ShowTrack() end)
    track:HookScript("OnMouseUp",   function() ScheduleHideTrack() end)

    return Update, track
end

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
