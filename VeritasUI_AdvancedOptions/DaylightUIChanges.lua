-- VeritasUI_AdvancedOptions / DaylightUIChanges.lua
-- The CVars DaylightUI sets, so the All CVars tab indexes them and the Featured tab's UI Replacements
-- section can put the ones still away from Blizzard's default back, as for ElvUI and EllesmereUI
-- (Browser.lua AO.SUITES). Only when the player asks: the same rule as EllesmereUIChanges.lua.
--
-- Read from DaylightUI 2.2.7 source (WoW Forever), 2026-11-25. Left out, as for the other suites: sound
-- volumes (InfoPanel DataTexts.lua:567) and graphics (QoL Sparkles.lua:37, outline modes), and everything
-- DaylightUI already puts back to the player's own value itself -- the NPC camera (Npc/Scene.lua:151),
-- the soft-target settings (QoL Defaults.lua:77), tutorials (QoL Tutorials.lua:25), friendly nameplates
-- in instances (Nameplates Manager.lua:887-889), questPOI (Core.lua:1146) -- and /dui platefix's brief
-- off-and-on of the nameplate switches (PlateReport.lua:1056-1069).
--
-- ⚠ Defaults, not "what you had before DaylightUI" -- the same limit as the other lists.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

AO.DAYLIGHTUI_CVARS = {
    -- Combat text: its own scrolling text keeps the game's switch on (CombatText/Feed.lua:250), its damage
    -- numbers' size and spread (DamageText.lua:109) and what they show (DamageText.lua:128)
    "enableFloatingCombatText", "WorldTextScale_v2", "floatingCombatTextCombatDamageDirectionalScale_v2",
    "floatingCombatTextCombatDamageDirectionalOffset_v2", "floatingCombatTextCombatDamage_v2",
    "floatingCombatTextCombatHealing_v2", "floatingCombatTextPetMeleeDamage_v2",
    "floatingCombatTextPetSpellDamage_v2",
    -- Nameplates (DaylightUI_Nameplates Manager.lua:826-857, :941; Minion.lua:291)
    "nameplateMaxDistance", "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale",
    "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateStackingTypes", "nameplateShowEnemyMinions",
    -- Chat (DaylightUI_Chat Chat.lua:1325-1337)
    "chatClassColorOverride", "showTimestamps", "whisperMode",
    -- Action bars, bags, minimap, damage meter, quests, camera (ActionBars Cooldowns.lua:931, Options.lua:393,
    -- :405; InfoPanel Options.lua:261, Meter.lua:1123; Quests Options.lua:136; QoL Camera.lua:28)
    "cooldownViewerEnabled", "displayFreeBagSlots", "expandBagBar", "rotateMinimap", "damageMeterEnabled",
    "autoQuestWatch", "cameraDistanceMaxZoomFactor",
}

local ipairs, format = ipairs, string.format

local DAYLIGHTUI_SET = {}
for _, name in ipairs(AO.DAYLIGHTUI_CVARS) do DAYLIGHTUI_SET[name] = true end

function AO:IsDaylightUICVar(name)
    return DAYLIGHTUI_SET[name] == true
end

-- Names from the list that exist on this client and differ from Blizzard's default right now.
function AO:DaylightUIChangedCVars()
    local changed = {}
    for _, name in ipairs(AO.DAYLIGHTUI_CVARS) do
        local val, def = AO:GetCVarInfo(name)
        if val ~= nil and def ~= nil and val ~= def then changed[#changed + 1] = name end
    end
    return changed
end

local function DaylightUILoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DaylightUI") and true or false
end
AO.DaylightUILoaded = DaylightUILoaded

-- Reset every listed CVar that still differs from its default. AO:ResetCVar defers to the end of
-- combat and reports that itself, so this works at any time.
function AO:ResetDaylightUIChanges()
    local changed = AO:DaylightUIChangedCVars()
    for _, name in ipairs(changed) do AO:ResetCVar(name) end
    VUI.Print("Advanced Options", format("Reset %d setting%s DaylightUI changes to Blizzard's defaults.",
        #changed, #changed == 1 and "" or "s"))
    if AO.RefreshBrowser then AO:RefreshBrowser() end
    if AO.RefreshFeaturedValues then AO:RefreshFeaturedValues() end
end

StaticPopupDialogs["VERITASUI_AO_RESET_DAYLIGHTUI"] = {
    text = "Reset the %d setting%s DaylightUI changes to Blizzard's defaults?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function() AO:ResetDaylightUIChanges() end,
}
