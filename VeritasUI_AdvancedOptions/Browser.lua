-- VeritasUI_AdvancedOptions / Browser.lua
-- Full CVar browser: searchable, sortable list with inline editing.
--
-- Uses Blizzard's ScrollBox + MinimalScrollBar for native virtual
-- scrolling — same system as Talents, Professions, Housing.

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
--
-- POLICY (formalized v1.6.41 per audit OQ#2): KNOWN_CVARS is
-- intentionally broad.  Dead names — CVars that existed in earlier
-- builds but have been removed in Midnight or any subsequent patch
-- cycle — are silently skipped at runtime via C_CVar.GetCVarInfo
-- returning nil (see Strategy 3 loop at line 225).  Entries are NOT
-- pruned on Midnight removals.
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

    -- Ensure every CVar in the Featured tab is also present in the browser,
    -- regardless of which enumeration strategy fired. Featured.lua loads before
    -- Browser.lua so AO.FEATURED_CATEGORIES is always populated at this point.
    for _, cat in ipairs(AO.FEATURED_CATEGORIES) do
        for _, ctrl in ipairs(cat.controls) do
            local name = ctrl.cvar
            if name and not cvarByName[name] then
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
--  Browser UI — Blizzard ScrollBox + MinimalScrollBar
--
--  Layout:
--    Search box at top
--    Column headers (★ | Name | Value | Default)
--    Native ScrollBox list of rows
--    Click row → inline expand with edit box + Set + Reset buttons
----------------------------------------------------------------
local ROW_H       = 20

function AO:BuildBrowserContent(parent)
    local INSET = 8

    -- ── Search Box ──────────────────────────────────────────
    local SB_INSET = AO.SB_INSET   -- shared with Featured tab for visual alignment

    local searchBox = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    searchBox:SetHeight(22)
    searchBox:SetPoint("TOPLEFT",  parent, "TOPLEFT",  INSET, -INSET)
    searchBox:SetPoint("RIGHT",    parent, "RIGHT",   -INSET,  0)
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

    -- ── ScrollBox + MinimalScrollBar ────────────────────────
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT",     divider,  "BOTTOMLEFT",  0, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", -SB_INSET, 4)

    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",    scrollBox, "TOPRIGHT",    4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

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
        AO:SetCVar(entry.name, self:GetText())
        RefreshEntry(entry)
        -- Update the row's display
        editingRow._valFs:SetText(entry.value)
        if entry.value ~= entry.default then
            editingRow._valFs:SetTextColor(0.4, 0.8, 1)
        else
            editingRow._valFs:SetTextColor(0.75, 0.75, 0.75)
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

    -- Element extent: fixed height for all rows. The inline editor
    -- floats as an overlay below the expanded row at a higher frame level,
    -- so no variable extent is needed.
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
        end

        -- ── Data bind ───────────────────────────────────────
        row._entry = elementData
        RefreshEntry(elementData)

        row._nameFs:SetText(elementData.name)
        row._valFs:SetText(elementData.value)
        row._defFs:SetText(elementData.default)

        -- Modified indicator
        if elementData.value ~= elementData.default then
            row._valFs:SetTextColor(0.4, 0.8, 1)
        else
            row._valFs:SetTextColor(0.75, 0.75, 0.75)
        end

        -- Star colour
        local isFav = AO:IsFavorite(elementData.name)
        row._starIcon:SetVertexColor(isFav and 1 or 0.25,
                                      isFav and 0.82 or 0.25,
                                      isFav and 0 or 0.25)
        row._starIcon:SetDesaturated(not isFav)

        -- Alternating background — derive from name byte sum (stable,
        -- no API call needed; FindIndex doesn't exist on ScrollBox).
        local nameSum = 0
        for i = 1, #elementData.name do nameSum = nameSum + elementData.name:byte(i) end
        row._bg:SetColorTexture(1, 1, 1, (nameSum % 2 == 0) and 0.03 or 0)

        -- ── Inline edit: close if this row is recycled while editing ──
        if editingRow == row then
            CloseInlineEdit()
        end
        -- Ensure value fontstring is visible on rebind
        row._valFs:Show()

        -- ── Row click handlers ──────────────────────────────
        row._star:SetScript("OnClick", function()
            AO:ToggleFavorite(elementData.name)
            AO:RefreshBrowser()
        end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                -- Right-click → reset to default
                AO:ResetCVar(elementData.name)
                RefreshEntry(elementData)
                row._valFs:SetText(elementData.value)
                row._valFs:SetTextColor(0.75, 0.75, 0.75)
                if editingRow == row then CloseInlineEdit() end
            else
                -- Left-click → toggle inline edit
                if editingRow == row then
                    CloseInlineEdit()
                else
                    OpenInlineEdit(row, elementData)
                end
            end
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
    end)

    -- ── Wire ScrollBox + ScrollBar ──────────────────────────
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- ── Data provider refresh ───────────────────────────────
    local function FullRefresh()
        EnumerateCVars()
        ApplyFilter(searchBox:GetText() or "")

        local dataProvider = CreateDataProvider()
        for _, entry in ipairs(filteredList) do
            dataProvider:Insert(entry)
        end
        scrollBox:SetDataProvider(dataProvider)
    end

    function AO:RefreshBrowser()
        CloseInlineEdit()
        FullRefresh()
    end

    -- Store refresh handle
    AO._browserRefresh = FullRefresh

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
