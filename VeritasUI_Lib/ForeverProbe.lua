-- ============================================================================
--  VeritasUI_Lib/ForeverProbe.lua  --  TEMPORARY PROBE, branch test/forever-probe.
--  DELETE before anything merges to main (and drop it from VeritasUI_Lib.toc).
--
--  /vui forever       full report (chat + VeritasUI_LibDB.foreverProbe)
--  Spec events (dual-spec swap) are printed as they fire while this file is loaded.
--
--  Measures what the Forever client (game type "camelot", Interface 16001) gives us before
--  any feature is gated. Expectations from Blizzard's source (Gethe/wow-ui-source, branch
--  forever = build 1.60.1.70755, the owner's installed build):
--    * WOW_PROJECT_CAMELOT = 18 and WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
--      (Blizzard_ProjectConstants/Camelot/ProjectConstants.lua:1-2, loaded only on camelot).
--    * Dual spec = spec GROUPS: C_SpecializationInfo.GetActiveSpecGroup / SetActiveSpecGroup,
--      GetNumSpecGroups (Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua
--      :112,124,370). What GetSpecialization returns there is UNMEASURED.
--    * Blizzard_EncounterJournal (standard, classic) and Blizzard_DelvesDifficultyPicker
--      (standard) do not load on camelot -- the NAMES section should list their globals.
-- ============================================================================
local VUI = _G.VeritasUI
if not VUI then return end

local lines

local function S(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local function out(fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then text = fmt end
    lines[#lines + 1] = text
    print("|cff00ccffVUI forever|r " .. text)
end

-- Calls fn(...) under pcall and returns a printable summary of every return value (nil included).
local function pack(...) return select("#", ...), { ... } end
local function call(fn, ...)
    if type(fn) ~= "function" then return "<no function>" end
    local n, r = pack(pcall(fn, ...))
    if not r[1] then return "<error: " .. S(r[2]) .. ">" end
    if n == 1 then return "<nothing>" end
    local parts = {}
    for i = 2, n do parts[#parts + 1] = S(r[i]) end
    return table.concat(parts, ", ")
end

local function countOf(fn, ...)
    if type(fn) ~= "function" then return "<no function>" end
    local ok, t = pcall(fn, ...)
    if not ok then return "<error: " .. S(t) .. ">" end
    if type(t) ~= "table" then return "<" .. type(t) .. ": " .. S(t) .. ">" end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function ns(name, fname)
    local t = _G[name]
    if type(t) ~= "table" then return nil end
    return t[fname]
end

-- ── Names VeritasUI references that Retail's Blizzard UI defines ─────────────
-- Generated 2026-11-03 from the Forever source tree evaluated for game type "standard"
-- (name, defining Blizzard addon). The probe prints only the ones missing here.
local NAMES = {
    { "MainActionBar", "Blizzard_ActionBar" },
    { "MultiBar5", "Blizzard_ActionBar" },
    { "MultiBar6", "Blizzard_ActionBar" },
    { "MultiBar7", "Blizzard_ActionBar" },
    { "MultiBarBottomLeft", "Blizzard_ActionBar" },
    { "MultiBarBottomRight", "Blizzard_ActionBar" },
    { "MultiBarLeft", "Blizzard_ActionBar" },
    { "MultiBarRight", "Blizzard_ActionBar" },
    { "SpellFlyout", "Blizzard_ActionBar" },
    { "AuctionHouseFrame", "Blizzard_AuctionHouseUI" },
    { "AuctionHouseFrameDisplayMode", "Blizzard_AuctionHouseUI" },
    { "AuctionHouseSearchContext", "Blizzard_AuctionHouseUI" },
    { "BuffFrame", "Blizzard_BuffFrame" },
    { "DebuffFrame", "Blizzard_BuffFrame" },
    { "ChatFrameChannelButton", "Blizzard_ChatFrame" },
    { "ChatFrameToggleVoiceDeafenButton", "Blizzard_ChatFrame" },
    { "ChatFrameToggleVoiceMuteButton", "Blizzard_ChatFrame" },
    { "ACTIVE_CHAT_EDIT_BOX", "Blizzard_ChatFrameBase" },
    { "CHAT_FRAME_FADE_OUT_TIME", "Blizzard_ChatFrameBase" },
    { "CHAT_FRAME_FADE_TIME", "Blizzard_ChatFrameBase" },
    { "CHAT_FRAME_TEXTURES", "Blizzard_ChatFrameBase" },
    { "ChatFrame1", "Blizzard_ChatFrameBase" },
    { "ChatFrameConstants", "Blizzard_ChatFrameBase" },
    { "ChatFrameMenuButton", "Blizzard_ChatFrameBase" },
    { "ChatFrameUtil", "Blizzard_ChatFrameBase" },
    { "DEFAULT_CHATFRAME_ALPHA", "Blizzard_ChatFrameBase" },
    { "FCF_FadeInChatFrame", "Blizzard_ChatFrameBase" },
    { "FCF_FadeOutChatFrame", "Blizzard_ChatFrameBase" },
    { "FCF_SetWindowAlpha", "Blizzard_ChatFrameBase" },
    { "FCF_SetWindowColor", "Blizzard_ChatFrameBase" },
    { "SELECTED_CHAT_FRAME", "Blizzard_ChatFrameBase" },
    { "BAG_ITEM_QUALITY_COLORS", "Blizzard_Colors" },
    { "ColorManager", "Blizzard_Colors" },
    { "ITEM_QUALITY_COLORS", "Blizzard_Colors" },
    { "DamageMeter", "Blizzard_DamageMeter" },
    { "DelvesDifficultyPickerFrame", "Blizzard_DelvesDifficultyPicker" },
    { "HasOverrideActionBar", "Blizzard_DeprecatedActionBar" },
    { "HasTempShapeshiftActionBar", "Blizzard_DeprecatedActionBar" },
    { "HasVehicleActionBar", "Blizzard_DeprecatedActionBar" },
    { "ChatFrame_OpenChat", "Blizzard_DeprecatedChatInfo" },
    { "NUM_CHAT_WINDOWS", "Blizzard_DeprecatedChatInfo" },
    { "INVENTORY_ALERT_COLORS", "Blizzard_DurabilityFrame" },
    { "EditModeManagerFrame", "Blizzard_EditMode" },
    { "EJ_ContentTab_Select", "Blizzard_EncounterJournal" },
    { "EncounterJournal", "Blizzard_EncounterJournal" },
    { "JourneyCardButtonMixin", "Blizzard_EncounterJournal" },
    { "WatchedFactionToggleFrameMixin", "Blizzard_EncounterJournal" },
    { "GameFontDisableSmall", "Blizzard_Fonts_Shared" },
    { "GameFontHighlight", "Blizzard_Fonts_Shared" },
    { "GameFontHighlightHuge", "Blizzard_Fonts_Shared" },
    { "GameFontHighlightSmall", "Blizzard_Fonts_Shared" },
    { "GameFontNormal", "Blizzard_Fonts_Shared" },
    { "GameFontNormalHuge", "Blizzard_Fonts_Shared" },
    { "GameFontNormalLarge", "Blizzard_Fonts_Shared" },
    { "GameFontNormalSmall", "Blizzard_Fonts_Shared" },
    { "GameTooltipText", "Blizzard_Fonts_Shared" },
    { "NumberFontNormal", "Blizzard_Fonts_Shared" },
    { "NumberFont_Outline_Med", "Blizzard_Fonts_Shared" },
    { "BattlePetToolTip_Show", "Blizzard_FrameXML" },
    { "BattlePetTooltip", "Blizzard_FrameXML" },
    { "BossBanner", "Blizzard_FrameXML" },
    { "CinematicFrame", "Blizzard_FrameXML" },
    { "EventToastManagerFrame", "Blizzard_FrameXML" },
    { "FloatingBattlePetTooltip", "Blizzard_FrameXML" },
    { "FloatingBattlePet_Toggle", "Blizzard_FrameXML" },
    { "MovieFrame", "Blizzard_FrameXML" },
    { "OptionsSliderTemplate", "Blizzard_FrameXML" },
    { "SecureActionButtonTemplate", "Blizzard_FrameXML" },
    { "TalkingHeadFrame", "Blizzard_FrameXML" },
    { "TopBannerManager_BannerFinished", "Blizzard_FrameXML" },
    { "TopBannerManager_Show", "Blizzard_FrameXML" },
    { "TopBannerMgr", "Blizzard_FrameXML" },
    { "ZoneTextFrame", "Blizzard_FrameXML" },
    { "NUM_BAG_SLOTS", "Blizzard_FrameXMLBase" },
    { "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "Blizzard_FrameXMLBase" },
    { "GameTime_GetLocalTime", "Blizzard_FrameXMLUtil" },
    { "ReputationUtil", "Blizzard_FrameXMLUtil" },
    { "GameMenuFrame", "Blizzard_GameMenu" },
    { "EmbeddedItemTooltip", "Blizzard_GameTooltip" },
    { "EmbeddedItemTooltip_Hide", "Blizzard_GameTooltip" },
    { "GameTooltip", "Blizzard_GameTooltip" },
    { "GameTooltipMoneyFormat", "Blizzard_GameTooltip" },
    { "GameTooltip_Hide", "Blizzard_GameTooltip" },
    { "ShoppingTooltip1", "Blizzard_GameTooltip" },
    { "ShoppingTooltip2", "Blizzard_GameTooltip" },
    { "HideUIPanel", "Blizzard_GlueParent" },
    { "ItemButton", "Blizzard_ItemButton" },
    { "SetItemButtonQuality", "Blizzard_ItemButton" },
    { "MacroFrame", "Blizzard_MacroUI" },
    { "MailFrame", "Blizzard_MailFrame" },
    { "BagBarExpandToggle", "Blizzard_MainMenuBarBagButtons" },
    { "BagsBar", "Blizzard_MainMenuBarBagButtons" },
    { "CharacterBag0Slot", "Blizzard_MainMenuBarBagButtons" },
    { "CharacterBag1Slot", "Blizzard_MainMenuBarBagButtons" },
    { "CharacterBag2Slot", "Blizzard_MainMenuBarBagButtons" },
    { "CharacterBag3Slot", "Blizzard_MainMenuBarBagButtons" },
    { "CharacterReagentBag0Slot", "Blizzard_MainMenuBarBagButtons" },
    { "MainMenuBarBackpackButton", "Blizzard_MainMenuBarBagButtons" },
    { "MapCanvasDataProviderMixin", "Blizzard_MapCanvas" },
    { "MapCanvasPinMixin", "Blizzard_MapCanvas" },
    { "DropdownButton", "Blizzard_Menu" },
    { "Menu", "Blizzard_Menu" },
    { "MenuResponse", "Blizzard_Menu" },
    { "MenuUtil", "Blizzard_Menu" },
    { "MenuVariants", "Blizzard_Menu" },
    { "WowStyle1DropdownTemplate", "Blizzard_Menu" },
    { "MicroMenu", "Blizzard_MicroMenu" },
    { "PlayerSpellsMicroButton", "Blizzard_MicroMenu" },
    { "AddonCompartmentFrame", "Blizzard_Minimap" },
    { "ExpansionLandingPageMinimapButton", "Blizzard_Minimap" },
    { "GameTimeFrame", "Blizzard_Minimap" },
    { "Minimap", "Blizzard_Minimap" },
    { "MinimapCluster", "Blizzard_Minimap" },
    { "Item", "Blizzard_ObjectAPI" },
    { "ItemLocation", "Blizzard_ObjectAPI" },
    { "Spell", "Blizzard_ObjectAPI" },
    { "UiMapPoint", "Blizzard_ObjectAPI" },
    { "AchievementObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "AdventureObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "BonusObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "CampaignQuestObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "InitiativeTasksObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "MonthlyActivitiesObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "ObjectiveTrackerFrame", "Blizzard_ObjectiveTracker" },
    { "ProfessionsRecipeTracker", "Blizzard_ObjectiveTracker" },
    { "QuestObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "ScenarioObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "UIWidgetObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "WorldQuestObjectiveTracker", "Blizzard_ObjectiveTracker" },
    { "ProfessionsCustomerOrdersFrame", "Blizzard_ProfessionsCustomerOrders" },
    { "Professions", "Blizzard_ProfessionsTemplates" },
    { "QuickJoinToastButton", "Blizzard_QuickJoin" },
    { "SecureHandlerBaseTemplate", "Blizzard_RestrictedAddOnEnvironment" },
    { "CreateSettingsButtonInitializer", "Blizzard_Settings_Shared" },
    { "CreateSettingsListSectionHeaderInitializer", "Blizzard_Settings_Shared" },
    { "Settings", "Blizzard_Settings_Shared" },
    { "SettingsCheckboxSliderControlTemplate", "Blizzard_Settings_Shared" },
    { "SettingsExpandableSectionTemplate", "Blizzard_Settings_Shared" },
    { "SettingsListSectionHeaderTemplate", "Blizzard_Settings_Shared" },
    { "SettingsPanel", "Blizzard_Settings_Shared" },
    { "SettingsTooltip", "Blizzard_Settings_Shared" },
    { "ButtonFrameTemplate", "Blizzard_SharedXML" },
    { "ButtonFrameTemplate_HidePortrait", "Blizzard_SharedXML" },
    { "COPPER_PER_GOLD", "Blizzard_SharedXML" },
    { "COPPER_PER_SILVER", "Blizzard_SharedXML" },
    { "CreateDataProvider", "Blizzard_SharedXML" },
    { "CreateScrollBoxListLinearView", "Blizzard_SharedXML" },
    { "CreateVector2D", "Blizzard_SharedXML" },
    { "EventFrame", "Blizzard_SharedXML" },
    { "EventUtil", "Blizzard_SharedXML" },
    { "FormatPercentage", "Blizzard_SharedXML" },
    { "GameTooltip_AddColoredLine", "Blizzard_SharedXML" },
    { "GameTooltip_AddErrorLine", "Blizzard_SharedXML" },
    { "GameTooltip_AddHighlightLine", "Blizzard_SharedXML" },
    { "GameTooltip_AddInstructionLine", "Blizzard_SharedXML" },
    { "GameTooltip_AddNormalLine", "Blizzard_SharedXML" },
    { "GameTooltip_SetTitle", "Blizzard_SharedXML" },
    { "GetClassColor", "Blizzard_SharedXML" },
    { "GetFactionColor", "Blizzard_SharedXML" },
    { "GetMoneyString", "Blizzard_SharedXML" },
    { "InputBoxTemplate", "Blizzard_SharedXML" },
    { "MagicButtonTemplate", "Blizzard_SharedXML" },
    { "MinimalScrollBar", "Blizzard_SharedXML" },
    { "MinimalSliderWithSteppersMixin", "Blizzard_SharedXML" },
    { "MoneyFormatterUtil", "Blizzard_SharedXML" },
    { "PLAYER_FACTION_COLORS", "Blizzard_SharedXML" },
    { "PLAYER_FACTION_GROUP", "Blizzard_SharedXML" },
    { "PanelTabButtonTemplate", "Blizzard_SharedXML" },
    { "PanelTemplates_GetSelectedTab", "Blizzard_SharedXML" },
    { "PanelTemplates_SetNumTabs", "Blizzard_SharedXML" },
    { "PanelTemplates_SetTab", "Blizzard_SharedXML" },
    { "PanelTemplates_TabResize", "Blizzard_SharedXML" },
    { "PlaySound", "Blizzard_SharedXML" },
    { "ReloadUI", "Blizzard_SharedXML" },
    { "SOUNDKIT", "Blizzard_SharedXML" },
    { "ScrollUtil", "Blizzard_SharedXML" },
    { "ScrollingEditBoxTemplate", "Blizzard_SharedXML" },
    { "SearchBoxTemplate", "Blizzard_SharedXML" },
    { "SharedTooltipTemplate", "Blizzard_SharedXML" },
    { "TimeUtil", "Blizzard_SharedXML" },
    { "UICheckButtonTemplate", "Blizzard_SharedXML" },
    { "UIPanelButtonTemplate", "Blizzard_SharedXML" },
    { "WowScrollBoxList", "Blizzard_SharedXML" },
    { "CreateColor", "Blizzard_SharedXMLBase" },
    { "Event", "Blizzard_SharedXMLBase" },
    { "EventRegistry", "Blizzard_SharedXMLBase" },
    { "GetCVar", "Blizzard_SharedXMLBase" },
    { "GetCVarBool", "Blizzard_SharedXMLBase" },
    { "GetCVarDefault", "Blizzard_SharedXMLBase" },
    { "RegisterCVar", "Blizzard_SharedXMLBase" },
    { "SetCVar", "Blizzard_SharedXMLBase" },
    { "WrapTextInColorCode", "Blizzard_SharedXMLBase" },
    { "TooltipDataProcessor", "Blizzard_SharedXMLGame" },
    { "TooltipUtil", "Blizzard_SharedXMLGame" },
    { "StaticPopupDialogs", "Blizzard_StaticPopup" },
    { "StaticPopup_FindVisible", "Blizzard_StaticPopup" },
    { "StaticPopup_Show", "Blizzard_StaticPopup" },
    { "MainStatusTrackingBarContainer", "Blizzard_StatusTrackingBar" },
    { "SecondaryStatusTrackingBarContainer", "Blizzard_StatusTrackingBar" },
    { "StatusTrackingBarInfo", "Blizzard_StatusTrackingBar" },
    { "StatusTrackingBarManager", "Blizzard_StatusTrackingBar" },
    { "TimeManagerClockButton", "Blizzard_TimeManager" },
    { "ClassTrainerFrame", "Blizzard_TrainerUI" },
    { "ClassTrainerFrame_Update", "Blizzard_TrainerUI" },
    { "ClassTrainerTrainButton", "Blizzard_TrainerUI" },
    { "UIErrorsFrame", "Blizzard_UIErrorsFrame" },
    { "CR_AVOIDANCE", "Blizzard_UIPanels_Game" },
    { "CR_CRIT_MELEE", "Blizzard_UIPanels_Game" },
    { "CR_CRIT_RANGED", "Blizzard_UIPanels_Game" },
    { "CR_CRIT_SPELL", "Blizzard_UIPanels_Game" },
    { "CR_HASTE_MELEE", "Blizzard_UIPanels_Game" },
    { "CR_LIFESTEAL", "Blizzard_UIPanels_Game" },
    { "CR_MASTERY", "Blizzard_UIPanels_Game" },
    { "CR_SPEED", "Blizzard_UIPanels_Game" },
    { "CR_VERSATILITY_DAMAGE_DONE", "Blizzard_UIPanels_Game" },
    { "CharacterFrame", "Blizzard_UIPanels_Game" },
    { "CharacterStatsPane", "Blizzard_UIPanels_Game" },
    { "CloseAllBags", "Blizzard_UIPanels_Game" },
    { "CloseBag", "Blizzard_UIPanels_Game" },
    { "ContainerFrameCombinedBags", "Blizzard_UIPanels_Game" },
    { "ContainerFrameUtil_GetItemButtonAndContainer", "Blizzard_UIPanels_Game" },
    { "GossipFrame", "Blizzard_UIPanels_Game" },
    { "ItemRefShoppingTooltip1", "Blizzard_UIPanels_Game" },
    { "ItemRefShoppingTooltip2", "Blizzard_UIPanels_Game" },
    { "ItemRefTooltip", "Blizzard_UIPanels_Game" },
    { "LIST_DELIMITER", "Blizzard_UIPanels_Game" },
    { "MAX_SPELL_SCHOOLS", "Blizzard_UIPanels_Game" },
    { "MERCHANT_ITEMS_PER_PAGE", "Blizzard_UIPanels_Game" },
    { "Mastery_OnEnter", "Blizzard_UIPanels_Game" },
    { "MerchantFrame", "Blizzard_UIPanels_Game" },
    { "MerchantFrameTab1", "Blizzard_UIPanels_Game" },
    { "MerchantFrameTab2", "Blizzard_UIPanels_Game" },
    { "MerchantFrame_Update", "Blizzard_UIPanels_Game" },
    { "MerchantFrame_UpdateMerchantInfo", "Blizzard_UIPanels_Game" },
    { "MerchantNextPageButton", "Blizzard_UIPanels_Game" },
    { "MerchantPrevPageButton", "Blizzard_UIPanels_Game" },
    { "OpenAllBags", "Blizzard_UIPanels_Game" },
    { "OpenBag", "Blizzard_UIPanels_Game" },
    { "PaperDollFrame_UpdateStats", "Blizzard_UIPanels_Game" },
    { "PaperDollItemSlotButton_Update", "Blizzard_UIPanels_Game" },
    { "PaperDollStatTooltip", "Blizzard_UIPanels_Game" },
    { "QuestFrame", "Blizzard_UIPanels_Game" },
    { "QuestInfoRewardsFrame", "Blizzard_UIPanels_Game" },
    { "ReputationFrame", "Blizzard_UIPanels_Game" },
    { "ToggleCharacter", "Blizzard_UIPanels_Game" },
    { "ShowUIPanel", "Blizzard_UIParentPanelManager" },
    { "UIPanelWindows", "Blizzard_UIParentPanelManager" },
    { "UISpecialFrames", "Blizzard_UIParentPanelManager" },
    { "PlayerFrame", "Blizzard_UnitFrame" },
    { "WeeklyRewardsFrame", "Blizzard_WeeklyRewards" },
}

-- Advanced Options Featured CVars (VeritasUI_AdvancedOptions/Featured.lua, 2026-11-03).
local CVARS = {
    "ActionButtonUseKeyDown", "RAIDsettingsEnabled", "ResampleAlwaysSharpen", "SoftTargetEnemy",
    "SoftTargetFriend", "SoftTargetInteract", "UberTooltips", "alwaysShowActionBars",
    "autoLootDefault", "cameraDistanceMaxZoomFactor", "cameraReduceUnexpectedMovement",
    "cameraWaterCollision", "chatBubbles", "chatBubblesParty", "colorblindMode",
    "colorblindSimulator", "countdownForCooldowns", "deselectOnClick", "enableFloatingCombatText",
    "ffxDeath", "ffxGlow", "ffxNether", "floatingCombatTextAuras_v2",
    "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2",
    "floatingCombatTextCombatState_v2", "floatingCombatTextComboPoints_v2",
    "floatingCombatTextDamageReduction_v2", "floatingCombatTextDodgeParryMiss_v2",
    "floatingCombatTextEnergyGains_v2", "floatingCombatTextFriendlyHealers_v2",
    "floatingCombatTextHonorGains_v2", "floatingCombatTextLowManaHealth_v2",
    "floatingCombatTextPeriodicEnergyGains_v2", "floatingCombatTextReactives_v2",
    "floatingCombatTextRepChanges_v2", "hideHelptips", "lockActionBars", "lootUnderMouse",
    "nameplateMaxDistance", "nameplateMaxScale", "nameplateMinScale", "nameplateOccludedAlphaMult",
    "nameplateSelectedScale", "profanityFilter", "reducedMotion", "removeChatDelay",
    "screenEdgeFlash", "showTargetOfTarget", "showTimestamps", "showToastWindow", "showTutorials",
    "sunShafts",
}

local MODULES = {
    "VeritasUI_Lib", "VeritasUI_AdvancedOptions", "VeritasUI_AuctionHouse", "VeritasUI_CleanSolo",
    "VeritasUI_PriorityRotation", "VeritasUI_QualityOfLife", "VeritasUI_ZoneQuests",
}

local function AddonState(name)
    local A = _G.C_AddOns
    if not A then return "C_AddOns missing" end
    -- GetAddOnInfo returns name, title, notes, loadable, reason, security
    local ok, _, _, _, loadable, reason = pcall(A.GetAddOnInfo, name)
    return ("loaded=%s loadable=%s reason=%s lod=%s"):format(call(A.IsAddOnLoaded, name),
        ok and S(loadable) or "?", ok and S(reason) or "?", call(A.IsAddOnLoadOnDemand, name))
end

local function IsLoaded(addon)
    local A = _G.C_AddOns
    if not (A and A.IsAddOnLoaded) then return false end
    local ok, v = pcall(A.IsAddOnLoaded, addon)
    return ok and v == true
end

local function Section(title) out("== %s", title) end

local function Report()
    lines = {}
    out("VeritasUI %s Forever probe, %s", S(VUI.VERSION), call(date, "%Y-%m-%d %H:%M"))

    Section("Build")
    out("GetBuildInfo: %s", call(GetBuildInfo))
    out("WOW_PROJECT_ID=%s  WOW_PROJECT_CAMELOT=%s  WOW_PROJECT_MAINLINE=%s",
        S(_G.WOW_PROJECT_ID), S(_G.WOW_PROJECT_CAMELOT), S(_G.WOW_PROJECT_MAINLINE))
    local matches = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^WOW_PROJECT_") and k ~= "WOW_PROJECT_ID" and v == _G.WOW_PROJECT_ID then
            matches[#matches + 1] = k
        end
    end
    table.sort(matches)
    out("constants equal to WOW_PROJECT_ID: %s", #matches > 0 and table.concat(matches, ", ") or "none")
    out("expansion: GetExpansionLevel=%s GetServerExpansionLevel=%s LE_EXPANSION_LEVEL_CURRENT=%s maxLevel=%s",
        call(_G.GetExpansionLevel), call(_G.GetServerExpansionLevel), S(_G.LE_EXPANSION_LEVEL_CURRENT),
        call(_G.GetMaxLevelForPlayerExpansion))
    out("player: level=%s class=%s", call(UnitLevel, "player"), call(UnitClass, "player"))

    Section("VeritasUI modules")
    for _, m in ipairs(MODULES) do out("%s: %s", m, AddonState(m)) end

    Section("Specs (Priority Rotation)")
    local SI = _G.C_SpecializationInfo
    out("C_SpecializationInfo: %s", SI and "present" or "MISSING")
    out("GetSpecialization=%s", call(ns("C_SpecializationInfo", "GetSpecialization")))
    out("GetNumSpecializations=%s", call(_G.GetNumSpecializations))
    local okN, nSpec = pcall(_G.GetNumSpecializations)
    if okN and type(nSpec) == "number" then
        for i = 1, math.min(nSpec, 6) do
            out("  spec %d: %s", i, call(ns("C_SpecializationInfo", "GetSpecializationInfo"), i))
        end
    end
    out("GetActiveSpecGroup=%s GetNumSpecGroups=%s", call(ns("C_SpecializationInfo", "GetActiveSpecGroup")),
        call(_G.GetNumSpecGroups))
    out("SetSpecialization fn=%s SetActiveSpecGroup fn=%s",
        S(type(ns("C_SpecializationInfo", "SetSpecialization")) == "function"),
        S(type(ns("C_SpecializationInfo", "SetActiveSpecGroup")) == "function"))

    Section("Single-Button Assistant")
    out("C_AssistedCombat: %s  IsAvailable=%s  GetActionSpell=%s  rotation spells=%s",
        _G.C_AssistedCombat and "present" or "MISSING",
        call(ns("C_AssistedCombat", "IsAvailable")), call(ns("C_AssistedCombat", "GetActionSpell")),
        countOf(ns("C_AssistedCombat", "GetRotationSpells")))

    Section("Quality of Life / Clean Solo features")
    out("C_DelvesUI.HasActiveDelve=%s", call(ns("C_DelvesUI", "HasActiveDelve")))
    out("C_WeeklyRewards.HasAvailableRewards=%s CanClaimRewards=%s",
        call(ns("C_WeeklyRewards", "HasAvailableRewards")), call(ns("C_WeeklyRewards", "CanClaimRewards")))
    out("C_MajorFactions.GetMajorFactionIDs count=%s", countOf(ns("C_MajorFactions", "GetMajorFactionIDs")))
    out("C_ChallengeMode.GetOverallDungeonScore=%s GetMapTable count=%s",
        call(ns("C_ChallengeMode", "GetOverallDungeonScore")), countOf(ns("C_ChallengeMode", "GetMapTable")))
    out("C_LFGInfo.CanPlayerUseGroupFinder=%s", call(ns("C_LFGInfo", "CanPlayerUseGroupFinder")))
    out("IsFlyableArea=%s IsAdvancedFlyableArea=%s", call(_G.IsFlyableArea), call(_G.IsAdvancedFlyableArea))
    out("C_MountJournal.GetMountIDs count=%s", countOf(ns("C_MountJournal", "GetMountIDs")))
    out("C_Navigation: %s  C_SuperTrack: %s  C_DamageMeter: %s", S(_G.C_Navigation ~= nil),
        S(_G.C_SuperTrack ~= nil), S(_G.C_DamageMeter ~= nil))
    out("C_Reputation.GetWatchedFactionData=%s", call(ns("C_Reputation", "GetWatchedFactionData")))
    out("C_QuestLog.GetNumQuestLogEntries=%s", call(ns("C_QuestLog", "GetNumQuestLogEntries")))
    for _, a in ipairs({ "Blizzard_AuctionHouseUI", "Blizzard_EncounterJournal", "Blizzard_WeeklyRewards",
            "Blizzard_DelvesDifficultyPicker", "Blizzard_DamageMeter", "Blizzard_PlayerSpells",
            "Blizzard_LegacySystem", "Blizzard_HousingDashboard", "Blizzard_MailFrame" }) do
        out("%s: %s", a, AddonState(a))
    end

    Section("Auction House")
    out("C_AuctionHouse: %s  GetNumOwnedAuctions fn=%s  IsThrottledMessageSystemReady=%s",
        _G.C_AuctionHouse and "present" or "MISSING", S(ns("C_AuctionHouse", "GetNumOwnedAuctions") ~= nil),
        call(ns("C_AuctionHouse", "IsThrottledMessageSystemReady")))

    Section("Blizzard globals VeritasUI references (missing only)")
    local missing, notLoaded = 0, {}
    for _, row in ipairs(NAMES) do
        local name, addon = row[1], row[2]
        if _G[name] == nil then
            if IsLoaded(addon) then
                missing = missing + 1
                out("  MISSING %s  (%s is loaded)", name, addon)
            else
                notLoaded[addon] = (notLoaded[addon] or 0) + 1
            end
        end
    end
    out("missing with their addon loaded: %d of %d", missing, #NAMES)
    for addon, n in pairs(notLoaded) do
        out("  %d names wait on %s (not loaded): %s", n, addon, AddonState(addon))
    end

    Section("Advanced Options Featured CVars (missing only)")
    local gone = 0
    for _, cv in ipairs(CVARS) do
        local ok, val = pcall(C_CVar.GetCVarInfo, cv)
        if not ok or val == nil then
            gone = gone + 1
            out("  MISSING %s", cv)
        end
    end
    out("missing: %d of %d", gone, #CVARS)

    local db = _G.VeritasUI_LibDB
    if type(db) == "table" then db.foreverProbe = lines end
    out("Done. Saved as VeritasUI_LibDB.foreverProbe (written to disk on /reload or logout).")
end
VUI.ProbeForever = Report

-- Spec swap events: printed live so a dual-spec swap at a class trainer / talent frame shows
-- what changes and which events fire.
local watch = CreateFrame("Frame")
for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    pcall(watch.RegisterEvent, watch, ev)
end
watch:SetScript("OnEvent", function(_, event, ...)
    print(("|cff00ccffVUI forever|r event %s (%s): GetSpecialization=%s GetActiveSpecGroup=%s"):format(
        event, call(function(...) return ... end, ...),
        call(ns("C_SpecializationInfo", "GetSpecialization")),
        call(ns("C_SpecializationInfo", "GetActiveSpecGroup"))))
end)
