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
-- Saved settings, split by SCOPE. The authority on which key goes where is
-- ~/.agents/skills/veritasui/references/setting-scope-map.md; `scope_map_test` enforces it.
-- Shared by every character: filtering choices are about how the player wants the tracker to
-- behave, not about a particular character's progress.
local UNIVERSAL = {
    enabled       = true,
    pinCampaign   = true,
    pinImportant  = true,
    pinLegendary  = true,
    pinMeta       = true,
    pinRepeatable = true,
}

-- ⚠ PER-CHARACTER, and not a preference: `manualWatched` is a snapshot of THIS character's
-- quest log ({ [questID] = true }). Sharing it would restore watch state for quests an alt has
-- never picked up.
local PERCHAR = {
    manualWatched = {},
}

local db  = nil  -- ACCOUNT-wide table; assigned at ADDON_LOADED
-- ⚠ Declared HERE, above every function that reads it. `cdb` is the PER-CHARACTER table and is
-- nil until PLAYER_LOGIN. SnapshotWatched/RestoreWatched reference it ~200 lines below this
-- point but are DEFINED above the assignment, so without this declaration the assignment would
-- create a global and those reads would silently resolve to it -- the /way v1.6.33 trap.
local cdb = nil  -- PER-CHARACTER table (manualWatched only); nil until PLAYER_LOGIN

-- ── No hot-global localization block here, on purpose ─────────────
-- Most modules in the suite open with a block of `local x = x` upvalues; this one
-- does not, and C_QuestLog, C_Map, pcall, table.insert, table.sort and GetTime are
-- consumed as bare globals, including inside the quest-log loops. That is the right
-- trade here and not an oversight: those blocks exist for genuinely hot paths — the
-- auction scan's per-row work runs hundreds of thousands of times, and the scan
-- progress bar's runs every frame — whereas this module's heaviest loop is driven by
-- a debounced event and walks a quest log of roughly 25-50 entries. Adding a block to
-- match the other modules would trade real lines for an unmeasurable saving.

-- ── Map-type constants (used by the location-based quest scan) ────
local MAP_TYPE_WORLD  = (Enum and Enum.UIMapType and Enum.UIMapType.World)  or 1
local MAP_TYPE_COSMIC = (Enum and Enum.UIMapType and Enum.UIMapType.Cosmic) or 0

-- ── Valid map set: current best map + descendant sub-areas ────────
-- The maps that count as "this zone" for the purpose of accepting a
-- POI. A city inside the current zone (Silvermoon City 2393 under
-- Eversong Woods 2395) is a descendant and counts; a SIBLING zone whose
-- art merely abuts the current map (Zul'Aman 2536) is NOT a descendant
-- and is rejected. Returns (set, bestMapID); bestMapID 0 if unresolved.
local function BuildValidMapSet()
    local set = {}
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID or mapID <= 0 then return set, 0 end
    set[mapID] = true
    local cok, children = pcall(C_Map.GetMapChildrenInfo, mapID, nil, true)
    if cok and children then
        for _, c in ipairs(children) do
            if c.mapID then set[c.mapID] = true end
        end
    end
    return set, mapID
end

-- ── Zone quest-ID set (location-based, per-POI mapID filtered) ────
-- Quest IDs whose POIs are on the current zone map (C_QuestLog.GetQuestsOnMap)
-- AND whose POI entry's own mapID belongs to the current zone or a
-- descendant sub-area. The per-POI mapID is the authoritative fix for the
-- sibling-bleed problem: when Zul'Aman (2536) terrain draws inside the
-- Eversong (2395) map, GetQuestsOnMap returns the Zul'Aman quests too, but
-- each carries mapID=2536, so the valid-map test rejects them. Verified
-- in-game (Eversong, best map 2395; via a temporary POI-struct probe):
--   Swords / Shrine (Zul'Aman)  → entry mapID 2536 → REJECTED
--   Windrunner (Eversong)        → entry mapID 2395 → kept
--   Stalkers / Veterans          → entry mapID 2393 (Silvermoon, a child) → kept
-- (GetQuestUiMapID was tried and REJECTED — it returns a quest's anchor/hub
-- map, not its objective zone; the per-POI mapID here is the objective's.)
-- Walks up to the closest non-empty map level, then filters that level.
-- Returns a set keyed by questID.
local function BuildZoneQuestSet()
    local set = {}
    local validMaps, bestMap = BuildValidMapSet()
    if not bestMap or bestMap == 0 then return set end
    local mapID, seen, safety = bestMap, {}, 0
    while mapID and mapID > 0 and safety < 20 do
        if seen[mapID] then break end
        seen[mapID] = true
        safety = safety + 1
        local info = C_Map.GetMapInfo(mapID)
        if not info then break end
        local mt = info.mapType or -1
        if mt == MAP_TYPE_WORLD or mt == MAP_TYPE_COSMIC then break end
        -- POLICY (falsified "fix", 2026-07-04 — do not re-add it): validMaps
        -- stays anchored to the BEST map + its descendants even when the walk
        -- ascends.  A v1.9.2 audit-remediation draft extended the accept set
        -- with each walked ancestor level + its descendants (reasoning: "the
        -- tracker empties in quest-less micro-maps"); in-game it pulled
        -- parent-zone quests into sub-zones — standing in Silvermoon City
        -- surfaced Eversong's Windrunner Spire quest — and was reverted the
        -- same day.  The strict semantics are INTENDED: a map with no quests
        -- of its own shows only pinned quests, and the walk exists solely to
        -- catch quests filed at an ancestor level whose per-POI mapID points
        -- back INTO the best map or its sub-areas (the v1.7.14 "Stalkers of
        -- the Stars" case).  Future audits: treat ascent-level rejection as
        -- policy, not drift.
        local quests = C_QuestLog.GetQuestsOnMap(mapID)
        if quests and #quests > 0 then
            for _, e in ipairs(quests) do
                -- Accept only POIs whose own map is this zone or a sub-area;
                -- reject sibling-zone bleed-ins. If the entry has no mapID,
                -- fall back to accepting (the POI is on our map at all).
                if e.questID and (not e.mapID or e.mapID == 0 or validMaps[e.mapID]) then
                    set[e.questID] = true
                end
            end
            return set   -- stop at the closest level that actually has quests
        end
        local par = info.parentMapID
        if not par or par <= 0 then break end
        mapID = par
    end
    return set
end

-- ── Watch type ────────────────────────────────────────────────────
local WATCH_TYPE = nil
local function GetWatchType()
    if WATCH_TYPE == nil then
        WATCH_TYPE = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 0
    end
    return WATCH_TYPE
end

-- Enum-safe classification constants — avoid hardcoded magic numbers.
-- Meta keeps its in-game-verified numeric fallback (4); the others are
-- nil-guarded at the call site, so a missing enum key merely disables
-- that classification check instead of comparing against a guess.
local QC = (Enum and Enum.QuestClassification) or {}
local QC_CAMPAIGN  = QC.Campaign
local QC_IMPORTANT = QC.Important
local QC_LEGENDARY = QC.Legendary
local QC_META      = QC.Meta or 4
local QC_RECURRING = QC.Recurring

-- ── Always-track predicate ────────────────────────────────────────
-- questClassification is the ONLY trusted quest-type signal (falsified
-- alternative, 2026-07-19 — do not re-add): GetQuestTagInfo tagName
-- substring matching pinned normal quests as important. Probed in-game:
-- "Stalkers of the Stars" (96049) carries tagID 282 / "Important Quest"
-- yet questClassification = 7 (Normal) and renders with normal-quest
-- icons — the tag layer disagrees with the classification layer, and
-- classification is what drives the quest log's visual language (pink !,
-- campaign shield) that the player actually sees. The legacy is* /
-- campaignID field checks remain as a harmless backup for quests where
-- classification is absent (nil never matches them).
local function IsAlwaysTracked(info)
    if not db then return false, nil end

    local qc = info.questClassification

    if db.pinCampaign then
        if info.isCampaign or (info.campaignID and info.campaignID > 0) then
            return true, "campaign"
        end
        if QC_CAMPAIGN and qc == QC_CAMPAIGN then return true, "campaign" end
    end

    if db.pinImportant then
        if info.isImportant then return true, "important" end
        if QC_IMPORTANT and qc == QC_IMPORTANT then return true, "important" end
    end

    if db.pinLegendary then
        if info.isLegendary then return true, "legendary" end
        if QC_LEGENDARY and qc == QC_LEGENDARY then return true, "legendary" end
    end

    if db.pinMeta then
        if info.isMeta then return true, "meta" end
        if qc == QC_META then return true, "meta" end
    end

    if db.pinRepeatable then
        if (info.frequency and info.frequency ~= 0) or info.isRepeatable then
            return true, "repeatable"
        end
        if QC_RECURRING and qc == QC_RECURRING then return true, "repeatable" end
    end

    return false, nil
end

-- ── Core sync ─────────────────────────────────────────────────────
-- lastDirectSync prevents duplicate work when QUEST_LOG_UPDATE fires
-- immediately after a zone-change-triggered sync.
local lastDirectSync = 0
local SYNC_COOLDOWN  = 0.5
local cachedQuestSet = nil   -- rebuilt on ZONE_CHANGED*, reused for QUEST_LOG_UPDATE

local function SyncTracking(verbose)
    if not db or not db.enabled then
        if verbose then print("[ZQ sync] disabled, aborting.") end
        return
    end

    local questSet = cachedQuestSet
    if not questSet then
        questSet = BuildZoneQuestSet()
        cachedQuestSet = questSet  -- cache first build so QUEST_LOG_UPDATE
                                   -- doesn't rebuild on every fire until the
                                   -- first ZONE_CHANGED event invalidates it
    end
    local watchType = GetWatchType()
    local removed, added = 0, 0

    -- Preserve the quest the player is actively navigating to (minimap arrow).
    -- Checking at sync time avoids event-ordering and arg-capture issues.
    local superQuestID = (C_SuperTrack
        and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID()) or 0

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if not ok or not info then
            if verbose then print("[ZQ sync] GetInfo(" .. i .. ") failed") end
        elseif not info.isHeader and not info.isHidden and info.questID then
            local pinned, tag = IsAlwaysTracked(info)
            local inZone = questSet[info.questID] or false
            local superTracked = superQuestID ~= 0 and info.questID == superQuestID

            if pinned or inZone or superTracked then
                local ok2 = pcall(C_QuestLog.AddQuestWatch, info.questID, watchType)
                if verbose then
                    local lbl = tag and (" (" .. tag .. ")")
                        or (inZone and " (zone)")
                        or (superTracked and " (super-tracked)") or ""
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
-- records ALL non-hidden quests at the moment ZQ is enabled or at
-- login, not at the moment it is disabled.  RestoreWatched restores
-- that snapshot state, not the player's original pre-enable tracking.
-- This is an accepted Midnight limitation.
local function SnapshotWatched()
    -- Guards on cdb, not db: manualWatched lives in the per-character table, which is nil
    -- until PLAYER_LOGIN. Both callers already run after that, but a nil guard on the wrong
    -- table is the kind of thing that only shows up when someone adds an earlier caller.
    if not cdb then return end
    cdb.manualWatched = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and not info.isHeader and not info.isHidden and info.questID then
            cdb.manualWatched[info.questID] = true
        end
    end
end

local function RestoreWatched()
    if not cdb then return end
    local watchType = GetWatchType()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and not info.isHeader and info.questID then
            if cdb.manualWatched[info.questID] then
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
local settingsCategoryID

local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local enableSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_enabled",
        "enabled",
        db,                                -- ACCOUNT table: `enabled` is universal
        type(UNIVERSAL.enabled),
        "Enable Zone Filtering",
        UNIVERSAL.enabled
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
            -- ACCOUNT table: every key in this loop is universal. Reading the default from
            -- UNIVERSAL rather than a union of both scopes means that adding a per-character key
            -- here fails loudly instead of silently registering it at account scope.
            db,
            type(UNIVERSAL[opt.key]),
            opt.name,
            UNIVERSAL[opt.key]
        )
        setting:SetValueChangedCallback(function(_, _)
            SyncTracking(false)
        end)
        Settings.CreateCheckbox(category, setting, opt.tip)
    end

    Settings.RegisterAddOnCategory(category)
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
ef:RegisterEvent("SUPER_TRACKING_CHANGED")
-- QUEST_ACCEPTED returns (removed v1.6.27, required again since v1.7.14):
-- the v1.6.27 removal was correct when the cache held the zone NAME set —
-- stable within a zone, so a newly accepted quest still matched by header.
-- v1.7.14 changed the cache to hold the zone QUEST-ID set, which changes on
-- every acceptance: a quest accepted in-zone was not in the stale set, and
-- the next QUEST_LOG_UPDATE sync actively UN-tracked it (undoing Blizzard's
-- auto-watch) until the next zone transition rebuilt the cache. This handler
-- only invalidates the cache and routes through the existing cancellable
-- debounce — NOT the stacked C_Timer.After the v1.6.27 removal eliminated.
-- Deliberately NOT invalidating on QUEST_LOG_UPDATE itself: that fires on
-- every objective tick (each kill credit), and rebuilding the map query per
-- burst is the exact cost the cache exists to avoid; stale IDs for quests
-- no longer in the log are dead keys the sync loop never consults.
ef:RegisterEvent("QUEST_ACCEPTED")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        -- Account table only: no identity yet, so cdb comes back nil. VUI.BindScopedDB
        -- replaces the hand-rolled seeding loop that used to live here -- that loop wrote
        -- EVERY default into the account root, which is the mechanism behind the pinning
        -- defect this refactor fixes, so it had to go rather than sit alongside the binder.
        -- It also deep-copies table defaults, so the local DeepCopy is no longer needed.
        db = VUI.BindScopedDB("VeritasUI_ZoneQuestsDB", UNIVERSAL, PERCHAR)
        -- InitializeOptions stays at PLAYER_LOGIN: Settings.RegisterAddOnSetting captures the
        -- table it is handed, and the per-character table does not exist yet here.
        -- InitializeOptions moved to PLAYER_LOGIN: Settings.RegisterAddOnSetting
        -- captures the table it is handed, so it must receive the per-character
        -- slot, which does not exist yet here.
        ef:UnregisterEvent("ADDON_LOADED")
        return
    end

    if not db then return end

    if event == "PLAYER_LOGIN" then
        -- Identity is available: bind BOTH tables. `db` is account-wide (every universal read
        -- below is unchanged); `cdb` is this character's slot and holds manualWatched only.
        db, cdb = VUI.BindScopedDB("VeritasUI_ZoneQuestsDB", UNIVERSAL, PERCHAR)

        -- ⚠ MIGRATION MUST RUN HERE: after the char table exists, and BEFORE anything reads a
        -- universal key. Read first and the feature acts on the pre-migration value for the
        -- whole session. Promotes this character's stored values for the newly-universal keys
        -- and clears the vestigial account-wide copy of manualWatched.
        local promoted = VUI.MigrateScopedDB("VeritasUI_ZoneQuestsDB", UNIVERSAL, PERCHAR,
                                            "__vuiScopeMigrated")
        if promoted then
            local names = {}
            for k in pairs(promoted) do names[#names + 1] = k end
            table.sort(names)
            VUI.Print("Zone Quests", "settings now shared across characters: "
                .. table.concat(names, ", ") .. "  (taken from this character)")
        end

        -- Old title-based snapshots migrate to questID-based. RE-POINTED at the per-character
        -- table: it used to run at ADDON_LOADED against the account root, which is where the
        -- key no longer lives. The root copy was migrated before any slot was ever seeded from
        -- it, so existing slots are already clean -- this now covers the one case the old
        -- placement never did, a slot created before the migration existed.
        if cdb and cdb.manualWatched then
            local first = next(cdb.manualWatched)
            if first and type(cdb.manualWatched[first]) == "table" then
                cdb.manualWatched = {}
            end
        end

        InitializeOptions()
        C_Timer.After(2.0, function()
            SnapshotWatched()
            SyncTracking(false)
            if db.enabled then
                VUI.Print("Zone Quests", "v" .. VUI.VERSION .. " active for |cFFFFCC00"
                    .. ZoneName() .. "|r  —  |cFFFFFF00/zq|r")
            end
        end)

    elseif event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED_INDOORS" then
        -- Always invalidate the cache so the next sync uses fresh zone data.
        cachedQuestSet = nil
        if not db or not db.enabled then return end
        if debounceTimer then debounceTimer:Cancel(); debounceTimer = nil end
        cachedQuestSet = BuildZoneQuestSet()
        lastDirectSync = GetTime()
        SyncTracking(false)

    elseif event == "QUEST_ACCEPTED" then
        -- Rebuild the zone quest set so the just-accepted quest is judged
        -- against fresh map data instead of being removed by a stale cache
        -- (see the registration comment above). One rebuild per acceptance
        -- burst — the debounce collapses the accompanying QUEST_LOG_UPDATEs.
        cachedQuestSet = nil
        if db.enabled then ScheduleSync() end

    elseif event == "SUPER_TRACKING_CHANGED" then
        -- Player set or cleared the minimap direction arrow. Re-sync so the
        -- quest appears/disappears from the tracker promptly.
        ScheduleSync()

    elseif event == "QUEST_LOG_UPDATE" then
        ScheduleSync()
    end
end)

-- ── Slash commands ────────────────────────────────────────────────
-- POLICY — output channel. User-facing messages go through VUI.Print, which tags them
-- [Zone Quests]. The diagnostic commands (synctest, dumpquest, debug) deliberately use
-- raw print: they are multi-line dumps with their own inline colouring, and a per-line
-- module tag would be noise in output whose purpose is to be copy-pasted. This split is
-- intentional, not drift — do not "unify" it. The one other bare print, in the header,
-- fires only when VUI itself is nil and therefore cannot use VUI.Print at all.
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
        -- A manual refresh should judge against fresh map data, not the
        -- cache — previously even /zq refresh couldn't rescue a quest the
        -- stale set had dropped.
        cachedQuestSet = nil
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
        local ok0, bestMap = pcall(C_Map.GetBestMapForUnit, "player")
        if ok0 and bestMap then
            local mi = C_Map.GetMapInfo(bestMap)
            print("  Best map: " .. bestMap .. " (" .. (mi and mi.name or "?") .. ")")
        end
        local qs = BuildZoneQuestSet()
        local qn = 0
        for _ in pairs(qs) do qn = qn + 1 end
        print("  Zone quest set: " .. qn .. " quest(s)")
        -- Per-quest dispositions deliberately live in /zq synctest, not here. This
        -- loop used to recompute them, and the copy had already drifted from
        -- SyncTracking in three ways at once: it had no super-tracked branch, so a
        -- quest kept solely by super-tracking was reported as dropped while it was in
        -- fact tracked; it tested zone before pin, inverting the precedence the real
        -- code uses for its label; and it built a fresh quest set, bypassing the cache
        -- the live tracker reads. /zq synctest calls SyncTracking in verbose mode, so
        -- its per-quest ADD/REMOVE lines come from the code that actually decides. Do
        -- not restore the loop by adding the missing super-tracked branch - that keeps
        -- the second copy alive and guarantees the next drift.
        print("  Per-quest dispositions: run |cFFFFFF00/zq synctest|r")
        print("  WatchType: " .. tostring(GetWatchType()))
        print("  db.enabled: " .. tostring(db and db.enabled))

    else
        if settingsCategoryID then
            Settings.OpenToCategory(settingsCategoryID)
        else
            VUI.Print("Zone Quests", "Settings not ready yet.")
        end
    end
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_ZoneQuests_OnAddonCompartmentClick()
    if settingsCategoryID then
        C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
    end
end
