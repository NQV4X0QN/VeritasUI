-- VeritasUI_AuctionHouse / Core.lua
-- Module init, saved variables, internal event bus, AH session lifecycle,
-- slash commands.
--
-- Owns the AH session lifecycle (AUCTION_HOUSE_SHOW/CLOSED/DISABLED), a tiny
-- internal pub/sub bus (AH.Events) that sibling files hook, the price-DB saved
-- vars, and the /ah slash surface (help / scan / wipe / diag / blocked /
-- settings). See AUCTIONHOUSE_DESIGN.md §2.8 (lifecycle).

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
local floor       = math.floor
local strtrim     = strtrim
local CreateFrame = CreateFrame

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
--  AH module owns its own. Defined FIRST so sibling files (Replicate.lua, etc.)
--  can subscribe at their own file-load time.
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
--  Account-wide saved var. The price database lives under db.prices; the
--  container shape below is stable and seeded on first run so every reader has
--  a predictable structure to work against.
----------------------------------------------------------------
local defaults = {
    dbVersion = 1,     -- schema version for the price DB (bump on layout change)
    prices    = {},    -- [itemKeyString] = price-history record (see Database.lua)
    settings  = {},    -- user toggles (tooltip display); settings.retentionDays optional
    lastScan  = 0,     -- Unix time of last full replicate scan (scan-floor bookkeeping)
    -- Sell strip: itemIDs the user has hidden from the native-Sell-tab bag strip
    -- (dyes, saved reagents, etc.). [itemID] = true. See UI/SellStrip.lua.
    sellBlocklist = {},
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
    -- Shopping tab removed: drop its now-orphaned persistence container if present.
    db.shopping = nil
    -- Auto-scan removed (2026-07-02): drop the orphaned settings toggle if present.
    if db.settings then db.settings.autoScan = nil end
    AH.db = db
end

----------------------------------------------------------------
--  Session lifecycle  (design §2.8)
--
--  AUCTION_HOUSE_SHOW    → AH open; queries allowed. Fire "AH_OPEN".
--  AUCTION_HOUSE_CLOSED  → tear down; abort any in-flight scan. Fire "AH_CLOSED".
--  AUCTION_HOUSE_DISABLED→ AH unavailable this session (e.g. another AH addon
--                          or a server gate). Degrade gracefully. Fire "AH_DISABLED".
--
--  Core only owns the state + the event broadcast. Replicate.lua subscribes to
--  "AH_CLOSED" to abort an in-flight scan.
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
            format("v%s loaded — |cFFFFFF00/ah|r", AH.VERSION))
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
--  Scan reporting
--
--  Replicate.lua fires these on the AH.Events bus; Core owns the user-facing
--  chat output so the scanner stays UI-agnostic.
----------------------------------------------------------------
AH.Events.On("AH_SCAN_START", function()
    -- Auto-scan removed (2026-07-02): all scans are user-initiated, one wording.
    VUI.Print(AH.TAG, "Full scan started…")
end)

AH.Events.On("AH_SCAN_COMPLETE", function(committed, rows)
    VUI.Print(AH.TAG, format(
        "Scan complete — |cFF00FF00%d|r items priced from |cFFFFFF00%d|r auctions.",
        committed or 0, rows or 0))
end)

AH.Events.On("AH_SCAN_FAILED", function(err)
    -- User-facing wording is fixed and cause-neutral: it failed and prices are
    -- not fresh. Any underlying error string (e.g. a coroutine error) is only
    -- surfaced under VUI.debug — we never assert a root cause to the user.
    VUI.Print(AH.TAG, "|cFFFF4444Scan failed —|r Prices were not updated; try again shortly.")
    if VUI.debug and err and err ~= "" then
        VUI.Print(AH.TAG, "|cFF888888[debug] scan-fail detail: " .. tostring(err) .. "|r")
    end
end)

----------------------------------------------------------------
--  Slash Commands
--
--  Surface: help / scan / wipe / diag / blocked / settings.
----------------------------------------------------------------
SLASH_VERITASUI_AH1 = "/ah"
SLASH_VERITASUI_AH2 = "/auctionhouse"

local function PrintHelp()
    VUI.Print(AH.TAG, "Commands:")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah|r              — show this help")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah scan|r         — full price scan (AH open; 15-min cooldown)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah diag|r         — diagnostic / state dump")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah check|r        — show stored price for a shift-clicked item")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah wipe|r         — clear the price database")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah blocked|r      — manage sell-strip hidden items")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah settings|r     — open settings panel")
end

local function PrintDiag()
    VUI.Print(AH.TAG, "Diagnostics:")
    VUI.Print(AH.TAG, format("  version:      |cFFFFFF00%s|r", tostring(AH.VERSION)))
    VUI.Print(AH.TAG, format("  db ready:     %s", AH.db and "|cFF00FF00yes|r" or "|cFFFF4444no|r"))
    if AH.db then
        local n = AH.DB and AH.DB.GetItemCount() or 0
        VUI.Print(AH.TAG, format("  db schema:    v%s", tostring(AH.db.dbVersion)))
        VUI.Print(AH.TAG, format("  priced items: |cFFFFFF00%d|r", n))
    end

    -- Session state.
    VUI.Print(AH.TAG, format("  AH open:      %s", AH.isOpen and "|cFF00FF00yes|r" or "no"))
    VUI.Print(AH.TAG, format("  AH disabled:  %s", AH.disabled and "|cFFFF4444yes|r" or "no"))

    -- Scan state.
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
        VUI.Print(AH.TAG, format("  scan:         %s", readyText))
    end

    -- Money helper self-test (verifies coin formatting without needing the AH).
    if AH.Money then
        VUI.Print(AH.TAG, format("  money fmt:    %s", AH.Money.Format(123456)))
    end
end

----------------------------------------------------------------
--  /ah check <item link>  — DIAGNOSTIC
--
--  Dump the stored price record for a shift-clicked item, so we can see whether
--  a scan actually updated it. Compare before/after a scan: if `seen`/`market`
--  don't change across a successful scan, that item's row is being skipped
--  (leading hypothesis: cold item-data cache → GetReplicateItemLink nil → row
--  dropped; see design §2.2). Also prints the derived key so a key mismatch
--  between the scanned link and the tooltip link would be visible.
----------------------------------------------------------------
local function PrintCheck(rawArg)
    if not AH.DB then
        VUI.Print(AH.TAG, "DB not loaded.")
        return
    end
    -- Pull the first hyperlink out of the raw (original-case) argument.
    local link = rawArg and rawArg:match("|H.-|h.-|h")
    if not link then
        VUI.Print(AH.TAG, "Usage: |cFFFFFF00/ah check|r then shift-click an item link.")
        return
    end

    local key = AH.DB.MakeKey(link)
    VUI.Print(AH.TAG, "Check: " .. link)
    VUI.Print(AH.TAG, format("  derived key:  |cFFFFFF00%s|r", tostring(key)))
    if not key then
        VUI.Print(AH.TAG, "  |cFFFF4444MakeKey returned nil|r — this link can't be priced.")
        return
    end

    local price = AH.DB.GetMarketPrice(key)
    local age   = AH.DB.GetPriceAge(key)
    local today = AH.DB.Today()
    VUI.Print(AH.TAG, format("  stored price: %s",
        price and AH.Money.Format(price) or "|cFFFF4444(none — never recorded)|r"))
    VUI.Print(AH.TAG, format("  age:          %s",
        age and (age .. " day(s)") or "|cFFFF4444n/a|r"))
    VUI.Print(AH.TAG, format("  today / seen: %d / %s",
        today, age and tostring(today - age) or "—"))

    local hist = AH.DB.GetPriceHistory(key)
    if hist[1] then
        VUI.Print(AH.TAG, format("  latest day:   day %d — min %s, qty %d",
            hist[1].day, AH.Money.Format(hist[1].min or 0), hist[1].qty or 0))
    else
        VUI.Print(AH.TAG, "  history:      |cFFFF4444empty|r")
    end
end

SlashCmdList["VERITASUI_AH"] = function(msg)
    msg = strtrim(msg or "")
    -- Split into command word + remainder. `rest` is lowercased for case-insensitive
    -- subcommand args ("clear"); `rawRest` preserves ORIGINAL case for args that
    -- must not be mangled — notably item links (/ah check), whose hyperlink data
    -- and item name are case-sensitive.
    local word, rawRest = msg:match("^(%S*)%s*(.-)$")
    local cmd  = (word or ""):lower()
    rawRest = rawRest or ""
    local rest = rawRest:lower()

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
        local ok, reason = AH.Replicate.Start()
        if not ok then
            VUI.Print(AH.TAG, reason or "Scan could not start.")
        end

    elseif cmd == "wipe" then
        if AH.DB then
            AH.DB.Wipe()
            VUI.Print(AH.TAG, "Price database cleared.")
        end

    elseif cmd == "diag" then
        PrintDiag()

    elseif cmd == "check" then
        PrintCheck(rawRest)

    elseif cmd == "blocked" then
        if AH.SellStrip then
            if rest == "clear" then
                AH.SellStrip.ClearBlocked()
            else
                AH.SellStrip.ListBlocked()
            end
        end

    else
        -- Default + explicit "help": print the command list.
        PrintHelp()
    end
end
