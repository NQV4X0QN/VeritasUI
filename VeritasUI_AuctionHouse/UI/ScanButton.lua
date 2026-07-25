-- VeritasUI_AuctionHouse / UI/ScanButton.lua
-- The "Scan" button — since v1.8.0 THE way to run a price scan (auto-scan-on-open
-- removed: an unattended scan fired at every AH open had nobody to retry it when
-- the server dropped the request, and no way to show that it had).
--
-- FIRE PATH: OnClick calls AH.Replicate.StartManual() (alias of Start())
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
-- re-fires); it disables only while rows actually drain (Progress() > 0). Since
-- v1.9.5's persistent 60s retry chain a dropped request recovers with zero clicks,
-- so this is the impatient path, no longer the only one.
--
-- ISOLATION (suite rule #4: one module never edits another)
--   Pure VIEW + controller over Replicate's PUBLIC api: AH.Replicate.StartManual(),
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
    if AH.Replicate and AH.Replicate.IsScanning and AH.Replicate.IsScanning() then
        local p = (AH.Replicate.Progress and AH.Replicate.Progress()) or 0
        if p > 0 then
            -- Rows are actually draining — a real scan is in flight; hands off.
            btn:SetText("Scanning…")
            btn:Disable()
        else
            -- Pre-data wait: EITHER a healthy 28-40s snapshot wait OR the hang.
            -- Must stay clickable — this is the state the whole test exists for.
            -- StartManual() internally refuses if a coroutine is live, so a click
            -- during a healthy wait is safe (duplicate request = known no-op).
            btn:SetText("Retry Scan")
            btn:Enable()
        end
        return
    end
    local wait = (AH.Replicate and AH.Replicate.SecondsUntilReady
        and AH.Replicate.SecondsUntilReady()) or 0
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
    if not (AH.Replicate and AH.Replicate.StartManual) then
        VUI.Print(AH.TAG, "Scanner not loaded.")
        return
    end
    -- Called synchronously, straight out of OnClick. v1.8.0 did this to preserve the
    -- hardware-event execution context through to C_AuctionHouse.ReplicateItems();
    -- v1.9.5 falsified that premise (see the header note) — the drop window is
    -- server-side and fire-path independent. Left synchronous because nothing here
    -- needs to wait, NOT because a defer is known to break the request.
    local ok, reason = AH.Replicate.StartManual()
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
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("VeritasUI: Manual price scan")
        GameTooltip:AddLine("Fires a full auction scan now.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("\"Retry Scan\" = a request is out but no data has arrived; "
            .. "click to re-fire (recovers a stuck scan).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    state.btn = btn
    state.built = true
    RefreshLabel()
end

----------------------------------------------------------------
--  Poll the label while the AH is open (cheap: 1 Hz, only while shown)
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
