-- VeritasUI_AuctionHouse / Replicate.lua
-- Full-scan driver (Phase 2). The ONLY sanctioned whole-AH snapshot is
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
-- Per-row policy (Phase 2 decisions):
--   * key  = AH.DB.MakeKey(link)  (gear keyed by itemID:ilvl, pets by speciesID,
--            everything else by itemID — design §2.2/§2.4)
--   * skip bid-only rows (buyoutPrice == 0): the DB tracks buyout market price
--   * unitPrice = floor(buyoutPrice / count) so stacks/commodities normalize
--   * aggregate per key within a scan: keep the min unit price + max qty seen,
--     then write once per key at the end (one DB.Record call per item, not per row)
--
-- Scan floor: Blizzard/-server throttle replicate heavily; we enforce a 15-min
-- minimum between scans (design §2.2), persisted across sessions.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local C_AuctionHouse = C_AuctionHouse
local floor      = math.floor
local time       = time
local coroutine  = coroutine
local CreateFrame = CreateFrame

AH.Replicate = {}

local SCAN_FLOOR_SECONDS = 15 * 60   -- minimum gap between full scans
local ROWS_PER_SLICE     = 2000      -- safety cap on rows per frame
local FRAME_BUDGET_MS    = 8         -- ~8ms/frame work budget (debugprofilestop)

local scanning   = false   -- a scan coroutine is in progress
local co                    -- the active coroutine
local driver               -- OnUpdate ticker frame
local progress   = 0        -- 0..1

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

        -- Progress + frame-budget yield.
        sliceCount = sliceCount + 1
        if sliceCount >= ROWS_PER_SLICE
           or (debugprofilestop() - sliceStart) >= FRAME_BUDGET_MS then
            progress = (i + 1) / num
            AH.Events.Fire("AH_SCAN_PROGRESS", progress)
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
--  Public: kick off a scan
--
--  Returns true if a scan was started, false + reason otherwise.
----------------------------------------------------------------
function AH.Replicate.Start(force)
    if scanning then
        return false, "A scan is already running."
    end
    if not AH.isOpen then
        return false, "Open the Auction House first."
    end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        return false, "C_AuctionHouse.ReplicateItems unavailable."
    end

    if not force then
        local wait = AH.Replicate.SecondsUntilReady()
        if wait > 0 then
            return false, string.format("Next scan available in %d:%02d.",
                floor(wait / 60), wait % 60)
        end
    end

    progress = 0
    scanning = true
    AH.Events.Fire("AH_SCAN_START")

    -- Fire the replicate request; the actual row read happens when
    -- REPLICATE_ITEM_LIST_UPDATE fires (handled below).
    C_AuctionHouse.ReplicateItems()
    return true
end

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
ef:SetScript("OnEvent", function(_, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
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
