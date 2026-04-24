-- VeritasUI_HUDFrame / SettingsPanel.lua
-- Layout configuration panel (standalone window, /hud config).
-- Modeled on PriorityRotation / Settings.lua BuildMainWindow pattern.

local _, HUF = ...

local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame   = CreateFrame
local C_Timer       = C_Timer
local ipairs, pairs = ipairs, pairs
local format        = string.format

local PNL_W = 520
local PNL_H = 1000

-- All created dropdown frames, for RefreshConfigPanel
local dropdownEntries = {}   -- { barKey, slotIdx, dd }

-- Panel bar width slider references, keyed by bar index. Populated by
-- BuildSizesSection and read by BuildPanelSection's mode dropdown callback
-- (for Enable/Disable) as well as RefreshConfigPanel.
local widthSliderRefs = {}   -- { [1]=slider, [2]=slider, [3]=slider }

-- Per-panel-bar slot-editor container frames. Each panel section has two
-- stacked containers at the same position; mode toggles visibility.
local normalSlotContainers = {}   -- [barIdx] = Frame (5 slot dropdowns)
local zoneSlotContainers   = {}   -- [barIdx] = Frame (3 rows × 4 dropdowns)

----------------------------------------------------------------
--  Sorted data point key list
----------------------------------------------------------------
local function GetSortedKeys()
    local dp = HUF.DataPoints
    if not dp then return {} end
    local keys = {}
    for k in pairs(dp) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

----------------------------------------------------------------
--  Create one slot dropdown
--  barKey conventions:
--    "leftBar" / "rightBar"        — writes to db.layout[barKey][slot]
--    "panelBar<N>" (1..3)          — writes to db.layout.panelBars[N][slot]
--    "panelBar<N>Zone<L|C|R>"      — writes to
--                                    db.layout.panelBarZones[N].<zone>[slot]
----------------------------------------------------------------
local function GetLayoutSlots(barKey)
    local layout = HUF.db and HUF.db.layout
    if not layout then return nil end

    -- Zone key: panelBar<N>Zone<Left|Center|Right>
    local zIdx, zName = barKey:match("^panelBar(%d)Zone(%a+)$")
    if zIdx and zName then
        zIdx = tonumber(zIdx)
        local zone = zName:lower()
        if not layout.panelBarZones then layout.panelBarZones = {} end
        if not layout.panelBarZones[zIdx] then
            layout.panelBarZones[zIdx] = { left = {}, center = {}, right = {} }
        end
        if not layout.panelBarZones[zIdx][zone] then
            layout.panelBarZones[zIdx][zone] = {}
        end
        return layout.panelBarZones[zIdx][zone]
    end

    -- Normal panel bar: panelBar<N>
    local idx = tonumber(barKey:match("^panelBar(%d)$"))
    if idx then
        if not layout.panelBars then layout.panelBars = {} end
        if not layout.panelBars[idx] then layout.panelBars[idx] = {} end
        return layout.panelBars[idx]
    end

    return layout[barKey]
end

local function MakeDropdown(parent, barKey, slotIdx, xOff, yOff, ddWidth)
    local ddName = format("VUI_HUD_DD_%s_%d", barKey, slotIdx)
    local dd = CreateFrame("Frame", ddName, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    UIDropDownMenu_SetWidth(dd, ddWidth or 140)

    UIDropDownMenu_Initialize(dd, function(ddFrame, level)
        local dp = HUF.DataPoints
        if not dp then return end
        local capturedDD   = ddFrame
        local capturedBar  = barKey
        local capturedSlot = slotIdx
        for _, k in ipairs(GetSortedKeys()) do
            local info = {}
            info.text    = dp[k] and dp[k].label or k
            info.value   = k
            info.func    = function(btn)
                UIDropDownMenu_SetSelectedValue(capturedDD, btn.value)
                UIDropDownMenu_SetText(capturedDD, btn.text)
                local slots = GetLayoutSlots(capturedBar)
                if slots then slots[capturedSlot] = btn.value end
                if HUF.RebuildAllBars then HUF.RebuildAllBars() end
            end
            info.checked  = (UIDropDownMenu_GetSelectedValue(ddFrame) == k)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Set initial displayed value
    local slots = GetLayoutSlots(barKey)
    local initKey = slots and slots[slotIdx]
    if initKey and HUF.DataPoints and HUF.DataPoints[initKey] then
        UIDropDownMenu_SetSelectedValue(dd, initKey)
        UIDropDownMenu_SetText(dd, HUF.DataPoints[initKey].label)
    end

    dropdownEntries[#dropdownEntries + 1] = { barKey = barKey, slotIdx = slotIdx, dd = dd }
    return dd
end

----------------------------------------------------------------
--  Section builder — header + separator + slot rows (vertical)
----------------------------------------------------------------
local SLOT_ROW_H = 30   -- pixels per slot row

local function BuildSection(parent, barKey, numSlots, hdrText, hdrX, hdrY, secW, ddW)
    -- Header
    local hdr = parent:CreateFontString(nil, "OVERLAY")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 13)
    hdr:SetTextColor(1, 0.82, 0)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", hdrX, hdrY)
    hdr:SetText(hdrText)

    -- Separator line
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetWidth(secW)
    sep:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -3)
    sep:SetColorTexture(1, 0.82, 0, 0.5)

    -- Slot rows — label and dropdown both derive Y from rowY so that edits
    -- to spacing track consistently between the two.
    for i = 1, numSlots do
        local rowY = -6 - (i - 1) * SLOT_ROW_H

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 4, rowY)
        lbl:SetText("Slot " .. i)
        lbl:SetTextColor(0.9, 0.9, 0.9)

        -- Dropdown anchors to parent TOPLEFT (original behaviour); Y is
        -- derived from rowY so label and dropdown move together. The -14
        -- visually centers the dropdown with the label text.
        MakeDropdown(parent, barKey, i, hdrX + 48, hdrY + rowY - 14, ddW or 140)
    end

    return sep
end

----------------------------------------------------------------
--  Build one panel bar section (5 slots in a horizontal row)
----------------------------------------------------------------
local PANEL_SLOT_W    = 96    -- width per slot column (5 × 96 = 480 < 506 content width)
local PANEL_SECTION_H = 150   -- height of one panel-bar section (header + sep + 3 zone rows + margin)
local ZONE_ROW_H      = 32    -- pixels per zone row (Left / Center / Right)

local function BuildPanelSection(parent, barIdx, hdrY)
    local barKey = "panelBar" .. barIdx
    local hdr = parent:CreateFontString(nil, "OVERLAY")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 13)
    hdr:SetTextColor(1, 0.82, 0)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, hdrY)
    hdr:SetText("Panel Bar " .. barIdx)

    -- Mode dropdown on the header row (right side)
    local modeLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 290, hdrY)
    modeLbl:SetText("Mode:")
    modeLbl:SetTextColor(0.9, 0.9, 0.9)

    local modeDD = CreateFrame("Frame",
        format("VUI_HUD_DD_PanelMode_%d", barIdx),
        parent, "UIDropDownMenuTemplate")
    modeDD:SetPoint("TOPLEFT", parent, "TOPLEFT", 320, hdrY + 4)
    UIDropDownMenu_SetWidth(modeDD, 110)

    local capturedIdx = barIdx
    UIDropDownMenu_Initialize(modeDD, function(_, level)
        for _, m in ipairs({ "normal", "fullwidth" }) do
            local info = {}
            info.text  = (m == "normal") and "Normal" or "Full-width"
            info.value = m
            info.func  = function(btn)
                UIDropDownMenu_SetSelectedValue(modeDD, btn.value)
                UIDropDownMenu_SetText(modeDD,
                    btn.value == "normal" and "Normal" or "Full-width")
                local db = HUF.db
                if not db then return end
                db.panelBars = db.panelBars or {}
                db.panelBars[capturedIdx] = db.panelBars[capturedIdx] or {}
                db.panelBars[capturedIdx].mode = btn.value
                if HUF.ApplyPanelBarMode then
                    HUF.ApplyPanelBarMode(capturedIdx)
                end
                -- Swap the slot-editor containers to match the new mode
                if normalSlotContainers[capturedIdx]
                   and zoneSlotContainers[capturedIdx] then
                    if btn.value == "fullwidth" then
                        normalSlotContainers[capturedIdx]:Hide()
                        zoneSlotContainers[capturedIdx]:Show()
                    else
                        zoneSlotContainers[capturedIdx]:Hide()
                        normalSlotContainers[capturedIdx]:Show()
                    end
                end
                -- Width slider is meaningless in fullwidth mode; reflect that.
                if widthSliderRefs[capturedIdx] then
                    if btn.value == "fullwidth" then
                        widthSliderRefs[capturedIdx]:Disable()
                    else
                        widthSliderRefs[capturedIdx]:Enable()
                    end
                end
            end
            info.checked =
                (UIDropDownMenu_GetSelectedValue(modeDD) == m)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Set initial display to match current DB mode
    local db = HUF.db
    local initMode = (db and db.panelBars and db.panelBars[barIdx]
                      and db.panelBars[barIdx].mode) or "normal"
    UIDropDownMenu_SetSelectedValue(modeDD, initMode)
    UIDropDownMenu_SetText(modeDD,
        initMode == "normal" and "Normal" or "Full-width")

    -- Separator below header
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetWidth(500)
    sep:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -3)
    sep:SetColorTexture(1, 0.82, 0, 0.5)

    -- ── Normal slot container (5 slots in a single row) ──
    -- Anchored below sep; only one container is shown at a time.
    local normalContainer = CreateFrame("Frame", nil, parent)
    normalContainer:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, 0)
    normalContainer:SetSize(500, ZONE_ROW_H)
    for i = 1, 5 do
        local xPos = 4 + (i - 1) * PANEL_SLOT_W
        local lbl = normalContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", normalContainer, "TOPLEFT", xPos, -6)
        lbl:SetText("Slot " .. i)
        lbl:SetTextColor(0.9, 0.9, 0.9)
        MakeDropdown(normalContainer, barKey, i, xPos - 14, -22, 70)
    end
    normalSlotContainers[barIdx] = normalContainer

    -- ── Zone slot container (3 rows × 4 slots) ──
    local zoneContainer = CreateFrame("Frame", nil, parent)
    zoneContainer:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, 0)
    zoneContainer:SetSize(500, 3 * ZONE_ROW_H)
    for rowIdx, zoneName in ipairs({ "Left", "Center", "Right" }) do
        local rowY = -6 - (rowIdx - 1) * ZONE_ROW_H

        local rowLbl = zoneContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rowLbl:SetPoint("TOPLEFT", zoneContainer, "TOPLEFT", 4, rowY)
        rowLbl:SetText(zoneName .. ":")
        rowLbl:SetTextColor(0.9, 0.9, 0.9)

        local zoneBarKey = format("panelBar%dZone%s", barIdx, zoneName)
        for slot = 1, 4 do
            -- 4 dropdowns spaced 110px apart starting after the label
            local xPos = 50 + (slot - 1) * 110
            MakeDropdown(zoneContainer, zoneBarKey, slot,
                xPos - 14, rowY - 4, 80)
        end
    end
    zoneSlotContainers[barIdx] = zoneContainer

    -- Initial visibility: show the container matching the bar's current mode
    if initMode == "fullwidth" then
        normalContainer:Hide()
        zoneContainer:Show()
    else
        zoneContainer:Hide()
        normalContainer:Show()
    end
end

----------------------------------------------------------------
--  Frame Sizes section — sliders for anchor and panel bar dimensions
----------------------------------------------------------------
local SLIDER_W   = 220
local LEFT_COL   = 4
local RIGHT_COL  = 264

local function MakeSlider(parent, frameName, x, yFromSep, sep, w, minVal, maxVal, step, initVal, labelFmt, onChange)
    local slider = CreateFrame("Slider", frameName, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", x, yFromSep)
    slider:SetWidth(w)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))
    slider:SetScript("OnValueChanged", function(self, val, userInput)
        self.Text:SetText(format(labelFmt, val))
        if not userInput then return end
        if onChange then onChange(val) end
    end)
    slider:SetValue(initVal)
    return slider
end

local function BuildSizesSection(parent, startY)
    local db = HUF.db

    local hdr = parent:CreateFontString(nil, "OVERLAY")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 13)
    hdr:SetTextColor(1, 0.82, 0)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_COL, startY)
    hdr:SetText("Frame Sizes")

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetWidth(500)
    sep:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -3)
    sep:SetColorTexture(1, 0.82, 0, 0.5)

    -- Sub-headers
    local leftLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    leftLbl:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", LEFT_COL, -8)
    leftLbl:SetText("Left Chat Frame")
    leftLbl:SetTextColor(0.9, 0.9, 0.9)

    local rightLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rightLbl:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", RIGHT_COL, -8)
    rightLbl:SetText("Right Chat Frame")
    rightLbl:SetTextColor(0.9, 0.9, 0.9)

    local lw = (db and db.leftAnchorWidth)   or 380
    local lh = (db and db.leftAnchorHeight)  or 220
    local rw = (db and db.rightAnchorWidth)  or 380
    local rh = (db and db.rightAnchorHeight) or 220

    -- Width sliders (left / right)
    MakeSlider(parent, "VUI_HUD_Slider_LeftW",  LEFT_COL,  -52, sep, SLIDER_W,
        200, 700, 10, lw, "Width: %dpx",
        function(val)
            if HUF.db then HUF.db.leftAnchorWidth = val end
            if HUF.leftAnchor then HUF.leftAnchor:SetWidth(val) end
        end)

    MakeSlider(parent, "VUI_HUD_Slider_RightW", RIGHT_COL, -52, sep, SLIDER_W,
        200, 700, 10, rw, "Width: %dpx",
        function(val)
            if HUF.db then HUF.db.rightAnchorWidth = val end
            if HUF.rightAnchor then HUF.rightAnchor:SetWidth(val) end
        end)

    -- Height sliders (left / right)
    MakeSlider(parent, "VUI_HUD_Slider_LeftH",  LEFT_COL,  -114, sep, SLIDER_W,
        80, 500, 10, lh, "Height: %dpx",
        function(val)
            if HUF.db then HUF.db.leftAnchorHeight = val end
            if HUF.leftAnchor then HUF.leftAnchor:SetHeight(val) end
        end)

    MakeSlider(parent, "VUI_HUD_Slider_RightH", RIGHT_COL, -114, sep, SLIDER_W,
        80, 500, 10, rh, "Height: %dpx",
        function(val)
            if HUF.db then HUF.db.rightAnchorHeight = val end
            if HUF.rightAnchor then HUF.rightAnchor:SetHeight(val) end
        end)

    -- Panel bar width sliders (three, stacked)
    local panelLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panelLbl:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", LEFT_COL, -170)
    panelLbl:SetText("Panel Bars")
    panelLbl:SetTextColor(0.9, 0.9, 0.9)

    local panelYBase = -200
    for i = 1, 3 do
        local pw_i = (db and db.panelBarWidth and db.panelBarWidth[i]) or 500
        local capturedIdx = i
        local slider = MakeSlider(parent, "VUI_HUD_Slider_PanelW" .. i,
            LEFT_COL, panelYBase - (i - 1) * 32, sep, 460,
            300, 1200, 10, pw_i,
            "Panel Bar " .. i .. " Width: %dpx",
            function(val)
                if HUF.db and HUF.db.panelBarWidth then
                    HUF.db.panelBarWidth[capturedIdx] = val
                end
                if HUF.panelBars and HUF.panelBars[capturedIdx] then
                    HUF.panelBars[capturedIdx]:SetWidth(val)
                    if HUF.RebuildAllBars then HUF.RebuildAllBars() end
                end
            end)
        widthSliderRefs[i] = slider
        -- Disable slider if the bar is currently in fullwidth mode.
        -- Width is still persisted; it just has no visible effect until
        -- the bar returns to normal mode.
        local mode = (db and db.panelBars and db.panelBars[i]
                      and db.panelBars[i].mode) or "normal"
        if mode == "fullwidth" then slider:Disable() end
    end
end

----------------------------------------------------------------
--  Build the panel
----------------------------------------------------------------
local function BuildConfigPanel()
    local win = CreateFrame("Frame", "VeritasUI_HUDFrameSettingsPanel", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(win)
    win:SetSize(PNL_W, PNL_H)
    win:SetPoint("CENTER")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop",  win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    win:Hide()
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)

    if win.TitleContainer and win.TitleContainer.TitleText then
        win.TitleContainer.TitleText:SetText("HUD Frame — Layout Configuration")
    elseif win.TitleText then
        win.TitleText:SetText("HUD Frame — Layout Configuration")
    end

    win.CloseButton:SetScript("OnClick", function() win:Hide() end)

    -- Register with UISpecialFrames so Escape closes it
    table.insert(UISpecialFrames, "VeritasUI_HUDFrameSettingsPanel")

    -- Content area — 12px inset sides, 32px from top to clear title bar
    local CONT = CreateFrame("Frame", nil, win)
    CONT:SetPoint("TOPLEFT",     win, "TOPLEFT",     8,  -32)
    CONT:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6,    6)

    -- ── Left Bar section (top-left quadrant) ─────────────────
    BuildSection(CONT, "leftBar",  3, "Left Bar",  4, -8, 240, 140)

    -- ── Right Bar section (top-right quadrant) ────────────────
    BuildSection(CONT, "rightBar", 3, "Right Bar", 264, -8, 240, 140)

    -- ── Three Panel Bar sections (lower half, each a horizontal row) ─
    -- Top of panel section is below the 3-slot left/right sections.
    -- 3 rows × SLOT_ROW_H + header+sep ≈ 90+30 = ~120px from top
    local panel1Y = -8 - 20 - 3 * SLOT_ROW_H - 20   -- header(20) + 3 rows + gap
    BuildPanelSection(CONT, 1, panel1Y)
    BuildPanelSection(CONT, 2, panel1Y - PANEL_SECTION_H)
    BuildPanelSection(CONT, 3, panel1Y - PANEL_SECTION_H * 2)

    -- ── Frame Sizes section (below all three panel sections) ──
    BuildSizesSection(CONT, panel1Y - PANEL_SECTION_H * 3)

    -- ── Bottom buttons ────────────────────────────────────────
    local resetBtn = CreateFrame("Button", nil, CONT, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("BOTTOMLEFT", CONT, "BOTTOMLEFT", 4, 8)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        local db = HUF.db
        if db then
            db.layout = nil
            -- Also reset per-bar mode so the UI matches fresh-install state
            if db.panelBars then
                for i = 1, 3 do
                    if db.panelBars[i] then
                        db.panelBars[i].mode = "normal"
                    end
                end
            end
        end
        if HUF.SeedDefaultPanelBarZones then HUF.SeedDefaultPanelBarZones() end
        if HUF.RebuildAllBars then HUF.RebuildAllBars() end
        if HUF.panelBars then
            for i = 1, 3 do
                if HUF.ApplyPanelBarMode then HUF.ApplyPanelBarMode(i) end
            end
        end
        if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
        VUI.Print("HUD Frame", "|cffffd100Layout reset to defaults.|r")
    end)

    HUF.ConfigPanel = win
end

----------------------------------------------------------------
--  RefreshConfigPanel — syncs dropdowns, mode selectors, slot-editor
--  container visibility, and width-slider enable state to the current DB.
----------------------------------------------------------------
function HUF.RefreshConfigPanel()
    local db = HUF.db
    if not db or not db.layout then return end
    local dp = HUF.DataPoints

    -- Slot dropdowns (normal-mode slot lists AND zone dropdowns — routed
    -- through GetLayoutSlots which handles both shapes)
    for _, entry in ipairs(dropdownEntries) do
        local slots = GetLayoutSlots(entry.barKey)
        local key   = slots and slots[entry.slotIdx]
        if key and dp and dp[key] then
            UIDropDownMenu_SetSelectedValue(entry.dd, key)
            UIDropDownMenu_SetText(entry.dd, dp[key].label)
        else
            -- Zone dropdowns are allowed to be empty; clear stale text.
            if entry.barKey:match("^panelBar%dZone%a+$") then
                UIDropDownMenu_SetText(entry.dd, "")
            end
        end
    end

    -- Per-panel-bar UI state: mode dropdown, container visibility,
    -- and width slider enable state.
    for i = 1, 3 do
        local mode = (db.panelBars and db.panelBars[i]
                      and db.panelBars[i].mode) or "normal"

        local modeDD = _G["VUI_HUD_DD_PanelMode_" .. i]
        if modeDD then
            UIDropDownMenu_SetSelectedValue(modeDD, mode)
            UIDropDownMenu_SetText(modeDD,
                mode == "normal" and "Normal" or "Full-width")
        end

        -- Swap the slot-editor containers to match the current mode.
        if normalSlotContainers[i] and zoneSlotContainers[i] then
            if mode == "fullwidth" then
                normalSlotContainers[i]:Hide()
                zoneSlotContainers[i]:Show()
            else
                zoneSlotContainers[i]:Hide()
                normalSlotContainers[i]:Show()
            end
        end

        if widthSliderRefs[i] then
            if mode == "fullwidth" then
                widthSliderRefs[i]:Disable()
            else
                widthSliderRefs[i]:Enable()
            end
        end
    end
end

----------------------------------------------------------------
--  Toggle
----------------------------------------------------------------
function HUF.ToggleConfigPanel()
    if not HUF.ConfigPanel then return end
    if HUF.ConfigPanel:IsShown() then
        HUF.ConfigPanel:Hide()
    else
        if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
        HUF.ConfigPanel:Show()
    end
end

----------------------------------------------------------------
--  Startup (PLAYER_LOGIN, after Core.lua and DataText.lua)
----------------------------------------------------------------
local spFrame = CreateFrame("Frame")
spFrame:RegisterEvent("PLAYER_LOGIN")
spFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local ok, err = pcall(BuildConfigPanel)
    if not ok then
        VUI.Print("HUD Frame", "|cFFFF4444Config panel error:|r " .. tostring(err))
    end
end)
