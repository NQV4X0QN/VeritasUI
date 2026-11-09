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
    L(IFACE, "muteSpellFizzle", "Mute game sounds", function()
        return Lea("MuteGameSounds") and Lea("MuteFizzle")
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
        "Another AddOn's quest tracker replaces the game's (its Enable Tracker option), so there is no tracker "
        .. "here to fade. Turn that off to use this one."),
    Q("VeritasUI_ZoneQuests", "enabled", "Enable Tracker", QuestieTracker,
        "Another AddOn's quest tracker replaces the game's (its Enable Tracker option) and keeps its own list "
        .. "of quests, so Zone Quests cannot filter it. Turn that off to use this one."),
}) do VUI.CONFLICT_RULES[#VUI.CONFLICT_RULES + 1] = rule end

local function Loaded(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded
    if not fn then return false end
    local ok, yes = pcall(fn, name)
    return ok and yes and true or false
end

-- "Another AddOn is doing this (Sell junk automatically). Turn it off there and /reload to use this one."
-- A rule may carry its own `reason` where "doing this" would not fit. Plain text: callers colour the whole line
-- red (TipWithReason, GameTooltip_AddErrorLine).
function VUI.ConflictReason(rule)
    if rule.reason then return rule.reason end
    return "Another AddOn is doing this (" .. rule.feature .. "). Turn it off there and /reload to use this one."
end

local resolved = {}
-- Marks every option of `module` that another AddOn is doing. Called by VUI.OptionUnavailable.
function VUI.ResolveConflicts(module)
    if resolved[module] then return end
    for _, rule in ipairs(VUI.CONFLICT_RULES) do
        if rule.module == module and Loaded(rule.addon) then
            local ok, on = pcall(rule.when)
            if ok and on then VUI.SetOptionUnavailable(module, rule.key, VUI.ConflictReason(rule)) end
        end
    end
    if IsLoggedIn and IsLoggedIn() then resolved[module] = true end
end
