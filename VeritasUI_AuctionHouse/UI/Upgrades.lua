-- VeritasUI_AuctionHouse / UI/Upgrades.lua
-- The Upgrades list (owner's request, 2026-11-26, WoW Forever): an Upgrades button in the bottom band fills the Buy
-- tab's results area with gear for sale that beats what you wear, scored the way Auto Equip scores it
-- (VeritasUI_Lib GearScore.lua: WoWSims stat weights for your class and playstyle, scaled to your level).
--
-- DATA. The replicate scan keeps the cheapest auction of every piece of gear, by item and name (Replicate.lua
-- NoteGear -> AH.db.gearListings, replaced whole by each completed scan). Opening the list scores each against
-- the worn piece for its slot (GS.AgainstWorn: Auto Equip's placement rules), keeps those that win by at least
-- MARGIN, drops any whose tooltip has a red line (a level, armor or weapon type you can't use yet), and sorts by
-- the column the player picks (gain by default). The Filter button beside Upgrades narrows it: a maximum price, a
-- minimum gain, and the best armor type you can wear only (on by default; see BEST ARMOR TYPE).
--
-- BUYING. A click hands the row to Blizzard: its own search bar searches the item's name
-- (SearchBar:SetSearchText + StartSearch, Blizzard_AuctionHouseSearchBar.lua:194-207), and when the results come
-- back the matching row is opened in Blizzard's buy screen (AuctionHouseFrame:SelectBrowseResult with Blizzard's
-- own browse result, Blizzard_AuctionHouseFrame.lua:683-695). Both measured clean on the owner's purchases
-- (test/gear-probe, 2026-11-26: no blocked action). The price you pay is the live one.
--
-- LOOK. Blizzard's own results list, standing in for its pieces: our headers, rows and scroll bar take the exact
-- places of Blizzard's (BrowseResultsFrame.ItemList), whose own are faded to 0 while ours is open and restored at
-- close; Blizzard's background and border are left showing. Rows have no stripes, as Blizzard's browse list
-- (BrowseResultsFrame.xml: hideStripes); the highlight is Blizzard's auctionhouse-ui-row-highlight; headers its
-- ColumnDisplayButtonShortTemplate with the sort arrow. The Upgrades button sits where Cancel Auction sits on the
-- Auctions tab. The list closes when the player browses, searches or leaves the Buy tab.
--
-- WoW Forever only, as Auto Equip's scoring: the weights are WoWSims Forever's, for Forever's stats.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame, format, floor, ipairs, pairs, pcall, type = CreateFrame, string.format, math.floor, ipairs, pairs,
    pcall, type

AH.Upgrades = {}
local U = AH.Upgrades

U.MARGIN = 0.01          -- at least 1% better, as Auto Equip
U.MAX_ROWS = 200
U.TOOLTIP_CHECKS = 300   -- red-line checks per opening, best first
local ROW_H = 20
local BTN_W, BTN_H = 158, 22   -- Blizzard's Cancel Auction button

local state = { built = false }

----------------------------------------------------------------
--  Scoring the listings
----------------------------------------------------------------
local SLOT_NAMES = {
    [1] = _G.INVTYPE_HEAD, [2] = _G.INVTYPE_NECK, [3] = _G.INVTYPE_SHOULDER, [5] = _G.INVTYPE_CHEST,
    [6] = _G.INVTYPE_WAIST, [7] = _G.INVTYPE_LEGS, [8] = _G.INVTYPE_FEET, [9] = _G.INVTYPE_WRIST,
    [10] = _G.INVTYPE_HAND, [11] = _G.INVTYPE_FINGER, [12] = _G.INVTYPE_FINGER, [15] = _G.INVTYPE_CLOAK,
    [16] = _G.INVTYPE_WEAPONMAINHAND, [17] = _G.INVTYPE_WEAPONOFFHAND, [18] = _G.INVTYPE_RANGED,
}

local function IsRed(c)
    local secret = _G.issecretvalue
    return type(c) == "table" and type(c.r) == "number" and not (secret and secret(c.r))
        and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
end

-- A red line on the item's tooltip: a requirement you don't meet. nil when the tooltip can't be read.
local function CannotUse(link)
    local tt = _G.C_TooltipInfo
    if not (tt and tt.GetHyperlink) then return nil end
    local ok, data = pcall(tt.GetHyperlink, link)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        if IsRed(line.leftColor) or IsRed(line.rightColor) then return true end
    end
    return false
end

----------------------------------------------------------------
--  Filters (owner, 2026-11-26): maximum price, minimum gain, best armor type only. Kept account-wide in
--  AH.db.upgradesFilter; the Filter button beside Upgrades sets them (Build).
----------------------------------------------------------------
U.FILTER_DEFAULTS = { maxPrice = 0, minGain = 0, bestArmor = true }   -- 0 = any
U.PRICE_STEPS = { 0, 5000, 10000, 50000, 100000, 500000, 1000000 }  -- copper: any, 50s, 1g, 5g, 10g, 50g, 100g
U.GAIN_STEPS = { 0, 0.05, 0.10, 0.25, 0.50 }

function U.Filter()
    local db = AH.db
    if type(db) ~= "table" then return U.FILTER_DEFAULTS end
    if type(db.upgradesFilter) ~= "table" then db.upgradesFilter = {} end
    local f = db.upgradesFilter
    for k, v in pairs(U.FILTER_DEFAULTS) do if f[k] == nil then f[k] = v end end
    return f
end

function U.FilterIsDefault()
    local f = U.Filter()
    for k, v in pairs(U.FILTER_DEFAULTS) do if f[k] ~= v then return false end end
    return true
end

-- BEST ARMOR TYPE. Which armor types you can wear is read off the game's own tooltips, not a table: the armor type
-- sits on the RIGHT of the slot line and Blizzard writes it in red when your class can't wear it yet (measured,
-- owner's screenshot, WoW Forever 2026-11-05: "Mail" in red right of "Legs" on a Hunter below the level for mail).
-- For each type, heaviest first, the first listed piece of it whose type line can be read decides; a type with no
-- readable piece listed is passed over (nothing of it is for sale, so filtering by the next one loses nothing).
-- Kept per level (training a type comes with a level).
local ARMOR_CHECKS = 25
local bestArmorCache = {}

local function TypeLineRed(link, typeName)
    local tt = _G.C_TooltipInfo
    if not (tt and tt.GetHyperlink) then return nil end
    local ok, data = pcall(tt.GetHyperlink, link)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local t = line.rightText
        if type(t) == "string" and not (_G.issecretvalue and _G.issecretvalue(t)) and t == typeName then
            return IsRed(line.rightColor)
        end
    end
    return nil
end

local function ArmorOf(link)
    local ok, _, _, subType, equipLoc, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok or classID ~= 4 or equipLoc == "INVTYPE_CLOAK" then return nil end
    if type(subclassID) ~= "number" or subclassID < 1 or subclassID > 4 then return nil end
    return subclassID, subType
end
U.ArmorOf = ArmorOf

function U.BestArmorType(listings, level)
    local key = tostring(level)
    if bestArmorCache[key] then return bestArmorCache[key] end
    for t = 4, 2, -1 do
        local tries = 0
        for _, g in pairs(listings) do
            local sub, name = ArmorOf(g.l)
            if sub == t and type(name) == "string" then
                tries = tries + 1
                local red = TypeLineRed(g.l, name)
                if red == false then bestArmorCache[key] = t; return t end
                if red == true or tries >= ARMOR_CHECKS then break end
            end
        end
    end
    return 1   -- not kept: unread tooltips may decide it next time
end
function U.ForgetArmor() bestArmorCache = {} end

-- Best first, by the percentage the Gain column shows (owner, 2026-11-27: "If something is a 5% gain, that should
-- be easily read as better than an item that is a 4% gain"). Until then the list ran on the raw score gain, so the
-- column read +3%, +2%, Empty Slot, +5%, +4% top to bottom. An empty slot (no percentage) beats any percentage;
-- equal percentages fall back to the score gain. Used for the default order and for which rows are kept.
local function ByGain(a, b)
    local pa, pb = a.pct or math.huge, b.pct or math.huge
    if pa ~= pb then return pa > pb end
    return a.gain > b.gain
end

-- ITEM DETAILS, READ ONCE AND KEPT (owner, 2026-11-27: "inconsistent ... makes me wonder if it's not showing me all
-- my possible upgrades"). Measured with a recorder on his Forever client: of 25,006 gear listings, 13,830-14,396 had
-- no item details loaded on each opening, a different set each time -- Lead Band of the Wolf, The 1 Ring, Ring of the
-- Moon each listed on some openings and missing on others, nothing changed in between. The game does not keep
-- details for that many items at once, so a list built from live reads drops a random half without a word.
-- So each listing's details (required level, quality, stats, red tooltip line at your level) are read once, the
-- moment they are loaded, and kept for the session in `facts`; the list is built from those. Opening the list asks
-- the game for every listing not yet read and shows "Reading item details" until they have all arrived, then builds
-- once. The wait follows the game's answers as the scan's gear wait does (landmine 201: answers come on sweeps more
-- than as ITEM_DATA_LOAD_RESULT, so both are followed; re-ask every 2 s; give up after 10 s with no answer), and
-- anything still unread is named under the list, never dropped silently.
local facts = {}            -- [link] = { req, q, stats, red, redLevel }
U.LOAD_QUIET = 10           -- seconds without a new answer before the wait gives up
U.LOAD_REASK = 2
local loader = { pending = nil }

local function ReadFacts(link)
    local okI, _, _, quality, _, reqLevel = pcall(C_Item.GetItemInfo, link)
    if not okI or reqLevel == nil then return nil end
    local okS, stats = pcall(C_Item.GetItemStats, link)
    local fct = { req = reqLevel, q = quality, stats = (okS and type(stats) == "table") and stats or {} }
    facts[link] = fct
    return fct
end
U.ReadFacts = ReadFacts
function U.ForgetFacts() facts = {} end

local function ItemID(link) return tonumber(link:match("|Hitem:(%d+)")) end

-- Whether every listing's details are in hand; asks the game for the rest. Returns the number still missing.
-- Your worn gear is read the same way and counted with them: reading thousands of listings can push your own
-- items' details out too, and an unreadable worn piece was shown as an empty slot (owner, 2026-11-27).
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 18 }
local function AskForMissing(listings)
    local missing, ids = 0, {}
    local function Need(l)
        if not facts[l] and not ReadFacts(l) then
            missing = missing + 1
            local id = ItemID(l)
            if id then ids[id] = true end
        end
    end
    for _, g in pairs(listings) do Need(g.l) end
    for _, s in ipairs(WORN_SLOTS) do
        local ok, l = pcall(GetInventoryItemLink, "player", s)
        if ok and type(l) == "string" then Need(l) end
    end
    local ask = C_Item and C_Item.RequestLoadItemDataByID
    if ask then for id in pairs(ids) do pcall(ask, id) end end
    return missing
end
U.AskForMissing = AskForMissing
-- Worn items' stats, from what has been read (GS.AgainstWorn's statsOf).
local function WornStats(l)
    local f = facts[l] or ReadFacts(l)
    return f and f.stats
end

-- { rows, info } for the player now. rows: { link, name, price, slot, new, worn, gain, pct, quality }.
-- info.unread: listings whose details never arrived (named under the list).
function U.Compute()
    local GS = VUI.GearScore
    local W = GS and GS.Current and GS.Current()
    if not W then return nil, "Upgrades need stat weights for your class, which WoW Forever has." end
    local listings = AH.db and AH.db.gearListings
    if type(listings) ~= "table" or not next(listings) then
        return nil, "Scan the Auction House first: the list comes from the last scan."
    end
    local okL, level = pcall(UnitLevel, "player")
    level = okL and level or 60
    local f = U.Filter()
    local best = f.bestArmor and U.BestArmorType(listings, level) or nil
    local rows, info = {}, { weights = W, at = AH.db.gearListingsAt, uncached = 0, unusable = 0, checked = 0,
        filtered = 0, bestArmor = best, unread = 0 }
    for _, g in pairs(listings) do
        local link, price = g.l, g.p
        local fct = facts[link] or ReadFacts(link)
        if not fct then
            info.unread = info.unread + 1
        elseif fct.req <= level then
            local slot, new, worn = GS.AgainstWorn(link, W, fct.stats, WornStats)
            if slot and type(new) == "number" and new > 0 then
                local gain = new - (worn or 0)
                if not worn or new > worn * (1 + U.MARGIN) + 1e-6 then
                    local pct = (worn and worn > 0) and (new / worn - 1) or nil
                    local sub = best and ArmorOf(link)
                    if (f.maxPrice > 0 and price > f.maxPrice)
                        or (f.minGain > 0 and pct and pct < f.minGain - 1e-9)
                        or (sub and sub < best) then
                        info.filtered = info.filtered + 1
                    else
                        rows[#rows + 1] = {
                            link = link, name = link:match("|h%[(.-)%]|h") or link, price = price, slot = slot,
                            new = new, worn = worn, gain = gain, pct = pct, quality = fct.q,
                        }
                    end
                end
            end
        end
    end
    info.uncached = info.unread
    table.sort(rows, ByGain)
    local kept = {}
    for _, r in ipairs(rows) do
        if info.checked >= U.TOOLTIP_CHECKS or #kept >= U.MAX_ROWS then break end
        info.checked = info.checked + 1
        -- The red-line read kept per level, so a tooltip unloaded later cannot change the answer.
        local fct = facts[r.link]
        local bad
        if fct and fct.redLevel == level then
            bad = fct.red
        else
            bad = CannotUse(r.link)
            if fct and bad ~= nil then fct.red, fct.redLevel = bad, level end
        end
        if bad then info.unusable = info.unusable + 1 else kept[#kept + 1] = r end
    end
    return kept, info
end

local SORTS = {
    gain = ByGain,
    price = function(a, b) return a.price < b.price end,
    name = function(a, b) if a.name ~= b.name then return a.name < b.name end return ByGain(a, b) end,
    slot = function(a, b) if a.slot ~= b.slot then return a.slot < b.slot end return ByGain(a, b) end,
}
U.SORTS = SORTS

----------------------------------------------------------------
--  Buying: Blizzard's search, then Blizzard's buy screen
----------------------------------------------------------------
-- Results can come back in more than one update; the wait ends at the first that holds the item, at the next
-- Upgrades click, at closing the Auction House, or after PENDING_SECONDS.
local PENDING_SECONDS = 10
local pendingName, pendingID, pendingAt
local buyFrame = CreateFrame("Frame")
local function ClearPending()
    pendingName, pendingID, pendingAt = nil, nil, nil
    buyFrame:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
end
U.ClearPending = ClearPending

buyFrame:SetScript("OnEvent", function()
    if not pendingName then return ClearPending() end
    if GetTime() - (pendingAt or 0) > PENDING_SECONDS then return ClearPending() end
    local f = _G.AuctionHouseFrame
    local okR, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not (okR and type(results) == "table") then return end
    local match
    for _, r in ipairs(results) do
        if r.itemKey and r.itemKey.itemID == pendingID then
            local okK, ki = pcall(C_AuctionHouse.GetItemKeyInfo, r.itemKey)
            if okK and ki and ki.itemName == pendingName then match = r; break end
            match = match or r
        end
    end
    if not match then return end
    ClearPending()
    if f and f.SelectBrowseResult then
        pcall(f.SelectBrowseResult, f, match)
        state.fromList = true   -- Blizzard's Back then returns to the list (see Build)
    end
end)

function U.Buy(link)
    local f = _G.AuctionHouseFrame
    local bar = f and f.SearchBar
    local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
    local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
    if not (bar and name and id) then return false end
    U.Hide()
    -- A category picked on the left (Weapons > One-Handed) narrows Blizzard's search to it, so boots would come
    -- back "No items found". Cleared first, the way Blizzard's own Favorites search does
    -- (Blizzard_AuctionHouseSearchBar.lua:210, SetSelectedCategory(nil)).
    local cats = f.GetCategoriesList and f:GetCategoriesList() or f.CategoriesList
    if cats and cats.SetSelectedCategory then pcall(cats.SetSelectedCategory, cats, nil) end
    pendingName, pendingID, pendingAt = name, id, GetTime()
    buyFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    local ok = pcall(function() bar:SetSearchText(name); bar:StartSearch() end)
    if not ok then ClearPending() end
    return ok
end

----------------------------------------------------------------
--  The list
----------------------------------------------------------------
-- Laid out as Blizzard lays out its browse list (owner, 2026-11-27: "more closely match Blizzard's layout"), from
-- WoW Forever's AuctionHouseTableBuilder.GetBrowseListLayout (Blizzard_AuctionHouseTableBuilder.lua:1040-1069):
-- Price 146 wide (168 where copper shows, C_AuctionHouse.SupportsCopperValues), its cell 0 in from the left and 14
-- from the right, right-aligned; Name takes the rest, 10 in; Level 55, 10 in; Quantity 83 (60 with copper), 10
-- in; then a 29-wide favourite column (10/5) with no header, which the last header runs over (TableBuilder.lua
-- ArrangeHeaders: trailing headerless widths join the last header). Each header after the first starts 2 to the
-- left of its column (SetColumnHeaderOverlap(2)) and its text sits 8 in (ColumnDisplayButtonShortTemplate).
-- Ours, the owner's order (2026-11-27, fourth try): Price first, where Blizzard's sits; Name taking the rest; Gain
-- left-aligned 10 in as Blizzard's text columns are; Slot where Quantity and the favourite column sit. No Level
-- column (owner: "If an item is a gain, its level doesn't really matter", and Name gets the room). Earlier tries:
-- Gain first (odd in both alignments), then Price, Gain, Name, Level, Slot.
-- Widths (owner, build 5): "Empty Slot" ran up against Slot, so 12 px moved from Slot to Gain and Name keeps its
-- width. Measured off his screenshots (Price's 146 = 385 px there): "Empty Slot" ~51 of Gain's 60 px of text room,
-- "Main Hand", the longest slot name, ~51 of Slot's 97. Now Gain 72 and Slot 85 of text room.
local SLOT_TRIM = 12
local COPPER = (function()
    local ok, v = pcall(function() return C_AuctionHouse.SupportsCopperValues() end)
    return ok and v and true or false
end)()
local PRICE_W = COPPER and 168 or 146
local QTY_W = COPPER and 60 or 83
local HEADER_OVERLAP = 2
U.COLUMNS = {   -- key, label, width (0 = the rest), cell padding left, right, justify, sort key
    { "price", _G.AUCTION_HOUSE_BROWSE_HEADER_PRICE or "Price", PRICE_W, 0, 14, "RIGHT", "price" },
    { "item", _G.AUCTION_HOUSE_BROWSE_HEADER_NAME or _G.NAME or "Name", 0, 10, 0, "LEFT", "name" },
    { "gain", "Gain", 70 + SLOT_TRIM, 10, 0, "LEFT", "gain" },
    { "slot", "Slot", QTY_W + 29 - SLOT_TRIM, 10, 5, "LEFT", "slot" },
}
local COLUMNS = U.COLUMNS

-- Where each column starts and ends: from the left edge up to the one that takes the rest, from the right edge
-- after it. { side = "LEFT"/"RIGHT"/"FILL", x = start from its edge, w = width; FILL: x from the left, r from the
-- right }.
function U.ColumnSpans()
    local fill
    for i, col in ipairs(COLUMNS) do if col[3] == 0 then fill = i end end
    local spans, x = {}, 0
    for i = 1, fill - 1 do spans[i] = { side = "LEFT", x = x, w = COLUMNS[i][3] }; x = x + COLUMNS[i][3] end
    local r = 0
    for i = #COLUMNS, fill + 1, -1 do
        r = r + COLUMNS[i][3]
        spans[i] = { side = "RIGHT", x = -r, w = COLUMNS[i][3] }
    end
    spans[fill] = { side = "FILL", x = x, r = r }
    return spans
end

local function Money(copper)
    if AH.Tooltip and AH.Tooltip.CoinMarkup then
        local ok, s = pcall(AH.Tooltip.CoinMarkup, copper)
        if ok and s then return s end
    end
    return GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)
end

local function GainText(r)
    if not r.worn then return "Empty Slot" end
    if r.pct then return format("+%d%%", floor(r.pct * 100 + 0.5)) end
    return format("+%.1f", r.gain)
end

-- Sort direction, as Blizzard's headers: a first click sorts the column its natural way, a second click on the
-- same header reverses it (AuctionHouseSortOrderSystemMixin); the arrow points up for smallest first and down for
-- largest first (AuctionHouseTableHeaderStringMixin:SetArrowState, TableBuilder.lua:913-920: Blizzard flips the
-- atlas with SetTexCoord(0, 1, 1, 0) for its ascending order, leaves it (0, 1, 0, 1) for descending).
local ASCENDING = { gain = false, price = true, name = true, slot = true }

local function SortedRows()
    local key = state.sort or "gain"
    local cmp = SORTS[key]
    local t = {}
    for i, r in ipairs(state.rows or {}) do t[i] = r end
    if state.reverse then table.sort(t, function(a, b) return cmp(b, a) end) else table.sort(t, cmp) end
    return t
end
U.SortedRows = function() return SortedRows() end
U._headers = function() return state.headers end

local function ShowRows(keepScroll)
    local dp = CreateDataProvider()
    for i, r in ipairs(SortedRows()) do r.index = i; dp:Insert(r) end
    local retain = keepScroll and _G.ScrollBoxConstants and _G.ScrollBoxConstants.RetainScrollPosition
    state.scroll:SetDataProvider(dp, retain)
    local key = state.sort or "gain"
    local up = (ASCENDING[key] and true or false) ~= (state.reverse and true or false)
    for _, h in ipairs(state.headers) do
        if h.arrow then
            h.arrow:SetShown(h.sortKey == key)
            if up then h.arrow:SetTexCoord(0, 1, 1, 0) else h.arrow:SetTexCoord(0, 1, 0, 1) end
        end
    end
end

-- A header click re-orders the rows already worked out; it never works the list out again (owner, 2026-11-27:
-- sorting by price "just hides more" -- until then every click re-ran Compute, which re-reads tooltips).
-- The list opens sorted by Gain, so a first click on Gain reverses it, as a click on the column Blizzard's list is
-- sorted by does (owner, build 10: the first click on a header did nothing -- state.sort was still nil while the
-- list showed Gain's order, so that click "chose" Gain's natural order again).
function U.SortBy(key)
    if (state.sort or "gain") == key then state.reverse = not state.reverse
    else state.sort, state.reverse = key, false end
    if state.list then ShowRows() end
end

local function SetLoading(on)
    if state.spinner then state.spinner:SetShown(on and true or false) end
end

local function Refresh(keepScroll)
    if not state.list then return end
    SetLoading(false)
    local rows, info = U.Compute()
    state.rows = rows or {}
    ShowRows(keepScroll)
    if not rows then
        state.empty:SetText(info)
    elseif #rows == 0 then
        state.empty:SetText((info.filtered or 0) > 0
            and "Nothing for sale beats what you wear within your filters."
            or "Nothing for sale beats what you wear. The list comes from the last scan.")
    else
        state.empty:SetText("")
    end
    local W = info and type(info) == "table" and info.weights
    if W then
        local age, ageText = info.at and floor((time() - info.at) / 60), ""
        if age then
            ageText = age < 60 and format(", scanned %d min ago", age) or format(", scanned %d h ago", floor(age / 60))
        end
        local hidden = (info.filtered or 0) > 0 and format(", %d hidden by filters", info.filtered) or ""
        local unread = (info.unread or 0) > 0 and format(", %d |4item:items; could not be read", info.unread) or ""
        state.sub:SetText(format("Scored for %s at level %d%s%s%s", W.profile.name, W.level, ageText, hidden, unread))
    else
        state.sub:SetText("")
    end
    return rows, info
end
U.Refresh = Refresh

-- Opening the list: read what is already loaded, ask the game for the rest, and build only when every listing's
-- details are in hand (or the game has gone LOAD_QUIET seconds without an answer). See ITEM DETAILS above.
-- Measured (owner's Forever client, build 9 recorder, 2026-11-27): first opening after a scan, 14,470 of 25,348
-- missing, all read in about 1 s, none unread; the next four openings instant and the same list to the name.

-- Opening the list: read what is already loaded, ask the game for the rest, and build only when every listing's
-- details are in hand (or the game has gone LOAD_QUIET seconds without an answer). See ITEM DETAILS above.
local loadTicker
local loadEvents = CreateFrame("Frame")
local function StopLoading()
    if loadTicker then loadTicker:Cancel(); loadTicker = nil end
    loadEvents:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    loader.pending = nil
end
U.StopLoading = StopLoading
loadEvents:SetScript("OnEvent", function() if loader.pending then loader.pending.lastAnswer = GetTime() end end)

local function ShowProgress(missing, total)
    SetLoading(true)
    state.empty:SetText("")
    state.sub:SetText(format("Reading item details: %d of %d", total - missing, total))
end

-- One sweep: reads every listing whose details have arrived; returns how many are still missing.
local function Sweep(listings)
    local missing = 0
    for _, g in pairs(listings) do
        if not facts[g.l] and not ReadFacts(g.l) then missing = missing + 1 end
    end
    for _, s in ipairs(WORN_SLOTS) do
        local ok, l = pcall(GetInventoryItemLink, "player", s)
        if ok and type(l) == "string" and not facts[l] and not ReadFacts(l) then missing = missing + 1 end
    end
    return missing
end

function U.Load(keepScroll)
    StopLoading()
    if not state.list then return end
    local listings = AH.db and AH.db.gearListings
    if type(listings) ~= "table" or not next(listings) or not (VUI.GearScore and VUI.GearScore.Current
        and VUI.GearScore.Current()) then
        return Refresh(keepScroll)
    end
    local total = 0
    for _ in pairs(listings) do total = total + 1 end
    local missing = AskForMissing(listings)
    if missing == 0 then return Refresh(keepScroll) end
    local now = GetTime()
    local p = { total = total, missing = missing, lastAnswer = now, lastAsk = now, keep = keepScroll }
    loader.pending = p
    state.rows = {}
    ShowRows()
    ShowProgress(missing, total)
    loadEvents:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    loadTicker = C_Timer.NewTicker(0.5, function()
        if loader.pending ~= p then return end
        if not (state.list and state.list:IsShown()) then return StopLoading() end
        local t = GetTime()
        local m = Sweep(listings)
        if m < p.missing then p.missing, p.lastAnswer = m, t end
        if m == 0 or t - p.lastAnswer >= U.LOAD_QUIET then
            StopLoading()
            return Refresh(p.keep)
        end
        if t - p.lastAsk >= U.LOAD_REASK then AskForMissing(listings); p.lastAsk = t end
        ShowProgress(m, p.total)
    end)
end

-- Blizzard's cell font (AuctionHouseTableCellTextTemplate and the item cell: Number14FontWhite,
-- TableBuilder.xml:20-27, :143) and its price display (AuctionHouseTableMoneyDisplayTemplate: MoneyDisplayFrameTemplate
-- with the Auction House coins, each coin in a 36 px slot so gold, silver and copper line up down the column,
-- MoneyFrame.lua:472-555). Its price cell puts the money 6 px left of a 16 px checkmark space at the cell's right
-- (AuctionHouseTableCellMinPriceMixin:Init, TableBuilder.lua:776-788), so the money ends 22 px inside the cell.
local CELL_FONT = "Number14FontWhite"
local PRICE_CHECK_SPACE = 16 + 6

local function InitRow(row, r)
    if not row.cells then
        row:SetHeight(ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        pcall(hl.SetAtlas, hl, "auctionhouse-ui-row-highlight")
        hl:SetBlendMode("ADD")
        row.cells = {}
        local spans = U.ColumnSpans()
        for i, col in ipairs(COLUMNS) do
            local s, padL, padR = spans[i], col[4], col[5]
            local okM, money
            if col[1] == "price" then
                okM, money = pcall(CreateFrame, "Frame", nil, row, "AuctionHouseTableMoneyDisplayTemplate")
                money = okM and money and type(money.MoneyDisplay) == "table" and money or nil
            end
            if money then
                money:SetPoint("TOPLEFT", row, "TOP" .. s.side, s.x + padL, 0)
                money:SetPoint("BOTTOMLEFT", row, "BOTTOM" .. s.side, s.x + padL, 0)
                money:SetWidth(s.w - padL - padR)
                money.MoneyDisplay:ClearAllPoints()
                money.MoneyDisplay:SetPoint("RIGHT", money, "RIGHT", -PRICE_CHECK_SPACE, 0)
                row.cells[i] = money
            else
                local fs = row:CreateFontString(nil, "OVERLAY", CELL_FONT)
                fs:SetJustifyH(col[6])
                fs:SetWordWrap(false)
                if col[1] == "item" then
                    -- Blizzard's item cell (AuctionHouseTableCellItemDisplayTemplate, TableBuilder.xml:124-149): a
                    -- 14 px icon at the cell's left in its 16 px border, the name 4 right of it and 1 down.
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(14, 14)
                    icon:SetPoint("LEFT", row, "LEFT", s.x + padL, 0)
                    local border = row:CreateTexture(nil, "ARTWORK", nil, 1)
                    border:SetSize(16, 16)
                    border:SetPoint("CENTER", icon, "CENTER")
                    pcall(border.SetAtlas, border, "auctionhouse-itemicon-small-border", false)
                    row.icon = icon
                    fs:SetPoint("LEFT", icon, "RIGHT", 4, -1)
                    fs:SetPoint("RIGHT", row, "RIGHT", -s.r - padR + 1, -1)
                else
                    -- the price falls back to coin text if Blizzard's display can't be made: same right edge
                    local inset = (col[1] == "price") and PRICE_CHECK_SPACE or 0
                    fs:SetPoint("LEFT", row, s.side, s.x + padL, 0)
                    fs:SetWidth(s.w - padL - padR - inset)
                end
                row.cells[i] = fs
            end
        end
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.data.link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        row:SetScript("OnClick", function(self) if self.data then U.Buy(self.data.link) end end)
    end
    row.data = r
    local okT, tex = pcall(C_Item.GetItemIconByID, tonumber(r.link:match("|Hitem:(%d+)")))
    row.icon:SetTexture(okT and tex or 134400)
    local qc = _G.ITEM_QUALITY_COLORS and r.quality and _G.ITEM_QUALITY_COLORS[r.quality]
    for i, col in ipairs(COLUMNS) do
        local k, text, cell = col[1], "", row.cells[i]
        if k == "price" and type(cell.MoneyDisplay) == "table" then
            pcall(cell.MoneyDisplay.SetAmount, cell.MoneyDisplay, r.price)
            text = nil
        elseif k == "gain" then text = GainText(r)
        elseif k == "price" then text = Money(r.price)
        elseif k == "item" then text = qc and qc.hex and (qc.hex .. r.name .. "|r") or r.name
        elseif k == "slot" then text = SLOT_NAMES[r.slot] or tostring(r.slot) end
        if text then cell:SetText(text) end
    end
end

-- Blizzard's own pieces of the results list that ours stands in for while it is open. Faded, not hidden or moved:
-- Blizzard's code keeps running them as before (SetAlpha changes nothing it reads), and they come back at Hide.
local STAND_IN = { "HeaderContainer", "ScrollBox", "ScrollBar", "ResultsText", "LoadingSpinner" }

local function FadeBlizzard(itemList, fade)
    for _, key in ipairs(STAND_IN) do
        local f = itemList and itemList[key]
        if f and f.SetAlpha then
            if fade then
                if state.alpha[key] == nil then state.alpha[key] = f.GetAlpha and f:GetAlpha() or 1 end
                f:SetAlpha(0)
            elseif state.alpha[key] ~= nil then
                f:SetAlpha(state.alpha[key])
                state.alpha[key] = nil
            end
        end
    end
end

local function Build()
    if state.built or not _G.AuctionHouseFrame or not VUI.IS_FOREVER then return end
    local ahf = _G.AuctionHouseFrame
    local area = ahf.BrowseResultsFrame
    local itemList = area and area.ItemList
    if not (itemList and itemList.HeaderContainer and itemList.ScrollBox) then return end
    state.itemList, state.alpha = itemList, {}

    -- Where Blizzard's Cancel Auction button sits on the Auctions tab (Blizzard_AuctionHouseAuctionsFrame.xml:64-68:
    -- 158 x 22, BOTTOMRIGHT -3,-22 of AuctionsFrame).
    local btn = CreateFrame("Button", "VUIAHUpgradesButton", ahf, "UIPanelButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    if ahf.AuctionsFrame then
        btn:SetPoint("BOTTOMRIGHT", ahf.AuctionsFrame, "BOTTOMRIGHT", -3, -22)
    else
        btn:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", -3, -4)
    end
    btn:SetFrameLevel((ahf:GetFrameLevel() or 0) + 10)
    btn:SetText("Upgrades")
    btn:SetScript("OnClick", function() if state.list:IsShown() then U.Hide() else U.Show() end end)
    -- Greyed with the reason while there is no recent scan (see U.ScanTooOld); a disabled button still shows its
    -- tooltip only when told to (motionScriptsWhileDisabled, UI.xsd:934; as Advanced Options' reset button).
    btn:SetMotionScriptsWhileDisabled(true)
    btn:SetScript("OnEnter", function(self)
        local why = U.ScanTooOld()
        if not why then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Upgrades", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        GameTooltip:AddLine(why, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    state.btn = btn

    -- FILTER: Blizzard's own filter dropdown (WowStyle1FilterDropdownTemplate, 93 wide, its red clear-filters X:
    -- Blizzard_AuctionHouseSearchBar.xml:19-35, .lua:139), 10 left of Upgrades as Blizzard's sits 10 left of
    -- Search. Shown while the list is open.
    local okD, dd = pcall(CreateFrame, "DropdownButton", "VUIAHUpgradesFilter", ahf, "WowStyle1FilterDropdownTemplate")
    if okD and dd then
        dd:SetWidth(93)
        dd:SetPoint("RIGHT", btn, "LEFT", -10, 0)
        dd:SetFrameLevel((ahf:GetFrameLevel() or 0) + 10)
        local label = type(dd.Text) == "table" and dd.Text.GetText and dd.Text or nil
        if label and (label:GetText() or "") == "" then label:SetText(_G.FILTER or "Filter") end
        local clear = CreateFrame("Button", nil, dd)
        clear:SetSize(23, 23)
        clear:SetPoint("CENTER", dd, "TOPRIGHT", -3, 0)
        clear:SetNormalAtlas("auctionhouse-ui-filter-redx")
        clear:SetHighlightAtlas("auctionhouse-ui-filter-redx", "ADD")
        local hl = clear:GetHighlightTexture()
        if hl then hl:SetAlpha(0.4) end
        local function Changed()
            clear:SetShown(not U.FilterIsDefault())
            if state.list and state.list:IsShown() and not loader.pending then Refresh() end
        end
        state.FilterChanged = Changed
        clear:SetScript("OnClick", function()
            local f = U.Filter()
            for k, v in pairs(U.FILTER_DEFAULTS) do f[k] = v end
            Changed()
        end)
        local function PriceText(c) return c == 0 and "Any" or Money(c) end
        dd:SetupMenu(function(_, root)
            root:CreateTitle("Maximum Price")
            for _, c in ipairs(U.PRICE_STEPS) do
                root:CreateRadio(PriceText(c), function() return U.Filter().maxPrice == c end,
                    function() U.Filter().maxPrice = c; Changed() end)
            end
            root:QueueSpacer()
            root:CreateTitle("Minimum Gain")
            for _, g in ipairs(U.GAIN_STEPS) do
                root:CreateRadio(g == 0 and "Any" or format("%d%%", floor(g * 100 + 0.5)),
                    function() return U.Filter().minGain == g end,
                    function() U.Filter().minGain = g; Changed() end)
            end
            root:QueueSpacer()
            root:CreateCheckbox("Best Armor Type Only", function() return U.Filter().bestArmor end,
                function() local f = U.Filter(); f.bestArmor = not f.bestArmor; Changed() end)
        end)
        clear:SetShown(not U.FilterIsDefault())
        dd:Hide()
        state.filterBtn = dd
    end

    -- Our list draws no background: Blizzard's own (the list art and its border) shows through, and our headers,
    -- rows and scroll bar take the exact places of Blizzard's (Blizzard_AuctionHouseItemList.xml:55-74).
    local list = CreateFrame("Frame", "VUIAHUpgradesList", ahf)
    list:SetAllPoints(itemList)
    list:SetFrameLevel((itemList:GetFrameLevel() or 0) + 20)
    list:EnableMouse(true)
    list:Hide()
    state.list = list

    -- The headers span the rows' width (Blizzard measures its table off the ScrollBox, ItemList.lua:107), so a
    -- column's header and its cells line up from either edge.
    local headers = CreateFrame("Frame", nil, list)
    headers:SetPoint("TOPLEFT", itemList.HeaderContainer, "TOPLEFT", 0, 0)
    headers:SetPoint("BOTTOMLEFT", itemList.HeaderContainer, "BOTTOMLEFT", 0, 0)
    headers:SetPoint("RIGHT", itemList.ScrollBox, "RIGHT", 0, 0)
    state.headers = {}
    local spans = U.ColumnSpans()
    for i, col in ipairs(COLUMNS) do
        local okH, h = pcall(CreateFrame, "Button", nil, headers, "ColumnDisplayButtonShortTemplate")
        if not okH then h = CreateFrame("Button", nil, headers) end
        local s, lap = spans[i], (i == 1) and 0 or HEADER_OVERLAP
        -- Top and bottom on the header row, as Blizzard's (TableBuilder.lua ArrangeHorizontally).
        local side = s.side == "FILL" and "LEFT" or s.side
        h:SetPoint("TOPLEFT", headers, "TOP" .. side, s.x - lap, 0)
        h:SetPoint("BOTTOMLEFT", headers, "BOTTOM" .. side, s.x - lap, 0)
        if s.side == "FILL" then
            h:SetPoint("TOPRIGHT", headers, "TOPRIGHT", -s.r, 0)
            h:SetPoint("BOTTOMRIGHT", headers, "BOTTOMRIGHT", -s.r, 0)
        else
            h:SetWidth(s.w + lap)
        end
        if h.SetText then h:SetText(col[2]) end
        -- Blizzard's sort arrow sits 3 px right of the header text (AuctionHouseTableHeaderStringTemplate).
        local arrow = h:CreateTexture(nil, "OVERLAY")
        pcall(arrow.SetAtlas, arrow, "auctionhouse-ui-sortarrow", true)
        if h.Text then arrow:SetPoint("LEFT", h.Text, "RIGHT", 3, 0) else arrow:SetPoint("RIGHT", h, "RIGHT", -4, 0) end
        h.arrow, h.sortKey = arrow, col[7]
        h:SetScript("OnClick", function() U.SortBy(col[7]) end)
        state.headers[#state.headers + 1] = h
    end

    local sub = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 8, 6)
    state.sub = sub

    local scroll = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scroll:SetPoint("TOPLEFT", itemList.ScrollBox, "TOPLEFT", 0, 0)
    scroll:SetPoint("RIGHT", itemList.ScrollBox, "RIGHT", 0, 0)
    scroll:SetPoint("BOTTOM", list, "BOTTOM", 0, 22)   -- room for the line above, under the rows
    local bar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 9, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 9, 4)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scroll, bar, view)
    state.scroll = scroll

    -- As Blizzard's "No items found" (ResultsText, Blizzard_AuctionHouseItemList.xml:92-104).
    local empty = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("TOP", scroll, "TOP", 0, -45)
    empty:SetPoint("LEFT", list, "LEFT", 45, 0)
    empty:SetPoint("RIGHT", list, "RIGHT", -67, 0)
    state.empty = empty

    -- While the details are read: Blizzard's own spinner as its results list shows one while searching
    -- (LoadingSpinner, SpinnerTemplate 90 x 90 at CENTER -12,-15 with its text above in GameFontNormalHuge4,
    -- Blizzard_AuctionHouseItemList.xml:74-88); the count goes on the line under the list.
    local okSp, spin = pcall(CreateFrame, "Frame", nil, list, "SpinnerTemplate")
    if okSp and spin then
        spin:SetSize(90, 90)
        spin:SetPoint("CENTER", list, "CENTER", -12, -15)
        local txt = spin:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge4")
        txt:SetPoint("BOTTOM", spin, "TOP", 0, 10)
        txt:SetText("Reading Item Details")
        spin:Hide()
        state.spinner = spin
    end

    -- The button shows on the Buy tab's browse view only, and leaving it (Blizzard's own mode switch) or starting
    -- a search closes the list. Hooks only: nothing of Blizzard's is called to change tabs.
    local function InBuy()
        local modes = _G.AuctionHouseFrameDisplayMode
        return not (modes and ahf.GetDisplayMode) or ahf:GetDisplayMode() == modes.Buy
    end
    state.InBuy = InBuy
    btn:SetShown(InBuy())

    -- BACK RETURNS TO THE LIST (owner, 2026-11-26). An item opened from Upgrades marks state.fromList. Blizzard's
    -- Back button (AuctionHouseCommoditiesBackButtonMixin:OnClick: SetDisplayMode(Buy),
    -- Blizzard_AuctionHouseCommoditiesBuyFrame.lua:4-7) then reopens our list where it was. PreClick marks the
    -- press so the mode switch it makes keeps the mark; any other way back to browsing (a search, a category,
    -- another tab) clears it, so Back from an item the player found himself stays Blizzard's.
    local modes = _G.AuctionHouseFrameDisplayMode
    if ahf.SetDisplayMode then
        hooksecurefunc(ahf, "SetDisplayMode", function()
            btn:SetShown(InBuy())
            if list:IsShown() then U.Hide() end
            local m = ahf.GetDisplayMode and ahf:GetDisplayMode()
            local inItem = modes and (m == modes.ItemBuy or m == modes.CommoditiesBuy)
            if not inItem and not state.backPressed then state.fromList = false end
        end)
    end
    if ahf.SearchBar and ahf.SearchBar.StartSearch then
        hooksecurefunc(ahf.SearchBar, "StartSearch", function()
            if list:IsShown() then U.Hide() end
            state.fromList = false
        end)
    end
    for _, key in ipairs({ "ItemBuyFrame", "CommoditiesBuyFrame" }) do
        local back = ahf[key] and ahf[key].BackButton
        if back and back.HookScript then
            back:HookScript("PreClick", function() state.backPressed = true end)
            back:HookScript("OnClick", function()
                local reopen = state.backPressed and state.fromList
                state.backPressed, state.fromList = false, false
                if reopen then U.Show(true) end
            end)
        end
    end
    state.built = true
    U.UpdateButton()
end

-- UPGRADES AND SCAN TAKE TURNS (owner, 2026-11-27): "When one is active, the other is greyed out." The list is only
-- the last scan's listings, and once Scan can run again (its 15-minute wait over, AH.Scan.SecondsUntilReady) the
-- auction house has moved on enough to want a fresh one. So Upgrades is on exactly while Scan counts down after a
-- scan that saved listings, and greyed -- with the reason on its tooltip -- while Scan is ready, while a scan runs
-- (its listings are about to be replaced), or before any scan. An open list closes when Scan becomes ready.
-- (Build 8 had a 30-minute age limit of its own instead.)
function U.ScanTooOld()
    local db = AH.db
    local scan = AH.Scan
    if scan and scan.IsScanning and scan.IsScanning() then
        return "Scanning. Upgrades open when the scan finishes."
    end
    local listings = type(db) == "table" and db.gearListings
    if type(listings) ~= "table" or not next(listings) or not db.gearListingsAt then
        return "Scan the Auction House first. Upgrades come from your last scan."
    end
    -- The last scan saved no listings of its own (audit A2, 2026-11-27): the Auction House closed while it was still
    -- reading gear, or it was a browse scan, which has no listings. Only a completed replicate scan writes
    -- gearListingsAt, in the same moment as lastScan (Replicate.lua); 60 s of slack covers a second boundary.
    if db.gearListingsAt < (tonumber(db.lastScan) or 0) - 60 then
        return "Your last scan did not read the gear for sale. Scan again to see upgrades."
    end
    local wait = scan and scan.SecondsUntilReady and scan.SecondsUntilReady() or 0
    if wait <= 0 then
        local mins = floor((time() - db.gearListingsAt) / 60)
        local ageText = mins < 120 and format("%d minutes", mins) or format("%d hours", floor(mins / 60))
        return format("Your last scan is %s old. Scan again to see current upgrades.", ageText)
    end
    return nil
end

local staleGen = 0
function U.UpdateButton()
    if not state.btn then return end
    local why = U.ScanTooOld()
    state.btn:SetEnabled(not why)
    if why then
        if state.list and state.list:IsShown() then U.Hide() end
        return
    end
    -- Re-check the moment Scan becomes ready: one timer per state, a newer call outdates it.
    staleGen = staleGen + 1
    local gen = staleGen
    local left = (AH.Scan.SecondsUntilReady() or 0) + 0.5
    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(1, left), function() if gen == staleGen then U.UpdateButton() end end)
    end
end

-- keepScroll: reopened by Back, so the list stays where the player left it.
function U.Show(keepScroll)
    Build()
    if not (state.built and state.InBuy()) then return end
    if U.ScanTooOld() then return U.UpdateButton() end
    FadeBlizzard(state.itemList, true)
    state.list:Show()
    if state.filterBtn then state.filterBtn:Show() end
    U.Load(keepScroll)
end

function U.Hide()
    StopLoading()
    if state.list then state.list:Hide() end
    if state.filterBtn then state.filterBtn:Hide() end
    if state.itemList then FadeBlizzard(state.itemList, false) end
end

AH.Events.On("AH_OPEN", function() Build(); U.UpdateButton() end)
AH.Events.On("AH_CLOSED", function() U.Hide(); ClearPending() end)
AH.Events.On("AH_SCAN_COMPLETE", function()
    U.UpdateButton()
    if state.list and state.list:IsShown() then U.Load() end
end)
-- A scan starting greys Upgrades (and closes the list); a failed one may leave Scan ready again.
AH.Events.On("AH_SCAN_START", function() U.UpdateButton() end)
AH.Events.On("AH_SCAN_REQUESTED", function() U.UpdateButton() end)
AH.Events.On("AH_SCAN_FAILED", function() U.UpdateButton() end)
-- A new level can bring a new armor type. And an open list is worked out again when you change what you wear or
-- level up (audit A1, 2026-11-27): its gains are against your gear at that moment, and Blizzard's character sheet
-- refreshes on the same events (PLAYER_EQUIPMENT_CHANGED, Camelot/PaperDollFrame.lua:337, :475). Batched to one
-- refresh per moment (equipping a set fires one event per slot); not while details are still being read.
do
    local lv = CreateFrame("Frame")
    lv:RegisterEvent("PLAYER_LEVEL_UP")
    lv:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    local due = false
    lv:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEVEL_UP" then U.ForgetArmor() end
        if due or not (state.list and state.list:IsShown()) then return end
        due = true
        C_Timer.After(0.2, function()
            due = false
            if state.list and state.list:IsShown() and not loader.pending then U.Refresh(true) end
        end)
    end)
end
