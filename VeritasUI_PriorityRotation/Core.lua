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
local _G              = _G
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
--  CVar management — idempotent, value-checks before writing.
--
--  Reads the current CVar value and skips the write if it already
--  matches the target. Safe to call from any number of code paths
--  without worrying about redundant writes or ordering.
----------------------------------------------------------------
function PR:EnsureActionBarCVar(enabled)
    local target = enabled and "0" or "1"
    if C_CVar.GetCVar("ActionButtonUseKeyDown") == target then return end
    local ok, err = pcall(C_CVar.SetCVar, "ActionButtonUseKeyDown", target)
    if not ok then
        VUI.Print("Priority Rotation",
            "|cFFFF8800ActionButtonUseKeyDown CVar could not be set — "
            .. "key-up firing may not work correctly. (" .. tostring(err) .. ")|r")
    end
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

rotBtn:WrapScript(rotBtn, "OnClick", [=[
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
--  Interleave Compiler
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
    if profile and profile.spells and #profile.spells > 0 then
        local cooldowns, fillers = {}, {}
        local cdNames,   fillNames = {}, {}
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
                    macrotext = "/use " .. useTarget
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
                        macrotext = "/cast " .. e.spellName
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
                    local freq = e.freq or 1
                    if freq <= 1 then
                        cooldowns[#cooldowns + 1] = macrotext
                        cdNames[#cdNames + 1]     = entryName
                    else
                        for _ = 1, freq do
                            fillers[#fillers + 1]   = macrotext
                            fillNames[#fillNames + 1] = entryName
                        end
                    end
                end
            end
        end
        local ci, fi = 1, 1
        while ci <= #cooldowns or fi <= #fillers do
            if ci <= #cooldowns then
                seq[#seq + 1] = cooldowns[ci]
                names[#seq]   = cdNames[ci]
                ci = ci + 1
            end
            if fi <= #fillers then
                seq[#seq + 1] = fillers[fi]
                names[#seq]   = fillNames[fi]
                fi = fi + 1
            end
        end
    end

    self.compiledSequence = seq
    self.compiledNames    = names
    self:InjectSequence(seq)
    self:ScheduleScan(0.5)
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
----------------------------------------------------------------
function PR:UpdateMacroStub()
    if InCombatLockdown() then return false end

    local macroBody = "#showtooltip\n/click " .. self.BUTTON_NAME
    local macroIcon = "ability_warrior_charge"
    local profile   = self:CurrentProfile()
    if profile and profile.spells and profile.spells[1] and profile.spells[1].icon then
        macroIcon = profile.spells[1].icon
    end

    local idx = GetMacroIndexByName(self.MACRO_NAME)
    if idx > 0 then
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
            CreateMacro(self.MACRO_NAME, macroIcon, macroBody)
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
--  Slot mapping covers Blizzard bars 1-9 (slots 1-12, 25-120).
--  Slots 13-24 are action bar pages 2+ (stance/stealth) and are
--  intentionally unmapped — macros are not placed there.
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
    { base =  72, bind = "MULTIACTIONBAR5BUTTON" },
    { base =  84, bind = "MULTIACTIONBAR6BUTTON" },
    { base =  96, bind = "MULTIACTIONBAR7BUTTON" },
    { base = 108, bind = "MULTIACTIONBAR8BUTTON" },
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

    local macroIdx = GetMacroIndexByName(macroName)
    if not macroIdx or macroIdx == 0 then return end

    self:ClearOverride(macroName)

    -- Midnight Secret Values: GetActionInfo can return secret values in
    -- raid/M+ zones; pcall each slot and count failures. Verbose callers
    -- (user-initiated /pr scan and "Scan & Bind" button) surface the
    -- diagnostic so the user knows what to do.
    local foundSlot
    local unreadableSlots = 0
    for slot = 1, 120 do
        local ok, actionType, id = pcall(GetActionInfo, slot)
        if ok then
            if actionType == "macro" and id == macroIdx then
                foundSlot = slot
                break
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
-- PLAYER_REGEN_ENABLED is owned by VUI.CombatQueue (Lib.lua).
-- All deferred post-combat actions go through VUI.CombatQueue.Add().

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        PR:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        PR:EnsureActionBarCVar(PR:IsEnabled())
        PR:SwitchToCurrentSpec()
        PR:CompileSequence()
        PR._lastProfileKey = PR:GetProfileKey()
        C_Timer.After(2, function() PR:UpdateMacroStub() end)
        PR:ScheduleScan(4)
        VUI.Print("Priority Rotation",
            format("v%s loaded — |cFFFFFF00/pr|r to open.", PR.VERSION))

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
        local override = PR.overrides[PR.MACRO_NAME]
        if override and override.keys then
            VUI.Print("Priority Rotation",
                "Keybind |cFF00FF00" .. tconcat(override.keys, ", ")
                .. "|r override active — spam the key to play.")
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
        if PR:UpdateMacroStub() then
            VUI.Print("Priority Rotation",
                "Macro |cFFFFFF00" .. PR.MACRO_NAME .. "|r ready in /macro.")
        end

    elseif cmd == "status" then
        local function yn(v) return v and "|cFF00FF00yes|r" or "|cFFFF4444no|r" end
        local macroIdx   = GetMacroIndexByName(PR.MACRO_NAME)
        local macroExists = macroIdx and macroIdx > 0
        local override   = PR.overrides[PR.MACRO_NAME]
        VUI.Print("Priority Rotation", "Status:")
        print("  Enabled:  " .. yn(PR:IsEnabled()))
        print("  Macro:    " .. yn(macroExists)
            .. (macroExists and "" or "  — run |cFFFFFF00/pr macro|r"))
        print("  On bar:   " .. (override
            and "|cFF00FF00slot " .. override.slot .. "|r"
            or  "|cFFFF4444no|r  — run |cFFFFFF00/pr scan|r"))
        print("  Keybind:  " .. ((override and override.keys)
            and "|cFF00FF00" .. tconcat(override.keys, ", ") .. "|r"
            or  "|cFFFF8800none|r — assign a key to the macro's bar slot"))
        print("  Compiled: " .. #PR.compiledSequence .. " step(s)")

    elseif cmd == "debug" then
        PR.debug = not PR.debug
        VUI.Print("Priority Rotation",
            "Debug " .. (PR.debug and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r"))

    elseif cmd == "test" then
        VUI.Print("Priority Rotation", "Diagnostic:")
        local p = PR:CurrentProfile()
        if not p then print("  |cFFFF4444No profile!|r"); return end
        print("  Spec: |cFFFFFF00" .. PR:GetCurrentSpecLabel() .. "|r")
        print("  Compiled: |cFFFFFF00" .. #PR.compiledSequence .. " steps|r")
        for i, s in ipairs(PR.compiledSequence) do
            local label = PR.compiledNames and PR.compiledNames[i] or s
            print("    " .. i .. ". " .. label)
        end
        local override = PR.overrides[PR.MACRO_NAME]
        if override and override.keys then
            print("  Keybind: |cFF00FF00" .. tconcat(override.keys, ", ") .. "|r")
        elseif override then
            print("  Macro slot: |cFFFF8800" .. override.slot .. "|r (no keybind)")
        else
            print("  Override: |cFFFF8800not active|r")
        end

    elseif cmd == "diag" then
        VUI.Print("Priority Rotation", "|cFFFFFF0012.0.5 API Diagnostic|r")
        print("─────────────────────────────────────────")

        local G = "|cFF00FF00"
        local R = "|cFFFF4444"
        local Y = "|cFFFFFF00"
        local E = "|r"

        local hasIssecret = type(issecretvalue) == "function"
        print("  issecretvalue():          " .. (hasIssecret and G.."available"..E or R.."NOT FOUND"..E))

        local hasFreeze = type(table.freeze) == "function"
        print("  table.freeze():           " .. (hasFreeze and G.."available (12.0.5 confirmed)"..E or Y.."not found (pre-12.0.5?)"..E))

        local hasRegBtn = C_ActionBar and type(C_ActionBar.RegisterActionUIButton) == "function"
        print("  C_ActionBar.RegisterActionUIButton: " .. (hasRegBtn and G.."available"..E or R.."NOT FOUND"..E))

        local hasUnregBtn = C_ActionBar and type(C_ActionBar.UnregisterActionUIButton) == "function"
        print("  C_ActionBar.UnregisterActionUIButton: " .. (hasUnregBtn and G.."available"..E or R.."NOT FOUND"..E))

        local hasSecrets = C_Secrets and type(C_Secrets) == "table"
        print("  C_Secrets namespace:      " .. (hasSecrets and G.."available"..E or R.."NOT FOUND"..E))

        local hasRestrict = C_RestrictedActions and type(C_RestrictedActions) == "table"
        print("  C_RestrictedActions:       " .. (hasRestrict and G.."available"..E or R.."NOT FOUND"..E))

        print("─────────────────────────────────────────")
        local cvarOk, cvarErr = pcall(C_CVar.SetCVar, "ActionButtonUseKeyDown", "0")
        if cvarOk then
            print("  SetCVar ActionButtonUseKeyDown: " .. G .. "OK" .. E)
        else
            print("  SetCVar ActionButtonUseKeyDown: " .. R .. "BLOCKED" .. E)
            print("    Error: " .. Y .. tostring(cvarErr) .. E)
        end

        local execOk, execErr = pcall(function()
            PR.rotBtn:Execute("local t = newtable(); t[1] = 'diag_test'")
        end)
        if execOk then
            print("  :Execute() newtable():    " .. G .. "OK" .. E)
        else
            print("  :Execute() newtable():    " .. R .. "BLOCKED" .. E)
            print("    Error: " .. Y .. tostring(execErr) .. E)
        end

        local macroOk, macroResult = pcall(GetMacroIndexByName, PR.MACRO_NAME)
        if macroOk then
            local idx = macroResult or 0
            if idx > 0 then
                print("  GetMacroIndexByName(\"" .. PR.MACRO_NAME .. "\"): " .. G .. "idx=" .. idx .. E)
            else
                print("  GetMacroIndexByName(\"" .. PR.MACRO_NAME .. "\"): " .. Y .. "not found (idx=0)" .. E)
            end
            if hasIssecret and issecretvalue(macroResult) then
                print("    ⚠ macroIndex is a |cFFFF8800SECRET VALUE|r")
            end
        else
            print("  GetMacroIndexByName: " .. R .. "ERROR" .. E .. " — " .. tostring(macroResult))
        end

        print("─────────────────────────────────────────")
        print("  Scanning slots 1-120 with GetActionInfo:")
        local macroIdx    = macroOk and macroResult or 0
        local foundSlots  = 0
        local macroSlots  = {}
        local secretSlots = 0
        local errorSlots  = 0

        for slot = 1, 120 do
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
                                print("    Slot " .. Y .. slot .. E .. ": type="
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
                    print("    Slot " .. Y .. slot .. E .. ": " .. R .. "ERROR" .. E .. " — " .. tostring(actionType))
                end
            end
        end

        print("  Summary:")
        print("    Populated slots: " .. Y .. foundSlots .. E)
        print("    Secret values:   " .. (secretSlots > 0 and R .. secretSlots .. E or G .. "0" .. E))
        if secretSlots > 5 then
            print("      (showing first 5 of " .. secretSlots .. ")")
        end
        print("    Errored slots:   " .. (errorSlots > 0 and R .. errorSlots .. E or G .. "0" .. E))
        if #macroSlots > 0 then
            print("    \"" .. PR.MACRO_NAME .. "\" macro found on: " .. G .. "slot(s) " .. table.concat(macroSlots, ", ") .. E)
        else
            print("    \"" .. PR.MACRO_NAME .. "\" macro found on: " .. R .. "NO SLOTS" .. E)
            if macroIdx > 0 then
                print("      (macro exists at idx=" .. macroIdx .. " but no slot matched)")
            else
                print("      (macro not in macro list — create with /pr macro)")
            end
        end

        print("─────────────────────────────────────────")
        local stepOk, stepVal = pcall(function() return PR.rotBtn:GetAttribute("step") end)
        if stepOk then
            local stepNum = tonumber(stepVal)
            if hasIssecret and issecretvalue(stepVal) then
                print("  rotBtn:GetAttribute('step'): |cFFFF8800SECRET VALUE|r")
            elseif stepNum then
                print("  rotBtn:GetAttribute('step'): " .. G .. stepNum .. E)
            else
                print("  rotBtn:GetAttribute('step'): " .. Y .. tostring(stepVal) .. " (type=" .. type(stepVal) .. ")" .. E)
            end
        else
            print("  rotBtn:GetAttribute('step'): " .. R .. "ERROR" .. E .. " — " .. tostring(stepVal))
        end

        print("─────────────────────────────────────────")
        local override = PR.overrides[PR.MACRO_NAME]
        if override then
            print("  Override slot: " .. G .. override.slot .. E)
            if override.keys then
                print("  Bound keys:   " .. G .. table.concat(override.keys, ", ") .. E)
            else
                print("  Bound keys:   " .. Y .. "none (macro found but no keybind assigned)" .. E)
            end
        else
            print("  Override:     " .. R .. "not active" .. E .. " (run /pr scan)")
        end

        print("─────────────────────────────────────────")
        print("  " .. Y .. "Run /pr diag in different contexts:" .. E)
        print("    • Open world (no secrets)")
        print("    • Inside M+/raid (secrets active)")
        print("    • In combat vs. out of combat")

    elseif cmd == "help" then
        VUI.Print("Priority Rotation", "Commands:")
        print("  |cFFFFFF00/pr|r           — toggle editor")
        print("  |cFFFFFF00/pr settings|r  — open settings panel")
        print("  |cFFFFFF00/pr scan|r      — bind to keybind/bar")
        print("  |cFFFFFF00/pr macro|r     — create macro stub")
        print("  |cFFFFFF00/pr status|r    — show current state at a glance")
        print("  |cFFFFFF00/pr reset|r     — reset to spec defaults")
        print("  |cFFFFFF00/pr clear|r     — clear spell list")
        print("  |cFFFFFF00/pr test|r      — show compiled sequence")
        print("  |cFFFFFF00/pr diag|r      — 12.0.5 API diagnostic")
        print("  |cFFFFFF00/pr debug|r     — toggle debug output")

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
