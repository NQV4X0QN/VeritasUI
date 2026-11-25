-- VeritasUI_Lib / SuiteLook.lua
-- Our windows in another UI suite's look, when the player uses one (owner, 2026-11-24: "I'd want it to look like it
-- was designed for Daylight"). Without one, nothing here does anything and every window keeps Blizzard's look.
--
-- DaylightUI 2.2.7 (WoW Forever), its public API (DaylightUI/API.md "Skin another addon's window"):
--   DaylightUI.API.For(name).RegisterSkin(addon, fn) -- fn(Kit) runs once `addon` has loaded and its Skins module is
--   on (API.lua:1911-1926; Skins Engine.lua:68-81: once, out of combat; an error names us once in chat and stops
--   that skin). Returns false while its Skins module is off: then nothing is dressed.
--   Kit.Window(frame) strips the window's own art and gives it its shell, title and close X (Skins Kit.lua:651-697);
--   Kit.Auto(root) dresses every standard control under it -- buttons, checkboxes, tabs, scroll bars, edit boxes,
--   dropdowns, list rows -- and is safe to run again (Kit.lua:2282-2350); Kit.SideTab(tab, isSelected) an icon tab
--   down a window's side (Kit.lua:1522-1559); Kit.RepaintRow(row) after its selection changed (Kit.lua:1444).
-- Kit is one table for the session (ns.Kit, passed to every skin), so it is kept and used as our windows are built:
-- they are made when first opened, long after the skin ran.
--
-- The windows are found through VUI.AnnounceFrame keys their modules already announce. Each is dressed once, out of
-- combat; controls a tab builds later are dressed when the window shows again (Kit.Auto skips what is done).

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, pairs, type = pcall, ipairs, pairs, type

local kit                 -- DaylightUI's Kit, once its skin has run
local waiting = {}        -- frames announced before that: { frame, how }
local dressed = setmetatable({}, { __mode = "k" })

local function IsSideTab(f)
    return type(f) == "table" and type(f.Icon) == "table" and type(f.SelectedTexture) == "table"
end
local function TabSelected(tab) return tab.SelectedTexture:IsShown() == true end

-- Its windows have no tabs on their edge: the pages are words along the header, right to left from the close X, the
-- picked one in the accent with a line under it (owner, 2026-11-25, its character window). DaylightUI 2.2.7
-- Windows/Frame.lua Win.Tabs :215-260 (gap 14, text size body), Character/Window.lua LayoutTabs :127-147 (each as wide
-- as its word plus 4, at least 30), Options/Widgets.lua W.Tab :1712 (24 high). The look itself is its public
-- Kit.Tab (Skins Kit.lua:1598: a button with a Text and no Icon gets W.TabLook, tan at rest, light on hover, the
-- accent and an underline when picked), driven through Kit.TabOf(tab).Pick. Lib's VUI.CreateSideTabs keeps its
-- tabs on win._sideTabs; they stay (the module still shows, hides, places and selects them) but out of sight and
-- out of reach, and each header tab follows its side tab's shown state.
local TAB_GAP, TAB_H, TAB_PAD, TAB_MIN = 14, 24, 4, 30
local function HeaderTabs(Kit, win)
    local st = win._sideTabs
    local api = VUI.SuiteAPI()
    if type(st) ~= "table" or st.header or not (api and api.Text) then return false end
    local close = win.CloseButton
    if type(close) ~= "table" then return false end
    local head = {}
    local clicked
    local function Layout()
        local right = close
        for i = #head, 1, -1 do
            local b, side = head[i], st.list[i]
            local on = side and side:IsShown() == true
            b:SetShown(on)
            if on then
                local w = b.Text:GetStringWidth()
                b:SetWidth(math.max(TAB_MIN, math.ceil(type(w) == "number" and w or 0) + TAB_PAD))
                b:ClearAllPoints()
                b:SetPoint("RIGHT", right, "LEFT", -TAB_GAP, 0)
                right = b
            end
        end
        if win.OnHeaderTabs then win.OnHeaderTabs(right ~= close and right or nil) end
    end
    for i, spec in ipairs(st.specs) do
        local b = CreateFrame("Button", nil, win)
        b:SetHeight(TAB_H)
        b.Text = api.Text(b, "body", "CENTER")
        b.Text:SetPoint("CENTER", b, "CENTER", 0, 1)
        b.Text:SetText(spec.label or spec.tooltip or "")
        b:SetScript("OnClick", function()
            if st.selected == i then return end
            clicked = i
            st.onSelect(i)
            clicked = nil
        end)
        Kit.Tab(b, function() return st.selected == i end)
        head[i] = b
        local side = st.list[i]
        if side then
            side:SetAlpha(0)
            if side.EnableMouse then side:EnableMouse(false) end
            side:HookScript("OnShow", Layout)
            side:HookScript("OnHide", Layout)
        end
    end
    st.header = head
    st.Pick = function(index)
        local TabOf = Kit.TabOf
        for i, b in ipairs(head) do
            local t = type(TabOf) == "function" and TabOf(b)
            if t and t.Pick then t.Pick(i == index, clicked == i) end
        end
    end
    if st.selected then st.Pick(st.selected) end
    -- The page's name is the picked tab now; a second copy under the title is not needed.
    if win.suiteSubtitle then win.suiteSubtitle:Hide() end
    local name = win.GetName and win:GetName()
    if name then
        VUI.HeaderTabWindows[name] = true
        VUI.SetManagedPanelExtraWidth(name, nil)
    end
    win:HookScript("OnShow", Layout)   -- a word's width is only right once its font has loaded
    Layout()
    return true
end
local function SideTabs(Kit, win)
    if HeaderTabs(Kit, win) then return end
    for _, child in ipairs({ win:GetChildren() }) do
        if IsSideTab(child) then Kit.SideTab(child, TabSelected) end
    end
end

-- Its header (owner, 2026-11-25: our tabs and X sat too high, the title above where its character window has its
-- name). DaylightUI 2.2.7 Windows/Frame.lua Win.Header :167-211: the title at the edge (16) and 12 down
-- (Win.TITLE_Y :27), title size; a sub line 4 under it, small size; the X at TOPRIGHT -9, -15 on a full header
-- (Win.CLOSE_X, Win.CloseY :26-31). Kit.Window puts a skinned window's title 6 down (Skins Kit.lua:547-554) and
-- leaves the game's X where it was. The tabs are anchored to the X, so they come down with it. Character/Window.lua
-- :161 colours the name in the class colour (Style.ClassColor, public as API.ClassColor); a window asks for that
-- with win.suiteClassColor. Kit.Light keeps the colour: Kit.Window relights its title on every show.
local function ClosePlace(win)
    local close = win.CloseButton
    if type(close) ~= "table" then return end
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -9, -15)
end
local function Header(Kit, win)
    ClosePlace(win)
    local tc = win.TitleContainer
    local title = (type(tc) == "table" and tc.TitleText) or win.TitleText
    if type(title) ~= "table" then return end
    local api = VUI.SuiteAPI()
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -12)
    title:SetJustifyH("LEFT")
    local sub = win.suiteSub
    if sub then
        if Kit.Font then Kit.Font(sub, 12) end
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetJustifyH("LEFT")
    end
    if win.suiteClassColor and api and api.ClassColor and Kit.Light then
        local ok, _, classFile = pcall(UnitClass, "player")
        if ok and classFile then
            local r, g, b = api.ClassColor(classFile)
            if type(r) == "number" then
                Kit.Light(title, { r, g, b })
                if sub then Kit.Light(sub, { r, g, b }) end
            end
        end
    end
    -- The title stops short of the tabs.
    win.OnHeaderTabs = win.OnHeaderTabs or function(left)
        title:SetPoint("RIGHT", left or win, left and "LEFT" or "RIGHT", left and -14 or -40, 0)
    end
end

local HOW = {}
-- A whole window: its shell, then every control in it; its header as its own, its tabs into the header.
function HOW.window(Kit, win)
    Kit.Window(win)
    Kit.Auto(win)
    Header(Kit, win)
    SideTabs(Kit, win)
    win:HookScript("OnShow", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then pcall(Kit.Auto, self) end
    end)
end
-- A control or a row built after its window (Priority Rotation's step rows): its controls only.
function HOW.part(Kit, f) Kit.Auto(f) end

-- Colours and sizes of its bag slots, which its API does not hand out (DaylightUI_Bags/Items.lua 2.2.7, read
-- 2026-11-25): Style.BORDER for the backing (DaylightUI/Style.lua:296; Items.lua:27); an empty slot's ring and the
-- well inside it (Items.lua:76-77), a common item's ring (:78); ring 1 px empty, 2 px filled, with one black pixel
-- outside it and one between it and the icon or well (Items.lua:23-26); the slot's highlight, white at 12% over the
-- icon (:559-560, :683-684); the icon's inner shadow, black at 55% (:69-70, :500-502); a hovered ring eased all the
-- way to the accent (:130, :437-473).
VUI.SUITE_BORDER = { 0.024, 0.024, 0.027 }
local SLOT_RING_EMPTY, SLOT_WELL, SLOT_RING_FULL = { 0.165, 0.149, 0.125 }, { 0.063, 0.063, 0.071 }, { 0.6, 0.6, 0.6 }

local function Fill(tex, c) tex:SetColorTexture(c[1], c[2], c[3], 1) end
local function Inset(tex, btn, n)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", n, -n)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -n, n)
end
-- n screen pixels in `frame`'s units, as its slots are measured in whole pixels (its Pixel.Px is not public).
local function Px(frame, n)
    local _, h = GetPhysicalScreenSize()
    local s = frame:GetEffectiveScale()
    if type(h) ~= "number" or h <= 0 or type(s) ~= "number" or s <= 0 then return n end
    return n * (768 / h) / s
end

-- An icon slot in its bags' look (owner, 2026-11-25: "take from the empty bag slots that DaylightUI uses"). The ring
-- is DaylightUI's own shell (API.Skin passes the shell options its bags use straight through, API.lua:995-1002;
-- Items.lua:27-37, 47-67), recoloured through the Kit (Kit.Paint, Kit.lua:216-232). `btn.tex` is the icon; it says
-- empty or filled by being hidden or shown.
function VUI.SuiteSlot(btn)
    local api = VUI.SuiteAPI()
    if not (api and type(api.Skin) == "function") or type(btn) ~= "table" or type(btn.tex) ~= "table"
        or btn.suiteSlot then return end
    local thin = not btn.tex:IsShown()
    local opts = { noBevel = true, noBackground = true, shadowPx = 0, shadowAlpha = 0 }
    opts.borderPx = function() return thin and 1 or 2 end
    local shell = api.Skin(btn, opts)
    if type(shell) ~= "table" or not shell.CreateTexture then return end
    if btn.border then btn.border:SetAlpha(0) end
    if btn.empty then btn.empty:SetAlpha(0) end
    local back = shell:CreateTexture(nil, "BACKGROUND", nil, -7)
    Fill(back, VUI.SUITE_BORDER)
    back:SetAllPoints(btn)
    local well = shell:CreateTexture(nil, "BACKGROUND", nil, -6)
    Fill(well, SLOT_WELL)
    local shadeFile = api.Media and api.Media("inner-shadow.png")
    local shade = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    if shadeFile then shade:SetTexture(shadeFile) end
    shade:SetVertexColor(0, 0, 0, 0.55)
    shade:SetAllPoints(btn.tex)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 1, 1, 0.12)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hovered = false
    local function Paint()
        local c = thin and SLOT_RING_EMPTY or SLOT_RING_FULL
        if hovered then local r, g, b = api.Accent(); c = { r, g, b } end
        if kit and kit.Paint then pcall(kit.Paint, shell, c) end
    end
    local function Layout()
        local e = Px(btn, 1)
        shell:ClearAllPoints()
        shell:SetPoint("TOPLEFT", btn, "TOPLEFT", e, -e)
        shell:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -e, e)
        api.Skin(btn, opts)                       -- lays the shell out again at its new size and ring width
        local inner = Px(btn, 1 + (thin and 1 or 2) + 1)
        Inset(well, btn, inner)
        Inset(btn.tex, btn, inner)
        well:SetShown(thin)
        shade:SetShown(not thin)
        hl:ClearAllPoints()
        hl:SetAllPoints(thin and well or btn.tex)
        Paint()
    end
    local function Set(filled)
        thin = not filled
        Layout()
    end
    btn:HookScript("OnEnter", function() hovered = true; Paint() end)
    btn:HookScript("OnLeave", function() hovered = false; Paint() end)
    hooksecurefunc(btn.tex, "Show", function() Set(true) end)
    hooksecurefunc(btn.tex, "Hide", function() Set(false) end)
    Layout()
    btn.suiteSlot = Set
end

-- DaylightUI's own class icons (owner, 2026-11-25: use them in place of Blizzard's): its unit frames' set, files in
-- its Media\class folder used where they are, through API.Media (DaylightUI_UnitFrames/UnitFrames.lua:471-475).
-- Round art on a clear square, drawn a little larger than the round opening it sits in (UF.CLASS_ICON_FILL 2.3:
-- 1.15 times the opening, UnitFrames.lua:358-360). Its other icon styles (an icon pack) are left out. nil without it.
local CLASS_ART = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
                    MAGE = true, WARLOCK = true, DRUID = true }
VUI.SUITE_CLASS_ICON_FILL = 1.15
function VUI.SuiteClassIcon(classFile)
    local api = VUI.SuiteAPI()
    if not (api and type(api.Media) == "function") or not CLASS_ART[classFile] then return nil end
    return api.Media("class\\" .. string.lower(classFile) .. ".tga")
end

-- Priority Rotation's step rows: no mount-list block behind them (row.cardArt, Editor.lua), and their icon and
-- After slots in the bags' look.
function HOW.prRow(Kit, row)
    for _, t in ipairs(row.cardArt or {}) do t:SetAlpha(0) end
    VUI.SuiteSlot(row.iconBtn)
    VUI.SuiteSlot(row.followBtn)
    Kit.Auto(row)
end
-- The Compiled Sequence card: no block either; the window's own background shows through.
function HOW.prCard(Kit, card)
    for _, t in ipairs(card.cardArt or {}) do t:SetAlpha(0) end
    Kit.Auto(card)
end
-- The trainer window draws its own DaylightUI-style list (Trainer.lua), so its rows are left to it.
function HOW.ownList(Kit, win)
    Kit.Window(win)
    Kit.Auto(win, { rows = false })
    ClosePlace(win)   -- its own header is laid out to DaylightUI's already (Trainer.lua); the X is the game's
    SideTabs(Kit, win)
    win:HookScript("OnShow", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then pcall(Kit.Auto, self, { rows = false }) end
    end)
end

-- Its options window's slider and reset arrow (owner, 2026-11-25: Advanced Options' sliders showed only their knob,
-- once the shell hid the template's track). Its Options/Widgets.lua 2.2.7: W.SliderLook (:2587-2630) a 4 px
-- ui-pill.png track tinted Theme `track` (#2c2c32, Options/Theme.lua:27) under a fill of the same art in the
-- Daylight gradient (#1e90ff to #e65a72, Style.lua:661; W.TintDaylight :127-137), a white ui-knob.png knob 12 px,
-- 14 while hovered or held (:21); the value in a box 60 wide (:20, W.Slider :2641-2652) drawn as W.InputLook
-- (:1367-1384): ui-round.png nine-slice tinted `control` (#222227) with a ui-round-line.png edge in `cardEdge`
-- (#2a2a30), slice margin 10 (:165-177). The reset arrow (resetArrow, :3620-3645): ui-reset.png at 14 tinted `faint`
-- (INK.OFF), the gradient on hover, shown only while the row is off its default. All its art is used where it is,
-- through API.Media.
local function Hex(h)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end
local TRACK, CONTROL, CARD_EDGE = Hex("2c2c32"), Hex("222227"), Hex("2a2a30")
local GRAD_A, GRAD_B = { 0.118, 0.565, 1 }, { 0.902, 0.353, 0.447 }
local function Gradient(tex)
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(GRAD_A[1], GRAD_A[2], GRAD_A[3], 1),
            CreateColor(GRAD_B[1], GRAD_B[2], GRAD_B[3], 1))
    end
end
local function Round(parent, api, layer, sub, outline)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetTexture(api.Media(outline and "ui-round-line.png" or "ui-round.png"))
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(10, 10, 10, 10)
        if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
    return t
end

function HOW.aoSlider(_, sl)
    local api = VUI.SuiteAPI()
    if not (api and api.Media) then return end
    local track = sl:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(api.Media("ui-pill.png"))
    track:SetPoint("LEFT", sl, "LEFT", 0, 0)
    track:SetPoint("RIGHT", sl, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetVertexColor(TRACK[1], TRACK[2], TRACK[3], 1)
    local fill = sl:CreateTexture(nil, "BORDER")
    fill:SetTexture(api.Media("ui-pill.png"))
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(4)
    Gradient(fill)
    sl:SetThumbTexture(api.Media("ui-knob.png"))
    local thumb = sl:GetThumbTexture()
    local held = false
    local function Knob(big)
        if thumb then thumb:SetSize(big and 14 or 12, big and 14 or 12); thumb:SetVertexColor(1, 1, 1, 1) end
    end
    Knob(false)
    local function PaintFill()
        local lo, hi = sl:GetMinMaxValues()
        local v, w = sl:GetValue(), sl:GetWidth()
        local frac = (type(lo) == "number" and type(hi) == "number" and hi > lo) and (v - lo) / (hi - lo) or 0
        fill:SetWidth(math.max(0.01, math.min(1, math.max(0, frac)) * (tonumber(w) or 0)))
    end
    sl:HookScript("OnValueChanged", PaintFill)
    sl:HookScript("OnSizeChanged", PaintFill)
    sl:HookScript("OnShow", PaintFill)
    sl:HookScript("OnEnter", function() Knob(true) end)
    sl:HookScript("OnLeave", function() Knob(held) end)
    sl:HookScript("OnMouseDown", function() held = true; Knob(true) end)
    sl:HookScript("OnMouseUp", function() held = false; Knob(sl:IsMouseOver()) end)
    PaintFill()
    -- The value, centred in its input-look box. The box is drawn on the row itself, under the value: a frame of its
    -- own covered the value and ran over the reset arrow (owner, 2026-11-25). It reaches to the reset button.
    local val, row, reset = sl._valText, sl:GetParent(), sl._resetBtn
    if val and row then
        local bg = Round(row, api, "BACKGROUND", 2, false)
        local edge = Round(row, api, "BACKGROUND", 3, true)
        for _, t in ipairs({ bg, edge }) do
            t:SetPoint("TOPLEFT", sl, "RIGHT", 8, 11)
            if reset then
                t:SetPoint("BOTTOMRIGHT", reset, "LEFT", -4, -11)
            else
                t:SetPoint("BOTTOMRIGHT", sl, "RIGHT", 68, -11)
            end
        end
        bg:SetVertexColor(CONTROL[1], CONTROL[2], CONTROL[3], 1)
        edge:SetVertexColor(CARD_EDGE[1], CARD_EDGE[2], CARD_EDGE[3], 1)
        val:ClearAllPoints()
        val:SetPoint("CENTER", bg, "CENTER", 0, 0)
        val:SetJustifyH("CENTER")
        local white = api.Colors().VALUE
        if white then val:SetTextColor(white[1] or white.r, white[2] or white.g, white[3] or white.b) end
    end
end

function HOW.aoReset(_, btn)
    local api = VUI.SuiteAPI()
    if not (api and api.Media) or not btn._icon then return end
    -- Hidden, not faded: the button's UpdateState sets the game icon's alpha on every change, which brought it back
    -- over this arrow (owner, 2026-11-25).
    btn._icon:Hide()
    if btn._hover then btn._hover:SetAlpha(0) end
    local arrow = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    arrow:SetTexture(api.Media("ui-reset.png"))
    arrow:SetSize(14, 14)
    arrow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local faint = api.Colors().OFF or { 0.55, 0.51, 0.45 }
    local function Rest() arrow:SetVertexColor(faint[1] or faint.r, faint[2] or faint.g, faint[3] or faint.b, 1) end
    Rest()
    btn:HookScript("OnEnter", function(self) if self:IsEnabled() then Gradient(arrow) end end)
    btn:HookScript("OnLeave", Rest)
    -- Shown only while its row is off the default, as its own rows' arrows are.
    local function Show() btn:SetAlpha(btn:IsEnabled() and 1 or 0) end
    hooksecurefunc(btn, "UpdateState", Show)
    Show()
end

local function Dress(frame, how)
    if dressed[frame] or not kit then return end
    if InCombatLockdown and InCombatLockdown() then
        VUI.CombatQueue.Add(function() Dress(frame, how) end)
        return
    end
    dressed[frame] = true
    local ok, err = pcall(HOW[how], kit, frame)
    if not ok and VUI.debug then VUI.Print("Lib", "SuiteLook: " .. tostring(err)) end
end

local function Want(frame, how)
    if type(frame) ~= "table" then return end
    if kit then Dress(frame, how) else waiting[#waiting + 1] = { frame, how } end
end

-- Repaints a side tab after Lib's VUI.CreateSideTabs moved the selection (the Kit repaints on a click itself).
function VUI.SuiteLookRepaint(tab)
    if kit and type(kit.RepaintRow) == "function" then pcall(kit.RepaintRow, tab) end
end
function VUI.SuiteLookOn() return kit ~= nil end
-- DaylightUI's public API while our windows wear its look (its Skins module on), else nil. For a module that
-- lays a window out in that look itself (Trainer.lua): Text, Colors, Accent, Media.
function VUI.SuiteAPI()
    if not kit then return nil end
    local a = _G.DaylightUI and _G.DaylightUI.API
    if type(a) == "table" and type(a.Text) == "function" and type(a.Colors) == "function" then return a end
    return nil
end

for key, how in pairs({
    ["PriorityRotation.Window"] = "window",
    ["AdvancedOptions.Window"] = "window",
    ["QualityOfLife.TrainerWindow"] = "ownList",
    ["PriorityRotation.EditorRow"] = "prRow",
    ["PriorityRotation.SequenceCard"] = "prCard",
    ["AdvancedOptions.Slider"] = "aoSlider",
    ["AdvancedOptions.ResetButton"] = "aoReset",
}) do
    VUI.OnFrameBuilt(key, function(frame) Want(frame, how) end)
end

-- DaylightUI loads first (VeritasUI_Lib's OptionalDeps), so its API is here at our file load.
local api = _G.DaylightUI and _G.DaylightUI.API
if type(api) == "table" and api.major == 1 and type(api.For) == "function" then
    local me = api.For("VeritasUI")
    if type(me) == "table" and type(me.RegisterSkin) == "function" then
        pcall(me.RegisterSkin, "VeritasUI_Lib", function(Kit)
            if type(Kit) ~= "table" or type(Kit.Window) ~= "function" or type(Kit.Auto) ~= "function" then
                return true
            end
            kit = Kit
            local list = waiting
            waiting = {}
            for _, w in ipairs(list) do Dress(w[1], w[2]) end
            return true
        end)
    end
end
