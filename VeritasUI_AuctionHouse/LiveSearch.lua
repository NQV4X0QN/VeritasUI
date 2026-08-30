-- VeritasUI_AuctionHouse / LiveSearch.lua
-- Record AUTHORITATIVE per-item prices from the auction house's OWN live searches.
--
-- ── WHY THIS EXISTS ──
-- The browse engine's `minPrice` is not the live lowest unit buyout. Measured twice,
-- both times with /ah browseprobe against Blizzard's ascending Sell-tab ladder at the
-- same moment:
--   2026-08-04  item 242639  browse 27500   cheapest listing 29800   ( -7.7% )
--   2026-08-29  item 237365  browse 204900  cheapest listing 352200  ( -41.8% )
-- The second capture is the important one, and it kills two earlier beliefs:
--   1. The gap is NOT bounded at ~7.7%. Tooltip.lua's decomposition block said only
--      7.7% was attributable to browse and the rest was scan staleness. On 237365 the
--      market had NOT moved -- the ladder read 352200 continuously while the probe ran
--      -- and browse was still 41.8% low.
--   2. It is not a stale whole-summary snapshot. `totalQuantity` came back 187985
--      against the tab's own 187986 Available -- accurate to ONE unit -- in the SAME
--      response as the bad price. Correct population, wrong price, one payload.
-- No reading of the market makes 204900 valid: it is below the price of a single unit
-- at the cheapest listing, so it is neither a unit price nor a stack total.
-- BrowseResultInfo carries exactly one price field (itemKey, appearanceLink,
-- totalQuantity, minPrice, containsOwnerItem), so there is no better field to read and
-- no fix available on the browse summary path itself.
--
-- ── WHAT THIS DOES INSTEAD ──
-- When you load an item into the Sell form, or open a commodity on the Buy tab, the
-- client has ALREADY run an authoritative per-item search -- Blizzard's own suggested
-- Unit Price comes from it (Blizzard_AuctionHouseCommoditiesSellFrame.lua:48-62 reads
-- GetCommoditySearchResultInfo(itemID, 1).unitPrice). Those results are sitting in the
-- client for free. This file listens for them and folds them into the price DB with
-- the SAME semantics the scan engines use, so the stored price for any item you
-- actually handle is corrected to the real ladder.
--
-- ⚠ It costs NOTHING. It sends no query of its own, so the ~100/min SendSearchQuery
-- cap is irrelevant here -- that cap is why a whole-AH scan cannot be built this way,
-- and why this is a CORRECTION layer over the scan rather than a replacement for it.
-- It fixes the items you look at. The other ~20,000 still come from the scan.
--
-- ⚠ IT MUST NEVER STAMP AH.db.lastScan. That field is the shared 15-minute scan floor
-- (Browse.lua Finish / AH.Replicate.SecondsUntilReady). Writing it here would let
-- ordinary sell-form browsing starve the real scan of its allowance.
--
-- ── TAINT POSTURE ──
-- This file mutates NOTHING of Blizzard's. It owns its own frame, registers two public
-- events on it, and calls read-only C_AuctionHouse getters. No Blizzard frame method,
-- no Blizzard table write, no hook on the sell form. That last point is deliberate:
-- SellStrip.lua reaches Blizzard's sell forms and had to move its own marker OFF the
-- frame at v1.15.4 precisely because SetItem -> CanPostItem -> C_AuctionHouse.
-- PostCommodity is a sensitive path with a crash history. Listening to an event that
-- already carries the item identity avoids that surface completely.
--
-- All four getters are declared SecretArguments = "AllowedWhenUntainted" in
-- AuctionHouseDocumentation.lua, so every call is pcall'd per the suite's standing rule.
--
-- ── RESIDUAL, UNMEASURED, RECORDED HONESTLY ──
-- The Auctions tab queries by item too (Blizzard_AuctionHouseFrame.lua:747 passes
-- separateOwnerItems = TRUE there, FALSE for Buy/Sell), and what "separate" does to the
-- returned result list is NOT documented and NOT measured. We record from it anyway,
-- because the dangerous reading -- that it returns only YOUR auctions -- is contradicted
-- by Blizzard_AuctionHouseAuctionsFrame.lua:236, where owner-only rows come from a
-- dedicated API (GetOwnedAuctionInfo / GetNumOwnedAuctions) that would be unnecessary if
-- the search query could produce them. Either surviving reading is harmless: owner rows
-- excluded gives the market min without you in it, owner rows included gives the true
-- min including you, which is what browse already reports.
-- ⚠ THE FALSIFYING OBSERVATION, if this is ever wrong: the stored price of an item YOU
-- HAVE POSTED starts tracking YOUR OWN posting price rather than the ladder. If that
-- shows up, gate this on the display mode being a Buy/Sell one and measure it properly.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
--
--  The commodity handler runs once per search-results event -- interactive rates, not
--  the ~20k/scan of Browse.AddPrices -- but the inner loop walks every listing of the
--  item, so keep the loop's lookups local.
----------------------------------------------------------------
local pcall  = pcall
local type   = type
local format = string.format
local min    = math.min

AH.LiveSearch = {}

-- Hard cap on the per-item listing walk. A commodity ladder is short (tens of rows),
-- but the count comes from the server and this loop runs on a UI event, so it is
-- bounded rather than trusted. Exceeding it is not an error and not data loss: the
-- results are sorted ascending by unit price (Blizzard's own auto-populate takes index
-- 1 and treats it as the price to match), so the minimum is at the FRONT and a partial
-- walk still finds it. The cap only protects against a pathological count.
local MAX_RESULTS = 500

-- Ring of the most recent corrections, for /ah live. Small on purpose: this is a
-- "is it working" readout, not a price history -- Database.lua already keeps per-day
-- min/max/qty for that.
local RECENT_MAX = 8

local observed  = 0   -- search-result events we acted on
local recorded  = 0   -- items written to the DB
local corrected = 0   -- writes that CHANGED the stored market price
local recent    = {}  -- newest last: { key=, old=, new= }

----------------------------------------------------------------
--  Commit one observation
--
--  Deliberately routed through AH.DB.Record, the same writer both scan engines use, so
--  a live-search price is indistinguishable in storage from a scanned one and the
--  per-day min/max/qty history stays continuous. Record() overwrites rec.market
--  unconditionally and refreshes rec.seen, which is exactly right here: this value is
--  both newer AND from a more authoritative endpoint than the scan's.
--
--  ⚠ The tooltip reads rec.market (AH.DB.GetMarketPrice), NOT days[day].min. That
--  matters: Record keeps the per-day MINIMUM, so a bogus low from an earlier scan stays
--  in the day's history while rec.market becomes correct. Repairing the historical min
--  is deliberately out of scope -- nothing reads it, and rewriting recorded history to
--  make a display look right is the wrong trade.
----------------------------------------------------------------
local function Commit(key, unitPrice, qty)
    if not key or not unitPrice or unitPrice <= 0 then return end
    if not (AH.db and AH.DB) then return end

    local old = AH.DB.GetMarketPrice(key)
    AH.DB.Record(key, unitPrice, qty)
    recorded = recorded + 1

    if old ~= unitPrice then
        corrected = corrected + 1
        recent[#recent + 1] = { key = key, old = old, new = unitPrice }
        if #recent > RECENT_MAX then table.remove(recent, 1) end
        if VUI.debug then
            VUI.Print(AH.TAG, format("livesearch %s: %s -> %s",
                key, tostring(old), tostring(unitPrice)))
        end
    end
end

----------------------------------------------------------------
--  COMMODITY_SEARCH_RESULTS_UPDATED  (payload: itemID)
--
--  Keyed through MakeKeyFromItemID, which is the same bare-itemID derivation MakeKey
--  falls through to for non-gear AND which refuses gear outright. A commodity search
--  can only ever concern a commodity, so that refusal is unreachable here -- but using
--  the shared helper rather than concatenating "i:" .. itemID keeps this file out of the
--  three-copy gear predicate Database.lua warns about.
--
--  Quantity comes from GetCommoditySearchResultsQuantity, the server's own total for the
--  item -- the direct analogue of browse's totalQuantity, and not a sum over the walked
--  page, so pagination cannot understate it.
----------------------------------------------------------------
local function OnCommodityResults(itemID)
    if type(itemID) ~= "number" or itemID <= 0 then return end
    if not AH.Setting("liveSearchPrices") then return end
    if not (AH.db and AH.DB) then return end

    local key = AH.DB.MakeKeyFromItemID(itemID)
    if not key then return end

    local okCount, count = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not okCount or type(count) ~= "number" or count <= 0 then return end

    local best
    for i = 1, min(count, MAX_RESULTS) do
        local okInfo, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if okInfo and type(info) == "table" then
            local unit = info.unitPrice
            if type(unit) == "number" and unit > 0 and (not best or unit < best) then
                best = unit
            end
        end
    end
    if not best then return end

    local okQty, qty = pcall(C_AuctionHouse.GetCommoditySearchResultsQuantity, itemID)
    if not okQty or type(qty) ~= "number" or qty < 0 then qty = nil end

    observed = observed + 1
    Commit(key, best, qty)
end

----------------------------------------------------------------
--  ITEM_SEARCH_RESULTS_UPDATED  (payload: itemKey)
--
--  The payload is an ItemKey, which MakeKeyFromItemKey already consumes -- gear item
--  level and battle-pet species arrive in it, so this path needs no link and no new key
--  logic at all.
--
--  BID-ONLY AUCTIONS ARE SKIPPED. ItemSearchResultInfo.buyoutAmount is Nilable and a
--  bid-only listing has no buyout; Replicate skips those rows and Browse counts them as
--  skipNoPrice, so including them here would make a live-search price mean something
--  different from a scanned one for the same item.
--
--  ⚠⚠ `buyoutAmount` IS THE PRICE. DO NOT DIVIDE IT BY `quantity`. v1.16.0 did exactly
--  that -- `floor(buyoutAmount / quantity)`, on the stated reasoning that it "matched
--  Replicate's floor(buyout/count)" -- and it was WRONG, because the two `quantity` fields
--  are not the same thing:
--    * Replicate's `count` comes from GetReplicateItemInfo and IS a per-auction stack size,
--      so dividing is right there.
--    * ItemSearchResultInfo's `quantity` is the number of AUCTIONS GROUPED AT THAT PRICE --
--      the count column the native item list renders -- so dividing turns one auction's
--      price into a fraction of itself.
--  MEASURED 2026-08-29, item 275334 (Pattern: Stretched Snakeskin Rack): three auctions at
--  a 50000 buyout, one at 100000. The native ladder and the Sell tab's Buyout Price both
--  read 50000; we stored floor(50000/3) = 16666 and the tooltip showed 1g66s66c against a
--  real cheapest of 5g. Off by the number of competing sellers, which is the worst possible
--  shape: it looks like a plausible price and it moves as the market changes.
--  SOURCE: Blizzard_AuctionHouseItemSellFrame.lua:325 does
--  `self.PriceInput:SetAmount(searchResult.buyoutAmount or 0)` -- straight through, no
--  division -- and :135-138 sorts by raw `buyoutAmount`. There is no per-unit arithmetic on
--  this path anywhere in Blizzard's code, because a non-commodity auction is one item.
--
--  ⚠ `quantity` IS still the right thing to SUM for the qty field: summing it across the
--  ladder gives the item's total availability (3 + 1 = 4 above, matching both the tab's
--  "4 Available" and browse's qty=4). It is the price that must not touch it.
--  There is no GetItemSearchResultsQuantity, so that sum is a floor, not a total, when the
--  set is paginated. Safe: Record only ever RAISES a day's qty (`if qty > d.qty`), so an
--  undercount cannot overwrite a better figure from a scan.
----------------------------------------------------------------
local function OnItemResults(itemKey)
    if type(itemKey) ~= "table" then return end
    if not AH.Setting("liveSearchPrices") then return end
    if not (AH.db and AH.DB) then return end

    local key = AH.DB.MakeKeyFromItemKey(itemKey)
    if not key then return end

    local okCount, count = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not okCount or type(count) ~= "number" or count <= 0 then return end

    local best, qtySum = nil, 0
    for i = 1, min(count, MAX_RESULTS) do
        local okInfo, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if okInfo and type(info) == "table" then
            local buyout = info.buyoutAmount
            local n = info.quantity
            if type(n) ~= "number" or n <= 0 then n = 1 end
            if type(buyout) == "number" and buyout > 0 then
                -- NO DIVISION. See the block above: buyoutAmount is already this auction's
                -- price, and `quantity` counts competing auctions at it.
                if not best or buyout < best then best = buyout end
                qtySum = qtySum + n
            end
        end
    end
    if not best then return end

    observed = observed + 1
    Commit(key, best, qtySum > 0 and qtySum or nil)
end

----------------------------------------------------------------
--  Event plumbing
--
--  Our OWN frame. Deliberately NOT gated on AH.isOpen: these events cannot fire outside
--  an auction house session, and an ordering guard would only be able to DROP a valid
--  observation if the event ever landed before AUCTION_HOUSE_SHOW was processed.
----------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        OnCommodityResults(arg1)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        OnItemResults(arg1)
    end
end)

----------------------------------------------------------------
--  Public readout (/ah live, /ah diag)
----------------------------------------------------------------
function AH.LiveSearch.Stats()
    return observed, recorded, corrected
end

function AH.LiveSearch.Recent()
    return recent
end

-- Exposed for the headless suite.
AH.LiveSearch._OnCommodityResults = OnCommodityResults
AH.LiveSearch._OnItemResults      = OnItemResults
