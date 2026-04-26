-- VeritasUI_PriorityRotation / Core.lua
-- One-button rotation cycler with per-spec profiles and action bar override.
--
-- Contract: All functions that modify secure state check InCombatLockdown
-- internally, so callers need not guard. Functions that only read state
-- or modify Lua-side data do not check combat.

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
PR.compiledNames    = {}      -- step → display name, built during compile
PR.iconCache        = {}      -- step → iconID, built during compile
PR.overriddenButton = nil
PR.needsRecompile   = false
PR.needsClearOverride = false

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
    if InCombatLockdown() then
        self.needsRecompile = true
        return
    end

    local seq, cache, names = {}, {}, {}
    local profile = self:CurrentProfile()
    if profile and profile.spells and #profile.spells > 0 then
        local cooldowns, fillers = {}, {}
        local cdIcons, fillIcons = {}, {}
        local cdNames, fillNames = {}, {}
        for _, e in ipairs(profile.spells) do
            if e then
                local macrotext, entryIcon, entryName
                if e.macroName then
                    -- Macro entry: look up current body at compile time
                    local mName, mIcon, mBody = GetMacroInfo(e.macroName)
                    if mBody and mBody ~= "" then
                        macrotext = mBody
                        entryIcon = mIcon or e.icon
                        entryName = "[MACRO:" .. (mName or e.macroName) .. "]"
                        -- Keep stored icon fresh
                        if mIcon then e.icon = mIcon end
                    end
                elseif e.itemID then
                    -- Trinket / item entry: emit a /use macro keyed on the
                    -- item NAME (not slot ID), so the rotation always fires
                    -- THIS specific item regardless of which inventory slot
                    -- it occupies. Falls back to /use item:<id> if name is
                    -- somehow missing (defensive — should never trigger
                    -- since drop handler validates name presence).
                    local useTarget = e.itemName
                    if not useTarget or useTarget == "" then
                        useTarget = "item:" .. tostring(e.itemID)
                    end
                    macrotext = "/use " .. useTarget
                    entryIcon = e.icon
                    entryName = "[ITEM:" .. (e.itemName or tostring(e.itemID)) .. "]"
                elseif e.spellName then
                    macrotext = "/cast " .. e.spellName
                    entryIcon = e.icon
                    entryName = e.spellName
                end

                if macrotext then
                    local freq = e.freq or 1
                    if freq <= 1 then
                        cooldowns[#cooldowns + 1] = macrotext
                        cdIcons[#cdIcons + 1] = entryIcon
                        cdNames[#cdNames + 1] = entryName
                    else
                        for _ = 1, freq do
                            fillers[#fillers + 1] = macrotext
                            fillIcons[#fillIcons + 1] = entryIcon
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
                cache[#seq]   = cdIcons[ci]
                names[#seq]   = cdNames[ci]
                ci = ci + 1
            end
            if fi <= #fillers then
                seq[#seq + 1] = fillers[fi]
                cache[#seq]   = fillIcons[fi]
                names[#seq]   = fillNames[fi]
                fi = fi + 1
            end
        end
    end

    self.compiledSequence = seq
    self.iconCache        = cache
    self.compiledNames    = names
    self:InjectSequence(seq)
    self.needsRecompile = false
    self:UpdateMacroStub()

    C_Timer.After(0.5, function()
        if not InCombatLockdown() then PR:ScanAndOverrideBarButton() end
    end)
end

-- Returns a Lua long-string literal that safely embeds any string content,
-- including those containing ]] or ]=] sequences.  Scans for the minimum
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
----------------------------------------------------------------
function PR:UpdateMacroStub()
    if InCombatLockdown() then return end

    local macroBody = "#showtooltip\n/click " .. self.BUTTON_NAME
    local macroIcon = "ability_warrior_charge"
    local profile   = self:CurrentProfile()
    if profile and profile.spells and profile.spells[1] and profile.spells[1].icon then
        macroIcon = profile.spells[1].icon
    end

    local idx = GetMacroIndexByName(self.MACRO_NAME)
    if idx > 0 then
        EditMacro(idx, self.MACRO_NAME, macroIcon, macroBody)
    else
        if GetNumMacros() < (MAX_ACCOUNT_MACROS or 120) then
            CreateMacro(self.MACRO_NAME, macroIcon, macroBody)
        end
    end
end

----------------------------------------------------------------
--  Action Bar Override
--
--  Redirects the bar button containing the Attack macro so that
--  pressing its keybind clicks rotBtn instead.  Works with any
--  bar — visible, hidden, or tucked away.
--
--  Slot mapping covers Blizzard bars 1-9 (slots 1-12, 25-120).
--  Slots 13-24 are action bar pages 2+ (stance/stealth) and
--  are intentionally unmapped — macros are not placed there.
----------------------------------------------------------------
local SECURE_HANDLER = CreateFrame("Frame", "PRSecureHandler", nil, "SecureHandlerBaseTemplate")

local SLOT_TO_FRAME = {}
local FRAME_DEFS = {
    { base =   0, prefix = "ActionButton" },
    { base =  24, prefix = "MultiBarRightButton" },
    { base =  36, prefix = "MultiBarLeftButton" },
    { base =  48, prefix = "MultiBarBottomRightButton" },
    { base =  60, prefix = "MultiBarBottomLeftButton" },
    { base =  72, prefix = "MultiBar5Button" },
    { base =  84, prefix = "MultiBar6Button" },
    { base =  96, prefix = "MultiBar7Button" },
    { base = 108, prefix = "MultiBar8Button" },
}
for _, def in ipairs(FRAME_DEFS) do
    for i = 1, 12 do
        SLOT_TO_FRAME[def.base + i] = def.prefix .. i
    end
end

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

-- Extra button names for Bartender4 / ElvUI (attribute scan only).
local ADDON_BAR_BUTTONS = {}
for i = 1, 12 do
    ADDON_BAR_BUTTONS[#ADDON_BAR_BUTTONS + 1] = "BT4Button" .. i
    for b = 1, 6 do
        ADDON_BAR_BUTTONS[#ADDON_BAR_BUTTONS + 1] = "ElvUI_Bar" .. b .. "Button" .. i
    end
end

local function OverrideBarButton(btn, btnName)
    btn:SetAttribute("pr-override", PR.BUTTON_NAME)
    btn:SetAttribute("type", "click")
    btn:SetAttribute("clickbutton", rotBtn)
    PR.overriddenButton = btnName
end

function PR:ClearOverride()
    if InCombatLockdown() then return end
    ClearOverrideBindings(SECURE_HANDLER)

    if self.overriddenButton and _G[self.overriddenButton] then
        local btn = _G[self.overriddenButton]
        btn:SetAttribute("pr-override", nil)
        btn:SetAttribute("type", "action")
        btn:SetAttribute("clickbutton", nil)
    end

    self.overriddenButton = nil
    self.overriddenKeys   = nil
end

function PR:ScanAndOverrideBarButton()
    if InCombatLockdown() or not PR:IsEnabled() then return end

    local macroIdx = GetMacroIndexByName(self.MACRO_NAME)
    if not macroIdx or macroIdx == 0 then return end

    self:ClearOverride()

    local foundSlot
    for slot = 1, 120 do
        local ok, actionType, id = pcall(GetActionInfo, slot)
        if ok and actionType == "macro" and id == macroIdx then
            foundSlot = slot
            break
        end
    end
    if not foundSlot then return end

    -- Strategy 1: Direct slot → frame name lookup
    local directName = SLOT_TO_FRAME[foundSlot]
    if directName then
        local btn = _G[directName]
        if btn then
            OverrideBarButton(btn, directName)
        end
    end

    -- Strategy 2: Attribute scan for addon bars (BT4, ElvUI)
    if not self.overriddenButton then
        for _, btnName in ipairs(ADDON_BAR_BUTTONS) do
            local btn = _G[btnName]
            if btn then
                local ok, slotAttr = pcall(function()
                    local a = tonumber(btn:GetAttribute("action"))
                    if not a or a == 0 then
                        local s = btn:GetID()
                        local p = tonumber(btn:GetAttribute("actionpage")) or 1
                        if s and s > 0 then a = s + (p - 1) * 12 end
                    end
                    return a
                end)
                if ok and slotAttr == foundSlot then
                    OverrideBarButton(btn, btnName)
                    break
                end
            end
        end
    end

    -- Strategy 3: Keybinding override (fallback)
    local bindingCmd = SLOT_TO_BIND[foundSlot]
    local boundKeys  = {}
    if bindingCmd then
        local k1, k2 = GetBindingKey(bindingCmd)
        if k1 then boundKeys[#boundKeys + 1] = k1 end
        if k2 then boundKeys[#boundKeys + 1] = k2 end
    end

    if not self.overriddenButton and #boundKeys > 0 then
        for _, key in ipairs(boundKeys) do
            SetOverrideBindingClick(SECURE_HANDLER, false, key, PR.BUTTON_NAME)
        end
    end

    self.overriddenKeys = #boundKeys > 0 and boundKeys or nil

    -- Icon ticker only makes sense when a bar button is directly overridden;
    -- keybind-only mode (Strategy 3) has no button whose icon to update.
    if self.overriddenButton then
        self:StartIconTicker()
    end
end

----------------------------------------------------------------
--  Dynamic Icon Ticker
--
--  Uses pre-built iconCache (step → iconID) to avoid per-tick
--  C_Spell.GetSpellInfo calls and string parsing.
--
--  SetTexture() on a button icon is NOT a protected operation,
--  so this runs freely during combat — which is exactly when the
--  user needs to see the next spell in the cycle.
----------------------------------------------------------------
local function UpdateIcon()
    if not PR.overriddenButton or #PR.compiledSequence == 0 then return end

    local btn = _G[PR.overriddenButton]
    if not btn then return end
    local icon = btn.icon or btn.Icon or _G[PR.overriddenButton .. "Icon"]
    if not icon then return end

    local step = tonumber(rotBtn:GetAttribute("step")) or 1
    local iconID = PR.iconCache[step]
    if iconID and type(iconID) == "number" then
        icon:SetTexture(iconID)
        icon:Show()
    end
end

function PR:StartIconTicker()
    if self.iconTicker then return end
    self.iconTicker = C_Timer.NewTicker(0.25, function()
        pcall(UpdateIcon)
    end)
end

function PR:StopIconTicker()
    if self.iconTicker then
        self.iconTicker:Cancel()
        self.iconTicker = nil
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
ef:RegisterEvent("PLAYER_REGEN_ENABLED")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        PR:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Manage Press and Hold Casting CVar automatically.
        -- PR requires key-up firing (0); disabling PR restores key-down (1).
        C_CVar.SetCVar("ActionButtonUseKeyDown", PR:IsEnabled() and "0" or "1")
        PR:SwitchToCurrentSpec()
        PR:CompileSequence()
        PR._lastProfileKey = PR:GetProfileKey()
        C_Timer.After(2, function() PR:UpdateMacroStub() end)
        C_Timer.After(4, function()
            if not InCombatLockdown() then PR:ScanAndOverrideBarButton() end
        end)
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
        C_Timer.After(1, function()
            if not InCombatLockdown() then PR:ScanAndOverrideBarButton() end
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        if PR.needsClearOverride then
            PR:ClearOverride()
            PR:StopIconTicker()
            PR.needsClearOverride = false
        end
        if PR.needsRecompile then PR:CompileSequence() end
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
        Settings.OpenToCategory(PR.settingsCategoryID)

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
        PR:ScanAndOverrideBarButton()
        if PR.overriddenButton then
            local keyInfo = ""
            if PR.overriddenKeys then
                keyInfo = " (|cFF00FF00" .. table.concat(PR.overriddenKeys, ", ") .. "|r)"
            end
            VUI.Print("Priority Rotation",
                "Bound to |cFF00FF00" .. PR.overriddenButton .. "|r"
                .. keyInfo .. " — spam the key to play.")
        elseif PR.overriddenKeys then
            VUI.Print("Priority Rotation",
                "Keybind |cFF00FF00" .. table.concat(PR.overriddenKeys, ", ")
                .. "|r override active — spam the key to play.")
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
        PR:UpdateMacroStub()
        VUI.Print("Priority Rotation",
            "Macro |cFFFFFF00" .. PR.MACRO_NAME .. "|r ready in /macro.")

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
        print("  Bar button: " .. (PR.overriddenButton
            and "|cFF00FF00" .. PR.overriddenButton .. "|r"
            or  "|cFFFF8800not found|r"))
        if PR.overriddenKeys then
            print("  Keybind: |cFF00FF00" .. table.concat(PR.overriddenKeys, ", ") .. "|r")
        else
            print("  Keybind: |cFFFF8800none|r")
        end

    elseif cmd == "diag" then
        VUI.Print("Priority Rotation", "|cFFFFFF0012.0.5 API Diagnostic|r")
        print("─────────────────────────────────────────")

        -- 1. Detect 12.0.5 APIs
        local G = "|cFF00FF00"   -- green
        local R = "|cFFFF4444"   -- red
        local Y = "|cFFFFFF00"   -- yellow
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

        -- 2. SetCVar test
        print("─────────────────────────────────────────")
        local cvarOk, cvarErr = pcall(C_CVar.SetCVar, "ActionButtonUseKeyDown", "0")
        if cvarOk then
            print("  SetCVar ActionButtonUseKeyDown: " .. G .. "OK" .. E)
        else
            print("  SetCVar ActionButtonUseKeyDown: " .. R .. "BLOCKED" .. E)
            print("    Error: " .. Y .. tostring(cvarErr) .. E)
        end

        -- 3. newtable() in Execute test
        local execOk, execErr = pcall(function()
            PR.rotBtn:Execute("local t = newtable(); t[1] = 'diag_test'")
        end)
        if execOk then
            print("  :Execute() newtable():    " .. G .. "OK" .. E)
        else
            print("  :Execute() newtable():    " .. R .. "BLOCKED" .. E)
            print("    Error: " .. Y .. tostring(execErr) .. E)
        end

        -- 4. GetMacroIndexByName test
        local macroOk, macroResult = pcall(GetMacroIndexByName, PR.MACRO_NAME)
        if macroOk then
            local idx = macroResult or 0
            if idx > 0 then
                print("  GetMacroIndexByName(\"" .. PR.MACRO_NAME .. "\"): " .. G .. "idx=" .. idx .. E)
            else
                print("  GetMacroIndexByName(\"" .. PR.MACRO_NAME .. "\"): " .. Y .. "not found (idx=0)" .. E)
            end
            if hasIssecret then
                local isSec = issecretvalue(macroResult)
                if isSec then
                    print("    ⚠ macroIndex is a |cFFFF8800SECRET VALUE|r")
                end
            end
        else
            print("  GetMacroIndexByName: " .. R .. "ERROR" .. E .. " — " .. tostring(macroResult))
        end

        -- 5. GetActionInfo slot scan
        print("─────────────────────────────────────────")
        print("  Scanning slots 1-120 with GetActionInfo:")
        local macroIdx = macroOk and macroResult or 0
        local foundSlots = 0
        local macroSlots = {}
        local secretSlots = 0
        local errorSlots = 0

        for slot = 1, 120 do
            local ok, actionType, id = pcall(GetActionInfo, slot)
            if ok then
                if actionType then
                    foundSlots = foundSlots + 1
                    -- Check if actionType is secret
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
                    -- Check for our macro (only if values aren't secret)
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
                print("      (macro not in macro list either — create with /pr macro)")
            end
        end

        -- 6. GetAttribute step test
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

        -- 7. Icon resolution test
        if PR.overriddenButton then
            local btn = _G[PR.overriddenButton]
            local icon = btn and (btn.icon or btn.Icon or _G[PR.overriddenButton .. "Icon"])
            print("  Overridden button icon:   " .. (icon and G .. "found" .. E or R .. "nil" .. E))
        else
            print("  Overridden button:        " .. Y .. "none (scan hasn't succeeded)" .. E)
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
        print("  |cFFFFFF00/pr reset|r     — reset to spec defaults")
        print("  |cFFFFFF00/pr clear|r     — clear spell list")
        print("  |cFFFFFF00/pr test|r      — show compiled sequence")
        print("  |cFFFFFF00/pr diag|r      — 12.0.5 API diagnostic")

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
