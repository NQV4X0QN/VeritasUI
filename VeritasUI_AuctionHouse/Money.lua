-- VeritasUI_AuctionHouse / Money.lua
-- Copper-amount formatting and AH price rounding helpers.
--
-- NOTE (design §2.1): AH money values are plain Lua copper integers, NOT
-- "Secret Values". This module is a convenience/consistency layer for display
-- and rounding — it is NOT a taint boundary and does no Secret handling.

local ADDON_NAME, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local floor = math.floor
local ceil  = math.ceil

AH.Money = {}

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD   = 10000

-- Break a copper amount into (gold, silver, copper) integers.
function AH.Money.Breakdown(copper)
    copper = floor(tonumber(copper) or 0)
    local g = floor(copper / COPPER_PER_GOLD)
    local s = floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
    local c = copper % COPPER_PER_SILVER
    return g, s, c
end

-- Blizzard-style money string WITH coin icons (matches MoneyFrame display
-- pixel-for-pixel). Uses Blizzard's own GetCoinTextureString so it is
-- indistinguishable from the default UI. Falls back to plain text if the
-- global is unavailable.
function AH.Money.Format(copper)
    copper = floor(tonumber(copper) or 0)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    return AH.Money.FormatText(copper)
end

-- Plain-text money string ("12g 34s 56c"), no icons. Leading zero parts are
-- omitted; copper is always shown so 0 renders as "0c".
function AH.Money.FormatText(copper)
    local g, s, c = AH.Money.Breakdown(copper)
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 or g > 0 then parts[#parts + 1] = s .. "s" end
    parts[#parts + 1] = c .. "c"
    return table.concat(parts, " ")
end

-- Mirror of Blizzard's AuctionHouseUtil.SanitizeAuctionHousePrice (design §2.1,
-- verified at Blizzard_AuctionHouseUtil.lua:603-608): round a raw price UP to a
-- valid AH price. On realms without copper support, round up to the nearest
-- silver; otherwise round up to the nearest copper.
--
-- SupportsCopperValues is only meaningful with the AH open; we pcall it and
-- default to "copper supported" (ceil) when it's unavailable, which is the
-- safe, lossless choice.
function AH.Money.SanitizePrice(raw)
    raw = tonumber(raw) or 0
    local supportsCopper = true
    if C_AuctionHouse and C_AuctionHouse.SupportsCopperValues then
        local ok, v = pcall(C_AuctionHouse.SupportsCopperValues)
        if ok then supportsCopper = v end
    end
    if not supportsCopper then
        return ceil(raw / COPPER_PER_SILVER) * COPPER_PER_SILVER
    end
    return ceil(raw)
end
