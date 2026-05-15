-- ============================================================
-- PriorityRotation — Profiles.lua
-- Per-spec profile management with starter spell lists.
-- ============================================================
local _, PR = ...

-- ── Starter spell lists ──────────────────────────────────────
PR.STARTER_LISTS = {
    [577] = {
        name   = "Havoc DH",
        spells = {
            { spellID = 188499, freq = 3 },  -- Blade Dance
            { spellID = 162794, freq = 1 },  -- Chaos Strike (filler)
            { spellID = 258920, freq = 3 },  -- Immolation Aura
            { spellID = 232893, freq = 3 },  -- Felblade
        },
    },
    [581] = {
        name   = "Vengeance DH",
        spells = {
            { spellID = 228477, freq = 2 },  -- Soul Cleave
            { spellID = 258920, freq = 3 },  -- Immolation Aura
            { spellID = 204021, freq = 3 },  -- Fiery Brand
            { spellID = 232893, freq = 3 },  -- Felblade
        },
    },
    [71] = {
        name   = "Arms Warrior",
        spells = {
            { spellID = 12294,  freq = 3 },  -- Mortal Strike
            { spellID = 7384,   freq = 2 },  -- Overpower
            { spellID = 163201, freq = 3 },  -- Execute
            { spellID = 1464,   freq = 1 },  -- Slam (filler)
        },
    },
    [72] = {
        name   = "Fury Warrior",
        spells = {
            { spellID = 184367, freq = 3 },  -- Rampage
            { spellID = 85288,  freq = 2 },  -- Raging Blow
            { spellID = 23881,  freq = 1 },  -- Bloodthirst (filler)
            { spellID = 280735, freq = 3 },  -- Execute
        },
    },
    [70] = {
        name   = "Retribution Paladin",
        spells = {
            { spellID = 20271,  freq = 3 },  -- Judgment
            { spellID = 53385,  freq = 2 },  -- Divine Storm
            { spellID = 35395,  freq = 1 },  -- Crusader Strike (filler)
            { spellID = 24275,  freq = 3 },  -- Hammer of Wrath
        },
    },
    [253] = {
        name   = "BM Hunter",
        spells = {
            { spellID = 34026,  freq = 2 },  -- Kill Command
            { spellID = 217200, freq = 3 },  -- Barbed Shot
            { spellID = 53351,  freq = 3 },  -- Kill Shot
            { spellID = 193455, freq = 1 },  -- Cobra Shot (filler)
        },
    },
    [254] = {
        name   = "MM Hunter",
        spells = {
            { spellID = 19434,  freq = 3 },  -- Aimed Shot
            { spellID = 185358, freq = 1 },  -- Arcane Shot (filler)
            { spellID = 257044, freq = 3 },  -- Rapid Fire
            { spellID = 53351,  freq = 3 },  -- Kill Shot
        },
    },
    [63] = {
        name   = "Fire Mage",
        spells = {
            { spellID = 257541, freq = 3 },  -- Phoenix Flames
            { spellID = 108853, freq = 3 },  -- Fire Blast
            { spellID = 11366,  freq = 3 },  -- Pyroblast
            { spellID = 133,    freq = 1 },  -- Fireball (filler)
        },
    },
    [64] = {
        name   = "Frost Mage",
        spells = {
            { spellID = 84714,  freq = 3 },  -- Frozen Orb
            { spellID = 44614,  freq = 3 },  -- Flurry
            { spellID = 30455,  freq = 2 },  -- Ice Lance
            { spellID = 116,    freq = 1 },  -- Frostbolt (filler)
        },
    },
    [259] = {
        name   = "Assassination Rogue",
        spells = {
            { spellID = 32645,  freq = 2 },  -- Envenom
            { spellID = 1329,   freq = 1 },  -- Mutilate (filler)
            { spellID = 703,    freq = 3 },  -- Garrote
            { spellID = 1943,   freq = 3 },  -- Rupture
        },
    },
    [260] = {
        name   = "Outlaw Rogue",
        spells = {
            { spellID = 2098,   freq = 2 },  -- Dispatch
            { spellID = 53,     freq = 1 },  -- Sinister Strike (filler)
            { spellID = 13877,  freq = 3 },  -- Blade Flurry
            { spellID = 195457, freq = 3 },  -- Grappling Hook
        },
    },
    [258] = {
        name   = "Shadow Priest",
        spells = {
            { spellID = 335467, freq = 3 },  -- Devouring Plague
            { spellID = 8092,   freq = 3 },  -- Mind Blast
            { spellID = 34914,  freq = 3 },  -- Vampiric Touch
            { spellID = 589,    freq = 1 },  -- Shadow Word: Pain (filler)
        },
    },
    [263] = {
        name   = "Enhancement Shaman",
        spells = {
            { spellID = 17364,  freq = 3 },  -- Stormstrike
            { spellID = 60103,  freq = 2 },  -- Lava Lash
            { spellID = 188196, freq = 1 },  -- Lightning Bolt (filler)
            { spellID = 196840, freq = 3 },  -- Frost Shock
        },
    },
    [251] = {
        name   = "Frost DK",
        spells = {
            { spellID = 49020,  freq = 2 },  -- Obliterate
            { spellID = 49143,  freq = 1 },  -- Frost Strike (filler)
            { spellID = 49184,  freq = 3 },  -- Howling Blast
            { spellID = 196770, freq = 3 },  -- Remorseless Winter
        },
    },
    [252] = {
        name   = "Unholy DK",
        spells = {
            { spellID = 275699, freq = 3 },  -- Apocalypse
            { spellID = 85948,  freq = 2 },  -- Festering Strike
            { spellID = 55090,  freq = 1 },  -- Scourge Strike (filler)
            { spellID = 47541,  freq = 2 },  -- Death Coil
        },
    },
    [269] = {
        name   = "Windwalker Monk",
        spells = {
            { spellID = 107428, freq = 3 },  -- Rising Sun Kick
            { spellID = 113656, freq = 3 },  -- Fists of Fury
            { spellID = 100784, freq = 2 },  -- Blackout Kick
            { spellID = 100780, freq = 1 },  -- Tiger Palm (filler)
        },
    },
    [103] = {
        name   = "Feral Druid",
        spells = {
            { spellID = 22568,  freq = 3 },  -- Ferocious Bite
            { spellID = 1079,   freq = 3 },  -- Rip
            { spellID = 1822,   freq = 3 },  -- Rake
            { spellID = 5221,   freq = 1 },  -- Shred (filler)
        },
    },
    [1467] = {
        name   = "Devastation Evoker",
        spells = {
            { spellID = 357208, freq = 3 },  -- Fire Breath
            { spellID = 382266, freq = 3 },  -- Eternity Surge
            { spellID = 362969, freq = 2 },  -- Disintegrate
            { spellID = 361469, freq = 1 },  -- Living Flame (filler)
        },
    },
}

-- ── Profile key ──────────────────────────────────────────────
function PR:GetProfileKey()
    local name  = UnitName("player") or "Unknown"
    local realm = GetRealmName()     or "Unknown"
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = specIndex and (C_SpecializationInfo.GetSpecializationInfo(specIndex) or 0) or 0
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
    local key = self:GetProfileKey()
    local profiles = self.db.profiles
    if not profiles[key] then profiles[key] = self:BuildDefaultProfile() end
    return profiles[key]
end

function PR:BuildDefaultProfile()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = 0
    if specIndex then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIndex) or 0
    end
    local starter   = self.STARTER_LISTS[specID]
    local profile   = {
        name   = starter and starter.name or self:GetCurrentSpecLabel(),
        spells = {},
    }
    if starter then
        for _, s in ipairs(starter.spells) do
            local info = C_Spell.GetSpellInfo(s.spellID)
            if info and info.name then
                table.insert(profile.spells, {
                    spellID   = s.spellID,
                    spellName = info.name,
                    icon      = info.iconID,
                    freq      = s.freq or 1,
                })
            end
        end
    end
    return profile
end

-- Debounced save — batches rapid editor changes into a single compile.
function PR:SaveCurrentProfile()
    self:ScheduleCompile()
end

function PR:ResetCurrentProfileToDefault()
    self.db.profiles[self:GetProfileKey()] = self:BuildDefaultProfile()
end

function PR:SwitchToCurrentSpec()
    return self:CurrentProfile()
end