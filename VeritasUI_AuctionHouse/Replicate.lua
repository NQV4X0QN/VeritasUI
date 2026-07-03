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
                                        -- probe ref §5 2026-06-27 + confirmed 26.5s on 2026-07-02): at the old
                                        -- 10s this fired a mislabeled "request was dropped" duplicate on EVERY
                                        -- healthy scan, muddying each trace. At 60s, one request producing zero
                                        -- events within the window is an unambiguous drop.
local scanning   = false   -- a scan coroutine is in progress
local co                    -- the active coroutine
local driver               -- OnUpdate ticker frame
local progress   = 0        -- 0..1
local retryTimer            -- C_Timer handle watching for a dropped ReplicateItems()
local fireTime              -- GetTime() at the moment ReplicateItems() was issued
local firstEventLogged      -- per-scan guard: trace only the FIRST event pulse, not every chunk

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

----------------------------------------------------------------
--  Snapshot search — DIAGNOSTIC (/ah find <shift-clicked item link>)
--
--  Sweeps the LAST replicate snapshot still in client memory for rows matching
--  a target itemID (by link, falling back to exact name for rows whose link is
--  nil), and prints what the scan actually saw for that item: row index, count,
--  buyoutPrice, link-resolved?, derived key. Purpose: discriminate the stale-
--  tooltip classes — "item absent from snapshot" (server-side omission) vs
--  "present but skipped" (nil link / bid-only / zero unit) — instead of
--  inferring from silence. Chunked on its own throwaway driver so a 270k-row
--  sweep never hitches the client. Run it right after a scan completes.
----------------------------------------------------------------
local MAX_FIND_PRINTS = 10   -- per-row print cap; the summary still counts all
function AH.Replicate.FindInSnapshot(targetItemID, targetName)
    if scanning then
        return false, "A scan is running — try again after it completes."
    end
    local num = C_AuctionHouse.GetNumReplicateItems() or 0
    if num == 0 then
        return false, "No replicate snapshot in memory — run a scan first, then /ah find again."
    end

    local i, found, nilLinks, printed = 0, 0, 0, 0
    local totalQty = 0
    local sweeper = CreateFrame("Frame")
    sweeper:SetScript("OnUpdate", function(self)
        local sliceStart = debugprofilestop()
        while i < num and (debugprofilestop() - sliceStart) < FRAME_BUDGET_MS do
            pcall(function()
                local name, _, count, _, _, _, _, _, _, buyoutPrice =
                    C_AuctionHouse.GetReplicateItemInfo(i)
                local link = C_AuctionHouse.GetReplicateItemLink(i)
                local isMatch = false
                if link then
                    local id = tonumber(link:match("|Hitem:(%d+)"))
                    isMatch = (id == targetItemID)
                else
                    nilLinks = nilLinks + 1
                    -- Fallback: name may resolve even when the link doesn't.
                    isMatch = (targetName ~= nil and name == targetName)
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
                            tostring(link and AH.DB.MakeKey(link))))
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
            -- GetReplicateItemInfo positional returns (design §2.2 verified order):
            -- name, texture, count, qualityID, usable, level, levelType, minBid,
            -- minIncrement, buyoutPrice, bidAmount, highBidder, ...
            local _, _, count, _, _, _, _, _, _, buyoutPrice = C_AuctionHouse.GetReplicateItemInfo(i)
            count = count or 1
            buyoutPrice = buyoutPrice or 0

            -- Skip bid-only auctions (no buyout) — DB tracks buyout market price.
            if buyoutPrice > 0 and count > 0 then
                local link = C_AuctionHouse.GetReplicateItemLink(i)
                if link then
                    local key = AH.DB.MakeKey(link)
                    if key then
                        local unit = floor(buyoutPrice / count)
                        if unit > 0 then
                            local a = agg[key]
                            if not a then
                                agg[key] = { unit = unit, qty = count }
                                kept = kept + 1
                            else
                                if unit < a.unit then a.unit = unit end
                                a.qty = a.qty + count
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

    -- Commit aggregates to the DB (also chunked — could be tens of thousands of keys).
    local day = AH.DB.Today()
    local committed = 0
    sliceStart = debugprofilestop()
    sliceCount = 0
    for key, a in pairs(agg) do
        AH.DB.Record(key, a.unit, a.qty, day)
        committed = committed + 1
        sliceCount = sliceCount + 1
        if sliceCount >= ROWS_PER_SLICE
           or (debugprofilestop() - sliceStart) >= FRAME_BUDGET_MS then
            coroutine.yield()
            sliceStart = debugprofilestop()
            sliceCount = 0
        end
    end

    return committed, num
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
            if VUI.debug then
                VUI.Print(AH.TAG, "|cFFFF4444Scan error|r: " .. tostring(a))
            end
            scanning = false
            co = nil
            driver:Hide()
            AH.Events.Fire("AH_SCAN_FAILED", tostring(a))
            return
        end
        if coroutine.status(co) == "dead" then
            -- Finished. a = committed count, b = rows scanned.
            scanning = false
            co = nil
            driver:Hide()
            progress = 1
            SetLastScanTime(time())
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

local function DoFire()
    scanning = true          -- set ONLY here, at the real fire moment
    fireTime = GetTime()     -- stamp for first-event / total-scan latency measurement
    firstEventLogged = false -- re-arm the one-line-per-scan trace for this attempt
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
    -- Arm a retry: if REPLICATE_ITEM_LIST_UPDATE doesn't arrive within
    -- REPLICATE_RETRY_DELAY seconds the request was silently dropped by the server.
    -- A dropped request produces NO event at all — so after this delay we know with
    -- certainty the call was dropped (not slow), and it's safe to retry.
    -- This is NOT a watchdog: it only fires when co is still nil (coroutine never
    -- started), meaning the event genuinely never arrived. If the event arrives
    -- first (normal path), CancelRetry() below defuses this timer immediately.
    CancelRetry()
    retryTimer = C_Timer.NewTimer(REPLICATE_RETRY_DELAY, function()
        retryTimer = nil
        -- Only retry if: AH still open, scan flag still set, but coroutine never started.
        -- co ~= nil means the event arrived and we're processing — don't retry.
        if not AH.isOpen or not scanning or co then return end
        if VUI.debug then
            VUI.Print(AH.TAG, "REPLICATE_ITEM_LIST_UPDATE not received after "
                .. REPLICATE_RETRY_DELAY .. "s — request was dropped; retrying ReplicateItems()")
        end
        C_AuctionHouse.ReplicateItems()
    end)
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
        if VUI.debug and not firstEventLogged then
            firstEventLogged = true
            local latency = fireTime and (GetTime() - fireTime) or -1
            VUI.Print(AH.TAG, format("REPLICATE_ITEM_LIST_UPDATE first pulse (scanning=%s, co=%s) "
                .. "time-to-first-event=%.1fs", tostring(scanning), tostring(co ~= nil), latency))
        end
        -- Event arrived — the request was NOT dropped. Cancel the retry timer.
        CancelRetry()
        -- The snapshot is ready to read. Only act if WE initiated a scan
        -- (scanning == true) and we're not already draining a coroutine.
        if not scanning or co then return end
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
        CancelRetry()
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
    end
end)
