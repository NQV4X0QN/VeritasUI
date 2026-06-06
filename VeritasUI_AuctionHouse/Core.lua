-- VeritasUI_AuctionHouse / Core.lua
-- Module init, saved variables, slash commands.
--
-- PHASE 0 (scaffolding): the module loads, seeds its saved-vars, registers
-- /ah with help/diag/settings stubs, and prints a load line. No AH features
-- yet — those land in later phases per AUCTIONHOUSE_DESIGN.md.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local pairs       = pairs
local type        = type
local format      = string.format
local strtrim     = strtrim
local CreateFrame = CreateFrame

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
AH.VERSION = VUI.VERSION
AH.TAG     = "Auction House"   -- chat prefix for VUI.Print

----------------------------------------------------------------
--  Defaults & state
--
--  Account-wide saved var. The price database (Phase 2) lives under
--  db.prices; we seed the container now so later phases have a stable
--  shape to write into. UI/feature toggles get added as phases land.
----------------------------------------------------------------
local defaults = {
    dbVersion = 1,     -- schema version for the price DB (bump on layout change)
    prices    = {},    -- [itemKeyString] = price-history record (Phase 2)
    settings  = {},    -- user toggles (Phase 3+)
}

local db

-- Recursive deep copy so nested table defaults never share references with
-- the defaults table. Same pattern as CleanSolo/ZoneQuests (see SKILL.md
-- Known Landmines: shallow-copy aliasing trap).
local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return c
end

function AH:InitDB()
    VeritasUI_AuctionHouseDB = VeritasUI_AuctionHouseDB or {}
    db = VeritasUI_AuctionHouseDB
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = (type(v) == "table") and DeepCopy(v) or v
        end
    end
    AH.db = db
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
        AH:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        VUI.Print(AH.TAG,
            format("v%s loaded — |cFFFFFF00/ah|r for commands.", AH.VERSION))
        ef:UnregisterEvent("PLAYER_LOGIN")
    end
end)

----------------------------------------------------------------
--  Slash Commands
--
--  Phase 0 surface: help / diag / settings. Feature subcommands
--  (scan, etc.) are added by the phase that implements them.
----------------------------------------------------------------
SLASH_VERITASUI_AH1 = "/ah"
SLASH_VERITASUI_AH2 = "/auctionhouse"

local function PrintHelp()
    VUI.Print(AH.TAG, "Commands:")
    print("  |cFFFFFF00/ah|r           — show this help")
    print("  |cFFFFFF00/ah diag|r      — diagnostic / state dump")
    print("  |cFFFFFF00/ah settings|r  — open settings panel")
end

local function PrintDiag()
    VUI.Print(AH.TAG, "Diagnostics:")
    print(format("  version:    |cFFFFFF00%s|r", tostring(AH.VERSION)))
    print(format("  db ready:   %s", AH.db and "|cFF00FF00yes|r" or "|cFFFF4444no|r"))
    if AH.db then
        local n = 0
        for _ in pairs(AH.db.prices) do n = n + 1 end
        print(format("  db schema:  v%s", tostring(AH.db.dbVersion)))
        print(format("  priced items: %d", n))
    end
    -- AH open-state probe — harmless read, useful baseline for later phases.
    local ahOpen = (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady ~= nil)
                   and (AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()) or false
    print(format("  AH open:    %s", ahOpen and "|cFF00FF00yes|r" or "no"))
end

SlashCmdList["VERITASUI_AH"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "settings" then
        if AH.settingsCategoryID then
            Settings.OpenToCategory(AH.settingsCategoryID)
        else
            VUI.Print(AH.TAG, "Settings are still loading — try again in a moment.")
        end

    elseif cmd == "diag" then
        PrintDiag()

    else
        -- Default + explicit "help": print the command list.
        PrintHelp()
    end
end
