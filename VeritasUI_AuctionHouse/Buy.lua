-- VeritasUI_AuctionHouse / Buy.lua
-- Phase 4 (Shopping tab) — PROTECTED PURCHASE engine + validation harness.
--
-- ⚠️ This is the module's FIRST protected WRITE path. Buying is a restricted action
-- (StartCommoditiesPurchase has HasRestrictions=true at 12.0.5) and directly tests
-- design OQ#5: "can our own hardware-event button call a protected C_AuctionHouse
-- function taint-clean?" Everything prior (scan, tooltips, browse, drill-down) was
-- read-only. We validate this in isolation BEFORE building the Buy UI around it.
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
--
-- The validation harness (/ah buytest) creates a real on-screen button the user clicks,
-- because a button OnClick is an unambiguous hardware event (a slash handler's
-- hardware-event status is murkier). If this proves taint-clean, the same engine powers
-- the Shopping tab's Buy Now; if blocked, we fall back to mirroring Blizzard's dialog.

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

----------------------------------------------------------------
--  Validation harness:  /ah buytest <itemID> [qty]
--
--  Creates a real, centered confirm button (hardware-event source). First click
--  initiates the purchase + quote; once the quote arrives the button relabels to show
--  the total and a second click confirms. This is the OQ#5 taint test — watch for a
--  blocked-action / taint error on either protected call.
----------------------------------------------------------------
local harness  -- the test button frame (created on first use)

local function EnsureHarness()
    if harness then return harness end

    local b = CreateFrame("Button", "VUI_AH_BuyTestButton", UIParent, "UIPanelButtonTemplate")
    b:SetSize(280, 32)
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    b:SetFrameStrata("DIALOG")
    b:Hide()

    -- A small close/cancel handle (right-click cancels the test).
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            AH.Buy.CancelCommodity()
            self:Hide()
            VUI.Print(AH.TAG, "Buy test cancelled.")
            return
        end

        if not AH.Buy.IsActive() then
            -- FIRST hardware click → initiate purchase + request quote.
            VUI.Print(AH.TAG, "buytest: calling StartCommoditiesPurchase (PROTECTED)...")
            self:SetText("Requesting quote...")
            self:Disable()
            AH.Buy.StartCommodity(self._itemID, self._qty, function(state, p1, p2)
                if state == "quote" then
                    local total = AH.Money and AH.Money.Format(p2) or tostring(p2)
                    self:Enable()
                    self:SetText("CONFIRM BUY  " .. tostring(self._qty) .. "x  =  " .. total)
                    self._readyToConfirm = true
                    VUI.Print(AH.TAG, "buytest: quote received — click again to confirm, right-click to cancel.")
                elseif state == "unavailable" then
                    self:Enable()
                    self:SetText("Price unavailable — click to retry")
                    self._readyToConfirm = false
                    VUI.Print(AH.TAG, "|cFFFFFF00buytest: price unavailable.|r")
                elseif state == "success" then
                    self:Hide()
                    VUI.Print(AH.TAG, "|cFF00FF00buytest: PURCHASE SUCCEEDED — protected path is TAINT-CLEAN.|r")
                elseif state == "failed" then
                    self:Enable()
                    self:SetText("Failed — click to retry")
                    self._readyToConfirm = false
                    VUI.Print(AH.TAG, "|cFFFF4444buytest: purchase failed:|r " .. tostring(p1))
                end
            end)

        elseif self._readyToConfirm then
            -- SECOND hardware click → confirm the quoted purchase.
            VUI.Print(AH.TAG, "buytest: calling ConfirmCommoditiesPurchase (PROTECTED)...")
            self._readyToConfirm = false
            self:SetText("Purchasing...")
            self:Disable()
            -- Re-enable shortly in case neither success nor fail fires (so the button
            -- isn't stuck), mirroring Blizzard's 2s safety timer.
            C_Timer.After(2, function()
                if self:IsShown() and not self:IsEnabled() then
                    self:Enable()
                    self:SetText("(no result yet) — click to retry")
                end
            end)
            AH.Buy.ConfirmCommodity()
        end
    end)

    harness = b
    return b
end

function AH.Buy.RunTest(itemID, qty)
    if not AH.isOpen then
        VUI.Print(AH.TAG, "Open the Auction House first, then /ah buytest <itemID> [qty].")
        return
    end
    itemID = tonumber(itemID)
    qty = tonumber(qty) or 1
    if not itemID then
        VUI.Print(AH.TAG, "Usage: |cFFFFFF00/ah buytest <itemID> [quantity]|r (commodity items only).")
        return
    end

    -- Prime the client with a commodity search first so the quote system has data.
    VUI.Print(AH.TAG, "buytest: searching commodity " .. itemID .. " x" .. qty .. " ...")
    AH.Search.QueryItem({ itemKey = C_AuctionHouse.MakeItemKey(itemID) }, function(state, data)
        if state == "results" and data and data.isCommodity then
            local b = EnsureHarness()
            b._itemID = itemID
            b._qty = qty
            b._readyToConfirm = false
            b:Enable()
            b:SetText("Buy " .. qty .. "x  (itemID " .. itemID .. ") — click to quote")
            b:Show()
            VUI.Print(AH.TAG, "buytest: commodity found — CLICK THE CENTERED BUTTON to test the protected buy. Right-click cancels.")
        elseif state == "results" and data and not data.isCommodity then
            VUI.Print(AH.TAG, "|cFFFFFF00buytest: that itemID is an ITEM, not a commodity.|r This harness tests the commodity path only.")
        elseif state == "empty" then
            VUI.Print(AH.TAG, "buytest: no auctions found for that itemID.")
        elseif state == "failed" then
            VUI.Print(AH.TAG, "|cFFFF4444buytest: search failed:|r " .. tostring(data))
        end
    end)
end
