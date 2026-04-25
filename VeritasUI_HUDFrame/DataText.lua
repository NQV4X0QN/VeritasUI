-- VeritasUI_HUDFrame / DataText.lua
-- Dynamic bar builder and update ticker.
-- Reads HUF.DataPoints and HUF.db.layout to populate the three bars.

local _, HUF = ...

local _G     = _G
local ipairs = ipairs
local pairs  = pairs
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
--  CreateInteractiveSlot — attaches click/hover handlers and a
--  HIGHLIGHT texture to a FontString, returning the click frame
--  (or nil if the data point has no interactive handlers).
--  Extracted so BuildBar and BuildZone can share the same wiring.
----------------------------------------------------------------
local function CreateInteractiveSlot(barFrame, fs, dp)
    if not (dp and (dp.onClick or dp.onEnter)) then return nil end

    local clickFrame = CreateFrame("Button", nil, barFrame)
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

    return clickFrame
end

----------------------------------------------------------------
--  BuildZones (fullwidth bars only)
--  Distributes up to 4 FontStrings per zone (12 total) across the
--  entire bar width using a SINGLE uniform stride so every label's
--  left edge sits at an equidistant x-coordinate regardless of
--  value content width.
--
--  Layout math:
--    PADDING       = 20px margin at left/right screen edges
--    LAST_RESERVE  = 180px reserved after position 12 for the
--                    rightmost label's value text to expand into
--                    before the screen edge
--    N             = 12 total slot positions (4 per zone × 3 zones)
--    step          = (W - 2*PADDING - LAST_RESERVE) / (N - 1)
--
--    Position p's LEFT = PADDING + (p - 1) * step
--
--  Zone offsets: LEFT → positions 1..4, CENTER → 5..8, RIGHT → 9..12.
--  Skipped slots in a zone leave visible gaps at their position,
--  which preserves the left/center/right grouping semantics when
--  zones aren't fully populated.
--
--  Every FontString is LEFT-justified so its ANCHOR is the label's
--  left edge — that's what guarantees the word spacing stays uniform
--  regardless of how long "Silvermoon City" or "909,829g" render.
----------------------------------------------------------------
local ZONE_EDGE_PADDING = 20     -- px margin at each bar edge
local ZONE_LAST_RESERVE = 180    -- px reserved for last label's value text
local ZONE_MAX_PER_ZONE = 4
local ZONE_TOTAL_SLOTS  = ZONE_MAX_PER_ZONE * 3

local function BuildZones(barFrame, zones, mountPoint, yOffset)
    if not zones then return end
    mountPoint = mountPoint or "BOTTOM"
    yOffset    = yOffset    or 0

    local w = barFrame:GetWidth()
    if not w or w <= 0 then w = UIParent:GetWidth() end

    local usable = w - 2 * ZONE_EDGE_PADDING - ZONE_LAST_RESERVE
    local step   = usable / (ZONE_TOTAL_SLOTS - 1)

    local anchor = (mountPoint == "BOTTOM") and "BOTTOMLEFT" or "LEFT"

    local zoneOrder = {
        { list = zones.left   or {}, offset = 0 },
        { list = zones.center or {}, offset = ZONE_MAX_PER_ZONE },
        { list = zones.right  or {}, offset = ZONE_MAX_PER_ZONE * 2 },
    }

    for _, z in ipairs(zoneOrder) do
        for i, key in ipairs(z.list) do
            if key and key ~= "" and i <= ZONE_MAX_PER_ZONE then
                local pos  = z.offset + i        -- 1..12
                local xOff = ZONE_EDGE_PADDING + (pos - 1) * step

                local fs = barFrame:CreateFontString(nil, "OVERLAY", nil, 7)
                fs:SetFont("Fonts\\FRIZQT__.TTF", 11)
                fs:SetJustifyH("LEFT")
                fs:SetPoint(anchor, barFrame, anchor, xOff, yOffset)
                fs:Show()

                local dp = HUF.DataPoints and HUF.DataPoints[key]
                local clickFrame = CreateInteractiveSlot(barFrame, fs, dp)

                barFrame._vuiSlots[#barFrame._vuiSlots + 1] =
                    { fs = fs, key = key, clickFrame = clickFrame }
            end
        end
    end
end

----------------------------------------------------------------
--  BuildBar
--  Creates FontStrings for one bar. Two rendering modes:
--    normal:    slotKeys distributed evenly across barFrame:GetWidth()
--    fullwidth: zones table with { left, center, right } lists —
--               renders via BuildZone instead of the normal loop.
--  Old FontStrings are hidden but not freed (WoW has no GC for
--  widget objects).
----------------------------------------------------------------
-- mountPoint / yOffset control where FontStrings anchor on the frame.
-- Left/right bars pass "BOTTOM", 8 so text sits in the bottom chrome strip.
-- Panel bar passes "BOTTOM", -7 so text sits on the chrome strip.
local function BuildBar(barFrame, slotKeys, mountPoint, yOffset, zones)
    if not barFrame then return end
    mountPoint = mountPoint or "CENTER"
    yOffset    = yOffset    or 0

    -- Hide previous FontStrings and detach their click frames.
    -- WoW has no widget GC, so we hide + unpoint + unhook rather than
    -- trying to free. If we skipped the click frames, stale HIGHLIGHT
    -- textures from prior layouts would stack and produce multiple
    -- hover boxes over the same visual slot.
    if barFrame._vuiSlots then
        for _, entry in ipairs(barFrame._vuiSlots) do
            entry.fs:SetText("")
            entry.fs:Hide()
            if entry.clickFrame then
                entry.clickFrame:Hide()
                entry.clickFrame:ClearAllPoints()
                entry.clickFrame:SetScript("OnEnter", nil)
                entry.clickFrame:SetScript("OnLeave", nil)
                entry.clickFrame:SetScript("OnClick", nil)
            end
        end
    end
    barFrame._vuiSlots = {}

    if zones then
        -- Fullwidth mode: unified 12-position stride across the whole bar.
        BuildZones(barFrame, zones, mountPoint, yOffset)
        return
    end

    -- Normal mode: single slot list distributed evenly across width.
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
        local clickFrame = CreateInteractiveSlot(barFrame, fs, dp)

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
                local mode = (db.panelBars and db.panelBars[i]
                              and db.panelBars[i].mode) or "normal"
                if mode == "fullwidth" then
                    local zones = db.layout.panelBarZones
                                  and db.layout.panelBarZones[i]
                    BuildBar(HUF.panelBars[i], nil, "BOTTOM", -7, zones)
                else
                    BuildBar(HUF.panelBars[i], db.layout.panelBars[i], "BOTTOM", -7)
                end
            end
        end
    end

    UpdateAllBars()

    -- Refresh settings panel dropdowns if the panel exists
    if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
end

----------------------------------------------------------------
--  Event-driven refresh
--
--  DataPoints can declare an `events` array. At PLAYER_LOGIN we
--  walk the registry once, collect the union of all listed events,
--  and register them on a single frame.
--
--  UNIT_EVENTS members use RegisterUnitEvent("player") so the C
--  engine filters non-player aura traffic before it reaches Lua.
--
--  A pending flag + C_Timer.After(0) coalesces a flurry of events
--  (e.g. multiple UNIT_AURA fires during a Meta cast) into a single
--  UpdateAllBars() call on the next frame.
----------------------------------------------------------------
local UNIT_EVENTS = {
    UNIT_AURA = true,
}

local _eventPending = false

local function RegisterDataPointEvents()
    local eventSet = {}
    for _, dp in pairs(HUF.DataPoints) do
        if dp.events then
            for _, ev in ipairs(dp.events) do
                eventSet[ev] = true
            end
        end
    end

    local evFrame = CreateFrame("Frame")
    evFrame:SetScript("OnEvent", function()
        if not _eventPending then
            _eventPending = true
            C_Timer.After(0, function()
                _eventPending = false
                UpdateAllBars()
            end)
        end
    end)

    for ev in pairs(eventSet) do
        if UNIT_EVENTS[ev] then
            evFrame:RegisterUnitEvent(ev, "player")
        else
            evFrame:RegisterEvent(ev)
        end
    end
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
    RegisterDataPointEvents()

    -- Start the update ticker
    local CFG = HUF.Config
    local interval = CFG and CFG.TICKER_INTERVAL or 2
    ticker = C_Timer.NewTicker(interval, UpdateAllBars)
end)
