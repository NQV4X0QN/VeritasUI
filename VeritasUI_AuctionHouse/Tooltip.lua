-- VeritasUI_AuctionHouse / Tooltip.lua
-- Append the stored market price to item AND battle-pet tooltips.
--
-- Pure DB READ — no live AH query, works offline (away from the AH).
--
-- ⚠ "Read-only, therefore no taint risk" USED TO BE ASSERTED HERE AND IS FALSE. Reading the
--   DB is harmless, but this file also MUTATES a shared secure Blizzard frame: it adds an
--   owned coin FontString to GameTooltip (see GetCoinFontString), and until v1.12.18 it also
--   HookScript'd GameTooltip's OnTooltipCleared. Do not re-add a blanket no-taint statement
--   to this file. (The UseContainerItem FORBIDDEN that prompted this note was ultimately
--   traced to UI/SellStrip.lua calling SetPostItem, fixed in v1.17.4 -- not to this file --
--   but "read-only" was never a reason to believe so.)
--
-- Three mechanisms:
--   * Items: TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item).
--   * All tooltip types: an AllTypes post-call that hides our coins, plus a poll backstop
--     for legacy tooltips — see the "Hiding the owned coin fontstring" block for why both.
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
    -- LiveSearch.lua — fold the AH's own per-item search results into the price DB.
    -- The CORRECTION LAYER for the browse minPrice defect documented below: it sends no
    -- query of its own (the client has already fetched the data to fill Blizzard's
    -- suggested Unit Price) and makes the stored price exact for every item you open on
    -- the Buy or Sell tab.
    liveSearchPrices = true,
    -- Which whole-AH scan engine the Scan button drives: "replicate" (Replicate.lua,
    -- C_AuctionHouse.ReplicateItems) or "browse" (Browse.lua, empty SendBrowseQuery).
    -- DEFAULT IS BROWSE (v1.12.12, owner decision after the arithmetic below).
    --
    -- ⚠ THE DEFAULT HAS MOVED THREE TIMES. Read this whole block before moving it again;
    -- the two previous flips were each made on a number that had not been decomposed.
    --
    -- KNOWN DEFECT, NOT A REASON TO REVERT ON ITS OWN: browse's minPrice is not the live
    -- lowest unit buyout. Measured twice with /ah browseprobe against Blizzard's ascending
    -- Sell-tab ladder at the same moment:
    --      2026-08-04  item 242639   browse 27500   cheapest listing 29800   ( -7.7%)
    --      2026-08-29  item 237365   browse 204900  cheapest listing 352200  (-41.8%)
    -- A minimum cannot sit below the cheapest thing on sale, so this is real. In both
    -- captures the quantity and the derived key were CORRECT (2026-08-29: 187985 against
    -- the tab's own 187986 Available, accurate to one unit, in the same payload as the bad
    -- price), so browse reads the right POPULATION and only the PRICE is wrong. Probably a
    -- server-side cached aggregate; still unverified.
    --
    -- ⚠ THE 7.7% CEILING WAS WRONG, AND THIS BLOCK ASSERTED IT FOR SEVENTEEN RELEASES.
    -- What stood here was:
    --      stored 2g11s vs market 2g64s (owner's first report)  = 20% gap
    --      stored 2g11s vs market 2g98s (minutes later)         = 29% gap
    --      browse minPrice vs market, SAME MOMENT               =  7.7% gap
    -- and concluded "only the 7.7% is attributable to browse". The DECOMPOSITION METHOD is
    -- sound and still the rule -- separate lag from staleness before acting, which is what
    -- /ah browseprobe is for. The CEILING it produced was not: 7.7% was one sample, and
    -- 237365 is 41.8% attributable to browse with the market provably still (the ladder
    -- read 352200 continuously across a 13s probe). Do not quote 7.7% as a bound again.
    --
    -- WHY BROWSE ANYWAY: replicate fails the first scan of most days -- the original
    -- complaint, unsolved for months, five hypotheses falsified. Browse completed in 10-15s
    -- every attempt, priced 22,540 items against replicate's 15,828 in 55.9s, and abandons
    -- no gear (replicate abandoned 38-67% of gear rows on two measured scans, which
    -- silently froze both the price AND the age of those items). And the defect above is now
    -- CORRECTED where it is felt: LiveSearch.lua rewrites the price of any item you open on
    -- the Buy or Sell tab from the AH's own authoritative per-item search, for free.
    -- ⚠ That correction is per-item and on-demand ONLY. It cannot cover the whole AH -- the
    -- per-item search is rate-capped, which is why the scan exists -- so an item you have
    -- never opened still carries whatever the scan stored.
    --
    -- ⚠ Deliberately NOT paired with a minutes-granularity age line. That was proposed and
    -- REJECTED by the owner: he reads the age line to decide whether to rescan, and
    -- per-minute noise on every tooltip is clutter, not signal. `seen` stays day-grained.
    --
    -- Escape hatch if prices feel wrong in use: /ah engine replicate. Spot-check any single
    -- item with /ah browseprobe, which compares browse's raw return against the game's own
    -- listing at the same moment; /ah live shows what the correction layer has fixed.
    scanEngine = "browse",
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

-- Keys that must NEVER be written into saved variables by seeding.
--
-- ⚠ THIS IS WHY v1.12.12's BROWSE TRIAL NEVER RAN. `scanEngine` was seeded like any
-- other toggle, so the first login on ANY release wrote a concrete engine name into
-- the saved variables permanently. From that moment on, changing the DEFAULT in this
-- file could not change behaviour for anyone who had already logged in -- which is
-- everyone. The default moved browse -> replicate -> browse across v1.12.9/11/12 and
-- every one of those flips was inert; the owner's confirmed saved variables read
-- `["scanEngine"] = "replicate"` while v1.12.12 shipped claiming browse was the
-- default, and the trial he agreed to silently ran on the other engine.
--
-- So: a setting whose default we intend to be able to CHANGE must not be pre-seeded.
-- Absence is meaningful -- it means "no explicit choice, follow the default" -- and
-- S() below already returns SETTING_DEFAULTS[key] for an absent key, so the default
-- becomes live with no other machinery. Only `/ah engine` writes this key, and that
-- write is a deliberate pin that correctly survives future default changes.
--
-- ⚠ Do not "tidy" this by folding scanEngine back into the seed loop for symmetry
-- with the tooltip toggles. The tooltip toggles are booleans the user drives from a
-- checkbox and whose defaults we have no intention of ever flipping; this one is a
-- policy default under active evaluation. The asymmetry is the point.
local SEED_EXEMPT = {
    scanEngine = true,
}

-- Seed missing toggle defaults (called once, after AH.db exists).
function AH.Tooltip.SeedDefaults()
    if not AH.db then return end
    AH.db.settings = AH.db.settings or {}

    -- One-time repair of the value the old seeding wrote (see SEED_EXEMPT above).
    -- Gated on a db flag so it runs exactly once ever, and so the second call in the
    -- same login (Settings.lua also calls SeedDefaults) neither re-clears nor
    -- re-prints. Destructive of one key, and announced, because a seeded value and a
    -- deliberate `/ah engine` pick are INDISTINGUISHABLE in the stored data -- there
    -- is no flag recording which wrote it. Rather than guess, clear it once and say
    -- so, naming the command that re-pins a real preference.
    if not AH.db.engineSettingUnseeded then
        AH.db.engineSettingUnseeded = true
        if AH.db.settings.scanEngine ~= nil then
            AH.db.settings.scanEngine = nil
            AH.engineSettingWasReset = true   -- Core.lua prints this at PLAYER_LOGIN
        end
    end

    for k, v in pairs(SETTING_DEFAULTS) do
        if AH.db.settings[k] == nil and not SEED_EXEMPT[k] then
            AH.db.settings[k] = v
        end
    end
end

----------------------------------------------------------------
--  The price line builder
----------------------------------------------------------------
local AGE_COLOR = VUI.COL.GRAY   -- grey, for the secondary "N seen · X days" line

-- Compute the raw price + optional extras line for a DB key. Returns
--   price (int copper), extrasLine (string|nil)   — or nil if no price/disabled.
-- The CALLER renders the price: the GameTooltip path draws an OWNED coin
-- fontstring (inline |A| atlas coins in the tooltip body font, copied from our label
-- line) — it NEVER calls
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
--     by OnAnyTooltip + WatchCoins (below; the OnTooltipCleared hook was removed in
--     v1.12.18) so it never leaks onto non-item tooltips.
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
-- Correct in every locale: Blizzard builds its own line as string.format("%s: %s",
-- SELL_PRICE, ...) (Blizzard_GameTooltip/Mainline/GameTooltip.lua:327), so its ": " is not
-- localized either and this prefix measures exactly what Blizzard renders. (A note here
-- until v1.17.8 claimed a locale-spacing defect and called it WON'T FIX for a single-user
-- English client; both halves were wrong.)
local SELL_PREFIX          = (SELL_PRICE or "Sell Price") .. ": " -- string we measure live
local COIN_COLUMN_FALLBACK = 59  -- used ONLY if the live measure returns nil (px)
local COIN_COLUMN_NUDGE    = 0   -- manual fine-tune added after auto-measure (px; + = right)
-- Backstop poll rate for hiding our owned coins on LEGACY (non-data-pipeline) tooltips.
-- ⚠ Must stay declared ABOVE WatchCoins: a local below a referencing closure binds as a nil
-- global (the /way trap, and v1.10.0's AFK_OVERLAY_STRATA), which would pass nil to NewTicker.
local COIN_WATCH_RATE      = 0.1 -- seconds; ticker exists ONLY while our coins are shown

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
--
-- ⚠ BLIZZARD'S FORMATTER FIRST (v1.17.8, audit A3). Blizzard's own Sell Price line is
-- `string.format("%s: %s", SELL_PRICE, MoneyFormatterUtil.FormatMoney(cost, GameTooltipMoneyFormat))`
-- (Blizzard_GameTooltip/Mainline/GameTooltip.lua:327). That config adds thousands separators to
-- gold (BreakUpLargeNumbers) and drops to g/s/c letters under Colorblind Mode
-- (Blizzard_SharedXML/MoneyFormatter.lua:134-142, 256-262); the hand-built markup below did
-- neither, so "12345g" sat under Blizzard's "12,345g". Its atlas markup defaults are the same
-- 14x14 / 2,0 we probe-matched (MoneyFormatter.lua:43-50), so glyph size and baseline do not
-- move. Safe from addon execution: the only Blizzard state it reads is the colorblind CVar, and
-- CVarCallbackRegistry:GetCVarValue caches only `if issecure()` (CvarUtil.lua:145-158).
-- The hand-built body stays as the fallback for a client without the formatter.
local function CoinMarkup(copper)
    if _G.MoneyFormatterUtil and _G.MoneyFormatterUtil.FormatMoney and _G.GameTooltipMoneyFormat then
        local ok, text = pcall(_G.MoneyFormatterUtil.FormatMoney,
            math.floor(tonumber(copper) or 0), _G.GameTooltipMoneyFormat)
        if ok and type(text) == "string" and text ~= "" and text ~= " " then return text end
    end
    local g, s, c = AH.Money.Breakdown(copper)
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN_G end
    if s > 0 then parts[#parts + 1] = s .. COIN_S end
    if c > 0 then parts[#parts + 1] = c .. COIN_C end
    if #parts == 0 then parts[1] = "0" .. COIN_C end
    return table.concat(parts, " ")
end
AH.Tooltip.CoinMarkup = CoinMarkup

-- Render the price as: a Friz "Auction:" label line + a coin fontstring WE OWN (body font, see FONT below).
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
    fs:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    coinFS[tooltip] = fs
    -- Our fontstring is parented to the tooltip and PERSISTS across hovers (there is no
    -- API to destroy a FontString, which is the whole reason a stale-coin problem exists).
    -- The Item post-call only fires for ITEM tooltips, so hiding it has to be driven from
    -- somewhere that also sees UNIT/spell/legacy tooltips — see OnAnyTooltip + WatchCoins.
    return fs
end

----------------------------------------------------------------
--  Hiding the owned coin fontstring
--
--  Two drivers, covering disjoint cases. Between them they reproduce exactly what the
--  old OnTooltipCleared HookScript did:
--
--    1. OnAnyTooltip  — an AllTypes tooltip post-call. Instant, and covers every tooltip
--       built through the data pipeline (item → unit/spell/mount/… repopulation, i.e. the
--       coin-leak bug fixed in v1.7.8).
--    2. WatchCoins    — a poll, alive ONLY while our coins are shown. Covers the residue
--       the post-call cannot see: tooltips built the legacy way (SetOwner + AddLine, no
--       ProcessInfo → no post-call of any type fires). Our own Scan button tooltip is one,
--       as are the AdvancedOptions / PriorityRotation / QualityOfLife text tooltips.
--
--  ⚠ WHY NOT tooltip:HookScript("OnTooltipCleared", …) — the mechanism this REPLACES.
--    That injected a tainted closure straight into GameTooltip's script dispatch with no
--    insulation. Blizzard insulates tooltip post-calls on purpose: TooltipDataHandler's
--    AddCall wraps an insecure registrant in forceinsecure() and every call is made via
--    securecallfunction (ProcessInfo is itself securecallfunction'd). A HookScript gets
--    none of that. Hooking a secure Blizzard frame's scripts is the same pattern removed
--    from PlayerFrame in v1.12.3; THIS instance survived that sweep only because the claim
--    was written as "the last place hooking a secure frame's MOUSE scripts", and
--    OnTooltipCleared is not a mouse script.
--    Surfaced by an ADDON_ACTION_FORBIDDEN on UseContainerItem() attributed to this module
--    (2026-08-04) which blocked using a quest-reward crafting-knowledge item until /reload.
--    ⚠ NOT PROVEN to have been the cause — the CreateFontString above also mutates a
--    secure frame from tainted code and the two armed together, so no observation could
--    separate them. This change removes the one that is a pattern we had already banned.
--
--    ✅ RESOLVED v1.17.4. This block used to list three surviving suspects in this file (the
--    owned fontstring, its anchor to GameTooltipTextLeftN, the WatchCoins ticker) and an
--    elimination test to run before touching them. The FORBIDDEN that motivated it was traced
--    to UI/SellStrip.lua calling SetPostItem and fixed there; a level-4 taint log afterwards
--    named nothing in this file. The three are recorded here only as the places to look FIRST
--    if a new blocked action ever names VeritasUI_AuctionHouse from a tooltip.
--    ⚠ Do not "fix" this by reverting to text coins in an AddLine. The owned fontstring
--    exists because the 12.0.7 native restyle was matched pixel-for-pixel over v1.7.15-17
--    with probe-verified values, and Blizzard's own money code CANNOT be used here (it does
--    arithmetic on a Secret Value inside instanced content — the v1.7.6 Delve crash, which
--    is the same class of place this FORBIDDEN was recorded).
--
--  ⚠ Do NOT "simplify" this back to a single driver: the post-call alone leaves stale
--    coins on legacy tooltips, and the poll alone shows them for up to one tick.
----------------------------------------------------------------
local watcher   -- C_Timer ticker, created on demand, cancelled when nothing is shown

-- True while the tooltip still legitimately displays the item we drew coins for. A legacy
-- text tooltip displays no item at all, which is what makes this a sufficient predicate:
-- item→item transitions are already handled synchronously by OnItemTooltip.
local function StillShowingAnItem(tooltip)
    if not tooltip:IsShown() then return false end
    if not (TooltipUtil and TooltipUtil.GetDisplayedItem) then return true end
    local ok, _, link = pcall(TooltipUtil.GetDisplayedItem, tooltip)
    return ok and link ~= nil
end

local function WatchCoins()
    if watcher then return end
    watcher = C_Timer.NewTicker(COIN_WATCH_RATE, function()
        local anyShown = false
        for tooltip, fs in pairs(coinFS) do
            if fs:IsShown() then
                if StillShowingAnItem(tooltip) then
                    anyShown = true
                else
                    fs:Hide()
                end
            end
        end
        if not anyShown and watcher then
            watcher:Cancel()
            watcher = nil
        end
    end)
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
    tooltip:AddLine(PRICE_PREFIX, HIGHLIGHT_FONT_COLOR:GetRGB())

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
    WatchCoins()
    return true
end

-- DIAGNOSTIC SEAM for /ah ttprobe. Exposes the EXACT price the tooltip render would use,
-- so a disagreement between the tooltip and /ah check can be localised to the lookup or to
-- the render instead of being argued about. Same reasoning as /ah browseprobe: the question
-- recurs and cannot be summoned on demand.
AH.Tooltip._BuildPriceData = BuildPriceData

-- LAST-RENDER RECORDER for /ah ttprobe. Records the link, key and price the tooltip path
-- ACTUALLY used on its most recent run, rather than letting a probe RECONSTRUCT them from a
-- shift-clicked link. The two are not the same input: a compound tooltip (a recipe that also
-- teaches an item, housing decor, a caged pet) displays more than one item name, and
-- TooltipUtil.GetDisplayedItem may resolve to an INNER item whose itemID differs from the one
-- the player shift-clicks. That difference is invisible to any reconstruction and is the
-- leading explanation for a tooltip and /ah check reporting different prices for "the same"
-- item. Records unconditionally; costs three table writes per priced tooltip.
local lastRender = {}
AH.Tooltip._LastRender = function() return lastRender end

local function AppendPriceForKey(tooltip, key)
    local price, extras = BuildPriceData(key)
    lastRender.key   = key
    lastRender.price = price
    lastRender.frame = tooltip and tooltip.GetName and tooltip:GetName() or "?"
    if not price then return end
    if not RenderCoinLine(tooltip, price) then
        -- Self-render path unavailable (no tooltip name/anchor) → plain text-coin line.
        local coins = AH.Money.Format(price) or tostring(price)
        tooltip:AddLine(PRICE_PREFIX .. "  " .. coins, HIGHLIGHT_FONT_COLOR:GetRGB())
    end
    if extras then tooltip:AddLine(extras) end
end

-- Append our line(s) to a tooltip for the given item link, if we have a price.
local function AppendPrice(tooltip, link)
    if not (AH.DB and link) then return end
    lastRender.link = link
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

-- Is the hovered item a bound instance? The tooltip data's GUID names the actual item under the
-- cursor (TooltipUtil.lua:9-21 resolves it first); C_Item.GetItemLocation(guid) turns it into a
-- location and C_Item.IsBound reads its bound state (ItemDocumentation.lua forever). No GUID, no
-- location, or any error -> not bound, so the price still shows.
local function IsBoundInstance(data, tooltip)
    local C = C_Item
    if not (C and C.GetItemLocation and C.IsBound) then return false end
    local guid = data and data.guid
    if not guid and tooltip and tooltip.GetPrimaryTooltipData then
        local okP, td = pcall(tooltip.GetPrimaryTooltipData, tooltip)
        if okP and type(td) == "table" then guid = td.guid end
    end
    if not guid then return false end
    local okL, loc = pcall(C.GetItemLocation, guid)
    if not (okL and loc) then return false end
    -- A merchant buyback item's GUID yields a location that is neither bag/slot nor equipment
    -- slot, and IsValid (C_Item.DoesItemExist, ItemLocation.lua:69) then throws "bad argument"
    -- (owner, 2026-11-12, hovering a buyback slot). Only a bag or equipment location is checked.
    if loc.HasAnyLocation and not loc:HasAnyLocation() then return false end
    local okV, valid = pcall(loc.IsValid, loc)
    if not (okV and valid) then return false end
    local okB, bound = pcall(C.IsBound, loc)
    return okB and bound == true
end

local function OnItemTooltip(tooltip, data)
    -- Only handle the shared GameTooltip + ItemRefTooltip family. Some internal
    -- tooltips (compare shopping, etc.) are children we don't want to touch.
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

    -- Our owned coin fontstring persists across hovers; hide it on EVERY rebuild so a
    -- non-priced item (where RenderCoinLine never runs) doesn't show stale coins from
    -- a previous priced hover. RenderCoinLine re-Shows it when there IS a price.
    local fs = coinFS[tooltip]
    if fs then fs:Hide() end

    -- Clear the per-pass outcome FIRST. Without this the recorder keeps the previous hover's
    -- key/price whenever this pass renders nothing (unpriced item, or gear whose link and id
    -- disagree), so /ah ttprobe would report a price that is not on screen -- and a test
    -- asserting "nothing rendered" would read the stale value and fail on correct code, which
    -- is exactly how this was found.
    lastRender.key, lastRender.price, lastRender.used = nil, nil, nil

    -- SOURCE CAPTURE for /ah ttprobe. All FOUR candidate identities are recorded before one
    -- is chosen, because a compound tooltip (this pattern teaches a decor item) can make them
    -- disagree, and picking the right source by reasoning is what produced the wrong answer
    -- twice. Measured 2026-08-29: hovering `Pattern: Stretched Snakeskin Rack` (275334) priced
    -- itemID 279346, the TAUGHT item -- a correct price for the wrong item.
    local dataLink = data and data.hyperlink
    lastRender.dataLink = dataLink
    lastRender.dataId   = data and data.id
    lastRender.primaryLink, lastRender.primaryId = nil, nil
    if tooltip.GetPrimaryTooltipData then
        local okP, td = pcall(tooltip.GetPrimaryTooltipData, tooltip)
        if okP and type(td) == "table" then
            lastRender.primaryLink = td.hyperlink
            lastRender.primaryId   = td.id
        end
    end
    lastRender.displayedLink, lastRender.displayedId = nil, nil
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local okD, _, dl, did = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if okD then
            lastRender.displayedLink = dl
            lastRender.displayedId   = did
        end
    end

    ----------------------------------------------------------------
    --  IDENTITY RESOLUTION -- read this before reordering anything.
    --
    --  ⚠ `data.hyperlink` CANNOT BE TRUSTED TO NAME THE HOVERED ITEM. On an item whose
    --  tooltip embeds another item -- a recipe/pattern that teaches something -- the data
    --  pipeline's `hyperlink` points at the TAUGHT item while `data.id` stays correct.
    --  MEASURED 2026-08-29 hovering `Pattern: Stretched Snakeskin Rack`:
    --      data.hyperlink      id=275334  link parses to 279346   <- Pattern id, WRONG link
    --      PrimaryTooltipData  id=275334  link parses to 279346   <- same
    --      GetDisplayedItem    id=275334  link parses to 275334   <- CORRECT
    --  v1.7.x-v1.17.1 preferred data.hyperlink, so the tooltip rendered a CORRECT price for
    --  the WRONG item (10000g1s, the decor item's price, on a pattern worth 5g). Silent, and
    --  invisible unless the inner item also happens to have a stored price.
    --
    --  WHY GetDisplayedItem IS RIGHT, from Blizzard's source rather than from the one
    --  measurement: TooltipUtil.lua:9-21 resolves GUID FIRST --
    --  `if tooltipData.guid then hyperlink = C_Item.GetItemLinkByGUID(tooltipData.guid)` --
    --  and only falls back to `tooltipData.hyperlink`. A GUID identifies the actual item
    --  instance under the cursor, so it cannot drift to an embedded item.
    --
    --  ⚠ THAT FALLBACK IS WHY THE ID CHECK BELOW EXISTS. With no GUID (a chat link, an
    --  ItemRefTooltip) GetDisplayedItem returns `tooltipData.hyperlink` -- the same untrusted
    --  string. So the link is VALIDATED against `data.id`, which was correct in every
    --  candidate measured, and a link that disagrees with it is discarded.
    --
    --  ⚠ THE CROSS-CHECK IS LOAD-BEARING; THE ORDERING IS NOT. Mutation-tested: swapping the
    --  two candidates back to data.hyperlink-first leaves the suite GREEN, because a lying
    --  link fails the id comparison and the loop moves on regardless of position. Do not
    --  "simplify" this by deleting the comparison and keeping the order -- that reinstates the
    --  bug in every no-GUID case while looking like the fix. The order only decides which of
    --  two ALREADY-VALID candidates wins, and GetDisplayedItem is first because a
    --  GUID-resolved link is the more specific identity.
    ----------------------------------------------------------------
    local authID = data and data.id
    local displayedLink = lastRender.displayedLink

    -- Battle-pet links are keyed by SPECIES and their data.id is the generic cage item, so
    -- the id check below must never touch them.
    local function IsPetLink(l)
        return type(l) == "string" and l:find("|Hbattlepet:", 1, true) ~= nil
    end

    local link, keyFromID
    if IsPetLink(displayedLink) then
        link, lastRender.used = displayedLink, "GetDisplayedItem (battlepet)"
    elseif IsPetLink(dataLink) then
        link, lastRender.used = dataLink, "data.hyperlink (battlepet)"
    elseif type(authID) == "number" and authID > 0 then
        -- Accept the first candidate whose OWN itemID matches the authoritative one.
        for _, pair in ipairs({ { displayedLink, "GetDisplayedItem" },
                               { dataLink, "data.hyperlink" } }) do
            local cand = pair[1]
            if type(cand) == "string" and tonumber(cand:match("|Hitem:(%d+)")) == authID then
                link, lastRender.used = cand, pair[2]
                break
            end
        end
        if not link then
            -- No link agrees with data.id. Key off the id alone rather than pricing whatever
            -- the wrong link points at. MakeKeyFromItemID refuses gear (its key needs an item
            -- level the id cannot supply), so gear in this state shows NO line -- which is the
            -- correct outcome: silence beats a confident wrong price.
            keyFromID, lastRender.used = authID, "data.id (no link agreed)"
        end
    else
        link = displayedLink or dataLink
        lastRender.used = displayedLink and "GetDisplayedItem (no id)" or "data.hyperlink (no id)"
    end

    -- A bound item (soulbound, warbound, Battle.net bound) can never go on the Auction House, so it
    -- gets no price line: a price there reads as "you can sell this". Only an item the player HOLDS
    -- has a bound state; a link (chat, dungeon journal) has no GUID and keeps its price.
    if not IsPetLink(link) and IsBoundInstance(data, tooltip) then
        lastRender.used = "bound (no line)"
        return
    end

    if keyFromID then
        local k = AH.DB and AH.DB.MakeKeyFromItemID(keyFromID)
        lastRender.link = "id:" .. keyFromID
        if k then pcall(AppendPriceForKey, tooltip, k) end
        return
    end
    if not link then return end

    -- Read-only DB lookup; pcall-guarded so a malformed link never errors a tooltip.
    pcall(AppendPrice, tooltip, link)
end

-- AllTypes tooltip post-call: hide our coins on EVERY data-pipeline tooltip build, whatever
-- the content type. ORDERING IS VERIFIED IN BLIZZARD SOURCE (TooltipDataHandler's
-- ProcessInsecureCalls dispatches the AllTypes list BEFORE the keyType list), so for a priced
-- item this hide always precedes OnItemTooltip's re-Show in the same synchronous rebuild —
-- no flicker. Scoped implicitly to tooltips we have decorated: no coinFS entry, no work.
local function OnAnyTooltip(tooltip)
    local fs = coinFS[tooltip]
    if fs then fs:Hide() end
end

----------------------------------------------------------------
--  Battle-pet tooltips
--
--  VERIFIED (against another auction AddOn's clean-room reference + Blizzard API usage):
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
    petTooltip:AddLine("Auction:  " .. coins, HIGHLIGHT_FONT_COLOR:GetRGB())
    if extras then petTooltip:AddLine(extras) end
end

local function HookBattlePetTooltips()
    -- Caged pet hovered in bags / AH / anywhere → BattlePetTooltip.
    if type(BattlePetToolTip_Show) == "function" then
        hooksecurefunc("BattlePetToolTip_Show", function(speciesID)
            pcall(AppendPetPrice, BattlePetTooltip, speciesID)
        end)
    elseif VUI.debug then
        VUI.Print(AH.TAG, VUI.COL.RED .. "BattlePetToolTip_Show missing|r — pet prices unavailable.")
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
            VUI.Print(AH.TAG, VUI.COL.RED .. "Tooltip hook unavailable|r (API missing).")
        end
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    -- Existence-guarded: if AllTypes is ever absent we still render prices correctly and
    -- WatchCoins remains as the (one-tick-slower) hide driver, so this degrades, not breaks.
    if TooltipDataProcessor.AllTypes then
        TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, OnAnyTooltip)
    end
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
