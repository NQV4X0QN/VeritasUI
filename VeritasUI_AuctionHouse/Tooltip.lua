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

-- GameTooltip path: render the price through a MoneyFrame WE OWN.
--
-- WHY NOT SetTooltipMoney (the v1.7.2 approach — REMOVED, it crashed):
--   SetTooltipMoney reuses Blizzard's pooled GameTooltipMoneyFrame. Calling it from
--   our insecure context taints that shared pool; Blizzard's OWN "Sell Price:" render
--   then runs through the tainted pool and throws doing secret-value arithmetic
--   (MoneyFrame.lua:340, "secret number value … tainted by VeritasUI_AuctionHouse").
--   Item sell-price money IS a Secret Value in Midnight. Our DB price is a plain
--   integer, so OUR frame never does secret arithmetic and is crash-safe even when
--   tainted — but we must never touch Blizzard's pool. See SKILL.md Known Landmines.
--
-- HOW THIS STAYS CLEAN:
--   * Our own MoneyFrame (TooltipMoneyFrameTemplate — verified 12.0.5: valid + has a
--     PrefixText region) gives coin glyphs pixel-identical to the Sell Price line.
--   * Parented to UIParent, NOT the tooltip, so we never modify the tooltip's child
--     list (another taint vector). Anchored to our blank line, raised to TOOLTIP
--     strata, and hidden on tooltip OnHide so it never orphans.
--   * NAMED, because MoneyFrame_Update may resolve its coin-button children by
--     _G[name.."GoldButton"]; an anonymous frame could break.
--   * STATIC type fed our plain-integer price (never player money, never a Secret).
--   * pcall-guarded with a text-coin fallback (the week-stable pre-1.7.2 rendering)
--     so any API drift degrades gracefully instead of crashing.
local PRICE_PREFIX = "Auction:  "   -- trailing spaces tune the coin column under Sell Price

local moneyFrames = {}   -- [tooltip] = our private MoneyFrame
local mfCount = 0

local function GetMoneyFrame(tooltip)
    local mf = moneyFrames[tooltip]
    if mf then return mf end
    mfCount = mfCount + 1
    mf = CreateFrame("Frame", "VUIAHTooltipMoney" .. mfCount, UIParent, "TooltipMoneyFrameTemplate")
    mf:SetFrameStrata("TOOLTIP")
    mf:SetFrameLevel(1000)
    -- STATIC so it shows OUR amount, not the player's money (default money type).
    if MoneyFrame_SetType then
        MoneyFrame_SetType(mf, "STATIC")
    elseif MoneyTypeInfo then
        mf.info = MoneyTypeInfo.STATIC
        mf.moneyType = "STATIC"
    end
    moneyFrames[tooltip] = mf
    -- Hide with the tooltip so the frame never lingers over empty screen (it is
    -- parented to UIParent, so it won't auto-hide with the tooltip).
    tooltip:HookScript("OnHide", function() mf:Hide() end)
    return mf
end

-- Shift our money frame so OUR coin block lines up under the native "Sell Price:"
-- coin block. "Auction:" is narrower than "Sell Price:", so a plain left-anchor leaves
-- our coins slightly left; we read the native coin's screen-x and offset to match
-- (self-correcting across any font/value width — no brittle trailing-space tuning).
--
-- ALIGN THE LEFT EDGE OF EACH BLOCK (each line's leftmost VISIBLE coin), NOT a shared
-- denomination. A money frame hides zero denominations, so the two lines often carry
-- different coins (Sell 57s vs. Auction 2g79s). Forcing silver-under-silver there
-- shoved the gold-bearing line's gold out past the tooltip border. Aligning leftmost-
-- to-leftmost instead makes both number sequences START at the same column and stay
-- in-bounds: same-denomination lines still align coin-for-coin (gold↔gold, silver↔
-- silver — the perfect cases); mismatched lines align block-left (best achievable —
-- there's no native gold coin for our gold to stack under). GetLeft() on a HIDDEN
-- button is garbage, so we only ever read a shown button.
local COIN_BUTTONS = { "GoldButton", "SilverButton", "CopperButton" }
local function FirstVisibleCoin(frame)
    for _, denom in ipairs(COIN_BUTTONS) do
        local b = frame[denom]
        if b and b:IsShown() then return b end
    end
end
local function AlignCoinsToNative(mf)
    local native = _G.GameTooltipMoneyFrame1
    if not (native and native:IsShown()) then return end
    local nb, mb = FirstVisibleCoin(native), FirstVisibleCoin(mf)
    if not (nb and mb) then return end
    local nx, mx = nb:GetLeft(), mb:GetLeft()
    if not (nx and mx) then return end
    local p, rel, rp, x, y = mf:GetPoint(1)
    if p then mf:SetPoint(p, rel, rp, (x or 0) + (nx - mx), y or 0) end
end

-- Render the price as a native money line. Returns true on success; false → caller
-- falls back to text coins.
--
-- ORDERING (v1.7.x bugfix diagnostic): the fallible / taint-sensitive money work runs
-- BEFORE we mutate the tooltip. A tooltip line can never be retracted, so if the money
-- render throws we must NOT have already added the blank reserve line — otherwise it
-- orphans as a visible gap above the text fallback ("space between Auction and Sell
-- Price"). Update the frame first; only reserve+overlay the row once it has succeeded.
local function RenderMoneyLine(tooltip, price)
    local name = tooltip.GetName and tooltip:GetName()
    if not name then return false end

    local mf = GetMoneyFrame(tooltip)

    -- Fallible work FIRST — no tooltip mutation yet. Re-assert STATIC each render in
    -- case the cached frame's money type got clobbered by a PLAYER_MONEY/zone event
    -- (the template registers for PLAYER_MONEY in its OnLoad). Capture the error so a
    -- /run VeritasUI.debug=true repro surfaces the real cause instead of swallowing it.
    local ok, err = pcall(function()
        if MoneyFrame_SetType then MoneyFrame_SetType(mf, "STATIC") end
        if mf.PrefixText then mf.PrefixText:SetText(PRICE_PREFIX) end
        MoneyFrame_Update(mf, price)               -- our plain-integer price (STATIC)
    end)
    if not ok then
        if VUI.debug then
            VUI.Print(AH.TAG, "|cFFFF4444money render failed|r: " .. tostring(err))
        end
        return false
    end

    -- Frame is valid and updated — now reserve the row and overlay our coins onto it.
    tooltip:AddLine(" ")                            -- blank line reserves the row
    local left = _G[name .. "TextLeft" .. tooltip:NumLines()]
    if not left then return false end
    mf:ClearAllPoints()
    mf:SetPoint("LEFT", left, "LEFT", 0, 0)
    mf:Show()
    AlignCoinsToNative(mf)                          -- nudge coins under Sell Price coins
    return true
end

local function AppendPriceForKey(tooltip, key)
    local price, extras = BuildPriceData(key)
    if not price then return end
    if not RenderMoneyLine(tooltip, price) then
        -- Money-frame path unavailable/failed → week-stable text coins.
        local coins = AH.Money and AH.Money.Format(price) or tostring(price)
        tooltip:AddLine(PRICE_PREFIX .. coins, 1, 1, 1)
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
