-- VeritasUI_ZoneQuests / ZoneQuests.lua
-- Filters the Objective Tracker to show only quests for your current zone.
-- Special quest types can be pinned so they always show regardless of zone.
--
-- Settings: Options → AddOns → Zone Quests   |   /zq   |   /zonequests

local ADDON_NAME   = "VeritasUI_ZoneQuests"
local SETTINGS_LABEL = "Zone Quests"
local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

-- ── Saved variable defaults ────────────────────────────────────────
local DEFAULTS = {
    enabled       = true,
    manualWatched = {},     -- { [questID] = true } for snapshot/restore
    pinCampaign   = true,
    pinImportant  = true,
    pinLegendary  = true,
    pinMeta       = true,
    pinRepeatable = true,
}

local db = nil  -- assigned only after ADDON_LOADED

-- ── Directional prefix stripper ───────────────────────────────────
local DIRECTIONAL = {
    ["northern "]=true, ["southern "]=true, ["eastern "]=true,
    ["western "]=true,  ["upper "]=true,    ["lower "]=true,
    ["inner "]=true,    ["outer "]=true,    ["the "]=true,
}
local function StripDir(s)
    for p in pairs(DIRECTIONAL) do
        if s:sub(1, #p) == p then return s:sub(#p + 1) end
    end
    return s
end

-- ── Zone name set ─────────────────────────────────────────────────
local function BuildZoneNameSet()
    local t = {}
    local function add(s)
        if not s or s == "" then return end
        local lo = s:lower()
        t[lo] = true
        local st = StripDir(lo)
        if st ~= lo then t[st] = true end
    end
    add(GetRealZoneText())
    add(GetZoneText())
    add(GetSubZoneText())
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapID and mapID > 0 then
        local seen, safety = {}, 0
        while mapID and mapID > 0 and safety < 20 do
            if seen[mapID] then break end
            seen[mapID] = true
            safety = safety + 1
            local info = C_Map.GetMapInfo(mapID)
            if not info then break end
            add(info.name)
            local par = info.parentMapID
            if not par or par <= 0 or par == 946 or par == 947 then break end
            mapID = par
        end
    end
    return t
end

local function HeaderMatches(header, nameSet)
    if not header or header == "" then return false end
    local h = header:lower()
    if nameSet[h] then return true end
    local hs = StripDir(h)
    if nameSet[hs] then return true end
    for name in pairs(nameSet) do
        if #name > 4 then
            if h:find(name, 1, true) then return true end
            if name:find(hs, 1, true) then return true end
        end
    end
    return false
end

-- ── Watch type ────────────────────────────────────────────────────
local WATCH_TYPE = nil
local function GetWatchType()
    if WATCH_TYPE == nil then
        WATCH_TYPE = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 0
    end
    return WATCH_TYPE
end

-- Enum-safe constant — avoids hardcoded magic numbers.
local META_CLASSIFICATION = (Enum and Enum.QuestClassification and Enum.QuestClassification.Meta) or 4

-- ── Always-track predicate ────────────────────────────────────────
local function IsAlwaysTracked(info)
    if not db then return false, nil end

    local tagName = nil
    if info.questID then
        local tok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, info.questID)
        if tok and tagInfo and tagInfo.tagName then
            tagName = tagInfo.tagName:lower()
        end
    end

    if db.pinCampaign then
        if info.isCampaign or (info.campaignID and info.campaignID > 0) then
            return true, "campaign"
        end
        if tagName and tagName:find("campaign", 1, true) then
            return true, "campaign"
        end
    end

    if db.pinImportant then
        if info.isImportant then return true, "important" end
        if tagName and tagName:find("important", 1, true) then
            return true, "important"
        end
    end

    if db.pinLegendary then
        if info.isLegendary then return true, "legendary" end
        if tagName and tagName:find("legendary", 1, true) then
            return true, "legendary"
        end
    end

    if db.pinMeta then
        if info.isMeta then return true, "meta" end
        if info.questClassification == META_CLASSIFICATION then return true, "meta" end
        if tagName and tagName:find("meta", 1, true) then
            return true, "meta"
        end
    end

    if db.pinRepeatable then
        if (info.frequency and info.frequency ~= 0) or info.isRepeatable then
            return true, "repeatable"
        end
    end

    return false, nil
end

-- ── Core sync ─────────────────────────────────────────────────────
-- lastDirectSync prevents duplicate work when QUEST_LOG_UPDATE fires
-- immediately after a zone-change-triggered sync.
local lastDirectSync = 0
local SYNC_COOLDOWN  = 0.5
local cachedNameSet  = nil   -- rebuilt on ZONE_CHANGED*, reused for QUEST_LOG_UPDATE

local function SyncTracking(verbose)
    if not db or not db.enabled then
        if verbose then print("[ZQ sync] disabled, aborting.") end
        return
    end

    local nameSet   = cachedNameSet or BuildZoneNameSet()
    local watchType = GetWatchType()
    local removed, added = 0, 0
    local currentHeader = nil

    -- Preserve the quest the player is actively navigating to (minimap arrow).
    -- Checking at sync time avoids event-ordering and arg-capture issues.
    local superQuestID = (C_SuperTrack
        and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID()) or 0

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if not ok or not info then
            if verbose then print("[ZQ sync] GetInfo(" .. i .. ") failed") end
        elseif info.isHeader then
            currentHeader = info.title
        elseif not info.isHidden and info.questID then
            local pinned, tag = IsAlwaysTracked(info)
            local inZone = HeaderMatches(currentHeader, nameSet)
            local superTracked = superQuestID ~= 0 and info.questID == superQuestID

            if pinned or inZone or superTracked then
                local ok2 = pcall(C_QuestLog.AddQuestWatch, info.questID, watchType)
                if verbose then
                    local lbl = tag and (" (" .. tag .. ")") or (superTracked and " (super-tracked)") or ""
                    print("[ZQ sync] ADD" .. lbl .. " '" .. tostring(info.title) .. "' ok=" .. tostring(ok2))
                end
                if ok2 then added = added + 1 end
            else
                local ok2 = pcall(C_QuestLog.RemoveQuestWatch, info.questID)
                if verbose then
                    print("[ZQ sync] REMOVE '" .. tostring(info.title) .. "' ok=" .. tostring(ok2))
                end
                if ok2 then removed = removed + 1 end
            end
        end
    end

    if verbose then print("[ZQ sync] Done. removed=" .. removed .. " added=" .. added) end
end

-- ── Snapshot / restore (uses questID for reliable matching) ───────
-- NOTE: Midnight removed IsQuestWatched(), so there is no API to
-- query which quests the player had manually tracked.  The snapshot
-- records ALL non-hidden quests as "watched".  This means disabling
-- Zone Quests will re-track everything rather than restoring the
-- exact pre-enable state.  This is an accepted Midnight limitation.
local function SnapshotWatched()
    db.manualWatched = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and not info.isHeader and not info.isHidden and info.questID then
            db.manualWatched[info.questID] = true
        end
    end
end

local function RestoreWatched()
    local watchType = GetWatchType()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and not info.isHeader and info.questID then
            if db.manualWatched[info.questID] then
                pcall(C_QuestLog.AddQuestWatch, info.questID, watchType)
            else
                pcall(C_QuestLog.RemoveQuestWatch, info.questID)
            end
        end
    end
end

local function ZoneName()
    return GetRealZoneText() or GetZoneText() or "Unknown"
end

-- ── Debounce ──────────────────────────────────────────────────────
local debounceTimer = nil
local function ScheduleSync()
    if debounceTimer then debounceTimer:Cancel() end
    debounceTimer = C_Timer.NewTimer(0.3, function()
        debounceTimer = nil
        -- Skip if a direct sync ran recently (zone change)
        if (GetTime() - lastDirectSync) > SYNC_COOLDOWN then
            SyncTracking(false)
        end
    end)
end

-- ── Options Panel — Blizzard native vertical layout ───────────────
local registeredCategory = nil
local settingsCategoryID

local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local enableSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_enabled",
        "enabled",
        VeritasUI_ZoneQuestsDB,
        type(DEFAULTS.enabled),
        "Enable Zone Filtering",
        DEFAULTS.enabled
    )
    enableSetting:SetValueChangedCallback(function(_, value)
        if value then
            SnapshotWatched()
            SyncTracking(false)
            VUI.Print("Zone Quests", "|cFF00FF00On.|r Filtering to |cFFFFCC00" .. ZoneName() .. "|r")
        else
            RestoreWatched()
            VUI.Print("Zone Quests", "|cFFFF4444Off.|r All quests shown.")
        end
    end)
    Settings.CreateCheckbox(category, enableSetting,
        "When enabled, only quests in your current zone appear in the Objective Tracker. "
        .. "Disabling will re-track all quests (Midnight removed the API to remember your original tracking state).")

    local pins = {
        { key = "pinCampaign",
          name = "Always Show: Campaign Quests",
          tip  = "Campaign quests always appear in the tracker regardless of your current zone." },
        { key = "pinImportant",
          name = "Always Show: Important Quests",
          tip  = "Important (story-critical) quests always appear. These use a pink exclamation mark." },
        { key = "pinLegendary",
          name = "Always Show: Legendary Quests",
          tip  = "Legendary quests always appear. These use a golden icon." },
        { key = "pinMeta",
          name = "Always Show: Meta Quests",
          tip  = "Meta quests always appear. These use a cyan icon and are usually zone-wide activities." },
        { key = "pinRepeatable",
          name = "Always Show: Daily & Weekly Quests",
          tip  = "Repeatable quests (dailies and weeklies) always appear in the tracker." },
    }

    for _, opt in ipairs(pins) do
        local setting = Settings.RegisterAddOnSetting(
            category,
            ADDON_NAME .. "_" .. opt.key,
            opt.key,
            VeritasUI_ZoneQuestsDB,
            type(DEFAULTS[opt.key]),
            opt.name,
            DEFAULTS[opt.key]
        )
        setting:SetValueChangedCallback(function(_, _)
            SyncTracking(false)
        end)
        Settings.CreateCheckbox(category, setting, opt.tip)
    end

    Settings.RegisterAddOnCategory(category)
    registeredCategory = category
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

-- ── Events ────────────────────────────────────────────────────────
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("ZONE_CHANGED")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("ZONE_CHANGED_INDOORS")
ef:RegisterEvent("QUEST_LOG_UPDATE")
ef:RegisterEvent("QUEST_ACCEPTED")
ef:RegisterEvent("SUPER_TRACKING_CHANGED")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        VeritasUI_ZoneQuestsDB = VeritasUI_ZoneQuestsDB or {}
        for k, v in pairs(DEFAULTS) do
            if VeritasUI_ZoneQuestsDB[k] == nil then
                VeritasUI_ZoneQuestsDB[k] = v
            end
        end
        -- Migrate old title-based snapshot to questID-based format
        if VeritasUI_ZoneQuestsDB.manualWatched then
            local first = next(VeritasUI_ZoneQuestsDB.manualWatched)
            if first and type(VeritasUI_ZoneQuestsDB.manualWatched[first]) == "table" then
                VeritasUI_ZoneQuestsDB.manualWatched = {}
            end
        end
        db = VeritasUI_ZoneQuestsDB
        InitializeOptions()
        ef:UnregisterEvent("ADDON_LOADED")
        return
    end

    if not db then return end

    if event == "PLAYER_LOGIN" then
        C_Timer.After(2.0, function()
            SnapshotWatched()
            SyncTracking(false)
            if db.enabled then
                VUI.Print("Zone Quests", "Active for |cFFFFCC00" .. ZoneName()
                    .. "|r  —  /zq or Options › AddOns › Zone Quests")
            end
        end)

    elseif event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED_INDOORS" then
        if debounceTimer then debounceTimer:Cancel(); debounceTimer = nil end
        cachedNameSet = BuildZoneNameSet()
        lastDirectSync = GetTime()
        SyncTracking(false)

    elseif event == "QUEST_ACCEPTED" then
        C_Timer.After(0.5, function() SyncTracking(false) end)

    elseif event == "SUPER_TRACKING_CHANGED" then
        -- Player set or cleared the minimap direction arrow. Re-sync so the
        -- quest appears/disappears from the tracker promptly.
        ScheduleSync()

    elseif event == "QUEST_LOG_UPDATE" then
        ScheduleSync()
    end
end)

-- ── Slash commands ────────────────────────────────────────────────
SLASH_VERITASUI_ZONEQUESTS1 = "/zq"
SLASH_VERITASUI_ZONEQUESTS2 = "/zonequests"
SlashCmdList["VERITASUI_ZONEQUESTS"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "off" or msg == "disable" then
        if not db then VUI.Print("Zone Quests", "Not ready."); return end
        if not db.enabled then VUI.Print("Zone Quests", "Already off."); return end
        db.enabled = false
        RestoreWatched()
        VUI.Print("Zone Quests", "|cFFFF4444Off.|r  /zq on to re-enable.")

    elseif msg == "on" or msg == "enable" then
        if not db then VUI.Print("Zone Quests", "Not ready."); return end
        if db.enabled then VUI.Print("Zone Quests", "Already on."); return end
        db.enabled = true
        SnapshotWatched()
        SyncTracking(false)
        VUI.Print("Zone Quests", "|cFF00FF00On.|r  " .. ZoneName())

    elseif msg == "refresh" then
        if not db then VUI.Print("Zone Quests", "Not ready."); return end
        SyncTracking(false)
        VUI.Print("Zone Quests", "Refreshed — " .. ZoneName())

    elseif msg == "synctest" then
        VUI.Print("Zone Quests", "|cFFFFFF00Running verbose sync...|r")
        SyncTracking(true)

    elseif msg:sub(1, 9) == "dumpquest" then
        local search = strtrim(msg:sub(10)):lower()
        if search == "" then
            VUI.Print("Zone Quests", "Usage: /zq dumpquest |cFFFFCC00<partial quest name>|r")
            return
        end
        local found = 0
        VUI.Print("Zone Quests", "|cFFFFFF00Searching for '|r" .. search .. "|cFFFFFF00'...|r")
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and info and not info.isHeader and info.title then
                if info.title:lower():find(search, 1, true) then
                    found = found + 1
                    print("|cFFFFCC00[" .. i .. "] Quest: |r" .. tostring(info.title))
                    local keys = {}
                    for k in pairs(info) do table.insert(keys, k) end
                    table.sort(keys)
                    for _, k in ipairs(keys) do
                        if info[k] ~= nil then
                            print("  |cFFAAFFAA" .. tostring(k) .. "|r = |cFFFFFFFF" .. tostring(info[k]) .. "|r")
                        end
                    end
                    if info.questID then
                        local tok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, info.questID)
                        if tok and tagInfo then
                            print("  |cFFCCCCFF--- GetQuestTagInfo ---")
                            local tkeys = {}
                            for k in pairs(tagInfo) do table.insert(tkeys, k) end
                            table.sort(tkeys)
                            for _, k in ipairs(tkeys) do
                                if tagInfo[k] ~= nil then
                                    print("  |cFFAAAAFF" .. tostring(k) .. "|r = |cFFFFFFFF" .. tostring(tagInfo[k]) .. "|r")
                                end
                            end
                        end
                    end
                end
            end
        end
        if found == 0 then
            VUI.Print("Zone Quests", "No quests found matching '" .. search .. "'.")
        else
            VUI.Print("Zone Quests", "Found " .. found .. " quest(s).")
        end

    elseif msg == "debug" then
        VUI.Print("Zone Quests", "|cFFFFFF00Debug:|r")
        print("  RealZone: " .. (GetRealZoneText() or "nil"))
        print("  Zone:     " .. (GetZoneText()     or "nil"))
        print("  SubZone:  " .. (GetSubZoneText()  or "nil"))
        local ns = BuildZoneNameSet()
        local nl = {}
        for n in pairs(ns) do table.insert(nl, n) end
        table.sort(nl)
        print("  Name set: " .. table.concat(nl, ", "))
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and info and info.isHeader then
                local m = HeaderMatches(info.title, ns)
                print("    [" .. (m and "|cFF44FF44MATCH|r" or "|cFFFF6666miss|r") .. "] " .. tostring(info.title))
            end
        end
        print("  WatchType: " .. tostring(GetWatchType()))
        print("  db.enabled: " .. tostring(db and db.enabled))

    else
        if registeredCategory then
            Settings.OpenToCategory(settingsCategoryID)
        else
            VUI.Print("Zone Quests", "Settings not ready yet.")
        end
    end
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_ZoneQuests_OnAddonCompartmentClick()
    if registeredCategory then
        C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
    end
end
