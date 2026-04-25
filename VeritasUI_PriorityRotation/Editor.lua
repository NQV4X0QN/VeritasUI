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
                local selTab = PanelTemplates_GetSelectedTab
                    and PanelTemplates_GetSelectedTab(MacroFrame)
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
        .."|cFFFFFF00Freq|r = how often per cycle (3+=priority/cooldown, 1=filler).")

    -- Divider below the header-label row. Column headers themselves are
    -- created AFTER the row loop so they can anchor to row 1's components
    -- and stay column-aligned automatically (the 22px gap leaves room for
    -- the header fontstrings between lHelp and divLine).
    local divLine = parent:CreateTexture(nil, "ARTWORK")
    divLine:SetHeight(1)
    divLine:SetPoint("TOPLEFT",  lHelp,  "BOTTOMLEFT", -4, -22)
    divLine:SetPoint("TOPRIGHT", parent, "TOPRIGHT",   -6,   0)
    divLine:SetColorTexture(0.35, 0.35, 0.35, 0.9)

    -- ── Rows ─────────────────────────────────────────────────
    local rows = {}
    local prevAnchor, prevPt, prevOffY = divLine, "BOTTOMLEFT", -4

    for i = 1, PR.MAX_SLOTS do
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(W - 12, ROW_H)
        row:SetPoint("TOPLEFT", prevAnchor, prevPt, 0, prevOffY)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        prevAnchor, prevPt, prevOffY = row, "BOTTOMLEFT", -4

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

        -- Card treatment: dark fill (BACKGROUND) + warm 1px border (BORDER).
        -- BACKGROUND/BORDER draw layers ensure all child frames (icon, text,
        -- arrows) render on top without any stacking workarounds.
        local cardFill = row:CreateTexture(nil, "BACKGROUND")
        cardFill:SetAllPoints()
        cardFill:SetColorTexture(0.07, 0.06, 0.05, 0.90)

        local CR, CG, CB, CA = 0.28, 0.23, 0.14, 0.75  -- warm amber border
        local bTop = row:CreateTexture(nil, "BORDER")
        bTop:SetColorTexture(CR, CG, CB, CA)
        bTop:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
        bTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        bTop:SetHeight(1)
        local bBot = row:CreateTexture(nil, "BORDER")
        bBot:SetColorTexture(CR, CG, CB, CA)
        bBot:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
        bBot:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        bBot:SetHeight(1)
        local bLft = row:CreateTexture(nil, "BORDER")
        bLft:SetColorTexture(CR, CG, CB, CA)
        bLft:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
        bLft:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        bLft:SetWidth(1)
        local bRgt = row:CreateTexture(nil, "BORDER")
        bRgt:SetColorTexture(CR, CG, CB, CA)
        bRgt:SetPoint("TOPRIGHT",    row, "TOPRIGHT",    0, 0)
        bRgt:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        bRgt:SetWidth(1)

        local numLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        numLbl:SetWidth(18)
        numLbl:SetText(i)
        numLbl:SetTextColor(0.75, 0.75, 0.20)
        numLbl:SetJustifyH("CENTER")

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

        local freqLbl = freqFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        freqLbl:SetPoint("CENTER")
        freqLbl:SetTextColor(1, 1, 1)
        row.freqLbl = freqLbl

        -- Both arrows use the SAME rotation value (-π/2 = CW in WoW screen
        -- space) to guarantee identical sub-pixel vertical rendering.
        -- Arrow-Down-Up tip starts at BOTTOM → CW 90° = points LEFT  (dec)
        -- Arrow-Up-Up   tip starts at TOP    → CW 90° = points RIGHT (inc)
        local decBtn = CreateFrame("Button", nil, freqFrame)
        decBtn:SetSize(20, ROW_H)
        decBtn:SetPoint("LEFT")
        local decArrow = decBtn:CreateTexture(nil, "ARTWORK")
        decArrow:SetSize(12, 12)
        decArrow:SetPoint("CENTER", freqFrame, "LEFT", 10, 0)
        decArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        decArrow:SetRotation(-math.pi / 2)
        decBtn:SetScript("OnEnter", function()
            decArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Down")
            decArrow:SetRotation(-math.pi / 2)
        end)
        decBtn:SetScript("OnLeave", function()
            decArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
            decArrow:SetRotation(-math.pi / 2)
        end)
        decBtn:SetScript("OnClick", function()
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.freq = math.max(1, (e.freq or 1) - 1)
            PR:SaveCurrentProfile(); editor:Refresh()
        end)

        local incBtn = CreateFrame("Button", nil, freqFrame)
        incBtn:SetSize(20, ROW_H)
        incBtn:SetPoint("RIGHT")
        local incArrow = incBtn:CreateTexture(nil, "ARTWORK")
        incArrow:SetSize(12, 12)
        incArrow:SetPoint("CENTER", freqFrame, "RIGHT", -10, 0)
        incArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        incArrow:SetRotation(-math.pi / 2)
        incBtn:SetScript("OnEnter", function()
            incArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Down")
            incArrow:SetRotation(-math.pi / 2)
        end)
        incBtn:SetScript("OnLeave", function()
            incArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
            incArrow:SetRotation(-math.pi / 2)
        end)
        incBtn:SetScript("OnClick", function()
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.freq = math.min(5, (e.freq or 1) + 1)
            PR:SaveCurrentProfile(); editor:Refresh()
        end)

        row.decBtn, row.incBtn = decBtn, incBtn
        rows[i] = row
    end

    -- ── Column headers ───────────────────────────────────────────────
    -- All anchored to rows[1]'s TOPLEFT for a CONSISTENT vertical baseline
    -- (anchoring to each column's TOP would put them at different heights
    -- because column heights differ: iconBtn=28, freqFrame=38, text=~12).
    --
    -- X offsets are hardcoded to match the row-column layout above:
    --   numLbl    LEFT=4,   width=18   → center=13
    --   iconBtn   LEFT=47,  width=28   → center=61
    --   nameLbl   LEFT=82,  width=130  → LEFT=82 (left-justified header)
    --   freqFrame LEFT=216, width=70   → center=251
    -- If you change row column sizing, update these offsets in lockstep.
    local HEADER_Y = 6
    local function MakeCenteredHeader(xOff, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOM", rows[1], "TOPLEFT", xOff, HEADER_Y)
        fs:SetTextColor(0.85, 0.75, 0.20)
        fs:SetText(text)
        return fs
    end

    MakeCenteredHeader(13,  "#")
    MakeCenteredHeader(61,  "Icon")
    local hAbility = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAbility:SetPoint("BOTTOMLEFT", rows[1], "TOPLEFT", 82, HEADER_Y)
    hAbility:SetTextColor(0.85, 0.75, 0.20)
    hAbility:SetText("Ability")
    MakeCenteredHeader(251, "Freq")

    -- Drop zone
    local dropZone = CreateFrame("Button", nil, parent)
    dropZone:SetSize(W - 12, 26)
    dropZone:SetPoint("TOPLEFT", rows[PR.MAX_SLOTS], "BOTTOMLEFT", 0, -6)
    dropZone:RegisterForClicks("LeftButtonUp")
    local dzFill = dropZone:CreateTexture(nil, "BACKGROUND")
    dzFill:SetAllPoints()
    dzFill:SetColorTexture(0.02, 0.12, 0.02, 0.75)
    local DZR, DZG, DZB, DZA = 0.10, 0.45, 0.10, 0.75
    local dzBTop = dropZone:CreateTexture(nil, "BORDER")
    dzBTop:SetColorTexture(DZR, DZG, DZB, DZA)
    dzBTop:SetPoint("TOPLEFT",  dropZone, "TOPLEFT",  0, 0)
    dzBTop:SetPoint("TOPRIGHT", dropZone, "TOPRIGHT", 0, 0)
    dzBTop:SetHeight(1)
    local dzBBot = dropZone:CreateTexture(nil, "BORDER")
    dzBBot:SetColorTexture(DZR, DZG, DZB, DZA)
    dzBBot:SetPoint("BOTTOMLEFT",  dropZone, "BOTTOMLEFT",  0, 0)
    dzBBot:SetPoint("BOTTOMRIGHT", dropZone, "BOTTOMRIGHT", 0, 0)
    dzBBot:SetHeight(1)
    local dzBLft = dropZone:CreateTexture(nil, "BORDER")
    dzBLft:SetColorTexture(DZR, DZG, DZB, DZA)
    dzBLft:SetPoint("TOPLEFT",    dropZone, "TOPLEFT",    0, 0)
    dzBLft:SetPoint("BOTTOMLEFT", dropZone, "BOTTOMLEFT", 0, 0)
    dzBLft:SetWidth(1)
    local dzBRgt = dropZone:CreateTexture(nil, "BORDER")
    dzBRgt:SetColorTexture(DZR, DZG, DZB, DZA)
    dzBRgt:SetPoint("TOPRIGHT",    dropZone, "TOPRIGHT",    0, 0)
    dzBRgt:SetPoint("BOTTOMRIGHT", dropZone, "BOTTOMRIGHT", 0, 0)
    dzBRgt:SetWidth(1)
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