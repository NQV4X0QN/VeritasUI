-- ============================================================
-- PriorityRotation — Profiles.lua
-- Per-spec profile management.
-- ============================================================
local _, PR = ...

-- ── Profile key ──────────────────────────────────────────────
function PR:GetProfileKey()
    local name  = UnitName("player") or "Unknown"
    local realm = _G.VeritasUI.RealmName() or "Unknown"
    -- Explicit branch, not the and/or form: GetSpecializationInfo returns many values and
    -- v1.6.25 found that form silently wrong without parentheses to truncate the call. This
    -- key names the saved profile, so a regression here strands every profile the player owns.
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = 0
    if specIndex then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIndex) or 0
    end
    return string.format("%s-%s-%d", realm, name, specID)
end

-- With no specialization chosen, WoW Forever's one spec per class is named after the class itself (1485
-- "Hunter", measured 2026-11-04), which read "Hunter Hunter" (owner, 2026-11-05): a spec named like the class
-- shows the class alone. No spec index at all also falls back to the class.
function PR:GetCurrentSpecLabel()
    local className = UnitClass("player")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specName
    if specIndex then
        local _, n = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        specName = n
    end
    if specName == "" or (specName and className and specName:lower() == className:lower()) then specName = nil end
    if specName and className then return specName .. " " .. className end
    return specName or className or "Unknown Spec"
end

-- ── Database ─────────────────────────────────────────────────
function PR:InitDB()
    VeritasUI_PriorityRotationDB = VeritasUI_PriorityRotationDB or {}
    local db = VeritasUI_PriorityRotationDB
    db.profiles = db.profiles or {}
    if db.enabled == nil then db.enabled = true end
    self.db = db
end

function PR:IsEnabled()
    return self.db and self.db.enabled ~= false
end

local adoptTried = {}
local function IsEmptyProfile(p)
    return type(p) ~= "table" or type(p.spells) ~= "table" or #p.spells == 0
end

function PR:CurrentProfile()
    -- Slash commands are registered at file scope, so /pr clear and /pr reset are callable
    -- in the file-load -> ADDON_LOADED window, before db exists. IsEnabled and
    -- CompileSequence already guard for that window; this is the choke point for the rest.
    -- Returning a throwaway default keeps the "always returns a profile" contract that ~25
    -- call sites rely on; writes to it are discarded, which beats erroring at 25 sites.
    if not self.db then return self:BuildDefaultProfile() end
    -- No realm yet (WoW Forever leaves GetRealmName blank): a list saved now would sit under a key
    -- this character never reads again, and later tie with its real list in the carry-over below.
    local VUI = _G.VeritasUI
    if not VUI.RealmName() then return self:BuildDefaultProfile() end
    local key = self:GetProfileKey()
    local profiles = self.db.profiles
    -- A profile saved before WoW Forever's realm change sits under the old realm name. An empty
    -- list (one v1.89.4 saved under the blank realm, or the default made here) never counts.
    -- Once per key per session: CurrentProfile runs on every press.
    if not adoptTried[key] then
        adoptTried[key] = true
        VUI.AdoptOldCharEntry(profiles, key, key:match("%-%d+$"), IsEmptyProfile)
    end
    if not profiles[key] then profiles[key] = self:BuildDefaultProfile() end
    return profiles[key]
end

function PR:BuildDefaultProfile()
    local profile   = {
        name      = self:GetCurrentSpecLabel(),
        spells    = {},
        -- When true, spell steps reacquire the nearest enemy the moment
        -- the current target dies (or you have none), so holding the
        -- rotation key keeps attacking into the next mob. Off by default;
        -- toggled per-spec in the Settings tab. See CompileSequence.
        reacquire = false,
    }
    -- v1.38.0 (owner): a new profile holds ONLY Blizzard's Single-Button Assistant -- running it
    -- without its hiccups (channels clipped by the next press, etc.) is what PR was made for. The
    -- spell comes from C_AssistedCombat.GetActionSpell (AssistedCombatDocumentation.lua); a plain
    -- spell entry, so it compiles with [nochanneling] like any other. Owner, 2026-10-31: he has run
    -- it through PR for months with no problems, and every class has it from level 1.
    -- v1.66.0 (owner): otherwise the profile starts EMPTY -- the hand-picked starter lists are gone --
    -- and always in WoW Forever, which has no assistant (C_AssistedCombat.IsAvailable false there,
    -- owner's /vui forever probe, 2026-11-04).
    local VUI = _G.VeritasUI
    if VUI and VUI.IS_FOREVER then return profile end
    local ac = _G.C_AssistedCombat
    local okS, sbaID = pcall(function() return ac and ac.GetActionSpell and ac.GetActionSpell() end)
    local sba = okS and sbaID and C_Spell.GetSpellInfo(sbaID)
    if sba and sba.name then
        table.insert(profile.spells, {
            spellID   = sbaID,
            spellName = sba.name,
            icon      = sba.iconID,
            freq      = 1,
        })
    end
    return profile
end

-- Debounced save — batches rapid editor changes into a single compile.
function PR:SaveCurrentProfile()
    self:ScheduleCompile()
end

function PR:ResetCurrentProfileToDefault()
    if not self.db then return end
    self.db.profiles[self:GetProfileKey()] = self:BuildDefaultProfile()
end

function PR:SwitchToCurrentSpec()
    return self:CurrentProfile()
end