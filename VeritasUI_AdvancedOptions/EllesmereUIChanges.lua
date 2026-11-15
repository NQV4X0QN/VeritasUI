-- VeritasUI_AdvancedOptions / EllesmereUIChanges.lua
-- The CVars EllesmereUI sets, so the All CVars tab indexes them and the Featured tab's UI Replacements
-- section can put the ones still away from Blizzard's default back, as for ElvUI (Browser.lua AO.SUITES).
--
-- ⚠ ONLY WHEN THE PLAYER ASKS (owner, 2026-11-14). A v1.89.0 test build offered a "Changed by EllesmereUI"
-- checkbox whenever any CVar below differed from its default. Many are ordinary settings players change
-- themselves (camera distance, brightness), so someone who never installed EllesmereUI saw an addon named
-- as having changed their settings. There is no record to gate on instead: the game can keep a CVar on the
-- account server (C_CVar.GetCVarInfo's isStoredServerAccount, Blizzard_APIDocumentationGenerated/
-- CVarDocumentation.lua:95), so EllesmereUI run on another computer changes it here too (owner: run on
-- the Mac, PC settings changed, EllesmereUI never installed there).
--
-- Read from EllesmereUI v9.6.9 source, 2026-10-29. Its own Uninstall (EllesmereUI_Uninstall.lua
-- :1-62) only puts a setting back while it still holds EllesmereUI's value, and its graphics and
-- sound writes bypass that record entirely, so leftovers are expected. Its graphics and sound
-- CVars are left out here for the same reason ElvUI's are: they are the player's own choices far
-- more often than an addon's.
--
-- ⚠ Defaults, not "what you had before EllesmereUI" -- the same limit as the ElvUI list.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

AO.ELLESMEREUI_CVARS = {
    -- Global settings: smart defaults + Lua errors (EllesmereUIOptions/EUI__General_Options.lua
    -- :1751-1768), lag tolerance and combat text size (same file)
    "cameraDistanceMaxZoomFactor", "ActionButtonUseKeyDown", "scriptErrors", "SpellQueueWindow",
    "WorldTextScale_v2",
    -- Spell ID on tooltip, aura IDs drawn by the game itself (EllesmereUI/EllesmereUI.lua:4436)
    "tooltipShowAuraSpellIDs",
    -- Nameplates (EllesmereUINameplates: EUI_Nameplates_Init.lua, _CastState.lua, _PlatePool.lua)
    "nameplateShowEnemies", "nameplateShowAll", "nameplateShowEnemyPets", "nameplateShowFriendlyNPCs",
    "nameplateShowFriendlyPlayers", "nameplateShowOnlyNameForFriendlyPlayerUnits",
    "nameplateUseClassColorForFriendlyPlayerUnitNames", "UnitNameFriendlyPlayerName",
    "ShowClassColorInNameplate", "ShowClassColorInFriendlyNameplate", "clampTargetNameplateToScreen",
    "nameplateSize", "nameplateStackingTypes", "nameplateOverlapH", "nameplateTargetBehindMaxDistance",
    "nameplateMaxAlpha", "nameplateMaxAlphaDistance", "nameplateMinAlpha", "nameplateMinAlphaDistance",
    "nameplateMaxScale", "nameplateMinScale", "nameplateSelectedScale", "nameplateOccludedAlphaMult",
    "nameplateMaxDistance", "nameplateMotionSpeed", "nameplateTopInset",
    "NamePlateEnemyNpcAuraDisplay", "NamePlateEnemyPlayerAuraDisplay",
    -- Mythic+ kick plates (EllesmereUIMythicTimer/EUI_MythicTimer_KickPlates.lua)
    "nameplateGlobalScale",
    -- Tooltips (EllesmereUIBlizzardSkin/EUI_BlizzardSkin_TooltipAnchor.lua)
    "UberTooltips",
    -- Chat and chat bubbles (EllesmereUIChat/EUI_Chat_Init.lua,
    -- EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_ChatBubbles.lua)
    "showTimestamps", "chatMouseScroll", "chatBubblesParty", "chatBubblesRaid",
    -- Action bars, minimap, damage meter, cooldown manager, aura bars, auto logging
    -- (EUI_ActionBars_Events.lua, EUI_Minimap_Apply.lua, EUI_DamageMeters_Lifecycle.lua,
    -- EUI_CDM_Lifecycle.lua, EUI_PlayerAuraBars_Bars.lua, EllesmereUIQoL_AutoLogging.lua)
    "countdownForCooldowns", "rotateMinimap", "damageMeterEnabled", "cooldownViewerEnabled",
    "CursorFreelookStartDelta", "advancedCombatLogging",
    -- Party Mode's temporary screen effect (EllesmereUI/EllesmereUI_PartyMode.lua), written without
    -- the Uninstall record
    "brightness", "contrast",
}

local ipairs, format = ipairs, string.format

local ELLESMEREUI_SET = {}
for _, name in ipairs(AO.ELLESMEREUI_CVARS) do ELLESMEREUI_SET[name] = true end

function AO:IsEllesmereUICVar(name)
    return ELLESMEREUI_SET[name] == true
end

-- Names from the list that exist on this client and differ from Blizzard's default right now.
function AO:EllesmereUIChangedCVars()
    local changed = {}
    for _, name in ipairs(AO.ELLESMEREUI_CVARS) do
        local val, def = AO:GetCVarInfo(name)
        if val ~= nil and def ~= nil and val ~= def then changed[#changed + 1] = name end
    end
    return changed
end

local function EllesmereUILoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUI") and true or false
end
AO.EllesmereUILoaded = EllesmereUILoaded

-- Reset every listed CVar that still differs from its default. AO:ResetCVar defers to the end of
-- combat and reports that itself, so this works at any time.
function AO:ResetEllesmereUIChanges()
    local changed = AO:EllesmereUIChangedCVars()
    for _, name in ipairs(changed) do AO:ResetCVar(name) end
    VUI.Print("Advanced Options", format("Reset %d setting%s EllesmereUI changes to Blizzard's defaults.",
        #changed, #changed == 1 and "" or "s"))
    if AO.RefreshBrowser then AO:RefreshBrowser() end
    if AO.RefreshFeaturedValues then AO:RefreshFeaturedValues() end
end

StaticPopupDialogs["VERITASUI_AO_RESET_ELLESMEREUI"] = {
    text = "Reset the %d setting%s EllesmereUI changes to Blizzard's defaults?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function() AO:ResetEllesmereUIChanges() end,
}
