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
local time       = time
local coroutine  = coroutine
local CreateFrame = CreateFrame

AH.Replicate = {}

local SCAN_FLOOR_SECONDS    = 15 * 60   -- minimum gap between full scans
local ROWS_PER_SLICE        = 2000      -- safety cap on rows per frame
local FRAME_BUDGET_MS       = 8         -- ~8ms/frame work budget (debugprofilestop)

local scanning   = false   -- a scan coroutine is in progress
local co                    -- the active coroutine
local driver               -- OnUpdate ticker frame
local progress   = 0        -- 0..1

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
--  The chunked row processor (coroutine body)
----------------------------------------------------------------
local function ProcessAllRows()
    local num = C_AuctionHouse.GetNumReplicateItems() or 0
    if num == 0 then
        return 0, 0
    end

    -- Per-scan aggregate: key -> { unit = minUnitPrice, qty = maxQty }.
    local agg = {}
    local kept = 0

    local sliceStart = debugprofilestop()
    local sliceCount = 0

    for i = 0, num - 1 do
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
        end
    end)
    return driver
end

----------------------------------------------------------------
--  FireWhenReady — issue ReplicateItems() only once Blizzard's throttle/
--  message system reports ready, deferring on the FIRST AH open of a session.
--
--  ROOT CAUSE (confirmed in-game 2026-06-15, hypothesis on the WHY):
--    On the first AH open since login, ReplicateItems() fired immediately on
--    AUCTION_HOUSE_SHOW is SILENTLY DROPPED — REPLICATE_ITEM_LIST_UPDATE never
--    fires, the scan sits at 0% forever, and the stuck `scanning` flag makes the
--    next attempt say "A scan is already running" until /reload. Re-opening the AH
--    in the SAME session works (verified: 265k auctions). The throttle-readiness
--    gate that would have prevented this lived in the old Throttle.lua, which was
--    CUT at v1.7.0 with the Shopping tab; auto-scan-on-open (v1.7.2) was added
--    afterward and fires with no readiness check.
--
--  DEFENSIVE DESIGN (this is a candidate fix shipped to test against a once-per-
--  24h repro — it must never be WORSE than today):
--    * If IsThrottledMessageSystemReady is ABSENT in 12.0.5 (unverified from the
--      platform side) → treat as ready and fire immediately = today's exact path.
--    * If present and READY → fire immediately (the same-session re-open path that
--      already works).
--    * If present and NOT ready → register for AUCTION_HOUSE_THROTTLED_SYSTEM_READY
--      and fire when it arrives. NOT a timeout/watchdog (that's the removed-v1.7.5
--      landmine) — a one-shot event wait that either fires or stays quiet.
--    * `scanning` is set TRUE only at the ACTUAL fire moment, so a deferred request
--      that never fires cannot strand the flag.
--  Debug output on every branch so tomorrow's single attempt is self-explaining.
----------------------------------------------------------------
local readyWaiter            -- frame waiting on AUCTION_HOUSE_THROTTLED_SYSTEM_READY
local pendingAuto            -- remembers the `auto` flag across the deferred wait

local function DoFire(auto)
    scanning = true          -- set ONLY here, at the real fire moment
    C_AuctionHouse.ReplicateItems()
    if VUI.debug then
        VUI.Print(AH.TAG, "ReplicateItems() fired (auto=" .. tostring(auto and true or false) .. ")")
    end
end

local function FireWhenReady(auto)
    local probe = C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
    -- API absent → preserve today's behavior exactly (fire immediately).
    if type(probe) ~= "function" then
        if VUI.debug then
            VUI.Print(AH.TAG, "IsThrottledMessageSystemReady absent — firing immediately (legacy path)")
        end
        DoFire(auto)
        return
    end

    local ok, ready = pcall(probe)
    if ok and ready then
        if VUI.debug then VUI.Print(AH.TAG, "throttle system READY — firing now") end
        DoFire(auto)
        return
    end

    -- Not ready (or the probe errored) → defer until the ready event. One-shot.
    if VUI.debug then
        VUI.Print(AH.TAG, "throttle system NOT ready — deferring scan until AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    end
    pendingAuto = auto
    if not readyWaiter then
        readyWaiter = CreateFrame("Frame")
        readyWaiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            -- Guards: AH may have closed during the wait, or another scan started.
            if not AH.isOpen or scanning then
                if VUI.debug then
                    VUI.Print(AH.TAG, "ready fired but skipping (isOpen="
                        .. tostring(AH.isOpen) .. ", scanning=" .. tostring(scanning) .. ")")
                end
                return
            end
            if VUI.debug then VUI.Print(AH.TAG, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY — firing deferred scan") end
            DoFire(pendingAuto)
        end)
    end
    readyWaiter:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
end


--
--  Start(auto):
--    auto = true → this is the auto-on-open scan; threaded into AH_SCAN_START
--                  so Core can word the start message differently.
--  The 15-min floor is ALWAYS honored (no force override — Auctionator proves
--  bypassing it just fires ReplicateItems into the server's own cooldown, which
--  is a silent no-op that looks like a failure).
--  Returns true if a scan was started, false + reason otherwise.
----------------------------------------------------------------
function AH.Replicate.Start(auto)
    if scanning then
        return false, "A scan is already running."
    end
    if not AH.isOpen then
        return false, "Open the Auction House first."
    end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        return false, "C_AuctionHouse.ReplicateItems unavailable."
    end

    local wait = AH.Replicate.SecondsUntilReady()
    if wait > 0 then
        return false, string.format("Next scan available in %d:%02d.",
            floor(wait / 60), wait % 60)
    end

    progress = 0
    AH.Events.Fire("AH_SCAN_START", auto and true or false)

    -- Fire the replicate request — but only once Blizzard's throttle/message system
    -- is READY. See FireWhenReady: on the FIRST AH open of a session the system isn't
    -- ready yet, and a ReplicateItems() fired too early is SILENTLY DROPPED (no
    -- REPLICATE_ITEM_LIST_UPDATE ever comes) — the confirmed "first-scan-of-session
    -- hangs at 0% until /reload" bug. We defer until AUCTION_HOUSE_THROTTLED_SYSTEM_READY
    -- instead. `scanning` is set TRUE only at the actual fire moment (inside
    -- FireWhenReady), never before — so a deferred-but-never-fired request can't strand
    -- the flag (which is exactly the stuck state we're fixing).
    FireWhenReady(auto)
    return true
end

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
ef:SetScript("OnEvent", function(_, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- DIAGNOSTIC (temp): print whenever the snapshot-ready event arrives, BEFORE
        -- the guard, so a "first-scan-of-the-day hang" can be classified:
        --   * line appears during a hang  → event DID fire; our guard dropped it
        --                                    (scanning/co state bug — fix in our code)
        --   * line NEVER appears in a hang → server never delivered the snapshot for
        --                                    the first request (readiness/timing — fix
        --                                    by deferring/retrying ReplicateItems)
        if VUI.debug then
            VUI.Print(AH.TAG, "REPLICATE_ITEM_LIST_UPDATE fired (scanning="
                .. tostring(scanning) .. ", co=" .. tostring(co ~= nil) .. ")")
        end
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
        if VUI.debug then VUI.Print(AH.TAG, "Scan aborted (AH closed).") end
    end
end)

----------------------------------------------------------------
--  Auto-scan on AH open
--
--  When the AH opens, kick off a scan to keep tooltip prices fresh so the user
--  never has to type /ah scan. Gated by the SAME 15-min floor as a manual scan,
--  so it silently no-ops if a scan ran recently — no spam on every AH visit.
--  Honors the db.settings.autoScan toggle (default ON when unset). Passes
--  auto=true so Core words the start message distinctly. The decline return
--  (too-recent / not-ready) is intentionally ignored: only a real start prints,
--  via the AH_SCAN_START event.
----------------------------------------------------------------
local function AutoScanEnabled()
    local s = AH.db and AH.db.settings
    if not s then return true end          -- default on before settings exist
    if s.autoScan == nil then return true end
    return s.autoScan
end

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

    if AutoScanEnabled() then
        AH.Replicate.Start(true)    -- auto=true (15-min floor always honored)
    end
end)
