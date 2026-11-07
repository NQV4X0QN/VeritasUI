-- VeritasUI_AuctionHouse / UI/CraftingOrder.lua
-- Adds a "Reagents Value:" line to Blizzard's Place Crafting Order form, showing
-- what the recipe's reagents are worth at the last-scanned auction price.
--
-- PURE DATABASE READER. It never queries the AH, never writes to the price store,
-- and works away from an auctioneer — same contract as Tooltip.lua. Nothing here
-- touches the scan engine.
--
-- ── Blizzard surface (verified against Auctionator's Source_Mainline/CraftingInfo,
--    which does the same job; API shapes taken from there rather than guessed) ──
--   * Frame is LoadOnDemand (Blizzard_ProfessionsCustomerOrders), so it does not
--     exist at PLAYER_LOGIN. The hook point is
--     PLAYER_INTERACTION_MANAGER_FRAME_SHOW with
--     Enum.PlayerInteractionType.ProfessionsCustomerOrder.
--   * Anchor is ProfessionsCustomerOrdersFrame.Form.ReagentContainer.Reagents;
--     our line sits under it, which is where the native layout leaves a gap.
--   * Costs come from the form's `transaction`:
--       transaction:GetRecipeSchematic().reagentSlotSchematics
--       transaction:GetAllocations(slotIndex)  ->  :FindAllocationByReagent(r)
--                                             ->  :GetQuantity()
--     An ALLOCATED reagent is priced at the quality actually chosen; an
--     unallocated Basic slot is priced at its CHEAPEST quality times the quantity
--     still required. That is why the screenshot case (every slot 0/N) still shows
--     a number: it is the cheapest-quality cost of filling the whole recipe.
--
-- ⚠ DELIBERATE DIVERGENCE FROM AUCTIONATOR: it prices each reagent as
--    `vendorPrice or auctionPrice`, preferring a vendor. We have no vendor-price
--    cache, so this is AUCTION-ONLY. That is also what was actually asked for
--    ("how much each item sells for on the auction house"), so it is a feature
--    boundary rather than a gap — but do not read our number as "cheapest way to
--    source these", because for vendor-stocked reagents it can be much higher.
--
-- ⚠ UNPRICED REAGENTS ARE COUNTED AND SHOWN. Auctionator contributes 0 for a
--    reagent it has no price for, silently, which makes a half-known recipe look
--    cheap rather than unknown. Since the owner uses the price-age line to decide
--    when to rescan, a silently-low total would actively mislead: we append
--    "(N unpriced)" instead.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
--
--  REFRESH_RATE gates an OnUpdate, so the handful of calls inside Recompute run
--  up to 10x/second while the form is open. Cold globals (CreateFrame, the Enum
--  lookup) are deliberately left alone per the suite's hot-path-only convention.
----------------------------------------------------------------
local ipairs      = ipairs
local pcall       = pcall
local format      = string.format
local CreateFrame = CreateFrame

AH.CraftingOrder = {}

-- 0.1s matches Lib's HOVER_FADE_POLL_RATE. Auctionator recomputes every frame;
-- reagent allocation only changes on a click, so 10 Hz is imperceptible and does
-- ~6x less work at 60fps. Not a per-frame OnUpdate, deliberately.
local REFRESH_RATE   = 0.1
local LABEL          = "Reagents Value:"
-- Vertical gap below the reagent grid, in pixels (larger = lower). Cosmetic only:
-- it centres the line in the band between the last reagent icon and Blizzard's
-- "Provide Optional Reagents:" label. This is THE knob for that position -- see the
-- single-point anchor in Build().
-- Settled by eye against the live client, not computed: the original anchor read
-- slightly too HIGH, 7 too LOW, 3 a touch high, 4 correct. Screenshot arithmetic was
-- deliberately avoided -- the captures came at different image scales, so pixel math
-- across them would have been false precision. This is THE knob for the vertical
-- position (see the single-point anchor in Build); nothing else affects it.
local LINE_GAP_Y     = 4
local UNPRICED_COLOR = "|cFFFF8800"   -- the orange used for restart/warning hints
-- The holder uses GameFontNormal, which is Blizzard's GOLD label font -- correct for
-- the "Reagents Value:" label, wrong for the amount: every other currency figure in
-- the UI (and our own tooltip price) renders WHITE. So the label inherits the font
-- and only the amount is wrapped.
--
-- Safe to wrap the whole coin string even though it contains |A:coin-*| atlas
-- markup: inline textures are not tinted by |c| colour codes. Auctionator relies on
-- the same thing (it wraps GetMoneyString's texture output in WHITE_FONT_COLOR), and
-- its coins render in their natural colours.
--
-- A literal rather than Blizzard's WHITE_FONT_COLOR:WrapTextInColorCode(): one less
-- global to depend on, matches UNPRICED_COLOR directly above, and keeps the headless
-- suite from needing a colour-mixin stub to assert on the output.
local AMOUNT_COLOR   = "|cFFFFFFFF"

local panel            -- our fontstring holder, created once
local elapsed   = 0


----------------------------------------------------------------
--  Price one reagent
--
--  Reagents are commodities, so MakeKeyFromItemID is the right key builder: it
--  returns "i:<itemID>" and deliberately returns nil for GEAR (a gear key needs an
--  item level, which needs a loaded link). A nil key therefore means "not
--  priceable by itemID alone", which for a reagent slot should not happen — but it
--  is treated as unpriced rather than assumed free.
--
--  Returns (copper, priced) so the caller can distinguish "worth 0" from "unknown".
----------------------------------------------------------------
local function UnitPrice(itemID)
    if not (AH.DB and itemID) then return 0, false end
    local key = AH.DB.MakeKeyFromItemID(itemID)
    if not key then return 0, false end
    local price = AH.DB.GetMarketPrice(key)
    if not price or price <= 0 then return 0, false end
    return price, true
end

----------------------------------------------------------------
--  Total the reagents for the form's current transaction
--
--  Every profession-API call is pcall-guarded: these are Blizzard mixin methods we
--  do not own, reached through a LoadOnDemand frame, and a nil/renamed method here
--  must degrade to "no line" rather than error on every frame of an open form.
--
--  Returns (copper, unpricedCount) or nil when there is nothing to show.
----------------------------------------------------------------
local function Recompute(form)
    local ok, transaction = pcall(function() return form.transaction end)
    if not ok or not transaction then return nil end

    local okS, schematic = pcall(transaction.GetRecipeSchematic, transaction)
    if not okS or type(schematic) ~= "table" then return nil end
    local slots = schematic.reagentSlotSchematics
    if type(slots) ~= "table" then return nil end

    local total, unpriced = 0, 0

    for slotIndex, slot in ipairs(slots) do
        local reagents = slot.reagents
        if type(reagents) == "table" and #reagents > 0 then
            local okA, allocations = pcall(transaction.GetAllocations, transaction, slotIndex)
            if not okA then allocations = nil end

            -- Sum what the user has actually allocated, per quality.
            local allocatedCount = 0
            if allocations then
                for _, reagent in ipairs(reagents) do
                    local itemID = reagent.itemID
                    if itemID then
                        local okF, alloc = pcall(allocations.FindAllocationByReagent,
                                                 allocations, reagent)
                        local qty = 0
                        if okF and alloc then
                            local okQ, q = pcall(alloc.GetQuantity, alloc)
                            qty = (okQ and type(q) == "number") and q or 0
                        end
                        if qty > 0 then
                            allocatedCount = allocatedCount + qty
                            local unit, priced = UnitPrice(itemID)
                            if priced then
                                total = total + unit * qty
                            else
                                unpriced = unpriced + 1
                            end
                        end
                    end
                end
            end

            -- Anything still required on a BASIC slot is costed at its cheapest
            -- quality. Optional/finishing slots are skipped when unallocated: the
            -- user has not chosen to include them, so charging for them would
            -- overstate the recipe (this mirrors the reference implementation's
            -- reagentType check).
            local required = slot.quantityRequired or 0
            local isBasic = Enum and Enum.CraftingReagentType
                            and slot.reagentType == Enum.CraftingReagentType.Basic
            if isBasic and allocatedCount < required then
                local remaining = required - allocatedCount
                local cheapest, found = nil, false
                for _, reagent in ipairs(reagents) do
                    if reagent.itemID then
                        local unit, priced = UnitPrice(reagent.itemID)
                        if priced and (not found or unit < cheapest) then
                            cheapest, found = unit, true
                        end
                    end
                end
                if found then
                    total = total + cheapest * remaining
                else
                    unpriced = unpriced + 1
                end
            end
        end
    end

    return total, unpriced
end

----------------------------------------------------------------
--  Render
----------------------------------------------------------------
local function BuildText(form)
    -- AH.Setting is defined in Tooltip.lua, which the TOC loads BEFORE this file,
    -- so it is guaranteed present — no guard, per the suite's guard policy for
    -- TOC-ordered module tables. It also supplies the default when the saved
    -- variable has not been seeded yet.
    -- WoW Forever has no crafting orders (owner, 2026-11-06), and no option for this there.
    if VUI.IS_FOREVER or not AH.Setting("craftShowReagentValue") then return nil end
    local total, unpriced = Recompute(form)
    if not total then return nil end
    -- Nothing known at all: say so rather than showing a confident 0g.
    if total <= 0 and (unpriced or 0) > 0 then
        return LABEL .. " " .. UNPRICED_COLOR .. "no scanned prices|r"
    end
    if total <= 0 then return nil end

    -- MODERN coin art, matching our tooltips: AH.Tooltip.CoinMarkup builds the
    -- inline |A:coin-gold:14:14:2:0|a atlas markup that was probe-matched to
    -- Blizzard's 12.0.7 "Sell Price:" line. AH.Money.Format would use
    -- GetCoinTextureString, which is the OLD coin art -- correct for CHAT output
    -- (see the QualityOfLife AutoSell landmine: Blizzard itself still uses old
    -- coins there) but wrong for a UI panel sitting beside Blizzard's own modern
    -- Posting Fee / Total Price lines.
    --
    -- Reused rather than re-declared: a second copy of those atlas constants is
    -- exactly the second-source drift the v1.9.13 consistency pass existed to
    -- remove, and these values were expensive to verify. Deliberately NOT moved
    -- into Money.lua where it arguably belongs -- that file's coin work is
    -- pixel-verified on Mac AND PC, and relocating it buys tidiness at the cost of
    -- disturbing working, hard-won code. Tooltip.lua loads before this file, so
    -- AH.Tooltip.CoinMarkup is TOC-guaranteed and needs no guard.
    local coins = AH.Tooltip.CoinMarkup(total)
    local text = LABEL .. " " .. AMOUNT_COLOR .. coins .. "|r"
    if (unpriced or 0) > 0 then
        text = text .. "  " .. UNPRICED_COLOR
            .. format("(%d unpriced)", unpriced) .. "|r"
    end
    return text
end

local function Refresh(self, delta)
    elapsed = elapsed + (delta or 0)
    if elapsed < REFRESH_RATE then return end
    elapsed = 0

    local form = self:GetParent()
    -- ⚠ NEVER Hide() this frame. OnUpdate does not fire on a hidden frame, so
    -- hiding it here (or in Build) deadlocks: no OnUpdate -> text never set ->
    -- never shown again. That exact bug shipped once (v1.12.8 development) and was
    -- found by a temporary probe, since removed, whose signature is worth knowing:
    -- BuildText returned the CORRECT string while the panel reported
    -- `shown=false ... text=""`. Recorded in PROBE_LIBRARY §5.
    --
    -- Nothing needs hiding anyway: an empty FontString renders nothing, and the
    -- frame is a child of Blizzard's Form, so it inherits the crafting window's
    -- visibility -- which also means OnUpdate costs nothing while that window is
    -- closed, without us managing it.
    self.Total:SetText(BuildText(form) or "")
end

----------------------------------------------------------------
--  Mount
--
--  Built once and kept: Blizzard's form is reused across orders, and re-creating
--  the holder per open would orphan a frame each time (WoW frames cannot be
--  destroyed — the same reasoning as AdvancedOptions' F-7 fix).
----------------------------------------------------------------
local function Build()
    if panel then return true end

    local ordersFrame = _G.ProfessionsCustomerOrdersFrame
    local form = ordersFrame and ordersFrame.Form
    -- Guard EVERY level: this is a LoadOnDemand Blizzard layout we do not own, and a
    -- restructure must cost us the feature, not throw on their frame's show. The path
    -- and the container's sibling keys (RecraftInfoText, OptionalReagents, Reagents)
    -- were dumped from the live client 2026-08-03 — see PROBE_LIBRARY §5, which is
    -- where to diff against if this ever stops resolving.
    local container = form and form.ReagentContainer
    local reagents = container and container.Reagents
    if not (form and reagents) then return false end

    panel = CreateFrame("Frame", nil, form)
    panel:SetSize(400, 16)
    -- Under the reagent list, matching where the native layout leaves a gap.
    -- ONE point, deliberately. Auctionator anchors this with two
    -- (LEFT..reagents,LEFT,0,-10 plus TOP..reagents,BOTTOM), which sets the
    -- vertical position twice with different values -- the -10 on the LEFT point
    -- fights the 0 on the TOP point. A single TOPLEFT fully determines a
    -- fixed-size frame and makes LINE_GAP_Y the only thing controlling the
    -- vertical position, so nudging it is predictable.
    panel:SetPoint("TOPLEFT", reagents, "BOTTOMLEFT", 0, -LINE_GAP_Y)

    panel.Total = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.Total:SetPoint("TOPLEFT")
    panel.Total:SetJustifyH("LEFT")

    panel:SetScript("OnUpdate", Refresh)
    -- Deliberately NOT hidden here -- see the warning in Refresh.
    return true
end

----------------------------------------------------------------
--  Event wiring
--
--  PLAYER_INTERACTION_MANAGER_FRAME_SHOW is the only reliable moment the
--  LoadOnDemand frame is guaranteed to exist. The Enum is read defensively so a
--  client without ProfessionsCustomerOrder simply never mounts.
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
ef:SetScript("OnEvent", function(_, _, interactionType)
    -- Measured as 60 on 12.0.7 (PROBE_LIBRARY §5), but read from the Enum rather
    -- than hardcoded: a client without this interaction type simply never mounts.
    local want = Enum and Enum.PlayerInteractionType
                 and Enum.PlayerInteractionType.ProfessionsCustomerOrder
    if want == nil or interactionType ~= want then return end
    Build()
end)

-- Exposed for the headless suite, which drives Recompute against a synthetic
-- transaction rather than a live profession frame.
-- Exposed for the headless suite, which drives the cost model against a synthetic
-- transaction rather than a live profession frame. `_Build` was also exported during
-- development and is NOT kept: nothing read it, and a write-only export is the F-8
-- finding class from the cycle-4 footprint pass.
AH.CraftingOrder.BuildText = BuildText
AH.CraftingOrder.Recompute = Recompute

