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
local RESET_SIZE     = 16

-- Exported for Featured.lua's extent calculator.
-- GAP between controls is a layout concern (Featured.lua) and is not included here.
AO.CONTROL_HEIGHTS = {
    checkbox    = ROW_HEIGHT,        -- 26
    slider      = ROW_HEIGHT + 8,    -- 34
    dropdown    = ROW_HEIGHT + 4,    -- 30
    multiselect = ROW_HEIGHT + 4,    -- 30, same dropdown
    button      = ROW_HEIGHT + 4,    -- 30, a 22 px panel button
}

----------------------------------------------------------------
--  Tooltip helper
----------------------------------------------------------------
-- Blizzard's settings tooltip: the name in white, the description in gold (Settings.InitTooltip,
-- Blizzard_Settings.lua: GameTooltip_AddHighlightLine + GameTooltip_AddNormalLine). Owner, 2026-11-01:
-- the description was grey. `reload`: Blizzard's restart line, a blank line then a red error line
-- (Blizzard_Settings.lua:475-477, GameTooltip_AddErrorLine).
local REQUIRES_RELOAD_TEXT = _G.REQUIRES_RELOAD or "Requires Reload"
local function ShowTooltip(owner, title, body, reload, xOffset)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", xOffset or 0, 0)
    GameTooltip:SetText(title, HIGHLIGHT_FONT_COLOR:GetRGB())
    if body then
        GameTooltip:AddLine(body, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    end
    if reload then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(REQUIRES_RELOAD_TEXT, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
    end
    GameTooltip:Show()
end

-- A row's CVars as they were when this session first built the row: a reload row shows "Requires
-- Reload" only while it differs from that (Blizzard's AddOn List, AddonList.lua:307-329).
local sessionStart = {}

-- A row was changed: Featured.lua shows its Reload UI button for a `restart` row (owner's request,
-- 2026-11-01), and the row's reset button and reload text follow the new value. Every write path
-- below calls this.
local function Changed(cfg)
    if cfg.restart and AO.ReloadNeeded then AO:ReloadNeeded() end
    if cfg._rowUpdate then cfg._rowUpdate() end
end

----------------------------------------------------------------
--  Reset-to-default button (shared across control types)
--
--  Blizzard's undo icon, the one its Cooldown Manager settings ("Revert Changes"), model viewer
--  (Reset Position), character customization (Reset Camera), transmog and housing use:
--  `common-icon-undo` (CooldownViewerSettings.lua:1216, ModelSceneControlFrame.lua:253,
--  Blizzard_CustomizationUI.xml:21). While the setting is at its default the button is disabled and its
--  icon greyed: desaturated, as Blizzard's own icon buttons do (IconButtonMixin:SetEnabledState,
--  Blizzard_SharedXML/Shared/Button/IconButtonTemplate.lua:48-51), and at half alpha, as its dropdown menus
--  grey a check they cannot use (UIDropDownMenu.lua:654-657). Desaturated alone read light, almost white
--  (owner, 2026-11-14). The icon steps 1,-1 while pressed (IconButtonTemplate.lua:30-38).
--  ⚠ MEASURED (owner, 2026-11-14): `common-icon-undo-disable`, the Cooldown Manager's disabled Revert art
--  (CooldownViewerSettings.lua:1216), is GOLD like the enabled one; Blizzard greys that button's frame and text,
--  not its icon. So it cannot mark our icon-only button, and is not used.
--  Hover: the same atlas added over it at 0.4, as housing's reset does
--  (HousingBlueprintCollection.xml:71). Until v1.89.0 this was `transmog-icon-revert` (no Blizzard
--  code in 12.1.5 uses it) tinted grey with a gold hover of our own.
--  The onReset callback lets the owning control refresh its visual state after the reset.
----------------------------------------------------------------
-- cvarName may be a list (a multi-select row): every CVar in it is reset.
local function NamesOf(cvarName)
    return type(cvarName) == "table" and cvarName or { cvarName }
end
local function AnyChanged(names)
    if not AO.GetCVarInfo then return true end   -- unknown: keep the button usable
    for _, name in ipairs(names) do
        local val, def = AO:GetCVarInfo(name)
        if val ~= nil and def ~= nil and val ~= def then return true end
    end
    return false
end

local function CreateResetButton(parent, cvarName, onReset, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(RESET_SIZE + 4, RESET_SIZE + 4)
    -- ⚠ A disabled Button runs no OnEnter/OnLeave unless told to: motionScriptsWhileDisabled defaults to
    -- false (Blizzard_SharedXML/UI.xsd:934). With the button disabled at default (most rows), hovering it
    -- showed nothing and the row's own tooltip flickered off and on at its edge (owner, 2026-11-14).
    -- Blizzard's buttons with a disabled tooltip set it (DisabledTooltipButtonTemplate,
    -- SharedTooltipTemplates.xml:135; UIButtonTemplate.lua:157).
    btn:SetMotionScriptsWhileDisabled(true)
    -- A 20 px target was "like threading a needle" (owner): the clickable area reaches 6 px past the art on
    -- the left, top and bottom. Not right: the scroll bar sits there.
    btn:SetHitRectInsets(-6, 0, -6, -6)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(RESET_SIZE, RESET_SIZE)
    icon:SetPoint("CENTER")
    icon:SetAtlas("common-icon-undo")
    btn._icon = icon

    local hover = btn:CreateTexture(nil, "OVERLAY")
    hover:SetAllPoints(icon)
    hover:SetAtlas("common-icon-undo")
    hover:SetBlendMode("ADD")
    hover:SetAlpha(0.4)
    hover:Hide()

    local names = NamesOf(cvarName)
    function btn:UpdateState()
        local changed = AnyChanged(names)
        self:SetEnabled(changed)
        icon:SetDesaturated(not changed)
        icon:SetAlpha(changed and 1 or 0.5)
        if not changed then hover:Hide() end
    end
    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then icon:SetPoint("CENTER", self, "CENTER", 1, -1) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        icon:SetPoint("CENTER", self, "CENTER")
    end)

    local isList = type(cvarName) == "table"
    btn:SetScript("OnEnter", function(self)
        -- Blizzard's tooltip colours: title white, text gold, and a name inside the gold text white, as its
        -- dropdown tooltips write each option's label (Settings.CreateOptionsInitTooltip,
        -- Blizzard_Settings.lua:442, :451). Was yellow on gold until v1.89.0 (owner: hard to tell apart).
        -- The name is the row's own label, the one on screen. The CVar name used to sit in the sentence; a long
        -- one (floatingCombatTextCombatHealing_v2) is one word the tooltip cannot wrap, so the sentence was
        -- cut to that word and an ellipsis (owner, 2026-11-14). It now has a grey line of its own, unwrapped,
        -- the colour Blizzard gives secondary lines (GameTooltip_AddDisabledLine, Blizzard_Settings.lua:453).
        local name = VUI.COL.HIGHLIGHT .. (label or (isList and "this list") or cvarName) .. "|r"
        local body
        if self:IsEnabled() then
            hover:Show()
            body = isList and ("Restore every choice in " .. name .. " to its default value.")
                or ("Restore " .. name .. " to its default value.")
        else
            body = isList and ("Every choice in " .. name .. " is already at its default value.")
                or (name .. " is already at its default value.")
        end
        ShowTooltip(self, "Reset to Default", body)
        if not isList then
            local grey = DISABLED_FONT_COLOR or GRAY_FONT_COLOR or { r = 0.5, g = 0.5, b = 0.5 }
            GameTooltip:AddLine(cvarName, grey.r, grey.g, grey.b, false)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        for _, name in ipairs(names) do AO:ResetCVar(name) end
        if onReset then onReset() end
    end)
    btn:UpdateState()
    return btn
end

----------------------------------------------------------------
--  "Requires Reload" (rows whose CVar applies only after a /reload)
--
--  Blizzard's AddOn List marks a row it cannot apply until a reload with red "Requires Reload"
--  text, REQUIRES_RELOAD in GameFontRed (AddonList.xml:64), shown only while that row differs from
--  what is loaded (AddonList_SetStatus, AddonList.lua:307-329). Blizzard's Options pages show no row
--  marker; the tooltip carries the red line (ShowTooltip above). Until v1.89.0 this was an orange
--  "!" shown all the time, our own.
----------------------------------------------------------------
local function CreateReloadText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontRed")
    fs:SetText(REQUIRES_RELOAD_TEXT)
    fs:Hide()
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

-- Blizzard's Options row hover (SettingsListElementTemplate, Blizzard_SettingControls.xml:50-64), the owner's pick
-- (2026-11-14) after a tooltip came up over blank space: the row's own tooltip area runs from its left edge to 80 px
-- short of its middle; while the mouse is there a white 10% band lights the row (HoverBackgroundTemplate,
-- :5-11) and the tooltip sits ANCHOR_RIGHT of that area at -10 (DefaultTooltipMixin,
-- Blizzard_SettingControls.lua:15-38). Each control shows the same tooltip on itself. The rest of the row shows no
-- tooltip (since 2026-11-27 it does light the band; see the note above LABEL_PAD).
-- Until v1.89.0 the whole row, edge to edge, carried the tooltip, with no band.
-- The row keeps the mouse over its whole width (cut to the band's height); `zone` marks the area and owns the
-- tooltip, with mouse motion of its own (re-fitted on every resize: Featured.lua re-anchors rows).
-- ⚠ Owner, 2026-11-14 (first in-game look): the band must be ONE height on every row, as Blizzard's is, and must
-- not stop inside the reset button. So it is ROW_HEIGHT tall, centred on the row's line -- `lineY` is the same
-- raise the reset button gets (a slider row's line sits above its centre, SLIDER_RESET_RAISE) -- and runs to the
-- reset button's right edge, the scroll box's own edge (Featured.lua: rows inset PAD_X 8, the button at +8), which
-- also keeps it off the scroll bar. The tooltip area takes the same height.
-- ⚠ Owner, 2026-11-14 (second look): every word of the name must bring the highlight up. Our window is narrower than
-- Blizzard's Options, so "middle - 80" (~140 px here) cut through long names ("Enable Floating Combat Text" lost it
-- between the "b" and the "a"). The area now reaches the end of the name plus LABEL_PAD, whichever is further, and
-- never past the label's own box (`row._label` / `row._labelX`, set by each factory), so it stops short of the control.
-- Re-measured on show: a name's width is only reliable once its font has loaded.
-- ⚠ Owner, 2026-11-27: the band must stay up wherever the mouse is on the line -- the blank middle, the slider,
-- the checkbox, the dropdown, the reset button -- and the tooltips stay exactly where they were. Blizzard does it
-- by giving every hoverable piece of a row its own row-wide HoverBackground (SettingsCheckboxTemplate,
-- Blizzard_SettingControls.xml:4-11, :82-86; DefaultTooltipMixin:OnEnter/OnLeave, .lua:26-51). Here one band
-- serves them all: the row takes the mouse over its whole width (no tooltip there), `zone` takes mouse motion
-- for the name's tooltip, and every frame in the row lights the band on enter. A watcher puts it out once the
-- frame under the mouse is no longer the row or something inside it, so moving between pieces never flickers it
-- and pieces nested inside a control keep it lit without a leave of their own.
-- ⚠ Not the band's box (build 1, owner 2026-11-27: no highlight moving onto a slider or from one reset button
-- down to the next). The reset button's mouse area reaches 6 px past its art (CreateResetButton), 3 px past the
-- band's 26, so a cursor coming from above or below entered it outside the box, the watcher put the band straight
-- out, and no further enter came while inside it. The slider's case looks the same; its mouse area is unmeasured.
local LABEL_PAD = 8
local function AttachRowTooltip(row, showTip, controls, lineY)
    lineY = lineY or 0
    local zone = CreateFrame("Frame", nil, row)
    zone:SetHeight(ROW_HEIGHT)
    if zone.SetMouseMotionEnabled then zone:SetMouseMotionEnabled(true) else zone:EnableMouse(true) end
    local band = row:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("LEFT", row, "LEFT", -10, lineY)
    band:SetPoint("RIGHT", row, "RIGHT", 8, lineY)
    band:SetHeight(ROW_HEIGHT)
    band:SetColorTexture(1, 1, 1, 0.1)
    band:Hide()
    -- Lib's walk: pcall'd and capped, since the focus can be a forbidden object.
    local function OnLine() return VUI.MouseIsWithin(row) end
    local watch = CreateFrame("Frame", nil, row)
    watch:Hide()
    watch:SetScript("OnUpdate", function(self)
        if not OnLine() then band:Hide(); self:Hide() end
    end)
    local function Light() band:Show(); watch:Show() end
    local function AreaWidth(w)
        local area = w / 2 - 80
        local label, x = row._label, row._labelX or 0
        if label then
            local textW = tonumber((label:GetStringWidth())) or 0
            local boxW = tonumber((label:GetWidth())) or LABEL_WIDTH
            area = math_max(area, x + textW + LABEL_PAD)
            area = math_min(area, x + boxW)
        end
        return math_max(0, math_min(area, w))
    end
    -- The zone starts at the name, not the row's edge: with mouse motion of its own it would otherwise sit over a
    -- checkbox and take its clicks. ANCHOR_RIGHT reads only its right and top, so the tooltip has not moved.
    local function Fit(self, w, h)
        w = tonumber(w) or tonumber((self:GetWidth())) or 0
        h = tonumber(h) or tonumber((self:GetHeight())) or ROW_HEIGHT
        local area = AreaWidth(w)
        local x = math_min(row._labelX or 0, area)
        zone:ClearAllPoints()
        zone:SetPoint("LEFT", row, "LEFT", x, lineY)
        zone:SetWidth(math_max(1, area - x))
        local spare = math_max(0, (h - ROW_HEIGHT) / 2)
        self:SetHitRectInsets(0, 0, math_max(0, spare - lineY), math_max(0, spare + lineY))
    end
    row:EnableMouse(true)
    Fit(row)
    row:SetScript("OnSizeChanged", Fit)
    row:HookScript("OnShow", function(self) band:Hide(); watch:Hide(); Fit(self) end)
    row:SetScript("OnEnter", function(self) Fit(self); Light() end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    zone:SetScript("OnEnter", function() Light(); showTip(zone, -10) end)
    zone:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row._zone = zone
    local isControl = {}
    for _, c in ipairs(controls or {}) do
        isControl[c] = true
        c:HookScript("OnEnter", function(self) Light(); showTip(self, 0) end)
        c:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Every other frame in the row (the reset button, a slider's arrows, an action button): the band only; each
    -- keeps its own tooltip.
    local function HookAll(f)
        for _, c in ipairs({ f:GetChildren() }) do
            if c ~= zone and c ~= watch then
                if not isControl[c] and c.HookScript then c:HookScript("OnEnter", Light) end
                HookAll(c)
            end
        end
    end
    HookAll(row)
end

-- Trailing furniture shared by all three factories: reset button on the far
-- right, "Requires Reload" to its left on a reload row, Blizzard's row tooltip (AttachRowTooltip),
-- and the row.Refresh handle Featured.lua's tab-show refresh reads.
--
-- ⚠ Deliberately NOT used by the dropdown's pcall fallback path: that path has
-- no reset button, no reload text and no tooltip, and returns early by design.
-- resetY: raises the reset button off the row's centre. A slider row is taller than its slider
-- (room under the bar), so a centred button sat below the slider (owner, 2026-10-30); sliders
-- pass SLIDER_RESET_RAISE.
-- resetNames: the multi-select's list of CVars, reset together; other rows reset cfg.cvar.
local SLIDER_RESET_RAISE = 9   -- owner, 2026-10-30: tuned in game (4, 8, 10, then 9)
local function FinishRow(row, cfg, Refresh, resetY, resetNames)
    local resetBtn = CreateResetButton(row, resetNames or cfg.cvar, function() Changed(cfg); Refresh() end, cfg.label)
    resetBtn:SetPoint("RIGHT", row, "RIGHT", 8, resetY or 0)

    local names = NamesOf(resetNames or cfg.cvar)
    local reloadText
    if cfg.restart then
        reloadText = CreateReloadText(row)
        reloadText:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
        for _, name in ipairs(names) do
            if sessionStart[name] == nil then sessionStart[name] = AO:GetCVar(name) or false end
        end
    end
    local function RowUpdate()
        resetBtn:UpdateState()
        if reloadText then
            local differs = false
            for _, name in ipairs(names) do
                if (AO:GetCVar(name) or false) ~= sessionStart[name] then differs = true end
            end
            reloadText:SetShown(differs)
        end
    end
    cfg._rowUpdate = RowUpdate
    RowUpdate()

    -- Every control the factory made (checkbox, slider, dropdown): the same tooltip on itself.
    local controls = {}
    for _, child in ipairs({ row:GetChildren() }) do
        if child ~= resetBtn and child.HookScript then controls[#controls + 1] = child end
    end
    AttachRowTooltip(row, function(owner, x) ShowTooltip(owner, cfg.label, cfg.tooltip, cfg.restart, x) end, controls,
        resetY)

    row.Refresh = function(...)
        Refresh(...)
        RowUpdate()
    end
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
--      anyNonZero = false,        -- checked for any value but "0" (a level CVar shown as on/off)
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
    row._label, row._labelX = label, 26   -- after the 22 px box + 4 (AttachRowTooltip)
    label:SetJustifyH("LEFT")
    label:SetText(cfg.label)

    -- Read initial value
    local function IsChecked()
        local val
        if cfg.anyNonZero then
            local raw = AO:GetCVar(cfg.cvar)
            val = raw ~= nil and raw ~= "0"
        else
            val = AO:GetCVarBool(cfg.cvar)
        end
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
        Changed(cfg)
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
    row._label, row._labelX = label, 0
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
            Changed(cfg)
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
    row._label, row._labelX = label, 0
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
                    local written = AO:SetCVar(cfg.cvar, opt.value)
                    Changed(cfg)
                    if written or not InCombatLockdown() then
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

----------------------------------------------------------------
--  4. MULTISELECT — several on/off CVars in one dropdown
--
--  cfg = {
--      cvar     = "masterCVar",   -- the row's own checkbox; the list's rows grey out while it is off
--      label    = "Display Label",
--      tooltip  = "Optional tooltip body text",
--      options  = { { cvar = "cvarName", text = "Row label" }, ... },
--  }
--
--  The master checkbox and label sit where a checkbox row's do, and the dropdown lines up with the
--  other dropdowns (owner, 2026-11-01: one row, not a separate "Shows" row under the master).
--  Blizzard's dropdown with checkbox rows (MenuTemplates.CreateCheckbox, MenuTemplates.lua:330-342:
--  a tick keeps the menu open, MenuResponse.Refresh). Each row reads and writes its own CVar; there
--  is no saved state of ours. A CVar this client does not have is left out of the list.
----------------------------------------------------------------
function AO:CreateMultiSelect(parent, cfg)
    local row = CreateRow(parent, ROW_HEIGHT + 4)

    local master = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    master:SetSize(22, 22)
    master:SetPoint("LEFT", row, "LEFT", 0, 0)

    -- 26 narrower than a checkbox row's label, so the dropdown starts where every other one does.
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", master, "RIGHT", 4, 0)
    label:SetWidth(LABEL_WIDTH - 26)
    row._label, row._labelX = label, 26
    label:SetJustifyH("LEFT")
    label:SetText(cfg.label)

    local masterOpt = { cvar = cfg.cvar }
    local options, names = {}, { cfg.cvar }
    for _, opt in ipairs(cfg.options) do
        if AO:GetCVarInfo(opt.cvar) ~= nil then
            options[#options + 1] = opt
            names[#names + 1] = opt.cvar
        end
    end

    local dropdown
    local okDD = pcall(function()
        dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    end)
    if not okDD or not dropdown then
        row.Refresh = function() end
        return row
    end
    dropdown:SetPoint("LEFT", label, "RIGHT", 4, 0)
    dropdown:SetWidth(150)

    -- A tick in combat is written when combat ends (AO:SetCVar); until then the live CVar still
    -- holds the old value, so the row shows the pending one instead.
    local pending = {}
    local function IsOn(opt)
        if pending[opt.cvar] ~= nil then return pending[opt.cvar] == "1" end
        return AO:GetCVar(opt.cvar) == "1"
    end

    local function CurrentText()
        local on = {}
        for _, opt in ipairs(options) do
            if IsOn(opt) then on[#on + 1] = opt.text end
        end
        if #on == 0 then return _G.NONE or "None" end
        if #on == #options then return _G.ALL or "All" end
        return table.concat(on, ", ")
    end

    local function Refresh()
        if not InCombatLockdown() then wipe(pending) end
        master:SetChecked(IsOn(masterOpt))
        if dropdown.OverrideText then dropdown:OverrideText(CurrentText()) end
    end

    local function MasterOn() return IsOn(masterOpt) end

    local function Toggle(opt)
        local value = IsOn(opt) and "0" or "1"
        if not AO:SetCVar(opt.cvar, value) and InCombatLockdown() then
            pending[opt.cvar] = value
        end
        Changed(cfg)
        Refresh()
    end
    master:SetScript("OnClick", function() Toggle(masterOpt) end)

    dropdown:SetupMenu(function(_, root)
        -- WoWUIBugs #783 taint workaround, as CreateDropdown
        root:SetMinimumWidth(150)
        -- None and All first (owner's standard for every dropdown of choices, 2026-11-01). Not
        -- stored: None is ticked when no choice is, All when every one is.
        local function Count()
            local n = 0
            for _, o in ipairs(options) do if IsOn(o) then n = n + 1 end end
            return n
        end
        local function SetEvery(on)
            for _, o in ipairs(options) do if IsOn(o) ~= on then Toggle(o) end end
        end
        local none = root:CreateCheckbox(_G.NONE or "None", function() return Count() == 0 end,
            function() if Count() > 0 then SetEvery(false) end end)
        local all = root:CreateCheckbox(_G.ALL or "All", function() return Count() == #options end,
            function() SetEvery(Count() < #options) end)
        for _, cb in ipairs({ none, all }) do
            if cb and cb.SetEnabled then cb:SetEnabled(MasterOn) end
        end
        for _, opt in ipairs(options) do
            local cb = root:CreateCheckbox(opt.text,
                function() return IsOn(opt) end,
                function() Toggle(opt) end)
            if cb and cb.SetEnabled then cb:SetEnabled(MasterOn) end
        end
    end)
    Refresh()

    return FinishRow(row, cfg, Refresh, nil, names)
end

----------------------------------------------------------------
--  5. BUTTON — an action, not a setting (UI Replacements)
--
--  cfg = { label = "ElvUI", buttonText = "Reset Changes", tooltip = "...", suite = "elvui" }
--  Blizzard's action row: the name on the left, a panel button on the right (SettingsButtonControlTemplate
--  via CreateSettingsButtonInitializer, Blizzard_SettingsDefinitions_Frame/AdvancedOptions.lua:333-342).
--  Disabled while there is nothing to do or the suite is still running (AO:SuiteState, Browser.lua); the
--  tooltip then ends with the reason as a red error line, as Blizzard gives a disabled option's reason
--  (GameTooltip_AddErrorLine, Blizzard_Settings.lua:459). No reset button: there is no value to reset.
----------------------------------------------------------------
function AO:CreateButtonRow(parent, cfg)
    local row = CreateRow(parent, AO.CONTROL_HEIGHTS.button)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetWidth(LABEL_WIDTH)
    row._label, row._labelX = label, 0
    label:SetJustifyH("LEFT")
    label:SetText(cfg.label)

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(140, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", 8, 0)
    btn:SetText(cfg.buttonText)
    btn:SetMotionScriptsWhileDisabled(true)   -- a disabled one still explains why (see CreateResetButton)

    local reason
    local function Refresh()
        local ok, info = true, nil
        if AO.SuiteState then ok, info = AO:SuiteState(cfg.suite) end
        btn:SetEnabled(ok and true or false)
        reason = (not ok) and info or nil
    end

    local function Tip(owner, x)
        ShowTooltip(owner, cfg.label, cfg.tooltip, nil, x)
        if reason then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(reason, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
            GameTooltip:Show()
        end
    end
    btn:SetScript("OnEnter", function(self) Refresh(); Tip(self) end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        if AO.AskSuiteReset then AO:AskSuiteReset(cfg.suite) end
    end)
    AttachRowTooltip(row, function(owner, x) Refresh(); Tip(owner, x) end)

    Refresh()
    row.Refresh = Refresh
    return row
end
