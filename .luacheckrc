-- .luacheckrc — WoW-aware luacheck config for VeritasUI
-- Run from the repo root:   luacheck .
--
-- Purpose (per the audit brief's Tooling section): define the Blizzard global
-- set as KNOWN so luacheck isn't drowned in false "undefined global" noise, and
-- enable accidental-global / unused-variable / unreachable-code detection.
--
-- WoW runs a Lua 5.1 base with NO standard io/os file access exposed to addons,
-- so we start from std="lua51" and then layer the WoW API on top as read_globals.

std = "lua51"

-- The suite's ONE writable global namespace + the WoW-API entry points an addon
-- is REQUIRED to define as globals (slash handlers, addon-compartment callbacks,
-- saved-variable tables). These are writes luacheck must not flag as leaks.
globals = {
    "VeritasUI",                       -- the single shared namespace (Lib.lua)
    -- Blizzard tables the suite legitimately WRITES to (RegisterManagedPanel):
    -- UIPanelWindows[name] = {...} and table.insert(UISpecialFrames, name).
    "UIPanelWindows", "UISpecialFrames",
    "StaticPopupDialogs",   -- copy-settings confirmations (Lib)
    -- SavedVariables (declared in each .toc; WoW injects/reads these as globals)
    "VeritasUI_AdvancedOptionsDB",
    "VeritasUI_AuctionHouseDB",
    "VeritasUI_CleanSoloDB",
    "VeritasUI_LibDB",
    "VeritasUI_PriorityRotationDB",
    "VeritasUI_QualityOfLifeDB",
    "VeritasUI_ZoneQuestsDB",
    -- SLASH_* command registrations (WoW reads these globals by name)
    "SLASH_VERITASUI1", "SLASH_VERITASUI2",
    "SLASH_VERITASUI_AO1", "SLASH_VERITASUI_AO2",
    "SLASH_VERITASUI_AH1", "SLASH_VERITASUI_AH2",
    "SLASH_VERITASUI_CLEANSOLO1", "SLASH_VERITASUI_CLEANSOLO2",
    "SLASH_VERITASUI_PR1", "SLASH_VERITASUI_PR2",
    "SLASH_VERITASUI_QOL1", "SLASH_VERITASUI_QOL2", "SLASH_VERITASUI_WAY1",
    "SLASH_VERITASUI_ZONEQUESTS1", "SLASH_VERITASUI_ZONEQUESTS2",
    "SlashCmdList",
    -- Addon-compartment callbacks (WoW calls these by global name from the TOC)
    "VeritasUI_AdvancedOptions_OnAddonCompartmentClick",
    "VeritasUI_CleanSolo_OnAddonCompartmentClick",
    "VeritasUI_PriorityRotation_OnAddonCompartmentClick",
    "VeritasUI_QualityOfLife_OnAddonCompartmentClick",
    "VeritasUI_ZoneQuests_OnAddonCompartmentClick",
}

-- The WoW API surface this suite actually touches. READ-ONLY: referencing them is
-- fine; assigning to them would (correctly) still warn. Kept to what the code uses
-- rather than the entire client API, so a genuine typo in an API name still surfaces.
read_globals = {
    -- Core frame / system
    "CreateFrame", "UIParent", "C_Timer", "hooksecurefunc", "InCombatLockdown",
    "issecretvalue", "debugprofilestop", "GetTime", "time", "date",
    "ReloadUI", "C_AddOns", "IsAddOnLoaded", "GetBuildInfo",
    "StaticPopup_Show", "ACCEPT", "CANCEL",
    -- Strings / math helpers WoW exposes globally
    "strtrim", "strsplit", "strjoin", "strlower", "strfind",
    "CreateColor", "CreateVector2D", "C_ClassColor",
    -- Settings / options framework
    "Settings", "SettingsPanel", "InterfaceOptions_AddCategory",
    "UISpecialFrames", "ShowUIPanel", "HideUIPanel",
    "PanelTemplates_SetTab", "PanelTemplates_SetNumTabs",
    "PanelTemplates_TabResize", "PanelTemplates_GetSelectedTab",
    -- Scroll / data-provider system
    "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil",
    "MenuResponse", "MenuUtil",
    -- Tooltips
    "GameTooltip", "ItemRefTooltip", "TooltipDataProcessor", "TooltipUtil",
    "C_TooltipInfo", "ITEM_LEVEL",
    "BattlePetTooltip", "FloatingBattlePetTooltip", "BattlePetToolTip_Show",
    "FloatingBattlePet_Toggle",
    -- Item / container / inventory
    "C_Item", "C_Container", "ItemLocation", "Item", "GetInventoryItemLink",
    "GetItemInfoInstant", "GetDetailedItemLevelInfo",
    "ITEM_QUALITY_COLORS", "BAG_ITEM_QUALITY_COLORS", "NUM_BAG_SLOTS",
    "C_TradeSkillUI", "C_Texture",
    -- Map / navigation / quests
    "C_Map", "C_Navigation", "C_SuperTrack", "C_QuestLog",
    "UiMapPoint", "GetRealZoneText", "GetZoneText", "GetSubZoneText",
    "Enum",
    -- Action bars / macros / spells / specs (PriorityRotation)
    "C_Spell", "C_SpecializationInfo", "GetSpecialization",
    "GetSpecializationInfo", "GetNumSpecializations", "SetSpecialization",
    "GetActionInfo", "GetMacroInfo", "GetMacroBody", "GetMacroIndexByName",
    "GetNumMacros", "CreateMacro", "EditMacro", "MAX_ACCOUNT_MACROS",
    "GetCursorInfo", "ClearCursor", "GetBindingKey", "SetOverrideBindingClick",
    "ClearOverrideBindings", "C_CVar", "C_ActionBar", "C_Secrets",
    "C_RestrictedActions", "PlayerSpellsFrame", "PlayerSpellsUtil",
    "ToggleSpellBook", "BOOKTYPE_SPELL", "MacroFrame", "ShowMacroFrame",
    "IsShiftKeyDown", "EditModeManagerFrame",
    -- Money / merchant / repair (QualityOfLife)
    "GetCoinTextureString", "C_CurrencyInfo", "GetMerchantItemLink",
    "GetMerchantNumItems", "MerchantFrame", "MERCHANT_ITEMS_PER_PAGE",
    "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems",
    "CanGuildBankRepair", "IsInGuild", "GetGuildInfoText", "GetMoney",
    "GetGuildBankWithdrawMoney",
    "SetItemButtonQuality",
    -- Player / unit / AFK
    "UnitName", "UnitClass", "UnitLevel", "UnitIsAFK", "UnitExists", "GetAverageItemLevel",
    "GetRealmName",
    "MoveViewRightStart", "MoveViewRightStop", "MinimapCluster",
    "NumberFontNormal", "NumberFontNormalRight",
    -- Auction House
    "C_AuctionHouse", "AuctionHouseFrame", "AuctionHouseFrameDisplayMode",
    -- Chat / UI elements (CleanSolo)
    "NUM_CHAT_WINDOWS", "FCF_SetWindowAlpha", "FCF_SetWindowColor",
    "FCF_FadeInChatFrame", "CHAT_FRAME_FADE_TIME", "CHAT_FRAME_FADE_OUT_TIME",
    "CHAT_TAB_HIDE_DELAY", "QuickJoinToastButton", "MicroMenu", "PlayerFrame",
    "VoiceChatTalkerContainer", "ChatFrame1EditBox", "UIErrorsFrame",
    "BagsBar", "BagBar", "MouseIsOver", "GetMouseFocus", "GetMouseFoci",
    "WorldMapFrame", "DEFAULTS",
    -- Console (AdvancedOptions enumeration fallbacks)
    "C_Console", "ConsoleGetAllCommands",
    -- Templates referenced by name in CreateFrame (string args, but listed for clarity)
}

-- Noise control --------------------------------------------------------------
-- Each module is its own addon loaded in its own file-chunk; the "..." vararg
-- carries (addonName, privateTable). Allow unused "self"/"_" and the loop-var
-- underscore convention the suite uses heavily.
ignore = {
    "212",   -- unused argument (event handlers often ignore some payload args)
    "213",   -- unused loop variable (the `for _, x in` convention)
    "432",   -- shadowing upvalue 'self' — idiomatic: outer self = module (AO:/PR:),
             -- inner self = the widget in a SetScript handler. Both intentional.
    "131",   -- unused implicitly-defined global — the SLASH_* command vars and
             -- *_OnAddonCompartmentClick callbacks are read BY NAME by the WoW
             -- client, never by our Lua, so luacheck can't see their "use".
}

-- Don't lint vendored/release artifacts or VCS internals.
exclude_files = {
    ".git/**",
    "**/*.zip",
}

-- Per-file relaxations -------------------------------------------------------
files["**/*.lua"] = {
    -- WoW addon files share no module scope; each gets (name, tbl) via "...".
    -- Treat that as expected rather than flagging an unused vararg.
    allow_defined_top = true,
}
