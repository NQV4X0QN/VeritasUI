-- VeritasUI_AuctionHouse / Buy.lua
-- Phase 4 (Shopping tab) — PROTECTED PURCHASE engine.
--
-- ⚠️ This is the module's FIRST protected WRITE path. Buying is a restricted action
-- (StartCommoditiesPurchase has HasRestrictions=true at 12.0.5) and resolves design OQ#5:
-- "can our own hardware-event button call a protected C_AuctionHouse function taint-clean?"
-- Proven YES — verified in-game via a validation harness (since removed); the Shopping
-- tab's Buy button now drives this engine directly.
--
-- VERIFIED two-step commodity flow (Blizzard_AuctionHouseBuyDialog.lua, 12.0.5):
--   1. HARDWARE click -> C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
--        -> server quote -> COMMODITY_PRICE_UPDATED(updatedUnitPrice, updatedTotalPrice)
--           (or COMMODITY_PRICE_UNAVAILABLE).
--   2. SECOND HARDWARE click -> C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
--        -> COMMODITY_PURCHASE_SUCCEEDED (or COMMODITY_PURCHASE_FAILED).
--   Quote has a server-side duration (C_AuctionHouse.GetQuoteDurationRemaining); if it
--   lapses the purchase must be re-initiated. CancelCommoditiesPurchase() aborts a quote.
--
-- TAINT RULE (design §2.6/§2.7): the protected calls must originate from a genuine
-- hardware event (button OnClick) and must NOT be routed through the throttle queue
-- (which defers execution and would strip the hardware-event context). Searches that
-- FEED the buy still go through the queue; the buy CALLS themselves do not.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local C_AuctionHouse = C_AuctionHouse
local CreateFrame = CreateFrame

AH.Buy = {}

----------------------------------------------------------------
--  Purchase engine (commodity)
--
--  State machine for ONE in-flight commodity purchase. Callers:
--    AH.Buy.StartCommodity(itemID, quantity, onState)  -- call from a HARDWARE event
--    AH.Buy.ConfirmCommodity()                          -- call from a HARDWARE event
--    AH.Buy.CancelCommodity()
--  onState(state, ...) is the UI callback:
--    "quote"   (unitPrice, totalPrice)  -- quote ready; safe to confirm
--    "unavailable"                       -- price unavailable; must restart
--    "success"                           -- purchase completed
--    "failed"                            -- purchase failed
----------------------------------------------------------------
local buy = {
    active   = false,
    itemID   = nil,
    quantity = 0,
    quoted   = false,
    onState  = nil,
}

local function ResetBuy()
    buy.active   = false
    buy.itemID   = nil
    buy.quantity = 0
    buy.quoted   = false
    buy.onState  = nil
end

-- STEP 1 — must be called from a hardware event (button OnClick).
function AH.Buy.StartCommodity(itemID, quantity, onState)
    if not (C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase) then
        if onState then onState("failed", "API unavailable") end
        return false
    end
    if not AH.isOpen then
        if onState then onState("failed", "AH closed") end
        return false
    end

    buy.active   = true
    buy.itemID   = itemID
    buy.quantity = quantity
    buy.quoted   = false
    buy.onState  = onState

    -- PROTECTED CALL — direct, from the hardware-event caller. NOT queued.
    C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
    return true
end

-- STEP 2 — must be called from a hardware event (button OnClick), after a quote.
function AH.Buy.ConfirmCommodity()
    if not buy.active or not buy.quoted then return false end
    if not (C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase) then return false end
    -- PROTECTED CALL — direct, from the hardware-event caller. NOT queued.
    C_AuctionHouse.ConfirmCommoditiesPurchase(buy.itemID, buy.quantity)
    return true
end

function AH.Buy.CancelCommodity()
    if buy.active and C_AuctionHouse.CancelCommoditiesPurchase then
        C_AuctionHouse.CancelCommoditiesPurchase()
    end
    ResetBuy()
end

function AH.Buy.IsActive() return buy.active end

----------------------------------------------------------------
--  Item buyout (single-step, no quote)
--
--  Unlike a commodity (fungible; quoted then confirmed in two hardware clicks), an
--  ITEM auction (gear/pet — non-fungible, unique auctionID) is bought with a SINGLE
--  protected call: C_AuctionHouse.PlaceBid(auctionID, bidAmount) where bidAmount is the
--  auction's full buyout. There is no server quote round-trip — the Shopping detail
--  view's Buy button IS the confirmation (the same model as Blizzard's own item-buy
--  flow and Auctionator's BuyItemDialog — studied for reference only, zero code reuse).
--
--  PlaceBid HasRestrictions=true at 12.0.5 (verified §2.6, recorded OQ#5 / Progress Log
--  12), so the SAME taint rule proven for the commodity path applies verbatim: the call
--  MUST originate from a genuine hardware event and MUST NOT be routed through the
--  throttle queue (deferral strips the hardware-event context). The feeding SEARCH still
--  goes through the queue; this protected CALL does not.
--
--  No callback/quote machinery: PlaceBid is fire-and-go. The detail view re-runs its
--  drill-down query after the click to reflect the now-removed auction (a re-query is
--  self-evidently correct and needs no completion event whose exact name/payload we
--  can't verify against on-disk source right now).
----------------------------------------------------------------
function AH.Buy.BuyItem(auctionID, bidAmount)
    if not (C_AuctionHouse and C_AuctionHouse.PlaceBid) then return false end
    if not AH.isOpen then return false end
    if not auctionID or not bidAmount then return false end
    -- PROTECTED CALL — direct, from the hardware-event caller. NOT queued.
    C_AuctionHouse.PlaceBid(auctionID, bidAmount)
    return true
end

----------------------------------------------------------------
--  Event wiring — drives the quote/result callbacks
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("COMMODITY_PRICE_UPDATED")
ef:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
ef:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
ef:RegisterEvent("COMMODITY_PURCHASE_FAILED")

ef:SetScript("OnEvent", function(_, event, a1, a2)
    if not buy.active then return end
    local cb = buy.onState

    if event == "COMMODITY_PRICE_UPDATED" then
        buy.quoted = true
        if cb then cb("quote", a1, a2) end   -- updatedUnitPrice, updatedTotalPrice

    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if cb then cb("unavailable") end

    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if cb then cb("success") end
        ResetBuy()

    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if cb then cb("failed", "purchase failed") end
        ResetBuy()
    end
end)

-- Abort any in-flight quote if the AH closes.
if AH.Events and AH.Events.On then
    AH.Events.On("AH_CLOSED", function()
        if buy.active then ResetBuy() end
    end)
end
