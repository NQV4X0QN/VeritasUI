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
-- FRAME LEVEL — the SKILL.md "Frame-level lesson" landmine
--   Absolute SetFrameLevel does NOT stick on a child of AuctionHouseFrame (set 50,
--   read back 1 -> buried). The PROVEN pattern (SellStrip.lua:396) is a RELATIVE
--   bump off the parent's level and inheriting by hierarchy. We parent to
--   AuctionHouseFrame and bump +10 (we're in the empty band BELOW the overlay, so we
--   don't need the strip's aggressive +50 to beat the click-swallowing overlay; we
--   only need to sit above the frame's own backdrop). No strata override, no
--   absolute level math.
--
-- BAR ART — Blizzard's Journeys delve card (v1.14.18)
--   SOURCED, not guessed: `JourneyCardButtonTemplate` in
--   Blizzard_EncounterJournal/Mainline/Blizzard_Journeys.xml:113-155. That is the
--   "Delves: Season 2" card (NormalTexture `ui-journeys-delve-button`, a
--   `JourneyCardName` title, a gold `JourneyCardLevel` reading
--   JOURNEYS_LEVEL_LABEL:format(level, maxLevel) = "Level 2/10", and the bar).
--   Its bar is a 335x18 StatusBar built from THREE pieces:
--       BACKGROUND  ui-journeys-renown-progressbar-BG      (rounded dark track)
--       BarTexture  ui-journeys-renown-progressbar-fill    (rounded fill)
--       ARTWORK     ui-journeys-renown-progressbar-frame   (rounded border)
--   We mirror that three-piece build for the LOOK (colour, track, border).
--   ⚠ IT IS NOT WHAT ROUNDS THE ENDS. This line used to claim it was, which is exactly the
--   v1.14.18 error: a border drawn over a StatusBar cannot round it, because SetValue crops
--   the fill rectangularly. The rounding comes from three-slicing the art so the caps keep
--   native width — see the ROUNDED ENDS block further down, which is the authority.
--
--   ⚠ THE PREVIOUS `auctionhouse-itemheaderframe` CARD IS GONE ON PURPOSE. It was the
--   grey squared-off surround the owner asked to remove (2026-08-23). Everything that
--   existed only to centre a small bar INSIDE that card went with it — INSET,
--   BAR_RAISE, BAR_SHRINK and NUDGE_Y's -2. Those were empirically-earned constants,
--   but they were earned against art that no longer exists: re-adding them would
--   offset the bar inside its own frame for no reason. Do not "restore" them.
--
--   ⚠ THE FILL ATLAS IS BAKED GREEN — Blizzard NEVER tints it. Verified in
--   Blizzard_Journeys.lua:234-249: the only calls on JourneyCardProgressBar are
--   SetShown / SetMinMaxValues / SetValue, with no SetStatusBarColor anywhere. So
--   SetStatusBarColor (which MULTIPLIES) must stay at 1,1,1 for the green phases or we
--   darken Blizzard's own colour, and the amber/red phases must SetDesaturated(true)
--   first or a red tint over green muddies to brown. See PHASE below.
--
--   MEASURED (via `/ah diag`, 12.1.0): all three atlases are native 335x18 and our rect is
--   170x18. Height maps 1:1 — no vertical distortion. Width is squashed ~2:1, which halves
--   the cap radius; that is why the ends read flat, and it is what the slicing addresses.
--   Widening is NOT an option: the band holds the money frame, the Scan button and the bar.
--
-- THE THREE-PHASE TRUTH (do not collapse into one % bar)
--   ⚠ READ WITH THE LABEL DEFAULT IN MIND: since v1.14.18 the label is OFF by default, so
--   the phase TEXT described below is not normally on screen — the sweep and the fill carry
--   the state. The text still exists and is correct under `/ah bartune label in|above`.
--   Phase 3 is replicate-only and replicate is not in practical use (see the label block).
--   Phase 1 — WAITING: ReplicateItems() fired, REPLICATE_ITEM_LIST_UPDATE hasn't
--     arrived. UNBOUNDED by design (§2.2: no timeout). Progress() is 0 and STAYS 0 —
--     no denominator exists, so a frozen "0%" would be a lie. INDETERMINATE sweep +
--     WaitLabel(): "Connecting…", then "Requesting auctions…" once AH_SCAN_REQUESTED
--     lands, each with a live "(Ns)" elapsed suffix and a "try N" counter from the
--     second attempt on (v1.9.5: the server can silently drop requests for ~12 min,
--     so a long wait must read as the addon working, not hung).
--   Phase 2 — PROCESSING: snapshot landed; the coroutine folds rows and Progress()
--     climbs 0->1. A real determinate fill + "Scanning… N%". This is the 1->100% the
--     user wants to watch.
--   Phase 3 — FINALIZING: main results are already committed; gear-residue retries are
--     waiting out item-record streaming. Honest live counts — "Finalizing gear… N/M",
--     or "Finalizing gear prices…" until FinalizeStatus has numbers. Its duration is
--     unknowable and it can end early on quiescence/budget, so it is deliberately NOT
--     folded into the 0-100% scale; see the fuller note in the ticker's Phase-3 branch.
--   Phase is a HYBRID of public accessors and lifecycle events, NOT accessors alone:
--     IsScanning() and Progress()==0  -> Phase 1 (indeterminate)
--     IsScanning() and Progress()>0   -> Phase 2 (determinate)
--     which Phase-1 wait it is <- state.phase, set by the AH_SCAN_REQUESTED handler
--     Phase 3 <- state.finalizing, set by the AH_SCAN_FINALIZING handler

local _, AH = ...
local VUI = _G.VeritasUI
if not VUI then return end

local CreateFrame = CreateFrame
local floor       = math.floor
local format      = string.format
-- Hot: WaitLabel reads GetTime once per frame, and a Phase-1 wait can now last minutes
-- (see v1.9.5). Localized for the same reason Replicate.lua localizes it.
local GetTime     = GetTime

----------------------------------------------------------------
--  Geometry — small, money-frame-scale. All tunable; the ANCHOR is verified but
--  these inner sizes have NOT been visually confirmed in-game.
----------------------------------------------------------------
local W         = 170    -- container width (fits "Scanning… 100%" at small font)
local H         = 18     -- ~ money frame height (19), aligned to it. ALSO the exact
                        -- height of Blizzard's Journey card bar (335x18), so the
                        -- rounded art maps 1:1 vertically with no distortion.
local GAP_X     = 108    -- gap between money frame right edge and our left edge.
                        -- v2: the manual Scan button (ScanButton.lua) now sits FIRST in
                        -- this band (it's persistent; this bar is scan-only), so the gap
                        -- clears it: 14 button gap + 80 button width + 14 clearance
                        -- (equal gaps — the button sits centered between money and bar).
local SWEEP_W   = 46     -- indeterminate sweep highlight width (scaled for small bar)
local SWEEP_SPS = 150    -- indeterminate sweep speed, pixels/second
local HOLD_SEC  = 2.5    -- how long the terminal (complete/failed) message lingers
local NUDGE_Y   = 0      -- was -2 until v1.14.18, to stop the removed
                        -- `auctionhouse-itemheaderframe` card's outset top edge bleeding
                        -- into the panel border above. With the card gone there is
                        -- nothing to clear, so the bar sits naturally centred on the
                        -- money frame again.

-- The bar IS the container: no outer card art to inset from, so the StatusBar fills the
-- frame and the art stretches to the same rect. The former BAR_H constant was replaced by
-- BarHeight() at v1.14.18, which reads the tunable and falls back to H — one place, and now
-- runtime-adjustable.

-- Blizzard's three-piece rounded bar (see the BAR ART header block for provenance).
local ATLAS_TRACK = "ui-journeys-renown-progressbar-BG"
local ATLAS_FILL  = "ui-journeys-renown-progressbar-fill"
local ATLAS_FRAME = "ui-journeys-renown-progressbar-frame"
-- Fallback fill if the Journeys atlases are absent from the client: the player
-- health-bar atlas this file used before v1.14.18. Squared ends, but present.
local ATLAS_FILL_LEGACY = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"

-- ROUNDED ENDS — three attempts during v1.14.18, and what the MEASUREMENT finally said
--
-- ⚠⚠ DO NOT MASK THIS BAR WITH `Professions-skillbar-mask`. MEASURED in the live client
-- via `/ah diag`: that atlas is native **512x512** — a square canvas, not a thin pill.
-- Stretched into our 170x18 rect the pill's alpha band collapses to roughly ONE PIXEL,
-- and the bar renders as a thin green line. That was the second attempt, and it was strictly worse
-- than the squared bar it replaced. The rank bar gets away with it because its Fill is
-- 441x18 and it drives the mask's WIDTH, never squashing its height.
--
-- ⚠ ALSO DEAD, and for the record so it is not re-tried: a border texture drawn OVER the
-- fill cannot round it (v1.14.18). `StatusBar:SetValue` crops the fill RECTANGULARLY.
--
-- ⚠ AND: the "the caps live in a native overhang" theory (also v1.14.18) is FALSIFIED by
-- measurement. All three Journeys atlases are native **335x18**, i.e. exactly the size of
-- Blizzard's own StatusBar in Blizzard_Journeys.xml:132. There is no overhang at all.
--
-- WHAT THE NUMBERS ACTUALLY SAY: native 335x18 into our 170x18 rect. Height maps 1:1, so
-- there is NO vertical distortion; the ONLY distortion is horizontal, ~2:1, which halves
-- the rounded cap radius and is why the ends read flat rather than round.
--
-- THE FIX THAT FOLLOWS: three-slice the art so the caps keep their NATIVE pixel width and
-- only the middle stretches. `SetTextureSliceMargins(l, t, r, b)` +
-- `SetTextureSliceMode` — idiom read from Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua:380-384.
-- Top/bottom margins are 0: the vertical axis already maps 1:1 and must not be sliced.
--
-- ⚠ THE FILL MUST BE SLICED TOO — the third attempt excluded it and that is why the bar still read
-- flat. MEASURED with `/ah baratlas` (the magenta-plate probe): all three atlases really
-- are pills with transparent margins, and stacked at NATIVE 335x18 they look exactly like
-- the Delve card (probe row 4). At our 170 width the stack shows NO transparency at all and
-- square corners (row 5), while the frame alone, SLICED, keeps its shape (row 6). The cap
-- margin is only a few px at 335; squashed 2:1 it goes sub-pixel, and the unsliced fill —
-- the green thing you actually see — then paints over the track's and frame's rounded caps.
-- So slicing the track and frame alone can never show: the fill covers them.
--
-- ⚠ The one UNMEASURED interaction: `StatusBar:SetValue` crops the fill via texcoords, and
-- how that composes with slicing is not documented and Blizzard never needs it (their bar
-- is native 1:1). Hence `barSliceFill`, default ON but revertible with
-- `/ah bartune fill off` — if a partial fill renders wrongly, that is the crop fighting the
-- slice, and it is a FUNCTIONAL fault, so it gets its own switch rather than being buried.
--
-- The margin is TUNABLE (`/ah bartune`) because the exact cap radius inside a 335x18
-- atlas is not something the source states, and this codebase settles that class of
-- number by eye (cf. the Delve nudge constants). The 9 ceiling comes from the DEFAULT 18px
-- height (a pill cannot round by more than half its height); it is a sanity clamp on the
-- input, not a per-height calculation, so a shorter bar simply renders wider caps.
local SLICE_MARGIN_DEFAULT = 9

-- Vertical room reserved for the label when it sits above the bar.
local LABEL_ABOVE_H = 12

-- Fallback offset from AuctionHouseFrame BOTTOMLEFT, from the verified rect:
--   money left = x41 vs AHF x36 -> +5; width 158 -> right edge +163; +GAP_X.
--   money y534 vs AHF y528 -> +6.
local FB_X = (41 - 36) + 158 + GAP_X   -- = 271
local FB_Y = (534 - 528)               -- = 6

-- Phase presentation. TWO branches per phase because the art decides the rules:
--   `journey` — the rounded Journeys art, whose fill is BAKED GREEN and untinted by
--     Blizzard. Green phases therefore pass 1,1,1 (no tint at all) so the bar is
--     Blizzard's exact colour, which is the entire point of the change. Amber and red
--     set `desat`, which desaturates the fill FIRST so the tint reads true instead of
--     multiplying into brown.
--   `legacy` — the pre-v1.14.18 health atlas fallback, which is neutral and needs the
--     old explicit tints.
-- ⚠ Do NOT collapse these into one table. A single green tint would darken the Journeys
-- art; a single 1,1,1 would leave the legacy fallback untinted and unreadable.
local PHASE = {
    wait = { journey = { 0.95, 0.72, 0.12, desat = true  }, legacy = { 0.85, 0.65, 0.10 } },
    run  = { journey = { 1.00, 1.00, 1.00, desat = false }, legacy = { 0.10, 0.70, 0.20 } },
    done = { journey = { 1.00, 1.00, 1.00, desat = false }, legacy = { 0.10, 0.70, 0.20 } },
    fail = { journey = { 0.85, 0.25, 0.25, desat = true  }, legacy = { 0.80, 0.20, 0.20 } },
}

----------------------------------------------------------------
--  State
----------------------------------------------------------------
local state = {
    built     = false,
    frame     = nil,   -- container
    bar       = nil,   -- StatusBar (determinate fill)
    fillTex   = nil,   -- the StatusBar's own texture (needed for SetDesaturated)
    journeyArt = false,-- true = rounded Journeys art loaded; false = legacy fallback
    slice      = nil,  -- horizontal slice margin actually applied (px)
    sliceTrack = false,-- did slicing take on the track texture?
    sliceFrame = false,-- ...and on the frame texture?
    sliceFill  = false,-- ...and on the FILL (the one that was missing until v1.14.18)
    sweep     = nil,   -- texture (indeterminate animation)
    label     = nil,   -- centred FontString
    sweepX    = 0,
    hideTimer = nil,
    phase     = nil,   -- "connect" | "requested" (which pre-% wait we're in)
    waitStart = nil,   -- GetTime() when the current wait began (for elapsed "(Ns)")
    finalizing = false, -- post-100% gear-residue retry phase (AH_SCAN_FINALIZING)
}

-- Apply a PHASE entry, picking the branch that matches the art actually loaded and
-- desaturating the fill only where the baked-green atlas would otherwise fight the tint.
local function ApplyPhase(name)
    local bar = state.bar
    if not bar then return end
    local spec = PHASE[name]
    if not spec then return end
    local c = state.journeyArt and spec.journey or spec.legacy
    local tex = state.fillTex
    -- SetDesaturated is a real Texture method, but it is only meaningful for the
    -- Journeys branch; the legacy tints already assume a neutral texture.
    if state.journeyArt and tex and tex.SetDesaturated then
        pcall(tex.SetDesaturated, tex, c.desat and true or false)
    end
    bar:SetStatusBarColor(c[1], c[2], c[3])
end

local function CancelHide()
    if state.hideTimer then
        state.hideTimer:Cancel()
        state.hideTimer = nil
    end
end

-- The horizontal slice margin in force. Absence means "use the shipped default", the same
-- convention as scanEngine / scanFloorSeconds. 0 disables slicing (plain stretch).
local function SliceMargin()
    local v = AH.db and AH.db.settings and AH.db.settings.barSliceMargin
    if type(v) == "number" and v >= 0 then return v end
    return SLICE_MARGIN_DEFAULT
end

-- Where the percentage text sits: "off" (DEFAULT), "in", or "above".
--
-- ⚠ DEFAULT IS "off" AS OF v1.14.18, at the owner's call, and the reasoning is sound: a
-- progress bar and a number stating the same progress are redundant, and BOTH terminal
-- states already report to chat — Core.lua:251 prints "Scan complete — N items priced." and
-- Core.lua:263 prints "Scan failed — ...". So the bar alone loses nothing on the determinate
-- 0->100% path, and it lets the bar be slim, which is what makes the rounded caps read.
--
-- ⚠ WHAT IS GENUINELY LOST, so nobody rediscovers it as a bug:
--   Phase 1 (indeterminate) held the only "how long have I been waiting" signal — the
--   elapsed "(Ns)" and the try counter. The animated SWEEP still says "working with no ETA",
--   which is the standard idiom, but the DURATION is now invisible. That mattered once:
--   v1.9.5 recorded the server silently dropping requests for ~12 minutes.
--   ⚠ This IS live on browse, not a replicate-only concern: Browse.lua:450-458 enqueues the
--   query behind IsThrottledMessageSystemReady and fires AH_SCAN_REQUESTED before any
--   results exist, and `progress` starts at 0 — so the Phase-1 sweep genuinely runs.
--   Recoverable with `/ah bartune label in|above`, which is why the label code is KEPT.
--
-- ⚠ PHASE 3 IS NOT A CONSIDERATION HERE — corrected 2026-08-23 after I wrongly listed it as
-- a cost of hiding the label. Phase 3 (FINALIZING, the gear-residue wait) is REPLICATE-ONLY
-- and browse never fires AH_SCAN_FINALIZING at all (zero occurrences in Browse.lua). Browse
-- keys gear off the result's own itemKey, so there is no deferred pile and nothing to
-- "finish resolving". Replicate is not in practical use: `scanEngine` defaults to "browse"
-- (Tooltip.lua:83) and is reachable only by an explicit `/ah engine replicate` pin or by
-- Browse.lua failing to load (which warns once per session). Do not weight phase 3 when
-- reasoning about this bar.
local function LabelPos()
    local v = AH.db and AH.db.settings and AH.db.settings.barLabelPos
    if v == "above" or v == "in" then return v end
    return "off"
end

-- Bar height. Tunable because removing the label FREED it: the text needed ~14px, the art
-- does not. Blizzard's bar is 335x18 (aspect 18.6:1); ours is 170 wide, so a height near 9
-- is GEOMETRICALLY SIMILAR to theirs and the caps come out proportionally as round as the
-- Delve card's. 18 is kept as the default because it is the measured, shipped value and
-- changing two things at once is how the last four rounds went wrong.
local function BarHeight()
    local v = AH.db and AH.db.settings and AH.db.settings.barHeight
    if type(v) == "number" and v >= 6 and v <= 24 then return v end
    return H
end

-- Point size adjustment applied to the INSIDE label so glyphs fit the bar (18px by
-- default, but see BarHeight()). Negative
-- shrinks. Only consulted when LabelPos() == "in".
local function FontDelta()
    local v = AH.db and AH.db.settings and AH.db.settings.barFontDelta
    if type(v) == "number" then return v end
    return -1
end

-- Whether the FILL is sliced as well. Default ON (see the block above); off restores the
-- v1.14.18 behaviour if the StatusBar crop and the slice turn out to conflict.
local function SliceFill()
    local v = AH.db and AH.db.settings and AH.db.settings.barSliceFill
    if v == nil then return true end
    return v and true or false
end

-- Three-slice a full-width bar texture so its rounded caps keep native pixel width while
-- only the middle stretches. Horizontal only: top/bottom stay 0 because the vertical axis
-- already maps 1:1 (native 18 == our 18) and slicing it would distort what currently is
-- undistorted. Every call is pcall'd: SetTextureSliceMargins/Mode are recent APIs and a
-- client without them must fall back to a plain stretch, not error inside Build.
local function ApplySlice(tex, margin)
    if not tex or not margin or margin <= 0 then return false end
    if not (tex.SetTextureSliceMargins and tex.SetTextureSliceMode) then return false end
    local okM = pcall(tex.SetTextureSliceMargins, tex, margin, 0, margin, 0)
    if not okM then return false end
    local mode = Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched
    if mode then pcall(tex.SetTextureSliceMode, tex, mode) end
    return true
end

----------------------------------------------------------------
--  Build once (lazy — AuctionHouseFrame must exist, same gate as SellStrip)
----------------------------------------------------------------
local function Build()
    if state.built or not AuctionHouseFrame then return end

    local f = CreateFrame("Frame", "VUIAHScanProgress", AuctionHouseFrame)
    -- With the label above, the container must be tall enough for text + bar; the bar is
    -- then pinned to the container's BOTTOM so the extra height grows upward and the bar
    -- stays aligned to the money frame.
    local labelAbove = (LabelPos() == "above")
    local barH = BarHeight()
    f:SetSize(W, labelAbove and (barH + LABEL_ABOVE_H) or barH)

    -- Anchor to the money frame's RIGHT if the global exists; else fall back to the
    -- verified BOTTOMLEFT offset. (MoneyFrameBorder is the name used by the verified
    -- geometry probe in SellStrip.lua:14.)
    local money = _G.MoneyFrameBorder
    if money then
        f:SetPoint("LEFT", money, "RIGHT", GAP_X, NUDGE_Y)
    else
        f:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", FB_X, FB_Y + NUDGE_Y)
    end

    -- RELATIVE level bump (SKILL.md "Frame-level lesson" — absolute SetFrameLevel
    -- does not stick here).
    f:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 0) + 10)

    -- Is Blizzard's rounded Journeys bar art present in this client? The names come from
    -- live Blizzard source (see the BAR ART header block), so this should always be true;
    -- the check exists because SetAtlas on an unknown name yields a BLANK texture, which
    -- would render the bar invisible rather than merely wrong.
    local haveArt = false
    if C_Texture and C_Texture.GetAtlasInfo then
        haveArt = (C_Texture.GetAtlasInfo(ATLAS_TRACK) and C_Texture.GetAtlasInfo(ATLAS_FILL)
                   and C_Texture.GetAtlasInfo(ATLAS_FRAME)) and true or false
    end
    state.journeyArt = haveArt

    -- SHAPE: the horizontal slice margin that keeps the rounded caps at native width.
    local slice = SliceMargin()
    state.slice = slice

    -- Determinate fill. The StatusBar now FILLS the container — there is no surrounding
    -- card to inset from. A StatusBar can't take an atlas NAME directly, so we build a
    -- texture, set its atlas (useAtlasSize=false so it stretches to our width rather
    -- than snapping to the native 335), and hand that to SetStatusBarTexture.
    local bar = CreateFrame("StatusBar", nil, f)
    if labelAbove then
        bar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
        bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        bar:SetHeight(barH)
    else
        bar:SetAllPoints(f)
    end


    -- Rounded dark track, behind the fill (Blizzard: BACKGROUND layer).
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    if haveArt then
        track:SetAtlas(ATLAS_TRACK, false)
        state.sliceTrack = ApplySlice(track, slice)
    else
        track:SetColorTexture(0, 0, 0, 0.55)
    end

    local fillTex = bar:CreateTexture(nil, "ARTWORK")
    fillTex:SetAtlas(haveArt and ATLAS_FILL or ATLAS_FILL_LEGACY, false)
    bar:SetStatusBarTexture(fillTex)
    -- ⚠ AFTER SetStatusBarTexture: the StatusBar may re-point its texture, and slicing a
    -- texture it then replaces would silently apply to nothing.
    if haveArt and SliceFill() then
        state.sliceFill = ApplySlice(fillTex, slice)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetClipsChildren(true)   -- keep the sweep inside the bar
    state.bar     = bar
    state.fillTex = fillTex

    -- Indeterminate sweep highlight (Phase 1) — same fill art, above the fill but below
    -- the rounded frame, so the frame masks its square edges at the rounded caps.
    -- Explicit sublevels: draw order within one layer is otherwise creation-order
    -- dependent, and the frame art is created after this.
    local sweep = bar:CreateTexture(nil, "ARTWORK")
    sweep:SetDrawLayer("ARTWORK", 2)
    sweep:SetAtlas(haveArt and ATLAS_FILL or ATLAS_FILL_LEGACY, false)
    sweep:SetVertexColor(1, 1, 1, 0.30)
    sweep:SetSize(SWEEP_W, barH)
    sweep:SetPoint("LEFT", bar, "LEFT", 0, 0)
    sweep:Hide()
    state.sweep = sweep

    -- Rounded border on top (Blizzard: ARTWORK layer). This is what actually reads as
    -- "rounded ends"; without it the fill's own corners are squared by the bar rect.
    if haveArt then
        local frameArt = bar:CreateTexture(nil, "OVERLAY")
        frameArt:SetDrawLayer("OVERLAY", 0)
        frameArt:SetAllPoints(bar)
        frameArt:SetAtlas(ATLAS_FRAME, false)
        state.sliceFrame = ApplySlice(frameArt, slice)
    end

    -- Status text.
    --
    -- ⚠ NOT PARENTED TO `bar`. It used to be, and `bar:SetClipsChildren(true)` (present for
    -- the sweep) therefore SHEARED the glyphs' ascenders and descenders against the 18px
    -- bar rect — the owner reported the font "cropping over the edges on the top and
    -- bottom" during v1.14.18 development. Clipping is wanted for the sweep and unwanted for the text, so
    -- the text gets its own unclipped host frame above the bar. Do not move it back onto
    -- `bar` for tidiness; the clip will silently return.
    local labelHost = CreateFrame("Frame", nil, f)
    labelHost:SetAllPoints(f)
    -- `or 0` matches this file's existing convention for frame levels (see the container's
    -- own SetFrameLevel above): GetFrameLevel is not guaranteed to answer a number before
    -- layout, and the headless mock returns nil, which surfaced it immediately.
    labelHost:SetFrameLevel((bar:GetFrameLevel() or 0) + 2)

    local label = labelHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- ⚠ ABOVE vs INSIDE is a real geometric conflict, not a bug. Blizzard's own bar carries
    -- NO text: Blizzard_Journeys.xml anchors `JourneyCardLevel` BOTTOM -> the bar's TOP +5,
    -- i.e. the label sits above it. That is why they never have to fit glyphs into 18px.
    -- "above" reproduces their arrangement (and lets the bar be slim and properly rounded);
    -- "in" keeps ours self-contained inside the money-frame band. Owner's call.
    local labelPos = LabelPos()
    if labelPos == "above" then
        label:SetPoint("BOTTOM", bar, "TOP", 0, 2)
        label:SetJustifyH("CENTER")
    else
        label:SetPoint("CENTER", bar, "CENTER", 0, 0)
        -- ⚠ Shrink ONLY for "in". This used to run for "off" too, because the branch was a
        -- bare `else` — harmless at runtime (the label is hidden) but it made the headless
        -- font assertion pass while exercising the OFF path, i.e. testing the wrong branch.
        if labelPos == "in" then
            -- DERIVED from whatever the font object actually is (never a hardcoded
            -- face/size — the frozen-cosmetic-constant trap), so a font change carries through.
            local face, size, flags = label:GetFont()
            local delta = FontDelta()
            if face and size and delta ~= 0 then
                pcall(label.SetFont, label, face, math.max(6, size + delta), flags)
            end
        end
    end
    label:SetText("")
    -- ⚠ CREATED EVEN WHEN OFF, then hidden. `state.label:SetText(...)` is called from the
    -- ticker, ShowScanning, ShowTerminal and Demo; making it nil would mean guarding all of
    -- them, and a missed guard is a runtime error mid-scan. A hidden FontString absorbs
    -- every write harmlessly.
    if LabelPos() == "off" then label:Hide() end
    state.label = label

    f:Hide()
    state.frame = f
    state.built = true
end

----------------------------------------------------------------
--  Per-frame poll: drives both phases off the public accessors.
----------------------------------------------------------------

-- Compose the Phase-1 wait label: phase-specific text + live elapsed "(Ns)".
-- "connect"   = AH_SCAN_START seen, AH_SCAN_REQUESTED not yet. Since v1.8.0 the
--               fire path is synchronous (Start() → DoFire() in one call stack —
--               all pre-fire gates were stripped), so this phase lasts zero
--               frames in practice; kept as the defensive default in case a
--               deferred fire path ever returns.
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
            -- Attempt counter (v1.9.5): the retry chain is now persistent
            -- ⚠ CORRECTED v1.13.8. This used to read "Replicate re-fires every 60s
            -- while the server drops requests". THERE IS NO AUTOMATIC RETRY. DoFire has
            -- exactly ONE caller (Replicate.lua:1074, inside Start), and
            -- Replicate.lua:247-250 states it outright: since v1.9.14 `attempts` counts
            -- USER-INITIATED fires only. The measurement behind the old wording was real
            -- — ~12 min of silent server drops on 2026-07-11 — but the automatic chain
            -- that was built for it has since been removed. Believing this comment
            -- means debugging a hang on the assumption that re-fires are happening
            -- while the addon is in fact sitting waiting for a click.
            -- So `attempts` climbs only when the USER clicks Retry Scan. Shown from the
            -- second attempt on; attempt 1 keeps the plain label.
            local tr = AH.Replicate.LastTrace and AH.Replicate.LastTrace()
            local attempts = tr and tr.attempts or 1
            if attempts > 1 then
                return format("%s (%ds, try %d)", base, secs, attempts)
            end
            return format("%s (%ds)", base, secs)
        end
    end
    return base
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
    -- DEMO HOLD (v1.14.18). `/ah bardemo` parks the bar in a chosen visual state and keeps
    -- it there, so its appearance can be inspected and screenshotted without running a real
    -- scan and without racing the scan floor. It NEVER consults either engine, and it sits
    -- ABOVE the engine gate below so that gate's semantics are untouched when no demo is
    -- active (ah_scanprogress_test case 1 asserts that gate).
    if state.demo then
        if state.demo == "wait" then
            local span = (state.bar:GetWidth() or W)
            state.sweepX = state.sweepX + SWEEP_SPS * elapsed
            if state.sweepX > span then state.sweepX = -SWEEP_W end
            state.sweep:SetPoint("LEFT", state.bar, "LEFT", state.sweepX, 0)
        end
        return
    end

    -- ⚠ FACADE, NOT AH.Replicate. This file read AH.Replicate.* directly at every site while
    -- browse has been the DEFAULT engine since v1.12.12, and Replicate.IsScanning() returns
    -- Replicate's own `scanning` local, which a browse scan never sets. So this first line
    -- early-returned for the whole scan: no sweep, a frozen "Connecting…", then a snap to
    -- "Scan complete" -- the entire three-phase readout inert on the engine that actually runs.
    -- AH.Scan.IsScanning() reports EITHER engine and AH.Scan.Progress() dispatches to whichever
    -- is live (Core.lua:484-501). The v1.12.9 facade migration moved ScanButton.lua over and
    -- missed this file.
    if not (AH.Scan and AH.Scan.IsScanning()) then return end

    local p = (AH.Scan.Progress and AH.Scan.Progress()) or 0
    if p > 0 then
        -- Phase 2 — determinate: real fill + percentage (1 -> 100%).
        if state.sweep:IsShown() then state.sweep:Hide() end
        ApplyPhase("run")
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
            ApplyPhase("wait")
            state.sweep:Show()
        end
        local span = (state.bar:GetWidth() or W)
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
    state.phase      = "connect"     -- pre-REQUESTED default (zero-length since v1.8.0's synchronous fire)
    state.waitStart  = GetTime()     -- start the elapsed "(Ns)" clock
    state.finalizing = false
    state.bar:SetValue(0)
    ApplyPhase("wait")
    state.sweep:Hide()         -- the ticker re-shows it on the first Phase-1 frame
    state.label:SetText(WaitLabel())
    state.frame:Show()
    StartTicking()
end

-- Park a terminal (complete/failed) message, then auto-hide after HOLD_SEC.
--
-- Deliberately NOT gated on IsScanning(), unlike the AH_SCAN_REQUESTED and
-- AH_SCAN_FINALIZING handlers below. That asymmetry is intended: those two only
-- mutate state, so a guard is free, whereas a terminal message is the one thing
-- that must land precisely because the scan has just stopped. There is also no
-- stray fire to guard against. Replicate's AH_CLOSED handler aborts by clearing
-- the scan coroutine and hiding its driver, and emits no terminal event of its
-- own, so AH_SCAN_COMPLETE / AH_SCAN_FAILED cannot arrive after a close. Nor can
-- a reopen inside HOLD_SEC surface a stale message: AH_CLOSED runs HideNow, which
-- hides the frame and cancels the hide timer, and AH_OPEN only calls Build().
local function ShowTerminal(text, phaseName, fill)
    if not state.built then return end
    StopTicking()
    state.phase      = nil
    state.waitStart  = nil
    state.finalizing = false
    state.sweep:Hide()
    ApplyPhase(phaseName)
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
    -- Facade: browse fires this event too (Browse.lua:374), but the Replicate-only gate meant
    -- the label stayed on "Connecting…" for an entire browse scan.
    if not (state.built and AH.Scan and AH.Scan.IsScanning()) then return end
    state.phase     = "requested"
    state.waitStart = GetTime()
    state.label:SetText(WaitLabel())
end)

-- Main drain finished and committed; gear-residue retries running (Phase 3).
--
-- ⚠ DELIBERATELY still gated on AH.Replicate, NOT the facade. Phase 3 is a cold-cache
-- gear-residue phase that only the replicate engine has -- Browse.lua:33 removes it entirely and
-- browse never fires this event. Routing this through AH.Scan would let a stray fire during a
-- browse scan enter a phase whose FinalizeStatus counts do not exist for that engine.
-- ah_scanprogress_test case 6 enforces this; if you "fix" it for consistency, that test fails.
AH.Events.On("AH_SCAN_FINALIZING", function()
    if not (state.built and AH.Replicate and AH.Replicate.IsScanning()) then return end
    state.finalizing = true
end)

AH.Events.On("AH_SCAN_COMPLETE", function(committed, rows)
    ShowTerminal(
        format("Scan complete — %d priced.", committed or 0),
        "done", 1)
end)

AH.Events.On("AH_SCAN_FAILED", function()
    ShowTerminal("Scan failed.", "fail", 1)
end)

-- AH closing aborts any in-flight scan (Replicate's AH_CLOSED handler tears down);
-- the bar should vanish immediately with it.
AH.Events.On("AH_CLOSED", function()
    HideNow()
end)

----------------------------------------------------------------
--  Public surface: demo hold + art probe (both v1.14.18)
--
--  These exist because the bar's APPEARANCE cannot be tested by the headless suite
--  (ah_scanprogress_test states this outright) and, before this, could only be seen by
--  running a real scan and waiting out the 15-minute floor between attempts. That made a
--  cosmetic iteration cost ~15 minutes and a screenshot caught in a ~30-second window.
----------------------------------------------------------------
AH.ScanProgress = AH.ScanProgress or {}

-- Park the bar in a fixed visual state until dismissed. Modes:
--   "run" (default) — determinate fill at `pct` with the "Scanning… N%" label
--   "wait"          — Phase-1 indeterminate: amber, animated sweep
--   "done" / "fail" — the terminal states, WITHOUT the auto-hide timer
--   "off"           — hide and return the bar to normal event-driven behaviour
-- Returns false if the bar could not be built (AH closed), so the caller can say why.
function AH.ScanProgress.Demo(mode, pct)
    mode = mode or "run"
    if mode == "off" then
        state.demo = nil
        HideNow()
        return true
    end
    Build()
    if not state.built then return false end
    CancelHide()
    state.finalizing = false
    state.phase      = nil
    state.waitStart  = nil
    state.demo       = mode

    if mode == "wait" then
        ApplyPhase("wait")
        state.bar:SetValue(0)
        state.sweepX = -SWEEP_W
        state.sweep:Show()
        state.label:SetText("Connecting…")
    else
        state.sweep:Hide()
        local v = tonumber(pct)
        if not v then v = 60 end
        if v < 0 then v = 0 elseif v > 100 then v = 100 end
        if mode == "fail" then
            ApplyPhase("fail")
            state.bar:SetValue(1)
            state.label:SetText("Scan failed.")
        elseif mode == "done" then
            ApplyPhase("done")
            state.bar:SetValue(1)
            state.label:SetText("Scan complete — 12345 priced.")
        else
            state.demo = "run"
            ApplyPhase("run")
            state.bar:SetValue(v / 100)
            state.label:SetText(format("Scanning… %d%%", floor(v)))
        end
    end

    state.frame:Show()
    ticker:Show()   -- only the demo branch runs; the engine gate is never reached
    return true
end

-- Report what the client actually gave us for the three bar atlases, plus the bar's live
-- rect. This is a MEASUREMENT, not a guess: the rounded-cap geometry depends on each
-- atlas's NATIVE size versus the rect we stretch it into, and that ratio is the one thing
-- the source cannot tell us. Consumed by `/ah diag`.
function AH.ScanProgress.ArtInfo()
    local out = {
        journeyArt = state.journeyArt,
        slice      = state.slice,
        sliceTrack = state.sliceTrack,
        sliceFrame = state.sliceFrame,
        sliceFill  = state.sliceFill,
        built      = state.built,
        atlases    = {},
    }
    for _, name in ipairs({ ATLAS_TRACK, ATLAS_FILL, ATLAS_FRAME }) do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        out.atlases[#out.atlases + 1] = {
            name   = name,
            ok     = info and true or false,
            width  = info and info.width or nil,
            height = info and info.height or nil,
        }
    end
    if state.bar then
        out.barW = state.bar:GetWidth()
        out.barH = state.bar:GetHeight()
    end
    out.frameW, out.frameH = W, H
    return out
end

----------------------------------------------------------------
--  /ah baratlas — VISUAL atlas probe (v1.14.18)
--
--  WHY THIS EXISTS: three attempts at rounding this bar failed, and all three rested on
--  ONE unverified assumption — that `ui-journeys-renown-progressbar-*` is a pill shape
--  with rounded caps and transparent corners. That was INFERRED from a screenshot of the
--  Delve card, never measured. `/ah diag` gave us native sizes but not SHAPE.
--
--  The trick is the MAGENTA backdrop: wherever the atlas is transparent, magenta shows
--  through. So a pill reads as a magenta rectangle with a coloured lozenge inside it, and
--  a plain rectangular atlas covers the magenta completely. That single distinction is
--  what decides whether rounding these ends is achievable at all.
--
--  Row 6 additionally shows the frame atlas WITH slice margins applied, to settle whether
--  SetTextureSliceMargins has any effect on an ATLAS-backed texture — `/ah bartune 9` and
--  `5` were visually identical, which suggests it does not.
----------------------------------------------------------------
local probeFrame

function AH.ScanProgress.AtlasProbe(show)
    if probeFrame and not show then probeFrame:Hide(); return true end

    if not probeFrame then
        -- No template: nothing here calls a backdrop method, and inheriting one only adds a
        -- dependency that can fail at CreateFrame.
        local f = CreateFrame("Frame", "VUIAHBarAtlasProbe", UIParent)
        f:SetSize(420, 260)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetColorTexture(0, 0, 0, 0.92)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", f, "TOP", 0, -8)
        title:SetText("Bar atlas probe — magenta = transparent")

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
        hint:SetText("drag to move  ·  /ah baratlas off to close")

        -- One row: magenta plate + the atlas drawn over it at the given size.
        local function Row(y, label, atlases, w, sliceMargin)
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y)
            fs:SetText(label)

            local plate = f:CreateTexture(nil, "BORDER")
            plate:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y - 14)
            plate:SetSize(w, H)
            plate:SetColorTexture(1, 0, 1, 1)   -- magenta: shows every transparent pixel

            for _, a in ipairs(atlases) do
                local t = f:CreateTexture(nil, "ARTWORK")
                t:SetPoint("TOPLEFT", plate, "TOPLEFT", 0, 0)
                t:SetSize(w, H)
                t:SetAtlas(a, false)
                if sliceMargin then ApplySlice(t, sliceMargin) end
            end
        end

        local NATIVE_W = 335   -- measured via /ah diag on 12.1.0
        Row(-26,  "1. BG          native " .. NATIVE_W .. "x18", { ATLAS_TRACK }, NATIVE_W)
        Row(-62,  "2. fill        native " .. NATIVE_W .. "x18", { ATLAS_FILL },  NATIVE_W)
        Row(-98,  "3. frame       native " .. NATIVE_W .. "x18", { ATLAS_FRAME }, NATIVE_W)
        Row(-134, "4. all three stacked, native", { ATLAS_TRACK, ATLAS_FILL, ATLAS_FRAME }, NATIVE_W)
        Row(-170, "5. all three stacked, OUR width " .. W .. "x18",
                  { ATLAS_TRACK, ATLAS_FILL, ATLAS_FRAME }, W)
        Row(-206, "6. frame at OUR width, sliced 9 (does slicing do anything?)",
                  { ATLAS_FRAME }, W, 9)

        probeFrame = f
    end

    probeFrame:Show()
    return true
end
