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
local math_abs       = math.abs
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

function AO:BuildBrowserContent(parent)
    local SCROLLBAR_W = 8
    local INSET       = 8

    -- ── Search Box ──────────────────────────────────────────
    -- Uses Blizzard's own SearchBoxTemplate (same as the Options
    -- panel search bar). Previous attempts failed because
    -- parent:GetWidth() returns 0 at build time (the browser
    -- container starts hidden). Fix: anchor with TOPLEFT + RIGHT
    -- so width is derived from the parent's layout engine, not
    -- from an explicit SetSize that depends on GetWidth().
    local searchBox = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    searchBox:SetHeight(22)
    searchBox:SetPoint("TOPLEFT",  parent, "TOPLEFT",  INSET, -INSET)
    searchBox:SetPoint("RIGHT",    parent, "RIGHT",   -INSET,  0)
    searchBox:SetAutoFocus(false)

    -- SearchBoxTemplate exposes .Instructions for placeholder text
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Search CVars...")
    end

    local searchAnchor = searchBox

    -- ── Column headers ──────────────────────────────────────
    -- Anchor-based width (LEFT + RIGHT) so it works even when
    -- the parent hasn't been shown yet.
    local headerFrame = CreateFrame("Frame", nil, parent)
    headerFrame:SetHeight(16)
    headerFrame:SetPoint("TOPLEFT",  searchAnchor, "BOTTOMLEFT",   0, -6)
    headerFrame:SetPoint("RIGHT",    parent,       "RIGHT",       -(INSET + SCROLLBAR_W + 4), 0)

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
    listFrame:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", -(SCROLLBAR_W + 12), 4)
    listFrame:EnableMouseWheel(true)

    local listChild = CreateFrame("Frame", nil, listFrame)
    listChild:SetWidth(1)    -- placeholder; real width set by OnSizeChanged + deferred init
    listFrame:SetScrollChild(listChild)

    listFrame:SetScript("OnSizeChanged", function(self, w)
        listChild:SetWidth(w)
    end)
    C_Timer.After(0, function()
        listChild:SetWidth(listFrame:GetWidth())
    end)

    -- ── Modern minimal scrollbar ────────────────────────────
    -- Slim thumb track on the right edge, matching the modern
    -- Blizzard style (Talents, Collections, Professions).
    -- Built from plain frames + textures — no legacy templates.
    local scrollTrack = CreateFrame("Frame", nil, parent)
    scrollTrack:SetWidth(SCROLLBAR_W)
    scrollTrack:SetPoint("TOPLEFT",    listFrame, "TOPRIGHT",    4, 0)
    scrollTrack:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMRIGHT", 4, 0)

    local trackBg = scrollTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)

    -- Round the track with small corner insets
    local trackBorder = scrollTrack:CreateTexture(nil, "BORDER")
    trackBorder:SetAllPoints()
    trackBorder:SetColorTexture(0.25, 0.25, 0.25, 0.4)

    local thumb = CreateFrame("Button", nil, scrollTrack)
    thumb:SetWidth(SCROLLBAR_W)
    thumb:EnableMouse(true)
    thumb:SetMovable(true)
    -- Drag is implemented via OnMouseDown / OnMouseUp / OnUpdate below;
    -- no OnClick handler is needed, so no RegisterForClicks call either.

    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.45, 0.45, 0.45, 0.8)

    local thumbHover = thumb:CreateTexture(nil, "HIGHLIGHT")
    thumbHover:SetAllPoints()
    thumbHover:SetColorTexture(0.6, 0.6, 0.6, 0.5)

    local MIN_THUMB_H = 24

    local function UpdateScrollbar()
        local maxScroll = listFrame:GetVerticalScrollRange()
        local trackH    = scrollTrack:GetHeight()

        if maxScroll <= 0 or trackH <= 0 then
            thumb:Hide()
            return
        end
        thumb:Show()

        -- Thumb height proportional to visible/total ratio
        local visibleH  = listFrame:GetHeight()
        local contentH  = visibleH + maxScroll
        local thumbH    = math_max(MIN_THUMB_H, (visibleH / contentH) * trackH)
        thumb:SetHeight(thumbH)

        -- Thumb position proportional to current scroll
        local curScroll = listFrame:GetVerticalScroll()
        local scrollPct = curScroll / maxScroll
        local travel    = trackH - thumbH
        local yOff      = -(scrollPct * travel)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", scrollTrack, "TOPLEFT", 0, yOff)
    end

    -- Mousewheel drives scroll + updates thumb
    listFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = cur - (delta * ROW_H * 3)
        newScroll = math_max(0, math_min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
        UpdateScrollbar()
    end)

    -- Mousewheel on the scrollbar track itself
    scrollTrack:EnableMouseWheel(true)
    scrollTrack:SetScript("OnMouseWheel", function(_, delta)
        local cur = listFrame:GetVerticalScroll()
        local maxScroll = listFrame:GetVerticalScrollRange()
        local newScroll = cur - (delta * ROW_H * 3)
        newScroll = math_max(0, math_min(newScroll, maxScroll))
        listFrame:SetVerticalScroll(newScroll)
        UpdateScrollbar()
    end)

    -- Thumb drag
    local isDragging = false
    local dragStartY, dragStartScroll

    thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
            dragStartY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
            dragStartScroll = listFrame:GetVerticalScroll()
            self:SetScript("OnUpdate", function()
                if not isDragging then return end
                local curY = select(2, GetCursorPosition()) / thumb:GetEffectiveScale()
                local deltaY = dragStartY - curY
                local trackH = scrollTrack:GetHeight()
                local thumbH = thumb:GetHeight()
                local travel = trackH - thumbH
                if travel <= 0 then return end
                local maxScroll = listFrame:GetVerticalScrollRange()
                local scrollDelta = (deltaY / travel) * maxScroll
                local newScroll = math_max(0, math_min(maxScroll, dragStartScroll + scrollDelta))
                listFrame:SetVerticalScroll(newScroll)
                UpdateScrollbar()
            end)
        end
    end)

    thumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            isDragging = false
            self:SetScript("OnUpdate", nil)
        end
    end)

    -- Click on track (above or below thumb) to page-jump
    scrollTrack:EnableMouse(true)
    scrollTrack:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local trackTop = self:GetTop()
        local clickPct = (trackTop - cursorY) / self:GetHeight()
        local maxScroll = listFrame:GetVerticalScrollRange()
        local newScroll = math_max(0, math_min(maxScroll, clickPct * maxScroll))
        listFrame:SetVerticalScroll(newScroll)
        UpdateScrollbar()
    end)

    -- ── Row pool ────────────────────────────────────────────
    local rows = {}
    local expandedName = nil   -- CVar name of the currently-expanded row
                               -- (keyed by name, not list index, so toggling
                               -- a favourite doesn't desync which row is open)

    local function CreateRow(index)
        local row = CreateFrame("Button", nil, listChild)
        row:SetHeight(ROW_H)

        -- Alternating background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.03 or 0)

        -- Highlight on hover
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)

        -- Star (favourite toggle)
        local star = CreateFrame("Button", nil, row)
        star:SetSize(16, ROW_H)
        star:SetPoint("LEFT", row, "LEFT", 0, 0)
        local starIcon = star:CreateTexture(nil, "OVERLAY")
        starIcon:SetSize(12, 12)
        starIcon:SetPoint("CENTER")
        starIcon:SetAtlas("auctionhouse-icon-favorite")
        row.star     = star
        row.starIcon = starIcon

        -- Name
        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFs:SetPoint("LEFT", star, "RIGHT", 4, 0)
        nameFs:SetWidth(200)
        nameFs:SetJustifyH("LEFT")
        row.nameFs = nameFs

        -- Value
        local valFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valFs:SetPoint("LEFT", nameFs, "RIGHT", 4, 0)
        valFs:SetWidth(100)
        valFs:SetJustifyH("LEFT")
        row.valFs = valFs

        -- Default
        local defFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        defFs:SetPoint("LEFT", valFs, "RIGHT", 4, 0)
        defFs:SetWidth(100)
        defFs:SetJustifyH("LEFT")
        defFs:SetTextColor(0.5, 0.5, 0.5)
        row.defFs = defFs

        -- Inline editor (hidden by default)
        local editor = CreateFrame("Frame", nil, row)
        editor:SetHeight(EXPAND_H)
        editor:SetPoint("TOPLEFT",  row, "BOTTOMLEFT",  20, 0)
        editor:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0,  0)
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

        editor.editBox    = editBox
        editor.setBtn     = setBtn
        editor.resetBtn   = resetDefBtn
        row.editor        = editor
        row._editorHeight = EXPAND_H

        return row
    end

    -- ── Refresh display ─────────────────────────────────────
    local function Refresh()
        EnumerateCVars()
        ApplyFilter(searchBox:GetText() or "")

        -- Ensure enough rows exist
        for i = #rows + 1, #filteredList do
            rows[i] = CreateRow(i)
        end

        -- Lay out visible rows
        local yOff = 0
        for i, entry in ipairs(filteredList) do
            local row = rows[i]
            if not row then break end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  listChild, "TOPLEFT",  0, yOff)
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, yOff)
            row:Show()

            -- Refresh entry data
            RefreshEntry(entry)

            -- Star
            local isFav = AO:IsFavorite(entry.name)
            row.starIcon:SetVertexColor(isFav and 1 or 0.25, isFav and 0.82 or 0.25, isFav and 0 or 0.25)
            row.starIcon:SetDesaturated(not isFav)
            row.star:SetScript("OnClick", function()
                AO:ToggleFavorite(entry.name)
                Refresh()
            end)

            -- Text
            row.nameFs:SetText(entry.name)
            row.valFs:SetText(entry.value)
            row.defFs:SetText(entry.default)

            -- Modified indicator — highlight value if different from default
            if entry.value ~= entry.default then
                row.valFs:SetTextColor(0.4, 0.8, 1)
            else
                row.valFs:SetTextColor(0.75, 0.75, 0.75)
            end

            -- Row click → toggle inline editor
            local expanded = (expandedName == entry.name)
            row.editor:SetShown(expanded)
            if expanded then
                row.editor.editBox:SetText(entry.value)
            end

            row:SetScript("OnClick", function()
                if expandedName == entry.name then
                    expandedName = nil
                else
                    expandedName = entry.name
                end
                Refresh()
            end)

            -- Editor callbacks
            row.editor.setBtn:SetScript("OnClick", function()
                local newVal = row.editor.editBox:GetText()
                AO:SetCVar(entry.name, newVal)
                RefreshEntry(entry)
                Refresh()
            end)
            row.editor.editBox:SetScript("OnEnterPressed", function(self)
                AO:SetCVar(entry.name, self:GetText())
                RefreshEntry(entry)
                Refresh()
                self:ClearFocus()
            end)
            row.editor.resetBtn:SetScript("OnClick", function()
                AO:ResetCVar(entry.name)
                RefreshEntry(entry)
                Refresh()
            end)

            -- Tooltip — show help text if available
            row:SetScript("OnEnter", function(self)
                if entry.help and entry.help ~= "" then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(entry.name, 1, 1, 1)
                    GameTooltip:AddLine(entry.help, 0.75, 0.75, 0.75, true)
                    if entry.locked then
                        GameTooltip:AddLine("Locked by graphics engine", 1, 0.6, 0)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            yOff = yOff - ROW_H
            if expanded then
                yOff = yOff - EXPAND_H
            end
        end

        -- Hide excess rows
        for i = #filteredList + 1, #rows do
            rows[i]:Hide()
        end

        listChild:SetHeight(math_abs(yOff) + 20)
        C_Timer.After(0, UpdateScrollbar)
    end

    -- Debounced search
    local searchTimer
    searchBox:HookScript("OnTextChanged", function(self, userInput)
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.2, function()
            searchTimer = nil
            expandedName = nil
            Refresh()
        end)
    end)

    -- Store refresh handle
    AO._browserRefresh = Refresh

    -- Initial populate deferred to first show
    parent:SetScript("OnShow", function()
        Refresh()
    end)

    return listFrame
end
