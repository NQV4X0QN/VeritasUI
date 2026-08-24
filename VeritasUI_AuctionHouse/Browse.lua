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
-- THE DEFAULT ENGINE (v1.12.12). Chosen because replicate fails the first scan of most
-- days -- the original complaint, unsolved for months -- while this path completed in
-- 10-15s on every attempt, priced 22,540 items against replicate's 15,828 in 55.9s, and
-- abandons no gear (replicate dropped 38-67% of gear rows on two measured scans).
--
-- ⚠ KNOWN DEFECT, shipped knowingly: minPrice is NOT the live lowest unit buyout. Measured
-- 2026-08-04, item 242639, one moment: Blizzard's ascending Sell-tab list showed the
-- cheapest listing at 29800; browse returned 27500. A minimum cannot sit below the cheapest
-- thing on sale. totalQuantity (79681 vs the tab's 79606) and the key were both right, so
-- the POPULATION is correct and only the PRICE lags -- probably a server-side cached
-- aggregate, unverified.
--
-- ⚠ SIZE IT BEFORE ACTING ON IT. The gap attributable to browse is ~7.7%. The 20-29% gaps
-- reported in use were mostly SCAN STALENESS (that commodity moved 41% in minutes) and
-- replicate would show the same. v1.12.11 reverted this engine on the conflated figure and
-- that was an over-correction; see the block above scanEngine in Tooltip.lua.
--
-- ⚠ Do not cite "/ah compare showed 98.2% commodity agreement" as evidence either way. It
-- is an average over a population dominated by items whose price had not moved, and it
-- concealed the failures on the ones that had -- the same report carried a 2:1 skew (1,400
-- lower vs 774 higher) that was the lag showing through and was dismissed as churn.
--
-- Use /ah browseprobe to check any single item against the game's own listing at the same
-- moment. That is the only tool that separates lag from staleness.


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
-- SKIP ACCOUNTING (v1.12.10). AddPrices used to drop three classes of result silently,
-- which meant this engine had NO coverage evidence at all — it replaced replicate's
-- MEASURED loss ("dropped: 10609", printed) with an unmeasured one. Two of these classes
-- are legitimate (nothing for sale / no buyout price); `noKey` is NOT, and is the one that
-- would represent real data loss on the default scan path.
local skipNoQty, skipNoPrice, skipNoKey = 0, 0, 0
local noKeyExamples        -- up to 5 itemIDs we could not key, for diagnosis
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
--  Blizzard browse-UI suppression
--
--  The scan's empty browse query is not private: the server REPLACES the shared
--  browse result set, and Blizzard's AuctionHouseBrowseResultsFrame — which renders
--  the Buy tab's list, INCLUDING the Favorites view (favorites are just a browse
--  search, C_AuctionHouse.SearchForFavorites) — re-reads that set on
--  AUCTION_HOUSE_BROWSE_RESULTS_UPDATED/ADDED (its OnEvent → UpdateBrowseResults →
--  GetBrowseResults, verified against wow-ui-source live 2026-08-23). Net effect:
--  clicking Scan visibly replaced the player's Favorites list with the entire
--  auction house streaming in.
--
--  While OUR scan is in flight, unregister those events on Blizzard's frame so its
--  Lua-side copy of the list (self.browseResults) is never repainted; on any scan
--  end (complete, fail, AH closed) re-register, and if the Favorites view was up,
--  re-issue the favorites search so the C-side result set matches the screen again.
--  The re-issue goes through the send queue: SearchForFavorites lives in the same
--  throttled-message system as browse queries, and the queue drains on
--  THROTTLED_SYSTEM_READY regardless of `scanning` (see the OnEvent note).
--
--  Deliberately NOT touched:
--    * AuctionHouseItemBuyFrame also registers ..._UPDATED, but only to refresh a
--      cosmetic refresh-button state (ItemList:UpdateRefreshFrame) — harmless.
--    * No Blizzard frame METHOD is called and no Blizzard table is written —
--      event-registration flips and a raw C_AuctionHouse call only. QueryAll /
--      SetDisplayMode would repaint "properly" but run Blizzard code from an
--      insecure path (the StaticPopupDialogs lesson, v1.12.5).
--
--  Known tradeoff: if the player had CATEGORY/search results up instead of
--  Favorites, those rows stay on screen (stale but intact) and are NOT re-queried —
--  strictly better than today's behaviour (list replaced by the full AH) without
--  replaying a search whose parameters live in Blizzard file-locals.
----------------------------------------------------------------
local BLIZZARD_BROWSE_EVENTS = {
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
}

local uiSuppressed     = false
local hadFavoritesView = false

local function SuppressBlizzardBrowseUI()
    local frame  = _G.AuctionHouseFrame
    local browse = frame and frame.BrowseResultsFrame
    if not browse then return end
    -- Captured at scan start. QueryItem / QueryAll / SendBrowseQueryInternal are
    -- the only writers of isDisplayingFavorites, and any of them running mid-scan
    -- means the player launched a competing query that clobbers the scan anyway.
    hadFavoritesView = frame.isDisplayingFavorites == true
    for _, ev in ipairs(BLIZZARD_BROWSE_EVENTS) do
        pcall(browse.UnregisterEvent, browse, ev)
    end
    uiSuppressed = true
end

local function RestoreBlizzardBrowseUI()
    if not uiSuppressed then return end
    uiSuppressed = false
    local frame  = _G.AuctionHouseFrame
    local browse = frame and frame.BrowseResultsFrame
    if browse then
        for _, ev in ipairs(BLIZZARD_BROWSE_EVENTS) do
            pcall(browse.RegisterEvent, browse, ev)
        end
    end
    local wasFavorites = hadFavoritesView
    hadFavoritesView = false
    if wasFavorites and AH.isOpen then
        Enqueue(function()
            local C = C_AuctionHouse
            if C and C.SearchForFavorites and AH.isOpen then
                -- Empty sorts = server default order; Blizzard's own sort list is a
                -- file-local and unreadable from here.
                C.SearchForFavorites({})
            end
        end)
    end
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
            -- ⚠ EVERY skip is counted. A silent skip on the default scan engine is
            -- indistinguishable from correct behaviour, which is exactly the hole this
            -- engine shipped with in v1.12.9.
            local _watch = AH.Browse._WatchResult
            if not (type(qty) == "number" and qty > 0) then
                if _watch then _watch(r, AH.DB.MakeKeyFromItemKey(r.itemKey), "SKIPPED: nothing for sale") end
                -- Legitimate: a listing with nothing actually available. Auctionator
                -- skips these too.
                skipNoQty = skipNoQty + 1
            elseif not (type(unit) == "number" and unit > 0) then
                if _watch then _watch(r, AH.DB.MakeKeyFromItemKey(r.itemKey), "SKIPPED: no buyout price") end
                -- Legitimate: bid-only, or no buyout. Replicate skips these as well, so
                -- both engines agree here.
                skipNoPrice = skipNoPrice + 1
            else
                local key = AH.DB.MakeKeyFromItemKey(r.itemKey)
                if _watch then _watch(r, key, key and "FOLDED" or "SKIPPED: unkeyable") end
                if not key then
                    -- ⚠ NOT legitimate — this is real data loss. Reachable when a gear
                    -- itemKey carries no usable itemLevel (MakeKeyFromItemKey refuses to
                    -- mint a bare i:<itemID> for gear, which design §2.4 forbids by
                    -- name), or when the itemKey is malformed. Capture examples so the
                    -- next step is a lookup, not a guess.
                    skipNoKey = skipNoKey + 1
                    if not noKeyExamples then noKeyExamples = {} end
                    if #noKeyExamples < 5 then
                        local id = type(r.itemKey) == "table" and r.itemKey.itemID
                        local lvl = type(r.itemKey) == "table" and r.itemKey.itemLevel
                        noKeyExamples[#noKeyExamples + 1] =
                            format("%s(ilvl %s)", tostring(id), tostring(lvl))
                    end
                else
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
    RestoreBlizzardBrowseUI()

    -- COVERAGE REPORT. Always printed, not debug-gated: this is the evidence that the
    -- default scan engine is not losing items, and it is worthless if it only appears
    -- when someone thought to enable logging. Two lines only when there is nothing
    -- alarming to say.
    local skipped = skipNoQty + skipNoPrice + skipNoKey
    if skipped > 0 then
        VUI.Print(AH.TAG, format(
            "  coverage: %d priced, %d skipped (%d nothing-for-sale, %d no-buyout, "
            .. "|cFF%s%d unkeyable|r)",
            seenCount, skipped, skipNoQty, skipNoPrice,
            skipNoKey > 0 and "FF4444" or "808080", skipNoKey))
    end
    if skipNoKey > 0 then
        -- Loud on purpose: an unkeyable result IS lost data, and this is the number that
        -- answers "is browse silently dropping items?" with evidence instead of a claim.
        VUI.Print(AH.TAG, format(
            "  |cFFFF4444%d result(s) could not be keyed and were NOT recorded.|r %s",
            skipNoKey,
            noKeyExamples and ("Examples: " .. table.concat(noKeyExamples, ", ")) or ""))
    end

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
    RestoreBlizzardBrowseUI()
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
    skipNoQty, skipNoPrice, skipNoKey = 0, 0, 0
    noKeyExamples = nil
    startedAt = GetTime()

    SuppressBlizzardBrowseUI()

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
    -- AH.isOpen is already false here, so this re-registers Blizzard's events
    -- without re-querying favorites — the frame must not stay deaf next session.
    RestoreBlizzardBrowseUI()
end)

----------------------------------------------------------------
--  /ah browseprobe — watch ONE item through a live browse scan
--
--  PERMANENT (promoted from a temporary probe in v1.12.11), for the same reason
--  /ah check and /qol ilvl are permanent: the question it answers recurs and cannot be
--  summoned on demand. A stored price disagreeing with the native AH has at least three
--  causes that are identical from outside -- browse priced it wrong; browse never
--  returned the item so the stored value is older; or the market moved -- and only the
--  raw API return separates them. This probe is ALSO the verification tool if browse is
--  ever considered for default again: it is what caught minPrice reading BELOW the
--  cheapest listing in existence (2026-08-04, item 242639, 27500 vs 29800).
--
--  Runs a DRY browse (writes nothing) and reports every browse result whose key matches
--  the watched item: raw minPrice, raw totalQuantity, the derived key, and whether the
--  result was skipped and why. Compare the reported minPrice against the lowest Unit
--  Price the native Sell tab is showing at that moment.
----------------------------------------------------------------
local watchKey, watchHits

function AH.Browse.SetWatch(key)
    watchKey, watchHits = key, {}
end

-- Called from AddPrices for every result, before any skip decision.
local function WatchResult(r, key, verdict)
    if not (watchKey and watchHits) then return end
    if key ~= watchKey then
        -- Also catch the case where the item is present but keys DIFFERENTLY than the
        -- tooltip does — which would be a key-derivation bug, not a price bug, and would
        -- otherwise look exactly like "browse never returned it".
        local id = type(r.itemKey) == "table" and r.itemKey.itemID
        local wantID = watchKey:match("^i:(%d+)")
        if not (wantID and id and tostring(id) == wantID) then return end
    end
    if #watchHits >= 8 then return end
    watchHits[#watchHits + 1] = format(
        "key=%s minPrice=%s qty=%s ilvl=%s species=%s -> %s",
        tostring(key),
        tostring(r.minPrice), tostring(r.totalQuantity),
        tostring(type(r.itemKey) == "table" and r.itemKey.itemLevel),
        tostring(type(r.itemKey) == "table" and r.itemKey.battlePetSpeciesID),
        verdict)
end

function AH.Browse.ReportWatch()
    if not watchKey then return end
    VUI.Print(AH.TAG, format("browseprobe for |cFFFFFF00%s|r:", watchKey))
    if not watchHits or #watchHits == 0 then
        VUI.Print(AH.TAG, "  |cFFFF4444browse returned NO result for this item.|r "
            .. "The stored price is therefore from an OLDER scan, not from this one — "
            .. "this is a COVERAGE gap, not a pricing error.")
    else
        for _, line in ipairs(watchHits) do
            VUI.Print(AH.TAG, "  " .. line)
        end
        VUI.Print(AH.TAG, "  Compare minPrice above against the lowest Unit Price the "
            .. "Sell tab is showing right now. If they differ, browse's minPrice is not "
            .. "the lowest unit buyout and the engine is wrong.")
    end
    local stored = AH.DB and AH.DB.GetMarketPrice(watchKey)
    VUI.Print(AH.TAG, format("  stored now: %s (age %s days)",
        stored and (AH.Money and AH.Money.Format(stored) or stored) or "none",
        tostring(AH.DB and AH.DB.GetPriceAge(watchKey))))
    watchKey, watchHits = nil, nil
end

-- Exposed for the headless suite.
AH.Browse._AddPrices = AddPrices
AH.Browse._Skips     = function() return skipNoQty, skipNoPrice, skipNoKey end
AH.Browse._QueueLen  = function() return #queue end

-- PROBE wiring: assigned after WatchResult exists so AddPrices resolves it at call time.
AH.Browse._WatchResult = WatchResult
