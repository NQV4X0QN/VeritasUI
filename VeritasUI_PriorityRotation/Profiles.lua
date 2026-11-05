-- ============================================================
-- PriorityRotation — Profiles.lua
-- Per-spec profile management.
-- ============================================================
local _, PR = ...

-- ── Profile key ──────────────────────────────────────────────
function PR:GetProfileKey()
    local name  = UnitName("player") or "Unknown"
    local realm = GetRealmName()     or "Unknown"
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

function PR:GetCurrentSpecLabel()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then return "Unknown Spec" end
    local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    local className = UnitClass("player")
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

function PR:CurrentProfile()
    -- Slash commands are registered at file scope, so /pr clear and /pr reset are callable
    -- in the file-load -> ADDON_LOADED window, before db exists. IsEnabled and
    -- CompileSequence already guard for that window; this is the choke point for the rest.
    -- Returning a throwaway default keeps the "always returns a profile" contract that ~25
    -- call sites rely on; writes to it are discarded, which beats erroring at 25 sites.
    if not self.db then return self:BuildDefaultProfile() end
    local key = self:GetProfileKey()
    local profiles = self.db.profiles
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