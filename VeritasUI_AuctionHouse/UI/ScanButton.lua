-- VeritasUI_AuctionHouse / UI/ScanButton.lua
-- The "Scan" button — since v1.8.0 THE way to run a price scan (auto-scan-on-open
-- removed: an unattended scan fired at every AH open had nobody to retry it when
-- the server dropped the request, and no way to show that it had).
--
-- FIRE PATH: OnClick calls AH.Scan.StartManual(), the engine facade in Core.lua, which
-- dispatches to Replicate.lua or Browse.lua per the scanEngine setting. This file stays
-- engine-agnostic on purpose -- see the facade's header.
-- SYNCHRONOUSLY — no timer, no event defer, no gate.
--
-- ⚠ v1.8.0 believed that synchronous fire was WHY manual scanning worked: that the
-- hardware-event execution context (propagated through synchronous calls, lost
-- across C_Timer / coroutine / OnEvent boundaries) was what let ReplicateItems()
-- through, following Auctionator's click-fired model. v1.9.5 FALSIFIED this from a
-- live repro: the server silently drops EVERY ReplicateItems() request for ~12
-- minutes after a long-idle login and then recovers on its own, regardless of how
-- the call was fired. The fire path is not a workaround for anything. It stays
-- synchronous because that is the simplest thing that works and nothing needs a
-- defer — NOT because deferring is known to break the request.
--
-- The button doubles as hung-scan recovery: during the pre-data wait it stays
-- ENABLED as "Retry Scan" (Start() clears a fired-but-never-arrived request and
-- re-fires); it disables only while rows actually drain (Progress() > 0).
--
-- ⚠ CORRECTED v1.13.8. This used to claim that since v1.9.5's "persistent 60s retry
-- chain a dropped request recovers with zero clicks, so this is the impatient path,
-- no longer the only one." That is the OPPOSITE of the truth and the more harmful of
-- the two stale retry comments: there is no automatic retry (DoFire has one caller,
-- Replicate.lua:1074; see Replicate.lua:247-250), so a dropped request recovers ONLY
-- when the user clicks this button. It is not the impatient path — it is the only
-- path. Which is precisely why it stays enabled through the wait.
--
-- ISOLATION (suite rule #4: one module never edits another)
--   Pure VIEW + controller over the SCAN FACADE's public api: AH.Scan.StartManual(),
--   .IsScanning(), .SecondsUntilReady(). Subscribes to the AH.Events bus only. No edits
--   to Replicate.lua internals, Core.lua, or any sibling UI file.
--
-- ANCHOR / FRAME LEVEL — reuse the verified ScanProgress/SellStrip pattern
--   Parent to AuctionHouseFrame (must exist; same lazy-build gate as SellStrip/
--   ScanProgress). RELATIVE frame-level bump off the parent (absolute SetFrameLevel
--   does not stick on an AuctionHouseFrame child — SKILL.md "Frame-level lesson"
--   landmine).
--
--   v2 REPOSITION (in-game finding): the original TOPRIGHT(-14,-30) anchor sat ON TOP
--   of Blizzard's own controls and made them unclickable. The button now lives in the
--   SAME verified-empty bottom band as the scan-progress bar (probe ref §2: the strip
--   right of MoneyFrameBorder x41 y534 w158 h19 is empty on ALL AH tabs and below the
--   sell-form overlay's y-range). Anchored to MoneyFrameBorder's RIGHT, offset past
--   the progress bar's span (GAP 8 + bar W 170 + 12), with the same BOTTOMLEFT
--   fallback scheme ScanProgress uses if the global is absent.
--
-- ENABLED-DURING-HANG (v2, in-game finding): the original label logic disabled the
--   button whenever IsScanning() was true — which INCLUDED the dropped-request state
--   (scanning=true, Progress()==0 for as long as the server keeps refusing; ~12
--   minutes in the v1.9.5 repro), the exact state StartManual() exists to recover.
--   The hang was therefore untestable. Now the button stays ENABLED through
--   the pre-data wait ("Retry Scan") and disables only during the actual row drain
--   (Progress() > 0). Misclicks during a HEALTHY wait are safe: StartManual() refuses
--   while a coroutine is draining, and a duplicate ReplicateItems() during the wait is
--   the same no-op the v1.7.9 10s retry already fired on every healthy scan.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame = CreateFrame

----------------------------------------------------------------
--  Geometry (all tunable; bottom-band placement mirrors ScanProgress.lua)
----------------------------------------------------------------
local BTN_W       = 80
local BTN_H       = 22     -- match the Cancel Auction button (standard UIPanelButton height)
local LEVEL_BUMP  = 10

-- v3 SWAP (user request): the button is the PERSISTENT element in this band (the
-- progress bar only shows mid-scan), so the button now sits FIRST, directly right
-- of the money frame; ScanProgress moved right of it (its GAP_X = 108 accounts for
-- this button's span: BAND_X 14 gap + 80 width + 14 clearance, which is the same
-- 108 the BAND_X note below derives independently).
local BAND_X      = 14    -- gap off the money frame's right edge. 14 centers the
                          -- button between money frame and scan bar: bar left edge
                          -- is at +108, so gaps are (108 - 80)/2 = 14 on each side.
local NUDGE_Y     = -1    -- vertical trim to sit level with the Cancel Auction button
                          -- (in-game tuned: -2 low, +2 high with the 22px button)

-- Fallback from AuctionHouseFrame BOTTOMLEFT if MoneyFrameBorder is absent, from
-- the verified rect (probe ref §2): money left +5, width 158 -> right edge +163.
local FB_X = (41 - 36) + 158 + BAND_X   -- = 177
local FB_Y = (534 - 528)                -- = 6

local state = { built = false, btn = nil }

----------------------------------------------------------------
--  DISABLED-ART PRE-WARM — real Enable()/Disable(), no streaming blank
--  (in-game finding 2026-07-02; root-caused 2026-07-04 by the /ah btnprobe
--  diagnostic, which was REMOVED in v1.9.11 after its measured values were
--  transcribed to PROBE_LIBRARY_AND_REFERENCE.md §2/§2.1 — that file is the
--  durable record and outranks this comment.)
--
--  The session's first real Disable() blanked the button for ~1s. The
--  investigation record, in order, so none of it is re-tried:
--    * v1.8.1 pre-filled GetDisabledTexture — a SILENT NO-OP: this
--      template is a three-slice build; GetNormalTexture/GetDisabledTexture
--      are nil (measured, not assumed), so the copy's guard always fell
--      through and its "verified" pass was a warm-cache coincidence.
--    * desaturation, overlay, and grey-text-on-normal-art emulations all
--      failed side-by-side comparison vs Cancel Auction. The last one came
--      from misreading the probe's file 130824 as the NORMAL art (fileID
--      recalled from memory — do not do that). The rendered evidence +
--      the highlight slice at 130826 settle the family mapping
--      (Disabled/Down/Highlight/Up ≈ 130824..130827): native disabled
--      buttons swap their three BACKGROUND slices to file 130824 — the
--      SILVER disabled art — and grey the text via GameFontDisable. The
--      blank was that silver file streaming on the session's first swap.
--
--  So: use the REAL Disable()/Enable() — native silver art, native grey
--  text, the suite's native-first philosophy — and kill the blank by
--  making the disabled art resident BEFORE the first flip:
--    * at build, flip Disable()→read→Enable() synchronously (no frame
--      renders in between, so nothing is ever visible) and record the
--      file(s) the template swaps into its BACKGROUND slices;
--    * park 1px, 5%-alpha textures on those files so they render — and
--      therefore stream — from AH open onward, seconds before any real
--      disable can occur.
--  Worst case (AH opened during an active cooldown on a cold client): the
--  countdown disables immediately at open and the silver art can still
--  take ~1s to appear ONCE, at open — not mid-interaction. A mid-session
--  flip can no longer blank.
----------------------------------------------------------------
local function PrewarmDisabledArt(btn)
    local files = {}
    pcall(function()
        btn:Disable()
        for _, region in ipairs({ btn:GetRegions() }) do
            if region:IsObjectType("Texture")
               and region:GetDrawLayer() == "BACKGROUND" then
                local f = region:GetTexture()
                if f then files[f] = true end
            end
        end
        btn:Enable()
    end)
    -- Measured fallback (probe library §2, 2026-07-04): if discovery came up
    -- empty, pre-warm the known disabled slice file directly.
    if not next(files) then files[130824] = true end
    for file in pairs(files) do
        local warm = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        warm:SetSize(1, 1)
        warm:SetPoint("CENTER")
        warm:SetAlpha(0.05)
        pcall(warm.SetTexture, warm, file)
    end
end

----------------------------------------------------------------
--  Label reflects live scan state (polled while shown)
----------------------------------------------------------------
local function RefreshLabel()
    local btn = state.btn
    if not btn then return end
    if AH.Scan and AH.Scan.IsScanning and AH.Scan.IsScanning() then
        local p = (AH.Scan.Progress and AH.Scan.Progress()) or 0
        if p > 0 then
            -- Rows are actually draining — a real scan is in flight; hands off.
            btn:SetText("Scanning…")
            btn:Disable()
        elseif AH.Scan.SupportsRetry and AH.Scan.SupportsRetry() then
            -- Pre-data wait on an engine where retrying MEANS something: replicate's
            -- ~28-40s snapshot wait, which can stretch indefinitely if the server drops
            -- the request. Must stay clickable — Start() clears a fired-but-never-arrived
            -- request and re-fires, and StartManual() refuses if a coroutine is live, so a
            -- click during a healthy wait is a known no-op.
            btn:SetText("Retry Scan")
            btn:Enable()
        else
            -- Pre-data wait on an engine with no retry path (browse, the default). This
            -- window is one throttled send plus a server round trip, so "Retry Scan"
            -- FLASHED on every scan and offered a recovery the engine cannot perform
            -- (owner-reported 2026-08-24). It reads as one continuous scan instead.
            -- ⚠ v1.14.17 removed the tooltip that EXPLAINED this recovery for exactly the
            -- same reason but kept the label state, which left the misleading affordance
            -- without its explanation. Half a fix; this is the other half.
            btn:SetText("Scanning…")
            btn:Disable()
        end
        return
    end
    local wait = (AH.Scan and AH.Scan.SecondsUntilReady
        and AH.Scan.SecondsUntilReady()) or 0
    if wait and wait > 0 then
        btn:SetText(string.format("%d:%02d", math.floor(wait / 60), wait % 60))
        btn:Disable()
    else
        btn:SetText("Scan")
        btn:Enable()
    end
end

----------------------------------------------------------------
--  OnClick — fires the scan directly (see the FIRE PATH note in the header)
----------------------------------------------------------------
local function OnClick()
    if not (AH.Scan and AH.Scan.StartManual) then
        VUI.Print(AH.TAG, "Scanner not loaded.")
        return
    end
    -- Called synchronously, straight out of OnClick. v1.8.0 did this to preserve the
    -- hardware-event execution context through to C_AuctionHouse.ReplicateItems();
    -- v1.9.5 falsified that premise (see the header note) — the drop window is
    -- server-side and fire-path independent. Left synchronous because nothing here
    -- needs to wait, NOT because a defer is known to break the request.
    local ok, reason = AH.Scan.StartManual()
    if not ok then
        VUI.Print(AH.TAG, reason or "Scan could not start.")
    end
    RefreshLabel()
end

----------------------------------------------------------------
--  Build once — lazy, gated on AuctionHouseFrame existing (SellStrip pattern)
----------------------------------------------------------------
local function Build()
    if state.built or not _G.AuctionHouseFrame then return end
    local parent = _G.AuctionHouseFrame

    local btn = CreateFrame("Button", "VUIAHScanButton", parent, "UIPanelButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    -- Bottom-band anchor (ScanProgress pattern): money frame's RIGHT edge if the
    -- global exists, else the verified BOTTOMLEFT fallback offsets.
    local money = _G.MoneyFrameBorder
    if money then
        btn:SetPoint("LEFT", money, "RIGHT", BAND_X, NUDGE_Y)
    else
        btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", FB_X, FB_Y + NUDGE_Y)
    end
    -- Relative level bump (absolute does not stick on an AH child —
    -- SKILL.md "Frame-level lesson").
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + LEVEL_BUMP)

    btn:SetText("Scan")

    -- Make the disabled slice art resident before any real disable can
    -- happen (see the DISABLED-ART PRE-WARM block comment).
    PrewarmDisabledArt(btn)

    btn:SetScript("OnClick", OnClick)
    -- No tooltip, deliberately (removed v1.14.17, owner request): Blizzard's own AH
    -- buttons carry none, the label already says what a click does, and the old text
    -- explained a "Retry Scan" recovery that belongs to the REPLICATE engine —
    -- Browse.Start refuses while a scan is running, so on the default engine the
    -- advice was wrong, not just noisy.

    state.btn = btn
    state.built = true
    RefreshLabel()
end

----------------------------------------------------------------
--  Poll the label while the AH is open (cheap: 2 Hz, only while shown)
----------------------------------------------------------------
local ticker = CreateFrame("Frame")
ticker:Hide()
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    RefreshLabel()
end)

----------------------------------------------------------------
--  Lifecycle — mirror SellStrip/ScanProgress: build+show on open, hide on close
----------------------------------------------------------------
AH.Events.On("AH_OPEN", function()
    Build()
    if state.btn then
        state.btn:Show()
        RefreshLabel()
        ticker:Show()
    end
end)

AH.Events.On("AH_CLOSED", function()
    ticker:Hide()
    if state.btn then state.btn:Hide() end
end)

-- Keep the label truthful as scan lifecycle events fire (immediate, not just on poll).
AH.Events.On("AH_SCAN_START", RefreshLabel)
AH.Events.On("AH_SCAN_REQUESTED", RefreshLabel)
AH.Events.On("AH_SCAN_COMPLETE", RefreshLabel)
AH.Events.On("AH_SCAN_FAILED", RefreshLabel)
