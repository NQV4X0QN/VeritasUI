-- VeritasUI_HUDFrame / DataText.lua
-- Dynamic bar builder and update ticker.
-- Reads HUF.DataPoints and HUF.db.layout to populate the three bars.

local _, HUF = ...

local _G     = _G
local ipairs = ipairs
local format = string.format
local C_Timer = C_Timer

local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Layout defaults (applied when db.layout is absent)
----------------------------------------------------------------
local DEFAULT_LAYOUT = {
    leftBar  = { "memory", "durability", "gold" },
    rightBar = { "guild",  "friends",    "zone" },
    panelBars = {
        [1] = { "haste", "mastery",      "crit",    "armor",      "ilvl"  },
        [2] = { "fps",   "latencyWorld", "memory",  "durability", "gold"  },
        [3] = { "spec",  "zone",         "friends", "guild",      "empty" },
    },
}

local ticker

----------------------------------------------------------------
--  FormatSlot — applies label/value/warn colors to one segment
----------------------------------------------------------------
local function FormatSlot(dp, rawValue)
    if rawValue == "" then return "" end
    local col
    if dp.tierColor then
        col = dp.tierColor() or "|cffffffff"
    else
        local warn = dp.warnThreshold and dp.warnThreshold()
        col = (warn and dp.warnColor) or "|cffffffff"
    end
    return "|cffffd100" .. dp.label .. ":|r " .. col .. rawValue .. "|r"
end

----------------------------------------------------------------
--  BuildBar
--  Creates one FontString per slot, distributed evenly across
--  the bar's width.  Old FontStrings are hidden but not freed
--  (WoW has no GC for widget objects).
----------------------------------------------------------------
-- mountPoint / yOffset control where FontStrings anchor on the frame.
-- Left/right bars pass "BOTTOM", 8 so text sits in the bottom chrome strip.
-- Panel bar passes "BOTTOM", -7 so text sits on the chrome strip.
local function BuildBar(barFrame, slotKeys, mountPoint, yOffset)
    if not barFrame then return end
    mountPoint = mountPoint or "CENTER"
    yOffset    = yOffset    or 0

    -- Hide previous FontStrings
    if barFrame._vuiSlots then
        for _, entry in ipairs(barFrame._vuiSlots) do
            entry.fs:SetText("")
            entry.fs:Hide()
        end
    end
    barFrame._vuiSlots = {}

    if not slotKeys or #slotKeys == 0 then return end

    local n = #slotKeys
    local fsParent = barFrame
    local w = barFrame:GetWidth()
    if not w or w <= 0 then w = 380 end
    for i, key in ipairs(slotKeys) do
        local fs = fsParent:CreateFontString(nil, "OVERLAY", nil, 7)
        fs:SetFont("Fonts\\FRIZQT__.TTF", 11)
        fs:SetJustifyH("CENTER")
        local xOff = w * (i - 0.5) / n - w * 0.5
        fs:SetPoint(mountPoint, fsParent, mountPoint, xOff, yOffset)
        fs:Show()

        local dp = HUF.DataPoints and HUF.DataPoints[key]
        local clickFrame
        if dp and (dp.onClick or dp.onEnter) then
            clickFrame = CreateFrame("Button", nil, barFrame)
            clickFrame:SetPoint("CENTER", fs, "CENTER", 0, 0)
            clickFrame:RegisterForClicks("AnyUp")
            clickFrame:SetSize(1, 1)

            local hl = clickFrame:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(clickFrame)
            hl:SetColorTexture(1, 1, 1, 0.15)
            hl:SetBlendMode("ADD")

            if dp.onClick then
                clickFrame:SetScript("OnClick", function(_, button)
                    dp.onClick(button)
                end)
            end

            clickFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(dp.label, 1, 0.82, 0)
                if dp.onEnter then dp.onEnter(GameTooltip) end
                if dp.onClick then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff40ff40Click to " ..
                        (dp.clickHint or "interact") .. "|r")
                end
                GameTooltip:Show()
            end)
            clickFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        barFrame._vuiSlots[i] = { fs = fs, key = key, clickFrame = clickFrame }
    end
end

HUF.BuildBar = BuildBar

----------------------------------------------------------------
--  UpdateBar — refreshes one bar's FontStrings from the registry
----------------------------------------------------------------
local function UpdateBar(barFrame)
    if not barFrame or not barFrame._vuiSlots then return end
    local dp = HUF.DataPoints
    if not dp then return end

    for _, entry in ipairs(barFrame._vuiSlots) do
        local point = dp[entry.key]
        if point then
            local val = point.getValue()
            entry.fs:SetText(val ~= "" and FormatSlot(point, val) or "")
            if entry.clickFrame then
                local tw, th = entry.fs:GetStringWidth(), entry.fs:GetStringHeight()
                if tw and tw > 0 then
                    entry.clickFrame:SetSize(tw + 4, (th or 14) + 4)
                end
            end
        else
            entry.fs:SetText("")
        end
    end
end

local function UpdateAllBars()
    local enabled = HUF.db and HUF.db.enabled ~= false
    if not enabled then return end
    UpdateBar(HUF.leftAnchor)
    UpdateBar(HUF.rightAnchor)
    if HUF.panelBars then
        for i = 1, 3 do UpdateBar(HUF.panelBars[i]) end
    end
end

----------------------------------------------------------------
--  RebuildAllBars
--  Ensures db.layout has defaults, rebuilds FontStrings, updates.
--  Called on PLAYER_LOGIN, after dropdown changes, and /hud set.
----------------------------------------------------------------
function HUF.RebuildAllBars()
    local db = HUF.db
    if not db then return end

    if not db.layout then db.layout = {} end

    -- Left / right bars: copy defaults only if absent
    if not db.layout.leftBar then
        db.layout.leftBar = {}
        for i, v in ipairs(DEFAULT_LAYOUT.leftBar) do db.layout.leftBar[i] = v end
    end
    if not db.layout.rightBar then
        db.layout.rightBar = {}
        for i, v in ipairs(DEFAULT_LAYOUT.rightBar) do db.layout.rightBar[i] = v end
    end

    -- Panel bars (3): each index copies defaults only if absent
    if not db.layout.panelBars then db.layout.panelBars = {} end
    for i = 1, 3 do
        if not db.layout.panelBars[i] then
            db.layout.panelBars[i] = {}
            for k, v in ipairs(DEFAULT_LAYOUT.panelBars[i]) do
                db.layout.panelBars[i][k] = v
            end
        end
    end

    BuildBar(HUF.leftAnchor,  db.layout.leftBar,  "BOTTOM", 8)
    BuildBar(HUF.rightAnchor, db.layout.rightBar, "BOTTOM", 8)
    if HUF.panelBars then
        for i = 1, 3 do
            if HUF.panelBars[i] then
                BuildBar(HUF.panelBars[i], db.layout.panelBars[i], "BOTTOM", -7)
            end
        end
    end

    UpdateAllBars()

    -- Refresh settings panel dropdowns if the panel exists
    if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
end

----------------------------------------------------------------
--  PLAYER_LOGIN — start after Core.lua's handler creates frames
----------------------------------------------------------------
local dtFrame = CreateFrame("Frame")
dtFrame:RegisterEvent("PLAYER_LOGIN")
dtFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Guard: Core.lua must have created the frames first
    if not HUF.leftAnchor or not HUF.rightAnchor or not HUF.panelBars then
        VUI.Print("HUD Frame", "|cFFFF4444DataText: frames not ready. Try /reload.|r")
        return
    end

    HUF.RebuildAllBars()

    -- Start the update ticker
    local CFG = HUF.Config
    local interval = CFG and CFG.TICKER_INTERVAL or 2
    ticker = C_Timer.NewTicker(interval, UpdateAllBars)
end)
