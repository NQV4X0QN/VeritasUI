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
    leftMode  = "lists",   -- "lists" | "recent" (sub-tab selection)
}

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

local function RefreshDataProvider()
    if not ui.scrollBox then return end
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
        -- TableBuilder populates the cells; we only add a hover highlight once.
        if not row._vuiHl then
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            row._vuiHl = hl
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

    local function AddColumn(headerText, width, cellTemplate, cellParam)
        local col = tb:AddColumn()
        -- AuctionHouseTableHeaderStringMixin:Init(owner, headerText, sortOrder).
        -- owner is a table; if it lacks RegisterHeader AND sortOrder is nil, the header
        -- is non-interactive (no sort yet — Layer 3+). We pass a bare owner + the text +
        -- nil sortOrder, which is exactly the "static label" case.
        col:ConstructHeader("BUTTON", "AuctionHouseTableHeaderStringTemplate", {}, headerText, nil)
        col:ConstructCells("FRAME", cellTemplate, cellParam)
        col:SetCellPadding(4, 4)
        if width then col:SetFixedConstraints(width, 0) else col:SetFillConstraints(1.0, 0) end
        return col
    end
    -- Price (fixed) · Name (fills the rest) · Available (fixed). Matches Auctionator and
    -- native Buy exactly — no "Scanned" column (it duplicated the live Price and deviated
    -- from native; the scanned/DB market price lives in item TOOLTIPS, its proper home).
    AddColumn("Price",     COL_PRICE_W, "VUIAHMoneyCellTemplate", "minPrice")
    AddColumn("Name",      nil,         "VUIAHItemCellTemplate")
    AddColumn("Available", COL_AVAIL_W, "VUIAHTextCellTemplate",  "totalQuantity")

    -- Arrange once after layout settles so the column headers render immediately when
    -- the tab is first shown (before any search). Deferred a frame so the header
    -- container's anchored width is resolved.
    C_Timer.After(0, function() EnsureArranged() end)

    UpdateLeftMode()   -- seed left-panel sub-tab state + placeholder text
end

----------------------------------------------------------------
--  Browse engine subscriptions (verified; unchanged from the browse view)
----------------------------------------------------------------
AH.Events.On("AH_BROWSE_START", function()
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
