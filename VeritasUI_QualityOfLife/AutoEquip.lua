-- VeritasUI_QualityOfLife / AutoEquip.lua
-- Auto Equip Upgrades (owner's request, 2026-11-04, WoW Forever: grey leather in the bags beat the starter cloth).
-- Kept out of QualityOfLife.lua, whose main chunk is near Lua's 200-locals limit.
--
-- WoW FOREVER ONLY (owner, 2026-11-26). The decision is a score from stat weights that exist for Forever alone
-- (WoWSims); Retail's item-level rules were removed with the owner's "I don't want us using that system anymore",
-- and Auto Equip is off and its options hidden on Retail until it has its own weights (open-work: PARKED Retail
-- stat weights). The fishing pole below is not part of Auto Equip and is untouched.
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
--   * better than what is worn: an empty slot, or a higher score (see Scores below), never a lighter armor type.
--     Rings go to an empty ring slot, else replace the lower-scoring one. Weapons only replace a worn weapon of the
--     same kind (two-hander for two-hander, ranged for ranged), so a weapon and off-hand pair is never broken up.

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

-- The stats of an item, for its score: every stat C_Item.GetItemStats reports (armor is RESISTANCE0_NAME), nil when
-- they cannot be read. Armor comes from ArmorValue (the stats, else the tooltip's "N Armor" line: which one WoW
-- Forever fills is unmeasured), so an item whose armor only the tooltip shows is never scored without it.
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

-- ── Scores (WoW Forever, 2026-11-26) ─────────────────────────
-- The score ALONE decides (VeritasUI_Lib GearScore.lua: WoWSims stat weights for your class and playstyle, scaled
-- to your level): the higher score wins, by at least SCORE_MARGIN so two near-equal pieces cannot swap back and
-- forth as your damage changes. Nothing falls back to item level (owner, 2026-11-26: the old item-level rules were
-- removed): stats that cannot be read yet wait for the next bag update, and two pieces with nothing your playstyle
-- scores leave the worn one on.
local SCORE_MARGIN = 0.01
local HAND = { [16] = "mh", [17] = "oh", [18] = "ranged" }

local function Weights()
    if not (VUI.IS_FOREVER and VUI.GearScore and VUI.GearScore.Current) then return nil end
    local ok, w = pcall(VUI.GearScore.Current)
    return ok and w or nil
end

local function ScoreOf(link, tip, hand, W)
    local st = StatsOf(link, tip)
    if not st then return nil end
    return VUI.GearScore.Score(st, hand, W)
end

-- true/false + reason. A score that cannot be read is false ("not readable yet": the next bag update tries again).
local function ScoreDecides(newScore, oldScore)
    if not (newScore and oldScore) then return false, "stats not readable yet" end
    if newScore == 0 and oldScore == 0 then return false, "nothing your playstyle scores on either" end
    local gain = oldScore > 0 and math.floor((newScore / oldScore - 1) * 100 + 0.5) or nil
    local how = format("score %.1f vs %.1f%s", newScore, oldScore, gain and format(" (%+d%%)", gain) or "")
    if newScore > oldScore * (1 + SCORE_MARGIN) + 1e-6 then return true, how end
    return false, how
end
VUI.QoL_AutoEquipScoreDecides = ScoreDecides   -- headless suite seam

-- The decision for one bag item: target slot (or nil) and the reason, for the probe.
-- probe (/qol equipcheck only): a quality that is not ticked or a bind-on-equip piece is still compared, so its
-- score can be read; the rule that stops it is named first and the piece is never reported as equippable.
local probeStop
local function DecideInner(bag, slot, info, W, probe)
    local link = info.hyperlink
    if not link then return nil, nil end
    local okE, equippable = pcall(C_Item.IsEquippableItem, link)
    if not (okE and equippable) then return nil, nil end   -- not gear: not listed at all
    if not QualityAllowed(info.quality) then
        local why = "quality " .. tostring(info.quality) .. " not chosen"
        if not probe then return nil, why end
        probeStop = why
    end
    local equipLoc, classID, subclassID = Info(link)
    if IsTool(classID, subclassID) then return nil, "profession tool" end
    local red, readable = RedLines(bag, slot)
    if not readable then return nil, "tooltip not readable yet" end
    if red and #red > 0 then return nil, "can't use: " .. table.concat(red, "; ") end
    local okB, bindType = pcall(function() return select(14, C_Item.GetItemInfo(link)) end)
    if okB and bindType == 2 and not info.isBound then
        if not probe then return nil, "binds when equipped" end
        probeStop = probeStop and (probeStop .. ", binds when equipped") or "binds when equipped"
    end
    if not W then return nil, "no stat weights for your class" end
    local bagTip = { "GetBagItem", bag, slot }
    if WEAPONS[equipLoc] then
        for _, s in ipairs(WEAPON_SLOTS) do
            local worn = WornLink(s)
            if worn and Info(worn) == equipLoc then
                local _, wClass, wSub = Info(worn)
                -- A Fishing Pole is only ever worn on purpose (to fish), so it is never swapped out here:
                -- Priority Rotation puts the weapons back on the next rotation press (its Reequip.lua).
                if wClass == 2 and wSub == 20 then return nil, "weapon: you are fishing" end
                if IsTool(wClass, wSub) then return s, "weapon: replaces a profession tool" end
                local hand = HAND[s]
                local better, how = ScoreDecides(ScoreOf(link, bagTip, hand, W),
                    ScoreOf(worn, { "GetInventoryItem", "player", s }, hand, W))
                return better and s or nil, "weapon: " .. how
            end
        end
        return nil, "weapon: no worn weapon of the same kind"
    end
    local slots = SLOTS[equipLoc]
    if not slots then return nil, "slot left alone (" .. tostring(equipLoc) .. ")" end
    for _, s in ipairs(slots) do
        if not WornLink(s) then return s, "empty slot" end
    end
    -- Two rings compare against the lower-scoring one.
    local wornScores, low, lowestSlot = {}, nil, nil
    for _, s in ipairs(slots) do
        local sc = ScoreOf(WornLink(s), { "GetInventoryItem", "player", s }, nil, W)
        if not sc then return nil, "stats not readable yet" end
        wornScores[s] = sc
        if not low or sc < low then low, lowestSlot = sc, s end
    end
    local worn = WornLink(lowestSlot)
    local mineT, theirsT = ArmorType(link, equipLoc), ArmorType(worn, equipLoc)
    if mineT and theirsT and mineT < theirsT then return nil, "lighter armor than what you wear" end
    if worn == link then return nil, "same item" end
    local better, how = ScoreDecides(ScoreOf(link, bagTip, nil, W), wornScores[lowestSlot])
    return better and lowestSlot or nil, how
end

local function Decide(bag, slot, info, W, probe)
    probeStop = nil
    local target, reason = DecideInner(bag, slot, info, W, probe)
    if probeStop then
        local stop = probeStop
        probeStop = nil
        if reason == nil and target == nil then return nil, stop end
        return nil, format("%s; otherwise %s%s", stop,
            target and ("it would go in slot " .. target .. " -- ") or "", tostring(reason))
    end
    return target, reason
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
    if not VUI.IS_FOREVER then
        VUI.Print("Quality of Life", "Auto Equip is WoW Forever only for now.")
        return
    end
    local W = Weights()
    VUI.Print("Quality of Life", format("Equip check (nothing is equipped). In combat: %s",
        tostring(InCombatLockdown() and true or false)))
    if not W then
        VUI.Print("Quality of Life", "  No stat weights for your class: nothing would be equipped.")
    else
        VUI.Print("Quality of Life", format("  Scoring for %s, level %d (percent stats x%.2f, avoidance x%.2f).",
            W.profile.name, W.level, W.s or 1, W.h or 1))
    end
    local n = 0
    ForEachBagItem(function(bag, slot, info)
        local target, reason = Decide(bag, slot, info, W, true)
        if reason or target then
            n = n + 1
            local unscored = ""
            if W and info.hyperlink then
                local _, un = VUI.GearScore.ScoreLink(info.hyperlink, nil, W)
                if un then
                    local names = {}
                    for k in pairs(un) do names[#names + 1] = tostring(_G[k] or k) end
                    table.sort(names)
                    unscored = "; not scored: " .. table.concat(names, ", ")
                end
            end
            VUI.Print("Quality of Life", format("  %s (q%s, ilvl %d): %s%s%s", tostring(info.hyperlink),
                tostring(info.quality), info.hyperlink and ItemLevel(info.hyperlink) or 0,
                target and ("WOULD EQUIP in slot " .. target .. " -- ") or "skip -- ", tostring(reason), unscored))
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
-- Retail: off whatever the saved setting says (WoW Forever only, see the header).
local function On()
    local db = DB()
    return VUI.IS_FOREVER and type(db) == "table" and db.autoEquip == true
end

local function Run()
    if not On() then pending = false; return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local okD, dead = pcall(_G.UnitIsDeadOrGhost, "player")
    if okD and dead then return end
    local okC, cursor = pcall(GetCursorInfo)
    if okC and cursor then return end
    local now, done = GetTime(), false
    local W = Weights()
    ForEachBagItem(function(bag, slot, info)
        if done then return end
        local target = Decide(bag, slot, info, W)
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

-- ── Fishing puts on your fishing pole (WoW Forever, owner 2026-11-12; always on, not tied to Auto Equip) ──
-- Pressing Fishing without a pole: the game refuses the cast and fires UNIT_SPELLCAST_FAILED for the player with
-- spell 7620 "Fishing" while the main hand holds no pole (measured, owner's Forever probe 2026-11-12: FAILED +
-- UI_ERROR_MESSAGE 278 ERR_SPELL_FAILED_EQUIPPED_ITEM_CLASS_S "Must have a Fishing Pole equipped", from an action
-- bar press). Out of combat we then equip the best usable pole from the bags (highest item level), so the next
-- press fishes. Matched by the spell's NAME so a higher Fishing rank counts too. Never in combat (fishing is not
-- possible then and equipping is the game's to refuse), while dead, or with something on the cursor. Priority
-- Rotation's rotation key puts the weapons back (its Reequip.lua). Retail fishes from the profession tool slot and
-- never sees this failure for a missing pole.
local FISHING_SPELL = 7620
local fishName, lastPoleTry = nil, 0

local function IsPole(link)
    local _, classID, subclassID = Info(link)
    return classID == 2 and subclassID == 20
end

local function BestPole()
    local best, bestLevel
    ForEachBagItem(function(bag, slot, info)
        local link = info.hyperlink
        if not (link and IsPole(link)) then return end
        local red, readable = RedLines(bag, slot)
        if readable and red and #red > 0 then return end   -- a pole you can't use yet
        local lvl = ItemLevel(link)
        if not bestLevel or lvl > bestLevel then best, bestLevel = link, lvl end
    end)
    return best
end

local fishFrame = CreateFrame("Frame")
fishFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
fishFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or type(spellID) ~= "number" or Secret(spellID) then return end
    if not fishName then
        local ok, n = pcall(C_Spell.GetSpellName, FISHING_SPELL)
        fishName = ok and type(n) == "string" and n ~= "" and n or nil
        if not fishName then return end
    end
    if spellID ~= FISHING_SPELL then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if not (ok and n == fishName) then return end
    end
    if InCombatLockdown() then return end
    local worn = WornLink(16)
    if worn and IsPole(worn) then return end   -- refused for another reason (no water, moving)
    local okD, dead = pcall(_G.UnitIsDeadOrGhost, "player")
    if okD and dead then return end
    local okC, cursor = pcall(GetCursorInfo)
    if okC and cursor then return end
    local now = GetTime()
    if now - lastPoleTry < 1 then return end
    local pole = BestPole()
    if not pole then return end
    lastPoleTry = now
    pcall(C_Item.EquipItemByName, pole, 16)
end)

-- ── Your Fishing key reels in (WoW Forever, owner 2026-11-12) ──
-- While the Fishing channel runs, every key bound to an action button holding Fishing (or bound to the spell itself)
-- is pointed at Blizzard's Interact Key binding, INTERACTTARGET = C_PlayerInteractionManager.InteractUnit
-- ("anyinteract") (forever Bindings_Camelot.xml:1140-1142); the soft target picks up the bobber (owner-tested with
-- Blizzard's own Interact Key, 2026-11-12). The keys go back when the channel ends. Only while Options > Controls >
-- Enable Interact Key is on: Blizzard's check, softTargetInteract == Enum.SoftTargetEnableFlags.Any (forever
-- Camelot/ControlsOverrides.lua:75); without it the key would do nothing during the cast. Override bindings are the
-- game's to refuse in combat, so they are set only out of combat and cleared through VUI.CombatQueue. A mouse click
-- on the Fishing button is unchanged (Blizzard's button is never touched).
local REEL_BINDS = {   -- action slot -> binding name, the bars' own (PriorityRotation Core.lua BIND_DEFS)
    { base = 0, bind = "ACTIONBUTTON" }, { base = 24, bind = "MULTIACTIONBAR3BUTTON" },
    { base = 36, bind = "MULTIACTIONBAR4BUTTON" }, { base = 48, bind = "MULTIACTIONBAR2BUTTON" },
    { base = 60, bind = "MULTIACTIONBAR1BUTTON" }, { base = 144, bind = "MULTIACTIONBAR5BUTTON" },
    { base = 156, bind = "MULTIACTIONBAR6BUTTON" }, { base = 168, bind = "MULTIACTIONBAR7BUTTON" },
}
local reelOwner = CreateFrame("Frame")
local reeling = false

local function IsFishing(spellID)
    if type(spellID) ~= "number" or Secret(spellID) then return false end
    if spellID == FISHING_SPELL then return true end
    if not fishName then
        local ok, n = pcall(C_Spell.GetSpellName, FISHING_SPELL)
        fishName = ok and type(n) == "string" and n ~= "" and n or nil
    end
    local ok, n = pcall(C_Spell.GetSpellName, spellID)
    return fishName ~= nil and ok and n == fishName
end

local function InteractKeyOn()
    local flags = _G.Enum and _G.Enum.SoftTargetEnableFlags
    local ok, v = pcall(GetCVar, "softTargetInteract")
    return flags and flags.Any and ok and tonumber(v) == flags.Any
end

-- Every key that casts Fishing now: its action buttons' bindings, and a binding to the spell itself.
local function FishingKeys()
    local keys, seen = {}, {}
    local function add(cmd)
        local okK, k1, k2 = pcall(GetBindingKey, cmd)
        if not okK then return end
        for _, k in ipairs({ k1, k2 }) do
            if type(k) == "string" and not seen[k] then seen[k] = true; keys[#keys + 1] = k end
        end
    end
    for _, def in ipairs(REEL_BINDS) do
        for i = 1, 12 do
            local okA, kind, id = pcall(GetActionInfo, def.base + i)
            if okA and kind == "spell" and IsFishing(id) then add(def.bind .. i) end
        end
    end
    if fishName then add("SPELL " .. fishName) end
    return keys
end

local function StopReel()
    if not reeling then return end
    if InCombatLockdown() then VUI.CombatQueue.Add(StopReel); return end
    pcall(ClearOverrideBindings, reelOwner)
    reeling = false
end

local function StartReel()
    if InCombatLockdown() or not InteractKeyOn() then return end
    local keys = FishingKeys()
    if #keys == 0 then return end
    pcall(ClearOverrideBindings, reelOwner)
    for _, k in ipairs(keys) do pcall(SetOverrideBinding, reelOwner, true, k, "INTERACTTARGET") end
    reeling = true
end

local reelFrame = CreateFrame("Frame")
reelFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
reelFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
reelFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        if IsFishing(spellID) then StartReel() end
    else
        StopReel()
    end
end)
