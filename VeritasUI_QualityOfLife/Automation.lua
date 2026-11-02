-- VeritasUI_QualityOfLife / Automation.lua
-- Feature batch Phase 3 (2026-11-01): small automations, kept out of QualityOfLife.lua, whose main chunk
-- is near Lua's 200-locals limit (QualityOfLife.lua :3604 comment).
--
-- Auto Accept Resurrection (v1.52.0). On RESURRECT_REQUEST this makes the call Blizzard's own Accept
-- button makes (AcceptResurrect, GameDialogDefs.lua:1154-1156, :1190-1192, :1226-1228; no restriction in
-- PlayerScriptDocumentation.lua:18). Blizzard's popup is NOT closed from here: closing it would run its
-- OnHide from our code and taint the shared popup frames, which later dialogs with protected buttons reuse
-- (the v1.12.5 lesson). Whether the game closes it on its own after an accept is measured in game first.
--   * A resurrection from a caster in combat (a battle res) is left to you unless "Also in Combat" is on.
--     The caster's name can be a secret value in instances; it is never compared or printed, only passed
--     to UnitAffectingCombat inside pcall, and a secret or unreadable answer counts as "in combat".
--   * Blizzard holds the Accept button for GetCorpseRecoveryDelay() seconds after repeated deaths (the
--     popups' StartDelay, :1139); the accept waits for that too.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall = pcall

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function On(key)
    local db = DB()
    return type(db) == "table" and db[key] == true
end

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function CasterInCombat(caster)
    if caster == nil then return false end
    local ok, v = pcall(UnitAffectingCombat, caster)
    if not ok or IsSecret(v) then return true end
    return v and true or false
end

local function Accept()
    if not On("autoAcceptRes") then return end
    if AcceptResurrect then pcall(AcceptResurrect) end
end

local resFrame = CreateFrame("Frame")
resFrame:RegisterEvent("RESURRECT_REQUEST")
resFrame:SetScript("OnEvent", function(_, _, caster)
    if not On("autoAcceptRes") then return end
    if not On("autoAcceptResCombat") and CasterInCombat(caster) then return end
    local delay = 0
    if GetCorpseRecoveryDelay then
        local ok, d = pcall(GetCorpseRecoveryDelay)
        if ok and type(d) == "number" and not IsSecret(d) then delay = d end
    end
    if delay > 0 then C_Timer.After(delay + 0.1, Accept) else Accept() end
end)
