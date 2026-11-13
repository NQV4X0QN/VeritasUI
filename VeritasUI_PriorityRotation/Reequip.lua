--[[
    VeritasUI_PriorityRotation — Reequip.lua
    Put your weapons back with the rotation key after fishing.

    WoW Forever puts the Fishing Pole in the main hand, and the game will not let an addon equip anything on its
    own in combat: Blizzard runs /equip and /equipslot as SECURE slash commands (Blizzard_ChatFrameBase/Shared/
    SlashCommands.lua:421-445, forever), so equipping in combat needs the player's own key press. The rotation
    button IS a key press: its press snippet (Core.lua rotBtn WrapScript) runs one macro per press. While a
    Fishing Pole is in the main hand, that press runs "/equipslot 16 <weapon>" (and 17 for an off hand) instead of
    a rotation step, and does not advance the rotation; the next press casts as normal.

    What goes back is what was in the hands before the pole went on, read here out of combat: the hands are
    sampled 0.2 s after the last PLAYER_EQUIPMENT_CHANGED for slot 16/17 (a two-handed pole empties both slots and
    the two events need not arrive together). The snippet's condition and macro are set with rotBtn:Execute, which
    the game allows only out of combat (queued through VUI.CombatQueue otherwise).

    Retail keeps fishing poles in the profession tool slot, so the main hand never holds one and this never fires.
    Not remembered across a /reload or logout: put the pole on after logging in for it to know your weapons.
]]

local VUI = _G.VeritasUI
if not VUI then return end
local _, PR = ...

local C_Item, C_Timer, CreateFrame = C_Item, C_Timer, CreateFrame
local GetInventoryItemID, InCombatLockdown, pcall, format = GetInventoryItemID, InCombatLockdown, pcall, string.format

local MAIN, OFF = 16, 17
-- Weapon class 2, subclass 20 = Fishing Poles (wago.tools Item table, build 1.60.1.70790; same IDs as
-- QualityOfLife AutoEquip's IsTool).
local WEAPON, FISHING_POLES = 2, 20

local function IsPole(itemID)
    if not itemID then return false end
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
    return ok and classID == WEAPON and subclassID == FISHING_POLES
end

local function ItemName(itemID)
    if not itemID then return nil end
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

local function Hands()
    local okM, mh = pcall(GetInventoryItemID, "player", MAIN)
    local okO, oh = pcall(GetInventoryItemID, "player", OFF)
    return okM and mh or nil, okO and oh or nil
end

-- The snippet's condition and macro. A long-string literal holds any item name.
local function Quote(s)
    local level = 0
    while s:find("]" .. string.rep("=", level) .. "]", 1, true) do level = level + 1 end
    local eq = string.rep("=", level)
    return "[" .. eq .. "[" .. s .. "]" .. eq .. "]"
end

local armedText   -- what the snippet holds now (nil = nothing armed)

local function SetSnippet(cond, text)
    local btn = PR.rotBtn
    if not (btn and btn.Execute) then return end
    if InCombatLockdown() then
        VUI.CombatQueue.Add(function() SetSnippet(cond, text) end)
        return
    end
    if cond and text then
        btn:Execute("reequipCond = " .. Quote(cond) .. "; reequipText = " .. Quote(text))
    else
        btn:Execute("reequipCond = nil; reequipText = nil")
    end
    armedText = text
end

-- The re-equip macro for the remembered hands, or nil when there is nothing to put back.
local function BuildText(mh, oh)
    local lines = {}
    local mhName, ohName = ItemName(mh), ItemName(oh)
    if mhName and not IsPole(mh) then lines[#lines + 1] = format("/equipslot %d %s", MAIN, mhName) end
    if ohName then lines[#lines + 1] = format("/equipslot %d %s", OFF, ohName) end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

local last = {}       -- the hands the last time no pole was held
local pending

local function Sample()
    pending = nil
    local mh, oh = Hands()
    if IsPole(mh) then
        local text = BuildText(last.mh, last.oh)
        if text and text ~= armedText then
            local okS, poles = pcall(C_Item.GetItemSubClassInfo, WEAPON, FISHING_POLES)
            if okS and type(poles) == "string" and poles ~= "" then
                SetSnippet(format("[equipped:%s] 1", poles), text)
            end
        end
    else
        last.mh, last.oh = mh, oh
        if armedText then SetSnippet(nil, nil) end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:SetScript("OnEvent", function(_, event, slot)
    if event == "PLAYER_EQUIPMENT_CHANGED" and slot ~= MAIN and slot ~= OFF then return end
    if pending then pending:Cancel() end
    pending = C_Timer.NewTimer(0.2, Sample)
end)

PR._ReequipSample = Sample
