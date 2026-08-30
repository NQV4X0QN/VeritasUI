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
        -- Seed first, then report. SeedDefaults is idempotent and is deliberately
        -- called from every path that needs the keys to exist (Tooltip.lua and
        -- Settings.lua already do); calling it here as well is what makes the notice
        -- below reliable, because cross-frame PLAYER_LOGIN dispatch order is not
        -- guaranteed and a notice printed before the seeding ran would never fire.
        if AH.Tooltip and AH.Tooltip.SeedDefaults then
            AH.Tooltip.SeedDefaults()
        end

        VUI.Print(AH.TAG,
            format("v%s loaded — |cFFFFFF00/ah|r", AH.VERSION))

        -- One-time, once ever: the engine setting was cleared so the default applies
        -- again. Announced rather than done quietly -- it discards a stored value, and
        -- if that value WAS a deliberate choice the user needs to know to re-pin it.
        if AH.engineSettingWasReset then
            AH.engineSettingWasReset = nil
            VUI.Print(AH.TAG, format(
                "Scan engine reset to the default (|cFFFFFF00%s|r). The stored value was "
                .. "written by a defaulting bug that made every default change inert. "
                .. "Use |cFFFFFF00/ah engine|r to pin a different one.",
                AH.Scan.EngineName()))
        end

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
    --
    -- ⚠ THE ENGINE NAME IS PART OF THE MESSAGE, DELIBERATELY. Until v1.12.13 this
    -- read "Full scan started…" with no engine, and there were TWO engines with
    -- materially different failure modes. The owner's v1.12.12 browse trial silently
    -- ran on replicate for its whole duration, and the only reason he noticed was
    -- that he recognised replicate's 60s "request was lost" line -- i.e. the system
    -- was diagnosed by a failure message that happens to be engine-specific, which
    -- is luck, not observability. An unobservable engine selection is
    -- indistinguishable from the right one (same rule as the counted browse skips).
    VUI.Print(AH.TAG, format("Full scan started… |cFF888888(%s)|r",
        AH.Scan.EngineName()))
end)

-- `sourceUnit` is the noun for the second number, supplied by the firing engine, or
-- nil when the engine has no meaningful source count to report.
--
-- ⚠ THE HARDCODED "auctions" WAS A FALSE CLAIM ON BROWSE. Replicate walks individual
-- auction rows, so "N items priced from M auctions" is true there and M is genuinely
-- informative (e.g. 15,828 from 272,220). Browse returns one SUMMARY per item and never
-- sees an auction count at all, so M was simply the item count again -- the owner's
-- v1.12.13 scan read "22702 items priced from 22702 auctions", which both repeats one
-- number under two labels and understates the real auction count by orders of
-- magnitude. Browse now omits the clause rather than inventing a figure; its coverage
-- and skip counts are reported separately by Browse.lua.
--
-- The noun is passed IN rather than derived from AH.Scan.EngineName() here, so Core
-- keeps owning the user-facing wording while staying engine-agnostic -- the same split
-- that lets the scanners stay UI-agnostic.
--
-- `dry` is set by an engine run that wrote nothing (/ah compare, /ah browseprobe). Such a
-- run prints its OWN completion line carrying the honest observed count, so ours is
-- suppressed: committed is 0 by definition on that path, and "Scan complete — 0 items
-- priced" printed directly underneath read like a FAILED scan. The owner hit exactly that
-- twice while diagnosing the browse minPrice defect.
AH.Events.On("AH_SCAN_COMPLETE", function(committed, rows, sourceUnit, dry)
    if dry then return end
    if sourceUnit and rows and rows > 0 then
        VUI.Print(AH.TAG, format(
            "Scan complete — |cFF00FF00%d|r items priced from |cFFFFFF00%d|r %s.",
            committed or 0, rows, sourceUnit))
    else
        VUI.Print(AH.TAG, format(
            "Scan complete — |cFF00FF00%d|r items priced.", committed or 0))
    end
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
    if AH.browseProbePending then
        AH.browseProbePending = false
        if AH.Browse and AH.Browse.ReportWatch then AH.Browse.ReportWatch() end
    end
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

-- Resolve the active engine. The stored setting is a deliberate `/ah engine` pin and
-- is ABSENT unless the user made one (see SEED_EXEMPT in Tooltip.lua for why seeding
-- it broke the v1.12.12 trial); AH.Setting returns the current default for an absent
-- key, so the default is live.
--
-- ⚠ The `or "replicate"` is a LOAD-ORDER guard, not a policy. Core.lua loads before
-- Tooltip.lua, which defines AH.Setting, so a caller reaching here before Tooltip.lua
-- has run gets replicate. It is unreachable in practice (every caller runs after
-- PLAYER_LOGIN). It previously carried a comment claiming a nil SETTING also meant
-- replicate -- false, and it read as deliberate policy while the real policy lived in
-- SETTING_DEFAULTS.
local warnedBrowseMissing = false
local function Engine()
    local which = AH.Setting and AH.Setting("scanEngine") or "replicate"
    if which == "browse" then
        if AH.Browse then return AH.Browse end
        -- Falling back is right (a scan beats no scan) but doing it SILENTLY is not:
        -- the user asked for browse and would get replicate's failure modes with no
        -- explanation. Once per session, not per scan.
        if not warnedBrowseMissing then
            warnedBrowseMissing = true
            VUI.Print(AH.TAG, "|cFFFF4444Browse engine did not load|r — using replicate instead.")
        end
    end
    return AH.Replicate
end
AH.Scan.Engine = Engine

function AH.Scan.EngineName()
    return (Engine() == AH.Browse) and "browse" or "replicate"
end

-- True when the active engine came from a `/ah engine` pin rather than the default.
-- Read only by the diagnostics, so the state dump can distinguish "browse because
-- that is the default" from "browse because you asked for it" -- the exact question
-- nobody could answer during the v1.12.12 trial.
function AH.Scan.EngineIsPinned()
    local s = AH.db and AH.db.settings
    return (s and s.scanEngine ~= nil) and true or false
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

-- Does the ACTIVE engine support the click-to-refire recovery that the button's "Retry Scan"
-- state offers? Asked through the facade rather than having the button test engine names --
-- UI/ScanButton.lua is a pure view over this API and references neither engine.
-- ⚠ Defaults to FALSE for an engine that does not declare it: a disabled "Scanning…" is never
-- wrong, whereas offering a recovery we cannot honour is.
function AH.Scan.SupportsRetry()
    local e = Engine()
    return (e and e.SupportsRetry) and true or false
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
--  Surface: help / scan / engine / floor / bardemo / bartune / baratlas / compare /
--  browseprobe / live / autoadvance / ttprobe /
--  diag / check / find / wipe / blocked / settings / debug.
--  This list, the `cmd ==` branches below, and PrintHelp are meant to stay
--  one-for-one — the list had drifted, silently gaining four commands it never
--  learned about, so check all three together when adding or removing one.
--
--  ⚠ IT DRIFTED AGAIN, THE SAME WAY, DESPITE THE WARNING ABOVE. v1.12.9 added
--  engine / compare / browseprobe as working branches and updated neither this
--  list nor PrintHelp, so for four releases the only way to discover the command
--  that selects the scan engine was to read the source. The owner hit exactly
--  that and asked where the command was. A comment telling a future reader to
--  check three places by hand did not survive one feature; the headless suite now
--  asserts the three agree, because that is the only version of this rule that
--  cannot be forgotten.
----------------------------------------------------------------
SLASH_VERITASUI_AH1 = "/ah"
SLASH_VERITASUI_AH2 = "/auctionhouse"

local function PrintHelp()
    VUI.Print(AH.TAG, "Commands:")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah|r              — show this help")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah scan|r         — full price scan (AH open; see /ah floor for the cooldown)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah floor|r        — show or set the scan cooldown (off | on | seconds)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah bardemo|r      — hold the scan bar in one state to inspect it")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah bartune|r      — tune the scan bar's rounded-cap slice margin")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah baratlas|r     — show the raw bar atlas art (shape probe)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah engine|r       — show or set the scan engine (browse | replicate)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah compare|r      — scan with browse, diff against the stored prices")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah browseprobe|r  — check one shift-clicked item against the live listing")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah live|r         — live-search price corrections (on | off | status)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah autoadvance|r  — load the next sell-strip item after a post (on | off)")
    VUI.Print(AH.TAG, "  |cFFFFFF00/ah ttprobe|r      — what the tooltip actually priced (no args = last render)")
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

    -- Which of the two scan engines is live, and WHY. Added v1.12.13: the module has
    -- shipped two engines since v1.12.9 and the state dump never named either, so a
    -- scan running on the wrong one was invisible in the one place built to answer
    -- "what is this module actually doing".
    VUI.Print(AH.TAG, format("  engine:       |cFFFFFF00%s|r (%s)",
        AH.Scan.EngineName(),
        AH.Scan.EngineIsPinned() and "pinned via /ah engine" or "default"))

    -- Live-search correction layer (LiveSearch.lua). Reported here for the same reason
    -- the engine name is: it silently REWRITES scanned prices, so a state dump that
    -- omitted it would leave "why is this price different from the last scan" unanswerable.
    -- `corrected` is the number that matters -- it is nonzero only if the layer is
    -- actually disagreeing with the scan, which is the whole point of it existing.
    if AH.LiveSearch then
        local obs, rec, corr = AH.LiveSearch.Stats()
        VUI.Print(AH.TAG, format("  live search:  %s — %d observed, %d recorded, "
            .. "|cFFFFFF00%d corrected|r (/ah live)",
            AH.Setting("liveSearchPrices") and "|cFF00FF00on|r" or "|cFFFF4444off|r",
            obs, rec, corr))
    end

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

    -- Scan floor, incl. whether it has been overridden away from the shipped default.
    -- Reported here because an override PERSISTS, and a silently-disabled cooldown is
    -- exactly the kind of state that is invisible until it surprises someone.
    if AH.Replicate and AH.Replicate.ScanFloorSeconds then
        local cur, def = AH.Replicate.ScanFloorSeconds()
        VUI.Print(AH.TAG, format("  scan floor:   |cFFFFFF00%ds|r%s", cur,
            (cur ~= def) and format(" |cFFFF4444(overridden; default %ds)|r", def) or ""))
    end

    -- Scan-bar art. MEASUREMENT for the rounded-cap work: whether each atlas resolved in
    -- THIS client, its native size, and the rect we stretch it into. The native:rect ratio
    -- is the one fact the Blizzard source cannot supply, and it decides whether the caps
    -- need slice margins rather than a plain stretch.
    if AH.ScanProgress and AH.ScanProgress.ArtInfo then
        local a = AH.ScanProgress.ArtInfo()
        VUI.Print(AH.TAG, format("  bar look:     %s  (built: %s)",
            a.journeyArt and "|cFF00FF00journeys|r" or "|cFFFF4444legacy fallback|r",
            a.built and "yes" or "no"))
        -- Reported separately from the look, because "wrong colour" and "still square" are
        -- different failures. `slice` is the horizontal margin keeping the caps at native
        -- width; track/frame report whether the slice APIs actually took.
        VUI.Print(AH.TAG, format("  bar shape:    slice |cFFFFFF00%s|r  (track: %s, frame: %s, fill: %s)",
            tostring(a.slice),
            a.sliceTrack and "|cFF00FF00ok|r" or "|cFFFF4444no|r",
            a.sliceFrame and "|cFF00FF00ok|r" or "|cFFFF4444no|r",
            a.sliceFill  and "|cFF00FF00ok|r" or "|cFFFF4444no|r"))
        for _, e in ipairs(a.atlases) do
            VUI.Print(AH.TAG, format("    %s  %s  native %sx%s",
                e.ok and "|cFF00FF00ok|r  " or "|cFFFF4444MISS|r",
                e.name, tostring(e.width), tostring(e.height)))
        end
        -- ⚠ Report the LABEL and HEIGHT pins too. Both persist, and both OVERRIDE the
        -- shipped defaults, so "why is the text still showing after we removed it" is
        -- otherwise invisible -- which is exactly what happened on 2026-08-23: an earlier
        -- `/ah bartune label above` outlived the default flip to "off".
        local lp = AH.db and AH.db.settings and AH.db.settings.barLabelPos
        local bh = AH.db and AH.db.settings and AH.db.settings.barHeight
        VUI.Print(AH.TAG, format("  bar label:    |cFFFFFF00%s|r%s",
            lp or "off", (lp ~= nil) and " |cFFFF4444(pinned; default off)|r" or " (default)"))
        VUI.Print(AH.TAG, format("  bar height:   |cFFFFFF00%s|r%s",
            tostring(bh or 18), (bh ~= nil) and " |cFFFF4444(pinned; default 18)|r" or " (default)"))
        VUI.Print(AH.TAG, format("    rect: bar %sx%s  container %dx%d",
            tostring(a.barW), tostring(a.barH), a.frameW, a.frameH))
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
            VUI.Print(AH.TAG, format("Scan engine: |cFFFFFF00%s|r (%s)  (/ah engine browse | replicate)",
                AH.Scan and AH.Scan.EngineName() or "?",
                AH.Scan and AH.Scan.EngineIsPinned() and "pinned" or "default"))
            VUI.Print(AH.TAG, "  |cFFFFFF00replicate|r — per-auction rows; fails the first scan most days.")
            VUI.Print(AH.TAG, "  |cFFFFFF00browse|r — per-item summaries; the endpoint Auctionator defaults to.")
            VUI.Print(AH.TAG, "  |cFF888888A pin persists and overrides future default changes; "
                .. "/ah engine default clears it.|r")
        elseif want == "default" then
            -- Deliberately reachable: pinning is now permanent (that is the point of
            -- the pin), so there has to be a way back to "follow the default" other
            -- than editing saved variables. Clearing the key IS the unpinned state --
            -- see SEED_EXEMPT in Tooltip.lua.
            if not (AH.db and AH.db.settings) then
                VUI.Print(AH.TAG, "Settings not loaded.")
                return
            end
            AH.db.settings.scanEngine = nil
            VUI.Print(AH.TAG, format("Scan engine pin cleared — now following the default (|cFFFFFF00%s|r).",
                AH.Scan.EngineName()))
        elseif want == "browse" or want == "replicate" then
            if not (AH.db and AH.db.settings) then
                VUI.Print(AH.TAG, "Settings not loaded.")
                return
            end
            AH.db.settings.scanEngine = want
            VUI.Print(AH.TAG, format("Scan engine pinned to |cFFFFFF00%s|r.", want))
        else
            VUI.Print(AH.TAG, "Usage: /ah engine browse | replicate | default")
        end

    elseif cmd == "browseprobe" then
        -- PERMANENT diagnostic: watch ONE item through a live dry browse scan and report
        -- the raw API values, to separate "browse priced it wrong" from "browse never
        -- returned it" from "the market moved". Kept because it is the only tool that
        -- can validate the browse engine against the game's own listing.
        local link = rawRest and rawRest:match("|H.-|h.-|h")
        if not link then
            VUI.Print(AH.TAG, "Usage: |cFFFFFF00/ah browseprobe|r then shift-click an item link "
                .. "(do it at the Auction House).")
            return
        end
        local key = AH.DB and AH.DB.MakeKey(link)
        if not key then
            VUI.Print(AH.TAG, "Could not derive a price key from that link.")
            return
        end
        if not (AH.Browse and AH.Browse.SetWatch) then
            VUI.Print(AH.TAG, "Browse engine not loaded.")
            return
        end
        AH.Browse.SetWatch(key)
        AH.browseProbePending = true
        local okP, reasonP = AH.Browse.Start({ dry = true })
        if not okP then
            AH.browseProbePending = false
            VUI.Print(AH.TAG, reasonP or "Probe could not start.")
        else
            VUI.Print(AH.TAG, format("Watching |cFFFFFF00%s|r through a dry browse scan…", key))
        end

    elseif cmd == "live" then
        -- Readout and toggle for LiveSearch.lua, the correction layer over the browse
        -- engine's minPrice defect. This exists because the layer is otherwise INVISIBLE:
        -- it prints nothing on the event by design (a search-results event fires on every
        -- sell-form load and every commodity opened on the Buy tab, so a chat line per
        -- observation would be unusable), and a silent price-rewriting path with no readout
        -- is exactly the "unmeasured" shape Browse.lua's coverage report was added to kill.
        if not AH.LiveSearch then
            VUI.Print(AH.TAG, "Live search not loaded.")
            return
        end
        local arg = strtrim(rest)   -- `rest` is already lowercased above
        if arg == "on" or arg == "off" then
            if not (AH.db and AH.db.settings) then
                VUI.Print(AH.TAG, "Settings not loaded.")
                return
            end
            AH.db.settings.liveSearchPrices = (arg == "on")
            -- Live variant: this takes effect on the next search-results event, with no
            -- /reload needed, so the stock PrintOnOff wording would print a false
            -- instruction (Lib's PrintOnOff appends "— /reload to apply").
            VUI.PrintOnOffLive(AH.TAG, "Live search prices", arg == "on")
            return
        end
        local obs, rec, corr = AH.LiveSearch.Stats()
        VUI.Print(AH.TAG, format("Live search prices: %s",
            AH.Setting("liveSearchPrices") and "|cFF00FF00on|r" or "|cFFFF4444off|r"))
        VUI.Print(AH.TAG, format("  %d search result(s) observed, %d recorded, "
            .. "|cFFFFFF00%d|r changed a stored price", obs, rec, corr))
        local list = AH.LiveSearch.Recent()
        if #list == 0 then
            VUI.Print(AH.TAG, "  no corrections yet — open an item on the Buy or Sell tab.")
        else
            VUI.Print(AH.TAG, "  most recent corrections (oldest first):")
            for i = 1, #list do
                local e = list[i]
                VUI.Print(AH.TAG, format("    %s  %s -> |cFF00FF00%s|r",
                    e.key,
                    e.old and AH.Money.FormatText(e.old) or "none",
                    AH.Money.FormatText(e.new)))
            end
        end

    elseif cmd == "ttprobe" then
        -- Localise a tooltip-vs-/ah check price disagreement. Reports the tooltip render's
        -- OWN computation for the shift-clicked link AND every stored record sharing the
        -- itemID, because the leading explanation for such a split is TWO records -- one
        -- keyed bare and one keyed with an item level -- which no other command can reveal.
        local link = rawRest and rawRest:match("|H.-|h.-|h")
        if not link then
            -- NO LINK => report what the tooltip path ACTUALLY used on its last run. This is
            -- the decisive mode: hover the item, then run this. A reconstruction from a
            -- shift-clicked link cannot see the case where the tooltip resolved a DIFFERENT
            -- item than the one you clicked, which a compound tooltip (recipe + taught item,
            -- housing decor) can do via TooltipUtil.GetDisplayedItem.
            local lr = AH.Tooltip and AH.Tooltip._LastRender and AH.Tooltip._LastRender()
            if not (lr and lr.link) then
                VUI.Print(AH.TAG, "No tooltip price rendered yet this session. Hover a priced "
                    .. "item, then run |cFFFFFF00/ah ttprobe|r again — or pass a shift-clicked "
                    .. "link to probe one directly.")
                return
            end
            VUI.Print(AH.TAG, "Last tooltip price render:")
            VUI.Print(AH.TAG, format("  frame:  %s", tostring(lr.frame)))
            VUI.Print(AH.TAG, format("  link:   %s", tostring(lr.link)))
            VUI.Print(AH.TAG, format("  itemID: |cFFFFFF00%s|r",
                tostring(lr.link:match("|Hitem:(%d+)") or lr.link:match("|Hbattlepet:(%d+)"))))
            VUI.Print(AH.TAG, format("  key:    |cFFFFFF00%s|r", tostring(lr.key)))
            VUI.Print(AH.TAG, format("  price:  |cFFFFFF00%s|r  (raw %s)",
                lr.price and AH.Money.FormatText(lr.price) or "none", tostring(lr.price)))
            VUI.Print(AH.TAG, format("  source used: |cFFFFFF00%s|r", tostring(lr.used)))
            -- All four candidate identities, so the correct SOURCE is chosen by measurement
            -- rather than by argument. On a compound tooltip these disagree.
            VUI.Print(AH.TAG, "  candidates:")
            VUI.Print(AH.TAG, format("    data.hyperlink      id=%s  %s",
                tostring(lr.dataId), tostring(lr.dataLink)))
            VUI.Print(AH.TAG, format("    PrimaryTooltipData  id=%s  %s",
                tostring(lr.primaryId), tostring(lr.primaryLink)))
            VUI.Print(AH.TAG, format("    GetDisplayedItem    id=%s  %s",
                tostring(lr.displayedId), tostring(lr.displayedLink)))
            VUI.Print(AH.TAG, "  |cFF888888Whichever line names the item you actually hovered "
                .. "is the source the tooltip should be reading.|r")
            return
        end
        local iid = link:match("|Hitem:(%d+)") or link:match("|Hbattlepet:(%d+)")
        VUI.Print(AH.TAG, format("ttprobe: %s", link))

        -- What MakeKey decides, and the two inputs that steer it.
        local _, _, _, equipLoc = (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(link)
        local okIlvl, ilvl = pcall(function()
            return (C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)(link)
        end)
        VUI.Print(AH.TAG, format("  equipLoc:   %s   ilvl: %s",
            (equipLoc == nil and "|cFFFF4444nil|r") or (equipLoc == "" and "empty (not gear)") or equipLoc,
            okIlvl and tostring(ilvl) or "|cFFFF4444error|r"))

        local key = AH.DB and AH.DB.MakeKey(link)
        VUI.Print(AH.TAG, format("  derived key: |cFFFFFF00%s|r", tostring(key)))

        -- The number the RENDER would use, straight off the tooltip module's own builder.
        if AH.Tooltip and AH.Tooltip._BuildPriceData and key then
            local p = AH.Tooltip._BuildPriceData(key)
            VUI.Print(AH.TAG, format("  tooltip would render: %s   (raw %s)",
                p and AH.Money.FormatText(p) or "|cFFFF4444nothing|r", tostring(p)))
            if p and AH.Tooltip.CoinMarkup then
                -- Escaped so the markup is READABLE rather than rendered as coin art.
                local mk = AH.Tooltip.CoinMarkup(p) or ""
                VUI.Print(AH.TAG, "  coin markup: " .. mk:gsub("|", "||"))
            end
        end
        VUI.Print(AH.TAG, format("  GetMarketPrice(key): %s",
            key and tostring(AH.DB.GetMarketPrice(key)) or "n/a"))

        -- EVERY record for this itemID. A bare key and an i:<id>:<ilvl> key holding
        -- different prices is the split that makes a tooltip and /ah check disagree.
        if iid and AH.db and AH.db.prices then
            local hits = 0
            for k, rec in pairs(AH.db.prices) do
                if k == "i:" .. iid or k:match("^i:" .. iid .. ":") or k == "p:" .. iid then
                    hits = hits + 1
                    VUI.Print(AH.TAG, format("  stored %s%s|r = %s  (seen day %s)",
                        k == key and "|cFF00FF00" or "|cFFFFFF00", k,
                        rec.market and AH.Money.FormatText(rec.market) or "nil",
                        tostring(rec.seen)))
                end
            end
            if hits == 0 then
                VUI.Print(AH.TAG, "  |cFFFF4444no stored record for this itemID at all.|r")
            elseif hits > 1 then
                VUI.Print(AH.TAG, "  |cFFFF4444More than one record for this itemID.|r "
                    .. "The green one is what MakeKey resolves to now; a different key holding "
                    .. "the price you see on the tooltip means the two paths disagree on the key.")
            end
        end

    elseif cmd == "autoadvance" then
        -- Toggle/readout for UI/SellStrip.lua's post-then-load-the-next-item behaviour.
        -- A slash toggle exists alongside the checkbox because this one has an UNPROVEN
        -- taint assumption behind it (see the block above ArmAutoAdvance): if the native
        -- Create Auction button ever starts failing on an auto-advanced item, the fix has
        -- to be reachable without hunting through the options panel mid-session.
        local want = strtrim(rest)   -- `rest` is already lowercased above
        if want == "on" or want == "off" then
            if not (AH.db and AH.db.settings) then
                VUI.Print(AH.TAG, "Settings not loaded.")
                return
            end
            AH.db.settings.sellAutoAdvance = (want == "on")
            if want == "off" and AH.SellStrip and AH.SellStrip.CancelAutoAdvance then
                AH.SellStrip.CancelAutoAdvance()   -- drop any advance already armed
            end
            VUI.PrintOnOffLive(AH.TAG, "Sell-strip auto-advance", want == "on")
        elseif want == "" then
            VUI.Print(AH.TAG, format("Sell-strip auto-advance: %s  (/ah autoadvance on | off)",
                AH.Setting("sellAutoAdvance") and "|cFF00FF00on|r" or "|cFFFF4444off|r"))
            VUI.Print(AH.TAG, "  |cFF888888Loads the next strip item after a post. "
                .. "It never posts anything — Create Auction is still a real click.|r")
        else
            VUI.Print(AH.TAG, "Usage: /ah autoadvance on | off")
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

    elseif cmd == "floor" then
        -- ⚠ GUARD FIRST. Every branch below reads or WRITES AH.db.settings, and an
        -- unguarded write throws "attempt to index a nil value (field 'db')" as a visible
        -- Lua error. `/ah engine` two branches up already does this; these did not.
        -- Reachable whenever the module disabled itself (AUCTION_HOUSE_DISABLED) or the DB
        -- never initialised, with slash commands still registered.
        if not (AH.db and AH.db.settings) then
            VUI.Print(AH.TAG, "Settings not loaded.")
            return
        end
        -- The scan cooldown. Absence of the setting means "use the shipped default", so
        -- `off`/`on` write and CLEAR the key rather than writing 900 (see
        -- Replicate.ScanFloorSeconds for why a seeded default is wrong here).
        local cur, def = 900, 900
        if AH.Replicate and AH.Replicate.ScanFloorSeconds then
            cur, def = AH.Replicate.ScanFloorSeconds()
        end
        if rest == "" then
            VUI.Print(AH.TAG, format("Scan floor: |cFFFFFF00%ds|r%s (default %ds).",
                cur, (cur == 0) and " |cFFFF4444(DISABLED)|r" or "", def))
            VUI.Print(AH.TAG, "  /ah floor off | on | <seconds>")
        elseif rest == "off" or rest == "0" then
            AH.db.settings.scanFloorSeconds = 0
            VUI.Print(AH.TAG, "Scan floor |cFFFF4444DISABLED|r — scans may be run back to back.")
            VUI.Print(AH.TAG, "  Blizzard's own throttling still applies; on the replicate engine a")
            VUI.Print(AH.TAG, "  repeat request may be refused or return the same snapshot.")
        elseif rest == "on" or rest == "default" then
            AH.db.settings.scanFloorSeconds = nil
            VUI.Print(AH.TAG, format("Scan floor restored to the default (%ds).", def))
        else
            local n = tonumber(rest)
            if n and n >= 0 then
                AH.db.settings.scanFloorSeconds = n
                VUI.Print(AH.TAG, format("Scan floor set to |cFFFFFF00%ds|r.", n))
            else
                VUI.Print(AH.TAG, "Usage: /ah floor [off | on | <seconds>]")
            end
        end

    elseif cmd == "baratlas" then
        -- Pure probe: draws the three bar atlases over a MAGENTA plate so transparency is
        -- visible. Settles whether the art is actually pill-shaped -- the assumption three
        -- failed rounding attempts all rested on and none of them verified.
        if not (AH.ScanProgress and AH.ScanProgress.AtlasProbe) then
            VUI.Print(AH.TAG, "Scan progress bar not loaded.")
        else
            AH.ScanProgress.AtlasProbe(rest ~= "off")
            VUI.Print(AH.TAG, (rest == "off") and "Atlas probe hidden."
                or "Atlas probe shown — magenta = transparent. /ah baratlas off to close.")
        end

    elseif cmd == "bartune" then
        -- ⚠ GUARD FIRST — same reason as /ah floor above.
        if not (AH.db and AH.db.settings) then
            VUI.Print(AH.TAG, "Settings not loaded.")
            return
        end
        -- The rounded-cap slice margin. Tunable because the cap radius baked into a
        -- 335x18 atlas is not something the Blizzard source states, and stretching to our
        -- 170 width is what flattened it. Ceiling is 9: an 18px-tall pill cannot round by
        -- more than half its height. 0 = no slicing (plain stretch, flat caps).
        if rest == "" then
            local cur = AH.db.settings.barSliceMargin
            VUI.Print(AH.TAG, format("Bar slice margin: |cFFFFFF00%s|r (default 9, max 9, 0 = off).",
                (cur == nil) and "9 (default)" or tostring(cur)))
            VUI.Print(AH.TAG, format("Bar label: |cFFFFFF00%s|r   font delta: |cFFFFFF00%+d|r",
                (AH.db.settings.barLabelPos == "above") and "above" or "in",
                tonumber(AH.db.settings.barFontDelta) or -1))
            VUI.Print(AH.TAG, "  /ah bartune <0-9> | fill on|off | label off|in|above | height <6-24> | font <-3..0>")
            VUI.Print(AH.TAG, "  then /reload and /ah bardemo to look at it")
        elseif rest == "label off" or rest == "label in" or rest == "label above" then
            -- Arrangement, not a bug: Blizzard's own bar has no text in it at all
            -- (Blizzard_Journeys.xml anchors the level label above the bar), which is why
            -- they never fit glyphs into 18px. Owner's aesthetic call.
            local mode = rest:match("^label%s+(%a+)$")
            AH.db.settings.barLabelPos = mode
            VUI.Print(AH.TAG, format("Bar label: |cFFFFFF00%s|r — /reload to rebuild the bar.",
                (mode == "above") and "ABOVE the bar (Blizzard's arrangement)"
                or (mode == "in") and "INSIDE the bar" or "OFF (bar only)"))
            if mode == "off" then
                VUI.Print(AH.TAG, "  Note: the indeterminate wait now shows only the sweep — no elapsed time.")
            end
        elseif rest:match("^height%s*%d+$") then
            local hgt = tonumber(rest:match("(%d+)$"))
            if hgt and hgt >= 6 and hgt <= 24 then
                AH.db.settings.barHeight = hgt
                VUI.Print(AH.TAG, format("Bar height |cFFFFFF00%d|r — /reload to rebuild.", hgt))
                VUI.Print(AH.TAG, "  ~9 is geometrically similar to Blizzard's 335x18, so caps round the same.")
            else
                VUI.Print(AH.TAG, "Usage: /ah bartune height <6-24>")
            end
        elseif rest:match("^font%s*[-+]?%d+$") then
            local d = tonumber(rest:match("([-+]?%d+)$"))
            AH.db.settings.barFontDelta = d
            VUI.Print(AH.TAG, format("Inside-label font delta |cFFFFFF00%+d|r — /reload to rebuild.", d))
        elseif rest == "fill on" or rest == "fill off" then
            -- Separate switch: slicing the FILL is the part that interacts with the
            -- StatusBar's texcoord crop, so a functional fault there must be revertible
            -- without also giving up the track/frame caps.
            AH.db.settings.barSliceFill = (rest == "fill on")
            VUI.Print(AH.TAG, format("Fill slicing |cFFFFFF00%s|r — /reload to rebuild the bar.",
                (rest == "fill on") and "ON" or "OFF"))
        else
            local n = tonumber(rest)
            if n and n >= 0 and n <= 9 then
                AH.db.settings.barSliceMargin = n
                VUI.Print(AH.TAG, format("Bar slice margin set to |cFFFFFF00%d|r — /reload to rebuild the bar.", n))
            else
                VUI.Print(AH.TAG, "Usage: /ah bartune <0-9> | fill on|off | label off|in|above")
                VUI.Print(AH.TAG, "                   | height <6-24> | font <-3..0>")
            end
        end

    elseif cmd == "bardemo" then
        -- Appearance harness for the scan bar. The headless suite cannot see the bar at
        -- all, so this is how a cosmetic change gets looked at without a real scan.
        if not (AH.ScanProgress and AH.ScanProgress.Demo) then
            VUI.Print(AH.TAG, "Scan progress bar not loaded.")
        else
            local mode, arg = rest:match("^(%a+)%s*(%d*)$")
            if rest == "" then mode, arg = "run", "60" end
            if mode ~= "run" and mode ~= "wait" and mode ~= "done"
               and mode ~= "fail" and mode ~= "off" then
                VUI.Print(AH.TAG, "Usage: /ah bardemo [run <pct> | wait | done | fail | off]")
            elseif AH.ScanProgress.Demo(mode, tonumber(arg)) then
                if mode == "off" then
                    VUI.Print(AH.TAG, "Bar demo cleared.")
                else
                    VUI.Print(AH.TAG, format("Bar demo: |cFFFFFF00%s|r — /ah bardemo off to clear.", mode))
                end
            else
                VUI.Print(AH.TAG, "Open the auction house first (the bar anchors to it).")
            end
        end

    else
        -- Default + explicit "help": print the command list.
        PrintHelp()
    end
end
