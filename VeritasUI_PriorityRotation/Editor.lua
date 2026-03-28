-- ============================================================
-- PriorityRotation — Editor.lua
-- Drag-and-drop spell list with freq spinner and sequence preview.
-- ============================================================
local _, PR = ...
local VUI = _G.VeritasUI
if not VUI then return end   -- Core.lua already printed the error

local ICON_SZ = 28
local ROW_H   = 38

-- Safe spellbook opener
local function OpenSpellBook()
    if PlayerSpellsUtil and PlayerSpellsUtil.OpenToSpellBookTab then
        PlayerSpellsUtil.OpenToSpellBookTab()
    elseif TogglePlayerSpellsFrame then
        TogglePlayerSpellsFrame()
    elseif PlayerSpellsFrame then
        if PlayerSpellsFrame:IsShown() then HideUIPanel(PlayerSpellsFrame)
        else ShowUIPanel(PlayerSpellsFrame) end
    elseif ToggleSpellBook then
        ToggleSpellBook(BOOKTYPE_SPELL or "spell")
    else
        VUI.Print("Priority Rotation", "Press |cFFFFFF00P|r to open your spellbook.")
    end
end

-- ── Drop helpers ─────────────────────────────────────────────
-- HandleDrop appends if slotIndex is beyond the current list
-- to prevent sparse array holes.

-- Extract the primary spell name from a macro body.
-- Tries #showtooltip first, then /cast or /use lines.
-- Strips macro conditionals like [@player, combat, nochanneling].
local function ExtractSpellFromMacro(macroName)
    local body = GetMacroBody(macroName)
    if not body or body == "" then return nil end

    -- Try #showtooltip <SpellName> first
    local showtt = body:match("#showtooltip%s+([^\n]+)")
    if showtt then
        showtt = strtrim(showtt)
        if showtt ~= "" then
            local info = C_Spell.GetSpellInfo(showtt)
            if info and info.spellID then return info.spellID end
        end
    end

    -- Try /cast or /use lines, stripping conditionals
    for line in body:gmatch("[^\n]+") do
        local spellName = line:match("^/[Cc]ast%s+(.+)") or line:match("^/[Uu]se%s+(.+)")
        if spellName then
            -- Strip conditionals: remove [...] blocks
            spellName = spellName:gsub("%b[]%s*", "")
            spellName = strtrim(spellName)
            -- Strip trailing ;fallback spells — take the first one
            spellName = spellName:match("^([^;]+)") or spellName
            spellName = strtrim(spellName)
            if spellName ~= "" then
                local info = C_Spell.GetSpellInfo(spellName)
                if info and info.spellID then return info.spellID end
            end
        end
    end
    return nil
end

-- BuildEntry creates a profile entry from the current cursor.
-- Returns (entry, errorMsg) — entry is nil on failure.
local function BuildEntryFromCursor()
    local cursorType, cursorData, _, cursorSpellID = GetCursorInfo()
    if not cursorType then return nil end

    if cursorType == "spell" then
        local spellID = cursorSpellID or cursorData
        local info = C_Spell.GetSpellInfo(spellID)
        if not (info and info.name) then
            return nil, "Could not resolve spell ID " .. tostring(spellID)
        end
        return {
            spellID   = spellID,
            spellName = info.name,
            icon      = info.iconID,
            freq      = 1,
        }
    elseif cursorType == "macro" then
        local rawIndex = cursorData
        local MAX_ACCT = MAX_ACCOUNT_MACROS or 120

        -- GetCursorInfo may return a tab-relative index when the user
        -- drags from the character-specific macro tab.  Character macros
        -- live at slots (MAX_ACCOUNT_MACROS+1) .. (MAX_ACCOUNT_MACROS+30),
        -- so we must detect and apply the offset.
        local mName, mIcon, mBody = GetMacroInfo(rawIndex)
        local cName, cIcon, cBody
        if rawIndex <= MAX_ACCT then
            cName, cIcon, cBody = GetMacroInfo(rawIndex + MAX_ACCT)
        end

        -- Decide which interpretation is correct:
        local usedCharSlot = false
        if cName and cName ~= "" then
            -- If the MacroFrame is open on the character tab, prefer that
            if MacroFrame and MacroFrame:IsShown() then
                local selTab = PanelTemplates_GetSelectedTab(MacroFrame)
                if selTab == 2 then
                    mName, mIcon, mBody = cName, cIcon, cBody
                    usedCharSlot = true
                end
            elseif not mName or mName == "" then
                -- MacroFrame not open but raw index failed; use char slot
                mName, mIcon, mBody = cName, cIcon, cBody
                usedCharSlot = true
            end
        end

        if not mName or mName == "" or not mBody or mBody == "" then
            return nil, "Could not read macro (index " .. tostring(rawIndex) .. ")."
        end
        return {
            macroName = mName,
            icon      = mIcon,
            freq      = 1,
        }
    end

    return nil, "Drag a spell or macro onto this slot."
end

local function HandleDrop(slotIndex)
    local entry, errMsg = BuildEntryFromCursor()
    if not entry then
        if errMsg then VUI.Print("Priority Rotation", errMsg) end
        return
    end

    local spells = PR:CurrentProfile().spells
    if slotIndex <= #spells then
        spells[slotIndex] = entry       -- overwrite existing slot
    else
        spells[#spells + 1] = entry     -- append (no sparse gaps)
    end

    ClearCursor()
    PR:SaveCurrentProfile()
    if PR.Editor then PR.Editor:Refresh() end
end

local function AppendSpell()
    local spells = PR:CurrentProfile().spells
    if #spells >= PR.MAX_SLOTS then
        VUI.Print("Priority Rotation", "List full (max " .. PR.MAX_SLOTS .. ").")
        return
    end
    local entry, errMsg = BuildEntryFromCursor()
    if not entry then
        if errMsg then VUI.Print("Priority Rotation", errMsg) end
        return
    end

    spells[#spells + 1] = entry
    ClearCursor()
    PR:SaveCurrentProfile()
    if PR.Editor then PR.Editor:Refresh() end
end

-- ── Build the editor ─────────────────────────────────────────
function PR:BuildEditor(parent, contentWidth)
    local W = contentWidth or parent:GetWidth()
    if W < 1 then W = 362 end
    local editor = {}

    local lHelp = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lHelp:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    lHelp:SetWidth(W - 16)
    lHelp:SetJustifyH("LEFT")
    lHelp:SetText(
        "|cFF00CCFFDrag spells|r from your spellbook or |cFF00CCFFmacros|r from /macro onto a slot.\n"
        .."Right-click to remove. Use arrows to reorder.\n"
        .."|cFFFFFF00Freq|r = how often per cycle (1=cooldown, 3+=filler).")

    local lCols = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lCols:SetPoint("TOPLEFT", lHelp, "BOTTOMLEFT", 4, -6)
    lCols:SetText("  #        Icon   Ability                 Freq")
    lCols:SetTextColor(0.65, 0.65, 0.25)

    local divLine = parent:CreateTexture(nil, "ARTWORK")
    divLine:SetHeight(1)
    divLine:SetPoint("TOPLEFT", lCols, "BOTTOMLEFT", -4, -2)
    divLine:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, 0)
    divLine:SetColorTexture(0.35, 0.35, 0.35, 0.9)

    -- ── Rows ─────────────────────────────────────────────────
    local rows = {}
    local prevAnchor, prevPt, prevOffY = divLine, "BOTTOMLEFT", -4

    for i = 1, PR.MAX_SLOTS do
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(W - 12, ROW_H)
        row:SetPoint("TOPLEFT", prevAnchor, prevPt, 0, prevOffY)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        prevAnchor, prevPt, prevOffY = row, "BOTTOMLEFT", -2

        row:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                local spells = PR:CurrentProfile().spells
                if spells[i] then
                    table.remove(spells, i)
                    PR:SaveCurrentProfile()
                    editor:Refresh()
                end
            else
                local cursorType = GetCursorInfo()
                if cursorType == "spell" or cursorType == "macro" then
                    HandleDrop(i)
                elseif not PR:CurrentProfile().spells[i] then
                    OpenSpellBook()
                end
            end
        end)
        row:SetScript("OnReceiveDrag", function() HandleDrop(i) end)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(i % 2 == 0 and 0.13 or 0.08, i % 2 == 0 and 0.13 or 0.08,
                           i % 2 == 0 and 0.14 or 0.09, 0.75)

        local numLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        numLbl:SetWidth(18)
        numLbl:SetText(i)
        numLbl:SetTextColor(0.75, 0.75, 0.20)
        numLbl:SetJustifyH("RIGHT")

        -- Move arrows
        local moveCol = CreateFrame("Frame", nil, row)
        moveCol:SetSize(20, ROW_H)
        moveCol:SetPoint("LEFT", numLbl, "RIGHT", 1, 0)
        local HALF_H = math.floor(ROW_H / 2)

        local moveUpBtn = CreateFrame("Button", nil, moveCol)
        moveUpBtn:SetSize(20, HALF_H)
        moveUpBtn:SetPoint("TOP", moveCol, "TOP", 0, 0)
        local upArrow = moveUpBtn:CreateTexture(nil, "ARTWORK")
        upArrow:SetSize(12, 10)
        upArrow:SetPoint("CENTER", 0, -1)
        upArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        moveUpBtn:SetScript("OnClick", function()
            local spells = PR:CurrentProfile().spells
            if i > 1 and spells[i] then
                spells[i], spells[i - 1] = spells[i - 1], spells[i]
                PR:SaveCurrentProfile(); editor:Refresh()
            end
        end)
        moveUpBtn:SetScript("OnEnter", function() upArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Down") end)
        moveUpBtn:SetScript("OnLeave", function() upArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up") end)
        row.moveUpBtn = moveUpBtn

        local moveDownBtn = CreateFrame("Button", nil, moveCol)
        moveDownBtn:SetSize(20, HALF_H)
        moveDownBtn:SetPoint("BOTTOM", moveCol, "BOTTOM", 0, 0)
        local downArrow = moveDownBtn:CreateTexture(nil, "ARTWORK")
        downArrow:SetSize(12, 10)
        downArrow:SetPoint("CENTER", 0, 1)
        downArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        moveDownBtn:SetScript("OnClick", function()
            local spells = PR:CurrentProfile().spells
            if spells[i] and spells[i + 1] then
                spells[i], spells[i + 1] = spells[i + 1], spells[i]
                PR:SaveCurrentProfile(); editor:Refresh()
            end
        end)
        moveDownBtn:SetScript("OnEnter", function() downArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Down") end)
        moveDownBtn:SetScript("OnLeave", function() downArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up") end)
        row.moveDownBtn = moveDownBtn
        row.moveCol = moveCol

        -- Icon
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(ICON_SZ, ICON_SZ)
        iconBtn:SetPoint("LEFT", moveCol, "RIGHT", 4, 0)
        iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local emptyTex = iconBtn:CreateTexture(nil, "ARTWORK")
        emptyTex:SetAllPoints()
        emptyTex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        iconBtn.empty = emptyTex

        local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:Hide()
        iconBtn.tex = iconTex

        iconBtn:SetScript("OnReceiveDrag", function() HandleDrop(i) end)
        iconBtn:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                if PR:CurrentProfile().spells[i] then
                    table.remove(PR:CurrentProfile().spells, i)
                    PR:SaveCurrentProfile(); editor:Refresh()
                end
            else
                local ct = GetCursorInfo()
                if ct == "spell" or ct == "macro" then HandleDrop(i)
                elseif not PR:CurrentProfile().spells[i] then OpenSpellBook() end
            end
        end)
        iconBtn:SetScript("OnEnter", function(self)
            local e = PR:CurrentProfile().spells[i]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e and e.spellID then
                GameTooltip:SetSpellByID(e.spellID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFFF6644Right-click to remove|r")
            elseif e and e.macroName then
                local resolvedSpellID = ExtractSpellFromMacro(e.macroName)
                if resolvedSpellID then
                    GameTooltip:SetSpellByID(resolvedSpellID)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF66BBFFMacro: " .. e.macroName .. "|r")
                else
                    GameTooltip:AddLine("Macro: " .. e.macroName, 1, 0.82, 0)
                    local body = GetMacroBody(e.macroName)
                    if body and body ~= "" then
                        GameTooltip:AddLine(body, 0.7, 0.7, 0.7, true)
                    end
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFFF6644Right-click to remove|r")
            else
                GameTooltip:AddLine("Slot " .. i, 1, 1, 0)
                GameTooltip:AddLine("Click to open spellbook, or drag a spell/macro here.", 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.iconBtn = iconBtn

        -- Spell name
        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLbl:SetPoint("LEFT", iconBtn, "RIGHT", 7, 0)
        nameLbl:SetWidth(130)
        nameLbl:SetJustifyH("LEFT")
        row.nameLbl = nameLbl

        -- Freq spinner
        local freqFrame = CreateFrame("Frame", nil, row)
        freqFrame:SetSize(70, ROW_H)
        freqFrame:SetPoint("LEFT", nameLbl, "RIGHT", 4, 0)
        freqFrame:Hide()
        row.freqFrame = freqFrame

        local freqLbl = freqFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        freqLbl:SetPoint("CENTER")
        freqLbl:SetTextColor(0.85, 0.75, 0.20)
        row.freqLbl = freqLbl

        local decBtn = CreateFrame("Button", nil, freqFrame)
        decBtn:SetSize(18, ROW_H)
        decBtn:SetPoint("LEFT")
        local dT = decBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dT:SetAllPoints()
        dT:SetText("|cFFFFFFFF< |r")
        decBtn:SetScript("OnClick", function()
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.freq = math.max(1, (e.freq or 1) - 1)
            PR:SaveCurrentProfile(); editor:Refresh()
        end)

        local incBtn = CreateFrame("Button", nil, freqFrame)
        incBtn:SetSize(18, ROW_H)
        incBtn:SetPoint("RIGHT")
        local iT = incBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iT:SetAllPoints()
        iT:SetText("|cFFFFFFFF >|r")
        incBtn:SetScript("OnClick", function()
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.freq = math.min(5, (e.freq or 1) + 1)
            PR:SaveCurrentProfile(); editor:Refresh()
        end)

        row.decBtn, row.incBtn = decBtn, incBtn
        rows[i] = row
    end

    -- Drop zone
    local dropZone = CreateFrame("Button", nil, parent)
    dropZone:SetSize(W - 12, 26)
    dropZone:SetPoint("TOPLEFT", rows[PR.MAX_SLOTS], "BOTTOMLEFT", 0, -6)
    dropZone:RegisterForClicks("LeftButtonUp")
    local dzBg = dropZone:CreateTexture(nil, "BACKGROUND")
    dzBg:SetAllPoints()
    dzBg:SetColorTexture(0.04, 0.22, 0.04, 0.60)
    local dzLbl = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dzLbl:SetAllPoints()
    dzLbl:SetJustifyH("CENTER")
    dzLbl:SetText("|cFF44FF44+  Drop a spell or macro here, or click to open spellbook|r")
    dropZone:SetScript("OnClick", function()
        local ct = GetCursorInfo()
        if ct == "spell" or ct == "macro" then AppendSpell() else OpenSpellBook() end
    end)
    dropZone:SetScript("OnReceiveDrag", AppendSpell)

    -- Sequence preview
    local seqHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seqHeader:SetPoint("TOPLEFT", dropZone, "BOTTOMLEFT", 0, -8)
    seqHeader:SetText("|cFFFFFF00Compiled Sequence:|r")

    local seqPreview = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seqPreview:SetPoint("TOPLEFT", seqHeader, "BOTTOMLEFT", 0, -2)
    seqPreview:SetWidth(W - 16)
    seqPreview:SetJustifyH("LEFT")
    seqPreview:SetTextColor(0.7, 0.7, 0.7)

    -- ── Refresh ──────────────────────────────────────────────
    function editor:Refresh()
        local spells = PR:CurrentProfile().spells
        local numSpells = #spells
        for i = 1, PR.MAX_SLOTS do
            local row = rows[i]
            local e   = spells[i]
            if e and (e.spellID or e.macroName) then
                -- Refresh icon: for macros, re-read the current macro icon
                local displayIcon = e.icon
                if e.macroName then
                    local _, freshIcon = GetMacroInfo(e.macroName)
                    if freshIcon then
                        displayIcon = freshIcon
                        e.icon = freshIcon
                    end
                end
                row.iconBtn.tex:SetTexture(displayIcon)
                row.iconBtn.tex:Show()
                row.iconBtn.empty:Hide()
                local displayName = e.spellName or e.macroName
                if e.macroName then
                    displayName = "|cFF66BBFF[M]|r " .. e.macroName
                end
                row.nameLbl:SetText(displayName)
                row.freqLbl:SetText("x" .. (e.freq or 1))
                row.decBtn:SetAlpha((e.freq or 1) > 1 and 1 or 0.30)
                row.incBtn:SetAlpha((e.freq or 1) < 5 and 1 or 0.30)
                row.freqFrame:Show()
                row.moveCol:Show()
                row.moveUpBtn:SetAlpha(i > 1 and 1 or 0.20)
                row.moveDownBtn:SetAlpha(i < numSpells and 1 or 0.20)
            else
                row.iconBtn.tex:Hide()
                row.iconBtn.empty:Show()
                row.nameLbl:SetText("|cFF3A3A3A-- empty --|r")
                row.freqFrame:Hide()
                row.moveCol:Hide()
            end
        end
        if #PR.compiledSequence > 0 then
            local displayNames = {}
            for idx, cast in ipairs(PR.compiledSequence) do
                local n = PR.compiledNames and PR.compiledNames[idx]
                if n then
                    -- Strip [MACRO:...] wrapper for compact display
                    local mTag = n:match("^%[MACRO:(.-)%]$")
                    displayNames[#displayNames + 1] = mTag and ("[M:" .. mTag .. "]") or n
                else
                    displayNames[#displayNames + 1] = cast:gsub("^/cast ", "")
                end
            end
            seqPreview:SetText(table.concat(displayNames, " > "))
        else
            seqPreview:SetText("|cFF888888(empty -- add spells above)|r")
        end
    end

    PR.Editor = editor
    return editor
end