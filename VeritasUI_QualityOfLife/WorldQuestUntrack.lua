-- VeritasUI_QualityOfLife / WorldQuestUntrack.lua
-- Untrack World Quests When Unfocused (v1.51.0, owner's request).
--
-- Clicking a world quest on the map tracks it AUTOMATICALLY and focuses it; clicking it again only
-- clears the focus, so the quest stayed in the tracker until untracked by hand (WorldQuestDataProvider.lua
-- :430-460: TrackWorldQuest(questID, Automatic) then SetSuperTrackedQuestID; a second click sets it to 0).
-- When focus leaves a world quest that is still AUTOMATICALLY watched, this removes the watch, the same
-- call Blizzard's own untrack makes (QuestUtils.lua:398-405, C_QuestLog.RemoveWorldQuestWatch). A world
-- quest tracked on purpose (shift-click, or Track in its menu: QuestWatchType.Manual) is left alone, and
-- one you are standing in still shows, as Blizzard shows it.
-- C API only: nothing of Blizzard's Lua is called or written. Blizzard's tracker updates itself on
-- QUEST_WATCH_LIST_CHANGED (QuestObjectiveTracker.lua:3), so no tracker call is needed.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall = pcall

local function Enabled()
    local db = _G.VeritasUI_QualityOfLifeDB
    -- Off unless saved on (v1.74.0: off by default, so an unseeded table must not read as on).
    return type(db) == "table" and db.untrackWorldQuestsOnUnfocus == true
end

local function Current()
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return nil end
    local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if ok and type(id) == "number" and id > 0 then return id end
end

local previous
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SUPER_TRACKING_CHANGED")
f:SetScript("OnEvent", function(_, event)
    local now = Current()
    local was = previous
    previous = now
    if event ~= "SUPER_TRACKING_CHANGED" or not was or was == now or not Enabled() then return end
    local ql = C_QuestLog
    if not (ql and ql.IsWorldQuest and ql.GetQuestWatchType and ql.RemoveWorldQuestWatch) then return end
    local okW, isWQ = pcall(ql.IsWorldQuest, was)
    if not (okW and isWQ) then return end
    local okT, watch = pcall(ql.GetQuestWatchType, was)
    local automatic = Enum and Enum.QuestWatchType and Enum.QuestWatchType.Automatic
    if okT and automatic ~= nil and watch == automatic then
        pcall(ql.RemoveWorldQuestWatch, was)
    end
end)
