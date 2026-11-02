-- VeritasUI_ZoneQuests / ZoneQuests.lua
-- Filters the Objective Tracker to show only quests for your current zone.
-- Special quest types can be pinned so they always show regardless of zone.
--
-- Settings: Options → AddOns → VeritasUI → Zone Quests   |   /zq   |   /zonequests

local ADDON_NAME   = "VeritasUI_ZoneQuests"
local SETTINGS_LABEL = "Zone Quests"
local VUI = _G.VeritasUI
if not VUI then
    print(RED_FONT_COLOR:WrapTextInColorCode("[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled."))
    return
end

-- ── Saved variable defaults ────────────────────────────────────────
-- Saved settings, split by SCOPE. The authority on which key goes where is
-- ~/.agents/skills/veritasui/references/setting-scope-map.md; `scope_map_test` enforces it.
-- Shared by every character: which quest types to keep is about how the player wants the tracker
-- to behave, not about a particular character's progress.
local UNIVERSAL = {
    pinCampaign   = true,
    pinImportant  = true,
    pinLegendary  = true,
    pinMeta       = true,
    pinRepeatable = true,
}

-- ⚠ PER-CHARACTER, and not a preference: `untrackedBeforeFilter` records THIS character's
-- quest log ({ [questID] = true } for quests the player had NOT tracked when filtering was
-- switched on; `false` = no record). Sharing it would apply one character's choices to quests
-- an alt has never picked up. Replaced `manualWatched` in v1.17.12 (audit Z1).
-- ⚠ `enabled` is PER-CHARACTER too (v1.35.6, audit Z1): it must share its record's scope. While it
-- was shared, turning filtering off on one character restored only that character, and every alt
-- it had filtered stayed filtered. Characters first seen after the change take the old shared
-- value (`SeedEnabledFromShared`), so nothing flips on or off at the update.
local PERCHAR = {
    enabled               = true,
    untrackedBeforeFilter = false,
}

local db  = nil  -- ACCOUNT-wide table; assigned at ADDON_LOADED
-- ⚠ Declared HERE, above every function that reads it. `cdb` is the PER-CHARACTER table and is
-- nil until PLAYER_LOGIN. RecordTrackingBeforeFilter/RestoreTracking reference it below this
-- point but are DEFINED above the assignment, so without this declaration the assignment would
-- create a global and those reads would silently resolve to it -- the /way v1.6.33 trap.
local cdb = nil  -- PER-CHARACTER table (enabled, untrackedBeforeFilter); nil until PLAYER_LOGIN

local function Enabled() return cdb ~= nil and cdb.enabled == true end

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
    if not db or not Enabled() then
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

-- ── Remember / restore the player's own tracking (audit Z1, v1.17.12) ──
-- C_QuestLog.GetQuestWatchType(questID) reports whether a quest is watched (nil = not watched;
-- QuestLogDocumentation.lua:555-566). Until v1.17.12 this file claimed Midnight had removed any
-- way to ask, snapshotted EVERY quest at every login, and on "off" tracked that list and
-- UNtracked everything else -- so untracked quests came back and quests picked up since login
-- vanished from the tracker.
--
-- Now the record is taken only at the off -> on moment, and holds just the quests the player
-- had chosen NOT to track. Turning filtering off untracks those and tracks everything else
-- (new quests included, which is what Blizzard does with a freshly accepted quest). No record
-- (filtering was already on before this version) -> track everything, once.
local function RecordTrackingBeforeFilter()
    if not cdb then return end
    local rec = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and not info.isHeader and not info.isHidden and info.questID then
            local okW, watchType = pcall(C_QuestLog.GetQuestWatchType, info.questID)
            if okW and watchType == nil then rec[info.questID] = true end
        end
    end
    cdb.untrackedBeforeFilter = rec
end

local function RestoreTracking()
    if not cdb then return end
    local rec = type(cdb.untrackedBeforeFilter) == "table" and cdb.untrackedBeforeFilter or nil
    local watchType = GetWatchType()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and info and not info.isHeader and not info.isHidden and info.questID then
            if rec and rec[info.questID] then
                pcall(C_QuestLog.RemoveQuestWatch, info.questID)
            else
                pcall(C_QuestLog.AddQuestWatch, info.questID, watchType)
            end
        end
    end
    cdb.untrackedBeforeFilter = false
end

-- One-time fix-up (audit Z1): a character that filtering was turned off for elsewhere, while
-- `enabled` was shared, logs in off but still holding its record and the filtered tracker. Put
-- its own tracking back -- only once the quest log has entries, so an empty log at login cannot
-- use up the record. Also run before a new record is taken, so the filtered state is never
-- recorded as the player's choice.
local restorePending = false
local function FinishPendingRestore()
    if not restorePending or not cdb then return end
    if type(cdb.untrackedBeforeFilter) ~= "table" then restorePending = false; return end
    if C_QuestLog.GetNumQuestLogEntries() == 0 then return end
    restorePending = false
    RestoreTracking()
end

-- Before BindScopedDB seeds this character's `enabled` with the default (at ADDON_LOADED when
-- the identity is already known, else at PLAYER_LOGIN), give a character not
-- seen since `enabled` became per-character (v1.35.6) the value that was shared until then.
-- The shared copy stays on the root as that seed; nothing reads it otherwise.
local function SeedEnabledFromShared()
    local root = _G.VeritasUI_ZoneQuestsDB
    local key = VUI.CharKey()
    if type(root) ~= "table" or type(root.enabled) ~= "boolean" or not key then return end
    if type(root.chars) ~= "table" then root.chars = {} end
    local slot = root.chars[key]
    if type(slot) ~= "table" then slot = {}; root.chars[key] = slot end
    if slot.enabled == nil then slot.enabled = root.enabled end
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
    local category = VUI.RegisterSettingsCategory(SETTINGS_LABEL)

    local enableSetting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_enabled",
        "enabled",
        cdb,                               -- PER-CHARACTER table: `enabled` is per-character
        type(PERCHAR.enabled),
        "Enable Zone Filtering",
        PERCHAR.enabled
    )
    enableSetting:SetValueChangedCallback(function(_, value)
        if value then
            FinishPendingRestore()
            RecordTrackingBeforeFilter()
            SyncTracking(false)
            VUI.Print("Zone Quests", VUI.COL.GREEN .. "On.|r Filtering to " .. VUI.COL.NORMAL .. ZoneName() .. "|r")
        else
            RestoreTracking()
            VUI.Print("Zone Quests", VUI.COL.RED .. "Off.|r Your own quest tracking is back.")
        end
    end)
    Settings.CreateCheckbox(category, enableSetting,
        "Shows only quests for your current zone in the Objective Tracker. Turning it off "
        .. "puts back the tracking you had before. Set for each character.")

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
        -- BindScopedDB seeds this character's slot here already when its identity is known, so
        -- the shared `enabled` must be copied in first (see SeedEnabledFromShared).
        SeedEnabledFromShared()
        db = VUI.BindScopedDB("VeritasUI_ZoneQuestsDB", UNIVERSAL, PERCHAR)
        -- InitializeOptions stays at PLAYER_LOGIN: Settings.RegisterAddOnSetting captures the
        -- table it is handed, and the per-character table (`enabled`) does not exist yet here.
        ef:UnregisterEvent("ADDON_LOADED")
        return
    end

    if not db then return end

    if event == "PLAYER_LOGIN" then
        -- Identity is available: bind BOTH tables. `db` is account-wide (every universal read
        -- below is unchanged); `cdb` is this character's slot: enabled and untrackedBeforeFilter.
        SeedEnabledFromShared()
        db, cdb = VUI.BindScopedDB("VeritasUI_ZoneQuestsDB", UNIVERSAL, PERCHAR)

        -- ⚠ MIGRATION MUST RUN HERE: after the char table exists, and BEFORE anything reads a
        -- universal key. Read first and the feature acts on the pre-migration value for the
        -- whole session. Promotes this character's stored values for the newly-universal keys
        -- and clears the vestigial account-wide copies of per-character keys.
        local promoted = VUI.MigrateScopedDB("VeritasUI_ZoneQuestsDB", UNIVERSAL, PERCHAR,
                                            "__vuiScopeMigrated")
        if promoted then
            local names = {}
            for k in pairs(promoted) do names[#names + 1] = k end
            table.sort(names)
            VUI.Print("Zone Quests", "settings now shared across characters: "
                .. table.concat(names, ", ") .. "  (taken from this character)")
        end

        -- Retire the pre-v1.17.12 login snapshot (audit Z1): it listed every quest, not the
        -- player's choices, so it cannot seed the new record.
        if cdb then cdb.manualWatched = nil end
        db.manualWatched = nil

        InitializeOptions()
        restorePending = not Enabled() and type(cdb and cdb.untrackedBeforeFilter) == "table"
        C_Timer.After(2.0, function()
            -- No snapshot here: the record is taken only when filtering is switched on.
            FinishPendingRestore()
            SyncTracking(false)
            -- Login line removed (suite-wide audit S2): Lib prints the one "VeritasUI vX loaded" line.
        end)

    elseif event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED_INDOORS" then
        -- Always invalidate the cache so the next sync uses fresh zone data.
        cachedQuestSet = nil
        if not Enabled() then return end
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
        if Enabled() then ScheduleSync() end

    elseif event == "SUPER_TRACKING_CHANGED" then
        -- Player set or cleared the minimap direction arrow. Re-sync so the
        -- quest appears/disappears from the tracker promptly.
        ScheduleSync()

    elseif event == "QUEST_LOG_UPDATE" then
        FinishPendingRestore()
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
        if not cdb then VUI.Print("Zone Quests", "Not ready."); return end
        if not cdb.enabled then VUI.Print("Zone Quests", "Already off."); return end
        cdb.enabled = false
        RestoreTracking()
        VUI.Print("Zone Quests", VUI.COL.RED .. "Off.|r  /zq on to re-enable.")

    elseif msg == "on" or msg == "enable" then
        if not cdb then VUI.Print("Zone Quests", "Not ready."); return end
        if cdb.enabled then VUI.Print("Zone Quests", "Already on."); return end
        cdb.enabled = true
        FinishPendingRestore()
        RecordTrackingBeforeFilter()
        SyncTracking(false)
        VUI.Print("Zone Quests", VUI.COL.GREEN .. "On.|r  " .. ZoneName())

    elseif msg == "refresh" then
        if not db then VUI.Print("Zone Quests", "Not ready."); return end
        -- A manual refresh should judge against fresh map data, not the
        -- cache — previously even /zq refresh couldn't rescue a quest the
        -- stale set had dropped.
        cachedQuestSet = nil
        SyncTracking(false)
        VUI.Print("Zone Quests", "Refreshed — " .. ZoneName())

    elseif msg == "synctest" then
        VUI.Print("Zone Quests", VUI.COL.YELLOW .. "Running verbose sync...|r")
        SyncTracking(true)

    elseif msg:sub(1, 9) == "dumpquest" then
        local search = strtrim(msg:sub(10)):lower()
        if search == "" then
            VUI.Print("Zone Quests", "Usage: /zq dumpquest " .. VUI.COL.NORMAL .. "<partial quest name>|r")
            return
        end
        local found = 0
        VUI.Print("Zone Quests", VUI.COL.YELLOW .. "Searching for '|r" .. search .. VUI.COL.YELLOW .. "'...|r")
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and info and not info.isHeader and info.title then
                if info.title:lower():find(search, 1, true) then
                    found = found + 1
                    print(VUI.COL.NORMAL .. "[" .. i .. "] Quest: |r" .. tostring(info.title))
                    local keys = {}
                    for k in pairs(info) do table.insert(keys, k) end
                    table.sort(keys)
                    for _, k in ipairs(keys) do
                        if info[k] ~= nil then
                            print("  " .. VUI.COL.GREEN .. tostring(k) .. "|r = "
                                .. VUI.COL.HIGHLIGHT .. tostring(info[k]) .. "|r")
                        end
                    end
                    if info.questID then
                        local tok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, info.questID)
                        if tok and tagInfo then
                            print("  " .. VUI.COL.LIGHTBLUE .. "--- GetQuestTagInfo ---")
                            local tkeys = {}
                            for k in pairs(tagInfo) do table.insert(tkeys, k) end
                            table.sort(tkeys)
                            for _, k in ipairs(tkeys) do
                                if tagInfo[k] ~= nil then
                                    print("  " .. VUI.COL.LIGHTBLUE .. tostring(k) .. "|r = "
                                        .. VUI.COL.HIGHLIGHT .. tostring(tagInfo[k]) .. "|r")
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
        VUI.Print("Zone Quests", VUI.COL.YELLOW .. "Debug:|r")
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
        print("  Per-quest dispositions: run " .. VUI.COL.YELLOW .. "/zq synctest|r")
        print("  WatchType: " .. tostring(GetWatchType()))
        print("  enabled (this character): " .. tostring(cdb and cdb.enabled))

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
