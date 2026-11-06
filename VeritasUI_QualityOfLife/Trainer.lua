-- VeritasUI_QualityOfLife / Trainer.lua
-- New class skills at the trainer (owner's request, 2026-11-05, WoW Forever). PROBE BUILD -- changes nothing:
-- the class trainer's list is saved each time you visit, and `/qol trainable` prints it with what a minimap
-- button would show.
--
-- MEASURED (owner, Forever, level 7, build 1): the spellbook lists NO future spells ("0 at later levels" while the
-- trainer shows Concussive Shot 8, Aspect of the Hawk 10 ...), so the spellbook alone cannot say what is coming.
-- SOURCED (Gethe wow-ui-source, forever branch, Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua): the trainer
-- window reads each service with GetTrainerServiceInfo(i) -> name, serviceType ("available" / "unavailable" /
-- "used"), texture, reqLevel, subText ("Rank 2") (:618), GetTrainerServiceCost(i) (:692),
-- GetTrainerServiceNumAbilityReq / GetTrainerServiceAbilityReq (:648-660); C_Trainer.GetTrainerType()
-- (Enum.TrainerType General 0, Tradeskills 2, Pet 3). Those only answer while the trainer window is open, so the
-- list is copied on TRAINER_SHOW / TRAINER_UPDATE. Which services the list holds follows the trainer's
-- Available / Unavailable / Known filters (GetNumTrainerServices counts the filtered list); recorded, not changed.
-- "Learned since the visit" = a spellbook spell with the same name and rank (UNMEASURED: Forever's spellbook
-- subName format).

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, format = pcall, ipairs, string.format

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function CharKey()
    local ok, name = pcall(UnitName, "player")
    local okR, realm = pcall(GetRealmName)
    return format("%s-%s", okR and realm or "?", ok and name or "?")
end

-- Every spellbook item of the player's bank: calls fn(info).
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

-- name -> { [subName] = true } for every spell you know.
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
    if type(db) ~= "table" then return end
    local okT, ttype = pcall(C_Trainer.GetTrainerType)
    local general = Enum and Enum.TrainerType and Enum.TrainerType.General or 0
    if not okT or ttype ~= general then return end
    local okTS, trade = pcall(IsTradeskillTrainer)
    if okTS and trade then return end
    local okN, n = pcall(GetNumTrainerServices)
    if not okN or type(n) ~= "number" then return end
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
                local okR, ability = pcall(GetTrainerServiceAbilityReq, i, a)
                if okR and ability then e.req = e.req or {}; e.req[#e.req + 1] = ability end
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
    db.trainerCache[CharKey()] = { list = list, filters = filters, level = UnitLevel("player"),
        trainer = UnitName("npc"), time = time() }
end

-- What a button would show: services at or below your level that you don't know yet, and those coming later.
local function Trainable()
    local db = DB()
    local cache = type(db) == "table" and db.trainerCache and db.trainerCache[CharKey()]
    if not cache then return nil end
    local known, level = KnownSpells(), UnitLevel("player") or 0
    local now, later = {}, {}
    for _, e in ipairs(cache.list or {}) do
        if e.type ~= "used" and not IsKnown(known, e) then
            if (e.level or 0) > level then later[#later + 1] = e else now[#now + 1] = e end
        end
    end
    return cache, now, later
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
        .. "filters available %s, unavailable %s, known %s.", UnitLevel("player") or 0, tostring(cache.trainer),
        tostring(cache.level), #(cache.list or {}), tostring(f.available), tostring(f.unavailable), tostring(f.used)))
    VUI.Print("Quality of Life", format("  %d to learn now, %d at later levels.", #now, #later))
    for _, e in ipairs(now) do VUI.Print("Quality of Life", Line("NOW", e)) end
    for i, e in ipairs(later) do
        if i > 8 then VUI.Print("Quality of Life", format("  ... and %d more later", #later - 8)); break end
        VUI.Print("Quality of Life", Line("LATER", e))
    end
    -- How the spellbook writes ranks, to match learned spells against the list.
    local shown = 0
    ForEachSpellBookItem(function(info)
        if shown < 3 and info.itemType == SPELL and info.subName and info.subName ~= "" then
            shown = shown + 1
            VUI.Print("Quality of Life", format("  spellbook: %s [%s]", tostring(info.name), tostring(info.subName)))
        end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRAINER_SHOW")
pcall(f.RegisterEvent, f, "TRAINER_UPDATE")
f:SetScript("OnEvent", function() Capture() end)
