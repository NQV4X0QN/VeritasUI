-- VeritasUI_QualityOfLife / AutoEquip.lua
-- Auto Equip Upgrades (owner's request, 2026-11-04, WoW Forever: grey leather in the bags beat the starter cloth).
-- Kept out of QualityOfLife.lua, whose main chunk is near Lua's 200-locals limit.
--
-- ⚠ TEST BUILD 1 IS A PROBE ONLY: `/qol equipcheck` prints what the decision below would equip, and why, for
-- every equippable item in your bags. Nothing is equipped. Equipping and the options come once its output has
-- been read (evidence gate: the probe goes first, alone).
--
-- The decision, per bag item, all read-only:
--   * quality allowed (Poor and Common by default; Uncommon, Rare, Epic, Legendary each opt-in);
--   * equippable (C_Item.IsEquippableItem) and not a slot we leave alone: trinkets (their worth is their effect,
--     not item level), shirt, tabard, bags, profession gear;
--   * usable: no red line on its tooltip (C_TooltipInfo.GetBagItem). Blizzard writes an unmet requirement --
--     armor or weapon type your class can't use, a level above yours -- in red. UNMEASURED: that the tooltip
--     data is filled in for a newly looted item; the probe prints the lines it saw;
--   * would not bind on equip (an unbound Bind on Equip item asks you to confirm; that stays your call);
--   * no main stat that is wrong for your spec (Strength / Agility / Intellect, C_Item.GetItemStats; the spec's
--     primaryStat from GetSpecializationInfo, 1 Strength, 2 Agility, 4 Intellect -- the owner's Forever probe read
--     4 for a Mage). An item with no main stat (most greys) passes;
--   * better than what is worn: an empty slot; or, for armor, a heavier armor type at the same or higher item level,
--     or the same type at a higher item level (never a lighter type); for anything else, a higher item level.
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
local QUALITY_DEFAULTS = { [0] = true, [1] = true }   -- Poor (grey), Common (white)

local MAIN_STATS = { [1] = "ITEM_MOD_STRENGTH_SHORT", [2] = "ITEM_MOD_AGILITY_SHORT", [4] = "ITEM_MOD_INTELLECT_SHORT" }

local function QualityAllowed(q)
    local db = DB()
    local t = type(db) == "table" and type(db.autoEquipQualities) == "table" and db.autoEquipQualities
    if t then return t[q] == true end
    return QUALITY_DEFAULTS[q] == true
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

-- The red tooltip lines of a bag item (an unmet requirement), and whether the tooltip could be read at all.
local function RedLines(bag, slot)
    local tt = _G.C_TooltipInfo
    if not (tt and tt.GetBagItem) then return nil, false end
    local ok, data = pcall(tt.GetBagItem, bag, slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil, false end
    local red = {}
    for _, line in ipairs(data.lines) do
        local c = line.leftColor
        if type(c) == "table" and c.r and not Secret(c.r) and c.r > 0.9 and c.g < 0.3 and c.b < 0.3 then
            red[#red + 1] = tostring(line.leftText)
        end
    end
    return red, true
end

local function SpecMainStat()
    local okI, idx = pcall(C_SpecializationInfo.GetSpecialization)
    if not okI or not idx then return nil end
    local ok, _, _, _, _, _, stat = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
    return ok and MAIN_STATS[stat] and stat or nil
end

-- nil if the item has no main stat, else true when one of them is the spec's.
local function MainStatFits(link, specStat)
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local any, fits = false, false
    for stat, key in pairs(MAIN_STATS) do
        if stats[key] then any = true; if stat == specStat then fits = true end end
    end
    if not any then return nil end
    return fits
end

local function WornLink(slot)
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    return ok and link or nil
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
    local equipLoc = Info(link)
    local red, readable = RedLines(bag, slot)
    if not readable then return nil, "tooltip not readable yet" end
    if red and #red > 0 then return nil, "can't use: " .. table.concat(red, "; ") end
    local okB, bindType = pcall(function() return select(14, C_Item.GetItemInfo(link)) end)
    if okB and bindType == 2 and not info.isBound then return nil, "binds when equipped" end
    local fits = MainStatFits(link, specStat)
    if fits == false then return nil, "main stat is not your spec's" end
    local ilvl = ItemLevel(link)
    if WEAPONS[equipLoc] then
        for _, s in ipairs(WEAPON_SLOTS) do
            local worn = WornLink(s)
            if worn and Info(worn) == equipLoc then
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
    local mine, theirs = ArmorType(link, equipLoc), ArmorType(worn, equipLoc)
    if mine and theirs and mine < theirs then
        return nil, "lighter armor than what you wear"
    elseif mine and theirs and mine > theirs and ilvl >= lowest then
        best, bestReason = lowestSlot, format("heavier armor, item level %d vs %d", ilvl, lowest)
    elseif ilvl > lowest then
        best, bestReason = lowestSlot, format("item level %d over %d", ilvl, lowest)
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
    VUI.Print("Quality of Life", format("Equip check (nothing is equipped). Spec main stat: %s; in combat: %s",
        tostring(specStat and MAIN_STATS[specStat] or "unknown"), tostring(InCombatLockdown() and true or false)))
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
