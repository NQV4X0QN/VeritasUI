-- VeritasUI_QualityOfLife / AutoEquip.lua
-- Auto Equip Upgrades (owner's request, 2026-11-04, WoW Forever: grey leather in the bags beat the starter cloth).
-- Kept out of QualityOfLife.lua, whose main chunk is near Lua's 200-locals limit.
--
-- Off until turned on (Quality of Life > Character and Gear). Then, out of combat, whenever your bags change and at
-- login, the first upgrade found is equipped and named in chat; the next one follows on the next bag update. Which
-- qualities count is one checkbox each: Poor and Common on, Uncommon, Rare, Epic, Legendary off (owner's spec).
-- `/qol equipcheck` prints the decision for every piece of gear in your bags without equipping anything.
-- Equipping: C_Item.EquipItemByName(link, slot) (ItemDocumentation.lua in both games; no restriction flag).
--
-- The decision, per bag item, all read-only:
--   * equippable (C_Item.IsEquippableItem) and its quality ticked;
--   * not a slot we leave alone: trinkets (their worth is their effect, not item level), shirt, tabard, bags,
--     ammo, profession gear; and never a profession tool (Skinning Knife, Mining Pick, Fishing Pole -- IsTool);
--   * usable: no red line on its tooltip, left or right side (C_TooltipInfo.GetBagItem). Blizzard writes an unmet
--     requirement -- armor or weapon type your class can't use (right side), a level above yours -- in red. An
--     unreadable tooltip waits for the next bag update;
--   * would not bind on equip (an unbound Bind on Equip item asks you to confirm; that stays your call);
--   * a main stat that is wrong for you (Strength / Agility / Intellect, C_Item.GetItemStats) only stops it when
--     what you wear has YOUR main stat and the new item is less than 5 item levels or 25% above it (whichever is
--     more); against gear with none (or an empty slot), or past that gap, the wrong stat counts for nothing and the
--     rest decides (v1.77.2, owner). Retail: the spec's
--     primaryStat (GetSpecializationInfo, 1 Strength, 2 Agility, 4 Intellect). WoW Forever has one "spec" per
--     class and it reported Intellect for the owner's Hunter (probe, 2026-11-04), so there the class decides:
--     Hunter and Rogue Agility, Warrior Strength, Mage, Priest and Warlock Intellect; hybrid classes get no check.
--     An item with no main stat (most greys) passes;
--   * better than what is worn: an empty slot; or stats first -- at least as much of every stat and more of one
--     wins, and the reverse never replaces, whatever the item levels (StatEdge); otherwise, for armor, a heavier
--     armor type at the same or higher item level, or the same type at a higher item level (never a lighter type);
--     for anything else, a higher item level. At equal item level, better quality wins, then more armor; the same
--     item never replaces itself.
--     Rings go to an empty ring slot, else replace the lower one. Weapons only replace a worn weapon of the same
--     kind (two-hander for two-hander, ranged for ranged), so a weapon and off-hand pair is never broken up.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, format = pcall, ipairs, string.format

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Equip location -> the character slots it can go in. Weapons are matched like for like (see the header).
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_CLOAK = { 15 },
}
local WEAPON_SLOTS = { 16, 17, 18 }
local WEAPONS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true, INVTYPE_RELIC = true,
}
-- Quality -> its option key (all universal, in QualityOfLife.lua's defaults).
VUI.QoL_AutoEquipQualityKeys = {
    [0] = "autoEquipPoor", [1] = "autoEquipCommon", [2] = "autoEquipUncommon",
    [3] = "autoEquipRare", [4] = "autoEquipEpic", [5] = "autoEquipLegendary",
}

local MAIN_STATS = { [1] = "ITEM_MOD_STRENGTH_SHORT", [2] = "ITEM_MOD_AGILITY_SHORT", [4] = "ITEM_MOD_INTELLECT_SHORT" }
local FOREVER_CLASS_STAT = { HUNTER = 2, ROGUE = 2, WARRIOR = 1, MAGE = 4, PRIEST = 4, WARLOCK = 4 }

local function QualityAllowed(q)
    local db = DB()
    local key = VUI.QoL_AutoEquipQualityKeys[q]
    return type(db) == "table" and key ~= nil and db[key] == true
end

local function ItemLevel(link)
    local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
    return ok and type(ilvl) == "number" and not Secret(ilvl) and ilvl or 0
end

local function Info(link)
    local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return nil end
    return equipLoc, classID, subclassID
end

local function IsRed(c)
    return type(c) == "table" and c.r and not Secret(c.r) and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
end

-- The red tooltip lines of a bag item (an unmet requirement), and whether the tooltip could be read at all. Both
-- sides of a line: the armor or weapon type sits on the RIGHT, beside the slot (owner's screenshot, WoW Forever
-- 2026-11-05: "Mail" in red right of "Legs" on a Hunter below the level for mail).
local function RedLines(bag, slot)
    local tt = _G.C_TooltipInfo
    if not (tt and tt.GetBagItem) then return nil, false end
    local ok, data = pcall(tt.GetBagItem, bag, slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil, false end
    local red = {}
    for _, line in ipairs(data.lines) do
        if IsRed(line.leftColor) then red[#red + 1] = tostring(line.leftText) end
        if IsRed(line.rightColor) then red[#red + 1] = tostring(line.rightText) end
    end
    return red, true
end

-- Armor value of an item, for a tie at equal item level: its stats first, else the "N Armor" line of its tooltip
-- (ARMOR_TEMPLATE). Returns the value and where it came from, or nil.
local function ArmorFromTooltip(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local tmpl = type(_G.ARMOR_TEMPLATE) == "string" and _G.ARMOR_TEMPLATE or "%s Armor"
    local pat = "^" .. tmpl:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%[sd]", "([%%d,%%.]+)") .. "$"
    for _, line in ipairs(data.lines) do
        local t = line.leftText
        if type(t) == "string" and not Secret(t) then
            local n = t:match(pat)
            n = n and tonumber((n:gsub("%D", "")))
            if n then return n end
        end
    end
    return nil
end

local function ArmorValue(link, tipFn, a, b)
    local ok, stats = pcall(C_Item.GetItemStats, link)
    local v = ok and type(stats) == "table" and stats.RESISTANCE0_NAME
    if type(v) == "number" and not Secret(v) then return v, "stats" end
    local tt = _G.C_TooltipInfo
    if not (tt and tt[tipFn]) then return nil end
    local okT, data = pcall(tt[tipFn], a, b)
    if not okT then return nil end
    local n = ArmorFromTooltip(data)
    return n, n and "tooltip" or nil
end

local function WornLink(slot)
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    return ok and link or nil
end

local function WornQuality(slot)
    local ok, q = pcall(GetInventoryItemQuality, "player", slot)
    return ok and type(q) == "number" and not Secret(q) and q or nil
end

-- Equal item level (owner, 2026-11-05: a white belt with 19 armor stayed in the bags behind a grey one with 18,
-- both item level 5): better quality wins, then more armor. Returns true or false and the reason.
local function TieBreak(bag, slot, info, wornSlot, ilvl)
    local wq = WornQuality(wornSlot)
    if wq and type(info.quality) == "number" then
        local q = info.quality
        if q > wq then return true, format("item level %d, better quality (%d over %d)", ilvl, q, wq) end
        if q < wq then return false, format("item level %d, lower quality (%d under %d)", ilvl, q, wq) end
    end
    local mine, src1 = ArmorValue(info.hyperlink, "GetBagItem", bag, slot)
    local theirs, src2 = ArmorValue(WornLink(wornSlot), "GetInventoryItem", "player", wornSlot)
    local how = format("armor %s vs %s, from %s/%s", tostring(mine), tostring(theirs), tostring(src1), tostring(src2))
    if mine and theirs and mine > theirs then return true, format("item level %d, more armor (%s)", ilvl, how) end
    return false, format("item level %d is not over %d (%s)", ilvl, ilvl, how)
end

local function SpecMainStat()
    if VUI.IS_FOREVER then
        local okC, _, classFile = pcall(UnitClass, "player")
        return okC and FOREVER_CLASS_STAT[classFile] or nil
    end
    local okI, idx = pcall(C_SpecializationInfo.GetSpecialization)
    if not okI or not idx then return nil end
    local ok, _, _, _, _, _, stat = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
    return ok and MAIN_STATS[stat] and stat or nil
end

-- nil if there is nothing to check (no main stat known for you, or none on the item), else true when one of the
-- item's main stats is yours.
local function MainStatFits(link, specStat)
    if not specStat then return nil end
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local any, fits = false, false
    for stat, key in pairs(MAIN_STATS) do
        if stats[key] then any = true; if stat == specStat then fits = true end end
    end
    if not any then return nil end
    return fits
end

-- Stats decide before item level when one item is at least as good in EVERY stat and better in one (owner,
-- 2026-11-05, WoW Forever: Hunter's Simple Cloak, item level 8, 8 Armor +1 Stamina, kept being swapped back to a
-- Handstitched Leather Cloak, item level 9, 8 Armor and nothing else). Every stat C_Item.GetItemStats reports
-- (armor is RESISTANCE0_NAME; weapon DPS, sockets and the rest count too), except a main stat that is not yours.
-- Returns 1 when `a` is better, -1 when `b` is, nil for equal stats, a trade-off (each better somewhere) or stats
-- that cannot be read -- those fall back to item level -- and a description for `/qol equipcheck`.
-- Armor comes from ArmorValue (the stats, else the tooltip's "N Armor" line: which one WoW Forever fills is
-- unmeasured), so an item whose armor only the tooltip shows is never beaten by a stat it lacks.
-- tip = { tooltip function name, arg1, arg2 } for that fallback.
local function StatsOf(link, tip)
    if not link then return nil end
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local copy = {}
    for k, v in pairs(stats) do
        if type(v) ~= "number" or Secret(v) then return nil end
        copy[k] = v
    end
    if copy.RESISTANCE0_NAME == nil and tip then copy.RESISTANCE0_NAME = ArmorValue(link, tip[1], tip[2], tip[3]) end
    return copy
end
local function StatEdge(a, b, specStat, tipA, tipB)
    local sa, sb = StatsOf(a, tipA), StatsOf(b, tipB)
    if not (sa and sb) then return nil, "stats unreadable" end
    local skip = {}
    if specStat then
        for stat, key in pairs(MAIN_STATS) do if stat ~= specStat then skip[key] = true end end
    end
    local aBetter, bBetter = {}, {}
    local function Walk(from, other, into)
        for key, v in pairs(from) do
            if not skip[key] and v > (other[key] or 0) then
                local name = tostring(_G[key] or key)
                into[#into + 1] = format("%s %s vs %s", name, tostring(v), tostring(other[key] or 0))
            end
        end
    end
    Walk(sa, sb, aBetter)
    Walk(sb, sa, bBetter)
    table.sort(aBetter); table.sort(bBetter)
    if #aBetter > 0 and #bBetter == 0 then return 1, "more " .. table.concat(aBetter, ", ") end
    if #bBetter > 0 and #aBetter == 0 then return -1, "less " .. table.concat(bBetter, ", ") end
    if #aBetter > 0 then return nil, "stats trade off" end
    return nil, "same stats"
end

-- Profession tools are never put on, and any real weapon of the same kind replaces one you wear (owner, 2026-11-04:
-- a Skinning Knife replaced his sword, and Raptor Strike needs a real weapon). In WoW Forever every tool is a weapon
-- of subclass Miscellaneous (14) -- Skinning Knife 7005, Mining Pick 2901, Blacksmith Hammer 5956, Arclight Spanner
-- 6219 -- and the Fishing Pole 6256 is subclass Fishing Poles (20): wago.tools Item table, build 1.60.1.70790.
-- Retail's profession gear has its own slots, which this never touches.
local function IsTool(classID, subclassID)
    return classID == 2 and (subclassID == 14 or subclassID == 20)
end

-- Armor subclass of a link (1 cloth .. 4 plate), or nil for anything else (cloaks count as nil: every class
-- wears a cloth cloak).
local function ArmorType(link, equipLoc)
    if not link or equipLoc == "INVTYPE_CLOAK" then return nil end
    local _, classID, subclassID = Info(link)
    if classID == 4 and type(subclassID) == "number" and subclassID >= 1 and subclassID <= 4 then return subclassID end
    return nil
end

-- The decision for one bag item: target slot (or nil) and the reason, for the probe.
local function Decide(bag, slot, info, specStat)
    local link = info.hyperlink
    if not link then return nil, nil end
    local okE, equippable = pcall(C_Item.IsEquippableItem, link)
    if not (okE and equippable) then return nil, nil end   -- not gear: not listed at all
    if not QualityAllowed(info.quality) then return nil, "quality " .. tostring(info.quality) .. " not chosen" end
    local equipLoc, classID, subclassID = Info(link)
    if IsTool(classID, subclassID) then return nil, "profession tool" end
    local red, readable = RedLines(bag, slot)
    if not readable then return nil, "tooltip not readable yet" end
    if red and #red > 0 then return nil, "can't use: " .. table.concat(red, "; ") end
    local okB, bindType = pcall(function() return select(14, C_Item.GetItemInfo(link)) end)
    if okB and bindType == 2 and not info.isBound then return nil, "binds when equipped" end
    local fits = MainStatFits(link, specStat)
    local ilvl = ItemLevel(link)
    -- A main stat that is not yours only stops the swap when what you wear carries YOUR main stat (owner,
    -- 2026-11-07, WoW Forever: Empyrean Treads, item level 15, 48 Armor +3 Intellect, stayed in the bags of a
    -- Hunter wearing Handstitched Leather Boots, item level 8, 31 Armor and no stat). Otherwise the wrong stat is
    -- worth nothing to you either way and the rest of the comparison decides (StatEdge already ignores it).
    -- Even then, an item far enough above the worn one goes to the comparison too (owner: +3 Agility at item level
    -- 15 should not beat item level 32): at least 5 item levels or 25% higher, whichever is more.
    local function KeepsYours(worn)
        if not (fits == false and worn ~= nil and MainStatFits(worn, specStat) == true) then return false end
        local wl = ItemLevel(worn)
        local need = wl + math.max(5, math.ceil(wl * 0.25))
        if ilvl >= need then return false end
        return true, format("main stat is not yours and what you wear has yours: item level %d is under the %d needed",
            ilvl, need)
    end
    local bagTip = { "GetBagItem", bag, slot }
    if WEAPONS[equipLoc] then
        for _, s in ipairs(WEAPON_SLOTS) do
            local worn = WornLink(s)
            if worn and Info(worn) == equipLoc then
                local _, wClass, wSub = Info(worn)
                if IsTool(wClass, wSub) then return s, "weapon: replaces a profession tool" end
                local keeps, why = KeepsYours(worn)
                if keeps then return nil, "weapon: " .. why end
                local edge, how = StatEdge(link, worn, specStat, bagTip, { "GetInventoryItem", "player", s })
                if edge == 1 then return s, "weapon: " .. how end
                if edge == -1 then return nil, "weapon: " .. how end
                local wl = ItemLevel(worn)
                if ilvl > wl then return s, format("weapon: item level %d over %d", ilvl, wl) end
                return nil, format("weapon: item level %d is not over %d", ilvl, wl)
            end
        end
        return nil, "weapon: no worn weapon of the same kind"
    end
    local slots = SLOTS[equipLoc]
    if not slots then return nil, "slot left alone (" .. tostring(equipLoc) .. ")" end
    local best, bestReason, lowestSlot, lowest
    for _, s in ipairs(slots) do
        local worn = WornLink(s)
        if not worn then return s, "empty slot" end
        local wl = ItemLevel(worn)
        if not lowest or wl < lowest then lowest, lowestSlot = wl, s end
    end
    local worn = WornLink(lowestSlot)
    local keeps, keepWhy = KeepsYours(worn)
    if keeps then return nil, keepWhy end
    local mine, theirs = ArmorType(link, equipLoc), ArmorType(worn, equipLoc)
    local edge, how = nil, nil
    if worn ~= link then
        edge, how = StatEdge(link, worn, specStat, bagTip, { "GetInventoryItem", "player", lowestSlot })
    end
    if mine and theirs and mine < theirs then
        return nil, "lighter armor than what you wear"
    elseif edge == 1 then
        best, bestReason = lowestSlot, how
    elseif edge == -1 then
        bestReason = how
    elseif mine and theirs and mine > theirs and ilvl >= lowest then
        best, bestReason = lowestSlot, format("heavier armor, item level %d vs %d", ilvl, lowest)
    elseif ilvl > lowest then
        best, bestReason = lowestSlot, format("item level %d over %d", ilvl, lowest)
    elseif ilvl == lowest and worn ~= link then
        local better, why = TieBreak(bag, slot, info, lowestSlot, ilvl)
        best, bestReason = better and lowestSlot or nil, why
    else
        bestReason = format("item level %d is not over %d", ilvl, lowest)
    end
    return best, bestReason
end

-- Every bag (backpack and the four bag slots; not the reagent bag), item by item.
local function ForEachBagItem(fn)
    for bag = 0, 4 do
        local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okN and n or 0) do
            local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if okI and type(info) == "table" then fn(bag, slot, info) end
        end
    end
end

VUI.QoL_EquipCheck = function()
    local specStat = SpecMainStat()
    VUI.Print("Quality of Life", format("Equip check (nothing is equipped). Main stat: %s; in combat: %s",
        tostring(specStat and MAIN_STATS[specStat] or "any"), tostring(InCombatLockdown() and true or false)))
    local n = 0
    ForEachBagItem(function(bag, slot, info)
        local target, reason = Decide(bag, slot, info, specStat)
        if reason or target then
            n = n + 1
            VUI.Print("Quality of Life", format("  %s (q%s, ilvl %d): %s%s", tostring(info.hyperlink),
                tostring(info.quality), info.hyperlink and ItemLevel(info.hyperlink) or 0,
                target and ("WOULD EQUIP in slot " .. target .. " -- ") or "skip -- ", tostring(reason)))
        end
    end)
    if n == 0 then VUI.Print("Quality of Life", "  no gear in your bags") end
end

-- ── Equipping ────────────────────────────────────────────────
-- One upgrade per pass; the bag update its swap causes starts the next pass, so a bag full of upgrades goes on
-- piece by piece and each decision sees the gear the previous one left. Never in combat (the game refuses armor
-- changes then): a pass asked for in combat waits for PLAYER_REGEN_ENABLED. Never while dead, or while something
-- is on the cursor (you are moving an item yourself). An item tried in the last 5 s is not tried again, so a swap
-- the game refuses cannot loop.
local pending, tried = false, {}
local function On() local db = DB(); return type(db) == "table" and db.autoEquip == true end

local function Run()
    if not On() then pending = false; return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local okD, dead = pcall(_G.UnitIsDeadOrGhost, "player")
    if okD and dead then return end
    local okC, cursor = pcall(GetCursorInfo)
    if okC and cursor then return end
    local specStat, now, done = SpecMainStat(), GetTime(), false
    ForEachBagItem(function(bag, slot, info)
        if done then return end
        local target = Decide(bag, slot, info, specStat)
        local link = info.hyperlink
        if not target or (tried[link] and now - tried[link] < 5) then return end
        tried[link] = now
        local equipLoc = Info(link)
        local ok = pcall(C_Item.EquipItemByName, link, target)
        if ok then
            done = true
            -- Named only once the slot holds it: the game can refuse the swap without an error to us (owner,
            -- 2026-11-05: "Equipped [Flimsy Chain Pants]" printed while the pants stayed in the bags).
            C_Timer.After(1, function()
                if WornLink(target) == link then
                    VUI.Print("Quality of Life", format("Equipped %s (%s).", link, tostring(_G[equipLoc] or equipLoc)))
                end
            end)
        end
    end)
end
VUI.QoL_AutoEquipRun = Run

local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then Run() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEVEL_UP" then
        -- Item data and tooltips settle after the loading screen; a new level can make an item wearable.
        C_Timer.After(2, Run)
    else
        Run()
    end
end)
