-- VeritasUI_AuctionHouse / Replicate.lua
-- Full-scan driver. The ONLY sanctioned whole-AH snapshot is
-- C_AuctionHouse.ReplicateItems() (design §2.2 — SendSearchQuery is capped at
-- 100/min and must NOT be used to scan).
--
-- Flow:
--   ReplicateItems() -> REPLICATE_ITEM_LIST_UPDATE -> read GetNumReplicateItems()
--   rows via GetReplicateItemInfo(i) + GetReplicateItemLink(i), fold into AH.DB.
--
-- CHUNKED (hard requirement, design §2.2): a snapshot can be 50k-200k+ rows.
-- Processing them in one synchronous loop freezes the client. We drive the row
-- loop from a coroutine resumed on an OnUpdate ticker, yielding after a time
-- budget per frame so the UI never hitches.
--
-- Per-row policy:
--   * key  = AH.DB.MakeKey(link)  (gear keyed by itemID:ilvl, pets by speciesID,
--            everything else by itemID — design §2.2/§2.4)
--   * skip bid-only rows (buyoutPrice == 0): the DB tracks buyout market price
--   * unitPrice = floor(buyoutPrice / count) so stacks/commodities normalize
--   * aggregate per key within a scan: keep the min unit price + max qty seen,
--     then write once per key at the end (one DB.Record call per item, not per row)
--
-- Scan floor: Blizzard/-server throttle replicate heavily; we enforce a 15-min
-- minimum between scans (design §2.2), persisted across sessions.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local C_AuctionHouse = C_AuctionHouse
local floor      = math.floor
local format     = string.format
local time       = time
local GetTime    = GetTime
local coroutine  = coroutine
local CreateFrame = CreateFrame

AH.Replicate = {}

local SCAN_FLOOR_SECONDS    = 15 * 60   -- minimum gap between full scans
local ROWS_PER_SLICE        = 2000      -- safety cap on rows per frame
local FRAME_BUDGET_MS       = 8         -- ~8ms/frame work budget (debugprofilestop)
local REPLICATE_RETRY_DELAY = 60        -- seconds to wait for REPLICATE_ITEM_LIST_UPDATE before retrying.
                                        -- MUST sit above the measured healthy first-event latency (~28-40s,
                                        -- probe ref §5 2026-06-27 + confirmed 26.5s on 2026-07-02 and 23.9s on
                                        -- 2026-07-11): at the old 10s this fired a mislabeled "request was
                                        -- dropped" duplicate on EVERY healthy scan, muddying each trace. At 60s,
                                        -- one request producing zero events within the window is an unambiguous
                                        -- drop. Since v1.9.5 the retry is PERSISTENT (re-arms after each
                                        -- re-fire) — see ArmRetry for the measurement that forced this.
local LINK_RETRY_WAIT       = 3         -- seconds between link retry passes (lets queued
                                        -- item-record loads stream in; cold-cache coverage fix)
local LINK_RETRY_BUDGET     = 45        -- hard cap (seconds) on the whole retry phase. Records
                                        -- stream at ~1k/3s (measured 2026-07-02), so ~15k gear
                                        -- rows need ~45s worst case. The phase also self-stops
                                        -- on the first pass that resolves nothing (quiescence),
                                        -- so the cap only binds while progress is still being made.
local scanning   = false   -- a scan coroutine is in progress
local co                    -- the active coroutine
local driver               -- OnUpdate ticker frame
local finder               -- OnUpdate ticker frame for /ah find, reused across calls
local progress   = 0        -- 0..1
local retryTimer            -- C_Timer handle watching for a dropped ReplicateItems()
local fireTime              -- GetTime() at the moment ReplicateItems() was issued
local finalizeResolved      -- live counters for the gear-residue retry phase;
local finalizeTotal         -- nil outside the phase (backs FinalizeStatus())
local firstEventLogged      -- per-scan guard: trace only the FIRST event pulse, not every chunk
local trace                 -- ALWAYS-ON diagnostic record of the current/most-recent scan
                            -- attempt chain (v1.9.5). The 2026-07-11 hang went dark because
                            -- the only instrumentation was debug-gated prints and debug was
                            -- off during the rare repro. This table records regardless of
                            -- VUI.debug; /ah diag dumps it. Fields:
                            --   startedAt         time() at first fire of the chain
                            --   firedAt           GetTime() of the LATEST fire (elapsed math)
                            --   attempts          total ReplicateItems() calls in the chain
                            --                     (auto re-fires AND manual Retry clicks —
                            --                     a manual retry on a still-hung request
                            --                     CONTINUES the chain, see DoFire)
                            --   pulses            REPLICATE_ITEM_LIST_UPDATE events seen
                            --   firstEventLatency GetTime()-firedAt at the first pulse
                            --   firstEventAttempt which attempt the first pulse followed
                            --   outcome           "requesting" | "processing" | "complete"
                            --                     | "failed" | "aborted"
                            --   committed, rows, totalTime   set on completion
local mainCommit            -- { kept, rows } once the phase-1 commit lands (set in
                            -- ProcessAllRows); nil until then. Lets the driver
                            -- distinguish a pre-commit failure (nothing durable →
                            -- AH_SCAN_FAILED) from a finalize-phase failure (main
                            -- results committed + scan floor running → report the
                            -- committed result; only late gear residue was lost).

----------------------------------------------------------------
--  Scan lifecycle — why there is NO timeout (do not re-add one)
--
--  ReplicateItems() -> REPLICATE_ITEM_LIST_UPDATE can take a long, UNBOUNDED
--  time: the snapshot is 8k-270k+ rows, and the request may sit QUEUED behind
--  the throttle system before the server even begins assembling it. Delivery
--  time has no fixed upper bound, so a fixed-timeout "watchdog" cannot tell
--  "lost forever" from "still coming" — it can only race a slow-but-successful
--  scan and kill it. A 45s watchdog (added v1.7.1) did exactly that: it
--  discarded scans whose data arrived a few seconds later, which is what made
--  scanning fail roughly half the time.
--
--  The proven model (what Auctionator does) is: NO timeout. Fire the request,
--  wait for the event however long it takes, process it when it lands.
--
--  The only real risk — `scanning` left stuck true if the event genuinely never
--  comes in a session — is handled WITHOUT a failure timer: a scan only lives
--  within one AH session, so we reset the flag on AH open and AH close (see the
--  AH_OPEN / AH_CLOSED handlers below). A fresh AH session can therefore always
--  start a new scan, with no false "already running" and no false "scan failed".
----------------------------------------------------------------

----------------------------------------------------------------
--  Scan-floor bookkeeping (persisted)
----------------------------------------------------------------
local function LastScanTime()
    return (AH.db and AH.db.lastScan) or 0
end

local function SetLastScanTime(t)
    if AH.db then AH.db.lastScan = t end
end

-- Seconds remaining before another scan is permitted (0 = ready).
function AH.Replicate.SecondsUntilReady()
    local elapsed = time() - LastScanTime()
    local remaining = SCAN_FLOOR_SECONDS - elapsed
    return remaining > 0 and remaining or 0
end

function AH.Replicate.IsScanning()
    return scanning
end

function AH.Replicate.Progress()
    return progress
end

-- Live finalize-phase counters: (resolved, total) while the gear-residue retry
-- phase runs, nil otherwise. Read by the ScanProgress label so the user sees
-- real movement ("Finalizing gear… 2,980/14,682") instead of a static phase
-- name. Deliberately NOT folded into Progress()'s 0..1: the residue total is
-- unknown until the main drain ends, and the phase can end early (quiescence /
-- budget) — a merged percentage would stall or jump. Honest counts instead.
function AH.Replicate.FinalizeStatus()
    if finalizeTotal then
        return finalizeResolved or 0, finalizeTotal
    end
end

-- The always-on scan trace (see the `trace` declaration for the field list).
-- Read by /ah diag (Core.lua) and the ScanProgress attempt counter. May be nil
-- (no scan attempted this session). Treat as read-only.
function AH.Replicate.LastTrace()
    return trace
end

----------------------------------------------------------------
--  Snapshot search — DIAGNOSTIC (/ah find <shift-clicked item link>)
--
--  Sweeps the LAST replicate snapshot still in client memory for rows matching
--  a target itemID (by link, falling back to exact name for rows whose link is
--  nil), and prints what the scan actually saw for that item: row index, count,
--  buyoutPrice, link-resolved?, derived key. Purpose: discriminate the stale-
--  tooltip classes — "item absent from snapshot" (server-side omission) vs
--  "present but skipped" (nil link / bid-only / zero unit) — instead of
--  inferring from silence. Chunked on a reused driver frame so a 270k-row
--  sweep never hitches the client. Run it right after a scan completes.
----------------------------------------------------------------
local MAX_FIND_PRINTS = 10   -- per-row print cap; the summary still counts all
function AH.Replicate.FindInSnapshot(targetItemID, targetName)
    if scanning then
        return false, "A scan is running — try again after it completes."
    end
    -- One sweep at a time. The driver frame is shared across calls now, so a
    -- second sweep would replace the first one's OnUpdate and abandon it partway
    -- with no summary printed. Refuse instead of losing it silently.
    if finder and finder:GetScript("OnUpdate") then
        return false, "A /ah find sweep is already running — wait for its summary."
    end
    local num = C_AuctionHouse.GetNumReplicateItems() or 0
    if num == 0 then
        return false, "No replicate snapshot in memory — run a scan first, then /ah find again."
    end

    local i, found, nilLinks, printed = 0, 0, 0, 0
    local totalQty = 0
    -- Created once and reused, same as EnsureDriver's scan driver: WoW frames
    -- cannot be destroyed, so a per-call frame stayed alive for the session. The
    -- per-sweep counters remain locals captured by a fresh closure each call, so
    -- there is no shared mutable state to reset or clobber.
    if not finder then finder = CreateFrame("Frame") end
    finder:SetScript("OnUpdate", function(self)
        local sliceStart = debugprofilestop()
        while i < num and (debugprofilestop() - sliceStart) < FRAME_BUDGET_MS do
            pcall(function()
                local _, _, count, _, _, _, _, _, _, buyoutPrice =
                    C_AuctionHouse.GetReplicateItemInfo(i)
                local link = C_AuctionHouse.GetReplicateItemLink(i)
                local isMatch = false
                if link then
                    isMatch = (tonumber(link:match("|Hitem:(%d+)")) == targetItemID)
                else
                    nilLinks = nilLinks + 1
                    -- Cold row: match via the position calibrated by the last scan.
                    local pos = AH.Replicate._itemIDPos
                    if pos then
                        isMatch = (select(pos, C_AuctionHouse.GetReplicateItemInfo(i))
                                   == targetItemID)
                    end
                end
                if isMatch then
                    found = found + 1
                    totalQty = totalQty + (count or 0)
                    if printed < MAX_FIND_PRINTS then
                        printed = printed + 1
                        VUI.Print(AH.TAG, format(
                            "  row %d: count=%s buyout=%s link=%s key=%s",
                            i, tostring(count), tostring(buyoutPrice),
                            link and "ok" or "|cFFFF4444NIL|r",
                            tostring(link and AH.DB.MakeKey(link)
                                or AH.DB.MakeKeyFromItemID(targetItemID))))
                    end
                end
            end)
            i = i + 1
        end
        if i >= num then
            self:SetScript("OnUpdate", nil)
            VUI.Print(AH.TAG, format(
                "/ah find: swept %d rows — |cFFFFFF00%d|r matching rows (total qty %d) "
                .. "for itemID %s; snapshot-wide nil links: |cFFFFFF00%d|r",
                num, found, totalQty, tostring(targetItemID), nilLinks))
            if found == 0 then
                VUI.Print(AH.TAG, "  → item is |cFFFF4444ABSENT from the snapshot|r "
                    .. "(server-side omission, not a row-skip in our scan).")
            end
        end
    end)
    -- Explicit, not relying on a fresh frame's default shown state: OnUpdate only
    -- fires while the frame is visible, and this one now outlives a single sweep.
    finder:Show()
    return true
end

----------------------------------------------------------------
--  The chunked row processor (coroutine body)
----------------------------------------------------------------
local function ProcessAllRows()
    local num = C_AuctionHouse.GetNumReplicateItems() or 0
    if num == 0 then
        return 0, 0
    end
    local initialNum = num   -- for the grew-mid-drain debug report

    -- Per-scan aggregate: key -> { unit = minUnitPrice, qty = maxQty }.
    local agg = {}
    local kept = 0

    local function Fold(key, unit, count)
        local a = agg[key]
        if not a then
            agg[key] = { unit = unit, qty = count }
            kept = kept + 1
        else
            if unit < a.unit then a.unit = unit end
            a.qty = a.qty + count
        end
    end

    -- Cold-cache row coverage (2026-07-02): ~144k of ~270k rows have nil links at
    -- scan time and were historically skipped — over half the AH unpriced.
    --
    -- ITEMID POSITION AUTO-CALIBRATION: the documented GetReplicateItemInfo
    -- signature (itemID at return 15) is WRONG on this client (verified in-game
    -- 2026-07-02: position 15 is not a number on any row). Rather than trust any
    -- documented position, discover it live: for the first CALIB_ROWS_NEEDED rows
    -- whose link DOES resolve, extract the itemID from the link and record which
    -- return positions (11+) hold that exact number. A position that matches on
    -- ~every sample is the real itemID slot. If none wins, itemIDPos stays nil
    -- and cold rows rely purely on the retry passes below.
    local itemIDPos          -- calibrated return position of itemID, or nil
    local calibrated = false
    local calibSamples = {}  -- [position] = hit count
    local calibRows = 0
    local CALIB_ROWS_NEEDED = 20

    local nilLinkKeyed = 0   -- non-gear rows priced via calibrated itemID
    local deferred     = {}  -- { row = i, id = itemID|nil } awaiting a link (gear / uncalibrated)
    local requestedIDs = {}  -- itemIDs already sent to RequestLoadItemDataByID (dedupe:
                             -- many rows share an itemID; one load request serves them all)

    local sliceStart = debugprofilestop()
    local sliceCount = 0

    -- CHUNK-TAIL GUARD (2026-07-02): Blizzard streams the snapshot in chunks,
    -- firing REPLICATE_ITEM_LIST_UPDATE once per chunk — but we start draining at
    -- the FIRST pulse, so GetNumReplicateItems() read once here can be a PARTIAL
    -- count. The old `for i = 0, num-1` froze that count and silently dropped any
    -- rows that streamed in during the multi-second drain: a systematic tail of
    -- never-priced items (observed 2026-07-02: an item with 352 live buyout units
    -- absent from a 270k-row scan → stale tooltip). The while-loop re-checks the
    -- live count at the boundary and keeps draining while the snapshot grows.
    local i = 0
    while i < num do
        -- Per-row read is pcall-isolated: a single malformed row (a secret value,
        -- a bad link, an itemInfo throw) is SKIPPED, not fatal to the whole scan.
        -- This is distinct from the documented cold-cache nil-link case (§2.2),
        -- which already degrades gracefully by skipping; this guards against an
        -- actual error propagating out of coroutine.resume and discarding a
        -- 50k-200k-row snapshot over one bad row.
        pcall(function()
            -- GetReplicateItemInfo positional returns, verified through 10 (§2.2):
            -- name, texture, count, qualityID, usable, level, levelType, minBid,
            -- minIncrement, buyoutPrice, ... (positions past 10 vary by client —
            -- see the auto-calibration above; do NOT hardcode an itemID position).
            local _, _, count, _, _, _, _, _, _, buyoutPrice = C_AuctionHouse.GetReplicateItemInfo(i)
            count = count or 1
            buyoutPrice = buyoutPrice or 0

            -- Skip bid-only auctions (no buyout) — DB tracks buyout market price.
            if buyoutPrice > 0 and count > 0 then
                local unit = floor(buyoutPrice / count)
                if unit > 0 then
                    local link = C_AuctionHouse.GetReplicateItemLink(i)
                    if link then
                        -- Calibration sampling: which return position holds the
                        -- itemID we can independently read from this row's link?
                        -- Own pcall: a secret-value comparison error here must not
                        -- abort this row's Fold below.
                        if not calibrated then pcall(function()
                            local linkID = tonumber(link:match("|Hitem:(%d+)"))
                            if linkID then
                                local rets = { C_AuctionHouse.GetReplicateItemInfo(i) }
                                for p = 11, #rets do
                                    if rets[p] == linkID then
                                        calibSamples[p] = (calibSamples[p] or 0) + 1
                                    end
                                end
                                calibRows = calibRows + 1
                                if calibRows >= CALIB_ROWS_NEEDED then
                                    calibrated = true
                                    local best, bestN
                                    for p, n in pairs(calibSamples) do
                                        if not bestN or n > bestN then best, bestN = p, n end
                                    end
                                    -- Consensus: winner must have hit on ~every sample
                                    -- (coincidental matches — e.g. a bidAmount equal to
                                    -- an itemID — can't sustain 90% across 20 rows).
                                    if best and bestN >= CALIB_ROWS_NEEDED * 0.9 then
                                        itemIDPos = best
                                    end
                                    -- Expose for /ah find (matches cold rows the same way).
                                    AH.Replicate._itemIDPos = itemIDPos
                                    if VUI.debug then
                                        VUI.Print(AH.TAG, "itemID position calibration: "
                                            .. (itemIDPos and ("return #" .. itemIDPos)
                                                or "|cFFFF4444no consensus|r — cold rows use retry passes only"))
                                    end
                                end
                            end
                        end) end
                        local key = AH.DB.MakeKey(link)
                        if key then Fold(key, unit, count) end
                    else
                        -- COLD-CACHE ROW (~half the snapshot, diagnosed 2026-07-02).
                        -- If calibration found the itemID slot, non-gear rows are
                        -- keyed right now (their key never needed the link). Gear —
                        -- or anything unresolvable — is deferred to the retry passes:
                        -- the GetReplicateItemLink call above queues a background
                        -- record load that typically lands within seconds.
                        local rowItemID = itemIDPos
                            and select(itemIDPos, C_AuctionHouse.GetReplicateItemInfo(i))
                        local key = (type(rowItemID) == "number")
                            and AH.DB.MakeKeyFromItemID(rowItemID) or nil
                        if key then
                            nilLinkKeyed = nilLinkKeyed + 1
                            Fold(key, unit, count)
                        else
                            local id = (type(rowItemID) == "number") and rowItemID or nil
                            deferred[#deferred + 1] = { row = i, id = id }
                            if id and not requestedIDs[id]
                               and C_Item and C_Item.RequestLoadItemDataByID then
                                requestedIDs[id] = true
                                pcall(C_Item.RequestLoadItemDataByID, id)
                            end
                        end
                    end
                end
            end
        end)

        -- Progress + frame-budget yield. Kept OUTSIDE the per-row pcall so the
        -- yield cadence is unaffected by a skipped row. `progress` backs the
        -- polled AH.Replicate.Progress() accessor (read by /ah diag).
        sliceCount = sliceCount + 1
        if sliceCount >= ROWS_PER_SLICE
           or (debugprofilestop() - sliceStart) >= FRAME_BUDGET_MS then
            progress = (i + 1) / num
            coroutine.yield()
            sliceStart = debugprofilestop()
            sliceCount = 0
        end

        i = i + 1
        -- Boundary re-check: pick up rows from chunks that arrived mid-drain.
        -- Growth is bounded (the server stops streaming once the snapshot is
        -- complete), so this cannot loop forever.
        if i >= num then
            local now = C_AuctionHouse.GetNumReplicateItems() or 0
            if now > num then num = now end
        end
    end

    if VUI.debug and num ~= initialNum then
        VUI.Print(AH.TAG, format(
            "snapshot grew mid-drain: %d rows at first pulse -> %d processed "
            .. "(chunk tail caught; pre-fix these %d rows were dropped)",
            initialNum, num, num - initialNum))
    end

    ----------------------------------------------------------------
    --  COMMIT PHASE 1 — main results, BEFORE the gear retry phase.
    --
    --  Committing early makes the 270k-row result durable the moment the drain
    --  finishes: if the AH closes during the (possibly 45s) retry phase below,
    --  the whole scan is no longer discarded with it — only the late gear
    --  residue is lost. Chunked like everything else.
    ----------------------------------------------------------------
    local day = AH.DB.Today()
    local function CommitKeys(keySet)
        -- keySet=nil commits ALL of agg; otherwise just the listed keys.
        -- AH.DB.Record is an upsert (per-day min/max fold), so re-committing a
        -- key later with its improved (lower-min) aggregate is safe and correct.
        sliceStart = debugprofilestop()
        sliceCount = 0
        local n = 0
        for key in pairs(keySet or agg) do
            local a = agg[key]
            if a then
                AH.DB.Record(key, a.unit, a.qty, day)
                n = n + 1
            end
            sliceCount = sliceCount + 1
            if sliceCount >= ROWS_PER_SLICE
               or (debugprofilestop() - sliceStart) >= FRAME_BUDGET_MS then
                coroutine.yield()
                sliceStart = debugprofilestop()
                sliceCount = 0
            end
        end
        return n
    end
    CommitKeys(nil)
    -- Main results are durable — start the scan floor NOW, not at coroutine end.
    -- If the AH closes during the retry phase below, the scan still "happened":
    -- without this, an abort mid-finalize would leave no cooldown and invite an
    -- immediate re-scan straight into the server's own replicate throttle.
    SetLastScanTime(time())
    -- Mark the commit for the driver's error path (see mainCommit declaration).
    mainCommit = { kept = kept, rows = num }

    ----------------------------------------------------------------
    --  RETRY PHASE — gear rows whose link was uncached on the main sweep.
    --
    --  The main drain's link calls + RequestLoadItemDataByID queued background
    --  record loads, which stream in at roughly ~1k records / 3s (measured
    --  2026-07-02: 2,980 of 14,682 resolved across three 3s passes — fixed pass
    --  counts are the wrong shape for a rate-limited stream). So: keep passing
    --  WHILE passes make progress, re-requesting stragglers each pass, and stop
    --  on quiescence (a pass in which not one row's link came back — the stream
    --  is dry) or on the hard budget (scan must terminate). Resolved keys are
    --  committed incrementally after each pass, so even an abort mid-phase keeps
    --  them. NOTE: "resolves nothing" means nothing LEFT THE PILE, not nothing
    --  was folded — see the two-counter comment in the pass loop below.
    ----------------------------------------------------------------
    local deferredTotal = #deferred
    local retryResolved = 0   -- rows whose link came back (NOT the fold count)
    local retryPasses   = 0
    if deferredTotal > 0 then
        -- Tell the progress UI we've entered the finalize phase (main results
        -- are already committed and usable; this is gear residue resolution).
        finalizeResolved, finalizeTotal = 0, deferredTotal
        AH.Events.Fire("AH_SCAN_FINALIZING", deferredTotal)
        local retryStart = GetTime()
        while #deferred > 0
              and (GetTime() - retryStart) < LINK_RETRY_BUDGET do
            retryPasses = retryPasses + 1
            local deadline = GetTime() + LINK_RETRY_WAIT
            while GetTime() < deadline do
                coroutine.yield()
            end
            local remaining   = {}
            local lateTouched = {}   -- keys folded this pass -> recommit below
            -- TWO counters, deliberately. A row leaves the pile the moment its
            -- link resolves, but only a subset of resolved rows are FOLDED into
            -- the aggregate (bid-only, zero count, unit 0 and nil-key rows are
            -- legitimately skipped). The two quantities drive two different
            -- decisions and one counter cannot serve both: passResolved gates
            -- CommitKeys (calling it with an empty set is pointless), while
            -- passTouched gates the quiescence break (a pass can drain rows
            -- without folding any, and that is NOT a dry stream).
            local passResolved = 0   -- rows folded into the aggregate this pass
            local passTouched  = 0   -- rows that left the pile this pass
            sliceStart = debugprofilestop()
            sliceCount = 0
            for d = 1, #deferred do
                local ent = deferred[d]
                local resolved = false
                pcall(function()
                    local link = C_AuctionHouse.GetReplicateItemLink(ent.row)
                    if link then
                        resolved = true   -- link is back; row leaves the pile
                        local _, _, count, _, _, _, _, _, _, buyoutPrice =
                            C_AuctionHouse.GetReplicateItemInfo(ent.row)
                        count = count or 1
                        buyoutPrice = buyoutPrice or 0
                        if buyoutPrice > 0 and count > 0 then
                            local key = AH.DB.MakeKey(link)
                            local unit = floor(buyoutPrice / count)
                            if key and unit > 0 then
                                Fold(key, unit, count)
                                lateTouched[key] = true
                                passResolved = passResolved + 1
                            end
                        end
                    elseif ent.id and C_Item and C_Item.RequestLoadItemDataByID then
                        -- Still cold — nudge the loader again for the next pass.
                        pcall(C_Item.RequestLoadItemDataByID, ent.id)
                    end
                end)
                if not resolved then
                    remaining[#remaining + 1] = ent
                else
                    passTouched = passTouched + 1
                    -- Live counter for the ScanProgress label. Counted here, on
                    -- resolution, so the numerator measures the same population
                    -- as the denominator (deferredTotal = rows deferred, not
                    -- rows eligible to fold). Counting folds instead meant the
                    -- label could never reach its own total even on a pass that
                    -- fully drained the pile. The denominator is NOT the side to
                    -- change: whether a row is bid-only is unknowable until its
                    -- link resolves.
                    finalizeResolved = (finalizeResolved or 0) + 1
                end
                sliceCount = sliceCount + 1
                if sliceCount >= ROWS_PER_SLICE
                   or (debugprofilestop() - sliceStart) >= FRAME_BUDGET_MS then
                    coroutine.yield()
                    sliceStart = debugprofilestop()
                    sliceCount = 0
                end
            end
            deferred = remaining
            retryResolved = retryResolved + passTouched
            if passResolved > 0 then
                CommitKeys(lateTouched)   -- durable immediately, upsert-safe
            end
            if passTouched == 0 then
                -- Quiescent pass: not one row left the pile, so the loader
                -- stream really is dry. Previously this tested the FOLD count,
                -- which abandoned the remaining pile whenever a pass resolved
                -- only skip-worthy rows — ordinary for a small bid-only tail,
                -- while the stream was demonstrably still delivering.
                break
            end
        end
    end

    finalizeResolved, finalizeTotal = nil, nil   -- phase over; FinalizeStatus() goes dark

    if VUI.debug then
        VUI.Print(AH.TAG, format(
            "row coverage: %d rows — cold rows keyed via itemID (pos %s): %d; "
            .. "link-retried: %d of %d resolved over %d pass(es); dropped: %d",
            num, tostring(itemIDPos), nilLinkKeyed,
            retryResolved, deferredTotal, retryPasses, #deferred))
    end

    return kept, num
end

----------------------------------------------------------------
--  Coroutine driver (resumes the processor each frame until done)
----------------------------------------------------------------
local function EnsureDriver()
    if driver then return driver end
    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        if not co then driver:Hide(); return end
        local ok, a, b = coroutine.resume(co)
        if not ok then
            -- Coroutine errored — abort cleanly.
            scanning = false
            co = nil
            driver:Hide()
            finalizeResolved, finalizeTotal = nil, nil
            if mainCommit then
                -- The error hit AFTER the phase-1 commit (gear-residue
                -- finalize path): the main scan is durable and the 15-min
                -- floor is already running, so "Scan failed — try again
                -- shortly" would be false on both counts. Report the
                -- committed result; only late gear residue was lost.
                progress = 1
                if trace then
                    trace.outcome   = "complete"
                    trace.committed = mainCommit.kept
                    trace.rows      = mainCommit.rows
                    trace.totalTime = fireTime and (GetTime() - fireTime) or nil
                end
                if VUI.debug then
                    VUI.Print(AH.TAG, "|cFFFF8800Finalize-phase error|r "
                        .. "(main results already committed): " .. tostring(a))
                end
                AH.Events.Fire("AH_SCAN_COMPLETE", mainCommit.kept, mainCommit.rows)
            else
                if trace then trace.outcome = "failed" end
                if VUI.debug then
                    VUI.Print(AH.TAG, "|cFFFF4444Scan error|r: " .. tostring(a))
                end
                AH.Events.Fire("AH_SCAN_FAILED", tostring(a))
            end
            return
        end
        if coroutine.status(co) == "dead" then
            -- Finished. a = committed count, b = rows scanned.
            scanning = false
            co = nil
            driver:Hide()
            progress = 1
            SetLastScanTime(time())
            if trace then
                trace.outcome   = "complete"
                trace.committed = a or 0
                trace.rows      = b or 0
                trace.totalTime = fireTime and (GetTime() - fireTime) or nil
            end
            AH.Events.Fire("AH_SCAN_COMPLETE", a or 0, b or 0)
            -- DEBUG (debug-gated): total scan time = fire -> drain complete. Pairs with
            -- the time-to-first-event trace in the event handler. Together they separate
            -- "slow to start" (server/readiness) from "slow to drain" (dataset size), so
            -- the retry threshold is set off first-event latency, never total time.
            if VUI.debug and fireTime then
                VUI.Print(AH.TAG, format("scan complete: %d committed / %d rows, total=%.1fs",
                    a or 0, b or 0, GetTime() - fireTime))
            end
        end
    end)
    return driver
end

----------------------------------------------------------------
--  DoFire — the ONE fire path (v1.8.0)
--
--  History (see git: v1.7.9 FireWhenReady, f484993 browse gate, 7965944 settle):
--  the first-open-of-session hang drove three generations of pre-fire gates —
--  throttle-readiness, a cold-edge settle delay, and a browse-readiness wait.
--  All were falsified or superseded in-game: [FIRE STATE] captured
--  throttleReady=true AND hasFullBrowse=true on a fresh login's first open
--  (2026-07-02), and the AH is fully usable during a hang, so no client-side
--  readiness signal distinguishes a doomed request from a good one. v1.8.0
--  removed auto-scan-on-open (the failing context) entirely; every scan is now
--  user-initiated and fires DIRECTLY and SYNCHRONOUSLY from its trigger —
--  the Scan button's OnClick (hardware-event stack, Auctionator's model) or
--  /ah scan. Do not reintroduce a deferred/gated fire path.
----------------------------------------------------------------
local function CancelRetry()
    if retryTimer then
        retryTimer:Cancel()
        retryTimer = nil
    end
end

----------------------------------------------------------------
--  ArmRetry — PERSISTENT re-fire (v1.9.5; replaces the one-shot retry)
--
--  Why persistent: 2026-07-11, first login after 6 idle days — the server
--  silently dropped every ReplicateItems() for ~12 minutes (numReplicate=0 at
--  each later fire proved nothing was ever assembled), then accepted one and
--  delivered a textbook-healthy scan (first pulse 23.9s, 255,990 rows). The
--  one-shot retry fired once at 60s and then gave up FOREVER — the addon sat
--  silent for the remaining ~11 minutes while the user's manual Retry clicks
--  did the job this timer should have done. Client-side gating cannot help:
--  throttleReady/hasFullBrowse read true at both failing and working fires
--  (measured 2026-07-02 AND 2026-07-11). The only strategy that works is to
--  keep asking until the server says yes.
--
--  Duplicate fires are proven safe: the v1.7.9 10s timer fired a duplicate on
--  every healthy scan for weeks with no harm, and the 2026-07-11 success came
--  4 minutes after a prior (dropped) fire — requests don't reset each other.
--
--  Unbounded BY DESIGN, same reasoning as the no-timeout rule above: a cap
--  would just recreate the "gave up N seconds before the server recovered"
--  failure at a different N. The chain lives only while the AH session does —
--  every re-fire re-checks (AH open, scanning, no coroutine), AH_CLOSED
--  cancels the timer, and a refused request is a server-side no-op, so an
--  abandoned-open-AH worst case is one dropped packet per minute.
----------------------------------------------------------------
local function ArmRetry()
    CancelRetry()
    retryTimer = C_Timer.NewTimer(REPLICATE_RETRY_DELAY, function()
        retryTimer = nil
        -- Only re-fire if: AH still open, scan flag still set, but the coroutine
        -- never started. co ~= nil means data arrived and we're processing.
        if not AH.isOpen or not scanning or co then return end
        if trace then
            trace.attempts = (trace.attempts or 1) + 1
            trace.firedAt  = GetTime()
        end
        if VUI.debug then
            VUI.Print(AH.TAG, format("REPLICATE_ITEM_LIST_UPDATE not received after %ds "
                .. "— request was dropped; re-firing ReplicateItems() (attempt %d)",
                REPLICATE_RETRY_DELAY, trace and trace.attempts or 0))
        end
        C_AuctionHouse.ReplicateItems()
        ArmRetry()   -- persistent: keep the chain alive until data arrives or the AH closes
    end)
end

local function DoFire()
    scanning = true          -- set ONLY here, at the real fire moment
    fireTime = GetTime()     -- stamp for first-event / total-scan latency measurement
    firstEventLogged = false -- re-arm the one-line-per-scan trace for this attempt
    mainCommit = nil         -- no durable commit yet for THIS attempt
    -- Trace chain continuity: a manual Retry click on a still-hung request
    -- (outcome "requesting" — no data ever arrived) CONTINUES the existing
    -- chain, so /ah diag shows the full history of a hang across user retries.
    -- Anything else (fresh scan, or a scan that reached data) starts a new chain.
    if trace and trace.outcome == "requesting" then
        trace.attempts = (trace.attempts or 1) + 1
        trace.firedAt  = GetTime()
    else
        trace = {
            startedAt = time(),
            firedAt   = GetTime(),
            attempts  = 1,
            pulses    = 0,
            outcome   = "requesting",
        }
    end
    -- FIRE-MOMENT STATE SNAPSHOT: capture the observable AH API state at the exact instant
    -- we issue ReplicateItems(). Compare a FAILING cold open vs the WORKING reopen right
    -- after — whatever field differs is the "something different on first open". This is
    -- the measurement, not a fix. All calls are guarded (APIs may be absent/erroring).
    if VUI.debug then
        local C = C_AuctionHouse or {}
        local function safe(fn) local ok, v = pcall(fn); return ok and v or "?" end
        VUI.Print(AH.TAG, format(
            "[FIRE STATE] throttleReady=%s hasFullBrowse=%s numReplicate=%s numOwned=%s",
            tostring(safe(function() return C.IsThrottledMessageSystemReady and C.IsThrottledMessageSystemReady() end)),
            tostring(safe(function() return C.HasFullBrowseResults and C.HasFullBrowseResults() end)),
            tostring(safe(function() return C.GetNumReplicateItems and C.GetNumReplicateItems() end)),
            tostring(safe(function() return C.GetNumOwnedAuctions and C.GetNumOwnedAuctions() end))
        ))
    end
    C_AuctionHouse.ReplicateItems()
    -- Phase marker for the progress UI: the request has gone out, so the bar can
    -- leave "Connecting…" and enter the snapshot wait (ScanProgress listens).
    AH.Events.Fire("AH_SCAN_REQUESTED")
    if VUI.debug then
        VUI.Print(AH.TAG, "ReplicateItems() fired")
    end
    -- Arm the persistent retry chain: if REPLICATE_ITEM_LIST_UPDATE doesn't
    -- arrive within REPLICATE_RETRY_DELAY seconds the request was silently
    -- dropped by the server (a dropped request produces NO event at all), so
    -- ArmRetry re-fires and re-arms until data arrives or the AH closes.
    -- This is NOT a watchdog: it only fires while co is still nil (coroutine
    -- never started). If the event arrives first (normal path), CancelRetry()
    -- in the event handler defuses the chain immediately.
    ArmRetry()
end

----------------------------------------------------------------
--  Start():  the ONE scan entry point (v1.8.0 — gates stripped)
--
--  Fires DIRECTLY and SYNCHRONOUSLY from whatever called it. From the Scan
--  button's OnClick that preserves the hardware-event execution context all the
--  way to ReplicateItems() (Auctionator's model — its click-fired scan never
--  exhibited the first-open hang). /ah scan takes the identical path.
--
--  The 15-min floor is ALWAYS honored (no force override — bypassing it fires
--  ReplicateItems into the server's own cooldown, a silent no-op that looks
--  like a failure).
--
--  Recovers a hung scan: if a prior fire this session left `scanning` true with
--  no coroutine (co == nil) — the fired-but-never-arrived state — clear it and
--  fire fresh. A scan actively draining rows (co ~= nil) is NOT interrupted.
--  Returns true if a scan was fired, false + reason otherwise.
----------------------------------------------------------------
function AH.Replicate.Start()
    if not AH.isOpen then
        return false, "Open the Auction House first."
    end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        return false, "C_AuctionHouse.ReplicateItems unavailable."
    end
    if scanning then
        if co then
            return false, "A scan is already processing."
        end
        -- scanning == true, co == nil  ->  a fired-but-never-arrived (hung) request:
        -- clear it and re-fire.
        scanning = false
        CancelRetry()
    end

    local wait = AH.Replicate.SecondsUntilReady()
    if wait > 0 then
        return false, string.format("Next scan available in %d:%02d.",
            floor(wait / 60), wait % 60)
    end

    progress = 0
    AH.Events.Fire("AH_SCAN_START")
    DoFire()
    return true
end

-- Back-compat alias: the Scan button (UI/ScanButton.lua) calls StartManual().
-- Since v1.8.0 there is only one fire path, so they are the same function.
AH.Replicate.StartManual = AH.Replicate.Start

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
ef:SetScript("OnEvent", function(_, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- DEBUG TRACE (permanent, debug-gated): logs the FIRST snapshot-ready pulse of
        -- each scan only, BEFORE the guard. Blizzard streams the snapshot in chunks and
        -- fires this event once PER chunk, so an unguarded print floods chat (and buries
        -- the one line that matters). The firstEventLogged guard collapses it to a single
        -- line per scan and reports time-to-first-event = GetTime() - fireTime.
        --
        -- Retained as the diagnostic for the "first-scan-of-the-day hang" class. If a
        -- hang recurs, this line classifies it instantly:
        --   * line appears during a hang  → event DID fire; our guard dropped it
        --                                   (scanning/co state bug — fix in our code)
        --   * line NEVER appears in a hang → server never delivered the snapshot for the
        --                                   first request (readiness/timing path)
        -- The reported latency also sets the retry threshold: a HEALTHY first arrival is
        -- ~28-40s (probe ref §5; confirmed 26.5s on 2026-07-02), so the retry timer must
        -- sit above that (REPLICATE_RETRY_DELAY=60) and stay gated on co==nil.
        -- Costs nothing in normal play (only emits under VeritasUI.debug).
        -- ALWAYS-ON trace capture (v1.9.5): pulse count + first-event latency are
        -- recorded regardless of VUI.debug, so the next rare hang repro is never
        -- dark. The debug flag now only gates the PRINT below.
        if trace then
            trace.pulses = (trace.pulses or 0) + 1
            if not trace.firstEventLatency then
                trace.firstEventLatency = trace.firedAt and (GetTime() - trace.firedAt) or -1
                trace.firstEventAttempt = trace.attempts
            end
        end
        if VUI.debug and not firstEventLogged then
            firstEventLogged = true
            local latency = fireTime and (GetTime() - fireTime) or -1
            VUI.Print(AH.TAG, format("REPLICATE_ITEM_LIST_UPDATE first pulse (scanning=%s, co=%s) "
                .. "time-to-first-event=%.1fs", tostring(scanning), tostring(co ~= nil), latency))
        end
        -- Event arrived — the request was NOT dropped. Cancel the retry chain.
        CancelRetry()
        -- The snapshot is ready to read. Only act if WE initiated a scan
        -- (scanning == true) and we're not already draining a coroutine.
        if not scanning or co then return end
        if trace then trace.outcome = "processing" end
        co = coroutine.create(ProcessAllRows)
        EnsureDriver():Show()
    end
end)

-- Abort any in-flight scan if the AH closes mid-scan.
AH.Events.On("AH_CLOSED", function()
    if scanning then
        scanning = false
        co = nil
        if driver then driver:Hide() end
        progress = 0
        finalizeResolved, finalizeTotal = nil, nil
        mainCommit = nil
        CancelRetry()
        if trace and (trace.outcome == "requesting" or trace.outcome == "processing") then
            trace.outcome = "aborted"
        end
        if VUI.debug then VUI.Print(AH.TAG, "Scan aborted (AH closed).") end
    end
end)

----------------------------------------------------------------
--  AH-open housekeeping
--
--  Auto-scan on open: REMOVED (2026-07-02). It fired ReplicateItems() from the
--  AH_OPEN event path, which is where the first-open-of-session replicate hang
--  lived (three weeks of falsified candidate fixes: throttle-ready gate, settle
--  delay, one-shot + bounded retries). Scans are now user-initiated only — the
--  Scan button (UI/ScanButton.lua, hardware-event fire path) or /ah scan.
----------------------------------------------------------------
AH.Events.On("AH_OPEN", function()
    -- F-2 stuck-flag guard (the correct fix that replaces the old watchdog): a
    -- scan only lives within one AH session. If a prior session ended with
    -- `scanning` still true (event genuinely never delivered, no AH_CLOSED seen),
    -- clear it here so a fresh session can always start a new scan — no false
    -- "A scan is already running", and no failure timer needed.
    if scanning and not co then
        scanning = false
        progress = 0
        -- Close out the stale trace chain: this is a NEW AH session, so a later
        -- scan must start a fresh chain, not continue the dead one's counters.
        if trace and trace.outcome == "requesting" then
            trace.outcome = "aborted"
        end
    end
end)
