-- ============================================================
-- PriorityRotation — SpellbookOpener.lua
-- Opens the spellbook from Priority Rotation WITHOUT tainting it.
-- ============================================================
--
-- ⚠ WHY THIS EXISTS (v1.22.1). PR used to open the spellbook itself, calling
-- PlayerSpellsUtil.OpenToSpellBookTab() from its own click handler. The spellbook then set itself
-- up as addon code, and a spell clicked in it reached CastSpellBookItem() tainted:
-- ADDON_ACTION_FORBIDDEN blamed on VeritasUI_PriorityRotation. Owner A/B, 2026-10-28, his UI-restyling AddOn off:
-- opened from an empty PR slot -> blocked; opened from the menu bar -> the same spell cast clean.
--
-- THE FIX, same shape as the sell strip's (v1.17.4): Priority Rotation never opens it. An invisible
-- SecureActionButton is laid over the hovered target and forwards the real click to Blizzard's own
-- menu-bar button, PlayerSpellsMicroButton (type "click", SecureTemplates.lua:560-567), whose
-- OnClick opens the window exactly as the menu bar does (MainMenuBarMicroButtons.lua:852-863).
--
-- ⚠ WOW FOREVER HAS ITS OWN SPELLBOOK BUTTON (v1.74.2). Its menu bar shows SpellbookMicroButton and
-- TalentMicroButton instead of the combined PlayerSpellsMicroButton (Blizzard_MicroMenu/Camelot/
-- MicroMenuContainerOverrides.lua:6-7, forever). The combined button still exists there and opens the tab
-- it suggests -- Talents while a talent point is unspent (MainMenuBarMicroButtons.lua:940-956) -- so an empty
-- PR slot opened the talent window (owner, 2026-11-07). In Forever we forward to SpellbookMicroButton,
-- whose `spellbookOnly` always opens the Spellbook (:947-948). Retail keeps the combined button.
--
-- WHICH TAB: the micro button reopens the last tab, but the window is declared
-- autoMinimizeWithOtherPanels (Blizzard_PlayerSpellsFrame.lua:489-498), so with another UI panel
-- open -- Priority Rotation's own window counts -- the panel manager minimizes it
-- (UIParentPanelManager.lua:763-790), and minimizing moves a tab that cannot be minimized (Talents)
-- to the minimizable one, the Spellbook (Blizzard_PlayerSpellsFrame.lua:431-441). Owner-measured
-- 2026-10-29: last tab Talents, with PR or the character sheet open -> opens on Spellbook; alone ->
-- opens on Talents.
--
-- ⚠ THE OVERLAY IS PARENTED TO UIParent AND POSITIONED BY ABSOLUTE COORDINATES. It is never a child
-- of the PR window and never anchored to it, so the window stays an ordinary insecure frame (a
-- secure descendant or anchor could restrict it in combat). It is hidden in combat and only shown
-- out of combat while the cursor is over a target.
--
-- Mouse handling: SetPropagateMouseMotion(true) lets hover reach the frame beneath, so its tooltip
-- and highlight still work (the pattern QualityOfLife's status-bar overlays use). Clicks are
-- consumed. Shift+click and a click while carrying a spell run the target's insecure handlers from
-- PostClick and forward nothing ("none" is not a SECURE_ACTIONS entry, so PerformAction finds no
-- handler and does nothing: SecureTemplates.lua:733-760).

local _, PR = ...
local VUI = _G.VeritasUI
if not VUI then return end

local POLL = 0.05
local targets = {}       -- ordered list of { frame = f, opts = { isActive, onDrop, onShift } }
local overlay, driver

local function CursorCarriesAbility()
    local kind = GetCursorInfo()
    return kind == "spell" or kind == "macro" or kind == "item"
end

-- Whether the top frame under the cursor is `frame` or something inside it. Keeps the overlay from
-- popping up over a target hidden behind another window (IsMouseOver ignores occlusion).
-- ⚠ Every GetParent is pcall'd and the walk is capped (audit P1): the focus can be a FORBIDDEN
-- object (measured: House Editor pins), whose widget calls raise from addon code -- 20 times a
-- second from Tick. An unreadable chain is not our target. Same shape as Lib's parent walks.
local FOCUS_WALK_MAX_DEPTH = 8
local function FocusIsWithin(frame)
    local foci = GetMouseFoci and GetMouseFoci()
    local f = foci and foci[1]
    local depth = 0
    while f and depth < FOCUS_WALK_MAX_DEPTH do
        if f == frame then return true end
        if not f.GetParent then return false end
        local ok, parent = pcall(f.GetParent, f)
        if not ok then return false end
        f = parent
        depth = depth + 1
    end
    return false
end

local function Place(target)
    local l, b, w, h = target:GetRect()
    if not (l and w and w > 0) then return false end
    local s = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    overlay:SetSize(w * s, h * s)
    return true
end

local function HideOverlay()
    if overlay and overlay:IsShown() and not InCombatLockdown() then overlay:Hide() end
    if overlay then overlay.current = nil end
end

local function Tick()
    if InCombatLockdown() then return end
    local cur = overlay.current
    if cur then
        if cur.frame:IsVisible() and cur.frame:IsMouseOver() and cur.opts.isActive() then return end
        HideOverlay()
    end
    for _, t in ipairs(targets) do
        if t.frame:IsVisible() and t.frame:IsMouseOver() and FocusIsWithin(t.frame) and t.opts.isActive() then
            if Place(t.frame) then
                overlay.current = t
                overlay:Show()
            end
            return
        end
    end
end

local function Build()
    if overlay or InCombatLockdown() then return overlay ~= nil end
    local micro = (VUI.IS_FOREVER and _G.SpellbookMicroButton) or _G.PlayerSpellsMicroButton
    if not micro then return false end

    overlay = CreateFrame("Button", "VUIPRSpellbookOpener", UIParent, "SecureActionButtonTemplate")
    overlay:SetFrameStrata("DIALOG")
    overlay:RegisterForClicks("LeftButtonUp")
    -- Act on release, whatever "cast on key down" says (same reason as the sell strip's buttons,
    -- SecureTemplates.lua:795-814).
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetAttribute("type1", "click")
    overlay:SetAttribute("shift-type1", "none")
    overlay:SetAttribute("clickbutton", micro)
    if overlay.SetPropagateMouseMotion then overlay:SetPropagateMouseMotion(true) end
    overlay:Hide()

    -- Carrying a spell: this click is a drop, so forward nothing. PreClick runs before the secure
    -- action; attributes cannot change in combat, and the overlay is never shown then.
    overlay:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        self._dropping = CursorCarriesAbility() and self.current and self.current.opts.onDrop ~= nil
        self:SetAttribute("type1", self._dropping and "none" or "click")
    end)
    overlay:SetScript("PostClick", function(self)
        local t = self.current
        if not t then return end
        if self._dropping then
            t.opts.onDrop()
        elseif IsShiftKeyDown() and t.opts.onShift then
            t.opts.onShift()
        end
        self._dropping = nil
    end)
    overlay:SetScript("OnReceiveDrag", function(self)
        local t = self.current
        if t and t.opts.onDrop then t.opts.onDrop() end
    end)

    driver = CreateFrame("Frame")
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < POLL then return end
        elapsed = 0
        Tick()
    end)
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:SetScript("OnEvent", HideOverlay)
    return true
end

PR.SpellbookOpener = {}

-- `frame` opens the spellbook on a left-click while opts.isActive() is true.
-- opts.onDrop(): a click or a drag-release while carrying a spell/macro/item.
-- opts.onShift(): a Shift+click.
function PR.SpellbookOpener.AddTarget(frame, opts)
    opts = opts or {}
    opts.isActive = opts.isActive or function() return true end
    targets[#targets + 1] = { frame = frame, opts = opts }
end

-- True once the overlay exists. Callers keep a fallback for when it cannot (no micro button).
function PR.SpellbookOpener.Ready()
    return Build()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Build()
end)
