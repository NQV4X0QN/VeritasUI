-- VeritasUI_AuctionHouse / Browse.lua
-- Whole-AH price scan via an EMPTY BROWSE QUERY, as an alternative to Replicate.lua.
--
-- ── WHY THIS EXISTS ──
-- Replicate.lua's C_AuctionHouse.ReplicateItems() fails the first scan of most days
-- and has resisted a fix since the module was written: taint, fire context, readiness
-- gates, request pacing and an account-level rate limit were each investigated and
-- falsified (see ArmStallDetector and the SKILL landmines).
--
-- MEASURED 2026-08-03, owner's PC: with our replicate scan freshly failed (zero event
-- pulses, no data), Auctionator's full scan returned 20,056 items seconds later on the
-- same character, realm and session. Its chat line read "summary mode" — that is its
-- IncrementalScan, which never calls ReplicateItems: it sends an EMPTY SendBrowseQuery
-- and paginates. Auctionator ships replicate DISABLED (Source/Config/Main.lua:
-- REPLICATE_SCAN = false, opt-in under Advanced), so its users are on this path.
--
-- So the hang is an ENDPOINT difference. This file is that endpoint.
--
-- ⚠ SendBrowseQuery is NOT SendSearchQuery. Design §2.2 correctly rejects
-- SendSearchQuery for scanning (item-specific, rate-capped ~100/min) but that was
-- wrongly generalised into "replicate is the only whole-AH scan", which is the belief
-- that kept this module on one endpoint for months. Different call, different cap.
--
-- ── WHAT IT COSTS AND WHAT IT BUYS ──
-- Browse returns per-item SUMMARIES: minPrice + totalQuantity, keyed by itemKey. That
-- is exactly what Replicate's Fold() computes from ~275k rows (minimum unit price and
-- summed quantity) — so the two produce the SAME two numbers, and every consumer in
-- this addon reads only those. What is genuinely lost is per-auction detail (individual
-- listings, time-left, stack sizes), which nothing stores or uses today; and the daily
-- `max`, which Database.lua writes and NOTHING reads.
--
-- What it buys: itemKey carries itemLevel and battlePetSpeciesID directly, so gear and
-- pets key without a loaded link. That removes the cold-cache retry phase entirely —
-- including the rows it still abandons at the LINK_RETRY_BUDGET cap (6,139 of 16,304 on
-- one measured scan, whose items therefore never got their price AGE refreshed either).
--
-- ── ⚠ OPEN QUESTION, DO NOT ASSUME SETTLED ──
-- Whether browse's `minPrice` is buyout-only or can reflect a BID. Replicate skips
-- bid-only auctions deliberately. Auctionator reads `bidAmount` as a separate field,
-- which SUGGESTS minPrice is buyout — but that is inference from field naming, not a
-- measurement, and this project has been burned by exactly that (see the MenuUtil
-- naming-pattern note in SKILL.md). `/ah compare` exists to settle it against real
-- data before this becomes the default engine.
--
-- ⚠ Default engine is REPLICATE. This is opt-in until `/ah compare` comes back clean:
-- a live price database is not the place to find out.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
--
--  AddPrices runs once per browse result — up to ~20k per scan — so its lookups are
--  hot. Cold globals (CreateFrame, C_Timer) stay global per the suite's convention.
----------------------------------------------------------------
local ipairs      = ipairs
local pcall       = pcall
local type        = type
local time        = time
local floor       = math.floor
local format      = string.format
local tinsert     = table.insert
local tremove     = table.remove
local CreateFrame = CreateFrame

AH.Browse = {}

-- Blizzard streams browse results in pages. A results table at or below this size is
-- treated as the START of a fresh set rather than an incremental update: the UPDATED
-- event also fires for the item-specific searches Blizzard's own UI runs, and those
-- return small sets. Auctionator uses 500 for the same discrimination.
local BATCH_SIZE = 500

local scanning   = false   -- a browse scan is in progress
local progress   = 0       -- 0..1
local agg                  -- [key] = { unit = minPrice, qty = totalQuantity }
local seenCount  = 0       -- browse results folded this scan
local pageCount  = 0       -- pages requested
local dryRun               -- when true, results are NOT written to the DB (/ah compare)
local dryResult            -- captured aggregate for the dry run
local startedAt

----------------------------------------------------------------
--  Send queue
--
--  Browse queries DO run inside Blizzard's throttled-message system — unlike
--  ReplicateItems, which was measured to produce no throttled-family events at all
--  (PROBE_LIBRARY §5). Auctionator routes every SendBrowseQuery and
--  RequestMoreBrowseResults through a queue for exactly this reason, and our own
--  AUCTIONHOUSE_DESIGN.md §"Phase 1" specified this queue before it was deleted at
--  v1.7.0 as Shopping-tab collateral. This is that queue, restored for the path that
--  actually needs it.
--
--  Single-step drain: send one, wait for THROTTLED_SYSTEM_READY, send the next.
----------------------------------------------------------------
local queue = {}

local function ThrottleReady()
    local C = C_AuctionHouse
    if not (C and C.IsThrottledMessageSystemReady) then return true end
    local ok, ready = pcall(C.IsThrottledMessageSystemReady)
    -- Absent or erroring API → treat as ready. Refusing to send would strand the scan
    -- silently, which is worse than sending slightly early.
    if not ok then return true end
    return ready ~= false
end

local function Drain()
    if #queue == 0 then return end
    if not ThrottleReady() then return end
    local fn = tremove(queue, 1)
    if fn then pcall(fn) end
end

local function Enqueue(fn)
    tinsert(queue, fn)
    Drain()
end

local function ClearQueue()
    for i = #queue, 1, -1 do queue[i] = nil end
end

----------------------------------------------------------------
--  Fold one page of browse results
--
--  Mirrors Replicate's Fold(): keep the MINIMUM unit price per key and SUM the
--  quantities, so both engines produce identical semantics for the two fields
--  anything actually reads.
--
--  Every field access is defensive: results come from a Blizzard API we do not own,
--  and one malformed row must not abort a 20k-item scan.
----------------------------------------------------------------
local function AddPrices(results)
    if type(results) ~= "table" then return end
    for _, r in ipairs(results) do
        if type(r) == "table" then
            local qty = r.totalQuantity
            local unit = r.minPrice
            -- Zero-quantity rows are listings with nothing actually available;
            -- Auctionator skips them too. Zero/absent price is not a price.
            if type(qty) == "number" and qty > 0
               and type(unit) == "number" and unit > 0 then
                local key = AH.DB.MakeKeyFromItemKey(r.itemKey)
                if key then
                    local a = agg[key]
                    if not a then
                        agg[key] = { unit = unit, qty = qty }
                        seenCount = seenCount + 1
                    else
                        if unit < a.unit then a.unit = unit end
                        a.qty = a.qty + qty
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
--  Commit / finish
----------------------------------------------------------------
local function Finish()
    local kept = 0
    if dryRun then
        dryResult = agg
    else
        local day = nil   -- Record() defaults to today
        for key, a in pairs(agg) do
            AH.DB.Record(key, a.unit, a.qty, day)
            kept = kept + 1
        end
        -- Shared scan floor. Deliberately the SAME field Replicate stamps
        -- (AH.db.lastScan): there is one auction house and one sensible scan cadence,
        -- so switching engines must not hand out a fresh allowance. Replicate owns the
        -- canonical reader, AH.Replicate.SecondsUntilReady.
        if AH.db then AH.db.lastScan = time() end
    end

    local rows = seenCount
    scanning, progress = false, 1
    agg = nil
    ClearQueue()

    local elapsed = startedAt and (GetTime() - startedAt) or 0
    if dryRun then
        VUI.Print(AH.TAG, format(
            "Browse dry run complete — %d items observed in %.0fs (nothing written).",
            rows, elapsed))
        AH.Events.Fire("AH_SCAN_COMPLETE", 0, rows)
    else
        AH.Events.Fire("AH_SCAN_COMPLETE", kept, rows)
    end
    dryRun = false
end

local function Fail(reason)
    scanning, progress = false, 0
    agg, dryRun = nil, false
    ClearQueue()
    AH.Events.Fire("AH_SCAN_FAILED", tostring(reason or "unknown"))
end

----------------------------------------------------------------
--  Pagination
--
--  Keep asking for more pages until Blizzard says the browse set is complete.
--  ⚠ NO TIMEOUT — the same rule as Replicate: delivery time is unbounded and a
--  fixed watchdog can only race a slow-but-successful scan and kill it (that bug cost
--  ~50% of scans at v1.7.1). AH_CLOSED is the only abort.
----------------------------------------------------------------
local function HasFullResults()
    local C = C_AuctionHouse
    if not (C and C.HasFullBrowseResults) then return true end
    local ok, full = pcall(C.HasFullBrowseResults)
    if not ok then return true end
    return full == true
end

local function NextStep()
    if not scanning then return end
    if not HasFullResults() then
        pageCount = pageCount + 1
        -- Progress is necessarily an estimate: Blizzard exposes no total. Report a
        -- curve that keeps moving without ever claiming completion, so the bar cannot
        -- sit at a number that looks finished while pages are still arriving.
        progress = 1 - (1 / (2 + pageCount * 0.35))
        Enqueue(function()
            if C_AuctionHouse and C_AuctionHouse.RequestMoreBrowseResults then
                C_AuctionHouse.RequestMoreBrowseResults()
            end
        end)
    else
        Finish()
    end
end

----------------------------------------------------------------
--  Public API — mirrors Replicate's so the façade can dispatch to either
----------------------------------------------------------------
function AH.Browse.IsScanning() return scanning end
function AH.Browse.Progress()   return progress end

-- Shared with Replicate on purpose; see Finish().
function AH.Browse.SecondsUntilReady()
    if AH.Replicate and AH.Replicate.SecondsUntilReady then
        return AH.Replicate.SecondsUntilReady()
    end
    return 0
end

-- opts.dry = true → observe and report without writing the price DB (/ah compare).
function AH.Browse.Start(opts)
    if not AH.isOpen then
        return false, "Open the Auction House first."
    end
    local C = C_AuctionHouse
    if not (C and C.SendBrowseQuery) then
        return false, "C_AuctionHouse.SendBrowseQuery unavailable."
    end
    if scanning then
        return false, "A scan is already running."
    end
    if AH.Replicate and AH.Replicate.IsScanning and AH.Replicate.IsScanning() then
        return false, "A replicate scan is already running."
    end

    dryRun = (opts and opts.dry) == true
    if not dryRun then
        local wait = AH.Browse.SecondsUntilReady()
        if wait > 0 then
            return false, format("Next scan available in %d:%02d.",
                floor(wait / 60), wait % 60)
        end
    end

    scanning  = true
    progress  = 0
    agg       = {}
    seenCount = 0
    pageCount = 0
    startedAt = GetTime()

    AH.Events.Fire("AH_SCAN_START")
    Enqueue(function()
        C_AuctionHouse.SendBrowseQuery({
            searchString     = "",
            sorts            = {},
            filters          = {},
            itemClassFilters = {},
        })
    end)
    AH.Events.Fire("AH_SCAN_REQUESTED")
    return true
end

-- Last dry-run aggregate, for /ah compare. Consumed by the caller.
function AH.Browse.TakeDryResult()
    local r = dryResult
    dryResult = nil
    return r
end

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
ef:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")

ef:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        -- Drain regardless of `scanning`: the queue is only ever populated by a scan,
        -- and draining a stale entry is harmless where stranding one is not.
        Drain()
        return
    end

    if not scanning then return end

    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
        if not ok or type(results) ~= "table" then return end
        -- ⚠ The size test is the batch-boundary discriminator, not an optimisation.
        -- This event also fires for the item-specific searches Blizzard's own UI runs
        -- while the AH is open; those return small sets and must not be folded into a
        -- full-scan aggregate as if they were the first page.
        if #results <= BATCH_SIZE then
            AddPrices(results)
            NextStep()
        end

    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        AddPrices(...)
        NextStep()

    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        Fail("the server refused the browse query")
    end
end)

-- A scan lives inside one AH session, exactly like Replicate's.
AH.Events.On("AH_CLOSED", function()
    if scanning then
        scanning, progress = false, 0
        agg, dryRun = nil, false
        ClearQueue()
        if VUI.debug then VUI.Print(AH.TAG, "Browse scan aborted (AH closed).") end
    else
        ClearQueue()
    end
end)

-- Exposed for the headless suite.
AH.Browse._AddPrices = AddPrices
AH.Browse._QueueLen  = function() return #queue end
