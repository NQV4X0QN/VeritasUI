-- VeritasUI_AdvancedOptions / Controls.lua
-- Factory functions for native-looking CVar controls.
--
-- Each factory returns the outermost frame so callers can anchor it.
-- All controls read their initial value from C_CVar on creation and
-- write back via AO:SetCVar on user interaction.

local ADDON_NAME, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G             = _G
local pcall          = pcall
local tonumber       = tonumber
local format         = string.format
local math_floor     = math.floor
local math_max       = math.max
local math_min       = math.min
local CreateFrame    = CreateFrame
local C_CVar         = C_CVar
local GameTooltip    = GameTooltip

----------------------------------------------------------------
--  Shared style constants
----------------------------------------------------------------
local ROW_HEIGHT     = 26
local LABEL_WIDTH    = 260
local RESET_SIZE     = 14

----------------------------------------------------------------
--  Tooltip helper
----------------------------------------------------------------
local function ShowTooltip(owner, title, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then
        GameTooltip:AddLine(body, 0.75, 0.75, 0.75, true)
    end
    GameTooltip:Show()
end

----------------------------------------------------------------
--  Reset-to-default button (shared across control types)
--
--  Small revert icon that resets a single CVar to its default.
--  Uses a texture atlas for the icon (no Unicode dependency).
--  The onReset callback lets the owning control refresh its
--  visual state after the reset.
----------------------------------------------------------------
local function CreateResetButton(parent, cvarName, onReset)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(RESET_SIZE + 4, RESET_SIZE + 4)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(RESET_SIZE, RESET_SIZE)
    icon:SetPoint("CENTER")
    icon:SetAtlas("transmog-icon-revert")
    icon:SetVertexColor(0.55, 0.55, 0.55)
    btn._icon = icon

    btn:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 0.82, 0)
        ShowTooltip(self, "Reset to Default",
            "Restore |cFFFFFF00" .. cvarName .. "|r to its default value.")
    end)
    btn:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(0.55, 0.55, 0.55)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        AO:ResetCVar(cvarName)
        if onReset then onReset() end
    end)
    return btn
end

----------------------------------------------------------------
--  Restart / reload indicator
--
--  A small warning icon next to controls whose CVar requires
--  a /reload or GX restart to take effect.
--  Uses a texture atlas instead of Unicode ⚠.
----------------------------------------------------------------
local function CreateRestartIndicator(parent, requiresRestart)
    if not requiresRestart then return nil end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText("!")
    fs:SetTextColor(1, 0.5, 0)
    return fs
end

----------------------------------------------------------------
--  1. CHECKBOX — boolean CVars
--
--  cfg = {
--      cvar     = "cvarName",
--      label    = "Display Label",
--      tooltip  = "Optional tooltip body text",
--      restart  = false,          -- requires /reload or GX restart
--      invert   = false,          -- display inverted (checked = "0")
--  }
----------------------------------------------------------------
function AO:CreateCheckbox(parent, cfg)
    local row = CreateFrame("Frame", nil, parent)
    local rowW = parent:GetWidth(); rowW = (rowW > 0) and rowW or 400
    row:SetSize(rowW, ROW_HEIGHT)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(cfg.label)

    -- Read initial value
    local function IsChecked()
        local val = AO:GetCVarBool(cfg.cvar)
        if cfg.invert then val = not val end
        return val and true or false
    end

    local function Refresh()
        cb:SetChecked(IsChecked())
    end
    Refresh()

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if cfg.invert then checked = not checked end
        AO:SetCVar(cfg.cvar, checked and "1" or "0")
    end)

    -- Reset button — anchored to the far right of the row
    local resetBtn = CreateResetButton(row, cfg.cvar, Refresh)
    resetBtn:SetPoint("RIGHT", row, "RIGHT", 8, 0)

    -- Restart indicator — to the left of the reset button
    if cfg.restart then
        local indicator = CreateRestartIndicator(row, true)
        if indicator then
            indicator:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
        end
    end

    -- Tooltip on the whole row
    if cfg.tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            ShowTooltip(self, cfg.label, cfg.tooltip
                .. (cfg.restart and "\n\n|cFFFF8800Requires /reload to take effect.|r" or ""))
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.Refresh = Refresh
    row.cvar    = cfg.cvar
    return row
end

----------------------------------------------------------------
--  2. SLIDER — numeric CVars
--
--  cfg = {
--      cvar      = "cvarName",
--      label     = "Display Label",
--      tooltip   = "Optional tooltip body text",
--      min       = 0,
--      max       = 100,
--      step      = 1,
--      decimals  = 0,              -- decimal places in display
--      restart   = false,
--      formatter = nil,            -- optional fn(value) → string
--  }
----------------------------------------------------------------
function AO:CreateSlider(parent, cfg)
    local row = CreateFrame("Frame", nil, parent)
    local rowW = parent:GetWidth(); rowW = (rowW > 0) and rowW or 400
    row:SetSize(rowW, ROW_HEIGHT + 8)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(cfg.label)

    local slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    slider:SetWidth(140)
    slider:SetHeight(16)
    slider:SetPoint("LEFT", label, "RIGHT", 8, -2)
    slider:SetMinMaxValues(cfg.min, cfg.max)
    slider:SetValueStep(cfg.step or 1)
    slider:SetObeyStepOnDrag(true)

    -- Hide the built-in Low/High labels from OptionsSliderTemplate
    local sliderName = slider:GetName()
    if sliderName then
        local low  = _G[sliderName .. "Low"]
        local high = _G[sliderName .. "High"]
        local text = _G[sliderName .. "Text"]
        if low  then low:SetText("")  end
        if high then high:SetText("") end
        if text then text:SetText("") end
    end

    -- Value display
    local valText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valText:SetWidth(50)
    valText:SetJustifyH("LEFT")

    local function FormatValue(v)
        if cfg.formatter then return cfg.formatter(v) end
        if (cfg.decimals or 0) > 0 then
            return format("%." .. cfg.decimals .. "f", v)
        end
        return format("%d", v)
    end

    local function Refresh()
        local raw = AO:GetCVar(cfg.cvar)
        local val = tonumber(raw) or cfg.min
        val = math_max(cfg.min, math_min(cfg.max, val))
        slider:SetValue(val)
        valText:SetText(FormatValue(val))
    end
    Refresh()

    slider:SetScript("OnValueChanged", function(self, value)
        -- Snap to step
        local step = cfg.step or 1
        if step > 0 then
            value = math_floor(value / step + 0.5) * step
        end
        valText:SetText(FormatValue(value))
        AO:SetCVar(cfg.cvar, tostring(value))
    end)

    -- Reset button — anchored to the far right of the row
    local resetBtn = CreateResetButton(row, cfg.cvar, Refresh)
    resetBtn:SetPoint("RIGHT", row, "RIGHT", 8, 0)

    -- Restart indicator — to the left of the reset button
    if cfg.restart then
        local indicator = CreateRestartIndicator(row, true)
        if indicator then
            indicator:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
        end
    end

    -- Tooltip
    if cfg.tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            ShowTooltip(self, cfg.label, cfg.tooltip
                .. (cfg.restart and "\n\n|cFFFF8800Requires /reload to take effect.|r" or ""))
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.Refresh = Refresh
    row.cvar    = cfg.cvar
    return row
end

----------------------------------------------------------------
--  3. DROPDOWN — enum/multi-choice CVars
--
--  cfg = {
--      cvar     = "cvarName",
--      label    = "Display Label",
--      tooltip  = "Optional tooltip body text",
--      options  = { { value = "0", text = "Off" }, { value = "1", text = "On" }, ... },
--      restart  = false,
--  }
--
--  Uses WowStyle1DropdownTemplate (Midnight modern dropdown) with
--  pcall-wrapped creation and the WoWUIBugs #783 taint workaround.
----------------------------------------------------------------
function AO:CreateDropdown(parent, cfg)
    local row = CreateFrame("Frame", nil, parent)
    local rowW = parent:GetWidth(); rowW = (rowW > 0) and rowW or 400
    row:SetSize(rowW, ROW_HEIGHT + 4)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(cfg.label)

    local dropdown
    local okDD = pcall(function()
        dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    end)

    if not okDD or not dropdown then
        -- Fallback: just show the raw value as text
        local fallback = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fallback:SetPoint("LEFT", label, "RIGHT", 8, 0)
        local raw = AO:GetCVar(cfg.cvar) or "?"
        fallback:SetText(raw)
        row.Refresh = function()
            fallback:SetText(AO:GetCVar(cfg.cvar) or "?")
        end
        row.cvar = cfg.cvar
        return row
    end

    dropdown:SetPoint("LEFT", label, "RIGHT", 4, 0)
    dropdown:SetWidth(150)

    local function CurrentText()
        local cur = AO:GetCVar(cfg.cvar)
        if cur ~= nil then
            local curStr = tostring(cur)
            for _, opt in ipairs(cfg.options) do
                if tostring(opt.value) == curStr then return opt.text end
            end
        end
        return cur or "?"
    end

    local function Refresh()
        if dropdown.OverrideText then
            dropdown:OverrideText(CurrentText())
        elseif dropdown.SetDefaultText then
            dropdown:SetDefaultText(CurrentText())
        end
    end

    dropdown:SetupMenu(function(_, root)
        -- WoWUIBugs #783 taint workaround
        root:SetMinimumWidth(150)

        for _, opt in ipairs(cfg.options) do
            root:CreateRadio(
                opt.text,
                function()
                    local cur = AO:GetCVar(cfg.cvar)
                    return cur ~= nil and tostring(cur) == tostring(opt.value)
                end,
                function()
                    AO:SetCVar(cfg.cvar, opt.value)
                    Refresh()
                    return MenuResponse.Close
                end
            )
        end
    end)
    Refresh()

    -- Reset button — anchored to the far right of the row
    local resetBtn = CreateResetButton(row, cfg.cvar, Refresh)
    resetBtn:SetPoint("RIGHT", row, "RIGHT", 8, 0)

    -- Restart indicator — to the left of the reset button
    if cfg.restart then
        local indicator = CreateRestartIndicator(row, true)
        if indicator then
            indicator:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
        end
    end

    -- Tooltip
    if cfg.tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            ShowTooltip(self, cfg.label, cfg.tooltip
                .. (cfg.restart and "\n\n|cFFFF8800Requires /reload to take effect.|r" or ""))
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.Refresh = Refresh
    row.cvar    = cfg.cvar
    return row
end
