-- VeritasUI_AuctionHouse / UI/ScanButton.lua
-- A manual "Scan" button mounted on the AH frame. Purpose is TWO-fold:
--   1. Feature: a user-triggered price scan (bypasses waiting for the auto-scan).
--   2. Diagnostic: it is the control in the hardware-event hypothesis test.
--
-- THE HYPOTHESIS THIS TESTS
--   Our auto-scan fires C_AuctionHouse.ReplicateItems() from a DETACHED callback
--   (AH_OPEN event -> FireWhenReady -> C_Timer), and on the first AH open of a session
--   the request is silently dropped (hangs at 0% until close/reopen). Auctionator's scan
--   button fires ReplicateItems() DIRECTLY inside its OnClick and works 100%. The
--   difference we are testing is the EXECUTION CONTEXT: a hardware-event stack (real
--   click) vs a detached timer/event callback.
--
--   This button calls AH.Replicate.StartManual() SYNCHRONOUSLY from OnClick — no timer,
--   no event defer, no throttle gate — so the hardware-event context (which propagates
--   through synchronous calls but is lost across C_Timer/coroutine/OnEvent boundaries) is
--   preserved all the way to ReplicateItems(). Auctionator's exact model.
--
--   EXPECTED OUTCOMES:
--     * Button scans 100% where auto-scan hangs -> hardware-event hypothesis CONFIRMED;
--       the fix for auto-scan must find a hardware-event path, and meanwhile the user has
--       a reliable manual scan + hung-scan recovery.
--     * Button ALSO hangs -> hypothesis DISPROVEN; execution context is not the factor.
--
-- ISOLATION (suite rule #4: one module never edits another)
--   Pure VIEW + controller over Replicate's PUBLIC api: AH.Replicate.StartManual(),
--   .IsScanning(), .SecondsUntilReady(). Subscribes to the AH.Events bus only. No edits
--   to Replicate.lua internals, Core.lua, or any sibling UI file.
--
-- ANCHOR / FRAME LEVEL — reuse the verified ScanProgress/SellStrip pattern
--   Parent to AuctionHouseFrame (must exist; same lazy-build gate as SellStrip/
--   ScanProgress). RELATIVE frame-level bump off the parent (absolute SetFrameLevel
--   does not stick on an AuctionHouseFrame child — SKILL.md:41 landmine). Anchored
--   TOPRIGHT inset from the AH frame's top-right, clear of the search/tab controls.

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame = CreateFrame

----------------------------------------------------------------
--  Geometry (all tunable; anchor parent is the verified AuctionHouseFrame)
----------------------------------------------------------------
local BTN_W       = 90
local BTN_H       = 22
local INSET_X     = -14   -- from AuctionHouseFrame TOPRIGHT (negative = leftward)
local INSET_Y     = -30   -- below the top edge, clear of the close button / title
local LEVEL_BUMP  = 10

local state = { built = false, btn = nil }

----------------------------------------------------------------
--  Label reflects live scan state (polled while shown)
----------------------------------------------------------------
local function RefreshLabel()
    local btn = state.btn
    if not btn then return end
    if AH.Replicate and AH.Replicate.IsScanning and AH.Replicate.IsScanning() then
        btn:SetText("Scanning…")
        btn:Disable()
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
--  OnClick — the hardware-event fire path (the whole point of this file)
----------------------------------------------------------------
local function OnClick()
    if not (AH.Replicate and AH.Replicate.StartManual) then
        VUI.Print(AH.TAG, "Scanner not loaded.")
        return
    end
    -- SYNCHRONOUS call inside OnClick: preserves the hardware-event execution context
    -- through to C_AuctionHouse.ReplicateItems(). Do NOT wrap this in C_Timer or defer
    -- it in any way — that would destroy the exact property under test.
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
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", INSET_X, INSET_Y)
    -- Relative level bump (absolute does not stick on an AH child — SKILL.md:41).
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + LEVEL_BUMP)
    btn:SetText("Scan")
    btn:SetScript("OnClick", OnClick)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("VeritasUI: Manual price scan")
        GameTooltip:AddLine("Fires a full auction scan now.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Also recovers a stuck auto-scan.", 0.8, 0.8, 0.8, true)
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
