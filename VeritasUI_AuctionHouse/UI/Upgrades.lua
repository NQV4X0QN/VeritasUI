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

-- { rows, info } for the player now. rows: { link, price, slot, new, worn, gain, pct, perGold, quality }.
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
        filtered = 0, bestArmor = best }
    for _, g in pairs(listings) do
        local link, price = g.l, g.p
        local okI, _, _, quality, _, reqLevel = pcall(C_Item.GetItemInfo, link)
        if not okI or reqLevel == nil then
            info.uncached = info.uncached + 1
        elseif reqLevel <= level then
            local slot, new, worn = GS.AgainstWorn(link, W)
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
                            link = link, price = price, slot = slot, new = new, worn = worn, gain = gain, pct = pct,
                            perGold = gain / math.max(price / 10000, 0.0001), quality = quality,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.gain > b.gain end)
    local kept = {}
    for _, r in ipairs(rows) do
        if info.checked >= U.TOOLTIP_CHECKS or #kept >= U.MAX_ROWS then break end
        info.checked = info.checked + 1
        local bad = CannotUse(r.link)
        if bad then info.unusable = info.unusable + 1 else kept[#kept + 1] = r end
    end
    return kept, info
end

local SORTS = {
    gain = function(a, b) return a.gain > b.gain end,
    pct = function(a, b) return (a.pct or math.huge) > (b.pct or math.huge) end,
    price = function(a, b) return a.price < b.price end,
    perGold = function(a, b) return a.perGold > b.perGold end,
    slot = function(a, b) if a.slot ~= b.slot then return a.slot < b.slot end return a.gain > b.gain end,
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
local COLUMNS = {   -- key, label, width (0 = the rest), sort key, justify
    { "item", _G.NAME or "Item", 0, "gain", "LEFT" },
    { "slot", "Slot", 90, "slot", "LEFT" },
    { "gain", "Gain", 70, "pct", "RIGHT" },
    { "price", _G.AUCTION_HOUSE_BROWSE_HEADER_PRICE or "Price", 120, "price", "RIGHT" },
    { "perGold", "Gain per Gold", 100, "perGold", "RIGHT" },
}

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

local function Refresh(keepScroll)
    if not state.list then return end
    local rows, info = U.Compute()
    state.rows = rows or {}
    table.sort(state.rows, SORTS[state.sort or "gain"])
    local dp = CreateDataProvider()
    for i, r in ipairs(state.rows) do r.index = i; dp:Insert(r) end
    local retain = keepScroll and _G.ScrollBoxConstants and _G.ScrollBoxConstants.RetainScrollPosition
    state.scroll:SetDataProvider(dp, retain)
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
        state.sub:SetText(format("Scored for %s at level %d%s%s", W.profile.name, W.level, ageText, hidden))
    else
        state.sub:SetText("")
    end
    for _, h in ipairs(state.headers) do
        if h.arrow then h.arrow:SetShown(h.sortKey == (state.sort or "gain")) end
    end
end
U.Refresh = Refresh

local function InitRow(row, r)
    if not row.cells then
        row:SetHeight(ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        pcall(hl.SetAtlas, hl, "auctionhouse-ui-row-highlight")
        hl:SetBlendMode("ADD")
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_H - 4, ROW_H - 4)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon = icon
        row.cells = {}
        for i, col in ipairs(COLUMNS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH(col[5])
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end
        local right = 0
        for i = #COLUMNS, 2, -1 do right = right + COLUMNS[i][3] end
        row.cells[1]:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        row.cells[1]:SetPoint("RIGHT", row, "RIGHT", -right - 4, 0)
        local x = -right
        for i = 2, #COLUMNS do
            row.cells[i]:SetPoint("LEFT", row, "RIGHT", x, 0)
            row.cells[i]:SetWidth(COLUMNS[i][3] - 6)
            x = x + COLUMNS[i][3]
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
    local name = r.link:match("|h%[(.-)%]|h") or r.link
    local qc = _G.ITEM_QUALITY_COLORS and r.quality and _G.ITEM_QUALITY_COLORS[r.quality]
    row.cells[1]:SetText(qc and qc.hex and (qc.hex .. name .. "|r") or name)
    row.cells[2]:SetText(SLOT_NAMES[r.slot] or tostring(r.slot))
    row.cells[3]:SetText(GainText(r))
    row.cells[4]:SetText(Money(r.price))
    row.cells[5]:SetText(format("%.2f", r.perGold))
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
            if state.list and state.list:IsShown() then Refresh() end
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

    local headers = CreateFrame("Frame", nil, list)
    headers:SetAllPoints(itemList.HeaderContainer)
    state.headers = {}
    local right = 0
    for i = #COLUMNS, 2, -1 do right = right + COLUMNS[i][3] end
    local x = -right
    for i, col in ipairs(COLUMNS) do
        local okH, h = pcall(CreateFrame, "Button", nil, headers, "ColumnDisplayButtonShortTemplate")
        if not okH then h = CreateFrame("Button", nil, headers) end
        if i == 1 then
            h:SetPoint("TOPLEFT", headers, "TOPLEFT", 0, 0)
            h:SetPoint("BOTTOMRIGHT", headers, "BOTTOMRIGHT", -right, 0)
        else
            h:SetPoint("TOPLEFT", headers, "TOPRIGHT", x, 0)
            h:SetSize(col[3], 19)
            x = x + col[3]
        end
        if h.SetText then h:SetText(col[2]) end
        -- Blizzard's sort arrow sits 3 px right of the header text (AuctionHouseTableHeaderStringTemplate).
        local arrow = h:CreateTexture(nil, "OVERLAY")
        pcall(arrow.SetAtlas, arrow, "auctionhouse-ui-sortarrow", true)
        if h.Text then arrow:SetPoint("LEFT", h.Text, "RIGHT", 3, 0) else arrow:SetPoint("RIGHT", h, "RIGHT", -4, 0) end
        h.arrow, h.sortKey = arrow, col[4]
        h:SetScript("OnClick", function() state.sort = col[4]; Refresh() end)
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
end

-- keepScroll: reopened by Back, so the list stays where the player left it.
function U.Show(keepScroll)
    Build()
    if not (state.built and state.InBuy()) then return end
    FadeBlizzard(state.itemList, true)
    state.list:Show()
    if state.filterBtn then state.filterBtn:Show() end
    Refresh(keepScroll)
end

function U.Hide()
    if state.list then state.list:Hide() end
    if state.filterBtn then state.filterBtn:Hide() end
    if state.itemList then FadeBlizzard(state.itemList, false) end
end

AH.Events.On("AH_OPEN", function() Build() end)
AH.Events.On("AH_CLOSED", function() U.Hide(); ClearPending() end)
AH.Events.On("AH_SCAN_COMPLETE", function() if state.list and state.list:IsShown() then Refresh() end end)
-- A new level can bring a new armor type.
do
    local lv = CreateFrame("Frame")
    lv:RegisterEvent("PLAYER_LEVEL_UP")
    lv:SetScript("OnEvent", function() U.ForgetArmor() end)
end
