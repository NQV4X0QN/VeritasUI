-- VeritasUI_Lib / GearScore.lua
-- Scores a piece of gear for the player's class, playstyle and level, from the stat weights in GearWeights.lua.
-- Shared by Quality of Life (Auto Equip, /qol equipcheck) and the Auction House (the upgrades list).
--
--   VUI.GearScore.Profiles(classFile)   the playstyles with weights for a class (nil: none)
--   VUI.GearScore.Profile(classFile)    the character's chosen playstyle (GS.GetChoice, provided by Quality of
--                                       Life's per-character `gearProfile`), else the class's first; nil when none
--   VUI.GearScore.Weights(profile, level, classFile, live)   the weights as used at that level; live =
--                                       { damage = your weapon damage per second, health = your max health }
--   VUI.GearScore.Current()             Weights for the player right now
--   VUI.GearScore.Score(stats, hand, weights)   score of a GetItemStats table; hand = "mh" | "oh" | "ranged" | nil
--                                       picks which weapon DPS weight counts. Returns score, unscored keys.
--   VUI.GearScore.ScoreLink(link, hand, weights)   the same for an item link
--
-- LEVEL (2026-11-26). Every weight is measured at level 60 on pre-raid gear. Below 60:
--   * RATINGS buy the same percent at every level in WoW Forever (game: GetCombatRatingBonusForCombatRatingValue
--     at level 16 = WoWSims CombatRatings.txt, levels 1-60). But a percent of YOUR damage is worth less when your
--     damage is smaller, while a point of attack power adds the same 1/14 damage per second at any level. So the
--     offensive percent stats (hit, crit, haste, expertise, armor penetration) are scaled by
--     s = your weapon damage per second / the playstyle's at 60. The playstyle's level-60 damage is read off its
--     own weights: 1% crit adds 1% of damage D, i.e. 0.14 x D attack power, so D60 = 100 x crit weight / attack
--     power weight. Yours is the game's (UnitDamage / UnitAttackSpeed, ranged for a ranged playstyle).
--   * AGILITY buys more crit at low level: Blizzard's PlayerExpectedStat (GearWeights.conv) gives crit per
--     Agility at every level (measured in game, level 16 Warrior: 0.150-0.152%; table 0.1515%; level 60 0.05%).
--     The crit part of the Agility weight is rebuilt from that table and then scaled by s like any percent.
--   * TANKS: avoidance (dodge, parry, block, defense) is a percent of the damage you take, worth more when your
--     health pool is bigger, so it is scaled by h = your max health / 6559 (WoWSims' Protection Warrior pre-raid
--     health). The dodge part of Agility follows the table the same way (dodge per Agility = crit per Agility,
--     twice that for Rogues and Hunters: WoWSims sim/core/base_stats.go dodgePerAgility).
--   * CASTERS AND HEALERS: their percent stats would scale with spell damage at your level, which the game does
--     not report. UNMEASURED: they are used at their level-60 values.
--   * SURVIVAL while leveling: OUR JUDGMENT, NOT MEASURED. Stamina gains SURVIVAL x (60 - L) / 59 x the
--     playstyle's largest main-stat weight, fading to nothing at 60. To be tuned with the owner in game.
--   * ARMOR (owner-approved 2026-11-26). A point of armor cuts damage taken by 1 / (armor + 400 + 85 x attacker
--     level) of itself (WoWSims Forever sim/core/armor_test.go); a point of Stamina adds 10 health (PlayerExpectedStat
--     HPPerStamina = 10 at every level). So armor's worth next to Stamina = health / (10 x (armor + K)), read from
--     your own armor and health against a mob of your level. CHECK THAT COULD FAIL: at 60 (7637 armor, 6559
--     health, level 63 boss) the formula gives 0.049 per point; WoWSims' Protection Warrior weights have
--     0.06 / 1.15 = 0.052. A tank's armor weight is its 60 value x (that ratio now / that ratio at 60); every
--     playstyle's leveling survival term values armor at the same ratio, so a Fury Warrior still prefers armor
--     while leveling. Level 16 Warrior, 1192 armor, 810 health: ratio 0.027; tank armor 0.06 -> 0.034.

local VUI = _G.VeritasUI
if not VUI then return end

local pairs, ipairs, type, pcall, math, tostring = pairs, ipairs, type, pcall, math, tostring

VUI.GearScore = {}
local GS = VUI.GearScore

GS.SURVIVAL = 0.5
GS.TANK_HEALTH_60 = 6559
GS.TANK_ARMOR_60 = 7637   -- WoWSims Protection Warrior Pre-BiS armor (its stats panel), measured against level 63
local HP_PER_STAMINA = 10 -- Blizzard PlayerExpectedStat HPPerStamina, every class and level 1-60 (wowf)
local MAX_LEVEL = 60
local K = {
    AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT", CRIT = "ITEM_MOD_CRIT_RATING_SHORT",
    ARMOR = "RESISTANCE0_NAME",
    DODGE = "ITEM_MOD_DODGE_RATING_SHORT", AP = "ITEM_MOD_ATTACK_POWER_SHORT",
    RAP = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
}
local OFFENSE = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT",
    "ITEM_MOD_EXPERTISE_RATING_SHORT", "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" }
local AVOID = { "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT", "ITEM_MOD_BLOCK_RATING_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" }
local MAIN = { "ITEM_MOD_STRENGTH_SHORT", K.AGI, "ITEM_MOD_INTELLECT_SHORT", K.AP, K.RAP,
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" }
local DOUBLE_DODGE = { ROGUE = true, HUNTER = true }
-- Not stats to score: the item's own weapon DPS is scored through `dps`; sockets are left out.
local IGNORE = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = true }

local function Data() return VUI.GearWeights end

function GS.Profiles(classFile)
    local d = Data()
    return d and d.profiles and d.profiles[classFile] or nil
end

local function ClassFile()
    local ok, _, file = pcall(UnitClass, "player")
    return ok and file or nil
end

-- The character's choice lives with the option that sets it (Quality of Life's per-character `gearProfile`,
-- set through GS.GetChoice / GS.SetChoice by that module). No hook: the class default.
function GS.Profile(classFile)
    local list = GS.Profiles(classFile or ClassFile())
    if not list or not list[1] then return nil end
    local want = GS.GetChoice and GS.GetChoice()
    if type(want) == "string" and want ~= "" then
        for _, p in ipairs(list) do if p.id == want then return p end end
    end
    return list[1]
end

local function Conv(classFile, level)
    local d = Data()
    local t = d and d.conv and d.conv[classFile] and d.conv[classFile].agi
    if not t then return nil, nil end
    return t[math.max(1, math.min(MAX_LEVEL, level))], t[MAX_LEVEL]
end

-- The playstyle's weapon damage per second at 60, read off its own crit and attack power weights (see LEVEL).
function GS.Damage60(profile)
    local w = profile.w
    local ap = profile.role == "ranged" and (w[K.RAP] or w[K.AP]) or (w[K.AP] or w[K.RAP])
    local crit = w[K.CRIT]
    if not (ap and ap > 0 and crit and crit > 0) then return nil end
    return 100 * crit / ap
end

function GS.Weights(profile, level, classFile, live)
    if not profile then return nil end
    level = math.floor(tonumber(level) or MAX_LEVEL)
    classFile = classFile or ClassFile()
    live = live or {}
    local src, w = profile.w, {}
    for k, v in pairs(src) do w[k] = v end
    local out = { w = w, dps = profile.dps, profile = profile, level = level, s = 1, h = 1 }
    if level >= MAX_LEVEL then return out end

    local per = Data().ratingPerPercent
    local physical = profile.role == "melee" or profile.role == "ranged" or profile.role == "tank"
    if physical then
        local d60 = GS.Damage60(profile)
        local s = (d60 and type(live.damage) == "number" and live.damage > 0) and math.min(1, live.damage / d60) or 1
        local h = 1
        if profile.role == "tank" and type(live.health) == "number" and live.health > 0 then
            h = math.min(1, live.health / GS.TANK_HEALTH_60)
        end
        out.s, out.h, out.damage60 = s, h, d60
        for _, k in ipairs(OFFENSE) do if w[k] then w[k] = w[k] * s end end
        if profile.role == "tank" then
            for _, k in ipairs(AVOID) do if w[k] then w[k] = w[k] * h end end
        end
        local now, top = Conv(classFile, level)
        if now and top and w[K.AGI] then
            local critPct = (src[K.CRIT] or 0) * per.crit
            local agi = w[K.AGI] - top * 100 * critPct + now * 100 * critPct * s
            if profile.role == "tank" then
                local dodgePct = (src[K.DODGE] or 0) * per.dodge * (DOUBLE_DODGE[classFile] and 2 or 1)
                agi = agi - top * 100 * dodgePct + now * 100 * dodgePct * h
            end
            w[K.AGI] = math.max(0, agi)
        end
    end
    local main = 0
    for _, k in ipairs(MAIN) do main = math.max(main, src[k] or 0) end
    local staBonus = GS.SURVIVAL * (MAX_LEVEL - level) / (MAX_LEVEL - 1) * main
    w[K.STA] = (w[K.STA] or 0) + staBonus

    -- ARMOR (2026-11-26, see ARMOR in the header): what a point is worth next to a point of Stamina at your
    -- level, against a mob of your level, from your own armor and health.
    local ratio = GS.ArmorPerStamina(live.armor, live.health, level)
    if ratio then
        out.armorRatio = ratio
        if profile.role == "tank" and (src[K.ARMOR] or 0) > 0 then
            w[K.ARMOR] = src[K.ARMOR] * ratio / GS.ArmorPerStamina(GS.TANK_ARMOR_60, GS.TANK_HEALTH_60, 63)
        end
        w[K.ARMOR] = (w[K.ARMOR] or 0) + staBonus * ratio
    end
    return out
end

-- Armor's worth next to one point of Stamina: a point of armor cuts the damage you take by 1 / (armor + K), K =
-- 400 + 85 x the attacker's level (WoWSims Forever sim/core/armor_test.go: armorConstant, 75% cap); a point of
-- Stamina adds HP_PER_STAMINA health, i.e. HP_PER_STAMINA / health of your health. nil without both readings.
function GS.ArmorPerStamina(armor, health, attackerLevel)
    if type(armor) ~= "number" or armor < 0 or type(health) ~= "number" or health <= 0 then return nil end
    local k = 400 + 85 * attackerLevel
    return health / (HP_PER_STAMINA * (armor + k))
end

-- Your weapon damage per second (main hand, or ranged) and max health, from the game. Fields nil when unreadable.
function GS.Live(ranged)
    local live = {}
    local secret = _G.issecretvalue
    if ranged then
        local ok, speed, lo, hi = pcall(_G.UnitRangedDamage, "player")
        if ok and type(speed) == "number" and speed > 0 and type(lo) == "number" and type(hi) == "number" then
            live.damage = (lo + hi) / 2 / speed
        end
    else
        local okD, lo, hi = pcall(_G.UnitDamage, "player")
        local okS, speed = pcall(_G.UnitAttackSpeed, "player")
        if okD and okS and type(lo) == "number" and type(hi) == "number" and type(speed) == "number" and speed > 0 then
            live.damage = (lo + hi) / 2 / speed
        end
    end
    local okH, hp = pcall(_G.UnitHealthMax, "player")
    if okH and type(hp) == "number" and not (secret and secret(hp)) then live.health = hp end
    -- UnitArmor's second return is the armor that counts (the probe, level 16 Warrior: 0, 1192, 1192, 1192).
    local okA, _, armor = pcall(_G.UnitArmor, "player")
    if okA and type(armor) == "number" and not (secret and secret(armor)) then live.armor = armor end
    if live.damage and secret and secret(live.damage) then live.damage = nil end
    return live
end

function GS.Current()
    local cls = ClassFile()
    local p = GS.Profile(cls)
    if not p then return nil end
    local okL, lvl = pcall(UnitLevel, "player")
    return GS.Weights(p, okL and lvl or MAX_LEVEL, cls, GS.Live(p.role == "ranged"))
end

function GS.Score(stats, hand, weights)
    if type(stats) ~= "table" or not weights then return nil end
    local score, unscored = 0, nil
    for k, v in pairs(stats) do
        if type(v) == "number" and not IGNORE[k] then
            local wk = weights.w[k]
            if wk then
                score = score + wk * v
            elseif not tostring(k):find("^EMPTY_SOCKET") then
                unscored = unscored or {}
                unscored[k] = v
            end
        end
    end
    local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    if type(dps) == "number" and hand and weights.dps and weights.dps[hand] then
        score = score + weights.dps[hand] * dps
    end
    return score, unscored
end

function GS.ScoreLink(link, hand, weights)
    weights = weights or GS.Current()
    if not (link and weights) then return nil end
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    return GS.Score(stats, hand, weights)
end

----------------------------------------------------------------
--  Against what you wear (the Auction House upgrades list, 2026-11-26)
--  The same placement rules as Auto Equip (QualityOfLife AutoEquip.lua): armor and jewelry by slot, two rings
--  against the lower-scoring one, weapons only against a worn weapon of the same kind, trinkets/shirt/tabard/bags
--  left out, never a lighter armor type than the one worn. Whether the character can USE the item (level, armor
--  or weapon skill) is the caller's to check.
--  GS.AgainstWorn(link, weights, stats) -> slot, newScore, wornScore (wornScore nil = empty slot), or nil + reason.
--  stats (optional): the new item's GetItemStats table, read earlier. The Auction House list passes it because the
--  game does not keep details for tens of thousands of items loaded at once (measured 2026-11-27: of 25,006 gear
--  listings, 13,830-14,396 unloaded on each opening, a different set each time), so a live read misses at random.
----------------------------------------------------------------
local ARMOR_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_CLOAK = { 15 },
}
local WEAPON_LOCS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true, INVTYPE_RELIC = true,
}
local HANDS = { [16] = "mh", [17] = "oh", [18] = "ranged" }
GS.ARMOR_SLOTS, GS.WEAPON_LOCS = ARMOR_SLOTS, WEAPON_LOCS

local function Instant(link)
    local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return nil end
    return equipLoc, classID, subclassID
end

local function WornLink(slot)
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    return ok and link or nil
end

local function ArmorType(link, equipLoc)
    if not link or equipLoc == "INVTYPE_CLOAK" then return nil end
    local _, classID, subclassID = Instant(link)
    if classID == 4 and type(subclassID) == "number" and subclassID >= 1 and subclassID <= 4 then return subclassID end
    return nil
end

-- statsOf (optional): function(link) -> GetItemStats-style table, used for the WORN items too (the AH list keeps what
-- it has read). A worn piece whose score cannot be read is "worn gear unreadable", never an empty slot (owner,
-- 2026-11-27: every Gain read Empty Slot with shields equipped -- the weapon path returned a nil worn score, which the
-- list shows as nothing worn).
function GS.AgainstWorn(link, weights, stats, statsOf)
    weights = weights or GS.Current()
    if not (link and weights) then return nil, "no scores" end
    local function Mine(hand)
        if type(stats) == "table" then return GS.Score(stats, hand, weights) end
        return GS.ScoreLink(link, hand, weights)
    end
    local function Worn(l, hand)
        if statsOf then
            local st = statsOf(l)
            if type(st) == "table" then return GS.Score(st, hand, weights) end
        end
        return GS.ScoreLink(l, hand, weights)
    end
    local equipLoc = Instant(link)
    if WEAPON_LOCS[equipLoc] then
        for s = 16, 18 do
            local worn = WornLink(s)
            if worn and Instant(worn) == equipLoc then
                local _, wClass, wSub = Instant(worn)
                if wClass == 2 and (wSub == 14 or wSub == 20) then return nil, "a tool in that hand" end
                local wornScore = Worn(worn, HANDS[s])
                if wornScore == nil then return nil, "worn gear unreadable" end
                return s, Mine(HANDS[s]), wornScore
            end
        end
        return nil, "no worn weapon of the same kind"
    end
    local slots = ARMOR_SLOTS[equipLoc]
    if not slots then return nil, "slot left alone" end
    local lowSlot, low
    for _, s in ipairs(slots) do
        local worn = WornLink(s)
        if not worn then return s, Mine(nil), nil end
        local sc = Worn(worn, nil)
        if sc and (not low or sc < low) then low, lowSlot = sc, s end
    end
    if not lowSlot then return nil, "worn gear unreadable" end
    local mineT, theirsT = ArmorType(link, equipLoc), ArmorType(WornLink(lowSlot), equipLoc)
    if mineT and theirsT and mineT < theirsT then return nil, "lighter armor" end
    return lowSlot, Mine(nil), low
end
