-- VeritasUI_Lib / SettingsCoverDropdown.lua -- a dropdown in the Options list with NO Blizzard dropdown in it
-- (TRIAL, owner 2026-11-03: Quality of Life's Quest Options only).
--
-- ⚠ WHY, measured in the owner's taintLog 11 run (~/Downloads/taint.log, 2026-11-02 23:21):
--   * Blizzard's Options list reuses its row frames between pages. Our Settings.CreateDropdown row wrote its
--     dropdown button's menu builder as ours (menuGenerator, DropdownButton.lua:239, log L47449, frame
--     ...d558e0). Nameplates' Style dropdown was later drawn on that same frame, its click read our leftover
--     builder (L164615, written only once in the whole log), the menu opened tainted and wrote the list's
--     `updateLock` (ScrollBox.lua:147, L183748, its first tainted write) -> Options > Social has
--     C_Discord.IsUserOAuthed() refused.
--   * Covering that Blizzard dropdown with a frame of ours did not help: the row underneath was still a
--     Blizzard dropdown filled in with our data.
--   * A row template of our own in the list taints the list on scroll (frame creation reads our mixin).
--   * Blizzard's menu opened from our code leaves its shared menu stock tainted for Blizzard's next dropdown.
-- So the row is Blizzard's SECTION HEADER row (SettingsListSectionHeaderTemplate, Blizzard_SettingControls.xml:13,
-- the same initializer CreateSettingsListSectionHeaderInitializer makes, :112-115) with an empty title. A header
-- has no control and nothing to click, so a Blizzard header later drawn on that frame has nothing that can open
-- a menu. A frame of ours parented to SettingsPanel (not to the list) draws the label and the dropdown where
-- Blizzard's sit and opens our own pop-out. Nothing is written on Blizzard's frames and Blizzard's menu is never
-- opened.
-- ⚠ SEARCH TAGS (owner's repro, 2026-11-03: Options search "repair" -> Nameplates > Style -> Social popup,
-- "VeritasUI_Lib"). Every search reads the search tags of EVERY initializer on every list page
-- (SettingsPanelMixin:FindInitializersMatchingSearchText -> MatchesSearchTags, Blizzard_SettingsPanel.lua:575-610,
-- Blizzard_Settings.lua:65-77). Tags added from addon code (initializer:AddSearchTags) are written tainted, so the
-- search runs tainted from the first one it reads and draws its results tainted. Never call AddSearchTags.
-- Blizzard adds tags safely only inside its own secure handler, from data.setting's name, read through
-- securecallfunction (Blizzard_SettingsInbound.lua:229-238) -- the path every Settings.CreateCheckbox row takes.
-- So each row gets its own TAG SETTING: an add-on setting on a throwaway table whose name is a plain string (the
-- same SecureUnpackArgs path as every other add-on setting, :208-212): 400 spaces, then the label. The search
-- matches the label inside the tag (Blizzard_Settings.lua:65-77, plain find). The header row shows its setting's
-- name as its title (SettingsListSectionHeaderMixin:Init, Blizzard_SettingControls.lua:95-97, TOPLEFT 7,-16,
-- SetTextToFit), so the spaces push the label past the list's right edge, where the list's scroll box clips it
-- (ScrollBoxBaseTemplate clipChildren="true", Blizzard_SharedXML/Shared/Scroll/ScrollBox.xml:20).
-- ⚠ NOT a hidden hyperlink, "|Hvui:<label>|h|h" (step 7): the header title drew it as raw text
-- ("|Hvui:Fade Action Bars", owner's screenshots 2026-11-03) on the pages and in search results.
-- The tag setting holds no value.
-- ⛔ NEVER a proxy setting with a FUNCTION name (step 5, 2026-11-03): Blizzard calls that function inside its
-- secure handlers (GetNameType at setting Init, GetName for the tag), so they ran as ours and left Settings' shared
-- tables tainted; Blizzard's own pages, registered after login, then wrote their rows' search fields as
-- VeritasUI_Lib -- the owner's `/vui probe search`: 27 Blizzard rows (Combat, General, Graphics) with searchTags /
-- searchIgnoredLayouts / parentInitializer tainted by VeritasUI_Lib, none of ours. Step 7 (plain string): 0.
-- UNMEASURED (2026-11-03): that leading spaces are drawn as width and the label lands outside the list.
-- ⚠ NOT the bare SettingsListElementTemplate (owner's Lua error, 2026-11-03): that template has no OnLoad in its
-- XML (:50-77; only the templates inheriting it run SettingsListElementMixin:OnLoad), so `cbrHandles` is never
-- made and its Init fails at Blizzard_SettingControls.lua:306. That is why no Blizzard page uses it bare.
-- Cost: a header row is 45 high (:14), not 26, so this row is taller than the rows around it.
local VUI = _G.VeritasUI
if not VUI then return end

local entries = {}                                           -- [initializer] = entry
local covers = {}                                            -- [initializer] = our cover button

-- Where Blizzard's Settings dropdown sits in its row: the control frame (223 x 38, DropdownWithSteppersTemplate,
-- SharedUIPanelTemplates.xml:1472) at LEFT = row CENTER -48, +3 (SettingsDropdownControlMixin:OnLoad,
-- Blizzard_SettingControls.lua:730), the 220-wide dropdown centred in it (:741, Blizzard_SettingControls.xml:172).
local DD_W, DD_H = 220, 25
local DD_X, DD_Y = -48 + 223 / 2, 3
local LABEL_X, LABEL_RIGHT, SUB_INDENT = 37, -85, 15
local ROW_HALF = 26 / 2             -- half a Blizzard settings row (SettingsDropdownControlTemplate, 280 x 26)

-- ── The cover's face ──────────────────────────────────────────────────────
-- Blizzard's dropdown face from the same template values (WowStyle2DropdownTemplate, MenuTemplates.xml:4-41)
-- and state rules (WowStyle2DropdownMixin:GetBackgroundAtlas / :OnButtonStateChanged, MenuTemplates.lua:
-- 1024-1054; mouse-down text displacement 2, -1, :1015-1016 and ButtonStateBehavior.lua:59-92).
local TEXT_X, DOWN_X, DOWN_Y = 13, 2, -1
local bit = _G.bit
local CHECKBOX = Settings and Settings.ControlType and Settings.ControlType.Checkbox or 2

local function FaceAtlas(c, enabled)
    if not enabled then return "common-dropdown-c-button-disabled" end
    if c.down and c.over then return "common-dropdown-c-button-pressedhover-1"
    elseif c.over then return "common-dropdown-c-button-hover-1"
    elseif c.down then return "common-dropdown-c-button-pressed-1"
    elseif c.menu then return "common-dropdown-c-button-open" end
    return "common-dropdown-c-button"
end

local function IsEnabled(e)
    if not e.isEnabled then return true end
    local ok, on = pcall(e.isEnabled)
    return ok and on and true or false
end

local function Refresh(c)
    local enabled = IsEnabled(c.entry)
    c.Background:SetAtlas(FaceAtlas(c, enabled), true)
    c.Arrow:SetShown(enabled and c.over or false)
    c.Arrow:SetDesaturated(not enabled)
    local col = enabled and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR
    c.Text:SetTextColor(col:GetRGB())
    -- The row label greys as Blizzard's does (SettingsListElementMixin:DisplayEnabled,
    -- Blizzard_SettingControls.lua:290).
    c.Label:SetTextColor((enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
    local dx, dy = 0, 0
    if c.down and enabled then dx, dy = DOWN_X, DOWN_Y end
    c.Text:ClearAllPoints()
    c.Text:SetPoint("LEFT", TEXT_X + dx, dy)
    c.Text:SetPoint("RIGHT", -TEXT_X + dx, dy)
    c.enabled = enabled
end

local function OptionBit(opt) return bit.lshift(1, opt.value - (opt.enumValueOffset or 1)) end
local function IsPicked(setting, opt)
    local v = setting:GetValue()
    if opt.controlType == CHECKBOX then return type(v) == "number" and bit.band(v, OptionBit(opt)) ~= 0 end
    return v == opt.value
end
local function Options(e)
    local ok, list = pcall(e.getOptions)
    return ok and type(list) == "table" and list or {}
end

-- The text Blizzard's dropdown shows: the picked rows' text joined by LIST_DELIMITER, else CUSTOM
-- (DropdownSelectionTextMixin:UpdateToMenuSelections, MenuTemplates.lua:760-795; default text CUSTOM,
-- Blizzard_Settings.lua:555). A row with no `text` is not listed (MenuUtil.GetElementText).
local function SelectionText(e)
    local texts = {}
    for _, opt in ipairs(Options(e)) do
        if opt.text and IsPicked(e.setting, opt) then texts[#texts + 1] = opt.text end
    end
    if #texts > 0 then return table.concat(texts, _G.LIST_DELIMITER or ", ") end
    return _G.CUSTOM or "Custom"
end

local function SyncText(c)
    local t = SelectionText(c.entry)
    if t ~= c.lastText then c.lastText = t; c.Text:SetText(t) end
    if IsEnabled(c.entry) ~= c.enabled then Refresh(c) end
end

-- ── The pop-out ────────────────────────────────────────────────────────────
-- Blizzard's Settings dropdown menu, measured from its code:
--   * MenuStyle2 (the WowStyle2 dropdown's menu, MenuTemplates.xml:4-6): background "common-dropdown-c-bg"
--     at -17, 12 / 17, -22 and insets 3 / 6 / 3 / 7 (MenuTemplates.lua:1135-1153); rows stacked with no gap
--     (AnchorUtil.VerticalLayout from the inset corner, Menu.lua:1476-1495); every row the same width
--     (:1398-1446); at least as wide as the dropdown (DropdownButton.lua:190-192).
--   * Checkbox rows (Settings.CreateDropdownCheckbox, Blizzard_Settings.lua:494-505): the tick box 4 in from the
--     row's left edge, text 7 right of the box and 1 up, GameFontHighlight, 20 high (Mainline/MenuVariants.lua:
--     9-24, Compositor.lua:69); tick "common-dropdown-ticksquare" + "common-dropdown-icon-checkmark-yellow"
--     at +2, +1; hover highlight "UI-QuestTitleHighlight" ADD (MenuVariants.lua:41-50); a pick keeps it open
--     (MenuResponse.Refresh, MenuTemplates.lua:341).
--   * Single-choice rows (Settings.CreateDropdownButton -> CreateHighlightRadio, Blizzard_Settings.lua:488-491,
--     MenuTemplates.lua:360-368 / 444-517): no tick, GameFontNormal text 14 in, gold when picked, very light
--     grey otherwise, white on hover; hover background "common-dropdown-customize-mouseover" at 0.15
--     (DarkMenuElementTemplate, SharedUIPanelTemplates.xml:1451-1468); a pick closes it.
-- Picks work as Blizzard's Settings inserter does (Blizzard_Settings.lua:507-544).
local ROW_H = 20
local INSET_L, INSET_T, INSET_R, INSET_B = 3, 6, 3, 7
local BOX_X, TEXT_GAP, RADIO_TEXT_X, RADIO_PAD = 4, 7, 14, 45
local popout

local function RadioColour(b)
    local col
    if b.picked then col = NORMAL_FONT_COLOR
    elseif b.hover then col = HIGHLIGHT_FONT_COLOR
    else col = _G.VERY_LIGHT_GRAY_COLOR end
    b.radioText:SetTextColor(col:GetRGB())
end

local function RowEnter(b)
    b.hover = true
    if b.isRadio then b.radioBG:SetAlpha(0.15); RadioColour(b) else b.highlight:Show() end
    if b.opt and b.opt.tooltip then
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, b.opt.label)
        GameTooltip_AddNormalLine(GameTooltip, b.opt.tooltip)
        GameTooltip:Show()
    end
end
local function RowLeave(b)
    b.hover = nil
    if b.isRadio then b.radioBG:SetAlpha(0); RadioColour(b) else b.highlight:Hide() end
    GameTooltip:Hide()
end

local function Pick(b)
    local e, opt = popout.entry, b.opt
    if not (e and opt) then return end
    local setting = e.setting
    if opt.controlType == CHECKBOX then
        local v = setting:GetValue()
        setting:SetValue(bit.bxor(type(v) == "number" and v or 0, OptionBit(opt)))
        PlaySound(IsPicked(setting, opt) and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        popout:Fill()
    else
        setting:SetValue(opt.value)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        popout:Close()
    end
end

local function NewRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)
    b.highlight = b:CreateTexture(nil, "BACKGROUND")
    b.highlight:SetAllPoints()
    b.highlight:SetBlendMode("ADD")
    b.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.highlight:Hide()
    -- Fills the whole row, as Blizzard's does: in DarkMenuElementTemplate the texture has no <Anchors>, so XML
    -- stretches it over its setAllPoints parent and useAtlasSize does not apply (SharedUIPanelTemplates.xml:
    -- 1457-1466). Anchored at CENTER at the atlas's own size it was a small grey box mid-row (owner, 2026-11-03).
    b.radioBG = b:CreateTexture(nil, "BACKGROUND")
    b.radioBG:SetAtlas("common-dropdown-customize-mouseover")
    b.radioBG:SetAllPoints()
    b.radioBG:SetAlpha(0)
    b.box = b:CreateTexture(nil, "ARTWORK")
    b.box:SetAtlas("common-dropdown-ticksquare", true)
    b.box:SetPoint("LEFT", BOX_X, 0)
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetAtlas("common-dropdown-icon-checkmark-yellow", true)
    b.mark:SetPoint("CENTER", b.box, "CENTER", 2, 1)
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    b.text:SetHeight(ROW_H)
    b.text:SetPoint("LEFT", b.box, "RIGHT", TEXT_GAP, 1)
    b.radioText = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.radioText:SetHeight(ROW_H)
    b.radioText:SetJustifyH("LEFT")
    b.radioText:SetPoint("TOPLEFT", RADIO_TEXT_X, 0)
    b:SetScript("OnClick", Pick)
    b:SetScript("OnEnter", RowEnter)
    b:SetScript("OnLeave", RowLeave)
    return b
end

-- Returns the width the row's contents need, as the menu measures it.
local function SetupRow(b, opt, picked)
    b.opt, b.picked = opt, picked
    b.isRadio = opt.controlType ~= CHECKBOX
    b.highlight:Hide(); b.radioBG:SetAlpha(0)
    b.box:SetShown(not b.isRadio); b.text:SetShown(not b.isRadio); b.radioText:SetShown(b.isRadio)
    b.mark:SetShown(not b.isRadio and picked)
    b:Show()
    if b.isRadio then
        b.radioText:SetText(opt.label or "")
        RadioColour(b)
        return RADIO_TEXT_X + (b.radioText:GetStringWidth() or 0) + RADIO_PAD
    end
    b.text:SetText(opt.label or "")
    return BOX_X + (b.box:GetWidth() or 0) + TEXT_GAP + (b.text:GetStringWidth() or 0)
end

local function BuildPopout()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("common-dropdown-c-bg")
    bg:SetPoint("TOPLEFT", -17, 12)
    bg:SetPoint("BOTTOMRIGHT", 17, -22)
    f.rows = {}

    function f:Fill()
        local c, e = self.cover, self.entry
        if not (c and e) then return end
        local need, n = 0, 0
        for _, opt in ipairs(Options(e)) do
            n = n + 1
            local b = self.rows[n] or NewRow(self)
            self.rows[n] = b
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", INSET_L, -INSET_T - (n - 1) * ROW_H)
            need = math.max(need, SetupRow(b, opt, IsPicked(e.setting, opt)))
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].opt = nil end
        local interior = math.max(math.ceil(need), (c:GetWidth() or 0) - INSET_L - INSET_R)
        for i = 1, n do self.rows[i]:SetWidth(interior) end
        self:SetSize(interior + INSET_L + INSET_R, n * ROW_H + INSET_T + INSET_B)
        SyncText(c)
    end

    function f:Close()
        local c = self.cover
        self:Hide()
        self.entry, self.cover = nil, nil
        GameTooltip:Hide()
        if c then
            c.menu = nil
            PlaySound(_G.MenuVariants.GetDropdownCloseSoundKit())   -- as DropdownButtonMixin:OnMenuClosed
            Refresh(c)
        end
    end

    -- Closes on a click anywhere else, as Blizzard's menus do (Menu.lua:56-71); a click on the cover toggles.
    f:RegisterEvent("GLOBAL_MOUSE_DOWN")
    f:SetScript("OnEvent", function(self)
        if not self:IsShown() then return end
        if self:IsMouseOver() or (self.cover and self.cover:IsMouseOver()) then return end
        self:Close()
    end)
    f:SetScript("OnKeyDown", function(self, key)
        local stop = key == "ESCAPE"
        if not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, not stop) end
        if stop then self:Close() end
    end)
    f:SetScript("OnUpdate", function(self)
        local c = self.cover
        if not (c and c:IsShown() and c.entry == self.entry) then self:Close() end
    end)
    return f
end

local function OpenPopout(c)
    if not IsEnabled(c.entry) then return end
    popout = popout or BuildPopout()
    if popout:IsShown() and popout.cover == c then popout:Close(); return end
    if popout:IsShown() then popout:Close() end
    popout.entry, popout.cover = c.entry, c
    popout:ClearAllPoints()
    popout:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, 0)        -- Blizzard's menu anchor (DropdownButton.xml:6-9)
    popout:Fill()
    popout:EnableKeyboard(not InCombatLockdown())
    popout:Show()
    c.menu = popout
    PlaySound(_G.MenuVariants.GetDropdownOpenSoundKit())        -- as DropdownButtonMixin:OnMenuOpened
    Refresh(c)
end

-- A left mouse-down on the cover is ours to handle, as Blizzard's dropdowns answer (DropdownButton.lua:
-- 174-176), so a menu that happens to be open does not treat the click as "elsewhere".
local function HandlesGlobalMouseEvent(_, buttonName, event)
    return event == "GLOBAL_MOUSE_DOWN" and buttonName == "LeftButton"
end

-- The row's tooltips, as Blizzard's Settings tooltips (Settings.InitTooltip, Blizzard_Settings.lua:288-296: the
-- name as a highlight line, the text as a normal line; DefaultTooltipMixin:OnEnter, Blizzard_SettingControls.lua:
-- 26-38: ANCHOR_RIGHT, -10, 0 on the hovered frame). On a tooltip of our own built from the same template as
-- Blizzard's SettingsTooltip (SharedTooltipTemplate, Blizzard_SettingsPanel.xml:115) at its scale, so
-- Blizzard's SettingsTooltip is never written to.
local tip
local function ShowTip(owner, name, text)
    if not tip then tip = CreateFrame("GameTooltip", "VeritasUI_SettingsTooltip", UIParent, "SharedTooltipTemplate") end
    local st = _G.SettingsTooltip
    if st and st.GetEffectiveScale and UIParent.GetEffectiveScale then
        tip:SetScale(st:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    tip:SetOwner(owner, "ANCHOR_RIGHT", -10, 0)
    _G.GameTooltip_AddHighlightLine(tip, name or "")
    if text then GameTooltip_AddNormalLine(tip, text) end
    tip:Show()
end
local function HideTip() if tip then tip:Hide() end end

local function CoverEnter(c)
    c.over = c.enabled or nil
    Refresh(c)
    ShowTip(c, c.entry.name, c.entry.tooltip)
end
local function CoverLeave(c)
    c.over, c.down = nil, nil
    Refresh(c)
    HideTip()
end
local function CoverDown(c, button)
    if button == "LeftButton" and c.enabled then c.down = true; Refresh(c) end
end
local function CoverUp(c)
    if c.down then c.down = nil; Refresh(c) end
end

local function NewCover(init, parent)
    local c = CreateFrame("Button", nil, parent or _G.SettingsPanel)
    c.init, c.entry = init, entries[init]
    c:SetSize(DD_W, DD_H)
    c:EnableMouse(true)
    c:RegisterForClicks("LeftButtonDown")
    c.Background = c:CreateTexture(nil, "BACKGROUND")
    c.Background:SetPoint("TOPLEFT", -7, 7)
    c.Background:SetPoint("BOTTOMRIGHT", 7, -7)
    c.Arrow = c:CreateTexture(nil, "OVERLAY")
    c.Arrow:SetAtlas("common-dropdown-c-button-hover-arrow", true)
    c.Arrow:SetPoint("BOTTOM", 0, -5)
    c.Text = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.Text:SetHeight(20)
    c.Text:SetWordWrap(false)
    c.Text:SetJustifyH("CENTER")
    -- The row label, drawn by us because the header row under it has an empty title: GameFontNormal, left
    -- 37 in, ending 85 left of the row's centre (SettingsListElementMixin:Init, Blizzard_SettingControls.lua:331-335).
    -- A sub-option (spec.sub) is indented 15 in the same font, as a Blizzard row indented with Indent() and no
    -- parent link (GetIndent :230-232, indentSize :1; font :331) -- see VUI.SettingsSubOption below.
    c.Label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.Label:SetJustifyH("LEFT")
    c.Label:SetWordWrap(false)
    c.Label:SetText(c.entry.name or "")
    -- The rest of the row is ours too, so the mouse never reaches the header row underneath (its own tooltip
    -- is anchored to its pushed-out title: far off the panel and titled "..."). `Hover` is where a Blizzard row's
    -- Tooltip frame sits (row TOPLEFT to 80 left of BOTTOM, Blizzard_SettingControls.xml:57-67): it shows the
    -- row's tooltip and Blizzard's hover bar (HoverBackgroundTemplate, :5-11: row TOPLEFT -10 to BOTTOMRIGHT -5,
    -- white at 0.1). `Block` catches the rest of the row and does nothing. Both sit below the dropdown.
    -- Hover area and bar are the height of a Blizzard row (26, SettingsDropdownControlTemplate's Size,
    -- Blizzard_SettingControls.xml:121-126), centred on our row's centre as that row would be -- so, like
    -- Blizzard's, the bar sits 3 lower than the dropdown, which is drawn at centre +3 (owner, 2026-11-03: our bar
    -- was the header row's full 45 and too tall).
    c.Block = CreateFrame("Frame", nil, parent or _G.SettingsPanel)
    c.Block:EnableMouse(true)
    c.Block:Hide()
    c.Hover = CreateFrame("Frame", nil, parent or _G.SettingsPanel)
    c.Hover:EnableMouse(true)
    c.Hover:Hide()
    c.Hover.Bar = c.Hover:CreateTexture(nil, "BACKGROUND")
    c.Hover.Bar:SetColorTexture(1, 1, 1, 0.1)
    c.Hover.Bar:Hide()
    c.Hover:SetScript("OnEnter", function(h)
        h.Bar:Show()
        ShowTip(h, c.entry.name, c.entry.tooltip)
    end)
    c.Hover:SetScript("OnLeave", function(h) h.Bar:Hide(); HideTip() end)
    c:SetScript("OnShow", function(self) self.Block:Show(); self.Hover:Show() end)
    c.HandlesGlobalMouseEvent = HandlesGlobalMouseEvent
    c:SetScript("OnClick", OpenPopout)
    c:SetScript("OnEnter", CoverEnter)
    c:SetScript("OnLeave", CoverLeave)
    c:SetScript("OnMouseDown", CoverDown)
    c:SetScript("OnMouseUp", CoverUp)
    c:SetScript("OnHide", function(self)
        self.over, self.down = nil, nil
        self.Block:Hide(); self.Hover:Hide(); self.Hover.Bar:Hide()
        if self.menu then local m = self.menu; self.menu = nil; pcall(m.Close, m) end
    end)
    c:Hide()
    return c
end

-- Each frame while Options is open: put a cover where Blizzard's dropdown would be on every row of ours that
-- is on screen, hide the rest. Reads the list's rows only; writes nothing on them.
-- The covers live in a frame of ours laid over the list's scroll box that clips its children, so a row half
-- scrolled out is cut at the list's edge as Blizzard's rows are (owner's screenshot, 2026-11-03: Hide Transforms
-- drawn below the bottom edge). Anchoring to the scroll box writes nothing on it.
local seen = {}
local clipper
local function Clipper(panel, scrollBox)
    if not clipper then
        clipper = CreateFrame("Frame", nil, panel)
        clipper:SetClipsChildren(true)
    end
    if scrollBox and clipper.box ~= scrollBox then
        clipper.box = scrollBox
        clipper:ClearAllPoints()
        clipper:SetAllPoints(scrollBox)
        clipper:SetFrameStrata(panel:GetFrameStrata())
        clipper:SetFrameLevel(scrollBox:GetFrameLevel() + 5)
    end
    return clipper
end
local function Track()
    local panel = _G.SettingsPanel
    local ok, list = pcall(panel.GetSettingsList, panel)
    local target = ok and list and list.ScrollBox and list.ScrollBox.ScrollTarget
    wipe(seen)
    if target then
        local clip = Clipper(panel, list.ScrollBox)
        for _, row in ipairs({ target:GetChildren() }) do
            local get = row.GetElementData
            local init = get and row:IsVisible() and get(row)
            if init and entries[init] then
                seen[init] = true
                local c = covers[init] or NewCover(init, clip)
                covers[init] = c
                if c.row ~= row then
                    c.row = row
                    c:ClearAllPoints()
                    c:SetPoint("CENTER", row, "CENTER", DD_X, DD_Y)
                    c.Label:ClearAllPoints()
                    c.Label:SetPoint("LEFT", row, "LEFT", LABEL_X + (c.entry.sub and SUB_INDENT or 0), 0)
                    c.Label:SetPoint("RIGHT", row, "CENTER", LABEL_RIGHT, 0)
                    c:SetFrameStrata(panel:GetFrameStrata())
                    c:SetFrameLevel(math.max(row:GetFrameLevel() + 10, clip:GetFrameLevel() + 3))
                    local level = c:GetFrameLevel()
                    c.Block:ClearAllPoints()
                    c.Block:SetAllPoints(row)
                    c.Block:SetFrameStrata(panel:GetFrameStrata())
                    c.Block:SetFrameLevel(level - 2)
                    c.Hover:ClearAllPoints()
                    c.Hover:SetPoint("TOPLEFT", row, "LEFT", 0, ROW_HALF)
                    c.Hover:SetPoint("BOTTOMRIGHT", row, "CENTER", -80, -ROW_HALF)
                    c.Hover:SetFrameStrata(panel:GetFrameStrata())
                    c.Hover:SetFrameLevel(level - 1)
                    c.Hover.Bar:ClearAllPoints()
                    c.Hover.Bar:SetPoint("TOPLEFT", row, "LEFT", -10, ROW_HALF)
                    c.Hover.Bar:SetPoint("BOTTOMRIGHT", row, "RIGHT", -5, -ROW_HALF)
                    c.lastText = nil
                    Refresh(c)
                end
                SyncText(c)
                if not c:IsShown() then c:Show() end
            end
        end
    end
    for init, c in pairs(covers) do
        if not seen[init] and c:IsShown() then c:Hide(); c.row = nil end
    end
end

local driver
local function StartTracking()
    if driver or not _G.SettingsPanel then return end
    driver = CreateFrame("Frame", nil, _G.SettingsPanel)    -- runs only while Options is shown
    driver:SetScript("OnUpdate", Track)
end

-- ── PROBE (trial, 2026-11-03): /vui probe search ────────────────────────────
-- Lists every Options list row whose fields Options search reads (FindInitializersMatchingSearchText and its
-- caller, Blizzard_SettingsPanel.lua:575-695) and are not secure, by issecurevariable, with who tainted them.
-- Diagnosis only: /reload afterwards. Walks categories the way search does (:604-610).
local PROBE_KEYS = { "searchTags", "searchIgnoredLayouts", "parentInitializer", "shownPredicates", "data" }
function VUI.ProbeSearchTaint()
    local panel, issecurevariable = _G.SettingsPanel, _G.issecurevariable
    if not (panel and panel.GetAllCategories and issecurevariable) then
        print("VeritasUI probe: SettingsPanel or issecurevariable missing"); return
    end
    local lines, perCat, total = {}, {}, 0
    local function Walk(cat)
        local ok, layout = pcall(panel.GetLayout, panel, cat)
        if not (ok and layout and layout.IsVerticalLayout and layout:IsVerticalLayout()) then return end
        local catName = (cat.GetName and cat:GetName()) or "?"
        for _, init in layout:EnumerateInitializers() do
            local bad = {}
            for _, key in ipairs(PROBE_KEYS) do
                local secure, by = issecurevariable(init, key)
                if not secure then bad[#bad + 1] = key .. "(" .. tostring(by) .. ")" end
            end
            if #bad > 0 then
                total = total + 1
                perCat[catName] = (perCat[catName] or 0) + 1
                local okN, nm = pcall(init.GetName, init)
                local okT, tpl = pcall(init.GetTemplate, init)
                lines[#lines + 1] = ("%s | %s | %s | %s"):format(catName, tostring(okN and nm or "?"),
                    tostring(okT and tpl or "?"), table.concat(bad, " "))
            end
        end
    end
    for _, cat in ipairs(panel:GetAllCategories()) do
        Walk(cat)
        local subs = cat.GetSubcategories and cat:GetSubcategories()
        if type(subs) == "table" then for _, sub in pairs(subs) do Walk(sub) end end
    end
    print(("VeritasUI probe: %d rows with insecure search fields"):format(total))
    for cat, n in pairs(perCat) do print(("  %s: %d"):format(cat, n)) end
    for i = 1, math.min(#lines, 60) do print("  " .. lines[i]) end
    if #lines > 60 then print(("  ... %d more"):format(#lines - 60)) end
end

-- Adds the row to `layout` and returns its initializer.
-- spec = { category = <the page's category>, setting = <Settings.RegisterAddOnSetting result>, name = "Label",
--          getOptions = function() return Settings.CreateControlTextContainer() data end, tooltip = "text",
--          isEnabled = function?, sub = true for a sub-option (indented; greying comes from isEnabled) }
local tagCount, tagStore = 0, {}
local TAG_PAD = string.rep(" ", 400)
local function TagSetting(category, label)
    if not (category and Settings.RegisterAddOnSetting and type(label) == "string") then return nil end
    tagCount = tagCount + 1
    local key = "tag" .. tagCount
    tagStore[key] = false
    local ok, s = pcall(Settings.RegisterAddOnSetting, category, "VeritasUI_SearchTag" .. tagCount, key, tagStore,
        "boolean", TAG_PAD .. label, false)
    return ok and s or nil
end

function VUI.AddCoverDropdown(layout, spec)
    if not (layout and layout.AddInitializer and Settings and Settings.CreateElementInitializer) then return nil end
    local tag = Settings.CreateSettingInitializer and TagSetting(spec.category, spec.name)
    local init
    if tag then
        local ok, made = pcall(Settings.CreateSettingInitializer, "SettingsListSectionHeaderTemplate",
            { setting = tag, tooltip = spec.tooltip })
        init = ok and made or nil
    end
    init = init or Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate",
        { name = "", tooltip = spec.tooltip })
    entries[init] = {
        setting = spec.setting, name = spec.name, tooltip = spec.tooltip,
        getOptions = spec.getOptions, isEnabled = spec.isEnabled, sub = spec.sub,
    }
    layout:AddInitializer(init)
    StartTracking()
    return init
end

-- A sub-option the way Blizzard's own pages indent one without a parent link (Nameplates.lua:435-465 Indent();
-- AdvancedOptions.lua:172-182 AddEvaluateStateCVar): indented 15, greyed by `isOn`, and re-checked the moment
-- the parent setting `parentVariable` changes (SettingsListElementMixin:Init, Blizzard_SettingControls.lua:324-
-- 329: the "cvar" is any setting variable in Settings' callback registry).
-- ⚠ NOT SetParentInitializer: Options search reads `initializer.parentInitializer` of every match
-- (Blizzard_SettingsPanel.lua:674-675). Written from our code it is tainted, and the search runs tainted
-- (owner's taint 2.log, 2026-11-03: L233371 reading parentInitializer, then SettingsPanel.lua:695 DisplayLayout
-- wrote the list's updateLock tainted, L357077).
function VUI.SettingsSubOption(init, parentVariable, isOn)
    if type(init) ~= "table" then return end
    if init.Indent then init:Indent() end
    if isOn and init.AddModifyPredicate then init:AddModifyPredicate(isOn) end
    if parentVariable and init.AddEvaluateStateCVar then init:AddEvaluateStateCVar(parentVariable) end
end
