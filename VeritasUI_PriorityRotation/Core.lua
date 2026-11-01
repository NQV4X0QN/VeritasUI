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
PR.AFTER_PRESSES = 4
rotBtn:Execute("macros = newtable(); macros[1] = ''; links = newtable(); armed = newtable(); nextLink = 0;"
    .. " followerTurn = true; armPresses = " .. PR.AFTER_PRESSES)

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
-- the same edge that casts.
--
-- "After" links (v1.36.0) are decided here, per press, not in the compiled list.
-- links[i] = { "[channeling:<target>] 1", <follower macrotext> }, Only After followers first.
-- A press that lands while the target channels re-arms every link on it for PR.AFTER_PRESSES
-- tries and otherwise steps as normal (its step carries [nochanneling], so it does nothing).
-- After the channel, presses ALTERNATE: an armed follower (taking turns), then the normal
-- rotation step, until every link's tries are spent. A follower still on cooldown just fails
-- and waits for the next channel.
-- WHY (measured 2026-10-31 with /pr afterlog, two runs of 8 Eye Beams):
--   * 2 tries each, back to back: all four landed inside ONE global cooldown, so whichever cast
--     first left the other nothing (Essence Break missed 5 of the first 5).
--   * 7 tries each, back to back (~1.5 s): Essence Break cast at every Eye Beam its cooldown
--     allowed, but when both followers were on cooldown the character stood still ~1.5 s.
--   Alternating with the rotation keeps both: the tries span more than one global cooldown, and
--   every other press is a normal step, so nothing ever stands idle. The snippet cannot see time
--   (no GetTime in RestrictedEnvironment.lua), so the window is counted in presses.
-- SecureCmdOptionParse is allowed in this environment (RestrictedEnvironment.lua:82); the
-- 2026-10-31 probe measured [channeling:Eye Beam] true on every press during 6 channels and false
-- on all 1302 outside.
rotBtn:WrapScript(rotBtn, "OnClick", [=[
    if down then return end
    -- TEMPORARY PROBE (/pr afterlog): counts presses so the log can list what each one cast.
    self:SetAttribute('vui-press', (tonumber(self:GetAttribute('vui-press')) or 0) + 1)
    if links and #links > 0 then
        local channeling, open = false, false
        for i = 1, #links do
            if SecureCmdOptionParse(links[i][1]) then
                armed[i] = armPresses
                channeling = true
            elseif (armed[i] or 0) > 0 then
                open = true
            end
        end
        if channeling then
            nextLink = 0
            followerTurn = true
        elseif open then
            if followerTurn then
                followerTurn = false
                local n = #links
                for k = 1, n do
                    local i = (nextLink + k - 1) % n + 1
                    if (armed[i] or 0) > 0 then
                        armed[i] = armed[i] - 1
                        nextLink = i
                        self:SetAttribute('macrotext', links[i][2])
                        return
                    end
                end
            else
                followerTurn = true
            end
        end
    end
    local step = tonumber(self:GetAttribute('step'))
    if not macros or #macros == 0 then return end
    self:SetAttribute('macrotext', macros[step] or '')
    step = step % #macros + 1
    self:SetAttribute('step', step)
]=])

PR.rotBtn = rotBtn

----------------------------------------------------------------
--  TEMPORARY PROBE (test/after-hold) — /pr afterlog. Not for release.
--  Owner saw Only After skip three Eye Beams in a row. For each end of a channel that an After
--  link waits for, records for 2.5 s: each follower's cooldown at the channel's end, whether it
--  cast (UNIT_SPELLCAST_SUCCEEDED) or failed, and what the first presses after it cast. Read-only:
--  it polls rotBtn's attributes and listens to the player's own cast events.
----------------------------------------------------------------
local alog
local alogFrame = CreateFrame("Frame")
alogFrame:Hide()

local function AlogName(id)
    if id == nil or (issecretvalue and issecretvalue(id)) then return nil end
    return C_Spell.GetSpellName(id)
end

local function AlogCooldown(name)
    local ok, cd = pcall(C_Spell.GetSpellCooldown, name)
    if not ok or not cd then return "cd ?" end
    if issecretvalue and (issecretvalue(cd.startTime) or issecretvalue(cd.duration)) then return "cd secret" end
    local left = (cd.startTime or 0) + (cd.duration or 0) - GetTime()
    if (cd.duration or 0) <= 1.6 or left <= 0 then return "ready" end
    return format("%.1fs left", left)
end

local function AlogFlush()
    local wdw = alog.window
    alog.window = nil
    local parts = {}
    for _, f in ipairs(wdw.followers) do
        parts[#parts + 1] = format("%s%s: %s, %s%s", f.name, f.only and " (only)" or "", f.cd,
            f.cast and "|cFF00FF00cast|r" or "|cFFFF4444not cast|r",
            f.failed > 0 and format(" (%d failed)", f.failed) or "")
    end
    VUI.Print("Priority Rotation", format("|cFFFFFF00%s #%d|r — %s. Presses: %s", wdw.target, wdw.n,
        tconcat(parts, "; "), #wdw.presses > 0 and tconcat(wdw.presses, ", ") or "none"))
end

alogFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
    if not alog then return end
    local name = AlogName(spellID)
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if not name then return end
        local followers = {}
        for _, l in ipairs(PR.compiledLinks or {}) do
            if l.target == name then
                -- Blade Dance casts as Death Sweep in Metamorphosis: match the override too.
                local ok, oid = pcall(C_Spell.GetOverrideSpell, l.name)
                followers[#followers + 1] = { name = l.name, only = l.only, cd = AlogCooldown(l.name),
                                              alt = ok and AlogName(oid) or nil, cast = false, failed = 0 }
            end
        end
        if #followers == 0 then return end
        if alog.window then AlogFlush() end
        alog.count[name] = (alog.count[name] or 0) + 1
        alog.window = { target = name, n = alog.count[name], t0 = GetTime(), followers = followers,
                        presses = {} }
    elseif alog.window and name then
        for _, f in ipairs(alog.window.followers) do
            if f.name == name or f.alt == name then
                if event == "UNIT_SPELLCAST_SUCCEEDED" then f.cast = true else f.failed = f.failed + 1 end
            end
        end
    end
end)

alogFrame:SetScript("OnUpdate", function()
    if not alog then return end
    local n = rotBtn:GetAttribute("vui-press")
    if n ~= alog.lastPress then
        alog.lastPress = n
        local w = alog.window
        if w and #w.presses < 8 then
            local text = rotBtn:GetAttribute("macrotext") or ""
            local lastLine = text:match("([^\n]*)$") or text
            w.presses[#w.presses + 1] = lastLine:match("%]%s*(.+)$") or lastLine:gsub("^/%a+%s*", "")
        end
    end
    if alog.window and GetTime() - alog.window.t0 > 2.5 then AlogFlush() end
end)

function PR:ToggleAfterLog()
    if alog then
        alog = nil
        alogFrame:UnregisterAllEvents()
        alogFrame:Hide()
        VUI.Print("Priority Rotation", "After log OFF.")
        return
    end
    alog = { count = {}, lastPress = rotBtn:GetAttribute("vui-press") }
    for _, ev in ipairs({ "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }) do
        alogFrame:RegisterUnitEvent(ev, "player")
    end
    alogFrame:Show()
    VUI.Print("Priority Rotation", "After log ON — one line per Eye Beam (or other After target)."
        .. " |cFFFFFF00/pr afterlog|r again to stop.")
end

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
--  "After" column (v1.36.0): NOT placed here. Until v1.36.0 a follower was
--  also emitted right after every occurrence of its target, which could
--  not hold anything back — the target step comes round whether or not
--  the target is ready, and the follower kept its own slots (owner: Essence
--  Break never waited for Eye Beam). Links now go to the press snippet
--  (rotBtn WrapScript above), which can SEE a channel; so only a spell
--  entry that has been seen channelling (e.channel, learned from
--  UNIT_SPELLCAST_CHANNEL_START) can be a target. "Only after"
--  (e.followOnly) drops the follower from the placement below, so it is
--  cast after the channel and never on its own. Adjacent duplicate steps
--  are collapsed (identical macrotext back-to-back adds nothing).
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

    self:MarkChannelEntries()   -- a spell dropped or a spec switched to since the channel was seen
    local seq, names, links = {}, {}, {}
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
        local entries = {}   -- resolved steps: { text, name, key, weight, follows, only, chanName }
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
                    -- A channel can be an "After" target only by a name the
                    -- [channeling:] conditional can carry: ] ; , would end it.
                    local chanName = e.channel and not e.macroName and not e.itemID
                        and e.spellName and not e.spellName:find("[%];,]") and e.spellName or nil
                    entries[#entries + 1] = {
                        text     = macrotext,
                        name     = entryName,
                        key      = PR.EntryKey(e),
                        weight   = weight,
                        follows  = e.follows,
                        only     = e.followOnly and true or false,
                        chanName = chanName,
                        current  = 0,   -- smooth-WRR accumulator
                    }
                end
            end
        end

        -- "After" links (see the press snippet on rotBtn). A link is live only when its target
        -- is in the list and has been seen channelling; otherwise it is inert and the follower
        -- is placed normally, so a not-yet-learned target can never silence an ability.
        local byKey = {}
        for _, it in ipairs(entries) do
            if it.key and not byKey[it.key] then byKey[it.key] = it end
        end
        -- Only After links first: this window is a held ability's only chance, while an Also
        -- After one still has its normal slots.
        local linked = {}
        for _, it in ipairs(entries) do if it.only then linked[#linked + 1] = it end end
        for _, it in ipairs(entries) do if not it.only then linked[#linked + 1] = it end end
        for _, it in ipairs(linked) do
            local target = it.follows and byKey[it.follows]
            if target and target ~= it and target.chanName then
                links[#links + 1] = {
                    cond   = "[channeling:" .. target.chanName .. "] 1",
                    text   = it.text,
                    name   = it.name,
                    target = target.name,
                    only   = it.only,
                }
                it.held = it.only
            end
        end

        -- Smooth weighted round-robin: cycle length = sum of weights;
        -- ipairs order makes tie-breaking stable in profile order.
        local placed = {}
        for _, it in ipairs(entries) do
            if not it.held then placed[#placed + 1] = it end
        end
        local total = 0
        for _, it in ipairs(placed) do total = total + it.weight end
        for _ = 1, total do
            local best
            for _, it in ipairs(placed) do
                it.current = it.current + it.weight
                if not best or it.current > best.current then best = it end
            end
            best.current = best.current - total
            -- Identical back-to-back steps are collapsed: a duplicate adds nothing at runtime.
            if seq[#seq] ~= best.text then
                seq[#seq + 1] = best.text
                names[#seq]   = best.name
            end
        end

        -- Cycle wrap-around collapse. The sequence is CYCLIC — the secure
        -- snippet advances with `step % #macros + 1` — so the last step and
        -- the first are adjacent at runtime as well, and that is the one
        -- adjacent pair the peephole above never compares. Left unhandled,
        -- {A freq 3, B freq 1} compiles to [A, B, A] and plays
        -- A,B,A,A,B,A… — a dead duplicate press every cycle, which is exactly
        -- the clumping the v1.9.6 redesign exists to remove. It happens
        -- whenever the top-weight entry also wins the final slot, i.e. the
        -- normal case. Exactly one drop can ever be needed: no two
        -- consecutive steps match, so the new last step cannot equal seq[1].
        if #seq > 1 and seq[#seq] == seq[1] then
            names[#seq] = nil
            seq[#seq]   = nil
        end
    end

    self.compiledSequence = seq
    self.compiledNames    = names
    self.compiledLinks    = links
    self:InjectSequence(seq, links)
    self:ScheduleScan(0.5)
    -- The editor redraws the instant a change is made, but the compile it triggers is debounced
    -- (ScheduleCompile, 0.3 s), so without this the preview showed the PREVIOUS sequence until
    -- something else redrew it (audit P4).
    self:RefreshUI()
    DebugPrint("Compiled " .. #seq .. " step(s), " .. #links .. " After link(s)")
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

function PR:InjectSequence(seq, links)
    if InCombatLockdown() then return end
    local lines = { "macros = newtable()", "links = newtable()", "armed = newtable()", "nextLink = 0",
                    "followerTurn = true" }
    if #seq > 0 then
        for i, macro in ipairs(seq) do
            lines[#lines + 1] = "macros[" .. i .. "] = " .. SafeQuote(macro)
        end
    else
        lines[#lines + 1] = "macros[1] = ''"
    end
    for i, l in ipairs(links or {}) do
        lines[#lines + 1] = "links[" .. i .. "] = newtable(" .. SafeQuote(l.cond) .. ", "
            .. SafeQuote(l.text) .. ")"
    end
    rotBtn:Execute(tconcat(lines, "\n"))
    rotBtn:SetAttribute("macrotext", seq[1] or "")
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
--  Channel learning — marks rotation spells seen channelling (e.channel)
----------------------------------------------------------------
PR._channelSeen = {}   -- [spellID] / [spellName] = true, this session

-- The spell tooltip's cast-time row reads "Channeled" for a channel and "Instant" for an instant
-- (measured 2026-10-31 with C_TooltipInfo.GetSpellByID on six Havoc spells: Eye Beam line 3 left =
-- "Channeled"; the other five "Instant"). English clients only: other languages translate it, and
-- for them the cast-event learning below still marks the spell after its first cast. Cached per
-- spell ID; an empty or secret answer is not cached, so it is asked again later.
PR._tipChannel = {}
local function TooltipSaysChannel(spellID)
    local known = PR._tipChannel[spellID]
    if known ~= nil then return known end
    local ok, d = pcall(C_TooltipInfo.GetSpellByID, spellID)
    if not ok or not d or not d.lines or #d.lines < 2 then return false end
    local found = false
    for i = 2, math.min(#d.lines, 5) do
        local t = d.lines[i].leftText
        if t == nil or (issecretvalue and issecretvalue(t)) then return false end
        if t == "Channeled" then found = true end
    end
    PR._tipChannel[spellID] = found
    return found
end

local function SeenChannelling(e)
    return e.spellID and (PR._channelSeen[e.spellID] or (e.spellName and PR._channelSeen[e.spellName])
        or TooltipSaysChannel(e.spellID))
end

-- Run at every compile, so a spell dropped into the rotation is checked at once.
function PR:MarkChannelEntries()
    if not self.db then return false end
    local changed = false
    for _, e in ipairs(self:CurrentProfile().spells) do
        if e and not e.channel and not e.macroName and not e.itemID and SeenChannelling(e) then
            e.channel = true
            changed = true
        end
    end
    return changed
end

-- v1.36.0: an "After" target must be a channelled spell. Links to a macro or trinket can never
-- be one, so they are cleared once (every profile), with one chat line saying so.
function PR:ClearNonSpellAfterLinks()
    if not self.db then return end
    local n = 0
    for _, profile in pairs(self.db.profiles or {}) do
        for _, e in ipairs(profile.spells or {}) do
            if e and e.follows and not e.follows:find("^spell") then
                e.follows, e.followOnly = nil, nil
                n = n + 1
            end
        end
    end
    if n > 0 then
        VUI.Print("Priority Rotation", format(
            "|cFFFFFF00After|r now waits for a channelled spell, so %d link(s) to a macro or trinket were cleared.",
            n))
    end
end

function PR:LearnChannel(spellID)
    if spellID == nil or (issecretvalue and issecretvalue(spellID)) then return end
    self._channelSeen[spellID] = true
    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if name and not (issecretvalue and issecretvalue(name)) then self._channelSeen[name] = true end
    if self:MarkChannelEntries() then self:SaveCurrentProfile() end
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

-- Learns which rotation spells are channels, the only valid "After" targets (no API says so;
-- the event's spellID does, and is secret only where spell casts are restricted:
-- UnitDocumentation.lua UnitSpellcastChannelStart, SecretWhenUnitSpellCastRestricted).
ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")

ef:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        PR:LearnChannel(arg3)

    elseif event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        PR:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        PR:RestoreKeyDownSettingOnce()
        PR:ClearNonSpellAfterLinks()
        PR:SwitchToCurrentSpec()
        PR:CompileSequence()
        PR._lastProfileKey = PR:GetProfileKey()
        -- Icon refresh only, and only for the rotation's own macro (create = false).
        C_Timer.After(2, function() if PR:IsEnabled() then PR:UpdateMacroStub(false) end end)
        PR:ScheduleScan(4)
        -- Login line removed (suite-wide audit S2): Lib prints the one "VeritasUI vX loaded" line.

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

    elseif cmd == "afterlog" then
        PR:ToggleAfterLog()   -- TEMPORARY PROBE

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
        -- side effect, and would silently clear a flag the user set from /vui debug.
        VUI.Print("Priority Rotation",
            "  |cFF888888combat-queue errors need suite-wide debug: /vui debug|r")

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

-- ── Spec switching ──────────────────────────────────────────
-- Shared by the Settings tab's Tools dropdown and the AddOns-menu flyout below, so both
-- switch the same way. Returns "combat" when refused for combat, true when a switch was
-- requested, false when there was nothing to do or the call failed.
function PR.SwitchSpec(i)
    if InCombatLockdown() then
        VUI.Print("Priority Rotation", "|cFFFF4444Can't switch spec in combat.|r")
        return "combat"
    end
    if i == C_SpecializationInfo.GetSpecialization() then return false end
    -- Midnight refactored the spec API into C_SpecializationInfo; the global
    -- SetSpecialization may be absent or shimmed. Try the modern namespace first, fall back
    -- to the global, surface the actual error if both fail so we can diagnose. err is
    -- seeded because if neither API exists no pcall runs and it would stay nil, printing
    -- "failed: nil" - the exact diagnostic dead end this block was written to prevent.
    local ok, err = false, "no spec-switch API on this client"
    if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
        ok, err = pcall(C_SpecializationInfo.SetSpecialization, i)
    end
    if not ok and SetSpecialization then
        ok, err = pcall(SetSpecialization, i)
    end
    if not ok then
        VUI.Print("Priority Rotation", "|cFFFF4444Spec switch failed:|r " .. tostring(err))
        return false
    end
    return true
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_PriorityRotation_OnAddonCompartmentClick()
    C_Timer.After(0, function() SlashCmdList["VERITASUI_PR"]("") end)
end

-- Hovering our entry in the minimap AddOns menu opens a flyout of this character's specs.
-- SOURCED (wow-ui-source live): Blizzard builds that menu itself, one plain button per addon,
-- and tags its root "MENU_ADDON_COMPARTMENT" (Blizzard_Minimap/Mainline/AddonCompartment.lua:23,
-- :33). Menu.ModifyMenu is Blizzard's extension point for tagged menus: our callback runs after
-- their generator on EVERY open, with the freshly built descriptions (Blizzard_Menu/Menu.lua:
-- 2623-2660), so the flyout is rebuilt each time and never duplicates. Our entry is found by its
-- text, which MenuUtil stores on the description (MenuUtil.lua:172-178) and which Blizzard sets
-- from our TOC Title (AddonCompartment.lua:85). Adding children to a button turns it into a
-- submenu parent.
-- MEASURED IN GAME (owner, 2026-10-24, Mac and PC): hovering opens the flyout, a spec click
-- switches, and a click on the parent still runs our compartment function and opens the window.
local function AddSpecFlyout(_, root)
    if not (root and root.EnumerateElementDescriptions) then return end
    local title = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Title")
    if not title then return end
    local n = GetNumSpecializations and GetNumSpecializations() or 0
    if n < 2 then return end
    for _, desc in root:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(desc) == title then
            -- Same WoWUIBugs #783 defence as the Tools dropdown (Settings.lua): a submenu built by
            -- addon code must not leave the menu compositor a tainted nil minimum width.
            desc:SetMinimumWidth(1)
            -- A submenu parent's click keeps the menu OPEN by default: the default (nil)
            -- response only closes menus when the element has no children, unless the element
            -- opts in (Menu.lua:2233-2243, flag at :742-748). Without this the AddOns menu stayed
            -- on screen after the click opened our window, unlike every other entry.
            desc:SetShouldRespondIfSubmenu(true)
            for i = 1, n do
                local id, name = C_SpecializationInfo.GetSpecializationInfo(i)
                if id and name then
                    desc:CreateRadio(name,
                        function() return C_SpecializationInfo.GetSpecialization() == i end,
                        function()
                            if PR.SwitchSpec(i) == "combat" then return MenuResponse.Refresh end
                            return MenuResponse.Close
                        end)
                end
            end
            return
        end
    end
end

if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.GetElementText then
    Menu.ModifyMenu("MENU_ADDON_COMPARTMENT", AddSpecFlyout)
end
