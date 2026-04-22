-- VeritasUI_HUDFrame / DataPoints.lua
-- Registry of all data text display points.
-- Each entry: { label, getValue, warnThreshold (optional), warnColor (optional) }

local _, HUF = ...

local _G             = _G
local ipairs         = ipairs
local pcall, type    = pcall, type
local format         = string.format
local math_floor     = math.floor
local collectgarbage = collectgarbage

local GetMoney                   = GetMoney
local GetZoneText                = GetZoneText
local GetMasteryBonus            = GetMasteryBonus
local GetCombatRatingBonus       = GetCombatRatingBonus
local GetInventoryItemDurability = GetInventoryItemDurability
local UnitArmor                  = UnitArmor
local GetAverageItemLevel        = GetAverageItemLevel
local IsInGuild                  = IsInGuild
local GetNumGuildMembers         = GetNumGuildMembers
local C_FriendList               = C_FriendList

----------------------------------------------------------------
--  Shared helpers
----------------------------------------------------------------
local DUR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }

local function GetLowestDurability()
    local lowest
    for _, slot in ipairs(DUR_SLOTS) do
        local ok, result = pcall(function()
            local cur, max = GetInventoryItemDurability(slot)
            if not cur or not max or max == 0 then return nil end
            return cur / max * 100
        end)
        if ok and type(result) == "number" then
            if not lowest or result < lowest then lowest = result end
        end
    end
    return lowest
end

local function FormatGold(copper)
    if copper <= 0 then return "0|cffffaa00g|r" end
    local g = math_floor(copper / 10000)
    local s = math_floor((copper % 10000) / 100)
    if g >= 1000 then
        return format("%d,%03d|cffffaa00g|r", math_floor(g / 1000), g % 1000)
    elseif g > 0 then
        return format("%d|cffffaa00g|r %d|cffc0c0c0s|r", g, s)
    elseif s > 0 then
        return format("%d|cffc0c0c0s|r %d|cffb87333c|r", s, copper % 100)
    else
        return format("%d|cffb87333c|r", copper % 100)
    end
end

----------------------------------------------------------------
--  Registry
----------------------------------------------------------------
HUF.DataPoints = {

    haste = {
        label    = "Haste",
        getValue = function()
            local ok, r = pcall(function()
                return format("%.1f%%", GetCombatRatingBonus(CR_HASTE_MELEE))
            end)
            return ok and r or "—"
        end,
    },

    mastery = {
        label    = "Mastery",
        getValue = function()
            local ok, r = pcall(function()
                return format("%.1f%%", GetMasteryBonus())
            end)
            return ok and r or "—"
        end,
    },

    crit = {
        label    = "Crit",
        getValue = function()
            local ok, r = pcall(function()
                return format("%.1f%%", GetCombatRatingBonus(CR_CRIT_MELEE))
            end)
            return ok and r or "—"
        end,
    },

    armor = {
        label    = "Armor",
        getValue = function()
            local ok, r = pcall(function()
                local base = UnitArmor("player")
                return format("%d", base)
            end)
            return ok and r or "—"
        end,
    },

    ilvl = {
        label    = "ilvl",
        getValue = function()
            local ok, r = pcall(function()
                local avg = GetAverageItemLevel()
                return format("%.0f", avg)
            end)
            return ok and r or "—"
        end,
    },

    memory = {
        label    = "Mem",
        getValue = function()
            local mb = collectgarbage("count") / 1024
            return format("%.1f MB", mb)
        end,
        warnThreshold = function()
            local mb = collectgarbage("count") / 1024
            local thresh = HUF.Config and HUF.Config.WARN_MEMORY_MB or 80
            return mb > thresh
        end,
        warnColor = "|cffff4444",
    },

    durability = {
        label    = "Dur",
        getValue = function()
            local pct = GetLowestDurability()
            return pct and format("%.0f%%", pct) or "—"
        end,
        warnThreshold = function()
            local pct = GetLowestDurability()
            local thresh = HUF.Config and HUF.Config.WARN_DURABILITY_PCT or 20
            return pct ~= nil and pct < thresh
        end,
        warnColor = "|cffff4444",
    },

    gold = {
        label    = "Gold",
        getValue = function()
            return FormatGold(GetMoney())
        end,
    },

    guild = {
        label    = "Guild",
        getValue = function()
            if not IsInGuild() then return "—" end
            local ok, r = pcall(function()
                local _, online = GetNumGuildMembers()
                return tostring(online)
            end)
            return (ok and r) or "—"
        end,
    },

    friends = {
        label    = "Friends",
        getValue = function()
            if not (C_FriendList and C_FriendList.GetNumOnlineFriends) then return "—" end
            local ok, r = pcall(function()
                return tostring(C_FriendList.GetNumOnlineFriends())
            end)
            return (ok and r) or "—"
        end,
    },

    zone = {
        label    = "Zone",
        getValue = function()
            return GetZoneText() or "—"
        end,
    },

    spec = {
        label    = "Spec",
        getValue = function()
            local ok, r = pcall(function()
                local idx = C_SpecializationInfo.GetSpecialization()
                if not idx then return "—" end
                local _, name = C_SpecializationInfo.GetSpecializationInfo(idx)
                return name or "—"
            end)
            return (ok and r) or "—"
        end,
    },

    empty = {
        label    = "Empty",
        getValue = function() return "" end,
    },
}
