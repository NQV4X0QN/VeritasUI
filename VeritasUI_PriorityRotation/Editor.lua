-- ============================================================
-- PriorityRotation — Editor.lua
-- Drag-and-drop spell list with freq spinner and sequence preview.
-- ============================================================
local _, PR = ...
local VUI = _G.VeritasUI
if not VUI then return end   -- Core.lua already printed the error

local ICON_SZ = 28
local ROW_H   = 38
-- Left edge of a row's dark block: past the slot number (4+18) and icon (5+28), plus a 3 px gap
-- -- the mount list's icon-outside-the-block layout. (The move arrows that sat between number and
-- icon were replaced by drag-to-reorder in v1.35.11.)
local BLOCK_X = 4 + 18 + 5 + ICON_SZ + 3

-- Spellbook / Macro toggles, shared by empty rotation slots and the Settings-tab buttons.
--
-- ⛔ PRIORITY ROTATION NEVER OPENS THE SPELLBOOK ITSELF (v1.22.1). Opening it from this code made
-- the spellbook set itself up as addon code, so a spell clicked in it was refused
-- (CastSpellBookItem, ADDON_ACTION_FORBIDDEN). The click is now forwarded to Blizzard's menu-bar
-- button by SpellbookOpener.lua's secure overlay, which sits on top of the slot or button and gets
-- the click before this runs. This function is only reached when the overlay is not there -- in
-- combat (it is hidden then) or if the menu-bar button is missing -- and it only explains.
local function ToggleSpellBookPanel()
    if InCombatLockdown() then
        VUI.Print("Priority Rotation", VUI.COL.RED .. "Can't toggle Spellbook in combat.|r")
        return
    end
    VUI.Print("Priority Rotation", "Open your spellbook from the menu bar or its key binding.")
end

local function ToggleMacroPanel()
    if InCombatLockdown() then
        VUI.Print("Priority Rotation", VUI.COL.RED .. "Can't toggle Macros in combat.|r")
        return
    end
    if MacroFrame and MacroFrame:IsShown() then
        pcall(HideUIPanel, MacroFrame)
        return
    end
    if ShowMacroFrame then pcall(ShowMacroFrame) end
end

-- Expose on PR so Settings.lua can call them without duplicating the logic.
PR.ToggleSpellBookPanel = ToggleSpellBookPanel
PR.ToggleMacroPanel     = ToggleMacroPanel

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
        if cName and cName ~= "" then
            -- If the MacroFrame is open on the character tab, prefer that
            if MacroFrame and MacroFrame:IsShown() then
                local selTab = PanelTemplates_GetSelectedTab
                    and PanelTemplates_GetSelectedTab(MacroFrame)
                if selTab == 2 then
                    mName, mIcon, mBody = cName, cIcon, cBody
                end
            elseif not mName or mName == "" then
                -- MacroFrame not open but raw index failed; use char slot
                mName, mIcon, mBody = cName, cIcon, cBody
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
    elseif cursorType == "item" then
        -- Items dragged from a bag, character pane trinket slot, or
        -- merchant. cursorData holds the itemID; cursorSpellID is unused.
        local itemID = cursorData
        -- C_Item.GetItemInfo return values may be Secret Values in raid
        -- encounters; guard the call and the equipLoc comparison.
        -- Mirrors IsEquippableGear in QualityOfLife.lua.
        local ok, name, _, quality, _, _, _, _, _, equipLoc, icon =
            pcall(C_Item.GetItemInfo, itemID)
        if not ok or not name then
            -- Item info isn't in the client cache yet (or returned a
            -- Secret Value). Rare for items the player owns (which are
            -- always cached), but possible for ephemeral cursor states.
            -- Ask the user to retry once cached.
            return nil, "Item info not loaded yet — try again in a moment."
        end
        local okEq, isTrinket = pcall(function()
            return equipLoc == "INVTYPE_TRINKET"
        end)
        if not okEq or not isTrinket then
            return nil, "Only trinkets can be added to the rotation right now."
        end
        return {
            itemID    = itemID,
            itemName  = name,
            itemQuality = quality,
            icon      = icon,
            freq      = 1,
        }
    end

    return nil, "Drag a spell, macro, or trinket onto this slot."
end

-- Resolve a follows-key (see PR.EntryKey) back to the profile entry it
-- names, or nil if that entry is no longer in the list (stale link —
-- kept in the data so re-adding the same ability reactivates it).
-- `spells` is OPTIONAL: pass it when the caller already holds the list, so a
-- full editor repaint resolves the profile once instead of once per row. The
-- followBtn tooltip caller has no such local in scope, hence the fallback.
local function FindEntryByKey(key, spells)
    if not key then return nil end
    for _, o in ipairs(spells or PR:CurrentProfile().spells) do
        if PR.EntryKey(o) == key then return o end
    end
end

local function EntryDisplayName(e)
    return e and (e.spellName or e.macroName or e.itemName) or "?"
end

-- "After Eye Beam: Essence Break (only), Blade Dance" lines under the compiled sequence: held
-- followers are not in the sequence at all, so without this they would vanish from the preview.
local function AfterLinksText()
    local byTarget, order = {}, {}
    for _, l in ipairs(PR.compiledLinks or {}) do
        if not byTarget[l.target] then byTarget[l.target] = {}; order[#order + 1] = l.target end
        local n = l.name:match("^%[MACRO:(.-)%]$") and ("[M:" .. l.name:match("^%[MACRO:(.-)%]$") .. "]")
            or l.name:match("^%[ITEM:(.-)%]$") and ("[T:" .. l.name:match("^%[ITEM:(.-)%]$") .. "]")
            or l.name
        local t = byTarget[l.target]
        t[#t + 1] = l.only and (n .. " (only)") or n
    end
    local out = {}
    for _, target in ipairs(order) do
        out[#out + 1] = VUI.COL.NORMAL .. "After " .. target .. ":|r " .. table.concat(byTarget[target], ", ")
    end
    return #out > 0 and ("\n\n" .. table.concat(out, "\n")) or ""
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

-- The bags' slot border around every icon box, empty or filled (owner, 2026-10-30): an
-- ItemButton's NormalTexture, Interface\Buttons\UI-Quickslot2, drawn 64 px on a 37 px button and
-- 1 px low (Blizzard_ItemButton/Shared/ItemButtonTemplate.xml:70-75), scaled to `size`. OVERLAY,
-- so it frames the icon the same way whether a slot is empty or filled.
local function SlotBorder(btn, size)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    local sz = math.floor(size * 64 / 37 + 0.5)
    border:SetSize(sz, sz)
    border:SetPoint("CENTER", btn, "CENTER", 0, -1)
    return border
end

-- ── Build the editor ─────────────────────────────────────────
function PR:BuildEditor(parent, contentWidth)
    local W = contentWidth or parent:GetWidth()
    if W < 1 then W = 362 end
    local editor = {}

    -- No explainer paragraph above the rows (removed v1.35.11, owner's request): each column
    -- header explains itself in a tooltip (HEADER_TIPS below), and an empty slot's tooltip says
    -- what to drag onto it.
    --
    -- Divider below the header-label row. Column headers themselves are
    -- created AFTER the row loop so they can anchor to row 1's components
    -- and stay column-aligned automatically (the 26px drop leaves room for
    -- the header fontstrings above divLine).
    local divLine = parent:CreateTexture(nil, "ARTWORK")
    divLine:SetHeight(1)
    divLine:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -26)
    -- Right end matches the rows' right edge (rows start 4 px left of this line
    -- and are W-12 wide, so both end 8 px inside the panel). The left end is
    -- inset 8 px too so the line sits evenly between the borders (owner's
    -- request): the rows' 4 px left inset holds the "#" column, not the line.
    divLine:SetWidth(W - 16)
    divLine:SetColorTexture(0.35, 0.35, 0.35, 0.9)

    -- ── Control-column grid (Frequency / After / Combat) ─────────
    -- The identity cluster (#, icon, name) is a compact left-
    -- aligned unit ending at x=212; the three CONTROL columns to its right
    -- sit on a computed grid. Geometry is exact, not eyeballed: PNL_W=420 →
    -- CONTENT_W=402 (Settings.lua) → ROW_W=390.
    --
    -- The eye judges gaps between VISIBLE edges — for the spinner that's
    -- the arrow ART (inset 4px inside its frame: 20px buttons, art centered
    -- ±10), not the invisible frame edge. With unequal element widths, even
    -- center-spacing and even gaps are mutually exclusive (the mismatch
    -- equals the half-width difference), so: the spinner is narrowed to 56
    -- (arrows tuck in beside the number instead of floating) and the three
    -- gaps — spinner→After, After→Combat, Combat→border — are split equal:
    -- 25/25/26 at the live width. Headers sit on true element centers.
    local ROW_W  = W - 12
    local FREQ_L = 216                        -- name ends 212 + 4 gap
    local FREQ_W, AFTER_W, CHK_W = 56, 24, 22
    local FREQ_VIS_R = FREQ_L + FREQ_W - 4    -- inc-arrow art right edge
    local CTL_GAP = math.floor((ROW_W - FREQ_VIS_R - AFTER_W - CHK_W) / 3)
    if CTL_GAP < 4 then CTL_GAP = 4 end
    local AFTER_L = FREQ_VIS_R + CTL_GAP
    local CHK_L   = AFTER_L + AFTER_W + CTL_GAP

    -- ── Rows ─────────────────────────────────────────────────
    local rows = {}
    -- Row 1 anchors 4 px left of divLine's start (divLine is inset 8, rows 4).
    local prevAnchor, prevPt, prevOffX, prevOffY = divLine, "BOTTOMLEFT", -4, -4

    for i = 1, PR.MAX_SLOTS do
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(W - 12, ROW_H)
        row:SetPoint("TOPLEFT", prevAnchor, prevPt, prevOffX, prevOffY)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        prevAnchor, prevPt, prevOffX, prevOffY = row, "BOTTOMLEFT", 0, -4

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
                if cursorType == "spell" or cursorType == "macro" or cursorType == "item" then
                    HandleDrop(i)
                elseif not PR:CurrentProfile().spells[i] then
                    if IsShiftKeyDown() then ToggleMacroPanel() else ToggleSpellBookPanel() end
                end
            end
        end)
        row:SetScript("OnReceiveDrag", function() HandleDrop(i) end)
        -- An empty slot opens the spellbook through the secure overlay (see ToggleSpellBookPanel).
        if PR.SpellbookOpener then
            PR.SpellbookOpener.AddTarget(row, {
                isActive = function() return not PR:CurrentProfile().spells[i] end,
                onDrop   = function() HandleDrop(i) end,
                onShift  = function() ToggleMacroPanel() end,
            })
        end

        -- ⚠ Blizzard's mount-list row (MountListButtonTemplate, Blizzard_Collections/Mainline/
        -- Blizzard_MountCollection.xml:80-130): the dark block is the PetList-ButtonBackground atlas,
        -- the icon sits outside it to the left, and PetList-ButtonHighlight lights it on hover
        -- (owner's request, v1.35.11; was a hand-drawn dark fill with a 1 px amber border). Here the
        -- slot number, arrows and icon stay left of the block; the block runs from just past the
        -- icon (BLOCK_X) to the row's right edge, under the name and the three control columns.
        local block = row:CreateTexture(nil, "BACKGROUND")
        block:SetAtlas("PetList-ButtonBackground")
        block:SetPoint("TOPLEFT",     row, "TOPLEFT",     BLOCK_X, 0)
        block:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0,       0)
        -- No hover highlight (owner, 2026-10-30): the row's own controls take the mouse, so the
        -- mount list's PetList-ButtonHighlight flickered off and on across the Frequency arrows.
        -- Drag-to-reorder target marker: the mount list's selected-row frame (PetList-ButtonSelect).
        local dropMark = row:CreateTexture(nil, "OVERLAY")
        dropMark:SetAtlas("PetList-ButtonSelect")
        dropMark:SetPoint("TOPLEFT",     block, "TOPLEFT",     0, 0)
        dropMark:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", 0, 0)
        dropMark:Hide()
        row.dropMark = dropMark
        -- Kept for a restyling addon (VeritasUI_ElvUI), which swaps the card for its own panel.
        row.cardArt = { block }

        -- Drag a filled slot by its block or its icon to move it (owner's request, v1.35.11;
        -- replaced the up/down arrows). The game's own drag events: OnDragStart once the mouse
        -- moves with the button held, OnDragStop on release, wherever the cursor is.
        row:RegisterForDrag("LeftButton")
        -- Says so on hover, so the drag can be found (owner, 2026-10-30).
        row:SetScript("OnEnter", function(self)
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(EntryDisplayName(e), HIGHLIGHT_FONT_COLOR:GetRGB())
            GameTooltip:AddLine("Drag to move", HIGHLIGHT_FONT_COLOR:GetRGB())
            GameTooltip:AddLine(VUI.COL.LIGHTBLUE .. "Right-click to remove|r")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnDragStart", function() editor:StartReorder(i) end)
        row:SetScript("OnDragStop",  function() editor:FinishReorder() end)

        local numLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        numLbl:SetWidth(18)
        numLbl:SetText(i)
        numLbl:SetTextColor(NORMAL_FONT_COLOR:GetRGB())   -- Blizzard gold (owner, 2026-11-01)
        numLbl:SetJustifyH("CENTER")

        -- Icon
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(ICON_SZ, ICON_SZ)
        iconBtn:SetPoint("LEFT", numLbl, "RIGHT", 5, 0)
        iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        iconBtn:RegisterForDrag("LeftButton")
        iconBtn:SetScript("OnDragStart", function() editor:StartReorder(i) end)
        iconBtn:SetScript("OnDragStop",  function() editor:FinishReorder() end)

        iconBtn.border = SlotBorder(iconBtn, ICON_SZ)

        local emptyTex = iconBtn:CreateTexture(nil, "ARTWORK")
        emptyTex:SetAllPoints()
        emptyTex:SetAtlas("bags-item-slot64")   -- bags' empty slot (ContainerFrame.xml:80)
        iconBtn.empty = emptyTex

        local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:Hide()
        iconBtn.tex = iconTex

        iconBtn:SetScript("OnReceiveDrag", function() HandleDrop(i) end)
        iconBtn:SetScript("OnClick", function(_, btn)
            -- Resolve the list once, as every sibling handler in this file does.
            -- table.remove mutates in place, so the single local stays correct.
            local spells = PR:CurrentProfile().spells
            if btn == "RightButton" then
                if spells[i] then
                    table.remove(spells, i)
                    PR:SaveCurrentProfile(); editor:Refresh()
                end
            else
                local ct = GetCursorInfo()
                if ct == "spell" or ct == "macro" or ct == "item" then HandleDrop(i)
                elseif not spells[i] then
                    if IsShiftKeyDown() then ToggleMacroPanel() else ToggleSpellBookPanel() end
                end
            end
        end)
        iconBtn:SetScript("OnEnter", function(self)
            local e = PR:CurrentProfile().spells[i]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e and e.spellID then
                GameTooltip:SetSpellByID(e.spellID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Drag to move", HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine(VUI.COL.LIGHTBLUE .. "Right-click to remove|r")
            elseif e and e.itemID then
                -- Items use the standard Blizzard item tooltip with quality
                -- header, ilvl, and use effect — same as hovering an item
                -- in the character pane.
                GameTooltip:SetItemByID(e.itemID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Drag to move", HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine(VUI.COL.LIGHTBLUE .. "Right-click to remove|r")
            elseif e and e.macroName then
                local resolvedSpellID = ExtractSpellFromMacro(e.macroName)
                if resolvedSpellID then
                    GameTooltip:SetSpellByID(resolvedSpellID)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(VUI.COL.LIGHTBLUE .. "Macro: " .. e.macroName .. "|r")
                else
                    GameTooltip:AddLine("Macro: " .. e.macroName, HIGHLIGHT_FONT_COLOR:GetRGB())
                    local body = GetMacroBody(e.macroName)
                    if body and body ~= "" then
                        GameTooltip:AddLine(body, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
                    end
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Drag to move", HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine(VUI.COL.LIGHTBLUE .. "Right-click to remove|r")
            else
                GameTooltip:AddLine("Slot " .. i, HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine("Click to toggle Spellbook · Shift-click to toggle Macros",
                    LIGHTBLUE_FONT_COLOR:GetRGB())
                GameTooltip:AddLine("Drag a spell, macro, or trinket here to fill this slot.",
                    NORMAL_FONT_COLOR:GetRGB())
            end
            GameTooltip:Show()
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.iconBtn = iconBtn

        -- Spell name
        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLbl:SetPoint("LEFT", iconBtn, "RIGHT", 11, 0)   -- 8 px inside the block (owner: 4 more)
        nameLbl:SetWidth(146)   -- ends at 212, where the control columns' grid starts (FREQ_L)
        nameLbl:SetJustifyH("LEFT")
        row.nameLbl = nameLbl

        -- Frequency spinner (grid column 1)
        local freqFrame = CreateFrame("Frame", nil, row)
        freqFrame:SetSize(FREQ_W, ROW_H)
        freqFrame:SetPoint("LEFT", row, "LEFT", FREQ_L, 0)
        freqFrame:Hide()
        row.freqFrame = freqFrame

        local freqLbl = freqFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        freqLbl:SetPoint("CENTER")
        freqLbl:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
        row.freqLbl = freqLbl

        -- ⚠ THE STANDARD ARROW (owner, 2026-10-30): the Journeys renown track's ONE-STEP arrow
        -- (RewardTrackButtonTemplate via RewardTrackArtButtonTemplate, Blizzard_FrameXML/
        -- RewardTrackTemplates.xml:131-165) -- ui-journeys-delve-arrow-big-left with its -pressed /
        -- -disable atlases, the same art added on top at 40% for hover. NOT the -small- atlases:
        -- those are the double "jump to the start / end" arrow (RewardTrackJumpButtonTemplate).
        -- Hover only brightens it; a click shifts it subtly. The right arrow is the left one
        -- mirrored, as Blizzard does (RewardTrackArtButtonMixin:OnLoad, RewardTrackTemplates.lua
        -- :255-262). Drawn at ARROW_W x ARROW_H, smaller than its 22x34 button, to fit the row.
        -- Until v1.35.11 these swapped to a different arrow on hover, which jumped.
        local ARROW_W, ARROW_H = 10, 15
        local function JourneysArrow(btn, facingRight)
            local function Tex(atlas, layer, alpha, blend)
                local t = btn:CreateTexture(nil, layer)
                t:SetAtlas(atlas)
                t:SetSize(ARROW_W, ARROW_H)
                t:SetPoint("CENTER")
                if alpha then t:SetAlpha(alpha) end
                if blend then t:SetBlendMode(blend) end
                if facingRight then t:SetTexCoord(1, 0, 0, 1) end
                return t
            end
            btn:SetNormalTexture(Tex("ui-journeys-delve-arrow-big-left", "ARTWORK"))
            btn:SetPushedTexture(Tex("ui-journeys-delve-arrow-big-left-pressed", "ARTWORK"))
            btn:SetDisabledTexture(Tex("ui-journeys-delve-arrow-big-left-disable", "ARTWORK"))
            btn:SetHighlightTexture(Tex("ui-journeys-delve-arrow-big-left", "HIGHLIGHT", 0.4, "ADD"))
        end

        local decBtn = CreateFrame("Button", nil, freqFrame)
        decBtn:SetSize(20, ROW_H)
        decBtn:SetPoint("LEFT")
        JourneysArrow(decBtn, false)
        decBtn:SetScript("OnClick", function()
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.freq = math.max(1, (e.freq or 1) - 1)
            PR:SaveCurrentProfile(); editor:Refresh()
        end)

        local incBtn = CreateFrame("Button", nil, freqFrame)
        incBtn:SetSize(20, ROW_H)
        incBtn:SetPoint("RIGHT")
        JourneysArrow(incBtn, true)
        incBtn:SetScript("OnClick", function()
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.freq = math.min(5, (e.freq or 1) + 1)
            PR:SaveCurrentProfile(); editor:Refresh()
        end)

        row.decBtn, row.incBtn = decBtn, incBtn

        -- "After" (follows) button — shows the icon of the channelled spell this one waits for
        -- (v1.36.0; the press snippet in Core.lua does the waiting). Left-click cycles through
        -- the other entries that have been seen channelling, then back to none; right-click
        -- switches between "also after" and "only after" (the LFG lock badge).
        local followBtn = CreateFrame("Button", nil, row)
        followBtn:SetSize(AFTER_W, AFTER_W)
        followBtn:SetPoint("LEFT", row, "LEFT", AFTER_L, 0)   -- grid column 2
        followBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local followEmpty = followBtn:CreateTexture(nil, "ARTWORK")
        followEmpty:SetAllPoints()
        followEmpty:SetAtlas("bags-item-slot64")   -- bags' empty slot (ContainerFrame.xml:80)
        followBtn.empty = followEmpty
        followBtn.border = SlotBorder(followBtn, AFTER_W)

        local followTex = followBtn:CreateTexture(nil, "ARTWORK")
        followTex:SetAllPoints()
        followTex:Hide()
        followBtn.tex = followTex

        -- "Only after" badge: the LFG list's lock (17x21), half size in the bottom-right corner.
        local followLock = followBtn:CreateTexture(nil, "OVERLAY", nil, 7)
        followLock:SetAtlas("LFG-lock")
        followLock:SetSize(9, 11)
        followLock:SetPoint("BOTTOMRIGHT", followBtn, "BOTTOMRIGHT", 2, -2)
        followLock:Hide()
        followBtn.lock = followLock

        followBtn:SetScript("OnClick", function(_, btn)
            local spells = PR:CurrentProfile().spells
            local e = spells[i]
            if not e then return end
            if btn == "RightButton" then
                if not e.follows then return end
                e.followOnly = (not e.followOnly) or nil
            else
                -- Candidates: every OTHER channelled spell, by key, in profile order. Deduplicated
                -- by key: e.follows stores a KEY, not a slot index, so two slots holding the same
                -- ability are one candidate (without this the forward search below always matches
                -- the FIRST duplicate and the cycle oscillates between two entries).
                local selfKey = PR.EntryKey(e)
                local cands, seen = {}, {}
                for j, o in ipairs(spells) do
                    local k = PR.EntryKey(o)
                    if j ~= i and k and k ~= selfKey and not seen[k] and o.channel
                            and not o.macroName and not o.itemID then
                        seen[k] = true
                        cands[#cands + 1] = k
                    end
                end
                if #cands == 0 and not e.follows then
                    VUI.Print("Priority Rotation",
                        VUI.COL.YELLOW .. "After|r waits for a channelled spell in this rotation, such as Eye Beam."
                        .. " Add one to the rotation first.")
                    return
                end
                local cur
                for idx, k in ipairs(cands) do
                    if k == e.follows then cur = idx; break end
                end
                -- none → first candidate → … → last candidate → none. A link to a target that is
                -- not (yet) a candidate steps to the first candidate, or to none if there is none.
                if cur then
                    e.follows = cands[cur + 1]   -- nil past the end = none
                else
                    e.follows = cands[1]
                end
                if not e.follows then e.followOnly = nil end
            end
            PR:SaveCurrentProfile(); editor:Refresh()
        end)
        followBtn:SetScript("OnEnter", function(self)
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local target = FindEntryByKey(e.follows)
            local me = EntryDisplayName(e)
            if target and target.channel then
                -- Blizzard's tooltip colours (owner, 2026-11-01): title white, description gold.
                GameTooltip:SetText(e.followOnly and "Only After" or "Also After", HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine(format(e.followOnly
                    and VUI.COL.HIGHLIGHT .. "%s|r is held until " .. VUI.COL.BRIGHTBLUE
                        .. "%s|r finishes channelling, then cast"
                        .. " on the next press. It is never cast on its own."
                    or  VUI.COL.HIGHLIGHT .. "%s|r is cast on the next press after " .. VUI.COL.BRIGHTBLUE
                        .. "%s|r finishes"
                        .. " channelling, and also at its normal frequency.",
                    me, EntryDisplayName(target)), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
            elseif target then
                GameTooltip:SetText("After", HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine(format("Not active: " .. VUI.COL.BRIGHTBLUE .. "%s|r is not a channelled spell,"
                    .. " and only a channel can be waited for. If it is one, cast it once and the"
                    .. " link turns on.", EntryDisplayName(target)),
                        RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
            else
                GameTooltip:SetText("After", HIGHLIGHT_FONT_COLOR:GetRGB())
                GameTooltip:AddLine("Not linked. Pick a channelled spell (such as Eye Beam) and this"
                    .. " ability is cast right after it finishes.",
                        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(e.follows and "Click to change · Right-click: Also / Only After"
                or "Click to pick", LIGHTBLUE_FONT_COLOR:GetRGB())
            GameTooltip:Show()
        end)
        followBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.followBtn = followBtn

        -- "Combat" (combat-only) checkbox — compiles [combat] into this entry's
        -- conditional (spell/trinket entries only; macro bodies are user-owned
        -- and untouched, so the box is hidden for macro entries). Replaces the
        -- user's hand-macro [combat, nochanneling] convention. The entry left
        -- unchecked is the opener: castable out of combat to start the fight.
        local combatChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        combatChk:SetSize(CHK_W, CHK_W)
        combatChk:SetPoint("LEFT", row, "LEFT", CHK_L, 0)     -- grid column 3
        combatChk:SetScript("OnClick", function(self)
            local e = PR:CurrentProfile().spells[i]
            if not e then return end
            e.combatOnly = self:GetChecked() and true or nil
            PR:SaveCurrentProfile(); editor:Refresh()
        end)
        combatChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Combat only", HIGHLIGHT_FONT_COLOR:GetRGB())
            GameTooltip:AddLine(
                "Checked: compiled with " .. VUI.COL.HIGHLIGHT .. "[combat]|r — this ability only"
                .. " casts while in combat. Leave your opener unchecked so a key"
                .. " press out of combat can start the fight.",
                    NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
            GameTooltip:Show()
        end)
        combatChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.combatChk = combatChk

        rows[i] = row
        VUI.AnnounceFrame("PriorityRotation.EditorRow", row)
    end

    -- ── Column headers ───────────────────────────────────────────────
    -- All anchored to rows[1]'s TOPLEFT for a CONSISTENT vertical baseline
    -- (anchoring to each column's TOP would put them at different heights
    -- because column heights differ: iconBtn=28, freqFrame=38, text=~12).
    --
    -- X offsets are hardcoded to match the row-column layout above:
    --   numLbl    LEFT=4,   width=18   → center=13
    --   iconBtn   LEFT=27,  width=28   → center=41
    --   nameLbl   LEFT=66,  width=146  → LEFT=66 (left-justified header)
    -- The three control columns sit on the computed equal-gap grid
    -- (FREQ_L / AFTER_L / CHK_L above) — headers center on element
    -- centers derived from the same constants, so they stay aligned
    -- for any panel width without hand-tuned offsets.
    local HEADER_Y = 6

    -- Each header explains its column on hover (v1.35.11). The wording is what the explainer
    -- paragraph and the Settings tab's "Rotation Columns" section used to say.
    local HEADER_TIPS = {
        ["#"]       = "Your rotation's slots, in order. Drag a slot up or down to move it.",
        Icon        = "Drag a spell from your spellbook, a macro from /macro or a trinket from your "
                      .."character pane onto a slot. Right-click a slot to remove it.",
        Ability     = "What is in the slot. " .. VUI.COL.LIGHTBLUE .. "[M]|r marks a macro, "
            .. VUI.COL.NORMAL .. "[T]|r a trinket.",
        Frequency   = "How often an ability is attempted relative to the others, spread as evenly as "
                      .."the numbers allow. 5 = attempted almost constantly (short cooldowns, spenders); "
                      .."1 = attempted rarely. It sets the spacing, not a literal count: back-to-back "
                      .."presses of the same ability are collapsed, so a high frequency buys shorter gaps "
                      .."rather than more steps. A not-ready attempt is skipped harmlessly, so err on the "
                      .."high side for important abilities.",
        After       = "Casts an ability on the next press after a channelled spell finishes, such as "
                      .."Essence Break after Eye Beam. Click a slot's box to pick the spell. Right-click "
                      .."for Only After (the lock): the ability is then held for it and never cast on "
                      .."its own.",
        Combat      = "Only cast in combat. Leave your opener unchecked so a key press can start the "
                      .."fight. Macros have no box: what they do is up to the macro.",
    }
    local function AddHeaderTip(fs, text)
        local tip = HEADER_TIPS[text]
        if not tip then return end
        local hit = CreateFrame("Frame", nil, parent)
        hit:SetPoint("TOPLEFT",     fs, "TOPLEFT",     -4,  3)
        hit:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT",  4, -3)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            -- Blizzard's tooltip colours (owner, 2026-11-01): the header's name white, its text gold.
            GameTooltip:SetText(text == "#" and "Order" or text, HIGHLIGHT_FONT_COLOR:GetRGB())
            GameTooltip:AddLine(tip, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fs.tipHit = hit
    end

    local function MakeCenteredHeader(xOff, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOM", rows[1], "TOPLEFT", xOff, HEADER_Y)
        fs:SetTextColor(NORMAL_FONT_COLOR:GetRGB())   -- Blizzard gold (owner, 2026-11-01)
        fs:SetText(text)
        AddHeaderTip(fs, text)
        return fs
    end

    MakeCenteredHeader(13,  "#")
    MakeCenteredHeader(41,  "Icon")
    local hAbility = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAbility:SetPoint("BOTTOMLEFT", rows[1], "TOPLEFT", 66, HEADER_Y)
    hAbility:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    hAbility:SetText("Ability")
    AddHeaderTip(hAbility, "Ability")
    MakeCenteredHeader(FREQ_L + FREQ_W / 2, "Frequency")
    MakeCenteredHeader(AFTER_L + AFTER_W / 2, "After")
    MakeCenteredHeader(CHK_L + CHK_W / 2, "Combat")
    editor.headerTips = HEADER_TIPS

    -- ── Sequence preview card ────────────────────────────────────
    -- Wraps the "Compiled Sequence:" header + preview text in a card
    -- with the rows' dark block art (PetList-ButtonBackground). Width is anchored to the last row's bottom
    -- corners: the right edge matches the rows, the left is inset 4 (below). The bottom
    -- edge anchors to parent's bottom so the card auto-fills the
    -- remaining vertical space, providing room for the scrollable
    -- preview text within. Empty rotation slots themselves accept
    -- drag-and-drop (spells/macros/trinkets), so no dedicated drop
    -- zone is needed — and the Spellbook / Macros buttons in the
    -- Settings tab cover the "open spellbook" affordance.
    local seqCard = CreateFrame("Frame", nil, parent)
    -- Left wall inset 4 px past the rows' left edge so the card sits 8 px from
    -- both panel borders (the right edge already matches the rows; owner's request).
    seqCard:SetPoint("TOPLEFT",  rows[PR.MAX_SLOTS], "BOTTOMLEFT",  4, -8)
    seqCard:SetPoint("TOPRIGHT", rows[PR.MAX_SLOTS], "BOTTOMRIGHT", 0, -8)
    seqCard:SetPoint("BOTTOM",   parent,             "BOTTOM",      0,  4)

    -- The same dark block as the rows (PetList-ButtonBackground), stretched to the card.
    local seqFill = seqCard:CreateTexture(nil, "BACKGROUND")
    seqFill:SetAtlas("PetList-ButtonBackground")
    seqFill:SetAllPoints()
    seqCard.cardArt = { seqFill }
    VUI.AnnounceFrame("PriorityRotation.SequenceCard", seqCard)

    -- Header at top of card with padding.
    local seqHeader = seqCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seqHeader:SetPoint("TOPLEFT", seqCard, "TOPLEFT", 6, -6)
    seqHeader:SetText("Compiled Sequence:")   -- GameFontNormalSmall: Blizzard gold

    -- Scrollable preview area — plain ScrollFrame with mousewheel.
    -- MinimalScrollBar is designed for lists (AO Browser/Featured),
    -- not single text blocks — WowScrollBoxList can't scroll WITHIN
    -- a single oversized element, only BETWEEN elements. For a
    -- wrapped paragraph, the bare ScrollFrame + mousewheel pattern
    -- is cleaner and actually scrollable.
    local seqScroll = CreateFrame("ScrollFrame", nil, seqCard)
    seqScroll:SetPoint("TOPLEFT",     seqHeader, "BOTTOMLEFT",  0, -2)
    seqScroll:SetPoint("BOTTOMRIGHT", seqCard,   "BOTTOMRIGHT", -8, 6)
    seqScroll:EnableMouseWheel(true)

    local seqScrollChild = CreateFrame("Frame", nil, seqScroll)
    seqScrollChild:SetSize(1, 1)
    seqScroll:SetScrollChild(seqScrollChild)

    local function UpdateSeqScrollChildWidth()
        local w = seqScroll:GetWidth()
        if w and w > 0 then seqScrollChild:SetWidth(w) end
    end
    seqScroll:HookScript("OnSizeChanged", UpdateSeqScrollChildWidth)
    C_Timer.After(0, UpdateSeqScrollChildWidth)

    seqScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local max = self:GetVerticalScrollRange() or 0
        local newVal = cur - (delta * 18)
        if newVal < 0 then newVal = 0 end
        if newVal > max then newVal = max end
        self:SetVerticalScroll(newVal)
    end)

    local seqPreview = seqScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seqPreview:SetPoint("TOPLEFT",  seqScrollChild, "TOPLEFT",  0, 0)
    seqPreview:SetPoint("TOPRIGHT", seqScrollChild, "TOPRIGHT", 0, 0)
    seqPreview:SetJustifyH("LEFT")
    seqPreview:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())   -- panel body: white (owner, 2026-11-01)

    -- ── Drag to reorder ──────────────────────────────────────
    -- The slot under the cursor; above the first row counts as slot 1, below the last as the last
    -- filled slot. Rows are fixed frames, so their screen bounds are read directly.
    local function SlotUnderCursor(numSpells)
        local _, cy = GetCursorPosition()
        local scale = rows[1]:GetEffectiveScale()
        if not cy or not scale or scale == 0 then return nil end
        cy = cy / scale
        local top1, bottomN = rows[1]:GetTop(), rows[PR.MAX_SLOTS]:GetBottom()
        if top1 and cy > top1 then return 1 end
        for k = 1, PR.MAX_SLOTS do
            local t, b = rows[k]:GetTop(), rows[k]:GetBottom()
            -- Each row also owns the 4 px gap above it, so no point between rows is a dead zone.
            if t and b and cy <= t + 4 and cy >= b then return math.min(k, numSpells) end
        end
        if bottomN and cy < bottomN then return numSpells end
        return nil
    end

    editor.rows = rows
    local dragDriver = CreateFrame("Frame", nil, parent)
    dragDriver:Hide()
    local dragFrom, dragTo

    local function ShowMark(slot)
        for k = 1, PR.MAX_SLOTS do rows[k].dropMark:SetShown(k == slot) end
    end

    dragDriver:SetScript("OnUpdate", function()
        local n = #PR:CurrentProfile().spells
        dragTo = SlotUnderCursor(n) or dragTo
        ShowMark(dragTo)
    end)

    function editor:StartReorder(from)
        local spells = PR:CurrentProfile().spells
        if not spells[from] or #spells < 2 then return end
        dragFrom, dragTo = from, from
        GameTooltip:Hide()
        rows[from]:SetAlpha(0.5)
        ShowMark(from)
        dragDriver:Show()
    end

    function editor:FinishReorder()
        if not dragFrom then return end
        dragDriver:Hide()
        local from = dragFrom
        dragFrom = nil
        rows[from]:SetAlpha(1)
        ShowMark(nil)
        local spells = PR:CurrentProfile().spells
        local to = SlotUnderCursor(#spells) or dragTo
        if to and to ~= from and spells[from] then
            -- "After" links store the target's KEY, not its slot, so they survive the move.
            local entry = table.remove(spells, from)
            table.insert(spells, math.max(1, math.min(to, #spells + 1)), entry)
            PR:SaveCurrentProfile()
        end
        editor:Refresh()
    end

    -- A drag cut short by the window closing ends without moving anything.
    parent:HookScript("OnHide", function()
        if dragFrom then
            dragDriver:Hide()
            rows[dragFrom]:SetAlpha(1)
            dragFrom = nil
            ShowMark(nil)
        end
    end)

    -- ── Refresh ──────────────────────────────────────────────
    function editor:Refresh()
        local spells = PR:CurrentProfile().spells
        for i = 1, PR.MAX_SLOTS do
            local row = rows[i]
            local e   = spells[i]
            if e and (e.spellID or e.macroName or e.itemID) then
                -- Refresh icon: for macros, re-read the current macro icon;
                -- for items, refresh icon from C_Item.GetItemInfo (in case
                -- the item got upgraded / changed quality).
                local displayIcon = e.icon
                if e.macroName then
                    local _, freshIcon = GetMacroInfo(e.macroName)
                    if freshIcon then
                        displayIcon = freshIcon
                        e.icon = freshIcon
                    end
                elseif e.itemID then
                    -- C_Item.GetItemInfo may return Secret Values in raid
                    -- encounters; guard the call. Refresh is purely cosmetic
                    -- — failure silently keeps the cached e.icon.
                    local ok, _, _, _, _, _, _, _, _, _, freshIcon =
                        pcall(C_Item.GetItemInfo, e.itemID)
                    if ok and freshIcon then
                        displayIcon = freshIcon
                        e.icon = freshIcon
                    end
                end
                row.iconBtn.tex:SetTexture(displayIcon)
                row.iconBtn.tex:Show()
                row.iconBtn.empty:Hide()
                local displayName = e.spellName or e.macroName or e.itemName
                if e.macroName then
                    -- Light-blue [M] tag (LIGHTBLUE_FONT_COLOR since the v1.58 colour sweep; it was cyan).
                    displayName = VUI.COL.LIGHTBLUE .. "[M]|r " .. e.macroName
                elseif e.itemID then
                    -- Gold [T] tag (NORMAL_FONT_COLOR) for "Trinket" — distinct from spells
                    -- (no tag, white) and macros (light-blue [M]). The trinket
                    -- name itself stays white for readability against the
                    -- dark row background.
                    displayName = VUI.COL.NORMAL .. "[T]|r " .. e.itemName
                end
                row.nameLbl:SetText(displayName)
                row.freqLbl:SetText("x" .. (e.freq or 1))
                -- At the limits the arrow shows Blizzard's disabled art and stops taking clicks.
                row.decBtn:SetEnabled((e.freq or 1) > 1)
                row.incBtn:SetEnabled((e.freq or 1) < 5)
                row.freqFrame:Show()
                -- "After" indicator: target's icon when the link resolves;
                -- dimmed empty slot when unset (or the target was removed —
                -- the stored key is kept, so re-adding the target relinks).
                -- Grey icon: the target is there but not yet seen channelling (link inactive).
                local target = FindEntryByKey(e.follows, spells)
                if target and target.icon then
                    row.followBtn.tex:SetTexture(target.icon)
                    row.followBtn.tex:SetDesaturated(not target.channel)
                    row.followBtn.tex:Show()
                    row.followBtn.empty:Hide()
                else
                    row.followBtn.tex:Hide()
                    row.followBtn.empty:Show()
                end
                row.followBtn.lock:SetShown(target and e.followOnly and true or false)
                row.followBtn:Show()
                -- Combat gate applies only to entries PR compiles itself
                -- (spells/trinkets); macro bodies are user-owned, so no box.
                if e.macroName then
                    row.combatChk:Hide()
                else
                    row.combatChk:SetChecked(e.combatOnly and true or false)
                    row.combatChk:Show()
                end
            else
                row.iconBtn.tex:Hide()
                row.iconBtn.empty:Show()
                row.nameLbl:SetText(VUI.COL.DISABLED .. "-- empty --|r")
                row.freqFrame:Hide()
                row.followBtn:Hide()
                row.combatChk:Hide()
            end
        end
        if #PR.compiledSequence > 0 then
            local displayNames = {}
            for idx, cast in ipairs(PR.compiledSequence) do
                local n = PR.compiledNames and PR.compiledNames[idx]
                if n then
                    -- Compact wrappers for the preview line:
                    --   [MACRO:Name] → [M:Name]
                    --   [ITEM:Name]  → [T:Name]
                    local mTag = n:match("^%[MACRO:(.-)%]$")
                    local iTag = n:match("^%[ITEM:(.-)%]$")
                    if mTag then
                        displayNames[#displayNames + 1] = "[M:" .. mTag .. "]"
                    elseif iTag then
                        displayNames[#displayNames + 1] = "[T:" .. iTag .. "]"
                    else
                        displayNames[#displayNames + 1] = n
                    end
                else
                    displayNames[#displayNames + 1] = cast:gsub("^/cast ", ""):gsub("^/use ", "")
                end
            end
            seqPreview:SetText(table.concat(displayNames, " > ") .. AfterLinksText())
        else
            local links = AfterLinksText()
            seqPreview:SetText(links ~= "" and links:gsub("^\n\n", "")
                or VUI.COL.GRAY .. "(empty -- add spells above)|r")
        end
        -- Resize the scroll child to fit the wrapped text so mousewheel
        -- scrolling works when the sequence overflows the card.
        seqScrollChild:SetHeight(math.max(seqPreview:GetStringHeight() + 4, 1))
    end

    PR.Editor = editor
    return editor
end