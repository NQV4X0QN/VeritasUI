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
local PNL_H = 420

-- All created dropdown frames, for RefreshConfigPanel
local dropdownEntries = {}   -- { barKey, slotIdx, dd }

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
----------------------------------------------------------------
local function MakeDropdown(parent, barKey, slotIdx, xOff, yOff, ddWidth)
    local ddName = format("VUI_HUD_DD_%s_%d", barKey, slotIdx)
    local dd = CreateFrame("Frame", ddName, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    UIDropDownMenu_SetWidth(dd, ddWidth or 140)

    UIDropDownMenu_Initialize(dd, function(ddFrame, level)
        local dp = HUF.DataPoints
        if not dp then return end
        local capturedDD  = ddFrame
        local capturedBar = barKey
        local capturedSlot = slotIdx
        for _, k in ipairs(GetSortedKeys()) do
            local info = {}
            info.text    = dp[k] and dp[k].label or k
            info.value   = k
            info.func    = function(btn)
                UIDropDownMenu_SetSelectedValue(capturedDD, btn.value)
                UIDropDownMenu_SetText(capturedDD, btn.text)
                local layout = HUF.db and HUF.db.layout
                if layout and layout[capturedBar] then
                    layout[capturedBar][capturedSlot] = btn.value
                end
                if HUF.RebuildAllBars then HUF.RebuildAllBars() end
            end
            info.checked  = (UIDropDownMenu_GetSelectedValue(ddFrame) == k)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Set initial displayed value
    local layout = HUF.db and HUF.db.layout
    local initKey = layout and layout[barKey] and layout[barKey][slotIdx]
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

    -- Slot rows
    for i = 1, numSlots do
        local rowY = -6 - (i - 1) * SLOT_ROW_H   -- offset from sep's BOTTOMLEFT

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 4, rowY)
        lbl:SetText("Slot " .. i)
        lbl:SetTextColor(0.9, 0.9, 0.9)

        -- Dropdown positioned to the right of label; y+4 to vertically center with label
        MakeDropdown(parent, barKey, i, hdrX + 48, hdrY - 20 - (i - 1) * SLOT_ROW_H, ddW or 140)
    end

    return sep
end

----------------------------------------------------------------
--  Build the center bar section (5 slots in a horizontal row)
----------------------------------------------------------------
local CENTER_SLOT_W = 96   -- width per slot column (5 × 96 = 480 < 506 content width)

local function BuildCenterSection(parent, hdrY)
    local hdr = parent:CreateFontString(nil, "OVERLAY")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 13)
    hdr:SetTextColor(1, 0.82, 0)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, hdrY)
    hdr:SetText("Center Bar")

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetWidth(500)
    sep:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -3)
    sep:SetColorTexture(1, 0.82, 0, 0.5)

    for i = 1, 5 do
        local xPos = 4 + (i - 1) * CENTER_SLOT_W

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", xPos, -6)
        lbl:SetText("Slot " .. i)
        lbl:SetTextColor(0.9, 0.9, 0.9)

        MakeDropdown(parent, "centerBar", i, xPos - 14, hdrY - 22, 70)
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

    win.TitleText:SetText("HUD Frame — Layout Configuration")

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

    -- ── Center Bar section (lower half, horizontal row) ───────
    -- Top of center section is below the 3-slot left/right sections.
    -- 3 rows × SLOT_ROW_H + header+sep ≈ 90+30 = ~120px from top
    local centerY = -8 - 20 - 3 * SLOT_ROW_H - 20   -- header(20) + 3 rows + gap
    BuildCenterSection(CONT, centerY)

    -- ── Bottom buttons ────────────────────────────────────────
    local resetBtn = CreateFrame("Button", nil, CONT, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("BOTTOMLEFT", CONT, "BOTTOMLEFT", 4, 8)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        local db = HUF.db
        if db then db.layout = nil end
        if HUF.RebuildAllBars then HUF.RebuildAllBars() end
        if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
        VUI.Print("HUD Frame", "|cffffd100Layout reset to defaults.|r")
    end)

    HUF.ConfigPanel = win
end

----------------------------------------------------------------
--  RefreshConfigPanel — syncs dropdown displays to current layout
----------------------------------------------------------------
function HUF.RefreshConfigPanel()
    local db = HUF.db
    if not db or not db.layout then return end
    local dp = HUF.DataPoints
    for _, entry in ipairs(dropdownEntries) do
        local layout = db.layout[entry.barKey]
        local key    = layout and layout[entry.slotIdx]
        if key and dp and dp[key] then
            UIDropDownMenu_SetSelectedValue(entry.dd, key)
            UIDropDownMenu_SetText(entry.dd, dp[key].label)
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
