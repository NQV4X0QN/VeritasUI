-- VeritasUI_QualityOfLife / LootSparkles.lua
-- Loot Sparkles (owner's request, 2026-11-27): the game's own sparkle on lootable quest objects.
-- Kept out of QualityOfLife.lua, whose main chunk is at Lua's 200-locals limit.
--
-- The sparkle is the game's, switched by one setting the game has but its Options do not show:
-- outlineModeShowLootEffectWhenDisabled (no Blizzard Lua reads or writes it: wow-ui-source live and forever).
-- Seen on the owner's account (WoW Forever config-cache.wtf, 2026-11-27), where two AddOns he tried had left it on; it
-- is stored with the account, so it follows the player to every computer. A graphics preset resets it (both of those
-- AddOns re-apply it on CVAR_UPDATE for graphicsQuality / raidGraphicsQuality), so while the option is on it is set
-- again a moment after a graphics change. The outline mode is left to the player.
--
--   * Offered only where the game has the setting (C_CVar.GetCVarInfo).
--   * On at login when the setting already is (an account that has it on keeps it, and the box says so).
--   * Off: the setting goes back to the game's default once, at the click; nothing is written after that.
--   * Never written in combat: a change waits for PLAYER_REGEN_ENABLED.

local VUI = _G.VeritasUI
if not VUI then return end

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local WATCHED = { graphicsquality = true, raidgraphicsquality = true, [CVAR:lower()] = true }
local REAPPLY_DELAY = 1   -- seconds after a graphics change: a preset sets many settings at once

local function DB() return _G.VeritasUI_QualityOfLifeDB end

local function Get()
    local cv = C_CVar
    if not (cv and cv.GetCVar) then return nil end
    local ok, v = pcall(cv.GetCVar, CVAR)
    return ok and v or nil
end

local function Exists()
    local cv = C_CVar
    if not (cv and cv.GetCVarInfo) then return false end
    local ok, v = pcall(cv.GetCVarInfo, CVAR)
    return ok and v ~= nil
end

local function Default()
    local cv = C_CVar
    local ok, v = false, nil
    if cv and cv.GetCVarDefault then ok, v = pcall(cv.GetCVarDefault, CVAR) end
    return (ok and type(v) == "string") and v or "0"
end

local function On()
    local db = DB()
    return type(db) == "table" and db.lootSparkles == true and Exists()
end

local pending   -- "on" / "off" waiting for combat to end
local function Write(value)
    if InCombatLockdown() then pending = value; return end
    pending = nil
    if Get() ~= value then pcall(C_CVar.SetCVar, CVAR, value) end
end

local function Apply()
    if On() then Write("1") end
end

local waiting = false
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CVAR_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        local db = DB()
        -- The game already shows the sparkle: the option reads on, and keeps it on through graphics changes.
        if type(db) == "table" and db.lootSparkles ~= true and Exists() and Get() == "1" then db.lootSparkles = true end
        Apply()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Write(pending) end
    elseif event == "CVAR_UPDATE" then
        if not On() or waiting or type(name) ~= "string" or not WATCHED[name:lower()] then return end
        waiting = true
        C_Timer.After(REAPPLY_DELAY, function() waiting = false; Apply() end)
    end
end)

-- Options (QualityOfLife.lua InitializeOptions, General). Only where the game has the setting.
VUI.QoL_LootSparklesOption = function(AddCheckbox)
    if not Exists() then return end
    AddCheckbox("lootSparkles", "Loot Sparkles",
        "Lootable quest objects sparkle, so they are easy to spot. This is the game's own sparkle; it is kept on "
        .. "when a graphics preset would turn it off. The setting is saved with your account, so it applies on "
        .. "every computer you play on.",
        function(value) Write(value and "1" or Default()) end)
end

VUI.QoL_LootSparkles = { CVAR = CVAR, Apply = Apply, On = On }   -- for qol_lootsparkles_test
