-- VeritasUI_AuctionHouse / Throttle.lua
-- Mandatory AH send-queue (design §2.7).
--
-- Blizzard rate-limits AH server traffic and exposes IsThrottledMessageSystemReady()
-- plus the AUCTION_HOUSE_THROTTLED_* event family. Blizzard's own SellFrame gates
-- on IsThrottledMessageSystemReady() before posting. Every outbound AH query
-- (browse / search / replicate / owned-auctions) in later phases MUST go through
-- this queue rather than calling C_AuctionHouse directly.
--
-- Contract:
--   AH.Throttle.Enqueue(fn[, label])  -- defer an AH send; runs fn() when ready
--   AH.Throttle.Clear()               -- drop all pending (called on AH close)
--   AH.Throttle.PendingCount()        -- diagnostics
--
-- Dispatch model:
--   * We only ever have ONE send in flight (Blizzard's throttle is global), so
--     we dispatch the head of the queue, then wait for the system to report
--     ready again before sending the next.
--   * THROTTLED_SYSTEM_READY re-arms us to send the next item.
--   * THROTTLED_MESSAGE_DROPPED means the last send was rejected by the client
--     throttler — we re-queue it at the head and try again when ready.
--   * AUCTION_HOUSE_CLOSED clears everything (queries are invalid with the AH shut).

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local C_AuctionHouse = C_AuctionHouse
local tinsert  = table.insert
local tremove  = table.remove

AH.Throttle = {}

local queue        = {}      -- array of { fn = function, label = string }
local lastDispatched          -- the item most recently sent (for DROPPED retry)
local awaitingReady = false    -- true once we've sent and are waiting for READY

-- Is the AH throttle system ready to accept another send right now?
local function SystemReady()
    if not (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady) then
        return false
    end
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return ok and ready or false
end

-- Try to dispatch the head of the queue if the system is ready and nothing is
-- currently in flight. Safe to call repeatedly (idempotent when not ready /
-- already awaiting / queue empty).
local function TryDispatch()
    if awaitingReady then return end
    if #queue == 0 then return end
    if not SystemReady() then return end

    local item = tremove(queue, 1)
    lastDispatched = item
    awaitingReady  = true

    local ok, err = pcall(item.fn)
    if not ok then
        -- The send function itself errored (not a throttle rejection). Surface
        -- under VUI.debug, drop it (don't retry a broken closure), and re-arm so
        -- the rest of the queue still drains.
        if VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444Throttle send error|r ("
                .. tostring(item.label or "?") .. "): " .. tostring(err))
        end
        lastDispatched = nil
        awaitingReady  = false
        TryDispatch()
    end
end

-- Public: defer an AH send. fn should call exactly one C_AuctionHouse query.
function AH.Throttle.Enqueue(fn, label)
    if type(fn) ~= "function" then return end
    tinsert(queue, { fn = fn, label = label })
    TryDispatch()
end

-- Public: drop everything pending and reset in-flight state.
function AH.Throttle.Clear()
    wipe(queue)
    lastDispatched = nil
    awaitingReady  = false
end

-- Public: how many sends are waiting (excludes the in-flight one).
function AH.Throttle.PendingCount()
    return #queue
end

-- Public: are we mid-flight waiting for the system to re-arm?
function AH.Throttle.IsAwaiting()
    return awaitingReady
end

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
ef:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")

ef:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        -- The throttler is ready for the next send.
        awaitingReady = false
        lastDispatched = nil
        TryDispatch()

    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        -- The last send was rejected by the client throttler. Put it back at the
        -- head and retry when the system reports ready again.
        if lastDispatched then
            tinsert(queue, 1, lastDispatched)
            lastDispatched = nil
        end
        awaitingReady = false
        if VUI.debug then
            VUI.Print(AH.TAG, "|cFFFFFF00Throttled message dropped|r — re-queued.")
        end
        TryDispatch()
    end
end)

-- Lifecycle hook: Core fires "AH_CLOSED" on AUCTION_HOUSE_CLOSED. Clear the queue
-- then — pending queries are invalid once the AH is shut. (Subscribed here so the
-- throttle owns its own teardown rather than Core reaching into it.)
if AH.Events and AH.Events.On then
    AH.Events.On("AH_CLOSED", function()
        AH.Throttle.Clear()
    end)
end
