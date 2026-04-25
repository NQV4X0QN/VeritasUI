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
--
--  Durability scan result is cached for 100ms because the ticker
--  invokes both getValue and tierColor back-to-back via FormatSlot
--  — without the cache each tick would scan the 11 gear slots twice.
----------------------------------------------------------------
local DUR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }

local _durCacheTime, _durCacheValue = -1, nil
local function GetLowestDurability()
    local now = GetTime()
    if _durCacheTime == now then return _durCacheValue end
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
    _durCacheTime, _durCacheValue = now, lowest
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
        events = { "UNIT_AURA", "COMBAT_RATING_UPDATE" },
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
        events = { "UNIT_AURA", "COMBAT_RATING_UPDATE", "MASTERY_UPDATE" },
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
        events = { "UNIT_AURA", "COMBAT_RATING_UPDATE" },
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
        events = { "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED" },
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
        onClick = function() ToggleCharacter("PaperDollFrame") end,
        onEnter = function(tooltip)
            local overall, equipped, pvp = GetAverageItemLevel()
            tooltip:AddDoubleLine("Overall",  format("%.1f", overall or 0))
            tooltip:AddDoubleLine("Equipped", format("%.1f", equipped or 0))
            if pvp and pvp > 0 then
                tooltip:AddDoubleLine("PvP", format("%.1f", pvp))
            end
        end,
        clickHint = "open character panel",
        events = { "PLAYER_EQUIPMENT_CHANGED" },
    },

    memory = {
        label    = "Mem",
        -- Sums per-addon memory via GetAddOnMemoryUsage to match the
        -- microbar AddOns tooltip. collectgarbage("count") returns the
        -- entire Lua heap (Blizzard UI + every framework + every addon),
        -- which is accurate but larger than what users expect when they
        -- see "AddOn Memory" reported elsewhere.
        getValue = function()
            local ok, r = pcall(function()
                UpdateAddOnMemoryUsage()
                local total = 0
                for i = 1, C_AddOns.GetNumAddOns() do
                    total = total + (GetAddOnMemoryUsage(i) or 0)
                end
                if total >= 1024 then
                    return format("%.1f MB", total / 1024)
                end
                return format("%.0f KB", total)
            end)
            return ok and r or "—"
        end,
        tierColor = function()
            UpdateAddOnMemoryUsage()
            local total = 0
            for i = 1, C_AddOns.GetNumAddOns() do
                total = total + (GetAddOnMemoryUsage(i) or 0)
            end
            local mb = total / 1024
            if mb < 50  then return "|cff40ff40" end
            if mb < 150 then return "|cffffd100" end
            return "|cffff4444"
        end,
        onClick = function()
            local before = collectgarbage("count")
            collectgarbage("collect")
            local freed = (before - collectgarbage("count")) / 1024
            DEFAULT_CHAT_FRAME:AddMessage(format(
                "|cffffd100[HUD Frame]|r Freed |cff40ff40%.2f MB|r of Lua memory.",
                freed))
        end,
        onEnter = function(tooltip)
            UpdateAddOnMemoryUsage()
            local addons = {}
            for i = 1, C_AddOns.GetNumAddOns() do
                local name = C_AddOns.GetAddOnInfo(i)
                local kb = GetAddOnMemoryUsage(i)
                if kb > 0 then addons[#addons+1] = { name = name, kb = kb } end
            end
            table.sort(addons, function(a, b) return a.kb > b.kb end)
            tooltip:AddLine(" ")
            for i = 1, math.min(10, #addons) do
                local a = addons[i]
                local c = a.kb > 10000 and "|cffff4444"
                       or a.kb > 2000  and "|cffffd100" or "|cff40ff40"
                local val = a.kb > 1024
                    and format("%.1f MB", a.kb / 1024)
                    or  format("%.0f KB", a.kb)
                tooltip:AddDoubleLine(a.name, c .. val .. "|r")
            end
        end,
        clickHint = "force garbage collection",
    },

    fps = {
        label    = "FPS",
        getValue = function()
            local ok, r = pcall(function()
                local fps = GetFramerate()
                return fps and format("%.0f", fps) or "—"
            end)
            return ok and r or "—"
        end,
        tierColor = function()
            local ok, fps = pcall(GetFramerate)
            if not ok or not fps then return "|cffffffff" end
            if fps >= 60 then return "|cff40ff40" end
            if fps >= 30 then return "|cffffd100" end
            return "|cffff4444"
        end,
    },

    latencyWorld = {
        label    = "Latency",
        -- Format matches Blizzard's Game Menu tooltip: "55 ms (home) / 57 ms (world)"
        -- Each value is colored independently so a spike on one side isn't
        -- masked by the other being fine.
        getValue = function()
            local ok, r = pcall(function()
                local _, _, home, world = GetNetStats()
                if not home and not world then return "—" end
                local function tier(ms)
                    if not ms or ms <= 0 then return "|cffffffff" end
                    if ms < 100 then return "|cff40ff40" end
                    if ms < 200 then return "|cffffd100" end
                    return "|cffff4444"
                end
                return format("%s%d ms|r (h) / %s%d ms|r (w)",
                    tier(home),  home  or 0,
                    tier(world), world or 0)
            end)
            return ok and r or "—"
        end,
        -- tierColor returns neutral white so the per-segment inline color
        -- codes in getValue aren't overridden. The outer wrapper still
        -- needs a valid color code, not an empty string, so FormatSlot's
        -- closing |r has something to close.
        tierColor = function() return "|cffffffff" end,
    },

    latencyHome = {
        label    = "Home Latency",
        getValue = function()
            local ok, r = pcall(function()
                local _, _, home = GetNetStats()
                return home and format("%d ms", home) or "—"
            end)
            return ok and r or "—"
        end,
        tierColor = function()
            local ok, _, _, home = pcall(GetNetStats)
            if not ok or not home then return "|cffffffff" end
            if home < 100 then return "|cff40ff40" end
            if home < 200 then return "|cffffd100" end
            return "|cffff4444"
        end,
    },

    durability = {
        label    = "Dur",
        getValue = function()
            local lowest = GetLowestDurability()
            return lowest and format("%.0f%%", lowest) or "—"
        end,
        tierColor = function()
            local lowest = GetLowestDurability()
            if not lowest then return "|cffffffff" end
            if lowest >= 50 then return "|cff40ff40" end
            if lowest >= 20 then return "|cffffd100" end
            return "|cffff4444"
        end,
        onClick = function() ToggleCharacter("PaperDollFrame") end,
        onEnter = function(tooltip)
            local slotNames = {
                [1]="Head", [3]="Shoulders", [5]="Chest", [6]="Waist",
                [7]="Legs", [8]="Feet", [9]="Wrist", [10]="Hands",
                [15]="Back", [16]="Main Hand", [17]="Off Hand",
            }
            tooltip:AddLine(" ")
            for _, s in ipairs(DUR_SLOTS) do
                local cur, max = GetInventoryItemDurability(s)
                if cur and max and max > 0 then
                    local p = (cur/max)*100
                    local c = p >= 50 and "|cff40ff40"
                           or p >= 20 and "|cffffd100" or "|cffff4444"
                    tooltip:AddDoubleLine(slotNames[s] or ("Slot "..s),
                        c .. format("%.0f%%|r", p))
                end
            end
        end,
        clickHint = "open character panel",
        events = { "UPDATE_INVENTORY_DURABILITY" },
    },

    gold = {
        label    = "Gold",
        getValue = function()
            local ok, r = pcall(function()
                local copper = GetMoney()
                local g = math.floor(copper / 10000)
                if g >= 1000000 then
                    return format("%.1fM g", g / 1000000)
                elseif g >= 1000 then
                    return format("%d,%03dg", math.floor(g/1000), g%1000)
                else
                    return format("%dg", g)
                end
            end)
            return ok and r or "—"
        end,
        -- No onClick: the Currency panel doesn't actually list raw gold,
        -- so clicking would mislead. Hover-only tooltip uses Blizzard's
        -- GetMoneyString for native g/s/c coin icon textures.
        onEnter = function(tooltip)
            local copper = GetMoney()
            tooltip:AddDoubleLine("Balance", GetMoneyString(copper, true))
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
        onClick = function()
            if IsInGuild() then ToggleGuildFrame() end
        end,
        onEnter = function(tooltip)
            if not IsInGuild() then
                tooltip:AddLine("Not in a guild", 1, 1, 1)
                return
            end
            local name = GetGuildInfo("player")
            local total, _, online = GetNumGuildMembers()
            if name then tooltip:AddLine(name, 1, 0.82, 0) end
            tooltip:AddDoubleLine("Online",
                format("%d / %d", online or 0, total or 0))
        end,
        clickHint = "open guild panel",
    },

    friends = {
        label    = "Friends",
        getValue = function()
            local ok, r = pcall(function()
                return tostring(C_FriendList.GetNumOnlineFriends() or 0)
            end)
            return ok and r or "—"
        end,
        onClick = function() ToggleFriendsFrame() end,
        onEnter = function(tooltip)
            local online = C_FriendList.GetNumOnlineFriends() or 0
            local total  = C_FriendList.GetNumFriends() or 0
            tooltip:AddDoubleLine("Online", format("%d / %d", online, total))
        end,
        clickHint = "open friends list",
    },

    zone = {
        label    = "Zone",
        getValue = function()
            local ok, r = pcall(function() return GetZoneText() or "—" end)
            return ok and r or "—"
        end,
        onClick = function() ToggleWorldMap() end,
        clickHint = "open world map",
        onEnter = function(tooltip)
            local z = GetZoneText() or "—"
            local sz = GetSubZoneText() or ""
            tooltip:AddLine(z, 1, 0.82, 0)
            if sz ~= "" and sz ~= z then
                tooltip:AddLine(sz, 1, 1, 1)
            end
            local mapID = C_Map.GetBestMapForUnit("player")
            local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then
                local x, y = pos:GetXY()
                tooltip:AddDoubleLine("Position",
                    format("%.1f, %.1f", x*100, y*100))
            end
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
        onClick = function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage("Can't change spec in combat",
                    1.0, 0.1, 0.1, 1.0)
                return
            end
            local numSpecs = GetNumSpecializations()
            if not numSpecs or numSpecs < 2 then return end
            local currentSpec = GetSpecialization()
            MenuUtil.CreateContextMenu(UIParent, function(_, rootDescription)
                rootDescription:CreateTitle("Switch Specialization")
                for i = 1, numSpecs do
                    local _, name = GetSpecializationInfo(i)
                    if name then
                        local lbl = (i == currentSpec)
                            and ("|cff40ff40" .. name .. " (current)|r") or name
                        local b = rootDescription:CreateButton(lbl, function()
                            C_SpecializationInfo.SetSpecialization(i)
                        end)
                        if i == currentSpec then b:SetEnabled(false) end
                    end
                end
            end)
        end,
        onEnter = function(tooltip)
            local idx = GetSpecialization()
            if not idx then return end
            local _, _, _, _, role, primary = GetSpecializationInfo(idx)
            -- Blizzard's API returns DAMAGER/TANK/HEALER, but the in-game
            -- Specialization panel labels these roles as Damage/Tank/Healer.
            -- Match the panel's terminology for consistency.
            local roleLabels = { DAMAGER = "Damage", TANK = "Tank", HEALER = "Healer" }
            if role then tooltip:AddDoubleLine("Role", roleLabels[role] or role) end
            local stats = { [1]="Strength", [2]="Agility", [4]="Intellect" }
            if primary and stats[primary] then
                tooltip:AddDoubleLine("Primary stat", stats[primary])
            end
        end,
        clickHint = "switch specialization",
        events = { "PLAYER_SPECIALIZATION_CHANGED" },
    },

    empty = {
        label    = "Empty",
        getValue = function() return "" end,
    },
}
