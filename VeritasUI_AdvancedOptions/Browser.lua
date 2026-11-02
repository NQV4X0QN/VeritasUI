-- VeritasUI_AdvancedOptions / Browser.lua
-- Full CVar browser: searchable, sortable list with inline editing.
--
-- Uses Blizzard's ScrollBox + MinimalScrollBar for native virtual
-- scrolling — same system as Talents, Professions, Housing.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local ipairs         = ipairs
local pcall          = pcall
local strlower       = string.lower
local strfind        = string.find
local format         = string.format
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local GameTooltip    = GameTooltip
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
--  CVar cache — populated once, reused across sessions
----------------------------------------------------------------
local cvarList       = nil   -- sorted array of { name=, value=, default=, locked= }
-- ⚠ Keyed by the LOWER-CASED name (audit O1): CVar names are not case-sensitive, and the lists
-- that feed this index spell some differently (KNOWN_CVARS "StatusTextDisplay", ElvUI's
-- "statusTextDisplay"), which gave one setting two rows.
local cvarByName     = {}    -- [strlower(name)] → entry ref
local filteredList   = {}    -- current search-filtered view

----------------------------------------------------------------
--  Enumeration strategies
--
--  1. C_Console.GetAllCommands()   — modern namespace (if it exists)
--  2. ConsoleGetAllCommands()      — legacy global (pre-namespace)
--  3. Probe a curated master list  — fallback for Midnight builds
--     where neither API is exposed to addon code
--
--  Strategy 3 iterates a comprehensive list of known CVar names
--  and probes each with C_CVar.GetCVarInfo.  Any name that returns
--  a non-nil value is a real CVar on this client.  This list is
--  intentionally broad — dead names are silently skipped.
----------------------------------------------------------------

-- Master list of known CVars to probe when no enumeration API is
-- available.  Sorted alphabetically for human readability.
--
-- POLICY (formalized v1.6.41 per audit OQ#2): KNOWN_CVARS is
-- intentionally broad.  Dead names — CVars that existed in earlier
-- builds but have been removed in Midnight or any subsequent patch
-- cycle — are silently skipped at runtime: the Strategy 3 probe loop
-- below calls C_CVar.GetCVarInfo for each name and builds a row only
-- when it returns a non-nil value.  Entries are NOT pruned on Midnight
-- removals.
--
-- (That pointer names the loop rather than citing a line number on
-- purpose.  The number drifted three times — v1.6.41 wrote "225",
-- v1.7.13 corrected it, and it was wrong again by v1.9.8.  Do not
-- re-add one.)
--
-- Rationale: removing a name from this list risks accidentally
-- removing a CVar that does exist on this client.  The cost of
-- keeping a dead name is one wasted probe per /reload (negligible);
-- the cost of removing a live name is a CVar that silently drops
-- out of the All CVars tab and becomes invisible to the user.
--
-- Therefore: extend freely; do not prune.  Apparent stale entries
-- are policy, not drift.
local KNOWN_CVARS = {
    -- Action Bars
    "ActionButtonUseKeyDown", "alwaysShowActionBars", "countdownForCooldowns",
    "lockActionBars",
    -- Accessibility
    "colorblindMode", "colorblindSimulator", "enableMovePad",
    "movieSubtitle", "reducedMotion", "screenEdgeFlash",
    "speechToText", "textToSpeech",
    -- Camera
    "cameraBobbing", "cameraDistanceMaxZoomFactor",
    "cameraPitchMoveSpeed", "cameraReduceUnexpectedMovement",
    "cameraSmoothStyle", "cameraWaterCollision", "cameraYawMoveSpeed",
    -- Chat
    "chatBubbles", "chatBubblesParty", "chatClassColorOverride",
    "chatMouseScroll", "chatStyle", "guildMemberNotify",
    "profanityFilter", "removeChatDelay", "showTimestamps",
    "whisperMode",
    -- Combat
    "autoSelfCast", "enableFloatingCombatText", "SpellQueueWindow",
    "floatingCombatTextAllSpellMechanics", "floatingCombatTextAuras",
    "floatingCombatTextCombatDamage", "floatingCombatTextCombatDamageAllAutos",
    "floatingCombatTextCombatDamageDirectionalOffset",
    "floatingCombatTextCombatDamageDirectionalScale",
    "floatingCombatTextCombatHealing", "floatingCombatTextCombatHealingAbsorbSelf",
    "floatingCombatTextCombatHealingAbsorbTarget",
    "floatingCombatTextCombatLogPeriodicSpells",
    "floatingCombatTextCombatState", "floatingCombatTextComboPoints",
    "floatingCombatTextDamageReduction", "floatingCombatTextDodgeParryMiss",
    "floatingCombatTextEnergyGains", "floatingCombatTextFriendlyHealers",
    "floatingCombatTextHonorGains", "floatingCombatTextLowManaHealth",
    "floatingCombatTextPeriodicEnergyGains", "floatingCombatTextPetMeleeDamage",
    "floatingCombatTextPetSpellDamage", "floatingCombatTextReactives",
    "floatingCombatTextRepChanges", "floatingCombatTextSpellMechanics",
    "floatingCombatTextSpellMechanicsOther",
    "floatingCombatTextFloatMode",
    "WorldTextScale", "WorldTextMinSize", "WorldTextCritSize",
    -- Display / Graphics
    "desktopGamma", "ffxDeath", "ffxGlow", "ffxNether",
    "gamma", "graphicsQuality",
    "MSAAQuality", "multiSampleFormats", "RAIDgraphicsQuality",
    "RAIDsettingsEnabled", "renderScale", "resampleQuality",
    "screenshotFormat", "screenshotQuality",
    "shadowMode", "shadowTextureSize", "sunShafts",
    "weatherDensity",
    -- Map / Minimap
    "miniWorldMap", "rotateMinimap",
    -- Mouse / Input
    "autoInteract", "autoLootDefault", "deselectOnClick",
    "enableWoWMouse", "interactOnLeftClick", "invertMouse",
    "lootUnderMouse", "mouseInvertPitch", "mouseSpeed",
    "rawMouseEnable",
    -- Nameplates
    "nameplateClassResourceTopInset", "nameplateLargeBottomInset",
    "nameplateLargeTopInset", "nameplateLargerScale",
    "nameplateMaxAlpha", "nameplateMaxAlphaDistance",
    "nameplateMaxDistance", "nameplateMaxScale", "nameplateMaxScaleDistance",
    "nameplateMinAlpha", "nameplateMinAlphaDistance",
    "nameplateMinScale", "nameplateMinScaleDistance",
    "nameplateMotion", "nameplateMotionSpeed",
    "nameplateOccludedAlphaMult", "nameplateOtherBottomInset",
    "nameplateOtherTopInset", "nameplateOverlapH", "nameplateOverlapV",
    "nameplatePersonalHideDelayAlpha", "nameplatePersonalHideDelaySeconds",
    "nameplatePersonalShowAlways", "nameplatePersonalShowInCombat",
    "nameplatePersonalShowWithTarget",
    "nameplateSelectedAlpha", "nameplateSelectedScale",
    "nameplateSelfAlpha", "nameplateSelfBottomInset", "nameplateSelfTopInset",
    "nameplateShowAll", "nameplateShowDebuffsOnFriendly",
    "nameplateShowEnemies", "nameplateShowEnemyGuardians",
    "nameplateShowEnemyMinions", "nameplateShowEnemyMinus",
    "nameplateShowEnemyPets", "nameplateShowEnemyTotems",
    "nameplateShowFriendlyGuardians", "nameplateShowFriendlyMinions",
    "nameplateShowFriendlyNPCs", "nameplateShowFriendlyPets",
    "nameplateShowFriendlyTotems", "nameplateShowFriends",
    "nameplateTargetBehindMaxDistance",
    -- Network
    "disableServerNagle", "lerpFrameRate", "maxFPS", "maxFPSBk",
    "useIPv6",
    -- Sound
    "Sound_EnableAllSound", "Sound_EnableAmbience", "Sound_EnableDialogue",
    "Sound_EnableEmoteSounds", "Sound_EnableErrorSpeech",
    "Sound_EnableMusic", "Sound_EnablePetSounds", "Sound_EnableSFX",
    "Sound_MasterVolume", "Sound_MusicVolume", "Sound_SFXVolume",
    "Sound_AmbienceVolume", "Sound_DialogVolume",
    -- Soft Targeting
    "SoftTargetEnemy", "SoftTargetEnemyArc", "SoftTargetEnemyRange",
    "SoftTargetForce", "SoftTargetFriend", "SoftTargetFriendArc",
    "SoftTargetFriendRange", "SoftTargetIconEnemy", "SoftTargetIconFriend",
    "SoftTargetInteract", "SoftTargetInteractArc", "SoftTargetInteractRange",
    "SoftTargetMatchLocked", "SoftTargetNameplateEnemy",
    "SoftTargetNameplateFriend", "SoftTargetNameplateInteract",
    "SoftTargetTooltipEnemy", "SoftTargetTooltipFriend",
    "SoftTargetTooltipInteract",
    -- Tooltips / UI
    "alwaysCompareItems", "autoQuestProgress", "autoQuestWatch",
    "displayFreeBagSlots", "doNotFlashLowHealthWarning",
    "empowerTapControls", "findYourselfMode",
    "instantQuestText", "lootLeftmostBin",
    "missingTransmogrifySourceInItemTooltips",
    "OutlineEngineMode",
    "predictedHealth", "scriptErrors",
    "showInGameNavigation", "showNPETutorials", "showTargetOfTarget",
    "showToastWindow", "showTutorials",
    "StatusText", "StatusTextDisplay", "threatShowNumeric",
    "UberTooltips", "uiScale", "useUiScale",
    "XPBarText",
}

local function EnumerateCVars()
    if cvarList then return end
    cvarList = {}
    cvarByName = {}

    local allCmds
    local enumSource = "probe"

    -- Strategy 1: C_Console.GetAllCommands (modern namespace)
    if C_Console and C_Console.GetAllCommands then
        local ok, result = pcall(C_Console.GetAllCommands)
        if ok and result then allCmds = result; enumSource = "C_Console" end
    end

    -- Strategy 2: ConsoleGetAllCommands (legacy global)
    if not allCmds and ConsoleGetAllCommands then
        local ok, result = pcall(ConsoleGetAllCommands)
        if ok and result then allCmds = result; enumSource = "ConsoleGetAll" end
    end

    if allCmds then
        -- Parse the enumeration result
        local cvarType = (Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar)
        for _, cmd in ipairs(allCmds) do
            local isCvar = false
            if cvarType and cmd.commandType == cvarType then
                isCvar = true
            elseif cmd.commandType == 0 then
                isCvar = true
            end
            if isCvar then
                local name = cmd.command
                if name and name ~= "" then
                    local val, def, server, locked = AO:GetCVarInfo(name)
                    local entry = {
                        name    = name,
                        value   = val or "",
                        default = def or "",
                        locked  = locked or false,
                        server  = server or false,
                        help    = cmd.help or "",
                    }
                    cvarList[#cvarList + 1] = entry
                    cvarByName[strlower(name)] = entry
                end
            end
        end
    else
        -- Strategy 3: probe known CVars by name
        for _, name in ipairs(KNOWN_CVARS) do
            if not cvarByName[strlower(name)] then
                local val, def, server, locked = AO:GetCVarInfo(name)
                if val ~= nil then
                    local entry = {
                        name    = name,
                        value   = val,
                        default = def or "",
                        locked  = locked or false,
                        server  = server or false,
                        help    = "",
                    }
                    cvarList[#cvarList + 1] = entry
                    cvarByName[strlower(name)] = entry
                end
            end
        end
    end

    -- Ensure every CVar in the Featured tab, and every CVar ElvUI or EllesmereUI sets
    -- (ElvUIChanges.lua, EllesmereUIChanges.lua), is also present in the browser, regardless of
    -- which enumeration strategy fired. All load before Browser.lua, so the lists are populated.
    local extra = {}
    for _, cat in ipairs(AO.FEATURED_CATEGORIES) do
        for _, ctrl in ipairs(cat.controls) do
            extra[#extra + 1] = ctrl.cvar
            for _, opt in ipairs(ctrl.type == "multiselect" and ctrl.options or {}) do
                extra[#extra + 1] = opt.cvar
            end
        end
    end
    for _, name in ipairs(AO.ELVUI_CVARS or {}) do extra[#extra + 1] = name end
    for _, name in ipairs(AO.ELLESMEREUI_CVARS or {}) do extra[#extra + 1] = name end
    do
        for _, name in ipairs(extra) do
            if name and not cvarByName[strlower(name)] then
                local val, def, server, locked = AO:GetCVarInfo(name)
                if val ~= nil then
                    local entry = {
                        name    = name,
                        value   = val,
                        default = def or "",
                        locked  = locked or false,
                        server  = server or false,
                        help    = "",
                    }
                    cvarList[#cvarList + 1] = entry
                    cvarByName[strlower(name)] = entry
                end
            end
        end
    end

    -- Sort alphabetically
    table.sort(cvarList, function(a, b) return strlower(a.name) < strlower(b.name) end)

    VUI.Print("Advanced Options",
        format("Browser: %d CVars indexed (via %s).", #cvarList, enumSource))
end

local function RefreshEntry(entry)
    if not entry then return end
    local val, def, server, locked = AO:GetCVarInfo(entry.name)
    entry.value   = val or ""
    entry.default = def or ""
    entry.locked  = locked or false
    entry.server  = server or false
end

-- Paint the Value column from the entry: blue when the CVar differs from its
-- default, grey when it matches. Every site that updates a row's value in place
-- must go through this. The right-click reset path used to hardcode the grey,
-- which asserted "this is the default" even when the write had been deferred
-- (combat) or rejected, leaving the live value still modified on screen.
--
-- shownValue overrides entry.value for the comparison, for the one caller that
-- displays a pending value the live CVar has not caught up to yet.
local function PaintValue(fs, entry, shownValue)
    if (shownValue or entry.value) ~= entry.default then
        fs:SetTextColor(0.4, 0.8, 1)
    else
        fs:SetTextColor(0.75, 0.75, 0.75)
    end
end

----------------------------------------------------------------
--  Search / filter
----------------------------------------------------------------
-- elvuiOnly: the "Changed by ElvUI" checkbox -- only CVars ElvUI sets that currently differ from
-- Blizzard's default. Values are re-read first so a row reset a moment ago drops out.
-- changedOnly: the "Changed" checkbox -- every indexed CVar that differs from its default, whoever
-- changed it. The two are exclusive (the checkbox handlers clear each other).
local elvuiOnly = false
local changedOnly = false

local function ApplyFilter(searchText)
    filteredList = {}
    if not cvarList then return end

    local query = strlower(searchText or "")
    local favs, nonFavs = {}, {}

    for _, entry in ipairs(cvarList) do
        local match = (query == "") or strfind(strlower(entry.name), query, 1, true)
        if match and elvuiOnly then
            if AO:IsElvUICVar(entry.name) then
                RefreshEntry(entry)
                match = entry.value ~= entry.default
            else
                match = false
            end
        elseif match and changedOnly then
            RefreshEntry(entry)
            match = entry.value ~= entry.default
        end
        if match then
            if AO:IsFavorite(entry.name) then
                favs[#favs + 1] = entry
            else
                nonFavs[#nonFavs + 1] = entry
            end
        end
    end

    -- Favourites first, then alphabetical
    for _, e in ipairs(favs)    do filteredList[#filteredList + 1] = e end
    for _, e in ipairs(nonFavs) do filteredList[#filteredList + 1] = e end
end

-- "Changed" Reset All: resets exactly the rows on screen, so the search box decides the scope --
-- searching "nameplate" first resets only nameplate settings. The names are taken when the button
-- is clicked and held here until the confirm popup is accepted.
local pendingReset

local function ShownChangedNames()
    local names = {}
    for _, e in ipairs(filteredList) do
        if e.value ~= e.default then names[#names + 1] = e.name end
    end
    return names
end

function AO:ResetCVarList(names)
    names = names or {}
    for _, name in ipairs(names) do AO:ResetCVar(name) end
    VUI.Print("Advanced Options", format("Reset %d setting%s to Blizzard's defaults.",
        #names, #names == 1 and "" or "s"))
    if AO.RefreshBrowser then AO:RefreshBrowser() end
end

StaticPopupDialogs["VERITASUI_AO_RESET_SHOWN"] = {
    text = "Reset the %d setting%s listed to Blizzard's defaults?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function()
        local names = pendingReset
        pendingReset = nil
        AO:ResetCVarList(names)
    end,
    OnCancel = function() pendingReset = nil end,
}

-- "Reset Everything": the console's own cvar_default, every CVar on the client, not just the ones
-- this browser indexes. Keybindings, Edit Mode layouts, chat windows and addon settings are not
-- CVars and are untouched. Refused in combat rather than queued: nothing about it should land
-- mid-fight.
--
-- ⚠ THE PLAYER SENDS IT (audit O3, v1.35.7). Until then this ran ConsoleExec("cvar_default") from
-- addon code. On 2026-10-30 that reset part of the list (nameplates went back live), then raised
-- an error that stopped it -- "The reset didn't run" -- and the owner had to type /console
-- cvar_default to finish. The error text was thrown away, so why is unknown. Now the chat box opens
-- with the command typed in and the player presses Enter: exactly the command he measured working.
-- Do NOT go back to ConsoleExec without capturing that error first.
--
-- After it is sent, counts the indexed CVars still away from default and says so once the CVar
-- changes stop (CVAR_UPDATE, debounced) -- the only way to see what cvar_default actually did
-- without opening the console. Gives up after two minutes if the command is never sent.
local RESET_COMMAND = "/console cvar_default"
local resetWatch, resetSettle, resetGiveUp

function AO:ReportAfterResetEverything()
    local left = 0
    for _, e in ipairs(cvarList or {}) do
        RefreshEntry(e)
        if e.value ~= e.default then left = left + 1 end
    end
    if left == 0 then
        VUI.Print("Advanced Options", "Every setting is back at Blizzard's default.")
    else
        VUI.Print("Advanced Options", format("Reset everything. %d setting%s listed here still differ%s "
            .. "from Blizzard's default: |cFFFFFF00/ao changed|r", left, left == 1 and "" or "s",
            left == 1 and "s" or ""))
    end
    if AO.RefreshBrowser then AO:RefreshBrowser() end
end

local function StopResetWatch()
    if resetWatch then resetWatch:UnregisterAllEvents() end
    if resetSettle then resetSettle:Cancel(); resetSettle = nil end
    if resetGiveUp then resetGiveUp:Cancel(); resetGiveUp = nil end
end

local function WatchForReset()
    if not resetWatch then
        resetWatch = CreateFrame("Frame")
        resetWatch:SetScript("OnEvent", function()
            if resetSettle then resetSettle:Cancel() end
            resetSettle = C_Timer.NewTimer(1, function()
                resetSettle = nil
                StopResetWatch()
                AO:ReportAfterResetEverything()
            end)
        end)
    end
    StopResetWatch()
    resetWatch:RegisterEvent("CVAR_UPDATE")
    resetGiveUp = C_Timer.NewTimer(120, function() resetGiveUp = nil; StopResetWatch() end)
end

function AO:ResetEverything()
    if InCombatLockdown() then
        VUI.Print("Advanced Options", "|cFFFF4444Can't reset everything during combat.|r Try again afterwards.")
        return false
    end
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
    if type(open) ~= "function" or not pcall(open, RESET_COMMAND) then
        VUI.Print("Advanced Options", "Type |cFFFFFF00" .. RESET_COMMAND .. "|r in chat to reset everything.")
        return false
    end
    WatchForReset()
    return true
end

StaticPopupDialogs["VERITASUI_AO_RESET_EVERYTHING"] = {
    text = "Reset EVERY game setting to Blizzard's defaults?\n\nThis includes your graphics, sound, "
        .. "interface and controls options, not just the ones listed here. Keybindings, Edit Mode "
        .. "layouts and addon settings are not affected.\n\nThe chat box opens with "
        .. RESET_COMMAND .. " typed in: press Enter to run it.",
    button1 = "Reset Everything",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
    OnAccept = function() AO:ResetEverything() end,
}

----------------------------------------------------------------
--  Browser UI — Blizzard ScrollBox + MinimalScrollBar
--
--  Layout:
--    Search box at top
--    Column headers (★ | Name | Value | Default)
--    Native ScrollBox list of rows
--    Left-click row  → inline edit box positioned over the Value column
--                      (Enter applies, Esc cancels, left-click again closes)
--    Right-click row → reset that CVar to its default
--
--  There are no Set or Reset buttons, and rows never expand.  v1.6.23/24
--  deleted the overlay editor panel and EXPAND_H entirely; that pattern is
--  on the do-not-reintroduce list.
----------------------------------------------------------------
local ROW_H       = 20

-- Column widths, shared by the header fontstrings and the row fontstrings. Their
-- alignment is load-bearing and stated as such where the header is built ("Right edge
-- matches the scrollBox so columns align with data rows"), but until now each width
-- was written twice, once per set, with nothing keeping the pairs equal. Collapsed for
-- the same reason v1.6.26 collapsed the control heights.
local COL_NAME_W  = 200
local COL_VAL_W   = 100
local COL_DEF_W   = 100

-- buttonBar: the window, whose ButtonFrameTemplate bottom bar holds the Reset buttons (Settings.lua).
function AO:BuildBrowserContent(parent, buttonBar)
    local INSET = 8

    -- ── Search Box ──────────────────────────────────────────
    local SB_INSET = AO.SB_INSET   -- shared with Featured tab for visual alignment

    local searchBox = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    searchBox:SetHeight(22)
    searchBox:SetPoint("TOPLEFT",  parent, "TOPLEFT",  INSET, -INSET)

    -- "Changed by ElvUI" filter, offered once ElvUI has run on this character (ElvUIChanges.lua).
    -- Sits to the right of the search box, which then ends at its left edge. Built always and shown
    -- per refresh (LayoutTop), so it does not depend on which login handler ran first.
    local elvuiCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    elvuiCheck:SetSize(24, 24)
    local elvuiLabel = elvuiCheck.Text or elvuiCheck.text
    if elvuiLabel then elvuiLabel:SetText("Changed by ElvUI") end
    local elvuiTextW = (elvuiLabel and tonumber(elvuiLabel:GetStringWidth())) or 100
    elvuiCheck:SetPoint("RIGHT", parent, "TOPRIGHT", -INSET - elvuiTextW - 4, -INSET - 11)
    elvuiCheck:Hide()

    -- "Changed" filter: always offered. Sits left of the ElvUI checkbox when that is shown,
    -- otherwise at the right edge; the search box ends at its left edge.
    local changedCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    changedCheck:SetSize(24, 24)
    local changedLabel = changedCheck.Text or changedCheck.text
    if changedLabel then changedLabel:SetText("Changed") end
    local changedTextW = (changedLabel and tonumber(changedLabel:GetStringWidth())) or 60

    local function LayoutTop()
        local offer = AO.elvuiRelevant and true or false
        elvuiCheck:SetShown(offer)
        changedCheck:ClearAllPoints()
        if offer then
            changedCheck:SetPoint("RIGHT", elvuiCheck, "LEFT", -changedTextW - 12, 0)
        else
            changedCheck:SetPoint("RIGHT", parent, "TOPRIGHT", -INSET - changedTextW - 4, -INSET - 11)
        end
        searchBox:SetPoint("RIGHT", changedCheck, "LEFT", -10, 0)
    end
    LayoutTop()
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Search CVars...")
    end

    -- ── Column headers ──────────────────────────────────────
    -- Right edge matches the scrollBox so columns align with data rows.
    local headerFrame = CreateFrame("Frame", nil, parent)
    headerFrame:SetHeight(16)
    headerFrame:SetPoint("TOPLEFT",  searchBox,  "BOTTOMLEFT",  0, -6)
    headerFrame:SetPoint("RIGHT",    parent,     "RIGHT",       -SB_INSET, 0)

    local hdrStar = CreateFrame("Frame", nil, headerFrame)
    hdrStar:SetSize(20, 16)
    hdrStar:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
    local hdrStarIcon = hdrStar:CreateTexture(nil, "OVERLAY")
    hdrStarIcon:SetSize(12, 12)
    hdrStarIcon:SetPoint("CENTER")
    hdrStarIcon:SetAtlas("auctionhouse-icon-favorite")
    hdrStarIcon:SetVertexColor(0.5, 0.5, 0.5)

    local hdrName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrName:SetPoint("LEFT", hdrStar, "RIGHT", 4, 0)
    hdrName:SetWidth(COL_NAME_W)
    hdrName:SetJustifyH("LEFT")
    hdrName:SetText("CVar")
    hdrName:SetTextColor(1, 0.82, 0)

    local hdrValue = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrValue:SetPoint("LEFT", hdrName, "RIGHT", 4, 0)
    hdrValue:SetWidth(COL_VAL_W)
    hdrValue:SetJustifyH("LEFT")
    hdrValue:SetText("Value")
    hdrValue:SetTextColor(1, 0.82, 0)

    local hdrDefault = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrDefault:SetPoint("LEFT", hdrValue, "RIGHT", 4, 0)
    hdrDefault:SetWidth(COL_DEF_W)
    hdrDefault:SetJustifyH("LEFT")
    hdrDefault:SetText("Default")
    hdrDefault:SetTextColor(1, 0.82, 0)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  headerFrame, "BOTTOMLEFT",  0, -2)
    divider:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -2)
    divider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

    -- ── ScrollBox + MinimalScrollBar ────────────────────────
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT",     divider,  "BOTTOMLEFT",  0, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", -SB_INSET, 4)

    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",    scrollBox, "TOPRIGHT",    4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    -- ── Filter footer ("Changed by ElvUI" / "Changed"): explanation + Reset All ───
    local FOOTER_H = 58
    local FOOTER_CHANGED_H = 70   -- the "Changed" explanation runs a line longer
    local footer, footerText, resetAllBtn, resetEverythingBtn
    do
        footer = CreateFrame("Frame", nil, parent)
        footer:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  INSET, 4)
        footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -INSET, 4)
        footer:SetHeight(FOOTER_H)
        footer:Hide()

        -- Both Reset buttons sit in the window's bottom bar, bottom right, where the Featured tab's
        -- Collapse All sits (owner, 2026-10-30): ButtonFrameTemplate's corner offset -6,4
        -- (MagicButton_OnLoad, SharedUIPanelTemplates.lua:36-39). Parented to this tab, so they
        -- show with it only; UpdateFooter shows them only while a filter is on.
        local bar = buttonBar or footer
        local barX, barY = buttonBar and -6 or 0, buttonBar and 4 or 2
        resetAllBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        resetAllBtn:SetSize(150, 22)
        resetAllBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", barX, barY)
        resetAllBtn:SetText("Reset All to Default")
        resetAllBtn:SetScript("OnClick", function()
            if changedOnly then
                local names = ShownChangedNames()
                local n = #names
                if n > 0 then
                    pendingReset = names
                    StaticPopup_Show("VERITASUI_AO_RESET_SHOWN", n, n == 1 and "" or "s")
                end
                return
            end
            local n = #AO:ElvUIChangedCVars()
            if n > 0 then StaticPopup_Show("VERITASUI_AO_RESET_ELVUI", n, n == 1 and "" or "s") end
        end)

        -- "Changed" mode with nothing searched: the console's cvar_default. It takes Reset All's
        -- place rather than sitting beside it, so the footer only ever offers one reset: everything
        -- (no search) or exactly the rows a search left (Reset All). Owner's design, 2026-10-29.
        resetEverythingBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        resetEverythingBtn:SetSize(150, 22)
        resetEverythingBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", barX, barY)
        resetEverythingBtn:SetText("Reset Everything")
        resetEverythingBtn:SetScript("OnClick", function()
            StaticPopup_Show("VERITASUI_AO_RESET_EVERYTHING")
        end)
        resetEverythingBtn:Hide()
        resetAllBtn:Hide()

        footerText = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        footerText:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -2)
        if buttonBar then
            -- Width only, no bottom anchor: the text keeps its natural height, which UpdateFooter
            -- reads to size the footer. A bottom anchor would clip it to the old height.
            footerText:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -2)
        else
            footerText:SetPoint("BOTTOMRIGHT", resetAllBtn, "BOTTOMLEFT", -10, 0)
        end
        footerText:SetJustifyH("LEFT")
        footerText:SetJustifyV("TOP")
        footerText:SetWordWrap(true)
    end

    -- Blizzard's own chat reset: chat tab menu > Settings (CHAT_CONFIGURATION, FloatingChatFrame.lua
    -- :504-505) > Chat Defaults (CHAT_DEFAULTS, ChatConfigFrame.xml:1506), which asks before resetting.
    local CHAT_HINT = format("Chat windows: right-click a chat tab, choose %s, then %s.",
        CHAT_CONFIGURATION or "Settings", CHAT_DEFAULTS or "Chat Defaults")

    -- UI suites known to write CVars again when they load (ElvUIChanges.lua, EllesmereUIChanges.lua).
    local REWRITERS = { "ElvUI", "EllesmereUI" }
    local function RunningRewriter()
        if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return nil end
        for _, name in ipairs(REWRITERS) do
            if C_AddOns.IsAddOnLoaded(name) then return name end
        end
        return nil
    end

    local function UpdateFooter(shown)
        local on = elvuiOnly or changedOnly
        footer:SetShown(on)
        -- Changed mode, nothing searched: Reset Everything (shown even when the list is empty -- it
        -- reaches CVars this list can't). Anything searched, or the ElvUI filter: Reset All.
        local searched = strtrim(searchBox:GetText() or "") ~= ""
        local everything = changedOnly and not searched
        resetEverythingBtn:SetShown(on and everything)
        resetAllBtn:SetShown(on and not everything)
        if not on then
            scrollBox:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SB_INSET, 4)
            return
        end
        local lead
        if changedOnly then
            local running = RunningRewriter()
            if running then
                lead = format("|cFFFF4444%s is running|r and may set some of these again when it loads. "
                    .. "Turn it off in the AddOns list before resetting.", running)
            elseif everything then
                lead = (shown == 0 and "Every setting listed here is at Blizzard's default. "
                        or "These differ from Blizzard's defaults, including changes you made yourself. ")
                    .. "Reset Everything resets every game setting, listed or not. Search to reset only some."
            elseif shown == 0 then
                lead = "Every setting listed here is at Blizzard's default."
            else
                lead = "These differ from Blizzard's defaults, including changes you made yourself. "
                    .. "Reset All to Default resets only the rows listed."
            end
        elseif AO.ElvUILoaded() then
            lead = "|cFFFF4444ElvUI is running|r and sets its nameplate settings again at every login. "
                .. "Turn it off in the AddOns list before resetting."
        elseif shown == 0 then
            lead = "Everything ElvUI changed is back at Blizzard's defaults."
        else
            lead = "These settings differ from Blizzard's defaults. Right-click a row to reset just that one."
        end
        footerText:SetText(lead .. "\n" .. CHAT_HINT)
        -- The footer is as tall as its text (owner, 2026-10-30: it left a blank band under the text
        -- once the Reset buttons moved to the bottom bar). The fixed heights are the fallback for a
        -- text height the client cannot give yet.
        local textH = tonumber(footerText:GetStringHeight()) or 0
        local h = (textH > 0) and (math.ceil(textH) + 6) or (changedOnly and FOOTER_CHANGED_H or FOOTER_H)
        footer:SetHeight(h)
        scrollBox:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SB_INSET, h + 8)
        resetAllBtn:SetEnabled(shown > 0)
    end

    -- ── Inline edit state ────────────────────────────────────
    local editingRow = nil   -- the row frame currently being edited

    -- Shared inline EditBox — positioned over a row's value fontstring.
    local inlineEdit = CreateFrame("EditBox", nil, scrollBox, "InputBoxTemplate")
    inlineEdit:SetHeight(ROW_H - 2)
    inlineEdit:SetAutoFocus(false)
    inlineEdit:Hide()

    local function CloseInlineEdit()
        if editingRow and editingRow._valFs then
            editingRow._valFs:Show()
        end
        editingRow = nil
        inlineEdit:ClearFocus()
        inlineEdit:Hide()
    end

    local function OpenInlineEdit(row, entry)
        -- Close any previous edit
        if editingRow and editingRow ~= row then CloseInlineEdit() end
        editingRow = row
        -- Position over the value fontstring
        row._valFs:Hide()
        inlineEdit:SetParent(row)
        inlineEdit:ClearAllPoints()
        inlineEdit:SetPoint("LEFT",  row._valFs, "LEFT",  -4, 0)
        inlineEdit:SetPoint("RIGHT", row._valFs, "RIGHT",  4, 0)
        inlineEdit:SetFrameLevel(row:GetFrameLevel() + 5)
        inlineEdit:SetText(entry.value)
        inlineEdit:Show()
        inlineEdit:SetFocus()
        inlineEdit:HighlightText()
    end

    -- Enter → apply the new value
    inlineEdit:SetScript("OnEnterPressed", function(self)
        if not editingRow then return end
        local entry = editingRow._entry
        if not entry then CloseInlineEdit(); return end
        local typed = self:GetText()
        -- AO:SetCVar returns false both when the write is deferred to the end of
        -- combat and when it genuinely fails, so disambiguate here rather than
        -- changing its contract — same shape as the Featured dropdown. On a
        -- deferred write RefreshEntry re-reads the live CVar, which is still the
        -- old value, and snaps the row back, discarding both the typed text and
        -- the optimistic cache write AO:SetCVar just made. Keep the typed value
        -- on screen instead; the CVar catches up when combat ends.
        -- No message is printed here: AO:SetCVar already reports both the
        -- deferred and the failed case itself.
        if AO:SetCVar(entry.name, typed) or not InCombatLockdown() then
            RefreshEntry(entry)
            editingRow._valFs:SetText(entry.value)
            PaintValue(editingRow._valFs, entry)
        else
            editingRow._valFs:SetText(typed)
            PaintValue(editingRow._valFs, entry, typed)
        end
        CloseInlineEdit()
    end)

    -- Escape → cancel editing
    inlineEdit:SetScript("OnEscapePressed", function()
        CloseInlineEdit()
    end)

    -- ── ScrollBox view + element initializer ────────────────
    -- Each element is a data entry from filteredList. The view
    -- recycles row frames automatically — no manual pool needed.
    local view = CreateScrollBoxListLinearView()

    -- Element extent: fixed height for all rows. The inline editor is
    -- parented to the clicked row and floats over its Value column at a
    -- higher frame level, so the row itself never changes height and no
    -- variable extent is needed.
    view:SetElementExtentCalculator(function(dataIndex, elementData)
        return ROW_H
    end)

    -- Initializer — called when a row frame is acquired from the pool.
    -- Sets up the frame's child regions on first use, then binds data.
    view:SetElementInitializer("Button", function(row, elementData)
        -- ── One-time setup (first acquisition) ──────────────
        if not row._nameFs then
            row:SetHeight(ROW_H)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            row._bg = bg

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.06)

            local star = CreateFrame("Button", nil, row)
            star:SetSize(16, ROW_H)
            star:SetPoint("LEFT", row, "LEFT", 0, 0)
            local starIcon = star:CreateTexture(nil, "OVERLAY")
            starIcon:SetSize(12, 12)
            starIcon:SetPoint("CENTER")
            starIcon:SetAtlas("auctionhouse-icon-favorite")
            row._star     = star
            row._starIcon = starIcon

            local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameFs:SetPoint("LEFT", star, "RIGHT", 4, 0)
            nameFs:SetWidth(COL_NAME_W)
            nameFs:SetJustifyH("LEFT")
            row._nameFs = nameFs

            local valFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valFs:SetPoint("LEFT", nameFs, "RIGHT", 4, 0)
            valFs:SetWidth(COL_VAL_W)
            valFs:SetJustifyH("LEFT")
            row._valFs = valFs

            local defFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            defFs:SetPoint("LEFT", valFs, "RIGHT", 4, 0)
            defFs:SetWidth(COL_DEF_W)
            defFs:SetJustifyH("LEFT")
            defFs:SetTextColor(0.5, 0.5, 0.5)
            row._defFs = defFs

            -- ── Row click handlers — wired ONCE per pool frame ──
            --
            -- v1.6.7's design, restated: handlers are wired at pool creation and
            -- read the row's data through the stable row._entry backref, so
            -- scrolling does not re-register clicks or allocate fresh closures
            -- per bind. These five lines had drifted into the data-bind section
            -- below (most likely during v1.6.18's initializer rewrite), which
            -- cost four closures and five calls on every row rebind.
            --
            -- ⚠ Nothing in here may capture elementData: this block runs once,
            -- while the frame is reused for a different CVar on every scroll
            -- step. Read self._entry at event time instead. A captured
            -- elementData binds the frame to whichever CVar occupied it first,
            -- and fails silently by acting on the wrong CVar.
            star:SetScript("OnClick", function(self)
                local e = self:GetParent()._entry
                if not e then return end
                AO:ToggleFavorite(e.name)
                AO:RefreshBrowser()
            end)

            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, button)
                local e = self._entry
                if not e then return end
                if button == "RightButton" then
                    -- Right-click → reset to default
                    AO:ResetCVar(e.name)
                    RefreshEntry(e)
                    self._valFs:SetText(e.value)
                    PaintValue(self._valFs, e)
                    if editingRow == self then CloseInlineEdit() end
                else
                    -- Left-click → toggle inline edit
                    if editingRow == self then
                        CloseInlineEdit()
                    else
                        OpenInlineEdit(self, e)
                    end
                end
            end)

            row:SetScript("OnEnter", function(self)
                local e = self._entry
                if e and e.help and e.help ~= "" then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(e.name, 1, 1, 1)
                    GameTooltip:AddLine(e.help, 1, 0.82, 0, true)   -- Blizzard's description gold
                    if e.locked then
                        GameTooltip:AddLine("Locked by graphics engine", 1, 0.6, 0)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        -- ── Data bind ───────────────────────────────────────
        row._entry = elementData
        RefreshEntry(elementData)

        row._nameFs:SetText(elementData.name)
        row._valFs:SetText(elementData.value)
        row._defFs:SetText(elementData.default)

        -- Modified indicator
        PaintValue(row._valFs, elementData)

        -- Star colour
        local isFav = AO:IsFavorite(elementData.name)
        row._starIcon:SetVertexColor(isFav and 1 or 0.25,
                                      isFav and 0.82 or 0.25,
                                      isFav and 0 or 0.25)
        row._starIcon:SetDesaturated(not isFav)

        -- Alternating background — driven by the row's position in the current
        -- filtered view, stamped onto the entry by FullRefresh.
        row._bg:SetColorTexture(1, 1, 1, ((elementData.rowIndex or 0) % 2 == 0) and 0.03 or 0)

        -- ── Inline edit: close if this row is recycled while editing ──
        if editingRow == row then
            CloseInlineEdit()
        end
        -- Ensure value fontstring is visible on rebind
        row._valFs:Show()
    end)

    -- ── Wire ScrollBox + ScrollBar ──────────────────────────
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- ── Data provider refresh ───────────────────────────────
    local function FullRefresh()
        EnumerateCVars()
        ApplyFilter(searchBox:GetText() or "")

        local dataProvider = CreateDataProvider()
        for i, entry in ipairs(filteredList) do
            -- Stamp the visible row position for the striping in the initializer.
            -- It must be stamped here, in the same pass that inserts into the
            -- provider, and not in EnumerateCVars: filteredList is rebuilt and
            -- reordered on every search and favourite toggle, so an enumeration-
            -- time index would follow the unfiltered alphabetical order instead
            -- of the view. The ScrollBox cannot supply this — the initializer
            -- signature in use is (row, elementData), with no index.
            entry.rowIndex = i
            dataProvider:Insert(entry)
        end
        scrollBox:SetDataProvider(dataProvider)
        LayoutTop()
        UpdateFooter(#filteredList)
    end

    function AO:RefreshBrowser()
        CloseInlineEdit()
        FullRefresh()
    end

    elvuiCheck:SetScript("OnClick", function(self)
        elvuiOnly = self:GetChecked() and true or false
        if elvuiOnly then changedOnly = false; changedCheck:SetChecked(false) end
        AO:RefreshBrowser()
    end)

    changedCheck:SetScript("OnClick", function(self)
        changedOnly = self:GetChecked() and true or false
        if changedOnly then elvuiOnly = false; elvuiCheck:SetChecked(false) end
        AO:RefreshBrowser()
    end)

    -- /ao changed: the All CVars tab with the "Changed" filter on.
    function AO:ShowChangedCVars()
        changedCheck:SetChecked(true)
        changedOnly = true
        elvuiCheck:SetChecked(false)
        elvuiOnly = false
        if AO.MainWindow then AO.MainWindow:ShowTab("browser") end
        AO:RefreshBrowser()
    end

    -- /ao elvui: the All CVars tab with the filter on.
    function AO:ShowElvUIChanges()
        if not AO.elvuiRelevant then
            VUI.Print("Advanced Options", "ElvUI has not run on this character, so there is nothing to undo.")
            return
        end
        elvuiCheck:SetChecked(true)
        elvuiOnly = true
        changedCheck:SetChecked(false)
        changedOnly = false
        if AO.MainWindow then AO.MainWindow:ShowTab("browser") end
        AO:RefreshBrowser()
    end

    -- ── Debounced search ────────────────────────────────────
    local searchTimer
    searchBox:HookScript("OnTextChanged", function()
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.2, function()
            searchTimer = nil
            CloseInlineEdit()
            FullRefresh()
        end)
    end)

    -- Initial populate deferred to first show
    parent:SetScript("OnShow", function()
        FullRefresh()
    end)

    return scrollBox
end
