-- VeritasUI_AdvancedOptions / Controls.lua
-- Factory functions for native-looking CVar controls.
--
-- Each factory returns the outermost frame so callers can anchor it.
-- All controls read their initial value from C_CVar on creation and
-- write back via AO:SetCVar on user interaction.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local pcall          = pcall
local tonumber       = tonumber
local format         = string.format
local math_floor     = math.floor
local math_max       = math.max
local math_min       = math.min
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local GameTooltip    = GameTooltip
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
--  Shared style constants
----------------------------------------------------------------
local ROW_HEIGHT     = 26
local LABEL_WIDTH    = 260
local RESET_SIZE     = 14

-- Exported for Featured.lua's extent calculator.
-- GAP between controls is a layout concern (Featured.lua) and is not included here.
AO.CONTROL_HEIGHTS = {
    checkbox = ROW_HEIGHT,        -- 26
    slider   = ROW_HEIGHT + 8,    -- 34
    dropdown = ROW_HEIGHT + 4,    -- 30
}

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
--  Uses "!" text (orange); atlas approach conflicted with pool-frame
--  reparenting and was abandoned.
--
--  Called only from inside FinishRow's `if cfg.restart` branch, so it always
--  creates the fontstring and never returns nil — the caller must not test it.
----------------------------------------------------------------
local function CreateRestartIndicator(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText("!")
    fs:SetTextColor(1, 0.5, 0)
    return fs
end

----------------------------------------------------------------
--  Shared row scaffolding
--
--  All three factories build the same outer frame and the same trailing
--  furniture. These two helpers hold the single copy. v1.6.26's theme was
--  collapsing exactly this kind of duplicate (CONTROL_HEIGHTS from one
--  ROW_HEIGHT, SB_INSET defined once), and the module's stated design goal is
--  that adding a CVar is one table entry — so duplication *inside* the
--  factories undercuts the layer they exist to provide.
----------------------------------------------------------------

-- Full-width row frame. The 400 fallback covers the first control created
-- before its parent has been laid out (GetWidth() == 0).
local function CreateRow(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    local rowW = parent:GetWidth(); rowW = (rowW > 0) and rowW or 400
    row:SetSize(rowW, height)
    return row
end

-- Trailing furniture shared by all three factories: reset button on the far
-- right, optional restart indicator to its left, optional whole-row tooltip,
-- and the row.Refresh handle Featured.lua's tab-show refresh reads.
--
-- ⚠ Deliberately NOT used by the dropdown's pcall fallback path: that path has
-- no reset button, no indicator and no tooltip, and returns early by design.
-- resetY: raises the reset button off the row's centre. A slider row is taller than its slider
-- (room under the bar), so a centred button sat below the slider (owner, 2026-10-30); sliders
-- pass SLIDER_RESET_RAISE.
local SLIDER_RESET_RAISE = 9   -- owner, 2026-10-30: tuned in game (4, 8, 10, then 9)
local function FinishRow(row, cfg, Refresh, resetY)
    local resetBtn = CreateResetButton(row, cfg.cvar, Refresh)
    resetBtn:SetPoint("RIGHT", row, "RIGHT", 8, resetY or 0)

    if cfg.restart then
        local indicator = CreateRestartIndicator(row)
        indicator:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
    end

    if cfg.tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            ShowTooltip(self, cfg.label, cfg.tooltip
                .. (cfg.restart and "\n\n|cFFFF8800Requires /reload to take effect.|r" or ""))
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.Refresh = Refresh
    return row
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
    local row = CreateRow(parent, ROW_HEIGHT)

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

    return FinishRow(row, cfg, Refresh)
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
    local row = CreateRow(parent, ROW_HEIGHT + 8)

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

    -- Hide the built-in Low/High/Text labels from OptionsSliderTemplate.
    -- The slider is deliberately created unnamed (see CreateFrame above), so the
    -- original _G[sliderName .. "Low"] lookup could never resolve and the labels
    -- rendered anyway. Prefer the template's parentKey references, and keep the
    -- name-based path as a fallback for a named slider. Both are optional: if a
    -- future template drops a key we silently leave it alone rather than error.
    local sliderName = slider:GetName()
    local function ClearLabel(key)
        local fs = slider[key] or (sliderName and _G[sliderName .. key])
        if fs and fs.SetText then fs:SetText("") end
    end
    ClearLabel("Low")
    ClearLabel("High")
    ClearLabel("Text")

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

    -- Declared BEFORE Refresh so Refresh can capture it as an upvalue.
    local pendingWrite

    local function Refresh()
        -- Cancel any in-flight debounced drag write: Refresh reflects the
        -- authoritative CVar value (reset button, external change), and a
        -- stale pending write landing 0.15s later would silently re-apply
        -- the dragged value over it.
        if pendingWrite then pendingWrite:Cancel(); pendingWrite = nil end
        local raw = AO:GetCVar(cfg.cvar)
        local val = tonumber(raw) or cfg.min
        val = math_max(cfg.min, math_min(cfg.max, val))
        slider:SetValue(val)
        valText:SetText(FormatValue(val))
    end
    Refresh()

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        -- Snap to step
        local step = cfg.step or 1
        if step > 0 then
            value = math_floor(value / step + 0.5) * step
        end
        valText:SetText(FormatValue(value))
        -- Skip programmatic SetValue calls (e.g. from Refresh); only write on user drag.
        if not userInput then return end
        -- Debounce: commit after drag settles instead of on every intermediate step.
        if pendingWrite then pendingWrite:Cancel() end
        pendingWrite = C_Timer.NewTimer(0.15, function()
            pendingWrite = nil
            AO:SetCVar(cfg.cvar, tostring(value))
        end)
    end)

    return FinishRow(row, cfg, Refresh, SLIDER_RESET_RAISE)
end

----------------------------------------------------------------
--  3. DROPDOWN — enum/multi-choice CVars
--
--  cfg = {
--      cvar     = "cvarName",
--      label    = "Display Label",
--      tooltip  = "Optional tooltip body text",
--      options  = { { value = "0", text = "Off" }, { value = "1", text = "On" }, ... },
--      valueText = nil,           -- optional fn(value) → text for a value not in options
--      restart  = false,
--  }
--
--  Uses WowStyle1DropdownTemplate (Midnight modern dropdown) with
--  pcall-wrapped creation and the WoWUIBugs #783 taint workaround.
----------------------------------------------------------------
function AO:CreateDropdown(parent, cfg)
    local row = CreateRow(parent, ROW_HEIGHT + 4)

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
            -- Optional cfg.valueText(value): readable text for a value not in the list (audit O4).
            if cfg.valueText then return cfg.valueText(curStr) end
        end
        return cur or "?"
    end

    -- Single place that knows how to paint the closed dropdown's label.
    local function SetLabel(text)
        if dropdown.OverrideText then
            dropdown:OverrideText(text)
        elseif dropdown.SetDefaultText then
            dropdown:SetDefaultText(text)
        end
    end

    local function Refresh()
        SetLabel(CurrentText())
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
                    -- AO:SetCVar returns false both when the write is deferred to
                    -- the end of combat and when it genuinely fails, so disambiguate
                    -- here rather than changing its contract. On a deferred write,
                    -- Refresh() would re-read the live CVar (still the old value) and
                    -- snap the label back, throwing away both the user's selection
                    -- and the optimistic cache write AO:SetCVar just made. Show the
                    -- chosen option instead; the CVar catches up when combat ends.
                    if AO:SetCVar(cfg.cvar, opt.value) or not InCombatLockdown() then
                        Refresh()
                    else
                        SetLabel(opt.text)
                    end
                    return MenuResponse.Close
                end
            )
        end
    end)
    Refresh()

    return FinishRow(row, cfg, Refresh)
end
