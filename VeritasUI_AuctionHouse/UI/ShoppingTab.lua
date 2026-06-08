-- VeritasUI_AuctionHouse / UI/ShoppingTab.lua
-- Phase 4: the SHOPPING tab — a modernized clean-room reimplementation of
-- Auctionator's Shopping tab (see AUCTIONHOUSE_DESIGN.md §0 TAB MODEL). Same
-- information architecture as Auctionator; rebuilt entirely on MODERN Blizzard UI
-- (SearchBoxTemplate w/ built-in clear-X, UIPanelButtonTemplate, InsetFrameTemplate,
-- WowScrollBoxList + MinimalScrollBar) so it reads as today's default UI, not 2020's.
--
-- LAYOUT (matches Auctionator's Shopping, modern elements):
--   [Search Term:] [ SearchBox(clear-X) ] [Search] [Search Options] [Add To List]
--   ┌ Shopping Lists | Recent Searches ┐   │ Price   Name        Available  Scanned
--   │                                  │   │ ─────────────────────────────────────
--   │   left inset (lists / recent)    │   │ [ WowScrollBoxList results ]
--   │                                  │   │
--   └ New List   Import   Export ──────┘   │                        [Export Results]
--
-- LAYER STATUS (this build = Layer 1, the skeleton):
--   ✅ Search strip + right results panel + left panel scaffold, modern elements.
--   ✅ Search → results works (reuses the verified AH.Search.Browse engine + shift-click).
--   🚧 Sub-tabs (Lists/Recent) toggle but show placeholders (content = Layer 3).
--   🚧 Search Options / Add To List / New List / Import / Export / Export Results render
--      in their correct positions but are honest stubs (print "later layer") — NOT wired.
--   🚧 Row-click drill-down + Buy Now = Layer 2.
-- Replaces UI/BrowseTab.lua (the pre-pivot search-only view).

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame = CreateFrame
local ipairs      = ipairs
local C_AuctionHouse = C_AuctionHouse

local ROW_H    = 22
local INSET    = 8
local SB_INSET = 16
local LEFT_W   = 230  -- left container width (narrowed — lists hold short search terms,
                      -- so the reclaimed width goes to the results columns on the right)

-- Right-panel result columns. Widened to fill the results box (esp. Name); the left
-- panel was narrowed to give this room. Anchor-based; tune in-game.
local COL_PRICE_X = 6
local COL_PRICE_W = 130
local COL_ICON_W  = ROW_H - 4
local COL_NAME_W  = 320
local COL_AVAIL_W = 80
local COL_DBP_W   = 130

----------------------------------------------------------------
--  Module-local UI state (single Shopping tab instance)
----------------------------------------------------------------
local ui = {
    built     = false,
    content   = nil,
    searchBox = nil,
    scrollBox = nil,
    scrollBar = nil,
    view      = nil,
    status    = nil,
    rows      = {},
    sort      = { order = nil, field = nil, kind = nil, dir = 1 },  -- active column sort (dir 1=asc, -1=desc)
    sortHeaders = {},   -- native header frames registered by our sort owner (RegisterHeader)
    leftMode  = "lists",   -- "lists" | "recent" (sub-tab selection)
    detail    = nil,       -- drill-down overlay state (built by BuildDetail)
}

-- Forward declarations for the drill-down detail view + sort plumbing. Defined later;
-- referenced as upvalues here so functions that mention them (sort owner, browse handlers)
-- bind to the SAME upvalue rather than capturing a nil global.
local OpenDetail, CloseDetail, BuildDetail, OnDetailResults, ApplySort, RefreshDataProvider
local SelectCommodityThrough, DetailRefresh, UpdateCommodityTotal
local PaintRowSelection, RepaintDetailSelection

----------------------------------------------------------------
--  Helpers (carried over from the verified browse view, unchanged)
----------------------------------------------------------------
local function ResolveName(entry)
    local info = AH.Search.GetKeyInfo(entry.itemKey)
    if info and info.itemName and info.itemName ~= "" then
        local r, g, b = 1, 1, 1
        if info.quality and C_Item and C_Item.GetItemQualityColor then
            local cr, cg, cb = C_Item.GetItemQualityColor(info.quality)
            if cr then r, g, b = cr, cg, cb end
        end
        return info.itemName, r, g, b, info.iconFileID
    end
    return nil
end

local function MoneyStr(copper)
    if not copper or copper <= 0 then return "" end
    return AH.Money and AH.Money.Format(copper) or tostring(copper)
end

-- Stored DB price — EXACT MATCH ONLY (OQ#6); blank on a miss, never an estimate.
local function DBPriceStr(entry)
    if not AH.DB then return "" end
    local price
    if entry.appearanceLink then
        price = AH.DB.GetMarketPriceForLink(entry.appearanceLink)
    end
    if not price and entry.itemID then
        price = AH.DB.GetMarketPrice("i:" .. entry.itemID)
    end
    return MoneyStr(price)
end

local function SetStatus(text)
    if not ui.status then return end
    if text and text ~= "" then
        ui.status:SetText(text); ui.status:Show()
    else
        ui.status:Hide()
    end
end

-- Push ui.rows into the ScrollBox as an index-range provider. With TableBuilder, the
-- elements are integer indices (1..#rows); TableBuilder's data provider closure maps
-- each index back to ui.rows[index] and populates the cells.
--
-- TableBuilder requires an Arrange() to compute column widths AND build the visible
-- headers; ScrollUtil.RegisterTableBuilder does NOT do this for us. Arrange() needs a
-- valid table width, which derives from the header container — at Build() time the
-- anchored width isn't resolved yet, so we (re)assert it from the live header-container
-- width here (this runs on search/refresh, long after layout settles) and Arrange before
-- handing rows to the scrollbox. Mirrors Auctionator calling tableBuilder:Arrange().
local function EnsureArranged()
    if not (ui.tableBuilder and ui.headerContainer) then return false end
    local w = ui.headerContainer:GetWidth()
    if not w or w <= 0 then return false end   -- layout not resolved yet; caller retries
    ui.tableBuilder:SetTableWidth(w)
    ui.tableBuilder:Arrange()
    return true
end

-- Sortable value for a row given a field+kind. Returns a comparable scalar.
--   "money"  → copper int (minPrice)
--   "number" → numeric (totalQuantity)
--   "name"   → resolved item name lowercased (async-cached; "" until it streams in,
--              so unresolved rows sort together at the top of an A→Z pass — they
--              re-sort automatically on the ITEM_KEY_ITEM_INFO_RECEIVED refresh)
local function SortValue(entry, field, kind)
    if kind == "name" then
        local info = AH.Search.GetKeyInfo(entry.itemKey)
        local n = info and info.itemName
        return (n and n ~= "") and n:lower() or ""
    end
    local v = entry[field]
    return tonumber(v) or 0
end

-- Stable comparator: primary by the active column, ties broken by name then itemID so
-- the order is deterministic (table.sort is not stable on its own).
local function MakeComparator(field, kind, dir)
    return function(a, b)
        local av, bv = SortValue(a, field, kind), SortValue(b, field, kind)
        if av ~= bv then
            if dir < 0 then return av > bv end
            return av < bv
        end
        local an = SortValue(a, "name", "name")
        local bn = SortValue(b, "name", "name")
        if an ~= bn then return an < bn end
        return (a.itemID or 0) < (b.itemID or 0)
    end
end

-- Reorder ui.rows in place per the active sort (no-op if no column selected).
function ApplySort()
    local s = ui.sort
    if not (s and s.field and #ui.rows > 1) then return end
    table.sort(ui.rows, MakeComparator(s.field, s.kind, s.dir))
end

----------------------------------------------------------------
--  NATIVE sort header owner
--
--  Verified via live-client introspection (/ah hdrdump) — the native
--  AuctionHouseTableHeaderStringTemplate is NOT a static label: its Init(owner, text,
--  sortOrder) registers with an OWNER and drives both the sort arrow (.Arrow child,
--  atlas auctionhouse-ui-sortarrow) AND the interactive hover/active highlight off that
--  owner's protocol. With our previous empty `{}` owner the header was inert — no arrow,
--  no highlight, dead click. The real owner contract (method names confirmed from the
--  live Buy-tab header's owner) is:
--    owner:RegisterHeader(headerFrame)         -- Init calls this; we track the frame
--    owner:SetSortOrder(sortOrder)             -- header OnClick calls this
--    owner:GetSortOrderState(sortOrder) -> n   -- UpdateArrow reads this; n is a member
--                                                 of the GLOBAL table AuctionHouseSortOrderState
--    owner:UpdateHeaders()                     -- re-run UpdateArrow on every header
--  Confirmed AuctionHouseSortOrderState (global, NOT under Enum.):
--    None=1, PrimarySorted=2, PrimaryReversed=3, Sorted=4, Reversed=5
--  Arrow shows for any non-None state; Sorted/PrimarySorted = up (ascending),
--  Reversed/PrimaryReversed = down (descending). We use PrimarySorted/PrimaryReversed
--  (we only ever have one active sort column → it's always the "primary").
--
--  We map our three columns to Enum.AuctionHouseSortOrder values (Price=0, Name=1) used
--  purely as stable per-column IDENTIFIERS for this owner — NOT passed to any server
--  query (our sort is client-side on ui.rows). The "Available" column has no clean
--  AuctionHouseSortOrder member, so it gets a private high ID; identity is all the owner
--  needs. Sort field/kind are carried on the column spec, keyed by that sortOrder id.
----------------------------------------------------------------
local SOS = _G.AuctionHouseSortOrderState or
    { None = 1, PrimarySorted = 2, PrimaryReversed = 3, Sorted = 4, Reversed = 5 }

local sortOwner = {}
ui.sortOwner = sortOwner

-- sortOrder id → { field, kind } for our columns (populated in AddColumn).
ui.sortSpecByOrder = {}

function sortOwner:RegisterHeader(headerFrame)
    -- Track each native header so UpdateHeaders can refresh them all. Idempotent.
    for _, h in ipairs(ui.sortHeaders) do
        if h == headerFrame then return end
    end
    ui.sortHeaders[#ui.sortHeaders + 1] = headerFrame
end

function sortOwner:GetAuctionHouseFrame()
    return AuctionHouseFrame
end

-- Header OnClick → establish/flip the sort. Same column toggles direction; a new column
-- starts ascending. Then re-sort rows, refresh every header's arrow, and re-provide.
function sortOwner:SetSortOrder(sortOrder)
    local spec = ui.sortSpecByOrder[sortOrder]
    if not spec then return end
    local s = ui.sort
    if s.order == sortOrder then
        s.dir = -s.dir
    else
        s.order, s.field, s.kind, s.dir = sortOrder, spec.field, spec.kind, 1
    end
    self:UpdateHeaders()
    RefreshDataProvider()
end

-- UpdateArrow reads this per header to decide arrow visibility + direction.
function sortOwner:GetSortOrderState(sortOrder)
    if ui.sort.order ~= sortOrder then
        return SOS.None
    end
    return (ui.sort.dir > 0) and SOS.PrimarySorted or SOS.PrimaryReversed
end

-- Re-run each native header's own UpdateArrow so arrows reflect the active sort.
function sortOwner:UpdateHeaders()
    for _, h in ipairs(ui.sortHeaders) do
        if h.UpdateArrow then h:UpdateArrow() end
    end
end

function RefreshDataProvider()
    if not ui.scrollBox then return end
    ApplySort()
    -- Arrange first so columns have widths + headers exist before rows are added. If the
    -- frame hasn't been laid out yet (width 0), retry next frame.
    if not EnsureArranged() then
        C_Timer.After(0, function()
            if EnsureArranged() and ui.scrollBox then
                ui.scrollBox:SetDataProvider(CreateIndexRangeDataProvider(#ui.rows))
            end
        end)
        return
    end
    ui.scrollBox:SetDataProvider(CreateIndexRangeDataProvider(#ui.rows))
end

-- Honest stub for not-yet-wired Layer-2/3/4 controls.
local function Stub(label)
    VUI.Print(AH.TAG, label .. " — coming in a later layer (Shopping is built in stages).")
end

----------------------------------------------------------------
--  Left-panel sub-tab switching (Shopping Lists / Recent Searches)
----------------------------------------------------------------
local function UpdateLeftMode()
    if not ui.leftInset then return end
    local isLists = (ui.leftMode == "lists")
    -- Native tab selection state via PanelTemplates_SetTab on the sub-tab container
    -- (tab id 1 = Shopping Lists, 2 = Recent Searches).
    if ui.subTabContainer then
        PanelTemplates_SetTab(ui.subTabContainer, isLists and 1 or 2)
    end
    if ui.leftPlaceholder then
        ui.leftPlaceholder:SetText(isLists
            and "No shopping lists yet.\n(Create one with New List — coming soon.)"
            or  "No recent searches yet.")
    end
end

----------------------------------------------------------------
--  Build (one-time)
----------------------------------------------------------------
local function Build(content)
    if ui.built then return end
    ui.built   = true
    ui.content = content

    --======================== TOP SEARCH STRIP ========================--
    -- Per Auctionator Main.xml: SearchLabel at TOPLEFT x=80 (clears portrait), then
    -- search box, then Search / Search Options / Add To List flowing left→right. We drop
    -- the literal "Search Term:" label (modern search box is self-evident) but keep the
    -- x=80 left start and the left→right button flow.
    local STRIP_Y = -10   -- below the title bar (Auctionator's frame starts at TOP y=-40)

    local searchBox = CreateFrame("EditBox", nil, content, "SearchBoxTemplate")
    searchBox:SetSize(220, 22)
    searchBox:SetPoint("TOPLEFT", content, "TOPLEFT", 80, STRIP_Y)
    searchBox:SetAutoFocus(false)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Search items...")
    end
    ui.searchBox = searchBox

    local searchBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    searchBtn:SetSize(90, 22)
    searchBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    searchBtn:SetText(SEARCH or "Search")
    ui.searchBtn = searchBtn

    local optBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    optBtn:SetSize(110, 22)
    optBtn:SetPoint("LEFT", searchBtn, "RIGHT", 5, 0)
    optBtn:SetText("Search Options")
    optBtn:SetScript("OnClick", function() Stub("Search Options") end)

    local addBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addBtn:SetSize(90, 22)
    addBtn:SetPoint("LEFT", optBtn, "RIGHT", 5, 0)
    addBtn:SetText("Add To List")
    addBtn:SetScript("OnClick", function() Stub("Add To List") end)

    local function DoSearch()
        local raw = searchBox:GetText() or ""
        local term = AH.Search.NormalizeSearchTerm(raw)
        if term == "" then return end
        searchBox:ClearFocus()
        ui.rows = {}
        RefreshDataProvider()
        SetStatus("Searching...")
        AH.Search.Browse(raw)
    end
    ui.DoSearch = DoSearch
    searchBtn:SetScript("OnClick", DoSearch)
    searchBox:SetScript("OnEnterPressed", function(self) DoSearch(); self:ClearFocus() end)

    --======================== LEFT PANEL ========================--
    -- Per Auctionator Main.xml: the lists/recents container is a FIXED-WIDTH (280)
    -- frame anchored TOP/BOTTOM/LEFT — NOT both corners (the earlier bug: anchoring
    -- BOTTOMRIGHT to a narrow button + SetWidth made the inset collapse to button width).
    -- It contains its own Inset(:SetAllPoints) + ScrollBox + ScrollBar. The results
    -- region then anchors to THIS container's right edge / scrollbar.
    --
    -- Sub-tabs (Shopping Lists / Recent Searches) sit ABOVE the container, bottom-aligned
    -- to its top-left (Auctionator: ContainerTabs BOTTOMLEFT = ListsContainer TOPLEFT x=20).
    -- New List bottom-left; Import/Export bottom-right of the container.

    -- Bottom buttons first (the container anchors its BOTTOM above them).
    local newBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    newBtn:SetSize(74, 22)
    newBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 5, INSET)
    newBtn:SetText("New List")
    newBtn:SetScript("OnClick", function() Stub("New List") end)

    -- The fixed-width left container (lists OR recents share this region; we toggle a
    -- placeholder inside for Layer 1).
    local leftContainer = CreateFrame("Frame", nil, content)
    leftContainer:SetWidth(LEFT_W)
    leftContainer:SetPoint("TOPLEFT",    content, "TOPLEFT", 20, STRIP_Y - 50)
    leftContainer:SetPoint("BOTTOM",     newBtn,  "TOP",     0, 8)
    ui.leftInset = leftContainer   -- (name kept for downstream refs)

    -- Inset border filling the container (NineSlice border via InsetFrameTemplate).
    -- Replace the template's default `.Bg` (old UI-Background-Marble) with the NATIVE AH
    -- background atlas `auctionhouse-background-index` — the exact themed texture Blizzard's
    -- own AH index/browse views use (Auctionator uses this same atlas). Native, not invented.
    local leftInsetBorder = CreateFrame("Frame", nil, leftContainer, "InsetFrameTemplate")
    leftInsetBorder:SetAllPoints()
    if leftInsetBorder.Bg then
        leftInsetBorder.Bg:SetAtlas("auctionhouse-background-index", true)
        leftInsetBorder.Bg:SetHorizTile(false)
        leftInsetBorder.Bg:SetVertTile(false)
    end

    -- Left scrollbar (trim style, as Auctionator) anchored to the container's right edge;
    -- the results region keys off this so the split is exact, not guessed.
    local leftScrollBar = CreateFrame("EventFrame", nil, leftContainer, "MinimalScrollBar")
    leftScrollBar:SetPoint("TOPLEFT",    leftContainer, "TOPRIGHT", 4, -2)
    leftScrollBar:SetPoint("BOTTOMLEFT", leftContainer, "BOTTOMRIGHT", 4, 2)
    ui.leftScrollBar = leftScrollBar

    local leftPlaceholder = leftContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    leftPlaceholder:SetPoint("CENTER", leftContainer, "CENTER", 0, 0)
    leftPlaceholder:SetWidth(LEFT_W - 24)
    leftPlaceholder:SetJustifyH("CENTER")
    ui.leftPlaceholder = leftPlaceholder

    -- Sub-tabs above the container — native PanelTopTabButtonTemplate tabs (the same
    -- "top tab" style Blizzard's Auctions/Bids tabs and Auctionator's Shopping sub-tabs
    -- use). They live in a dedicated container frame: PanelTopTabButtonTemplate inherits
    -- PanelTabButtonTemplate, which carries parentArray="Tabs", so parenting them to a
    -- private container keeps that auto-insert out of any Blizzard array (the §2.9 trap).
    -- PanelTemplates_SetTab(container, id) drives the selected state.
    local subTabContainer = CreateFrame("Frame", nil, content)
    subTabContainer:SetSize(LEFT_W, 24)
    subTabContainer:SetPoint("BOTTOMLEFT", leftContainer, "TOPLEFT", 10, 0)   -- inset ~10px so the tab's transparent rounded left-skirt clears the panel edge (native tab strips inset similarly)
    ui.subTabContainer = subTabContainer

    local tabLists = CreateFrame("Button", nil, subTabContainer, "PanelTopTabButtonTemplate")
    tabLists:SetID(1)
    tabLists:SetText("Shopping Lists")
    tabLists:SetPoint("BOTTOMLEFT", subTabContainer, "BOTTOMLEFT", 0, 0)
    tabLists:SetScript("OnClick", function() ui.leftMode = "lists"; UpdateLeftMode() end)
    ui.tabLists = tabLists

    local tabRecent = CreateFrame("Button", nil, subTabContainer, "PanelTopTabButtonTemplate")
    tabRecent:SetID(2)
    tabRecent:SetText("Recent Searches")
    tabRecent:SetPoint("LEFT", tabLists, "RIGHT", -16, 0)   -- native tab strip overlaps slightly
    tabRecent:SetScript("OnClick", function() ui.leftMode = "recent"; UpdateLeftMode() end)
    ui.tabRecent = tabRecent

    -- Tell PanelTemplates how many tabs the container has (sizes + enables them).
    PanelTemplates_SetNumTabs(subTabContainer, 2)
    PanelTemplates_SetTab(subTabContainer, 1)

    -- Import / Export at the container's bottom-right (Auctionator: Export RIGHT =
    -- RecentsContainer RIGHT x=20; Import RIGHT = Export LEFT).
    local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportBtn:SetSize(68, 22)
    exportBtn:SetPoint("BOTTOM", newBtn, "BOTTOM", 0, 0)
    exportBtn:SetPoint("RIGHT", leftScrollBar, "RIGHT", 0, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function() Stub("Export") end)

    local importBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importBtn:SetSize(68, 22)
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    importBtn:SetPoint("BOTTOM", newBtn, "BOTTOM", 0, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function() Stub("Import") end)

    --======================== RIGHT PANEL (results) ========================--
    -- Per Auctionator Main.xml: ResultsListing anchors TOPLEFT = ListsContainer.ScrollBar
    -- TOPRIGHT x=5 (the split is defined by the LEFT scrollbar's right edge), BOTTOMRIGHT
    -- = parent BOTTOMRIGHT x=-20. The results inset is drawn AROUND the listing.
    -- Column headers = native tab-bordered ColumnDisplayButtonTemplate buttons.
    local exportResultsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportResultsBtn:SetSize(120, 22)
    exportResultsBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, INSET)
    exportResultsBtn:SetText("Export Results")
    exportResultsBtn:SetScript("OnClick", function() Stub("Export Results") end)

    -- Results inset: from the left scrollbar's right edge across to near the frame's
    -- right edge. The scrollbar sits OUTSIDE the inset's right border in the small
    -- remaining margin (content right is now -8 from the frame edge; inset right -16
    -- leaves ~8px for the bar).
    local rightInset = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
    -- LEFT (horizontal only) keys off the left scrollbar's right edge; TOP keys off the
    -- left container so both panels' tops are governed by ONE shared reference and align
    -- exactly. (Previously TOPLEFT also pinned the top to the scrollbar, whose own top is
    -- leftContainer −2, dragging the right panel down a couple px.)
    rightInset:SetPoint("LEFT",   leftScrollBar, "RIGHT", 8, 0)
    rightInset:SetPoint("RIGHT",  content,       "RIGHT", -16, 0)
    rightInset:SetPoint("TOP",    leftContainer, "TOP",   0, 0)
    rightInset:SetPoint("BOTTOM", exportResultsBtn, "TOP", 0, 8)   -- +8 to match the left panel (newBtn TOP +8); was +6, sitting 2px lower
    ui.rightInset = rightInset
    -- Native AH background atlas (see left inset) instead of the template's marble.
    if rightInset.Bg then
        rightInset.Bg:SetAtlas("auctionhouse-background-index", true)
        rightInset.Bg:SetHorizTile(false)
        rightInset.Bg:SetVertTile(false)
    end

    --======================== HEADER + SCROLLBOX + TABLEBUILDER ========================--
    -- Native results table via Blizzard's TableBuilder (CreateTableBuilder): it lays the
    -- tab-bordered column headers edge-to-edge in HeaderContainer and drives each row's
    -- cells from the same column defs, so headers and cells share one width model.
    -- Cell templates: UI/ShoppingCells.xml (VUIAH*CellTemplate); header template: native
    -- AuctionHouseTableHeaderStringTemplate (the tab-bordered ColumnDisplayButtonShort).

    -- Header container straddles the inset's TOP border (native: column headers sit
    -- half-above the results frame, overlapping its top edge — see Blizzard's Buy tab).
    -- Parented to `content` (not the inset) so it isn't clipped, and centered vertically
    -- on the inset's top edge. TableBuilder fills it with the tab-bordered header buttons.
    local headerContainer = CreateFrame("Frame", nil, content)
    headerContainer:SetHeight(19)
    headerContainer:SetPoint("LEFT",   rightInset, "TOPLEFT",  6, 0)
    headerContainer:SetPoint("RIGHT",  rightInset, "TOPRIGHT", -6, 0)
    headerContainer:SetPoint("BOTTOM", rightInset, "TOP",      0, 0)   -- header bottoms seat just at/above the frame's top border (native look)
    ui.headerContainer = headerContainer

    -- ScrollBox fills the inset (headers are outside/above it now); ScrollBar OUTSIDE
    -- the inset's right edge.
    local scrollBox = CreateFrame("Frame", nil, rightInset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT",     rightInset, "TOPLEFT",     4, -6)
    scrollBox:SetPoint("BOTTOMRIGHT", rightInset, "BOTTOMRIGHT", -4, 4)
    ui.scrollBox = scrollBox

    local scrollBar = CreateFrame("EventFrame", nil, content, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",    rightInset, "TOPRIGHT", 4, -4)
    scrollBar:SetPoint("BOTTOMLEFT", rightInset, "BOTTOMRIGHT", 4, 4)
    ui.scrollBar = scrollBar

    local status = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    status:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
    status:SetTextColor(0.7, 0.7, 0.7)
    status:Hide()
    ui.status = status

    -- ScrollBox list view: each element is a 1-based index into ui.rows; the row frame
    -- is a bare Button (TableBuilder owns its cells). Element extent = ROW_H.
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, index)
        -- TableBuilder populates the cells; we add a hover highlight + click once.
        if not row._vuiHl then
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            row._vuiHl = hl
        end
        -- Row-click → drill into this item's individual auctions. `index` is the 1-based
        -- position into ui.rows (the index-range data provider); read the browse row back
        -- from there. Re-bound each init (rows recycle) so the captured index is current.
        row._vuiIndex = index
        if not row._vuiClickWired then
            row:RegisterForClicks("LeftButtonUp")
            row:SetScript("OnClick", function(self)
                local entry = ui.rows[self._vuiIndex]
                if entry and entry.itemKey then OpenDetail(entry) end
            end)
            row._vuiClickWired = true
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    ui.view = view

    -- TableBuilder: header container + data provider (index -> rowData) + columns.
    local tb = CreateTableBuilder()
    tb:SetHeaderContainer(headerContainer)
    -- Overlap adjacent column headers by 2px so their edge slices MERGE into one
    -- connecting bracket (native uses SetColumnHeaderOverlap(2)); without this each
    -- header draws its own full Left+Right slices and you get doubled brackets.
    tb:SetColumnHeaderOverlap(2)
    tb:SetDataProvider(function(index) return ui.rows[index] end)
    ScrollUtil.RegisterTableBuilder(scrollBox, tb, function(elementData) return elementData end)
    ui.tableBuilder = tb

    local function AddColumn(headerText, width, cellTemplate, cellParam, sortOrder, sortField, sortKind)
        local col = tb:AddColumn()
        -- AuctionHouseTableHeaderStringMixin:Init(owner, headerText, sortOrder). Passing
        -- our real sortOwner + a sortOrder id activates the NATIVE machinery: Init calls
        -- owner:RegisterHeader(self); the header's own OnClick calls owner:SetSortOrder;
        -- its UpdateArrow reads owner:GetSortOrderState. This lights the genuine sort
        -- arrow AND the interactive hover/active highlight — no fabrication. (Verified
        -- owner contract via /ah hdrdump against the live 12.0.5 client.)
        if sortOrder ~= nil then
            ui.sortSpecByOrder[sortOrder] = { field = sortField, kind = sortKind }
            col:ConstructHeader("BUTTON", "AuctionHouseTableHeaderStringTemplate",
                ui.sortOwner, headerText, sortOrder)
        else
            col:ConstructHeader("BUTTON", "AuctionHouseTableHeaderStringTemplate", {}, headerText, nil)
        end
        col:ConstructCells("FRAME", cellTemplate, cellParam)
        col:SetCellPadding(4, 4)
        if width then col:SetFixedConstraints(width, 0) else col:SetFillConstraints(1.0, 0) end
        return col
    end
    -- Price (fixed) · Name (fills the rest) · Available (fixed). Matches Auctionator and
    -- native Buy exactly — no "Scanned" column (it duplicated the live Price and deviated
    -- from native; the scanned/DB market price lives in item TOOLTIPS, its proper home).
    -- sortOrder ids: Price/Name reuse Enum.AuctionHouseSortOrder.Price/Name (0/1) as stable
    -- per-column identifiers (NOT sent to any server query — sort is client-side); Available
    -- has no clean enum member, so it gets a private high id (identity is all the owner needs).
    local SO = Enum and Enum.AuctionHouseSortOrder or {}
    AddColumn("Price",     COL_PRICE_W, "VUIAHMoneyCellTemplate", "minPrice",
        SO.Price or 0, "minPrice", "money")
    AddColumn("Name",      nil,         "VUIAHItemCellTemplate",  nil,
        SO.Name or 1,  "name", "name")
    AddColumn("Available", COL_AVAIL_W, "VUIAHTextCellTemplate",  "totalQuantity",
        1000,          "totalQuantity", "number")

    -- Arrange once after layout settles so the column headers render immediately when
    -- the tab is first shown (before any search). Deferred a frame so the header
    -- container's anchored width is resolved.
    C_Timer.After(0, function() EnsureArranged() end)

    UpdateLeftMode()   -- seed left-panel sub-tab state + placeholder text
end

----------------------------------------------------------------
--  DRILL-DOWN DETAIL VIEW (Layer 2)
--
--  Clicking a browse row opens this over the results inset: Back + item header, a
--  native TableBuilder list of that item's individual auctions (Price / Qty / Time
--  Left / Seller), and an adaptive footer:
--    • COMMODITY (fungible: ore/herbs/potions) — a quantity box + a two-step Buy
--      (Start → server quote → Confirm), each step a hardware-event button click,
--      driven by the proven AH.Buy commodity engine.
--    • ITEM (gear/pet: unique auctionID) — select a row, then a single-click Buy
--      (C_AuctionHouse.PlaceBid via AH.Buy.BuyItem) — one protected call, no quote.
--  Both protected calls originate from the Buy button's OnClick (a genuine hardware
--  event) and are NOT routed through the throttle queue (§2.6 / OQ#5). The FEEDING
--  search (AH.Search.QueryItem) is throttle-queued; the buy CALL is not.
--
--  To avoid any overlay bleed-through (and to sidestep fabricating an opaque fill —
--  native-asset discipline), we HIDE the browse list/headers/scrollbar while the
--  detail view is shown and restore them on Back. The detail view reuses the SAME
--  cell templates (VUIAHMoneyCellTemplate / VUIAHTextCellTemplate) — no new XML.
----------------------------------------------------------------

-- Single largest-unit time-left string ("2d", "14h", "3m"); blank if unknown. Uses
-- Blizzard's own SecondsToTime so the wording matches the default UI.
local function TimeLeftText(secs)
    if not secs or secs <= 0 then return "" end
    if SecondsToTime then
        local ok, s = pcall(SecondsToTime, secs, true, false, 1)  -- noSeconds, abbrev, 1 unit
        if ok and s and s ~= "" then return s end
    end
    return ""
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function DetailStatus(text)
    local d = ui.detail
    if not (d and d.status) then return end
    if text and text ~= "" then d.status:SetText(text); d.status:Show()
    else d.status:Hide() end
end

-- TableBuilder needs a resolved header-container width before Arrange (mirrors the
-- Push the auction rows into the headerless list (plain index-range provider; the row
-- initializer reads ui.detail.rows[index] and fills price + quantity).
function DetailRefresh()
    local d = ui.detail
    if not (d and d.scrollBox) then return end
    d.scrollBox:SetDataProvider(CreateIndexRangeDataProvider(#d.rows))
end

-- Paint ONE row's gold selection overlay against the current selection state. Reads the
-- row's own _vuiIndex, so it works whether called from the element initializer or a live
-- ForEachFrame walk. Commodities select cumulatively (rows 1..selThrough); items select
-- the single selIndex row.
function PaintRowSelection(row)
    if not (row and row._vuiSel and row._vuiIndex) then return end
    local d = ui.detail
    local selected = false
    if d then
        if d.isCommodity then
            selected = d.selThrough ~= nil and row._vuiIndex <= d.selThrough
        else
            selected = d.selIndex == row._vuiIndex
        end
    end
    if selected then row._vuiSel:Show() else row._vuiSel:Hide() end
end

-- Repaint selection on all CURRENTLY-REALIZED rows. The data-provider swap in DetailRefresh
-- only re-runs the element initializer when the row set changes; a pure selection change
-- (same rows, different highlight) leaves realized frames untouched — so we walk the live
-- frames directly. This is what makes a click visibly update the gold highlight.
function RepaintDetailSelection()
    local d = ui.detail
    if not (d and d.scrollBox and d.scrollBox.ForEachFrame) then return end
    d.scrollBox:ForEachFrame(function(row) PaintRowSelection(row) end)
end

-- Cumulative commodity selection: clicking row N selects rows 1..N (cheapest through N),
-- sums their quantities into the Quantity box, highlights them gold, and re-renders — the
-- native commodity-buy behavior. Clicking the same row again toggles the selection off.
function SelectCommodityThrough(index)
    local d = ui.detail
    if not (d and d.isCommodity and d.rows) then return end
    if d.selThrough == index then
        d.selThrough = nil           -- click same row again → clear
    else
        d.selThrough = index
    end
    local total = 0
    if d.selThrough then
        if d.selThrough >= #d.rows and d.serverQty then
            -- Selecting through the last row = "buy all" → use the server's authoritative
            -- total (the row-sum can under-count vs the server quantity).
            total = d.serverQty
        else
            for i = 1, d.selThrough do
                total = total + (d.rows[i] and d.rows[i].quantity or 0)
            end
        end
    end
    local cap = d.serverQty or d.maxQty or total
    -- Programmatic SetNumber: OnTextChanged's `userInput` arg is false here, so it won't
    -- clear the selection we're setting (no home-grown flag needed).
    if total > 0 and d.qtyBox then
        d.qtyBox:SetNumber(math.min(total, cap))
    elseif d.qtyBox then
        d.qtyBox:SetNumber(1)
    end
    UpdateCommodityTotal()
    RepaintDetailSelection()         -- repaint the gold highlight on live rows 1..selThrough
end

-- Re-run the drill-down for the open item (after a purchase, to drop the bought row).
local function DetailRequery()
    local d = ui.detail
    if not (d and d.entry) then return end
    d.rows = {}; DetailRefresh(); DetailStatus("Loading...")
    AH.Search.QueryItem(d.entry, OnDetailResults)
end

-- Running total for the commodity qty selector via the native MoneyDisplayFrame. Sum is
-- a local estimate from the cheapest unit; the authoritative total is the server quote
-- shown on the Buy→Confirm button. We tint the label "(est.)" so it never reads as final.
function UpdateCommodityTotal()
    local d = ui.detail
    if not (d and d.isCommodity and d.totalMoney) then return end
    local qty = clamp(tonumber(d.qtyBox:GetNumber()) or 1, 1, d.maxQty or 1)
    -- Blended total: fill `qty` units from the cheapest rows upward (how a commodity
    -- purchase actually fills across price tiers), summing unit×take per tier.
    local remaining, total = qty, 0
    for i = 1, #d.rows do
        if remaining <= 0 then break end
        local r = d.rows[i]
        local take = math.min(remaining, r.quantity or 0)
        total = total + take * (r.unitPrice or 0)
        remaining = remaining - take
    end
    local unit = (d.rows[1] and d.rows[1].unitPrice) or 0   -- cheapest unit (Unit Price line)
    if d.unitMoney and d.unitMoney.SetAmount then d.unitMoney:SetAmount(unit) end
    if d.totalMoney.SetAmount then d.totalMoney:SetAmount(total) end
end

-- Reset the footer to its idle state for the current mode (commodity vs item).
local function ResetBuyControls()
    local d = ui.detail
    if not d then return end
    d.buyState = "idle"
    if d.isCommodity then
        d.qtyLabel:Show(); d.qtyBox:Show()
        d.unitLabel:Show(); d.unitMoney:Show()
        d.totalLabel:Show(); d.totalMoney:Show(); d.itemHint:Hide()
        d.buyBtn:SetText("Buy"); d.buyBtn:Enable()
        UpdateCommodityTotal()
    else
        d.qtyLabel:Hide(); d.qtyBox:Hide()
        d.unitLabel:Hide(); d.unitMoney:Hide()
        d.totalLabel:Hide(); d.totalMoney:Hide(); d.itemHint:Show()
        d.selIndex = nil; d.selected = nil
        d.buyBtn:SetText("Buy"); d.buyBtn:Disable()
    end
end

function BuildDetail()
    local d = ui.detail
    if d and d.built then return end
    d = ui.detail or {}
    ui.detail = d
    d.built = true
    d.rows  = {}

    -- The detail surface occupies the SAME right-hand region the browse results used
    -- (the left Shopping Lists panel stays visible). Parented to ui.content — NOT to
    -- ui.rightInset — so that inset's border doesn't enclose us as a "box". OpenDetail
    -- hides the browse right-side widgets (rightInset/scrollbox/headers) while this shows.
    local frame = CreateFrame("Frame", nil, ui.content)
    -- Match the browse rightInset's VERTICAL extent exactly (top+bottom+left) so the detail
    -- panels line up level with the Shopping Lists frame. Extend ONLY the right edge — to
    -- content right −8 (the browse inset stops at −16 to leave its own scrollbar room) —
    -- reclaiming ~8px of dead chrome while still leaving a little margin past our scrollbar.
    frame:SetPoint("TOPLEFT",     ui.rightInset, "TOPLEFT",     0, 0)
    frame:SetPoint("BOTTOMLEFT",  ui.rightInset, "BOTTOMLEFT",  0, 0)
    frame:SetPoint("RIGHT",       ui.content,    "RIGHT",       -8, 0)
    frame:Hide()
    d.frame = frame

    --— Back as a real button (native uses a framed button), then a TWO-PANE split: a WIDE
    --  left detail pane and a NARROW right list pane (native ratio is roughly 2:1). —--
    local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    back:SetSize(90, 22)
    back:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    back:SetText("Back")
    back:SetScript("OnClick", function() CloseDetail() end)
    d.backBtn = back

    -- Panes start below the Back button and stop short of the bottom. The LEFT (detail)
    -- pane is WIDE; the RIGHT (list) pane is NARROW — just price + quantity. Scrollbar
    -- lives OUTSIDE the right inset, on the chrome.
    local PANES_TOP   = -32
    local RIGHT_PANE_W = 200   -- list column: price + qty, room for large gold AND large qty
    local SB_GAP       = 10    -- chrome room for the scrollbar right of the inset (was 18 —
                               -- too wide, left dead space; the MinimalScrollBar needs ~10)

    -- RIGHT list inset. Background = the verified native commodities-market atlas (the same
    -- one CommoditiesBuyFrame.Background uses) — it has NO baked-in category divider, unlike
    -- auctionhouse-background-index (whose vertical divider was showing as the stray line +
    -- doubled edge). Scrollbar lives out on the chrome in SB_GAP.
    local rightInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    rightInset:SetWidth(RIGHT_PANE_W)
    rightInset:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -SB_GAP, PANES_TOP)
    rightInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SB_GAP, 2)
    if rightInset.Bg then
        rightInset.Bg:SetAtlas("auctionhouse-background-buy-noncommodities-market", false)
        rightInset.Bg:SetHorizTile(false); rightInset.Bg:SetVertTile(false)
    end
    d.rightInset = rightInset
    local rightPane = CreateFrame("Frame", nil, rightInset)
    rightPane:SetPoint("TOPLEFT",     rightInset, "TOPLEFT",     4, -4)
    rightPane:SetPoint("BOTTOMRIGHT", rightInset, "BOTTOMRIGHT", -4, 4)
    d.rightPane = rightPane

    -- LEFT detail inset: WIDE, fills from the left edge to just before the right inset.
    -- Background = the verified native non-commodities-market atlas (no divider).
    local leftInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    leftInset:SetPoint("TOPLEFT",     frame, "TOPLEFT",  0, PANES_TOP)
    leftInset:SetPoint("BOTTOMRIGHT", rightInset, "BOTTOMLEFT", -2, 0)   -- narrow divider gap
    if leftInset.Bg then
        leftInset.Bg:SetAtlas("auctionhouse-background-buy-noncommodities-market", false)
        leftInset.Bg:SetHorizTile(false); leftInset.Bg:SetVertTile(false)
    end
    d.leftInset = leftInset
    local leftPane = CreateFrame("Frame", nil, leftInset)
    leftPane:SetPoint("TOPLEFT",     leftInset, "TOPLEFT",     4, -4)
    leftPane:SetPoint("BOTTOMRIGHT", leftInset, "BOTTOMRIGHT", -4, 4)
    d.leftPane = leftPane

    -- Item card: a THIN 1px-bordered banner (NOT InsetFrameTemplate, which draws a heavy
    -- beveled frame). Uses BackdropTemplate with Blizzard's 1px tooltip-style edge file so
    -- the border is a clean single line, matching native ItemDisplay's thin border. The
    -- header atlas fills inside it.
    local card = CreateFrame("Frame", nil, leftPane, "BackdropTemplate")
    card:SetPoint("TOPLEFT",  leftPane, "TOPLEFT",  8, -8)
    card:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT", -8, -8)
    card:SetHeight(62)
    card:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)   -- dull dark grey, inset look (was 0.5 — too bright)
    d.card = card
    -- Header background atlas behind the card content (inside the thin border).
    local cardBg = card:CreateTexture(nil, "BACKGROUND")
    cardBg:SetPoint("TOPLEFT", card, "TOPLEFT", 3, -3)
    cardBg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 3)
    cardBg:SetAtlas("auctionhouse-background-buy-noncommodities-header", false)
    cardBg:SetHorizTile(false); cardBg:SetVertTile(false)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", card, "LEFT", 12, 0)
    icon:Hide()
    d.icon = icon
    -- Real circular mask (TempPortraitAlphaMask is a circular mask that ships in every
    -- client — verified-present native asset, used widely for round icons).
    local mask = card:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)
    d.iconMask = mask
    -- Native circular item border ring — sized noticeably larger than the icon so it reads
    -- as a ring AROUND it (native ratio is ~1.4x), not a tight outline.
    local iconBorder = card:CreateTexture(nil, "OVERLAY")
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetSize(56, 56)
    iconBorder:SetAtlas("auctionhouse-itemicon-border-white", false)
    iconBorder:Hide()
    d.iconBorder = iconBorder

    local nameFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFS:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    nameFS:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(true)
    nameFS:SetMaxLines(2)
    d.nameFS = nameFS

    -- Stacked controls below the card. Indented further right to match native spacing.
    local ROW_LABEL_X = 24   -- label left inset within the left pane (indented)
    local VALUE_X     = 130  -- where values/inputs begin

    -- Quantity row: "Quantity" + input + Max (Max sits right of the input).
    local qtyLabel = leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qtyLabel:SetPoint("TOPLEFT", card, "BOTTOMLEFT", ROW_LABEL_X, -24)
    qtyLabel:SetText("Quantity")
    d.qtyLabel = qtyLabel

    local qtyBox = CreateFrame("EditBox", nil, leftPane, "VUIAHInputBoxTemplate")
    qtyBox:SetSize(110, 26)   -- not too wide; a couple px taller to match native proportions
    qtyBox:SetPoint("LEFT", leftPane, "LEFT", VALUE_X, 0)
    qtyBox:SetPoint("TOP", qtyLabel, "TOP", 0, 6)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetFontObject("ChatFontNormal")
    qtyBox:SetTextInsets(6, 6, 0, 0)
    qtyBox:SetJustifyH("LEFT")
    qtyBox:SetNumber(1)
    qtyBox:SetScript("OnTextChanged", function(self, userInput)
        if ui.detail.buyState == "quoted" then
            AH.Buy.CancelCommodity()
            ui.detail.buyState = "idle"
            ui.detail.buyBtn:SetText("Buy"); ui.detail.buyBtn:Enable()
        end
        -- Manual typing clears any cumulative row selection (the highlight no longer
        -- reflects the entered number). We use the NATIVE `userInput` arg (true only for
        -- real keystrokes; false for programmatic SetNumber) instead of a home-grown flag —
        -- that flag was racing, so SelectCommodityThrough's own SetNumber tripped the clear,
        -- wiping the selection + scroll-resetting via DetailRefresh. Repaint, don't rebuild.
        if userInput and ui.detail and ui.detail.selThrough ~= nil then
            ui.detail.selThrough = nil
            RepaintDetailSelection()
        end
        UpdateCommodityTotal()
    end)
    qtyBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    qtyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    d.qtyBox = qtyBox

    -- Unit Price row: "Unit Price" + MoneyDisplay.
    local unitLabel = leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unitLabel:SetPoint("TOPLEFT", qtyLabel, "BOTTOMLEFT", 0, -22)
    unitLabel:SetText("Unit Price")
    d.unitLabel = unitLabel

    local unitMoney = CreateFrame("Frame", nil, leftPane, "VUIAHPanelMoneyTemplate")
    unitMoney:SetPoint("LEFT", leftPane, "LEFT", VALUE_X, 0)
    unitMoney:SetPoint("TOP", unitLabel, "TOP", 0, 0)
    if unitMoney.SetAmount then unitMoney:SetAmount(0) end
    d.unitMoney = unitMoney

    -- Total Price row: "Total Price" + MoneyDisplay.
    local totalLabel = leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLabel:SetPoint("TOPLEFT", unitLabel, "BOTTOMLEFT", 0, -22)
    totalLabel:SetText("Total Price")
    d.totalLabel = totalLabel

    local totalMoney = CreateFrame("Frame", nil, leftPane, "VUIAHPanelMoneyTemplate")
    totalMoney:SetPoint("LEFT", leftPane, "LEFT", VALUE_X, 0)
    totalMoney:SetPoint("TOP", totalLabel, "TOP", 0, 0)
    if totalMoney.SetAmount then totalMoney:SetAmount(0) end
    d.totalMoney = totalMoney

    -- Buy button: anchored to the SAME grid as the qty box + money values (leftPane LEFT +
    -- VALUE_X) so its left edge lines up exactly — the previous totalLabel-relative offset
    -- put it on a different reference, which is why it drifted right. Width matches the box.
    local buyBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
    buyBtn:SetSize(110, 26)
    buyBtn:SetPoint("LEFT", leftPane, "LEFT", VALUE_X, 0)
    buyBtn:SetPoint("TOP", totalLabel, "BOTTOM", 0, -30)
    buyBtn:SetText("Buy")
    d.buyBtn = buyBtn

    -- Item-mode hint (shown instead of the quantity/price rows for non-commodity items).
    local itemHint = leftPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemHint:SetPoint("TOPLEFT", card, "BOTTOMLEFT", ROW_LABEL_X, -24)
    itemHint:SetPoint("RIGHT", leftPane, "RIGHT", -8, 0)
    itemHint:SetJustifyH("LEFT")
    itemHint:SetText("Select an auction from the list, then Buy.")
    d.itemHint = itemHint

    -- The Buy button: branches on commodity (two-step quote/confirm) vs item (single
    -- PlaceBid). EVERY protected call here originates from this OnClick (hardware event).
    buyBtn:SetScript("OnClick", function(self)
        local dd = ui.detail
        if not dd then return end

        if dd.isCommodity then
            if dd.buyState == "idle" then
                local qty = clamp(tonumber(dd.qtyBox:GetNumber()) or 1, 1, dd.maxQty or 1)
                dd.buyQty = qty
                dd.buyState = "quoting"
                self:Disable(); self:SetText("Requesting quote...")
                AH.Buy.StartCommodity(dd.itemID, qty, function(state, p1, p2)
                    local d2 = ui.detail
                    if not d2 then return end
                    if state == "quote" then
                        d2.buyState = "quoted"
                        self:Enable()
                        self:SetText("Confirm  " .. (AH.Money and AH.Money.Format(p2) or tostring(p2)))
                        DetailStatus("")
                    elseif state == "unavailable" then
                        d2.buyState = "idle"
                        self:Enable(); self:SetText("Buy")
                        DetailStatus("Price unavailable - try again.")
                    elseif state == "success" then
                        DetailStatus("Purchased.")
                        ResetBuyControls()
                        C_Timer.After(0.4, DetailRequery)
                    elseif state == "failed" then
                        d2.buyState = "idle"
                        self:Enable(); self:SetText("Buy")
                        DetailStatus("Purchase failed.")
                    end
                end)
            elseif dd.buyState == "quoted" then
                dd.buyState = "buying"
                self:Disable(); self:SetText("Buying...")
                AH.Buy.ConfirmCommodity()
                -- Safety: if neither success nor fail arrives, un-stick the button.
                C_Timer.After(2, function()
                    if ui.detail and ui.detail.buyState == "buying" then
                        ResetBuyControls(); DetailStatus("")
                    end
                end)
            end
        else
            -- Item path: buy the selected auction's full buyout in one protected call.
            local sel = dd.selected
            if not (sel and sel.auctionID and sel.price) then return end
            self:Disable(); self:SetText("Buying...")
            AH.Buy.BuyItem(sel.auctionID, sel.price)
            DetailStatus("Purchased.")
            C_Timer.After(0.5, DetailRequery)
        end
    end)

    --— headerless auction list (native has NO column headers; just price-left / qty-right).
    --  Plain WowScrollBoxList of Button rows, each with a left MoneyDisplay (price) + a
    --  right quantity fontstring — no TableBuilder, so there's nothing to draw headers.
    --  Scrollbar sits OUTSIDE the inset, on the chrome in the SB_GAP (native placement). —--
    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",    rightInset, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", rightInset, "BOTTOMRIGHT", 4, 2)
    scrollBar:Hide()
    d.scrollBar = scrollBar

    local scrollBox = CreateFrame("Frame", nil, rightPane, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT",     rightPane, "TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", 0, 0)
    d.scrollBox = scrollBox

    local status = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    status:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
    status:SetTextColor(0.7, 0.7, 0.7)
    status:Hide()
    d.status = status

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", function(row, index)
        -- Native banded-row visuals, using the EXACT atlases Blizzard's commodity list uses
        -- (verified via /ah rowdump): a full-width rowstripe background on every row, a hover
        -- highlight, and a gold selection overlay. No alternation — native uses rowstripe-1
        -- uniformly (confirmed: all rows reported auctionhouse-rowstripe-1).
        if not row._vuiStripe then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetAtlas("auctionhouse-rowstripe-1", false)   -- full-width row band
            row._vuiStripe = bg
        end
        if not row._vuiHl then
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetAtlas("auctionhouse-ui-row-highlight", false)   -- native hover highlight
            row._vuiHl = hl
        end
        -- Gold selection overlay (native auctionhouse-ui-row-select). Cumulative for
        -- commodities: rows 1..selThrough show it.
        if not row._vuiSel then
            local s = row:CreateTexture(nil, "OVERLAY")
            s:SetAllPoints()
            s:SetAtlas("auctionhouse-ui-row-select", false)
            s:Hide()
            row._vuiSel = s
        end
        -- Build the two columns once. Native gives PRICE the bulk of the row width (so big
        -- gold values don't clip) and pins the small QUANTITY number to the far right. Price
        -- is right-justified up to a fixed right reserve; quantity occupies that reserve.
        if not row._vuiPrice then
            local QTY_RESERVE = 76   -- right-side space reserved for the quantity (fits 6 digits)
            local price = CreateFrame("Frame", nil, row, "VUIAHRowMoneyTemplate")
            price:SetPoint("LEFT",  row, "LEFT",  6, 0)
            price:SetPoint("RIGHT", row, "RIGHT", -QTY_RESERVE, 0)   -- price spans most of the row
            price:EnableMouse(false)   -- let clicks fall through to the row Button (the
                                       -- MoneyDisplayFrame is mouse-enabled by default and
                                       -- was swallowing the first click over the price half)
            row._vuiPrice = price
            local qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            qty:SetPoint("RIGHT", row, "RIGHT", -8, 0)   -- quantity pinned far-right
            qty:SetJustifyH("RIGHT")
            row._vuiQty = qty
        end

        local data = ui.detail and ui.detail.rows and ui.detail.rows[index]
        if data then
            if row._vuiPrice.SetAmount then row._vuiPrice:SetAmount(data.unitPrice or 0) end
            row._vuiQty:SetText(data.quantity and tostring(data.quantity) or "")
        end

        row._vuiIndex = index
        PaintRowSelection(row)   -- show gold overlay if this row is in the selection
        if not row._vuiClickWired then
            row:RegisterForClicks("LeftButtonUp")
            row:SetScript("OnClick", function(self)
                local d3 = ui.detail
                if not d3 then return end
                if d3.isCommodity then
                    -- Cumulative select: clicking row N selects rows 1..N (cheapest through
                    -- N), fills the quantity with their summed quantity — native behavior.
                    SelectCommodityThrough(self._vuiIndex)
                else
                    local ent = d3.rows[self._vuiIndex]
                    if not (ent and ent.auctionID and ent.unitPrice) then return end  -- buyout only
                    d3.selIndex = self._vuiIndex
                    d3.selected = { auctionID = ent.auctionID, price = ent.unitPrice }
                    d3.buyBtn:SetText("Buy  " .. (AH.Money and AH.Money.Format(ent.unitPrice) or ent.unitPrice))
                    d3.buyBtn:Enable()
                    RepaintDetailSelection()   -- repaint selection on live rows
                end
            end)
            row._vuiClickWired = true
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    d.view = view
end

function OpenDetail(entry)
    BuildDetail()
    local d = ui.detail
    d.entry       = entry
    d.itemID      = entry.itemID or (entry.itemKey and entry.itemKey.itemID)
    d.isCommodity = nil   -- resolved when results arrive
    d.rows        = {}
    d.selIndex    = nil
    d.selThrough  = nil
    d.selected    = nil
    d.maxQty      = 1
    d.serverQty   = nil
    d.buyState    = "idle"

    -- Hide the browse RIGHT-side widgets (the left Shopping Lists panel stays visible).
    if ui.scrollBox then ui.scrollBox:Hide() end
    if ui.scrollBar then ui.scrollBar:Hide() end
    if ui.headerContainer then ui.headerContainer:Hide() end
    if ui.rightInset then ui.rightInset:Hide() end
    d.frame:Show()
    d.scrollBar:Show()

    -- Header name/icon from cached key info (may be nil until it streams in).
    local info = AH.Search.GetKeyInfo(entry.itemKey)
    if info and info.itemName and info.itemName ~= "" then
        local r, g, b = 1, 1, 1
        if info.quality and C_Item and C_Item.GetItemQualityColor then
            local cr, cg, cb = C_Item.GetItemQualityColor(info.quality)
            if cr then r, g, b = cr, cg, cb end
        end
        d.nameFS:SetText(info.itemName); d.nameFS:SetTextColor(r, g, b)
        if info.iconFileID then
            d.icon:SetTexture(info.iconFileID); d.icon:Show()
            -- Tint the native circular border ring to the item's quality color.
            d.iconBorder:SetVertexColor(r, g, b); d.iconBorder:Show()
        else
            d.icon:Hide(); d.iconBorder:Hide()
        end
    else
        d.nameFS:SetText("Loading..."); d.nameFS:SetTextColor(0.7, 0.7, 0.7)
        d.icon:Hide(); d.iconBorder:Hide()
    end

    -- Detail panes start hidden until the mode (commodity/item) is known.
    d.qtyLabel:Hide(); d.qtyBox:Hide()
    d.unitLabel:Hide(); d.unitMoney:Hide()
    d.totalLabel:Hide(); d.totalMoney:Hide(); d.itemHint:Hide()
    d.buyBtn:Disable(); d.buyBtn:SetText("Buy")

    DetailStatus("Loading...")
    DetailRefresh()
    AH.Search.QueryItem(entry, OnDetailResults)
end

function CloseDetail()
    local d = ui.detail
    if not (d and d.built) then return end
    AH.Search.CancelItemQuery()
    if AH.Buy.IsActive() then AH.Buy.CancelCommodity() end
    d.frame:Hide()
    d.scrollBar:Hide()
    if ui.scrollBox then ui.scrollBox:Show() end
    if ui.scrollBar then ui.scrollBar:Show() end
    if ui.headerContainer then ui.headerContainer:Show() end
    if ui.rightInset then ui.rightInset:Show() end
end

-- AH.Search.QueryItem callback (may fire multiple times: progressive pages + requery).
function OnDetailResults(state, data)
    local d = ui.detail
    if not (d and d.built and d.frame:IsShown()) then return end

    if state == "failed" then
        d.rows = {}; DetailRefresh(); DetailStatus("Search failed - try again.")
        return
    elseif state == "empty" then
        d.rows = {}; DetailRefresh(); DetailStatus("No auctions found.")
        return
    elseif state ~= "results" or not data then
        return
    end

    -- First results page establishes the mode + footer; later pages just extend rows.
    local firstResolve = (d.isCommodity == nil)
    d.isCommodity = data.isCommodity and true or false

    local entries = data.entries or {}
    -- Pre-format the time-left field the text cell reads (cells read named fields only).
    local total = 0
    for _, e in ipairs(entries) do
        e.timeLeftText = TimeLeftText(e.timeLeftSeconds)
        total = total + (e.quantity or 0)
    end
    d.rows   = entries
    d.maxQty = (total > 0) and total or 1
    -- Server's authoritative total quantity (may exceed the summed visible rows due to
    -- pagination/rounding). When the user selects through the LAST row ("buy all"), native
    -- fills the box with THIS, not the client row-sum — so capture it once results are full.
    if data.isFull and C_AuctionHouse and C_AuctionHouse.GetCommoditySearchResultsQuantity and d.itemID then
        local ok, q = pcall(C_AuctionHouse.GetCommoditySearchResultsQuantity, d.itemID)
        if ok and q and q > 0 then d.serverQty = q end
    end

    if d.qtyBox then
        local cur = tonumber(d.qtyBox:GetNumber()) or 1
        if cur > d.maxQty then d.qtyBox:SetNumber(d.maxQty) end
    end

    DetailStatus(#entries == 0 and (data.isFull and "No auctions found." or "Loading...") or "")
    DetailRefresh()

    if firstResolve then ResetBuyControls() end
end

----------------------------------------------------------------
--  Browse engine subscriptions (verified; unchanged from the browse view)
----------------------------------------------------------------
AH.Events.On("AH_BROWSE_START", function()
    -- A fresh search supersedes any open drill-down — return to the results list.
    if ui.detail and ui.detail.built and ui.detail.frame:IsShown() then CloseDetail() end
    ui.rows = {}; RefreshDataProvider(); SetStatus("Searching...")
end)

AH.Events.On("AH_BROWSE_UPDATE", function(results, full)
    ui.rows = results or {}; RefreshDataProvider()
    if #ui.rows == 0 then
        SetStatus(full and "No auctions found." or "Searching...")
    else
        SetStatus("")
    end
end)

AH.Events.On("AH_BROWSE_FAILED", function()
    SetStatus("Search failed — try again.")
end)

-- Shift-click an item → its name into our search box + run, only when our tab is visible.
if _G.HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        if not (ui.content and ui.content:IsVisible() and ui.searchBox) then return end
        local name = AH.Search.NormalizeSearchTerm(link)
        if not name or name == "" then return end
        ui.searchBox:SetText(name)
        if ui.DoSearch then ui.DoSearch() end
    end)
end

-- Debounced re-render as item key info streams in (resolves "..." placeholders).
local keyInfoFrame = CreateFrame("Frame")
local keyInfoTimer
keyInfoFrame:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
keyInfoFrame:SetScript("OnEvent", function()
    if not (ui.scrollBox and #ui.rows > 0) then return end
    if keyInfoTimer then keyInfoTimer:Cancel() end
    keyInfoTimer = C_Timer.NewTimer(0.2, function()
        keyInfoTimer = nil
        if ui.scrollBox and #ui.rows > 0 then RefreshDataProvider() end
    end)
end)

----------------------------------------------------------------
--  Register the tab with the injector
----------------------------------------------------------------
if AH.UI and AH.UI.AddTab then
    AH.UI.AddTab({
        key    = "shopping",
        label  = "Shopping",
        header = "Auction House",
        build  = Build,
    })
end
