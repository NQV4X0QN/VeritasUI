-- VeritasUI_AuctionHouse / UI/FilterFlyout.lua
-- Phase 4 Layer 4: the Shopping tab's "Filter" control — a clean-room reproduction of
-- Blizzard's native Buy-tab Filter button + filter flyout, extended with our own
-- additional filters, all in ONE flyout (the user's requirement: no tab-hopping).
--
-- ── VERIFIED NATIVE COMPOSITION (live-client introspection, 2026-06-10) ──────────────
--   Button (AuctionHouseFrame.SearchBar.FilterButton): a plain Button, ~90x18, NO
--     button-API textures — its look is a single BACKGROUND texture whose atlas is
--     swapped by state, plus a GameFontNormal "Filter" label (the gold ▶ chevron is
--     baked INTO the atlas art, not a separate region). Verified atlas set (all exist
--     via C_Texture.GetAtlasInfo, all 97x26):
--       normal  = common-dropdown-b-button
--       hover   = common-dropdown-b-button-hover
--       pressed = common-dropdown-b-button-pressed
--       open    = common-dropdown-b-button-open      (shown while the flyout is open)
--       disabled= common-dropdown-b-button-disabled
--     Scripts wired natively: OnEnter/OnLeave/OnMouseDown/OnMouseUp (no OnClick — it
--     drives off mouse up/down). NO GetHighlightTexture (hover IS an atlas swap).
--   Flyout panel: background atlas `common-dropdown-bg` (ARTWORK), FULLSCREEN_DIALOG
--     strata. Section headers + checkbox labels = GameFontHighlight; the level-range
--     separator "-" = GameFontHighlightSmall. Checkboxes are TEXTURE-built (not
--     CheckButton objects in native): box = `common-dropdown-ticksquare`, check =
--     `common-dropdown-icon-checkmark-yellow`. Edit boxes (28x16) use the 3-slice
--     `common-search-border-left/middle/right`.
--
-- ── VERIFIED FILTER VOCABULARY (Enum.AuctionHouseFilter, 14 members) ──────────────────
--   None=0  UncollectedOnly=1  UsableOnly=2  CurrentExpansionOnly=3  UpgradesOnly=4
--   ExactMatch=5  PoorQuality=6 .. ArtifactQuality=12  LegendaryCraftedItemOnly=13
--   → ALL of Uncollected/Usable/CurrentExpansion/Upgrades/Exact + the 7 qualities are
--     SERVER-SIDE: add them to SendBrowseQuery's `filters[]`. (Earlier plan had Exact as
--     a client filter; the enum proves it's native server-side — we use Blizzard's
--     mechanism, per suite rule #1.) Level Range → query.minLevel/maxLevel.
--   The ONLY genuinely client-side filters (no native query field — verified in the
--   filterdump pass) are ITEM LEVEL and MAX BUYOUT; both read fields already on our
--   browse rows (itemKey.itemLevel, minPrice), so no async machinery is needed.
--
-- CLEAN-ROOM: this is OUR frame, OUR texture-built controls, OUR state — we reproduce
-- the native LOOK using the verified atlases/fonts, but never reuse Blizzard's actual
-- flyout frame (which floats under UIParent and is bound to the Buy tab's protected
-- query state). Visually indistinguishable; functionally ours. No protected calls.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame = CreateFrame
local ipairs      = ipairs
local tonumber    = tonumber
local format      = string.format

----------------------------------------------------------------
--  Module table + filter state
----------------------------------------------------------------
AH.Filter = {}
local F = AH.Filter

local E = (Enum and Enum.AuctionHouseFilter) or {}

-- Live filter state. Defaults mirror the native flyout: all rarities ON, every toggle
-- OFF, level/ilvl/buyout empty. Session-volatile (the native flyout doesn't persist
-- across reloads either); persisting is a possible later refinement.
local state = {
    minLevel = nil, maxLevel = nil,             -- server: required (player) level range
    toggles  = {                                 -- server: Enum.AuctionHouseFilter members
        uncollected = false, usable = false,
        currentExpansion = false, upgrades = false,
        exact = false,
    },
    rarity   = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true }, -- server: by qualityID
    -- client-side post-filters (no native query field):
    minILvl  = nil, maxILvl = nil,               -- item level range
    maxBuyoutCopper = nil,                        -- max unit/buyout price (copper)
}

-- Quality id (0..6) -> Enum.AuctionHouseFilter quality member.
local QUALITY_FILTER = {
    [0] = E.PoorQuality, [1] = E.CommonQuality, [2] = E.UncommonQuality,
    [3] = E.RareQuality, [4] = E.EpicQuality,   [5] = E.LegendaryQuality,
    [6] = E.ArtifactQuality,
}
-- Rarity rows, top→bottom, matching the native flyout order.
local RARITY_ROWS = {
    { q = 0, label = "Poor" },      { q = 1, label = "Common" },
    { q = 2, label = "Uncommon" },  { q = 3, label = "Rare" },
    { q = 4, label = "Epic" },      { q = 5, label = "Legendary" },
    { q = 6, label = "Artifact" },
}

----------------------------------------------------------------
--  Public API consumed by ShoppingTab / Search
----------------------------------------------------------------
-- Build the AuctionHouseBrowseQuery option set from the SERVER-side filter state.
-- Returns { filters = { Enum.AuctionHouseFilter.* }, minLevel?, maxLevel? } — shaped
-- exactly as AH.Search.Browse(term, opts) already threads into SendBrowseQuery.
function F.GetServerOpts()
    local filters = {}
    local t = state.toggles
    if t.uncollected      and E.UncollectedOnly      then filters[#filters+1] = E.UncollectedOnly end
    if t.usable           and E.UsableOnly           then filters[#filters+1] = E.UsableOnly end
    if t.currentExpansion and E.CurrentExpansionOnly then filters[#filters+1] = E.CurrentExpansionOnly end
    if t.upgrades         and E.UpgradesOnly         then filters[#filters+1] = E.UpgradesOnly end
    if t.exact            and E.ExactMatch           then filters[#filters+1] = E.ExactMatch end

    -- Rarity: if every quality is checked (the default), send NO quality filters — an
    -- empty/quality-free `filters` already means "all qualities", so we avoid a 7-element
    -- array on the common path. Only when a SUBSET is checked do we restrict to those.
    local allChecked = true
    for q = 0, 6 do if not state.rarity[q] then allChecked = false; break end end
    if not allChecked then
        for q = 0, 6 do
            if state.rarity[q] and QUALITY_FILTER[q] then
                filters[#filters+1] = QUALITY_FILTER[q]
            end
        end
    end

    local opts = { filters = filters }
    if state.minLevel then opts.minLevel = state.minLevel end
    if state.maxLevel then opts.maxLevel = state.maxLevel end
    return opts
end

-- Apply the CLIENT-side post-filters (item level + max buyout) to a list of adapted
-- browse rows. Returns a NEW filtered array; returns the input unchanged when no client
-- filter is active (cheap common path). Item-level filtering skips rows with no real
-- item level (commodities key itemLevel 0) so they pass — matching the reference
-- (Auctionator) behavior; documented so a future pass doesn't "fix" it into dropping
-- commodities. Max-buyout compares the row's lowest price (minPrice, copper); rows with
-- no buyout (minPrice 0, bid-only) pass.
function F.ApplyClient(rows)
    if type(rows) ~= "table" then return {} end
    local minI, maxI, maxB = state.minILvl, state.maxILvl, state.maxBuyoutCopper
    if not (minI or maxI or maxB) then return rows end

    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        local keep = true

        local il = (r.itemKey and r.itemKey.itemLevel) or 0
        if il and il > 0 then
            if minI and il < minI then keep = false end
            if keep and maxI and il > maxI then keep = false end
        end

        if keep and maxB then
            local p = r.minPrice or 0
            if p > 0 and p > maxB then keep = false end
        end

        if keep then out[#out+1] = r end
    end
    return out
end

local clientChangeHandler
function F.SetClientChangeHandler(fn) clientChangeHandler = fn end
local function NotifyClientChange()
    if clientChangeHandler then pcall(clientChangeHandler) end
end

-- ShoppingTab also registers a SERVER-change handler: changing a server-side control
-- (level range / rarity / toggles) re-runs the current search with the new GetServerOpts,
-- so the flyout behaves dynamically like Blizzard's (no manual re-Search needed). The
-- handler debounces on its side; here we just fire the signal.
local serverChangeHandler
function F.SetServerChangeHandler(fn) serverChangeHandler = fn end
local function NotifyServerChange()
    if serverChangeHandler then pcall(serverChangeHandler) end
end

----------------------------------------------------------------
--  Native-faithful widget builders (texture-built from verified atlases)
----------------------------------------------------------------
-- A checkbox matching the native flyout: box = common-dropdown-ticksquare, check =
-- common-dropdown-icon-checkmark-yellow, GameFontHighlight label (optionally tinted to a
-- quality color). onToggle(checked) fires on click. Returns the CheckButton.
local CHECK_SIZE = 20

local function CreateCheck(parent, text, r, g, b, onToggle)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(CHECK_SIZE, CHECK_SIZE)

    local box = cb:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints()
    box:SetAtlas("common-dropdown-ticksquare", false)
    cb:SetNormalTexture(box)

    local check = cb:CreateTexture(nil, "ARTWORK")
    check:SetPoint("CENTER")
    check:SetAtlas("common-dropdown-icon-checkmark-yellow", true)
    cb:SetCheckedTexture(check)

    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)
    cb:SetHighlightTexture(hl)

    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(text)
    if r then label:SetTextColor(r, g, b) end
    cb.Label = label

    cb:SetScript("OnClick", function(self)
        if onToggle then onToggle(self:GetChecked() and true or false) end
    end)
    return cb
end

-- A small numeric edit box wearing the native 3-slice search border
-- (common-search-border-left/middle/right). `digits` caps input length. onCommit(num)
-- fires on Enter or focus-loss with the parsed number (nil if blank). Returns the EditBox.
local EDIT_H = 18

local function CreateNumBox(parent, width, digits, onCommit)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, EDIT_H)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontSmall")
    eb:SetJustifyH("CENTER")
    eb:SetNumeric(true)
    eb:SetMaxLetters(digits or 4)
    eb:SetTextInsets(3, 3, 0, 0)

    -- 3-slice border (drawn just outside the text area). Left/right caps at atlas width,
    -- middle stretched between. Heights set to the box so the border hugs the field.
    local cap = 8   -- approximate cap width; tuned in-game against the native field
    local left = eb:CreateTexture(nil, "BACKGROUND")
    left:SetAtlas("common-search-border-left", false)
    left:SetPoint("TOPLEFT", eb, "TOPLEFT", -cap, 2)
    left:SetPoint("BOTTOMLEFT", eb, "BOTTOMLEFT", -cap, -2)
    left:SetWidth(cap)

    local right = eb:CreateTexture(nil, "BACKGROUND")
    right:SetAtlas("common-search-border-right", false)
    right:SetPoint("TOPRIGHT", eb, "TOPRIGHT", cap, 2)
    right:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", cap, -2)
    right:SetWidth(cap)

    local mid = eb:CreateTexture(nil, "BACKGROUND")
    mid:SetAtlas("common-search-border-middle", false)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)

    local function commit(self)
        local txt = self:GetText()
        local n = tonumber(txt)
        if txt == "" then n = nil end
        if onCommit then onCommit(n) end
    end
    eb:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

----------------------------------------------------------------
--  The flyout panel (built lazily, anchored under the Filter button)
----------------------------------------------------------------
local FLYOUT_W   = 212
local PAD_L      = 16     -- content left inset
local ROW_GAP    = 6
local SECTION_GAP = 10

local flyout       -- the panel frame (created on first toggle)
local filterButton -- the Filter button (created by CreateButton)

-- Forward decl: update the button's background atlas from its current state.
local UpdateButtonVisual

local function BuildFlyout(anchorButton)
    if flyout then return flyout end

    local f = CreateFrame("Frame", nil, anchorButton)
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- native flyout strata; floats above results
    f:SetToplevel(true)
    f:SetWidth(FLYOUT_W)
    f:Hide()
    -- Anchor below the Filter button, left edges aligned (native flyout drops from the
    -- button). y -2 tucks it just under the button's bottom border.
    f:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -2)

    -- Panel background: the verified native dropdown panel atlas. SetAllPoints so the
    -- bordered art frames the whole flyout (the atlas includes its own border).
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("common-dropdown-bg", false)

    -- Layout cursor (y grows downward as negative offsets from the top inset).
    local y = -14
    local function Header(text)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L - 2, y)
        h:SetText(text)
        y = y - (select(2, h:GetFont()) or 12) - 4
        return h
    end
    local function Check(text, r, g, b, onToggle, initial)
        local cb = CreateCheck(f, text, r, g, b, onToggle)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, y)
        cb:SetChecked(initial and true or false)
        y = y - CHECK_SIZE - 2
        return cb
    end
    local function Gap(n) y = y - (n or SECTION_GAP) end

    --======================== LEVEL RANGE (server: minLevel/maxLevel) ========================--
    Header("Level Range")
    do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, y)
        row:SetSize(FLYOUT_W - PAD_L * 2, EDIT_H + 4)

        local minBox = CreateNumBox(row, 36, 4, function(n) state.minLevel = n; NotifyServerChange() end)
        minBox:SetPoint("LEFT", row, "LEFT", 8, 0)

        local dash = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dash:SetPoint("LEFT", minBox, "RIGHT", 8, 0)
        dash:SetText("-")

        local maxBox = CreateNumBox(row, 36, 4, function(n) state.maxLevel = n; NotifyServerChange() end)
        maxBox:SetPoint("LEFT", dash, "RIGHT", 8, 0)

        f.minLevelBox, f.maxLevelBox = minBox, maxBox
        y = y - (EDIT_H + 6)
    end
    Gap()

    --======================== NATIVE TOGGLES (server: filter members) ========================--
    f.checkUncollected = Check("Uncollected Only", nil, nil, nil,
        function(c) state.toggles.uncollected = c; NotifyServerChange() end, state.toggles.uncollected)
    f.checkUsable = Check("Usable Only", nil, nil, nil,
        function(c) state.toggles.usable = c; NotifyServerChange() end, state.toggles.usable)
    f.checkCurrentExp = Check("Current Expansion Only", nil, nil, nil,
        function(c) state.toggles.currentExpansion = c; NotifyServerChange() end, state.toggles.currentExpansion)
    Gap()

    --======================== EQUIPMENT (server) ========================--
    Header("Equipment")
    f.checkUpgrades = Check("Upgrades Only", nil, nil, nil,
        function(c) state.toggles.upgrades = c; NotifyServerChange() end, state.toggles.upgrades)
    Gap()

    --======================== RARITY (server: quality members) ========================--
    Header("Rarity")
    f.rarityChecks = {}
    for _, spec in ipairs(RARITY_ROWS) do
        local r, g, b = 1, 1, 1
        if C_Item and C_Item.GetItemQualityColor then
            local cr, cg, cb = C_Item.GetItemQualityColor(spec.q)
            if cr then r, g, b = cr, cg, cb end
        end
        local q = spec.q
        f.rarityChecks[q] = Check(spec.label, r, g, b,
            function(c) state.rarity[q] = c; NotifyServerChange() end, state.rarity[q])
    end
    Gap()

    --======================== OUR ADDITIONS (client-side post-filters) ========================--
    Header("More Filters")
    do
        -- Item Level range (client: itemKey.itemLevel).
        local ilLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ilLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, y - 2)
        ilLabel:SetText("Item Level")
        y = y - 18

        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, y)
        row:SetSize(FLYOUT_W - PAD_L * 2, EDIT_H + 4)

        local minBox = CreateNumBox(row, 44, 4, function(n) state.minILvl = n; NotifyClientChange() end)
        minBox:SetPoint("LEFT", row, "LEFT", 8, 0)

        local dash = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dash:SetPoint("LEFT", minBox, "RIGHT", 8, 0)
        dash:SetText("-")

        local maxBox = CreateNumBox(row, 44, 4, function(n) state.maxILvl = n; NotifyClientChange() end)
        maxBox:SetPoint("LEFT", dash, "RIGHT", 8, 0)

        f.minILvlBox, f.maxILvlBox = minBox, maxBox
        y = y - (EDIT_H + 8)
    end
    do
        -- Max Buyout (client: minPrice). Entered in whole gold; stored as copper.
        local mbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        mbLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, y - 2)
        mbLabel:SetText("Max Buyout")
        y = y - 18

        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, y)
        row:SetSize(FLYOUT_W - PAD_L * 2, EDIT_H + 4)

        local goldBox = CreateNumBox(row, 80, 9, function(n)
            state.maxBuyoutCopper = n and (n * 10000) or nil   -- gold → copper
            NotifyClientChange()
        end)
        goldBox:SetPoint("LEFT", row, "LEFT", 8, 0)

        local gLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gLabel:SetPoint("LEFT", goldBox, "RIGHT", 10, 0)
        gLabel:SetText("|cFFFFD700g|r")

        f.maxBuyoutBox = goldBox
        y = y - (EDIT_H + 8)
    end

    -- Finalize panel height from the layout cursor (+ bottom inset).
    f:SetHeight(-y + 14)

    -- Outside-click-to-close (native flyout behavior). Modern Blizzard menus auto-close on
    -- the GLOBAL_MOUSE_DOWN event: it fires for EVERY mouse-down anywhere and does NOT
    -- intercept the click, so the user's click still lands on whatever they clicked AND the
    -- flyout dismisses — exactly the native feel. While shown, we listen; on a down that is
    -- NOT over the flyout (or its children, which sit within its rect) and NOT over the
    -- Filter button itself (so clicking the button still toggles cleanly rather than
    -- double-acting), we close. We register on show / unregister on hide so it costs nothing
    -- while closed.
    f:SetScript("OnEvent", function(self, event)
        if event ~= "GLOBAL_MOUSE_DOWN" then return end
        if self:IsMouseOver() then return end
        if filterButton and filterButton:IsMouseOver() then return end  -- button OnClick handles toggle
        F.Close()
    end)
    f:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)

    flyout = f
    return f
end

----------------------------------------------------------------
--  The Filter button (reskinned native dropdown button)
----------------------------------------------------------------
local BTN_ATLAS = {
    normal   = "common-dropdown-b-button",
    hover    = "common-dropdown-b-button-hover",
    pressed  = "common-dropdown-b-button-pressed",
    open     = "common-dropdown-b-button-open",
    disabled = "common-dropdown-b-button-disabled",
}

UpdateButtonVisual = function()
    local b = filterButton
    if not (b and b._bg) then return end
    local open = flyout and flyout:IsShown()
    local atlas
    if not b:IsEnabled() then
        atlas = BTN_ATLAS.disabled
    elseif b._over and b._down then
        atlas = BTN_ATLAS.pressed        -- active press always wins
    elseif b._over then
        atlas = BTN_ATLAS.hover          -- HOVER wins over open: hovering must always
                                         -- highlight, even while the flyout is showing
                                         -- (no verified -open-hover atlas exists, so the
                                         -- plain hover art is the honest choice).
    elseif open then
        atlas = BTN_ATLAS.open           -- showing-but-not-hovered → the open/pressed look
    else
        atlas = BTN_ATLAS.normal
    end
    b._bg:SetAtlas(atlas, false)
end

function F.IsShown() return flyout and flyout:IsShown() or false end

function F.Close()
    if flyout and flyout:IsShown() then
        flyout:Hide()
        UpdateButtonVisual()
    end
end

function F.Toggle(anchorButton)
    local f = BuildFlyout(anchorButton)
    if f:IsShown() then f:Hide() else f:Show() end
    UpdateButtonVisual()
end

-- Build the Filter button. `parent` is the search-strip content frame. Returns the
-- button so the caller can anchor it where the old "Search Options" button sat.
function F.CreateButton(parent)
    local b = CreateFrame("Button", nil, parent)
    -- FRAME height = 22 so it sits on the SAME grid as the 22h UIPanelButtonTemplate siblings
    -- (Search / Add To List) when chained by LEFT→RIGHT. The visible pill height is set just
    -- below via the background TEXTURE (decoupled from the frame), so matching the siblings'
    -- visible height never moves the frame off the grid.
    b:SetSize(96, 22)
    local VISIBLE_H = 28   -- visible pill height — KEEP at 28 (the height that looked right).
    -- The art is NOT vertically centered within its atlas (more transparent padding on one
    -- side), so a texture centered on the grid renders the visible pill HIGH. We offset the
    -- TEXTURE down by TEX_Y so the visible art lands on the baseline — WITHOUT moving the
    -- frame (frame stays 22h on the grid, so no staircase). TEX_Y is the only knob for
    -- vertical position now; tune ±1 if the pill isn't perfectly level.
    local TEX_Y = -1

    -- Single background texture, atlas swapped by state (the native technique — the gold
    -- "Filter ▶" art, chevron included, lives in the atlas itself). Sized to VISIBLE_H and
    -- centered-then-nudged so the VISIBLE art (not the padded texture) sits on the grid.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("CENTER", b, "CENTER", 0, TEX_Y)
    bg:SetSize(96, VISIBLE_H)
    bg:SetAtlas(BTN_ATLAS.normal, false)
    b._bg = bg

    -- GameFontNormal label (the gold "Filter" text), matching native.
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", b, "CENTER", -4, 0)   -- nudged left so it clears the baked ▶
    label:SetText(FILTER or "Filter")
    b._label = label

    b._over, b._down = false, false
    b:SetScript("OnEnter", function(self) self._over = true; UpdateButtonVisual() end)
    b:SetScript("OnLeave", function(self) self._over = false; UpdateButtonVisual() end)
    b:SetScript("OnMouseDown", function(self) self._down = true; UpdateButtonVisual() end)
    b:SetScript("OnMouseUp",   function(self) self._down = false; UpdateButtonVisual() end)
    b:SetScript("OnClick", function(self) F.Toggle(self) end)

    filterButton = b
    return b
end

-- Close the flyout when the AH closes (the Shopping tab's content is torn down/hidden).
AH.Events.On("AH_CLOSED", function() F.Close() end)
