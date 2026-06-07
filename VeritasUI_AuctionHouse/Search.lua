-- VeritasUI_AuctionHouse / Search.lua
-- Phase 4: the AH query layer. Two independent sub-systems, both data-only (no UI):
--
--   1. BROWSE  — keyword search of the whole AH via SendBrowseQuery. Returns
--      lightweight per-item summaries (itemKey, totalQuantity, minPrice). Robust;
--      no item-cache dependency. Paginates to completion. Fires events on AH.Events.
--
--   2. ITEM SCAN (drill-down) — per-item detail via SendSearchQuery for one itemKey,
--      returning the individual auctions. This API has TWO documented failure modes
--      (design §2.3) that a naive caller hits as a silent hang or a false "empty":
--        (a) the call is SILENTLY IGNORED if the item's key info isn't cached yet;
--        (b) the results event sometimes reports ZERO results when results exist.
--      The scan engine below handles both by construction:
--        - CACHE GATE: poll C_AuctionHouse.GetItemKeyInfo(itemKey) until non-nil
--          before sending (also tells us item-vs-commodity).
--        - VALIDATE & RETRY: after a results event, re-check HasSearchResults +
--          HasFull*SearchResults + quantity; if empty-but-incomplete, re-issue.
--        - REQUEST MATCHING: each scan has a token; incoming events are matched to
--          the ACTIVE request so a rapid re-click never renders stale results.
--        - BOUNDED TIMEOUT: if the key never caches or results never arrive, fail
--          cleanly (never an infinite spinner).
--        - PROGRESSIVE: delivers partial pages as they arrive (data.isFull flags
--          completeness), paginating via RequestMore*SearchResults until full.
--      The identical cache landmine affects Phase 5's SendSellSearchQuery, so this
--      engine is built as a reusable foundation, not a one-off.
--
-- ALL outbound server sends route through AH.Throttle (Phase 1). The only sanctioned
-- whole-AH snapshot remains ReplicateItems (Replicate.lua); SendSearchQuery is capped
-- at 100/min and is used ONLY for single-item drill-down here.
--
-- Verified against Blizzard 12.0.5 API docs (AuctionHouseDocumentation.lua):
--   SendBrowseQuery(query={searchString,sorts,minLevel?,maxLevel?,filters?,itemClassFilters?})
--   HasFullBrowseResults() / GetBrowseResults() -> {BrowseResultInfo} / RequestMoreBrowseResults()
--   GetItemKeyInfo(itemKey) -> ItemKeyInfo? {itemName,quality,iconFileID,isCommodity,isPet,...}
--   SendSearchQuery(itemKey, sorts, separateOwnerItems, minLevelFilter=0, maxLevelFilter=0)
--   HasSearchResults(itemKey) / HasFullItemSearchResults(itemKey) / GetItemSearchResultsQuantity(itemKey)
--   GetNumItemSearchResults(itemKey) / GetItemSearchResultInfo(itemKey, luaIndex)
--   RequestMoreItemSearchResults(itemKey)
--   HasFullCommoditySearchResults(itemID) / GetCommoditySearchResultsQuantity(itemID)
--   GetNumCommoditySearchResults(itemID) / GetCommoditySearchResultInfo(itemID, luaIndex)
--   RequestMoreCommoditySearchResults(itemID) / MakeItemKey(itemID, itemLevel, itemSuffix, speciesID)
-- Events: AUCTION_HOUSE_BROWSE_RESULTS_UPDATED (no payload) / _ADDED (addedResults) /
--   _BROWSE_FAILURE; ITEM_SEARCH_RESULTS_UPDATED (itemKey, newAuctionID?) / _ADDED (itemKey);
--   COMMODITY_SEARCH_RESULTS_UPDATED (itemID) / COMMODITY_SEARCH_RESULTS_RECEIVED.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local C_AuctionHouse = C_AuctionHouse
local ipairs   = ipairs
local type     = type
local tconcat  = table.concat
local floor    = math.floor
local GetTime  = GetTime
local strtrim  = strtrim

AH.Search = {}

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
-- Cheapest-first sort (Enum.AuctionHouseSortOrder.Price = 0, ascending).
local PRICE_SORT = {
    { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0,
      reverseSort = false },
}

local SCAN_TIMEOUT   = 10.0   -- seconds before a drill-down scan fails cleanly
local SCAN_POLL_RATE = 0.1    -- cache-gate / deadline poll cadence (10 Hz)
local SCAN_MAX_TRIES = 8      -- bound on validate-and-retry re-issues per scan

----------------------------------------------------------------
--  Small helpers
----------------------------------------------------------------
-- Stable string identity for an ItemKey (matches the 4-field join Blizzard's UI
-- uses); lets us compare an incoming event's key to our active request's key.
local function ItemKeyString(k)
    if type(k) ~= "table" then return "" end
    return (k.itemID or 0) .. " " .. (k.itemSuffix or 0) .. " "
        .. (k.itemLevel or 0) .. " " .. (k.battlePetSpeciesID or 0)
end

-- Owners[] -> display string ("Alice, Bob"); empty when unknown.
local function OwnersText(owners)
    if type(owners) ~= "table" or #owners == 0 then return "" end
    return tconcat(owners, ", ")
end

-- Normalize a raw search string into what SendBrowseQuery's `searchString` expects:
-- the plain item NAME. Players commonly shift-click an item (or paste a link) into a
-- search box, producing a full hyperlink:
--    |cffa335ee|Hitem:212398::...|h[Nightfall Curseblade's Warglaive]|h|r
-- The AH server matches on the visible name, so a link-laden string matches NOTHING
-- (returns 0 results even when the item is listed — observed in-game). We extract the
-- bracketed display name from any hyperlink; if there's no link, we strip any stray
-- color/escape codes and return the trimmed plain text unchanged.
-- Returns the cleaned string (never nil; "" if input is empty/garbage).
local function NormalizeSearchTerm(raw)
    if type(raw) ~= "string" then return "" end

    -- Pull the FIRST hyperlink's display text: ...|h[Name]|h...
    local linkName = raw:match("|H.-|h%[(.-)%]|h")
    if linkName and linkName ~= "" then
        return linkName
    end

    -- Bare battlepet/item links sometimes appear without the bracket wrapper; fall
    -- back to stripping all WoW escape sequences (|c..|r color, |H..|h link, |T..|t
    -- texture, |A..|a atlas) and trimming what's left.
    local s = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                 :gsub("|H.-|h", ""):gsub("|h", "")
                 :gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return strtrim(s)
end
AH.Search.NormalizeSearchTerm = NormalizeSearchTerm   -- exposed for the UI search box

----------------------------------------------------------------
--  BROWSE sub-system
----------------------------------------------------------------
local browse = {
    active  = false,
    token   = 0,       -- monotonic; guards stale paginate callbacks
    term    = nil,
    results = nil,     -- last GetBrowseResults() snapshot
}

-- Adapt a BrowseResultInfo into a flat, UI-friendly row. NOTE: name/icon/quality are
-- NOT on BrowseResultInfo — the consumer resolves those via AH.Search.GetKeyInfo
-- (async-cached). We pass the itemKey + the cheap summary fields through verbatim.
local function AdaptBrowseResult(r)
    return {
        itemKey          = r.itemKey,
        itemID           = r.itemKey and r.itemKey.itemID,
        appearanceLink   = r.appearanceLink,
        totalQuantity    = r.totalQuantity or 0,
        minPrice         = r.minPrice or 0,   -- live lowest unit/buyout, copper int
        containsOwnerItem = r.containsOwnerItem or false,
    }
end

local function AdaptBrowseList(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, #list do
            out[i] = AdaptBrowseResult(list[i])
        end
    end
    return out
end

-- Public: start a keyword browse. opts (all optional):
--   filters          = { Enum.AuctionHouseFilter.* }   (e.g. quality)
--   itemClassFilters = { ... }
--   minLevel, maxLevel = number
--   sorts            = AuctionHouseSortType[]  (defaults to cheapest-first)
function AH.Search.Browse(term, opts)
    if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then return false end
    if not AH.isOpen then
        VUI.Print(AH.TAG, "Open the Auction House first.")
        return false
    end
    opts = opts or {}

    -- Normalize: a shift-clicked item / pasted link becomes its plain name, which is
    -- what the AH server matches on (a raw |Hitem:..|h string matches nothing).
    local searchString = NormalizeSearchTerm(term)

    browse.token   = browse.token + 1
    browse.active  = true
    browse.term    = searchString
    browse.results = nil

    local query = {
        searchString     = searchString,
        filters          = opts.filters or {},
        itemClassFilters = opts.itemClassFilters or {},
        sorts            = opts.sorts or PRICE_SORT,
    }
    if opts.minLevel then query.minLevel = opts.minLevel end
    if opts.maxLevel then query.maxLevel = opts.maxLevel end

    AH.Events.Fire("AH_BROWSE_START", browse.term)
    AH.Throttle.Enqueue(function()
        C_AuctionHouse.SendBrowseQuery(query)
    end, "browse")
    return true
end

function AH.Search.IsBrowsing()    return browse.active end
function AH.Search.GetBrowseTerm() return browse.term end

-- Pass-through for async key info (name/icon/quality/isCommodity). May be nil until
-- Blizzard caches it; callers re-resolve on ITEM_KEY_ITEM_INFO_RECEIVED if needed.
function AH.Search.GetKeyInfo(itemKey)
    if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and itemKey) then return nil end
    local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
    return ok and info or nil
end

-- Internal: a browse results event arrived (UPDATED has no payload → re-read;
-- ADDED carries the delta but we re-read the full set for a consistent snapshot).
local function OnBrowseResults()
    if not browse.active then return end

    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    browse.results = ok and results or {}

    local full = true
    if C_AuctionHouse.HasFullBrowseResults then
        local okf, hf = pcall(C_AuctionHouse.HasFullBrowseResults)
        full = okf and hf or false
    end

    AH.Events.Fire("AH_BROWSE_UPDATE", AdaptBrowseList(browse.results), full)

    if not full then
        -- Page in the rest (throttled), guarded against a stale browse superseding us.
        local myToken = browse.token
        AH.Throttle.Enqueue(function()
            if browse.active and browse.token == myToken then
                C_AuctionHouse.RequestMoreBrowseResults()
            end
        end, "browse-more")
    else
        browse.active = false
    end
end

local function OnBrowseFailure()
    if not browse.active then return end
    browse.active = false
    AH.Events.Fire("AH_BROWSE_FAILED")
end

----------------------------------------------------------------
--  ITEM SCAN sub-system (drill-down) — the search-scan engine
--
--  Single active request at a time (the UI shows one item's detail at once); a new
--  QueryItem supersedes any in-flight one. Callback contract:
--    cb("results", { isCommodity=bool, entries={...}, isFull=bool })  -- may fire >1x
--    cb("empty")    -- confirmed full with zero results
--    cb("failed", reason)  -- timeout / bad input / API missing
--  Entry shape (normalized across item & commodity):
--    { unitPrice, quantity, timeLeftSeconds, owners (string), itemLink?, auctionID,
--      isCommodity, containsOwnerItem }
----------------------------------------------------------------
local scan = {
    active      = false,
    token       = 0,
    phase       = nil,    -- "caching" | "searching"
    itemKey     = nil,
    keyString   = nil,
    itemID      = nil,
    isCommodity = nil,    -- resolved from key info once cached
    deadline    = 0,
    tries       = 0,
    callback    = nil,
    pollAccum   = 0,
}
local scanDriver   -- OnUpdate frame (cache-gate poll + deadline watch)

local function ScanFinish(active)
    scan.active = false
    scan.phase  = nil
    if scanDriver then scanDriver:Hide() end
end

local function ScanFail(reason)
    if not scan.active then return end
    local cb = scan.callback
    ScanFinish(false)
    if cb then pcall(cb, "failed", reason) end
end

-- Build normalized entries from whichever result set matches the active scan.
local function ReadItemEntries()
    local key = scan.itemKey
    local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
    local entries = {}
    for i = 1, n do
        local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
        if r then
            entries[#entries + 1] = {
                unitPrice        = r.buyoutAmount,     -- may be nil (bid-only)
                bidAmount        = r.bidAmount,
                quantity         = r.quantity or 1,
                timeLeftSeconds  = r.timeLeftSeconds,
                owners           = OwnersText(r.owners),
                itemLink         = r.itemLink,
                auctionID        = r.auctionID,
                isCommodity      = false,
                containsOwnerItem = r.containsOwnerItem or false,
            }
        end
    end
    return entries
end

local function ReadCommodityEntries()
    local id = scan.itemID
    local n = C_AuctionHouse.GetNumCommoditySearchResults(id) or 0
    local entries = {}
    for i = 1, n do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
        if r then
            entries[#entries + 1] = {
                unitPrice        = r.unitPrice,
                bidAmount        = nil,
                quantity         = r.quantity or 1,
                timeLeftSeconds  = r.timeLeftSeconds,
                owners           = OwnersText(r.owners),
                itemLink         = nil,
                auctionID        = r.auctionID,
                isCommodity      = true,
                containsOwnerItem = r.containsOwnerItem or false,
            }
        end
    end
    return entries
end

-- Issue (or re-issue) the search for the active scan. Routed through throttle.
local function ScanSend()
    scan.tries = scan.tries + 1
    if scan.tries > SCAN_MAX_TRIES then
        ScanFail("too many empty retries")
        return
    end
    local key = scan.itemKey
    local myToken = scan.token
    AH.Throttle.Enqueue(function()
        if scan.active and scan.token == myToken then
            C_AuctionHouse.SendSearchQuery(key, PRICE_SORT, false)
        end
    end, "item-scan")
end

-- A results event arrived for our identity. Validate; deliver / paginate / retry.
local function ScanOnResults()
    if not scan.active then return end

    local has, full, quantity
    if scan.isCommodity then
        local id  = scan.itemID
        local mk  = C_AuctionHouse.MakeItemKey(id)
        has      = C_AuctionHouse.HasSearchResults(mk)
        full     = C_AuctionHouse.HasFullCommoditySearchResults(id)
        quantity = C_AuctionHouse.GetCommoditySearchResultsQuantity(id) or 0
    else
        local key = scan.itemKey
        has      = C_AuctionHouse.HasSearchResults(key)
        full     = C_AuctionHouse.HasFullItemSearchResults(key)
        quantity = C_AuctionHouse.GetItemSearchResultsQuantity(key) or 0
    end

    -- False-empty guard: no results, OR claims results but nothing actually loaded
    -- and not yet complete -> re-issue rather than trust the empty (design §2.3).
    if (not has) or (has and not full and quantity == 0) then
        ScanSend()
        return
    end

    local entries = scan.isCommodity and ReadCommodityEntries() or ReadItemEntries()
    local cb = scan.callback

    if full and #entries == 0 then
        ScanFinish(false)
        if cb then pcall(cb, "empty") end
        return
    end

    -- Deliver this page (progressive). Keep paginating until full.
    if cb then
        pcall(cb, "results", {
            isCommodity = scan.isCommodity,
            entries     = entries,
            isFull      = full,
        })
    end

    if not full then
        local myToken = scan.token
        AH.Throttle.Enqueue(function()
            if not (scan.active and scan.token == myToken) then return end
            if scan.isCommodity then
                C_AuctionHouse.RequestMoreCommoditySearchResults(scan.itemID)
            else
                C_AuctionHouse.RequestMoreItemSearchResults(scan.itemKey)
            end
        end, "item-scan-more")
    else
        ScanFinish(true)   -- complete; callback already got isFull=true
    end
end

-- OnUpdate driver: handles the CACHE GATE (poll GetItemKeyInfo until the key resolves,
-- then transition to searching and send) and the DEADLINE (fail cleanly on timeout).
-- Result arrival itself is event-driven (ScanOnResults); this only drives the gate
-- and the safety timeout.
local function EnsureScanDriver()
    if scanDriver then return scanDriver end
    scanDriver = CreateFrame("Frame")
    scanDriver:Hide()
    scanDriver:SetScript("OnUpdate", function(self, elapsed)
        if not scan.active then self:Hide(); return end

        if GetTime() > scan.deadline then
            ScanFail("timed out")
            return
        end

        scan.pollAccum = scan.pollAccum + elapsed
        if scan.pollAccum < SCAN_POLL_RATE then return end
        scan.pollAccum = 0

        if scan.phase == "caching" then
            -- Calling GetItemKeyInfo both checks and nudges the cache fill.
            local info = AH.Search.GetKeyInfo(scan.itemKey)
            if info then
                scan.isCommodity = info.isCommodity and true or false
                scan.phase = "searching"
                ScanSend()
            end
        end
    end)
    return scanDriver
end

-- Public: drill into one item. `source` is either a browse result (has .itemKey) or
-- a raw ItemKey table. callback per the contract above. Returns true if started.
function AH.Search.QueryItem(source, callback)
    if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery) then
        if callback then pcall(callback, "failed", "AH API unavailable") end
        return false
    end
    if not AH.isOpen then
        if callback then pcall(callback, "failed", "Auction House is closed") end
        return false
    end

    local itemKey = source and (source.itemKey or source)
    if type(itemKey) ~= "table" or not itemKey.itemID then
        if callback then pcall(callback, "failed", "bad item key") end
        return false
    end

    -- Supersede any in-flight scan (token bump invalidates its throttled closures).
    scan.token       = scan.token + 1
    scan.active      = true
    scan.phase       = "caching"
    scan.itemKey     = itemKey
    scan.keyString   = ItemKeyString(itemKey)
    scan.itemID      = itemKey.itemID
    scan.isCommodity = nil
    scan.tries       = 0
    scan.deadline    = GetTime() + SCAN_TIMEOUT
    scan.pollAccum   = SCAN_POLL_RATE   -- poll on the very next tick
    scan.callback    = callback

    -- Fast path: key already cached -> skip straight to searching.
    local info = AH.Search.GetKeyInfo(itemKey)
    if info then
        scan.isCommodity = info.isCommodity and true or false
        scan.phase = "searching"
        ScanSend()
    end

    EnsureScanDriver():Show()
    return true
end

function AH.Search.CancelItemQuery()
    if scan.active then
        scan.token = scan.token + 1   -- invalidate pending closures
        ScanFinish(false)
    end
end

function AH.Search.IsScanning() return scan.active end

----------------------------------------------------------------
--  Event wiring
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
ef:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
ef:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
ef:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
       or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        OnBrowseResults()

    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        OnBrowseFailure()

    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        -- arg1 = itemKey. Only act if it matches our active (non-commodity) scan.
        if scan.active and not scan.isCommodity
           and ItemKeyString(arg1) == scan.keyString then
            ScanOnResults()
        end

    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        -- arg1 = itemID. Only act if it matches our active (commodity) scan.
        if scan.active and scan.isCommodity and arg1 == scan.itemID then
            ScanOnResults()
        end
    end
end)

-- Abort any in-flight work when the AH closes (queries are invalid; queue is cleared
-- by Throttle's own AH_CLOSED handler).
AH.Events.On("AH_CLOSED", function()
    browse.active = false
    if scan.active then
        scan.token = scan.token + 1
        ScanFinish(false)
    end
end)
