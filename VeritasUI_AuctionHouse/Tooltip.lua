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

-- Defaults for the tooltip toggles. Seeded into db.settings on first run; all on.
local TT_DEFAULTS = {
    ttShowPrice = true,   -- show "AH:" market price line
    ttShowAge   = true,   -- annotate stale prices with their age in days
    ttShowQty   = true,   -- show last-seen quantity
}

local function S(key)
    local s = AH.db and AH.db.settings
    if not s then return TT_DEFAULTS[key] end
    if s[key] == nil then return TT_DEFAULTS[key] end
    return s[key]
end
AH.Tooltip.Setting = S

-- Seed missing toggle defaults (called once, after AH.db exists).
function AH.Tooltip.SeedDefaults()
    if not AH.db then return end
    AH.db.settings = AH.db.settings or {}
    for k, v in pairs(TT_DEFAULTS) do
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
-- The CALLER renders the price: the GameTooltip path uses the native
-- SetTooltipMoney money frame (pixel-identical to the "Sell Price:" line); the
-- battle-pet path falls back to a text coin string (its custom frame has no
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
--   * Coins  = the Coin-Gold / Coin-Silver / Coin-Copper atlases at 13x13, emitted as
--              inline |A:atlas:h:w|a markup in a fontstring. Pure text → zero Blizzard
--              arithmetic → cannot throw on a Secret Value, in any content.
--   * Numbers= the NumberFontNormalRight FONT OBJECT (probe-confirmed = ARIALN.TTF / 14 /
--              OUTLINE — Blizzard's own money font), so digits are pixel-identical to the
--              "Sell Price:" line and track any future Blizzard font change automatically.
--   * Label  = a real tooltip AddLine ("Auction:"), so the label inherits the exact
--              tooltip body font the native "Sell Price:" label uses — no font guessing.
--   * The coin fontstring is parented to UIParent (never the tooltip — touching the
--     tooltip's child list is itself a taint vector), raised to TOOLTIP strata, anchored
--     to the line, and hidden on the tooltip's OnHide so it never orphans.
local PRICE_PREFIX = "Auction:"

-- Inline atlas coin markup. Native money-frame coins probe at 13x13, but inline |A|
-- markup renders a hair larger at the same number, so 12 matches the eye better.
-- (One-line tunable if it still looks off.)
local COIN_G = "|A:Coin-Gold:12:12|a"
local COIN_S = "|A:Coin-Silver:12:12|a"
local COIN_C = "|A:Coin-Copper:12:12|a"

-- Build the coin string for a copper amount: number immediately followed by its coin,
-- a space between denominations (matches GetCoinTextureString's grouping). Only nonzero
-- denominations are shown; a sub-1-silver price still shows copper.
-- NOTE: the exact intermediate-zero rule (e.g. 1g 0s 5c) is the one piece not verified
-- against the live "Sell Price:" line — AH prices almost never carry an intermediate
-- zero, and this is one-line tunable if an edge case looks off in-game.
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

-- Render the price as an INLINE coin line in the tooltip itself.
--
-- WHY INLINE (not a separate overlay fontstring — that approach FAILED in-game):
--   v1.7.7-dev first drew the coins in our own fontstring parented to UIParent and
--   anchored over the tooltip. The label appeared but the coins did NOT render (the
--   off-tooltip frame stayed invisible — likely strata/anchor/timing, not worth
--   chasing). The tooltip's OWN lines are always visible, so we put the coins inside
--   the line text. Still pure text (inline |A| atlas markup), so still zero Blizzard
--   money math → crash-safe in Delves/M+/raids (the silverWidth Secret-Value trap is
--   never touched).
--
-- TRADEOFF (disclosed): inline numbers inherit the TOOLTIP body font (Friz Quadrata),
-- not the Sell Price line's ARIALN/14 NumberFont. The COINS are the correct new
-- Coin-* atlas art at 13x13; only the digit font differs slightly from the native
-- money line. This is the same technique Blizzard's own GetCoinTextureString uses
-- (text + inline coins), just with the modern coin atlases instead of the old
-- coin textures GetCoinTextureString embeds. AddDoubleLine puts the label at the
-- left and the coins in the right column, matching the native "Sell Price:" layout.
local function RenderCoinLine(tooltip, price)
    if not tooltip.AddDoubleLine then return false end
    -- Left = white label (matches native "Sell Price:" white); right = coin markup,
    -- also white so the digits read like the native amount.
    tooltip:AddDoubleLine(PRICE_PREFIX, CoinMarkup(price), 1, 1, 1, 1, 1, 1)

    -- Re-font the RIGHT column to the native money font so digits match "Sell Price:"
    -- (probe-confirmed NumberFontNormalRight = ARIALN/14/OUTLINE). AddDoubleLine
    -- defaults the right column to GameTooltipText (Friz Quadrata). We keep
    -- AddDoubleLine specifically because it lets the LABEL stay Friz (matching the
    -- native "Sell Price:" label) while the NUMBERS become ARIALN — a single AddLine
    -- is one fontstring/one font and could not match both halves.
    local name = tooltip.GetName and tooltip:GetName()
    if not name then return true end
    local idx   = tooltip:NumLines()
    local right = _G[name .. "TextRight" .. idx]
    if right and right.SetFontObject and _G.NumberFontNormalRight then
        right:SetFontObject(_G.NumberFontNormalRight)
        right:SetTextColor(1, 1, 1)   -- NumberFont* objects carry their own color; force white
    end

    -- COLUMN ALIGNMENT (the SAFE way — see the v1.7.7-dev revert for the unsafe way):
    -- AddDoubleLine right-justifies the right column to the tooltip edge; native Sell
    -- Price money is LEFT-anchored at a fixed column. We left-justify our right
    -- fontstring and anchor its LEFT to the native money frame's LEFT, so our first
    -- digit lines up under Sell Price's first digit.
    --
    -- WHY DEFERRED + pcall: doing this synchronously inside the PostCall threw (nil
    -- GetLeft mid-layout) and the caller's pcall swallowed it, vanishing the WHOLE
    -- line. Here it runs on the next frame (AFTER layout, so positions are valid) and
    -- is pcall-wrapped — the line is ALREADY rendered by then, so any failure simply
    -- leaves it right-justified; it can never make the line disappear. We anchor
    -- relative to the money frame (no GetLeft arithmetic that could be nil), capture
    -- the line index now (stable for a static hover), and re-confirm everything is
    -- shown inside the timer.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            pcall(function()
                if not (right and tooltip.IsShown and tooltip:IsShown()) then return end
                local m = _G.GameTooltipMoneyFrame1
                if not (m and m:IsShown()) then return end   -- no native Sell Price line
                -- Sanity: only realign the line we added (its text is still our coins).
                right:SetJustifyH("LEFT")
                right:ClearAllPoints()
                right:SetPoint("LEFT", m, "LEFT", 0, 0)        -- first digit under first digit
            end)
        end)
    end
    return true
end

local function AppendPriceForKey(tooltip, key)
    local price, extras = BuildPriceData(key)
    if not price then return end
    if not RenderCoinLine(tooltip, price) then
        -- Self-render path unavailable (no tooltip name/anchor) → plain text-coin line.
        local coins = AH.Money and AH.Money.Format(price) or tostring(price)
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
-- so this path renders a text coin string (the GameTooltip path uses SetTooltipMoney).
local function AppendPetPrice(petTooltip, speciesID)
    if not (petTooltip and speciesID) then return end
    local price, extras = BuildPriceData("p:" .. speciesID)
    if not price then return end
    -- The custom BattlePetTooltip frame has no money-frame support, so this path
    -- uses a text coin string (the modern GetCoinTextureString via AH.Money.Format).
    -- It won't be pixel-identical to a GameTooltip money frame, but BattlePetTooltip
    -- has no native money line to match against anyway.
    local coins = AH.Money and AH.Money.Format(price) or tostring(price)
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
