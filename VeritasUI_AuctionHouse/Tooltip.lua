-- VeritasUI_AuctionHouse / Tooltip.lua
-- Append the stored market price to item AND battle-pet tooltips.
--
-- Pure DB READ — no live AH query, works offline (away from the AH), and is
-- read-only so it carries no taint risk. Two distinct mechanisms (verified 12.0.5):
--   * Items: TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item).
--   * Battle pets: hooksecurefunc("BattlePetToolTip_Show", fn) — pets do NOT use
--     TooltipDataProcessor; the global is called with speciesID as arg 1, and the
--     frame shown is the custom BattlePetTooltip (not a GameTooltip).

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local TooltipDataProcessor = TooltipDataProcessor
local TooltipUtil          = TooltipUtil
local Enum                 = Enum
local pairs                = pairs

AH.Tooltip = {}

-- Defaults for this module's user toggles. Seeded into db.settings on first run;
-- all on. Renamed from TT_DEFAULTS in v1.12.8: it is no longer tooltip-only, and
-- Settings.lua already documents SeedDefaults as the SINGLE seeding authority, so
-- new toggles belong here rather than in a second table that could drift out of
-- sync with the settings panel.
local SETTING_DEFAULTS = {
    ttShowPrice = true,   -- show "AH:" market price line
    ttShowAge   = true,   -- annotate stale prices with their age in days
    ttShowQty   = true,   -- show last-seen quantity
    -- UI/CraftingOrder.lua — "Reagents Value:" on the Place Crafting Order form
    craftShowReagentValue = true,
}

local function S(key)
    local s = AH.db and AH.db.settings
    if not s then return SETTING_DEFAULTS[key] end
    if s[key] == nil then return SETTING_DEFAULTS[key] end
    return s[key]
end
AH.Tooltip.Setting = S
-- Canonical module-wide accessor. AH.Tooltip.Setting is kept as the original name
-- so existing call sites are untouched; new files should read AH.Setting.
AH.Setting = S

-- Seed missing toggle defaults (called once, after AH.db exists).
function AH.Tooltip.SeedDefaults()
    if not AH.db then return end
    AH.db.settings = AH.db.settings or {}
    for k, v in pairs(SETTING_DEFAULTS) do
        if AH.db.settings[k] == nil then
            AH.db.settings[k] = v
        end
    end
end

----------------------------------------------------------------
--  The price line builder
----------------------------------------------------------------
local AGE_COLOR = "|cFF808080"   -- grey, for the secondary "N seen · X days" line

-- Compute the raw price + optional extras line for a DB key. Returns
--   price (int copper), extrasLine (string|nil)   — or nil if no price/disabled.
-- The CALLER renders the price: the GameTooltip path draws an OWNED coin
-- fontstring (inline |A| atlas coins + NumberFontNormalRight) — it NEVER calls
-- Blizzard money code (see the "WHY NOT MoneyFrame_Update" block below / LM-7).
-- The battle-pet path uses a text coin string (its custom frame has no
-- money-frame support).
local function BuildPriceData(key)
    if not S("ttShowPrice") then return nil end
    if not (AH.DB and key) then return nil end

    local price = AH.DB.GetMarketPrice(key)
    if not price or price <= 0 then return nil end

    local extras = {}
    if S("ttShowQty") then
        local hist = AH.DB.GetPriceHistory(key)
        -- hist is sorted newest-first, so hist[1] is the most-recently-recorded
        -- day's entry (not necessarily *today* — the last scan may be older).
        local latest = hist[1]
        if latest and latest.qty and latest.qty > 0 then
            extras[#extras + 1] = latest.qty .. " seen"
        end
    end
    if S("ttShowAge") then
        local age = AH.DB.GetPriceAge(key)
        if age and age > 0 then
            extras[#extras + 1] = (age == 1 and "1 day old" or (age .. " days old"))
        end
    end
    local extrasLine = (#extras > 0) and (AGE_COLOR .. table.concat(extras, "  ·  ") .. "|r") or nil

    return price, extrasLine
end

-- GameTooltip path: render the price as a SELF-RENDERED coin widget.
--
-- WHY NOT MoneyFrame_Update (v1.7.6 "private MoneyFrame" — REMOVED, it ALSO crashed):
--   v1.7.6 rendered through our own TooltipMoneyFrameTemplate, believing that since
--   OUR price is a plain integer the update was crash-safe. WRONG — proven in-game by
--   /ah probe + a Delve repro: MoneyFrame_Update throws at MoneyFrame.lua:340 on
--   'silverWidth' (a Secret Value) — an INTERNAL coin-column width Blizzard's own layout
--   math computes, which becomes Secret in instanced content (Delves/M+/raids). It has
--   nothing to do with our price. So MoneyFrame_Update itself is unsafe from our context;
--   we must not call it at all. (The v1.7.6 SKILL/design-doc "crash-safe — verified
--   in-game" claim is hereby falsified — see Known Landmines correction.)
--
-- HOW THIS RENDERS NATIVELY WITHOUT ANY MONEY MATH (probe-verified specs 12.0.5):
--   * Coins  = the Coin-Gold / Coin-Silver / Coin-Copper atlases at 14x14, emitted as
--              inline |A:atlas:h:w|a markup in a fontstring. Pure text → zero Blizzard
--              arithmetic → cannot throw on a Secret Value, in any content.
--   * Numbers= the tooltip BODY font, copied at render time from our own label line
--              (probe-verified 12.0.7 = FRIZQT__ / 12 / no-outline, identical to the
--              native "Sell Price:" line). Was NumberFontNormalRight (ARIALN/14/OUTLINE)
--              until 12.0.7, when Blizzard moved the price off the MoneyFrame to an inline
--              body-font text line; the old pin no longer matched, so we now copy the live
--              label font and genuinely track any future Blizzard restyle.
--   * Label  = a real tooltip AddLine ("Auction:"), so the label inherits the exact
--              tooltip body font the native "Sell Price:" label uses — no font guessing.
--   * The coin fontstring is created once per tooltip frame and PARENTED TO THE
--     TOOLTIP (an earlier UIParent-parented overlay attempt rendered invisible —
--     see the RenderCoinLine block below), anchored to our label line, and hidden
--     on OnTooltipCleared so it never leaks onto non-item tooltips.
local PRICE_PREFIX = "Auction:"

-- Where the coin block starts: the x-offset (px, from the line's LEFT edge) at which our
-- first coin digit sits, chosen to land directly under the native "Sell Price:" coin
-- column. That position is the rendered width of the native "Sell Price: " prefix in the
-- tooltip body font — but that width is RASTERIZED PER-OS: macOS and Windows render the
-- same FRIZQT__/12 glyphs to slightly different pixel widths, so a hardcoded constant
-- drifts a fraction of a pixel between machines (the first digit sits just left/right of
-- the native one — sub-pixel on the OS it was measured on, ~1px on the other). We
-- therefore MEASURE it live at render time (MeasureNativePrefix) so each OS self-corrects,
-- the same principle as copying the live label font. The constants below are only the
-- fallback (if the live measure fails) and an optional manual fine-tune.
-- WON'T FIX, decided in cycle 4, not an oversight: the word comes from Blizzard's
-- localized SELL_PRICE global but the ": " is ours, so a locale that spaces its colon
-- (Prix de vente : ) measures one space short and shifts the first coin digit a few
-- pixels left of the native column - the exact defect the live measure exists to kill.
-- Cosmetic, non-enUS only, and this is a single-user addon on an English client. The
-- suite's only other hardcoded-English site, the "Defaults" fallback in Lib's reload
-- button anchor search, carries the same note and the same decision.
local SELL_PREFIX          = (SELL_PRICE or "Sell Price") .. ": " -- string we measure live
local COIN_COLUMN_FALLBACK = 59  -- used ONLY if the live measure returns nil (px)
local COIN_COLUMN_NUDGE    = 0   -- manual fine-tune added after auto-measure (px; + = right)

-- Inline atlas coin markup, matched EXACTLY to the native "Sell Price:" line via raw-
-- markup probe (12.0.7): |A:coin-gold:14:14:2:0|a. The :14:14 is the icon size (an
-- earlier 13x13 figure was wrong — native is 14, corrected in v1.7.15); the trailing
-- :2:0 are the atlas x/y pixel offsets native uses to vertically center the coin on
-- the text baseline.
-- Omitting either made ours read small and sit slightly off. (Sizes are tunable here.)
local COIN_G = "|A:coin-gold:14:14:2:0|a"
local COIN_S = "|A:coin-silver:14:14:2:0|a"
local COIN_C = "|A:coin-copper:14:14:2:0|a"

-- Build the coin string for a copper amount: number immediately followed by its coin,
-- a space between denominations (matches GetCoinTextureString's grouping). Only nonzero
-- denominations are shown; a sub-1-silver price still shows copper.
-- NOTE: the exact intermediate-zero rule (e.g. 1g 0s 5c) is the one piece not verified
-- against the live "Sell Price:" line — AH prices almost never carry an intermediate
-- zero, and this is one-line tunable if an edge case looks off in-game.
-- AH.Money needs no nil-guard here or in the two text-coin fallbacks below: the TOC loads
-- Money.lua before this file, both files bail identically if VUI is missing, and every call
-- site runs at hover time. Two guards that could never fire were removed in v1.9.13 - do not
-- re-add them; the load order is the guarantee. The `or tostring(price)` fallbacks stay,
-- since those cover Format returning nil, which is a different risk.
local function CoinMarkup(copper)
    local g, s, c = AH.Money.Breakdown(copper)
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN_G end
    if s > 0 then parts[#parts + 1] = s .. COIN_S end
    if c > 0 then parts[#parts + 1] = c .. COIN_C end
    if #parts == 0 then parts[1] = "0" .. COIN_C end
    return table.concat(parts, " ")
end
AH.Tooltip.CoinMarkup = CoinMarkup

-- Render the price as: a Friz "Auction:" label line + an ARIALN coin fontstring WE OWN.
--
-- WHY A FONTSTRING WE OWN (not AddDoubleLine's right column):
--   AddDoubleLine's right column is POSITION-MANAGED by Blizzard's tooltip layout. We
--   could re-font it (SetFontObject stuck → ARIALN coins rendered) but every attempt to
--   re-POSITION it was ignored or clobbered by Blizzard's layout pass after our PostCall
--   returned (right-justified stayed; a deferred re-anchor only held for one frame →
--   flicker; a synchronous coordinate re-anchor threw and vanished the line). Conclusion
--   (deduced, not client-verified): we cannot reposition the managed column. So we don't
--   use it — we add a PLAIN left label line (Friz, matches "Sell Price:"), then draw the
--   coins in a fontstring we CREATE and OWN, parented to the TOOLTIP. Blizzard's layout
--   manages only its own line regions, not an extra child we add, so our anchor sticks.
--
--   (This is the corrected version of the earlier failed "overlay" attempt — that one
--   was parented to UIParent and rendered invisible; parenting to the tooltip fixes it.)
--
-- FONT: coins copy the tooltip BODY font from our label line at render time (probe-
--   verified 12.0.7 = FRIZQT__/12/no-outline, the native "Sell Price:" font). Do NOT
--   re-pin to NumberFontNormalRight — that was ARIALN/14/OUTLINE and stopped matching
--   when Blizzard moved the price to an inline body-font line in 12.0.7.
-- CRASH-SAFE: pure text + inline |A| atlas coin markup, zero Blizzard money math, so the
--   silverWidth Secret-Value trap (Delves/M+/raids) is never touched.

local coinFS = {}   -- [tooltip] = our owned coin fontstring (one per tooltip frame)

local function GetCoinFontString(tooltip)
    local fs = coinFS[tooltip]
    if fs then return fs end
    fs = tooltip:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    fs:SetTextColor(1, 1, 1)
    coinFS[tooltip] = fs
    -- Our fontstring is parented to the tooltip and PERSISTS across hovers. The Item
    -- post-call (OnItemTooltip) only fires for ITEM tooltips, so when GameTooltip is
    -- repopulated as a UNIT/spell/etc. tooltip our hide-logic never runs and the stale
    -- coins from the last item leak onto it (the reported bug: a player unit tooltip
    -- showing the previous item's price). OnTooltipCleared fires whenever the tooltip is
    -- cleared BEFORE any repopulation, regardless of the next content type, so hide our
    -- coins there. For a priced ITEM the Item post-call re-Shows them in the same
    -- synchronous SetItem rebuild (clear → set data → post-call), so there's no flicker.
    if tooltip.HookScript then
        tooltip:HookScript("OnTooltipCleared", function() fs:Hide() end)
    end
    return fs
end

-- Measure the rendered px width of the native "Sell Price: " prefix in the SAME font the
-- tooltip line uses, so the coin column self-corrects per-OS (macOS/Windows rasterize the
-- glyphs to slightly different widths). Uses a reusable hidden UIParent fontstring set to
-- the live line font. Returns nil if it can't measure (caller falls back to the constant).
local measureFS
local function MeasureNativePrefix(fontPath, fontSize, fontFlags)
    if not fontPath then return nil end
    if not measureFS then
        measureFS = UIParent:CreateFontString(nil, "BACKGROUND")
        measureFS:Hide()
    end
    measureFS:SetFont(fontPath, fontSize, fontFlags or "")
    measureFS:SetText(SELL_PREFIX)
    local w = measureFS:GetStringWidth()
    if not w or w <= 0 then return nil end
    return w
end

local function RenderCoinLine(tooltip, price)
    if not (tooltip.AddLine and tooltip.CreateFontString) then return false end

    -- Resolve the frame name BEFORE adding anything. false means "I rendered nothing, caller
    -- use the text-coin fallback", so every false exit must leave the tooltip untouched -
    -- which is why this lookup happens first instead of after the label row.
    local name = tooltip.GetName and tooltip:GetName()
    if not name then return false end

    -- Friz label line (matches native "Sell Price:" label font). Reserves the row.
    tooltip:AddLine(PRICE_PREFIX, 1, 1, 1)

    -- NumLines is only correct once the label row exists, so this one cannot be hoisted.
    -- Returning true here is deliberate, not a copy of the bug fixed above: the label row is
    -- already committed, so returning false would make the caller add a SECOND "Auction:"
    -- line. The exit cannot fire anyway - the AddLine directly above guarantees the row.
    local left = _G[name .. "TextLeft" .. tooltip:NumLines()]
    if not left then return true end

    -- Place our coin block so its first digit lands under the native "Sell Price:" coin
    -- column. We anchor to OUR label's LEFT edge (same row → correct Y) and offset by the
    -- native prefix's rendered width, MEASURED LIVE in the actual line font (see
    -- MeasureNativePrefix) so it self-corrects across macOS/Windows rasterization instead
    -- of trusting a baked constant. We deliberately do NOT read GetLeft() of the freshly-
    -- added label or the money frame (stale/nil mid-layout → the throw that vanished the
    -- line earlier). COIN_COLUMN_NUDGE is the optional manual fine-tune; COIN_COLUMN_FALLBACK
    -- is used only if the live measure fails.
    local fs = GetCoinFontString(tooltip)
    -- Match the native "Sell Price:" coins exactly: probe-verified 12.0.7 they are the
    -- tooltip BODY font (FRIZQT__ / 12 / no-outline), identical to our label line. Copy
    -- the font straight off our just-added label fontstring so we track Blizzard's font
    -- per-tooltip and across future restyles — what the old NumberFontNormalRight pin
    -- only claimed to do but didn't (it stayed ARIALN/14/OUTLINE after the 12.0.7 change).
    local lf, ls, lflags = left:GetFont()
    if lf then fs:SetFont(lf, ls, lflags or "") end
    fs:SetText(CoinMarkup(price))
    fs:ClearAllPoints()
    local column = MeasureNativePrefix(lf, ls, lflags) or COIN_COLUMN_FALLBACK
    fs:SetPoint("LEFT", left, "LEFT", column + COIN_COLUMN_NUDGE, 0)
    fs:Show()
    return true
end

local function AppendPriceForKey(tooltip, key)
    local price, extras = BuildPriceData(key)
    if not price then return end
    if not RenderCoinLine(tooltip, price) then
        -- Self-render path unavailable (no tooltip name/anchor) → plain text-coin line.
        local coins = AH.Money.Format(price) or tostring(price)
        tooltip:AddLine(PRICE_PREFIX .. "  " .. coins, 1, 1, 1)
    end
    if extras then tooltip:AddLine(extras) end
end

-- Append our line(s) to a tooltip for the given item link, if we have a price.
local function AppendPrice(tooltip, link)
    if not (AH.DB and link) then return end
    local key = AH.DB.MakeKey(link)
    if key then AppendPriceForKey(tooltip, key) end
end

----------------------------------------------------------------
--  Hook registration
--
--  AddTooltipPostCall fires on every tooltip (re)build. We re-derive the link
--  fresh each call (cheap) and let Blizzard's own rebuild clear prior lines, so
--  there is no line-stacking on repeated refreshes — each rebuild starts clean
--  and we append exactly once.
----------------------------------------------------------------
local function OnItemTooltip(tooltip, data)
    -- Only handle the shared GameTooltip + ItemRefTooltip family. Some internal
    -- tooltips (compare shopping, etc.) are children we don't want to touch.
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

    -- Our owned coin fontstring persists across hovers; hide it on EVERY rebuild so a
    -- non-priced item (where RenderCoinLine never runs) doesn't show stale coins from
    -- a previous priced hover. RenderCoinLine re-Shows it when there IS a price.
    local fs = coinFS[tooltip]
    if fs then fs:Hide() end

    local link = data and data.hyperlink
    if not link and TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, l = TooltipUtil.GetDisplayedItem(tooltip)
        link = l
    end
    if not link then return end

    -- Read-only DB lookup; pcall-guarded so a malformed link never errors a tooltip.
    pcall(AppendPrice, tooltip, link)
end

----------------------------------------------------------------
--  Battle-pet tooltips
--
--  VERIFIED (against Auctionator's clean-room reference + Blizzard API usage):
--  battle-pet tooltips do NOT flow through TooltipDataProcessor /
--  Enum.TooltipDataType.BattlePet. The correct hook is the global function
--  BattlePetToolTip_Show(speciesID, ...) — Blizzard hands us the speciesID as
--  arg 1 directly, which maps straight to our DB key "p:<speciesID>". The frame
--  shown is the custom BattlePetTooltip (not a GameTooltip), and chat-link pets
--  use FloatingBattlePetTooltip via FloatingBattlePet_Toggle.
----------------------------------------------------------------

-- Append our price line(s) to a custom battle-pet tooltip FRAME (BattlePetTooltip
-- / FloatingBattlePetTooltip). These are NOT GameTooltips — no money-frame support,
-- so this path renders a text coin string (the GameTooltip path draws an owned
-- coin fontstring — never Blizzard money code).
local function AppendPetPrice(petTooltip, speciesID)
    if not (petTooltip and speciesID) then return end
    local price, extras = BuildPriceData("p:" .. speciesID)
    if not price then return end
    -- The custom BattlePetTooltip frame has no money-frame support, so this path
    -- uses a text coin string (the modern GetCoinTextureString via AH.Money.Format).
    -- It won't be pixel-identical to a GameTooltip money frame, but BattlePetTooltip
    -- has no native money line to match against anyway.
    local coins = AH.Money.Format(price) or tostring(price)
    petTooltip:AddLine("Auction:  " .. coins, 1, 1, 1)
    if extras then petTooltip:AddLine(extras) end
end

local function HookBattlePetTooltips()
    -- Caged pet hovered in bags / AH / anywhere → BattlePetTooltip.
    if type(BattlePetToolTip_Show) == "function" then
        hooksecurefunc("BattlePetToolTip_Show", function(speciesID)
            pcall(AppendPetPrice, BattlePetTooltip, speciesID)
        end)
    elseif VUI.debug then
        VUI.Print(AH.TAG, "|cFFFF4444BattlePetToolTip_Show missing|r — pet prices unavailable.")
    end

    -- Chat-link / floating pet tooltip → FloatingBattlePetTooltip. Its species id
    -- is on the frame after the toggle, so read it from the frame.
    if type(FloatingBattlePet_Toggle) == "function" then
        hooksecurefunc("FloatingBattlePet_Toggle", function()
            if FloatingBattlePetTooltip and FloatingBattlePetTooltip:IsShown() then
                pcall(AppendPetPrice, FloatingBattlePetTooltip, FloatingBattlePetTooltip.speciesID)
            end
        end)
    end
end

local function Register()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
            and Enum and Enum.TooltipDataType) then
        if VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444Tooltip hook unavailable|r (API missing).")
        end
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    HookBattlePetTooltips()
end

----------------------------------------------------------------
--  Startup — seed defaults then register the hook on login.
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function()
    AH.Tooltip.SeedDefaults()
    Register()
    ef:UnregisterAllEvents()
end)
