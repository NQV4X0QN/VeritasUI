-- VeritasUI_AuctionHouse / Database.lua
-- Native price database. Hand-rolled, no LibCBOR (suite rule: no
-- external libraries). Account-wide, persisted in VeritasUI_AuctionHouseDB.prices.
--
-- KEY SCHEME (resolves design OQ#3):
--   "p:<speciesID>"          battle pets (speciesID parsed from the battlepet link)
--   "i:<itemID>:<itemLevel>" equippable gear (ilvl appended so variants don't collide)
--   "i:<itemID>"             everything else (commodities, mats, consumables, recipes…)
-- The full 4-field C_AuctionHouse ItemKey (suffix/enchant/etc.) is intentionally NOT
-- used — itemID[:ilvl] is the right granularity for a price database, and Midnight
-- largely removed item suffixes. itemLevel comes from GetDetailedItemLevelInfo(link)
-- (NOT GetReplicateItemInfo's `level`, which is the required PLAYER level — design §2.2).
--
-- RECORD SHAPE:
--   prices[key] = {
--     market = <int copper>,        -- most recent scan's min unit buyout (quick read)
--     seen   = <dayNumber>,         -- last Unix-day we recorded this item
--     days   = { [day] = { min=<int>, max=<int>, qty=<int> } },  -- per-day history
--   }
-- Prices are PER-UNIT copper integers (design §2.1: AH money is plain integers, not
-- Secret Values). Day = floor(time()/86400) (absolute Unix day; comparison/pruning
-- works identically to a custom epoch, with no magic constant to carry).

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local floor   = math.floor
local time    = time
local tonumber = tonumber
local pairs   = pairs

local GetItemInfoInstant       = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo

AH.DB = {}

local DEFAULT_RETENTION_DAYS = 14

-- Current absolute Unix day.
local function Today()
    return floor(time() / 86400)
end
AH.DB.Today = Today

----------------------------------------------------------------
--  Key derivation
--
--  Works from an item/battlepet LINK (what GetReplicateItemLink and tooltips
--  give us). Returns a string key, or nil if the link can't be parsed.
----------------------------------------------------------------
function AH.DB.MakeKey(link)
    if type(link) ~= "string" then return nil end

    -- linkType + first numeric id: |Hitem:1234... or |Hbattlepet:567...
    local linkType, id = link:match("|H(%a+):(%d+)")
    if not linkType then
        -- Bare "item:1234:..." form (no hyperlink wrapper) — tolerate it.
        linkType, id = link:match("^(%a+):(%d+)")
    end
    if not linkType or not id then return nil end

    if linkType == "battlepet" then
        return "p:" .. id
    end

    if linkType ~= "item" then
        -- Unknown link type (currency, keystone, etc.) — not auctionable in a way
        -- we price; skip.
        return nil
    end

    local itemID = tonumber(id)
    if not itemID then return nil end

    -- Equippable gear → append item level so different-ilvl drops don't collapse.
    local _, _, _, equipLoc = GetItemInfoInstant(link)
    local isGear = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
                   and not equipLoc:find("BAG", 1, true)
    if isGear then
        local ilvl = GetDetailedItemLevelInfo(link)
        if ilvl and ilvl > 0 then
            return "i:" .. itemID .. ":" .. ilvl
        end
        -- Gear with no resolvable item level must NOT be keyed. A link can be
        -- loaded while the detailed item data behind it is not (different cache
        -- layers), so this is reachable on a cold cache. Returning a bare
        -- i:<itemID> here would create exactly the ilvl-agnostic gear key the
        -- design forbids, collapsing every ilvl variant of the item into one
        -- price record. Returning nil defers the row into the existing retry
        -- machinery, which already handles this case. Matches
        -- MakeKeyFromItemID's policy, written later for the same problem.
        return nil
    end

    return "i:" .. itemID
end

-- Key derivation WITHOUT a link — for replicate rows whose link is still
-- uncached (GetReplicateItemLink nil) but whose row itemID is known (the 15th
-- GetReplicateItemInfo return, always present). Non-gear items are keyed by
-- bare itemID, identical to MakeKey's fallthrough, so no link is needed.
-- Gear returns nil: its key requires the item level, which requires the
-- loaded link — callers must defer those rows until the link resolves.
-- (Diagnosed 2026-07-02: ~138k of ~268k replicate rows had nil links at scan
-- time and were silently skipped, leaving over half the AH unpriced per scan.)
function AH.DB.MakeKeyFromItemID(itemID)
    if type(itemID) ~= "number" or itemID <= 0 then return nil end
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    local isGear = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
                   and not equipLoc:find("BAG", 1, true)
    if isGear then return nil end
    return "i:" .. itemID
end

----------------------------------------------------------------
--  Writes
----------------------------------------------------------------

-- Fold one item's per-scan aggregate (min unit price + total qty) into the DB.
-- `day` defaults to today; passed in by the scanner so a whole scan shares one day.
function AH.DB.Record(key, unitPrice, qty, day)
    if not AH.db or not key or not unitPrice or unitPrice <= 0 then return end
    day = day or Today()
    local prices = AH.db.prices

    local rec = prices[key]
    if not rec then
        rec = { market = unitPrice, seen = day, days = {} }
        prices[key] = rec
    end

    rec.market = unitPrice
    rec.seen   = day

    local d = rec.days[day]
    if not d then
        d = { min = unitPrice, max = unitPrice, qty = qty or 0 }
        rec.days[day] = d
    else
        if unitPrice < d.min then d.min = unitPrice end
        if unitPrice > d.max then d.max = unitPrice end
        if (qty or 0) > d.qty then d.qty = qty or 0 end
    end

    -- Prune this item's own stale day-entries (cheap; bounded by retention).
    local retention = (AH.db.settings and AH.db.settings.retentionDays) or DEFAULT_RETENTION_DAYS
    local cutoff = day - retention
    for dd in pairs(rec.days) do
        if dd <= cutoff then rec.days[dd] = nil end
    end
end

----------------------------------------------------------------
--  Reads
----------------------------------------------------------------

-- Quick market price (last scan's min unit buyout) for a key. Returns int or nil.
function AH.DB.GetMarketPrice(key)
    local rec = AH.db and key and AH.db.prices[key]
    return rec and rec.market or nil
end

-- Convenience: market price straight from an item link (derives the key).
function AH.DB.GetMarketPriceForLink(link)
    local key = AH.DB.MakeKey(link)
    if not key then return nil end
    return AH.DB.GetMarketPrice(key), key
end

-- Sorted price history (newest day first). Returns array of
-- { day, min, max, qty }.
function AH.DB.GetPriceHistory(key)
    local rec = AH.db and key and AH.db.prices[key]
    if not rec then return {} end
    local out = {}
    for day, d in pairs(rec.days) do
        out[#out + 1] = { day = day, min = d.min, max = d.max, qty = d.qty }
    end
    table.sort(out, function(a, b) return a.day > b.day end)
    return out
end

-- How many distinct priced items are stored.
function AH.DB.GetItemCount()
    if not AH.db then return 0 end
    local n = 0
    for _ in pairs(AH.db.prices) do n = n + 1 end
    return n
end

-- Days since this item's price was last seen (nil if never).
function AH.DB.GetPriceAge(key)
    local rec = AH.db and key and AH.db.prices[key]
    if not rec or not rec.seen then return nil end
    return Today() - rec.seen
end

-- Wipe the entire price store (diagnostic / user reset).
function AH.DB.Wipe()
    if AH.db then AH.db.prices = {} end
end
