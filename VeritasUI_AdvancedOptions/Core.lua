-- VeritasUI_AdvancedOptions / Core.lua
-- Module init, saved variables, slash commands.

local ADDON_NAME, AO = ...
local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local pairs          = pairs
local pcall          = pcall
local type           = type
local format         = string.format
local strtrim        = strtrim
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local C_CVar         = C_CVar
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------
--  Constants
----------------------------------------------------------------
AO.VERSION  = VUI.VERSION
AO.SB_INSET = 16        -- MinimalScrollBar width + gap; both scroll tabs must match

----------------------------------------------------------------
--  Defaults & state
--
--  We do NOT persist CVar values — WoW's own CVar persistence
--  handles that.  We persist UI-side state: collapsed categories,
--  favourited CVars in the browser, and the last active tab.
----------------------------------------------------------------
-- Saved state, split by SCOPE. Authority: references/setting-scope-map.md in the skill
-- directory; enforced by scope_map_test and module_scope_test.
--
-- Shared by every character: these are all UI-side preferences about the browser itself.
local UNIVERSAL = {
    collapsed  = {},          -- [categoryKey] = true/false
    favorites  = {},          -- [cvarName]    = true
    lastTab    = 1,           -- 1 = Featured, 2 = All CVars
}

-- ⚠ PER-CHARACTER, and a PAIRED CONSTRAINT: cvarCache and cacheVersion must ALWAYS share a
-- scope. cacheVersion invalidates cvarCache on addon upgrade; if it were account-wide while the
-- cache is per-character, the FIRST character to log in after an upgrade would stamp the new
-- version and every other character's stale cache would never be invalidated again. That is a
-- defect this refactor would CREATE, not one it inherits.
--
-- The cache is per-character because WoW's own CVars are a mix of account- and character-scoped,
-- so one character's last-known-good value is not safe to apply to another.
local PERCHAR = {
    cvarCache    = {},        -- [cvarName] = last-known-good string value
                              -- Fallback for CVars registered by Blizzard LoD
                              -- subsystems (Blizzard_NamePlates, Blizzard_CombatText)
                              -- that aren't in the registry at PLAYER_LOGIN.
    cacheVersion = 0,         -- AO.VERSION the cache was last built for. Previously UNDECLARED,
                              -- which is how the scope map missed it on the first pass: it is a
                              -- live saved key that never appeared in a defaults table.
}

local db     -- ACCOUNT-wide table (collapsed/favorites/lastTab). Also exposed as AO.db.
-- ⚠ Declared here, above every reader. `cdb` is the PER-CHARACTER table and is nil until
-- PLAYER_LOGIN, because VUI.BindScopedDB deliberately does NOT fall back to the account root.
local cdb    -- PER-CHARACTER table (cvarCache/cacheVersion); nil before PLAYER_LOGIN

-- Called TWICE: at ADDON_LOADED and again at PLAYER_LOGIN. That double call is why this module
-- was the awkward one to convert.
--
-- Under VUI.BindCharDB the first call returned the account ROOT as a stand-in for the character
-- slot, so all of this ran twice against two different tables -- which meant the per-character
-- CVar cache was seeded and version-stamped into ACCOUNT-wide storage at load time.
-- VUI.BindScopedDB deliberately returns nil for the character table instead, so everything
-- per-character now happens only on the second call. Do not "simplify" the early return away.
--
-- The hand-rolled seeding loop that used to live here is gone: BindScopedDB seeds both scopes
-- and DEEP-copies table defaults, which is strictly better than the shallow copy it replaced
-- (that copy's own comment warned it would alias a nested default).
function AO:InitDB()
    db, cdb = VUI.BindScopedDB("VeritasUI_AdvancedOptionsDB", UNIVERSAL, PERCHAR)
    AO.db = db      -- public surface; Settings.lua reads AO.db.lastTab, a universal key

    if not cdb then return end   -- ADDON_LOADED pass: no identity, so no per-character work

    -- MUST run here: after the character table exists, and before anything reads a universal
    -- key. Promotes this character's collapsed/favorites/lastTab to account scope and drops the
    -- vestigial account-wide copies of the CVar cache.
    local promoted = VUI.MigrateScopedDB("VeritasUI_AdvancedOptionsDB", UNIVERSAL, PERCHAR,
                                         "__vuiScopeMigrated")
    if promoted then
        local names = {}
        for k in pairs(promoted) do names[#names + 1] = k end
        table.sort(names)
        VUI.Print("Advanced Options", "settings now shared across characters: "
            .. table.concat(names, ", ") .. "  (taken from this character)")
    end

    -- Clear the CVar cache on version change to evict entries from renamed/removed CVars.
    -- Reads and writes cdb: both keys are per-character, and splitting them would break
    -- invalidation for every character but the first to log in after an upgrade.
    if cdb.cacheVersion ~= AO.VERSION then
        cdb.cvarCache    = {}
        cdb.cacheVersion = AO.VERSION
    end
end

----------------------------------------------------------------
--  CVar helpers — thin wrappers with pcall + combat guard
----------------------------------------------------------------

--- Read a CVar value. Returns string or nil on failure.
--- Falls back to a saved-vars cache for CVars whose Blizzard
--- subsystem hasn't loaded yet at PLAYER_LOGIN time.
function AO:GetCVar(name)
    local ok, val = pcall(C_CVar.GetCVar, name)
    if ok and val ~= nil then
        -- Live value available — update the cache.
        if cdb then cdb.cvarCache[name] = val end
        return val
    end
    -- CVar not (yet) in the registry — return cached value if we have one.
    -- The `or nil` cannot swallow a real value the way GetCVarBool's did: every writer
    -- of cvarCache stores a string — this function's own read above, and SetCVar's
    -- three writes, whose callers pass "1"/"0", tostring(value), a dropdown's string
    -- option, or an edit box's text. Even "" is truthy in Lua.
    return cdb and cdb.cvarCache[name] or nil
end

--- Read a CVar as a boolean. Returns true/false or nil on failure.
--- NOTE: a plain `ok and val or nil` would collapse a legitimate `false`
--- into nil, making "off" indistinguishable from "unreadable" — the
--- explicit branch preserves the documented contract.
function AO:GetCVarBool(name)
    local ok, val = pcall(C_CVar.GetCVarBool, name)
    if ok then return val end
    return nil
end

--- Read the default value for a CVar. Returns string or nil.
function AO:GetCVarDefault(name)
    -- Explicit branch, matching GetCVarBool above and GetCVarInfo below: every
    -- pcall-wrapped read in this file distinguishes "call failed" from "call returned
    -- a falsy value". Identical behaviour for a string API; one rule instead of two.
    local ok, val = pcall(C_CVar.GetCVarDefault, name)
    if ok then return val end
    return nil
end

--- Full CVar info. Returns (value, default, serverStored, lockedByGx) or nils.
function AO:GetCVarInfo(name)
    local ok, val, def, server, locked = pcall(C_CVar.GetCVarInfo, name)
    if ok then return val, def, server, locked end
    return nil, nil, nil, nil
end

--- Set a CVar. Combat-defers if needed. Returns true on immediate success.
function AO:SetCVar(name, value)
    if InCombatLockdown() then
        VUI.CombatQueue.Add(function()
            local ok, err = pcall(C_CVar.SetCVar, name, value)
            if ok then
                if cdb then cdb.cvarCache[name] = value end
            else
                VUI.Print("Advanced Options",
                    format("|cFFFF4444Failed to set %s:|r %s", name, tostring(err)))
            end
        end)
        -- Optimistically cache even for deferred writes so the UI
        -- reflects the pending value immediately.
        if cdb then cdb.cvarCache[name] = value end
        VUI.Print("Advanced Options",
            format("|cFFFFFF00%s|r will be set after combat.", name))
        return false
    end
    local ok, err = pcall(C_CVar.SetCVar, name, value)
    if not ok then
        VUI.Print("Advanced Options",
            format("|cFFFF4444Failed to set %s:|r %s", name, tostring(err)))
        return false
    end
    if cdb then cdb.cvarCache[name] = value end
    return true
end

--- Reset a CVar to its default value.
function AO:ResetCVar(name)
    local def = self:GetCVarDefault(name)
    if def ~= nil then
        return self:SetCVar(name, def)
    end
    return false
end

----------------------------------------------------------------
--  Favourites helpers (Browser tab)
----------------------------------------------------------------
function AO:IsFavorite(cvarName)
    -- `or false` is a deliberate nil -> false normalisation, not the collapse
    -- GetCVarBool was fixed for: ToggleFavorite only ever stores true or nil, so no
    -- real boolean is swallowed. Keep the boolean return; the Browser's star colour
    -- reads it three times per row and an explicit branch would buy nothing.
    return db and db.favorites[cvarName] or false
end

function AO:ToggleFavorite(cvarName)
    if not db then return end
    if db.favorites[cvarName] then
        db.favorites[cvarName] = nil
    else
        db.favorites[cvarName] = true
    end
end

----------------------------------------------------------------
--  Collapse state helpers (Featured tab)
----------------------------------------------------------------
function AO:IsCollapsed(categoryKey)
    -- Explicit, because this is the one accessor here whose stored value can really be
    -- false: ToggleCollapsed writes `not db.collapsed[key]`. The short form swallowed
    -- that false and returned false anyway — correct by coincidence, since the
    -- swallowed value and the fallback happened to match. That stops being true the
    -- day the fallback changes, so it is not left resting on the coincidence.
    if not db then return false end
    local v = db.collapsed[categoryKey]
    if v == nil then return false end
    return v
end

function AO:ToggleCollapsed(categoryKey)
    if not db then return end
    db.collapsed[categoryKey] = not db.collapsed[categoryKey]
end

----------------------------------------------------------------
--  Event Handler
----------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        AO:InitDB()
        ef:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Second InitDB pass: identity is now available, so this is the one that binds the
        -- per-character table and does the per-character work. AO does NOT use the Blizzard
        -- Settings framework for its values (its own window reads AO.db at call time), so unlike
        -- the other three modules there is no captured-table constraint here.
        --
        -- ⚠ The first pass seeded only the ACCOUNT table. It does NOT seed a character's slot from
        -- the root -- VUI.BindScopedDB never copies root keys into a slot, because that copy is
        -- what pinned a shipped default per character.
        AO:InitDB()
        -- Login line removed (suite-wide audit S2): Lib prints the one "VeritasUI vX loaded" line.
        ef:UnregisterEvent("PLAYER_LOGIN")
    end
end)

----------------------------------------------------------------
--  Slash Commands
----------------------------------------------------------------
SLASH_VERITASUI_AO1 = "/ao"
SLASH_VERITASUI_AO2 = "/advancedoptions"

SlashCmdList["VERITASUI_AO"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    -- No "settings" subcommand: this module has no Options -> AddOns entry (see the
    -- header in Settings.lua). "/ao settings" therefore falls through to the else
    -- branch and toggles the window, which is where the settings actually are --
    -- deliberately graceful rather than a dead command.
    if cmd == "help" then
        VUI.Print("Advanced Options", "Commands:")
        VUI.Print("Advanced Options", "  |cFFFFFF00/ao|r           — toggle window")
        VUI.Print("Advanced Options", "  |cFFFFFF00/ao help|r      — show this help")

    else
        -- Default: toggle main window
        if AO.MainWindow then
            if AO.MainWindow:IsShown() then
                VUI.CloseManagedPanel(AO.MainWindow)
            else
                AO:ShowWindow()
            end
        else
            VUI.Print("Advanced Options",
                "|cFFFF4444Window failed to load. Try /reload|r")
        end
    end
end

--- Open the main window to the last-used tab.
function AO:ShowWindow()
    if not self.MainWindow then return end
    local tab = (db and db.lastTab == 2) and "browser" or "featured"
    self.MainWindow:ShowTab(tab)
end

-- ── Addon Compartment (minimap dropdown) ────────────────────
function VeritasUI_AdvancedOptions_OnAddonCompartmentClick()
    C_Timer.After(0, function() SlashCmdList["VERITASUI_AO"]("") end)
end
