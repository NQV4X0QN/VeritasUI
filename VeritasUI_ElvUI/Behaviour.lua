-- VeritasUI_ElvUI / Behaviour.lua
-- Phase 4: features that cannot work, or work differently, because ElvUI draws that part of the
-- screen itself. Unlike the skins, these do not follow ElvUI's skin switch: they depend on which
-- frames ElvUI replaces, not on how anything looks.

local _, NS = ...
local VUI = _G.VeritasUI
if not (VUI and NS.E) then return end

----------------------------------------------------------------
--  Clean Solo: the fades and the hidden buttons
----------------------------------------------------------------
-- ElvUI hides Blizzard's action bars, player frame, micro menu and bag bar and draws its own, and
-- runs its own chat panels, so these Clean Solo options act on frames ElvUI has replaced or
-- already controls. Owner-tested with ElvUI, 2026-10-28: the fades had no effect; the button and
-- macro-name hides are handled by ElvUI's own options (owner's call, same day). Must run before
-- PLAYER_LOGIN, when Clean Solo reads these; this file loads after Clean Solo (OptionalDeps).
if VUI.SetOptionUnavailable then
    local REASON = "Not available with ElvUI (handled by ElvUI)."
    for _, key in ipairs({ "fadeChatTabs", "transparentChatBG", "fadeMicroMenu",
                           "fadePlayerFrame", "fadeActionBars", "fadeDelay",
                           "hideSocialButton", "hideChatButtons", "hideVoiceChatButton",
                           "hideBagButtons", "hideMacroNames" }) do
        VUI.SetOptionUnavailable("VeritasUI_CleanSolo", key, REASON)
    end
end

----------------------------------------------------------------
--  Quality of Life: auto repair and auto sell junk -- only while ElvUI's own is on
----------------------------------------------------------------
-- Unlike Clean Solo's options these still work under ElvUI, and ElvUI ships its versions off, so
-- they are given up only when the player has switched ElvUI's on: otherwise both would act at
-- every merchant. ElvUI's switches: General > Automation > Auto Repair, E.db.general.autoRepair
-- 'NONE' / 'GUILD' / 'PLAYER' (ElvUI_Options/Game/Shared/General.lua:116; read by
-- Misc.lua:241), and Bags > Vendor Grays > Enable, E.db.bags.vendorGrays.enable
-- (ElvUI_Options/Game/Shared/Bags.lua:252; read by Misc.lua:239).
--
-- Read at file load, before Quality of Life's PLAYER_LOGIN reads the marks. E:PrepDB fills E.db
-- from the saved profile in ElvUI's OnInitialize (Initialize.lua:680, :714-715), which AceAddon runs
-- on ElvUI's ADDON_LOADED -- before this addon loads, since it depends on ElvUI (load order
-- inferred, not probed). If E.db were not ready, nothing is marked and both features simply run,
-- which is the pre-existing behaviour. A change to either ElvUI switch applies after a /reload.
if VUI.SetOptionUnavailable then
    local db = NS.E.db
    local general = db and db.general
    if general and general.autoRepair and general.autoRepair ~= "NONE" then
        VUI.SetOptionUnavailable("VeritasUI_QualityOfLife", "autoRepair",
            "Not available while ElvUI's Auto Repair is on.")
    end
    local grays = db and db.bags and db.bags.vendorGrays
    if grays and grays.enable then
        VUI.SetOptionUnavailable("VeritasUI_QualityOfLife", "autoSellJunk",
            "Not available while ElvUI's Vendor Grays is on.")
    end
end

----------------------------------------------------------------
--  Quality of Life: reputation bar click
----------------------------------------------------------------
-- Clicking Blizzard's reputation bar opens the watched faction's page (Journeys.lua). ElvUI hides
-- that bar and shows its own, whose holder frame opens the character pane's reputation tab
-- (ElvUI/Game/Shared/Modules/DataBars/Reputation.lua:203-207, wired as the holder's OnMouseDown
-- in DataBars.lua:36). Give ElvUI's bar the same left-click as Blizzard's. Other buttons, combat
-- (ElvUI refuses there with its own message), and a session without Quality of Life fall through
-- to ElvUI's handler unchanged.
--
-- The honor bar needs nothing: ElvUI's runs TogglePVPUI (Honor.lua:78-80), which is exactly
-- what Quality of Life's honor click does.
local wired = false
local function WireReputationBar()
    if wired then return true end
    local holder = _G.ElvUI_ReputationBarHolder
    if not (holder and holder.GetScript) then return false end
    local original = holder:GetScript("OnMouseDown")
    holder:SetScript("OnMouseDown", function(self, button, ...)
        if button == "LeftButton" and not InCombatLockdown() and VUI.OpenWatchedFactionPage then
            VUI.OpenWatchedFactionPage()
        elseif original then
            original(self, button, ...)
        end
    end)
    wired = true
    return true
end

-- ElvUI builds its data bars while initialising at login; the order of login handlers between
-- addons is not something to rely on, so retry a bounded number of times, as Journeys.lua does.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local attemptsLeft = 10
    local function Try()
        if WireReputationBar() then return end
        attemptsLeft = attemptsLeft - 1
        if attemptsLeft > 0 then C_Timer.After(0.5, Try) end
    end
    Try()
end)

NS.WireReputationBar = WireReputationBar
