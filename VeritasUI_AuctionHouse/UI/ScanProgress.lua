-- VeritasUI_AuctionHouse / UI/ScanProgress.lua
-- A small, tab-independent scan-progress readout mounted in the empty band to the
-- RIGHT of the AH money frame (bottom-left). Visible on Buy / Sell / Auctions alike.
--
-- WHY THIS FILE EXISTS, AND WHY IT TOUCHES NOTHING ELSE
--   The scan already tracks progress end-to-end: Replicate.lua maintains a 0..1
--   `progress` (updated each coroutine slice) and exposes AH.Replicate.Progress()
--   + AH.Replicate.IsScanning(); the lifecycle is broadcast on the AH.Events bus
--   (AH_SCAN_START / AH_SCAN_COMPLETE / AH_SCAN_FAILED). Until now the ONLY
--   consumer was the text line in `/ah diag`. This file is a pure VIEW: it
--   subscribes to those existing events and polls Progress(). No edits to
--   Replicate.lua or Core.lua (suite rule #4).
--
-- ANCHOR (introspection-verified geometry, 12.0.5 — see SellStrip.lua:10-16)
--   AuctionHouseFrame    x36 y528 w800 h538
--   MoneyFrameBorder     x41 y534 w158 h19   (very bottom-left; PRESENT ON ALL TABS)
--   The money frame's right edge is ~x199; the band from there to the frame's right
--   wall is empty on every tab AND sits BELOW the sell-form overlay's y-range, which
--   is exactly why the money frame is never occluded. We mount in that band, aligned
--   to the money frame's height, so the bar is safe on all three tabs.
--   Primary anchor: LEFT -> MoneyFrameBorder's RIGHT (auto y-alignment, tracks Bliz
--   moving it). Fallback (global absent): BOTTOMLEFT of AuctionHouseFrame at the
--   offset computed from the verified rect (money right edge +gap; +6 y).
--
-- FRAME LEVEL — the SKILL.md:41 landmine
--   Absolute SetFrameLevel does NOT stick on a child of AuctionHouseFrame (set 50,
--   read back 1 -> buried). The PROVEN pattern (SellStrip.lua:396) is a RELATIVE
--   bump off the parent's level and inheriting by hierarchy. We parent to
--   AuctionHouseFrame and bump +10 (we're in the empty band BELOW the overlay, so we
--   don't need the strip's aggressive +50 to beat the click-swallowing overlay; we
--   only need to sit above the frame's own backdrop). No strata override, no
--   absolute level math.
--
-- BORDER ART
--   Reuse the SAME art that frames the sell strip: the `auctionhouse-itemheaderframe`
--   atlas (SellStrip.lua:417; cf. SKILL.md:44), applied as a BACKGROUND texture
--   slightly outset from the bar, at small scale.
--
-- THE TWO-PHASE TRUTH (do not collapse into one % bar)
--   Phase 1 — WAITING: ReplicateItems() fired, REPLICATE_ITEM_LIST_UPDATE hasn't
--     arrived. UNBOUNDED by design (§2.2: no timeout). Progress() is 0 and STAYS 0 —
--     no denominator exists, so a frozen "0%" would be a lie. We show an INDETERMINATE
--     sweep + "Waiting for data…".
--   Phase 2 — PROCESSING: snapshot landed; the coroutine folds rows and Progress()
--     climbs 0->1. A real determinate fill + "Scanning… N%". This is the 1->100% the
--     user wants to watch.
--   Phase is derived purely from the public accessors:
--     IsScanning() and Progress()==0  -> Phase 1 (indeterminate)
--     IsScanning() and Progress()>0   -> Phase 2 (determinate)

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame = CreateFrame
local floor       = math.floor
local format      = string.format

----------------------------------------------------------------
--  Geometry — small, money-frame-scale. All tunable; the ANCHOR is verified but
--  these inner sizes have NOT been visually confirmed in-game.
----------------------------------------------------------------
local W         = 170    -- container width (fits "Scanning… 100%" at small font)
local H         = 18     -- ~ money frame height (19), aligned to it
local GAP_X     = 108    -- gap between money frame right edge and our left edge.
                        -- v2: the manual Scan button (ScanButton.lua) now sits FIRST in
                        -- this band (it's persistent; this bar is scan-only), so the gap
                        -- clears it: 14 button gap + 80 button width + 14 clearance
                        -- (equal gaps — the button sits centered between money and bar).
local INSET     = 2      -- gap between container edge and the fill bar
local BAR_RAISE = 1      -- shift inner bar+backing UP this many px so it sits at the
                        -- atlas's visual center (the art's center reads higher than
                        -- the frame's geometric center). Top inset shrinks, bottom
                        -- inset grows by the same amount -> bar rises, height unchanged.
local BAR_SHRINK = 1     -- trim this many px off the BOTTOM edge only. The atlas's
                        -- bottom border art is visually thicker than its top, so the
                        -- box's bounding-box center (541.0 measured) reads ~1px low.
                        -- A pure move can't fix it (the two integer positions land at
                        -- 541 and 542, straddling the 541.5 perceptual target); a
                        -- bottom-only shrink lands box-bottom at 535 -> center 541.5.
local SWEEP_W   = 46     -- indeterminate sweep highlight width (scaled for small bar)
local SWEEP_SPS = 150    -- indeterminate sweep speed, pixels/second
local HOLD_SEC  = 2.5    -- how long the terminal (complete/failed) message lingers
local NUDGE_Y   = -2     -- drop the whole panel down a couple px so the atlas top
                        -- edge stops bleeding into the panel border above it

-- Fallback offset from AuctionHouseFrame BOTTOMLEFT, from the verified rect:
--   money left = x41 vs AHF x36 -> +5; width 158 -> right edge +163; +GAP_X.
--   money y534 vs AHF y528 -> +6.
local FB_X = (41 - 36) + 158 + GAP_X   -- = 271
local FB_Y = (534 - 528)               -- = 6

-- Phase colours (explicit RGB — no dependency on unverified VUI palette helpers).
local COLOR_WAIT = { 0.85, 0.65, 0.10 }  -- amber: indeterminate / waiting
local COLOR_RUN  = { 0.10, 0.70, 0.20 }  -- green: real progress
local COLOR_DONE = { 0.10, 0.70, 0.20 }  -- green: complete
local COLOR_FAIL = { 0.80, 0.20, 0.20 }  -- red:   failed

----------------------------------------------------------------
--  State
----------------------------------------------------------------
local state = {
    built     = false,
    frame     = nil,   -- container
    bar       = nil,   -- StatusBar (determinate fill)
    sweep     = nil,   -- texture (indeterminate animation)
    label     = nil,   -- centred FontString
    sweepX    = 0,
    hideTimer = nil,
    phase     = nil,   -- "connect" | "requested" (which pre-% wait we're in)
    waitStart = nil,   -- GetTime() when the current wait began (for elapsed "(Ns)")
    finalizing = false, -- post-100% gear-residue retry phase (AH_SCAN_FINALIZING)
}

local function CancelHide()
    if state.hideTimer then
        state.hideTimer:Cancel()
        state.hideTimer = nil
    end
end

----------------------------------------------------------------
--  Build once (lazy — AuctionHouseFrame must exist, same gate as SellStrip)
----------------------------------------------------------------
local function Build()
    if state.built or not AuctionHouseFrame then return end

    local f = CreateFrame("Frame", "VUIAHScanProgress", AuctionHouseFrame)
    f:SetSize(W, H)

    -- Anchor to the money frame's RIGHT if the global exists; else fall back to the
    -- verified BOTTOMLEFT offset. (MoneyFrameBorder is the name used by the verified
    -- geometry probe in SellStrip.lua:14.)
    local money = _G.MoneyFrameBorder
    if money then
        f:SetPoint("LEFT", money, "RIGHT", GAP_X, NUDGE_Y)
    else
        f:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", FB_X, FB_Y + NUDGE_Y)
    end

    -- RELATIVE level bump (SKILL.md:41 — absolute SetFrameLevel does not stick here).
    f:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 0) + 10)

    -- Backing card: the same atlas that frames the sell strip, at small scale,
    -- slightly outset so the rounded border sits around the bar.
    local cardArt = f:CreateTexture(nil, "BACKGROUND")
    cardArt:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
    cardArt:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    cardArt:SetAtlas("auctionhouse-itemheaderframe")

    -- Dark inner backing so the fill + text read cleanly inside the atlas frame.
    -- Raised by BAR_RAISE: smaller top inset, larger bottom inset -> centered on the
    -- atlas art rather than the frame's geometric center.
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -(INSET - BAR_RAISE))
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -INSET, INSET + BAR_RAISE + BAR_SHRINK)
    bg:SetColorTexture(0, 0, 0, 0.55)

    -- Determinate fill (raised in lockstep with the backing).
    -- Modern smooth fill = the player health-bar atlas, confirmed present in-client
    -- via live introspection. A StatusBar can't take an atlas NAME directly, so we
    -- build a texture, set its atlas (useAtlasSize=false so it stretches to fill
    -- rather than snapping to native size), and hand that to SetStatusBarTexture.
    -- It's tintable, so our green/amber phase colors via SetStatusBarColor apply.
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -(INSET - BAR_RAISE))
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -INSET, INSET + BAR_RAISE + BAR_SHRINK)
    local barTex = bar:CreateTexture(nil, "ARTWORK")
    barTex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health", false)
    bar:SetStatusBarTexture(barTex)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetClipsChildren(true)   -- keep the sweep inside the bar
    state.bar = bar

    -- Indeterminate sweep highlight (Phase 1) — same atlas as the fill.
    local sweep = bar:CreateTexture(nil, "OVERLAY")
    sweep:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health", false)
    sweep:SetVertexColor(1, 1, 1, 0.30)
    sweep:SetSize(SWEEP_W, H - INSET * 2)
    sweep:SetPoint("LEFT", bar, "LEFT", 0, 0)
    sweep:Hide()
    state.sweep = sweep

    -- Centred status text.
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", bar, "CENTER", 0, 0)
    label:SetText("")
    state.label = label

    f:Hide()
    state.frame = f
    state.built = true
end

----------------------------------------------------------------
--  Per-frame poll: drives both phases off the public accessors.
----------------------------------------------------------------

-- Compose the Phase-1 wait label: phase-specific text + live elapsed "(Ns)".
-- "connect"   = before AUCTION_HOUSE_THROTTLED_SYSTEM_READY (throttle/connect wait)
-- "requested" = ReplicateItems() has fired; awaiting the snapshot (AH_SCAN_REQUESTED)
-- These are TRUE state transitions from Replicate, not invented progress — there is
-- still no percentage here (no denominator), only which wait we're in and how long.
local function WaitLabel()
    local base = (state.phase == "requested")
        and "Requesting auctions…"
        or  "Connecting…"
    if state.waitStart then
        local secs = floor(GetTime() - state.waitStart)
        if secs > 0 then
            return format("%s (%ds)", base, secs)
        end
    end
    return base
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
    if not (AH.Replicate and AH.Replicate.IsScanning()) then return end

    local p = AH.Replicate.Progress() or 0
    if p > 0 then
        -- Phase 2 — determinate: real fill + percentage (1 -> 100%).
        if state.sweep:IsShown() then state.sweep:Hide() end
        state.bar:SetStatusBarColor(COLOR_RUN[1], COLOR_RUN[2], COLOR_RUN[3])
        state.bar:SetValue(p)
        if state.finalizing then
            -- Phase 3 — gear-residue retries (AH_SCAN_FINALIZING): main results
            -- are already committed; the scan is waiting out item-record
            -- streaming for cold gear rows. Honest LIVE COUNTS (resolved/total
            -- from Replicate.FinalizeStatus) — deliberately not merged into the
            -- 0-100% scale, which would stall/jump (unknowable duration, phase
            -- can end early on quiescence/budget with residue).
            local resolved, total
            if AH.Replicate.FinalizeStatus then
                resolved, total = AH.Replicate.FinalizeStatus()
            end
            if resolved and total and total > 0 then
                state.label:SetText(format("Finalizing gear… %d/%d", resolved, total))
            else
                state.label:SetText("Finalizing gear prices…")
            end
        else
            state.label:SetText(format("Scanning… %d%%", floor(p * 100)))
        end
    else
        -- Phase 1 — indeterminate: empty fill, sweeping highlight.
        if not state.sweep:IsShown() then
            state.bar:SetValue(0)
            state.bar:SetStatusBarColor(COLOR_WAIT[1], COLOR_WAIT[2], COLOR_WAIT[3])
            state.sweep:Show()
        end
        local span = (state.bar:GetWidth() or (W - INSET * 2))
        state.sweepX = state.sweepX + SWEEP_SPS * elapsed
        if state.sweepX > span then state.sweepX = -SWEEP_W end
        state.sweep:SetPoint("LEFT", state.bar, "LEFT", state.sweepX, 0)
        state.label:SetText(WaitLabel())
    end
end)

local function StartTicking()
    if not state.built then return end
    state.sweepX = -SWEEP_W
    ticker:Show()
end

local function StopTicking()
    ticker:Hide()
end

----------------------------------------------------------------
--  Show / terminal-message helpers
----------------------------------------------------------------
local function ShowScanning()
    Build()
    if not state.built then return end
    CancelHide()
    state.phase      = "connect"     -- first wait: throttle/connect (pre-ReplicateItems)
    state.waitStart  = GetTime()     -- start the elapsed "(Ns)" clock
    state.finalizing = false
    state.bar:SetValue(0)
    state.bar:SetStatusBarColor(COLOR_WAIT[1], COLOR_WAIT[2], COLOR_WAIT[3])
    state.sweep:Hide()         -- the ticker re-shows it on the first Phase-1 frame
    state.label:SetText(WaitLabel())
    state.frame:Show()
    StartTicking()
end

-- Park a terminal (complete/failed) message, then auto-hide after HOLD_SEC.
local function ShowTerminal(text, color, fill)
    if not state.built then return end
    StopTicking()
    state.phase      = nil
    state.waitStart  = nil
    state.finalizing = false
    state.sweep:Hide()
    state.bar:SetStatusBarColor(color[1], color[2], color[3])
    state.bar:SetValue(fill)
    state.label:SetText(text)
    state.frame:Show()
    CancelHide()
    state.hideTimer = C_Timer.NewTimer(HOLD_SEC, function()
        state.hideTimer = nil
        if state.frame then state.frame:Hide() end
    end)
end

local function HideNow()
    StopTicking()
    CancelHide()
    state.phase      = nil
    state.waitStart  = nil
    state.finalizing = false
    if state.frame then state.frame:Hide() end
end

----------------------------------------------------------------
--  Event wiring (consumes the existing scan lifecycle — defines nothing new)
----------------------------------------------------------------
AH.Events.On("AH_OPEN", function()
    Build()   -- AuctionHouseFrame exists by now; create the (hidden) bar.
end)

AH.Events.On("AH_SCAN_START", function()
    ShowScanning()
end)

-- ReplicateItems() has gone out: leave the connect wait, enter the snapshot wait.
-- Reset the elapsed clock so "(Ns)" times THIS phase, not the whole scan. Guarded
-- so a stray fire can't resurrect the bar after a terminal/close.
AH.Events.On("AH_SCAN_REQUESTED", function()
    if not (state.built and AH.Replicate and AH.Replicate.IsScanning()) then return end
    state.phase     = "requested"
    state.waitStart = GetTime()
    state.label:SetText(WaitLabel())
end)

-- Main drain finished and committed; gear-residue retries running (Phase 3).
AH.Events.On("AH_SCAN_FINALIZING", function()
    if not (state.built and AH.Replicate and AH.Replicate.IsScanning()) then return end
    state.finalizing = true
end)

AH.Events.On("AH_SCAN_COMPLETE", function(committed, rows)
    ShowTerminal(
        format("Scan complete — %d priced.", committed or 0),
        COLOR_DONE, 1)
end)

AH.Events.On("AH_SCAN_FAILED", function()
    ShowTerminal("Scan failed.", COLOR_FAIL, 1)
end)

-- AH closing aborts any in-flight scan (Replicate's AH_CLOSED handler tears down);
-- the bar should vanish immediately with it.
AH.Events.On("AH_CLOSED", function()
    HideNow()
end)
