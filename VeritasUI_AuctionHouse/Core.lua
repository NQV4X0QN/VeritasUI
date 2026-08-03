-- VeritasUI_AuctionHouse / Core.lua
-- Module init, saved variables, internal event bus, AH session lifecycle,
-- slash commands.
--
-- Owns the AH session lifecycle (AUCTION_HOUSE_SHOW/CLOSED/DISABLED), a tiny
-- internal pub/sub bus (AH.Events) that sibling files hook, the price-DB saved
-- vars, and the /ah slash surface (help / scan / diag / check / find / wipe /
-- blocked / settings / debug). See AUCTIONHOUSE_DESIGN.md §2.8 (lifecycle).

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
    -- Schema version, reported by /ah diag. Diagnostic only: InitDB seeds keys
    -- solely when absent, so an existing saved-variables file keeps its stored
    -- value forever and bumping this number would not upgrade anything. Schema
    -- changes are made as unconditional tombstone assignments below (see
    -- db.shopping and db.settings.autoScan), which are version-independent and
    -- need no comparison. Do not treat this as a migration trigger without
    -- first adding the comparison it would require.
    dbVersion = 1,
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

-- Coin formatter shared by /ah check and /ah compare.
--
-- ⚠ Declared HERE, above its first consumer. It previously sat further down, next to
-- /ah check, and adding /ah compare above it silently turned every reference in the
-- reporter into a nil GLOBAL lookup -- Lua binds a bare identifier at closure-creation
-- time, so a `local function` declared below a closure that calls it is not visible to
-- it. That is the same trap that broke /way (v1.6.33) and it fails at RUN time, not
-- load time. Keep this above every caller.
--
-- /ah check and /ah compare both run when something is already wrong, so neither may
-- error if a sibling module failed to load. The TOC loads Core.lua BEFORE Money.lua, so
-- unlike Tooltip.lua this file has no load-order guarantee to lean on. Falling back to
-- raw copper keeps the report readable; folding the nil case into the "never recorded"
-- string would report a missing module as a missing price.
local function MoneyStr(copper)
    return AH.Money and AH.Money.Format(copper) or tostring(copper)
end

----------------------------------------------------------------
--  /ah compare reporter (v1.12.9)
--
--  Diffs a dry-run BROWSE aggregate against the stored price database. On a database
--  built by replicate scans that is a direct engine-vs-engine comparison, and it exists
--  to answer ONE question with data instead of inference: is browse's minPrice
--  buyout-only, or does it include BIDS? Replicate deliberately skips bid-only
--  auctions, so if browse were pricing bids it would read systematically LOWER.
--
--  Auctionator reading `bidAmount` as a separate field suggests minPrice is buyout, but
--  that is a naming pattern, not a measurement — the same class of reasoning this
--  project has already been burned by. Hence this.
--
--  Reports coverage both ways too, because "browse missed items replicate had" would be
--  a disqualifying finding on its own.
----------------------------------------------------------------
-- Gear keys carry an item level ("i:<id>:<ilvl>"); commodities do not ("i:<id>"); pets
-- are "p:<species>". The split matters: replicate can only key gear via a loaded link,
-- so gear is exactly the population its retry budget abandons — which means a
-- discrepancy concentrated in gear supports "stored gear is stale", while one spread
-- evenly across commodities would point at browse pricing something different.
local function KeyClass(key)
    if key:byte(1) == 112 then return "pet" end            -- "p:"
    return key:find(":%d+:%d+$") and "gear" or "commodity"
end

local function Median(t)
    if #t == 0 then return 0 end
    table.sort(t)
    local mid = floor(#t / 2)
    if #t % 2 == 1 then return t[mid + 1] end
    return (t[mid] + t[mid + 1]) / 2
end

local function ReportComparison()
    local browse = AH.Browse and AH.Browse.TakeDryResult()
    if not browse then
        VUI.Print(AH.TAG, "Comparison produced no data.")
        return
    end

    -- Per-class tallies, so the gear-staleness explanation is tested rather than told.
    local cls = {}
    local function C(k)
        cls[k] = cls[k] or { both = 0, lower = 0, higher = 0, same = 0,
                             browseOnly = 0, ratios = {} }
        return cls[k]
    end

    for key, a in pairs(browse) do
        local c = C(KeyClass(key))
        local stored = AH.DB and AH.DB.GetMarketPrice(key)
        if stored and stored > 0 then
            c.both = c.both + 1
            c.ratios[#c.ratios + 1] = a.unit / stored
            if a.unit < stored then c.lower = c.lower + 1
            elseif a.unit > stored then c.higher = c.higher + 1
            else c.same = c.same + 1 end
        else
            c.browseOnly = c.browseOnly + 1
        end
    end

    -- Coverage the other way. ⚠ Split by FRESHNESS: the price store keeps 14 days, so a
    -- stored key browse did not return is usually just an expired listing, not a browse
    -- gap. Only a key the MOST RECENT scan touched (age 0) is a real gap — conflating
    -- the two is what made the first run's "browse missed 6028" uninterpretable.
    local gapToday, staleOnly = 0, 0
    local gapExamples = {}
    if AH.db and AH.db.prices then
        for key in pairs(AH.db.prices) do
            if not browse[key] then
                local age = AH.DB.GetPriceAge(key)
                if age == 0 then
                    gapToday = gapToday + 1
                    if #gapExamples < 5 then gapExamples[#gapExamples + 1] = key end
                else
                    staleOnly = staleOnly + 1
                end
            end
        end
    end

    VUI.Print(AH.TAG, "Engine comparison (browse vs stored):")
    for _, name in ipairs({ "commodity", "gear", "pet" }) do
        local c = cls[name]
        if c and (c.both > 0 or c.browseOnly > 0) then
            VUI.Print(AH.TAG, format("  %-9s in both %d  identical %d (%.1f%%)  lower %d  higher %d  browse-only %d",
                name, c.both, c.same,
                c.both > 0 and (c.same / c.both * 100) or 0,
                c.lower, c.higher, c.browseOnly))
            if c.both > 0 then
                -- MEDIAN, not mean. A mean of ratios is outlier-dominated: one item
                -- stored at 1c and browsed at 100g contributes a ratio of 10,000,000.
                -- The first run reported a mean of 26.9 alongside 89.7% IDENTICAL
                -- prices, which is arithmetically consistent and completely useless.
                VUI.Print(AH.TAG, format("            median ratio %.3f  (1.000 = agreement)",
                    Median(c.ratios)))
            end
        end
    end
    VUI.Print(AH.TAG, format("  stored but not returned by browse: |cFFFFFF00%d from the latest scan|r "
        .. "(real gap) + %d older (expired listings, expected)", gapToday, staleOnly))
    if #gapExamples > 0 then
        VUI.Print(AH.TAG, "    real-gap examples: " .. table.concat(gapExamples, ", "))
    end
    VUI.Print(AH.TAG, "  |cFFFFFF00Reading:|r commodities should be near-identical — both engines take "
        .. "the min of the same listings. Gear mismatches are EXPECTED while replicate is "
        .. "the engine, because its retry budget abandons gear rows so stored gear is old. "
        .. "A real problem would be commodities disagreeing, or a nonzero real gap.")
end

AH.Events.On("AH_SCAN_COMPLETE", function()
    if AH.comparePending then
        AH.comparePending = false
        ReportComparison()
    end
end)
AH.Events.On("AH_SCAN_FAILED", function()
    if AH.comparePending then
        AH.comparePending = false
        VUI.Print(AH.TAG, "Comparison aborted — the browse scan did not complete.")
    end
end)

----------------------------------------------------------------
--  Scan engine facade (v1.12.9)
--
--  There are now TWO whole-AH scan engines:
--    Replicate.lua — C_AuctionHouse.ReplicateItems(). Per-auction rows. The original,
--                    and the one that fails the first scan of most days.
--    Browse.lua    — an empty SendBrowseQuery + pagination. Per-item summaries.
--                    Measured working at the exact moment replicate was dead.
--
--  Both expose the same four functions, so this facade dispatches on the scanEngine
--  setting and every caller stays engine-agnostic. That matters most for
--  UI/ScanButton.lua, whose header states it is a pure VIEW over a PUBLIC scan api and
--  must not reach into internals — pointing it here keeps that true while making the
--  engine swappable.
--
--  Dispatch is at CALL time, not load time: Core.lua loads before both engines.
----------------------------------------------------------------
AH.Scan = {}

-- "browse" only when explicitly selected; anything else (including a nil setting on a
-- database that predates it) means replicate. Fail-safe toward the engine whose
-- behaviour is fully characterised.
local function Engine()
    local which = AH.Setting and AH.Setting("scanEngine") or "replicate"
    if which == "browse" and AH.Browse then return AH.Browse end
    return AH.Replicate
end
AH.Scan.Engine = Engine

function AH.Scan.EngineName()
    return (Engine() == AH.Browse) and "browse" or "replicate"
end

function AH.Scan.Start(...)
    local e = Engine()
    if not (e and e.Start) then return false, "No scan engine loaded." end
    return e.Start(...)
end
-- Back-compat alias: ScanButton historically called StartManual().
AH.Scan.StartManual = AH.Scan.Start

function AH.Scan.IsScanning()
    -- Report EITHER engine as busy, not just the selected one. Switching the setting
    -- mid-scan must not make a running scan invisible to the button and the bar.
    local r = AH.Replicate and AH.Replicate.IsScanning and AH.Replicate.IsScanning()
    local b = AH.Browse    and AH.Browse.IsScanning    and AH.Browse.IsScanning()
    return (r or b) and true or false
end

function AH.Scan.Progress()
    if AH.Replicate and AH.Replicate.IsScanning and AH.Replicate.IsScanning() then
        return AH.Replicate.Progress()
    end
    if AH.Browse and AH.Browse.IsScanning and AH.Browse.IsScanning() then
        return AH.Browse.Progress()
    end
    return 0
end

function AH.Scan.SecondsUntilReady()
    -- The floor is SHARED (one auction house, one sensible cadence) and both engines
    -- read/write AH.db.lastScan, so either accessor answers. Replicate owns the
    -- canonical implementation.
    local e = Engine()
    if e and e.SecondsUntilReady then return e.SecondsUntilReady() end
    return 0
end

----------------------------------------------------------------
--  Slash Commands
--
--  Surface: help / scan / diag / check / find / wipe / blocked / settings / debug.
--  This list, the `cmd ==` branches below, and PrintHelp are meant to stay
--  one-for-one — the list had drifted, silently gaining four commands it never
--  learned about, so check all three together when adding or removing one.
----------------------------------------------------------------
SLASH_VERITASUI_AH1 = "/ah"
SLASH_VERITASUI_AH2 = "/auctionhouse"

local function PrintHelp()
    VUI.Print(AH.TAG, "Commands:")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah|r              — show this help")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah scan|r         — full price scan (AH open; 15-min cooldown)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah diag|r         — diagnostic / state dump")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah check|r        — show stored price for a shift-clicked item")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah find|r         — search the last scan's raw data for a shift-clicked item")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah wipe|r         — clear the price database")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah blocked|r      — manage sell-strip hidden items")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah settings|r     — open settings panel")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah debug|r        — toggle debug prints (suite-wide)")
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
        local wait = AH.Scan.SecondsUntilReady()
        local readyText
        if AH.Scan.IsScanning() then
            readyText = format("|cFFFFFF00scanning %d%%|r", floor(AH.Scan.Progress() * 100))
        elseif wait > 0 then
            readyText = format("cooldown %d:%02d", floor(wait / 60), wait % 60)
        else
            readyText = "|cFF00FF00ready|r"
        end
        VUI.Print(AH.TAG, format("  scan:         %s", readyText))
    end

    -- Always-on scan trace (v1.9.5): the full attempt-chain record of the
    -- current/most-recent scan, captured regardless of the debug flag — so a
    -- hang can be classified after the fact even when debug was off during it.
    if AH.Replicate and AH.Replicate.LastTrace then
        local tr = AH.Replicate.LastTrace()
        if tr then
            local line
            if tr.outcome == "requesting" then
                line = format("|cFFFFFF00requesting|r — attempt %d, no data for %ds",
                    tr.attempts or 0,
                    tr.firedAt and floor(GetTime() - tr.firedAt) or 0)
            elseif tr.outcome == "complete" then
                line = format("|cFF00FF00complete|r — %d attempt(s), %d/%d in %.0fs",
                    tr.attempts or 0, tr.committed or 0, tr.rows or 0, tr.totalTime or 0)
            else
                -- processing / failed / aborted
                line = format("%s — %d attempt(s)", tostring(tr.outcome), tr.attempts or 0)
            end
            VUI.Print(AH.TAG, format("  last scan:    %s", line))
            VUI.Print(AH.TAG, format("  first data:   %s; event pulses: %d",
                tr.firstEventLatency
                    and format("%.1fs after fire (attempt %d)",
                        tr.firstEventLatency, tr.firstEventAttempt or 1)
                    or "|cFFFF4444never arrived|r",
                tr.pulses or 0))
            -- Throttled-message timeline — THE line that classifies a lost request.
            -- DROPPED present => Blizzard's throttle system ate the request, so a
            -- retry is the right recovery. Nothing at all => the request went out
            -- and was refused, so backing off is. See Replicate.lua THROTTLE_EVENTS
            -- for why these are indistinguishable without this. Its own line so it
            -- survives a copy-paste.
            local thr = tr.throttle
            if thr and #thr > 0 then
                local parts = {}
                for i = 1, #thr do
                    parts[i] = format("%s@%.1fs", thr[i].label, thr[i].at or -1)
                end
                VUI.Print(AH.TAG, format("  throttle:     %s%s",
                    table.concat(parts, " "),
                    tr.throttleOverflow
                        and format(" (+%d more)", tr.throttleOverflow) or ""))
            else
                VUI.Print(AH.TAG,
                    "  throttle:     |cFFFFFF00(no throttled-message events seen)|r")
            end
            if AH.Replicate.ThrottleUnregistered then
                local bad = AH.Replicate.ThrottleUnregistered()
                if bad then
                    VUI.Print(AH.TAG, format(
                        "  throttle reg: |cFFFF4444FAILED for %s|r "
                        .. "(renamed in this client — the line above is unreliable)", bad))
                end
            end
        end
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
        price and MoneyStr(price) or "|cFFFF4444(none — never recorded)|r"))
    VUI.Print(AH.TAG, format("  age:          %s",
        age and (age .. " day(s)") or "|cFFFF4444n/a|r"))
    VUI.Print(AH.TAG, format("  today / seen: %d / %s",
        today, age and tostring(today - age) or "—"))

    local hist = AH.DB.GetPriceHistory(key)
    if hist[1] then
        VUI.Print(AH.TAG, format("  latest day:   day %d — min %s, qty %d",
            hist[1].day, MoneyStr(hist[1].min or 0), hist[1].qty or 0))
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
        -- Routed through the facade so /ah scan and the Scan button always use the
        -- SAME engine. Two entry points that could disagree is how a comparison gets
        -- silently invalidated.
        if not (AH.Scan and AH.Scan.Start) then
            VUI.Print(AH.TAG, "Scanner not loaded.")
            return
        end
        local ok, reason = AH.Scan.Start()
        if not ok then
            VUI.Print(AH.TAG, reason or "Scan could not start.")
        end

    elseif cmd == "engine" then
        local want = strtrim(rest)   -- `rest` is already lowercased above
        if want == "" then
            VUI.Print(AH.TAG, format("Scan engine: |cFFFFFF00%s|r  (/ah engine browse | replicate)",
                AH.Scan and AH.Scan.EngineName() or "?"))
            VUI.Print(AH.TAG, "  |cFFFFFF00replicate|r — per-auction rows; fails the first scan most days.")
            VUI.Print(AH.TAG, "  |cFFFFFF00browse|r — per-item summaries; the endpoint Auctionator defaults to.")
        elseif want == "browse" or want == "replicate" then
            if not (AH.db and AH.db.settings) then
                VUI.Print(AH.TAG, "Settings not loaded.")
                return
            end
            AH.db.settings.scanEngine = want
            VUI.Print(AH.TAG, format("Scan engine set to |cFFFFFF00%s|r.", want))
        else
            VUI.Print(AH.TAG, "Usage: /ah engine browse | replicate")
        end

    elseif cmd == "compare" then
        -- Runs a BROWSE scan in dry-run mode (nothing written) and diffs its prices
        -- against what is already stored, which on a replicate-scanned database is a
        -- direct engine-vs-engine comparison. This is what settles whether browse's
        -- minPrice is buyout-only: if browse reads systematically LOWER, it is
        -- including bids, which replicate deliberately skips.
        if not (AH.Browse and AH.Browse.Start) then
            VUI.Print(AH.TAG, "Browse engine not loaded.")
            return
        end
        AH.comparePending = true
        local ok, reason = AH.Browse.Start({ dry = true })
        if not ok then
            AH.comparePending = false
            VUI.Print(AH.TAG, reason or "Comparison could not start.")
        else
            VUI.Print(AH.TAG, "Comparing browse prices against the stored database "
                .. "(dry run — nothing will be written)…")
        end

    elseif cmd == "wipe" then
        if AH.DB then
            AH.DB.Wipe()
            VUI.Print(AH.TAG, "Price database cleared.")
        else
            VUI.Print(AH.TAG, "DB not loaded.")
        end

    elseif cmd == "diag" then
        PrintDiag()

    elseif cmd == "debug" then
        -- Suite-wide toggle: VUI.debug is the shared Lib gate every module's
        -- debug prints check. Surfaced here because the AH scanner is its
        -- heaviest consumer and "/run VeritasUI.debug = true" proved to be an
        -- incantation nobody remembers during a live repro (2026-07-11).
        VUI.debug = not VUI.debug
        VUI.Print(AH.TAG, "Debug prints " .. (VUI.debug
            and "|cFF00FF00ON|r (suite-wide; scans now emit fire/latency traces)"
            or  "|cFFFF4444OFF|r"))

    elseif cmd == "check" then
        PrintCheck(rawRest)

    elseif cmd == "find" then
        -- DIAGNOSTIC: sweep the last replicate snapshot for a shift-clicked item.
        if not (AH.Replicate and AH.Replicate.FindInSnapshot) then
            VUI.Print(AH.TAG, "Scanner not loaded.")
            return
        end
        local link = rawRest:match("|H.-|h.-|h")
        local itemID = link and tonumber(link:match("|Hitem:(%d+)"))
        if not itemID then
            VUI.Print(AH.TAG, "Usage: |cFFFFFF00/ah find|r then shift-click an item link.")
            return
        end
        VUI.Print(AH.TAG, format("Searching last snapshot for %s (itemID %d)…", link, itemID))
        local ok, reason = AH.Replicate.FindInSnapshot(itemID)
        if not ok then
            VUI.Print(AH.TAG, reason or "Sweep could not start.")
        end

    elseif cmd == "blocked" then
        if AH.SellStrip then
            if rest == "clear" then
                AH.SellStrip.ClearBlocked()
            else
                AH.SellStrip.ListBlocked()
            end
        else
            VUI.Print(AH.TAG, "Sell strip not loaded.")
        end

    else
        -- Default + explicit "help": print the command list.
        PrintHelp()
    end
end
