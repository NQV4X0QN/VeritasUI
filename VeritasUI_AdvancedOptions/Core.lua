-- VeritasUI_AdvancedOptions / Core.lua
-- Module init, saved variables, slash commands.

local ADDON_NAME, AO = ...
local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G             = _G
local pairs          = pairs
local pcall          = pcall
local type           = type
local format         = string.format
local strtrim        = strtrim
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local C_CVar         = C_CVar
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
AO.VERSION = VUI.VERSION

----------------------------------------------------------------
--  Defaults & state
--
--  We do NOT persist CVar values — WoW's own CVar persistence
--  handles that.  We persist UI-side state: collapsed categories,
--  favourited CVars in the browser, and the last active tab.
----------------------------------------------------------------
local defaults = {
    collapsed = {},          -- [categoryKey] = true/false
    favorites = {},          -- [cvarName]    = true
    lastTab   = 1,           -- 1 = Featured, 2 = All CVars
}

local db

function AO:InitDB()
    VeritasUI_AdvancedOptionsDB = VeritasUI_AdvancedOptionsDB or {}
    db = VeritasUI_AdvancedOptionsDB
    for k, v in pairs(defaults) do
        if db[k] == nil then
            -- Deep-copy table defaults to avoid shared references
            if type(v) == "table" then
                db[k] = {}
                for sk, sv in pairs(v) do db[k][sk] = sv end
            else
                db[k] = v
            end
        end
    end
    AO.db = db
end

----------------------------------------------------------------
--  CVar helpers — thin wrappers with pcall + combat guard
----------------------------------------------------------------

--- Read a CVar value. Returns string or nil on failure.
function AO:GetCVar(name)
    local ok, val = pcall(C_CVar.GetCVar, name)
    return ok and val or nil
end

--- Read a CVar as a boolean. Returns true/false or nil on failure.
function AO:GetCVarBool(name)
    local ok, val = pcall(C_CVar.GetCVarBool, name)
    return ok and val or nil
end

--- Read the default value for a CVar. Returns string or nil.
function AO:GetCVarDefault(name)
    local ok, val = pcall(C_CVar.GetCVarDefault, name)
    return ok and val or nil
end

--- Full CVar info. Returns (value, default, serverStored, lockedByGx) or nils.
function AO:GetCVarInfo(name)
    local ok, val, def, server, locked = pcall(C_CVar.GetCVarInfo, name)
    if ok then return val, def, server, locked end
    return nil, nil, nil, nil
end

--- Set a CVar. Combat-defers if needed. Returns true on immediate success.
function AO:SetCVar(name, value)
    if InCombatLockdown() then
        VUI.CombatQueue.Add(function()
            local ok, err = pcall(C_CVar.SetCVar, name, value)
            if not ok then
                VUI.Print("Advanced Options",
                    format("|cFFFF4444Failed to set %s:|r %s", name, tostring(err)))
            end
        end)
        VUI.Print("Advanced Options",
            format("|cFFFFFF00%s|r will be set after combat.", name))
        return false
    end
    local ok, err = pcall(C_CVar.SetCVar, name, value)
    if not ok then
        VUI.Print("Advanced Options",
            format("|cFFFF4444Failed to set %s:|r %s", name, tostring(err)))
        return false
    end
    return true
end

--- Reset a CVar to its default value.
function AO:ResetCVar(name)
    local def = self:GetCVarDefault(name)
    if def ~= nil then
        return self:SetCVar(name, def)
    end
    return false
end

----------------------------------------------------------------
--  Favourites helpers (Browser tab)
----------------------------------------------------------------
function AO:IsFavorite(cvarName)
    return db and db.favorites[cvarName] or false
end

function AO:ToggleFavorite(cvarName)
    if not db then return end
    if db.favorites[cvarName] then
        db.favorites[cvarName] = nil
    else
        db.favorites[cvarName] = true
    end
end

----------------------------------------------------------------
--  Collapse state helpers (Featured tab)
----------------------------------------------------------------
function AO:IsCollapsed(categoryKey)
    return db and db.collapsed[categoryKey] or false
end

function AO:ToggleCollapsed(categoryKey)
    if not db then return end
    db.collapsed[categoryKey] = not db.collapsed[categoryKey]
end

----------------------------------------------------------------
--  Event Handler
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        AO:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        VUI.Print("Advanced Options",
            format("v%s loaded — |cFFFFFF00/ao|r to open.", AO.VERSION))
        ef:UnregisterEvent("PLAYER_LOGIN")
    end
end)

----------------------------------------------------------------
--  Slash Commands
----------------------------------------------------------------
SLASH_VERITASUI_AO1 = "/ao"
SLASH_VERITASUI_AO2 = "/advancedoptions"

SlashCmdList["VERITASUI_AO"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "settings" then
        if AO.settingsCategoryID then
            Settings.OpenToCategory(AO.settingsCategoryID)
        end

    elseif cmd == "help" then
        VUI.Print("Advanced Options", "Commands:")
        print("  |cFFFFFF00/ao|r           — toggle window")
        print("  |cFFFFFF00/ao settings|r  — open settings panel")

    else
        -- Default: toggle main window
        if AO.MainWindow then
            if AO.MainWindow:IsShown() then
                VUI.CloseManagedPanel(AO.MainWindow)
            else
                AO:ShowWindow()
            end
        else
            VUI.Print("Advanced Options",
                "|cFFFF4444Window failed to load. Try /reload|r")
        end
    end
end

--- Open the main window to the last-used tab.
function AO:ShowWindow()
    if not self.MainWindow then return end
    local tab = (db and db.lastTab == 2) and "browser" or "featured"
    self.MainWindow:ShowTab(tab)
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_AdvancedOptions_OnAddonCompartmentClick()
    C_Timer.After(0, function() SlashCmdList["VERITASUI_AO"]("") end)
end
