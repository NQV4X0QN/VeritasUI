-- VeritasUI_QualityOfLife / Journeys.lua
-- ============================================================================
-- Restores the "Show as Experience Bar" checkbox to the Adventure Guide's Journeys
-- "Encounters" cards -- Delves and Prey -- which Blizzard ships without it while the
-- Renown cards above them have it.
--
-- WHY THIS IS A MISSING WIDGET, NOT A MISSING CAPABILITY (all verified against
-- wow-ui-source live, 2026-08-24):
--   * `JourneyCardButtonMixin = CreateFromMixins(RenownCardButtonMixin)`
--     (Blizzard_Journeys.lua:357). The encounter cards ALREADY inherit the OnEnter that
--     reveals the toggle (:335-337) and the OnLeave that hides it (:347-349).
--   * Those are no-ops purely because the guard is `if self.WatchedFactionToggleFrame`,
--     and only `RenownCardButtonTemplate` declares that child (Blizzard_Journeys.xml:57).
--     `JourneyCardButtonTemplate` (xml:113) does not. So creating the child is the whole
--     fix -- Blizzard's own show/hide logic then drives it.
--   * `JourneyCardInitializer` already sets `button.majorFactionData = elementData`
--     (:207-208), identical to the renown initializer, so factionID/isUnlocked are there.
--   * Both card types come from the SAME enumeration -- `GetMajorFactionIDs` (:93-99) --
--     and `ShouldDisplayMajorFactionAsJourney` only chooses which bucket they land in.
--     Delves and Prey are ordinary major factions.
--
-- MEASURED IN GAME (probe v1-v3, owner-confirmed 2026-08-24), because none of it could
-- be read from source:
--   * `C_Reputation.SetWatchedFactionByID` ACCEPTS these factions. Confirmed end to end:
--     watching 2796 "Delves: Season 2" produced a real bar reading
--     `Delves: Season 2 (Warband) 2750 / 4200`, matching the Journeys card exactly.
--   * ⚠ THE WRITE IS ASYNCHRONOUS. `GetWatchedFactionData()` still returns the OLD
--     faction immediately after the call; the new value arrives on `UPDATE_FACTION`.
--     Two successive probes wrongly concluded "REFUSED" by reading it synchronously.
--     NEVER read this back in the same frame to confirm a write.
--   * ⚠ `C_Reputation.GetFactionDataByID` returns NIL for all four journey factions,
--     even unlocked ones -- which is also why they are absent from Character>Reputation
--     (that pane walks `GetNumFactions()` and watches by INDEX, an index they have no
--     entry for; this checkbox watches by ID and needs no index). Blizzard's own
--     `WatchedFactionToggleFrameMixin:OnShow` derives its checked state from that nil
--     call, so it would ALWAYS draw unchecked here. Corrected below -- see OnShow.
--   * `SetWatchedFactionByID` is NOT protected: the probe called it from a plain
--     C_Timer callback with no hardware event and it worked. No taint concern.
--
-- WHAT WE REUSE RATHER THAN REBUILD: Blizzard's global `WatchedFactionToggleFrameMixin`
--   supplies OnClick (the SetWatchedFactionByID call plus
--   `StatusTrackingBarManager:UpdateBarsShown()` and the correct sound), OnEnter and
--   OnLeave verbatim (Blizzard_Journeys.lua:919-947). Only OnShow is overridden, and only
--   for the nil-factionData defect above. `UICheckButtonTemplate` already carries a `Text`
--   fontstring anchored LEFT-to-RIGHT x=-2 (CheckButtonTemplates.xml:54-57) -- the exact
--   anchor Blizzard's Journeys XML re-declares -- so we set that instead of making our own.
--   ⚠ Blizzard's OnShow resolves the card as `self:GetParent():GetParent()` (:922), so the
--   checkbox MUST sit exactly two levels under the card: card -> container -> checkbox.
--   Do not flatten that hierarchy.
-- ============================================================================

local VUI = _G.VeritasUI
if not VUI then
    print("VeritasUI_QualityOfLife: VeritasUI_Lib missing — Journeys checkbox disabled")
    return
end

local CreateFrame    = CreateFrame
local hooksecurefunc = hooksecurefunc
local Mixin          = Mixin
local pcall          = pcall
local type           = type

-- Placement: in the free right-hand part of the card's "Level N/10" row.
--
-- ⚠ ANCHOR TO `JourneyCardLevel`, NOT TO THE PROGRESS BAR OR THE CARD EDGE. Aligning the
-- checkbox with that row is the entire intent, so anchoring to the row itself makes
-- Blizzard own the vertical position: if they ever move it, we inherit the move instead of
-- needing the offset re-tuned by eye. Do not "simplify" this back to a bar-relative or
-- card-relative Y constant.
--
-- The first attempt did anchor to JourneyCardProgressBar (xml:132-136) and sat 4px high.
-- Both routes agree on why: JourneyCardLevel is 10 tall with its bottom at bar top + 5
-- (xml:167-172), so its centre is 10 above the bar, and a 20-tall container centred there
-- needs its bottom at the bar's top -- 4 lower than a +4 bar offset. The owner's
-- independent eyeball measurement was also "about 4 pixels down".
--
-- OFFSET_X reproduces Blizzard's own horizontal inset EXACTLY rather than being eyeballed,
-- so the label ends the same distance from the card's right edge as it does on the Renown
-- cards. Derivation, all from source: their WatchedFactionToggleFrame is a 200-wide frame
-- anchored RIGHT x=30 (xml:57-61), so its left edge sits at cardWidth + 30 - 200; both card
-- templates are 374 wide (xml:6 and xml:114), giving 204 from the card's left edge. Our
-- anchor origin is JourneyCardLevel's left edge, which is the card's x=25 (it inherits
-- JourneyCardName's LEFT, xml:161-171). 204 - 25 = 179.
-- ⚠ If you change the container's 200 width, this constant must be re-derived, not nudged.
-- The first attempt used 145, which left the label ~34px further in than the Renown cards.
local OFFSET_X = 179
local OFFSET_Y = 0

----------------------------------------------------------------
--  Is `factionID` the currently watched faction?
--
--  Replaces the `GetFactionDataByID(...).isWatched` read that Blizzard's OnShow uses,
--  because that call returns nil for every journey faction (measured). GetWatchedFaction-
--  Data is ID-based and does report them.
----------------------------------------------------------------
local function IsWatching(factionID)
    if not factionID or factionID == 0 then return false end
    local ok, watched = pcall(C_Reputation.GetWatchedFactionData)
    if not ok or not watched then return false end
    return watched.factionID == factionID
end

----------------------------------------------------------------
--  Build the toggle on one journey card (idempotent).
----------------------------------------------------------------
local function Attach(card)
    if card.WatchedFactionToggleFrame then return end
    local bar = card.JourneyCardProgressBar
    if not bar then return end   -- not a journey card, or template changed

    local container = CreateFrame("Frame", nil, card)
    container:SetSize(200, 20)
    -- Row-relative when available (see the OFFSET_X/Y comment); the bar is only a fallback
    -- so a template change that drops JourneyCardLevel degrades to a visible checkbox
    -- 4px high rather than to no checkbox at all.
    local row = card.JourneyCardLevel
    if row then
        container:SetPoint("LEFT", row, "LEFT", OFFSET_X, OFFSET_Y)
    else
        container:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", OFFSET_X - 5, 4)
    end
    container:Hide()   -- Blizzard's inherited OnEnter/OnLeave own visibility from here

    local cb = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("LEFT")
    cb:SetHitRectInsets(0, 0, 0, 0)

    local label = cb.Text or cb.Label
    if label then label:SetText(SHOW_FACTION_ON_MAINSCREEN) end

    Mixin(cb, WatchedFactionToggleFrameMixin)

    -- Call Blizzard's OnShow first: it is what resolves self.renownCard and
    -- self.factionID, which its OnClick/OnEnter/OnLeave all depend on. Then fix the
    -- checked state, which it derives from a call that is nil here.
    cb:SetScript("OnShow", function(self)
        pcall(WatchedFactionToggleFrameMixin.OnShow, self)
        if not self.factionID or self.factionID == 0 then
            local data = card.majorFactionData
            self.factionID = data and data.factionID or 0
        end
        self.renownCard = self.renownCard or card
        self:SetChecked(IsWatching(self.factionID))
    end)

    -- Blizzard's handlers verbatim, with the two fields they read guaranteed present in
    -- case a handler ever fires before OnShow has run.
    local function guard(fn)
        return function(self)
            self.renownCard = self.renownCard or card
            if not self.factionID then
                local data = card.majorFactionData
                self.factionID = data and data.factionID or 0
            end
            pcall(fn, self)
        end
    end
    cb:SetScript("OnClick", guard(WatchedFactionToggleFrameMixin.OnClick))
    cb:SetScript("OnEnter", guard(WatchedFactionToggleFrameMixin.OnEnter))
    cb:SetScript("OnLeave", guard(WatchedFactionToggleFrameMixin.OnLeave))

    container.WatchFactionCheckbox = cb
    card.WatchedFactionToggleFrame = container
end

----------------------------------------------------------------
--  Install: post-hook the journey card mixin's OnEnter.
--
--  Hooking the GLOBAL mixin table (writing a KEY, never the global itself) rather than
--  chasing the live frame path: `JourneyCardButtonMixin.OnEnter` is a direct key created
--  by CreateFromMixins, so XML `mixin="JourneyCardButtonMixin"` copies our hooked wrapper
--  onto every card the ScrollBox builds afterwards. That avoids depending on the
--  EncounterJournal frame hierarchy or on the element factory's local initializers
--  (Blizzard_Journeys.lua:254-264), neither of which is reachable from outside.
--
--  Hooking RenownCardButtonMixin is NOT affected -- CreateFromMixins COPIED the function,
--  so the renown cards keep Blizzard's original and are left completely alone.
--
--  ⚠ We must create the toggle AND show it here, because a hooksecurefunc post-hook runs
--  AFTER Blizzard's own `if self.WatchedFactionToggleFrame then :Show()` has already
--  tested a field that did not exist yet. Without the Show, the first hover of a card
--  would build the widget invisibly and only the second hover would reveal it.
--  `isUnlocked` mirrors Blizzard's own condition (:335), so locked tracks get no toggle.
--
--  ORDERING: Blizzard_EncounterJournal is load-on-demand and its card frames are not
--  created until the Journeys list is first laid out, so installing at ADDON_LOADED is
--  always ahead of the first card. A card built before the hook (not observed) simply
--  lacks the toggle until the next /reload.
----------------------------------------------------------------
local installed = false

local function Install()
    if installed then return end
    if type(_G.JourneyCardButtonMixin) ~= "table" then return end
    if type(_G.JourneyCardButtonMixin.OnEnter) ~= "function" then return end
    if type(_G.WatchedFactionToggleFrameMixin) ~= "table" then return end
    installed = true

    hooksecurefunc(_G.JourneyCardButtonMixin, "OnEnter", function(card)
        Attach(card)
        local data = card.majorFactionData
        if card.WatchedFactionToggleFrame and data and data.isUnlocked then
            card.WatchedFactionToggleFrame:Show()
        end
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addon)
    if addon == "Blizzard_EncounterJournal" then
        Install()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Covers a /reload that happens while the Adventure Guide is already loaded, where
-- ADDON_LOADED for it may fire before this file runs.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    Install()
end

----------------------------------------------------------------
--  Click the reputation status bar -> open that faction's own page.
--
--  MAJOR FACTIONS (which is what Delves, Prey and every Renown track are) go to the
--  Journeys page. The four-call sequence is Blizzard's own, lifted verbatim from
--  `ShowMajorFactionRenown` in Blizzard_EncounterJournal_Bootstrap.lua:38-46 -- the path
--  the renown NPC uses:
--      HideUIPanel(EncounterJournal);
--      ShowUIPanel(EncounterJournal);
--      EJ_ContentTab_Select(EncounterJournal.JourneysTab:GetID());
--      EncounterJournalJourneysFrame:ResetView(nil, majorFactionID);
--
--  ⚠ THE ORDER IS LOAD-BEARING, NOT INCIDENTAL -- do not reorder or drop steps.
--  `JourneysFrameMixin:ResetView` picks its destination by asking which subframe is
--  ALREADY shown (Blizzard_Journeys.lua:278-295); its `else` branch at :296 falls back to
--  the main journeys list. So the tab must be selected -- making JourneysList visible --
--  BEFORE ResetView is called, or a click lands on the list instead of the faction page.
--  ResetView itself handles a faction already being open (:285-289 NavBar_Reset + Refresh),
--  so repeat clicks and switching factions are Blizzard's problem, not ours.
--
--  Blizzard_EncounterJournal is load-on-demand, hence the explicit
--  EncounterJournal_LoadUI() -- the bootstrap registers that same function as its loadFunc.
--
--  EVERYTHING ELSE (friendships, plain factions, anything with no Journeys page) opens
--  Character > Reputation selected to that faction, which is the equivalent window for it.
--  The index walk is needed because the pane addresses factions by INDEX, not ID.
--
--  Hooked on the bar frames rather than on their mixin because Blizzard_ActionBar is not
--  load-on-demand: `StatusTrackingBarContainerMixin:InitializeBars`
--  (StatusTrackingManagerOverrides.lua:44-66) has already run and created them by the time
--  we load, so hooking ReputationStatusBarMixin.OnLoad would be too late. Both containers
--  are walked because Main and Secondary each build a full set of bars and EditMode decides
--  which is on screen.
--
--  Taint: safe per our own measured precedent -- the ActionButton hook landmine is about
--  ActionButton CHILDREN (v1.6.14 -> v1.6.15); parent bar frames are fine to hook, and this
--  frame carries no secure attributes. `enableMouse` is already true on
--  StatusTrackingBarTemplate (StatusTrackingBarTemplate.xml:3) and no OnMouseUp exists to
--  displace, so HookScript adds a handler without replacing Blizzard behaviour.
----------------------------------------------------------------
--  TOGGLE SEMANTICS: a second click closes the window, a third reopens it. The close is
--  deliberately NARROW -- it fires only when the window is already showing THIS faction's
--  own page. If the Adventure Guide is open on Dungeons, or on a different faction's
--  journey, a click NAVIGATES to this faction instead of closing; closing there would
--  discard the user's place in a window they were reading for another reason, and it would
--  take two clicks to get where one click should go. ResetView's own
--  already-open branches (Blizzard_Journeys.lua:285-295) exist precisely to make that
--  navigation case work, so we let it.
local function JourneyPageIsShowing(factionID)
    local ej = _G.EncounterJournal
    local journeys = _G.EncounterJournalJourneysFrame
    if not (ej and journeys) then return false end
    if not ej:IsShown() or not journeys:IsShown() then return false end

    -- ResetView parks the faction on JourneyProgress and shows it (:283-284), so this is
    -- the authoritative "which faction am I looking at" read.
    local progress = journeys.JourneyProgress
    if not (progress and progress:IsShown()) then return false end
    local data = progress.majorFactionData
    return (data and data.factionID) == factionID
end

local function OpenMajorFactionJourney(factionID)
    -- Checked BEFORE the load-on-demand block on purpose: if the addon is not loaded these
    -- frames cannot exist, so this correctly returns false and we fall through to opening.
    if JourneyPageIsShowing(factionID) then
        pcall(HideUIPanel, _G.EncounterJournal)
        return true
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded
       and not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
       and _G.EncounterJournal_LoadUI then
        pcall(_G.EncounterJournal_LoadUI)
    end

    local ej = _G.EncounterJournal
    local journeys = _G.EncounterJournalJourneysFrame
    if not (ej and journeys and journeys.ResetView) then return false end

    pcall(HideUIPanel, ej)
    pcall(ShowUIPanel, ej)
    if ej.JourneysTab and _G.EJ_ContentTab_Select then
        pcall(_G.EJ_ContentTab_Select, ej.JourneysTab:GetID())
    end
    pcall(journeys.ResetView, journeys, nil, factionID)
    return true
end

-- Same narrow rule as JourneyPageIsShowing, for the non-major-faction path.
local function ReputationPaneIsShowing(factionID)
    local charFrame, repFrame = _G.CharacterFrame, _G.ReputationFrame
    if not (charFrame and repFrame) then return false end
    if not charFrame:IsShown() or not repFrame:IsShown() then return false end

    local okIndex, index = pcall(C_Reputation.GetSelectedFaction)
    if not okIndex or not index then return false end
    local okData, data = pcall(C_Reputation.GetFactionDataByIndex, index)
    if not okData or not data then return false end
    return data.factionID == factionID
end

local function OpenReputationPane(factionID)
    if ReputationPaneIsShowing(factionID) then
        if _G.ToggleCharacter then pcall(_G.ToggleCharacter, "ReputationFrame") end
        return
    end

    local okCount, count = pcall(C_Reputation.GetNumFactions)
    for i = 1, (okCount and count) or 0 do
        local ok, data = pcall(C_Reputation.GetFactionDataByIndex, i)
        if ok and data and data.factionID == factionID then
            pcall(C_Reputation.SetSelectedFaction, i)
            if _G.EventRegistry then
                pcall(_G.EventRegistry.TriggerEvent, _G.EventRegistry,
                      "ReputationFrame.NewFactionSelected")
            end
            break
        end
    end
    if _G.CharacterFrame and not _G.CharacterFrame:IsShown() and _G.ToggleCharacter then
        pcall(_G.ToggleCharacter, "ReputationFrame")
    end
end

local function OpenFactionPage(factionID)
    if not factionID or factionID == 0 then return end

    local ok, isMajor = pcall(C_Reputation.IsMajorFaction, factionID)
    if ok and isMajor and OpenMajorFactionJourney(factionID) then return end

    OpenReputationPane(factionID)
end

----------------------------------------------------------------
--  Honor bar -> the PvP UI (v1.15.1).
--
--  `TogglePVPUI()` is the whole implementation, and it ALREADY has the narrow-close
--  behaviour we hand-rolled for the reputation path. It is
--  `PVEFrame_ToggleFrame("PVPUIFrame", nil)` (Blizzard_PVPUI_Bootstrap.lua:7-9), and
--  PVEFrame_ToggleFrame (PVEFrame.lua:31-56) closes ONLY when PVEFrame is shown AND
--  PVPUIFrame is the side panel currently up (:45-48); if PVEFrame is open on some other
--  panel it falls through to PVEFrame_ShowFrame and NAVIGATES. It also owns the
--  load-on-demand of Blizzard_PVPUI and the `C_LFGInfo.CanPlayerUseGroupFinder` guard.
--  So: do NOT add toggle logic, an IsShown check, or a LoadUI call here. It is one call by
--  design, and it is the same function Blizzard's own TOGGLEPVPUI keybinding invokes.
----------------------------------------------------------------
local function ToggleHonorUI()
    if _G.TogglePVPUI then pcall(_G.TogglePVPUI) end
end

local hookedBars = {}

----------------------------------------------------------------
--  Hook every status bar we have a destination for.
--
--  Add a bar by adding one entry to `actions` -- the enum key comes from
--  StatusTrackingBarInfo.BarsEnum (StatusTrackingManager.lua:5). Deliberately NOT wired:
--  Experience (no "experience window" exists), Artifact, Azerite, HouseFavor -- none were
--  asked for, and a click that opens something surprising is worse than a click that does
--  nothing.
----------------------------------------------------------------
local function HookStatusBars()
    local manager = _G.StatusTrackingBarManager
    local info    = _G.StatusTrackingBarInfo
    if not (manager and manager.barContainers and info and info.BarsEnum) then return false end

    local actions = {
        [info.BarsEnum.Reputation] = function(bar)
            local okData, watched = pcall(C_Reputation.GetWatchedFactionData)
            local factionID = (okData and watched and watched.factionID) or bar.factionID
            OpenFactionPage(factionID)
        end,
        [info.BarsEnum.Honor] = ToggleHonorUI,
    }

    local found = false
    for _, container in ipairs(manager.barContainers) do
        for barIndex, action in pairs(actions) do
            local bar = container.bars and container.bars[barIndex]
            if bar then
                found = true
                if not hookedBars[bar] then
                    hookedBars[bar] = true
                    bar:HookScript("OnMouseUp", function(self, button)
                        if button ~= "LeftButton" then return end
                        action(self)
                    end)
                end
            end
        end
    end
    return found
end

local barLoader = CreateFrame("Frame")
barLoader:RegisterEvent("PLAYER_LOGIN")
barLoader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not HookStatusBars() then
        -- Containers exist but bars not built yet: retry once next frame rather than
        -- silently doing nothing.
        C_Timer.After(0, HookStatusBars)
    end
end)
