-- VeritasUI_Lib / Conflicts.lua
-- Graceful conflicts (v1.79.0). When
-- another AddOn is already doing what one of our options does, ours steps aside: the option is greyed in
-- Options with the reason in red at the end of its tooltip, its feature does not run, and its saved value is
-- left as it was, so it comes back by itself once the other AddOn stops doing that job. This only builds on
-- VUI.SetOptionUnavailable (Lib.lua), which every module's options page and feature start-up already honour.
--
-- Ours is greyed only when the other AddOn's matching option is actually ON, read from its saved settings
-- (Leatrix Plus keeps "On"/"Off" strings in LeaPlusDB; the defaults below are its own, from its LoadVarChk
-- calls, Leatrix_Plus.lua 1.60.29 :15888-16065). An AddOn whose settings cannot be read would be greyed by
-- presence alone. A row of a tick-box dropdown is "key:rowId" (Interface's Hide Top Banners, Hide Transforms).
--
-- Rules are evaluated when a module first asks, once you are logged in (every AddOn's saved settings are
-- loaded by PLAYER_LOGIN); before that they are evaluated but not remembered.
--
-- Sourced from Leatrix Plus 1.60.29 (WoW Forever edition), read 2026-11-08 -- each rule names what it does:
--   AutoSellJunk / AutoRepairGear       sells greys / repairs at merchants (:7273, :7753)
--   AutomateQuests + AutoQuestRegular|Daily|Weekly accepts quests; + AutoQuestCompleted hands them in (:6807-7069)
--   AutomateGossip                      picks an NPC's only dialogue option (:6585)
--   AutoAcceptRes                       accepts resurrections (:12604)
--   AcceptPartyFriends + FriendlyGuild  accepts group invites from guild members (:4724, :19872)
--   ShowTrainAllButton                  a Train All button at trainers (:12296)
--   FasterMovieSkip                     skips movies without the prompt (:5170)
--   EasyItemDestroy                     fills in DELETE (:8778)
--   RestoreChatMessages                 puts chat back after a reload (:9543)
--   TipModEnable                        rewrites the unit tooltip: the name's colour (:14571-14608), the guild line
--                                       and its colour (:14614-14631, + TipShowRank/TipShowOtherRank for the
--                                       rank), and the target line with TipShowTarget (:14720)
--   NoSocialButton / HideMacroText      hides the social button / macro names (:13353, :12658)
--   NoChatButtons                       hides the chat buttons, the menu unless ShowChatMenuButton, the voice
--                                       buttons unless ShowVoiceButtons (:13579, :19898)
--   MuteGameSounds + MuteFizzle         mutes the spell fizzle (Leatrix_Plus_Mute.lua :51)
--   HideErrorMessages                   replaces the error frame's handler (:8736)
--   HideZoneText / HideBossBanner / HideEventToasts   the zone text, the boss banner, every event toast (:8497,
--                                       :6773, :6731)
--   NoTransforms + TransHallowed|TransLantern|TransNobleBunny|TransTurkey   the holiday costumes (:12059-12235)

local VUI = _G.VeritasUI
if not VUI then return end

local QOL, IFACE = "VeritasUI_QualityOfLife", "VeritasUI_Interface"

-- Leatrix Plus: its saved option is "On", the missing value taking Leatrix's own default.
local function Lea(key, default)
    local db = _G.LeaPlusDB
    local v = type(db) == "table" and db[key] or nil
    if v == nil then v = default or "Off" end
    return v == "On"
end
local function LeaAny(keys)
    for _, k in ipairs(keys) do if Lea(k[1], k[2]) then return true end end
    return false
end

local LEATRIX = { addon = "Leatrix_Plus", title = "Leatrix Plus" }
local function L(module, key, feature, when)
    return { module = module, key = key, addon = LEATRIX.addon, title = LEATRIX.title, feature = feature,
             when = when }
end
local function TOASTS(id) return IFACE, "hideTopBanners:" .. id end

VUI.CONFLICT_RULES = {
    L(QOL, "autoSellJunk", "Sell junk automatically", function() return Lea("AutoSellJunk") end),
    L(QOL, "autoRepair", "Repair automatically", function() return Lea("AutoRepairGear") end),
    L(QOL, "autoAcceptQuest", "Automate quests", function()
        return Lea("AutomateQuests") and LeaAny({ { "AutoQuestRegular", "On" }, { "AutoQuestDaily", "On" },
            { "AutoQuestWeekly", "On" } })
    end),
    L(QOL, "autoTurnInQuest", "Automate quests", function()
        return Lea("AutomateQuests") and Lea("AutoQuestCompleted", "On")
    end),
    L(QOL, "pickOnlyGossip", "Automate gossip", function() return Lea("AutomateGossip") end),
    L(QOL, "autoAcceptRes", "Accept resurrection", function() return Lea("AutoAcceptRes") end),
    -- v1.81.0: Accept Group Invites From (Invites.lua) replaces Accept Invites from Guildmates; Leatrix's Party from
    -- friends accepts friends' invites always and guild members' with FriendlyGuild (:4724, :19872), so the whole
    -- dropdown steps aside. Its Block options (:4462-4801, :9526) map to Decline From Strangers' rows.
    L(QOL, "acceptInvitesFrom", "Party from friends", function() return Lea("AcceptPartyFriends") end),
    L(QOL, "declineStrangers:duels", "Block duels", function() return Lea("NoDuelRequests") end),
    L(QOL, "declineStrangers:invites", "Block party invites", function() return Lea("NoPartyInvites") end),
    L(QOL, "declineStrangers:joins", "Block requested invites", function() return Lea("NoRequestedInvites") end),
    L(QOL, "declineStrangers:bnet", "Block friend requests", function() return Lea("NoFriendRequests") end),
    L(QOL, "declineStrangers:quests", "Block shared quests", function() return Lea("NoSharedQuests") end),
    L(QOL, "trainAllButton", "Show train all button", function() return Lea("ShowTrainAllButton") end),
    L(QOL, "skipCinematics", "Faster movie skip", function() return Lea("FasterMovieSkip") end),
    L(QOL, "fillDeleteConfirm", "Easy item destroy", function() return Lea("EasyItemDestroy") end),
    L(QOL, "chatRememberLines", "Restore chat messages", function() return Lea("RestoreChatMessages") end),
    -- v1.82.0: Use arrow keys in chat (:13333), Disable chat fade (:8528); Filter chat messages (:12407) gates its
    -- three blocks (:12454-12518), each mapped to its Hide Chat Spam row.
    L(QOL, "chatArrowKeys", "Use arrow keys in chat", function() return Lea("UseArrowKeysInChat") end),
    L(QOL, "chatNeverFade", "Disable chat fade", function() return Lea("NoChatFade") end),
    L(QOL, "chatHideSpam:spellLinks", "Block spell links during combat", function()
        return Lea("FilterChatMessages") and Lea("BlockSpellLinks")
    end),
    L(QOL, "chatHideSpam:drunk", "Block drunken spam", function()
        return Lea("FilterChatMessages") and Lea("BlockDrunkenSpam")
    end),
    L(QOL, "chatHideSpam:duels", "Block duel spam", function()
        return Lea("FilterChatMessages") and Lea("BlockDuelSpam")
    end),
    L(QOL, "tooltipClassNames", "Enhance tooltip", function() return Lea("TipModEnable") end),
    L(QOL, "tooltipGuildmates", "Enhance tooltip", function() return Lea("TipModEnable") end),
    L(QOL, "tooltipGuildRank", "Enhance tooltip", function()
        return Lea("TipModEnable") and (Lea("TipShowRank", "On") or Lea("TipShowOtherRank"))
    end),
    L(QOL, "tooltipTarget", "Enhance tooltip", function()
        return Lea("TipModEnable") and Lea("TipShowTarget", "On")
    end),
    L(IFACE, "hideSocialButton", "Hide social button", function() return Lea("NoSocialButton") end),
    L(IFACE, "hideChatButtons", "Hide chat buttons", function()
        return Lea("NoChatButtons") and not Lea("ShowChatMenuButton")
    end),
    L(IFACE, "hideVoiceChatButton", "Hide chat buttons", function()
        return Lea("NoChatButtons") and not Lea("ShowVoiceButtons")
    end),
    L(IFACE, "hideMacroNames", "Hide macro text", function() return Lea("HideMacroText") end),
    L(IFACE, "hideKeybindText", "Hide keybind text", function() return Lea("HideKeybindText") end),   -- v1.82.0
    L(IFACE, "outOfRangeIcons", "Show range coloring", function() return Lea("ShowRangeColoring") end),
    -- v1.84.0: Mute Sounds rows. Mute game sounds (:5046-5073) and Mute mount sounds (:4933-4952) each gate their own
    -- picks; a row steps aside when the matching pick is live.
    L(IFACE, "muteSounds:fizzle", "Mute game sounds, Fizzle", function()
        return Lea("MuteGameSounds") and Lea("MuteFizzle")
    end),
    L(IFACE, "muteSounds:chimes", "Mute game sounds, Chimes", function()
        return Lea("MuteGameSounds") and Lea("MuteChimes")
    end),
    L(IFACE, "muteSounds:ready", "Mute game sounds, Ready", function()
        return Lea("MuteGameSounds") and Lea("MuteReady")
    end),
    L(IFACE, "muteSounds:trains", "Mute game sounds, Trains", function()
        return Lea("MuteGameSounds") and Lea("MuteTrains")
    end),
    L(IFACE, "muteSounds:vault", "Mute game sounds, Vaults", function()
        return Lea("MuteGameSounds") and Lea("MuteVaults")
    end),
    L(IFACE, "muteSounds:yawns", "Mute game sounds, Yawns", function()
        return Lea("MuteGameSounds") and Lea("MuteYawns")
    end),
    L(IFACE, "muteSounds:airships", "Mute mount sounds, Airships and Zeppelins", function()
        return Lea("MuteMountSounds") and (Lea("MuteAirships") or Lea("MuteZeppelins"))
    end),
    L(IFACE, "muteSounds:steps", "Mute mount sounds, Horsesteps and Mechsteps", function()
        return Lea("MuteMountSounds") and (Lea("MuteHorsesteps") or Lea("MuteMechSteps"))
    end),
    L(IFACE, "muteSounds:striders", "Mute mount sounds, Mechstriders", function()
        return Lea("MuteMountSounds") and Lea("MuteStriders")
    end),
    L(IFACE, "hideErrorText", "Hide error messages", function() return Lea("HideErrorMessages") end),
    L(IFACE, "hideTopBanners:zone", "Hide zone text", function() return Lea("HideZoneText") end),
    L(IFACE, "hideTopBanners:boss", "Hide boss banner", function() return Lea("HideBossBanner") end),
    L(IFACE, "hideProfessionGear:holiday", "Remove transforms", function()
        return Lea("NoTransforms") and LeaAny({ { "TransHallowed" }, { "TransLantern" }, { "TransNobleBunny" },
            { "TransTurkey" } })
    end),
}
-- Every event toast row (Leatrix hides them all, "Hide event toasts").
for _, id in ipairs({ "levelup", "scenario", "messages", "weekly", "renown", "other" }) do
    local module, key = TOASTS(id)
    VUI.CONFLICT_RULES[#VUI.CONFLICT_RULES + 1] = L(module, key, "Hide event toasts",
        function() return Lea("HideEventToasts") end)
end

-- Questie (12.6.4, WoW Forever; read 2026-11-08). Its options live in AceDB: the live profile is Questie.db.profile
-- (Questie.lua:35, made at its ADDON_LOADED), defaults from Modules/Options/QuestieOptionsDefaults.lua; a value that
-- cannot be read takes that default.
--   trackerEnabled (default ON)   "Enable Tracker" "will replace the default Blizzard Quest Tracker with the Questie
--                                 Tracker" (TrackerTab/QuestieOptionsTracker.lua:103-104); in Forever it hides
--                                 ObjectiveTrackerFrame (QuestieCompat.lua:395-416), so our tracker fade has nothing
--                                 to fade. Questie has its own tracker fading options.
--   autoAccept.enabled / autocomplete (default off)   "Auto Accept Quests" / "Auto Complete Quests" (AutoTab/
--                                 QuestieOptionsAuto.lua:43, :60; Auto/AutoQuesting.lua:16-106).
-- Zone Quests: Questie's tracker does NOT follow the game's tracked list (owner, 2026-11-08: it showed every quest
-- with Zone Quests on). Why, from its source: with "Automatically track quests" (autoTrackQuests, default on) it
-- shows every quest not in its OWN untracked list (QuestieTracker.IsTrackedByQuestie, Tracker/QuestieTracker.lua
-- :1174-1183; the game's list is read only while its tracker is off, Quest/QuestieQuest.lua:486-491), its start-up
-- never reads the game's tracked list (QuestieTracker.Initialize, :225-270), and it learns of an untrack only through
-- a hook it installs at that start-up (:1248-1268) -- after Zone Quests has already filtered the list at login. So
-- Zone Quests steps aside while Questie's tracker is on.
local function QuestieOpt(read, default)
    local ok, v = pcall(function() return read(_G.Questie.db.profile) end)
    if not ok or v == nil then return default end
    return v and true or false
end
local function Q(module, key, feature, when, reason)
    return { module = module, key = key, addon = "Questie", title = "Questie", feature = feature, when = when,
             reason = reason }
end
local function QuestieTracker()
    return VUI.IS_FOREVER and QuestieOpt(function(p) return p.trackerEnabled end, true)
end
for _, rule in ipairs({
    Q(QOL, "autoAcceptQuest", "Auto Accept Quests", function()
        return QuestieOpt(function(p) return p.autoAccept.enabled end, false)
    end),
    Q(QOL, "autoTurnInQuest", "Auto Complete Quests", function()
        return QuestieOpt(function(p) return p.autocomplete end, false)
    end),
    Q(IFACE, "fadeObjectiveTracker", "Enable Tracker", QuestieTracker,
        "Questie's quest tracker replaces the game's (its Enable Tracker option), so there is no tracker "
        .. "here to fade. Turn that off to use this one."),
    Q("VeritasUI_ZoneQuests", "enabled", "Enable Tracker", QuestieTracker,
        "Questie's quest tracker replaces the game's (its Enable Tracker option) and keeps its own list "
        .. "of quests, so Zone Quests cannot filter it. Turn that off to use this one."),
}) do VUI.CONFLICT_RULES[#VUI.CONFLICT_RULES + 1] = rule end

-- DaylightUI 2.2.7 (WoW Forever; read 2026-11-24). A suite of separate AddOns (DaylightUI + DaylightUI_<Module>);
-- its public API reads settings: DaylightUI.API.GetSetting(scope, path) (DaylightUI/API.lua:930, nil while that
-- module is off) and IsModuleEnabled(name) (:935). Modules switch on in DaylightUI's PLAYER_LOGIN
-- (Core.lua:1014-1016), so our modules list DaylightUI in OptionalDeps: it loads, and handles PLAYER_LOGIN, first.
-- Character and NPC are part of the core AddOn; their `enabled` setting is the switch. Paths and defaults:
--   Bags      enabled (true) gates sellJunk / autoRepair (true): Window.lua:1598-1614, Defaults.lua:6,31-32
--   QoL       afkScreen, trainAll, autoDelete (true); skipCinematics, skipGossip, questAccept, questTurnIn (false);
--             quietErrors / errorText (true), zoneTitle (true; zone text to alpha 0), levelUp (true; level-up toast
--             to alpha 0): Defaults.lua:89-192, ZoneTitle.lua:48, LevelUp.lua:245-255
--   Tooltip   style ("rich" draws its own card over the tooltip, Rich/Rich.lua:20-35), classColors (simple style
--             only), showTarget, guildRank (true): Defaults.lua:19-46
--   Chat      always replaces how the chat windows look (ChatFrames kept at alpha 0 in its "daylight" style,
--             faded in "classic"; Box.lua:1-25, Chat.lua:1090-1095); copyButton, linkTooltips, shortTags, history,
--             arrowHistory (up/down recall sent lines, plain arrows reach the box), hideButtons (QuickJoinToast,
--             channel, voice buttons): Defaults.lua, Chat.lua:66-91
--   ActionBars always parks MainActionBar and MultiBar* (Park.lua:16-17,81-106; no switch); microMenu / bagBar
--             "hidden" (default) parks them (Hide.lua:15-18,72-83)
--   UnitFrames player.enabled (true) parks PlayerFrame (Blizzard.lua:168-176)
--   InfoPanel map.enabled (true) moves the minimap into its panel (Minimap.lua:1013-1134); the game's XP and
--             reputation bars are hidden unless xp.enabled is false and xp.gameBar true (XPBar.lua:569-579);
--             meter.enabled (true) turns the game's damage meter off (Meter.lua:1118-1124)
--   Buffs     settings.hideBlizzardFrames (true) hides BuffFrame / DebuffFrame (Bar.lua:1401-1457)
--   Quests    always starves the game's tracker (Blizzard.lua:38-78); it FOLLOWS the game's watch list
--             (Data.lua:221-235), so Zone Quests still works with filter "all" and steps aside for "zone" / "log"
--   AuctionHouse enabled (its window over the game's, Window.lua:1-18), tooltip (price lines; works without the
--             window, Tooltip.lua:4-8)
--   Character enabled (replaces CharacterFrame); NPC enabled + trainer (replaces ClassTrainerFrame): true
local function DUIGet(scope, path)
    local api = _G.DaylightUI and _G.DaylightUI.API
    if type(api) ~= "table" or type(api.GetSetting) ~= "function" then return nil end
    local ok, v = pcall(api.GetSetting, scope, path)
    if ok then return v end
    return nil
end
local function DUIModule(name)
    local api = _G.DaylightUI and _G.DaylightUI.API
    if type(api) ~= "table" or type(api.IsModuleEnabled) ~= "function" then return false end
    local ok, on = pcall(api.IsModuleEnabled, name)
    return ok and on == true
end
-- A setting that is on: true, or (for a choice) any value but false. nil = the module is off.
local function DUIOn(scope, path)
    if not DUIModule(scope) then return false end
    local v = DUIGet(scope, path)
    return v ~= nil and v ~= false
end
-- For modules that fit in with DaylightUI rather than step aside (QoL Trainer.lua's minimap button).
VUI.DaylightOn = DUIOn

local DUI_TITLE = "DaylightUI"
local function D(module, key, duiAddon, feature, when, reason)
    return { module = module, key = key, addon = duiAddon, title = DUI_TITLE, feature = feature, when = when,
             reason = reason }
end
local function Replaces(what)
    return "DaylightUI replaces " .. what .. ", so this has nothing to change. Turn that off there and /reload "
        .. "to use this one."
end
local AH = "VeritasUI_AuctionHouse"
local function ActionBarsOn() return DUIModule("ActionBars") end
local function ChatOn() return DUIModule("Chat") end
local function MapOn() return DUIOn("InfoPanel", "map.enabled") end
local function RichTips() return DUIModule("Tooltip") and DUIGet("Tooltip", "style") ~= "simple" end
local function CharacterOn() return DUIOn("Character", "enabled") end
for _, rule in ipairs({
    -- Interface
    D(IFACE, "fadeActionBars", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn, Replaces("the action bars")),
    D(IFACE, "fadeMainActionBar", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn, Replaces("the action bars")),
    D(IFACE, "hideMacroNames", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn, Replaces("the action bars")),
    D(IFACE, "hideKeybindText", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn, Replaces("the action bars")),
    D(IFACE, "outOfRangeIcons", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn, Replaces("the action bars")),
    -- The micro menu and bag bar: "hidden" parks them, "shown" hands them to its own fade (microMenuFade /
    -- bagBarFade) and skins them (Hide.lua:1-6; Options.lua:442-444) -- DaylightUI handles them either way
    -- (owner, 2026-11-24: our Fade Micro Menu did nothing).
    D(IFACE, "fadeMicroMenu", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn,
        "DaylightUI hides or fades the micro menu itself, so this has nothing to change. Turn its Action Bars off "
        .. "and /reload to use this one."),
    D(IFACE, "fadeBagButtons", "DaylightUI_ActionBars", "Action Bars", ActionBarsOn,
        "DaylightUI hides or fades the bag bar itself, so this has nothing to change. Turn its Action Bars off "
        .. "and /reload to use this one."),
    D(IFACE, "fadePlayerFrame", "DaylightUI_UnitFrames", "Unit Frames", function()
        return DUIOn("UnitFrames", "player.enabled")
    end, Replaces("the player frame")),
    D(IFACE, "fadeMinimapButtons", "DaylightUI_InfoPanel", "Info Panel", MapOn, Replaces("the minimap")),
    D(IFACE, "fadeMinimapAlerts", "DaylightUI_InfoPanel", "Info Panel", MapOn, Replaces("the minimap")),
    D(IFACE, "fadeStatusBars", "DaylightUI_InfoPanel", "Info Panel", function()
        return DUIModule("InfoPanel")
            and not (DUIGet("InfoPanel", "xp.enabled") == false and DUIGet("InfoPanel", "xp.gameBar") == true)
    end, Replaces("the experience and reputation bars")),
    -- Its own meter turns the game's off and never back on (Meter.lua:1118-1124), so with the game's meter
    -- still off there is nothing for our fade either (owner, 2026-11-24: our fade did nothing).
    D(IFACE, "fadeDamageMeter", "DaylightUI_InfoPanel", "Info Panel, Damage meter", function()
        if not DUIModule("InfoPanel") then return false end
        if DUIOn("InfoPanel", "meter.enabled") then return true end
        local ok, v = pcall(GetCVar, "damageMeterEnabled")
        return ok and v == "0"
    end, Replaces("the damage meter")),
    D(IFACE, "fadeAuras", "DaylightUI_Buffs", "Buffs", function()
        return DUIOn("Buffs", "settings.hideBlizzardFrames")
    end, Replaces("the buff frames")),
    D(IFACE, "fadeObjectiveTracker", "DaylightUI_Quests", "Quests", function() return DUIModule("Quests") end,
        Replaces("the quest tracker")),
    D(IFACE, "fadeChatTabs", "DaylightUI_Chat", "Chat", ChatOn, Replaces("the chat window")),
    D(IFACE, "hideChatButtons", "DaylightUI_Chat", "Chat, Hide buttons", function()
        return DUIOn("Chat", "hideButtons")
    end),
    D(IFACE, "hideVoiceChatButton", "DaylightUI_Chat", "Chat, Hide buttons", function()
        return DUIOn("Chat", "hideButtons")
    end),
    D(IFACE, "hideSocialButton", "DaylightUI_Chat", "Chat, Hide buttons", function()
        return DUIOn("Chat", "hideButtons")
    end),
    D(IFACE, "hideErrorText", "DaylightUI_QoL", "Quality of Life, error messages", function()
        return DUIOn("QoL", "quietErrors") or DUIOn("QoL", "errorText")
    end),
    D(IFACE, "hideTopBanners:zone", "DaylightUI_QoL", "Quality of Life, Zone title", function()
        return DUIOn("QoL", "zoneTitle")
    end),
    D(IFACE, "hideTopBanners:levelup", "DaylightUI_QoL", "Quality of Life, Level up", function()
        return DUIOn("QoL", "levelUp")
    end),
    -- Zone Quests: DaylightUI's tracker follows the game's watch list, so filtering it works -- unless its own
    -- filter shows the current zone ("zone") or the whole quest log ("log").
    D("VeritasUI_ZoneQuests", "enabled", "DaylightUI_Quests", "Quests, Show", function()
        return DUIModule("Quests") and DUIGet("Quests", "filter") ~= "all" and DUIGet("Quests", "filter") ~= nil
    end, "DaylightUI's quest tracker already picks which quests to show: it is set to show this zone's quests or "
        .. "your whole quest log. Set it to show your tracked quests there and /reload to use this one."),
    -- Quality of Life
    D(QOL, "autoSellJunk", "DaylightUI_Bags", "Bags, Sell junk", function()
        return DUIOn("Bags", "enabled") and DUIOn("Bags", "sellJunk")
    end),
    D(QOL, "autoRepair", "DaylightUI_Bags", "Bags, Repair", function()
        return DUIOn("Bags", "enabled") and DUIOn("Bags", "autoRepair")
    end),
    D(QOL, "afkScreen", "DaylightUI_QoL", "Quality of Life, AFK screen", function()
        return DUIOn("QoL", "afkScreen")
    end),
    -- Its own Train all button on the game's trainer window, or its trainer page in place of that window.
    D(QOL, "trainAllButton", "DaylightUI_QoL", "Quality of Life, Train all", function()
        return DUIOn("QoL", "trainAll")
    end),
    D(QOL, "trainAllButton", "DaylightUI", "Trainer page", function()
        return DUIOn("NPC", "enabled") and DUIOn("NPC", "trainer")
    end, Replaces("the trainer window")),
    D(QOL, "fillDeleteConfirm", "DaylightUI_QoL", "Quality of Life, Delete", function()
        return DUIOn("QoL", "autoDelete")
    end),
    D(QOL, "skipCinematics", "DaylightUI_QoL", "Quality of Life, Skip cinematics", function()
        return DUIOn("QoL", "skipCinematics")
    end),
    D(QOL, "pickOnlyGossip", "DaylightUI_QoL", "Quality of Life, Skip gossip", function()
        return DUIOn("QoL", "skipGossip")
    end),
    D(QOL, "autoAcceptQuest", "DaylightUI_QoL", "Quality of Life, Accept quests", function()
        return DUIOn("QoL", "questAccept")
    end),
    D(QOL, "autoTurnInQuest", "DaylightUI_QoL", "Quality of Life, Turn in quests", function()
        return DUIOn("QoL", "questTurnIn")
    end),
    D(QOL, "tooltipClassNames", "DaylightUI_Tooltip", "Tooltip", function()
        return RichTips() or DUIOn("Tooltip", "classColors")
    end),
    D(QOL, "tooltipGuildmates", "DaylightUI_Tooltip", "Tooltip, Rich style", RichTips),
    D(QOL, "tooltipFactionColors", "DaylightUI_Tooltip", "Tooltip, Rich style", RichTips),
    D(QOL, "tooltipTarget", "DaylightUI_Tooltip", "Tooltip, Target", function()
        return DUIOn("Tooltip", "showTarget")
    end),
    D(QOL, "tooltipGuildRank", "DaylightUI_Tooltip", "Tooltip, Guild rank", function()
        return DUIOn("Tooltip", "guildRank")
    end),
    D(QOL, "chatCopyButton", "DaylightUI_Chat", "Chat, Copy button", function() return DUIOn("Chat", "copyButton") end),
    D(QOL, "chatItemTooltips", "DaylightUI_Chat", "Chat, Link tooltips", function()
        return DUIOn("Chat", "linkTooltips")
    end),
    D(QOL, "chatShortChannels", "DaylightUI_Chat", "Chat, Short tags", function()
        return DUIOn("Chat", "shortTags")
    end),
    D(QOL, "chatRememberLines", "DaylightUI_Chat", "Chat, History", function() return DUIOn("Chat", "history") end),
    D(QOL, "chatRememberTyped", "DaylightUI_Chat", "Chat, Arrow history", function()
        return DUIOn("Chat", "arrowHistory")
    end),
    D(QOL, "chatArrowKeys", "DaylightUI_Chat", "Chat, Arrow history", function()
        return DUIOn("Chat", "arrowHistory")
    end),
    D(QOL, "chatNeverFade", "DaylightUI_Chat", "Chat", ChatOn, Replaces("the chat window")),
    D(QOL, "charEnchants", "DaylightUI", "Character window", CharacterOn, Replaces("the character window")),
    D(QOL, "charDurability", "DaylightUI", "Character window", CharacterOn, Replaces("the character window")),
    D(QOL, "charStatHighlight", "DaylightUI", "Character window", CharacterOn, Replaces("the character window")),
    -- Auction House: its window over the game's (our sell strip and Scan button sit on the game's), and its
    -- tooltip prices (ours would be a second price line).
    D(AH, "ahWindow", "DaylightUI_AuctionHouse", "Auction House", function()
        return DUIOn("AuctionHouse", "enabled")
    end, Replaces("the Auction House window")),
    D(AH, "ttShowPrice", "DaylightUI_AuctionHouse", "Auction House, Tooltip prices", function()
        return DUIOn("AuctionHouse", "tooltip")
    end),
}) do VUI.CONFLICT_RULES[#VUI.CONFLICT_RULES + 1] = rule end

local function Loaded(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded
    if not fn then return false end
    local ok, yes = pcall(fn, name)
    return ok and yes and true or false
end

-- "Leatrix Plus is doing this (Sell junk automatically). Turn it off there and /reload to use this one."
-- The reason names the AddOn (owner, 2026-11-24: a greyed option's tooltip may name the AddOn that greys it).
-- A rule may carry its own `reason` where "doing this" would not fit. Plain text: callers colour the whole line
-- red (TipWithReason, GameTooltip_AddErrorLine).
function VUI.ConflictReason(rule)
    if rule.reason then return rule.reason end
    return (rule.title or "Another AddOn") .. " is doing this (" .. rule.feature
        .. "). Turn it off there and /reload to use this one."
end

local resolved = {}
local takenBy = {}   -- takenBy[module][key] = the AddOn's name, for VUI.ConflictTitle
-- Marks every option of `module` that another AddOn is doing. Called by VUI.OptionUnavailable.
-- Not remembered while DaylightUI is loaded but has not switched its modules on yet (they start in its own
-- PLAYER_LOGIN): asked again, the answer can still change.
function VUI.ResolveConflicts(module)
    if resolved[module] then return end
    for _, rule in ipairs(VUI.CONFLICT_RULES) do
        if rule.module == module and Loaded(rule.addon) then
            local ok, on = pcall(rule.when)
            if ok and on then
                VUI.SetOptionUnavailable(module, rule.key, VUI.ConflictReason(rule))
                takenBy[module] = takenBy[module] or {}
                takenBy[module][rule.key] = rule.title
            end
        end
    end
    local dui = _G.DaylightUI
    local duiPending = type(dui) == "table" and Loaded("DaylightUI") and not dui.loggedIn
    if IsLoggedIn and IsLoggedIn() and not duiPending then resolved[module] = true end
end

-- The name of the AddOn doing an option of `module` (a conflict rule's title), or nil.
function VUI.ConflictTitle(module, key)
    VUI.ResolveConflicts(module)
    return takenBy[module] and takenBy[module][key] or nil
end
