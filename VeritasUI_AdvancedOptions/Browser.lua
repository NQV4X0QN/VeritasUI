-- VeritasUI_AdvancedOptions / Browser.lua
-- Full CVar browser: searchable, sortable list with inline editing.
--
-- Phase 3 implementation. This file provides the data-layer
-- (enumeration + caching) and the scroll-list UI.

local ADDON_NAME, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G             = _G
local pairs, ipairs  = pairs, ipairs
local pcall          = pcall
local type, tostring = type, tostring
local strlower       = string.lower
local strfind        = string.find
local format         = string.format
local math_max       = math.max
local math_min       = math.min
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local C_CVar         = C_CVar
local GameTooltip    = GameTooltip

----------------------------------------------------------------
--  CVar cache — populated once, reused across sessions
----------------------------------------------------------------
local cvarList       = nil   -- sorted array of { name=, value=, default=, locked= }
local cvarByName     = {}    -- [name] → entry ref
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
-- Extend this list freely — invalid names are harmlessly skipped.
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
                    cvarByName[name] = entry
                end
            end
        end
    else
        -- Strategy 3: probe known CVars by name
        for _, name in ipairs(KNOWN_CVARS) do
            if not cvarByName[name] then
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
                    cvarByName[name] = entry
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

----------------------------------------------------------------
--  Search / filter
----------------------------------------------------------------
local function ApplyFilter(searchText)
    filteredList = {}
    if not cvarList then return end

    local query = strlower(searchText or "")
    local favs, nonFavs = {}, {}

    for _, entry in ipairs(cvarList) do
        local match = (query == "") or strfind(strlower(entry.name), query, 1, true)
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

----------------------------------------------------------------
--  Browser UI
--
--  Layout:
--    Search box at top
--    Column headers (★ | Name | Value | Default)
--    Scrolling list of rows
--    Each row: fav star | cvar name | current value | default
--    Click row → inline expand with edit box + Set + Reset buttons
----------------------------------------------------------------
local ROW_H       = 20
local VISIBLE_ROWS = 22
local EXPAND_H    = 28

local POOL_SIZE = VISIBLE_ROWS + 4   -- enough rows to cover viewport + buffer

function AO:BuildBrowserContent(parent)
    local SCROLLBAR_W = 8
    local INSET       = 8

    -- ── Search Box ──────────────────────────────────────────
    local searchBox = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    searchBox:SetHeight(22)
    searchBox:SetPoint("TOPLEFT",  parent, "TOPLEFT",  INSET, -INSET)
    searchBox:SetPoint("RIGHT",    parent, "RIGHT",   -INSET,  0)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Search CVars...")
    end

    -- ── Column headers ──────────────────────────────────────
    local headerFrame = CreateFrame("Frame", nil, parent)
    headerFrame:SetHeight(16)
    headerFrame:SetPoint("TOPLEFT",  searchBox,  "BOTTOMLEFT",  0, -6)
    headerFrame:SetPoint("RIGHT",    parent,     "RIGHT",       -(INSET + SCROLLBAR_W), 0)

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
    hdrName:SetWidth(200)
    hdrName:SetJustifyH("LEFT")
    hdrName:SetText("CVar")
    hdrName:SetTextColor(1, 0.82, 0)

    local hdrValue = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrValue:SetPoint("LEFT", hdrName, "RIGHT", 4, 0)
    hdrValue:SetWidth(100)
    hdrValue:SetJustifyH("LEFT")
    hdrValue:SetText("Value")
    hdrValue:SetTextColor(1, 0.82, 0)

    local hdrDefault = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrDefault:SetPoint("LEFT", hdrValue, "RIGHT", 4, 0)
    hdrDefault:SetWidth(100)
    hdrDefault:SetJustifyH("LEFT")
    hdrDefault:SetText("Default")
    hdrDefault:SetTextColor(1, 0.82, 0)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  headerFrame, "BOTTOMLEFT",  0, -2)
    divider:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -2)
    divider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

    -- ── Scroll container ────────────────────────────────────
    local listFrame = CreateFrame("ScrollFrame", nil, parent)
    listFrame:SetPoint("TOPLEFT",     divider,  "BOTTOMLEFT",  0, -2)
    listFrame:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", -(SCROLLBAR_W + 8), 4)

    local listChild = CreateFrame("Frame", nil, listFrame)
    listChild:SetWidth(1)
    listFrame:SetScrollChild(listChild)

    -- Width sync
    listFrame:SetScript("OnSizeChanged", function(self, w)
        listChild:SetWidth(w)
    end)
    C_Timer.After(0, function()
        listChild:SetWidth(listFrame:GetWidth())
    end)

    -- ── Scrollbar ───────────────────────────────────────────
    local UpdateScrollbar = VUI.AttachSlimScrollbar(listFrame, {
        wheelStep      = ROW_H * 3,
        scrollbarWidth = SCROLLBAR_W,
        gap            = 4,
        parent         = parent,
    })

    -- ── Virtual scroll state ────────────────────────────────
    local expandedName = nil
    local lastScroll   = -1
    local yPositions   = {}    -- [i] = top y of row i (positive, distance from top)
    local totalVirtualH = 0

    -- ── Shared inline editor (one instance, repositioned) ───
    local editor = CreateFrame("Frame", nil, listChild)
    editor:SetHeight(EXPAND_H)
    editor:Hide()

    local editBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    editBox:SetSize(160, 20)
    editBox:SetPoint("LEFT", editor, "LEFT", 4, 0)
    editBox:SetAutoFocus(false)

    local setBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    setBtn:SetSize(40, 20)
    setBtn:SetPoint("LEFT", editBox, "RIGHT", 6, 0)
    setBtn:SetText("Set")

    local resetDefBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    resetDefBtn:SetSize(60, 20)
    resetDefBtn:SetPoint("LEFT", setBtn, "RIGHT", 4, 0)
    resetDefBtn:SetText("Reset")

    -- Editor callbacks — use expandedName to find the active entry.
    setBtn:SetScript("OnClick", function()
        if not expandedName then return end
        local entry = cvarByName[expandedName]
        if not entry then return end
        AO:SetCVar(entry.name, editBox:GetText())
        RefreshEntry(entry)
        -- Rebind so the row reflects the new value.
        lastScroll = -1
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        if not expandedName then return end
        local entry = cvarByName[expandedName]
        if not entry then return end
        AO:SetCVar(entry.name, self:GetText())
        RefreshEntry(entry)
        self:ClearFocus()
        lastScroll = -1
    end)
    resetDefBtn:SetScript("OnClick", function()
        if not expandedName then return end
        local entry = cvarByName[expandedName]
        if not entry then return end
        AO:ResetCVar(entry.name)
        RefreshEntry(entry)
        lastScroll = -1
    end)

    -- ── Row pool (fixed-size, created once) ─────────────────
    local pool = {}

    for pi = 1, POOL_SIZE do
        local row = CreateFrame("Button", nil, listChild)
        row:SetHeight(ROW_H)
        row:Hide()

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
        nameFs:SetWidth(200)
        nameFs:SetJustifyH("LEFT")
        row._nameFs = nameFs

        local valFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valFs:SetPoint("LEFT", nameFs, "RIGHT", 4, 0)
        valFs:SetWidth(100)
        valFs:SetJustifyH("LEFT")
        row._valFs = valFs

        local defFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        defFs:SetPoint("LEFT", valFs, "RIGHT", 4, 0)
        defFs:SetWidth(100)
        defFs:SetJustifyH("LEFT")
        defFs:SetTextColor(0.5, 0.5, 0.5)
        row._defFs = defFs

        -- Stable reference for click handlers (updated by BindRow)
        row._entry = nil

        pool[pi] = row
    end

    -- ── Bind a pool row to a data entry ─────────────────────
    local function BindRow(row, entry, dataIndex)
        row._entry = entry

        -- Refresh this single entry's live CVar value
        RefreshEntry(entry)

        row._nameFs:SetText(entry.name)
        row._valFs:SetText(entry.value)
        row._defFs:SetText(entry.default)

        -- Modified indicator
        if entry.value ~= entry.default then
            row._valFs:SetTextColor(0.4, 0.8, 1)
        else
            row._valFs:SetTextColor(0.75, 0.75, 0.75)
        end

        -- Star colour
        local isFav = AO:IsFavorite(entry.name)
        row._starIcon:SetVertexColor(isFav and 1 or 0.25,
                                      isFav and 0.82 or 0.25,
                                      isFav and 0 or 0.25)
        row._starIcon:SetDesaturated(not isFav)

        -- Alternating background based on data index
        row._bg:SetColorTexture(1, 1, 1, (dataIndex % 2 == 0) and 0.03 or 0)
    end

    -- ── Compute virtual layout ──────────────────────────────
    local function ComputeLayout()
        yPositions = {}
        totalVirtualH = 0
        for i, entry in ipairs(filteredList) do
            yPositions[i] = totalVirtualH
            totalVirtualH = totalVirtualH + ROW_H
            if expandedName == entry.name then
                totalVirtualH = totalVirtualH + EXPAND_H
            end
        end
        listChild:SetHeight(math_max(totalVirtualH, 1))
    end

    -- ── Rebind visible rows ─────────────────────────────────
    --  Called on every scroll position change. Only touches the
    --  ~24 pool rows — O(filteredList) scan to find visible range,
    --  O(POOL_SIZE) binds. No frame creation, no closure allocation.
    local function RebindVisibleRows()
        local scroll   = listFrame:GetVerticalScroll()
        local viewH    = listFrame:GetHeight()
        local scrollEnd = scroll + viewH

        local poolIdx    = 1
        local editorUsed = false

        for i, entry in ipairs(filteredList) do
            local rowTop = yPositions[i]
            if not rowTop then break end
            local isExpanded = (expandedName == entry.name)
            local rowBot = rowTop + ROW_H + (isExpanded and EXPAND_H or 0)

            -- Skip rows entirely above the viewport
            if rowBot <= scroll then
                -- nothing
            elseif rowTop >= scrollEnd then
                -- Past the viewport — no more visible rows
                break
            else
                -- Visible — bind to a pool row
                local row = pool[poolIdx]
                if not row then break end

                BindRow(row, entry, i)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  listChild, "TOPLEFT",  0, -rowTop)
                row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -rowTop)
                row:Show()

                -- Position the shared editor beneath this row
                if isExpanded then
                    editor:ClearAllPoints()
                    editor:SetPoint("TOPLEFT",  listChild, "TOPLEFT",  20, -(rowTop + ROW_H))
                    editor:SetPoint("TOPRIGHT", listChild, "TOPRIGHT",  0, -(rowTop + ROW_H))
                    editBox:SetText(entry.value)
                    editor:Show()
                    editorUsed = true
                end

                poolIdx = poolIdx + 1
            end
        end

        -- Hide unused pool rows
        for i = poolIdx, POOL_SIZE do
            pool[i]:Hide()
            pool[i]._entry = nil
        end

        if not editorUsed then editor:Hide() end
        UpdateScrollbar()
    end

    -- ── Full refresh (filter/favourite/expand change) ───────
    local function FullRefresh()
        EnumerateCVars()
        ApplyFilter(searchBox:GetText() or "")
        ComputeLayout()
        listFrame:SetVerticalScroll(0)   -- show results from the top
        lastScroll = -1                  -- force rebind on next OnUpdate
    end

    -- ── Row click handlers (bound once, use row._entry) ─────
    for _, row in ipairs(pool) do
        row._star:SetScript("OnClick", function()
            if not row._entry then return end
            AO:ToggleFavorite(row._entry.name)
            FullRefresh()
        end)

        row:SetScript("OnClick", function()
            if not row._entry then return end
            if expandedName == row._entry.name then
                expandedName = nil
            else
                expandedName = row._entry.name
            end
            ComputeLayout()
            lastScroll = -1
        end)

        row:SetScript("OnEnter", function(self)
            local e = self._entry
            if e and e.help and e.help ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(e.name, 1, 1, 1)
                GameTooltip:AddLine(e.help, 0.75, 0.75, 0.75, true)
                if e.locked then
                    GameTooltip:AddLine("Locked by graphics engine", 1, 0.6, 0)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- ── Scroll-position monitor ─────────────────────────────
    --  Checks once per frame whether the scroll position changed;
    --  if so, rebinds the visible pool rows. The comparison is a
    --  single number check — negligible per-frame cost.
    listFrame:HookScript("OnUpdate", function()
        local scroll = listFrame:GetVerticalScroll()
        if scroll ~= lastScroll then
            lastScroll = scroll
            RebindVisibleRows()
        end
    end)

    -- ── Debounced search ────────────────────────────────────
    local searchTimer
    searchBox:HookScript("OnTextChanged", function()
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.2, function()
            searchTimer = nil
            expandedName = nil
            FullRefresh()
        end)
    end)

    -- Store refresh handle
    AO._browserRefresh = FullRefresh

    -- Initial populate deferred to first show
    parent:SetScript("OnShow", function()
        FullRefresh()
    end)

    return listFrame
end
