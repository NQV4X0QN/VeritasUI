-- VeritasUI_AuctionHouse / UI/SellStrip.lua
-- ============================================================================
-- Architecture A: a horizontal strip of your sellable bag items, mounted in the
-- empty band at the bottom of the native Sell tab's left column (under the
-- "Create Auction" button). Click an icon -> AuctionHouseFrame:SetPostItem(loc)
-- (the native loader, PROVEN taint-clean) -> the item populates Blizzard's own
-- Sell form -> you verify -> you click Blizzard's Create Auction. We NEVER make a
-- protected call; Blizzard owns the post entirely.
--
-- VERIFIED GEOMETRY (live introspection, 12.0.5):
--   AuctionHouseFrame                 x36 y528 w800 h538
--   {Item,Commodities}SellFrame       x40 y555 w363 h442  (the left-column form)
--   PostButton "Create Auction"       commodity y643 / item y688, h22
--   MoneyFrameBorder (gold display)   x41 y534 w158 h19   (very bottom)
--   BuyoutModeCheckButton             x48 y563 (COLLIDES with our strip -> hidden)
--   => empty band under Create Auction, above the gold bar (~y555..y643).
--
-- VERIFIED PREDICATE (bag introspection): an item appears when it is UNBOUND and
-- has a vendor sell price (matched 31/31 observed sellables). A Shift-Right-click
-- blocklist (AH.db.sellBlocklist[itemID]) hides items you never want to list.
--
-- SCROLL: a fixed row of reusable item buttons + mouse-wheel paging by an offset.
-- (We deliberately do NOT use the ScrollBox horizontal view: CreateScrollBoxList-
-- HorizontalView does not exist at 12.0.5 -- it nil-errored. A manual row of small
-- icons is simpler, fully under our control, and uses only certain APIs.)
-- ============================================================================

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize
----------------------------------------------------------------
local CreateFrame      = CreateFrame
local hooksecurefunc   = hooksecurefunc
local ipairs, pairs    = ipairs, pairs
local pcall            = pcall
local next             = next
local sort             = table.sort
local max, floor       = math.max, math.floor
local C_Container      = C_Container
local C_Item           = C_Item
local GameTooltip      = GameTooltip

----------------------------------------------------------------
--  Constants (from verified geometry)
----------------------------------------------------------------
local ICON      = 37     -- standard item-button icon size
local GAP       = 4      -- horizontal gap between icons
local STEP      = ICON + GAP
local PAD_L     = 2      -- left inset inside the strip
local STRIP_W   = 330    -- slightly inset from the 342 column so the row can center
local STRIP_H   = 40     -- one icon tall
local STRIP_X   = 22     -- offset from AuctionHouseFrame LEFT (centers the row in the column)
local STRIP_Y   = 42     -- offset from AuctionHouseFrame BOTTOM (raised for even bottom cushion)
local VISIBLE   = floor((STRIP_W - PAD_L) / STEP)   -- how many icons fit

----------------------------------------------------------------
--  State
----------------------------------------------------------------
AH.SellStrip = AH.SellStrip or {}

local state = {
    built         = false,
    strip         = nil,
    card          = nil,    -- backing inset card behind the icon row
    buttons       = {},     -- pool of reusable item buttons (size VISIBLE)
    items         = {},     -- current sellable list
    offset        = 0,      -- index of first visible item (0-based)
    posted        = nil,    -- { bag, slot } currently loaded in the native sell slot, or nil
    hooked        = false,
    pending       = {},     -- itemIDs whose GetItemInfo returned nil (cache miss); cleared each CollectItems
    refreshTimer  = nil,    -- debounce handle for GET_ITEM_INFO_RECEIVED bursts
}

local Refresh, UpdateVisibility, Render, ScheduleRefresh   -- forward decls

----------------------------------------------------------------
--  Tooltip for a strip button (shared by OnEnter and by scroll-refresh).
--
--  Factored out so a scroll can re-show the tooltip for whatever button is
--  CURRENTLY under the cursor: scrolling reassigns each button's .data without
--  the mouse moving, so no OnEnter fires and a stale tooltip would otherwise
--  linger until the user moves off and back. Render() calls this for the
--  hovered button after re-laying-out the page.
----------------------------------------------------------------
local function ShowButtonTooltip(button)
    if not (button and button.data) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, button.data.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFF00FF00Click|r to load into the Sell form.", 1, 1, 1)
    GameTooltip:AddLine("|cFFFF8800Shift-Right-click|r to hide from this strip.", 1, 1, 1)
    GameTooltip:Show()
end

----------------------------------------------------------------
--  Hide the Buyout Mode checkbox (it collides with the strip; user always sells
--  in buyout mode). Uses the suite's idempotent suppress helper, which re-hides on
--  any Blizzard Show and is combat-safe. Done for both sell forms.
----------------------------------------------------------------
local function SuppressBuyoutCheckbox()
    for _, formKey in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local form = AuctionHouseFrame and AuctionHouseFrame[formKey]
        local cb = form and form.BuyoutModeCheckButton
        if cb and VUI.SuppressFrame then VUI.SuppressFrame(cb) end
    end
end

----------------------------------------------------------------
--  Sell display mode?
----------------------------------------------------------------
local function IsSellMode()
    local dm = AuctionHouseFrame and AuctionHouseFrame.displayMode
    if not dm then return false end
    local M = AuctionHouseFrameDisplayMode
    return M and (dm == M.CommoditiesSell or dm == M.ItemSell)
end

----------------------------------------------------------------
--  Collect sellable bag items (unbound + vendor price, minus blocklist).
----------------------------------------------------------------
local function CollectItems()
    local out = {}
    local block = AH.db and AH.db.sellBlocklist
    state.pending = {}   -- clear cache-miss set for this pass
    for bag = 0, 5 do  -- bags 0-5 incl. reagent bag (5): reagents ARE postable commodities.
                       -- The old "bag 5 not AH-postable" claim was an unverified guess —
                       -- probe-disproven 2026-06-20 (3 reagents in bag 5 all postable, commodity=2).
        local n = C_Container and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                -- info.isBound may be a secret value in some contexts; guard the
                -- comparison. Items that fail any guard are skipped (treated as
                -- not-sellable). Mirrors QoL ScanJunk / IsEquippableGear discipline.
                local okB, unbound = pcall(function() return not info.isBound end)
                local itemID = info.itemID
                if okB and unbound and itemID and not (block and block[itemID]) then
                    -- The vendor sell price (GetItemInfo index 11) and the
                    -- comparison against it may both touch a secret value; guard
                    -- the call and the arithmetic separately, as QoL ScanJunk does.
                    local okP, sellPrice = pcall(function()
                        return select(11, C_Item.GetItemInfo(info.hyperlink))
                    end)
                    if okP then
                        local okC, sellable = pcall(function()
                            return sellPrice and sellPrice > 0
                        end)
                        if okC and sellable then
                            -- Reject warband-bound-until-equipped equipment: effectively
                            -- account-soulbound, cannot be auctioned, yet reads
                            -- isBound=false (binds on equip) WITH a sell price, so the
                            -- unbound+price predicate alone lets it through. VERIFIED
                            -- (probe, 12.0.5, item 249677 Twinthorn Wildglaive):
                            -- IsBoundToAccountUntilEquip is the ONLY clean discriminator —
                            -- warband-until-equip gear reports bindType=2, IDENTICAL to
                            -- ordinary sellable BoE, so bindType cannot tell them apart.
                            -- Conservative: only reject on a definitive true; on pcall
                            -- error or a cold/absent result we SHOW the item (never hide a
                            -- legit sellable on doubt — at worst a warband item flashes for
                            -- one refresh, then self-corrects when its cache warms).
                            local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                            local okW, warband = pcall(function()
                                return loc and loc:IsValid()
                                    and C_Item.IsBoundToAccountUntilEquip
                                    and C_Item.IsBoundToAccountUntilEquip(loc) or false
                            end)
                            if not (okW and warband) then
                                out[#out + 1] = {
                                    bag = bag, slot = slot, link = info.hyperlink,
                                    itemID = itemID, texture = info.iconFileID,
                                    count = info.stackCount, quality = info.quality,
                                    name = info.hyperlink:match("%[(.-)%]") or "",
                                }
                            end
                        elseif okP and sellPrice == nil then
                            -- GetItemInfo returned nil — item data not yet in the
                            -- client cache. Request a fill and track the itemID so
                            -- GET_ITEM_INFO_RECEIVED can schedule a Refresh once it
                            -- lands. The item will appear on the next Refresh pass.
                            state.pending[itemID] = true
                            if C_Item.RequestLoadItemDataByID then
                                pcall(C_Item.RequestLoadItemDataByID, itemID)
                            end
                        end
                    end
                end
            end
        end
    end
    sort(out, function(a, b) return a.name < b.name end)
    return out
end

----------------------------------------------------------------
--  Wire one reusable button to an item (or hide it if data == nil)
----------------------------------------------------------------
-- MIDNIGHT reagent-quality tier atlases (verified via live-bag introspection — NOT a
-- formula; the DF/TWW "-Small"/plain names still exist in GetAtlasInfo but render OLD
-- art). Note the irregular T3 name (no "-12-" infix) — a real Midnight quirk.
local TIER_ATLAS = {
    [1] = "Professions-Icon-Quality-12-Tier1-Inv",
    [2] = "Professions-Icon-Quality-12-Tier2-Inv",
    [3] = "Professions-Icon-Quality-Tier3-Inv",
}

local function SetButton(button, data)
    if not data then button:Hide(); return end
    button.data = data
    button.icon:SetTexture(data.texture)
    -- Desaturate the icon when this exact stack (bag+slot) is the one loaded into the
    -- native sell slot — mirrors Blizzard graying the bag item. Matched by bag/slot so
    -- only the loaded stack dims, not other stacks of the same item.
    local isPosted = state.posted
        and state.posted.bag == data.bag and state.posted.slot == data.slot
    button.icon:SetDesaturated(isPosted and true or false)
    if data.count and data.count > 1 then
        button.count:SetText(data.count)
        button.count:Show()
    else
        button.count:Hide()
    end
    -- Quality border: mirror Blizzard's item-button behavior — EVERY item shows a
    -- border (verified via live region probe: native buttons carry an always-shown
    -- BORDER-layer edge on junk AND a quality overlay on colored items). We reproduce
    -- that as one vertex-colored ring. Color = BAG_ITEM_QUALITY_COLORS (the bag palette:
    -- Common = gray 0.659, Uncommon = green, Rare = blue, …; full table verified via
    -- /dump). Poor (0) has no bag-palette entry, so fall back to GetItemQualityColor(0),
    -- which is gray — matching the gray edge native draws on junk. Default missing
    -- quality to Common so a nil quality still renders the gray edge, never nothing.
    local q = data.quality or 1
    local color = BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[q]
    local r, g, b
    if color then
        r, g, b = color.r, color.g, color.b
    elseif C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(q)   -- Poor (0) → gray
    end
    if r then
        button.border:SetVertexColor(r, g, b)
        button.border:Show()
    else
        button.border:Hide()
    end
    -- Profession reagent-quality tier marker (upper-left), e.g. crafted reagents.
    -- API verified (design doc): C_TradeSkillUI.GetItemReagentQualityByItemInfo -> 1/2/3.
    -- Atlases in TIER_ATLAS (file scope) are the verified Midnight names. Guard with
    -- GetAtlasInfo so any unmapped tier renders nothing instead of erroring.
    local tierAtlas
    if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
        local ok, tier = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, data.itemID)
        if ok and tier then
            local name = TIER_ATLAS[tier]
            if name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
                tierAtlas = name
            end
        end
    end
    if tierAtlas then
        button.tier:SetAtlas(tierAtlas)
        button.tier:Show()
    else
        button.tier:Hide()
    end
    button:Show()
end

-- Built entirely from primitives. Neither ItemButtonTemplate nor the ScrollBox
-- horizontal view exist at 12.0.5 in the form we need (both nil-errored), so we use
-- only guaranteed primitives: a plain Button + icon texture + count fontstring +
-- a quality border + a hover highlight.
local function MakeButton(parent, index)
    -- Anonymous frame: these buttons are never referenced by global name (no XML
    -- template inheritance, no _G lookups), so naming them would only pollute the
    -- global namespace. `index` is still used for left-offset positioning below.
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b:SetPoint("LEFT", parent, "LEFT", PAD_L + (index - 1) * STEP, 0)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Quality border: a thin tinted square frame (Blizzard's WhiteIconFrame), matching
    -- the bag / sell-slot look. NOT UI-ActionButton-Border with ADD blend — that was the
    -- distracting action-button GLOW, which Blizzard doesn't use on bag/AH item slots.
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.border:SetPoint("TOPLEFT", 0, 0)
    b.border:SetPoint("BOTTOMRIGHT", 0, 0)
    b.border:Hide()

    -- Profession reagent-quality tier icon (the diamond/pennant marker Blizzard shows
    -- in bag slots), upper-left. 22w x 20h — the atlas isn't square; matching Blizzard's
    -- wider-than-tall aspect (a square size stretched it vertically).
    b.tier = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.tier:SetPoint("TOPLEFT", -3, 3)
    b.tier:SetSize(22, 20)
    b.tier:Hide()

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.count:Hide()

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    b:SetScript("OnEnter", function(self)
        ShowButtonTooltip(self)
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnClick", function(self, mouseButton)
        local data = self.data
        if not data then return end
        if mouseButton == "RightButton" then
            -- Shift is required to hide. A bare right-click is ignored: the
            -- strip sits over the bag/sell area where right-clicks fly often,
            -- and blocklisting the wrong item is annoying to undo. Requiring
            -- Shift makes hiding a deliberate act.
            if not IsShiftKeyDown() then return end
            if not AH.db then return end
            AH.db.sellBlocklist = AH.db.sellBlocklist or {}
            AH.db.sellBlocklist[data.itemID] = true
            VUI.Print(AH.TAG, "Hidden from the sell strip: " .. data.link
                .. "  |cFF888888(/ah blocked to manage)|r")
            Refresh()
        else
            local loc = ItemLocation:CreateFromBagAndSlot(data.bag, data.slot)
            if loc and loc:IsValid() and AuctionHouseFrame and AuctionHouseFrame.SetPostItem then
                -- Hardware-event-initiated native load; proven taint-clean.
                AuctionHouseFrame:SetPostItem(loc)
            end
        end
    end)
    return b
end

----------------------------------------------------------------
--  Render the current page (offset -> VISIBLE buttons); paging is mouse-wheel only
----------------------------------------------------------------
function Render()
    local n = #state.items
    local maxOffset = max(0, n - VISIBLE)
    if state.offset > maxOffset then state.offset = maxOffset end
    if state.offset < 0 then state.offset = 0 end

    for i = 1, VISIBLE do
        SetButton(state.buttons[i], state.items[state.offset + i])
    end

    -- After a re-layout (e.g. mouse-wheel scroll), the cursor may still be over a
    -- button whose .data just changed — but no OnEnter fired because the mouse
    -- didn't move. Re-show the tooltip for whichever visible button is currently
    -- under the cursor so it always reflects the item actually being hovered. If
    -- the cursor is over the strip but on a now-empty/hidden slot, hide the stale
    -- tooltip rather than leave it showing the old item.
    if state.strip:IsMouseOver() then
        for i = 1, VISIBLE do
            local b = state.buttons[i]
            if b:IsShown() and b:IsMouseOver() then
                ShowButtonTooltip(b)
                return
            end
        end
        GameTooltip:Hide()
    end
end

function Refresh()
    -- Gate on the AH SESSION, not visibility, so the bag warms while the strip
    -- is still hidden on the Buy tab. Render() is safe on a hidden strip: it only
    -- sets button .data and Show/Hide on children of a hidden parent (nothing
    -- draws), and the tooltip branch is false because IsMouseOver() is false on a
    -- hidden frame. This kills the on-screen reshuffle as GET_ITEM_INFO_RECEIVED
    -- resolves a cold item cache.
    if not (state.built and AH.isOpen) then return end
    state.items = CollectItems()
    Render()
end

----------------------------------------------------------------
--  Build once
----------------------------------------------------------------
local function Build()
    if state.built or not AuctionHouseFrame then return end

    local strip = CreateFrame("Frame", "VUIAHSellStrip", AuctionHouseFrame)
    strip:SetSize(STRIP_W, STRIP_H)
    strip:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", STRIP_X, STRIP_Y)
    -- The sell form has a full-size "Overlay" Button (verified: {Item,Commodities}-
    -- SellFrame.Overlay, x40 y555 w363 h442) that sits ON TOP of our strip and
    -- swallows mouse CLICKS (wheel falls through because the overlay has no wheel
    -- handler — that's why scrolling worked but clicking didn't). Raise our strip's
    -- frame level well above it so our icons receive clicks.
    strip:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 0) + 50)
    strip:EnableMouseWheel(true)
    strip:SetScript("OnMouseWheel", function(_, delta)
        state.offset = state.offset - delta   -- wheel-up = show earlier items
        Render()
    end)
    strip:Hide()

    -- Backing card: reproduce the SAME art the native sell-slot card uses. The probe
    -- showed ItemDisplay carries TWO border elements: a UI-Frame-Inner* NineSlice
    -- (the THICK, square inset — InsetFrameTemplate gives this, and it matched the
    -- outer panel walls, NOT what we want) AND a single atlas region,
    -- "auctionhouse-itemheaderframe" — the THIN, ROUNDED AH item-card art. That atlas
    -- is the look we want, so we apply it directly (no template). Parented to the strip
    -- (level 51) so it renders above the form by hierarchy; icons (later strip children)
    -- draw on top by sibling order.
    local card = CreateFrame("Frame", nil, strip)
    card:SetPoint("TOPLEFT", strip, "TOPLEFT", -7, 7)
    card:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 4, -5)
    local cardArt = card:CreateTexture(nil, "BACKGROUND")
    cardArt:SetAllPoints()
    cardArt:SetAtlas("auctionhouse-itemheaderframe")   -- native AH item-card frame art
    card:Hide()
    state.card = card

    -- Reusable button row.
    for i = 1, VISIBLE do
        state.buttons[i] = MakeButton(strip, i)
        state.buttons[i]:Hide()
    end

    state.strip = strip
    state.built = true

    SuppressBuyoutCheckbox()

    if not state.hooked then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function()
            UpdateVisibility()
        end)
        -- Track which bag/slot is loaded in the native sell slot so we can desaturate
        -- the matching strip icon (mirrors Blizzard graying the bag item). These hooks
        -- catch loads/clears from ANY source — our strip OR a native bag right-click.
        hooksecurefunc(AuctionHouseFrame, "SetPostItem", function(_, itemLocation)
            if itemLocation and itemLocation.GetBagAndSlot then
                local ok, bag, slot = pcall(itemLocation.GetBagAndSlot, itemLocation)
                if ok and bag and slot then
                    state.posted = { bag = bag, slot = slot }
                else
                    state.posted = nil
                end
            else
                state.posted = nil
            end
            Render()
        end)
        if AuctionHouseFrame.ClearPostItem then
            hooksecurefunc(AuctionHouseFrame, "ClearPostItem", function()
                state.posted = nil
                Render()
            end)
        end
        state.hooked = true
    end

    UpdateVisibility()
end

----------------------------------------------------------------
--  Visibility
----------------------------------------------------------------
function UpdateVisibility()
    if not state.built then return end
    if IsSellMode() then
        state.card:Show()
        state.strip:Show()
        SuppressBuyoutCheckbox()   -- re-assert after Blizzard rebuilds the form
        Refresh()
    else
        state.card:Hide()
        state.strip:Hide()
    end
end

----------------------------------------------------------------
--  Blocklist management (/ah blocked)
----------------------------------------------------------------
function AH.SellStrip.ListBlocked()
    local block = AH.db and AH.db.sellBlocklist
    if not block or not next(block) then
        VUI.Print(AH.TAG, "Sell-strip blocklist is empty.")
        return
    end
    VUI.Print(AH.TAG, "Sell-strip blocklist:")
    for itemID in pairs(block) do
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        VUI.Print(AH.TAG, ("  |cFFFFFF00%s|r (id %d)"):format(name or "item", itemID))
    end
    VUI.Print(AH.TAG, "  |cFF888888/ah blocked clear|r to empty the list.")
end

function AH.SellStrip.ClearBlocked()
    if AH.db then AH.db.sellBlocklist = {} end
    VUI.Print(AH.TAG, "Sell-strip blocklist cleared.")
    Refresh()
end

----------------------------------------------------------------
--  Triggers (AuctionHouseFrame is LoadOnDemand)
----------------------------------------------------------------
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

-- Debounced Refresh: GET_ITEM_INFO_RECEIVED can fire in rapid bursts (one event
-- per item as the cache fills). Collapse the burst into a single Refresh 0.1s
-- after the last event rather than re-running CollectItems on every individual fire.
function ScheduleRefresh()
    if state.refreshTimer then
        state.refreshTimer:Cancel()
    end
    state.refreshTimer = C_Timer.NewTimer(0.1, function()
        state.refreshTimer = nil
        Refresh()
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("BAG_UPDATE_DELAYED")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_AuctionHouseUI" then Build() end
    elseif event == "BAG_UPDATE_DELAYED" then
        Refresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- arg1 is the itemID whose data just landed. Only act if it was one of
        -- the items we flagged as a cache miss in the last CollectItems pass.
        local itemID = arg1
        if itemID and state.pending[itemID] then
            ScheduleRefresh()
        end
    end
end)

if IsAddOnLoaded and IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    Build()
end

if AH.Events and AH.Events.On then
    AH.Events.On("AH_OPEN", function()
        Build()
        UpdateVisibility()  -- shows + refreshes if you opened straight into Sell
        -- Warm the bag when the AH did NOT open into Sell: the strip stays hidden,
        -- so the GET_ITEM_INFO_RECEIVED burst settles off-screen (v1.7.15). Guarded
        -- because UpdateVisibility ALREADY refreshes in Sell mode -- unconditional,
        -- this ran a full six-bag CollectItems pass twice per Sell-mode open (three
        -- times on the session's first). Do NOT move this into UpdateVisibility's
        -- else branch: that function is also the SetDisplayMode hook, so it would
        -- scan on every tab switch away from Sell, which currently costs nothing.
        if not IsSellMode() then Refresh() end
    end)
end
