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

local GetHaste                   = GetHaste
local GetCritChance              = GetCritChance
local GetMasteryEffect           = GetMasteryEffect
local GetInventoryItemDurability = GetInventoryItemDurability
local UnitArmor                  = UnitArmor
local GetAverageItemLevel        = GetAverageItemLevel
local GetNumGuildMembers         = GetNumGuildMembers
local GetMoney                   = GetMoney
local GetZoneText                = GetZoneText
local GetSpecialization          = GetSpecialization
local GetSpecializationInfo      = GetSpecializationInfo
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

----------------------------------------------------------------
--  Registry
----------------------------------------------------------------
HUF.DataPoints = {

    haste = {
        label    = "Haste",
        getValue = function()
            local ok, r = pcall(function()
                local h = GetHaste()
                return h and format("%.1f%%", h) or "—"
            end)
            return ok and r or "—"
        end,
    },

    mastery = {
        label    = "Mastery",
        getValue = function()
            local ok, r = pcall(function()
                local effect = select(1, GetMasteryEffect())
                return effect and format("%.1f%%", effect) or "—"
            end)
            return ok and r or "—"
        end,
    },

    crit = {
        label    = "Crit",
        getValue = function()
            local ok, r = pcall(function()
                local c = GetCritChance()
                return c and format("%.1f%%", c) or "—"
            end)
            return ok and r or "—"
        end,
    },

    armor = {
        label    = "Armor",
        getValue = function()
            local ok, r = pcall(function()
                local _, effective = UnitArmor("player")
                return effective and tostring(math_floor(effective)) or "—"
            end)
            return ok and r or "—"
        end,
    },

    ilvl = {
        label    = "ilvl",
        getValue = function()
            local ok, r = pcall(function()
                local _, equipped = GetAverageItemLevel()
                return equipped and format("%.0f", equipped) or "—"
            end)
            return ok and r or "—"
        end,
    },

    memory = {
        label    = "Mem",
        getValue = function()
            local ok, r = pcall(function()
                local mem = collectgarbage("count")
                return format("%.1f MB", mem / 1024)
            end)
            return ok and r or "—"
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
            local ok, r = pcall(function()
                local lowest = 100
                for slot = 1, 18 do
                    local cur, max = GetInventoryItemDurability(slot)
                    if cur and max and max > 0 then
                        local pct = (cur / max) * 100
                        if pct < lowest then lowest = pct end
                    end
                end
                return format("%.0f%%", lowest)
            end)
            return ok and r or "—"
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
            local ok, r = pcall(function()
                local copper = GetMoney()
                local gold = math_floor(copper / 10000)
                if gold >= 1000000 then
                    return format("%.1fM g", gold / 1000000)
                elseif gold >= 1000 then
                    return format("%d,%03dg", math_floor(gold / 1000), gold % 1000)
                else
                    return format("%dg", gold)
                end
            end)
            return ok and r or "—"
        end,
    },

    guild = {
        label    = "Guild",
        getValue = function()
            local ok, r = pcall(function()
                local _, numOnline = GetNumGuildMembers()
                return numOnline and tostring(numOnline) or "—"
            end)
            return ok and r or "—"
        end,
    },

    friends = {
        label    = "Friends",
        getValue = function()
            local ok, r = pcall(function()
                local online = C_FriendList.GetNumOnlineFriends()
                return online and tostring(online) or "—"
            end)
            return ok and r or "—"
        end,
    },

    zone = {
        label    = "Zone",
        getValue = function()
            local ok, r = pcall(function()
                return GetZoneText() or "—"
            end)
            return ok and r or "—"
        end,
    },

    spec = {
        label    = "Spec",
        getValue = function()
            local ok, r = pcall(function()
                local specIndex = GetSpecialization()
                if not specIndex then return "—" end
                local _, name = GetSpecializationInfo(specIndex)
                return name or "—"
            end)
            return ok and r or "—"
        end,
    },

    empty = {
        label    = "Empty",
        getValue = function() return "" end,
    },
}
