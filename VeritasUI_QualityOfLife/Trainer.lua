-- VeritasUI_QualityOfLife / Trainer.lua
-- WoW Forever: new class skills at your trainer (owner's request, 2026-11-05). A class-icon button by the minimap
-- shows when your class trainer has something for your level; it opens a read-only copy of the trainer window
-- (no Train buttons) listing what you can learn now and what comes later. `/qol trainable` prints the same list.
--
-- WHERE THE LIST COMES FROM -- the trainer, saved at each visit:
--   MEASURED (owner, Forever, level 7): the spellbook lists NO future spells, and shows no rank for ranked
--   spells (only "Racial" / "Passive"), so it can say neither what is coming nor which rank you know.
--   SOURCED (Gethe wow-ui-source, forever branch, Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua): the trainer
--   window reads each service with GetTrainerServiceInfo(i) -> name, serviceType ("available" / "unavailable" /
--   "used"), texture, reqLevel, subText (:618), GetTrainerServiceCost (:692), GetTrainerServiceNumAbilityReq /
--   GetTrainerServiceAbilityReq -> name, met (:648-660); C_Trainer.GetTrainerType() (General 0, Tradeskills 2,
--   Pet 3). They answer only while the trainer window is open, so the list is copied on TRAINER_SHOW and on every
--   TRAINER_UPDATE (which follows a purchase, :279-294). MEASURED (owner): 119 services, every later level
--   included, with the trainer's default filters (Available + Unavailable, not Already Known) -- so a spell you
--   buy drops out of the saved list at once. Learned without the trainer: a spellbook spell of the same name and
--   sub-text (works for unranked spells only).
--
-- THE BUTTON copies the AddOn button's look (Camelot/AddonCompartment.xml: 23 x 22, atlas
-- ui-hud-minimap-addon-indicator, the same atlas in ADD at 0.1 hover / 0.2 pressed) with the class icon
-- (Interface\Icons\ClassIcon_<CLASS>) in the frame's opening: measured from the art (atlas 3945, the -2x rect
-- 911-957 x 509-553) as 31 x 23 at 2x -> 11.5 tall at 1x, centred, 1 px above the frame's centre. PLACE: 1 px
-- under the tracking button (MinimapCluster.Tracking.Button, 23 x 23, left of the zone text; Mainline/Minimap.xml
-- forever), left of the mail icon -- owner moved it there in game (Forever's mail icon is much larger than
-- Retail's and the button looked odd under it) and set the gap to match the calendar-to-compartment gap.
-- Without a tracking button: the mail spot
-- (MinimapCluster.IndicatorFrame), or under the mail icon. Parented to UIParent and only READS Blizzard's frames
-- (MinimapCluster is an Edit Mode system, landmine 114).
--
-- THE WINDOW is our own frame built to the trainer window's measurements (Blizzard_TrainerUI.xml forever):
-- ButtonFrameTemplate 338 x 424; list 302 x 330 at the Inset's TOPLEFT +5,-5 with MinimalScrollBar; the
-- TrainerTextures backdrop around it (-3,4 / 3,-4); rows 47 high (CLASS_TRAINER_SKILL_HEIGHT) with the trainer
-- row art, a 36 px icon at LEFT 6, name GameFontNormal, "(Rank 2)" GameFontNormalSmall, requirements
-- SystemFont_Shadow_Small, cost SmallMoneyFrameTemplate TOPRIGHT 5,-7; your money bottom-left on the money border.
-- Blizzard's own ClassTrainerFrame is not used: it lives in a load-on-demand addon and its code reads the open
-- trainer.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, format = pcall, ipairs, string.format

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function CharKey()
    local ok, name = pcall(UnitName, "player")
    local okR, realm = pcall(GetRealmName)
    return format("%s-%s", okR and realm or "?", ok and name or "?")
end
local function Level() local ok, l = pcall(UnitLevel, "player"); return ok and l or 0 end

-- ── Spellbook (learned without the trainer) ──────────────────
local function ForEachSpellBookItem(fn)
    local sb = _G.C_SpellBook
    if not (sb and sb.GetNumSpellBookSkillLines and sb.GetSpellBookSkillLineInfo and sb.GetSpellBookItemInfo) then
        return false
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local okN, lines = pcall(sb.GetNumSpellBookSkillLines)
    for i = 1, (okN and lines or 0) do
        local okL, line = pcall(sb.GetSpellBookSkillLineInfo, i)
        if okL and type(line) == "table" and not line.isGuild then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local okI, info = pcall(sb.GetSpellBookItemInfo, slot, bank)
                if okI and type(info) == "table" then fn(info) end
            end
        end
    end
    return true
end

local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1

local function KnownSpells()
    local known = {}
    ForEachSpellBookItem(function(info)
        if info.itemType == SPELL and type(info.name) == "string" then
            known[info.name] = known[info.name] or {}
            known[info.name][info.subName or ""] = true
        end
    end)
    return known
end

local function IsKnown(known, e)
    local ranks = known[e.name]
    if not ranks then return false end
    if e.sub == nil or e.sub == "" then return true end
    return ranks[e.sub] == true
end

-- ── Capture at the trainer ───────────────────────────────────
local function Capture()
    local db = DB()
    if type(db) ~= "table" then return false end
    local okT, ttype = pcall(C_Trainer.GetTrainerType)
    local general = Enum and Enum.TrainerType and Enum.TrainerType.General or 0
    if not okT or ttype ~= general then return false end
    local okTS, trade = pcall(IsTradeskillTrainer)
    if okTS and trade then return false end
    local okN, n = pcall(GetNumTrainerServices)
    if not okN or type(n) ~= "number" then return false end
    local list = {}
    for i = 1, n do
        local ok, name, stype, icon, level, sub = pcall(GetTrainerServiceInfo, i)
        if ok and name and stype ~= "header" then
            local e = { name = name, type = stype, icon = icon, level = level, sub = sub }
            local okC, cost = pcall(GetTrainerServiceCost, i)
            e.cost = okC and cost or nil
            local okS, line = pcall(GetTrainerServiceSkillLine, i)
            e.line = okS and line or nil
            local okA, na = pcall(GetTrainerServiceNumAbilityReq, i)
            for a = 1, (okA and na or 0) do
                local okR, ability, met = pcall(GetTrainerServiceAbilityReq, i, a)
                if okR and ability then
                    e.req = e.req or {}
                    e.req[#e.req + 1] = { ability, met and true or false }
                end
            end
            list[#list + 1] = e
        end
    end
    local filters = {}
    for _, f in ipairs({ "available", "unavailable", "used" }) do
        local okF, on = pcall(GetTrainerServiceTypeFilter, f)
        filters[f] = okF and on and true or false
    end
    db.trainerCache = db.trainerCache or {}
    db.trainerCache[CharKey()] = { list = list, filters = filters, level = Level(),
        trainer = UnitName("npc"), time = time() }
    return true
end

-- ⚠ The probe build (9bc1946) saved each requirement as a bare name string, not { name, met }. Indexing
-- that string gives nil, and format(tmpl, nil) threw on every row redraw (owner, 2026-11-05). A list saved
-- that way says nothing about whether the requirement is met, so it counts as met (neither red nor
-- blocking) until the next trainer visit saves the list again.
local function ReqInfo(r)
    if type(r) == "string" then return r, true end
    if type(r) == "table" and type(r[1]) == "string" then return r[1], r[2] and true or false end
    return nil
end

local function ReqsMet(e)
    for _, r in ipairs(e.req or {}) do
        local name, met = ReqInfo(r)
        if name and not met then return false end
    end
    return true
end

-- The saved list for this character, split: `now` = at or below your level and not known; `later` = above it.
-- `shown` = both, in the trainer's own order (what the window lists).
local function Trainable()
    local db = DB()
    local cache = type(db) == "table" and db.trainerCache and db.trainerCache[CharKey()]
    if not cache then return nil end
    local known, level = KnownSpells(), Level()
    local now, later, shown = {}, {}, {}
    for _, e in ipairs(cache.list or {}) do
        if e.type ~= "used" and not IsKnown(known, e) then
            shown[#shown + 1] = e
            if (e.level or 0) > level then later[#later + 1] = e else now[#now + 1] = e end
        end
    end
    return cache, now, later, shown
end
VUI.QoL_Trainable = Trainable

local function Line(tag, e)
    return format("  %s  %s%s (level %s, %s, cost %s%s)", tag, tostring(e.name),
        (e.sub and e.sub ~= "") and (" [" .. e.sub .. "]") or "", tostring(e.level), tostring(e.type),
        tostring(e.cost), e.line and (", " .. tostring(e.line)) or "")
end

VUI.QoL_TrainableProbe = function()
    local cache, now, later = Trainable()
    if not cache then
        VUI.Print("Quality of Life", "Trainer check: no trainer list saved yet -- talk to your class trainer once.")
        return
    end
    local f = cache.filters or {}
    VUI.Print("Quality of Life", format("Trainer check (level %d): list from %s at level %s, %d services; "
        .. "filters available %s, unavailable %s, known %s.", Level(), tostring(cache.trainer),
        tostring(cache.level), #(cache.list or {}), tostring(f.available), tostring(f.unavailable), tostring(f.used)))
    VUI.Print("Quality of Life", format("  %d to learn now, %d at later levels.", #now, #later))
    for _, e in ipairs(now) do VUI.Print("Quality of Life", Line("NOW", e)) end
    for i, e in ipairs(later) do
        if i > 8 then VUI.Print("Quality of Life", format("  ... and %d more later", #later - 8)); break end
        VUI.Print("Quality of Life", Line("LATER", e))
    end
end

if not VUI.IS_FOREVER then return end   -- Retail characters learn their class spells without a trainer

local function ClassIcon()
    local ok, _, classFile = pcall(UnitClass, "player")
    return "Interface\\Icons\\ClassIcon_" .. ((ok and classFile) or "WARRIOR")
end

-- ── The window ───────────────────────────────────────────────
local WIN_NAME = "VUIQoLTrainerListFrame"
VUI.RegisterManagedPanel(WIN_NAME, { area = "left", pushable = 0 })

local TRAINER_TEX = "Interface\\ClassTrainerFrame\\TrainerTextures"
local ROW_H, LIST_W, LIST_H = 47, 302, 330
local win

local function Requirements(e)
    local level, parts = Level(), {}
    if e.level and e.level > 1 then
        local tmpl = level >= e.level and (TRAINER_REQ_LEVEL or "Level %d") or (TRAINER_REQ_LEVEL_RED or "Level %d")
        parts[#parts + 1] = format(tmpl, e.level)
    end
    for _, r in ipairs(e.req or {}) do
        local name, met = ReqInfo(r)
        if name then
            local tmpl = met and (TRAINER_REQ_ABILITY or "%s") or (TRAINER_REQ_ABILITY_RED or "%s")
            parts[#parts + 1] = format(tmpl, name)
        end
    end
    if #parts == 0 then return "" end
    return (REQUIRES_LABEL or "Requires:") .. " " .. table.concat(parts, PLAYER_LIST_DELIMITER or ", ")
end

local function BuildRow(row)
    row:SetSize(298, ROW_H)
    row:SetNormalTexture(TRAINER_TEX)
    row:GetNormalTexture():SetTexCoord(0.00195313, 0.57421875, 0.65820313, 0.75000000)
    row:SetHighlightTexture(TRAINER_TEX, "ADD")
    row:GetHighlightTexture():SetTexCoord(0.00195313, 0.57421875, 0.75390625, 0.84570313)
    local dis = row:CreateTexture(nil, "BACKGROUND")
    dis:SetPoint("TOPLEFT", 2, -2)
    dis:SetPoint("BOTTOMRIGHT", -2, 2)
    dis:SetColorTexture(0.55, 0.55, 0.55, 1)
    dis:SetBlendMode("MOD")
    row.disabledBG = dis
    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 6, 0)
    row.icon = icon
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetJustifyH("LEFT")
    name:SetHeight(12)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
    row.name = name
    local sub = row:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    sub:SetJustifyH("LEFT")
    sub:SetJustifyV("MIDDLE")
    sub:SetSize(240, 30)
    sub:SetPoint("LEFT", name, "LEFT", 0, -19)
    row.subText = sub
    local nameSub = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameSub:SetJustifyH("LEFT")
    nameSub:SetHeight(12)
    nameSub:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 5, -1)
    row.nameSubText = nameSub
    local money = CreateFrame("Frame", nil, row, "SmallMoneyFrameTemplate")
    money:SetPoint("TOPRIGHT", 5, -7)
    if MoneyFrame_SetType then pcall(MoneyFrame_SetType, money, "STATIC") end
    row.money = money
    row.built = true
end

local function InitRow(row, e)
    if not row.built then BuildRow(row) end
    local level = Level()
    local available = (e.level or 0) <= level and ReqsMet(e)
    row.icon:SetTexture(e.icon)
    row.icon:SetDesaturated(not available)
    row.disabledBG:SetShown(not available)
    if available then
        row.name:SetText(e.name)
    else
        row.name:SetText((GRAY_FONT_COLOR_CODE or "") .. tostring(e.name) .. (FONT_COLOR_CODE_CLOSE or ""))
    end
    if e.sub and e.sub ~= "" then
        row.nameSubText:SetText((PARENS_TEMPLATE or "(%s)"):format(e.sub))
    else
        row.nameSubText:SetText("")
    end
    row.subText:SetText(Requirements(e))
    if e.cost and e.cost > 0 and MoneyFrame_Update then
        row.money:Show()
        pcall(MoneyFrame_Update, row.money, e.cost)
        if SetMoneyFrameColorByFrame then
            local okM, money = pcall(GetMoney)
            pcall(SetMoneyFrameColorByFrame, row.money, (okM and money or 0) >= e.cost and "white" or "red")
        end
    else
        row.money:Hide()
    end
end

local function RefreshWindow()
    if not (win and win:IsShown()) then return end
    local _, _, _, shown = Trainable()
    -- Titled with your character's name, not the trainer's: any of the class's trainers teaches this list
    -- (owner, 2026-11-05: naming one of them looked odd). First AND last name: Forever's UnitName returns the
    -- surname as a second value, and Blizzard joins them with NameUtil.FormatUnitNameForDisplay
    -- (Blizzard_FrameXMLUtil/Camelot/NameUtil.lua, forever).
    local okN, me = false, nil
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        okN, me = pcall(NameUtil.FormatUnitNameForDisplay, "player")
    end
    if not (okN and me) then okN, me = pcall(UnitName, "player") end
    if okN and me and win.SetTitle then win:SetTitle(me) end
    local provider = CreateDataProvider()
    for _, e in ipairs(shown or {}) do provider:Insert(e) end
    win.ScrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    win.empty:SetShown(not shown or #shown == 0)
    if MoneyFrame_Update then
        local okM, money = pcall(GetMoney)
        pcall(MoneyFrame_Update, win.money, okM and money or 0)
    end
end

local function BuildWindow()
    win = CreateFrame("Frame", WIN_NAME, UIParent, "ButtonFrameTemplate")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:Hide()
    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function(self) VUI.CloseManagedPanel(self:GetParent()) end)
    end
    -- The trainer's own portrait needs the trainer present (SetPortraitTexture "npc"); the class icon stands in,
    -- through Blizzard's PortraitFrameMixin:SetPortraitToClassIcon (Blizzard_SharedXML/PortraitFrame.lua:67).
    local okC, _, classFile = pcall(UnitClass, "player")
    if okC and classFile and win.SetPortraitToClassIcon then win:SetPortraitToClassIcon(classFile) end
    if win.SetTitle then win:SetTitle(TRAINER or "Trainer") end

    local moneyBg = win:CreateTexture(nil, "ARTWORK")
    moneyBg:SetTexture("Interface\\MoneyFrame\\UI-MoneyFrame-Border")
    moneyBg:SetSize(148, 34)
    moneyBg:SetPoint("BOTTOMLEFT", 5, -9)
    local money = CreateFrame("Frame", nil, win, "SmallMoneyFrameTemplate")
    money:SetPoint("RIGHT", moneyBg, "RIGHT", 8, 6)
    win.money = money

    local box = CreateFrame("Frame", nil, win, "WowScrollBoxList")
    box:SetSize(LIST_W, LIST_H)
    box:SetPoint("TOPLEFT", win.Inset or win, "TOPLEFT", 5, -5)
    win.ScrollBox = box
    local bar = CreateFrame("EventFrame", nil, win, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 5, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 5, -2)

    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(TRAINER_TEX)
    bg:SetTexCoord(0.00195313, 0.58593750, 0.00195313, 0.65429688)
    bg:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 4)
    bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -4)

    local view = CreateScrollBoxListLinearView(1, 1, 0, 1, 0)
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    local empty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", box, "CENTER")
    empty:SetWidth(LIST_W - 40)
    empty:SetText("Nothing left to learn from this trainer.")
    win.empty = empty

    win:SetScript("OnShow", RefreshWindow)
    win:RegisterEvent("PLAYER_MONEY")
    win:RegisterEvent("PLAYER_LEVEL_UP")
    win:SetScript("OnEvent", function() C_Timer.After(0, RefreshWindow) end)
end

local function ToggleWindow()
    if not win then BuildWindow() end
    if win:IsShown() then VUI.CloseManagedPanel(win) else VUI.OpenManagedPanel(win) end
end
VUI.QoL_TrainerWindowToggle = ToggleWindow

-- ── The minimap button ───────────────────────────────────────
local SIZE_W, SIZE_H, ICON, GAP = 23, 22, 11.5, 2
local TRACK_GAP = 1   -- owner, in game: the gap between the calendar and the AddOn compartment under it
local button, watcher, anchoredTo
local enabled, active, pendingLevel = false, false, nil
local hasNow = false   -- something on the saved list is learnable at your level

local function Shown(f) return f and f.IsShown and f:IsShown() end

local function Follow()
    local cluster = _G.MinimapCluster
    local ind = cluster and cluster.IndicatorFrame
    if not (button and ind and active and ind:IsVisible()) then
        if button and button:IsShown() then button:Hide() end
        return
    end
    local point, target, rel, y = "TOP", ind, "TOP", 0
    local track = cluster.Tracking and cluster.Tracking.Button
    if track and track:IsVisible() then
        -- Under the tracking button, left of the mail icon (owner, 2026-11-05: Forever's mail icon is much larger
        -- and the button looked odd hung beneath it). Header Underneath (Edit Mode) puts the zone text below the
        -- map and the indicator ABOVE it (Camelot/Minimap.lua SetHeaderUnderneath: IndicatorFrame BOTTOMLEFT to
        -- ZoneTextButton TOPLEFT), so the button goes above the tracking button there.
        if ind:GetPoint(1) == "BOTTOMLEFT" then
            point, target, rel, y = "BOTTOM", track, "TOP", TRACK_GAP
        else
            point, target, rel, y = "TOP", track, "BOTTOM", -TRACK_GAP
        end
    elseif Shown(ind.MailFrame) then
        target, rel, y = ind.MailFrame, "BOTTOM", -GAP
    end
    local key = tostring(target) .. point .. rel
    if key ~= anchoredTo then
        button:ClearAllPoints()
        button:SetPoint(point, target, rel, 0, y)
        anchoredTo = key
    end
    local scale = ind:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if scale > 0 and math.abs(button:GetScale() - scale) > 0.001 then button:SetScale(scale) end
    local alpha = ind:GetEffectiveAlpha()
    if button:GetAlpha() ~= alpha then button:SetAlpha(alpha) end
    if not button:IsShown() then button:Show() end
end

-- Shown when something is learnable now; with Always Show Trainer Button (owner, 2026-11-05) also when nothing
-- is, the class icon then dimmed (desaturated, at 50%) so it reads at a glance that nothing is ready, as
-- Blizzard greys a button with nothing to act on.
local function Refresh()
    local _, now = Trainable()
    local db = DB()
    local always = type(db) == "table" and db.trainerButtonAlways == true
    hasNow = now ~= nil and #now > 0
    active = enabled and (hasNow or always)
    if button and button.Icon then
        button.Icon:SetDesaturated(not hasNow)
        button.Icon:SetAlpha(hasNow and 1 or 0.5)
    end
    Follow()
end
VUI.QoL_TrainerButtonRefresh = Refresh

local function SetAdd(a) if button then button.AddTexture:SetAlpha(a) end end

local function SkillName(e) return (e.sub and e.sub ~= "") and format("%s (%s)", e.name, e.sub) or e.name end

-- The tooltip. Learnable now: those skills, in tooltip green (owner's colours). Nothing yet: the next level's
-- skills, greyed. No saved list: how to get one.
local function ShowTip(self)
    local cache, now, later = Trainable()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local gold, white = NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR
    if not cache then
        GameTooltip_SetTitle(GameTooltip, "No Trainer List Yet")
        GameTooltip:AddLine("Talk to your class trainer once to see your skills here.", white.r, white.g, white.b, true)
    elseif now and #now > 0 then
        GameTooltip_SetTitle(GameTooltip, "New Skills at Your Trainer")
        for _, e in ipairs(now) do
            -- Skills in tooltip green (GREEN_FONT_COLOR, the green of Blizzard's tooltip instruction lines). The
            -- font colours come from the client's colour table, not Lua, so the fallback is its value.
            local green = GREEN_FONT_COLOR
            if green then GameTooltip:AddLine(SkillName(e), green:GetRGB())
            else GameTooltip:AddLine(SkillName(e), 0.1, 1, 0.1) end
        end
    else
        -- Only the next level's skills, in the trainer's order, in Blizzard's grey for "not ready yet", with
        -- that level beside each (owner, 2026-11-06: no later levels, no "and N more").
        GameTooltip_SetTitle(GameTooltip, "No New Skills Yet")
        local nextLevel
        for _, e in ipairs(later or {}) do
            if e.level and (not nextLevel or e.level < nextLevel) then nextLevel = e.level end
        end
        local grey = GRAY_FONT_COLOR
        local r, g, b = 0.5, 0.5, 0.5   -- GRAY_FONT_COLOR's value, if the client's colour table lacks it
        if grey then r, g, b = grey:GetRGB() end
        for _, e in ipairs(later or {}) do
            if e.level == nextLevel then
                GameTooltip:AddDoubleLine(SkillName(e), format("Level %d", e.level), r, g, b, r, g, b)
            end
        end
    end
    -- The click line in gold, matching Blizzard's Tracking tooltip instruction above it (owner).
    GameTooltip:AddLine("Click to see the trainer's list.", gold:GetRGB())
    GameTooltip:Show()
end

local function Build()
    button = CreateFrame("Button", "VUIQoLTrainerButton", UIParent)
    button:SetSize(SIZE_W, SIZE_H)
    button:SetFrameStrata("MEDIUM")
    local frameTex = button:CreateTexture(nil, "ARTWORK")
    frameTex:SetAtlas("ui-hud-minimap-addon-indicator", true)
    frameTex:SetPoint("CENTER")
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(ClassIcon())
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(ICON, ICON)
    icon:SetPoint("CENTER", 0, 1)
    button.Icon = icon
    local add = button:CreateTexture(nil, "OVERLAY", nil, 1)
    add:SetAtlas("ui-hud-minimap-addon-indicator", true)
    add:SetPoint("CENTER")
    add:SetBlendMode("ADD")
    add:SetAlpha(0)
    button.AddTexture = add
    button:Hide()
    button:SetScript("OnClick", ToggleWindow)
    button:SetScript("OnMouseDown", function() SetAdd(0.2) end)
    button:SetScript("OnMouseUp", function(self) SetAdd(self:IsMouseOver() and 0.1 or 0) end)
    button:SetScript("OnEnter", function(self)
        SetAdd(0.1)
        ShowTip(self)
    end)
    button:SetScript("OnLeave", function(self)
        SetAdd(0)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnUpdate", Follow)
end

function VUI.QoL_TrainerButtonSet(on)
    enabled = on and true or false
    if on and not button then Build() end
    if watcher then watcher:SetShown(enabled) end
    Refresh()
end

-- ── Events ───────────────────────────────────────────────────
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_LEVEL_UP",
                     "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local db = DB()
        if type(db) == "table" and db.trainerButton ~= false then VUI.QoL_TrainerButtonSet(true) end
        return
    end
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then Capture() end
    if event == "PLAYER_LEVEL_UP" then
        -- UnitLevel can still read the old level during the event; read again a moment later.
        if not pendingLevel then
            pendingLevel = true
            C_Timer.After(1, function() pendingLevel = nil; Refresh(); RefreshWindow() end)
        end
    end
    Refresh()
    RefreshWindow()
end)
