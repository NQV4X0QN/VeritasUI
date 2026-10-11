-- VeritasUI_AuctionHouse / UI/SellStrip.lua
-- ============================================================================
-- Architecture A: a horizontal strip of your sellable bag items, mounted in the
-- empty band at the bottom of the native Sell tab's left column (under the
-- "Create Auction" button). Two real presses on one icon, both handled by Blizzard:
-- right-click is forwarded to that item's own bag button, whose handler loads the
-- Sell form; left-click on the loaded stack is forwarded to Create Auction. The strip
-- itself never loads or posts anything (see "Secure click wiring" below).
--
-- ⚠ CORRECTED v1.17.8. This header used to say the strip called
-- AuctionHouseFrame:SetPostItem(loc), "the native loader, PROVEN taint-clean". That call
-- WAS the cause of the v1.17.4 UseContainerItem FORBIDDEN, and "proven taint-clean" was a
-- narrow measurement written up as a guarantee -- it steered three audits away from this
-- file. The strip has not called SetPostItem since v1.17.4. Never write "proven" about
-- taint without naming exactly what was measured.
--
-- VERIFIED GEOMETRY (live introspection, 12.0.5):
--   AuctionHouseFrame                 x36 y528 w800 h538
--   {Item,Commodities}SellFrame       x40 y555 w363 h442  (the left-column form)
--   PostButton "Create Auction"       commodity y643 / item y688, h22
--   MoneyFrameBorder (gold display)   x41 y534 w158 h19   (very bottom)
--   BuyoutModeCheckButton             x48 y563 (COLLIDES with our strip -> hidden)
--   => empty band under Create Auction, above the gold bar (~y555..y643).
--
-- PREDICATE (v1.14.16): C_AuctionHouse.IsSellItemValid(loc, false) — the SAME
-- check SetPostItem itself gates on, so the strip shows exactly what the native
-- loader will accept (see the CollectItems block comment). A Shift-Left-click
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
    -- Only promise the load when it can happen: it forwards to the item's button in Blizzard's
    -- bag window, which exists only while that bag is open (see WireSecureClicks).
    if button.canLoad then
        GameTooltip:AddLine("|cFF00FF00Right-click|r to load into the Sell form.", 1, 1, 1)
    else
        GameTooltip:AddLine("|cFFFF8800Open your bags|r to load this item.", 1, 1, 1)
    end
    GameTooltip:AddLine("|cFFFF8800Shift-Left-click|r to hide from this strip.", 1, 1, 1)
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
--  Pin the Quantity row visible on both sell forms (v1.14.20).
--
--  WHY: Blizzard hides that row whenever you can only post one of the item, at
--  Blizzard_AuctionHouseSellFrame.lua:396-397 inside AuctionHouseSellFrameMixin
--  :SetItem (verified against wow-ui-source live 2026-08-24):
--      local showQuantity = self:GetMaxQuantity() > 1;
--      self.QuantityInput:SetShown(showQuantity);
--  The sell form is a VerticalLayoutFrame (Blizzard_AuctionHouseSellFrame.xml:163)
--  and QuantityInput carries layoutIndex 20 (xml:229-231); LayoutFrame.lua:38
--  excludes any child that is not :IsShown() from the layout, so EVERY row below it
--  -- Unit Price 30, Duration 40, Deposit 50, Total Price 60, Create Auction 70 --
--  slides up one row height. Clicking a 1-count vs a 2+-count icon in the strip
--  therefore moves the Create Auction button, which defeats click muscle memory.
--
--  Line 397 is the ONLY place in the entire AH source that changes this row's
--  visibility (grep of every QuantityInput reference across
--  Blizzard_AuctionHouse*.lua/xml), and the forms are driven through instance
--  dispatch -- self.CommoditiesSellFrame:SetItem(loc) / self.ItemSellFrame:SetItem
--  (Blizzard_AuctionHouseFrame.lua:625,629), including the SetItem(nil) clears at
--  :634-637 -- so a post-hook on each form's SetItem catches every load and clear.
--
--  After re-showing we re-run three things SetItem already did while the row was
--  still hidden, so we inherit Blizzard's logic instead of re-deriving it:
--    MarkDirty()          -- re-request a layout pass (LayoutFrame.lua:84); the
--        pass is deferred to OnUpdate and GetLayoutChildren() is recomputed then
--        (LayoutFrame.lua:78-81,254), so a child shown after SetItem's own
--        MarkDirty at :404 is still picked up. Needed for the non-SetItem calls.
--    UpdateFocusTabbing() -- reads QuantityInput:IsShown() to wire Tab order
--        (sellframe:357, item-form override itemsellframe:419-422). SetItem runs it
--        at :406, i.e. while hidden, so Tab would skip the now-visible box.
--    UpdatePostState()    -- recomputes MaxButton:SetEnabled(quantity < max)
--        (sellframe:344); on the commodities path the quantity is set AFTER that
--        call (commoditiessellframe:173), so "Max" can be left enabled at 1 of 1.
--  Plus InputBox:SetCursorPosition(0) -- Blizzard's own documented hack for text
--  set on an edit box that is shown in the same frame (sellframe:399-402,
--  commoditiessellframe:176-179). We move the show into that same frame, so the
--  condition their comment describes applies to us and the "1" could render
--  scrolled out of view without it.
--
--  Applied to BOTH forms so the button sits at one fixed height for every sale.
--  On the gear form the row reads 1 with "Max" greyed, since equipment max is 1.
--
--  Not combat-gated: QuantityInput is a plain Frame (xml:229) and Blizzard itself
--  calls SetShown on it from SetItem during combat. Over-max typing stays clamped
--  by Blizzard's own input callback (sellframe:289-292), so an always-editable box
--  cannot post more than you own.
----------------------------------------------------------------
-- Which sell forms we have already hooked. ⚠ Deliberately a MODULE-LOCAL table keyed by the
-- form, NOT a `form._vuiQuantityPinned` field on Blizzard's frame (which is what v1.14.20
-- shipped). Writing our own bookkeeping onto a Blizzard frame is a taint write on a frame
-- whose SetItem -> CanPostItem path reaches `C_AuctionHouse.PostCommodity`, and this module's
-- landmines record a historical crash INSIDE Blizzard's commodity-post code on the native
-- Create Auction click. Nothing reads this but us, so it does not belong on their frame.
-- (Contrast VeritasUI_QualityOfLife/Journeys.lua, where `card.WatchedFactionToggleFrame` MUST
-- be set on Blizzard's frame because Blizzard's own inherited OnEnter reads that exact field.)
local quantityPinnedForms = {}

local function PinQuantityRow()
    for _, formKey in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local form = AuctionHouseFrame and AuctionHouseFrame[formKey]
        if form and form.QuantityInput then
            local function pin()
                local q = form.QuantityInput
                -- Re-read each call, so re-check it: a nil here would otherwise throw from
                -- inside a hooksecurefunc post-hook on every sell-form load.
                if not q then return end
                -- Already visible (2+ available): Blizzard ran the updates below
                -- itself with the correct state, so there is nothing to correct.
                if q:IsShown() then return end
                q:Show()
                if form.MarkDirty then form:MarkDirty() end
                pcall(form.UpdateFocusTabbing, form)
                pcall(form.UpdatePostState, form)
                if q.InputBox then
                    pcall(q.InputBox.SetCursorPosition, q.InputBox, 0)
                end
            end

            if not quantityPinnedForms[form] then
                quantityPinnedForms[form] = true
                hooksecurefunc(form, "SetItem", pin)
            end

            pin()   -- the form may already hold an item when we first hook
        end
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
--  The native "Create Auction" button for whichever sell frame is live.
--
--  Blizzard keeps a separate sell frame per commodity status and each owns its
--  own PostButton (Blizzard_AuctionHouseSellFrame.xml:259, parentKey="PostButton",
--  inherits UIPanelButtonTemplate). SetPostItem picks the frame by
--  C_AuctionHouse.GetItemCommodityStatus (Blizzard_AuctionHouseFrame.lua:620-630),
--  so displayMode is the authoritative read-back of which one is showing.
--
--  Returned to be handed to a SecureActionButton as "clickbutton" — we forward a
--  real left-click to it rather than calling PostItem ourselves. Blizzard's own
--  OnClick (Blizzard_AuctionHouseSellFrame.lua:206) then runs in SECURE execution.
----------------------------------------------------------------
local function GetActivePostButton()
    if not (AuctionHouseFrame and IsSellMode()) then return nil end
    local M = AuctionHouseFrameDisplayMode
    local frame
    if M and AuctionHouseFrame.displayMode == M.CommoditiesSell then
        frame = AuctionHouseFrame.CommoditiesSellFrame
    else
        frame = AuctionHouseFrame.ItemSellFrame
    end
    -- Never substitute a disabled button: UpdatePostButtonState disables it when the
    -- item isn't postable (Blizzard_AuctionHouseSellFrame.lua:465-468), and Click()
    -- on a disabled button is a no-op — which is exactly what a player clicking it
    -- themselves would get. Returning it anyway keeps our behaviour identical.
    return frame and frame.PostButton or nil
end

----------------------------------------------------------------
--  Collect sellable bag items (minus blocklist).
--
--  PREDICATE (v1.14.16): C_AuctionHouse.IsSellItemValid(loc, false) — the SAME
--  check AuctionHouseFrameMixin:SetPostItem gates on before loading the sell form
--  (Blizzard_AuctionHouseFrame.lua, verified against wow-ui-source live
--  2026-08-23), so the strip shows exactly the set of items the native loader
--  will accept when clicked. The original heuristic (unbound + vendor price > 0,
--  "matched 31/31 observed sellables") was measurement-complete for the bags it
--  was built against but WRONG as a definition: auctionable items with NO vendor
--  value (caged pets, various BoEs/reagents) read sellPrice 0/nil and were
--  silently hidden — the owner-reported gap that motivated this change.
--  ⚠ displayError=false is REQUIRED: the parameter DEFAULTS TO TRUE, which would
--  pop a UI error for every non-sellable slot on every refresh pass.
--
--  The unbound pre-filter stays: nothing bound is ever auctionable, it skips the
--  ItemLocation + API call for most of the bag, and isBound may be secret in
--  some contexts (guarded, skip-on-doubt, as before). The vendor-price heuristic
--  remains ONLY as the fallback when IsSellItemValid is absent or errors.
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
                    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)

                    local include = false
                    local decided = false
                    if C_AuctionHouse and C_AuctionHouse.IsSellItemValid then
                        local okV, valid = pcall(function()
                            return loc and loc:IsValid()
                                and C_AuctionHouse.IsSellItemValid(loc, false) == true
                        end)
                        if okV then
                            decided = true
                            include = valid == true
                        end
                    end

                    if not decided then
                        -- FALLBACK — the pre-v1.14.16 heuristic, for when
                        -- IsSellItemValid is absent or errored. The vendor sell
                        -- price (GetItemInfo index 11) and the comparison against
                        -- it may both touch a secret value; guard the call and the
                        -- arithmetic separately, as QoL ScanJunk does.
                        local okP, sellPrice = pcall(function()
                            return select(11, C_Item.GetItemInfo(info.hyperlink))
                        end)
                        if okP then
                            local okC, sellable = pcall(function()
                                return sellPrice and sellPrice > 0
                            end)
                            include = (okC and sellable) == true
                        end
                    end

                    -- Reject warband-bound-until-equipped equipment: effectively
                    -- account-soulbound, cannot be auctioned, yet reads
                    -- isBound=false (binds on equip), so the unbound pre-filter
                    -- lets it through. VERIFIED (probe, 12.0.5, item 249677
                    -- Twinthorn Wildglaive): IsBoundToAccountUntilEquip is the
                    -- ONLY clean discriminator — warband-until-equip gear reports
                    -- bindType=2, IDENTICAL to ordinary sellable BoE. Kept as
                    -- belt-and-braces under the API predicate too: whether
                    -- IsSellItemValid rejects warband gear itself is UNMEASURED,
                    -- and this check only ever removes a definitively-unpostable
                    -- item. Conservative: only reject on a definitive true; on
                    -- pcall error or a cold/absent result we SHOW the item (never
                    -- hide a legit sellable on doubt).
                    if include then
                        local okW, warband = pcall(function()
                            return loc and loc:IsValid()
                                and C_Item.IsBoundToAccountUntilEquip
                                and C_Item.IsBoundToAccountUntilEquip(loc) or false
                        end)
                        if okW and warband then include = false end
                    end

                    if include then
                        out[#out + 1] = {
                            bag = bag, slot = slot, link = info.hyperlink,
                            itemID = itemID, texture = info.iconFileID,
                            count = info.stackCount, quality = info.quality,
                            name = info.hyperlink:match("%[(.-)%]") or "",
                        }
                    else
                        -- Excluded. If that's because the item's data is not yet
                        -- in the client cache (GetItemInfo nil), request a fill
                        -- and track the itemID so GET_ITEM_INFO_RECEIVED can
                        -- schedule a Refresh once it lands — the item then
                        -- re-evaluates on the next pass. This covers both the
                        -- fallback's nil sellPrice AND an IsSellItemValid verdict
                        -- delivered against cold data.
                        local okN, itemName = pcall(function()
                            return (C_Item.GetItemInfo(info.hyperlink))
                        end)
                        if okN and itemName == nil then
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
-- Profession-quality marker: asked of Blizzard per item, exactly as the bag buttons do.
-- SetItemCraftingQualityOverlay (Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua:323-349)
-- tries C_TradeSkillUI.GetItemReagentQualityInfo, then GetItemCraftedQualityInfo, and draws
-- `qualityInfo.iconInventory` at its native atlas size at TOPLEFT -3,2 (:300-316). Until v1.17.8
-- this file kept its own table of three atlas names found by probing (with an irregular tier-3
-- name) and asked only the reagent API, so crafted items showed no marker here while the bags
-- showed one (audit A4). We call the APIs, not SetItemCraftingQualityOverlay itself: that
-- helper registers our button on Blizzard's EventRegistry, which the strip does not need.
local function QualityMarkerAtlas(link)
    if not (C_TradeSkillUI and link) then return nil end
    for _, fn in ipairs({ C_TradeSkillUI.GetItemReagentQualityInfo,
                          C_TradeSkillUI.GetItemCraftedQualityInfo }) do
        if fn then
            local ok, info = pcall(fn, link)
            if ok and type(info) == "table" and type(info.iconInventory) == "string" then
                return info.iconInventory
            end
        end
    end
    return nil
end

----------------------------------------------------------------
--  Secure click wiring — the whole taint fix lives here.
--
--  The strip never loads or posts anything itself. Each button is a
--  SecureActionButton whose "clickbutton" delegate is retargeted per state, so a
--  real hardware press is forwarded to one of Blizzard's own widgets and Blizzard's
--  handler runs in SECURE execution:
--
--    right-click  -> that item's native bag button. Blizzard's
--                    ContainerFrameItemButton_OnClick else-branch (ContainerFrame.lua
--                    :1386-1392) calls SetPostItem itself. NOTE it must be RIGHT:
--                    :1338 LeftButton calls PickupContainerItem and would put the
--                    item on the cursor.
--    left-click   -> the live Create Auction button, and ONLY while this exact stack
--                    is the loaded one. Blizzard's OnClick posts.
--    shift+left   -> blocklist, handled insecurely in PostClick.
--
--  Why this replaces auto-advance: a post-completion event has no hardware press
--  behind it, so any load we drive from one is tainted by construction, and the
--  taint reaches BankPanel.bankType via CloseAllBags (ContainerFrame.lua:2017) and
--  blocks UseContainerItem. Two presses on one icon costs no mouse travel and
--  creates no taint at all.
--
--  shift-type1 is set to "" rather than left unset: SecureButton_GetModifiedAttribute
--  falls back from "shift-type1" to "type1" when the prefixed key is absent
--  (SecureTemplates.lua:119-131), so an unset key would make shift+left POST.
----------------------------------------------------------------
local function WireSecureClicks(button, data, isPosted)
    -- Attributes on a secure frame cannot be rewritten in combat. The auction house
    -- is unreachable in combat, so this is belt-and-braces rather than a live path.
    if InCombatLockdown() then return end

    local bagButton = data and ContainerFrameUtil_GetItemButtonAndContainer
        and ContainerFrameUtil_GetItemButtonAndContainer(data.bag, data.slot) or nil
    button:SetAttribute("type2", bagButton and "click" or nil)
    button:SetAttribute("clickbutton2", bagButton)
    -- ⚠ ContainerFrameUtil_GetItemButtonAndContainer returns a button ONLY for a bag whose
    -- window is shown (ContainerFrame.lua:2037-2046 -> GetShownFrameForID :2137-2143). With the
    -- bags closed there is nothing to forward to, so a right-click does nothing. Recorded for
    -- the tooltip, and the strip re-wires on Blizzard's bag open/close notifications (Build).
    -- A bag addon that replaces Blizzard's bag windows never shows them, so loading from the
    -- strip is unavailable there by construction; the tooltip says so rather than promising it.
    button.canLoad = bagButton ~= nil

    local postButton = isPosted and GetActivePostButton() or nil
    button:SetAttribute("type1", postButton and "click" or nil)
    button:SetAttribute("clickbutton1", postButton)
    button:SetAttribute("shift-type1", "")
end

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
    WireSecureClicks(button, data, isPosted)
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
    -- Profession-quality marker (upper-left), from Blizzard (see QualityMarkerAtlas). Guarded
    -- with GetAtlasInfo so an atlas the client does not have renders nothing instead of blank.
    local tierAtlas = QualityMarkerAtlas(data.link)
    if tierAtlas and C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(tierAtlas) then
        tierAtlas = nil
    end
    if tierAtlas then
        button.tier:SetAtlas(tierAtlas, true)   -- native size, as Blizzard's TextureKitConstants.UseAtlasSize
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
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
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

    -- Profession-quality marker, upper-left. Sized by its atlas (SetAtlas(..., true) in
    -- SetButton) and placed where Blizzard places its own: TOPLEFT -3,2 at OVERLAY 7
    -- (ItemButtonTemplate.lua:306-308). Was a fixed 22x20 at -3,3 until v1.17.8.
    b.tier = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.tier:SetPoint("TOPLEFT", -3, 2)
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

    -- PostClick, NOT OnClick: SecureActionButtonTemplate installs its own OnClick
    -- (SecureActionButton_OnClick) and replacing it would disable the secure
    -- forwarding entirely. PostClick runs insecurely AFTER the secure action, which
    -- is the correct home for our own bookkeeping.
    --
    -- Only the blocklist lives here now. Loading and posting are BOTH performed by
    -- Blizzard, via a real click forwarded to Blizzard's own widgets:
    --   right-click -> the item's native bag button  (ContainerFrame.lua:1386 loads
    --                  the sell form; this is Blizzard's own bag gesture)
    --   left-click  -> the sell frame's Create Auction button, but only while THIS
    --                  stack is the loaded one
    -- Both attributes are written in SetButton(). We no longer call SetPostItem, and
    -- we no longer post anything ourselves.
    b:SetScript("PostClick", function(self, mouseButton)
        local data = self.data
        if not data then return end
        -- Shift+Left-click hides the item. Moved off Shift+Right-click at v1.17.4
        -- because right-click is now Blizzard's load gesture and must stay unshared.
        if mouseButton ~= "LeftButton" or not IsShiftKeyDown() then return end
        if not AH.db then return end
        AH.db.sellBlocklist = AH.db.sellBlocklist or {}
        AH.db.sellBlocklist[data.itemID] = true
        VUI.Print(AH.TAG, "Hidden from the sell strip: " .. data.link
            .. "  |cFF888888(/ah blocked to manage)|r")
        Refresh()
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
    PinQuantityRow()

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

    -- Re-wire the load path whenever Blizzard opens or closes a bag window (audit A2): the
    -- right-click target only exists while its bag is shown, and before v1.17.8 nothing redrew
    -- the strip on a bag change, so closing the bags before opening the Sell tab left every
    -- right-click dead. Blizzard announces all four on EventRegistry (ContainerFrame.lua:690,
    -- 714, 1900, 1956/2024). OpenBag fires from the frame's OnShow, before its item buttons are
    -- necessarily laid out, so the re-render waits one frame; a burst (OpenAllBags opens every
    -- bag) collapses into one.
    if EventRegistry and EventRegistry.RegisterCallback then
        local pendingRewire = false
        local function OnBagsChanged()
            if pendingRewire then return end
            pendingRewire = true
            C_Timer.After(0, function()
                pendingRewire = false
                if state.built and AH.isOpen and IsSellMode() then Render() end
            end)
        end
        local owner = {}
        for _, ev in ipairs({ "ContainerFrame.OpenBag", "ContainerFrame.CloseBag",
                              "ContainerFrame.OpenAllBags", "ContainerFrame.CloseAllBags" }) do
            EventRegistry:RegisterCallback(ev, OnBagsChanged, owner)
        end
    end

    UpdateVisibility()
end

----------------------------------------------------------------
--  /ah stripdiag — why is a strip right-click dead? (owner report 2026-10-11:
--  the strip "randomly becomes unclickable" with bags open, surviving AH close/reopen)
--
--  Hover the dead icon, then run it. Short lines on purpose: the owner plays on a PC
--  and reports by screenshot. Every line separates one hypothesis:
--    under cursor   -> something is covering the strip (frame level), or not
--    canLoad/target -> no bag button found, or a STALE one (wrong bag/slot, hidden)
--    gated          -> Blizzard's secure "click" action refuses the target
--                      (HasAccessConstraints / ForbiddenAspect.ScriptedInput,
--                      SecureTemplates.lua:560-566) — nothing happens, no error
--    merchant/list  -> ContainerFrame.lua:1376-1393 routes the click elsewhere
--  Then it RE-WIRES the strip, so "does a right-click work now?" says whether the
--  wiring had gone stale. Reads only, apart from that re-wire.
----------------------------------------------------------------
function AH.SellStrip.Diag()
    local P = function(s) VUI.Print(AH.TAG, s) end
    local function yn(v) return v and "|cFF00FF00Y|r" or "|cFFFF4444N|r" end
    local function nm(f)
        if not f then return "none" end
        local ok, n = pcall(f.GetName, f)
        return (ok and n) or "<anon>"
    end
    if not state.built then P("Strip not built yet — open the auction house."); return end

    local item = AuctionHouseFrame.ItemSellFrame
    local comm = AuctionHouseFrame.CommoditiesSellFrame
    local function lvl(f) return f and f.GetFrameLevel and f:GetFrameLevel() or "-" end
    P(("strip: open=%s sell=%s shown=%s lvl=%s | overlay lvl item=%s comm=%s"):format(
        yn(AH.isOpen), yn(IsSellMode()), yn(state.strip:IsShown()), lvl(state.strip),
        lvl(item and item.Overlay), lvl(comm and comm.Overlay)))

    local focus = GetMouseFoci and GetMouseFoci()
    focus = focus and focus[1]
    local hovered, idx
    for i = 1, VISIBLE do
        if state.buttons[i] == focus then hovered, idx = focus, i end
    end
    P("under cursor: " .. (idx and ("strip icon #" .. idx) or nm(focus)))

    local b = hovered or state.buttons[1]
    local d = b and b.data
    if not d then P("no item on that icon."); return end
    P(("item: %s bag %s slot %s canLoad=%s type2=%s"):format(
        tostring(d.link), tostring(d.bag), tostring(d.slot), yn(b.canLoad),
        tostring(b:GetAttribute("type2"))))

    local t = b:GetAttribute("clickbutton2")
    if t then
        local tb = t.GetBagID and t:GetBagID()
        local ts = t.GetID and t:GetID()
        local okC, constrained = pcall(t.HasAccessConstraints, t)
        local okF, forbidden = pcall(t.HasAnyForbiddenAspects, t,
            Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptedInput)
        P(("target: %s shown=%s bag %s slot %s match=%s"):format(nm(t), yn(t:IsVisible()),
            tostring(tb), tostring(ts), yn(tb == d.bag and ts == d.slot)))
        P(("gated: constraints=%s forbidden=%s"):format(
            okC and tostring(constrained) or "?", okF and tostring(forbidden) or "?"))
    else
        P("target: none")
    end
    local now = ContainerFrameUtil_GetItemButtonAndContainer
        and ContainerFrameUtil_GetItemButtonAndContainer(d.bag, d.slot)
    P(("fresh lookup: %s same=%s | merchant=%s combat=%s"):format(nm(now), yn(now == t),
        yn(MerchantFrame and MerchantFrame:IsShown()), yn(InCombatLockdown())))

    Render()
    P("Re-wired the strip. Right-click the icon again and note whether it works now.")
end

-- TEST SEAM. Returns the REAL state table (not a copy), so a suite drives the same table
-- the module reads — the qol_ilvl_test lesson: a test that toggles a parallel copy makes
-- its own assertions unfalsifiable. Exists because Build() does live frame geometry that
-- cannot be stubbed faithfully. Same pattern as Browse.lua's _AddPrices/_Skips/_QueueLen.
-- Not used at runtime.
AH.SellStrip._State            = function() return state end

----------------------------------------------------------------
--  Visibility
----------------------------------------------------------------
function UpdateVisibility()
    if not state.built then return end
    if IsSellMode() then
        state.card:Show()
        state.strip:Show()
        SuppressBuyoutCheckbox()   -- re-assert after Blizzard rebuilds the form
        PinQuantityRow()           -- ditto; installs the SetItem hook on first pass
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

    -- Teardown on close. Core documents AH_CLOSED as the teardown signal and every
    -- other AH UI file subscribes; this one did not, so state.pending survived the
    -- session and GET_ITEM_INFO_RECEIVED kept arming debounce timers during normal
    -- play for items that were cold when the AH shut, each resolving to a Refresh
    -- that only early-returns on AH.isOpen. Nothing is lost by dropping the set: the
    -- next session's CollectItems pass rebuilds it from the bags.
    --
    -- Do NOT fix this by unregistering GET_ITEM_INFO_RECEIVED instead. The v1.7.15
    -- warm-while-hidden behaviour needs that event delivered with the strip hidden,
    -- and removing the registration would bring back the on-screen reshuffle that
    -- change existed to kill. Clear the state, keep the registration.
    AH.Events.On("AH_CLOSED", function()
        if state.refreshTimer then
            state.refreshTimer:Cancel()
            state.refreshTimer = nil
        end
        state.pending = {}
    end)
end
