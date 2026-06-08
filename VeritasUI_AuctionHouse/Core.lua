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
local floor       = math.floor
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
    settings  = {},    -- user toggles (Phase 3+); settings.retentionDays optional
    lastScan  = 0,     -- Unix time of last full replicate scan (Phase 2 scan-floor)
    -- Phase 4 Layer 3: Shopping tab persistence (UI feature, NOT price-DB layout —
    -- so this does NOT bump dbVersion, which gates the prices schema specifically).
    --   lists  = array of { name = "...", items = { "term", ... } }
    --   recent = newest-first array of search-term strings (capped in Shopping.lua)
    shopping  = { lists = {}, recent = {} },
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
--  Scan reporting (Phase 2)
--
--  Replicate.lua fires these on the AH.Events bus; Core owns the user-facing
--  chat output so the scanner stays UI-agnostic.
----------------------------------------------------------------
AH.Events.On("AH_SCAN_START", function()
    VUI.Print(AH.TAG, "Full scan started…")
end)

AH.Events.On("AH_SCAN_COMPLETE", function(committed, rows)
    VUI.Print(AH.TAG, format(
        "Scan complete — |cFF00FF00%d|r items priced from |cFFFFFF00%d|r auctions.",
        committed or 0, rows or 0))
end)

AH.Events.On("AH_SCAN_FAILED", function(err)
    VUI.Print(AH.TAG, "|cFFFF4444Scan failed:|r " .. tostring(err))
end)

----------------------------------------------------------------
--  Slash Commands
--
--  Phase 2 surface: help / diag / scan / wipe / throttletest / settings.
--  Feature subcommands are added by the phase that implements them.
----------------------------------------------------------------
SLASH_VERITASUI_AH1 = "/ah"
SLASH_VERITASUI_AH2 = "/auctionhouse"

local function PrintHelp()
    VUI.Print(AH.TAG, "Commands:")
    print("  |cFFFFFF00/ah|r              — show this help")
    print("  |cFFFFFF00/ah scan|r         — full price scan (AH open; 15-min cooldown)")
    print("  |cFFFFFF00/ah scan force|r   — scan now, ignoring the cooldown")
    print("  |cFFFFFF00/ah search <text>|r — test browse query (AH open; prints results)")
    print("  |cFFFFFF00/ah diag|r         — diagnostic / state dump")
    print("  |cFFFFFF00/ah wipe|r         — clear the price database")
    print("  |cFFFFFF00/ah throttletest|r — enqueue a no-op AH send (AH must be open)")
    print("  |cFFFFFF00/ah settings|r     — open settings panel")
end

-- Phase 4 diagnostic: run a browse query through AH.Search and print the first
-- handful of results, so the query layer is verifiable before the UI exists.
local function SearchTest(term)
    if not AH.Search then
        VUI.Print(AH.TAG, "Search layer not loaded.")
        return
    end
    if term == "" then
        VUI.Print(AH.TAG, "Usage: |cFFFFFF00/ah search <text>|r")
        return
    end

    -- One-shot listeners scoped to this test (the bus has no unsubscribe; we gate on
    -- a local 'done' flag so stale fires after completion are ignored).
    local done = false
    VUI.Print(AH.TAG, format("Searching for |cFFFFFF00%s|r ...", term))

    AH.Events.On("AH_BROWSE_UPDATE", function(results, full)
        if done then return end
        local n = #results
        if not full then
            print(format("  ... %d so far (paging)", n))
            return
        end
        done = true
        VUI.Print(AH.TAG, format("Browse complete — |cFF00FF00%d|r distinct items:", n))
        for i = 1, math.min(n, 10) do
            local r = results[i]
            local info = AH.Search.GetKeyInfo(r.itemKey)
            local name = (info and info.itemName) or ("itemID " .. tostring(r.itemID))
            local price = AH.Money and AH.Money.Format(r.minPrice) or tostring(r.minPrice)
            print(format("  %2d. %s  |cFFFFFFFF%s|r  x%d", i, name, price, r.totalQuantity))
        end
        if n > 10 then print(format("  ... and %d more", n - 10)) end
    end)

    AH.Events.On("AH_BROWSE_FAILED", function()
        if done then return end
        done = true
        VUI.Print(AH.TAG, "|cFFFF4444Browse failed|r (server error).")
    end)

    AH.Search.Browse(term)
end

local function PrintDiag()
    VUI.Print(AH.TAG, "Diagnostics:")
    print(format("  version:      |cFFFFFF00%s|r", tostring(AH.VERSION)))
    print(format("  db ready:     %s", AH.db and "|cFF00FF00yes|r" or "|cFFFF4444no|r"))
    if AH.db then
        local n = AH.DB and AH.DB.GetItemCount() or 0
        print(format("  db schema:    v%s", tostring(AH.db.dbVersion)))
        print(format("  priced items: |cFFFFFF00%d|r", n))
    end

    -- Session state.
    print(format("  AH open:      %s", AH.isOpen and "|cFF00FF00yes|r" or "no"))
    print(format("  AH disabled:  %s", AH.disabled and "|cFFFF4444yes|r" or "no"))

    -- Scan state (Phase 2).
    if AH.Replicate then
        local wait = AH.Replicate.SecondsUntilReady()
        local readyText
        if AH.Replicate.IsScanning() then
            readyText = format("|cFFFFFF00scanning %d%%|r", floor(AH.Replicate.Progress() * 100))
        elseif wait > 0 then
            readyText = format("cooldown %d:%02d", floor(wait / 60), wait % 60)
        else
            readyText = "|cFF00FF00ready|r"
        end
        print(format("  scan:         %s", readyText))
    end

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
    msg = strtrim(msg or "")
    -- ORIGINAL case preserved — item names in /ah search are case-sensitive to read).
    local word, rest = msg:match("^(%S*)%s*(.-)$")
    local cmd = (word or ""):lower()

    if cmd == "settings" then
        if AH.settingsCategoryID then
            Settings.OpenToCategory(AH.settingsCategoryID)
        else
            VUI.Print(AH.TAG, "Settings are still loading — try again in a moment.")
        end

    elseif cmd == "scan" then
        if not AH.Replicate then
            VUI.Print(AH.TAG, "Scanner not loaded.")
            return
        end
        local force = (rest:lower() == "force")
        local ok, reason = AH.Replicate.Start(force)
        if not ok then
            VUI.Print(AH.TAG, reason or "Scan could not start.")
        end

    elseif cmd == "search" then
        SearchTest(rest)

    elseif cmd == "wipe" then
        if AH.DB then
            AH.DB.Wipe()
            VUI.Print(AH.TAG, "Price database cleared.")
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
