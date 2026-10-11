-- VeritasUI_AuctionHouse / Replicate.lua
-- Full-scan driver, built on C_AuctionHouse.ReplicateItems().
--
-- ⚠ FINDING (2026-08-03) — ReplicateItems IS NOT THE ONLY WHOLE-AH SCAN, AND IT MAY BE
-- THE WRONG ONE. This header used to state that it is "the ONLY sanctioned whole-AH
-- snapshot (design §2.2 — SendSearchQuery is capped at 100/min and must NOT be used to
-- scan)". That conflates two different APIs and is the belief that kept this module tied
-- to a flaky endpoint for months:
--   * C_AuctionHouse.SendSearchQuery   — item-specific search, rate-capped. Correctly
--                                        rejected for scanning. Design §2.2 is right here.
--   * C_AuctionHouse.SendBrowseQuery   — NOT the same call, NOT the same cap. An EMPTY
--                                        browse query plus RequestMoreBrowseResults()
--                                        pagination enumerates the whole AH as per-item
--                                        summaries (minPrice + totalQuantity).
--
-- Auctionator ships BOTH scans and defaults to the browse one: Source/Config/Main.lua has
-- REPLICATE_SCAN = false, its single Full Scan button branches on that option
-- (Tabs/Auctionator/Mixins/ScanButton.lua), and replicate is opt-in via an Advanced
-- checkbox (Config/Mixins/Advanced.lua). The replicate code is maintained, not dead — it
-- buys per-auction detail a summary cannot — but it is not what their users run.
--
-- MEASURED, owner's PC: with our replicate scan freshly failed ("request was lost", zero
-- event pulses), Auctionator's browse scan succeeded seconds later on the same character,
-- realm and session — 20,056 items, comparable to our usual 19-25k. So the browse path
-- works at the exact moment this one is dead. That is the strongest lead we have ever had
-- on the first-scan-of-the-day hang, and it is an ENDPOINT difference, not a timing,
-- taint, readiness, fire-context or rate-limit difference — all five of which were
-- investigated and falsified (see ArmStallDetector and the SKILL landmines).
--
-- Root cause of the replicate failure is still UNKNOWN and is no longer the priority:
-- the plan is to add the browse-summary scan rather than keep trying to repair this one.
-- ⚠ Do not "simplify" that away as duplication if both paths end up present.
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
--   * aggregate per key within a scan: keep the MIN unit price + the SUMMED qty
--     (each row is a distinct auction, so the units listed for an item is the sum
--     of its rows' counts, NOT its largest stack), then write once per key at the
--     end (one DB.Record call per item, not per row). AH.DB.Record then keeps a
--     per-day MAX of that per-scan sum, so the pipeline is: sum within a scan,
--     max across scans within a day. Both halves are deliberate.
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
-- Hot: three of the eleven call sites are inside the per-row slice loops, evaluated up to
-- once per row across a ~270k-row snapshot.
local debugprofilestop = debugprofilestop

AH.Replicate = {}

local SCAN_FLOOR_SECONDS    = 15 * 60   -- DEFAULT minimum gap between full scans.
                                        -- Overridable per-account via
                                        -- db.settings.scanFloorSeconds (`/ah floor`);
                                        -- see ScanFloorSeconds() below.
local ROWS_PER_SLICE        = 2000      -- safety cap on rows per frame
local FRAME_BUDGET_MS       = 8         -- ~8ms/frame work budget (debugprofilestop)
local REPLICATE_STALL_TIMEOUT = 60      -- seconds of total silence after which the request is declared LOST.
                                        -- MUST sit above the measured healthy first-event latency (~28-40s,
                                        -- probe ref §5 2026-06-27 + confirmed 26.5s on 2026-07-02, 23.9s on
                                        -- 2026-07-11 and 26.0s on 2026-07-24): at the old 10s this tripped on
                                        -- EVERY healthy scan. At 60s, one request producing zero events inside
                                        -- the window is an unambiguous loss. This does NOT abort the scan (see
                                        -- the no-timeout rule above) — it only reports, and reports nothing
                                        -- about the cause beyond the recorded facts. See ArmStallDetector.
local LINK_RETRY_WAIT       = 3         -- seconds between link retry passes (lets queued
                                        -- item-record loads stream in; cold-cache coverage fix)
local LINK_RETRY_BUDGET     = 120       -- hard cap (seconds) on the whole retry phase.
                                        --
                                        -- ⚠ RAISED 45 -> 120 in v1.12.9 because 45 was MEASURABLY
                                        -- too small and was silently costing data. Owner's scan
                                        -- 2026-08-03: "link-retried: 10165 of 16304 resolved over
                                        -- 15 pass(es); dropped: 6139" — 15 passes x LINK_RETRY_WAIT
                                        -- (3s) = 45s exactly, i.e. the cap, with 38% of gear rows
                                        -- still unresolved and therefore ABANDONED. An abandoned
                                        -- row gets no AH.DB.Record() call, so it updates neither
                                        -- the price NOR `seen` — those items keep an old price and
                                        -- an old age immediately after a successful scan, and
                                        -- rescanning drops them again. The old figure assumed
                                        -- ~1k records/3s and ~15k gear rows; the measured stream
                                        -- ran ~677/pass against 16.3k rows, so the assumption was
                                        -- wrong in both terms.
                                        --
                                        -- Raising this does NOT lengthen healthy scans: the phase
                                        -- breaks on the first pass that resolves nothing
                                        -- (quiescence, see passTouched below), so the cap only
                                        -- binds while progress is still being made.
                                        --
                                        -- ⚠ AND RAISING IT DID NOT HELP. The very next scan
                                        -- (2026-08-04) ran only 4 passes = 12s, nowhere near this
                                        -- cap, exiting on QUIESCENCE with 10,609 of 15,894 gear
                                        -- rows unresolved — worse than the 6,139 that motivated the
                                        -- raise. So the budget was the binding constraint on ONE
                                        -- scan and the quiescence break on the next; concluding
                                        -- "the cap is the problem" from a single sample was wrong.
                                        --
                                        -- ⚠ CAUSE UNKNOWN. Do not fill this gap with a guess; two
                                        -- have already been wrong.
                                        --
                                        -- RETRACTED (v1.12.10): v1.12.9 asserted here, in the
                                        -- CHANGELOG and in a SKILL landmine that the cause was this
                                        -- loop "passively re-polling instead of requesting item
                                        -- data". That is FALSE and was written without reading the
                                        -- loop. We request at deferral time (see the
                                        -- RequestLoadItemDataByID call beside `requestedIDs`) AND
                                        -- re-request every pass for any row still cold (see the
                                        -- `elseif ent.id` branch in the retry loop). Auctionator's
                                        -- LoadItemData does the same thing on a 0.4s ticker; we do it
                                        -- on a LINK_RETRY_WAIT ticker. The mechanism claimed missing
                                        -- is present in both places.
                                        --
                                        -- WHAT IS ACTUALLY KNOWN: on 2026-08-03 fifteen passes
                                        -- resolved 10,165 rows and hit this cap; on 2026-08-04 four
                                        -- passes resolved 5,285 and exited on QUIESCENCE with 10,609
                                        -- outstanding. So the machinery demonstrably works and then
                                        -- demonstrably stops, and the difference between the two runs
                                        -- is unexplained. Candidates, all UNMEASURED: item-data
                                        -- requests being throttled after a burst of ~16k; rows whose
                                        -- itemID never calibrated, which are polled forever because
                                        -- the re-request is gated on `ent.id`; and a quiescence break
                                        -- that concludes the stream is dry after a SINGLE empty 3s
                                        -- pass. The scan-end diagnostics added in v1.12.10 (id-less
                                        -- row count, consecutive dry passes) exist to separate these.
                                        --
                                        -- Browse.lua is the default engine and has no deferred pile,
                                        -- so this path is not on the critical path — but replicate is
                                        -- KEPT as the fallback, and a fallback with an unexplained
                                        -- data loss is not a fallback. Finish the measurement.
                                        --
                                        -- ⚠ This is a BAND-AID, not the fix. Browse.lua gets the
                                        -- item level from the browse result's itemKey, so it has
                                        -- no deferred pile, no budget and nothing to drop. When
                                        -- browse becomes the default engine this constant stops
                                        -- mattering; do not tune it further, switch engine.

----------------------------------------------------------------
--  Throttled-message instrumentation (v1.12.6)
--
--  WHY THIS EXISTS — read before deleting it as noise.
--
--  ⚠ MEASURED RESULT (2026-07-31, Mac 12.0.7) — READ BEFORE TRUSTING THIS LINE.
--  On a FULLY SUCCESSFUL scan (275,455 rows, first data 32.8s after fire, 106,926
--  pulses) the log came back EMPTY: not one of the six events fired anywhere in the
--  32.8s request->data window. So `ReplicateItems()` is NOT instrumented by the
--  throttled-message family at all, and a blank log during a HANG proves nothing.
--  The discriminator described below does not work. Do not rebuild a retry policy
--  on it, and do not re-derive the idea — it is measured, not argued (probe ref §5).
--
--  That also corrects the reasoning that produced this code: Throttle.lua (v1.6.46,
--  deleted v1.7.0) and the design doc's "retry on _DROPPED" mandate governed
--  SendBrowseQuery, which IS in the throttled system. Replicate never was. Cutting
--  Throttle.lua with the Shopping tab lost nothing this path could have used.
--
--  KEPT, and as of v1.12.7 it has a real future use rather than just a null baseline:
--  the browse-query scan path (see the FINDING block at the top of this file) DOES run
--  inside the throttled-message system — Auctionator routes every SendBrowseQuery and
--  RequestMoreBrowseResults through a queue for exactly that reason. So these events go
--  from inert to load-bearing the moment that path lands. Until then, the null baseline
--  still makes a NON-blank log decisive where it was previously ambiguous.
--
--  ── original rationale, retained for the history ──
--
--  Two DIFFERENT failures both present as "ReplicateItems() fired, zero event
--  pulses, identical [FIRE STATE]", and they need OPPOSITE responses:
--
--    (a) the request was DROPPED by Blizzard's throttled-message system
--        -> a re-fire is the correct recovery (a lost packet, not a refusal)
--    (b) the server is RATE-LIMITING replicate for this account
--        -> re-firing is futile and plausibly re-arms the window
--
--  We have never been able to tell them apart, and the whole history of this bug
--  is guesses about which regime we are in — each of which works for one and
--  fails the other:
--    v1.9.5  "always retry, forever"  -> right for (a); 4h/240 re-fires answered
--                                        nothing in (b), 2026-07-24
--    v1.9.14 "never retry"            -> right for (b); removed the thing that
--                                        DID rescue (a) (probe ref §5 2026-06-27:
--                                        "first request dropped and rescued by the
--                                        v1.7.9 retry", and again 2026-07-11)
--
--  Both observations are real, which is only consistent with both regimes existing.
--  That inference still stands; only the proposed instrument for telling them apart
--  was falsified.
--
--  ALWAYS-ON, deliberately not gated on VUI.debug: this reproduces once a day at
--  most and cannot be summoned, so the flag would be off exactly when it mattered
--  (the same reasoning as the v1.9.5 scan trace).
--
--  Names are pcall-registered individually: an invalid name would otherwise throw
--  at load and take the whole module with it. All six registered cleanly on 12.0.7.
----------------------------------------------------------------
local THROTTLE_EVENTS = {
    -- short label                     -- event name
    DROPPED  = "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    QUEUED   = "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
    SENT     = "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    RESPONSE = "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
    READY    = "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    BROWSEFAIL = "AUCTION_HOUSE_BROWSE_FAILURE",
}
-- Bound the per-scan log. _SENT/_QUEUED/_READY also fire for Blizzard's own AH
-- queries, so a long session could otherwise grow this without limit. 40 is far
-- more than the handful the dead window produces, and overflow is counted rather
-- than dropped silently.
local THROTTLE_LOG_CAP = 40

local scanning   = false   -- a scan coroutine is in progress
local co                    -- the active coroutine
local driver               -- OnUpdate ticker frame
local finder               -- OnUpdate ticker frame for /ah find, reused across calls
local progress   = 0        -- 0..1
local stallTimer            -- C_Timer handle watching for a lost ReplicateItems()
local fireTime              -- GetTime() at the moment ReplicateItems() was issued
local finalizeResolved      -- live counters for the gear-residue retry phase;
local finalizeTotal         -- nil outside the phase (backs FinalizeStatus())
local noIDRows              -- deferred rows with no resolvable itemID (can never be re-requested)
local dryPasses             -- consecutive retry passes that resolved NOTHING
local firstEventLogged      -- per-scan guard: trace only the FIRST event pulse, not every chunk
local trace                 -- ALWAYS-ON diagnostic record of the current/most-recent scan
                            -- attempt chain (v1.9.5). The 2026-07-11 hang went dark because
                            -- the only instrumentation was debug-gated prints and debug was
                            -- off during the rare repro. This table records regardless of
                            -- VUI.debug; /ah diag dumps it. Fields:
                            --   startedAt         time() at first fire of the chain
                            --   firedAt           GetTime() of the LATEST fire (elapsed math)
                            --   attempts          total ReplicateItems() calls in the chain.
                            --                     Since v1.9.14 there are no automatic
                            --                     re-fires, so this counts user-initiated
                            --                     fires only (a manual retry on a still-hung
                            --                     request CONTINUES the chain, see DoFire)
                            --   pulses            REPLICATE_ITEM_LIST_UPDATE events seen
                            --   firstEventLatency GetTime()-firedAt at the first pulse
                            --   firstEventAttempt which attempt the first pulse followed
                            --   throttle          ordered list of throttled-family events seen
                            --                     while the scan was in flight (see THROTTLE_EVENTS)
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

-- The floor actually in force. ABSENCE of the setting means "use the shipped default",
-- the same convention as `scanEngine` (SEED_EXEMPT in Tooltip.lua) and for the same
-- reason: a seeded copy of the default would make a future default change inert, and it
-- would be indistinguishable from a deliberate choice.
--
-- 0 disables OUR floor entirely. ⚠ That does NOT remove Blizzard's own throttling:
-- `ReplicateItems` has a server-side cooldown of its own, so on the replicate engine a
-- disabled floor mostly means the request is refused or returns the same snapshot. On
-- the BROWSE engine (the default since v1.12.12) there is no such fixed cooldown — the
-- send queue gates on IsThrottledMessageSystemReady — so repeat scans do genuinely work.
-- Added v1.14.18 for iteration on the scan bar's appearance: waiting 15 minutes to see a
-- cosmetic change once is not a workable test loop.
local function ScanFloorSeconds()
    local s = AH.db and AH.db.settings and AH.db.settings.scanFloorSeconds
    if type(s) == "number" and s >= 0 then return s end
    return SCAN_FLOOR_SECONDS
end

-- Exposed so `/ah floor` and `/ah diag` report the same number the gate uses, rather
-- than each re-deriving it (the three-way slash drift lesson, Core.lua:514).
function AH.Replicate.ScanFloorSeconds()
    return ScanFloorSeconds(), SCAN_FLOOR_SECONDS
end

-- Seconds remaining before another scan is permitted (0 = ready).
-- Click-to-refire IS meaningful here: the pre-data wait is a ~30s snapshot wait that can
-- stretch indefinitely when the server silently drops the request (measured ~12 min, v1.9.5),
-- and Start() clears a fired-but-never-arrived request and re-fires. That is what the
-- "Retry Scan" button state exists for.
AH.Replicate.SupportsRetry = true

function AH.Replicate.SecondsUntilReady()
    local elapsed = time() - LastScanTime()
    local remaining = ScanFloorSeconds() - elapsed
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
--  a target itemID, and prints what the scan actually saw for that item: row
--  index, count, buyoutPrice, link-resolved?, derived key. Warm rows match on
--  the itemID parsed out of the row's own link; cold rows (nil link) match on
--  the return position calibrated live by the last scan, the same mechanism the
--  scan itself uses. There is NO name-based fallback — matching is by itemID
--  only, both paths. Purpose: discriminate the stale-tooltip classes — "item
--  absent from snapshot" (server-side omission) vs "present but skipped"
--  (nil link / bid-only / zero unit) — instead of inferring from silence.
--  Chunked on a reused driver frame so a 270k-row sweep never hitches the
--  client. Run it right after a scan completes.
----------------------------------------------------------------
local MAX_FIND_PRINTS = 10   -- per-row print cap; the summary still counts all
function AH.Replicate.FindInSnapshot(targetItemID)
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

    -- Per-scan aggregate: key -> { unit = minUnitPrice, qty = summedQty }.
    -- qty SUMS across rows because each replicate row is a distinct auction. Do NOT
    -- "correct" this to a max: that would collapse every item to its biggest single
    -- stack and silently under-report availability across the whole database, with
    -- no error and no way to notice except comparing against the live AH.
    -- The per-DAY max across scans is applied later, by AH.DB.Record.
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
                            -- ⚠ A deferred row with NO itemID can never be re-requested:
                            -- the nudge in the retry loop is gated on `ent.id`. Such rows
                            -- are polled forever and resolve only by luck. Counted so
                            -- "the server stopped answering" can be told apart from
                            -- "we never asked for these" — one of the three unmeasured
                            -- candidates behind the early-quiescence exit.
                            if not id then noIDRows = noIDRows + 1 end
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
                -- Quiescent pass: not one row left the pile. Previously this tested the
                -- FOLD count, which abandoned the remaining pile whenever a pass resolved
                -- only skip-worthy rows — ordinary for a small bid-only tail, while the
                -- stream was demonstrably still delivering.
                --
                -- ⚠ COUNTED, not acted on. Breaking here is still the behaviour; the
                -- counter exists because ONE empty 3s window is thin evidence that
                -- asynchronous item data has stopped arriving, and that is one of the
                -- three unmeasured candidates for the 2026-08-04 early exit. If real
                -- scans show the break firing at dryPasses == 1 while rows remain, the
                -- fix is to require consecutive dry passes — but that is a change to make
                -- ON EVIDENCE, after two wrong guesses, not before it.
                dryPasses = (dryPasses or 0) + 1
                break
            else
                dryPasses = 0
            end
        end
    end

    -- Diagnostic tail: report WHY the retry phase ended, with the numbers that separate
    -- the candidate causes. Always printed when rows were abandoned — an unexplained loss
    -- that only shows under a debug flag is an unexplained loss nobody will ever explain.
    if deferredTotal and deferredTotal > 0 and #deferred > 0 then
        VUI.Print(AH.TAG, format(
            "  |cFFFF4444%d of %d gear rows abandoned.|r ended=%s  passes=%d  "
            .. "no-itemID rows=%d (never re-requestable)",
            #deferred, deferredTotal,
            ((dryPasses or 0) > 0) and "quiescence (a pass resolved nothing)"
                or "budget exhausted",
            retryPasses or 0, noIDRows or 0))
        VUI.Print(AH.TAG, "  Those rows updated neither price nor age. "
            .. "|cFFFFFF00/ah engine browse|r has no deferred pile.")
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
                AH.Events.Fire("AH_SCAN_COMPLETE", mainCommit.kept, mainCommit.rows, "auctions")
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
            -- Drop items this auction house no longer lists (audit A1; see AH.DB.PruneUnseen).
            -- Only on this full-completion path: a scan that ended in the finalize-error branch
            -- above, or was aborted by AH_CLOSED, removes nothing.
            AH.DB.PruneUnseen(AH.DB.Today())
            if trace then
                trace.outcome   = "complete"
                trace.committed = a or 0
                trace.rows      = b or 0
                trace.totalTime = fireTime and (GetTime() - fireTime) or nil
            end
            -- "auctions" is accurate here and nowhere else: this engine walks individual
            -- auction rows. Browse deliberately passes no noun (see the handler in
            -- Core.lua) because it only ever sees per-item summaries.
            AH.Events.Fire("AH_SCAN_COMPLETE", a or 0, b or 0, "auctions")
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
local function CancelStallDetector()
    if stallTimer then
        stallTimer:Cancel()
        stallTimer = nil
    end
end

----------------------------------------------------------------
--  ArmStallDetector — detect a lost request; decide nothing (v1.12.6)
--
--  Reports a request that produced no data, and stops. It does not re-fire, and
--  as of v1.12.6 it no longer claims to know the recovery, because we don't yet.
--
--  ⚠ THE v1.9.14 MODEL THIS REPLACES WAS WRONG IN BOTH DIRECTIONS. It is quoted
--  here so the same two mistakes are not made a third time:
--
--    1. "Re-asking is futile at any duration." Drawn from one measurement — 4h of
--       60s re-fires answering nothing (2026-07-24). But the probe library records
--       the opposite twice: §5 2026-06-27, "first request dropped and rescued by
--       the v1.7.9 retry", and again 2026-07-11. v1.9.14 dismissed the 2026-07-11
--       episode as untrusted; it should have treated two contradictory results as
--       evidence of two different failures, not as one bad datum.
--
--    2. "Close and reopen recovers it; no waiting is involved, which rules out any
--       time-based server cooldown." The procedure it cites as proof begins "wait
--       60s". It concluded waiting was irrelevant from a recipe containing a wait.
--       Falsified outright by the owner on 2026-07-31: close/reopen fails, /reload
--       fails, and only elapsed time works. Note also that what closing the AH
--       really did pre-v1.9.14 was cancel the re-fire chain (AH_CLOSED cancels it)
--       — it stopped the hammering, which is not the same as a fresh session.
--
--  What survives from that investigation and is still believed:
--    * [FIRE STATE] is byte-identical at a failing fire and a succeeding one
--      (2026-07-02, 2026-07-11, 2026-07-24) — no client-side signal predicts it,
--      so pre-fire readiness gates cannot work (three were tried and falsified).
--    * Search / buy / sell work normally during a hang: only bulk replicate fails.
--    * event pulses: 0 at every hang — the snapshot never starts, so this is not
--      our guard dropping a delivered event.
--
--  The open question is which of the two regimes in THROTTLE_EVENTS we are in, and
--  the throttled-family log now answers it from a single real occurrence. Until
--  then this handler deliberately prescribes nothing except "wait for the floor"
--  and "send me the trace".
--
--  Deliberately does NOT abort the scan: `scanning` stays true and the event
--  handler stays live, so a late snapshot is still processed (the no-timeout rule
--  above). That matters more now than it did: if we are in the dropped-packet
--  regime, late delivery is exactly what we would be throwing away.
----------------------------------------------------------------
local function ArmStallDetector()
    CancelStallDetector()
    stallTimer = C_Timer.NewTimer(REPLICATE_STALL_TIMEOUT, function()
        stallTimer = nil
        -- Only report if: AH still open, scan flag still set, but the coroutine
        -- never started. co ~= nil means data arrived and we're processing.
        if not AH.isOpen or not scanning or co then return end
        -- Says only what is known. It does NOT quote a cooldown (v1.12.6 did, and the
        -- attempt-stamp behind it was reverted in v1.12.7 — see DoFire), and it does
        -- NOT prescribe a recovery: reopening and /reload are both confirmed useless,
        -- and no client-side signal distinguishes this from a slow-but-coming scan.
        VUI.Print(AH.TAG, format(
            "|cFFFF4444No response after %ds — the request was lost.|r "
            .. "You can press |cFFFFFF00Scan|r again. Reopening the Auction House "
            .. "makes no difference, and neither does /reload.", REPLICATE_STALL_TIMEOUT))
    end)
end

local function DoFire()
    scanning = true          -- set ONLY here, at the real fire moment
    fireTime = GetTime()     -- stamp for first-event / total-scan latency measurement
    firstEventLogged = false -- re-arm the one-line-per-scan trace for this attempt
    -- Retry-phase diagnostics, reset per attempt. Initialised to 0 rather than left nil
    -- because both are incremented, not assigned, at their use sites.
    noIDRows  = 0
    dryPasses = 0
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
    -- ⚠ DO NOT stamp the scan floor here. v1.12.6 did, and it was REVERTED in
    -- v1.12.7 after the premise collapsed.
    --
    -- The idea was Auctionator parity: its FullScan stamps TimeOfLastReplicateScan
    -- on every ATTEMPT, before the call, so it can never re-ask inside 15 minutes.
    -- The reasoning was that a lost request means the server is rate-limiting us and
    -- we were hammering it.
    --
    -- WHAT KILLED IT (measured 2026-08-03, owner's PC): with our replicate scan
    -- freshly failed, Auctionator's full scan succeeded seconds later — 20,056 items.
    -- But it ran in "summary mode", i.e. IncrementalScan, which does NOT call
    -- ReplicateItems at all: it sends an empty SendBrowseQuery and paginates. So the
    -- comparison never tested this endpoint, and the floor was copied from the half
    -- of the reference implementation Auctionator ships DISABLED
    -- (Source/Config/Main.lua: REPLICATE_SCAN = false, opt-in under Advanced).
    --
    -- With no evidence of an account-level replicate quota, a 15-minute lockout after
    -- a failure cost the user a quarter of an hour and bought nothing. The evidence
    -- for "re-asking is harmful" remains one 4-hour measurement contradicted twice in
    -- the probe library, which is not enough to spend the user's time on.
    --
    -- The floor stays SUCCESS-ONLY (the two SetLastScanTime calls in ProcessAllRows
    -- and the driver), which is how it worked from v1.6.47 to v1.12.5.
    C_AuctionHouse.ReplicateItems()
    -- Phase marker for the progress UI: the request has gone out, so the bar can
    -- leave "Connecting…" and enter the snapshot wait (ScanProgress listens).
    AH.Events.Fire("AH_SCAN_REQUESTED")
    if VUI.debug then
        VUI.Print(AH.TAG, "ReplicateItems() fired")
    end
    -- Arm the stall detector: if REPLICATE_ITEM_LIST_UPDATE doesn't arrive
    -- within REPLICATE_STALL_TIMEOUT seconds the request was lost (a lost
    -- request produces NO event at all). It does not re-fire and does not
    -- abort — it marks the session and tells the user to reopen the AH.
    -- If the event arrives first (normal path), CancelStallDetector() in the
    -- event handler defuses it immediately.
    ArmStallDetector()
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
        CancelStallDetector()
    end

    local wait = AH.Replicate.SecondsUntilReady()
    if wait > 0 then
        return false, format("Next scan available in %d:%02d.",
            floor(wait / 60), wait % 60)
    end

    progress = 0
    AH.Events.Fire("AH_SCAN_START")
    DoFire()
    return true
end

-- Back-compat alias. Since v1.8.0 there is only one fire path, so this is the same
-- function as Start.
--
-- ⚠ CORRECTED v1.13.8. This used to say "the Scan button (UI/ScanButton.lua) calls
-- StartManual()". The button calls AH.Scan.StartManual — the FACADE in Core.lua — and
-- has done since the v1.12.9 migration. THIS alias has zero callers anywhere in the
-- suite; the only reference to it is the line below. Left in place as a deliberate
-- back-compat surface, but do not read it as live.
AH.Replicate.StartManual = AH.Replicate.Start

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")

-- Throttled-family registration (see THROTTLE_EVENTS for why). Per-name pcall so
-- one renamed event cannot take the module down at load; anything that fails to
-- register is reported by /ah diag rather than failing silently.
local throttleRegistered, throttleInvalid = {}, {}
for label, evName in pairs(THROTTLE_EVENTS) do
    if pcall(ef.RegisterEvent, ef, evName) then
        throttleRegistered[evName] = label
    else
        throttleInvalid[#throttleInvalid + 1] = label
    end
end

-- Reports any throttled-family event name that failed to register, so /ah diag can
-- say "the throttle line is unreliable" instead of letting a renamed event read as
-- a meaningful silence — which is the exact misreading this instrumentation exists
-- to prevent. Returns nil when all names registered.
function AH.Replicate.ThrottleUnregistered()
    if #throttleInvalid == 0 then return nil end
    return table.concat(throttleInvalid, ", ")
end

-- Record a throttled-family event against the in-flight scan.
--
-- Only records while a request is actually outstanding (scanning and no coroutine
-- yet): that fire -> first-data window is the one we need classified, and it keeps
-- Blizzard's own AH query traffic out of the log. Never prints — _SENT/_QUEUED can
-- fire repeatedly and a print here would bury the line that matters.
local function RecordThrottleEvent(label)
    if not trace or not scanning or co then return end
    local list = trace.throttle
    if not list then list = {}; trace.throttle = list end
    if #list >= THROTTLE_LOG_CAP then
        trace.throttleOverflow = (trace.throttleOverflow or 0) + 1
        return
    end
    list[#list + 1] = {
        label = label,
        at    = trace.firedAt and (GetTime() - trace.firedAt) or -1,
    }
end

ef:SetScript("OnEvent", function(_, event)
    local throttleLabel = throttleRegistered[event]
    if throttleLabel then
        RecordThrottleEvent(throttleLabel)
        return
    end
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
        -- The reported latency also sets the stall threshold: a HEALTHY first arrival is
        -- ~28-40s (probe ref §5; confirmed 26.5s on 2026-07-02, 26.0s on 2026-07-24), so
        -- the stall timer must sit above that (REPLICATE_STALL_TIMEOUT=60).
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
        CancelStallDetector()
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
        CancelStallDetector()
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
    -- Stuck-flag guard (v1.7.5 — the correct fix that replaces the old watchdog): a
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
