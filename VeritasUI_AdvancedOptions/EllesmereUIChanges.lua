-- VeritasUI_AdvancedOptions / EllesmereUIChanges.lua
-- The CVars EllesmereUI sets, so the All CVars tab indexes them and its "Changed" filter can list
-- the ones still away from Blizzard's default after EllesmereUI is gone (Browser.lua).
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
