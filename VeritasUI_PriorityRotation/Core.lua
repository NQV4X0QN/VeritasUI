-- VeritasUI_PriorityRotation / Core.lua
-- One-button rotation cycler with per-spec profiles and action bar override.
--
-- Contract: All functions that modify secure state check InCombatLockdown
-- internally, so callers need not guard. Functions that only read state
-- or modify Lua-side data do not check combat.
--
-- ┌─ TAINT CONTRACT ──────────────────────────────────────────────────────────┐
-- │ Midnight 12.0 Secret Values: taint on any SecureActionButton propagates   │
-- │ to its entire execution context. Blizzard's cooldown/combat code then     │
-- │ throws "Secret values only allowed during untainted execution" in          │
-- │ Delves, M+, and raids.                                                    │
-- │                                                                            │
-- │ NAMING: `rotBtn` is PR's OWN SecureActionButton, created tainted at        │
-- │ load; nothing else shares its execution context, so PR writes its          │
-- │ attributes freely (see rotBtn:SetAttribute at load and in                  │
-- │ InjectSequence).  `btn` below means one of BLIZZARD's ActionButtons,       │
-- │ whose context Blizzard's own cooldown code depends on.  The two are        │
-- │ NOT interchangeable - that is the whole boundary this block guards.        │
-- │                                                                            │
-- │ SAFE from addon code:                                                      │
-- │   rotBtn:Execute(...)           — runs in the secure restricted env        │
-- │   SetOverrideBindingClick(...)  — does not touch button attributes         │
-- │   icon:SetTexture(...)          — unprotected rendering property           │
-- │                                                                            │
-- │ NEVER from addon code:                                                     │
-- │   btn:SetAttribute(...)         — taints the button's execution context    │
-- │   btn.icon:Show() / Hide()      — taints ActionButton children             │
-- │   any API call inside Execute() that touches protected game state          │
-- │                                                                            │
-- │ The secure execution core (WrapScript + newtable + Execute) is correct.   │
-- │ All historical breakage has been code AROUND it crossing this boundary.   │
-- └───────────────────────────────────────────────────────────────────────────┘

local ADDON_NAME, PR = ...
local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local ipairs          = ipairs
local pcall, tonumber = pcall, tonumber
local type, format    = type, string.format
local tconcat         = table.concat
local CreateFrame     = CreateFrame
local C_Timer         = C_Timer
local C_Spell         = C_Spell
local InCombatLockdown = InCombatLockdown
local GetActionInfo    = GetActionInfo
local GetMacroIndexByName = GetMacroIndexByName

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
PR.VERSION          = VUI.VERSION
PR.MAX_SLOTS        = 10
PR.MAX_ACTION_SLOT  = 180   -- Action Bar 8 ends at slot 180 (page 15 x 12)
PR.MACRO_NAME       = "Attack"
PR.BUTTON_NAME      = "PRAttackButton"
PR.compiledSequence = {}
PR.compiledNames    = {}   -- step → display name, built during compile
PR.overrides        = {}   -- [macroName] = { slot, keys } — populated by scan
PR.debug            = false
-- Diagnostic state — keys are the offending name/ID, value `true` means
-- "we have already warned about this one this session".  Cleared when
-- the underlying macro/spell becomes valid again so a subsequent
-- delete-and-recompile re-warns.  Survives until /reload.
PR._missingMacroWarned = {}
PR._missingSpellWarned = {}

----------------------------------------------------------------
--  Debug output — gated on PR.debug; never clutters normal play.
--  Toggle at runtime with /pr debug.
----------------------------------------------------------------
local function DebugPrint(msg)
    if PR.debug then VUI.Print("Priority Rotation", "|cFF888888[debug]|r " .. msg) end
end

----------------------------------------------------------------
--  "Cast on key down" — NOT ours to change (audit P2, v1.17.10)
--
--  The rotation needs ITS button to act on key release (see the PARITY note on the
--  WrapScript below). Until v1.17.9 that was done by forcing WoW's account-wide
--  ActionButtonUseKeyDown CVar to "0" at every login -- which changes every action bar for
--  every VeritasUI player, rotation user or not -- and to "1" when PR was disabled.
--  Blizzard lets each secure button decide for itself: SecureActionButton_ShouldUseOnKeyDown
--  reads the button's `useOnKeyDown` attribute and falls back to the CVar only when it is nil
--  (Blizzard_FrameXML/SecureTemplates.lua:795-803, used at :813-814). So rotBtn sets that
--  attribute below and the CVar is left to the player.
--
--  Because every user's value had been overwritten since PR existed, no personal choice
--  survives in it; it is put back to WoW's default ONCE (db.keyDownRestored), after combat if
--  needed. After that the player's own setting is never touched again.
----------------------------------------------------------------
function PR:RestoreKeyDownSettingOnce()
    if not self.db or self.db.keyDownRestored then return end
    VUI.CombatQueue.Add(function()
        local cv  = C_CVar
        local def = cv and cv.GetCVarDefault and cv.GetCVarDefault("ActionButtonUseKeyDown")
        if def and cv.GetCVar("ActionButtonUseKeyDown") ~= def then
            local ok = pcall(cv.SetCVar, "ActionButtonUseKeyDown", def)
            if not ok then return end   -- try again next login
            VUI.Print("Priority Rotation", "WoW's |cFFFFFF00cast on key down|r setting has been "
                .. "put back to its default. VeritasUI no longer changes it; set it in WoW's options "
                .. "as you like.")
        end
        PR.db.keyDownRestored = true
    end)
end

----------------------------------------------------------------
--  Scan scheduler — single cancellable handle, never piles up.
--
--  Any code path that needs to trigger a scan calls ScheduleScan.
--  A pending scan is always cancelled before a new one is set, so
--  only one scan timer exists at any given time. The callback
--  re-checks InCombatLockdown so a scan never fires mid-combat
--  regardless of when it was scheduled.
----------------------------------------------------------------
function PR:ScheduleScan(delay)
    if self._scanTimer then self._scanTimer:Cancel() end
    self._scanTimer = C_Timer.NewTimer(delay, function()
        self._scanTimer = nil
        if not InCombatLockdown() then self:ScanAndOverrideBarButton() end
    end)
end

----------------------------------------------------------------
--  Secure Action Button
----------------------------------------------------------------
local rotBtn = CreateFrame("Button", PR.BUTTON_NAME, UIParent,
    "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
rotBtn:SetAttribute("type", "macro")
-- Act on key RELEASE for this button only, whatever the player's account-wide setting says
-- (see RestoreKeyDownSettingOnce above for why the CVar is no longer used).
rotBtn:SetAttribute("useOnKeyDown", false)
rotBtn:SetAttribute("step", 1)
rotBtn:SetAttribute("macrotext", "")
rotBtn:RegisterForClicks("AnyUp", "AnyDown")
-- Must be shown for SetOverrideBindingClick to route clicks here.
-- Parked off-screen at 1×1 px so it's functionally invisible.
rotBtn:SetSize(1, 1)
rotBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
rotBtn:SetAlpha(0)
rotBtn:Show()

-- Initialize macros table immediately to prevent nil-access if
-- a click arrives before the first InjectSequence call.
rotBtn:Execute("macros = newtable(); macros[1] = ''")

-- PARITY BUG (found 2026-07-11, latent since inception): the keybind path
-- (SetOverrideBindingClick) delivers TWO clicks per physical press — key-down
-- and key-up — and this wrap ran on both, advancing two steps per press while
-- the cast fires only on the UP edge (this button's useOnKeyDown=false attribute;
-- until v1.17.10 the account-wide ActionButtonUseKeyDown=0). Result: every other
-- compiled step was silently discarded. The old clumping compiler masked it
-- (consecutive duplicate steps put every spell in both parity classes); the
-- v1.9.6 smooth-weave compiler exposed it as hard starvation — with an
-- even-length cycle the executed parity is FIXED, and any ability living
-- only on the other parity NEVER casts (observed in-game: Immolation Aura
-- silent for 40s). The `down` argument is standard in secure OnClick
-- snippets; gating on it consumes exactly one step per physical press, on
-- the same edge that casts — which also restores the "After" adjacency
-- guarantee (the follower step is the literal next executed step).
rotBtn:WrapScript(rotBtn, "OnClick", [=[
    if down then return end
    local step = tonumber(self:GetAttribute('step'))
    if not macros or #macros == 0 then return end
    self:SetAttribute('macrotext', macros[step] or '')
    step = step % #macros + 1
    self:SetAttribute('step', step)
]=])

PR.rotBtn = rotBtn

----------------------------------------------------------------
--  Debounced compile — editor changes batch into a single compile
----------------------------------------------------------------
function PR:ScheduleCompile()
    if self._compileTimer then self._compileTimer:Cancel() end
    self._compileTimer = C_Timer.NewTimer(0.3, function()
        self._compileTimer = nil
        self:CompileSequence()
    end)
end

----------------------------------------------------------------
--  Entry identity — stable key for an entry across sessions/reorders.
--  Used by the "After" (follows) feature: e.follows stores the TARGET
--  entry's key, so the link survives list reordering and re-adding the
--  same spell. Nil for entries that can't be identified.
----------------------------------------------------------------
function PR.EntryKey(e)
    if not e then return nil end
    if e.macroName then return "macro:" .. e.macroName end
    if e.itemID    then return "item:"  .. tostring(e.itemID) end
    if e.spellID   then return "spell:" .. tostring(e.spellID) end
    if e.spellName then return "spellname:" .. e.spellName end
    return nil
end

----------------------------------------------------------------
--  Smooth-Weave Compiler (v1.9.6 — replaces the clumping interleave)
--
--  WHY (design session 2026-07-11): PR is a BLIND stepper — the secure
--  snippet cannot see cooldowns, so the only lever for "cast X reliably
--  when it comes off cooldown" is HOW OFTEN the sequence attempts X.
--  Attempt economics are lopsided: a not-ready attempt costs one press
--  (~100ms at spam/hardware-repeat rates; the GCD throttles real
--  throughput, not presses), while a ready ability waiting for its next
--  step costs seconds of uptime. So high priority = attempted often,
--  and attempts must be SPREAD EVENLY. The old interleave appended
--  copies in blocks (freq 4 → four consecutive steps of the same
--  spell), guaranteeing dead-press runs and long gaps — the root of
--  "misses the window" complaints.
--
--  Placement: smooth weighted round-robin (the nginx algorithm) —
--  each slot, every entry gains its weight; the highest current wins
--  the slot and pays back the total. Deterministic, respects profile
--  order on ties, and yields per-entry gaps as even as arithmetic
--  allows (weight 4 of total 10 → attempted every 2-3 steps).
--
--  Follow-up pairing ("After" column): an entry with e.follows set is
--  ALSO emitted immediately after every occurrence of its target, on
--  top of its own weighted placement. This is the class-agnostic form
--  of "Blade Dance must land within 6s of Eye Beam": whenever the
--  target actually casts, the very next press attempts the follower.
--  Followers cascade (A after B after C) with a per-step visited guard
--  so a cycle in hand-edited data cannot loop. Adjacent duplicate
--  steps are collapsed (identical macrotext back-to-back adds nothing).
--
--  Constraints this design honors (memory: pr-rotation-constraints):
--  castsequence and multi-line /cast fallback are both falsified by
--  in-game testing — everything here is plain single-/cast steps,
--  the same runtime mechanics PR has always used.
----------------------------------------------------------------
function PR:CompileSequence()
    if not self.db then return end
    if InCombatLockdown() then
        -- Dedup: only one compile queued at a time; flag clears when it fires.
        if not self._compileQueued then
            self._compileQueued = true
            VUI.CombatQueue.Add(function()
                PR._compileQueued = false
                PR:CompileSequence()
            end)
        end
        return
    end

    local seq, names = {}, {}
    local profile = self:CurrentProfile()
    -- Reacquire prefix — prepended to spell steps only when the profile
    -- opts in. `/cleartarget [dead]` drops a corpse; `/targetenemy
    -- [noexists]` then grabs the nearest enemy only when you have no
    -- target. A live, manually-chosen target satisfies neither condition,
    -- so it is never overridden — the sole triggers are target death and
    -- your own tab/click. Macro and item steps are left untouched (macros
    -- may carry their own @mouseover/@focus targeting; trinkets need no
    -- target). These are ordinary secure macro commands run through the
    -- existing macrotext path — no new taint surface.
    local reacqPrefix = (profile and profile.reacquire)
        and "/cleartarget [dead]\n/targetenemy [noexists]\n" or ""
    if profile and profile.spells and #profile.spells > 0 then
        local entries = {}   -- resolved steps: { text, name, key, weight, follows }
        for _, e in ipairs(profile.spells) do
            if e then
                local macrotext, entryName
                if e.macroName then
                    local mName, mIcon, mBody = GetMacroInfo(e.macroName)
                    if mBody and mBody ~= "" then
                        macrotext = mBody
                        entryName = "[MACRO:" .. (mName or e.macroName) .. "]"
                        if mIcon then e.icon = mIcon end   -- keep editor icon current
                        -- Macro is back; reset warning state so a future
                        -- delete-and-recompile warns again.
                        PR._missingMacroWarned[e.macroName] = nil
                    elseif not PR._missingMacroWarned[e.macroName] then
                        -- Macro has been deleted or renamed since the entry
                        -- was authored.  Without this warning the entry is
                        -- silently elided from the rotation and the user
                        -- has no signal that anything is wrong.
                        PR._missingMacroWarned[e.macroName] = true
                        VUI.Print("Priority Rotation", format(
                            "|cFFFF8800Missing macro|r |cFFFFFF00%s|r — entry skipped this session. Recreate the macro in |cFFFFFF00/macro|r.",
                            e.macroName))
                    end
                elseif e.itemID then
                    local useTarget = e.itemName
                    if not useTarget or useTarget == "" then
                        useTarget = "item:" .. tostring(e.itemID)
                    end
                    macrotext = "/use " .. (e.combatOnly and "[combat, nochanneling] "
                        or "[nochanneling] ") .. useTarget
                    entryName = "[ITEM:" .. (e.itemName or tostring(e.itemID)) .. "]"
                elseif e.spellName then
                    -- Validate spellID resolves; stale IDs would otherwise
                    -- emit /cast lines that surface as "Unknown spell"
                    -- chat noise at every key press, with no diagnostic.
                    -- Skip and warn once per session per stale ID.  A
                    -- missing spellID (older profile entry) is allowed
                    -- through unchanged — only stored IDs are validated.
                    local stale = false
                    if e.spellID then
                        local info = C_Spell.GetSpellInfo(e.spellID)
                        if info == nil then stale = true end
                    end
                    if not stale then
                        -- CHANNEL PROTECTION (2026-07-11, verified in-game): a press
                        -- landing mid-channel CLIPS the channel tail at GCD-end —
                        -- one unprotected Throw Glaive macro cost every Eye Beam its
                        -- full-channel bonus and ~4-6k DPS before it was found. The
                        -- user's hand-built macros have always carried
                        -- [nochanneling]; spell entries compiled here must get the
                        -- same protection or raw-spell profiles clip. A press during
                        -- a channel becomes a no-op; the channel completes; the next
                        -- press casts normally. Macro entries are NOT touched —
                        -- their bodies (and conditionals) belong to the user.
                        --
                        -- COMBAT GATE (v1.9.7): per-entry opt-in [combat] — the
                        -- Editor's "Combat" checkbox. Replicates the user's
                        -- hand-macro convention [combat, nochanneling] so profiles
                        -- no longer need hand-built macros at all; the entry left
                        -- unchecked is the designated opener (castable out of
                        -- combat to start the fight).
                        macrotext = reacqPrefix .. "/cast "
                            .. (e.combatOnly and "[combat, nochanneling] "
                                or "[nochanneling] ") .. e.spellName
                        entryName = e.spellName
                        if e.spellID then
                            PR._missingSpellWarned[e.spellID] = nil
                        end
                    elseif not PR._missingSpellWarned[e.spellID] then
                        PR._missingSpellWarned[e.spellID] = true
                        VUI.Print("Priority Rotation", format(
                            "|cFFFF8800Stale spell|r |cFFFFFF00%s|r (ID %d) — entry skipped this session. Drag the current version of the spell back onto the slot.",
                            e.spellName, e.spellID))
                    end
                end

                if macrotext then
                    local weight = e.freq or 1
                    if weight < 1 then weight = 1 elseif weight > 5 then weight = 5 end
                    entries[#entries + 1] = {
                        text    = macrotext,
                        name    = entryName,
                        key     = PR.EntryKey(e),
                        weight  = weight,
                        follows = e.follows,
                        current = 0,   -- smooth-WRR accumulator
                    }
                end
            end
        end

        -- Smooth weighted round-robin: cycle length = sum of weights;
        -- ipairs order makes tie-breaking stable in profile order.
        local total = 0
        for _, it in ipairs(entries) do total = total + it.weight end
        local base = {}
        for _ = 1, total do
            local best
            for _, it in ipairs(entries) do
                it.current = it.current + it.weight
                if not best or it.current > best.current then best = it end
            end
            best.current = best.current - total
            base[#base + 1] = best
        end

        -- Follower map: target key → followers in profile order. A follows
        -- link whose target isn't in the compiled list is inert (the target
        -- was removed or elided) — re-adding the same spell reactivates it.
        local followersOf
        for _, it in ipairs(entries) do
            if it.follows then
                followersOf = followersOf or {}
                local l = followersOf[it.follows]
                if not l then l = {}; followersOf[it.follows] = l end
                l[#l + 1] = it
            end
        end

        -- Emit with cascading follower insertion. `visited` is per base
        -- step so chains (A after B after C) expand fully but a cycle in
        -- hand-edited data terminates. Identical back-to-back steps are
        -- collapsed — a duplicate adds nothing at runtime (same macrotext),
        -- and skipping its cascade is correct because the surviving copy
        -- already cascaded the same follower set.
        local function Emit(it, visited)
            if seq[#seq] == it.text then return end
            seq[#seq + 1] = it.text
            names[#seq]   = it.name
            local fl = followersOf and it.key and followersOf[it.key]
            if fl then
                for _, f in ipairs(fl) do
                    if not visited[f] then
                        visited[f] = true
                        Emit(f, visited)
                    end
                end
            end
        end
        for _, it in ipairs(base) do
            Emit(it, { [it] = true })
        end

        -- Cycle wrap-around collapse. The sequence is CYCLIC — the secure
        -- snippet advances with `step % #macros + 1` — so the last step and
        -- the first are adjacent at runtime as well, and that is the one
        -- adjacent pair the peephole in Emit never compares. Left unhandled,
        -- {A freq 3, B freq 1} compiles to [A, B, A] and plays
        -- A,B,A,A,B,A… — a dead duplicate press every cycle, which is exactly
        -- the clumping the v1.9.6 redesign exists to remove. It happens
        -- whenever the top-weight entry also wins the final slot, i.e. the
        -- normal case.
        --
        -- Dropping the LAST step is safe here precisely BECAUSE the two texts
        -- are identical. If that step was a follower emitted for "After"
        -- adjacency, the wrap now lands on seq[1], which carries the same
        -- macrotext — so "the follower is the literal next executed step"
        -- still holds for the target that ends the cycle. And exactly one drop
        -- can ever be needed: Emit guarantees no two consecutive steps match,
        -- so the new last step cannot equal seq[1] either.
        if #seq > 1 and seq[#seq] == seq[1] then
            names[#seq] = nil
            seq[#seq]   = nil
        end
    end

    self.compiledSequence = seq
    self.compiledNames    = names
    self:InjectSequence(seq)
    self:ScheduleScan(0.5)
    -- The editor redraws the instant a change is made, but the compile it triggers is debounced
    -- (ScheduleCompile, 0.3 s), so without this the preview showed the PREVIOUS sequence until
    -- something else redrew it (audit P4).
    self:RefreshUI()
    DebugPrint("Compiled " .. #seq .. " step(s)")
end

-- Returns a Lua long-string literal that safely embeds any string content,
-- including those containing ]] or ]=] sequences. Scans for the minimum
-- nesting level whose closing delimiter does not appear in the string.
local function SafeQuote(s)
    local level = 0
    while s:find("]" .. string.rep("=", level) .. "]", 1, true) do
        level = level + 1
    end
    local eq = string.rep("=", level)
    return "[" .. eq .. "[" .. s .. "]" .. eq .. "]"
end

function PR:InjectSequence(seq)
    if InCombatLockdown() then return end
    if #seq > 0 then
        local lines = { "macros = newtable()" }
        for i, macro in ipairs(seq) do
            lines[#lines + 1] = "macros[" .. i .. "] = " .. SafeQuote(macro)
        end
        rotBtn:Execute(tconcat(lines, "\n"))
        rotBtn:SetAttribute("macrotext", seq[1])
    else
        rotBtn:Execute("macros = newtable()\nmacros[1] = ''")
        rotBtn:SetAttribute("macrotext", "")
    end
    rotBtn:SetAttribute("step", 1)
end

----------------------------------------------------------------
--  Macro Stub
--
--  Returns true on success, false on failure. Silent combat-lockdown
--  no-op returns false; callers that surface a success message should
--  gate it on the return value.
--
--  ⚠ OWNERSHIP (audit P1, v1.17.10): "Attack" is an ordinary macro name, so a macro by that
--  name is only OURS if its body clicks our button. This used to run at every login for every
--  player, created the macro whether or not the rotation was set up, and overwrote any macro of
--  the player's own that happened to be called Attack -- then bound the rotation to its key.
--  Now: `create` is true only for an explicit request (/pr macro, the Create / Update button);
--  the login refresh only ever edits a macro that is already ours, and a foreign one is never
--  written to or bound.
----------------------------------------------------------------
-- 1 = ours, 0 = no macro by that name, -1 = a different macro holds the name. Second return is
-- the macro index when one exists.
function PR:StubState()
    local idx = GetMacroIndexByName(self.MACRO_NAME)
    if not idx or idx == 0 then return 0 end
    local _, _, body = GetMacroInfo(idx)
    if type(body) == "string" and body:find("/click " .. self.BUTTON_NAME, 1, true) then
        return 1, idx
    end
    return -1, idx
end

local FOREIGN_ATTACK_MSG = "|cFFFF8800A macro named |cFFFFFF00Attack|r already exists and isn't the "
    .. "rotation's.|r It has been left alone. Rename it in |cFFFFFF00/macro|r, then click "
    .. "|cFFFFFF00Create / Update Macro|r."

function PR:UpdateMacroStub(create)
    if InCombatLockdown() then return false end

    local state, idx = self:StubState()
    if state == -1 then
        if create or not self._foreignWarned then
            self._foreignWarned = true
            VUI.Print("Priority Rotation", FOREIGN_ATTACK_MSG)
        end
        return false
    end
    if state == 0 and not create then return false end

    local macroBody = "#showtooltip\n/click " .. self.BUTTON_NAME
    local macroIcon = "ability_warrior_charge"
    local profile   = self:CurrentProfile()
    if profile and profile.spells and profile.spells[1] and profile.spells[1].icon then
        macroIcon = profile.spells[1].icon
    end

    if state == 1 then
        -- pcall-wrap the EditMacro write — historically reliable but the
        -- macro frame can be in a transient state during /reload bursts
        -- or addon-driven CreateMacro pile-ups; a hard error here would
        -- leave the user with a vague Lua popup instead of a clean
        -- 'try again in a moment' message.  Matches the failure-return
        -- contract used by the macro-list-full branch below.
        local ok, err = pcall(EditMacro, idx, self.MACRO_NAME, macroIcon, macroBody)
        if not ok then
            VUI.Print("Priority Rotation",
                "|cFFFF4444Couldn't update the Attack macro|r — "
                .. tostring(err))
            return false
        end
        return true
    else
        if GetNumMacros() < (MAX_ACCOUNT_MACROS or 120) then
            -- pcall-wrap CreateMacro for the same reason v1.6.39 wrapped
            -- EditMacro in the sibling branch above — the macro frame can
            -- be in a transient state during /reload bursts.  Mirrors the
            -- failure-return contract from EditMacro and the macro-
            -- list-full branch below.
            local ok, err = pcall(CreateMacro, self.MACRO_NAME, macroIcon, macroBody)
            if not ok then
                VUI.Print("Priority Rotation",
                    "|cFFFF4444Couldn't create the Attack macro|r — "
                    .. tostring(err))
                return false
            end
            return true
        else
            VUI.Print("Priority Rotation",
                "|cFFFF4444Can't create the Attack macro — your account macro list is full "
                .. "(120/120).|r Delete an unused macro in |cFFFFFF00/macro|r, then try again.")
            return false
        end
    end
end

----------------------------------------------------------------
--  Action Bar Keybind Override
--
--  Redirects the bar button containing a macro so that pressing its
--  keybind clicks rotBtn instead. Works with any bar — visible,
--  hidden, or tucked away.
--
--  Slot mapping (audit P3, v1.17.10 — sourced, Blizzard_ActionBar/Shared/MultiActionBars.lua:1-8
--  and MultiActionBars.xml actionpage attributes): Action Bar 1 = slots 1-12; Bars 2-5 =
--  pages 6/5/3/4 = slots 61-72, 49-60, 25-36, 37-48; Bars 6-8 = pages 13/14/15 = slots
--  145-180. UNMAPPED on purpose: 13-24 (main bar page 2) and 73-144 (the bonus pages WoW swaps
--  in for druid forms, stealth, etc.) -- a key bound there belongs to the main bar, so no
--  binding of ours can stand in for it. Until v1.17.10 slots 73-120 were mapped to Bars 6-8
--  (wrong: that bound the rotation to an unrelated Bar 6-8 key) and 121-180 were never scanned.
--
--  Direct mouse clicks still work via the macro's /click PRAttackButton.
--
--  ScanAndOverrideBarButton accepts an optional macroName so the same
--  scan machinery can support additional macros in the future (e.g. an
--  interrupt rotation) without structural changes. ClearOverride clears
--  all override bindings for SECURE_HANDLER — with a single macro this
--  is correct; future multi-macro support would re-apply remaining
--  overrides here after removing the requested one.
----------------------------------------------------------------
local SECURE_HANDLER = CreateFrame("Frame", "PRSecureHandler", nil, "SecureHandlerBaseTemplate")

local SLOT_TO_BIND = {}
local BIND_DEFS = {
    { base =   0, bind = "ACTIONBUTTON" },
    { base =  24, bind = "MULTIACTIONBAR3BUTTON" },
    { base =  36, bind = "MULTIACTIONBAR4BUTTON" },
    { base =  48, bind = "MULTIACTIONBAR2BUTTON" },
    { base =  60, bind = "MULTIACTIONBAR1BUTTON" },
    { base = 144, bind = "MULTIACTIONBAR5BUTTON" },
    { base = 156, bind = "MULTIACTIONBAR6BUTTON" },
    { base = 168, bind = "MULTIACTIONBAR7BUTTON" },
}
for _, def in ipairs(BIND_DEFS) do
    for i = 1, 12 do
        SLOT_TO_BIND[def.base + i] = def.bind .. i
    end
end

function PR:ClearOverride(macroName)
    if InCombatLockdown() then
        VUI.CombatQueue.Add(function() PR:ClearOverride(macroName) end)
        return
    end
    ClearOverrideBindings(SECURE_HANDLER)
    if macroName then
        self.overrides[macroName] = nil
    else
        self.overrides = {}
    end
    DebugPrint("ClearOverride" .. (macroName and " (" .. macroName .. ")" or " (all)"))
end

function PR:ScanAndOverrideBarButton(macroName, verbose)
    macroName = macroName or self.MACRO_NAME
    if InCombatLockdown() or not self:IsEnabled() then return end

    -- Only a macro that is ours (see StubState). A different macro called Attack is the player's;
    -- taking over its key would hijack whatever it does.
    local state, macroIdx = self:StubState()
    if state ~= 1 then
        if state == -1 then
            -- Drop any binding left from when the name was still ours (body edited mid-session).
            self:ClearOverride(macroName)
            if verbose then VUI.Print("Priority Rotation", FOREIGN_ATTACK_MSG) end
        end
        return
    end

    self:ClearOverride(macroName)

    -- Midnight Secret Values: GetActionInfo can return secret values in
    -- raid/M+ zones; pcall each slot and count failures. Verbose callers
    -- (user-initiated /pr scan and "Scan & Bind" button) surface the
    -- diagnostic so the user knows what to do.
    -- A bindable copy wins over an unbindable one found earlier (e.g. Attack on a form page AND
    -- on Bar 6), so the scan does not stop at the first match.
    local foundSlot
    local unreadableSlots = 0
    for slot = 1, PR.MAX_ACTION_SLOT do
        local ok, actionType, id = pcall(GetActionInfo, slot)
        if ok then
            if actionType == "macro" and id == macroIdx then
                if SLOT_TO_BIND[slot] then foundSlot = slot; break end
                foundSlot = foundSlot or slot
            end
        else
            unreadableSlots = unreadableSlots + 1
        end
    end

    if not foundSlot then
        if verbose and unreadableSlots > 0 then
            VUI.Print("Priority Rotation",
                format("|cFFFF8800Scan incomplete:|r %d slot(s) unreadable "
                    .. "(likely Midnight Secret Values in raid / M+). "
                    .. "Re-run |cFFFFFF00/pr scan|r after leaving the encounter, "
                    .. "or move the Attack macro to a different bar.",
                    unreadableSlots))
        end
        DebugPrint("Scan: " .. macroName .. " not found (" .. unreadableSlots .. " unreadable slots)")
        return
    end

    -- Keybinding override — the sole click-routing mechanism.
    local bindingCmd = SLOT_TO_BIND[foundSlot]
    local boundKeys  = {}
    if bindingCmd then
        local k1, k2 = GetBindingKey(bindingCmd)
        if k1 then boundKeys[#boundKeys + 1] = k1 end
        if k2 then boundKeys[#boundKeys + 1] = k2 end
    end

    self.overrides[macroName] = {
        slot = foundSlot,
        keys = #boundKeys > 0 and boundKeys or nil,
    }

    if #boundKeys > 0 then
        for _, key in ipairs(boundKeys) do
            SetOverrideBindingClick(SECURE_HANDLER, false, key, PR.BUTTON_NAME)
        end
        DebugPrint("Scan: " .. macroName .. " bound to " .. tconcat(boundKeys, ", "))
    else
        DebugPrint("Scan: " .. macroName .. " found on slot " .. foundSlot .. " — no keybind")
    end
end

----------------------------------------------------------------
--  UI Refresh — called by Settings.lua and event handlers
----------------------------------------------------------------
function PR:RefreshUI()
    if self.Editor then self.Editor:Refresh() end
    if self.MainWindow and self.MainWindow.RefreshBadge then
        self.MainWindow:RefreshBadge()
    end
end

----------------------------------------------------------------
--  Event Handler
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- UPDATE_MACROS fires when any macro is created, edited, deleted, or
-- reordered.  We re-run the compile so the missing-macro warning (v1.6.39)
-- surfaces immediately on external deletion (the user has no other
-- trigger; PR's own editor is debounced separately).  ScheduleCompile's
-- 0.3s debounce coalesces editor bursts (rapid save/rename/reorder) into
-- a single recompile, and CompileSequence's `if not self.db then return`
-- guard makes any early fire (before ADDON_LOADED) a no-op.
ef:RegisterEvent("UPDATE_MACROS")
-- PLAYER_REGEN_ENABLED is owned by VUI.CombatQueue (Lib.lua).
-- All deferred post-combat actions go through VUI.CombatQueue.Add().

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        PR:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        PR:RestoreKeyDownSettingOnce()
        PR:SwitchToCurrentSpec()
        PR:CompileSequence()
        PR._lastProfileKey = PR:GetProfileKey()
        -- Icon refresh only, and only for the rotation's own macro (create = false).
        C_Timer.After(2, function() if PR:IsEnabled() then PR:UpdateMacroStub(false) end end)
        PR:ScheduleScan(4)
        VUI.Print("Priority Rotation",
            format("v%s loaded — |cFFFFFF00/pr|r", PR.VERSION))

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local newKey = PR:GetProfileKey()
        if newKey == PR._lastProfileKey then return end
        PR._lastProfileKey = newKey

        PR:SwitchToCurrentSpec()
        PR:CompileSequence()
        VUI.Print("Priority Rotation",
            format("Switched to |cFFFFFF00%s|r.", PR:GetCurrentSpecLabel()))
        PR:RefreshUI()
        PR:ScheduleScan(1)

    elseif event == "UPDATE_MACROS" then
        -- Route through ScheduleCompile so editor bursts (rapid
        -- save/rename/reorder) collapse into one recompile 0.3s after
        -- the last fire.  CompileSequence then surfaces its missing-macro warning
        -- for any rotation entry whose macro was deleted, and the now-
        -- missing entry is elided so the rotation continues working
        -- with whatever else is in the profile.
        PR:ScheduleCompile()
    end
end)

----------------------------------------------------------------
--  Slash Commands
----------------------------------------------------------------
SLASH_VERITASUI_PR1 = "/pr"
SLASH_VERITASUI_PR2 = "/priorityrotation"

SlashCmdList["VERITASUI_PR"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "settings" then
        if PR.settingsCategoryID then
            Settings.OpenToCategory(PR.settingsCategoryID)
        else
            -- Settings.lua hasn't reached its category-registration line
            -- yet (rare: typing /pr settings during the PLAYER_LOGIN
            -- burst before Settings panel init completes).  Friendly
            -- message instead of Settings.OpenToCategory(nil) error.
            VUI.Print("Priority Rotation",
                "Priority Rotation is still loading — try again in a moment.")
        end

    elseif cmd == "clear" then
        PR:CurrentProfile().spells = {}
        PR:CompileSequence()
        PR:RefreshUI()
        VUI.Print("Priority Rotation", "Spell list cleared.")

    elseif cmd == "reset" then
        PR:ResetCurrentProfileToDefault()
        PR:CompileSequence()
        PR:RefreshUI()
        VUI.Print("Priority Rotation", "Reset to spec defaults.")

    elseif cmd == "scan" then
        if InCombatLockdown() then
            VUI.Print("Priority Rotation", "|cFFFF4444Can't scan in combat.|r")
            return
        end
        PR:ScanAndOverrideBarButton(PR.MACRO_NAME, true)
        -- A foreign "Attack" was already explained by the scan; the not-found advice below
        -- would contradict it.
        if PR:StubState() == -1 then return end
        local override = PR.overrides[PR.MACRO_NAME]
        if override and override.keys then
            VUI.Print("Priority Rotation",
                "Keybind |cFF00FF00" .. tconcat(override.keys, ", ")
                .. "|r override active — spam the key to play.")
        elseif override and not SLOT_TO_BIND[override.slot] then
            -- Slots 13-24 (main bar page 2) and 73-144 (form/stealth bonus pages), which
            -- SLOT_TO_BIND deliberately does not map. They arrive here in the same
            -- keys == nil state as an unbound main-bar slot, but the advice below is
            -- useless for them: no key assigned to such a slot produces a binding this
            -- code can override, so the user could follow it forever. Druid form bars
            -- and the rogue stealth bar are ordinary places to park a macro.
            VUI.Print("Priority Rotation",
                "|cFFFF8800Found on slot " .. override.slot
                .. "|r — that bar page can't be bound. Move the macro to a main bar.")
        elseif override then
            VUI.Print("Priority Rotation",
                "|cFFFF8800Found on slot " .. override.slot
                .. "|r but no keybind — assign a key to that bar slot, then /pr scan.")
        else
            VUI.Print("Priority Rotation",
                "|cFFFF8800Not found.|r Put |cFFFFFF00"
                .. PR.MACRO_NAME .. "|r macro on any action bar (visible or hidden) "
                .. "with a keybind, then /pr scan")
        end

    elseif cmd == "macro" then
        if InCombatLockdown() then
            VUI.Print("Priority Rotation", "|cFFFF4444Can't create macro in combat.|r")
            return
        end
        if PR:UpdateMacroStub(true) then
            VUI.Print("Priority Rotation",
                "Macro |cFFFFFF00" .. PR.MACRO_NAME
                .. "|r is ready — drag it from /macro to an action bar.")
        end
        -- On failure, UpdateMacroStub already printed the specific reason.

    elseif cmd == "status" then
        local function yn(v) return v and "|cFF00FF00yes|r" or "|cFFFF4444no|r" end
        local stubState  = PR:StubState()
        local macroExists = stubState == 1
        local override   = PR.overrides[PR.MACRO_NAME]
        VUI.Print("Priority Rotation", "Status:")
        VUI.Print("Priority Rotation", "  Enabled:  " .. yn(PR:IsEnabled()))
        VUI.Print("Priority Rotation", "  Macro:    " .. yn(macroExists)
            .. (macroExists and "" or (stubState == -1
                and "  — another macro is named Attack; rename it"
                or  "  — run |cFFFFFF00/pr macro|r")))
        VUI.Print("Priority Rotation", "  On bar:   " .. (override
            and "|cFF00FF00slot " .. override.slot .. "|r"
            or  "|cFFFF4444no|r  — run |cFFFFFF00/pr scan|r"))
        VUI.Print("Priority Rotation", "  Keybind:  " .. ((override and override.keys)
            and "|cFF00FF00" .. tconcat(override.keys, ", ") .. "|r"
            or  "|cFFFF8800none|r — assign a key to the macro's bar slot"))
        VUI.Print("Priority Rotation", "  Compiled: " .. #PR.compiledSequence .. " step(s)")

    elseif cmd == "debug" then
        PR.debug = not PR.debug
        VUI.Print("Priority Rotation",
            "Debug " .. (PR.debug and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r"))

    elseif cmd == "test" then
        VUI.Print("Priority Rotation", "Diagnostic:")
        local p = PR:CurrentProfile()
        if not p then VUI.Print("Priority Rotation", "  |cFFFF4444No profile!|r"); return end
        VUI.Print("Priority Rotation", "  Spec: |cFFFFFF00" .. PR:GetCurrentSpecLabel() .. "|r")
        VUI.Print("Priority Rotation", "  Compiled: |cFFFFFF00" .. #PR.compiledSequence .. " steps|r")
        for i, s in ipairs(PR.compiledSequence) do
            local label = PR.compiledNames and PR.compiledNames[i] or s
            VUI.Print("Priority Rotation", "    " .. i .. ". " .. label)
            -- With debug on, show the step's ACTUAL macrotext so compiled
            -- conditionals ([nochanneling], reacquire lines) are verifiable
            -- in-game instead of inferred from behavior (2026-07-11: the
            -- channel-protection rollout was untestable without this).
            if PR.debug then
                for line in s:gmatch("[^\n]+") do
                    VUI.Print("Priority Rotation", "       |cFF888888" .. line .. "|r")
                end
            end
        end
        local override = PR.overrides[PR.MACRO_NAME]
        if override and override.keys then
            VUI.Print("Priority Rotation", "  Keybind: |cFF00FF00" .. tconcat(override.keys, ", ") .. "|r")
        elseif override then
            VUI.Print("Priority Rotation", "  Macro slot: |cFFFF8800" .. override.slot .. "|r (no keybind)")
        else
            VUI.Print("Priority Rotation", "  Override: |cFFFF8800not active|r")
        end

    elseif cmd == "diag" then
        local patch = (GetBuildInfo and select(1, GetBuildInfo())) or "?"
        VUI.Print("Priority Rotation", "|cFFFFFF00" .. patch .. " API Diagnostic|r")
        VUI.Print("Priority Rotation", "─────────────────────────────────────────")

        local G = "|cFF00FF00"
        local R = "|cFFFF4444"
        local Y = "|cFFFFFF00"
        local E = "|r"

        local hasIssecret = type(issecretvalue) == "function"
        VUI.Print("Priority Rotation", "  issecretvalue():          " .. (hasIssecret and G.."available"..E or R.."NOT FOUND"..E))

        -- luacheck: ignore 143 (table.freeze is a deliberate feature-probe)
        local hasFreeze = type(table.freeze) == "function"
        VUI.Print("Priority Rotation", "  table.freeze():           " .. (hasFreeze and G.."available"..E or Y.."not found"..E))

        local hasRegBtn = C_ActionBar and type(C_ActionBar.RegisterActionUIButton) == "function"
        VUI.Print("Priority Rotation", "  C_ActionBar.RegisterActionUIButton: " .. (hasRegBtn and G.."available"..E or R.."NOT FOUND"..E))

        local hasUnregBtn = C_ActionBar and type(C_ActionBar.UnregisterActionUIButton) == "function"
        VUI.Print("Priority Rotation", "  C_ActionBar.UnregisterActionUIButton: " .. (hasUnregBtn and G.."available"..E or R.."NOT FOUND"..E))

        local hasSecrets = C_Secrets and type(C_Secrets) == "table"
        VUI.Print("Priority Rotation", "  C_Secrets namespace:      " .. (hasSecrets and G.."available"..E or R.."NOT FOUND"..E))

        local hasRestrict = C_RestrictedActions and type(C_RestrictedActions) == "table"
        VUI.Print("Priority Rotation", "  C_RestrictedActions:       " .. (hasRestrict and G.."available"..E or R.."NOT FOUND"..E))

        VUI.Print("Priority Rotation", "─────────────────────────────────────────")
        -- Write-permission probe: write back the CVar's CURRENT value. It is the
        -- player's own setting, so a diagnostic must never change it; a same-value
        -- SetCVar still exercises write lockdown, which is all this probe tests.
        local cvarCur = C_CVar.GetCVar("ActionButtonUseKeyDown")
        local cvarOk, cvarErr = pcall(C_CVar.SetCVar, "ActionButtonUseKeyDown", cvarCur or "0")
        if cvarOk then
            VUI.Print("Priority Rotation", "  SetCVar ActionButtonUseKeyDown: " .. G .. "OK" .. E)
        else
            VUI.Print("Priority Rotation", "  SetCVar ActionButtonUseKeyDown: " .. R .. "BLOCKED" .. E)
            VUI.Print("Priority Rotation", "    Error: " .. Y .. tostring(cvarErr) .. E)
        end

        local execOk, execErr = pcall(function()
            PR.rotBtn:Execute("local t = newtable(); t[1] = 'diag_test'")
        end)
        if execOk then
            VUI.Print("Priority Rotation", "  :Execute() newtable():    " .. G .. "OK" .. E)
        else
            VUI.Print("Priority Rotation", "  :Execute() newtable():    " .. R .. "BLOCKED" .. E)
            VUI.Print("Priority Rotation", "    Error: " .. Y .. tostring(execErr) .. E)
        end

        local macroOk, macroResult = pcall(GetMacroIndexByName, PR.MACRO_NAME)
        if macroOk then
            local idx = macroResult or 0
            if idx > 0 then
                VUI.Print("Priority Rotation", "  GetMacroIndexByName(\"" .. PR.MACRO_NAME .. "\"): " .. G .. "idx=" .. idx .. E)
            else
                VUI.Print("Priority Rotation", "  GetMacroIndexByName(\"" .. PR.MACRO_NAME .. "\"): " .. Y .. "not found (idx=0)" .. E)
            end
            if hasIssecret and issecretvalue(macroResult) then
                VUI.Print("Priority Rotation", "    ⚠ macroIndex is a |cFFFF8800SECRET VALUE|r")
            end
        else
            VUI.Print("Priority Rotation", "  GetMacroIndexByName: " .. R .. "ERROR" .. E .. " — " .. tostring(macroResult))
        end

        VUI.Print("Priority Rotation", "─────────────────────────────────────────")
        VUI.Print("Priority Rotation", "  Scanning slots 1-" .. PR.MAX_ACTION_SLOT .. " with GetActionInfo:")
        local macroIdx    = macroOk and macroResult or 0
        local foundSlots  = 0
        local macroSlots  = {}
        local secretSlots = 0
        local errorSlots  = 0

        for slot = 1, PR.MAX_ACTION_SLOT do
            local ok, actionType, id = pcall(GetActionInfo, slot)
            if ok then
                if actionType then
                    foundSlots = foundSlots + 1
                    if hasIssecret then
                        local typeSecret = issecretvalue(actionType)
                        local idSecret   = issecretvalue(id)
                        if typeSecret or idSecret then
                            secretSlots = secretSlots + 1
                            if secretSlots <= 5 then
                                VUI.Print("Priority Rotation", "    Slot " .. Y .. slot .. E .. ": type="
                                    .. (typeSecret and "|cFFFF8800<SECRET>|r" or tostring(actionType))
                                    .. "  id="
                                    .. (idSecret and "|cFFFF8800<SECRET>|r" or tostring(id)))
                            end
                        end
                    end
                    if actionType == "macro" and id == macroIdx and macroIdx > 0 then
                        macroSlots[#macroSlots + 1] = slot
                    end
                end
            else
                errorSlots = errorSlots + 1
                if errorSlots <= 3 then
                    VUI.Print("Priority Rotation", "    Slot " .. Y .. slot .. E .. ": " .. R .. "ERROR" .. E .. " — " .. tostring(actionType))
                end
            end
        end

        VUI.Print("Priority Rotation", "  Summary:")
        VUI.Print("Priority Rotation", "    Populated slots: " .. Y .. foundSlots .. E)
        VUI.Print("Priority Rotation", "    Secret values:   " .. (secretSlots > 0 and R .. secretSlots .. E or G .. "0" .. E))
        if secretSlots > 5 then
            VUI.Print("Priority Rotation", "      (showing first 5 of " .. secretSlots .. ")")
        end
        VUI.Print("Priority Rotation", "    Errored slots:   " .. (errorSlots > 0 and R .. errorSlots .. E or G .. "0" .. E))
        if #macroSlots > 0 then
            VUI.Print("Priority Rotation", "    \"" .. PR.MACRO_NAME .. "\" macro found on: " .. G .. "slot(s) " .. tconcat(macroSlots, ", ") .. E)
        else
            VUI.Print("Priority Rotation", "    \"" .. PR.MACRO_NAME .. "\" macro found on: " .. R .. "NO SLOTS" .. E)
            if macroIdx > 0 then
                VUI.Print("Priority Rotation", "      (macro exists at idx=" .. macroIdx .. " but no slot matched)")
            else
                VUI.Print("Priority Rotation", "      (macro not in macro list — create with /pr macro)")
            end
        end

        VUI.Print("Priority Rotation", "─────────────────────────────────────────")
        local stepOk, stepVal = pcall(function() return PR.rotBtn:GetAttribute("step") end)
        if stepOk then
            local stepNum = tonumber(stepVal)
            if hasIssecret and issecretvalue(stepVal) then
                VUI.Print("Priority Rotation", "  rotBtn:GetAttribute('step'): |cFFFF8800SECRET VALUE|r")
            elseif stepNum then
                VUI.Print("Priority Rotation", "  rotBtn:GetAttribute('step'): " .. G .. stepNum .. E)
            else
                VUI.Print("Priority Rotation", "  rotBtn:GetAttribute('step'): " .. Y .. tostring(stepVal) .. " (type=" .. type(stepVal) .. ")" .. E)
            end
        else
            VUI.Print("Priority Rotation", "  rotBtn:GetAttribute('step'): " .. R .. "ERROR" .. E .. " — " .. tostring(stepVal))
        end

        VUI.Print("Priority Rotation", "─────────────────────────────────────────")
        local override = PR.overrides[PR.MACRO_NAME]
        if override then
            VUI.Print("Priority Rotation", "  Override slot: " .. G .. override.slot .. E)
            if override.keys then
                VUI.Print("Priority Rotation", "  Bound keys:   " .. G .. tconcat(override.keys, ", ") .. E)
            else
                VUI.Print("Priority Rotation", "  Bound keys:   " .. Y .. "none (macro found but no keybind assigned)" .. E)
            end
        else
            VUI.Print("Priority Rotation", "  Override:     " .. R .. "not active" .. E .. " (run /pr scan)")
        end

        VUI.Print("Priority Rotation", "─────────────────────────────────────────")
        VUI.Print("Priority Rotation", "  " .. Y .. "Run /pr diag in different contexts:" .. E)
        VUI.Print("Priority Rotation", "    • Open world (no secrets)")
        VUI.Print("Priority Rotation", "    • Inside M+/raid (secrets active)")
        VUI.Print("Priority Rotation", "    • In combat vs. out of combat")

    elseif cmd == "help" then
        VUI.Print("Priority Rotation", "Commands:")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr|r           — toggle editor")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr settings|r  — open settings panel")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr scan|r      — bind to keybind/bar")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr macro|r     — create macro stub")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr status|r    — show current state at a glance")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr reset|r     — reset to spec defaults")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr clear|r     — clear spell list")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr test|r      — show compiled sequence")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr diag|r      — live-patch API diagnostic")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr debug|r     — toggle debug output")
        VUI.Print("Priority Rotation", "  |cFFFFFF00/pr help|r      — show this help")
        -- /pr debug gates DebugPrint only. The two operations this module defers through
        -- VUI.CombatQueue, the queued recompile and ClearOverride, swallow errors unless
        -- the separate suite-wide VUI.debug flag is set, so someone diagnosing "my
        -- rotation didn't recompile after combat" with /pr debug alone gets silence.
        -- Pointed at the existing suite-wide toggle rather than making /pr debug write
        -- VUI.debug: that would turn every other module's debug output on and off as a
        -- side effect, and would silently clear a flag the user set from /ah debug.
        VUI.Print("Priority Rotation",
            "  |cFF888888combat-queue errors need suite-wide debug: /ah debug|r")

    else
        if PR.MainWindow then
            if PR.MainWindow:IsShown() then
                VUI.CloseManagedPanel(PR.MainWindow)
            else
                PR.MainWindow:ShowTab("editor")
            end
        else
            VUI.Print("Priority Rotation", "|cFFFF4444Editor failed to load. Try /reload|r")
        end
    end
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_PriorityRotation_OnAddonCompartmentClick()
    C_Timer.After(0, function() SlashCmdList["VERITASUI_PR"]("") end)
end
