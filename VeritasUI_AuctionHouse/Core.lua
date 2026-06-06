-- VeritasUI_AuctionHouse / Core.lua
-- Module init, saved variables, internal event bus, AH session lifecycle,
-- slash commands.
--
-- PHASE 1: adds the AH session lifecycle (AUCTION_HOUSE_SHOW/CLOSED/DISABLED),
-- a tiny internal pub/sub bus (AH.Events) that later phases hook, and /ah
-- diagnostics for the throttle queue + money helpers. Still no user-facing
-- feature — this is foundation (per AUCTIONHOUSE_DESIGN.md §2.7/2.8, Phase 1).

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
local ipairs      = ipairs
local type        = type
local format      = string.format
local strtrim     = strtrim
local CreateFrame = CreateFrame
local C_AuctionHouse = C_AuctionHouse

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
AH.VERSION = VUI.VERSION
AH.TAG     = "Auction House"   -- chat prefix for VUI.Print

----------------------------------------------------------------
--  Internal event bus  (AH.Events)
--
--  A minimal in-module pub/sub. VeritasUI_Lib has no EventBus, and a change in
--  one module must never require edits in another (suite design rule #4), so the
--  AH module owns its own. Defined FIRST so sibling files (Throttle.lua, and
--  later Replicate/Search/etc.) can subscribe at their own file-load time.
--
--    AH.Events.On(name, fn)   -- subscribe; fn(...) receives Fire's varargs
--    AH.Events.Fire(name, ...) -- publish to all subscribers (pcall-isolated)
----------------------------------------------------------------
AH.Events = {}
local listeners = {}   -- [eventName] = { fn, fn, ... }

function AH.Events.On(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then return end
    local list = listeners[name]
    if not list then
        list = {}
        listeners[name] = list
    end
    list[#list + 1] = fn
end

function AH.Events.Fire(name, ...)
    local list = listeners[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and VUI.debug then
            VUI.Print(AH.TAG, format("|cFFFF4444Event handler error|r (%s): %s",
                tostring(name), tostring(err)))
        end
    end
end

----------------------------------------------------------------
--  Session state
----------------------------------------------------------------
AH.isOpen   = false   -- true between AUCTION_HOUSE_SHOW and AUCTION_HOUSE_CLOSED
AH.disabled = false   -- true after AUCTION_HOUSE_DISABLED (this session)

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
--  Session lifecycle  (design §2.8)
--
--  AUCTION_HOUSE_SHOW    → AH open; queries allowed. Fire "AH_OPEN".
--  AUCTION_HOUSE_CLOSED  → tear down; cancel in-flight queue. Fire "AH_CLOSED".
--  AUCTION_HOUSE_DISABLED→ AH unavailable this session (e.g. another AH addon
--                          or a server gate). Degrade gracefully. Fire "AH_DISABLED".
--
--  Core only owns the state + the event broadcast. Throttle.lua subscribes to
--  "AH_CLOSED" to clear its queue; later phases subscribe to "AH_OPEN" to scan.
----------------------------------------------------------------
local function OnAuctionHouseShow()
    AH.isOpen = true
    if VUI.debug then VUI.Print(AH.TAG, "AH opened.") end
    AH.Events.Fire("AH_OPEN")
end

local function OnAuctionHouseClosed()
    AH.isOpen = false
    if VUI.debug then VUI.Print(AH.TAG, "AH closed.") end
    AH.Events.Fire("AH_CLOSED")
end

local function OnAuctionHouseDisabled()
    AH.disabled = true
    AH.isOpen = false
    VUI.Print(AH.TAG, "|cFFFFFF00Auction House is disabled this session|r — "
        .. "cached prices still work; live queries do not.")
    AH.Events.Fire("AH_DISABLED")
end

----------------------------------------------------------------
--  Event Handler
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("AUCTION_HOUSE_SHOW")
ef:RegisterEvent("AUCTION_HOUSE_CLOSED")
ef:RegisterEvent("AUCTION_HOUSE_DISABLED")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        AH:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        VUI.Print(AH.TAG,
            format("v%s loaded — |cFFFFFF00/ah|r for commands.", AH.VERSION))
        ef:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "AUCTION_HOUSE_SHOW" then
        OnAuctionHouseShow()

    elseif event == "AUCTION_HOUSE_CLOSED" then
        OnAuctionHouseClosed()

    elseif event == "AUCTION_HOUSE_DISABLED" then
        OnAuctionHouseDisabled()
    end
end)

----------------------------------------------------------------
--  Slash Commands
--
--  Phase 1 surface: help / diag / settings / throttletest.
--  Feature subcommands (scan, etc.) are added by the phase that
--  implements them.
----------------------------------------------------------------
SLASH_VERITASUI_AH1 = "/ah"
SLASH_VERITASUI_AH2 = "/auctionhouse"

local function PrintHelp()
    VUI.Print(AH.TAG, "Commands:")
    print("  |cFFFFFF00/ah|r              — show this help")
    print("  |cFFFFFF00/ah diag|r         — diagnostic / state dump")
    print("  |cFFFFFF00/ah throttletest|r — enqueue a no-op AH send (AH must be open)")
    print("  |cFFFFFF00/ah settings|r     — open settings panel")
end

local function PrintDiag()
    VUI.Print(AH.TAG, "Diagnostics:")
    print(format("  version:      |cFFFFFF00%s|r", tostring(AH.VERSION)))
    print(format("  db ready:     %s", AH.db and "|cFF00FF00yes|r" or "|cFFFF4444no|r"))
    if AH.db then
        local n = 0
        for _ in pairs(AH.db.prices) do n = n + 1 end
        print(format("  db schema:    v%s", tostring(AH.db.dbVersion)))
        print(format("  priced items: %d", n))
    end

    -- Session state.
    print(format("  AH open:      %s", AH.isOpen and "|cFF00FF00yes|r" or "no"))
    print(format("  AH disabled:  %s", AH.disabled and "|cFFFF4444yes|r" or "no"))

    -- Throttle state.
    if AH.Throttle then
        local ready = false
        if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
            local ok, r = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
            ready = ok and r or false
        end
        print(format("  throttle:     ready=%s  awaiting=%s  pending=%d",
            ready and "|cFF00FF00yes|r" or "no",
            AH.Throttle.IsAwaiting() and "yes" or "no",
            AH.Throttle.PendingCount()))
    end

    -- Money helper self-test (verifies format + sanitize without needing the AH).
    if AH.Money then
        print(format("  money fmt:    %s  |  sanitize(12345.6)=%d",
            AH.Money.Format(123456), AH.Money.SanitizePrice(12345.6)))
    end
end

-- Phase 1 DoD: verify the throttle queue with a throwaway no-op send. Requires
-- the AH to be open (IsThrottledMessageSystemReady is only meaningful then).
local function ThrottleTest()
    if not AH.isOpen then
        VUI.Print(AH.TAG, "Open the Auction House first, then run |cFFFFFF00/ah throttletest|r.")
        return
    end
    VUI.Print(AH.TAG, format("Enqueuing no-op send (pending before: %d)...",
        AH.Throttle.PendingCount()))
    AH.Throttle.Enqueue(function()
        VUI.Print(AH.TAG, "|cFF00FF00Throttle dispatch fired|r — queue is working.")
    end, "throttletest")
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

    elseif cmd == "throttletest" then
        ThrottleTest()

    else
        -- Default + explicit "help": print the command list.
        PrintHelp()
    end
end
