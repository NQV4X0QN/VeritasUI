-- VeritasUI_QualityOfLife / Trainer.lua
-- New class skills at the trainer (owner's request, 2026-11-05, WoW Forever). BUILD 1 = PROBE ONLY:
-- `/qol trainable` prints what a minimap button would show, and changes nothing.
--
-- SOURCED (Gethe wow-ui-source, forever branch): Blizzard's own spellbook calls a spell "Trainable" when its
-- spellbook item is a FutureSpell (Enum.SpellBookItemType 2), not off-spec, and its learned level is at or
-- below yours (Blizzard_PlayerSpells/SpellBook/Blizzard_SpellBookItem.lua:219-247, SPELLBOOK_TRAINABLE). A
-- trainer's own list needs the trainer window open (TRAINER_SHOW), which only talking to the trainer does.
-- UNMEASURED: that Forever's spellbook lists every spell a trainer sells as a FutureSpell (ranks included).

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, format = pcall, ipairs, string.format

-- Every spellbook item of the player's bank: calls fn(info, slot, levelLearned, skillLineName).
local function ForEachSpellBookItem(fn)
    local sb = _G.C_SpellBook
    if not (sb and sb.GetNumSpellBookSkillLines and sb.GetSpellBookSkillLineInfo and sb.GetSpellBookItemInfo) then
        return false
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local okN, lines = pcall(sb.GetNumSpellBookSkillLines)
    for i = 1, (okN and lines or 0) do
        local okL, line = pcall(sb.GetSpellBookSkillLineInfo, i)
        if okL and type(line) == "table" and not line.isGuild and not line.offSpecID then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local okI, info = pcall(sb.GetSpellBookItemInfo, slot, bank)
                if okI and type(info) == "table" then
                    local okV, lvl = pcall(sb.GetSpellBookItemLevelLearned, slot, bank)
                    fn(info, slot, okV and lvl or nil, line.name)
                end
            end
        end
    end
    return true
end

local FUTURE = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell or 2

-- The spells you could learn at your trainer now, and those coming at later levels.
local function Trainable()
    local now, later, level = {}, {}, UnitLevel("player") or 0
    local ok = ForEachSpellBookItem(function(info, _, lvl, lineName)
        if info.itemType ~= FUTURE or info.isOffSpec then return end
        local e = { name = info.name, sub = info.subName, level = lvl, line = lineName, spellID = info.spellID }
        if lvl and lvl > level then later[#later + 1] = e else now[#now + 1] = e end
    end)
    return ok, now, later
end
VUI.QoL_Trainable = Trainable

VUI.QoL_TrainableProbe = function()
    local ok, now, later = Trainable()
    if not ok then VUI.Print("Quality of Life", "Trainer check: the spellbook can't be read here."); return end
    VUI.Print("Quality of Life", format("Trainer check (level %d): %d to learn now, %d at later levels.",
        UnitLevel("player") or 0, #now, #later))
    for _, e in ipairs(now) do
        VUI.Print("Quality of Life", format("  NOW  %s%s (level %s, %s, id %s)", tostring(e.name),
            (e.sub and e.sub ~= "") and (" " .. e.sub) or "", tostring(e.level), tostring(e.line), tostring(e.spellID)))
    end
    for i, e in ipairs(later) do
        if i > 5 then VUI.Print("Quality of Life", format("  ... and %d more later", #later - 5)); break end
        VUI.Print("Quality of Life", format("  LATER  %s%s (level %s)", tostring(e.name),
            (e.sub and e.sub ~= "") and (" " .. e.sub) or "", tostring(e.level)))
    end
end
