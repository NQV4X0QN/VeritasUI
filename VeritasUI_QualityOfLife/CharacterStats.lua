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
-- Highlight Gear for Stats. Hovering a stat lights the highlight of each equipped slot whose item has that
-- stat (C_Item.GetItemStats keys), with the slot button's own highlight
-- (LockHighlight; no new art). Cleared when the tooltip hides, which covers leaving the stat and closing
-- the window. v1.71.3: the attributes too, and WoW Forever's own stat list (Hit, Expertise, Defense...).
-- Forever's character window gives most stats a tooltip builder of its own, the attributes a LOCAL one
-- (Camelot/PaperDollFrameStats.lua:249, :338), so the highlight is also hooked on each stat frame's
-- OnEnter: every stat row is labelled by the global PaperDollFrame_SetLabelAndText in both games
-- (Camelot/PaperDollFrame.lua:2504, Mainline :1988), and a post-hook there meets every frame.
-- A key that is not in the list still matches when its text names the stat ("Agility or Intellect").
--
-- No diminishing returns in WoW Forever: owner's probe 2026-11-06, bonus(crit, 1) x 10,000 =
-- bonus(crit, 10,000) = 714.2857 -- rating converts at a flat rate, so the option is not offered there.

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

-- label -> { cr = combat rating (nil for crit: chosen at hover; nil = no diminishing returns line),
--            mods = GetItemStats keys, word = text a key's string must contain to match (nil = list only) }
local STATS
local function Stats()
    if STATS then return STATS end
    STATS = {}
    local fmt = _G.STAT_FORMAT
    local function add(name, cr, mods, word)
        if type(fmt) == "string" and type(name) == "string" then
            local set = {}
            for _, k in ipairs(mods) do set[k] = true end
            STATS[format(fmt, name)] = { cr = cr, mods = set, crit = (cr == "crit"), word = word }
        end
    end
    -- Attributes: Blizzard labels them SPELL_STAT<i>_NAME (Mainline PaperDollFrame.lua:617, Camelot :690).
    local ATTR = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }
    for i, key in ipairs(ATTR) do
        local name = _G["SPELL_STAT" .. i .. "_NAME"]
        add(name, nil, { "ITEM_MOD_" .. key .. "_SHORT" }, name)
    end
    add(_G.STAT_CRITICAL_STRIKE, "crit", { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT",
        "ITEM_MOD_CRIT_RANGED_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" })
    add(_G.STAT_HASTE, _G.CR_HASTE_MELEE, { "ITEM_MOD_HASTE_RATING_SHORT" })
    add(_G.STAT_MASTERY, _G.CR_MASTERY, { "ITEM_MOD_MASTERY_RATING_SHORT" })
    add(_G.STAT_VERSATILITY, _G.CR_VERSATILITY_DAMAGE_DONE, { "ITEM_MOD_VERSATILITY" })
    add(_G.STAT_LIFESTEAL, _G.CR_LIFESTEAL, { "ITEM_MOD_CR_LIFESTEAL_SHORT" })
    add(_G.STAT_AVOIDANCE, _G.CR_AVOIDANCE, { "ITEM_MOD_CR_AVOIDANCE_SHORT" })
    add(_G.STAT_SPEED, _G.CR_SPEED, { "ITEM_MOD_CR_SPEED_SHORT" })
    -- WoW Forever's stat list (Camelot/PaperDollFrameConstants.lua:35-91); its rows are labelled with
    -- these globals (Camelot/PaperDollFrameStats.lua :178 :362 :441 :550 :675, PaperDollFrame.lua :801
    -- :841 :1102 :1143). No combat rating: Forever has no diminishing returns.
    add(_G.STAT_HIT_CHANCE, nil, { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT",
        "ITEM_MOD_HIT_RANGED_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT" })
    add(_G.STAT_EXPERTISE, nil, { "ITEM_MOD_EXPERTISE_RATING_SHORT" })
    add(_G.STAT_ARMOR_PENETRATION, nil, { "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" })
    add(_G.STAT_SPELLPOWER, nil, { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" })
    add(_G.STAT_SPELLHEALING, nil, { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT" })
    add(_G.DEFENSE, nil, { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" })
    add(_G.STAT_DODGE, nil, { "ITEM_MOD_DODGE_RATING_SHORT" })
    add(_G.STAT_PARRY, nil, { "ITEM_MOD_PARRY_RATING_SHORT" })
    add(_G.STAT_BLOCK, nil, { "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT" })
    return STATS
end

-- True when an item's GetItemStats table has the stat: a listed key, or (attributes) a key whose text
-- names it, as Retail's "[Agility or Intellect]" keys do.
local function HasStat(stats, stat)
    for k in pairs(stats) do
        if stat.mods[k] then return true end
        if stat.word then
            local s = _G[k]
            if type(s) == "string" and s:find(stat.word, 1, true) then return true end
        end
    end
    return false
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
    if VUI.IS_FOREVER or not On("charDiminishingReturns") then return false end
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
local litFor   -- the stat frame whose tooltip lit them

-- Cleared once the tooltip is no longer up for that stat (the mouse left it, the window closed): a frame of
-- ours checks each frame while anything is lit. ⚠ Not a HookScript on GameTooltip (audit 2026-11-09 Q7): a
-- script hook on a shared Blizzard frame runs our code inside Blizzard's own calls (landmine 2: a GameTooltip
-- hook once blocked using bag items until /reload).
local watcher = CreateFrame("Frame")
watcher:Hide()

local function Unlight()
    for button in pairs(lit) do
        pcall(button.UnlockHighlight, button)
        lit[button] = nil
    end
    litFor = nil
    watcher:Hide()
end

watcher:SetScript("OnUpdate", function()
    local tip = GameTooltip
    local up = tip and litFor and tip:IsShown() and tip:IsOwned(litFor)
    if not up then Unlight() end
end)

local function Light(stat, owner)
    Unlight()
    if not On("charStatHighlight") or not (C_Item and C_Item.GetItemStats) then return end
    for _, name in ipairs(SLOTS) do
        local button = _G["Character" .. name .. "Slot"]
        local slot = button and button.GetID and button:GetID()
        local link = slot and GetInventoryItemLink("player", slot)
        if link then
            local ok, stats = pcall(C_Item.GetItemStats, link)
            if ok and type(stats) == "table" and HasStat(stats, stat) then
                pcall(button.LockHighlight, button)
                lit[button] = true
            end
        end
    end
    if next(lit) then
        litFor = owner
        watcher:Show()
    end
end

local function OnStatTooltip(frame)
    if not (GameTooltip and GameTooltip:IsOwned(frame)) then return end
    local stat = StatFor(frame)
    if not stat then return end
    if frame.unit ~= "pet" then Light(stat, frame) end
    if AddDiminishing(stat) then GameTooltip:Show() end
end

-- The frame-level hook: highlight only (the diminishing returns lines stay on the two builders above,
-- which Retail's Mastery re-runs as its UpdateTooltip, PaperDollFrame.lua:1212).
local hookedFrames = setmetatable({}, { __mode = "k" })
local function OnStatEnter(frame)
    if not (GameTooltip and GameTooltip:IsOwned(frame)) or frame.unit == "pet" then return end
    local stat = StatFor(frame)
    if stat then Light(stat, frame) end
end
local function OnLabelSet(frame)
    if type(frame) ~= "table" or hookedFrames[frame] or not frame.HookScript then return end
    hookedFrames[frame] = true
    pcall(frame.HookScript, frame, "OnEnter", OnStatEnter)
end

-- PaperDollFrame.lua is part of Blizzard_UIPanels_Game; install as soon as its globals exist.
local installed = {}
local function Install()
    for _, name in ipairs({ "PaperDollStatTooltip", "Mastery_OnEnter" }) do
        if not installed[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, OnStatTooltip)
            installed[name] = true
        end
    end
    if not installed.label and type(_G.PaperDollFrame_SetLabelAndText) == "function" then
        hooksecurefunc("PaperDollFrame_SetLabelAndText", OnLabelSet)
        installed.label = true
    end
    return installed.PaperDollStatTooltip and installed.Mastery_OnEnter and installed.label
end
if not Install() then
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self) if Install() then self:UnregisterAllEvents() end end)
end
