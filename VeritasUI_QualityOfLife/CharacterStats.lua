-- VeritasUI_QualityOfLife / CharacterStats.lua
-- Feature batch Phase 4 (v1.53.0): the character window's stat tooltips. Kept out of QualityOfLife.lua,
-- whose main chunk is near Lua's 200-locals limit (QualityOfLife.lua :3604 comment).
--
-- Both features post-hook Blizzard's two stat tooltip builders and only ADD to GameTooltip: nothing of
-- Blizzard's is replaced or written. CharacterStatFrameTemplate's OnEnter calls the global
-- PaperDollStatTooltip by name, or the frame's onEnterFunc, which PaperDollFrame_SetMastery sets to the
-- global Mastery_OnEnter on every stats update (CharacterFrame.xml:125-131, PaperDollFrame.lua:1224), so
-- hooksecurefunc on the two globals catches every stat. The stat is told by its label, which Blizzard
-- writes as format(STAT_FORMAT, STAT_*) (PaperDollFrame_SetLabelAndText, :1988-1991); pooled stat frames
-- change stat between updates, so nothing is remembered per frame.
--
-- Show Diminishing Returns. Measured in game (owner, 2026-11-01): GetCombatRatingBonusForCombatRatingValue
-- applies diminishing returns to the value it is given (haste: 1 rating x 90,000 = 2045.45%, 90,000 rating
-- = 126%). So everything comes from that one Blizzard call, with no copied breakpoint table:
--   per   = bonus of 1 rating (no penalty that low) = the full value of a point of rating
--   lost  = rating - bonus(rating) / per             (rating the penalty has taken away)
--   next  = first rating above yours where a point is worth less than it is now (binary search on the
--           slope); "to cap" when a point is worth nothing past it.
-- Crit uses the rating Blizzard's own tooltip uses (spell, ranged or melee, whichever crit is highest:
-- PaperDollFrame_SetCritChance :1031-1053). Versatility uses damage done, the rating it shows (:1279).
--
-- Highlight Gear for Stats. Hovering Critical Strike, Haste, Mastery, Versatility, Leech, Avoidance or
-- Speed lights the highlight of each equipped slot whose item has that stat (C_Item.GetItemStats keys, as
-- EllesmereUI reads them), with the slot button's own highlight (LockHighlight; no new art). Cleared when
-- the tooltip hides, which covers leaving the stat and closing the window.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, pairs, ipairs, type, format, floor, ceil = pcall, pairs, ipairs, type, string.format, math.floor, math.ceil

local function DB() return _G.VeritasUI_QualityOfLifeDB end
-- Default ON: only an explicit false turns one off.
local function On(key)
    local db = DB()
    return not (type(db) == "table" and db[key] == false)
end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- label -> { cr = combat rating (nil for crit: chosen at hover), mod = GetItemStats key }
local STATS
local function Stats()
    if STATS then return STATS end
    STATS = {}
    local fmt = _G.STAT_FORMAT
    local function add(name, cr, mod)
        if type(fmt) == "string" and type(name) == "string" then
            STATS[format(fmt, name)] = { cr = cr, mod = mod, crit = (cr == "crit") }
        end
    end
    add(_G.STAT_CRITICAL_STRIKE, "crit", "ITEM_MOD_CRIT_RATING_SHORT")
    add(_G.STAT_HASTE, _G.CR_HASTE_MELEE, "ITEM_MOD_HASTE_RATING_SHORT")
    add(_G.STAT_MASTERY, _G.CR_MASTERY, "ITEM_MOD_MASTERY_RATING_SHORT")
    add(_G.STAT_VERSATILITY, _G.CR_VERSATILITY_DAMAGE_DONE, "ITEM_MOD_VERSATILITY")
    add(_G.STAT_LIFESTEAL, _G.CR_LIFESTEAL, "ITEM_MOD_CR_LIFESTEAL_SHORT")
    add(_G.STAT_AVOIDANCE, _G.CR_AVOIDANCE, "ITEM_MOD_CR_AVOIDANCE_SHORT")
    add(_G.STAT_SPEED, _G.CR_SPEED, "ITEM_MOD_CR_SPEED_SHORT")
    return STATS
end

local function StatFor(frame)
    local label = frame and frame.Label
    if not (label and label.GetText) then return nil end
    local ok, text = pcall(label.GetText, label)
    if not ok or type(text) ~= "string" or IsSecret(text) then return nil end
    return Stats()[text]
end

-- Blizzard's crit choice, PaperDollFrame_SetCritChance :1031-1053.
local function CritRating()
    local ok, spell, ranged, melee = pcall(function()
        local minCrit = GetSpellCritChance(2)
        for i = 3, (_G.MAX_SPELL_SCHOOLS or 7) do minCrit = math.min(minCrit, GetSpellCritChance(i)) end
        return minCrit, GetRangedCritChance(), GetCritChance()
    end)
    if not ok or IsSecret(spell) or IsSecret(ranged) or IsSecret(melee) then return nil end
    if spell >= ranged and spell >= melee then return _G.CR_CRIT_SPELL end
    if ranged >= melee then return _G.CR_CRIT_RANGED end
    return _G.CR_CRIT_MELEE
end

-- Pure arithmetic on a bonus(cr, value) function; exposed for the test.
-- Returns lost, toNext, nextIsCap -- or nil when it cannot be worked out.
local function Diminishing(bonus, cr, rating)
    if type(rating) ~= "number" or rating <= 0 then return nil end
    local per = bonus(cr, 1)
    if type(per) ~= "number" or per <= 0 then return nil end
    local eff = bonus(cr, rating)
    if type(eff) ~= "number" then return nil end
    local lost = rating - eff / per
    if lost < 0.5 then lost = 0 end
    local function slope(r) return bonus(cr, r + 1) - bonus(cr, r) end
    local now = slope(rating)
    if now <= per * 1e-6 then return floor(lost + 0.5), nil, true end   -- already at the cap
    local function worse(r) return slope(r) < now * 0.99 end
    local lo, hi = rating, rating + 1000
    while not worse(hi) do
        lo = hi
        hi = rating + (hi - rating) * 2
        if hi - rating > 1e8 then return floor(lost + 0.5), nil, false end
    end
    while hi - lo > 1 do
        local mid = floor((lo + hi) / 2)
        if worse(mid) then hi = mid else lo = mid end
    end
    -- The window [hi, hi+1] is the first one that is worth less; the penalty starts within it.
    local capped = slope(hi + 2) <= per * 1e-6
    return floor(lost + 0.5), ceil(hi - rating), capped
end
VUI.QoL_Diminishing = Diminishing

local function Number(n)
    return _G.BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function AddDiminishing(stat)
    if not On("charDiminishingReturns") then return false end
    local bonus = _G.GetCombatRatingBonusForCombatRatingValue
    if not (bonus and GetCombatRating) then return false end
    local cr = stat.crit and CritRating() or stat.cr
    if type(cr) ~= "number" then return false end
    local okR, rating = pcall(GetCombatRating, cr)
    if not okR or IsSecret(rating) then return false end
    local okD, lost, toNext, capped = pcall(Diminishing, bonus, cr, rating)
    if not okD or lost == nil or IsSecret(lost) then return false end
    local c = NORMAL_FONT_COLOR
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("Rating lost to diminishing returns: %s", Number(lost)), c.r, c.g, c.b, true)
    if toNext and capped then
        GameTooltip:AddLine(format("Rating to cap: %s", Number(toNext)), c.r, c.g, c.b, true)
    elseif toNext then
        GameTooltip:AddLine(format("Rating to next penalty: %s", Number(toNext)), c.r, c.g, c.b, true)
    elseif capped then
        GameTooltip:AddLine("At the cap: more rating adds nothing.", c.r, c.g, c.b, true)
    end
    return true
end

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand" }
local lit = {}

local function Unlight()
    for button in pairs(lit) do
        pcall(button.UnlockHighlight, button)
        lit[button] = nil
    end
end

local function Light(stat)
    Unlight()
    if not On("charStatHighlight") or not (C_Item and C_Item.GetItemStats) then return end
    for _, name in ipairs(SLOTS) do
        local button = _G["Character" .. name .. "Slot"]
        local slot = button and button.GetID and button:GetID()
        local link = slot and GetInventoryItemLink("player", slot)
        if link then
            local ok, stats = pcall(C_Item.GetItemStats, link)
            if ok and type(stats) == "table" and stats[stat.mod] then
                pcall(button.LockHighlight, button)
                lit[button] = true
            end
        end
    end
end

local function OnStatTooltip(frame)
    if not (GameTooltip and GameTooltip:IsOwned(frame)) then return end
    local stat = StatFor(frame)
    if not stat then return end
    Light(stat)
    if AddDiminishing(stat) then GameTooltip:Show() end
end

-- PaperDollFrame.lua is part of Blizzard_UIPanels_Game; install as soon as its two globals exist.
local installed = {}
local function Install()
    for _, name in ipairs({ "PaperDollStatTooltip", "Mastery_OnEnter" }) do
        if not installed[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, OnStatTooltip)
            installed[name] = true
        end
    end
    return installed.PaperDollStatTooltip and installed.Mastery_OnEnter
end
if not Install() then
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self) if Install() then self:UnregisterAllEvents() end end)
end
if GameTooltip then GameTooltip:HookScript("OnHide", function() if next(lit) then Unlight() end end) end
