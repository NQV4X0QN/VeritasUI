-- VeritasUI_AuctionHouse / UI/TabInject.lua
-- Phase 4: inject our own tab(s) into Blizzard's AuctionHouseFrame, matching the
-- native Buy/Sell/Auctions strip. This is the module's first in-AH UI surface.
-- Content for each tab is supplied by a sibling file (e.g. UI/BrowseTab.lua) via
-- AH.UI.AddTab; this file owns ONLY the injection machinery (tab buttons, the
-- SetDisplayMode hook, tab switching, anchoring, idempotent re-injection).
--
-- Authoritative design: AUCTIONHOUSE_DESIGN.md §2.9 (verified vs Blizzard 12.0.5).
-- The hard-won facts that shape this file:
--
--  * parentArray TRAP. The base PanelTabButtonTemplate carries parentArray="Tabs",
--    and the AH tab template chain inherits it
--    (AuctionHouseFrameTabTemplate -> PanelTabButtonTemplate). So ANY button created
--    from that template is auto-appended to its PARENT frame's `.Tabs` array. If we
--    parented our tab button to AuctionHouseFrame, it would silently land in
--    AuctionHouseFrame.Tabs and pollute Blizzard's protected tab system. MITIGATION
--    (structural, not stylistic): our tab button is parented to OUR OWN root frame,
--    so the auto-insert lands in root.Tabs and never touches Blizzard's array.
--
--  * Inherit AuctionHouseFrameTabTemplate, NOT the DisplayMode variant. The
--    DisplayMode mixin's OnClick drives Blizzard's SetDisplayMode; the plain tab
--    template gives the identical native look + OnShow auto-resize with no OnClick to
--    fight. We attach our own OnClick.
--
--  * SetDisplayMode hook MUST guard on `#mode > 0`. Our own SetDisplayMode({}) call
--    (used to tear down Blizzard's view when our tab is clicked) re-enters the hook
--    with an EMPTY table; without the guard we would deselect the very tab we are
--    about to select, fighting ourselves.
--
--  * Idempotent re-injection. AuctionHouseFrame is LoadOnDemand and re-shows on every
--    AH open. We create our frames ONCE (reuse-if-present) and only re-resolve the
--    anchor on subsequent opens. No duplicate tabs.
--
--  * TSM-style scale guard. Some addons "hide" the AH by scaling it < 0.5 instead of
--    hiding it; building tabs at that scale corrupts positioning. We defer until the
--    frame is full-size.
--
-- Taint note: SetDisplayMode / SetTitle / show-hide / PanelTemplates_* are ordinary
-- (non-protected) UI calls. Driving them from our code does not taint Blizzard's
-- protected Buy/Sell write paths (those require a hardware-event origin, an
-- independent concern handled in Phase 5/6). This is the same boundary Auctionator
-- operates within (studied for reference only; zero code reuse).

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize globals
----------------------------------------------------------------
local CreateFrame   = CreateFrame
local hooksecurefunc = hooksecurefunc
local ipairs        = ipairs
local type          = type
local tinsert       = table.insert
local pcall         = pcall
local PanelTemplates_SelectTab   = PanelTemplates_SelectTab
local PanelTemplates_DeselectTab = PanelTemplates_DeselectTab
local PanelTemplates_TabResize   = PanelTemplates_TabResize

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
-- Inherit the plain AH tab template (native look + OnShow auto-resize, no
-- display-mode OnClick). See header note.
local TAB_TEMPLATE  = "AuctionHouseFrameTabTemplate"
local TAB_PADDING   = 20   -- matches AuctionHouseFrameTabMixin (TAB_PADDING)
local TAB_MIN_WIDTH = 70   -- matches AuctionHouseFrameTabMixin (MIN_TAB_WIDTH)

-- Anchor relationship between adjacent tabs. The AUTHORITATIVE native spacing is set
-- at runtime by PanelTemplates_AnchorTabs (called from AuctionHouseFrameMixin:OnLoad
-- via PanelTemplates_SetNumTabs), which re-anchors every native tab as:
--     thisTab:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", 3, 0)
-- This OVERRIDES the LEFT/RIGHT x=-15 anchors written in Blizzard_AuctionHouseFrame.xml
-- (those are only the pre-OnLoad initial state). Matching the runtime values —
-- TOPLEFT -> previous TOPRIGHT, x=3 — places our tab with the exact native gap.
-- (LibAHTab independently uses OFFSET_X=3 with TOPLEFT/TOPRIGHT, corroborating this.)
local ANCHOR_POINT, ANCHOR_REL, ANCHOR_X, ANCHOR_Y = "TOPLEFT", "TOPRIGHT", 3, 0

local MIN_SCALE = 0.5   -- below this, AuctionHouseFrame is "hidden" by scale (TSM)

-- Default body region for content frames (inset from AuctionHouseFrame). Verified
-- against native subframe anchors (Blizzard_AuctionHouseFrame.xml, 12.0.5):
--   SearchBar:    TOPRIGHT (-12, -29)        -- top strip clears the title bar
--   CategoriesList(left): LEFT x=4, TOP = SearchBar BOTTOM -4
--   BrowseResultsFrame:   RIGHT x=-23
--   Money frame occupies the bottom ~27px (MoneyFrameBorder at BOTTOMLEFT y=6, h=19).
-- So our content body spans the full inner frame BELOW the title band and ABOVE the
-- money frame. Content owners (ShoppingTab) anchor their search strip TOPRIGHT and
-- their left/right panels below it, mirroring the native offsets above.
--   top:    -28  (just under the title bar; the search strip itself sits at ~ -29)
--   bottom: +28  (clears the money frame so bottom buttons don't collide with gold)
--   left:    +4  (matches CategoriesList LEFT x=4)
--   right:   -8  (our results use an OUTSIDE scrollbar in the right margin, so we don't
--                 need Blizzard's wider -23 reserve; extend closer to the frame edge)
local CONTENT_L, CONTENT_T, CONTENT_R, CONTENT_B = 4, -28, -8, 28

----------------------------------------------------------------
--  State
----------------------------------------------------------------
AH.UI = AH.UI or {}

local state = {
    root     = nil,    -- our private root frame (parent of our tab buttons)
    hooked   = false,  -- SetDisplayMode hook installed
    selected = nil,    -- currently-selected entry (one of ours) or nil
    tabs     = {},     -- ordered array of entries { key, label, header, onShow, button, content }
    byKey    = {},     -- key -> entry
    pending  = {},     -- specs registered before injection (built on first EnsureInjected)
}

-- Forward declarations (mutual references between helpers).
local EnsureInjected, LayoutTabs, BuildTab, SelectTab

----------------------------------------------------------------
--  Tab anchoring
----------------------------------------------------------------
-- The native tab to anchor our first tab against: the rightmost SHOWN tab in
-- AuctionHouseFrame.Tabs (by computed right edge, so a hidden tab can't strand us),
-- falling back to the last native tab if right edges aren't computed yet.
-- NOTE (design §2.9, OQ#1b): full coexistence with OTHER tab-injecting AH addons
-- (anchoring past their injected tabs too) is intentionally deferred — reliably
-- detecting a foreign addon's tabs (grandchildren via their own root frames) is
-- fragile, and this is a single-AH-addon account. We re-resolve on every open so a
-- layout shift can't strand us; foreign-tab walking can be added here later without
-- restructuring if a second AH addon is ever installed.
local function GetAnchorTab()
    local tabs = AuctionHouseFrame and AuctionHouseFrame.Tabs
    if not tabs or #tabs == 0 then return nil end

    local best, bestRight
    for _, t in ipairs(tabs) do
        if t.IsShown and t:IsShown() then
            local r = t.GetRight and t:GetRight()
            if r and (not bestRight or r > bestRight) then
                best, bestRight = t, r
            end
        end
    end
    return best or tabs[#tabs]
end

-- Position our tabs in order: the first against the native anchor tab, each
-- subsequent one against the previous of ours. Re-resolvable any time.
function LayoutTabs()
    local anchor = GetAnchorTab()
    if not anchor then return end
    for i, e in ipairs(state.tabs) do
        local rel = (i == 1) and anchor or state.tabs[i - 1].button
        e.button:ClearAllPoints()
        e.button:SetPoint(ANCHOR_POINT, rel, ANCHOR_REL, ANCHOR_X, ANCHOR_Y)
    end
end

----------------------------------------------------------------
--  Tab selection
----------------------------------------------------------------
-- Switch to one of OUR tabs. Tears down Blizzard's view via SetDisplayMode({})
-- (empty list -> Blizzard hides all its subframes and selects no native tab; our
-- hook ignores it because #mode == 0), deselects every tab (native + ours), selects
-- ours, retitles, and shows our content. Pure UI show/hide — no protected calls.
function SelectTab(entry)
    if not AuctionHouseFrame then return end

    AuctionHouseFrame:SetDisplayMode({})
    AuctionHouseFrame.displayMode = nil

    for _, t in ipairs(AuctionHouseFrame.Tabs) do
        PanelTemplates_DeselectTab(t)
    end
    for _, e in ipairs(state.tabs) do
        PanelTemplates_DeselectTab(e.button)
        e.content:Hide()
    end

    PanelTemplates_SelectTab(entry.button)
    AuctionHouseFrame:SetTitle(entry.header)
    entry.content:Show()
    state.selected = entry

    if entry.onShow then
        local ok, err = pcall(entry.onShow, entry.content)
        if not ok and VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444tab onShow error|r ("
                .. tostring(entry.key) .. "): " .. tostring(err))
        end
    end
end

----------------------------------------------------------------
--  SetDisplayMode hook
--
--  When Blizzard switches to a REAL display mode (a non-empty subframe list — i.e.
--  the user clicked Buy/Sell/Auctions), tear down OUR view: hide our content and
--  deselect our tabs. The `#mode > 0` guard is essential: our own SelectTab calls
--  SetDisplayMode({}) (empty), which must NOT trigger this teardown.
----------------------------------------------------------------
local function InstallHook()
    if state.hooked then return end
    hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
        if type(mode) == "table" and #mode > 0 then
            for _, e in ipairs(state.tabs) do
                e.content:Hide()
                PanelTemplates_DeselectTab(e.button)
            end
            state.selected = nil
        end
    end)
    state.hooked = true
end

----------------------------------------------------------------
--  Tab construction
----------------------------------------------------------------
-- Build one tab from a spec:
--   spec = {
--     key    = "browse",                  -- unique string id (required)
--     label  = "Browse",                  -- tab button text (required)
--     header = "Auction House — Browse",  -- AH title shown when active (required)
--     build  = function(content) end,     -- one-time content setup (optional)
--     onShow = function(content) end,     -- run each time the tab is selected (optional)
--   }
-- The content frame is parented to AuctionHouseFrame (NOT our root) and given a
-- default body region; content owners re-anchor their own children freely. (Content
-- frames carry no tab template, so no parentArray concern — only the BUTTON does.)
function BuildTab(spec)
    local content = CreateFrame("Frame", nil, AuctionHouseFrame)
    content:SetPoint("TOPLEFT",     AuctionHouseFrame, "TOPLEFT",     CONTENT_L, CONTENT_T)
    content:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", CONTENT_R, CONTENT_B)
    content:Hide()

    -- Parented to OUR root so the inherited parentArray="Tabs" lands in root.Tabs,
    -- never AuctionHouseFrame.Tabs. This is the structural clean-room guarantee.
    local button = CreateFrame("Button", nil, state.root, TAB_TEMPLATE)
    button:SetText(spec.label)
    PanelTemplates_TabResize(button, TAB_PADDING, nil, TAB_MIN_WIDTH)

    local entry = {
        key     = spec.key,
        label   = spec.label,
        header  = spec.header,
        onShow  = spec.onShow,
        button  = button,
        content = content,
    }
    button:SetScript("OnClick", function() SelectTab(entry) end)

    tinsert(state.tabs, entry)
    state.byKey[spec.key] = entry

    if spec.build then
        local ok, err = pcall(spec.build, content)
        if not ok and VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444tab build error|r ("
                .. tostring(spec.key) .. "): " .. tostring(err))
        end
    end

    LayoutTabs()
    return entry
end

----------------------------------------------------------------
--  Injection lifecycle (idempotent; scale-guarded)
----------------------------------------------------------------
local retryFrame   -- OnUpdate ticker used only while waiting out a sub-0.5 scale

local function ScheduleRetry()
    if not retryFrame then retryFrame = CreateFrame("Frame") end
    retryFrame:SetScript("OnUpdate", function(self)
        if AuctionHouseFrame and AuctionHouseFrame:GetScale() >= MIN_SCALE then
            self:SetScript("OnUpdate", nil)
            EnsureInjected()
        end
    end)
end

-- Create our injection scaffold once; thereafter just re-resolve the anchor. Safe to
-- call on every AH open. Bails cleanly if the AH frame isn't loaded yet or is scaled
-- down (TSM workaround).
function EnsureInjected()
    if not AuctionHouseFrame then return end
    if AuctionHouseFrame:GetScale() < MIN_SCALE then
        ScheduleRetry()
        return
    end

    if not state.root then
        state.root = CreateFrame("Frame", nil, AuctionHouseFrame)
        state.root:SetSize(1, 1)
        state.root:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT")
        InstallHook()

        -- Build any tabs registered before the AH frame existed.
        local pend = state.pending
        state.pending = {}
        for _, spec in ipairs(pend) do
            BuildTab(spec)
        end

        if VUI.debug then
            VUI.Print(AH.TAG, "Tab injection ready (" .. #state.tabs .. " tab(s)).")
        end
    else
        -- Already injected — re-resolve the anchor in case the strip shifted.
        LayoutTabs()
    end
end

----------------------------------------------------------------
--  Public API
----------------------------------------------------------------
-- Register a tab. Called by content files (e.g. UI/BrowseTab.lua) at load time,
-- which is BEFORE AuctionHouseFrame exists (LoadOnDemand) — so we queue the spec and
-- build it on first injection. If called after injection, builds immediately.
-- Returns the entry (post-injection) or nil (queued).
function AH.UI.AddTab(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string"
       or type(spec.label) ~= "string" or type(spec.header) ~= "string" then
        if VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444AddTab: bad spec|r (need key/label/header strings).")
        end
        return nil
    end
    if state.byKey[spec.key] then
        return state.byKey[spec.key]   -- already registered; idempotent
    end

    if state.root then
        return BuildTab(spec)
    end
    tinsert(state.pending, spec)
    return nil
end

-- Diagnostics / programmatic control.
function AH.UI.IsInjected()  return state.root ~= nil end
function AH.UI.GetTab(key)   return state.byKey[key] end
function AH.UI.SelectByKey(key)
    local e = state.byKey[key]
    if e then SelectTab(e) end
end

----------------------------------------------------------------
--  Trigger: ensure injection as soon as the AH UI exists, and on every open
--
--  AuctionHouseFrame is LoadOnDemand. Two independent triggers, both idempotent, so
--  we're correct regardless of event ordering (design §2.9: "hook ADDON_LOADED for
--  Blizzard_AuctionHouseUI, OR guard on first AUCTION_HOUSE_SHOW"):
--    1. ADDON_LOADED for Blizzard_AuctionHouseUI — fires exactly when the frame is
--       created. Also covers the case where another addon force-loads the AH UI.
--    2. AH_OPEN (Core, on AUCTION_HOUSE_SHOW) — re-resolves the anchor each open and
--       backstops #1 if the addon was somehow already loaded before we hooked.
----------------------------------------------------------------
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_AuctionHouseUI" then
        self:UnregisterEvent("ADDON_LOADED")
        EnsureInjected()
    end
end)

-- If the AH UI is already loaded by the time this file runs, inject now (the
-- ADDON_LOADED above would never fire for it again).
if IsAddOnLoaded and IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    loader:UnregisterEvent("ADDON_LOADED")
    EnsureInjected()
end

if AH.Events and AH.Events.On then
    AH.Events.On("AH_OPEN", function()
        EnsureInjected()
    end)
end
